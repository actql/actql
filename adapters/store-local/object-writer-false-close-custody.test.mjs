import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

// Actual Store, staging file and native FD. Only the FD close observation is
// controlled; contract control remains a double, not original Core admission.
async function fixture(t, {primary} = {}) {
  const directory = await fs.mkdtemp(join(tmpdir(), 'actql-c-writer-false-close-'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('original false-close authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1048576,
    maxObjectBytes: 16384, maxObjects: 40, maxContractNodes: 1000,
    maxContractDepth: 30}, createPublicationContractControlFixture());
  const originalOpen = fs.open;
  let handle, path, writer, parent, passed = false, blocked = true;
  let opens = 0, writes = 0, stats = 0, closes = 0;
  fs.open = async (...args) => {
    const actual = await Reflect.apply(originalOpen, fs, args);
    if (!String(args[0]).startsWith(join(directory, 'staging', 'object-'))) return actual;
    assert.equal(handle, undefined, 'cleanup must not open another writer');
    handle = actual;
    path = args[0];
    opens++;
    return new Proxy(actual, {get(target, key) {
      if (key === 'write') return async (...writeArgs) => {
        writes++;
        if (primary !== undefined) throw primary;
        return Reflect.apply(target.write, target, writeArgs);
      };
      if (key === 'stat') return async (...statArgs) => {
        stats++;
        return Reflect.apply(target.stat, target, statArgs);
      };
      if (key === 'close') return async () => {
        closes++;
        // Explicit false is NOT the native undefined-success response. Keep
        // the real OS descriptor open so the independent oracle can see it.
        if (blocked) return false;
        await target.close();
      };
      const value = Reflect.get(target, key, target);
      return typeof value === 'function' ? value.bind(target) : value;
    }});
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = originalOpen;
    syncBuiltinESMExports();
    blocked = false;
    try { await parent?.abort(); } catch { /* Retain failed original custody. */ }
    try { await writer?.cancel(); } catch { /* Retain failed original custody. */ }
    // A failing old product may have lost its handle. Close the diagnostic FD
    // directly only in teardown, never as product cleanup/retirement evidence.
    if (handle?.fd >= 0) await handle.close();
    try {
      assert.equal(await store.close(), true);
      if (passed) await fs.rm(directory, {recursive: true});
      else t.diagnostic(`Preserved false-close failure: ${directory}`);
    } catch (error) {
      t.diagnostic(`Preserved pending false-close Store: ${directory}`);
      if (passed) throw error;
    }
  });
  return {store, counts: () => ({opens, writes, stats, closes}), fd: () => handle?.fd,
    path: () => path, allowClose() { blocked = false; },
    writer() { writer = store.createObjectWriter(3); return writer; },
    parent() {
      parent = preparePrivatePublicationHolding(store, {name: 'model_invocation_evidence',
        semanticCid: cid('original false-close semantic'),
        holdingCid: cid('original false-close holding'), wire: 'abc'});
      return parent;
    }, pass() { passed = true; }};
}

test('writer cancellation keeps the same live FD and reservation after explicit false close', async t => {
  const f = await fixture(t), writer = f.writer();
  await writer.append('abc');
  await assert.rejects(writer.cancel(), {code: 'PublicationStoreCleanupPending'});
  assert(f.fd() >= 0);
  assert.equal((await fs.stat(f.path())).size, 3);
  assert.equal(writer.status().cleanupPending, true);
  assert.equal(writer.status().reservationHeld, true);
  assert.equal(f.store.status().reservedBytes, 3);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  const before = f.counts();
  f.allowClose();
  assert.deepEqual(await Promise.all([writer.cancel(), writer.cancel()]), [true, false]);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, closes: before.closes + 1});
  assert.equal(writer.status().cleanupPending, false);
  assert.equal(writer.status().reservationHeld, false);
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(f.store.status().objectCount, 0);
  assert.equal(await writer.cancel(), false);
  f.pass();
});

test('seal cannot publish or return capacity while its actual writer FD close is false', async t => {
  const f = await fixture(t), writer = f.writer();
  await writer.append('abc');
  await assert.rejects(writer.seal(cid('abc')), {code: 'PublicationStoreCleanupPending'});
  assert(f.fd() >= 0);
  assert.equal(writer.status().cleanupPending, true);
  assert.equal(writer.status().reservationHeld, true);
  assert.equal(f.store.status().objectCount, 0);
  assert.equal(f.store.status().reservedBytes, 3);
  assert.deepEqual(f.counts(), {opens: 1, writes: 1, stats: 1, closes: 2});
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  const before = f.counts();
  f.allowClose();
  assert.equal(await writer.cancel(), true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, closes: before.closes + 1});
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(f.store.status().objectCount, 0);
  f.pass();
});

test('encrypted private parent preserves frozen write cause and same false-close cleanup', async t => {
  const primary = Object.freeze(Object.assign(new Error('OriginalFrozenWriteFailure'),
    {code: 'OriginalFrozenWriteFailure'}));
  const f = await fixture(t, {primary}), parent = f.parent();
  await assert.rejects(parent.commit(), error => {
    assert.equal(error.cause, primary);
    assert.equal(error.cleanupHandle, parent);
    assert.equal(error.cleanupPending, true);
    return true;
  });
  assert(f.fd() >= 0);
  assert.equal(parent.status().committed, false);
  assert.equal(parent.status().preparedPending, true);
  assert.equal(f.store.status().reservedBytes, 132);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  const before = f.counts();
  f.allowClose();
  const first = parent.abort();
  assert.strictEqual(parent.abort(), first);
  assert.equal(await first, true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, closes: before.closes + 1});
  assert.equal(parent.status().preparedPending, false);
  assert.equal(parent.status().committed, false);
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(f.store.status().objectCount, 0);
  await parent.abort();
  assert.equal(f.counts().closes, before.closes + 1);
  f.pass();
});

test('encrypted private seal keeps original parent pending until confirmed close-only abort', async t => {
  const f = await fixture(t), parent = f.parent();
  await assert.rejects(parent.commit(), error => {
    assert.equal(error.code, 'PublicationStoreCleanupPending');
    assert.equal(error.cleanupHandle, parent);
    assert.equal(error.cleanupPending, true);
    return true;
  });
  assert(f.fd() >= 0);
  assert.equal(parent.status().committed, false);
  assert.equal(parent.status().preparedPending, true);
  assert.equal(f.store.status().reservedBytes, 132);
  assert.equal(f.store.status().objectCount, 0);
  assert.deepEqual(f.counts(), {opens: 1, writes: 1, stats: 1, closes: 3});
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  const before = f.counts();
  f.allowClose();
  assert.equal(await parent.abort(), true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, closes: before.closes + 1});
  assert.equal(parent.status().preparedPending, false);
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(f.store.status().objectCount, 0);
  f.pass();
});
