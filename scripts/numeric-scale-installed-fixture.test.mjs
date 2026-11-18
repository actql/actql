// Exercise the actual actor launcher and installed-package resolution.
// These controls do not open a Host or claim numeric/Store acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdir, mkdtemp, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

import {runNumericScalePhase} from './numeric-scale-installed-fixture.mjs';

test('numeric phases launch the staged actor from its installed consumer without ambient module overrides', async t => {
  const consumer = await realpath(await mkdtemp(join(tmpdir(), 'actql-numeric-launch-')));
  t.after(() => rm(consumer, {recursive: true, force: true}));
  const actor = join(consumer, 'actor.mjs');
  await writeFile(actor, `import {writeFileSync} from 'node:fs';
const [phase, directory, referencePath, count] = process.argv.slice(2);
writeFileSync(referencePath + '.' + phase, JSON.stringify({
  actor: process.argv[1], phase, directory, referencePath, count, cwd: process.cwd(),
  nodePath: process.env.NODE_PATH ?? null, nodeOptions: process.env.NODE_OPTIONS ?? null,
  pid: process.pid,
}));
console.log(JSON.stringify({phase, rowsVerified: Number(count) + (phase === 'wrong-result' ? 1 : 0),
  closeReturned: true, pid: process.pid}));
`);
  const oldPath = process.env.NODE_PATH, oldOptions = process.env.NODE_OPTIONS;
  try {
    process.env.NODE_PATH = '/foreign'; process.env.NODE_OPTIONS = '--import=/foreign';
    const prepared = {consumer, actor}, referencePath = join(consumer, 'original-reference');
    const pids = [];
    for (const phase of ['produce', 'restore']) {
      runNumericScalePhase(prepared, phase, consumer, referencePath, 1000);
      const actual = JSON.parse(await readFile(referencePath + '.' + phase, 'utf8'));
      pids.push(actual.pid);
      assert.deepEqual({...actual, pid: undefined}, {
        actor, phase, directory: consumer, referencePath, count: '1000', cwd: consumer,
        nodePath: null, nodeOptions: null, pid: undefined,
      });
    }
    assert.notEqual(pids[0], pids[1]);
    assert.throws(() => runNumericScalePhase(prepared, 'wrong-result', consumer, referencePath, 1000));
    assert.equal(process.env.NODE_PATH, '/foreign');
    assert.equal(process.env.NODE_OPTIONS, '--import=/foreign');
  } finally {
    if (oldPath === undefined) delete process.env.NODE_PATH; else process.env.NODE_PATH = oldPath;
    if (oldOptions === undefined) delete process.env.NODE_OPTIONS; else process.env.NODE_OPTIONS = oldOptions;
  }
});

test('the byte-exact numeric actor resolves the installed Node package before any Host operation', async t => {
  const {stageNumericScaleActor} = await import('./numeric-scale-installed-fixture.mjs');
  const consumer = await mkdtemp(join(tmpdir(), 'actql-numeric-resolution-'));
  t.after(() => rm(consumer, {recursive: true, force: true}));
  const pkg = join(consumer, 'node_modules/@actql/node'); await mkdir(pkg, {recursive: true});
  await writeFile(join(pkg, 'package.json'), JSON.stringify({name: '@actql/node', type: 'module', exports: './index.mjs'}));
  await writeFile(join(pkg, 'index.mjs'), `import {writeFileSync} from 'node:fs';
export function open(options) {
  writeFileSync(process.env.ACTQL_NUMERIC_TEST_OPEN, JSON.stringify(options));
  throw new Error('InstalledNumericFixtureReachedBeforeHost');
}
`);
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const actor = await stageNumericScaleActor({repository, consumer});
  assert.deepEqual(await readFile(actor), await readFile(new URL('../adapters/host-node/fixtures/numeric-scale-public-process.mjs', import.meta.url)));
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  const stateDir = join(consumer, 'unused-state');
  for (const {phase, count} of [
    ...[1000, 10000, 10001].map(count => ({phase: 'produce', count})),
    ...['produce', 'produce-source', 'restore'].map(phase => ({phase, count: 100000})),
  ]) {
    const observed = join(consumer, `open-${phase}-${count}.json`);
    const child = spawnSync(process.execPath, [actor, phase, stateDir, join(consumer, 'unused-ref'), String(count)],
      {cwd: consumer, env: {...env, ACTQL_NUMERIC_TEST_OPEN: observed}, encoding: 'utf8', timeout: 10000});
    assert.ifError(child.error); assert.equal(child.signal, null); assert.equal(child.status, 1);
    assert.match(child.stderr, /InstalledNumericFixtureReachedBeforeHost/);
    assert.doesNotMatch(child.stderr, /ERR_MODULE_NOT_FOUND/);
    assert.deepEqual(JSON.parse(await readFile(observed, 'utf8')), count === 100000 ? {
      stateDir,
      installation: {requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824},
        sourceFreeMaxWork: 30000000},
    } : {stateDir});
  }
});


test('numeric preparation refuses absent normal artifacts before Source or consumer I/O', async () => {
  const {prepareNumericScaleConsumer} = await import('./numeric-scale-installed-fixture.mjs');
  const original = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  try {
    delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    await assert.rejects(prepareNumericScaleConsumer({repository: '/must-not-read-source',
      directory: '/must-not-create-consumer', command() {assert.fail('No pack or install fallback');}}),
      {message: 'NumericScaleRequiresMatchingNormalClientPackages'});
  } finally {
    if (original === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = original;
  }
});
