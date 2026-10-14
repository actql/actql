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
const productSource = readFileSync(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = productSource.indexOf('  const preparePrivateEvidenceInput =');
const end = productSource.indexOf('  const preparePrivateEvidenceBytes =', start);
assert.ok(start >= 0 && end > start);
const encoderStart = productSource.indexOf('function encodePrivateEvidenceEnvelope(');
const encoderEnd = productSource.indexOf('\nasync function syncDirectoryPath', encoderStart);
assert.ok(encoderStart >= 0 && encoderEnd > encoderStart);
const currentSource = productSource.slice(encoderStart, encoderEnd) + '\n' +
  productSource.slice(start, end);

function encoder(source, {splitFinal = false, failAppend = false, pauseAppend = false} = {}) {
  const counts = {jsonEnvelope: 0, stringEnvelopeCopy: 0, crypto: 0, cancel: 0};
  let envelope;
  const BufferView = new Proxy(Buffer, {get(target, key) {
    if (key !== 'from') return Reflect.get(target, key);
    return (...args) => {
      if (typeof args[0] === 'string' && args[0].startsWith(
        '{"version":"actql-private-publication-evidence/0.1"')) {
        counts.stringEnvelopeCopy++;
      }
      return Buffer.from(...args);
    };
  }});
  const json = {stringify(value, ...args) {
    if (value?.version === 'actql-private-publication-evidence/0.1') {
      counts.jsonEnvelope++;
    }
    return JSON.stringify(value, ...args);
  }};
  const primary = new Error('independent append failure');
  const cleanup = new Error('independent cancel failure');
  let resumeAppend, enteredAppend;
  const appendEntered = new Promise(resolve => { enteredAppend = resolve; });
  const appendGate = new Promise(resolve => { resumeAppend = resolve; });
  const prepare = runInNewContext(source + '\npreparePrivateEvidenceInput;', {
    Buffer: BufferView, Uint8Array, JSON: json,
    active() {}, configuration: {maxObjectBytes: 16384},
    cidHex(value) { assert.equal(value, semanticCid); },
    fail(code) { throw Object.assign(new Error(code), {code}); },
    privateEvidenceKey: () => Buffer.alloc(32, 7), privateEvidenceAad: aad,
    randomBytes: size => { assert.equal(size, 12); return Buffer.alloc(12, 9); },
    createCipheriv(...args) {
      counts.crypto++;
      const cipher = crypto.createCipheriv(...args);
      if (!splitFinal) return cipher;
      // A backend double supplies a nonempty final block without changing
      // total authenticated ciphertext. Preserve the existing fallback.
      let tail;
      const update = cipher.update.bind(cipher), final = cipher.final.bind(cipher);
      cipher.update = bytes => {
        const result = update(bytes);
        tail = result.subarray(-1);
        return result.subarray(0, -1);
      };
      cipher.final = () => { assert.equal(final().length, 0); return tail; };
      return cipher;
    },
    createPreparedObjectWriter(expected) {
      return {
        async append(bytes) {
          if (failAppend) throw primary;
          assert.equal(bytes.length, expected);
          envelope = Buffer.from(bytes);
          enteredAppend();
          if (pauseAppend) await appendGate;
        },
        async seal() { return {cid: cid(envelope), bytes: expected, prepared: {}}; },
        async cancel() { counts.cancel++; throw cleanup; },
        status: () => ({reservationHeld: failAppend, custodyPending: false,
          cleanupPending: failAppend}),
      };
    },
  });
  return {prepare, counts, primary, cleanup, envelope: () => envelope,
    appendEntered, resumeAppend};
}

test('private envelope: encoding completes synchronously before the writer wait', async () => {
  // The original input remains separately owned. Mutating this test-owned
  // backing after append entry cannot alter the already encoded envelope.
  const input = Uint8Array.from([0, 255, 13]);
  const original = encoder(originalSource);
  await original.prepare(name, input, semanticCid, false);
  const current = encoder(currentSource, {pauseAppend: true});
  const operation = current.prepare(name, input, semanticCid, false);
  await current.appendEntered;
  try {
    assert.equal(current.counts.crypto, 1);
    assert.deepEqual(current.envelope(), original.envelope());
    input.fill(88);
    assert.deepEqual(current.envelope(), original.envelope());
  } finally { current.resumeAppend(); }
  const prepared = await operation;
  assert.equal(prepared.physicalCid, cid(original.envelope()));
  // A source boundary check, not a GC/heap proof or a writer ACK. The helper
  // returns only the original complete Buffer and cannot suspend or create IO.
  const synchronous = productSource.slice(encoderStart, encoderEnd);
  assert.match(synchronous, /^function encodePrivateEvidenceEnvelope\(/u);
  assert.doesNotMatch(synchronous, /\bawait\b|createPreparedObjectWriter/u);
  assert.match(synchronous, /return envelope;/u);
});

test('private envelope: fixed old bytes and CID without full JSON String backing', async () => {
  const rawBacking = Buffer.alloc(64, 88);
  rawBacking.set([0, 255, 13], 20);
  const inputs = ['', 'a', 'ab', 'abc', '{"p":null,"text":"é/e\u0301"}\r\n',
    rawBacking.subarray(20, 23), 'x'.repeat(12192)];
  for (const input of inputs) {
    const old = encoder(originalSource), current = encoder(currentSource);
    const isWire = typeof input === 'string';
    const before = await old.prepare(name, input, semanticCid, isWire);
    const after = await current.prepare(name, input, semanticCid, isWire);
    assert.deepEqual(current.envelope(), old.envelope());
    assert.equal(after.physicalCid, before.physicalCid);
    const n = isWire ? Buffer.byteLength(input) : input.byteLength;
    assert.equal(after.bytes, 128 + 4 * Math.ceil(n / 3));
    assert.equal(old.counts.jsonEnvelope, 1);
    assert.equal(old.counts.stringEnvelopeCopy, 1);
    assert.equal(current.counts.jsonEnvelope, 0);
    assert.equal(current.counts.stringEnvelopeCopy, 0);
  }
  const current = encoder(currentSource);
  await assert.rejects(current.prepare(name, 'x'.repeat(12193), semanticCid, true),
    {code: 'PublicationObjectLimit'});
  assert.equal(current.counts.crypto, 0);
});

test('private envelope: nonempty crypto final preserves exact original serialization', async () => {
  const old = encoder(originalSource, {splitFinal: true});
  const current = encoder(currentSource, {splitFinal: true});
  const before = await old.prepare(name, 'abc', semanticCid, true);
  const after = await current.prepare(name, 'abc', semanticCid, true);
  assert.deepEqual(current.envelope(), old.envelope());
  assert.equal(after.physicalCid, before.physicalCid);
  assert.equal(after.bytes, 132);
});

test('private envelope: append failure retains original primary and cleanup cause', async () => {
  const current = encoder(currentSource, {failAppend: true});
  await assert.rejects(current.prepare(name, 'abc', semanticCid, true), error => {
    assert.equal(error, current.primary);
    assert.equal(error.cleanupFailure, current.cleanup);
    return true;
  });
  assert.equal(current.counts.cancel, 1);
});

test('private envelope: actual encrypted Store restart keeps old bytes/CID and no envelope copy', async t => {
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
  const wire = '{"p":null,"text":"é/e\u0301"}\r\n';
  const old = encoder(originalSource);
  const expected = await old.prepare(name, wire, semanticCid, true);
  const randomBytes = crypto.randomBytes, stringify = JSON.stringify, from = Buffer.from;
  let jsonEnvelope = 0, stringEnvelopeCopy = 0;
  crypto.randomBytes = size => size === 12 ? Buffer.alloc(12, 9) : randomBytes(size);
  JSON.stringify = function(value, ...args) {
    if (value?.version === 'actql-private-publication-evidence/0.1') jsonEnvelope++;
    return Reflect.apply(stringify, JSON, [value, ...args]);
  };
  Buffer.from = function(...args) {
    if (typeof args[0] === 'string' && args[0].startsWith(
      '{"version":"actql-private-publication-evidence/0.1"')) stringEnvelopeCopy++;
    return Reflect.apply(from, Buffer, args);
  };
  syncBuiltinESMExports();
  let prepared;
  try { prepared = await store.preparePrivateEvidence(name, wire, semanticCid); }
  finally {
    crypto.randomBytes = randomBytes; JSON.stringify = stringify; Buffer.from = from;
    syncBuiltinESMExports();
  }
  const holdingCid = cid('envelope original holding');
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid, manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}]}, [prepared.prepared]);
  assert.equal(await store.close(), true);
  const reopened = await openLocalPublicationStore(configuration, control);
  stores.push(reopened);
  assert.deepEqual(await reopened.readPrivateEvidence(name, semanticCid, holdingCid),
    Buffer.from(wire, 'utf8'));
  assert.equal(prepared.physicalCid, expected.physicalCid);
  assert.equal(prepared.bytes, expected.bytes);
  assert.equal(jsonEnvelope, 0);
  assert.equal(stringEnvelopeCopy, 0);
});
