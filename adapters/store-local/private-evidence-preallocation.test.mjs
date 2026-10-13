// Actual Node Store I/O with the existing Core contract-control double.
// These extent/copy witnesses do not establish whole-phase capacity funding.
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const digest = text => `sha256:${crypto.createHash('sha256')
  .update(text, 'utf8').digest('hex')}`;
const control = createPublicationContractControlFixture();
const name = 'model_invocation_evidence';
const rawBinding = bytes => ({
  semanticCid: digest('extent raw semantic'), holdingCid: digest('extent raw holding'),
  wire: '', byteCount: bytes.byteLength,
  contentCid: `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`,
});

async function fixture(t, maxObjectBytes, withKey = true) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-evidence-extent-'));
  const configuration = {
    directory, storeAuthorityCid: digest('C extent fixture authority'),
    ...(withKey ? {privateEvidenceKey: Buffer.alloc(32, 7)} : {}),
    capacityBytes: 1024 * 1024, maxObjectBytes,
    maxObjects: 32, maxContractNodes: 4096, maxContractDepth: 64,
  };
  const stores = [];
  t.after(async () => {
    for (const store of stores) assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  const store = await openLocalPublicationStore(configuration, control);
  stores.push(store);
  return {store, configuration, stores};
}

async function countPreparation(wire, operation) {
  const originals = {
    randomBytes: crypto.randomBytes, createCipheriv: crypto.createCipheriv,
    from: Buffer.from,
  };
  const counts = {nonce: 0, cipher: 0, plaintextCopy: 0};
  crypto.randomBytes = (...args) => {
    if (args[0] === 12) counts.nonce++;
    return Reflect.apply(originals.randomBytes, crypto, args);
  };
  crypto.createCipheriv = (...args) => {
    counts.cipher++;
    return Reflect.apply(originals.createCipheriv, crypto, args);
  };
  Buffer.from = function(...args) {
    if (args[0] === wire && args[1] === 'utf8') counts.plaintextCopy++;
    return Reflect.apply(originals.from, Buffer, args);
  };
  syncBuiltinESMExports();
  try { await operation(); }
  finally {
    Object.assign(crypto, {
      randomBytes: originals.randomBytes, createCipheriv: originals.createCipheriv,
    });
    Buffer.from = originals.from;
    syncBuiltinESMExports();
  }
  return counts;
}

test('private evidence: oversized encrypted extent refuses before crypto '
    + 'and String plaintext copy', async t => {
  // Independent closed-format boundaries: E(0)=128, E(3)=132,
  // E(12192)=16384, E(12193)=16388. No product-generated expectations.
  for (const [limit, wire] of [[127, ''], [131, 'abc'],
    [16384, 'x'.repeat(12193)]]) {
    for (const bytesEntry of [false, true]) {
      const {store} = await fixture(t, limit);
      const input = bytesEntry ? Buffer.from(wire, 'utf8') : wire;
      const binding = bytesEntry ? rawBinding(input) : undefined;
      const counts = await countPreparation(wire, async () => {
        await assert.rejects(bytesEntry
          ? store.prepareModelRawEvidence(binding, input)
          : store.preparePrivateEvidence(name, input, digest('extent')),
        {code: 'PublicationObjectLimit'});
      });
      assert.deepEqual(counts, {nonce: 0, cipher: 0, plaintextCopy: 0});
      assert.equal(store.status().storedBytes, 0);
      assert.equal(store.status().reservedBytes, 0);
      assert.equal(store.status().reservedObjects, 0);
    }
  }
});

test('private evidence: independent exact encrypted extents still prepare '
    + 'and release', async t => {
  for (const [limit, wire] of [[128, ''], [132, 'abc'],
    [16384, 'x'.repeat(12192)]]) {
    for (const bytesEntry of [false, true]) {
      const {store} = await fixture(t, limit);
      const input = bytesEntry ? Buffer.from(wire) : wire;
      const preparedObjects = bytesEntry
        ? await store.prepareModelRawEvidence(rawBinding(input), input)
        : [await store.preparePrivateEvidence(name, wire, digest('fit'))];
      const prepared = preparedObjects[preparedObjects.length - 1];
      assert.equal(prepared.bytes, limit);
      for (const object of preparedObjects) {
        assert.equal(await object.prepared.release(), true);
      }
      assert.equal(store.status().reservedBytes, 0);
    }
  }
});

test('private evidence: Unicode, CRLF and NULL wire survive unchanged '
    + 'after actual Store restart', async t => {
  const {store, configuration, stores} = await fixture(t, 16384);
  const wire = '{"p":null,"text":"é/e\u0301\\r\\n"}\r\n';
  const semanticCid = digest(wire);
  const holdingCid = digest('original extent holding');
  const prepared = await store.preparePrivateEvidence(name, wire, semanticCid);
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid,
    manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
  }, [prepared.prepared]);
  assert.equal(await store.close(), true);
  const reopened = await openLocalPublicationStore(configuration, control);
  stores.push(reopened);
  const read = await reopened.readPrivateEvidence(name, semanticCid, holdingCid);
  assert.deepEqual(read, Buffer.from(wire, 'utf8'));
  assert.equal(`sha256:${crypto.createHash('sha256').update(read).digest('hex')}`,
    semanticCid);
});

