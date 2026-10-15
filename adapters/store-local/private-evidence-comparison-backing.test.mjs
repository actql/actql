// Real encrypted Store/FD/holding operations. Contract control is a double;
// authored bindings here issue no semantic Core receipt or capacity grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createCipheriv, createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const key = Buffer.alloc(32, 7);
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-private-comparison-'));
  const configuration = {directory, storeAuthorityCid: cid('original private comparison Store'),
    privateEvidenceKey: key, capacityBytes: 1048576, maxObjectBytes: 16384,
    maxObjects: 64, maxContractNodes: 4096, maxContractDepth: 64};
  const control = createPublicationContractControlFixture();
  const stores = [await openLocalPublicationStore(configuration, control)];
  let passed = false;
  t.after(async () => {
    for (const store of stores) assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Original private comparison failure retained: ${directory}`);
  });
  return {store: stores[0], configuration, control, stores, pass() { passed = true; }};
}
async function commit(store, binding) {
  const object = await store.preparePrivateEvidence(binding.name, binding.wire, binding.semanticCid);
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: binding.holdingCid,
    manifest_cid: binding.semanticCid,
    objects: [{cid: object.physicalCid, byte_count: object.bytes}]}, [object.prepared]);
}

test('private confirmation uses exact dedicated synchronous UTF8 comparison backing', async t => {
  const f = await fixture(t);
  for (const [index, wire] of ['', 'a', 'e\u0301\r\n', '\u00e9\n', '\0\u{1f4a1}', 'x'.repeat(12192)].entries()) {
    const binding = {name: 'model_call_attempt', wire,
      semanticCid: cid(`original comparison ${index}`), holdingCid: cid(`original holding ${index}`)};
    await commit(f.store, binding);
    const expected = Buffer.from(wire, 'utf8');
    const equals = Buffer.prototype.equals;
    const operands = [];
    // Observe only this comparison operand. The diagnostic deliberately
    // extends its lifetime; it proves extent/identity, not collection or ACK.
    Buffer.prototype.equals = function(other) {
      if (other instanceof Uint8Array && equals.call(this, expected) && equals.call(other, expected)) {
        operands.push(other);
      }
      return equals.call(this, other);
    };
    try {
      assert.equal((await f.store.confirmPrivateEvidence(binding)).holding_cid, binding.holdingCid);
      assert.equal(operands.length, 1);
      assert.equal(operands[0].byteLength, expected.byteLength);
      assert.equal(operands[0].byteOffset, 0, 'comparison must not borrow a pool slice');
      assert.equal(operands[0].buffer.byteLength, expected.byteLength,
        'price the dedicated backing, not only the compared view');
    } finally { Buffer.prototype.equals = equals; }
  }
  f.pass();
});

function independentEnvelope(bytes, name, semanticCid, ordinal) {
  const cipher = createCipheriv('aes-256-gcm', key, Buffer.alloc(12, ordinal));
  cipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`));
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return Buffer.from(JSON.stringify({version: 'actql-private-publication-evidence/0.1',
    nonce: Buffer.alloc(12, ordinal).toString('base64'), tag: cipher.getAuthTag().toString('base64'),
    ciphertext: encrypted.toString('base64')}));
}

test('private confirmation keeps malformed truncated Unicode newline and unequal bytes distinct', async t => {
  const f = await fixture(t);
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
    const binding = {name: 'model_attempt_outcome', wire: item.wire,
      semanticCid: cid(`malformed original ${index}`), holdingCid: cid(`malformed holding ${index}`)};
    const bytes = independentEnvelope(item.bytes, binding.name, binding.semanticCid, index + 1);
    const writer = f.store.createPreparedObjectWriter(bytes.byteLength);
    await writer.append(bytes);
    const object = await writer.seal(cid(bytes));
    await f.store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private', holding_cid: binding.holdingCid,
      manifest_cid: binding.semanticCid,
      objects: [{cid: object.cid, byte_count: object.bytes}]}, [object.prepared]);
    await assert.rejects(f.store.confirmPrivateEvidence(binding), {code: 'PublicationPrivateEvidenceConflict'});
    await assert.rejects(f.store.confirmPrivateEvidence({...binding, name: 'model_call_attempt'}),
      {code: 'PublicationPrivateEvidenceCorrupt'});
  }
  f.pass();
});

test('private confirmation preserves same holding reconciliation after lost reply and reopen', async t => {
  const f = await fixture(t);
  const binding = {name: 'model_dispatch_authority', wire: 'original-e\u0301\r\n\0\u{1f4a1}',
    semanticCid: cid('lost original authority'), holdingCid: cid('lost original authority holding')};
  let commits = 0;
  const owner = preparePrivatePublicationHolding({
    confirmPrivateEvidence: value => f.store.confirmPrivateEvidence(value),
    preparePrivateEvidence: (...args) => f.store.preparePrivateEvidence(...args),
    async commitPhysicalHolding(...args) {
      commits++;
      await f.store.commitPhysicalHolding(...args);
      throw new Error('LostOriginalPrivateCommitReply');
    },
  }, binding);
  await owner.commit();
  await owner.retry();
  assert.equal(commits, 1);
  assert.equal(owner.status().committed, true);
  assert.equal(owner.status().preparedPending, false);
  assert.equal(await f.store.close(), true);
  const reopened = await openLocalPublicationStore(f.configuration, f.control);
  f.stores.push(reopened);
  const saved = await reopened.confirmPrivateEvidence(binding);
  assert.equal(saved.holding_cid, binding.holdingCid);
  assert.equal(saved.manifest_cid, binding.semanticCid);
  assert.equal(commits, 1);
  assert.equal((await reopened.retirePhysicalHolding(binding.holdingCid)).deleted, true);
  assert.equal(reopened.status().reservedBytes, 0);
  assert.equal(reopened.status().storedBytes, 0);
  f.pass();
});

test('private confirmation rejects unequal wire length before allocating its comparison operand', async t => {
  const f = await fixture(t);
  const binding = {name: 'model_call_attempt', wire: 'a',
    semanticCid: cid('length-first original'), holdingCid: cid('length-first holding')};
  await commit(f.store, binding);
  const unequalWire = 'x'.repeat(f.configuration.maxObjectBytes + 1);
  const from = Buffer.from, allocate = Buffer.allocUnsafeSlow;
  let comparisons = 0;
  Buffer.from = function(value, ...args) {
    if (value === unequalWire) comparisons++;
    return Reflect.apply(from, this, [value, ...args]);
  };
  Buffer.allocUnsafeSlow = function(length) {
    if (length === unequalWire.length) comparisons++;
    return Reflect.apply(allocate, this, [length]);
  };
  try {
    await assert.rejects(f.store.confirmPrivateEvidence({...binding, wire: unequalWire}),
      {code: 'PublicationPrivateEvidenceConflict'});
    assert.equal(comparisons, 0, 'length mismatch must not encode or allocate the proposed wire');
  } finally {
    Buffer.from = from;
    Buffer.allocUnsafeSlow = allocate;
  }
  assert.equal((await f.store.confirmPrivateEvidence(binding)).holding_cid, binding.holdingCid);
  f.pass();
});
