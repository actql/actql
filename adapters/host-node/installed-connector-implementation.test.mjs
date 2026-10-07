import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, rm, symlink, rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {captureInstalledConnectorImplementation} from './installed-connector-implementation.mjs';
import {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';

const hash = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-implementation-binding-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = 'adapters/connectors/local/iceberg/worker.py';
  const file = join(root, path);
  await mkdir(join(root, 'adapters/connectors/local/iceberg'), {recursive: true});
  await writeFile(file, 'original worker\n');
  const entry = {name: 'local', registration: 'local', revision: 'local/0.1',
    implementationFiles: [{path, href: pathToFileURL(file).href}]};
  return {root, path, file, entry};
}

test('implementation binding has an independent content preimage and survives identical reconstruction', async t => {
  const f = await fixture(t);
  const expected = hash(JSON.stringify({files: [{cid: hash('original worker\n'), path: f.path}],
    registration: 'local', revision: 'local/0.1', version: 'actql-installed-connector-implementation/0.1'}));
  const first = captureInstalledConnectorImplementation(f.entry);
  assert.equal(first.identity, expected);
  assert.equal(captureInstalledConnectorImplementation(f.entry).identity, expected);
  first.assertCurrent();
  // Mutating caller metadata cannot replace the captured inventory.
  f.entry.implementationFiles[0].href = pathToFileURL(join(f.root, 'foreign.py')).href;
  first.assertCurrent();
  await writeFile(f.file, 'changed worker\n');
  assert.throws(() => first.assertCurrent(), {code: 'InstalledConnectorImplementationChanged'});
});

test('implementation identity binds revision and contract bytes, not only a path', async t => {
  const f = await fixture(t);
  const original = captureInstalledConnectorImplementation(f.entry).identity;
  assert.notEqual(captureInstalledConnectorImplementation({...f.entry, revision: 'local/0.2'}).identity, original);
  const path = 'spec/contracts/actql-local-table-iceberg.json';
  await mkdir(join(f.root, 'spec/contracts'), {recursive: true});
  const file = join(f.root, path);
  await writeFile(file, '{"contract":"first"}');
  const selected = {...f.entry, implementationFiles: [...f.entry.implementationFiles,
    {path, href: pathToFileURL(file).href}]};
  const first = captureInstalledConnectorImplementation(selected);
  await writeFile(file, '{"contract":"second"}');
  assert.throws(() => first.assertCurrent(), {code: 'InstalledConnectorImplementationChanged'});
  assert.notEqual(captureInstalledConnectorImplementation(selected).identity, first.identity);
  assert.equal(captureInstalledConnectorImplementation({...selected,
    implementationFiles: [...selected.implementationFiles].reverse()}).identity,
  captureInstalledConnectorImplementation(selected).identity);
});

test('implementation inventory refuses duplicate, foreign, linked and oversized files', async t => {
  const f = await fixture(t), declared = f.entry.implementationFiles[0];
  for (const files of [[], [declared, declared], [{...declared, path: '../worker.py'}],
    [{...declared, path: 'adapters/connectors/other/worker.py'}],
    [{...declared, href: 'https://example.invalid/worker.py'}]]) {
    assert.throws(() => captureInstalledConnectorImplementation({...f.entry,
      implementationFiles: files}), {code: 'InvalidConnectorImplementationInventory'});
  }
  await rm(f.file);
  const outside = join(f.root, 'outside.py');
  await writeFile(outside, 'do not read');
  await symlink(outside, f.file);
  assert.throws(() => captureInstalledConnectorImplementation(f.entry));
  await rm(f.file);
  await mkdir(f.file);
  assert.throws(() => captureInstalledConnectorImplementation(f.entry),
    {code: 'InvalidConnectorImplementationFile'});
  await rm(f.file, {recursive: true});
  await writeFile(f.file, Buffer.alloc(16 * 1024 * 1024 + 1));
  assert.throws(() => captureInstalledConnectorImplementation(f.entry), {code: 'ConnectorImplementationByteLimit'});
});

test('changed installed implementation cannot prepare, dispatch or reconcile with a different worker', async t => {
  const f = await fixture(t);
  const implementation = captureInstalledConnectorImplementation(f.entry);
  const bridge = createIcebergPhysicalBridge({implementation, run: 'binding-check',
    python: pathToFileURL(join(f.root, 'uninstalled-python')),
    catalog: {database: join(f.root, 'absent.db'), warehouse: join(f.root, 'absent-warehouse'),
      catalogCid: hash('catalog'), limits: {bytes: 1048576, files: 16, operations: 16}}});
  const schemaWire = '{}';
  const operation = {request_cid: hash('request'), schema_cid: hash(schemaWire)};
  const material = {operation, mapping: {}, rows: [], reservation: {bytes: 1, files: 1}, schemaWire};
  const prepared = bridge.prepareWrite(material);
  await writeFile(f.file, 'changed worker\n');
  assert.throws(() => bridge.prepareWrite(material), {code: 'InstalledConnectorImplementationChanged'});
  await assert.rejects(bridge.execute(prepared, {useCid: hash('use')}),
    {code: 'InstalledConnectorImplementationChanged'});
  await assert.rejects(bridge.reconcileOperation(operation), {code: 'InstalledConnectorImplementationChanged'});
  assert.deepEqual(bridge.status(prepared), {attempted: false, stopped: false});
  const {access} = await import('node:fs/promises');
  await assert.rejects(access(join(f.root, 'absent.db')), {code: 'ENOENT'});
  await assert.rejects(access(join(f.root, 'absent-warehouse')), {code: 'ENOENT'});
});

test('implementation observation refuses a linked parent even within the same package', async t => {
  const f = await fixture(t);
  const original = join(f.root, 'adapters/connectors/local/iceberg');
  const relocated = join(f.root, 'adapters/connectors/local/relocated');
  await rename(original, relocated);
  await symlink(relocated, original, 'dir');
  assert.throws(() => captureInstalledConnectorImplementation(f.entry),
    {code: 'InvalidConnectorImplementationFile'});
});
