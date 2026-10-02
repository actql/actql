import test from 'node:test';
import assert from 'node:assert/strict';
import { pipelineBounds, inspectPipelineBacking } from './pipeline.mjs';
import { fixedCorpus } from '../../corpus.mjs';
import { registry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { mapBounds } from './maps.mjs';
import { nativeUnitFixture } from './native-unit-fixture.mjs';
const cases = fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1);
function observation(c, target) {
  const b = pipelineBounds(c, registry, target);
  const arrayCapacity = Object.fromEntries(Object.entries(b).map(([k, v]) => [k, Number(v)]));
  const maps = mapBounds(c, registry);
  return { faults: [{ kind: 'capacity observation', event: 'checkpoint', arrayCapacity,
    mapCapacity: maps.capacity, mapEntries: maps.entries,
    ...(target === 'native' ? { nativeMaps: nativeUnitFixture(maps) } : {}),
    mapAliases: { inputBinding: false, inputProjection: false, bindingProjection: false },
    keep: arrayCapacity.keep, terms: arrayCapacity.terms,
    outputRows: arrayCapacity.outputRows, outputCells: arrayCapacity.outputCells }] };
}
test('current buffer bounds follow the executed DISTINCT input, not realized duplicate counts or labels', () => {
  for (const c of cases) for (const target of ['js', 'wasm', 'native']) {
    const o = observation(c, target);
    const claim = inspectPipelineBacking(c, o, registry, target, target);
    assert.equal(claim.allocationBytes, false);
    assert.equal(claim.uniqueAllocationSum, false);
    assert.equal(claim.units, target === 'js' ? 'visible elements' : 'current fixed-buffer slots');
    const expanded = structuredClone(o);
    expanded.faults[0].arrayCapacity.keep += 1;
    assert.throws(() => inspectPipelineBacking(c, expanded, registry, target, target), /keep capacity exceeds independent input bound/);
  }
});
test('missing capacity, an expanded schema and a foreign execution are refused', () => {
  const c = cases[0], o = observation(c, 'native');
  assert.throws(() => inspectPipelineBacking(c, o, registry, 'wasm', 'native'), /another target/);
  const missing = structuredClone(o); delete missing.faults[0].arrayCapacity;
  assert.throws(() => inspectPipelineBacking(c, missing, registry, 'native', 'native'), /Missing real state/);
  const expanded = structuredClone(o); expanded.faults[0].arrayCapacity.inputNames += 1;
  assert.throws(() => inspectPipelineBacking(c, expanded, registry, 'native', 'native'), /inputNames capacity exceeds/);
});
test('JS is limited to independently checked visible lengths', () => {
  const c = cases.find(c => pipelineBounds(c, registry, 'js').keep > 0n), o = observation(c, 'js');
  o.faults[0].keep -= 1;
  assert.throws(() => inspectPipelineBacking(c, o, registry, 'js', 'js'));
});
