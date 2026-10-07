import test from 'node:test';
import assert from 'node:assert/strict';
import { arrayStorageExtent, inspectNativeArrays } from './native-array.mjs';
const d = (owner, backing, slots, elementBytes, length = slots) => ({
  owner, backing, slots, length, elementBytes, ownerBytes: '24',
  backingBytes: String(8 + elementBytes * slots), ownerStatic: false, backingStatic: slots === 0,
});
function fixture() {
  return { inputNames: d('1', '2', 3, 8), outputNames: d('3', '4', 3, 8), sortedIndices: d('5', '6', 8, 4, 3), snapshot: d('7', '8', 0, 8), rowSources: d('9', '8', 0, 8) };
}
const capacities = { inputNames: 3, outputNames: 3, sortedIndices: 8, snapshot: 0, rowSources: 0 };
const ceilings = { inputNames: 3n, outputNames: 3n, sortedIndices: 8n, snapshot: 0n, rowSources: 0n };
test('array extents derive from declared fields and typed runtime allocation, not a measured maximum', () => {
  assert.equal(arrayStorageExtent('int', 8), 64n);
  assert.equal(arrayStorageExtent('reference', 3), 56n);
  assert.throws(() => arrayStorageExtent('Value', 3), /Unreviewed/);
  assert.throws(() => arrayStorageExtent('int', 2147483648));
  const claim = inspectNativeArrays(fixture(), capacities, ceilings);
  assert.equal(claim.uniqueStorageBytes, '232');
  assert.equal(claim.dynamicRequestedBytes, '224');
  assert.equal(claim.inputDerivedBound, '240');
  assert.equal(claim.completeLifetimeUnion, false);
  assert.equal(claim.unconditionalAllocationBytes, false);
});
test('a shared real owner/backing is counted once; copies count independently', () => {
  const observed = fixture(); observed.outputNames = structuredClone(observed.inputNames);
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '176');
  observed.outputNames.owner = '3';
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '200');
  observed.outputNames.backing = '4';
  assert.equal(inspectNativeArrays(observed, capacities, ceilings).uniqueStorageBytes, '232');
});
test('shared empty singleton storage is separate from dynamic requested extents', () => {
  const observed = { inputNames: d('1', '2', 0, 8), outputNames: d('3', '2', 0, 8), sortedIndices: null, snapshot: d('4', '2', 0, 8), rowSources: d('5', '2', 0, 8) };
  const c = { inputNames: 0, outputNames: 0, sortedIndices: 0, snapshot: 0, rowSources: 0 };
  const b = { inputNames: 0n, outputNames: 0n, sortedIndices: 0n, snapshot: 0n, rowSources: 0n };
  const claim = inspectNativeArrays(observed, c, b);
  assert.equal(claim.uniqueStorageBytes, '104');
  assert.equal(claim.dynamicRequestedBytes, '96');
  assert.equal(claim.staticStorageBytes, '8');
  assert.equal(claim.inputDerivedBound, '128');
});
test('missing backing, underbound extents and inconsistent aliases cannot issue a selected-array claim', () => {
  for (const mutate of [o => delete o.inputNames.backing, o => delete o.snapshot, o => o.rowSources = null,
    o => o.snapshot.length = 1,
    o => o.inputNames.backingBytes = '24', o => o.sortedIndices.elementBytes = 8,
    o => o.sortedIndices.backingStatic = true, o => o.sortedIndices.backing = o.inputNames.backing,
    o => o.sortedIndices.slots = 9, o => o.sortedIndices = null]) {
    const observed = fixture(); mutate(observed);
    assert.throws(() => inspectNativeArrays(observed, capacities, ceilings));
  }
});
