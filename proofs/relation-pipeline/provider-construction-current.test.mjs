import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash} from './inventory.mjs';
import {selectedBeforeCleanupContinuation, selectedBeforeRowCleanupContinuation, selectedBeforeBoundedChainQuote,
  managedBeforeCleanupContinuation, reviewedFunction} from './capacity/parent-control/provider-construction-source-review.mjs';
import {providerConstructionBound, retainedProviderConstructionBound, inspectProviderConstruction} from './capacity/parent-control/provider-construction.mjs';
import {adoptedConstructionReview, beforeAdoptedConstructionSource, retainedConstructionRead} from './capacity/parent-control/provider-construction-adopted-review.mjs';
import {adoptedConstructionFixtureRead, retainedConstructionFixtureRead}
  from './fixtures/retained-construction-source.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
test('reviewed chain quote cannot discard a retained or unreclaimed suffix floor', () => {
  const source=read('src/connectors/local/selected_relation_provider.mbt').toString();
  for(const [from,to] of [
    ['if reclaimed_prefix == count {', 'if reclaimed_prefix > 0 {'],
    ['        base.execution_bytes\n', '        0L\n'],
  ]) {
    const changed=source.replace(from,to);assert.notEqual(changed,source);
    assert.throws(()=>selectedBeforeBoundedChainQuote(changed),/Changed reviewed representation delta/);
  }
});
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
test('archived execution reviews remain bound to their exact inputs without freezing current helpers', () => {
  const providerPaths = new Set([...JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/provider-construction-current.json')).providers.map(p => p.path),
    'src/connectors/local/managed_provider.mbt', 'src/execution_relation/generated_sequence.mbt']);
  const archived = new Map();
  const currentRead = read;
  const readArchived = path => {
    if (!providerPaths.has(path)) return currentRead(path);
    if (!archived.has(path)) archived.set(path, execFileSync('git', ['--no-replace-objects', 'show',
      `67dc8d72c3bdf378a82a9a5d56399070b06e7fae^:${path}`], {cwd: root}));
    return archived.get(path);
  };
  return checkArchivedExecutionReviews(readArchived);
});

