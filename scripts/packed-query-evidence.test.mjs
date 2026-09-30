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
