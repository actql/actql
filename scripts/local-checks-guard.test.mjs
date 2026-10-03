import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {acquireLocalLocks, checkBudget, durationSeconds, lockDirectory,
  lockOwnerStatus, runLocalCheck} from './local-checks-guard.mjs';

const guard = new URL('./local-checks-guard.mjs', import.meta.url).href;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function fixture(t) {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), 'actql-local-guard-')));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const home = join(directory, 'home'), root = join(directory, 'checkout');
  mkdirSync(home); mkdirSync(root);
  const env = {...process.env, HOME: home};
  delete env.NODE_TEST_CONTEXT;
  return {directory, home, root, env};
}
function steps(source) {
  return [{name: 'fixture', command: process.execPath, args: ['-e', source]}];
}
function start(f, options = {}, extraEnv = {}) {
  const config = {root: f.root, heavy: true, timeoutSeconds: 10, graceSeconds: 0.2,
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
  return {child, done};
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
  stderr = 'drain', cancellation, outputBytes = 200000, failFinalEvidence = false} = {}) {
  const caller = join(f.directory, 'caller.mjs'), receiver = join(f.directory, 'receiver.cjs');
  const ready = join(f.directory, 'output-ready'), done = join(f.directory, 'caller-done');
  const source = locateEvidence + `
    ${cancellation ? "process.on('SIGTERM', () => process.exit(7)); setInterval(() => {}, 1000);" : ''}
    process.stdout.write('o'.repeat(${outputBytes}), () => {
      process.stderr.write('e'.repeat(${outputBytes}), () => {
        ${failEvidence ? "const target = path.join(attempt, 'output.log'); fs.renameSync(target, target + '.saved'); fs.writeFileSync(target, 'replacement bytes');" : ''}
        fs.writeFileSync(${JSON.stringify(ready)}, 'ready'); process.exitCode = ${exitCode};
      });
    });`;
  writeFileSync(caller, `import {runLocalCheck} from ${JSON.stringify(guard)};
    import {existsSync, writeFileSync} from 'node:fs';
    const abort = new AbortController();
    ${cancellation === 'caller' ? `const poll = setInterval(() => {
      if (existsSync(${JSON.stringify(ready)})) { clearInterval(poll); abort.abort(); }
    }, 20);` : ''}
    const config = ${JSON.stringify({root: f.root, heavy: true,
      timeoutSeconds: cancellation === 'timeout' ? 0.5 : 10, graceSeconds: 0.2,
      steps: steps(source)})};
    config.steps[0].name = 'd'.repeat(200000);
    process.exitCode = await runLocalCheck(config, {signal: abort.signal});
    writeFileSync(${JSON.stringify(done)}, String(process.exitCode));`);
  writeFileSync(receiver, `const fs = require('fs'), assert = require('assert');
    const [file, mode, ready, done] = process.argv.slice(2);
    assert(fs.fstatSync(0).isFIFO(), 'receiver must be a real pipe');
    fs.writeFileSync(file, '');
    if (mode === 'closed') process.exit(0);
    const bound = setTimeout(() => process.exit(90), 12000);
    const poll = setInterval(() => {
      if (mode === 'stall') {
        if (fs.existsSync(done)) process.exit(0);
      } else if (fs.existsSync(ready)) {
        clearInterval(poll);
        // Do not read until the command has produced all its output. Both
        // pipes fill before the old supervisor reaches its immediate exit.
        setTimeout(() => {
          const chunks = [];
          process.stdin.on('data', chunk => chunks.push(chunk));
          process.stdin.on('end', () => { fs.writeFileSync(file, Buffer.concat(chunks)); clearTimeout(bound); });
        }, 150);
      }
    }, 20);`);
  const out = join(f.directory, 'caller.stdout'), err = join(f.directory, 'caller.stderr');
  const env = {...f.env};
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
    env.NODE_OPTIONS = `--import=${preload}`;
  }
  const started = performance.now();
  const result = spawnSync('bash', ['-o', 'pipefail', '-c',
    '{ "$1" "$2" 2>&1 1>&3 | "$1" "$3" "$5" "$9" "$6" "$7"; } 3>&1 | "$1" "$3" "$4" "$8" "$6" "$7"',
    'pipe-fixture', process.execPath, caller, receiver, out, err, ready, done, stdout, stderr],
  {env, encoding: 'utf8', timeout: 15000});
  assert.equal(result.error, undefined, 'caller delivery must not need the external kill bound');
  assert.equal(result.signal, null);
  return {...result, elapsed: performance.now() - started,
    stdout: readFileSync(out), stderr: readFileSync(err, 'utf8')};
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
    assert.equal(record.status, cancellation === 'timeout' ? 'timeout' : 'interrupted');
    assert.equal(record.callerOutputComplete, false);
    assertFullCallerOutput(result.stdout);
    assert.deepEqual(locks(f), []);
  });
}

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
  const lock = acquireLocalLocks({root: f.root, heavy: true, directory});
  assert.throws(() => acquireLocalLocks({root: link, heavy: false, directory}), /lock busy/u);
  assert.match(lockOwnerStatus(lock.owner), /PID present/u);
  assert.ok(directory.path.startsWith(join(f.home, '.cache/actql/local-checks')));
  lock.release(); assert.deepEqual(locks(f), []);
});

