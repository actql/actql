import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, writeFile, rm, open} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from './installed-project-connections.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME, 'Select the actual matching Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));

async function fixture(t, selected = true) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-connections-'));
  t.after(() => rm(directory, {recursive: true}));
  await writeFile(join(directory, 'actql.config.json'),
    selected ? '{"version":"actql-config/0.1","connectors":"./original/connections.json"}'
      : '{"version":"actql-config/0.1"}');
  await mkdir(join(directory, 'original'));
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  return {directory, project, path: join(directory, 'original/connections.json')};
}

test('actual Common project connections retain the same project and exact UTF8 entry bytes', async t => {
  const f = await fixture(t);
  const entry = '{ "connector" : "notion", "databases":{}, "credentials":{"integration_token":{"env":"N\\u004fTION"}} }';
  const wire = ' \n{"version":"actql-connectors/0.1","connections":{"café😀":' + entry + '}}\n';
  await writeFile(f.path, wire);
  let current = true, checks = 0;
  const view = await loadInstalledProjectConnections(moon, f.project,
    {assertCurrent() {checks++; assert.ok(current);}});
  const original = view.originalsForRuntime(moon);
  assert.strictEqual(original.project, f.project.originalsForRuntime(moon));
  assert.equal(original.path, f.path);
  assert.equal(original.wire, wire);
  assert.equal(moon.clientProjectConnectionsOriginalWire(original.connections), wire);
  assert.equal(moon.clientProjectConnectionsCount(original.connections), 1);
  assert.equal(moon.clientProjectConnectionsName(original.connections, 0), 'café😀');
  assert.equal(moon.clientProjectConnectionsConnector(original.connections, 0), 'notion');
  assert.equal(moon.clientProjectConnectionsEntryOriginalJson(original.connections, 0), entry);
  assert.equal(moon.clientProjectConnectionsEntryOriginalJson(original.connections, 1) == null, true);
  assert.strictEqual(view.originalsForRuntime(moon), original);
  assert.ok(Object.isFrozen(view) && Object.isFrozen(original));
  assert.ok(checks >= 4);
  assert.throws(() => view.originalsForRuntime({...moon}), {code: 'ForeignInstalledProjectRuntime'});
  for (const project of [{...f.project}, Object.create(f.project)]) {
    await assert.rejects(loadInstalledProjectConnections(moon, project,
      {assertCurrent() {assert.fail('No foreign project current check');}}),
    {code: 'ForeignInstalledProjectOriginal'});
  }
  current = false;
  assert.throws(() => view.originalsForRuntime(moon), assert.AssertionError);
});

test('actual Common project connections preserve absent versus explicit empty declarations', async t => {
  const absent = await fixture(t, false);
  const view = await loadInstalledProjectConnections(moon, absent.project, {
    assertCurrent() {}, openFile() {assert.fail('No absent file read');},
  });
  assert.equal(view.originalsForRuntime(moon).wire, undefined);
  assert.equal(view.originalsForRuntime(moon).connections, undefined);
  const empty = await fixture(t);
  const wire = '{"version":"actql-connectors/0.1","connections":{}}';
  await writeFile(empty.path, wire);
  const selected = await loadInstalledProjectConnections(moon, empty.project, {assertCurrent() {}});
  const original = selected.originalsForRuntime(moon);
  assert.equal(original.wire, wire);
  assert.equal(moon.clientProjectConnectionsCount(original.connections), 0);
});

test('actual Common refuses malformed or missing selected connections without a plain fallback', async t => {
  const f = await fixture(t);
  await assert.rejects(loadInstalledProjectConnections(moon, f.project,
    {assertCurrent() {}}), {code: 'ENOENT'});
  for (const wire of [Buffer.from([0xff]), '{"version":"actql-connectors/0.1","connections":{"n":{"connector":"notion"},"unused":null}}',
    '{"version":"actql-connectors/0.1","connections":{},"allow":true}']) {
    await writeFile(f.path, wire);
    await assert.rejects(loadInstalledProjectConnections(moon, f.project,
      {assertCurrent() {}}));
  }
});

test('actual project connection acquisition refuses currentness loss after its original read', async t => {
  const f = await fixture(t);
  await writeFile(f.path, '{"version":"actql-connectors/0.1","connections":{}}');
  let current = true, opens = 0, closes = 0;
  const failure = new Error('Original installation changed');
  await assert.rejects(loadInstalledProjectConnections(moon, f.project, {
    assertCurrent() {if (!current) throw failure;},
    async openFile(path, flags) {
      assert.equal(path, f.path); opens++;
      const handle = await open(path, flags);
      return {read: (...args) => handle.read(...args), async close() {
        closes++; await handle.close(); current = false;
      }};
    },
  }), error => error === failure);
  assert.equal(opens, 1); assert.equal(closes, 1);
});

test('actual project connection acquisition retains a pending original FD and retries only close', async t => {
  const f = await fixture(t);
  await writeFile(f.path, '{"version":"actql-connectors/0.1","connections":{}}');
  let opens = 0, closes = 0, handle, pending;
  t.after(async () => {
    if (pending?.status().pending) await pending.retry();
    else if (handle !== undefined && handle.fd !== -1) await handle.close();
  });
  await assert.rejects(loadInstalledProjectConnections(moon, f.project, {
    assertCurrent() {},
    async openFile(path, flags) {
      opens++; handle = await open(path, flags);
      return {read: (...args) => handle.read(...args), async close() {
        closes++;
        if (closes === 1) return false;
        await handle.close();
      }};
    },
  }), error => {
    assert.equal(error.message, 'InstalledSourceProfileCleanupPending');
    assert.equal(error.cleanupPending, true); pending = error.cleanupHandle;
    return true;
  });
  assert.equal(pending.status().pending, true);
  assert.equal(opens, 1); assert.equal(closes, 1);
  assert.equal((await pending.retry()).pending, false);
  assert.equal(opens, 1); assert.equal(closes, 2);
  await assert.rejects(handle.stat(), {code: 'EBADF'});
});
