// Actual Store bytes, prepared handles and holding durability. Only the
// directory-sync fault is injected; no Model/public execution is claimed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'physical-holding-release-', label: 'physical holding prepared release'});
  const directory = join(scratch.path, 'store');
  const bytes = Buffer.from('exact original captured bytes\n');
  let syncHook;
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('independent Store authority'), capacityBytes: 65536,
    maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture(), {async syncDirectory(path) {
    if (path === join(directory, 'physical-holdings')) await syncHook?.();
    const fd = await open(path, 'r');
    try { await fd.sync(); } finally { await fd.close(); }
  }});
  const writer = store.createPreparedObjectWriter(bytes.length);
  await writer.append(bytes);
  const physical = await writer.seal(cid(bytes));
  const holding = Object.freeze({version: 'actql-local-physical-holding/0.1',
    namespace: 'content', holding_cid: cid('original holding'),
    manifest_cid: cid('independent original reference'),
    objects: [{cid: cid(bytes), byte_count: bytes.length}]});
  const objectPath = join(directory, 'objects', cid(bytes).slice(7));
  const holdingPath = join(directory, 'physical-holdings', holding.holding_cid.slice(7) + '.json');
  t.after(async () => {
    syncHook = undefined;
    // Reconcile only this diagnostic's same original holding. If bytes were
    // lost, preserve the failed environment instead of deleting its evidence.
    try {
      if (await store.inspectPhysicalHolding(holding.holding_cid) !== undefined) {
        await store.commitPhysicalHolding(holding, []);
      }
      if (physical.prepared.status().pending) await physical.prepared.release();
      if (!store.status().closed) await store.close();
    } catch (error) { t.diagnostic(`Original diagnostic custody retained: ${error.code ?? error.message}`); }
  });
  return {scratch, bytes, store, physical, holding, objectPath, holdingPath,
    setSyncHook(value) { syncHook = value; }};
}

test('lost physical holding commit reply cannot let prepared cleanup delete its original bytes', async t => {
  const f = await fixture(t);
  const fault = Object.assign(new Error('Independent holding ACK lost'), {code: 'EIO'});
  let syncAttempts = 0;
  f.setSyncHook(() => { syncAttempts++; throw fault; });
  await assert.rejects(f.store.commitPhysicalHolding(f.holding, [f.physical.prepared]), error => error === fault);
  const originalHolding = await readFile(f.holdingPath);
  assert.deepEqual(JSON.parse(originalHolding), f.holding);
  assert.equal(f.physical.prepared.status().pending, true);
  const firstRelease = await f.physical.prepared.release();
  const bytesStillPresent = await readFile(f.objectPath).then(value => value.equals(f.bytes),
    error => error.code === 'ENOENT' ? false : Promise.reject(error));
  await writeFile(join(f.scratch.path, 'lost-reply-observation.json'), JSON.stringify({
    firstRelease, bytesStillPresent, pending: f.physical.prepared.status().pending, syncAttempts}));
  assert.equal(firstRelease, false, 'visible-but-unconfirmed holding keeps the same prepared responsibility');
  assert.equal(bytesStillPresent, true, 'cleanup cannot erase bytes a lost commit may reference');
  assert.equal(f.physical.prepared.status().pending, true);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  await assert.rejects(f.store.commitPhysicalHolding(f.holding, []), error => error === fault);
  assert.equal(await f.physical.prepared.release(), false);
  assert.deepEqual(await readFile(f.holdingPath), originalHolding);
  assert.equal(f.store.status().storedBytes, f.bytes.length);
  f.setSyncHook(undefined);
  const reconciled = await f.store.commitPhysicalHolding(f.holding, []);
  assert.equal(reconciled.created, false);
  assert.equal(f.physical.prepared.status().pending, false);
  assert.equal(await f.physical.prepared.release(), false, 'confirmed adoption already retires this handle');
  const chunks = [];
  await f.store.consumePhysicalHolding(f.holding.holding_cid, 0, chunk => chunks.push(Buffer.from(chunk)));
  assert.deepEqual(Buffer.concat(chunks), f.bytes);
  await f.store.retirePhysicalHolding(f.holding.holding_cid);
  assert.equal(f.store.status().storedBytes, 0);
  await f.store.close();
  f.scratch.passed();
});

test('prepared release serializes behind the same in-flight holding commit', async t => {
  const f = await fixture(t);
  let enter, resume;
  const entered = new Promise(resolve => { enter = resolve; });
  const paused = new Promise(resolve => { resume = resolve; });
  f.setSyncHook(async () => { enter(); await paused; });
  const commit = f.store.commitPhysicalHolding(f.holding, [f.physical.prepared]);
  let release;
  try {
    await entered;
    let releaseSettled = false;
    release = f.physical.prepared.release().then(value => { releaseSettled = true; return value; });
    await yieldTurn();
    const bytesStillPresent = await readFile(f.objectPath).then(value => value.equals(f.bytes),
      error => error.code === 'ENOENT' ? false : Promise.reject(error));
    await writeFile(join(f.scratch.path, 'inflight-observation.json'), JSON.stringify({
      releaseSettled, bytesStillPresent, pending: f.physical.prepared.status().pending}));
    assert.equal(releaseSettled, false, 'same material queue orders release after commit confirmation');
    assert.equal(bytesStillPresent, true);
  } finally {
    resume();
    await Promise.allSettled([commit, release].filter(Boolean));
  }
  await commit;
  assert.equal(await release, false);
  assert.equal(f.physical.prepared.status().pending, false);
  assert.deepEqual(await readFile(f.objectPath), f.bytes);
  await f.store.retirePhysicalHolding(f.holding.holding_cid);
  assert.equal(f.store.status().storedBytes, 0);
  await f.store.close();
  f.scratch.passed();
});

test('an uncommitted prepared object still releases exactly once through the same owner', async t => {
  const f = await fixture(t);
  const first = f.physical.prepared.release();
  assert.strictEqual(f.physical.prepared.release(), first);
  assert.equal(await first, true);
  assert.equal(f.physical.prepared.status().pending, false);
  assert.equal(await f.physical.prepared.release(), false);
  assert.equal(f.store.status().storedBytes, 0);
  await assert.rejects(readFile(f.objectPath), {code: 'ENOENT'});
  await assert.rejects(readFile(f.holdingPath), {code: 'ENOENT'});
  await f.store.close();
  f.scratch.passed();
});