test('unknown/stale/PID-reused owners and changed tokens are never reclaimed', t => {
  const f = fixture(t), directory = lockDirectory(f.home);
  const lock = acquireLocalLocks({root: f.root, heavy: true, directory});
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
  assert.throws(() => acquireLocalLocks({root: f.root, heavy: true, directory}), /lock busy/u);
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
    assert.deepEqual(locks(f), [record.locks[0].split('/').at(-1)]);
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

test('same-worktree race admits one command; a different heavy worktree is refused', async t => {
  const f = fixture(t), marker = join(f.root, 'started');
  const first = start(f, {steps: steps(`require('fs').writeFileSync(${JSON.stringify(marker)}, 'x'); setTimeout(()=>{}, 450)`)});
  await until(() => existsSync(marker));
  const same = start(f, {}, {TMPDIR: join(f.directory, 'different-temp')});
  const otherRoot = join(f.directory, 'other'); mkdirSync(otherRoot);
  const other = start(f, {root: otherRoot});
  for (const result of await Promise.all([same.done, other.done])) {
    assert.equal(result.code, 1);
    assert.match(result.stderr, /lock busy/u);
    assert.doesNotMatch(result.stdout, /fixture ran/u);
  }
  assert.equal((await first.done).code, 0);
  assert.deepEqual(locks(f), []);
});

test('focused work in another worktree does not take the heavy lock', async t => {
  const f = fixture(t), marker = join(f.root, 'started');
  const first = start(f, {steps: steps(`require('fs').writeFileSync(${JSON.stringify(marker)}, 'x'); setTimeout(()=>{}, 350)`)});
  await until(() => existsSync(marker));
  const otherRoot = join(f.directory, 'other'); mkdirSync(otherRoot);
  assert.equal((await start(f, {root: otherRoot, heavy: false}).done).code, 0);
  assert.equal((await first.done).code, 0);
});

test('timeout stops inherited descendants and leaves an unrelated process alive', async t => {
  const f = fixture(t), pids = join(f.root, 'pids');
  const unrelated = spawn(process.execPath, ['-e', 'setInterval(()=>{}, 1000)']);
  t.after(() => unrelated.kill());
  const source = `const {spawn}=require('child_process');
    const c=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});
    require('fs').writeFileSync(${JSON.stringify(pids)},JSON.stringify([process.pid,c.pid]));
    console.log('before timeout');setInterval(()=>{},1000);`;
  const result = await start(f, {timeoutSeconds: 0.25, steps: steps(source)}).done;
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
      assert.equal(locks(f).length, 2);
    } else {
      assert.equal(record.exitCode, exitCode || 1);
      assert.deepEqual(locks(f), []);
    }
  });
}

