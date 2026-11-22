import assert from 'node:assert/strict';
import test from 'node:test';
import {installedRowUpdateRequestWires, packInstalledRowUpdateRecovery,
  restoreInstalledRowUpdateMembers, unpackInstalledRowUpdateRecovery} from './installed-row-update-recovery.mjs';

test('update recovery retains original global indexes before restoring any selected member', () => {
  const first = Object.freeze({memberIndex: 1}), last = Object.freeze({memberIndex: 3});
  const context = {members: [{}, {}, {}, {}], recorded: {members: [{}, {}, {}, {}]},
    memberIndexes: [1, 3], durable: {connectorRecovery: [last, first]}};
  const seen = [];
  const requests = restoreInstalledRowUpdateMembers(context, 4, 'InvalidOriginal', (original, index, entry) => {
    assert.equal(original, context);
    seen.push(entry);
    return [context.members[index]];
  });
  assert.deepEqual(seen, [first, last]);
  assert.equal(requests.requests[0][0], context.members[1]);
  assert.equal(requests.requests[1][0], context.members[3]);
  const sparse = new Array(2);
  sparse[1] = 3;
  const restored = restoreInstalledRowUpdateMembers({...context, memberIndexes: sparse}, 4, 'InvalidOriginal',
    (_original, index, entry) => {
      assert.equal(index, 3);
      assert.equal(entry, last);
      return [context.members[index]];
    });
  assert.equal(restored.requests.length, 2);
  assert.equal(0 in restored.requests, false);
  assert.equal(restored.requests[1][0], context.members[3]);
  for (const invalid of [
    {...context, memberIndexes: [3, 1]},
    {...context, memberIndexes: [1, 1]},
    {...context, durable: {connectorRecovery: [first, first]}},
    {...context, durable: {connectorRecovery: [first, {memberIndex: 4}]}},
  ]) {
    assert.throws(() => restoreInstalledRowUpdateMembers(invalid, 4, 'InvalidOriginal', () => {
      throw new Error('Invalid selection reached the connector codec');
    }), {code: 'InvalidOriginal'});
  }
});

test('update recovery keeps the exact bounded provider wire and rejects foreign requests and malformed envelopes', () => {
  const wire = '{"binding":{"origin":"provider.example"},"member":{"effectId":"update"},"requests":["request-wire"],"version":"codec"}';
  const digest = 'sha256:ed238ff90ed70fb2f42e8b134e92f687146d71c34d318927157f47ef8295aea7';
  const request = Object.freeze({});
  let encoded = 0;
  const codec = {
    requestCid(value) {assert.equal(value, request); return 'original';},
    savedWire(value) {assert.equal(value, request); encoded++; return 'request-wire';},
  };
  assert.throws(() => installedRowUpdateRequestWires([{request, requestCid: 'foreign'}], 1,
    codec, 'Invalid', 'Foreign'), {code: 'Foreign'});
  assert.equal(encoded, 0);
  const requests = installedRowUpdateRequestWires([{request, requestCid: 'original'}], 1,
    codec, 'Invalid', 'Foreign');
  assert.equal(encoded, 1);
  const data = {version: 'codec', binding: {origin: 'provider.example'},
    member: {effectId: 'update'}, requests};
  const saved = packInstalledRowUpdateRecovery('provider-update', data, wire.length, 'Limit');
  assert.deepEqual(saved, {kind: 'provider-update', observationCid: digest, wire});
  assert.throws(() => packInstalledRowUpdateRecovery('provider-update', data, wire.length - 1, 'Limit'),
    {code: 'Limit'});
  assert.deepEqual(unpackInstalledRowUpdateRecovery(saved, saved.kind, wire.length, [{}], [{}], 1, 'Invalid'), data);
  assert.throws(() => unpackInstalledRowUpdateRecovery(saved, saved.kind, wire.length - 1, [{}], [{}], 1, 'Invalid'),
    {code: 'Invalid'});
  assert.throws(() => unpackInstalledRowUpdateRecovery({...saved, wire: 'invalid'}, saved.kind,
    wire.length, [{}], [{}], 1, 'Invalid'), {code: 'Invalid'});
  assert.throws(() => unpackInstalledRowUpdateRecovery(saved, saved.kind, wire.length, [{}], [], 1, 'Invalid'),
    {code: 'Invalid'});
});
