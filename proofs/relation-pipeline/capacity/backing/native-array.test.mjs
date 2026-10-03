import test from 'node:test';
import assert from 'node:assert/strict';
import { arrayStorageExtent, inspectNativeArrays } from './native-array.mjs';
const d = (owner, backing, slots, elementBytes, length = slots) => ({
  owner, backing, slots, length, elementBytes, ownerBytes: '24',
  backingBytes: String(8 + elementBytes * slots), ownerStatic: false, backingStatic: slots === 0,
});
function fixture() {
  return { inputNames: d('1', '2', 3, 8), outputNames: d('3', '4', 3, 8), sortedIndices: d('5', '6', 8, 4, 3) };
}
const capacities = { inputNames: 3, outputNames: 3, sortedIndices: 8 };
const ceilings = { inputNames: 3n, outputNames: 3n, sortedIndices: 8n };
test('array extents derive from declared fields and typed runtime allocation, not a measured maximum', () => {
  assert.equal(arrayStorageExtent('int', 8), 64n);
  assert.equal(arrayStorageExtent('reference', 3), 56n);
  assert.throws(() => arrayStorageExtent('Value', 3), /Unreviewed/);
  assert.throws(() => arrayStorageExtent('int', 2147483648));
  const claim = inspectNativeArrays(fixture(), capacities, ceilings);
  assert.equal(claim.uniqueStorageBytes, '176');
  assert.equal(claim.dynamicRequestedBytes, '176');
  assert.equal(claim.inputDerivedBound, '176');
  assert.equal(claim.completeLifetimeUnion, false);
  assert.equal(claim.unconditionalAllocationBytes, false);
});
test('a shared real owner/backing is counted once; copies count independently', () => {
  const observed = fixture(); observed.outputNames = structuredClone(observed.inputNames);
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '120');
  observed.outputNames.owner = '3';
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '144');
  observed.outputNames.backing = '4';
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '176');
});
test('shared empty singleton storage is separate from dynamic requested extents', () => {
  const observed = { inputNames: d('1', '2', 0, 8), outputNames: d('3', '2', 0, 8), sortedIndices: null };
  const c = { inputNames: 0, outputNames: 0, sortedIndices: 0 };
  const b = { inputNames: 0n, outputNames: 0n, sortedIndices: 0n };
  const claim = inspectNativeArrays(observed, c, b);
  assert.equal(claim.uniqueStorageBytes, '56');
  assert.equal(claim.dynamicRequestedBytes, '48');
  assert.equal(claim.staticStorageBytes, '8');
  assert.equal(claim.inputDerivedBound, '64');
});
test('missing backing, underbound extents and inconsistent aliases cannot issue a selected-array claim', () => {
  for (const mutate of [o => delete o.inputNames.backing,
    o => o.inputNames.backingBytes = '24', o => o.sortedIndices.elementBytes = 8,
    o => o.sortedIndices.backingStatic = true, o => o.sortedIndices.backing = o.inputNames.backing,
    o => o.sortedIndices.slots = 9, o => o.sortedIndices = null]) {
    const observed = fixture(); mutate(observed);
    assert.throws(() => inspectNativeArrays(observed, capacities, ceilings));
  }
});
