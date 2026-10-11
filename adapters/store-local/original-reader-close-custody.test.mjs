import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import {lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createContext, runInContext} from 'node:vm';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

// Actual product functions and original OS FD; only close failure and unrelated
// Catalog/metadata/unlink ports are controlled. Not a public Run acceptance.
const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
function part(first, next) {
  const start = source.indexOf(first), end = source.indexOf(next, start);
  assert(start >= 0 && end > start);
  return source.slice(start, end);
}
const consumeBody = part('  const consumeObject = async (', '\n  const withCommittedResult = async (');
const physicalBody = part('  const consumePhysicalHolding = async (', '\n  const ensurePhysicalHoldingDeletion = async ');
const retireBody = part('  const createPhysicalHoldingDeletionCleanup = record => {', '\n  const retirePhysicalHolding = async ');

async function fixture(t, {closeFailures = 1, consumerFailure, openFailure} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-original-reader-'));
  const path = join(directory, 'original');
  const bytes = Buffer.from('original');
  await writeFile(path, bytes);
  const original = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  t.after(async () => {
    if (original.fd >= 0) await original.close();
    await rm(directory, {recursive: true});
  });
  const cid = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const record = {holding_cid: 'holding-original', manifest_cid: 'manifest-original', objects: [{cid, byte_count: bytes.length}]};
  let attempts = 0, published = 0, opens = 0;
  const closeFailure = Object.assign(new Error('OriginalFdClosePending'), {code: 'EIO'});
  const unlinks = [], readers = new Map();
  const context = createContext({
    active() {}, quantity: value => Number.isSafeInteger(value) && value >= 0,
    fail(code) { throw Object.assign(new Error(code), {code}); }, constants, createHash,
    configuration: {maxObjectBytes: bytes.length}, objectPath: () => path, cidHex: value => value.slice(7),
    async open(selected) {
      opens++;
      assert.equal(selected, path);
      if (openFailure) throw openFailure;
      return {
        stat: () => original.stat(), createReadStream: options => original.createReadStream(options),
        async close() {
          attempts++;
          if (attempts <= closeFailures) throw closeFailure;
          await original.close();
        },
      };
    },
    activePhysicalHoldingReaders: readers, async inspectPhysicalHolding() { return record; },
    pendingPhysicalHoldingDeletions: new Map(), materialRetentionBusy: Promise.resolve(), preparedObjects: new Map(),
    async ensurePhysicalHoldingDeletion() {}, async readPhysicalHolding() { return record; },
    physicalHoldingPath: () => join(directory, 'holding'), physicalHoldingDeletionPath: () => join(directory, 'deletion'),
    physicalHoldingsDirectory: directory, physicalHoldingDeletionsDirectory: directory, objectsDirectory: directory,
    lstat, async materialHasLiveReference() { return false; }, async unlink(selected) { unlinks.push(selected); },
    async syncDirectory() {}, storedBytes: bytes.length, objectCount: 1, Buffer,
  });
  const product = runInContext(`(() => {${consumeBody}\n${physicalBody}\n${retireBody}
    return {consumePhysicalHolding, createPhysicalHoldingDeletionCleanup};})()`, context);
  return {original, bytes, path, closeFailure, readers, unlinks, context,
    attempts: () => attempts, published: () => published, opens: () => opens,
    async consume() {
      const result = await product.consumePhysicalHolding(record.holding_cid, 0, async chunk => {
        assert.equal(chunk.toString(), bytes.toString());
        if (consumerFailure) throw consumerFailure;
      });
      published++;
      return result;
    },
    retire: () => product.createPhysicalHoldingDeletionCleanup(record).retry(),
  };
}

test('original FD close failure retains reader and byte custody through failed retry', async t => {
  const f = await fixture(t, {closeFailures: 2});
  let failure;
  await assert.rejects(f.consume(), error => { failure = error; return error === f.closeFailure; });
  const handle = failure.cleanupHandle;
  assert.equal(handle.status().pending, true);
  assert(f.original.fd >= 0);
  assert.equal(f.readers.get('holding-original'), 1);
  assert.equal(f.published(), 0);
  assert.equal((await f.retire()).pending, true);
  assert.equal(f.context.storedBytes, f.bytes.length);
  assert.equal(f.unlinks.length, 0);
  const one = handle.retry(), same = handle.retry();
  assert.equal(one, same, 'concurrent retry borrows the same original close flight');
  await assert.rejects(one, error => error === f.closeFailure);
  assert.equal(f.attempts(), 2);
  assert.equal(handle.status().pending, true);
  assert.equal(f.readers.get('holding-original'), 1);
  assert.equal((await f.retire()).pending, true);
  await handle.retry();
  assert.equal(handle.status().pending, false);
  assert.equal(f.original.fd, -1);
  assert.equal(f.readers.size, 0);
  assert.equal(f.opens(), 1, 'cleanup never reopens by path');
  assert.equal((await f.retire()).pending, false);
  assert.equal(f.context.storedBytes, 0);
  assert(f.unlinks.includes(f.path));
  await handle.retry();
  assert.equal(f.attempts(), 3, 'confirmed close is not repeated');
});

test('consumer failure remains primary while original FD cleanup is pending', async t => {
  const primary = new Error('OriginalConsumerFailure');
  const f = await fixture(t, {consumerFailure: primary});
  await assert.rejects(f.consume(), error => error === primary);
  assert.equal(primary.cleanupError, f.closeFailure);
  assert.equal(primary.cleanupHandle.status().pending, true);
  assert.equal(f.published(), 0);
  assert.equal(f.readers.size, 1);
  await primary.cleanupHandle.retry();
  assert.equal(f.original.fd, -1);
  assert.equal(f.readers.size, 0);
});

