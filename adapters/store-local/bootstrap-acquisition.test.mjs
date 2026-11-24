// Physical opening clamps only, not a normal original Run envelope, StoreACK,
// restored Ledger or Model permission. Expectations are independent constants.
import assert from 'node:assert/strict';
import {lstat, mkdir, mkdtemp, opendir, readdir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

// Fixed current format, with an optional stable lease only on supported native runtimes.
const rootEntries = Object.freeze([
  'attempts', 'clocks', 'contracts', 'deletions', 'deliveries',
  'delivery-attempts-index.json', 'delivery-attempts.sqlite3', 'effect-capture-custody',
  'indexes', 'manifest-reads', 'metadata-deletions', 'metadata-inventories', 'objects',
  'physical-holding-deletions', 'physical-holdings', 'prepared-custody', 'prepared-schemas',
  'retention-extensions', 'staging', 'store.json',
]);
const nativeLease = 'owner-lease';
const migrationFiles = ['delivery-attempts-index.json', 'delivery-attempts.sqlite3'];

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-bootstrap-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 100, maxContractDepth: 10};
  const control = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore(configuration, control);
  await store.close();
  const actualNames = await readdir(directory);
  const expectedNames = actualNames.includes(nativeLease) ? [...rootEntries, nativeLease] : [...rootEntries];
  assert.deepEqual(actualNames.sort(), expectedNames.sort());
  const independentContract = JSON.stringify({version: 'actql-local-publication-store/0.1',
    isolation: 'execution-namespace', store_authority_cid: configuration.storeAuthorityCid});
  assert.equal(await readFile(join(directory, 'store.json'), 'utf8'), independentContract);
  const bounds = {maxDirectoryEntries: expectedNames.length,
    maxWireBytes: expectedNames.reduce((total, name) => total + Buffer.byteLength(name), 0) +
      2 * Buffer.byteLength(independentContract)};
  return {directory, configuration, control, bounds,
    open: limits => openLocalPublicationStore(configuration, control, undefined, limits)};
}

test('Store bootstrap exact raw footprint and one-short are independent of maxObjects', async t => {
  const f = await fixture(t);
  const store = await f.open(f.bounds);
  assert.equal(store.status().objectCount, 0);
  await store.close();
  await assert.rejects(f.open({...f.bounds, maxDirectoryEntries: f.bounds.maxDirectoryEntries - 1}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  await assert.rejects(f.open({...f.bounds, maxWireBytes: f.bounds.maxWireBytes - 1}),
    error => error.code === 'InvalidPublicationStoreObject' ||
      error.code === 'UnknownPublicationStoreFormat');
  await assert.rejects(lstat(join(f.directory, 'owner')), {code: 'ENOENT'});
  // Neither role mutates the persisted Store contract or object quota.
  assert.equal(JSON.parse(await readFile(join(f.directory, 'store.json'))).version,
    'actql-local-publication-store/0.1');
});

test('Store bootstrap nested scans share the cumulative ceiling instead of one limit per directory', async t => {
  const f = await fixture(t);
  const staging = join(f.directory, 'staging', 'object-00000000-0000-0000-0000-000000000001');
  const clock = join(f.directory, 'clocks', '.staging-independent');
  await writeFile(staging, '');
  await writeFile(clock, '');
  const bounds = {maxDirectoryEntries: f.bounds.maxDirectoryEntries + 2,
    maxWireBytes: f.bounds.maxWireBytes + 128};
  await assert.rejects(f.open({...bounds, maxDirectoryEntries: bounds.maxDirectoryEntries - 1}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  // The first nested scan consumed one entry. The next cannot acquire its own
  // independent ceiling, and must refuse before removing the clock staging file.
  await assert.rejects(lstat(staging), {code: 'ENOENT'});
  assert.equal((await lstat(clock)).isFile(), true);
  await assert.rejects(lstat(join(f.directory, 'owner')), {code: 'ENOENT'});
  await writeFile(staging, '');
  const store = await f.open(bounds);
  await store.close();
  await assert.rejects(lstat(staging), {code: 'ENOENT'});
  await assert.rejects(lstat(clock), {code: 'ENOENT'});
});

test('Store bootstrap recursive temporary cleanup counts descendants without hidden native scans', async t => {
  async function legacyFixture() {
    const f = await fixture(t);
    // Project the empty legacy layout in this disposable fixture. The
    // actual initial adoption owns recursive staging cleanup.
    for (const name of migrationFiles) await rm(join(f.directory, name));
    const path = join(f.directory, 'deliveries', '.staging-test', 'child');
    await mkdir(path, {recursive: true});
    await writeFile(join(path, 'record'), '');
    return {f, path, bounds: {...f.bounds, maxWireBytes: f.bounds.maxWireBytes + 128,
      maxDirectoryEntries: f.bounds.maxDirectoryEntries - migrationFiles.length + 2}};
  }
  const short = await legacyFixture();
  await assert.rejects(short.f.open({...short.bounds, maxDirectoryEntries: short.bounds.maxDirectoryEntries - 1}),
    {code: 'PublicationStoreBootstrapEntriesLimit'});
  assert.equal((await lstat(join(short.path, 'record'))).isFile(), true);
  const exact = await legacyFixture();
  const store = await exact.f.open(exact.bounds);
  await store.close();
  await assert.rejects(lstat(join(exact.f.directory, 'deliveries', '.staging-test')), {code: 'ENOENT'});
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
  await assert.rejects(f.open(f.bounds), error => {
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
  const path = join(f.directory, 'physical-holding-deletions');
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
  await assert.rejects(f.open(f.bounds), error => {
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
