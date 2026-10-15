import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// Actual encrypted Store; the existing protocol control is an explicit Core
// double. This scalar clamp does not reserve bytes or acknowledge persistence.
const cid = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const control = createPublicationContractControlFixture();
async function fixture(t, maxObjectBytes) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-wire-limit-'));
  const configuration = {directory, storeAuthorityCid: cid('wire-limit-authority'),
    privateEvidenceKey: Buffer.alloc(32, 9), capacityBytes: 1024 * 1024,
    maxObjectBytes, maxObjects: 16, maxContractNodes: 1024, maxContractDepth: 32};
  const store = await openLocalPublicationStore(configuration, control);
  t.after(async () => {
    assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  return {store, configuration};
}

test('original Store exposes the exact closed encrypted wire ceiling without a write or grant', async t => {
  // Independent format oracle: E(B)=128+4*ceil(B/3), including tag and nonce.
  for (const [maximum, expected] of [[128, 0], [131, 0], [132, 3],
    [16384, 12192], [16387, 12192], [16388, 12195]]) {
    const {store, configuration} = await fixture(t, maximum);
    const before = store.status();
    assert.equal(store.privateEvidenceWireLimit(), expected);
    configuration.maxObjectBytes = 1048576;
    assert.equal(store.privateEvidenceWireLimit(), expected, 'original immutable Store selection');
    assert.deepEqual(store.status(), before, 'query does not reserve, write or release');
  }
  const {store} = await fixture(t, 127);
  assert.throws(() => store.privateEvidenceWireLimit(), {code: 'PublicationObjectLimit'});
});

test('original wire ceiling uses UTF8 bytes, with exact encrypted fit and one byte over rejected', async t => {
  const {store} = await fixture(t, 16384);
  const maximum = store.privateEvidenceWireLimit();
  assert.equal(maximum, 12192);
  const wire = 'é'.repeat(6096);
  assert.equal(wire.length, 6096);
  assert.equal(Buffer.byteLength(wire), maximum);
  const prepared = await store.preparePrivateEvidence('model_capture_bundle', wire, cid(wire));
  try {
    assert.equal(prepared.bytes, 16384);
    const before = store.status();
    await assert.rejects(store.preparePrivateEvidence('model_capture_bundle', wire + 'x', cid(wire + 'x')),
      {code: 'PublicationObjectLimit'});
    assert.deepEqual(store.status(), before, 'refusal does not issue a second reservation');
  } finally { assert.equal(await prepared.prepared.release(), true); }
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().reservedObjects, 0);
});

test('closing Store does not reissue an export ceiling or retire an outstanding private preparation', async t => {
  const {store} = await fixture(t, 16384);
  const maximum = store.privateEvidenceWireLimit();
  const prepared = await store.preparePrivateEvidence('model_capture_bundle', 'original', cid('original'));
  try {
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.equal(store.status().closed, false);
    assert.equal(prepared.prepared.status().pending, true);
    // seal moved the original reservation into actual stored-object custody;
    // it did not release that object or the still-pending prepared handle.
    assert.equal(prepared.bytes, 140); // E(8)=128+4*ceil(8/3)
    assert.equal(store.status().storedBytes, 140);
    assert.equal(store.status().objectCount, 1);
    assert.throws(() => store.privateEvidenceWireLimit(), {code: 'PublicationStoreClosed'});
    assert.equal(maximum, 12192, 'prior scalar is only DATA, never continuing admission');
  } finally { assert.equal(await prepared.prepared.release(), true); }
  assert.equal(await store.close(), true);
  assert.throws(() => store.privateEvidenceWireLimit(), {code: 'PublicationStoreClosed'});
});
