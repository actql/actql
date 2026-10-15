// Real encrypted Store and physical bytes. Portable contract control is a
// double: these authored bindings issue no Core receipt or capacity grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createCipheriv, createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const key = Buffer.alloc(32, 7);
const kinds = ['retention_contract', 'metadata_retention_policy', 'clock_contract', 'data_policy'];
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-raw-comparison-'));
  const authority = cid('independent comparison authority');
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: authority,
    privateEvidenceKey: key, capacityBytes: 1048576, maxObjectBytes: 16384,
    maxObjects: 64, maxContractNodes: 4096, maxContractDepth: 64},
  createPublicationContractControlFixture());
  let passed = false;
  t.after(async () => {
    assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Original comparison failure retained: ${directory}`);
  });
  return {store, authority, pass() { passed = true; }};
}

// Observe only the comparison operand, not arbitrary pooled runtime buffers.
// This diagnostic extends its lifetime; it proves extent/identity, not GC.
function observeComparison(wires) {
  const expected = wires.map(wire => Buffer.from(wire, 'utf8'));
  const equals = Buffer.prototype.equals;
  const comparisons = [];
  Buffer.prototype.equals = function(other) {
    const selected = expected.findIndex(bytes => equals.call(this, bytes) &&
      other instanceof Uint8Array && equals.call(other, bytes));
    if (selected >= 0) comparisons.push({wire: wires[selected], operand: other});
    return equals.call(this, other);
  };
  return {comparisons, restore() { Buffer.prototype.equals = equals; }};
}
function exactOperand(item) {
  const length = Buffer.byteLength(item.wire, 'utf8');
  assert.equal(item.operand.byteLength, length);
  assert.equal(item.operand.byteOffset, 0, 'comparison must not borrow a pool slice');
  assert.equal(item.operand.buffer.byteLength, length,
    'the original supplier prices the backing, not only the comparison view');
}
async function commitRaw(store, binding, bytes) {
  const prepared = await store.prepareModelRawEvidence(binding, bytes);
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: binding.holdingCid,
    manifest_cid: binding.semanticCid,
    objects: prepared.map(object => ({cid: object.physicalCid, byte_count: object.bytes}))},
  prepared.map(object => object.prepared));
}

test('raw descriptor comparison uses exact dedicated UTF8 bytes including empty and boundary wire',
  async t => {
    const f = await fixture(t);
    const raw = Uint8Array.of(0, 255, 13);
    const wires = ['', 'a', 'e\u0301\r\n', '\u00e9\n', '\0\u{1f4a1}', 'x'.repeat(12192)];
    for (const [index, wire] of wires.entries()) {
      const binding = {semanticCid: cid(`descriptor comparison ${index}`),
        holdingCid: cid(`descriptor comparison holding ${index}`), wire,
        contentCid: cid(raw), byteCount: raw.byteLength};
      await commitRaw(f.store, binding, raw);
      const probe = observeComparison([wire]);
      try {
        assert.deepEqual(await f.store.readModelRawEvidence(binding), raw);
        assert.equal(probe.comparisons.length, 1);
        exactOperand(probe.comparisons[0]);
      } finally { probe.restore(); }
    }
    f.pass();
  });

test('selected original comparisons keep exact Unicode and dedicated per-wire workspace', async t => {
  const f = await fixture(t);
  const originals = kinds.map(kind => {
    const wire = JSON.stringify({kind, text: 'e\u0301\r\n\0\u{1f4a1}'});
    return {kind, wire, cid: cid(wire)};
  });
  for (const original of originals) await f.store.putSemantic(original.wire, original.cid);
  const probe = observeComparison(originals.map(value => value.wire));
  try {
    assert.equal(await f.store.confirmModelRawCaptureOriginals(originals, f.authority), true);
    assert.equal(probe.comparisons.length, 4);
    probe.comparisons.forEach(exactOperand);
    assert.equal(new Set(probe.comparisons.map(item => item.operand.buffer)).size, 4);
  } finally { probe.restore(); }
  // Matching policy/CID does not permit canonicalizing data values or newlines.
  for (const changed of ['\u00e9\r\n\0\u{1f4a1}', 'e\u0301\n\0\u{1f4a1}', 'different length']) {
    const wrong = originals.map((value, index) => index === 0
      ? {...value, wire: JSON.stringify({kind: value.kind, text: changed})} : value);
    await assert.rejects(f.store.confirmModelRawCaptureOriginals(wrong, f.authority),
      {code: 'PublicationModelRawOriginalMismatch'});
  }
  f.pass();
});

// Independent encrypted input: do not ask the product encoder to produce an
// expected malformed byte sequence or reinterpret it as replacement text.
function independentEnvelope(bytes, name, semanticCid, ordinal) {
  const nonce = Buffer.alloc(12, ordinal);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`));
  const ciphertext = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return Buffer.from(JSON.stringify({version: 'actql-private-publication-evidence/0.1',
    nonce: nonce.toString('base64'), tag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64')}));
}
test('raw descriptor comparison rejects independent malformed truncated and unequal byte sequences',
  async t => {
    const f = await fixture(t);
    const raw = Uint8Array.of(0, 255, 13);
    const cases = [
      {bytes: Uint8Array.of(0xc3), wire: '\ufffd'},
      {bytes: Uint8Array.of(0xc3, 0x28), wire: '\ufffd('},
      {bytes: Uint8Array.of(0xf0, 0x9f, 0x92), wire: '\ufffd'},
      {bytes: Uint8Array.of(0x61, 0), wire: 'a'},
      {bytes: Uint8Array.of(0x61, 0x62, 0x63), wire: 'abd'},
      {bytes: Uint8Array.of(0x65, 0xcc, 0x81), wire: '\u00e9'},
      {bytes: Uint8Array.of(13), wire: '\n'},
    ];
    for (const [index, item] of cases.entries()) {
      const binding = {semanticCid: cid(`independent malformed descriptor ${index}`),
        holdingCid: cid(`independent malformed descriptor holding ${index}`), wire: item.wire,
        contentCid: cid(raw), byteCount: raw.byteLength};
      const objects = [];
      for (const [name, bytes] of [['model_raw_descriptor', item.bytes], ['model_raw_content', raw]]) {
        const wire = independentEnvelope(bytes, name, binding.semanticCid, index + 1);
        const writer = f.store.createPreparedObjectWriter(wire.byteLength);
        await writer.append(wire);
        const object = await writer.seal(cid(wire));
        objects.push(object);
      }
      await f.store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
        namespace: 'publication-private', holding_cid: binding.holdingCid,
        manifest_cid: binding.semanticCid,
        objects: objects.map(object => ({cid: object.cid, byte_count: object.bytes}))},
      objects.map(object => object.prepared));
      await assert.rejects(f.store.readModelRawEvidence(binding),
        {code: 'PublicationPrivateEvidenceConflict'});
    }
    f.pass();
  });
