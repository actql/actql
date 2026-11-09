import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash} from './inventory.mjs';
import {providerConstructionBound, retainedProviderConstructionBound, inspectProviderConstruction} from './capacity/parent-control/provider-construction.mjs';
import {adoptedConstructionReview, beforeAdoptedConstructionSource, retainedConstructionRead} from './capacity/parent-control/provider-construction-adopted-review.mjs';
import {adoptedConstructionFixtureRead, retainedConstructionFixtureRead}
  from './fixtures/retained-construction-source.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
test('retained constructor fixtures bind every provider to its original source identity', () => {
  const original = JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/provider-construction.json'));
  assert.equal(original.providers.length, 11);
  for (const provider of original.providers) {
    assert.equal(hash(retainedConstructionFixtureRead(provider.path)), provider.sourceDigest, provider.name);
  }
  for (const name of ['selected_relation_provider', 'append_provider', 'values_provider']) {
    const provider = original.providers.find(provider => provider.name === name);
    assert.notEqual(hash(read(provider.path)), provider.sourceDigest, 'Current Source must not replace retained fixture input');
  }
});
test('current five-field candidate component derives 2432 without promoting historical observations', () => {
  // The reviewed Set change replaces only the capacity callback's query.
  // Its constructor arguments, binding, captures and lifecycle callbacks keep
  // the complete preimage from before 06f0975a12, independently of its quote.
  const set = read('src/connectors/local/set_provider.mbt').toString();
  const bounded = '      @execution.generated_bounded_sequence_capacity(\n        sequence, limits, measurement,\n      )';
  assert.equal(set.split(bounded).length, 2, 'Reach the one reviewed Set capacity query');
  assert.equal(hash(set.replace(bounded,
    '      @execution.generated_sequence_capacity(sequence, limits, measurement)')),
    '8fbb2829e812b1d7e09a2bcf9d3d05958acbb72ee8fd25c8fa2d445c90002d7d');
  const current = providerConstructionBound(read);
  assert.equal(current.recordBytes, 48);
  assert.equal(current.bytes, 11 * (48 + 4 * 40) + 120 + 24);
  assert.equal(current.layoutRevision, 'current-five-field');
  assert.equal(current.modelPrefixTuple.included, false);
  assert.equal(current.completeConstructorByteCorrespondence, false);
  assert.equal(current.completeParentUpper, false);
  assert.equal(current.completePipelineUpper, false);
  const retained = retainedProviderConstructionBound(retainedConstructionFixtureRead);
  assert.equal(retained.recordBytes, 40);
  assert.equal(retained.bytes, 2344);
  assert.equal(retained.layoutRevision, 'retained-four-field');
});
test('archived adopted deltas reconstruct all three authenticated complete prior sources', () => {
  for (const entry of adoptedConstructionReview.sources) {
    const expected = execFileSync('git', ['--no-replace-objects', 'show',
      `${adoptedConstructionReview.previousRevision}:${entry.path}`], {cwd: root}).toString();
    const source = adoptedConstructionFixtureRead(entry.path).toString();
    assert.equal(beforeAdoptedConstructionSource(source, entry.path), expected);
    assert.throws(() => beforeAdoptedConstructionSource(expected, entry.path), /Unreviewed adopted/);
    assert.throws(() => beforeAdoptedConstructionSource(source + '\n', entry.path), /Unreviewed adopted/);
  }
});
for (const [name, path, from, to] of [
  ['extra candidate field', 'src/connectors/local/managed_provider.mbt', 'struct ManagedProvider {', 'struct ManagedProvider {\n  extra : String'],
  ['bound Infer tuple in a candidate', 'src/connectors/local/managed_provider.mbt', 'infer_relation_prefix: None,', 'infer_relation_prefix: Some((prefix, 0, execution, measurement)),'],
  ['dropped immutable query-time original', 'src/execution_relation/generated_sequence.mbt', 'query_time : @publication.QueryEvaluationTime?', 'query_time : Int'],
  ['unreviewed constructor allocation', 'src/connectors/local/selected_relation_provider.mbt', 'fn selected_relation_provider(', 'fn selected_relation_provider(\n  extra : String,'],
  ['changed same-original refinement', 'src/execution_relation/generated_sequence.mbt',
    '!physical_equal(original.contracts, candidate.contracts)', 'false'],
  ['prebound workspace growth at preparation', 'src/execution_relation/generated_sequence.mbt',
    'working: None,', 'working: Some(foreign),'],
  ['rebound workspace growth in refinement', 'src/execution_relation/generated_sequence.mbt',
    '!physical_equal(original.working, candidate.working)', 'false'],
]) test(`current source correspondence rejects ${name}`, () => {
  const source = read(path).toString();
  assert(source.includes(from));
  const changed = source.replace(from, to);
  assert.throws(() => providerConstructionBound(p => p === path ? changed : read(p)), /Unreviewed current constructor source/);
});

test('current census refuses unknown changes in every complete constructor source', () => {
  const profile = JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/provider-construction-current.json'));
  const paths = new Set([...profile.providers.map(p => p.path), ...Object.keys(profile.sourcePremises)]);
  assert.equal(paths.size, 13);
  for (const path of paths) {
    assert.throws(() => providerConstructionBound(p => p === path ?
      Buffer.concat([read(path), Buffer.from('\n')]) : read(p)), /Unreviewed current constructor source/);
  }
});

test('current observation admission rejects retained layout and component overflow', () => {
  // Synthetic checker inputs, not claimed Native measurements.
  const fact = {kind: 'provider construction observation', providerRecordFields: 5,
    providers: 11, records: 11, arraySlots: 11, callbacks: 0, defaultArrays: 0,
    indexedBytes: 2432, unclassifiedCaptures: 0, scalarDynamicCallbacks: 0};
  assert.equal(inspectProviderConstruction([fact], read, 'native').recipe.bytes, 2432);
  assert.throws(() => inspectProviderConstruction([{...fact, indexedBytes: 2433}], read, 'native'),
    /exceeds source-derived envelope/);
  assert.throws(() => inspectProviderConstruction([fact], retainedConstructionFixtureRead, 'native',
    {retained: true}), /Retained four-field source cannot authenticate current/);
  for (const providerRecordFields of [undefined, 4, 6])
    assert.throws(() => inspectProviderConstruction([{...fact, providerRecordFields}], read, 'native'),
      /cannot authenticate retained four-field/);
});

test('current source does not acquire retained observation qualification', () => {
  const generated = 'src/execution_relation/generated_sequence.mbt';
  assert.throws(() => retainedConstructionRead(read)(generated), /Unreviewed adopted constructor source/);
  assert.throws(() => retainedProviderConstructionBound(read), /Unreviewed provider constructor/);
});
