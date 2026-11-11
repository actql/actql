import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {availableParallelism, hostname, tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {acquireLocalLocks, checkBudget, durationSeconds, lockDirectory,
  availableVerificationMemory, heavyResourceAdmission, heavyResourceRequest,
  lockOwnerStatus, runLocalCheck} from './local-checks-guard.mjs';

const tinyResources = {memoryBytes: 16 * 1024 * 1024, diskBytes: 1024 * 1024, cpuThreads: 1};
const guard = new URL('./local-checks-guard.mjs', import.meta.url).href;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
// Normal cancellation must allow a process exit, pipe EOF and the supervisor's
// bounded ps inspection. This is fixture-only, not a production change.
const cancellationGraceSeconds = 3;
// These ordering tests need time to start both Node processes and observe their
// readiness/exit records. Timeout still fires through the real production timer.
const cancellationTimeoutSeconds = 3;
function fixture(t) {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), 'actql-local-guard-')));
  const runs = [];
  t.after(async () => {
    // Only signal caller handles owned by this fixture. Their supervisors retain
    // responsibility for process-group cancellation and its finite TERM grace.
    for (const {child} of runs) {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGINT');
    }
    const outcomes = await Promise.allSettled(runs.map(run => run.done));
    const cleanupFailure = outcomes.find(result => result.status === 'rejected');
    // passed/error are TestContext APIs present since Node 20.12/21.7.
    if (t.passed === true && !cleanupFailure) {
      rmSync(directory, {recursive: true, force: true});
      return;
    }
    const error = t.error?.cause ?? t.error ?? cleanupFailure?.reason;
    writeFileSync(join(directory, 'failure.json'), JSON.stringify({
      test: t.name, error: String(error?.stack ?? error).slice(0, 16384),
      callers: outcomes.map((result, index) => {
        if (result.status === 'rejected') return {pid: runs[index].child.pid, error: String(result.reason)};
        const {code, signal, stdout, stderr} = result.value;
        writeFileSync(join(directory, `caller-${index}.stdout`), stdout);
        writeFileSync(join(directory, `caller-${index}.stderr`), stderr);
        return {pid: runs[index].child.pid, code, signal};
      }),
    }, null, 2) + '\n');
    t.diagnostic(`Failed local guard fixture retained: ${directory}`);
    if (cleanupFailure) throw cleanupFailure.reason;
  }, {timeout: 30000});
  const home = join(directory, 'home'), root = join(directory, 'checkout');
  mkdirSync(home); mkdirSync(root);
  const env = {...process.env, HOME: home};
  delete env.NODE_TEST_CONTEXT;
  return {directory, home, root, env, runs, diagnostic: message => t.diagnostic(message)};
}
function steps(source) {
  return [{name: 'fixture', command: process.execPath, args: ['-e', source]}];
}
function start(f, options = {}, extraEnv = {}) {
  const config = {root: f.root, heavy: true, heavyResources: tinyResources, timeoutSeconds: 10, graceSeconds: cancellationGraceSeconds,
    steps: steps('console.log("fixture ran")'), ...options};
  const script = `import {runLocalCheck} from ${JSON.stringify(guard)};
    process.exitCode = await runLocalCheck(${JSON.stringify(config)});`;
  const child = spawn(process.execPath, ['--input-type=module', '-e', script],
    {env: {...f.env, ...extraEnv}, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', data => { stdout += data; });
  child.stderr.on('data', data => { stderr += data; });
  const done = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({code, signal, stdout, stderr}));
  });
  const run = {child, done};
  f.runs.push(run);
  return run;
}
async function until(predicate) {
  const deadline = Date.now() + 10_000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error('Fixture did not reach expected state');
    await sleep(20);
  }
}
function attempts(f, root = f.root) {
  const parent = join(root, '_build/local-checks/attempts');
  return existsSync(parent) ? readdirSync(parent).map(name => join(parent, name)) : [];
}
function summary(directory) { return JSON.parse(readFileSync(join(directory, 'summary.json'), 'utf8')); }
function locks(f) { return readdirSync(lockDirectory(f.home).path); }
function live(pid) {
  const result = spawnSync('ps', ['-p', String(pid), '-o', 'stat='], {encoding: 'utf8'});
  return result.status === 0 && result.stdout.trim() && !result.stdout.trim().startsWith('Z');
}
const locateEvidence = `const fs = require('fs'), path = require('path');
  const parent = path.join(process.cwd(), '_build/local-checks/attempts');
  const attempt = path.join(parent, fs.readdirSync(parent)[0]);`;

