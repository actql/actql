// These small acceptance guards share the existing packed-query CI test entry.
import './readme-quickstart.test.mjs';
import './packed-package-boundaries.test.mjs';
import './public-query-cases.test.mjs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const scratch = new URL('../_build/packed-query-evidence-tests/', import.meta.url);
mkdirSync(scratch, {recursive: true});
// Output/exit assertions must not depend on Node starting within 500 ms.
// This is a test watchdog, not a change to the evidence runner's timeout.
const normalExitWatchdog = 30_000;
const timeoutDeadline = 25;
// No output is produced, whether the timeout arrives before or after startup.
const silentUntilKilled = 'setInterval(() => {}, 1000)';

for (const scenario of ['success', 'slow-success', 'nonzero', 'keep']) {
  test(`packed query evidence preserves ${scenario} before cleanup`, async t => {
    const root = mkdtempSync(new URL('case-', scratch));
    t.after(() => rmSync(root, {recursive: true}));
    const sibling = join(root, 'another-owner');
    mkdirSync(sibling);
    writeFileSync(join(sibling, 'keep'), 'untouched');
    let directory;
    const githubOutput = join(root, 'step-output');
    const action = withPackedQueryEvidence({scratch: root, revision: 'fixed-sha',
      githubOutput,
      keepArtifacts: scenario === 'keep'}, async evidence => {
      directory = evidence.directory;
      const tarball = join(evidence.root, 'fixture.tgz');
      writeFileSync(tarball, 'abc');
      evidence.recordTarball(tarball);
      evidence.run(process.execPath, ['-e',
        (scenario === 'slow-success'
          ? 'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 750);'
          : '') +
        "process.stdout.write('out'); process.stderr.write('err');" +
        (scenario === 'nonzero' ? 'process.exit(7)' : '')],
      {timeout: normalExitWatchdog});
    });
    if (scenario === 'nonzero') {
      await assert.rejects(action, {code: 'PackedQueryCommandFailed'});
    } else await action;
    assert.equal(readFileSync(githubOutput, 'utf8'),
      `evidence-directory=${directory}\n`);
    const summary = JSON.parse(readFileSync(join(directory, 'summary.json')));
    assert.equal(summary.revision, 'fixed-sha');
    assert.equal(summary.status, scenario === 'nonzero'
      ? 'failed' : 'passed');
    assert.equal(summary.tarballs[0].sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    assert.equal(readFileSync(join(directory, '001.stdout.log'), 'utf8'), 'out');
    assert.equal(readFileSync(join(directory, '001.stderr.log'), 'utf8'), 'err');
    const result = summary.commands[0];
    assert.ok(result.elapsedMs > 0);
    assert.equal(result.error, null);
    assert.equal(result.signal, null);
    assert.equal(result.status, scenario === 'nonzero' ? 7 : 0);
    assert.equal(existsSync(join(directory, 'artifacts')), scenario === 'keep');
    assert.equal(summary.artifactsRemoved, scenario !== 'keep');
    assert.equal(readFileSync(join(sibling, 'keep'), 'utf8'), 'untouched');
    assert.ok(readdirSync(directory).includes('summary.json'));
  });
}

test('timeout without output persists empty streams and reclaims artifacts',
async t => {
  const root = mkdtempSync(new URL('timeout-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const githubOutput = join(root, 'step-output');
  await assert.rejects(withPackedQueryEvidence({scratch: root,
    revision: 'fixed-sha', githubOutput}, ({run}) => {
    run(process.execPath, ['-e', silentUntilKilled], {timeout: timeoutDeadline});
  }), {code: 'PackedQueryCommandFailed'});
  const directory = readFileSync(githubOutput, 'utf8')
    .trim().slice('evidence-directory='.length);
  const summary = JSON.parse(readFileSync(join(directory, 'summary.json')));
  assert.equal(summary.status, 'failed');
  assert.equal(summary.revision, 'fixed-sha');
  assert.equal(summary.commands.length, 1);
  const result = summary.commands[0];
  assert.equal(result.error.code, 'ETIMEDOUT');
  assert.equal(result.signal, 'SIGKILL');
  assert.equal(result.status, null);
  assert.ok(result.elapsedMs > 0);
  assert.equal(readFileSync(join(directory, '001.stdout.log'), 'utf8'), '');
  assert.equal(readFileSync(join(directory, '001.stderr.log'), 'utf8'), '');
  assert.equal(summary.artifactsRemoved, true);
  assert.equal(existsSync(join(directory, 'artifacts')), false);
});

for (const scenario of ['nonzero', 'timeout']) {
test(`recorded ${scenario} remains a failing process exit`, () => {
  const root = mkdtempSync(new URL('exit-', scratch));
  try {
    const githubOutput = join(root, 'step-output');
    const result = spawnSync(process.execPath, ['--input-type=module', '-e',
      `import {withPackedQueryEvidence} from ${JSON.stringify(
        new URL('./packed-query-evidence.mjs', import.meta.url).href)};
       await withPackedQueryEvidence({scratch: ${JSON.stringify(root)},
         githubOutput: ${JSON.stringify(githubOutput)},
         revision: 'fixed'}, ({run}) => run(process.execPath,
           ['-e', ${JSON.stringify(scenario === 'timeout'
             ? silentUntilKilled : 'process.exit(9)')}],
           {timeout: ${scenario === 'timeout'
             ? timeoutDeadline : normalExitWatchdog}}));`],
      {encoding: 'utf8', timeout: normalExitWatchdog * 2});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.notEqual(result.status, null);
    assert.notEqual(result.status, 0);
    const evidence = readFileSync(githubOutput, 'utf8')
      .trim().slice('evidence-directory='.length);
    assert.equal(readFileSync(join(evidence, '001.stdout.log'), 'utf8'), '');
    assert.equal(readFileSync(join(evidence, '001.stderr.log'), 'utf8'), '');
    const observation = JSON.parse(readFileSync(join(evidence, 'summary.json')))
      .commands[0];
    if (scenario === 'timeout') {
      assert.equal(observation.error.code, 'ETIMEDOUT');
      assert.equal(observation.signal, 'SIGKILL');
      assert.equal(observation.status, null);
    } else {
      assert.equal(observation.error, null);
      assert.equal(observation.signal, null);
      assert.equal(observation.status, 9);
    }
    assert.equal(existsSync(join(evidence, 'artifacts')), false);
  } finally { rmSync(root, {recursive: true}); }
});
}

// Deterministic failure evidence, separate from packed product acceptance.
import {renameSync, symlinkSync} from 'node:fs';
import {createCommandEvidence, COMMAND_OUTPUT_LIMIT} from './packed-query-evidence.mjs';

for (const [scenario, script, options, expected] of [
  ['nonzero', "console.log('partial'); process.exit(7)", {}, {status: 7, signal: null}],
  ['signal', "console.error('before signal'); process.kill(process.pid, 'SIGTERM')", {}, {status: null, signal: 'SIGTERM'}],
  ['timeout', silentUntilKilled, {timeout: timeoutDeadline, killSignal: 'SIGKILL'}, {status: null, signal: 'SIGKILL'}],
]) {
  test(`command attempt retains exact ${scenario} identity and incomplete invocation`, t => {
    const root = mkdtempSync(new URL('attempt-', scratch));
    t.after(() => rmSync(root, {recursive: true}));
    const recorder = createCommandEvidence({scratch: root, revision: 'declared-source',
      env: {...process.env, GITHUB_RUN_ID: '42', GITHUB_RUN_ATTEMPT: '3', GITHUB_SHA: 'a'.repeat(40), GITHUB_JOB: 'probe'}});
    const {result} = recorder.capture(process.execPath, ['-e', script], {timeout: normalExitWatchdog, ...options});
    recorder.finish('failed');
    const summary = JSON.parse(readFileSync(join(recorder.directory, 'summary.json')));
    const outcome = JSON.parse(readFileSync(join(recorder.directory, '001.result.json')));
    assert.equal(summary.complete, false);
    assert.equal(summary.status, 'failed');
    assert.deepEqual(summary.github, {runId: '42', runAttempt: '3', eventSha: 'a'.repeat(40), job: 'probe'});
    assert.equal(outcome.status, expected.status);
    assert.equal(outcome.signal, expected.signal);
    assert.equal(outcome.status, result.status);
    assert.equal(outcome.command, process.execPath);
    assert.deepEqual(outcome.args, ['-e', script]);
    assert.equal(outcome.cwd.path, process.cwd());
    assert.equal(typeof outcome.cwd.inode, 'string');
    assert.ok(Date.parse(outcome.endedAt) >= Date.parse(outcome.startedAt));
    assert.equal(typeof outcome.source.dirty, 'boolean');
    assert.match(outcome.source.revision, /^[a-f0-9]{40}$/u);
    const started = JSON.parse(readFileSync(join(recorder.directory, '001.started.json')));
    assert.equal(started.complete, false);
    assert.equal(started.endedAt, null);
    assert.equal(started.status, null);
    assert.equal(started.outputComplete, false);
    if (scenario === 'timeout') assert.equal(outcome.error.code, 'ETIMEDOUT');
  });
}

test('write failure cannot replace primary command failure; old snapshots survive', t => {
  const root = mkdtempSync(new URL('write-failure-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const recorder = createCommandEvidence({scratch: root});
  const target = join(root, 'unrelated');
  writeFileSync(target, 'untouched');
  renameSync(join(recorder.directory, 'summary.json'), join(recorder.directory, 'original-summary.json'));
  symlinkSync(target, join(recorder.directory, 'summary.json'));
  const {result, outcome, writeFailure} = recorder.capture(process.execPath, ['-e', 'process.exit(9)']);
  assert.equal(result.status, 9);
  assert.equal(outcome.verificationStatus, 9);
  assert.ok(writeFailure);
  assert.equal(readFileSync(target, 'utf8'), 'untouched');
  assert.equal(JSON.parse(readFileSync(join(recorder.directory, '001.result.json'))).status, 9);
  assert.ok(readdirSync(recorder.directory).some(name => name.endsWith('.summary.json')));
  assert.throws(() => recorder.finish('failed'), /OwnershipChanged/u);
});

test('replaced artifact root is never cleaned or followed', async t => {
  const root = mkdtempSync(new URL('replacement-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const target = join(root, 'unrelated');
  mkdirSync(target);
  writeFileSync(join(target, 'keep'), 'untouched');
  let directory;
  await assert.rejects(withPackedQueryEvidence({scratch: root}, evidence => {
    directory = evidence.directory;
    renameSync(evidence.root, join(evidence.directory, 'original-artifacts'));
    symlinkSync(target, evidence.root);
  }), /ArtifactDirectoryOwnershipChanged/u);
  assert.equal(readFileSync(join(target, 'keep'), 'utf8'), 'untouched');
  const summary = JSON.parse(readFileSync(join(directory, 'summary.json')));
  assert.equal(summary.status, 'failed');
  assert.equal(summary.complete, false);
  assert.equal(summary.artifactsRemoved, false);
  assert.equal(summary.evidenceErrors[0].stage, 'cleanup');
});

test('owned output is bounded and authorization arguments and streams are masked', t => {
  const root = mkdtempSync(new URL('redaction-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const env = {...process.env, EXAMPLE_TOKEN: 'fixture-secret-value'};
  const recorder = createCommandEvidence({scratch: root, env});
  recorder.capture(process.execPath, ['-e',
    "console.log(process.env.EXAMPLE_TOKEN); console.log('Bearer fixture-auth'); console.error('https://user:pass@example.invalid/?token=fixture-query');",
    '--', '--token', 'fixture-argv'], {env});
  const summary = readFileSync(join(recorder.directory, 'summary.json'), 'utf8');
  const logs = ['stdout', 'stderr'].map(stream => readFileSync(join(recorder.directory, `001.${stream}.log`), 'utf8')).join('');
  for (const secret of ['fixture-secret-value', 'fixture-auth', 'fixture-query', 'fixture-argv', 'user:pass']) {
    assert.ok(!(summary + logs).includes(secret), secret);
  }
  assert.ok(!summary.includes('"env"'), 'environment is not serialized');
  const capture = recorder.capture(process.execPath, ['-e', "process.stdout.write('x'.repeat(9 * 1024 * 1024))"]);
  assert.equal(capture.result.error.code, 'ENOBUFS');
  assert.equal(capture.outcome.outputComplete, false);
  assert.ok(readFileSync(join(recorder.directory, '002.stdout.log')).length <= COMMAND_OUTPUT_LIMIT);
});

import {checkCommandEvidenceUpload} from './packed-query-evidence.mjs';
import {parse as parseYaml} from 'yaml';

test('uploader selects partial start snapshots, refuses missing evidence and unsafe files', t => {
  const root = mkdtempSync(new URL('upload-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const recorder = createCommandEvidence({scratch: root});
  const selected = checkCommandEvidenceUpload(recorder.directory);
  assert.ok(selected.includes('summary.json'));
  assert.ok(selected.includes('0001.summary.json'));
  assert.ok(!selected.includes('001.result.json'), 'missing result remains missing');
  assert.throws(() => checkCommandEvidenceUpload(join(root, 'missing')), {code: 'ENOENT'});
  writeFileSync(join(recorder.directory, 'foreign.stdout.log'), 'private payload');
  assert.throws(() => checkCommandEvidenceUpload(recorder.directory), /UnexpectedEvidenceUploadFile/u);
  rmSync(join(recorder.directory, 'foreign.stdout.log'));
  symlinkSync(join(recorder.directory, 'summary.json'), join(recorder.directory, '001.stdout.log'));
  assert.throws(() => checkCommandEvidenceUpload(recorder.directory), /UnsafeEvidenceUploadFile/u);
});

test('existing failure probe collects after failure and separately tests upload failure', () => {
  const action = parseYaml(readFileSync(new URL('../.github/actions/upload-packed-query-evidence/action.yml', import.meta.url), 'utf8'));
  const probe = parseYaml(readFileSync(new URL('../.github/workflows/packed-query-evidence-probe.yml', import.meta.url), 'utf8'));
  const job = probe.jobs['failure-probe'];
  assert.deepEqual(job.strategy.matrix.fault, ['nonzero', 'timeout', 'interrupted', 'upload']);
  assert.equal(job['timeout-minutes'], 3, 'existing watchdog is unchanged');
  const collect = job.steps.find(step => step.id === 'collection');
  assert.match(collect.if, /^always\(\)/u);
  assert.equal(collect['continue-on-error'], undefined);
  assert.equal(job.steps.find(step => step.id === 'probe')['continue-on-error'], undefined);
  const upload = action.runs.steps.find(step => step.id === 'upload');
  assert.equal(upload.with['if-no-files-found'], 'error');
  assert.equal(upload.with['retention-days'], 7);
  assert.match(upload.with.name, /github.run_id.*github.run_attempt/u);
  assert.match(upload.with.path, /\*\.started\.json/u);
  assert.match(upload.with.path, /\*\.result\.json/u);
  assert.ok(!upload.with.path.includes('artifacts'));
  const report = action.runs.steps.at(-1);
  assert.equal(report.if, 'always()');
  // Execute the action's exact report shell, not a separately reimplemented model.
  for (const [outcome, exit] of [['success', 0], ['failure', 1], ['skipped', 1]]) {
    const result = spawnSync('bash', ['-c', report.run], {encoding: 'utf8',
      env: {...process.env, UPLOAD_OUTCOME: outcome}});
    assert.equal(result.status, exit);
    assert.match(result.stdout, outcome === 'success' ? /does not establish verification success/u : /verification result is unchanged/u);
  }
});

test('abrupt parent termination leaves only honest start evidence for collection', t => {
  const root = mkdtempSync(new URL('interrupted-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const githubOutput = join(root, 'step-output');
  const child = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {withPackedQueryEvidence} from ${JSON.stringify(new URL('./packed-query-evidence.mjs', import.meta.url).href)};
     await withPackedQueryEvidence({scratch: ${JSON.stringify(root)}, githubOutput: ${JSON.stringify(githubOutput)}},
       ({run}) => run(process.execPath, ['-e', "process.kill(process.ppid, 'SIGKILL')"]));`],
    {encoding: 'utf8', timeout: normalExitWatchdog});
  assert.equal(child.signal, 'SIGKILL');
  const directory = readFileSync(githubOutput, 'utf8').trim().slice('evidence-directory='.length);
  const summary = JSON.parse(readFileSync(join(directory, 'summary.json')));
  assert.equal(summary.complete, false);
  assert.equal(summary.status, 'running');
  assert.equal(summary.commands[0].status, null);
  assert.equal(existsSync(join(directory, '001.result.json')), false);
  assert.equal(existsSync(join(directory, '001.stdout.log')), false);
  assert.ok(checkCommandEvidenceUpload(directory).includes('001.started.json'));
});


test('child cwd outside Git retains the recorder repository source identity', t => {
  const root = mkdtempSync(new URL('child-source-', scratch));
  t.after(() => rmSync(root, {recursive: true}));
  const recorder = createCommandEvidence({scratch: root, cwd: process.cwd()});
  // An isolated consumer cwd can have a different directory identity from the
  // repository whose helper and package source are being verified.
  const {outcome} = recorder.capture(process.execPath, ['-e', ''], {cwd: root});
  assert.equal(outcome.cwd.path, root);
  assert.deepEqual(outcome.source, recorder.summary.source);
  assert.match(outcome.source.revision, /^[a-f0-9]{40}$/u);
});
