import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const scratch = new URL('../_build/packed-query-evidence-tests/', import.meta.url);
mkdirSync(scratch, {recursive: true});
for (const scenario of ['success', 'nonzero', 'timeout', 'keep']) {
  test(`packed query evidence preserves ${scenario} before cleanup`, async t => {
    const root = mkdtempSync(new URL('case-', scratch));
    t.after(() => rmSync(root, {recursive: true}));
    const sibling = join(root, 'another-owner');
    mkdirSync(sibling);
    writeFileSync(join(sibling, 'keep'), 'untouched');
    let directory;
    const action = withPackedQueryEvidence({scratch: root, revision: 'fixed-sha',
      keepArtifacts: scenario === 'keep'}, async evidence => {
      directory = evidence.directory;
      const tarball = join(evidence.root, 'fixture.tgz');
      writeFileSync(tarball, 'abc');
      evidence.recordTarball(tarball);
      evidence.run(process.execPath, ['-e',
        "process.stdout.write('out'); process.stderr.write('err');" +
        (scenario === 'nonzero' ? 'process.exit(7)' : scenario === 'timeout'
          ? 'setInterval(() => {}, 1000)' : '')], {timeout: 500});
    });
    if (['nonzero', 'timeout'].includes(scenario)) {
      await assert.rejects(action, {code: 'PackedQueryCommandFailed'});
    } else await action;
    const summary = JSON.parse(readFileSync(join(directory, 'summary.json')));
    assert.equal(summary.revision, 'fixed-sha');
    assert.equal(summary.status, ['nonzero', 'timeout'].includes(scenario)
      ? 'failed' : 'passed');
    assert.equal(summary.tarballs[0].sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    assert.equal(readFileSync(join(directory, '001.stdout.log'), 'utf8'), 'out');
    assert.equal(readFileSync(join(directory, '001.stderr.log'), 'utf8'), 'err');
    const result = summary.commands[0];
    assert.ok(result.elapsedMs > 0);
    if (scenario === 'timeout') {
      assert.equal(result.error.code, 'ETIMEDOUT');
      assert.equal(result.signal, 'SIGKILL');
      assert.equal(result.status, null);
    } else assert.equal(result.status, scenario === 'nonzero' ? 7 : 0);
    assert.equal(existsSync(join(directory, 'artifacts')), scenario === 'keep');
    assert.equal(summary.artifactsRemoved, scenario !== 'keep');
    assert.equal(readFileSync(join(sibling, 'keep'), 'utf8'), 'untouched');
    assert.ok(readdirSync(directory).includes('summary.json'));
  });
}

for (const scenario of ['nonzero', 'timeout']) {
test(`recorded ${scenario} remains a failing process exit`, () => {
  const root = mkdtempSync(new URL('exit-', scratch));
  try {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e',
      `import {withPackedQueryEvidence} from ${JSON.stringify(
        new URL('./packed-query-evidence.mjs', import.meta.url).href)};
       await withPackedQueryEvidence({scratch: ${JSON.stringify(root)},
         revision: 'fixed'}, ({run}) => run(process.execPath,
           ['-e', ${JSON.stringify(scenario === 'timeout'
             ? 'setInterval(() => {}, 1000)' : 'process.exit(9)')}],
           {timeout: 500}));`], {encoding: 'utf8'});
    assert.notEqual(result.status, 0);
    const evidence = join(root, readdirSync(root)[0]);
    const observation = JSON.parse(readFileSync(join(evidence, 'summary.json')))
      .commands[0];
    if (scenario === 'timeout') assert.equal(observation.error.code, 'ETIMEDOUT');
    else assert.equal(observation.status, 9);
    assert.equal(existsSync(join(evidence, 'artifacts')), false);
  } finally { rmSync(root, {recursive: true}); }
});
}