// Node's spawn(..., stdio: 'pipe') may use socket pairs. Shell pipelines give
// both supervisor streams actual pipes, checked by each receiver with fstat.
function pipedRun(f, {exitCode = 0, failEvidence = false, stdout = 'drain',
  stderr = 'drain', cancellation, outputBytes = 200000, failFinalEvidence = false,
  cancelBeforeReady = false, delayGroupInspection = false, failExitEvidence = false} = {}) {
  const caller = join(f.directory, 'caller.mjs'), receiver = join(f.directory, 'receiver.cjs');
  const ready = join(f.directory, 'output-ready'), done = join(f.directory, 'caller-done');
  const release = join(f.directory, 'release-handler'), handlerReady = join(f.directory, 'handler-ready');
  const events = join(f.directory, 'cancellation-events');
  const lifecycle = join(f.directory, 'pipe-lifecycle.jsonl');
  const traceSource = `const trace = (event, details = {}) => fs.appendFileSync(
    ${JSON.stringify(lifecycle)}, JSON.stringify({event, pid: process.pid,
      parentPid: process.ppid, at: Date.now(), ...details}) + '\\n');`;
  const eventSource = `const event = value => fs.appendFileSync(${JSON.stringify(events)}, JSON.stringify(value) + '\\n');`;
  const source = locateEvidence + `
    ${traceSource}
    trace('command-start');
    process.on('exit', code => trace('command-exit', {code}));
    ${cancellation ? eventSource + `
      // Hold handler installation behind an explicit gate. The negative control
      // cancels at output readiness while this gate is still closed.
      setInterval(() => {}, 1000);
      const poll = setInterval(() => {
        if (!fs.existsSync(${JSON.stringify(release)})) return;
        clearInterval(poll);
        process.on('SIGTERM', () => {
          const record = JSON.parse(fs.readFileSync(path.join(attempt, 'summary.json')));
          event({event: 'TERM', status: record.status, code: record.steps[0].code ?? null});
          process.exit(7);
        });
        event({event: 'handler-ready'});
        fs.writeFileSync(${JSON.stringify(handlerReady)}, 'ready');
      }, 10);` : ''}
    process.stdout.write('o'.repeat(${outputBytes}), () => {
      process.stderr.write('e'.repeat(${outputBytes}), () => {
        ${failEvidence ? "const target = path.join(attempt, 'output.log'); fs.renameSync(target, target + '.saved'); fs.writeFileSync(target, 'replacement bytes');" : ''}
        ${cancellation ? "event({event: 'output-ready'});" : ''}
        fs.writeFileSync(${JSON.stringify(ready)}, 'ready'); process.exitCode = ${exitCode};
        trace('command-output-ready');
      });
    });`;
  writeFileSync(caller, `import {runLocalCheck} from ${JSON.stringify(guard)};
    import fs, {existsSync, writeFileSync} from 'node:fs';
    ${traceSource}
    trace('caller-start');
    const abort = new AbortController();
    ${cancellation ? eventSource + `
      const poll = setInterval(() => {
        if (!existsSync(${JSON.stringify(ready)})) return;
        ${cancelBeforeReady ? `
          clearInterval(poll); event({event: 'caller-cancel'}); abort.abort();` : `
          if (!existsSync(${JSON.stringify(release)})) writeFileSync(${JSON.stringify(release)}, 'release');
          if (!existsSync(${JSON.stringify(handlerReady)})) return;
          clearInterval(poll);
          ${cancellation === 'caller' ? "event({event: 'caller-cancel'}); abort.abort();" : ''}`}
      }, 20);` : ''}
    const config = ${JSON.stringify({root: f.root, heavy: true,
      timeoutSeconds: cancellation === 'timeout' ? cancellationTimeoutSeconds : 10,
      graceSeconds: cancellation ? cancellationGraceSeconds : 0.2,
      steps: steps(source)})};
    ${failExitEvidence ? `config.steps.push({name: 'must-not-start', command: process.execPath,
      args: ['-e', 'require("fs").writeFileSync(${JSON.stringify(join(f.directory, 'later-started'))}, "started")']});` : ''}
    config.steps[0].name = 'd'.repeat(200000);
    process.exitCode = await runLocalCheck(config, {signal: abort.signal});
    writeFileSync(${JSON.stringify(done)}, String(process.exitCode));
    trace('caller-done', {code: process.exitCode});`);
  writeFileSync(receiver, `const fs = require('fs'), assert = require('assert');
    ${traceSource}
    const [file, mode, ready, done] = process.argv.slice(2);
    const stream = file.endsWith('caller.stdout') ? 'stdout' : 'stderr';
    trace('receiver-start', {stream, mode});
    process.on('exit', code => trace('receiver-exit', {stream, code}));
    assert(fs.fstatSync(0).isFIFO(), 'receiver must be a real pipe');
    fs.writeFileSync(file, '');
    if (mode === 'closed') process.exit(0);
    const bound = setTimeout(() => {
      trace('receiver-bound', {stream}); process.exit(90);
    }, 12000);
    const poll = setInterval(() => {
      if (mode === 'stall') {
        if (fs.existsSync(done)) process.exit(0);
      } else if (fs.existsSync(ready)) {
        clearInterval(poll);
        // Do not read until the command has produced all its output. Both
        // pipes fill before the old supervisor reaches its immediate exit.
        setTimeout(() => {
          trace('receiver-drain', {stream});
          const chunks = [];
          process.stdin.on('data', chunk => chunks.push(chunk));
          process.stdin.on('end', () => {
            const bytes = Buffer.concat(chunks);
            fs.writeFileSync(file, bytes); clearTimeout(bound);
            trace('receiver-end', {stream, bytes: bytes.length});
          });
        }, 150);
      }
    }, 20);`);
  const out = join(f.directory, 'caller.stdout'), err = join(f.directory, 'caller.stderr');
  const env = {...f.env};
  if (failExitEvidence) {
    const preload = join(f.directory, 'fail-exit-save-once.mjs');
    writeFileSync(preload, `import fs from 'node:fs';
      import {syncBuiltinESMExports} from 'node:module';
      if (process.argv[1]?.endsWith('/local-checks-supervisor.mjs')) {
        const original = fs.writeFileSync; let failed = false;
        fs.writeFileSync = (file, value, ...args) => {
          if (!failed && typeof value === 'string' && value.startsWith('{') &&
              JSON.parse(value).steps?.[0]?.exitedAt) {
            failed = true; throw Object.assign(new Error('exit evidence save failed once'), {code: 'EIO'});
          }
          return original(file, value, ...args);
        };
        syncBuiltinESMExports();
      }`);
    env.NODE_OPTIONS = [env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ');
  }
  if (delayGroupInspection) {
    const preload = join(f.directory, 'slow-group-inspection.mjs');
    writeFileSync(preload, `import childProcess from 'node:child_process';
      import fs from 'node:fs';
      import {syncBuiltinESMExports} from 'node:module';
      if (process.argv[1]?.endsWith('/local-checks-supervisor.mjs')) {
        const original = childProcess.spawnSync;
        childProcess.spawnSync = (command, ...args) => {
          if (command === 'ps' && fs.existsSync(${JSON.stringify(ready)})) {
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 250);
          }
          return original(command, ...args);
        };
        syncBuiltinESMExports();
      }`);
    env.NODE_OPTIONS = [env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ');
  }
  if (failFinalEvidence) {
    const preload = join(f.directory, 'fail-final-save.mjs');
    writeFileSync(preload, `import fs from 'node:fs';
      import {syncBuiltinESMExports} from 'node:module';
      if (process.argv[1]?.endsWith('/local-checks-supervisor.mjs')) {
        const original = fs.writeFileSync;
        fs.writeFileSync = (file, value, ...args) => {
          if (typeof value === 'string' && value.startsWith('{') && JSON.parse(value).complete === true) {
            throw Object.assign(new Error('late evidence save ' + 'l'.repeat(200000)), {code: 'EIO'});
          }
          return original(file, value, ...args);
        };
        syncBuiltinESMExports();
      }`);
    env.NODE_OPTIONS = [env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ');
  }
  const started = performance.now();
  const result = spawnSync('bash', ['-o', 'pipefail', '-c',
    '{ "$1" "$2" 2>&1 1>&3 | "$1" "$3" "$5" "$9" "$6" "$7"; } 3>&1 | "$1" "$3" "$4" "$8" "$6" "$7"',
    'pipe-fixture', process.execPath, caller, receiver, out, err, ready, done, stdout, stderr],
  {env, encoding: 'utf8', timeout: 15000});
  if (result.error || result.signal) {
    // The shell's kill bound alone cannot identify which descendant stayed
    // alive. Preserve its captured streams and report fixed-fixture lifecycle
    // metadata even when spawnSync did not return a normal pipeline status.
    writeFileSync(join(f.directory, 'pipe-shell.stdout'), result.stdout ?? '');
    writeFileSync(join(f.directory, 'pipe-shell.stderr'), result.stderr ?? '');
    const trace = existsSync(lifecycle) ? readFileSync(lifecycle, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
    const records = attempts(f).map(directory => {
      try {
        const record = summary(directory);
        return {status: record.status, exitCode: record.exitCode,
          supervisorPid: record.owner?.pid, locksReleased: record.locksReleased,
          complete: record.complete, outputComplete: record.outputComplete,
          callerOutputComplete: record.callerOutputComplete,
          steps: record.steps.map(({status, code, signal, streamsComplete}) =>
            ({status, code, signal, streamsComplete})), errors: record.errors};
      } catch (error) { return {unreadable: error.code ?? error.name}; }
    });
    const state = {shellPid: result.pid, error: result.error?.code, status: result.status, signal: result.signal,
      elapsed: performance.now() - started, outputReady: existsSync(ready),
      callerDone: existsSync(done) ? readFileSync(done, 'utf8') : null,
      capturedBytes: {shellStdout: Buffer.byteLength(result.stdout ?? ''),
        shellStderr: Buffer.byteLength(result.stderr ?? ''),
        stdout: existsSync(out) ? readFileSync(out).length : null,
        stderr: existsSync(err) ? readFileSync(err).length : null}, trace, records};
    const pids = [...new Set([result.pid, ...trace.map(item => item.pid),
      ...trace.map(item => item.parentPid), ...records.map(item => item.supervisorPid)]
      .filter(pid => Number.isInteger(pid) && pid > 0))];
    const processes = spawnSync('ps', ['-p', pids.join(','), '-o', 'pid=',
      '-o', 'ppid=', '-o', 'pgid=', '-o', 'stat='],
    {encoding: 'utf8', timeout: 1000, maxBuffer: 16384});
    state.processes = {status: processes.status, error: processes.error?.code,
      rows: processes.stdout ?? ''};
    writeFileSync(join(f.directory, 'pipe-failure.json'), JSON.stringify(state, null, 2) + '\n');
    f.diagnostic(`Pipe fixture failure: ${JSON.stringify(state)}`);
  }
  assert.equal(result.error, undefined, 'caller delivery must not need the external kill bound');
  assert.equal(result.signal, null);
  return {...result, elapsed: performance.now() - started,
    stdout: readFileSync(out), stderr: readFileSync(err, 'utf8'),
    events: existsSync(events) ? readFileSync(events, 'utf8').trim().split('\n').map(JSON.parse) : []};
}

function assertFullCallerOutput(bytes) {
  assert.equal(bytes.length, 400000);
  assert.equal(bytes.filter(byte => byte === 111).length, 200000);
  assert.equal(bytes.filter(byte => byte === 101).length, 200000);
}

for (const [exitCode, failEvidence] of [[0, false], [7, false], [7, true]]) {
  test(`real caller pipes retain full stdout and stderr for exit ${exitCode}, evidence failure ${failEvidence}`, t => {
    const f = fixture(t), result = pipedRun(f, {exitCode, failEvidence});
    assert.equal(result.status, exitCode, result.stderr.slice(-2000));
    assertFullCallerOutput(result.stdout);
    const [evidence] = attempts(f), record = summary(evidence);
    assert.ok(result.stderr.includes('== ' + 'd'.repeat(200000) + '\n'));
    assert.ok(result.stderr.includes(`Local check evidence: ${evidence}\n`));
    if (failEvidence) {
      assert.equal(readFileSync(join(evidence, 'output.log'), 'utf8'), 'replacement bytes');
      assert.ok(result.stderr.endsWith('EvidenceFileOwnershipChanged\n'));
      assert.equal(record.complete, false);
    } else {
      assert.deepEqual(result.stdout, readFileSync(join(evidence, 'output.log')));
      assert.equal(result.stderr, `Local check budget: 10s; TERM grace: 0.2s\nLocal check evidence: ${evidence}\n== ` +
        'd'.repeat(200000) + `\nLocal check evidence: ${evidence}\n`);
      assert.equal(record.complete, exitCode === 0);
    }
    assert.equal(record.callerOutputComplete, true);
    assert.equal(record.exitCode, exitCode);
    assert.deepEqual(locks(f), []);
  });
}

test('evidence failure after direct exit drains caller pipes even when process inspection exceeds stop grace', t => {
  const f = fixture(t), result = pipedRun(f, {exitCode: 7, failEvidence: true, delayGroupInspection: true});
  assert.equal(result.status, 7, result.stderr.slice(-2000));
  assertFullCallerOutput(result.stdout);
  const [evidence] = attempts(f), record = summary(evidence);
  assert.equal(record.steps[0].code, 7);
  assert.equal(record.steps[0].streamsComplete, true);
  assert.equal(record.complete, false);
  assert.equal(record.exitCode, 7);
  assert.equal(record.callerOutputComplete, true);
  assert.equal(record.locksReleased, true);
  assert.equal(readFileSync(join(evidence, 'output.log'), 'utf8'), 'replacement bytes');
  assert(result.stderr.includes('EvidenceFileOwnershipChanged'));
  assert.deepEqual(locks(f), []);
});

test('transient exit evidence failure stops later commands while retaining actual exit and complete output', t => {
  const f = fixture(t), result = pipedRun(f, {failExitEvidence: true});
  assert.equal(result.status, 1, result.stderr.slice(-2000));
  assertFullCallerOutput(result.stdout);
  const [evidence] = attempts(f), record = summary(evidence);
  assert.equal(record.steps.length, 1);
  assert.equal(record.steps[0].code, 0);
  assert.equal(record.steps[0].status, 'failed');
  assert.equal(record.steps[0].streamsComplete, true);
  assert.equal(record.complete, false);
  assert.equal(record.exitCode, 1);
  assert.equal(record.callerOutputComplete, true);
  assert.equal(record.locksReleased, true);
  assert(record.errors.some(error => error.stage === 'summary' && error.code === 'EIO'));
  assert.equal(existsSync(join(f.directory, 'later-started')), false);
  assert.deepEqual(locks(f), []);
});

test('real caller stderr drains pending diagnostics even with empty command output', t => {
  const f = fixture(t), result = pipedRun(f, {outputBytes: 0});
  assert.equal(result.status, 0);
  assert.equal(result.stdout.length, 0);
  const [evidence] = attempts(f);
  const expected = `Local check budget: 10s; TERM grace: 0.2s\nLocal check evidence: ${evidence}\n== ` +
    'd'.repeat(200000) + `\nLocal check evidence: ${evidence}\n`;
  assert.equal(Buffer.byteLength(result.stderr), Buffer.byteLength(expected));
  assert.equal(result.stderr, expected);
  assert.equal(summary(evidence).callerOutputComplete, true);
  assert.deepEqual(locks(f), []);
});

test('real caller stderr drains a late evidence-save error after the main output barrier', t => {
  const f = fixture(t), result = pipedRun(f, {outputBytes: 0, failFinalEvidence: true});
  assert.equal(result.status, 1);
  assert.equal(result.stdout.length, 0);
  assert.ok(result.stderr.includes('== ' + 'd'.repeat(200000) + '\n'));
  assert.ok(result.stderr.endsWith('late evidence save ' + 'l'.repeat(200000) + '\n'));
  const [evidence] = attempts(f), record = summary(evidence);
  assert.equal(record.callerOutputComplete, true);
  assert.equal(record.outputComplete, true);
  assert.equal(record.complete, false);
  assert.equal(record.exitCode, 1);
  assert.ok(record.errors.some(error => error.stage === 'summary' && error.code === 'EIO'));
  assert.deepEqual(locks(f), []);
});

for (const stream of ['stdout', 'stderr']) {
  for (const mode of ['stall', 'closed']) {
    for (const exitCode of [0, 7]) {
      test(`${mode} caller ${stream} has a bounded exit and preserves command status ${exitCode}`, t => {
        const f = fixture(t), result = pipedRun(f, {exitCode, [stream]: mode});
        assert.equal(result.status, exitCode || 1, result.stderr.slice(-2000));
        assert.ok(result.elapsed < 10000, `forwarding took ${result.elapsed}ms`);
        const [evidence] = attempts(f), record = summary(evidence);
        assertFullCallerOutput(readFileSync(join(evidence, 'output.log')));
        if (stream === 'stderr') assertFullCallerOutput(result.stdout);
        else assert.ok(result.stderr.includes('== ' + 'd'.repeat(200000) + '\n'));
        assert.equal(record.exitCode, exitCode || 1);
        assert.equal(record.steps[0].code, exitCode);
        assert.equal(record.steps[0].streamsComplete, true);
        assert.equal(record.outputComplete, true);
        assert.equal(record.callerOutputComplete, false);
        assert.equal(record.complete, false);
        assert.equal(record.locksReleased, true);
        assert.ok(record.errors.some(error => error.stage === `${stream} forwarding`));
        assert.deepEqual(locks(f), []);
      });
    }
  }
}

for (const cancellation of ['timeout', 'caller']) {
  test(`closed caller stderr cannot replace first-cause ${cancellation} status`, t => {
    const f = fixture(t), result = pipedRun(f, {stderr: 'closed', cancellation});
    const expected = cancellation === 'timeout' ? 124 : 130;
    assert.equal(result.status, expected);
    const record = summary(attempts(f)[0]);
    assert.equal(record.exitCode, expected);
    assert.equal(record.steps[0].code, 7);
    assert.equal(record.steps[0].signal, null);
    const status = cancellation === 'timeout' ? 'timeout' : 'interrupted';
    assert.equal(record.status, status);
    assert.deepEqual(result.events, [
      {event: 'output-ready'}, {event: 'handler-ready'},
      ...(cancellation === 'caller' ? [{event: 'caller-cancel'}] : []),
      {event: 'TERM', status, code: null},
    ], 'cancellation is established after readiness and before the direct exit');
    assert.equal(record.steps[0].streamsComplete, true);
    assert.equal(record.outputComplete, true);
    assert.equal(record.callerOutputComplete, false);
    assert.equal(record.complete, false);
    assert.equal(record.locksReleased, true);
    assert.ok(record.errors.some(error => error.stage === 'stderr forwarding'));
    assertFullCallerOutput(result.stdout);
    assert.deepEqual(result.stdout, readFileSync(join(attempts(f)[0], 'output.log')));
    assert.deepEqual(locks(f), []);
  });
}

test('caller cancellation before handler readiness records SIGTERM instead of a handler exit', t => {
  const f = fixture(t), result = pipedRun(f, {
    stderr: 'closed', cancellation: 'caller', cancelBeforeReady: true,
  });
  const record = summary(attempts(f)[0]);
  assert.equal(result.status, 130);
  assert.deepEqual(result.events, [{event: 'output-ready'}, {event: 'caller-cancel'}]);
  assert.equal(record.exitCode, 130);
  assert.equal(record.status, 'interrupted');
  assert.equal(record.steps[0].code, null);
  assert.equal(record.steps[0].signal, 'SIGTERM');
  assert.equal(record.steps[0].streamsComplete, true);
  assert.equal(record.outputComplete, true);
  assert.equal(record.callerOutputComplete, false);
  assert.equal(record.complete, false);
  assert.equal(record.locksReleased, true);
  assertFullCallerOutput(result.stdout);
  assert.deepEqual(result.stdout, readFileSync(join(attempts(f)[0], 'output.log')));
  assert.deepEqual(locks(f), []);
});

test('failed fixtures retain actual evidence and reap owned callers; successful fixtures are removed', async t => {
  const f = fixture(t), harness = join(f.directory, 'retention.test.mjs');
  const paths = join(f.directory, 'fixture-paths.json');
  const unrelatedReady = join(f.root, 'unrelated-ready');
  const unrelated = start(f, {graceSeconds: cancellationGraceSeconds, steps: steps(`
    require('fs').writeFileSync(${JSON.stringify(unrelatedReady)}, String(process.pid));
    setInterval(() => {}, 1000);`)});
  await until(() => existsSync(unrelatedReady));
  // Exercise a real failing child test and real Node outcome APIs, without
  // failing this suite or importing/re-running its other test definitions.
  writeFileSync(harness, `import assert from 'node:assert/strict';
    import {spawn} from 'node:child_process';
    import {existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
    import {tmpdir} from 'node:os'; import {join} from 'node:path'; import test from 'node:test';
    const guard = ${JSON.stringify(guard)};
    const tinyResources = ${JSON.stringify(tinyResources)};
    const cancellationGraceSeconds = ${cancellationGraceSeconds};
    const sleep = ${sleep.toString()};
    ${[fixture, steps, start, until].map(fn => fn.toString()).join('\n')}
    const paths = {};
    test('intentional fixture failure', async t => {
      assert.equal(typeof t.passed, 'boolean');
      const f = fixture(t); paths.failed = f.directory;
      writeFileSync(${JSON.stringify(paths)}, JSON.stringify(paths));
      const marker = join(f.root, 'owned-pid');
      start(f, {graceSeconds: ${cancellationGraceSeconds}, steps: steps(
        "process.stdout.write('before fixture assertion' + String.fromCharCode(10), () => {" +
        "require('fs').writeFileSync(" + JSON.stringify(marker) + ", String(process.pid));});" +
        "setInterval(() => {}, 1000);")});
      await until(() => existsSync(marker));
      assert.fail('intentional fixture assertion');
    });
    test('intentional fixture success', async t => {
      const f = fixture(t); paths.passed = f.directory;
      writeFileSync(${JSON.stringify(paths)}, JSON.stringify(paths));
      assert.equal((await start(f).done).code, 0);
    });`);
  const result = spawnSync(process.execPath, ['--test', harness],
    {env: f.env, encoding: 'utf8', timeout: 20000});
  assert.equal(result.error, undefined);
  assert.equal(result.status, 1, result.stderr);
  const retained = JSON.parse(readFileSync(paths));
  t.after(() => { if (t.passed) rmSync(retained.failed, {recursive: true, force: true}); });
  assert.ok(result.stdout.includes(`Failed local guard fixture retained: ${retained.failed}`));
  assert.equal(existsSync(retained.passed), false, 'successful fixture cleanup is unchanged');
  const failed = {root: join(retained.failed, 'checkout')};
  const [evidence] = attempts(failed), record = summary(evidence);
  const failure = JSON.parse(readFileSync(join(retained.failed, 'failure.json')));
  assert.match(failure.error, /intentional fixture assertion/u);
  assert.equal(record.status, 'interrupted');
  assert.equal(record.exitCode, 130);
  assert.equal(record.locksReleased, true);
  assert.equal(record.steps[0].streamsComplete, true);
  assert.equal(readFileSync(join(evidence, 'output.log'), 'utf8'), 'before fixture assertion\n');
  assert.equal(readFileSync(join(retained.failed, 'caller-0.stdout'), 'utf8'), 'before fixture assertion\n');
  assert.equal(failure.callers[0].code, 130);
  assert.equal(Boolean(live(failure.callers[0].pid)), false);
  assert.equal(Boolean(live(Number(readFileSync(join(failed.root, 'owned-pid'))))), false);
  assert.equal(Boolean(live(Number(readFileSync(unrelatedReady)))), true, 'another fixture is not signalled');
  unrelated.child.kill('SIGINT');
  assert.equal((await unrelated.done).code, 130);
});

test('budgets come from workflow or explicit positive timer-safe seconds', () => {
  assert.equal(checkBudget(undefined, 30), 1800);
  assert.equal(checkBudget('0.2', 30), 0.2);
  assert.throws(() => checkBudget(undefined, undefined), /supply --timeout-seconds/u);
  for (const value of ['0', '-1', 'NaN', 'Infinity', '1e9', '2147484', '', undefined]) {
    assert.throws(() => durationSeconds(value), /positive/u);
  }
});

test('locks use canonical worktree and home/host state, not TMPDIR', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const link = join(f.directory, 'checkout-link'); symlinkSync(f.root, link);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  assert.throws(() => acquireLocalLocks({root: link, heavy: false, directory}), /lock busy/u);
  assert.match(lockOwnerStatus(lock.owner), /PID present/u);
  assert.ok(directory.path.startsWith(join(f.home, '.cache/actql/local-checks')));
  lock.release(); assert.deepEqual(locks(f), []);
});

test('unknown/stale/PID-reused owners and changed tokens are never reclaimed', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const foreign = {...lock.owner, token: 'different-owner', pid: 2147483647};
  writeFileSync(lock.paths[0], JSON.stringify(foreign));
  assert.throws(() => lock.release(), /changed local check lock/u);
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: false, directory}), /No automatic stale-lock removal/u);
  assert.equal(JSON.parse(readFileSync(lock.paths[0])).token, 'different-owner');
  assert.equal(lockOwnerStatus({...lock.owner, uid: -1}), 'unknown');
});