test('frozen consumer failure is preserved as cause with original FD cleanup', async t => {
  const primary = Object.freeze(new Error('OriginalFrozenFailure'));
  const f = await fixture(t, {consumerFailure: primary});
  let failure;
  await assert.rejects(f.consume(), error => { failure = error; return error.cause === primary; });
  await failure.cleanupHandle.retry();
  assert.equal(f.original.fd, -1);
  assert.equal(f.published(), 0);
});

test('confirmed original close releases the same reader once', async t => {
  const f = await fixture(t, {closeFailures: 0});
  const result = await f.consume();
  assert.equal(result.bytes, f.bytes.length);
  assert.equal(f.original.fd, -1);
  assert.equal(f.readers.size, 0);
  assert.equal(f.attempts(), 1);
  assert.equal(f.published(), 1);
  assert.equal((await f.retire()).pending, false);
});

test('open rejection before allocation releases only its unacquired reader', async t => {
  const primary = new Error('OriginalOpenFailure');
  const f = await fixture(t, {openFailure: primary});
  await assert.rejects(f.consume(), error => error === primary);
  assert.equal(f.readers.size, 0);
  assert.equal(f.attempts(), 0);
  assert.equal(primary.cleanupHandle, undefined);
  assert.equal(f.published(), 0);
});

test('actual encrypted Store read blocks retirement and close until original FD retry succeeds', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-failed-close-'));
  const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const store = await openLocalPublicationStore({
    directory, storeAuthorityCid: digest('original failed-close authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 16, maxContractNodes: 4096, maxContractDepth: 64,
  }, createPublicationContractControlFixture());
  const semanticCid = digest('original failed-close semantic record');
  const holdingCid = digest('original failed-close physical holding');
  const prepared = await store.preparePrivateEvidence('model_invocation_evidence', 'abc', semanticCid);
  assert.equal(prepared.bytes, 132, 'independent three-byte AES-GCM envelope size');
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
    holding_cid: holdingCid, manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: 132}],
  }, [prepared.prepared]);
  const probe = await open(join(directory, 'objects', prepared.physicalCid.slice(7)), 'r');
  const prototype = Object.getPrototypeOf(probe);
  const createReadStream = prototype.createReadStream;
  await probe.close();
  let original, closeAttempts = 0, captures = 0;
  const closeFailure = Object.assign(new Error('ActualOriginalFdClosePending'), {code: 'EIO'});
  prototype.createReadStream = function(options) {
    // inspectPhysicalHolding first verifies the object through verifyObject.
    // This finite hunk targets the later actual consumeObject FD, not that
    // separate metadata/verification close obligation.
    if (!new Error().stack.includes('at consumeObject ')) {
      return Reflect.apply(createReadStream, this, [options]);
    }
    captures++;
    original = this;
    const close = this.close;
    this.close = function() {
      closeAttempts++;
      if (closeAttempts <= 2) return Promise.reject(closeFailure);
      return Reflect.apply(close, this, []);
    };
    return Reflect.apply(createReadStream, this, [options]);
  };
  t.after(async () => {
    prototype.createReadStream = createReadStream;
    // Failed test teardown never leaves its original FD/Store lock behind.
    if (closeFailure.cleanupHandle?.status().pending) {
      closeAttempts = 2;
      await closeFailure.cleanupHandle.retry();
    } else if (original?.fd >= 0) {
      closeAttempts = 2;
      await original.close();
    }
    if (!store.status().closed) {
      await store.retirePhysicalHolding(holdingCid);
      await store.close();
    }
    await rm(directory, {recursive: true});
  });
  await assert.rejects(store.readPrivateEvidence('model_invocation_evidence', semanticCid, holdingCid),
    error => error === closeFailure);
  prototype.createReadStream = createReadStream;
  assert.equal(captures, 1);
  assert(original.fd >= 0);
  assert.equal(closeAttempts, 1);
  assert.equal(closeFailure.cleanupHandle.status().pending, true);
  assert.equal(store.status().storedBytes, 132);
  await assert.rejects(store.close(), error => error.code === 'PublicationStoreCleanupPending');
  const retirement = await store.retirePhysicalHolding(holdingCid);
  assert.equal(retirement.deleted, false, JSON.stringify({retirement, closeAttempts, fd: original.fd}));
  assert.equal(retirement.cleanup.status().pending, true);
  assert.equal((await lstat(join(directory, 'objects', prepared.physicalCid.slice(7)))).size, 132);
  await assert.rejects(store.close(), error => error.code === 'PublicationStoreCleanupPending');
  const cleanup = closeFailure.cleanupHandle;
  await assert.rejects(cleanup.retry(), error => error === closeFailure);
  assert.equal(cleanup.status().pending, true);
  assert.equal(store.status().storedBytes, 132);
  await cleanup.retry();
  assert.equal(original.fd, -1);
  assert.equal(cleanup.status().pending, false);
  assert.equal((await store.retirePhysicalHolding(holdingCid)).deleted, true);
  assert.equal(store.status().storedBytes, 0);
  await store.close();
  // Node's FileHandle close event can invoke the stream's idempotent close
  // callback too. Count no additional invocation from OUR settled retry.
  const completedCloseCalls = closeAttempts;
  await cleanup.retry();
  assert.equal(closeAttempts, completedCloseCalls);
});
