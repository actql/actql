// Actual Store/crypto; portable contract control remains an explicit double.
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

test('private raw content and descriptor AAD have exact distinct backings through Store reopen', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-aad-backing-'));
  const configuration = {directory, storeAuthorityCid: cid('AAD backing authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1048576,
    maxObjectBytes: 16384, maxObjects: 40, maxContractNodes: 1000, maxContractDepth: 30};
  const control = createPublicationContractControlFixture();
  const stores = [], pending = [];
  let passed = false;
  const originalCipher = crypto.createCipheriv, originalDecipher = crypto.createDecipheriv;
  const aads = [];
  function observe(original) {
    return (...args) => {
      const operation = Reflect.apply(original, crypto, args);
      const setAAD = operation.setAAD;
      operation.setAAD = function(bytes, ...rest) {
        aads.push(bytes);
        return Reflect.apply(setAAD, this, [bytes, ...rest]);
      };
      return operation;
    };
  }
  crypto.createCipheriv = observe(originalCipher);
  crypto.createDecipheriv = observe(originalDecipher);
  syncBuiltinESMExports();
  const restore = () => {
    crypto.createCipheriv = originalCipher; crypto.createDecipheriv = originalDecipher;
    syncBuiltinESMExports();
  };
  t.after(async () => {
    restore();
    for (const object of pending) await object.prepared.release();
    for (const store of stores) assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved original AAD-backing failure: ${directory}`);
  });
  const store = await openLocalPublicationStore(configuration, control);
  stores.push(store);
  const raw = Buffer.alloc(8192);
  for (let index = 0; index < raw.length; index++) raw[index] = index % 251;
  const binding = {semanticCid: cid('original AAD semantic'),
    holdingCid: cid('original AAD holding'), wire: '{"reason":null,"risk":"e\u0301"}\r\n',
    byteCount: raw.length, contentCid: cid(raw)};
  const prepared = await store.prepareModelRawEvidence(binding, raw);
  pending.push(...prepared);
  function verify(bytes, name) {
    // Independently authored historical preimage, not the product helper.
    const expected = Buffer.from('actql-private-publication-evidence/0.1\0' +
      name + '\0' + binding.semanticCid, 'utf8');
    assert.deepEqual(bytes, expected);
    assert.equal(bytes.byteOffset, 0, 'AAD must not borrow a shared pool slice');
    assert.equal(bytes.buffer.byteLength, expected.length, 'price the backing, not the view');
  }
  assert.equal(aads.length, 2);
  verify(aads[0], 'model_raw_content');
  verify(aads[1], 'model_raw_descriptor');
  assert.notEqual(aads[0].buffer, aads[1].buffer);
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: binding.holdingCid,
    manifest_cid: binding.semanticCid,
    objects: prepared.map(object => ({cid: object.physicalCid, byte_count: object.bytes}))},
  prepared.map(object => object.prepared));
  for (const object of pending.splice(0)) await object.prepared.release();
  assert.equal(await store.close(), true);
  const reopened = await openLocalPublicationStore(configuration, control);
  stores.push(reopened);
  assert.deepEqual(await reopened.readModelRawEvidence(binding), raw);
  assert.equal(aads.length, 4);
  verify(aads[2], 'model_raw_descriptor');
  verify(aads[3], 'model_raw_content');
  assert.equal(new Set(aads.map(bytes => bytes.buffer)).size, 4);
  t.diagnostic(JSON.stringify({aadBytes: aads.map(bytes => bytes.length),
    aadBackingBytes: aads.map(bytes => bytes.buffer.byteLength),
    qualification: 'Actual crypto and reopened Store, Core contract-control double; no normal funding.',
    normalNumericProfile: null, publicE2E: 0}));
  passed = true;
});