test('state directory symlinks and foreign lock-file symlinks are refused', t => {
  const f = fixture(t), foreign = join(f.directory, 'foreign'); mkdirSync(foreign);
  symlinkSync(foreign, join(f.home, '.cache'));
  assert.throws(() => lockDirectory(f.home), /without symlinks/u);
  assert.deepEqual(readdirSync(foreign), []);
  rmSync(join(f.home, '.cache'));
  const directory = lockDirectory(f.home);
  const sentinel = join(foreign, 'sentinel'); writeFileSync(sentinel, 'untouched');
  symlinkSync(sentinel, join(directory.path, 'heavy.lock'));
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory}), /lock busy/u);
  assert.equal(readFileSync(sentinel, 'utf8'), 'untouched');
  assert.deepEqual(readdirSync(directory.path), ['heavy.lock']);
});

test('a FIFO lock fails promptly without reclaiming it or leaving the partial worktree lock', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const fifo = join(directory.path, 'heavy.lock');
  const made = spawnSync('mkfifo', [fifo], {encoding: 'utf8', timeout: 1000});
  assert.equal(made.status, 0, made.stderr);
  const unrelated = join(directory.path, 'unrelated.lock'); writeFileSync(unrelated, 'untouched');
  const script = `import {acquireLocalLocks} from ${JSON.stringify(guard)};
    acquireLocalLocks({root: ${JSON.stringify(f.root)}, heavy: true});`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', script],
    {env: f.env, encoding: 'utf8', timeout: 1000, killSignal: 'SIGKILL'});
  assert.equal(result.error, undefined, 'lock inspection must not require the external kill bound');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /lock busy/u);
  assert.ok(lstatSync(fifo).isFIFO());
  assert.equal(readFileSync(unrelated, 'utf8'), 'untouched');
  assert.deepEqual(locks(f).sort(), ['heavy.lock', 'unrelated.lock']);
});

