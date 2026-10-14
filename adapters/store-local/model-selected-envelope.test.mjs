// Selected first-M1 physical Store component only. The contract control is
// explicitly a double; bytes/FD custody do not authenticate Model admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

test('selected raw8192 and descriptor12192 keep exact distinct envelope/snapshot backings through original writes and restart', async t => {
  // Independently fixed selected extents, not numbers measured from output.
  // E(8192)=11052; E(12192)=16384; E(12193)>16384.
  const raw = Buffer.alloc(8192);
  for (let index = 0; index < raw.length; index++) raw[index] = index % 256;
  const original = Buffer.from(raw);
  const descriptor = '{"reason":null,"risk":"e\u0301"}\r\n' + ' '.repeat(12162);
  assert.equal(Buffer.byteLength(descriptor), 12192);
  const directory = await fs.mkdtemp(join(tmpdir(), 'actql-c-selected-envelope-'));
  const configuration = {directory, storeAuthorityCid: cid('selected Store authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1048576,
    maxObjectBytes: 16384, maxObjects: 40, maxContractNodes: 1000, maxContractDepth: 30};
  const control = createPublicationContractControlFixture();
  const stores = [];
  const store = await openLocalPublicationStore(configuration, control);
  stores.push(store);
  const binding = Object.freeze({semanticCid: cid('selected raw descriptor identity'),
    holdingCid: cid('selected original holding'), wire: descriptor,
    byteCount: 8192, contentCid: cid(original)});
  const alloc = Buffer.alloc, slow = Buffer.allocUnsafeSlow, open = fs.open;
  const envelopes = [], snapshots = [], writes = [];
  let enter, release, passed = false, prepared;
  const entered = new Promise(resolve => { enter = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  Buffer.alloc = function(size, ...args) {
    const bytes = Reflect.apply(alloc, Buffer, [size, ...args]);
    if (size === 11052 || size === 16384) envelopes.push(bytes);
    return bytes;
  };
  Buffer.allocUnsafeSlow = function(size) {
    const bytes = Reflect.apply(slow, Buffer, [size]);
    if (size === 11052 || size === 16384) snapshots.push(bytes);
    return bytes;
  };
  fs.open = async (...args) => {
    const handle = await Reflect.apply(open, fs, args);
    if (!String(args[0]).startsWith(join(directory, 'staging', 'object-'))) return handle;
    return new Proxy(handle, {get(target, name) {
      if (name === 'write') return async (...writeArgs) => {
        writes.push(writeArgs[0]);
        if (writes.length === 1) { enter(); await gate; }
        return await target.write(...writeArgs);
      };
      const value = Reflect.get(target, name, target);
      return typeof value === 'function' ? value.bind(target) : value;
    }});
  };
  syncBuiltinESMExports();
  const restore = () => {
    Buffer.alloc = alloc; Buffer.allocUnsafeSlow = slow; fs.open = open;
    syncBuiltinESMExports();
  };
  t.after(async () => {
    release(); restore();
    if (prepared !== undefined) for (const object of prepared) await object.prepared.release();
    for (const current of stores) assert.equal(await current.close(), true);
    if (passed) await fs.rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved selected Store failure: ${directory}`);
  });
  const pending = store.prepareModelRawEvidence(binding, raw);
  try {
    await entered;
    assert.equal(envelopes.length, 1);
    assert.equal(snapshots.length, 1);
    assert.equal(writes[0], snapshots[0]);
    assert.notEqual(raw.buffer, envelopes[0].buffer);
    assert.notEqual(envelopes[0].buffer, snapshots[0].buffer);
    assert.deepEqual([raw.buffer.byteLength, envelopes[0].buffer.byteLength,
      snapshots[0].buffer.byteLength], [8192, 11052, 11052]);
    assert.equal(store.status().reservedBytes, 11052);
    // The producer still owns this input. Its later mutation cannot modify
    // the encrypted snapshot already queued for the SAME original writer.
    raw.fill(88);
  } finally { release(); }
  try { prepared = await pending; } finally { restore(); }
  assert.deepEqual(envelopes.map(bytes => bytes.byteLength), [11052, 16384]);
  assert.deepEqual(snapshots.map(bytes => bytes.buffer.byteLength), [11052, 16384]);
  assert.equal(new Set([...envelopes, ...snapshots].map(bytes => bytes.buffer)).size, 4);
  assert.deepEqual(snapshots[0], envelopes[0]);
  assert.deepEqual(snapshots[1], envelopes[1]);
  assert.equal(prepared[0].bytes, 16384);
  assert.equal(prepared[1].bytes, 11052);
  assert.equal(prepared[0].physicalCid, cid(envelopes[1]));
  assert.equal(prepared[1].physicalCid, cid(envelopes[0]));
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: binding.holdingCid,
    manifest_cid: binding.semanticCid,
    objects: prepared.map(object => ({cid: object.physicalCid, byte_count: object.bytes}))},
  prepared.map(object => object.prepared));
  assert.equal(await store.close(), true);
  const reopened = await openLocalPublicationStore(configuration, control);
  stores.push(reopened);
  const restored = await reopened.readModelRawEvidence(binding);
  assert.deepEqual(restored, original);
  assert.equal(restored.byteLength, 8192);
  assert.notEqual(restored.buffer, raw.buffer);
  await assert.rejects(reopened.readModelRawEvidence({...binding,
    semanticCid: cid('foreign semantic identity')}), {code: 'PublicationPrivateEvidenceUnavailable'});
  passed = true;
  // Instrumentation retains the four observed buffers until this test ends.
  // That is not evidence that all four remain product-live simultaneously,
  // nor a bound on controls/Strings/crypto/metadata or immediate GC behavior.
});
