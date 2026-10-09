import test from 'node:test';
import assert from 'node:assert/strict';
import { mapBounds, inspectPipelineMaps } from './maps.mjs';
import { fixedCorpus } from '../../corpus.mjs';
// The restricted capacity proof retains the complete six-descriptor cohort.
import { corpusBaseline as registry, registry as currentRegistry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { inputs, violation } from '../model.mjs';
import { nativeUnitFixture } from './native-unit-fixture.mjs';
const cases = fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1);
function observation(c, target = 'js') {
  const b = mapBounds(c, registry);
  return { faults: [{ kind: 'capacity observation', event: 'start',
    mapCapacity: b.capacity, mapEntries: b.entries,
    ...(target === 'native' ? { nativeMaps: nativeUnitFixture(b) } : {}),
    mapAliases: { inputBinding: false, inputProjection: false, bindingProjection: false } }] };
}
test('empty and nonempty DISTINCT inputs retain the constructor table bound', () => {
  assert(cases.some(c => c.rows.length === 0));
  for (const c of cases) {
    const b = mapBounds(c, registry); assert.equal(b.currentTableSlots, 24);
    for (const target of ['js', 'wasm', 'native']) {
      const result = inspectPipelineMaps(c, observation(c, target), registry, target, target);
      assert.equal(result.allocationBytes, false); assert.equal(result.physicalBackingIdentityVerified, target === 'native');
      if (target === 'native') {
        const width = b.entries.inputOrdinals;
        assert.equal(result.conditionalNativeRequestedExtent.currentBound, String(360 + 96 * width));
        assert.equal(result.conditionalNativeRequestedExtent.replacementBound, undefined);
        assert.equal(result.conditionalNativeRequestedExtent.unconditionalAllocationBytes, false);
        assert(result.conditionalNativeRequestedExtent.remainingPremises.length > 0);
      } else assert.equal(result.conditionalNativeRequestedExtent, undefined);
    }
  }
});
test('actual native descriptor admission refuses missing backing identity, aliasing and byte relabeling', () => {
  const c = cases[0];
  for (const change of [e => delete e.nativeMaps,
    e => e.nativeMaps.inputOrdinals.table = e.nativeMaps.bindingOrdinals.table,
    e => e.nativeMaps.bindingOrdinals.requestedBytes = '0']) {
    const o = observation(c, 'native'); change(o.faults[0]);
    assert.throws(() => inspectPipelineMaps(c, o, registry, 'native', 'native'));
  }
  assert.throws(() => inspectPipelineMaps(c, observation(c, 'native'), registry, 'js', 'js'), /another target/);
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

test('the restricted capacity cohort retains every original case and refuses wider derived schemas', () => {
  assert.equal(cases.length, 28);
  const current = fixedCorpus(currentRegistry, registrations);
  assert.equal(current.length, 114);
  for (const c of cases) assert.deepEqual(current.find(next => next.id === c.id), c);
  const wider = current.filter(c => c.steps.filter(s => s.op === 'distinct').length === 1)
    .filter(c => inputs(c, currentRegistry)[0].width > 3);
  assert.deepEqual(wider.map(c => [c.id, inputs(c, currentRegistry)[0].width]), [
    ['pair:derive/distinct', 4], ['extension:seed:105106:38', 4], ['extension:seed:105106:40', 5],
  ]);
  for (const c of wider) assert.throws(() => mapBounds(c, currentRegistry), /existing schema domain/);
});