test('nonempty success records completion only after owned locks are released', async t => {
  const f = fixture(t), alias = join(f.directory, 'checkout-alias'); symlinkSync(f.root, alias);
  const result = await start(f, {root: alias}).done;
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /fixture ran/u);
  const [evidence] = attempts(f), record = summary(evidence);
  assert.equal(record.complete, true);
  assert.equal(record.exitCode, 0);
  assert.equal(record.status, 'passed');
  assert.equal(record.steps.length, 1);
  assert.equal(record.steps[0].status, 'passed');
  assert.equal(readFileSync(join(evidence, 'output.log'), 'utf8'), 'fixture ran\n');
  assert.deepEqual(locks(f), []);
});

test('redaction cannot grow persisted output past the byte limit or certify truncated evidence', async t => {
  const f = fixture(t);
  const result = await start(f, {steps: steps("process.stdout.write('z8q1'.repeat(900000))")},
    {FIXTURE_SECRET: 'z8q1'}).done;
  assert.equal(result.code, 1, result.stderr);
  const [evidence] = attempts(f), record = summary(evidence);
  const bytes = readFileSync(join(evidence, 'output.log'));
  assert.equal(bytes.length, 8 * 1024 * 1024);
  assert.equal(bytes.includes('z8q1'), false);
  assert.equal(record.outputComplete, false);
  assert.equal(record.complete, false);
  assert.equal(record.exitCode, 1);
  assert.notEqual(record.status, 'passed');
  assert.deepEqual(locks(f), []);
});

for (const exitCode of [0, 7]) {
  test(`changed lock ownership leaves an incomplete summary and preserves command status ${exitCode}`, async t => {
    const f = fixture(t);
    const source = locateEvidence + `
      const record = JSON.parse(fs.readFileSync(path.join(attempt, 'summary.json')));
      fs.writeFileSync('slot-lock-before.json', fs.readFileSync(record.locks[1]));
      fs.writeFileSync('barrier-lock-before.json', fs.readFileSync(record.heavyAdmission.barrier));
      const owner = JSON.parse(fs.readFileSync(record.locks[0]));
      owner.token = 'changed-owner'; fs.writeFileSync(record.locks[0], JSON.stringify(owner));
      console.log('owned command completed'); process.exit(${exitCode});`;
    const result = await start(f, {steps: steps(source)}).done;
    assert.equal(result.code, exitCode || 1, result.stderr);
    const record = summary(attempts(f)[0]);
    assert.equal(record.complete, false);
    assert.equal(record.exitCode, exitCode || 1);
    assert.equal(record.locksReleased, false);
    assert.notEqual(record.status, 'passed');
    assert.equal(record.steps[0].code, exitCode);
    assert.equal(JSON.parse(readFileSync(record.locks[0])).token, 'changed-owner');
    // Refused original worktree custody must preserve the shared reservation
    // and compatibility barrier too; it cannot certify available capacity.
    assert.deepEqual(locks(f).sort(), [...record.locks,
      record.heavyAdmission.barrier].map(path => path.split('/').at(-1)).sort());
    assert.deepEqual(readFileSync(record.locks[1]), readFileSync(join(f.root, 'slot-lock-before.json')));
    assert.deepEqual(readFileSync(record.heavyAdmission.barrier),
      readFileSync(join(f.root, 'barrier-lock-before.json')));
    const member = JSON.parse(readFileSync(record.locks[1]));
    const barrier = JSON.parse(readFileSync(record.heavyAdmission.barrier));
    for (const key of ['token', 'pid', 'uid', 'host', 'worktree']) {
      assert.equal(member[key], record.owner[key]);
      assert.equal(barrier[key], record.owner[key]);
    }
    assert.equal(member.heavyPool.version, 'actql-local-heavy-pool/' + String(1));
    assert.equal(barrier.heavyPool.version, member.heavyPool.version);
    assert.equal(member.heavyPool.token, barrier.heavyPool.token);
    assert.equal(member.heavyPool.slot, record.heavyAdmission.slot);
    assert.deepEqual(member.heavyPool.resources, tinyResources);
  });
}

