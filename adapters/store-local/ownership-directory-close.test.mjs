// Fresh real Store and directory FD; no historical namespace or Run is opened.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

async function fixture(t, mode, failSync = false) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'ownership-directory-close-', label: 'same Store retirement directory FD'});
  const directory = join(scratch.path, 'store');
  const configuration = {directory, privateEvidenceKey: Buffer.alloc(32, 7),
    storeAuthorityCid: `sha256:${'a'.repeat(64)}`,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32};
  const control = createPublicationContractControlFixture();
  const from = Buffer.from;
  let ownedKey;
  Buffer.from = function(value, ...args) {
    const copy = Reflect.apply(from, this, [value, ...args]);
    if (value === configuration.privateEvidenceKey) ownedKey = copy;
    return copy;
  };
  let store;
  try { store = await openLocalPublicationStore(configuration, control); }
  finally { Buffer.from = from; }
  const open = fs.open;
  const closeFailure = Object.freeze(new Error('OriginalRetirementDirectoryCloseFailure'));
  const syncFailure = Object.freeze(new Error('OriginalRetirementDirectorySyncFailure'));
  let original, closeOriginal, next, allowClose = false;
  let opens = 0, syncs = 0, closes = 0;
  fs.open = async (...args) => {
    const handle = await Reflect.apply(open, fs, args);
    if (args[0] !== directory) return handle;
    opens++;
    if (original !== undefined) return handle;
    original = handle;
    const sync = handle.sync.bind(handle);
    closeOriginal = handle.close.bind(handle);
    handle.sync = async () => {
      syncs++;
      if (failSync) throw syncFailure;
      return sync();
    };
    handle.close = async () => {
      closes++;
      if (!allowClose) {
        if (mode === 'false') return false;
        throw closeFailure;
      }
      return closeOriginal();
    };
    return handle;
  };
  syncBuiltinESMExports();
  t.after(async () => {
    allowClose = true;
    fs.open = open;
    syncBuiltinESMExports();
    if (original !== undefined) await closeOriginal();
    if (next !== undefined && !next.status().closed) await next.close();
    if (!store.status().closed) await store.close();
    scratch.passed();
  });
  return {scratch, directory, store, ownedKey, closeFailure, syncFailure,
    original: () => original, counts: () => ({opens, syncs, closes}),
    allowClose: () => { allowClose = true; },
    successor: async () => { next = await openLocalPublicationStore(configuration, control); return next; }};
}

for (const mode of ['false', 'reject']) {
  test(`retirement ${mode} directory close retains the same FD and original key`, async t => {
    const f = await fixture(t, mode);
    const first = f.store.close();
    assert.equal(first, f.store.close());
    await assert.rejects(first, error => mode === 'false'
      ? error.code === 'PublicationStoreCleanupPending' : error === f.closeFailure);
    assert.equal(f.store.status().closed, false);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
    await f.original().stat();
    assert.deepEqual(f.counts(), {opens: 1, syncs: 1, closes: 1});
    f.allowClose();
    const retry = f.store.close();
    assert.equal(retry, f.store.close());
    assert.equal(await retry, true);
    await assert.rejects(f.original().stat(), {code: 'EBADF'});
    assert.deepEqual(f.counts(), {opens: 1, syncs: 1, closes: 2});
    assert.deepEqual(f.ownedKey, Buffer.alloc(32));
    assert.equal(await f.store.close(), true);
    assert.deepEqual(f.counts(), {opens: 1, syncs: 1, closes: 2});
    f.scratch.passed();
  });

  test(`failed sync plus ${mode} close retains both causes until original FD retires`, async t => {
    const f = await fixture(t, mode, true);
    await assert.rejects(f.store.close(), error => {
      assert.equal(error.primaryFailure, f.syncFailure);
      assert.equal(error.cause, f.syncFailure);
      if (mode === 'reject') assert.equal(error.cleanupError, f.closeFailure);
      if (mode === 'false') assert.equal(error.cleanupError.code, 'PublicationStoreCleanupPending');
      return true;
    });
    await f.original().stat();
    assert.equal(f.store.status().closed, false);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
    f.allowClose();
    assert.equal(await f.store.close(), true);
    await assert.rejects(f.original().stat(), {code: 'EBADF'});
    assert.deepEqual(f.counts(), {opens: 2, syncs: 1, closes: 2},
      'close the failed FD first; a failed sync still requires fresh original-root durability');
    assert.deepEqual(f.ownedKey, Buffer.alloc(32));
    f.scratch.passed();
  });
}

test('pending old retirement directory close cannot remove a healthy successor', async t => {
  const f = await fixture(t, 'reject');
  await assert.rejects(f.store.close(), error => error === f.closeFailure);
  const successor = await f.successor();
  const path = join(f.directory, 'owner', 'owner.json');
  const bytes = await fs.readFile(path), before = await fs.lstat(path);
  f.allowClose();
  assert.equal(await f.store.close(), true);
  await assert.rejects(f.original().stat(), {code: 'EBADF'});
  assert.deepEqual(await fs.readFile(path), bytes);
  assert.equal((await fs.lstat(path)).ino, before.ino);
  assert.equal(successor.status().closed, false);
  await successor.close();
  f.scratch.passed();
});
