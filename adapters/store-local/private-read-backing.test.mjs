// Actual encrypted Store and Node crypto; portable contract control is a
// double. Exact backing extent is not a complete Model funding declaration.
import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = value => `sha256:${crypto.createHash('sha256').update(value).digest('hex')}`;
const name = 'model_invocation_evidence';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-read-backing-'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('private read backing authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1048576, maxObjectBytes: 16384, maxObjects: 32,
    maxContractNodes: 4096, maxContractDepth: 64}, createPublicationContractControlFixture());
  let passed = false;
  t.after(async () => {
    assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved original read-backing failure: ${directory}`);
  });
  return {store, pass() { passed = true; }};
}

async function commit(store, object, semanticCid, holdingCid) {
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid, manifest_cid: semanticCid,
    objects: [{cid: object.physicalCid ?? object.cid, byte_count: object.bytes}]},
  [object.prepared]);
}

function observeDecipher(t) {
  const original = crypto.createDecipheriv;
  const inputs = [];
  crypto.createDecipheriv = (...args) => {
    const entry = {key: args[1], nonce: args[2]};
    inputs.push(entry);
    const decipher = Reflect.apply(original, crypto, args);
    const update = decipher.update, setTag = decipher.setAuthTag;
    decipher.setAuthTag = function(tag, ...rest) {
      entry.tag = tag;
      return Reflect.apply(setTag, this, [tag, ...rest]);
    };
    decipher.update = function(bytes, ...rest) {
      entry.ciphertext = bytes;
      return Reflect.apply(update, this, [bytes, ...rest]);
    };
    return decipher;
  };
  syncBuiltinESMExports();
  const restore = () => { crypto.createDecipheriv = original; syncBuiltinESMExports(); };
  t.after(restore);
  return {inputs, restore};
}

test('private read key and Base64 fields have exact dedicated backings and original key retirement', async t => {
  const f = await fixture(t);
  const probe = observeDecipher(t);
  try {
    for (const [index, wire] of ['', 'a', '{"p":null,"text":"e\u0301"}\r\n'].entries()) {
      const semantic = cid(`private read semantic ${index}`);
      const holding = cid(`private read original holding ${index}`);
      const object = await f.store.preparePrivateEvidence(name, wire, semantic);
      await commit(f.store, object, semantic, holding);
      const restored = await f.store.readPrivateEvidence(name, semantic, holding);
      assert.deepEqual(restored, Buffer.from(wire, 'utf8'));
      const original = probe.inputs.at(-1);
      for (const [field, length] of [['key', 32], ['nonce', 12], ['tag', 16],
        ['ciphertext', Buffer.byteLength(wire, 'utf8')]]) {
        assert.equal(original[field].byteLength, length);
        assert.equal(original[field].byteOffset, 0, `${field} must not borrow a pool slice`);
        assert.equal(original[field].buffer.byteLength, length,
          `${field} backing must match the independent extent`);
      }
      assert.deepEqual(original.key, Buffer.alloc(32), 'same temporary key is zeroed after read');
      assert.notEqual(original.key.buffer, original.nonce.buffer);
      assert.notEqual(original.nonce.buffer, original.tag.buffer);
    }
  } finally { probe.restore(); }
  f.pass();
  // Instrumentation extends these buffer references through test completion.
  // It does not prove production GC, a Store ACK or a whole-phase upper bound.
});

test('private read still rejects malformed and noncanonical Base64 before crypto', async t => {
  const f = await fixture(t);
  const probe = observeDecipher(t);
  try {
    // Independently authored closed shape. Physical bytes/CID/holding are
    // genuine; invalid encrypted fields must fail before the crypto decoder.
    const original = {version: 'actql-private-publication-evidence/0.1',
      nonce: 'AAAAAAAAAAAAAAAA', tag: 'AAAAAAAAAAAAAAAAAAAAAA==', ciphertext: ''};
    for (const [index, [field, value]] of [
      ['nonce', 'AAA='], ['tag', 'AAAA'], ['ciphertext', 'AAA'],
      ['ciphertext', 'AB=='], ['ciphertext', 'AA A='],
    ].entries()) {
      const bytes = Buffer.from(JSON.stringify({...original, [field]: value}));
      const writer = f.store.createPreparedObjectWriter(bytes.length);
      await writer.append(bytes);
      const object = await writer.seal();
      const semantic = cid(`invalid Base64 semantic ${index}`);
      const holding = cid(`invalid Base64 original holding ${index}`);
      await commit(f.store, object, semantic, holding);
      await assert.rejects(f.store.readPrivateEvidence(name, semantic, holding),
        {code: 'PublicationPrivateEvidenceCorrupt'});
      assert.equal(probe.inputs.length, 0);
    }
  } finally { probe.restore(); }
  f.pass();
});
