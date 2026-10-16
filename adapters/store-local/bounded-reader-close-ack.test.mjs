// Actual bounded metadata reader and native FD. Only close/read outcomes are
// controlled; no historical Store, Run, provider, permission or lease is used.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openLocalPublicationStore, readBoundedLocalMetadata} from './publication-store.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

async function fixture(t, {outcomes = ['false', 'false'], primary, openFailure} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'bounded-reader-ack-', label: 'original metadata reader close acknowledgement'});
  const path = join(scratch.path, 'original'), bytes = Buffer.from('original metadata bytes\n');
  await fs.writeFile(path, bytes, {mode: 0o600});
  const originalOpen = fs.open;
  const closeFailure = Object.assign(new Error('original metadata FD close'), {code: 'EIO'});
  let handle, nativeClose, caught, opens = 0, reads = 0, closes = 0, retired = 0, returned = 0;
  fs.open = async (...args) => {
    if (args[0] !== path) return Reflect.apply(originalOpen, fs, args);
    opens++;
    if (openFailure !== undefined) throw openFailure;
    assert.equal(handle, undefined, 'retry cannot open a replacement file');
    handle = await Reflect.apply(originalOpen, fs, args);
    nativeClose = handle.close.bind(handle);
    const read = handle.read.bind(handle);
    handle.read = async (...values) => {
      reads++;
      if (primary !== undefined) throw primary;
      return read(...values);
    };
    handle.close = async () => {
      const outcome = outcomes[closes++];
      if (outcome === 'false') return false;
      if (outcome === 'reject') throw closeFailure;
      return nativeClose();
    };
    return handle;
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = originalOpen;
    syncBuiltinESMExports();
    outcomes.length = 0;
    if (caught?.cleanupHandle?.status().pending) await caught.cleanupHandle.retry();
    // A red old product can lose its export. This diagnostic still closes
    // only its exact fresh FD, without claiming that as product cleanup.
    if (handle?.fd >= 0) await nativeClose();
  });
  return {scratch, path, bytes, closeFailure, fd: () => handle?.fd,
    counts: () => ({opens, reads, closes, retired, returned}),
    async read() {
      try {
        const value = await readBoundedLocalMetadata(path, bytes.length, () => { retired++; });
        returned++;
        return value;
      } catch (error) { caught = error; throw error; }
    }};
}

test('bounded original false close cannot return bytes or acknowledge the metadata FD', async t => {
  const f = await fixture(t);
  let failure;
  await assert.rejects(f.read(), error => { failure = error; return error.cleanupPending === true; });
  assert(f.fd() >= 0);
  assert.deepEqual(f.counts(), {opens: 1, reads: 2, closes: 1, retired: 0, returned: 0});
  const cleanup = failure.cleanupHandle, snapshot = cleanup.status();
  assert.equal(snapshot.pending, true);
  const retry = cleanup.retry();
  assert.equal(cleanup.retry(), retry);
  await assert.rejects(retry, {code: 'PublicationMetadataReaderCleanupPending'});
  assert(f.fd() >= 0);
  assert.equal(cleanup.status().pending, true);
  assert.equal(f.counts().retired, 0);
  assert.equal((await cleanup.retry()).pending, false);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {opens: 1, reads: 2, closes: 3, retired: 1, returned: 0});
  assert.equal(snapshot.pending, true, 'escaped status snapshots stay immutable');
  await cleanup.retry();
  assert.equal(f.counts().closes, 3);
  f.scratch.passed();
});

test('bounded original rejected close followed by false retry retains the same FD and primary', async t => {
  const f = await fixture(t, {outcomes: ['reject', 'false']});
  await assert.rejects(f.read(), error => error === f.closeFailure);
  const cleanup = f.closeFailure.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  await assert.rejects(cleanup.retry(), {code: 'PublicationMetadataReaderCleanupPending'});
  assert(f.fd() >= 0);
  assert.equal(cleanup.status().pending, true);
  assert.equal(f.counts().retired, 0);
  assert.equal((await cleanup.retry()).pending, false);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {opens: 1, reads: 2, closes: 3, retired: 1, returned: 0});
  f.scratch.passed();
});

for (const field of ['cleanupPending', 'cleanupHandle', 'cleanupError']) {
  test(`bounded original readonly ${field} cannot mask the primary or lose cleanup`, async t => {
    const primary = Object.defineProperty(new Error('original metadata read'), field,
      {value: field === 'cleanupPending' ? false : undefined});
    assert.equal(Object.isExtensible(primary), true);
    const f = await fixture(t, {primary, outcomes: ['reject', 'false']});
    let failure;
    await assert.rejects(f.read(), error => {
      failure = error;
      return error.cause === primary && error.cleanupPending === true;
    });
    assert.equal(failure.cleanupError, f.closeFailure);
    assert(f.fd() >= 0);
    const cleanup = failure.cleanupHandle;
    await assert.rejects(cleanup.retry(), {code: 'PublicationMetadataReaderCleanupPending'});
    assert.equal(cleanup.status().pending, true);
    assert.equal(f.counts().retired, 0);
    await cleanup.retry();
    assert.equal(f.fd(), -1);
    assert.deepEqual(f.counts(), {opens: 1, reads: 1, closes: 3, retired: 1, returned: 0});
    assert.equal(Object.getOwnPropertyDescriptor(primary, field).value,
      field === 'cleanupPending' ? false : undefined);
    f.scratch.passed();
  });
}

