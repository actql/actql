import test from 'node:test';
import assert from 'node:assert/strict';
import { mapBounds, inspectPipelineMaps } from './maps.mjs';
import { fixedCorpus } from '../../corpus.mjs';
import { registry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { violation } from '../model.mjs';
const cases = fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1);
function observation(c) {
  const b = mapBounds(c, registry);
  return { faults: [{ kind: 'capacity observation', event: 'start',
    mapCapacity: b.capacity, mapEntries: b.entries,
    mapAliases: { inputBinding: false, inputProjection: false, bindingProjection: false } }] };
}
test('empty and nonempty DISTINCT inputs retain the constructor table bound', () => {
  assert(cases.some(c => c.rows.length === 0));
  for (const c of cases) {
    const b = mapBounds(c, registry); assert.equal(b.currentTableSlots, 32); assert.equal(b.replacementOverlapTableSlots, 40);
    for (const target of ['js', 'wasm', 'native']) {
      const result = inspectPipelineMaps(c, observation(c), registry, target, target);
      assert.equal(result.allocationBytes, false); assert.equal(result.physicalBackingIdentityVerified, false);
      if (target === 'native') {
        const width = b.entries.inputOrdinals;
        assert.equal(result.conditionalNativeRequestedExtent.currentBound, String(480 + 96 * width));
        assert.equal(result.conditionalNativeRequestedExtent.replacementBound, String(600 + 96 * width));
        assert.equal(result.conditionalNativeRequestedExtent.unconditionalAllocationBytes, false);
        assert(result.conditionalNativeRequestedExtent.remainingPremises.length > 0);
      } else assert.equal(result.conditionalNativeRequestedExtent, undefined);
    }
  }
});
test('allocation expansion, forbidden contents and shared metadata owners fail admission', () => {
  const c = cases[0];
  const expanded = observation(c); expanded.faults[0].mapCapacity.inputOrdinals = 16;
  assert.equal(violation(expanded.faults[0]), 'Map buckets exceed the admitted constructor bound');
  assert.throws(() => inspectPipelineMaps(c, expanded, registry, 'js', 'js'), /constructor bound/);
  const wrong = observation(c); wrong.faults[0].mapEntries.snapshot = 1;
  assert.throws(() => inspectPipelineMaps(c, wrong, registry, 'js', 'js'), /independent DISTINCT contract/);
  const shared = observation(c); shared.faults[0].mapAliases.inputProjection = true;
  assert.throws(() => inspectPipelineMaps(c, shared, registry, 'native', 'native'), /unexpectedly alias/);
});
test('whole foreign target observations and missing fields are not substitutes', () => {
  const c = cases[0], o = observation(c);
  assert.throws(() => inspectPipelineMaps(c, o, registry, 'wasm', 'native'), /another target/);
  delete o.faults[0].mapCapacity;
  assert.throws(() => inspectPipelineMaps(c, o, registry, 'native', 'native'));
});