for (const name of ['output.log', 'summary.json']) {
  for (const replacement of ['symlink', 'hardlink', 'regular', 'fifo']) {
    test(`replaced ${name} ${replacement} is never truncated and preserves a failing command`, async t => {
      const f = fixture(t), sentinel = join(f.directory, 'sentinel');
      writeFileSync(sentinel, 'unrelated bytes');
      const operation = {
        symlink: `fs.symlinkSync(${JSON.stringify(sentinel)}, target)`,
        hardlink: `fs.linkSync(${JSON.stringify(sentinel)}, target)`,
        regular: `fs.writeFileSync(target, 'replacement bytes')`,
        fifo: `require('child_process').execFileSync('mkfifo', [target])`,
      }[replacement];
      const source = locateEvidence + `
        const target = path.join(attempt, ${JSON.stringify(name)});
        fs.renameSync(target, target + '.saved'); ${operation};
        console.log('original failure output'); process.exit(7);`;
      const result = await start(f, {steps: steps(source)}).done;
      assert.equal(result.code, 7, result.stderr);
      assert.equal(readFileSync(sentinel, 'utf8'), 'unrelated bytes');
      const [evidence] = attempts(f), target = join(evidence, name);
      if (replacement === 'regular') assert.equal(readFileSync(target, 'utf8'), 'replacement bytes');
      if (replacement === 'fifo') assert.ok(lstatSync(target).isFIFO());
      const record = JSON.parse(readFileSync(join(evidence, name === 'summary.json' ? 'summary.json.saved' : 'summary.json')));
      assert.equal(record.complete, false);
      if (name === 'output.log') assert.equal(record.exitCode, 7);
      assert.match(result.stdout, /original failure output/u);
      assert.deepEqual(locks(f), []);
    });
  }
}

for (const replaceParent of [false, true]) {
  test(`replaced evidence ${replaceParent ? 'parent' : 'attempt'} directory is refused`, async t => {
    const f = fixture(t), foreign = join(f.directory, 'foreign'); mkdirSync(foreign);
    const source = locateEvidence + `
      const replaced = ${replaceParent ? 'parent' : 'attempt'};
      fs.renameSync(replaced, replaced + '.saved');
      const destination = ${replaceParent ? `path.join(${JSON.stringify(foreign)}, path.basename(attempt))` : JSON.stringify(foreign)};
      fs.mkdirSync(destination, {recursive: true});
      for (const name of ['summary.json', 'output.log']) fs.writeFileSync(path.join(destination, name), 'unrelated bytes');
      fs.symlinkSync(${JSON.stringify(foreign)}, replaced);
      console.log('directory replacement output');`;
    const result = await start(f, {steps: steps(source)}).done;
    assert.equal(result.code, 1, result.stderr);
    assert.match(result.stderr, /EvidenceDirectoryOwnershipChanged/u);
    const parent = join(f.root, '_build/local-checks/attempts');
    const retained = replaceParent ? join(parent + '.saved', readdirSync(parent + '.saved')[0]) :
      join(parent, readdirSync(parent).find(name => name.endsWith('.saved')));
    assert.equal(summary(retained).complete, false);
    const destination = replaceParent ? join(foreign, readdirSync(foreign)[0]) : foreign;
    for (const name of ['summary.json', 'output.log']) assert.equal(readFileSync(join(destination, name), 'utf8'), 'unrelated bytes');
    assert.deepEqual(locks(f), []);
  });
}

test('an existing evidence ancestor symlink starts no command and changes no foreign directory', async t => {
  const f = fixture(t), foreign = join(f.directory, 'foreign'); mkdirSync(foreign);
  writeFileSync(join(foreign, 'sentinel'), 'unrelated bytes');
  symlinkSync(foreign, join(f.root, '_build'));
  const result = await start(f).done;
  assert.equal(result.code, 1, result.stderr);
  assert.doesNotMatch(result.stdout, /fixture ran/u);
  assert.deepEqual(readdirSync(foreign), ['sentinel']);
  assert.equal(readFileSync(join(foreign, 'sentinel'), 'utf8'), 'unrelated bytes');
  assert.deepEqual(locks(f), []);
});

test('failure preserves exit status and logs, without retry, then releases locks', async t => {
  const f = fixture(t), marker = join(f.root, 'calls');
  const result = await start(f, {steps: steps(`require('fs').appendFileSync(${JSON.stringify(marker)}, 'x'); console.log('failure details'); process.exit(7)`)}).done;
  assert.equal(result.code, 7, result.stderr);
  assert.equal(readFileSync(marker, 'utf8'), 'x');
  const [evidence] = attempts(f);
  assert.equal(summary(evidence).status, 'failed');
  assert.equal(summary(evidence).complete, false);
  assert.equal(summary(evidence).exitCode, 7);
  assert.equal(summary(evidence).steps[0].code, 7);
  assert.equal(summary(evidence).steps[0].streamsComplete, true);
  assert.ok(summary(evidence).steps[0].exitedAt);
  assert.match(readFileSync(join(evidence, 'output.log'), 'utf8'), /failure details/u);
  assert.deepEqual(locks(f), []);
});

// Hold the admitted command until the competing caller has finished. A fixed
// sleep can end before a slow caller reaches admission and cannot prove a race.
function heldSteps(marker, release) {
  return steps(`const fs = require('fs');
    fs.writeFileSync(${JSON.stringify(marker)}, 'x');
    const timer = setInterval(() => {
      if (fs.existsSync(${JSON.stringify(release)})) clearInterval(timer);
    }, 10);`);
}

test('heavy admission refuses memory, disk, CPU pressure and more than four reservations', () => {
  const available = {memoryBytes: 1024 ** 3, totalMemoryBytes: 2 * 1024 ** 3,
    diskBytes: 1024 ** 3, cpuThreads: 4};
  assert.equal(heavyResourceAdmission(tinyResources, [], available).admitted, true);
  for (const key of Object.keys(available)) {
    assert.equal(heavyResourceAdmission(tinyResources, [], {...available, [key]: 0}).admitted,
      false, key);
  }
  assert.equal(heavyResourceAdmission(tinyResources, Array(4).fill(tinyResources),
    {...available, cpuThreads: 64}).admitted, false);
  for (const value of [null, [], {unknown: 1}, {cpuThreads: 0}, {diskBytes: -1},
    {memoryBytes: 1.5}, {memoryBytes: Number.MAX_SAFE_INTEGER + 1}]) {
    assert.throws(() => heavyResourceRequest(value), /resources|request/u);
  }
});

test('heavy admission does not subtract existing memory estimates from current availability again', () => {
  const gib = 1024 ** 3;
  const request = {memoryBytes: 6 * gib, diskBytes: 2 * gib, cpuThreads: 1};
  const members = [{memoryBytes: 8 * gib, diskBytes: 2 * gib, cpuThreads: 1}];
  const available = {memoryBytes: 15118284881, totalMemoryBytes: 32 * gib,
    diskBytes: 40 * gib, cpuThreads: 10};
  assert.equal(heavyResourceAdmission(request, members, available).admitted, true);
  assert.equal(heavyResourceAdmission(request, members,
    {...available, memoryBytes: 6 * gib}).admitted, false);
  assert.equal(heavyResourceAdmission(request, members,
    {...available, totalMemoryBytes: 14 * gib}).admitted, false);
});

test('available memory uses OS availability rather than cache-depleted raw free pages', () => {
  assert.equal(availableVerificationMemory('linux',
    'MemTotal: 2048000 kB\nMemFree: 100 kB\nMemAvailable: 1024000 kB\n'), 1024000 * 1024);
  assert.equal(availableVerificationMemory('darwin',
    'The system has 34359738368.\nSystem-wide memory free percentage: 35%\n',
    32 * 1024 ** 3), Math.floor(32 * 1024 ** 3 * 0.35));
  for (const [platform, text] of [['linux', 'MemFree: 100 kB'],
    ['darwin', 'System-wide memory free percentage: 101%'], ['darwin', 'unknown']]) {
    assert.throws(() => availableVerificationMemory(platform, text, 32 * 1024 ** 3),
      /could not be measured/u);
  }
});

test('four real heavy supervisors coexist, refuse a fifth, and keep the legacy barrier until last release', async t => {
  if (availableParallelism() < 4) {
    t.skip('Four CPU reservations require four actual available CPUs; pure admission counters still run');
    return;
  }
  const f = fixture(t), directory = lockDirectory(f.home), runs = [], markers = [], releases = [];
  for (let index = 0; index < 4; index++) {
    const root = join(f.directory, `parallel-${index}`); mkdirSync(root);
    const marker = join(root, 'started'), release = join(root, 'release');
    markers.push(marker); releases.push(release);
    runs.push(start(f, {root, timeoutSeconds: 30, steps: heldSteps(marker, release)}));
  }
  await until(() => markers.every(existsSync));
  const barrier = join(directory.path, 'heavy.lock');
  const originalBarrier = readFileSync(barrier, 'utf8');
  try {
    assert.equal(locks(f).filter(name => name.startsWith('heavy-slot-')).length, 4);
    const fifthRoot = join(f.directory, 'fifth'); mkdirSync(fifthRoot);
    const fifth = await start(f, {root: fifthRoot}).done;
    assert.equal(fifth.code, 1);
    assert.match(fifth.stderr, /queue\/resource pressure/u);
    assert.doesNotMatch(fifth.stdout, /fixture ran/u);
    // This is the old guard's exclusive-create primitive, not a pooled reader.
    const legacy = spawnSync(process.execPath, ['-e',
      `require('fs').openSync(${JSON.stringify(barrier)}, 'wx');`], {encoding: 'utf8'});
    assert.equal(legacy.status, 1);
    assert.match(legacy.stderr, /EEXIST/u);
    writeFileSync(releases[0], 'x');
    assert.equal((await runs[0].done).code, 0);
    assert.equal(readFileSync(barrier, 'utf8'), originalBarrier,
      'one completed Owner cannot release a compatibility barrier held by other jobs');
    const replacement = await start(f, {root: fifthRoot}).done;
    assert.equal(replacement.code, 0, replacement.stderr);
    assert.equal(locks(f).filter(name => name.startsWith('heavy-slot-')).length, 3);
  } finally {
    for (const release of releases) writeFileSync(release, 'x');
    for (const result of await Promise.all(runs.map(run => run.done))) {
      assert.equal(result.code, 0, result.stderr);
    }
  }
  assert.deepEqual(locks(f), []);
});

