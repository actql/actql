import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import fs, {lstat, mkdtemp, open, rm} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function fixture(t, {closeFailures = 1, consumerFailure, openFailure} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-original-reader-'));
  const originalOpen = fs.open;
  const holdingCid = digest('original reader holding');
  const bytes = Buffer.from('original');
  const cid = digest(bytes);
  const path = join(directory, 'objects', cid.slice(7));
  const closeFailure = Object.assign(new Error('OriginalFdClosePending'), {code: 'EIO'});
  let store, writer, preparation, original, failure;
  let attempts = 0, published = 0, opens = 0;
  let allowClose = false, retiring = false, committed = false;
  t.after(async () => {
    fs.open = originalOpen;
    syncBuiltinESMExports();
    allowClose = true;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    else if (original?.fd >= 0) await original.close();
    if (store !== undefined && !store.status().closed) {
      if (committed) assert.equal((await store.retirePhysicalHolding(holdingCid)).cleanup.status().pending, false);
      else if (preparation !== undefined) await preparation.release();
      else await writer?.cancel();
      assert.equal(await store.close(), true);
    }
    await rm(directory, {recursive: true});
  });
  store = await openLocalPublicationStore({
    directory, storeAuthorityCid: digest('original reader authority'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 4096, maxObjects: 16,
    maxContractNodes: 4096, maxContractDepth: 64,
  }, createPublicationContractControlFixture());
  writer = store.createPreparedObjectWriter(bytes.length);
  await writer.append(bytes);
  preparation = (await writer.seal(cid)).prepared;
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1', namespace: 'content',
    holding_cid: holdingCid, manifest_cid: digest('original reader manifest'),
    objects: [{cid, byte_count: bytes.length}],
  }, [preparation]);
  committed = true;
  fs.open = async (...args) => {
    // The verifier uses O_NONBLOCK. Retirement owns its separate descriptor.
    if (retiring || args[0] !== path || args[1] !== (constants.O_RDONLY | constants.O_NOFOLLOW)) {
      return originalOpen(...args);
    }
    opens++;
    if (openFailure !== undefined) throw openFailure;
    assert.equal(original, undefined, 'the original reader may acquire only one FD');
    original = await originalOpen(...args);
    const close = original.close;
    original.close = function() {
      attempts++;
      if (!allowClose && attempts <= closeFailures) return Promise.reject(closeFailure);
      return Reflect.apply(close, this, []);
    };
    return original;
  };
  syncBuiltinESMExports();
  return {store, bytes, path, closeFailure, fd: () => original?.fd,
    attempts: () => attempts, published: () => published, opens: () => opens,
    async consume() {
      try {
        const result = await store.consumePhysicalHolding(holdingCid, 0, async chunk => {
          assert.deepEqual(chunk, bytes);
          if (consumerFailure !== undefined) throw consumerFailure;
        });
        published++;
        return result;
      } catch (error) { failure = error; throw error; }
    },
    async retire() {
      retiring = true;
      try { return (await store.retirePhysicalHolding(holdingCid)).cleanup.status(); }
      finally { retiring = false; }
    },
  };
}

test('original FD close failure retains reader and byte custody through failed retry', async t => {
  const f = await fixture(t, {closeFailures: 2});
  let failure;
  await assert.rejects(f.consume(), error => { failure = error; return error === f.closeFailure; });
  const handle = failure.cleanupHandle;
  assert.equal(handle.status().pending, true);
  assert(f.fd() >= 0);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(f.published(), 0);
  assert.equal((await f.retire()).pending, true);
  assert.equal(f.store.status().storedBytes, f.bytes.length);
  assert.equal((await lstat(f.path)).size, f.bytes.length);
  const one = handle.retry(), same = handle.retry();
  assert.equal(one, same, 'concurrent retry borrows the same original close flight');
  await assert.rejects(one, error => error === f.closeFailure);
  assert.equal(f.attempts(), 2);
  assert.equal(handle.status().pending, true);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal((await f.retire()).pending, true);
  await handle.retry();
  assert.equal(handle.status().pending, false);
  assert.equal(f.fd(), -1);
  assert.equal(f.opens(), 1, 'cleanup never reopens by path');
  assert.equal((await f.retire()).pending, false);
  assert.equal(f.store.status().storedBytes, 0);
  await assert.rejects(lstat(f.path), {code: 'ENOENT'});
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
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  await primary.cleanupHandle.retry();
  assert.equal(f.fd(), -1);
  assert.equal((await f.retire()).pending, false);
});

test('frozen consumer failure is preserved as cause with original FD cleanup', async t => {
  const primary = Object.freeze(new Error('OriginalFrozenFailure'));
  const f = await fixture(t, {consumerFailure: primary});
  let failure;
  await assert.rejects(f.consume(), error => { failure = error; return error.cause === primary; });
  await failure.cleanupHandle.retry();
  assert.equal(f.fd(), -1);
  assert.equal(f.published(), 0);
});

test('confirmed original close releases the same reader once', async t => {
  const f = await fixture(t, {closeFailures: 0});
  const result = await f.consume();
  assert.equal(result.bytes, f.bytes.length);
  assert.equal(f.fd(), -1);
  assert.equal(f.attempts(), 1);
  assert.equal(f.published(), 1);
  assert.equal((await f.retire()).pending, false);
});

test('open rejection before allocation releases only its unacquired reader', async t => {
  const primary = new Error('OriginalOpenFailure');
  const f = await fixture(t, {openFailure: primary});
  await assert.rejects(f.consume(), error => error === primary);
  assert.equal(f.attempts(), 0);
  assert.equal(f.fd(), undefined);
  assert.equal((await f.retire()).pending, false);
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
  const read = prototype.read;
  await probe.close();
  let original, closeAttempts = 0, captures = 0;
  const closeFailure = Object.assign(new Error('ActualOriginalFdClosePending'), {code: 'EIO'});
  prototype.read = function(...args) {
    // inspectPhysicalHolding first verifies the object through verifyObject.
    // This finite hunk targets the later actual consumeObject FD, not that
    // separate metadata/verification close obligation.
    if (!new Error().stack.includes('at consumeObject ')) {
      return Reflect.apply(read, this, args);
    }
    captures++;
    original = this;
    const close = this.close;
    this.close = function() {
      closeAttempts++;
      if (closeAttempts <= 2) return Promise.reject(closeFailure);
      return Reflect.apply(close, this, []);
    };
    return Reflect.apply(read, this, args);
  };
  t.after(async () => {
    prototype.read = read;
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
  prototype.read = read;
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