test('private evidence: original validation and missing-key priority remain '
    + 'before encrypted extent refusal', async t => {
  const {store} = await fixture(t, 131, false);
  await assert.rejects(store.preparePrivateEvidence(name, 'abc', 'invalid'),
    {code: 'InvalidPublicationObjectCid'});
  await assert.rejects(store.preparePrivateEvidence(name, 'abc', digest('key')),
    {code: 'PublicationPrivateEvidenceKeyUnavailable'});
  await assert.rejects(store.preparePrivateEvidence('Invalid', 'abc', digest('key')),
    {code: 'InvalidPublicationPrivateEvidence'});
  assert.throws(() => store.preparePrivateEvidence(name, 'x'.repeat(132),
    digest('key')), {code: 'InvalidPublicationPrivateEvidence'});
});

test('private evidence: completed AES-GCM block does not acquire a second '
    + 'ciphertext backing through concat', async t => {
  const {store} = await fixture(t, 16384);
  const wire = 'original e\u0301 bytes\r\n';
  const semanticCid = digest(wire);
  const holdingCid = digest('single ciphertext backing');
  const originalCipher = crypto.createCipheriv;
  const originalConcat = Buffer.concat;
  let ciphertextBlock;
  let finalBytes;
  let ciphertextCopies = 0;
  crypto.createCipheriv = (...args) => {
    const cipher = Reflect.apply(originalCipher, crypto, args);
    const update = cipher.update;
    const final = cipher.final;
    cipher.update = function(...updateArgs) {
      ciphertextBlock = Reflect.apply(update, this, updateArgs);
      return ciphertextBlock;
    };
    cipher.final = function(...finalArgs) {
      const result = Reflect.apply(final, this, finalArgs);
      finalBytes = result.byteLength;
      return result;
    };
    return cipher;
  };
  Buffer.concat = function(chunks, ...args) {
    if (ciphertextBlock !== undefined && chunks.includes(ciphertextBlock)) {
      ciphertextCopies++;
    }
    return Reflect.apply(originalConcat, Buffer, [chunks, ...args]);
  };
  syncBuiltinESMExports();
  let prepared;
  try {
    prepared = await store.preparePrivateEvidence(name, wire, semanticCid);
  } finally {
    crypto.createCipheriv = originalCipher;
    Buffer.concat = originalConcat;
    syncBuiltinESMExports();
  }
  // Commit before assertions so failure teardown still preserves/settles the
  // actual writer custody. This is not Core admission or capacity evidence.
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid,
    manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
  }, [prepared.prepared]);
  assert.deepEqual(await store.readPrivateEvidence(name, semanticCid, holdingCid),
    Buffer.from(wire, 'utf8'));
  assert.equal(ciphertextBlock.byteLength, 20);
  assert.equal(finalBytes, 0);
  assert.equal(ciphertextCopies, 0);
});