test('a live legacy singleton and malformed pooled members are retained, not bypassed', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const barrier = join(directory.path, 'heavy.lock');
  const legacy = {token: 'legacy-live-owner', pid: process.pid, uid: process.getuid(),
    host: hostname(), worktree: f.root};
  writeFileSync(barrier, JSON.stringify(legacy));
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: true,
    heavyResources: tinyResources, directory}), /lock busy/u);
  assert.deepEqual(JSON.parse(readFileSync(barrier)), legacy);
  rmSync(barrier); // fixture owns this inert fake lock, not a production Owner.
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const slot = lock.paths[1], original = readFileSync(slot, 'utf8');
  const malformed = JSON.parse(original); malformed.heavyPool.resources = {cpuThreads: 1};
  writeFileSync(slot, JSON.stringify(malformed));
  const other = join(f.directory, 'other'); mkdirSync(other);
  assert.throws(() => acquireLocalLocks({root: other, heavy: true,
    heavyResources: tinyResources, directory}), /lock busy/u);
  assert.equal(readFileSync(slot, 'utf8'), JSON.stringify(malformed));
  writeFileSync(slot, original); lock.release();
  assert.deepEqual(locks(f), []);
});

test('pooled admission and release retain an orphan member whose worktree lock is missing', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const worktree = lock.paths[0], original = readFileSync(worktree, 'utf8');
  const barrier = readFileSync(join(directory.path, 'heavy.lock'), 'utf8');
  const member = readFileSync(lock.paths[1], 'utf8');
  rmSync(worktree); // This fixture owns the original lock and restores its bytes below.
  const other = join(f.directory, 'other'); mkdirSync(other);
  try {
    assert.throws(() => acquireLocalLocks({root: other, heavy: true,
      heavyResources: tinyResources, directory}), /lock busy/u);
    assert.throws(() => lock.release(), /lock busy/u);
    assert.equal(readFileSync(join(directory.path, 'heavy.lock'), 'utf8'), barrier);
    assert.equal(readFileSync(lock.paths[1], 'utf8'), member);
    assert.deepEqual(locks(f).sort(), ['heavy-slot-1.lock', 'heavy.lock']);
  } finally { writeFileSync(worktree, original); }
  // Recreating an original lock is manual fixture recovery, not guard recovery.
});

test('pooled admission and release refuse a member whose worktree Owner token changed', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const worktree = lock.paths[0], original = readFileSync(worktree, 'utf8');
  const changed = {...JSON.parse(original), token: 'a-different-worktree-owner'};
  writeFileSync(worktree, JSON.stringify(changed));
  const barrier = readFileSync(join(directory.path, 'heavy.lock'), 'utf8');
  const member = readFileSync(lock.paths[1], 'utf8');
  const other = join(f.directory, 'other'); mkdirSync(other);
  try {
    assert.throws(() => acquireLocalLocks({root: other, heavy: true,
      heavyResources: tinyResources, directory}), /lock busy/u);
    assert.throws(() => lock.release(), /changed local check lock/u);
    assert.equal(readFileSync(join(directory.path, 'heavy.lock'), 'utf8'), barrier);
    assert.equal(readFileSync(lock.paths[1], 'utf8'), member);
    assert.equal(readFileSync(worktree, 'utf8'), JSON.stringify(changed));
    assert.equal(locks(f).length, 3);
  } finally { writeFileSync(worktree, original); }
  lock.release();
  assert.deepEqual(locks(f), []);
});

test('partial heavy admission failure releases only its new locks and preserves other members', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: true,
    heavyResources: {cpuThreads: 0}, directory}), /positive safe integers/u);
  assert.deepEqual(locks(f), [], 'failed first construction leaves no barrier or reservation');
  const first = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const original = locks(f).sort().map(name => [name, readFileSync(join(directory.path, name), 'utf8')]);
  const other = join(f.directory, 'other'); mkdirSync(other);
  assert.throws(() => acquireLocalLocks({root: other, heavy: true,
    heavyResources: {...tinyResources, cpuThreads: Number.MAX_SAFE_INTEGER}, directory}),
  /queue\/resource pressure/u);
  assert.deepEqual(locks(f).sort().map(name => [name, readFileSync(join(directory.path, name), 'utf8')]),
    original, 'failed second construction cannot remove a retained member or its barrier');
  first.release();
  assert.deepEqual(locks(f), []);
});

test('unknown pool admission mutex is retained without acquiring a slot', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const mutex = join(directory.path, 'heavy-pool-admission.lock');
  writeFileSync(mutex, 'unknown-owner');
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: true,
    heavyResources: tinyResources, directory}), /No automatic stale-lock removal/u);
  assert.equal(readFileSync(mutex, 'utf8'), 'unknown-owner');
  assert.deepEqual(locks(f), ['heavy-pool-admission.lock']);
});

test('oversized heavy member metadata refuses admission and release while preserving custody', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const slot = lock.paths[1], original = readFileSync(slot, 'utf8');
  const oversized = JSON.stringify({...JSON.parse(original), unknown: 'x'.repeat(16385)});
  writeFileSync(slot, oversized);
  const barrier = readFileSync(join(directory.path, 'heavy.lock'), 'utf8');
  const other = join(f.directory, 'other'); mkdirSync(other);
  try {
    assert.throws(() => acquireLocalLocks({root: other, heavy: true,
      heavyResources: tinyResources, directory}), /lock busy/u);
    assert.throws(() => lock.release(), /metadata is ambiguous/u);
    assert.equal(readFileSync(slot, 'utf8'), oversized);
    assert.equal(readFileSync(join(directory.path, 'heavy.lock'), 'utf8'), barrier);
    assert.equal(locks(f).length, 3);
  } finally { writeFileSync(slot, original); }
  lock.release();
  assert.deepEqual(locks(f), []);
});

test('changed pooled epoch and out-of-range slots refuse admission without reclaiming custody', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, heavyResources: tinyResources, directory});
  const barrier = join(directory.path, 'heavy.lock'), original = readFileSync(barrier, 'utf8');
  const changed = JSON.parse(original); changed.heavyPool.token = 'changed-epoch';
  writeFileSync(barrier, JSON.stringify(changed));
  assert.throws(() => lock.release(), /changed heavy compatibility barrier/u);
  assert.equal(locks(f).length, 3);
  writeFileSync(barrier, original);
  const unknown = join(directory.path, 'heavy-slot-5.lock'); writeFileSync(unknown, 'unreviewed-slot');
  const other = join(f.directory, 'other'); mkdirSync(other);
  assert.throws(() => acquireLocalLocks({root: other, heavy: true,
    heavyResources: tinyResources, directory}), /lock busy/u);
  assert.equal(readFileSync(unknown, 'utf8'), 'unreviewed-slot');
  rmSync(unknown); lock.release();
  assert.deepEqual(locks(f), []);
});

test('same-worktree race refuses overlap while independent heavy worktrees share admission', async t => {
  const f = fixture(t), marker = join(f.root, 'started'), release = join(f.root, 'release');
  const first = start(f, {steps: heldSteps(marker, release)});
  await until(() => existsSync(marker));
  let admitted;
  try {
    const same = start(f, {}, {TMPDIR: join(f.directory, 'different-temp')});
    const otherRoot = join(f.directory, 'other'); mkdirSync(otherRoot);
    const other = start(f, {root: otherRoot});
    const refused = await same.done;
    assert.equal(refused.code, 1);
    assert.match(refused.stderr, /lock busy/u);
    assert.doesNotMatch(refused.stdout, /fixture ran/u);
    const accepted = await other.done;
    assert.equal(accepted.code, 0, accepted.stderr);
    assert.match(accepted.stdout, /fixture ran/u);
    assert.equal(locks(f).length, 3, 'original command retains worktree, reservation and compatibility barrier');
  } finally {
    writeFileSync(release, 'x');
    admitted = await first.done;
  }
  assert.equal(admitted.code, 0, admitted.stderr);
  assert.deepEqual(locks(f), []);
});

test('focused work in another worktree does not take the heavy lock', async t => {
  const f = fixture(t), marker = join(f.root, 'started'), release = join(f.root, 'release');
  const first = start(f, {steps: heldSteps(marker, release)});
  await until(() => existsSync(marker));
  let admitted;
  try {
    const otherRoot = join(f.directory, 'other'); mkdirSync(otherRoot);
    assert.equal((await start(f, {root: otherRoot, heavy: false}).done).code, 0);
    assert.equal(locks(f).length, 3, 'focused work finishes while the original heavy custody remains');
  } finally {
    writeFileSync(release, 'x');
    admitted = await first.done;
  }
  assert.equal(admitted.code, 0, admitted.stderr);
  assert.deepEqual(locks(f), []);
});

