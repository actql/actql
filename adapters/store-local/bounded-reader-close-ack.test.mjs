// Actual bounded metadata reader and native FD. Only close/read outcomes are
// controlled; no historical Store, Run, provider, permission or lease is used.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {readBoundedLocalMetadata} from './publication-store.mjs';

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

test('bounded original pre-acquisition failure keeps its identity and has no FD duty', async t => {
  const primary = Object.freeze(new Error('original open refusal'));
  const unopened = await fixture(t, {openFailure: primary});
  await assert.rejects(unopened.read(), error => error === primary);
  assert.deepEqual(unopened.counts(), {opens: 1, reads: 0, closes: 0, retired: 1, returned: 0});
  assert.equal(primary.cleanupHandle, undefined);
  unopened.scratch.passed();
});
