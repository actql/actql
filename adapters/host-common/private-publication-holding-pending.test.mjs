// Actual Store custody and directory ACK faults. The preparation/confirmation
// ports below are explicit boundary doubles, not genuine Core admission.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createPublicationContractControlFixture} from './publication-contract-control.fixture.mjs';
import {preparePrivatePublicationHolding} from './private-publication-holding.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t, raw) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-pending-'));
  const binding = {name: raw ? 'model_raw_response' : 'effect_preview',
    semanticCid: cid('pending original semantic'), holdingCid: cid('pending original holding'),
    wire: '{"original":null}', ...(raw ? {contentCid: cid('raw'), byteCount: 3} : {})};
  const lostAck = Object.assign(new Error('IndependentDirectoryAckFailure'), {code: 'EIO'});
  let failSync = false;
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('pending authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture(), {async syncDirectory(path) {
    if (failSync && path === join(directory, 'physical-holdings')) throw lostAck;
    const handle = await open(path, 'r');
    try { await handle.sync(); } finally { await handle.close(); }
  }});
  const object = await store.preparePrivateEvidence(raw ? 'model_raw_content' : binding.name,
    raw ? 'raw' : binding.wire, binding.semanticCid);
  const record = {version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
    holding_cid: binding.holdingCid, manifest_cid: binding.semanticCid,
    objects: [{cid: object.physicalCid, byte_count: object.bytes}]};
  failSync = true;
  await assert.rejects(store.commitPhysicalHolding(record, [object.prepared]), error => error === lostAck);
  const objectPath = join(directory, 'objects', object.physicalCid.slice(7));
  const holdingPath = join(directory, 'physical-holdings', binding.holdingCid.slice(7) + '.json');
  const originalBytes = await readFile(objectPath), originalHolding = await readFile(holdingPath);
  assert.equal(await object.prepared.release(), false);
  assert.equal(object.prepared.status().pending, true);
  // Never remove an unresolved original Store. If same-operation reconciliation
  // or close fails, the test teardown itself fails and leaves the directory.
  t.after(async () => {
    failSync = false;
    await store.commitPhysicalHolding(record, []);
    await store.retirePhysicalHolding(binding.holdingCid);
    assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  const counts = {prepare: 0, commit: 0};
  const constructionFailure = Object.assign(new Error('IndependentDescriptorConstructionFailure'),
    {cleanupPending: true, cleanupHandle: object.prepared});
  const boundary = raw ? {
    async confirmModelRawEvidence() { return undefined; },
    async prepareModelRawEvidence() { counts.prepare++; throw constructionFailure; },
    async commitPhysicalHolding() { counts.commit++; throw lostAck; },
  } : {
    async confirmPrivateEvidence() { return undefined; },
    async preparePrivateEvidence() { counts.prepare++; return object; },
    async commitPhysicalHolding() { counts.commit++; throw lostAck; },
  };
  const owner = preparePrivatePublicationHolding(boundary, binding, raw ? Buffer.from('raw') : undefined);
  const checkBytes = async () => {
    assert.deepEqual(await readFile(objectPath), originalBytes);
    assert.deepEqual(await readFile(holdingPath), originalHolding);
    assert.equal(object.prepared.status().pending, true);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  };
  const reconcile = async () => {
    failSync = false;
    const confirmed = await store.commitPhysicalHolding(record, []);
    assert.equal(confirmed.created, false);
    assert.equal(object.prepared.status().pending, false);
    // Already adopted handles legitimately return false with pending=false.
    assert.equal(await object.prepared.release(), false);
  };
  return {owner, object, counts, checkBytes, reconcile, constructionFailure};
}

const pending = owner => error => {
  assert.equal(error.code, 'PrivatePublicationHoldingCleanupPending');
  assert.equal(error.cleanupPending, true);
  assert.equal(error.cleanupHandle, owner);
  return true;
};

test('private holding: false construction cleanup keeps same custody and blocks new preparation', async t => {
  const f = await fixture(t, true);
  await assert.rejects(f.owner.commit(), error => error === f.constructionFailure);
  const retry = f.owner.commit();
  assert.equal(f.owner.commit(), retry);
  await assert.rejects(retry, pending(f.owner));
  assert.equal(f.counts.prepare, 1);
  assert.equal(f.counts.commit, 0);
  assert.equal(f.owner.status().preparedPending, true);
  assert.equal(f.owner.status().abandoned, false);
  await f.checkBytes();
  await f.reconcile();
  assert.equal(await f.owner.abort(), true);
  assert.equal(f.owner.status().preparedPending, false);
});

test('private holding: false construction cleanup cannot report abort complete or lose retry handle', async t => {
  const f = await fixture(t, true);
  await assert.rejects(f.owner.commit(), error => error === f.constructionFailure);
  const first = f.owner.abort();
  assert.equal(f.owner.abort(), first);
  await assert.rejects(first, pending(f.owner));
  assert.equal(f.owner.status().preparedPending, true);
  assert.equal(f.owner.status().abandoned, false);
  await f.checkBytes();
  await assert.rejects(f.owner.abort(), pending(f.owner));
  assert.equal(f.counts.prepare, 1);
  await f.reconcile();
  assert.equal(await f.owner.abort(), true);
  assert.equal(f.owner.status().preparedPending, false);
});

test('private holding: visible unknown prepared output keeps abort pending until same ACK reconciliation', async t => {
  const f = await fixture(t, false);
  await assert.rejects(f.owner.commit(), {cleanupPending: true, cleanupHandle: f.owner});
  await assert.rejects(f.owner.abort(), pending(f.owner));
  assert.equal(f.owner.status().abandoned, false);
  assert.equal(f.owner.status().preparedPending, true);
  await f.checkBytes();
  await f.reconcile();
  assert.equal(await f.owner.abort(), true);
  assert.equal(f.owner.status().preparedPending, false);
  assert.deepEqual(f.counts, {prepare: 1, commit: 1});
});