test('Native approval OS sampler timeout remains inside the existing owned process group', async t => {
  const f = fixture(t), pids = join(f.root, 'sampler-descendants');
  const worker = `require('fs').writeFileSync(${JSON.stringify(pids)}, JSON.stringify([process.pid]));setInterval(()=>{},1000);`;
  const source = `const {execFile}=require('child_process');
    execFile('/usr/bin/time', ['-p','-o',${JSON.stringify(join(f.root, 'resource-report'))},
      process.execPath,'-e',${JSON.stringify(worker)}], {timeout:500, killSignal:'SIGKILL'}, () => {
      // The sampler is gone; its actual child still belongs to the SAME guard.
      process.exit(0);
    });`;
  const result = await start(f, {timeoutSeconds: cancellationTimeoutSeconds, steps: steps(source)}).done;
  assert.notEqual(result.code, 0, 'Killing only the sampler cannot establish completion');
  for (const pid of JSON.parse(readFileSync(pids))) assert.equal(Boolean(live(pid)), false);
  const record = summary(attempts(f)[0]);
  assert.equal(record.outputComplete, true);
  assert.equal(record.locksReleased, true);
  assert.deepEqual(locks(f), []);
  // This proves operator process ownership only, not a Native Host/Store ACK.
});

test('timeout stops inherited descendants and leaves an unrelated process alive', async t => {
  const f = fixture(t), pids = join(f.root, 'pids');
  const unrelated = spawn(process.execPath, ['-e', 'setInterval(()=>{}, 1000)']);
  t.after(() => unrelated.kill());
  const source = `const {spawn}=require('child_process');
    const c=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});
    require('fs').writeFileSync(${JSON.stringify(pids)},JSON.stringify([process.pid,c.pid]));
    console.log('before timeout');setInterval(()=>{},1000);`;
  const result = await start(f, {timeoutSeconds: cancellationTimeoutSeconds, steps: steps(source)}).done;
  assert.equal(result.code, 124, result.stderr);
  for (const pid of JSON.parse(readFileSync(pids))) assert.equal(Boolean(live(pid)), false);
  assert.ok(live(unrelated.pid));
  assert.equal(summary(attempts(f)[0]).status, 'timeout');
  assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /before timeout/u);
  assert.deepEqual(locks(f), []);
});

for (const [exitCode, resistant] of [[0, false], [7, false], [7, true]]) {
  test(`leftover descendant cleanup preserves status ${exitCode} with TERM resistance ${resistant}`, async t => {
    const f = fixture(t), pidFile = join(f.root, 'descendant-pid');
    const descendant = `${resistant ? "process.on('SIGTERM',()=>{});" : ''}
      process.send('ready'); setTimeout(()=>{}, 2000);`;
    const source = `const {spawn} = require('child_process');
      const child = spawn(process.execPath, ['-e', ${JSON.stringify(descendant)}],
        {stdio: ['ignore', 'ignore', 'ignore', 'ipc']});
      child.once('message', () => {
        require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
        child.disconnect(); child.unref(); console.log('parent exit ${exitCode}'); process.exit(${exitCode});
      });`;
    const result = await start(f, {graceSeconds: 0.1, steps: steps(source)}).done;
    assert.equal(result.code, exitCode || 1, result.stderr);
    const record = summary(attempts(f)[0]);
    assert.equal(record.complete, false);
    assert.equal(record.steps[0].code, exitCode);
    assert.match(record.status, /command left running descendants/u);
    assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
    assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /parent exit/u);
    if (resistant) {
      assert.match(record.status, /SIGKILL escalation/u);
      assert.equal(locks(f).length, 3);
    } else {
      assert.equal(record.exitCode, exitCode || 1);
      assert.deepEqual(locks(f), []);
    }
  });
}

test('TERM-resistant descendants trigger owned-group KILL and retain locks', async t => {
  const f = fixture(t), pidFile = join(f.root, 'pid');
  const captured = join(f.root, 'output-captured'), preload = join(f.directory, 'capture-ready.mjs');
  writeFileSync(preload, `import childProcess from 'node:child_process';
    import fs from 'node:fs';
    import {syncBuiltinESMExports} from 'node:module';
    if (process.argv[1]?.endsWith('/local-checks-supervisor.mjs')) {
      const original = childProcess.spawn;
      childProcess.spawn = (...args) => {
        const child = original(...args);
        // Register after the supervisor's capture listener. A PID file proves
        // handler installation, not that the supervisor observed stdout yet.
        setImmediate(() => child.stdout?.on('data', bytes => {
          if (bytes.toString().includes('resistant')) fs.writeFileSync(${JSON.stringify(captured)}, 'observed');
        }));
        return child;
      };
      syncBuiltinESMExports();
    }`);
  f.env.NODE_OPTIONS = [f.env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ');
  // Cancellation must follow handler installation, rather than race Node startup
  // against a 0.2s timeout. Delay readiness past the former timeout explicitly;
  // timeout cancellation itself is covered by the inherited-pipe cases below.
  const source = `setTimeout(() => {
    process.on('SIGTERM',()=>{});
    require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));
    console.log('resistant'); setInterval(()=>{},1000);
  }, 350);`;
  const run = start(f, {graceSeconds: 0.1, steps: steps(source)});
  let result;
  try {
    await until(() => existsSync(pidFile) && existsSync(captured));
    run.child.kill('SIGINT');
  } finally { result = await run.done; }
  assert.equal(result.code, 130, result.stderr);
  assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
  assert.equal(locks(f).length, 3);
  assert.match(summary(attempts(f)[0]).status, /^interrupted/u);
  assert.match(summary(attempts(f)[0]).status, /SIGKILL escalation/u);
  assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /resistant/u);
  const next = await start(f).done;
  assert.equal(next.code, 1);
  assert.match(next.stderr, /No automatic stale-lock removal/u);
});

for (const exitCode of [0, 7]) {
  for (const [cancellation, resistant] of [['timeout', false], ['timeout', true], ['caller', false], ['caller', true]]) {
    test(`inherited pipes retain direct exit ${exitCode} before ${cancellation} cancellation and TERM resistance ${resistant}`, async t => {
      const f = fixture(t), pidFile = join(f.root, 'descendant-pid');
      const termObserved = join(f.root, 'descendant-TERM');
      const descendant = locateEvidence + `
        process.on('SIGTERM', () => {
          const record = JSON.parse(fs.readFileSync(path.join(attempt, 'summary.json')));
          fs.writeFileSync(${JSON.stringify(termObserved)}, JSON.stringify({
            status: record.status, code: record.steps[0].code,
            streamsComplete: record.steps[0].streamsComplete,
          }));
          ${resistant ? '' : 'process.exit(0);'}
        });
        // Resistance, not a short grace or a self-expiring timer, forces KILL.
        // Readiness proves this handler is installed before the direct exit.
        process.send('ready'); setInterval(()=>{}, 1000);`;
      const source = `const {spawn} = require('child_process');
        const child = spawn(process.execPath, ['-e', ${JSON.stringify(descendant)}],
          {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
        child.once('message', () => {
          require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
          child.disconnect(); child.unref(); console.log('direct stdout'); console.error('direct stderr');
          process.exit(${exitCode});
        });`;
      const run = start(f, {timeoutSeconds: cancellation === 'timeout' ? cancellationTimeoutSeconds : 10,
        graceSeconds: cancellationGraceSeconds, steps: steps(source)});
      let pending, result;
      try {
        await until(() => {
          try {
            if (attempts(f).length === 0) return false;
            pending = summary(attempts(f)[0]);
            return pending.steps[0]?.code === exitCode;
          } catch (error) {
            if (error.code === 'ENOENT' || error instanceof SyntaxError) return false;
            throw error;
          }
        });
        assert.equal(pending.complete, false);
        assert.equal(pending.status, exitCode ? 'failed' : 'running', 'direct exit precedes cancellation');
        assert.equal(pending.steps[0].streamsComplete, false);
        assert.equal(pending.steps[0].status, exitCode ? 'failed' : 'draining');
        assert.ok(pending.steps[0].exitedAt);
        assert.equal(locks(f).length, 3, 'direct exit alone must not release custody');
        if (cancellation === 'caller') run.child.kill('SIGINT');
      } finally { result = await run.done; }
      const expected = exitCode || (cancellation === 'timeout' ? 124 : 130);
      assert.equal(result.code, expected, result.stderr);
      const record = summary(attempts(f)[0]);
      assert.equal(record.complete, false);
      assert.equal(record.exitCode, expected);
      assert.equal(record.steps[0].code, exitCode);
      assert.equal(record.steps[0].signal, null);
      assert.deepEqual(JSON.parse(readFileSync(termObserved)), {
        status: cancellation === 'timeout' ? 'timeout' : 'interrupted',
        code: exitCode, streamsComplete: false,
      }, 'TERM observes an already-persisted direct exit, before inherited pipes close');
      assert.equal(record.steps[0].streamsComplete, !resistant);
      assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
      assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /direct stdout/u);
      assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /direct stderr/u);
      if (resistant) {
        assert.match(record.status, /SIGKILL escalation/u);
        assert.equal(record.outputComplete, false);
        assert.equal(record.locksReleased, false);
        assert.equal(locks(f).length, 3);
      } else {
        assert.equal(record.status, cancellation === 'timeout' ? 'timeout' : 'interrupted');
        assert.equal(record.outputComplete, true);
        assert.equal(record.locksReleased, true);
        assert.deepEqual(locks(f), []);
      }
    });
  }
}

