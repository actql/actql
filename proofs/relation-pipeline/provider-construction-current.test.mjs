import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {providerConstructionBound, retainedProviderConstructionBound, inspectProviderConstruction} from './capacity/parent-control/provider-construction.mjs';
import {adoptedConstructionReview, beforeAdoptedConstructionSource, retainedConstructionRead} from './capacity/parent-control/provider-construction-adopted-review.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
test('current five-field candidate component derives 2432 without promoting historical observations', () => {
  const current = providerConstructionBound(read);
  assert.equal(current.recordBytes, 48);
  assert.equal(current.bytes, 11 * (48 + 4 * 40) + 120 + 24);
  assert.equal(current.layoutRevision, 'current-five-field');
  assert.equal(current.modelPrefixTuple.included, false);
  assert.equal(current.completeConstructorByteCorrespondence, false);
  assert.equal(current.completeParentUpper, false);
  assert.equal(current.completePipelineUpper, false);
  const retained = retainedProviderConstructionBound(retainedConstructionRead(read));
  assert.equal(retained.recordBytes, 40);
  assert.equal(retained.bytes, 2344);
  assert.equal(retained.layoutRevision, 'retained-four-field');
});
test('adopted deltas reconstruct all three authenticated complete prior sources', () => {
  for (const entry of adoptedConstructionReview.sources) {
    const expected = execFileSync('git', ['--no-replace-objects', 'show',
      `${adoptedConstructionReview.previousRevision}:${entry.path}`], {cwd: root}).toString();
    assert.equal(beforeAdoptedConstructionSource(read(entry.path).toString(), entry.path), expected);
    assert.throws(() => beforeAdoptedConstructionSource(expected, entry.path), /Unreviewed adopted/);
    assert.throws(() => beforeAdoptedConstructionSource(read(entry.path).toString() + '\n', entry.path), /Unreviewed adopted/);
  }
});
for (const [name, path, from, to] of [
  ['extra candidate field', 'src/connectors/local/managed_provider.mbt', 'struct ManagedProvider {', 'struct ManagedProvider {\n  extra : String'],
  ['bound Infer tuple in a candidate', 'src/connectors/local/managed_provider.mbt', 'infer_relation_prefix: None,', 'infer_relation_prefix: Some((prefix, 0, execution, measurement)),'],
  ['dropped immutable query-time original', 'src/execution_relation/generated_sequence.mbt', 'query_time : @publication.QueryEvaluationTime?', 'query_time : Int'],
  ['unreviewed constructor allocation', 'src/connectors/local/selected_relation_provider.mbt', 'fn selected_relation_provider(', 'fn selected_relation_provider(\n  extra : String,'],
]) test(`current source correspondence rejects ${name}`, () => {
  const source = read(path).toString();
  assert(source.includes(from));
  const changed = source.replace(from, to);
  assert.throws(() => providerConstructionBound(p => p === path ? changed : read(p)), /Unreviewed adopted/);
});

test('current observation admission rejects retained layout and component overflow', () => {
  // Synthetic checker inputs, not claimed Native measurements.
  const fact = {kind: 'provider construction observation', providerRecordFields: 5,
    providers: 11, records: 11, arraySlots: 11, callbacks: 0, defaultArrays: 0,
    indexedBytes: 2432, unclassifiedCaptures: 0, scalarDynamicCallbacks: 0};
  assert.equal(inspectProviderConstruction([fact], read, 'native').recipe.bytes, 2432);
  assert.throws(() => inspectProviderConstruction([{...fact, indexedBytes: 2433}], read, 'native'),
    /exceeds source-derived envelope/);
  assert.throws(() => inspectProviderConstruction([fact], retainedConstructionRead(read), 'native',
    {retained: true}), /Retained four-field source cannot authenticate current/);
  for (const providerRecordFields of [undefined, 4, 6])
    assert.throws(() => inspectProviderConstruction([{...fact, providerRecordFields}], read, 'native'),
      /cannot authenticate retained four-field/);
});
