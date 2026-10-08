import assert from 'node:assert/strict';

// Authored acceptance scopes, independent of the claim or reported test count.
// A marker is emitted only after intermediate and final observations succeed.
export const bridgeCases = Object.freeze([
  {case: 'empty-number', clock: 'number', rows: 0},
  {case: 'nullable-number', clock: 'number', rows: 2},
  {case: 'duplicate-payload-number', clock: 'number', rows: 2},
  {case: 'timestamp-original-text', clock: 'timestamp', rows: 1},
].map(Object.freeze));
const prefix = 'ACTQL_EVENTS_BRIDGE:';

export function observeBridgeCases(output, status) {
  assert.equal(status, 0, 'Failed Bridge observation');
  const observed = output.split(/\r?\n/u).filter(line => line.startsWith(prefix))
    .map(line => JSON.parse(line.slice(prefix.length)));
  assert.deepEqual(observed, bridgeCases, 'Incomplete or changed actual Bridge cases');
  return observed;
}
