import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, open, readdir, rm} from 'node:fs/promises';
import fsPromises from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join, sep} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const control = createPublicationContractControlFixture();
const cid = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const contract = control.seal('run_invocation', JSON.stringify({
  version: 'actql-run-invocation/0.1', invocation_template_cid: cid('template'),
  observation_set_cid: cid('observations'),
}), limits);
const configuration = directory => ({directory, storeAuthorityCid: cid('authority'),
  capacityBytes: 1048576, maxObjectBytes: 65536, maxObjects: 100,
  maxContractNodes: 4096, maxContractDepth: 64});
async function actualSync(path) {
  const handle = await open(path, 'r');
  try { await handle.sync(); } finally { await handle.close(); }
}

test('semantic metadata commits its payload and final names without intermediate custody persistence', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-commit-'));
  let store;
  t.after(async () => { await store?.close(); await rm(directory, {recursive: true}); });
  const synced = [];
  store = await openLocalPublicationStore(configuration(directory), control, {
    async syncDirectory(path) { synced.push(path); await actualSync(path); },
  });
  const originalOpen = fsPromises.open;
  let fileSyncs = 0, fileCloses = 0;
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (String(path).startsWith(join(directory, 'staging') + sep)) {
      const sync = handle.sync, close = handle.close;
      handle.sync = function() { fileSyncs++; return Reflect.apply(sync, this, []); };
      handle.close = function() { fileCloses++; return Reflect.apply(close, this, []); };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    synced.length = 0;
    const stored = await store.putPublicationContract(contract.name, contract.wire);
    assert.equal(stored.semanticCid, contract.identity);
    assert.equal(fileSyncs, 1, 'only the original immutable payload is file-synced');
    assert.equal(fileCloses, 1, 'its same native FD closes before publication');
    assert.deepEqual(synced.map(path => path.slice(directory.length + 1)),
      ['objects', 'contracts']);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
    assert.equal(store.status().objectCount, 1);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal((await store.readPublicationContract(contract.identity, contract.name)).wire,
      contract.wire);
  } finally {
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('semantic metadata retains the same failed native close before publication or capacity retirement', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-close-'));
  let store, retained, originalFailure, refuse = true;
  t.after(async () => {
    refuse = false;
    await originalFailure?.cleanupHandle.retry();
    await store?.close();
    await rm(directory, {recursive: true});
  });
  store = await openLocalPublicationStore(configuration(directory), control);
  const originalOpen = fsPromises.open;
  let acquisitions = 0;
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (String(path).startsWith(join(directory, 'staging') + sep)) {
      acquisitions++;
      retained = handle;
      const close = handle.close;
      handle.close = function() { return refuse ? Promise.resolve(false) : Reflect.apply(close, this, []); };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(store.putPublicationContract(contract.name, contract.wire), error => {
      originalFailure = error;
      return error.cleanupPending === true && error.cleanupHandle.status().pending === true;
    });
    assert.ok(retained.fd >= 0);
    assert.equal(store.status().reservedObjects, 1);
    assert.equal(store.status().objectCount, 0);
    assert.deepEqual(await readdir(join(directory, 'contracts')), []);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    refuse = false;
    assert.equal((await originalFailure.cleanupHandle.retry()).pending, false);
    assert.equal(retained.fd, -1);
    assert.equal(acquisitions, 1, 'cleanup never reopens or repeats a write');
    assert.equal(store.status().reservedObjects, 0);
  } finally {
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('a lost original object-link reply is observed without a replacement allocation', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-link-reply-'));
  const store = await openLocalPublicationStore({...configuration(directory), maxObjects: 1}, control);
  t.after(async () => { await store.close(); await rm(directory, {recursive: true}); });
  const originalLink = fsPromises.link;
  let lost = false;
  fsPromises.link = async function(from, to) {
    const result = await Reflect.apply(originalLink, this, [from, to]);
    if (!lost && String(to).startsWith(join(directory, 'objects') + sep)) {
      lost = true;
      throw Object.assign(new Error('lost original link reply'), {code: 'EIO'});
    }
    return result;
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(store.putPublicationContract(contract.name, contract.wire), {code: 'EIO'});
    assert.equal(lost, true);
    assert.equal(store.status().objectCount, 1,
      'the real completed allocation remains charged, not refunded after an unknown reply');
    assert.equal(store.status().reservedObjects, 0);
    assert.deepEqual(await readdir(join(directory, 'contracts')), []);
    const stored = await store.putPublicationContract(contract.name, contract.wire);
    assert.equal(stored.physical.created, false);
    assert.equal(store.status().objectCount, 1);
  } finally {
    fsPromises.link = originalLink;
    syncBuiltinESMExports();
  }
});

test('cold recovery preserves a completed original object before semantic visibility', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-cold-'));
  let store;
  t.after(async () => { await store?.close(); await rm(directory, {recursive: true}); });
  const selected = {...configuration(directory), maxObjects: 1};
  const source = `
    import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
    import {open} from 'node:fs/promises';
    import {join} from 'node:path';
    let armed = false;
    const store = await openLocalPublicationStore(${JSON.stringify(selected)},
      createPublicationContractControlFixture(), {async syncDirectory(path) {
        const fd = await open(path, 'r');
        try { await fd.sync(); } finally { await fd.close(); }
        if (armed && path === join(${JSON.stringify(directory)}, 'objects')) {
          process.stdout.write('ORIGINAL_OBJECT_DURABLE');
          process.exit(0);
        }
      }});
    armed = true;
    await store.putPublicationContract(${JSON.stringify(contract.name)}, ${JSON.stringify(contract.wire)});
    throw Error('missing selected crash point');
  `;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', source],
    {encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
  assert.equal(child.status, 0, child.stderr);
  assert.equal(child.signal, null);
  assert.equal(child.stdout, 'ORIGINAL_OBJECT_DURABLE');
  assert.deepEqual(await readdir(join(directory, 'contracts')), []);
  store = await openLocalPublicationStore(selected, control);
  assert.equal(store.status().objectCount, 1);
  assert.deepEqual(await readdir(join(directory, 'staging')), []);
  const stored = await store.putPublicationContract(contract.name, contract.wire);
  assert.equal(stored.physical.created, false);
  assert.equal(store.status().objectCount, 1);
});
