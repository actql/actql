import assert from 'node:assert/strict';
import test from 'node:test';
import {restoreInstalledRowUpdateMembers} from './installed-row-update-recovery.mjs';

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