test('bounded original healthy close retains existing bytes and single acknowledgement', async t => {
  const healthy = await fixture(t, {outcomes: []});
  assert.deepEqual(await healthy.read(), healthy.bytes);
  assert.deepEqual(healthy.counts(), {opens: 1, reads: 2, closes: 1, retired: 1, returned: 1});
  healthy.scratch.passed();
});

for (const field of ['cleanupHandle', 'cleanupPending']) {
  test(`bounded original inherited ${field} setter cannot discard same-FD custody`, async t => {
    let intercepted = 0;
    class OriginalReadFailure extends Error {}
    Object.defineProperty(OriginalReadFailure.prototype, field, {
      get() { return field === 'cleanupPending' ? false : undefined; },
      set(_value) { intercepted++; },
    });
    const primary = new OriginalReadFailure('original metadata read');
    const f = await fixture(t, {primary, outcomes: ['reject', 'false']});
    let failure;
    await assert.rejects(f.read(), error => {
      failure = error;
      assert.equal(error, primary, 'safe extensible Error retains identity');
      assert.equal(error.cleanupPending, true);
      assert.equal(typeof error.cleanupHandle?.retry, 'function');
      return true;
    });
    assert.equal(intercepted, 0, 'diagnostic transfer does not call an inherited setter');
    assert(Object.hasOwn(primary, 'cleanupHandle'));
    assert(Object.hasOwn(primary, 'cleanupPending'));
    const cleanup = failure.cleanupHandle;
    const first = cleanup.retry();
    assert.equal(cleanup.retry(), first);
    await assert.rejects(first, {code: 'PublicationMetadataReaderCleanupPending'});
    assert.equal(cleanup.status().pending, true);
    assert(f.fd() >= 0);
    await cleanup.retry();
    assert.equal(f.fd(), -1);
    assert.deepEqual(f.counts(), {opens: 1, reads: 1, closes: 3, retired: 1, returned: 0});
    await cleanup.retry();
    assert.equal(f.counts().closes, 3);
    f.scratch.passed();
  });
}

test('bounded original pre-acquisition failure keeps its identity and has no FD duty', async t => {
  const primary = Object.freeze(new Error('original open refusal'));
  const unopened = await fixture(t, {openFailure: primary});
  await assert.rejects(unopened.read(), error => error === primary);
  assert.deepEqual(unopened.counts(), {opens: 1, reads: 0, closes: 0, retired: 1, returned: 0});
  assert.equal(primary.cleanupHandle, undefined);
  unopened.scratch.passed();
});

test('actual Store original binding keeps its read count through false close and close-only retry', async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'bounded-store-ack-', label: 'same Store metadata FD acknowledgement'});
  const directory = join(scratch.path, 'store'), path = join(directory, 'store.json');
  const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  // Real Store/FD/ownership and the existing Core storage-binding codec.
  // This observation still issues no Run/resource/Model admission or grant.
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: `sha256:${createHash('sha256').update('original metadata FD').digest('hex')}`,
    privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32}, runtimeCore(moon).publicationControl);
  const originalOpen = fs.open;
  let original, nativeClose, failure, blocked = true, opens = 0, closes = 0;
  fs.open = async (...args) => {
    const handle = await Reflect.apply(originalOpen, fs, args);
    if (args[0] !== path) return handle;
    opens++;
    assert.equal(original, undefined, 'pending original binding cannot open a replacement read');
    original = handle;
    nativeClose = handle.close.bind(handle);
    handle.close = async () => {
      closes++;
      return blocked ? false : nativeClose();
    };
    return handle;
  };
  syncBuiltinESMExports();
  t.after(async () => {
    blocked = false;
    fs.open = originalOpen;
    syncBuiltinESMExports();
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    if (original?.fd >= 0) await nativeClose();
    if (!store.status().closed) await store.close();
  });
  await assert.rejects(store.observeOriginalModelStorageBinding(), error => {
    failure = error;
    return error.cleanupPending === true;
  });
  assert(original.fd >= 0);
  assert.equal(opens, 1);
  await assert.rejects(store.observeOriginalModelStorageBinding(), {code: 'PublicationStoreCleanupPending'});
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(store.status().closed, false);
  assert.equal(closes, 1, 'Store close cannot pretend that a pending caller FD retired');
  const cleanup = failure.cleanupHandle;
  await assert.rejects(cleanup.retry(), {code: 'PublicationMetadataReaderCleanupPending'});
  assert.equal(cleanup.status().pending, true);
  assert.equal(opens, 1);
  blocked = false;
  await cleanup.retry();
  assert.equal(original.fd, -1);
  assert.equal(closes, 3);
  fs.open = originalOpen;
  syncBuiltinESMExports();
  assert.ok(await store.observeOriginalModelStorageBinding(), 'normal new observation resumes only after retirement');
  await store.close();
  assert.equal(store.status().closed, true);
  scratch.passed();
});
