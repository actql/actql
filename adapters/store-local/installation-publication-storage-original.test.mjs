// Actual Store/contract FD/currentness and same-handle cleanup. Contract control
// and key/capacity are explicit fixtures; no semantic issuer or funding claim.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const authority = cid('original installation publication Store fixture');

async function fixture(t, {key = Buffer.alloc(32, 7)} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'installation-storage-original-', label: 'original installation publication Store',
  });
  const directory = join(scratch.path, 'store');
  const control = {...createPublicationContractControlFixture(),
    sealRunEvidence() { throw new Error('ModelOrRunEvidenceMustNotBeIssued'); }};
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: authority, privateEvidenceKey: key === null ? undefined : key,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32}, control);
  t.after(async () => {
    if (!store.status().closed) assert.equal(await store.close(), true);
  });
  return {store, scratch, contractPath: join(directory, 'store.json')};
}

test('original installation observation projects exact Store DATA without Model evidence', async t => {
  const f = await fixture(t);
  const before = f.store.status();
  const handle = await f.store.observeOriginalInstallationPublicationStorageBinding();
  assert.deepEqual(handle, {kind: 'installation-publication-storage-binding'});
  assert.equal(Object.isFrozen(handle), true);
  const evidence = f.store.originalInstallationPublicationStorageBindingEvidence(handle);
  assert.equal(Object.isFrozen(evidence), true);
  assert.deepEqual(evidence, {storeContractWire: await readFile(f.contractPath, 'utf8'),
    storeAuthorityCid: authority, keyGenerationCid: cid(Buffer.alloc(32, 7)),
    privateNamespace: 'publication-private'});
  assert.equal(await f.store.observeOriginalInstallationPublicationStorageBinding(), handle);
  assert.equal(f.store.originalInstallationPublicationStorageBindingEvidence(handle), evidence);
  assert.deepEqual(f.store.status(), before, 'observation neither reserves nor stores a publication');
  assert.equal(await f.store.close(), true);
  assert.throws(() => f.store.originalInstallationPublicationStorageBindingEvidence(handle),
    {code: 'PublicationStoreClosed'});
  await assert.rejects(f.store.observeOriginalInstallationPublicationStorageBinding(),
    {code: 'PublicationStoreClosed'});
  // Escaped DATA remains inspectable; close is not an acknowledgement of its
  // String/backing aliases or permission to use a retired original Store.
  assert.equal(evidence.privateNamespace, 'publication-private');
  f.scratch.passed();
});

test('copied and equal foreign Store handles cannot replace original membership', async t => {
  const a = await fixture(t), b = await fixture(t);
  const first = await a.store.observeOriginalInstallationPublicationStorageBinding();
  const second = await b.store.observeOriginalInstallationPublicationStorageBinding();
  assert.deepEqual(a.store.originalInstallationPublicationStorageBindingEvidence(first),
    b.store.originalInstallationPublicationStorageBindingEvidence(second));
  for (const handle of [undefined, {...first}, second, {kind: 'model-original-storage-binding'}]) {
    assert.throws(() => a.store.originalInstallationPublicationStorageBindingEvidence(handle),
      {code: 'ForeignOriginalInstallationPublicationStorageBinding'});
  }
  assert.equal(await a.store.close(), true);
  assert.equal(await b.store.close(), true);
  a.scratch.passed(); b.scratch.passed();
});

test('missing Store key never becomes an installation binding or new key supplier', async t => {
  const f = await fixture(t, {key: null});
  await assert.rejects(f.store.observeOriginalInstallationPublicationStorageBinding(),
    {code: 'PublicationPrivateEvidenceKeyUnavailable'});
  assert.throws(() => f.store.originalInstallationPublicationStorageBindingEvidence({}),
    {code: 'ForeignOriginalInstallationPublicationStorageBinding'});
  assert.equal(await f.store.close(), true);
  f.scratch.passed();
});

test('new observation requires exact original Store contract bytes', async t => {
  const f = await fixture(t);
  const original = await readFile(f.contractPath);
  // This fresh diagnostic changes no Run, original provider state or key.
  // Even semantically equal JSON is not the exact original wire here.
  await writeFile(f.contractPath, Buffer.concat([original, Buffer.from('\n')]));
  await assert.rejects(f.store.observeOriginalInstallationPublicationStorageBinding(),
    {code: 'PublicationStoreAuthorityMismatch'});
  await writeFile(f.contractPath, original);
  assert.equal(await f.store.close(), true);
  f.scratch.passed();
});

for (const outcome of ['false', 'reject']) {
  test(`${outcome} Store contract FD close forbids replacement observation until original ACK`, async t => {
    const f = await fixture(t);
    const probe = await open(f.contractPath, 'r');
    const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
    await probe.close();
    let original, nativeClose, cleanup, blocked = true, reads = 0, closes = 0;
    const primary = new Error('OriginalInstallationStoreContractCloseRefused');
    prototype.stat = function(...args) {
      if (original === undefined && new Error().stack.split('\n')[2]?.includes('readBounded')) {
        original = this;
        nativeClose = this.close;
        const read = this.read;
        this.read = function(...readArgs) {
          reads++;
          return Reflect.apply(read, this, readArgs);
        };
        this.close = function(...closeArgs) {
          closes++;
          if (blocked) return outcome === 'false' ? Promise.resolve(false) : Promise.reject(primary);
          return Reflect.apply(nativeClose, this, closeArgs);
        };
      }
      return Reflect.apply(stat, this, args);
    };
    t.after(async () => {
      prototype.stat = stat;
      blocked = false;
      if (cleanup?.status().pending) await cleanup.retry();
      assert(original === undefined || original.fd === -1);
    });
    await assert.rejects(f.store.observeOriginalInstallationPublicationStorageBinding(), error => {
      cleanup = error.cleanupHandle;
      return cleanup?.status().pending === true;
    });
    assert(original.fd >= 0);
    const readCalls = reads;
    await assert.rejects(f.store.observeOriginalInstallationPublicationStorageBinding(),
      {code: 'PublicationStoreCleanupPending'});
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.equal(reads, readCalls);
    await assert.rejects(cleanup.retry());
    assert.equal(cleanup.status().pending, true);
    assert.equal(closes, 2);
    blocked = false;
    await cleanup.retry();
    assert.equal(original.fd, -1);
    assert.equal(closes, 3);
    assert.equal(reads, readCalls, 'same-FD cleanup is close only');
    prototype.stat = stat;
    const handle = await f.store.observeOriginalInstallationPublicationStorageBinding();
    assert.equal(f.store.originalInstallationPublicationStorageBindingEvidence(handle).storeAuthorityCid, authority);
    assert.equal(await f.store.close(), true);
    f.scratch.passed();
  });
}