function checkArchivedExecutionReviews(read) {
  // The reviewed Set change replaces only the capacity callback's query.
  // Its constructor arguments, binding, captures and lifecycle callbacks keep
  // the complete preimage from before 06f0975a12, independently of its quote.
  const set = read('src/connectors/local/set_provider.mbt').toString();
  const bounded = '      @execution.generated_bounded_sequence_capacity(\n        sequence, limits, measurement,\n      )';
  assert.equal(set.split(bounded).length, 2, 'Reach the one reviewed Set capacity query');
  assert.equal(hash(set.replace(bounded,
    '      @execution.generated_sequence_capacity(sequence, limits, measurement)')),
    '8fbb2829e812b1d7e09a2bcf9d3d05958acbb72ee8fd25c8fa2d445c90002d7d');
  // The reviewed scalar COUNT change selects the bounded quote in the same
  // capacity callback. It changes no constructor field, capture or lifecycle
  // callback; reversing only that query recovers the complete prior Source.
  // Callback execution remains outside the eleven-candidate construction bound.
  const countPath = 'src/connectors/local/global_count_provider.mbt';
  const count = read(countPath).toString();
  assert.equal(count.split(bounded).length, 2, 'Reach the one reviewed COUNT capacity query');
  const priorCount = count.replace(bounded,
    '      @execution.generated_sequence_capacity(sequence, limits, measurement)');
  assert.equal(hash(priorCount),
    '77ab701f6dbd8974eab545bca95b7453e2f494f96450b855b911a87649e5deef');
  // UNNEST changes the same quote callback without changing its constructor
  // fields, captures or lifecycle. Its output execution is a separate bound.
  const unnestPath = 'src/connectors/local/unnest_provider.mbt';
  const unnest = read(unnestPath).toString();
  assert.equal(unnest.split(bounded).length, 2, 'Reach the one reviewed UNNEST capacity query');
  const priorUnnest = unnest.replace(bounded,
    '      @execution.generated_sequence_capacity(sequence, limits, measurement)');
  assert.equal(hash(priorUnnest),
    '73ef7e256f5fc062cad8c00a3e39341a0e138493cbb01a7b9c6a45a05a2e986b');
  // Property borrowing changes only an execution predicate before the
  // selected factory. Keep the archived execution-body reversals on their
  // exact archived input; they are not admission gates for unrelated current
  // private helpers. The current factory itself must still match that input.
  const archivedSelected = execFileSync('git', ['--no-replace-objects', 'show',
    '67dc8d72c3bdf378a82a9a5d56399070b06e7fae^:src/connectors/local/selected_relation_provider.mbt'],
  {cwd: root}).toString();
  assert.equal(hash(archivedSelected),
    '187ea820725576df7510584c9b1c5707cc1ab338c4f9c6d3bf60f1728b9094e4');
  const factory = source => reviewedFunction(source, 'selected_relation_provider');
  assert.equal(factory(read('src/connectors/local/selected_relation_provider.mbt').toString()),
    factory(archivedSelected), 'Current factory and its callback/capture declarations remain exact');
  const selectedBytes = Buffer.from(selectedBeforeBoundedChainQuote(
    selectedBeforeCleanupContinuation(selectedBeforeRowCleanupContinuation(
      archivedSelected))));
  assert.equal(hash(selectedBytes),
    'e42963ae653cff94ddd089a2c33a5f02d5da1a56efde8567f9a0caf7fbc20d55',
    'Execution cleanup observer and bounded quote must preserve the complete prior Source');
  assert.equal(hash(managedBeforeCleanupContinuation(read('src/connectors/local/managed_provider.mbt').toString())),
    'c71bfd51bf16313deb4eb1f6d197ce618a5f4db4d24d963bdef92f941e401dc0',
    'Execution-only callback slot/helper must preserve candidate construction');
  // The reviewed singleton PIVOT guard changes only the private prefix query.
  // It cannot affect a multi-child prefix or allocate another constructor.
  // Reverse that exact delta before the independent prior-Source checks.
  const pivot = `          !(@execution.generated_sequence_step_count(sequence) == 1 &&
          @lower.kernel_pivot(kernel) is Some(_)) &&
`;
  assert.equal(selectedBytes.toString().split(pivot).length, 2,
    'Reach the one reviewed singleton PIVOT scratch-eligibility guard');
  const beforePivot = Buffer.from(selectedBytes.toString().replace(pivot, ''));
  assert.equal(hash(beforePivot),
    '18df1ab5731e9208f1ab95856799286ab779b48fe7e99d97d322d34a52b1fcad',
    'Singleton PIVOT eligibility must preserve the complete prior Source');
  // F0bf adds only this private scratch-eligibility arm. Reverse it before
  // checking the complete old Source and its original fixed prefix/tail;
  // candidate construction and the numeric/NULL unary pilot do not change.
  const window = `      // The bounded window child detaches its accepted output. Cleanup drops
      // its maps, membership array and recheck cursors before the next child.
      Some(@lower.WindowStep(_)) => ()
`;
  assert.equal(beforePivot.toString().split(window).length, 2,
    'Reach the one reviewed Window scratch-eligibility arm');
  const beforeWindow = Buffer.from(beforePivot.toString().replace(window, ''));
  assert.equal(hash(beforeWindow),
    '4167c79f880f1734c25bac7eb53323a8a005b1bc9ba28725e591a14c939370c2',
    'Window eligibility must preserve the complete prior Source');
  const selectedPrefix = beforeWindow.subarray(0, 38533);
  assert.equal(hash(selectedPrefix),
    '9c38a2c47f93832736444f5826d176ba7e749e75683778df74765814e5fa924a',
    'only the reviewed private carried-key classifier extends the complete prior Source');
  assert.match(beforeWindow.subarray(38533).toString(), /fn selected_join_borrows_carried_values\(/u);
  const selected = selectedPrefix.toString();
  assert.equal(hash(selected.slice(selected.indexOf('fn selected_relation_provider('))),
    'f100dd3ac842dd087b494382c42be9dfb613184a35f26164f2788ba8ed6544b5');
  // CROSS JOIN changes only the quote callback. Candidate layout/captures and
  // the actual constructor/lifecycle remain outside callback execution.
  const crossPath = 'src/connectors/local/cross_join_provider.mbt';
  const cross = read(crossPath).toString();
  // The reviewed typed work refusal changes only the error mapper preceding
  // the constructor. Reverse exactly that arm to authenticate the complete
  // prior Source; candidate layout, captures and cleanup observer stay exact.
  const typedWork = '    @execution.ControlWorkLimit => @connector.ControlWorkLimit\n';
  assert.equal(cross.split(typedWork).length, 2, 'Reach the one typed work-refusal arm');
  const beforeTypedWork = cross.replace(typedWork, '');
  assert.equal(hash(beforeTypedWork),
    'a02cf4c88fe349c5a71aaec5348e62f9af3555b530a8d97715a0f13255771590',
    'Typed work classification must preserve the complete previously reviewed Source');
  assert.equal(cross.slice(cross.indexOf('fn cross_join_provider(')),
    beforeTypedWork.slice(beforeTypedWork.indexOf('fn cross_join_provider(')),
    'Constructor and all execution/cleanup callback bodies remain unchanged');
  for (const changed of [beforeTypedWork,
    cross.replace(typedWork, typedWork + typedWork),
    cross.replace(typedWork, '    @execution.ControlWorkLimit => @connector.Execution(@execution.InputLimit)\n')]) {
    assert.notEqual(changed.split(typedWork).length, 2,
      'The runtime work-cause premise changes independently of candidate construction');
  }
  assert.equal(cross.split(bounded).length, 2, 'Reach the one reviewed CROSS JOIN capacity query');
  const cleanupObserver = `      ).map(owner => {
        owner.cleanup_continuation = Some(() => {
          @execution.bounded_cross_join_cleanup_continuation(active)
        })
        owner
      })`;
  assert.equal(cross.split(cleanupObserver).length, 2, 'Reach the one execution-only Cross Join observer');
  const beforeObserver = beforeTypedWork.replace(cleanupObserver, '      )');
  assert.equal(hash(beforeObserver),
    '0e2b820abd78a4391861332f8748682cb1b70c536dd05f9bc7126531bd197942',
    'Cross Join observer must preserve the complete prior candidate constructor Source');
  const priorCross = beforeObserver.replace(bounded,
    '      @execution.generated_sequence_capacity(sequence, limits, measurement)');
  assert.equal(hash(priorCross),
    '74bd36805e65a2340a49d7c554cfea4b807a45676867560a3dd654a14ae89218');
  const retained = retainedProviderConstructionBound(retainedConstructionFixtureRead);
  assert.equal(retained.recordBytes, 40);
  assert.equal(retained.bytes, 2344);
  assert.equal(retained.layoutRevision, 'retained-four-field');
}
test('current factories derive 2552 without promoting archived execution observations', () => {
  const current = providerConstructionBound(read);
  assert.equal(current.recordBytes, 56);
  assert.equal(current.bytes, 11 * (56 + 4 * 40) + 120 + 24 + 2 * 16);
  assert.equal(current.completeConstructorByteCorrespondence, false);
  assert.equal(current.completeParentUpper, false);
  assert.equal(current.completePipelineUpper, false);
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
  ['unreviewed constructor allocation', 'src/connectors/local/selected_relation_provider.mbt', 'fn selected_relation_provider(', 'fn selected_relation_provider(\n  extra : String,'],
]) test(`current source correspondence rejects ${name}`, () => {
  const source = read(path).toString();
  assert(source.includes(from));
  const changed = source.replace(from, to);
  assert.throws(() => providerConstructionBound(p => p === path ? changed : read(p)),
    /Unreviewed current constructor source|Changed current ManagedProvider declaration|Changed current candidate construction wrapper|Candidate wrapper must not own a bound Infer tuple/);
});

test('current census binds complete factories without freezing unrelated module text', () => {
  const profile = JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/provider-construction-current.json'));
  for (const provider of profile.providers) {
    const path = provider.path;
    const unrelated = Buffer.concat([read(path), Buffer.from('\n// No candidate construction changes.\n')]);
    const bound = providerConstructionBound(p => p === path ? unrelated : read(p));
    assert.equal(bound.bytes, 2552);
    assert.equal(bound.completePipelineUpper, false);
    const source = read(path).toString();
    const changed = source.replace(`fn ${provider.name}(`, `fn ${provider.name}(\n  unaccounted_capture : String,`);
    assert.notEqual(changed, source);
    assert.throws(() => providerConstructionBound(p => p === path ? changed : read(p)),
      /Unreviewed current constructor source/);
  }
});

test('private execution helpers do not change the constructor-only claim', () => {
  const path='src/connectors/local/selected_relation_provider.mbt';
  const source=read(path).toString();
  const changed=source.replace('fn selected_binding_outputs_borrowed(',
    '// Execution-only helper documentation.\nfn selected_binding_outputs_borrowed(');
  assert.notEqual(changed,source);
  const bound=providerConstructionBound(file=>file===path?changed:read(file));
  assert.equal(bound.bytes,2552);
  assert.equal(bound.sourceReview.selectedDigest,hash(changed));
  assert.equal(bound.completePipelineUpper,false);
  const allocation=source.replace('  for\n    provider in [',
    '  let extra = Array::make(100, None)\n  for\n    provider in [');
  assert.notEqual(allocation,source);
  assert.throws(()=>providerConstructionBound(file=>file===path?allocation:read(file)),
    /Unreviewed current constructor source/);
});

test('current observation admission rejects retained layout and component overflow', () => {
  // Synthetic checker inputs, not claimed Native measurements.
  const fact = {kind: 'provider construction observation', providerRecordFields: 6,
    providers: 11, records: 11, arraySlots: 11, callbacks: 0, defaultArrays: 0,
    indexedBytes: 2552, numericStartExtensions: 2, numericStartExtensionBytes: 32, unclassifiedCaptures: 0, scalarDynamicCallbacks: 0};
  assert.equal(inspectProviderConstruction([fact], read, 'native').recipe.bytes, 2552);
  assert.throws(() => inspectProviderConstruction([{...fact, indexedBytes: 2553}], read, 'native'),
    /exceeds source-derived envelope/);
  assert.throws(() => inspectProviderConstruction([fact], retainedConstructionFixtureRead, 'native',
    {retained: true}), /Retained four-field source cannot authenticate current/);
  for (const fields of [{numericStartExtensions: undefined}, {numericStartExtensions: 1},
    {numericStartExtensionBytes: 16}]) {
    assert.throws(() => inspectProviderConstruction([{...fact, ...fields}], read, 'native'),
      /Numeric start extent/);
  }
  for (const providerRecordFields of [undefined, 4, 5, 7])
    assert.throws(() => inspectProviderConstruction([{...fact, providerRecordFields}], read, 'native'),
      /cannot authenticate a different provider layout/);
});

test('current source does not acquire retained observation qualification', () => {
  const generated = 'src/execution_relation/generated_sequence.mbt';
  assert.throws(() => retainedConstructionRead(read)(generated), /Unreviewed adopted constructor source/);
  assert.throws(() => retainedProviderConstructionBound(read), /Unreviewed provider constructor/);
});