for (const cancellation of ['timeout', 'caller']) {
  for (const resistant of [false, true]) {
    test(`${cancellation} cancellation keeps its status when a later TERM handler exits 7, with descendant resistance ${resistant}`, async t => {
      const f = fixture(t), ready = join(f.root, 'ready');
      const termObserved = join(f.root, 'direct-TERM');
      const descendant = `${resistant ? "process.on('SIGTERM',()=>{});" : ''}
        process.send('ready'); setInterval(()=>{}, 1000);`;
      const source = locateEvidence + `process.on('SIGTERM', () => {
          const record = JSON.parse(fs.readFileSync(path.join(attempt, 'summary.json')));
          fs.writeFileSync(${JSON.stringify(termObserved)}, JSON.stringify({
            status: record.status, code: record.steps[0].code ?? null,
          }));
          console.log('TERM handler exits 7'); process.exit(7);
        });
        // Keep the direct process alive even if its descendant exits before
        // Node dispatches the direct process's queued TERM callback.
        setInterval(()=>{}, 1000);
        const child = require('child_process').spawn(process.execPath, ['-e', ${JSON.stringify(descendant)}],
          {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
        child.once('message', () => {
          require('fs').writeFileSync(${JSON.stringify(ready)}, JSON.stringify([process.pid, child.pid]));
        });`;
      const run = start(f, {timeoutSeconds: cancellation === 'timeout' ? cancellationTimeoutSeconds : 10,
        graceSeconds: cancellationGraceSeconds, steps: steps(source)});
      let result;
      try {
        await until(() => existsSync(ready));
        if (cancellation === 'caller') run.child.kill('SIGINT');
      } finally { result = await run.done; }
      const expected = cancellation === 'timeout' ? 124 : 130;
      assert.equal(result.code, expected, result.stderr);
      const record = summary(attempts(f)[0]);
      assert.equal(record.exitCode, expected);
      assert.equal(record.steps[0].code, 7, 'late direct exit remains diagnostic evidence');
      assert.deepEqual(JSON.parse(readFileSync(termObserved)), {
        status: cancellation === 'timeout' ? 'timeout' : 'interrupted', code: null,
      }, 'cancellation is persisted before the TERM handler exits');
      assert.equal(record.steps[0].status, 'failed');
      assert.ok(record.steps[0].exitedAt);
      assert.equal(record.steps[0].streamsComplete, !resistant);
      assert.equal(record.complete, false);
      assert.equal(record.outputComplete, !resistant);
      assert.equal(record.locksReleased, !resistant);
      assert.equal(locks(f).length, resistant ? 3 : 0);
      assert.match(record.status, cancellation === 'timeout' ? /^timeout/u : /^interrupted/u);
      if (resistant) assert.match(record.status, /SIGKILL escalation/u);
      for (const pid of JSON.parse(readFileSync(ready))) assert.equal(Boolean(live(pid)), false);
      assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /TERM handler exits 7/u);
    });
  }
}

for (const [exitCode, error] of [[0, true], [7, true], [0, false]]) {
  test(`failed stdout drain cannot certify direct exit ${exitCode}, with error event ${error}`, async t => {
    const f = fixture(t), preload = join(f.directory, 'fail-drain.mjs');
    const pidFile = join(f.root, 'descendant-pid');
    // Inject only a read-side stream fault into a real owned process. The
    // command still exits normally and its inherited-pipe descendant is real.
    writeFileSync(preload, `import childProcess from 'node:child_process';
      import {syncBuiltinESMExports} from 'node:module';
      if (process.argv[1]?.endsWith('/local-checks-supervisor.mjs')) {
        const original = childProcess.spawn;
        childProcess.spawn = (...args) => {
          const child = original(...args);
          child.once('exit', () => child.stdout.destroy(${error ? "Object.assign(new Error('fixture stdout drain failed'), {code: 'EIO'})" : ''}));
          return child;
        };
        syncBuiltinESMExports();
      }`);
    const source = `const child = require('child_process').spawn(process.execPath,
      ['-e', "process.send('ready'); setInterval(()=>{},1000)"],
      {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
      child.once('message', () => {
        require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
        child.disconnect(); child.unref(); console.log('before drain failure'); process.exit(${exitCode});
      });`;
    // A drain fault still cancels a real inherited-pipe descendant. Allow the
    // same bounded normal-cancellation grace as the other lifecycle fixtures.
    const result = await start(f, {timeoutSeconds: cancellationTimeoutSeconds, graceSeconds: cancellationGraceSeconds,
      steps: steps(source)}, {NODE_OPTIONS: `--import=${preload}`}).done;
    assert.equal(result.code, exitCode || (error ? 1 : 124), result.stderr);
    const record = summary(attempts(f)[0]);
    assert.equal(record.exitCode, result.code);
    assert.equal(record.steps[0].code, exitCode);
    assert.equal(record.steps[0].streamsComplete, false);
    assert.equal(record.outputComplete, false);
    assert.equal(record.complete, false);
    if (error) assert.deepEqual(record.steps[0].streamErrors, [{stream: 'stdout', code: 'EIO'}]);
    assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
    assert.equal(record.locksReleased, true);
    assert.deepEqual(locks(f), []);
  });
}

test('caller SIGKILL disconnect is watched and cancels the owned children', async t => {
  const f = fixture(t), marker = join(f.root, 'pid');
  const run = start(f, {steps: steps(`require('fs').writeFileSync(${JSON.stringify(marker)},String(process.pid));setInterval(()=>{},1000)`)});
  await until(() => existsSync(marker));
  run.child.kill('SIGKILL');
  const result = await run.done;
  assert.equal(result.signal, 'SIGKILL');
  assert.equal(Boolean(live(Number(readFileSync(marker)))), false);
  assert.equal(summary(attempts(f)[0]).status, 'parent disconnected');
  assert.deepEqual(locks(f), []);
});

test('supervisor SIGKILL retains ownership rather than auto-clearing a stale PID', async t => {
  const f = fixture(t), marker = join(f.root, 'started');
  const run = start(f, {steps: steps(`require('fs').writeFileSync(${JSON.stringify(marker)},'x');setTimeout(()=>{},350)`)});
  await until(() => existsSync(marker));
  const record = summary(attempts(f)[0]);
  process.kill(record.owner.pid, 'SIGKILL');
  assert.equal((await run.done).code, 137);
  assert.equal(locks(f).length, 3);
  const next = await start(f).done;
  assert.equal(next.code, 1);
  assert.match(next.stderr, /No automatic stale-lock removal/u);
});

test('cancelled before acquisition starts nothing and does not signal other processes', async t => {
  const f = fixture(t), abort = new AbortController(); abort.abort();
  assert.equal(await runLocalCheck({root: f.root}, {signal: abort.signal}), 130);
  assert.deepEqual(readdirSync(f.home), []);
  assert.deepEqual(readdirSync(f.root), []);
});

test('delayed valid ps snapshots still confirm completion and release owned locks', async t => {
  const f = fixture(t), bin = join(f.directory, 'bin'); mkdirSync(bin);
  const ps = join(bin, 'ps');
  writeFileSync(ps, '#!/bin/sh\n/bin/sleep 2.3\nexec /bin/ps "$@"\n');
  chmodSync(ps, 0o755);
  const result = await start(f, {}, {PATH: bin + ':' + process.env.PATH}).done;
  assert.equal(result.code, 0, result.stderr);
  const record = summary(attempts(f)[0]);
  assert.equal(record.complete, true);
  assert.equal(record.outputComplete, true);
  assert.equal(record.locksReleased, true);
  assert.deepEqual(locks(f), []);
});

test('ps failure after execution retains locks and cannot certify completion', async t => {
  const f = fixture(t), bin = join(f.directory, 'bin'), count = join(f.directory, 'ps-count'); mkdirSync(bin);
  const ps = join(bin, 'ps');
  writeFileSync(ps, `#!${process.execPath}\nconst fs=require('fs');const p=${JSON.stringify(count)};
    if(fs.existsSync(p)) process.exit(9); fs.writeFileSync(p,'x');
    const r=require('child_process').spawnSync('/bin/ps',process.argv.slice(2),{stdio:'inherit'});process.exit(r.status);\n`);
  chmodSync(ps, 0o755);
  const result = await start(f, {}, {PATH: bin + ':' + process.env.PATH}).done;
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /Cannot inspect owned process group/u);
  assert.equal(locks(f).length, 3);
  assert.equal(summary(attempts(f)[0]).complete, false);
});
