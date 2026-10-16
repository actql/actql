// Actual Content holding, OS FD and Store. Only close outcomes and the
// consumer failure are controlled; contract admission is the existing double.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t, {outcomes = ['false', 'false'], primary} = {}) {
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
  let original, nativeClose, attempts = 0, streams = 0, consumerCalls = 0, caught;
  prototype.stat = function(...args) {
    if (original === undefined && new Error().stack.split('\n')[2]?.includes('consumeObject')) {
      original = this;
      nativeClose = this.close;
      const stream = this.createReadStream;
      this.createReadStream = function(options) {
        streams++;
        return Reflect.apply(stream, this, [options]);
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
    return Reflect.apply(stat, this, args);
  };
  t.after(async () => {
    prototype.stat = stat;
    // Always close this fresh diagnostic's same FD; failed assertions keep
    // their original scratch/raw rather than erasing the counterexample.
    if (original?.fd >= 0) {
      outcomes.length = 0;
      if (caught?.cleanupHandle?.status().pending) await caught.cleanupHandle.retry();
      if (original.fd >= 0) await Reflect.apply(nativeClose, original, []);
    }
    if (!store.status().closed) await store.close();
  });
  return {scratch, store, bytes, path, holding, closeFailure,
    fd: () => original?.fd, counts: () => ({attempts, streams, consumerCalls}),
    async read() {
      try {
        return await store.consumePhysicalHolding(holding.holding_cid, 0, chunk => {
          consumerCalls++;
          assert.deepEqual(chunk, bytes);
          if (primary !== undefined) throw primary;
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
  assert.equal(f.counts().streams, 1);
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

for (const field of ['cleanupPending', 'cleanupHandle', 'cleanupError']) {
  test(`readonly ${field} cannot hide the physical reader's original failure or cleanup`, async t => {
    const primary = new Error('original Content consumer refused');
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
