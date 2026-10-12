// Physical opening clamps only, not a normal original Run envelope, StoreACK,
// restored Ledger or Model permission. Expectations are independent constants.
import assert from 'node:assert/strict';
import {lstat, mkdir, mkdtemp, opendir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-bootstrap-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 100, maxContractDepth: 10};
  const control = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore(configuration, control);
  await store.close();
  return {directory, configuration, control,
    open: limits => openLocalPublicationStore(configuration, control, undefined, limits)};
}

test('Store bootstrap exact raw footprint and one-short are independent of maxObjects', async t => {
  const f = await fixture(t);
  // Independently declared layout: seventeen subdirectories + store.json,
  // 242 ASCII name bytes and two 177-byte contract reads = 596 raw bytes.
  const store = await f.open({maxDirectoryEntries: 18, maxWireBytes: 596});
  assert.equal(store.status().objectCount, 0);
  await store.close();
  await assert.rejects(f.open({maxDirectoryEntries: 17, maxWireBytes: 596}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  await assert.rejects(f.open({maxDirectoryEntries: 18, maxWireBytes: 595}),
    error => error.code === 'InvalidPublicationStoreObject' ||
      error.code === 'UnknownPublicationStoreFormat');
  await assert.rejects(lstat(join(f.directory, 'owner')), {code: 'ENOENT'});
  // Neither role mutates the persisted Store contract or object quota.
  assert.equal(JSON.parse(await readFile(join(f.directory, 'store.json'))).version,
    'actql-local-publication-store/0.1');
});

test('Store bootstrap nested scans share the cumulative ceiling instead of one limit per directory', async t => {
  const f = await fixture(t);
  const key = 'b'.repeat(64), result = 'c'.repeat(64);
  const path = join(f.directory, 'retention-extensions', key, result);
  await mkdir(path, {recursive: true});
  await writeFile(join(path, '0.json'), '');
  // Same eighteen root entries, then one entry at each of three nested scans.
  const store = await f.open({maxDirectoryEntries: 21, maxWireBytes: 730});
  await store.close();
  await assert.rejects(f.open({maxDirectoryEntries: 20, maxWireBytes: 730}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  await assert.rejects(lstat(join(f.directory, 'owner')), {code: 'ENOENT'});
  assert.equal((await lstat(join(path, '0.json'))).isFile(), true);
});

test('Store bootstrap recursive temporary cleanup counts descendants without hidden native scans', async t => {
  const f = await fixture(t);
  const path = join(f.directory, 'deliveries', '.staging-test', 'child');
  await mkdir(path, {recursive: true});
  await writeFile(join(path, 'record'), '');
  // Eighteen root entries + temporary directory + child directory + record.
  await assert.rejects(f.open({maxDirectoryEntries: 20, maxWireBytes: 800}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  assert.equal((await lstat(join(path, 'record'))).isFile(), true);
  const store = await f.open({maxDirectoryEntries: 21, maxWireBytes: 800});
  await store.close();
  await assert.rejects(lstat(join(f.directory, 'deliveries', '.staging-test')), {code: 'ENOENT'});
});

test('Store bootstrap validates the closed bounds before any filesystem acquisition', async t => {
  const f = await fixture(t);
  f.configuration.directory = join(f.directory, 'uncreated');
  for (const limits of [null, true, {}, {maxWireBytes: 10},
    {maxWireBytes: 0, maxDirectoryEntries: 1},
    {maxWireBytes: -1, maxDirectoryEntries: 1},
    {maxWireBytes: 1, maxDirectoryEntries: Infinity},
    {maxWireBytes: 1, maxDirectoryEntries: Number.MAX_SAFE_INTEGER + 1},
    {maxWireBytes: 10, maxDirectoryEntries: 1, grant: true}]) {
    await assert.rejects(f.open(limits), {code: 'InvalidPublicationStoreBootstrapBounds'});
    await assert.rejects(lstat(f.configuration.directory), {code: 'ENOENT'});
  }
});

test('Store bootstrap false Dir close is pending rather than confirmed physical retirement', async t => {
  const f = await fixture(t);
  const path = f.directory;
  const probe = await opendir(path);
  const prototype = Object.getPrototypeOf(probe), close = prototype.close;
  await probe.close();
  let rejectClose = true, failure, original;
  t.after(async () => {
    rejectClose = false;
    prototype.close = close;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    else if (original) await Reflect.apply(close, original, []).catch(() => {});
  });
  prototype.close = function(...args) {
    if (typeof args[0] === 'function' || this.path !== path) return Reflect.apply(close, this, args);
    original = this;
    if (rejectClose) return Promise.resolve(false);
    return Reflect.apply(close, this, args);
  };
  await assert.rejects(f.open({maxDirectoryEntries: 18, maxWireBytes: 596}), error => {
    failure = error;
    return error.code === 'PublicationStoreBootstrapCleanupPending';
  });
  assert.equal(failure.cleanupHandle.status().pending, true);
  await assert.rejects(failure.cleanupHandle.retry(), {code: 'PublicationStoreBootstrapCleanupPending'});
  assert.equal(failure.cleanupHandle.status().pending, true);
  rejectClose = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
});

test('Store bootstrap post-owner failed Dir close retains the same Dir and original ownership', async t => {
  const f = await fixture(t);
  const path = join(f.directory, 'physical-holdings');
  const probe = await opendir(path);
  const prototype = Object.getPrototypeOf(probe), close = prototype.close, read = prototype.read;
  await probe.close();
  const blocked = Object.assign(new Error('OriginalBootstrapDirClosePending'), {code: 'EIO'});
  let original, failure, rejectClose = true, reads = 0, closes = 0;
  t.after(async () => {
    prototype.close = close;
    prototype.read = read;
    rejectClose = false;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    else if (original) await Reflect.apply(close, original, []).catch(() => {});
  });
  prototype.read = function(...args) {
    if (this.path === path) { original = this; reads++; }
    return Reflect.apply(read, this, args);
  };
  prototype.close = function(...args) {
    if (typeof args[0] === 'function' || this.path !== path) return Reflect.apply(close, this, args);
    assert.strictEqual(this, original);
    closes++;
    if (rejectClose) return Promise.reject(blocked);
    return Reflect.apply(close, this, args);
  };
  await assert.rejects(f.open({maxDirectoryEntries: 18, maxWireBytes: 596}), error => {
    failure = error;
    return error.cause === blocked;
  });
  const owner = await readFile(join(f.directory, 'owner', 'owner.json'));
  assert.equal(JSON.parse(owner).pid, process.pid);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(reads, 1);
  assert.equal(closes, 2); // Initial close and same-Dir opening cleanup attempt.
  const flight = failure.cleanupHandle.retry();
  assert.strictEqual(failure.cleanupHandle.retry(), flight);
  await assert.rejects(flight, error => error === blocked);
  assert.deepEqual(await readFile(join(f.directory, 'owner', 'owner.json')), owner);
  rejectClose = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(reads, 1);
  assert.equal(closes, 4);
  await assert.rejects(lstat(join(f.directory, 'owner')), {code: 'ENOENT'});
  await failure.cleanupHandle.retry();
  assert.equal(closes, 4);
});
