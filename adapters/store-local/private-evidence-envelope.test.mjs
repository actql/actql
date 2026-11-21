// Encoding witnesses, not Core admission or a whole-phase capacity profile.
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import {syncBuiltinESMExports} from 'node:module';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';
import {encodePrivateEvidenceEnvelope} from './publication-store-private-evidence.mjs';

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const cid = bytes => `sha256:${hash(bytes)}`;
const name = 'model_invocation_evidence';
const semanticCid = cid('independent envelope input');
const aad = (name, semanticCid) => Buffer.from(
  `actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`, 'utf8');
// Verbatim accepted main dc5fac54ad4ffa6ed5710117a29a8f89cb987817 function.
// This original remains fixed when the production encoder changes.
const originalSource = readFileSync(new URL(
  './private-evidence-envelope-original.fixture.txt', import.meta.url), 'utf8');
assert.equal(hash(originalSource),
  '29b84639d41ef2a68e673c3995cca107b9aa687c5dd46b2a7fafe4963536d879');
function cipherWithOptionalFinal(createCipheriv, splitFinal) {
  const cipher = createCipheriv();
  if (!splitFinal) return cipher;
  // Return part of the real authenticated ciphertext through final().
  let tail;
  const update = cipher.update.bind(cipher), final = cipher.final.bind(cipher);
  cipher.update = bytes => {
    const result = update(bytes);
    tail = result.subarray(-1);
    return result.subarray(0, -1);
  };
  cipher.final = () => { assert.equal(final().length, 0); return tail; };
  return cipher;
}

async function oldEnvelope(input, {evidenceName = name, splitFinal = false} = {}) {
  let envelope;
  // Evaluate only the frozen historical input. The current encoder and Store
  // run through their real imports below.
  const prepare = runInNewContext(originalSource + '\npreparePrivateEvidenceInput;', {
    Buffer, Uint8Array, JSON,
    active() {}, configuration: {maxObjectBytes: 16384},
    cidHex(value) { assert.equal(value, semanticCid); },
    fail(code) { throw Object.assign(new Error(code), {code}); },
    privateEvidenceKey: () => Buffer.alloc(32, 7), privateEvidenceAad: aad,
    randomBytes: size => { assert.equal(size, 12); return Buffer.alloc(12, 9); },
    createCipheriv: (...args) => cipherWithOptionalFinal(() => crypto.createCipheriv(...args), splitFinal),
    createPreparedObjectWriter(expected) {
      return {
        async append(bytes) {
          assert.equal(bytes.length, expected);
          envelope = Buffer.from(bytes);
        },
        async seal() { return {cid: cid(envelope), bytes: expected, prepared: {}}; },
      };
    },
  });
  const prepared = await prepare(evidenceName, input, semanticCid, typeof input === 'string');
  assert.equal(prepared.physicalCid, cid(envelope));
  return envelope;
}

