import assert from 'node:assert/strict';
import { inputs } from '../model.mjs';
import { currentSlotsCeiling } from './model.mjs';
import { inspectPipelineMaps } from './maps.mjs';
import { inspectNativeArrays } from './native-array.mjs';
// Dimensions come from the independent oracle applied to the executed case.
// Each bound concerns a current container, not a sum of unique allocations.
export function pipelineBounds(testCase, registry, target) {
  assert(['js', 'wasm', 'native'].includes(target));
  const obligations = inputs(testCase, registry);
  assert.equal(obligations.length, 1);
  const { rows: n, width: w } = obligations[0];
  const grown = h => target === 'js' ? BigInt(h) : currentSlotsCeiling(h);
  return {
    inputNames: BigInt(w), outputNames: BigInt(w), snapshot: 0n, rowSources: 0n,
    keep: grown(n), terms: grown(w), sortedIndices: grown(n),
    outputRows: grown(n), outputCells: BigInt(n) * grown(w),
    outputMaxRow: n === 0 ? 0n : grown(w),
    values: grown(w), slotRoots: grown(w), outputRow: grown(w),
    checkedRow: grown(w), captureRow: grown(w),
  };
}
export function inspectPipelineBacking(testCase, observation, registry, requestedTarget, executionTarget) {
  assert.equal(executionTarget, requestedTarget, 'Backing execution belongs to another target');
  const maps = inspectPipelineMaps(testCase, observation, registry, requestedTarget, executionTarget);
  const bounds = pipelineBounds(testCase, registry, requestedTarget);
  const events = observation.faults.filter(e => e.kind === 'capacity observation' &&
    ['start', 'checkpoint', 'before-cleanup', 'after-cleanup'].includes(e.event));
  assert(events.length > 0, 'Missing actual container-capacity observations');
  const selectedArrayExtents = [];
  for (const e of events) {
    const { portPreparation, pendingPortNames, completedPortNames, ...metadataPreparation } = e.metadataPreparation;
    assert.deepEqual(metadataPreparation, { stepped: false, lookup: false, source: false, generatedField: -1, generatedSeen: 0, termColumn: false, nameCharge: false,
      snapshotEntries: 0, sourceEntries: 0 }, 'Metadata preparation lies outside the admitted DISTINCT pilot');
    // The reviewed completionPreparationScope keeps port-name backing outside
    // this selected Array census. Check its existing width/transfer law without
    // weakening the exact refusal of other unmodeled metadata work above.
    assert.equal(typeof portPreparation, 'boolean', 'Missing completion-port preparation state');
    for (const count of [pendingPortNames, completedPortNames]) {
      assert(Number.isSafeInteger(count) && count >= 0, 'Invalid completion-port name count');
    }
    assert(BigInt(pendingPortNames) + BigInt(completedPortNames) <= bounds.outputNames,
      'Completion-port names exceed independent schema width');
    assert(portPreparation ? completedPortNames === 0 : pendingPortNames === 0,
      'Completion-port names have overlapping preparation/finished owners');
    assert(completedPortNames === 0 || BigInt(completedPortNames) === bounds.outputNames,
      'Finished completion-port names differ from independent schema width');
    assert(e.arrayCapacity, 'Missing real state Array capacity');
    assert.deepEqual(Object.keys(e.arrayCapacity).sort(), Object.keys(bounds).sort());
    for (const [name, ceiling] of Object.entries(bounds)) {
      const actual = e.arrayCapacity[name];
      assert(Number.isSafeInteger(actual) && actual >= 0, 'Invalid observed capacity');
      assert(BigInt(actual) <= ceiling, `${name} capacity exceeds independent input bound`);
    }
    // makei(width, ...) has exactly width slots on every admitted target.
    assert.equal(BigInt(e.arrayCapacity.inputNames), bounds.inputNames);
    assert.equal(BigInt(e.arrayCapacity.outputNames), bounds.outputNames);
    if (requestedTarget === 'native') {
      selectedArrayExtents.push(inspectNativeArrays(e.nativeArrays, e.arrayCapacity, bounds));
    } else assert.equal(e.nativeArrays, undefined, 'Native Array descriptors belong to another target');
    if (requestedTarget === 'js') {
      // These are visible lengths on JS, never observations of engine storage.
      assert.equal(e.arrayCapacity.keep, e.keep);
      assert.equal(e.arrayCapacity.terms, e.terms);
      assert.equal(e.arrayCapacity.outputRows, e.outputRows);
      assert.equal(e.arrayCapacity.outputCells, e.outputCells);
    }
  }
  return { target: requestedTarget, observations: events.length,
    units: requestedTarget === 'js' ? 'visible elements' : 'current fixed-buffer slots',
    uniqueAllocationSum: false, allocationBytes: false,
    ...(maps.conditionalNativeRequestedExtent ? {
      conditionalNativeRequestedExtent: maps.conditionalNativeRequestedExtent,
      selectedNativeArrayExtents: selectedArrayExtents,
    } : {}) };
}