test('TERM-resistant descendants trigger owned-group KILL and retain locks', async t => {
  const f = fixture(t), pidFile = join(f.root, 'pid');
  const source = `process.on('SIGTERM',()=>{}); require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));console.log('resistant');setInterval(()=>{},1000);`;
  const result = await start(f, {timeoutSeconds: 0.2, graceSeconds: 0.1, steps: steps(source)}).done;
  assert.equal(result.code, 124, result.stderr);
  assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
  assert.equal(locks(f).length, 2);
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
      const descendant = `${resistant ? "process.on('SIGTERM',()=>{});" : ''}
        process.send('ready'); setTimeout(()=>{}, 3000);`;
      const source = `const {spawn} = require('child_process');
        const child = spawn(process.execPath, ['-e', ${JSON.stringify(descendant)}],
          {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
        child.once('message', () => {
          require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
          child.disconnect(); child.unref(); console.log('direct stdout'); console.error('direct stderr');
          process.exit(${exitCode});
        });`;
      const run = start(f, {timeoutSeconds: cancellation === 'timeout' ? 0.7 : 3,
        graceSeconds: 0.15, steps: steps(source)});
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
        assert.equal(pending.steps[0].streamsComplete, false);
        assert.equal(pending.steps[0].status, exitCode ? 'failed' : 'draining');
        assert.ok(pending.steps[0].exitedAt);
        assert.equal(locks(f).length, 2, 'direct exit alone must not release custody');
        if (cancellation === 'caller') run.child.kill('SIGINT');
      } finally { result = await run.done; }
      const expected = exitCode || (cancellation === 'timeout' ? 124 : 130);
      assert.equal(result.code, expected, result.stderr);
      const record = summary(attempts(f)[0]);
      assert.equal(record.complete, false);
      assert.equal(record.exitCode, expected);
      assert.equal(record.steps[0].code, exitCode);
      assert.equal(record.steps[0].streamsComplete, !resistant);
      assert.equal(Boolean(live(Number(readFileSync(pidFile)))), false);
      assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /direct stdout/u);
      assert.match(readFileSync(join(attempts(f)[0], 'output.log'), 'utf8'), /direct stderr/u);
      if (resistant) {
        assert.match(record.status, /SIGKILL escalation/u);
        assert.equal(record.outputComplete, false);
        assert.equal(record.locksReleased, false);
        assert.equal(locks(f).length, 2);
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
      const descendant = `${resistant ? "process.on('SIGTERM',()=>{});" : ''}
        process.send('ready'); setTimeout(()=>{}, 3000);`;
      const source = `process.on('SIGTERM', () => { console.log('TERM handler exits 7'); process.exit(7); });
        const child = require('child_process').spawn(process.execPath, ['-e', ${JSON.stringify(descendant)}],
          {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
        child.once('message', () => {
          require('fs').writeFileSync(${JSON.stringify(ready)}, JSON.stringify([process.pid, child.pid]));
        });`;
      const run = start(f, {timeoutSeconds: cancellation === 'timeout' ? 0.7 : 3,
        graceSeconds: 0.15, steps: steps(source)});
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
      assert.equal(record.steps[0].status, 'failed');
      assert.ok(record.steps[0].exitedAt);
      assert.equal(record.steps[0].streamsComplete, !resistant);
      assert.equal(record.complete, false);
      assert.equal(record.outputComplete, !resistant);
      assert.equal(record.locksReleased, !resistant);
      assert.equal(locks(f).length, resistant ? 2 : 0);
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
      ['-e', "process.send('ready'); setTimeout(()=>{},3000)"],
      {stdio: ['ignore', 'inherit', 'inherit', 'ipc']});
      child.once('message', () => {
        require('fs').writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
        child.disconnect(); child.unref(); console.log('before drain failure'); process.exit(${exitCode});
      });`;
    const result = await start(f, {timeoutSeconds: 0.7, steps: steps(source)},
      {NODE_OPTIONS: `--import=${preload}`}).done;
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
  assert.equal(locks(f).length, 2);
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
  assert.equal(locks(f).length, 2);
  assert.equal(summary(attempts(f)[0]).complete, false);
});
