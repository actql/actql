// Fresh actual Store directory FDs and keys. No existing Run, namespace,
// credential, provider or historical custody is opened by these controls.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
  prefix: 'opening-directory-close-', label: 'original Store opening directory FDs'});
after(() => scratch.passed());

async function fixture(t, phase, mode, syncFailure = false) {
  const isolated = await fs.mkdtemp(join(scratch.path, 'case-'));
  const directory = join(isolated, 'store'), ownerDirectory = join(directory, 'owner');
  const key = Buffer.alloc(32, 7);
  const configuration = {directory, privateEvidenceKey: key,
    storeAuthorityCid: `sha256:${'a'.repeat(64)}`, capacityBytes: 65536,
    maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32};
  const control = createPublicationContractControlFixture();
  const closeFailure = Object.freeze(new Error('OriginalOpeningDirectoryClose'));
  const syncError = Object.freeze(new Error('OriginalOpeningDirectorySync'));
  const open = fs.open, from = Buffer.from;
  let original, originalClose, allow = false, store, failure, ownedKey, ownerBytes;
  let syncs = 0, closes = 0, selectedOpens = 0, ownerMetadataPath;
  Buffer.from = function(value, ...args) {
    const bytes = Reflect.apply(from, this, [value, ...args]);
    if (value === key) ownedKey = bytes;
    return bytes;
  };
  fs.open = async (...args) => {
    const handle = await Reflect.apply(open, fs, args);
    const acquisition = new Error().stack.includes('acquireStoreOwnership');
    const staged = typeof args[0] === 'string' && args[0].startsWith(directory + '/.owner-opening-') && !args[0].slice((directory + '/.owner-opening-').length).includes('/');
    const selected = phase === 'owner' ? (args[0] === ownerDirectory || staged) && acquisition
      : args[0] === directory && (phase === 'owned-root' ? acquisition : !acquisition);
    if (!selected) return handle;
    selectedOpens++;
    if (original !== undefined) return handle;
    original = handle;
    if (phase !== 'format-root') {
      ownerMetadataPath = join(phase === 'owner' ? args[0] : ownerDirectory, 'owner.json');
      ownerBytes = await fs.readFile(ownerMetadataPath);
    }
    const sync = handle.sync.bind(handle);
    originalClose = handle.close.bind(handle);
    handle.sync = async () => {
      syncs++;
      if (syncFailure) throw typeof syncFailure === 'object' ? syncFailure.value : syncError;
      return sync();
    };
    handle.close = async () => {
      closes++;
      if (!allow) {
        if (mode === 'false') return false;
        throw closeFailure;
      }
      return originalClose();
    };
    return handle;
  };
  syncBuiltinESMExports();
  const restore = () => { fs.open = open; Buffer.from = from; syncBuiltinESMExports(); };
  t.after(async () => {
    allow = true; restore();
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    if (original !== undefined) await originalClose();
    if (store !== undefined && !store.status().closed) await store.close();
    // A pre-fix rejected opener exports neither its owner nor its FD. Drain
    // only this fresh diagnostic's FD above, then remove its observed original
    // record under the test-owned scratch, never an old/foreign owner.
    if (store === undefined && ownerBytes !== undefined) {
      const path = ownerMetadataPath;
      try {
        const current = await fs.readFile(path);
        assert.deepEqual(current, ownerBytes);
        assert.equal(JSON.parse(current).pid, process.pid);
        await fs.unlink(path); await fs.rmdir(phase === 'owner' ? path.slice(0, -'/owner.json'.length) : ownerDirectory);
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    ownedKey?.fill(0);
  });
  return {configuration, control, closeFailure, syncError, restore,
    open: async () => {
      try { store = await openLocalPublicationStore(configuration, control); return store; }
      catch (error) { failure = error; throw error; }
      finally { Buffer.from = from; }
    },
    original: () => original, key: () => ownedKey,
    counts: () => ({syncs, closes, selectedOpens}), allow: () => { allow = true; },
    ownerPath: join(ownerDirectory, 'owner.json')};
}

for (const mode of ['false', 'reject']) {
  for (const value of [null, undefined]) {
    test(`thrown ${value} sync plus ${mode} close cannot mask original FD custody`, async t => {
      const f = await fixture(t, 'owner', mode, {value});
      let failure;
      await assert.rejects(f.open(), error => {
        failure = error;
        assert.equal(Object.hasOwn(error, 'primaryFailure'), true);
        assert.equal(error.primaryFailure, value);
        assert.equal(error.cleanupHandle.status().pending, true);
        return true;
      });
      await f.original().stat();
      assert.deepEqual(f.key(), Buffer.alloc(32, 7));
      f.allow();
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      await assert.rejects(f.original().stat(), {code: 'EBADF'});
      assert.equal(f.counts().syncs, 1);
      assert.deepEqual(f.key(), Buffer.alloc(32));
    });
  }
}

for (const kind of ['readonly-pending', 'inherited-handle', 'inherited-pending-setter']) {
  test(`opening sync failure with ${kind} preserves primary and exports original FD`, async t => {
    const prior = Object.freeze({original: 'prior diagnostic facet'});
    class OriginalError extends Error {}
    if (kind === 'inherited-handle') Object.defineProperty(OriginalError.prototype,
      'cleanupHandle', {value: prior});
    if (kind === 'inherited-pending-setter') Object.defineProperty(OriginalError.prototype,
      'cleanupPending', {get() { return false; }, set() {}});
    const primary = new OriginalError('OriginalOpeningSync');
    if (kind === 'readonly-pending') Object.defineProperty(primary, 'cleanupPending', {value: false});
    const f = await fixture(t, 'owner', 'reject', {value: primary});
    let failure;
    await assert.rejects(f.open(), error => {
      failure = error;
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.cleanupHandle.status().pending, true);
      if (kind === 'inherited-handle') assert.equal(primary.cleanupHandle, prior);
      if (kind === 'readonly-pending') assert.equal(primary.cleanupPending, false);
      if (kind === 'inherited-pending-setter') {
        assert.equal(Object.hasOwn(primary, 'cleanupPending'), true);
        assert.equal(primary.cleanupPending, true);
      }
      return true;
    });
    await f.original().stat();
    f.allow();
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await assert.rejects(f.original().stat(), {code: 'EBADF'});
    assert.equal(f.counts().syncs, 1);
  });
}

for (const mode of ['false', 'reject']) {
  for (const phase of ['format-root', 'owner', 'owned-root']) {
    test(`${phase} ${mode} close exports its same FD and initialization custody`, async t => {
      const f = await fixture(t, phase, mode);
      let failure;
      await assert.rejects(f.open(), error => {
        failure = error;
        assert.equal(error.cleanupPending, true);
        assert.equal(error.cleanupHandle.status().pending, true);
        return true;
      });
      await f.original().stat();
      assert.equal(f.counts().syncs, 1);
      assert.deepEqual(f.key(), Buffer.alloc(32, 7), 'pending opener retains its original key');
      const before = f.counts();
      const retry = failure.cleanupHandle.retry();
      assert.equal(retry, failure.cleanupHandle.retry());
      await assert.rejects(retry, error => mode === 'reject' ? error === f.closeFailure
        : error.code === 'PublicationDirectorySyncCleanupPending');
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.deepEqual(f.counts(), {...before, closes: before.closes + 1});
      if (phase !== 'format-root') {
        await assert.rejects(openLocalPublicationStore(f.configuration, f.control),
          {code: 'PublicationStoreBusy'});
      }
      f.allow();
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      await assert.rejects(f.original().stat(), {code: 'EBADF'});
      assert.equal(f.counts().syncs, 1, 'cleanup must never repeat the failed initialization sync');
      assert.deepEqual(f.key(), Buffer.alloc(32), 'key retirement follows original cleanup');
      await assert.rejects(fs.readFile(f.ownerPath), {code: 'ENOENT'});
      const settled = f.counts();
      await failure.cleanupHandle.retry();
      assert.deepEqual(f.counts(), settled);
      f.restore();
      const healthy = await openLocalPublicationStore(f.configuration, f.control);
      await healthy.close();
    });
  }

  test(`failed owner sync plus ${mode} close retains the original primary and FD`, async t => {
    const f = await fixture(t, 'owner', mode, true);
    let failure;
    await assert.rejects(f.open(), error => {
      failure = error;
      assert.equal(error.primaryFailure, f.syncError);
      assert.equal(error.cleanupHandle.status().pending, true);
      return true;
    });
    await f.original().stat();
    f.allow();
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(f.key(), Buffer.alloc(32));
    assert.equal(f.counts().syncs, 1);
    await assert.rejects(f.original().stat(), {code: 'EBADF'});
  });
}
