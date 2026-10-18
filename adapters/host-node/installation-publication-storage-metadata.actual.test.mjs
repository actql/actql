// Actual Common/Store consumer. Key/capacity/current are explicit fixtures;
// no authenticated installation metadata publication or cold adoption is claimed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createInstallationPublicationStorageMetadata} from
  '../host-common/installation-publication-storage-metadata.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

const runtimePath = process.env.ACTQL_TEST_INSTALLATION_STORAGE_RUNTIME;
assert.equal(typeof runtimePath, 'string', 'An exact matching runtime is required');
const moon = await import(pathToFileURL(runtimePath).href);
const control = runtimeCore(moon).publicationControl;
const authority = 'sha256:' + '1'.repeat(64);
const cid = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const bounds = Object.freeze({maxWireBytes: 2048, maxNodes: 32, maxDepth: 2});

async function fixture(t, options = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'installation-storage-common-', label: 'actual Common installation storage metadata'});
  const directory = join(scratch.path, 'store');
  const key = Buffer.alloc(32, 7);
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: authority,
    privateEvidenceKey: options.missingKey ? undefined : key,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32}, control);
  t.after(async () => {
    if (!store.status().closed) assert.equal(await store.close(), true);
    key.fill(0);
  });
  return {store, key, scratch, contractPath: join(directory, 'store.json'),
    metadata: createInstallationPublicationStorageMetadata(moon, store,
      options.bounds ?? bounds, options.assertCurrent ?? (() => {}))};
}

test('same actual Store projects one Common binding with exact retained contract and purpose', async t => {
  const f = await fixture(t), view = f.metadata, before = f.store.status();
  assert.throws(() => view.binding(), {code: 'InstallationPublicationStorageUnobserved'});
  assert.equal(await view.observe(), view);
  const binding = view.binding(), wire = view.wire();
  assert.equal(await view.observe(), view);
  assert.equal(view.binding(), binding, 're-observation does not issue a replacement DATA original');
  assert.equal(view.wire(), wire);
  assert.equal(view.cid(), cid(wire));
  assert.equal(wire, JSON.stringify({key_generation_cid: cid(f.key),
    private_namespace: 'publication-private', store_authority_cid: authority,
    store_contract_wire: await readFile(f.contractPath, 'utf8'),
    version: 'actql-installation-publication-storage-binding/0.1'}));
  assert.deepEqual(f.store.status(), before, 'DATA observation allocates no Store holding or reservation');
  assert.equal(view.forget(), false, 'the live original Store still owns its duties');
  assert.equal(await f.store.close(), true);
  assert.equal(view.forget(), true);
  assert.throws(() => view.binding(), {code: 'InstallationPublicationStorageMetadataForgotten'});
  assert.throws(() => view.wire(), {code: 'InstallationPublicationStorageMetadataForgotten'});
  assert.equal(typeof binding, 'object', 'escaped DATA is not a physical retirement ACK');
  f.scratch.passed();
});

test('copied metadata receiver and equal foreign Store DATA cannot replace original references', async t => {
  const a = await fixture(t), b = await fixture(t);
  await a.metadata.observe(); await b.metadata.observe();
  assert.equal(a.metadata.cid(), b.metadata.cid());
  assert.notEqual(a.metadata.binding(), b.metadata.binding());
  for (const receiver of [undefined, {...a.metadata}, b.metadata]) {
    assert.throws(() => Reflect.apply(a.metadata.binding, receiver, []),
      {code: 'ForeignInstallationPublicationStorageMetadata'});
    await assert.rejects(Reflect.apply(a.metadata.observe, receiver, []),
      {code: 'ForeignInstallationPublicationStorageMetadata'});
  }
  const original = await a.store.observeOriginalInstallationPublicationStorageBinding();
  assert.throws(() => b.store.originalInstallationPublicationStorageBindingEvidence(original),
    {code: 'ForeignOriginalInstallationPublicationStorageBinding'});
  assert.equal(await a.store.close(), true); assert.equal(await b.store.close(), true);
  assert.equal(a.metadata.forget(), true); assert.equal(b.metadata.forget(), true);
  a.scratch.passed(); b.scratch.passed();
});

test('fresh observation refuses changed Store bytes instead of reconstructing from cached DATA', async t => {
  const f = await fixture(t);
  await f.metadata.observe();
  const wire = await readFile(f.contractPath);
  await writeFile(f.contractPath, Buffer.concat([wire, Buffer.from('\n')]));
  await assert.rejects(f.metadata.observe(), {code: 'PublicationStoreAuthorityMismatch'});
  assert.equal(f.metadata.forget(), false);
  await writeFile(f.contractPath, wire);
  assert.equal(await f.store.close(), true); assert.equal(f.metadata.forget(), true);
  f.scratch.passed();
});

