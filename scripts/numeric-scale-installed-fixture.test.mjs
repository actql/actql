// Source-extracted launch wiring and an inert installed-package resolution
// fixture. Neither check opens a Host or claims numeric/Store acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdir, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const sourceUrl = new URL('../adapters/host-node/client-numeric-scale-public.test.mjs', import.meta.url);
test('numeric phases launch the same staged actor from the actual installed consumer', async () => {
  const source = await readFile(sourceUrl, 'utf8');
  const start = source.indexOf('function runPhase('), end = source.indexOf('\nfor (const', start);
  assert(start >= 0 && end > start);
  const prepared = {consumer: '/explicit/fresh-consumer', actor: '/explicit/fresh-consumer/numeric-scale-public-process.mjs'};
  const environment = {FIXTURE: 'retained', NODE_PATH: '/foreign', NODE_OPTIONS: '--import=/foreign'};
  const calls = [];
  const invoke = new Function('assert', 'spawnSync', 'process', 'prepared', 'root', 'join', 'fileURLToPath', 'moduleUrl',
    source.slice(start, end).replaceAll('import.meta.url', 'moduleUrl') + '\nreturn runPhase;')(
      assert, (command, args, options) => {
        calls.push({command, args, options});
        return {status: 0, signal: null, pid: 123,
          stdout: JSON.stringify({phase: args[1], rowsVerified: 1000, closeReturned: true, pid: 123}), stderr: ''};
      }, {execPath: process.execPath, env: environment}, prepared, '/source-checkout', join, fileURLToPath, sourceUrl.href);
  for (const phase of ['produce', 'restore']) invoke(phase, '/original-state', '/same-reference', 1000);
  for (const [index, call] of calls.entries()) {
    assert.equal(call.command, process.execPath);
    assert.deepEqual(call.args, [prepared.actor, index === 0 ? 'produce' : 'restore', '/original-state', '/same-reference', '1000']);
    assert.equal(call.options.cwd, prepared.consumer);
    assert.equal(call.options.timeout, 360000);
    assert.equal(call.options.maxBuffer, 8 * 1024 * 1024);
    assert.equal(call.options.env.FIXTURE, 'retained');
    assert.equal(call.options.env.NODE_PATH, undefined);
    assert.equal(call.options.env.NODE_OPTIONS, undefined);
  }
  assert.equal(environment.NODE_PATH, '/foreign', 'the parent environment is unchanged');
});

test('the byte-exact numeric actor resolves the installed Node package before any Host operation', async t => {
  const {stageNumericScaleActor} = await import('./numeric-scale-installed-fixture.mjs');
  const consumer = await mkdtemp(join(tmpdir(), 'actql-numeric-resolution-'));
  t.after(() => rm(consumer, {recursive: true, force: true}));
  const pkg = join(consumer, 'node_modules/@actql/node'); await mkdir(pkg, {recursive: true});
  await writeFile(join(pkg, 'package.json'), JSON.stringify({name: '@actql/node', type: 'module', exports: './index.mjs'}));
  await writeFile(join(pkg, 'index.mjs'), 'export function open(){throw new Error("InstalledNumericFixtureReachedBeforeHost");}\n');
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const actor = await stageNumericScaleActor({repository, consumer});
  assert.deepEqual(await readFile(actor), await readFile(new URL('../adapters/host-node/fixtures/numeric-scale-public-process.mjs', import.meta.url)));
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  const child = spawnSync(process.execPath, [actor, 'produce', join(consumer, 'unused-state'), join(consumer, 'unused-ref'), '1000'],
    {cwd: consumer, env, encoding: 'utf8', timeout: 10000});
  assert.ifError(child.error); assert.equal(child.signal, null); assert.equal(child.status, 1);
  assert.match(child.stderr, /InstalledNumericFixtureReachedBeforeHost/);
  assert.doesNotMatch(child.stderr, /ERR_MODULE_NOT_FOUND/);
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
