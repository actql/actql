// Actual Store, original ownership inode/token and native directory sync.
// Only one selected retirement syscall fails; no historical namespace is used.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

async function fixture(t, mode) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'ownership-retirement-phase-', label: 'same Store ownership retirement phase'});
  const directory = join(scratch.path, 'store'), owner = join(directory, 'owner');
  const record = join(owner, 'owner.json'), key = Buffer.alloc(32, 7);
  const control = createPublicationContractControlFixture();
  const configuration = {directory, privateEvidenceKey: key,
    storeAuthorityCid: `sha256:${createHash('sha256').update('same original retirement').digest('hex')}`,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32};
  const from = Buffer.from;
  let ownedKey;
  Buffer.from = function(value, ...args) {
    const copy = Reflect.apply(from, this, [value, ...args]);
    if (value === key) ownedKey = copy;
    return copy;
  };
  let store;
  try { store = await openLocalPublicationStore(configuration, control); }
  finally { Buffer.from = from; }
  const qualified = JSON.parse(await fs.readFile(record)).leaseAnchor !== undefined;
  const originalOpen = fs.open, originalRmdir = fs.rmdir;
  const primary = Object.freeze(Object.assign(new Error('original directory retirement failed'), {code: 'EIO'}));
  let armed = true, newStore, rootSyncs = 0, directoryCloses = 0;
  fs.rmdir = async (...args) => {
    if (armed && mode === 'rmdir' && args[0] === owner) {
      armed = false;
      throw primary;
    }
    return Reflect.apply(originalRmdir, fs, args);
  };
  fs.open = async (...args) => {
    const handle = await Reflect.apply(originalOpen, fs, args);
    if (args[0] !== directory) return handle;
    const sync = handle.sync.bind(handle), close = handle.close.bind(handle);
    handle.sync = async () => {
      rootSyncs++;
      if (armed && mode === 'sync') { armed = false; throw primary; }
      return sync();
    };
    handle.close = async () => { directoryCloses++; return close(); };
    return handle;
  };
  syncBuiltinESMExports();
  t.after(async () => {
    armed = false;
    fs.open = originalOpen;
    fs.rmdir = originalRmdir;
    syncBuiltinESMExports();
    if (newStore !== undefined && !newStore.status().closed) await newStore.close();
    if (!store.status().closed) {
      try { await store.close(); }
      catch { t.diagnostic(`Original failed retirement retained without reconstructing owner: ${directory}`); }
    }
  });
  return {scratch, directory, owner, record, store, primary, ownedKey, key, qualified,
    counts: () => ({rootSyncs, directoryCloses}),
    async successor() { newStore = await openLocalPublicationStore(configuration, control); return newStore; }};
}

for (const phase of ['rmdir', 'sync']) {
  test(`same original ownership resumes after ${phase} failed beyond owner-record unlink`, async t => {
    const f = await fixture(t, phase);
    const close = f.store.close();
    assert.equal(f.store.close(), close);
    await assert.rejects(close, error => error === f.primary);
    await assert.rejects(fs.readFile(f.record), {code: 'ENOENT'});
    assert.equal(f.store.status().closed, false);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
    await assert.rejects(f.store.observeOriginalModelStorageBinding(), {code: 'PublicationStoreClosed'});
    const retry = f.store.close();
    assert.equal(f.store.close(), retry, 'the same Store still owns one close flight');
    assert.equal(await retry, true);
    assert.equal(f.store.status().closed, true);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32));
    assert.deepEqual(f.key, Buffer.alloc(32, 7), 'only the original owned key copy retires');
    await assert.rejects(fs.lstat(f.owner), {code: 'ENOENT'});
    assert.equal(f.counts().rootSyncs, phase === 'sync' ? 2 : 1);
    assert.equal(f.counts().directoryCloses, f.counts().rootSyncs);
    assert.equal(await f.store.close(), true);
    assert.equal(f.counts().rootSyncs, phase === 'sync' ? 2 : 1);
    f.scratch.passed();
  });
}

test('retiring old ownership never unlinks a healthy successor after original directory removal', async t => {
  const f = await fixture(t, 'sync');
  await assert.rejects(f.store.close(), error => error === f.primary);
  await assert.rejects(fs.lstat(f.owner), {code: 'ENOENT'});
  if (f.qualified) {
    await assert.rejects(f.successor(), {code: 'PublicationStoreBusy'});
    assert.equal(await f.store.close(), true, 'the original lease drains before handing ownership to a successor');
  }
  const next = await f.successor();
  const bytes = await fs.readFile(f.record), before = await fs.lstat(f.record);
  assert.equal(await f.store.close(), true);
  assert.deepEqual(await fs.readFile(f.record), bytes);
  const after = await fs.lstat(f.record);
  assert.equal(after.dev, before.dev);
  assert.equal(after.ino, before.ino);
  assert.equal(next.status().closed, false);
  const writer = next.createPreparedObjectWriter(3);
  await writer.append('abc');
  const physical = await writer.seal(`sha256:${createHash('sha256').update('abc').digest('hex')}`);
  await physical.prepared.release();
  await next.close();
  f.scratch.passed();
});

test('pending original retirement refuses a replacement ownership directory', async t => {
  const f = await fixture(t, 'rmdir');
  await assert.rejects(f.store.close(), error => error === f.primary);
  const saved = join(f.scratch.path, 'same-original-owner');
  await fs.rename(f.owner, saved);
  await fs.mkdir(f.owner);
  const replacement = await fs.lstat(f.owner);
  try {
    await assert.rejects(f.store.close(), {code: 'PublicationStoreOwnershipLost'});
    assert.equal((await fs.lstat(f.owner)).ino, replacement.ino);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
  } finally {
    // Only this known-empty disposable replacement is removed. Restore the
    // original directory inode, never manufacture its removed owner record.
    await fs.rmdir(f.owner);
    await fs.rename(saved, f.owner);
  }
  assert.equal(await f.store.close(), true);
  f.scratch.passed();
});

test('pending old root durability cannot retire against a replacement Store directory', async t => {
  const f = await fixture(t, 'sync');
  await assert.rejects(f.store.close(), error => error === f.primary);
  const saved = join(f.scratch.path, 'same-original-root');
  await fs.rename(f.directory, saved);
  await fs.mkdir(f.directory);
  const replacement = await fs.lstat(f.directory);
  try {
    await assert.rejects(f.store.close(), {code: 'PublicationStoreOwnershipLost'});
    assert.equal((await fs.lstat(f.directory)).ino, replacement.ino);
    assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
    assert.equal(f.counts().rootSyncs, 1, 'foreign root must not receive old durability I/O');
  } finally {
    await fs.rmdir(f.directory);
    await fs.rename(saved, f.directory);
  }
  assert.equal(await f.store.close(), true);
  f.scratch.passed();
});

for (const target of ['owner', 'directory']) {
  test(`initially absent ${target} cannot acknowledge original ownership retirement`, async t => {
    const f = await fixture(t, 'none');
    const path = f[target], saved = join(f.scratch.path, 'same-original-directory');
    await fs.rename(path, saved);
    try {
      await assert.rejects(f.store.close(), {code: 'PublicationStoreOwnershipLost'});
      assert.equal(f.store.status().closed, false);
      assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
    } finally { await fs.rename(saved, path); }
    assert.equal(await f.store.close(), true);
    f.scratch.passed();
  });
}
