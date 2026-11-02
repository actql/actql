import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {mkdtemp, readFile, rename, rm, stat} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {prepareInstalledPublicationRoot} from './installed-publication-root.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';
import {preparePrivateEvidenceKeyInstallation, PRIVATE_EVIDENCE_KEY_FILE}
  from './local-continuation-evidence.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
async function fixture(t) {
  const parent = await mkdtemp(join(tmpdir(), 'actql-publication-private-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const root = join(parent, 'host'), checkpoints = join(root, 'checkpoints');
  const storeAuthorityCid = cid(JSON.stringify({version: 'actql-local-store-owner/0.1',
    root, principalId: 'person'}));
  return {root, checkpoints, storeAuthorityCid,
    keyPath: join(checkpoints, PRIVATE_EVIDENCE_KEY_FILE),
    intentPath: join(checkpoints, 'private-evidence-initialization.json'),
    adoptedPath: join(checkpoints, 'private-evidence-adopted.json'),
    ownerPath: join(root, 'publication', 'owner', 'owner.json')};
}

// Actual normal Journal first-initialization proof and prepared exclusion.
// The Store's schema codec is a test fixture, not an installed-package claim.
async function openLater(f) {
  const originals = {host: {}, installation: {root: f.root}, generation: {},
    supplier() {}, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(originals);
  let installation, store;
  const close = async () => {
    await store?.close();
    installation?.key.fill(0);
    assert.equal((await journal.close()).pending, false);
  };
  try {
    assert.equal(await journal.admitRootFormat(f.root), 'current');
    const ownership = journal.privateEvidenceInitializationOwnership();
    installation = await preparePrivateEvidenceKeyInstallation(f.checkpoints, {
      storeDirectory: join(f.root, 'publication'), storeAuthorityCid: f.storeAuthorityCid,
      preparedOwnership: ownership, assertCurrent: () => journal.assertInitializationCurrent(),
      assertFirstInitialization: () => journal.assertPrivateEvidenceFirstInitialization(),
    });
    return {installation, close, async adopt() {
      store = await openLocalPublicationStore({directory: join(f.root, 'publication'),
        storeAuthorityCid: f.storeAuthorityCid, capacityBytes: 1048576,
        maxObjectBytes: 65536, maxObjects: 32, maxContractNodes: 1000, maxContractDepth: 64,
        privateEvidenceKey: installation?.key}, createPublicationContractControlFixture(),
      undefined, undefined, ownership);
      await installation?.adoptStore(store);
    }};
  } catch (cause) {await close(); throw cause;}
}

test('fresh publication passes its exact private generation to normal Store adoption and reopen', async t => {
  const f = await fixture(t);
  await prepareInstalledPublicationRoot(f.root, 'person');
  const bytes = await readFile(f.keyPath), intent = await readFile(f.intentPath);
  try {
    assert.equal(bytes.length, 32);
    assert.equal((await stat(f.keyPath)).mode & 0o777, 0o600);
    assert.equal(JSON.parse(intent).storeAuthorityCid, f.storeAuthorityCid);
    await assert.rejects(stat(f.adoptedPath), {code: 'ENOENT'});
    await assert.rejects(stat(join(f.root, 'account', 'account.json')), {code: 'ENOENT'});
    for (let attempt = 0; attempt < 2; attempt++) {
      const host = await openLater(f);
      try {
        assert.equal(host.installation.keyId, cid(bytes));
        assert.equal(host.installation.key.equals(bytes), true);
        await host.adopt();
      } finally {await host.close();}
    }
    assert.equal((await readFile(f.keyPath)).equals(bytes), true);
    assert.deepEqual(await readFile(f.intentPath), intent);
  } finally {bytes.fill(0);}
});

test('current publication confers no first-key authority', async t => {
  const f = await fixture(t);
  await admitHostRootFormat(f.root);
  await prepareInstalledPublicationRoot(f.root, 'person');
  const host = await openLater(f);
  try {assert.equal(host.installation, undefined);}
  finally {await host.close();}
  await assert.rejects(stat(f.keyPath), {code: 'ENOENT'});
  await assert.rejects(stat(f.intentPath), {code: 'ENOENT'});
});

test('post-publication continuation failure retains the same pending private generation', async t => {
  const f = await fixture(t), primary = new Error('later provider failure');
  await assert.rejects((async () => {
    await prepareInstalledPublicationRoot(f.root, 'person');
    throw primary;
  })(), error => error === primary);
  const savedId = JSON.parse(await readFile(f.intentPath)).keyId;
  await prepareInstalledPublicationRoot(f.root, 'person');
  const host = await openLater(f);
  try {assert.equal(host.installation.keyId, savedId); await host.adopt();}
  finally {await host.close();}
});

test('missing pending original key is refused without replacement by publication or normal startup', async t => {
  const f = await fixture(t);
  await prepareInstalledPublicationRoot(f.root, 'person');
  const intent = await readFile(f.intentPath);
  await rename(f.keyPath, f.keyPath + '.test-owned-original');
  await prepareInstalledPublicationRoot(f.root, 'person');
  await assert.rejects(openLater(f), {code: 'PrivateEvidenceKeyUnavailable'});
  await assert.rejects(stat(f.keyPath), {code: 'ENOENT'});
  assert.deepEqual(await readFile(f.intentPath), intent);
});

for (const target of ['intentPath', 'keyPath']) {
  test(`partial private ${target} write retains original FD and exclusion, never generates a replacement`, async t => {
    const f = await fixture(t), originalOpen = fs.promises.open;
    const primary = new Error('original partial private initialization write');
    let canClose = false, writes = 0, replacementCloses = 0, failure, held;
    fs.promises.open = async function(path, ...args) {
      const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
      if (path === f[target] && args[0] === 'wx') {
        held = handle;
        const close = handle.close, write = handle.writeFile;
        handle.writeFile = async function(bytes) {
          writes++; await Reflect.apply(write, handle, [bytes.subarray(0, 3)]); throw primary;
        };
        handle.close = async function() {
          if (!canClose) throw new Error('original private FD close pending');
          return Reflect.apply(close, handle, []);
        };
      }
      return handle;
    };
    syncBuiltinESMExports();
    try {
      await assert.rejects(prepareInstalledPublicationRoot(f.root, 'person'), error => {
        failure = error; return error.cleanupHandle.status().pending;
      });
      assert.equal(failure.primaryFailure.cause, primary);
      const owner = await readFile(f.ownerPath);
      held.close = () => {replacementCloses++; throw new Error('replacement close must not run');};
      await failure.cleanupHandle.retry();
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.deepEqual(await readFile(f.ownerPath), owner);
      canClose = true;
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(writes, 1); assert.equal(replacementCloses, 0);
      assert.equal((await stat(f[target])).size, 3);
      await assert.rejects(held.stat(), {code: 'EBADF'});
      await prepareInstalledPublicationRoot(f.root, 'person');
      await assert.rejects(openLater(f), {code: target === 'intentPath'
        ? 'InvalidPrivateEvidenceInstallation' : 'InvalidPrivateEvidenceKey'});
      assert.equal((await stat(f[target])).size, 3);
      assert.equal(writes, 1);
    } finally {
      canClose = true; await failure?.cleanupHandle.retry();
      fs.promises.open = originalOpen; syncBuiltinESMExports();
    }
  });
}

// An older Account-only publication is existing state, not fresh-key proof.
test('a saved Account intent cannot authorize a missing private-key generation', async t => {
  const f = await fixture(t);
  const rootCreation = await admitHostRootFormat(f.root);
  const original = await prepareLocalPublicationStoreOwnership(join(f.root, 'publication'));
  try {
    await prepareOrdinaryLocalAccount({root: f.root, principal: 'person',
      preparedOriginal: original, rootCreation});
  } finally {
    assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  }
  const accountIntent = await readFile(join(f.root, 'account-initialization.json'));
  await prepareInstalledPublicationRoot(f.root, 'person');
  const host = await openLater(f);
  try {assert.equal(host.installation, undefined);}
  finally {await host.close();}
  await assert.rejects(stat(f.keyPath), {code: 'ENOENT'});
  assert.deepEqual(await readFile(join(f.root, 'account-initialization.json')), accountIntent);
});

test('publication clears its loaded private key bytes before returning', async t => {
  const f = await fixture(t), originalOpen = fs.promises.open;
  let loaded;
  fs.promises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (path === f.keyPath && typeof args[0] === 'number') {
      const read = handle.read;
      handle.read = async function(buffer, ...rest) {
        const result = await Reflect.apply(read, handle, [buffer, ...rest]);
        if (buffer.byteLength === 32) loaded = buffer;
        return result;
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    await prepareInstalledPublicationRoot(f.root, 'person');
    assert.equal(loaded?.byteLength, 32);
    assert.equal(loaded.every(byte => byte === 0), true);
    assert.equal((await stat(f.keyPath)).size, 32);
  } finally {
    loaded?.fill(0);
    fs.promises.open = originalOpen; syncBuiltinESMExports();
  }
});

test('an unobserved original key close retains custody until that same method can be captured', async t => {
  const f = await fixture(t), originalOpen = fs.promises.open;
  const primary = new Error('original key close observation unavailable');
  let observable = false, failure, writes = 0, handle;
  fs.promises.open = async function(path, ...args) {
    const original = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (path !== f.keyPath || args[0] !== 'wx') return original;
    handle = original;
    const close = original.close, write = original.writeFile;
    original.writeFile = async function(...values) {writes++; return Reflect.apply(write, original, values);};
    Object.defineProperty(original, 'close', {configurable: true, get() {
      if (!observable) throw primary;
      return close;
    }});
    return original;
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(prepareInstalledPublicationRoot(f.root, 'person'), error => {
      failure = error; return error.cleanupHandle.status().pending;
    });
    const owner = await readFile(f.ownerPath);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(await readFile(f.ownerPath), owner);
    assert.equal(writes, 0);
    observable = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await assert.rejects(handle.stat(), {code: 'EBADF'});
    await prepareInstalledPublicationRoot(f.root, 'person');
    await assert.rejects(openLater(f), {code: 'InvalidPrivateEvidenceKey'});
    assert.equal(writes, 0);
    assert.equal((await stat(f.keyPath)).size, 0);
  } finally {
    observable = true; await failure?.cleanupHandle.retry();
    fs.promises.open = originalOpen; syncBuiltinESMExports();
  }
});