test('original Host current refusal after awaited Store observation leaves Common unissued', async t => {
  let checks = 0;
  const refusal = Object.freeze(Object.assign(new Error('OriginalHostCurrentRefused'),
    {code: 'OriginalHostCurrentRefused'}));
  const f = await fixture(t, {assertCurrent() { if (++checks === 2) throw refusal; }});
  await assert.rejects(f.metadata.observe(), error => error === refusal);
  assert.throws(() => f.metadata.binding(), {code: 'InstallationPublicationStorageUnobserved'});
  assert.equal(f.metadata.forget(), false);
  assert.equal(await f.store.close(), true); assert.equal(f.metadata.forget(), true);
  f.scratch.passed();
});

test('same Store closing during the original after-await fence cannot issue the Common binding', async t => {
  let checks = 0, close;
  const f = await fixture(t, {assertCurrent() { if (++checks === 2) close = f.store.close(); }});
  await assert.rejects(f.metadata.observe(), {code: 'PublicationStoreClosed'});
  assert.equal(await close, true);
  assert.equal(f.metadata.forget(), true);
  f.scratch.passed();
});

test('missing actual key and exhausted Common codec remain refused without a substitute supplier', async t => {
  const absent = await fixture(t, {missingKey: true});
  await assert.rejects(absent.metadata.observe(), {code: 'PublicationPrivateEvidenceKeyUnavailable'});
  const exhausted = await fixture(t, {bounds: {...bounds, maxWireBytes: 1}});
  await assert.rejects(exhausted.metadata.observe(), {code: 'MoonBitHostFailure'});
  assert.throws(() => exhausted.metadata.binding(), {code: 'InstallationPublicationStorageUnobserved'});
  for (const f of [absent, exhausted]) {
    assert.equal(f.metadata.forget(), false);
    assert.equal(await f.store.close(), true); assert.equal(f.metadata.forget(), true);
    f.scratch.passed();
  }
});

test('one original asynchronous observation stays pending without a second read or early forgetting', async t => {
  const f = await fixture(t);
  let release, entered = 0;
  const delayed = Object.freeze({
    status: f.store.status,
    originalInstallationPublicationStorageBindingEvidence:
      f.store.originalInstallationPublicationStorageBindingEvidence,
    async observeOriginalInstallationPublicationStorageBinding() {
      entered++;
      await new Promise(resolve => { release = resolve; });
      return f.store.observeOriginalInstallationPublicationStorageBinding();
    },
  });
  // Only this Promise delay is a fixture. The observed original and all Store
  // read/close actions still come from f.store, not from a synthetic binding.
  const view = createInstallationPublicationStorageMetadata(moon, delayed, bounds, () => {});
  const pending = view.observe();
  assert.equal(entered, 1);
  assert.equal(view.forget(), false);
  await assert.rejects(view.observe(), {code: 'InstallationPublicationStorageObservationPending'});
  assert.equal(entered, 1);
  release(); await pending;
  assert.equal(view.cid(), cid(view.wire()));
  assert.equal(await f.store.close(), true);
  assert.equal(view.forget(), true); assert.equal(f.metadata.forget(), true);
  f.scratch.passed();
});

for (const outcome of ['false', 'reject']) {
  test(`${outcome} original Store FD close retains the same cleanup through the Common caller`, async t => {
    const f = await fixture(t);
    const probe = await open(f.contractPath, 'r');
    const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
    await probe.close();
    let original, nativeClose, cleanup, blocked = true, reads = 0;
    const failure = Object.freeze(new Error('OriginalInstallationStoreCloseRefused'));
    prototype.stat = function(...args) {
      if (original === undefined && new Error().stack.split('\n')[2]?.includes('readBounded')) {
        original = this; nativeClose = this.close;
        const read = this.read;
        this.read = function(...input) { reads++; return Reflect.apply(read, this, input); };
        this.close = function(...input) {
          if (blocked) return outcome === 'false' ? Promise.resolve(false) : Promise.reject(failure);
          return Reflect.apply(nativeClose, this, input);
        };
      }
      return Reflect.apply(stat, this, args);
    };
    t.after(async () => {
      prototype.stat = stat; blocked = false;
      if (cleanup?.status().pending) await cleanup.retry();
      assert(original === undefined || original.fd === -1);
    });
    await assert.rejects(f.metadata.observe(), error => {
      cleanup = error.cleanupHandle;
      return cleanup?.status().pending === true;
    });
    assert(original.fd >= 0);
    assert.equal(f.metadata.forget(), false);
    const readCount = reads;
    await assert.rejects(f.metadata.observe(), {code: 'PublicationStoreCleanupPending'});
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    await assert.rejects(cleanup.retry());
    assert.equal(cleanup.status().pending, true);
    blocked = false; await cleanup.retry();
    assert.equal(original.fd, -1);
    assert.equal(reads, readCount, 'cleanup retries close only, not the contract read');
    prototype.stat = stat;
    await f.metadata.observe();
    assert.equal(await f.store.close(), true); assert.equal(f.metadata.forget(), true);
    f.scratch.passed();
  });
}