async function observeEncoding(operation, {splitFinal = false} = {}) {
  const {randomBytes, createCipheriv} = crypto;
  const stringify = JSON.stringify, from = Buffer.from;
  const counts = {jsonEnvelope: 0, stringEnvelopeCopy: 0, crypto: 0};
  crypto.randomBytes = size => size === 12 ? Buffer.alloc(12, 9) : randomBytes(size);
  crypto.createCipheriv = (...args) => {
    counts.crypto++;
    return cipherWithOptionalFinal(() => createCipheriv(...args), splitFinal);
  };
  JSON.stringify = function(value, ...args) {
    if (value?.version === 'actql-private-publication-evidence/0.1') counts.jsonEnvelope++;
    return Reflect.apply(stringify, JSON, [value, ...args]);
  };
  Buffer.from = function(...args) {
    if (typeof args[0] === 'string' && args[0].startsWith(
      '{"version":"actql-private-publication-evidence/0.1"')) counts.stringEnvelopeCopy++;
    return Reflect.apply(from, Buffer, args);
  };
  syncBuiltinESMExports();
  try { return {value: await operation(counts), counts}; }
  finally {
    crypto.randomBytes = randomBytes; crypto.createCipheriv = createCipheriv;
    JSON.stringify = stringify; Buffer.from = from;
    syncBuiltinESMExports();
  }
}

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-envelope-'));
  const configuration = {directory, storeAuthorityCid: cid('envelope authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1024 * 1024,
    maxObjectBytes: 16384, maxObjects: 32, maxContractNodes: 4096, maxContractDepth: 64};
  const control = createPublicationContractControlFixture();
  const stores = [];
  t.after(async () => {
    for (const store of stores) assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  const store = await openLocalPublicationStore(configuration, control);
  stores.push(store);
  return {configuration, control, stores, store};
}

test('private envelope: encoding completes synchronously before the writer wait', async t => {
  const {store} = await fixture(t);
  const input = Uint8Array.from([0, 255, 13]);
  const original = await oldEnvelope(input, {evidenceName: 'model_raw_content'});
  await observeEncoding(async counts => {
    const pending = store.prepareModelRawEvidence({semanticCid, holdingCid: cid('raw holding'),
      contentCid: cid(input), byteCount: input.byteLength, wire: ''}, input);
    const synchronousEncodes = counts.crypto;
    input.fill(88);
    const objects = await pending;
    try {
      assert.equal(synchronousEncodes, 1);
      assert.equal(objects[1].physicalCid, cid(original));
      assert.equal(objects[1].bytes, original.byteLength);
    } finally {
      for (const object of objects) assert.equal(await object.prepared.release(), true);
    }
  });
});

test('private envelope: fixed old bytes and CID without full JSON String backing', async t => {
  const {store} = await fixture(t);
  const rawBacking = Buffer.alloc(64, 88);
  rawBacking.set([0, 255, 13], 20);
  const inputs = ['', 'a', 'ab', 'abc', '{"p":null,"text":"é/e\u0301"}\r\n',
    rawBacking.subarray(20, 23), 'x'.repeat(12192)];
  for (const input of inputs) {
    const original = await oldEnvelope(input);
    const isWire = typeof input === 'string';
    const {value: current, counts} = await observeEncoding(() =>
      encodePrivateEvidenceEnvelope(input, isWire, Buffer.alloc(32, 7), aad(name, semanticCid), 16384));
    assert.deepEqual(current, original);
    assert.equal(cid(current), cid(original));
    const n = isWire ? Buffer.byteLength(input) : input.byteLength;
    assert.equal(current.byteLength, 128 + 4 * Math.ceil(n / 3));
    assert.deepEqual(counts, {jsonEnvelope: 0, stringEnvelopeCopy: 0, crypto: 1});
  }
  const {counts} = await observeEncoding(() =>
    assert.rejects(store.preparePrivateEvidence(name, 'x'.repeat(12193), semanticCid),
      {code: 'PublicationObjectLimit'}));
  assert.equal(counts.crypto, 0);
});

test('private envelope: nonempty crypto final preserves exact original serialization', async () => {
  const original = await oldEnvelope('abc', {splitFinal: true});
  const {value: current} = await observeEncoding(() =>
    encodePrivateEvidenceEnvelope('abc', true, Buffer.alloc(32, 7), aad(name, semanticCid), 16384),
  {splitFinal: true});
  assert.deepEqual(current, original);
  assert.equal(cid(current), cid(original));
  assert.equal(current.byteLength, 132);
});

test('private envelope: actual encrypted Store restart keeps old bytes/CID and no envelope copy', async t => {
  const {configuration, control, stores, store} = await fixture(t);
  const wire = '{"p":null,"text":"é/e\u0301"}\r\n';
  const original = await oldEnvelope(wire);
  const {value: prepared, counts} = await observeEncoding(() =>
    store.preparePrivateEvidence(name, wire, semanticCid));
  const holdingCid = cid('envelope original holding');
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid, manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}]}, [prepared.prepared]);
  assert.equal(await store.close(), true);
  const reopened = await openLocalPublicationStore(configuration, control);
  stores.push(reopened);
  assert.deepEqual(await reopened.readPrivateEvidence(name, semanticCid, holdingCid),
    Buffer.from(wire, 'utf8'));
  assert.equal(prepared.physicalCid, cid(original));
  assert.equal(prepared.bytes, original.byteLength);
  assert.equal(counts.jsonEnvelope, 0);
  assert.equal(counts.stringEnvelopeCopy, 0);
});
