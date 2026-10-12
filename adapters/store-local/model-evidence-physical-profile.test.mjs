// Independent physical-profile witnesses for C's pending Model capacity sum.
// These do not admit a Model observation, install extra holding, or prove the
// complete memory cost of crypto, parsing, control records or stream buffers.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const digest = text => `sha256:${createHash('sha256')
  .update(text, 'utf8').digest('hex')}`;
const control = createPublicationContractControlFixture();

async function fixture(t, maxObjectBytes = 128 * 1024) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-model-profile-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory,
    storeAuthorityCid: digest('C physical profile fixture authority'),
    privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1024 * 1024,
    maxObjectBytes,
    maxObjects: 32,
    maxContractNodes: 4096,
    maxContractDepth: 64,
  };
  const store = await openLocalPublicationStore(configuration, control);
  t.after(() => store.close());
  return {store, configuration};
}

test('Model physical profile: independent UTF-8 envelope sizes and original '
    + 'wire survive Store restart', async t => {
  const {store, configuration} = await fixture(t);
  // Fixed arithmetic: AES-GCM ciphertext length B; base64 4*ceil(B/3);
  // the closed envelope is 128 ASCII bytes before ciphertext. Expectations
  // are not calculated by the Store or from its observed envelope.
  const vectors = [
    ['', 0, 128], ['a', 1, 132], ['ab', 2, 132], ['abc', 3, 132],
    ['é', 2, 132], ['e\u0301', 3, 132], ['\r\n', 2, 132],
    ['{"p":null}', 10, 144], ['x'.repeat(49153), 49153, 65668],
  ];
  const originals = [];
  for (const [index, [wire, plaintextBytes, encryptedBytes]] of
    vectors.entries()) {
    assert.equal(Buffer.byteLength(wire, 'utf8'), plaintextBytes);
    const semanticCid = digest(`C original physical record ${index}`);
    const holdingCid = digest(`C physical custody ${index}`);
    const prepared = await store.preparePrivateEvidence(
      'model_invocation_evidence', wire, semanticCid,
    );
    assert.equal(prepared.bytes, encryptedBytes);
    assert.equal((await store.verifyObject(prepared.physicalCid)).bytes,
      encryptedBytes);
    assert.equal(prepared.prepared.status().pending, true);
    await store.commitPhysicalHolding({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private', holding_cid: holdingCid,
      manifest_cid: semanticCid,
      objects: [{cid: prepared.physicalCid, byte_count: encryptedBytes}],
    }, [prepared.prepared]);
    assert.equal(prepared.prepared.status().pending, false);
    assert.deepEqual(await store.readPrivateEvidence(
      'model_invocation_evidence', semanticCid, holdingCid,
    ), Buffer.from(wire, 'utf8'));
    originals.push({wire, semanticCid, holdingCid});
  }
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().reservedObjects, 0);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, control);
  t.after(() => reopened.close());
  for (const {wire, semanticCid, holdingCid} of originals) {
    assert.deepEqual(await reopened.readPrivateEvidence(
      'model_invocation_evidence', semanticCid, holdingCid,
    ), Buffer.from(wire, 'utf8'));
  }
});

test('Model physical profile: exact envelope limit succeeds; one byte short '
    + 'cannot acquire prepared file custody', async t => {
  const exact = await fixture(t, 132);
  const prepared = await exact.store.preparePrivateEvidence(
    'model_invocation_evidence', 'abc', digest('C exact physical envelope'),
  );
  assert.equal(prepared.bytes, 132);
  assert.equal(prepared.prepared.status().pending, true);
  assert.equal(await prepared.prepared.release(), true);
  assert.equal(prepared.prepared.status().pending, false);
  assert.equal(await prepared.prepared.release(), false);
  const short = await fixture(t, 131);
  await assert.rejects(short.store.preparePrivateEvidence(
    'model_invocation_evidence', 'abc', digest('C short physical envelope'),
  ), {code: 'PublicationObjectLimit'});
  assert.equal(short.store.status().storedBytes, 0);
  assert.equal(short.store.status().reservedBytes, 0);
  assert.equal(short.store.status().reservedObjects, 0);
});

test('Model physical profile: selected Node FileHandle stream defaults to '
    + '64KiB independently of plaintext or envelope length', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-stream-profile-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'fixed-file');
  await writeFile(path, Buffer.alloc(65668, 7));
  const handle = await open(path, 'r');
  const stream = handle.createReadStream({autoClose: false});
  try {
    assert.equal(stream.readableHighWaterMark, 65536);
    let bytes = 0;
    for await (const chunk of stream) {
      assert.ok(chunk.byteLength > 0);
      bytes += chunk.byteLength;
    }
    assert.equal(bytes, 65668);
  } finally {
    stream.destroy();
    await handle.close();
  }
  // highWaterMark is not a total heap ceiling, nor a minimum read size.
  // Do not infer a general ceil(E/65536) bound on retained chunk headers.
});

test('Model physical profile: private read does not retain chunk copies '
    + 'plus a second full envelope concatenation', async t => {
  const {store} = await fixture(t);
  const semanticCid = digest('C no duplicate envelope original');
  const holdingCid = digest('C no duplicate envelope holding');
  const prepared = await store.preparePrivateEvidence(
    'model_invocation_evidence', 'abc', semanticCid,
  );
  assert.equal(prepared.bytes, 132);
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid,
    manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: 132}],
  }, [prepared.prepared]);
  // Observe the real read path, not a reimplementation or fixture counter.
  // The plaintext concatenation has length 3 and remains permitted. Its
  // independent encrypted length 132 identifies the duplicate envelope.
  const originalConcat = Buffer.concat;
  let envelopeConcatenations = 0;
  Buffer.concat = function(chunks, ...arguments_) {
    if (chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0) === 132) {
      envelopeConcatenations++;
    }
    return Reflect.apply(originalConcat, Buffer, [chunks, ...arguments_]);
  };
  try {
    assert.deepEqual(await store.readPrivateEvidence(
      'model_invocation_evidence', semanticCid, holdingCid,
    ), Buffer.from('abc'));
  } finally {
    Buffer.concat = originalConcat;
  }
  assert.equal(envelopeConcatenations, 0);
});
