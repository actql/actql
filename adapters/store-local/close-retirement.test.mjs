// Actual same Store/ownership/key lifetime; no new normal-profile coefficients.
import assert from 'node:assert/strict';
import {chmod, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-close-retirement-'));
  const key = Buffer.alloc(32, 7), from = Buffer.from;
  let ownedKey;
  // Test-only observation of the actual configuration copy, not a product
  // getter or a replacement Store/cleanup implementation.
  Buffer.from = function(value, ...args) {
    const result = Reflect.apply(from, this, [value, ...args]);
    if (value === key) ownedKey = result;
    return result;
  };
  const configuration = {directory, privateEvidenceKey: key,
    storeAuthorityCid: 'sha256:' + 'a'.repeat(64), capacityBytes: 65536,
    maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 100, maxContractDepth: 10};
  const control = createPublicationContractControlFixture();
  let store;
  try { store = await openLocalPublicationStore(configuration, control); }
  finally { Buffer.from = from; }
  const owner = join(directory, 'owner'), record = join(owner, 'owner.json');
  const original = await readFile(record);
  t.after(async () => {
    await chmod(owner, 0o700).catch(() => {});
    if (!store.status().closed) {
      await writeFile(record, original).catch(() => {});
      await store.close();
    }
    await rm(directory, {recursive: true, force: true});
  });
  return {store, key, ownedKey, directory, owner, record, original, configuration, control};
}

test('actual Store failed close retains original ownership and key for single-flight retry', async t => {
  const f = await fixture(t);
  await chmod(f.owner, 0o500);
  const first = f.store.close();
  assert.strictEqual(f.store.close(), first);
  await assert.rejects(first, {code: 'EACCES'});
  assert.equal(f.store.status().closed, false);
  assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
  assert.deepEqual(await readFile(f.record), f.original);
  await assert.rejects(openLocalPublicationStore(f.configuration, f.control), {code: 'PublicationStoreBusy'});
  // Failed cleanup admits no new read/write, even though closed is not true.
  await assert.rejects(f.store.observeOriginalModelStorageBinding(), {code: 'PublicationStoreClosed'});
  await chmod(f.owner, 0o700);
  const retry = f.store.close();
  assert.strictEqual(f.store.close(), retry);
  assert.equal(await retry, true);
  assert.equal(f.store.status().closed, true);
  assert.deepEqual(f.ownedKey, Buffer.alloc(32));
  assert.deepEqual(f.key, Buffer.alloc(32, 7));
  await assert.rejects(readFile(f.record), {code: 'ENOENT'});
  assert.equal(await f.store.close(), true);
  const next = await openLocalPublicationStore(f.configuration, f.control);
  await next.close();
});

test('actual Store absent or foreign ownership cannot authorize key retirement', async t => {
  const f = await fixture(t);
  await rm(f.record);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreOwnershipLost'});
  assert.equal(f.store.status().closed, false);
  assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
  const foreign = {...JSON.parse(f.original), token: 'foreign'};
  await writeFile(f.record, JSON.stringify(foreign));
  await assert.rejects(f.store.close(), {code: 'PublicationStoreOwnershipLost'});
  assert.deepEqual(JSON.parse(await readFile(f.record)), foreign);
  assert.deepEqual(f.ownedKey, Buffer.alloc(32, 7));
  // Restore only this disposable test's exact saved record; product cleanup
  // does not reconstruct absent ownership or authorize from a copied token.
  await writeFile(f.record, f.original);
  assert.equal(await f.store.close(), true);
  assert.deepEqual(f.ownedKey, Buffer.alloc(32));
});
