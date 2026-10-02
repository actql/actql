import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { providerConstructionBound, inspectProviderConstruction } from './capacity/parent-control/provider-construction.mjs';
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
// Synthetic admission tests, separate from the archived real native reader.
const fact = () => ({ kind: 'provider construction observation', providers: 11,
  records: 11, arraySlots: 11, callbacks: 30, defaultArrays: 1, indexedBytes: 1504,
  unclassifiedCaptures: 0, scalarDynamicCallbacks: 0 });
test('constructor bound is derived from source counts and declared ABI, not observations', () => {
  const b = providerConstructionBound(read);
  assert.equal(b.bytes, 2344);
  assert.equal(b.bytes, 11 * (40 + 4 * 40) + 120 + 24);
  assert.equal(b.completeParentUpper, false);
  assert.equal(b.completePipelineUpper, false);
  assert.equal(inspectProviderConstruction([fact()], read, 'native').recipe.bytes, b.bytes);
  assert.equal(inspectProviderConstruction([{ ...fact(), indexedBytes: 2344 }], read, 'native').recipe.bytes, b.bytes);
});
test('constructor source and compatibility representation are independent admission premises', () => {
  for (const path of ['src/connectors/local/selected_relation_provider.mbt',
    'src/connectors/local/managed_provider.mbt', 'src/execution_relation/generated_sequence.mbt']) {
    assert.throws(() => providerConstructionBound(p => p === path ? Buffer.concat([read(p), Buffer.from('\n')]) : read(p)),
      /Unreviewed provider constructor|Changed provider representation premise/);
  }
});
test('constructor facts cannot be relabeled as portable or complete pipeline evidence', () => {
  for (const target of ['js', 'wasm'])
    assert.throws(() => inspectProviderConstruction([fact()], read, target), /native only/);
  assert.throws(() => inspectProviderConstruction([], read, 'native'), /Missing real/);
  for (const [key, value] of Object.entries({ providers: 10, records: 10, arraySlots: 10,
    callbacks: 45, defaultArrays: 2, unclassifiedCaptures: 1, scalarDynamicCallbacks: 45,
    indexedBytes: 2345 })) {
    assert.throws(() => inspectProviderConstruction([{ ...fact(), [key]: value }], read, 'native'));
  }
  assert.throws(() => inspectProviderConstruction([{ ...fact(), indexedBytes: 0 }], read, 'native'), /Missing candidate/);
});
test('scalar callback counts never become measured extents or a complete byte guarantee', () => {
  const result = inspectProviderConstruction([{ ...fact(), callbacks: 20, scalarDynamicCallbacks: 20 }], read, 'native');
  assert.equal(result.scalarPayloadBytesObserved, false);
  assert.equal(result.completeConstructorByteCorrespondence, false);
  assert(result.recipe.unresolved.some(p => p.includes('scalar callback')));
  assert.throws(() => inspectProviderConstruction([{ ...fact(), callbacks: 40, scalarDynamicCallbacks: 5 }], read, 'native'),
    /Too many constructor callbacks/);
});
