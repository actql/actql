// Actual Content holding, OS FD and Store. Only close outcomes and the
// original read failure are controlled; contract admission is the existing double.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t, {outcomes = ['false', 'false'], primary,
  rejectRead = primary !== undefined, diagnosticCleanup, maxRead = Infinity} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'physical-reader-ack-', label: 'original Content reader close acknowledgement'});
  const directory = join(scratch.path, 'store');
  const bytes = Buffer.from('original content bytes 01234567');
  assert.equal(bytes.length, 31);
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('original Content reader authority'), capacityBytes: 65536,
    maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture());
  const writer = store.createPreparedObjectWriter(bytes.length);
  await writer.append(bytes);
  const physical = await writer.seal(cid(bytes));
  const holding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
    holding_cid: cid('original Content reader holding'), manifest_cid: cid('original Content reference'),
    objects: [{cid: physical.cid, byte_count: 31}]};
  await store.commitPhysicalHolding(holding, [physical.prepared]);
  const path = join(directory, 'objects', physical.cid.slice(7));
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
  await probe.close();
  const closeFailure = new Error('original Content FD close rejected');
  let original, nativeClose, attempts = 0, reads = 0, consumerCalls = 0, caught;
  prototype.stat = function(...args) {
    if (original === undefined && new Error().stack.split('\n')[2]?.includes('consumeObject')) {
      original = this;
      nativeClose = this.close;
      const read = this.read;
      this.read = function(buffer, offset, length, position) {
        reads++;
        return Reflect.apply(read, this, [buffer, offset, Math.min(length, maxRead), position]);
      };
      this.close = function(...closeArgs) {
        if (new Error().stack.split('\n')[2]?.includes('node:internal/fs/streams:')) {
          return Reflect.apply(nativeClose, this, closeArgs);
        }
        const outcome = outcomes[attempts++];
        if (outcome === 'false') return Promise.resolve(false);
        if (outcome === 'reject') return Promise.reject(closeFailure);
        return Reflect.apply(nativeClose, this, closeArgs);
      };
    }
    // Fail the same acquired FD before its first read. This isolates the
    // diagnostic attachment from data delivery.
    if (this === original && rejectRead) return Promise.reject(primary);
    return Reflect.apply(stat, this, args);
  };
  t.after(async () => {
    prototype.stat = stat;
    // Always close this fresh diagnostic's same FD; failed assertions keep
    // their original scratch/raw rather than erasing the counterexample.
    if (original?.fd >= 0) {
      outcomes.length = 0;
      // A red diagnostic may have observed the exact facade in a setter that
      // discards it. This test-only backstop closes that same original duty;
      // the product must still export it through the returned failure.
      const cleanup = caught?.cleanupHandle ?? diagnosticCleanup?.();
      if (cleanup?.status().pending) await cleanup.retry();
      if (original.fd >= 0) await Reflect.apply(nativeClose, original, []);
    }
    if (!store.status().closed) await store.close();
  });
  return {scratch, store, bytes, path, holding, closeFailure,
    fd: () => original?.fd, counts: () => ({attempts, reads, consumerCalls}),
    async read() {
      try {
        return await store.consumePhysicalHolding(holding.holding_cid, 0, chunk => {
          consumerCalls++;
          assert.deepEqual(chunk, bytes);
        });
      } catch (failure) { caught = failure; throw failure; }
    }};
}

async function finish(f, cleanup) {
  const before = f.counts();
  await cleanup.retry();
  assert.equal(cleanup.status().pending, false);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: before.attempts + 1});
  assert.deepEqual(await readFile(f.path), f.bytes);
  const confirmed = f.counts();
  await cleanup.retry();
  assert.deepEqual(f.counts(), confirmed, 'settled cleanup neither closes nor reads again');
  await f.store.retirePhysicalHolding(f.holding.holding_cid);
  assert.equal(f.store.status().storedBytes, 0);
  await f.store.close();
  f.scratch.passed();
}

test('false physical close keeps the original Content FD and 31-byte holding pending', async t => {
  const f = await fixture(t);
  let failure;
  await assert.rejects(f.read(), error => { failure = error; return error.code === 'PublicationStoreCleanupPending'; });
  const cleanup = failure.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  assert(f.fd() >= 0);
  assert.equal(f.counts().reads, 1);
  assert.equal(f.store.status().storedBytes, 31);
  const retirement = await f.store.retirePhysicalHolding(f.holding.holding_cid);
  assert.equal(retirement.deleted, false);
  assert.equal(retirement.cleanup.status().pending, true);
  assert.deepEqual(await readFile(f.path), f.bytes);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  const one = cleanup.retry();
  assert.strictEqual(cleanup.retry(), one);
  await assert.rejects(one, {code: 'PublicationStoreCleanupPending'});
  assert.equal(cleanup.status().pending, true);
  assert(f.fd() >= 0);
  assert.equal(f.store.status().storedBytes, 31);
  await finish(f, cleanup);
});

