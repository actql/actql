import assert from 'node:assert/strict';
import { inputs } from '../model.mjs';
import { distinctMapExtent } from './native-extent.mjs';
// The actual constructor is Map([]); the admitted schema has at most 3 keys.
// Eight slots, including at zero entries, remain allocated after clear.
// This is table-slot structure, not Map/Entry/engine allocation bytes.
export function mapBounds(testCase, registry) {
  const obligations = inputs(testCase, registry); assert.equal(obligations.length, 1);
  const w = obligations[0].width;
  assert(w >= 1 && w <= 3, 'Map no-grow premise requires the existing schema domain');
  return { capacity: { inputOrdinals: 8, bindingOrdinals: 8, projectionOrdinals: 8, snapshot: 8 },
    entries: { inputOrdinals: w, bindingOrdinals: 0, projectionOrdinals: w, snapshot: 0 },
    currentTableSlots: 32, replacementOverlapTableSlots: 40,
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
  }
  return { target: requestedTarget, observations: events.length,
    units: 'Map table slots and live entries', allocationBytes: false,
    physicalBackingIdentityVerified: false, replacementOverlapObserved: false,
    ...(requestedTarget === 'native' ? { conditionalNativeRequestedExtent: {
      currentBound: distinctMapExtent(b.entries.inputOrdinals).toString(),
      replacementBound: distinctMapExtent(b.entries.inputOrdinals, true).toString(),
      units: 'native Map leaf requested bytes',
      // Descriptor/identity correspondence was checked on core objects, not
      // independently on every private table in the executing child state.
      remainingPremises: ['native ABI field-layout correspondence for the child instance',
        'actual pipeline table identities and replacement lifetime',
        'borrowed referents and remaining runtime allocations', 'reservation custody'],
      unconditionalAllocationBytes: false,
    } } : {}) };
}
