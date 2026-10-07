import assert from 'node:assert/strict';
import { inputs } from '../model.mjs';
import { distinctMapExtent, mapRequestedExtent } from './native-extent.mjs';
// The actual constructor is Map([]); the admitted schema has at most 3 keys.
// Eight slots, including at zero entries, remain allocated after clear.
// This is table-slot structure, not Map/Entry/engine allocation bytes.
export function mapBounds(testCase, registry) {
  const obligations = inputs(testCase, registry); assert.equal(obligations.length, 1);
  const w = obligations[0].width;
  assert(w >= 1 && w <= 3, 'Map no-grow premise requires the existing schema domain');
  return { capacity: { inputOrdinals: 8, bindingOrdinals: 8, projectionOrdinals: 8 },
    entries: { inputOrdinals: w, bindingOrdinals: 0, projectionOrdinals: w },
    currentTableSlots: 24,
    allocationBytes: false };
}
export function inspectPipelineMaps(testCase, observation, registry, requestedTarget, executionTarget) {
  assert(['js', 'wasm', 'native'].includes(requestedTarget));
  assert.equal(executionTarget, requestedTarget, 'Map execution belongs to another target');
  const b = mapBounds(testCase, registry);
  const events = observation.faults.filter(e => e.kind === 'capacity observation' &&
    ['start', 'checkpoint', 'before-cleanup', 'after-cleanup'].includes(e.event));
  assert(events.length > 0, 'Missing actual Map observations');
  for (const e of events) {
    assert.deepEqual(e.mapCapacity, b.capacity, 'Map buckets exceed the admitted constructor bound');
    assert.deepEqual(e.mapEntries, b.entries, 'Map contents differ from the independent DISTINCT contract');
    assert.deepEqual(e.mapAliases, { inputBinding: false, inputProjection: false, bindingProjection: false },
      'Independent metadata Map owners unexpectedly alias');
    if (requestedTarget === 'native') {
      assert.deepEqual(Object.keys(e.nativeMaps ?? {}).sort(), Object.keys(b.capacity).sort(), 'Missing actual native Map descriptors');
      const identities = new Set(); let extent = 0n;
      for (const name of Object.keys(b.capacity)) {
        const actual = e.nativeMaps[name];
        assert.deepEqual(Object.keys(actual).sort(), ['owner', 'table', 'slots', 'entries', 'requestedBytes'].sort());
        for (const key of ['owner', 'table']) {
          assert(typeof actual[key] === 'string' && /^[1-9][0-9]*$/.test(actual[key]));
          assert(BigInt(actual[key]) <= 18446744073709551615n);
          assert(!identities.has(actual[key]), 'Independent native Map allocations alias');
          identities.add(actual[key]);
        }
        assert.equal(actual.slots, b.capacity[name]); assert.equal(actual.entries, b.entries[name]);
        assert.equal(actual.requestedBytes, mapRequestedExtent(actual.slots, actual.entries).toString(), 'Native descriptor differs from independently derived extent');
        extent += BigInt(actual.requestedBytes);
      }
      assert(extent <= distinctMapExtent(b.entries.inputOrdinals), 'Current native Map leaves exceed their input-derived bound');
    } else assert.equal(e.nativeMaps, undefined, 'Native descriptors belong to another target');
  }
  return { target: requestedTarget, observations: events.length,
    units: 'Map table slots and live entries', allocationBytes: false,
    physicalBackingIdentityVerified: requestedTarget === 'native', replacementOverlapObserved: false,
    ...(requestedTarget === 'native' ? { conditionalNativeRequestedExtent: {
      currentBound: distinctMapExtent(b.entries.inputOrdinals).toString(),
      units: 'native Map leaf requested bytes',
      remainingPremises: ['unobserved allocation/assignment overlap and complete lifetime union',
        'borrowed referents and remaining runtime allocations', 'reservation custody'],
      unconditionalAllocationBytes: false,
    } } : {}) };
}
