// Real encrypted Store and holding owner; semantic Core admission is a
// separate boundary. The descriptor below is explicit authored test DATA.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-lookup-raw-'));
  const configuration = {directory, storeAuthorityCid: cid('lookup raw Store'),
    privateEvidenceKey: Buffer.alloc(32, 17), capacityBytes: 1048576,
    maxObjectBytes: 16384, maxObjects: 40, maxContractNodes: 1000, maxContractDepth: 30};
  const control = createPublicationContractControlFixture(), stores = [];
  const store = await openLocalPublicationStore(configuration, control); stores.push(store);
  let passed = false;
  t.after(async () => {
    for (const current of stores) assert.equal(await current.close(), true);
    if (passed) await rm(directory, {recursive:true, force:true});
    else t.diagnostic(`Preserved lookup raw Store failure: ${directory}`);
  });
  return {store, directory, configuration, control, stores, pass() {passed = true;}};
}
const transport = Buffer.from('{"files":[{"id":"original","text":"raw transport, not projected ContentRef"}]}\r\n');
const binding = () => ({name:'lookup_raw_response', semanticCid:cid('original raw metadata'),
  holdingCid:cid('original lookup holding'), wire:'{"version":"actql-lookup-raw-response/0.1"}',
  contentCid:cid(transport), byteCount:transport.byteLength});
const readBinding = ({semanticCid, holdingCid, wire, contentCid, byteCount}) =>
  ({semanticCid, holdingCid, wire, contentCid, byteCount});

test('lookup raw holding encrypts original bytes and restores the same descriptor after cold reopen', async t => {
  const f = await fixture(t), original = binding();
  const owner = preparePrivatePublicationHolding(f.store, original, transport);
  const record = await owner.commit();
  assert.equal(owner.status().committed, true);
  assert.equal(owner.status().preparedPending, false);
  assert.equal(record.holding_cid, original.holdingCid);
  assert.equal(record.manifest_cid, original.semanticCid);
  assert.equal(record.objects.length, 2);
  for (const object of record.objects) {
    const hex = object.cid.slice(7);
    const stored = await readFile(join(f.directory, 'objects', hex));
    assert.equal(cid(stored), object.cid);
    assert.equal(stored.includes(transport), false);
    assert.equal(stored.includes(Buffer.from(original.wire)), false);
  }
  assert.equal(await f.store.close(), true);
  const cold = await openLocalPublicationStore(f.configuration, f.control); f.stores.push(cold);
  assert.deepEqual(await cold.readLookupRawEvidence(readBinding(original)), transport);
  assert.equal((await cold.confirmLookupRawEvidence(readBinding(original))).record.holding_cid,
    original.holdingCid);
  await assert.rejects(cold.readModelRawEvidence(readBinding(original)),
    {code:'PublicationPrivateEvidenceCorrupt'});
  const retained = preparePrivatePublicationHolding(cold, original, transport);
  assert.equal((await retained.commit()).holding_cid, original.holdingCid);
  assert.equal(retained.status().preparedPending, false);
  f.pass();
});

test('lookup raw Store rejects changed physical bytes before reserving a writer', async t => {
  const f = await fixture(t), original = readBinding(binding()), before = f.store.status();
  await assert.rejects(f.store.prepareLookupRawEvidence(original, Buffer.from('different')),
    {code:'PublicationModelRawContentMismatch'});
  const after = f.store.status();
  assert.equal(after.reservedBytes, before.reservedBytes);
  assert.equal(after.reservedObjects, before.reservedObjects);
  assert.equal(await f.store.confirmLookupRawEvidence(original), undefined);
  f.pass();
});
