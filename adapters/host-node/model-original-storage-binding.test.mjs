import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openContinuationEvidence} from './local-continuation-evidence.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

const cid = n => `sha256:${n.repeat(64)}`;
const digest = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const authority = cid('1');
const selectedStoreWire = '{"version":"actql-local-publication-store/0.1","isolation":"execution-namespace","store_authority_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}';
const selectedStoreCid = 'sha256:247d00ffcfddef53c9631b096e4ee3dfd37e2f83a035e0bcf6f7559b852476df';
const control = runtimeCore(moon).publicationControl;
const limits = {maxWireBytes: 2048, maxNodes: 32, maxDepth: 2};

async function fixture(t) {
  const state = await mkdtemp(join(tmpdir(), 'actql-original-storage-binding-'));
  const key = Buffer.alloc(32, 7);
  const keyId = digest(key);
  const open = () => openContinuationEvidence({stateDirectory: state, key, keyId,
    contractControl: control, preparation: () => undefined,
    isTerminalRunOutcome: () => false, store: {storeAuthorityCid: authority}});
  const owners = [];
  const evidence = () => { const owner = open(); owners.push(owner); return owner; };
  t.after(async () => {
    for (const owner of owners) await owner.close();
    await rm(state, {recursive: true, force: true});
    key.fill(0);
  });
  return {state, key, keyId, evidence};
}

test('original storage binding observes the actual Store and keeps one nominal installation view', async t => {
  const f = await fixture(t), owner = f.evidence();
  await assert.rejects(owner.originalModelStorageBindingEvidence(undefined),
    {code: 'ForeignOriginalModelStorageBinding'});
  const handle = await owner.observeOriginalModelStorageBinding();
  const admitted = await owner.originalModelStorageBindingEvidence(handle);
  assert.equal(Object.isFrozen(handle), true);
  assert.equal(await owner.observeOriginalModelStorageBinding(), handle);
  assert.equal(await owner.originalModelStorageBindingEvidence(handle), admitted);
  const body = JSON.parse(handle.wire);
  assert.equal(body.store_contract_wire, selectedStoreWire);
  assert.equal(body.store_contract_cid, selectedStoreCid);
  assert.equal(digest(selectedStoreWire), selectedStoreCid);
  assert.equal(await readFile(join(f.state, 'private-store', 'store.json'), 'utf8'), selectedStoreWire);
  assert.equal(body.store_authority_cid, authority);
  assert.equal(body.key_generation_cid, f.keyId);
  assert.equal(body.private_namespace, 'local-continuation-private');
  assert.equal('path' in body || 'key' in body || 'holding_cid' in body, false);
  assert.equal(body.self_cid, admitted.identity);
  assert.equal('restore' in handle || 'send' in handle || 'read' in handle, false);
});

test('original storage binding refuses copied foreign and restarted handles before adoption', async t => {
  const f = await fixture(t), first = f.evidence(), other = f.evidence();
  const handle = await first.observeOriginalModelStorageBinding();
  for (const foreign of [undefined, null, handle.identity, {...handle}]) {
    await assert.rejects(first.originalModelStorageBindingEvidence(foreign),
      {code: 'ForeignOriginalModelStorageBinding'});
  }
  const otherHandle = await other.observeOriginalModelStorageBinding();
  assert.equal(otherHandle.identity, handle.identity);
  assert.notEqual(otherHandle, handle);
  await assert.rejects(other.originalModelStorageBindingEvidence(handle),
    {code: 'ForeignOriginalModelStorageBinding'});
  await first.close();
  const restarted = f.evidence();
  await assert.rejects(restarted.originalModelStorageBindingEvidence(handle),
    {code: 'ForeignOriginalModelStorageBinding'});
  const fresh = await restarted.observeOriginalModelStorageBinding();
  assert.equal(fresh.identity, handle.identity, 'a fresh observation is not old nominal custody');
});

test('original storage binding refuses actual Store alteration after issuance', async t => {
  const f = await fixture(t), owner = f.evidence();
  const handle = await owner.observeOriginalModelStorageBinding();
  const path = join(f.state, 'private-store', 'store.json');
  await writeFile(path, selectedStoreWire.replace(authority, cid('3')));
  await assert.rejects(owner.originalModelStorageBindingEvidence(handle),
    {code: 'PublicationStoreAuthorityMismatch'});
  await writeFile(path, selectedStoreWire);
  assert.equal((await owner.originalModelStorageBindingEvidence(handle)).identity, handle.identity);
});

test('original storage binding physical handle is valid only for the same live Store', async t => {
  const f = await fixture(t);
  const configuration = {directory: join(f.state, 'direct'), storeAuthorityCid: authority,
    capacityBytes: 4096, maxObjectBytes: 2048, maxObjects: 8,
    maxContractNodes: 32, maxContractDepth: 4, privateEvidenceKey: f.key};
  let store = await openLocalPublicationStore(configuration, control);
  t.after(async () => { if (!store.status().closed) await store.close(); });
  assert.throws(() => store.originalModelStorageBindingEvidence(undefined),
    {code: 'ForeignOriginalModelStorageBinding'});
  const handle = await store.observeOriginalModelStorageBinding();
  assert.equal(store.originalModelStorageBindingEvidence(handle).identity, handle.identity);
  await store.close();
  assert.throws(() => store.originalModelStorageBindingEvidence(handle),
    {code: 'PublicationStoreClosed'});
  store = await openLocalPublicationStore(configuration, control);
  assert.throws(() => store.originalModelStorageBindingEvidence(handle),
    {code: 'ForeignOriginalModelStorageBinding'});
  const current = await store.observeOriginalModelStorageBinding();
  assert.equal(current.identity, handle.identity);
  assert.notEqual(current, handle);
});

test('original storage binding independent canonical vector and contradictions use actual Common validator', () => {
  const body = {key_generation_cid: cid('2'), private_namespace: 'local-continuation-private',
    store_authority_cid: authority, store_contract_cid: selectedStoreCid,
    store_contract_wire: selectedStoreWire, version: 'actql-model-original-storage-binding/0.1'};
  const expected = 'sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3';
  assert.equal(digest(JSON.stringify(body)), expected);
  const admitted = control.sealRunEvidence('model_original_storage_binding', JSON.stringify(body), limits);
  assert.equal(admitted.identity, expected);
  for (const change of [{store_contract_cid: cid('3')}, {store_authority_cid: cid('3')},
    {store_contract_wire: selectedStoreWire.replace('execution-namespace', 'shared')},
    {private_namespace: 'publication-private'}, {key_generation_cid: null},
    {holding_cid: cid('4')}, {artifact_cid: cid('4')}, {path: '/test/not-a-binding'}]) {
    assert.throws(() => control.sealRunEvidence('model_original_storage_binding',
      JSON.stringify({...body, ...change}), limits));
  }
});