test('false close-only retry cannot settle an earlier rejected physical close', async t => {
  const f = await fixture(t, {outcomes: ['reject', 'false']});
  await assert.rejects(f.read(), error => error === f.closeFailure);
  const cleanup = f.closeFailure.cleanupHandle;
  await assert.rejects(cleanup.retry(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(cleanup.status().pending, true);
  assert(f.fd() >= 0);
  assert.equal(f.counts().consumerCalls, 1);
  await finish(f, cleanup);
});

for (const outcome of ['false', 'reject']) {
  test(`actual short reads retain their original filled bytes and ${outcome}-close duty`, async t => {
    const f = await fixture(t, {outcomes: [outcome], maxRead: 3});
    let failure;
    await assert.rejects(f.read(), error => {
      failure = error;
      return outcome === 'false' ? error.code === 'PublicationStoreCleanupPending' : error === f.closeFailure;
    });
    assert.equal(f.counts().reads, 11);
    assert.equal(f.counts().consumerCalls, 1, 'fill the original piece instead of copying short chunks');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert(f.fd() >= 0);
    assert.equal(f.store.status().storedBytes, 31);
    await finish(f, failure.cleanupHandle);
  });
}

for (const field of ['cleanupPending', 'cleanupHandle', 'cleanupError']) {
  test(`readonly ${field} cannot hide the physical reader's original failure or cleanup`, async t => {
    const primary = new Error('original Content FD read refused');
    Object.defineProperty(primary, field, {value: false});
    assert.equal(Object.isExtensible(primary), true);
    const f = await fixture(t, {outcomes: ['reject'], primary});
    let failure;
    await assert.rejects(f.read(), error => { failure = error; return error.cause === primary; });
    assert.equal(primary[field], false);
    assert.equal(failure.cleanupError, f.closeFailure);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert(f.fd() >= 0);
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    await finish(f, failure.cleanupHandle);
  });
}

for (const field of ['cleanupHandle', 'cleanupPending', 'cleanupError']) {
  test(`inherited ${field} setter cannot discard the original Content FD responsibility`, async t => {
    let assigned;
    class Primary extends Error {}
    Object.defineProperty(Primary.prototype, field, {
      get() { return field === 'cleanupPending' ? false : undefined; },
      set(value) { assigned = value; }, configurable: true,
    });
    const primary = new Primary('original Content reader failure');
    const f = await fixture(t, {outcomes: ['reject'], primary,
      diagnosticCleanup: () => field === 'cleanupHandle' ? assigned : undefined});
    let failure;
    await assert.rejects(f.read(), error => { failure = error;return error === primary; });
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupError, f.closeFailure);
    assert.equal(typeof failure.cleanupHandle?.retry, 'function');
    assert.equal(Object.hasOwn(failure, field), true);
    assert.equal(assigned, undefined, 'own diagnostics must not invoke a discarding inherited setter');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert(f.fd() >= 0);
    assert.equal(f.store.status().storedBytes, 31);
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    await finish(f, failure.cleanupHandle);
  });
}

test('an existing inherited cleanup facet stays on the original failure while the new FD uses its wrapper', async t => {
  const f = await fixture(t, {outcomes: ['reject']});
  const priorFd = await open(f.path, 'r');
  let priorPending = true;
  const prior = Object.freeze({status: () => ({pending: priorPending}),
    async retry() {if (priorPending) {await priorFd.close();priorPending = false;}}});
  t.after(() => prior.retry());
  class Primary extends Error {}
  Object.defineProperty(Primary.prototype, 'cleanupHandle', {value: prior});
  const primary = new Primary('earlier independent original FD');
  // The callback fails after the actual Store reader has acquired its bytes.
  let failure;
  await assert.rejects(f.store.consumePhysicalHolding(f.holding.holding_cid, 0,
    () => {throw primary;}), error => {failure = error;return error.cause === primary;});
  assert.strictEqual(primary.cleanupHandle, prior);
  assert.notStrictEqual(failure.cleanupHandle, prior);
  assert.equal(Object.hasOwn(primary, 'cleanupHandle'), false);
  assert.equal(prior.status().pending, true);
  await priorFd.stat();
  await finish(f, failure.cleanupHandle);
  assert.equal(prior.status().pending, true, 'new duty must not retire the earlier independent FD');
  await prior.retry();
});

for (const primary of [null, undefined]) {
  test(`thrown ${String(primary)} retains the same Content FD and original close failure`, async t => {
    const f = await fixture(t, {outcomes: ['reject'], primary, rejectRead: true});
    let failure;
    await assert.rejects(f.read(), error => {failure = error;return error.cause === primary;});
    assert.equal(failure.cleanupError, f.closeFailure);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert(f.fd() >= 0);
    await finish(f, failure.cleanupHandle);
  });
}
