import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash} from '../../inventory.mjs';
import {providerConstructionBound, currentFactoryDeclaration,
  currentProviderRecordDeclaration} from './provider-construction.mjs';
import {checkParentCensus} from './bounds.mjs';
import {checkConstructionSourceReview} from './provider-construction-source-review.mjs';
import {currentConstructionReview, historicalConstructionSource}
  from './provider-construction-current-review.mjs';
import {beforeAdoptedConstructionSource} from './provider-construction-adopted-review.mjs';
import {adoptedConstructionFixtureRead} from '../../fixtures/retained-construction-source.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const directory = 'proofs/relation-pipeline/capacity/parent-control/';
const read = path => readFileSync(new URL('../../../../' + path, import.meta.url));
const historicalProfile = JSON.parse(read(directory + 'provider-construction.json'));
const selectedPath = 'src/connectors/local/selected_relation_provider.mbt';
const managedPath = 'src/connectors/local/managed_provider.mbt';
const generatedPath = 'src/execution_relation/generated_sequence.mbt';

test('current constructor admission binds current sources and keeps the conditional envelope', () => {
  const bound = providerConstructionBound(read);
  assert.equal(bound.providerCount, 11);
  assert.equal(bound.callbackCount, 44);
  assert.equal(bound.bytes, 2552);
  assert.equal(bound.completeConstructorByteCorrespondence, false);
  assert.equal(bound.completeParentUpper, false);
  assert.equal(bound.completePipelineUpper, false);
  assert.equal(bound.sourceReview.selectedDigest, hash(read(selectedPath)));
  assert.equal(bound.sourceReview.managedDigest, hash(read(managedPath)));
  assert.equal(bound.sourceReview.generatedDigest, hash(read(generatedPath)));
});

test('archived constructor review retains its authenticated historical preimages separately', () => {
  for (const entry of currentConstructionReview.sources) {
    // Actual retained Git bytes are independent of the literal reversal.
    const gitBytes = execFileSync('git', ['--no-replace-objects', 'show',
      `${entry.previousRevision}:${entry.path}`], {cwd: root});
    assert.equal(hash(gitBytes), entry.previousSha256);
    assert.equal(historicalConstructionSource(beforeAdoptedConstructionSource(
      adoptedConstructionFixtureRead(entry.path).toString(), entry.path), entry), gitBytes.toString());
  }
});

test('the unmodified historical checker still refuses the current source', () => {
  assert.throws(() => checkConstructionSourceReview(historicalProfile, read),
    /Unreviewed provider constructor selected_relation_provider/);
});

for (const [name, path, before, after] of [
  ['extra candidate', selectedPath, '      values_provider(execution, measurement),',
    '      values_provider(execution, measurement),\n      values_provider(execution, measurement),'],
  ['additional constructor parameter', selectedPath,
    '  family? : Array[ManagedProvider] = [],\n) -> ManagedProvider {',
    '  family? : Array[ManagedProvider] = [],\n  extra : Int,\n) -> ManagedProvider {'],
  ['changed candidate factory attribute', selectedPath,
    'fn selected_relation_provider(', '#inline\nfn selected_relation_provider('],
  ['prefix substituted by full count', selectedPath,
    '            let reclaims_scratch = state.position <= reclaimed_prefix',
    '            let reclaims_scratch = state.position <= count'],
  ['missing cleanup ACK', selectedPath, '        if reclaimed.val {', '        if true {'],
  ['changed constructor callback field', managedPath,
    '  accepts : ', '  extra_capture : Int\n  accepts : '],
  ['changed provider record representation', managedPath,
    'struct ManagedProvider {', '#valtype\nstruct ManagedProvider {'],
  ['changed constructor wrapper capture', managedPath,
    '    start_extension: None,', '    start_extension: Some(unreviewed),'],
  ['changed constructor wrapper attribute', managedPath,
    'pub fn managed_provider_with_numeric(', '#inline\npub fn managed_provider_with_numeric('],
  ['foreign current start tag', managedPath,
    '  Numeric(', '  ForgedNumeric('],
  ['inline current start tag layout', managedPath,
    'priv enum ManagedProviderStartExtension {', '#valtype\npriv enum ManagedProviderStartExtension {'],
]) {
  test(`current construction refuses ${name}`, () => {
    const original = read(path).toString();
    assert(original.includes(before), `Missing independent negative target ${name}`);
    const changed = original.replace(before, after);
    assert.notEqual(changed, original);
    const runtimeOnly=['prefix substituted by full count','missing cleanup ACK'].includes(name);
    const inspect=runtimeOnly?checkParentCensus:providerConstructionBound;
    assert.throws(() => inspect(file => file === path ? changed : read(file)),
      runtimeOnly?/Unreviewed .* source captures|Changed row cleanup stop\/ACK boundary/:
        /Unreviewed current constructor source|Unreviewed provider candidate inventory|Changed current ManagedProvider declaration|Changed current candidate construction wrapper|Changed current start extension/);
  });
}

test('constructor declarations retain representation attributes across comments and documentation markers', () => {
  const managed = read(managedPath).toString();
  const record = currentProviderRecordDeclaration(managed, 'ManagedProvider');
  for (const prefix of ['#valtype\n', '#valtype\n/* layout attribute */\n///|\n']) {
    const changed = managed.replace('struct ManagedProvider {', prefix + 'struct ManagedProvider {');
    assert.notEqual(currentProviderRecordDeclaration(changed, 'ManagedProvider'), record);
    assert.throws(() => providerConstructionBound(path => path === managedPath ? changed : read(path)),
      /Changed current ManagedProvider declaration/);
  }
  const name = 'managed_provider_with_numeric';
  const wrapper = currentFactoryDeclaration(managed, name);
  for (const prefix of ['#inline\n', '#coverage.skip\n///|\n', '#cfg(\n  target="native"\n)\n///|\n']) {
    const changed = managed.replace(`pub fn ${name}(`, prefix + `pub fn ${name}(`);
    assert.notEqual(currentFactoryDeclaration(changed, name), wrapper);
    assert.throws(() => providerConstructionBound(path => path === managedPath ? changed : read(path)),
      /Changed current candidate construction wrapper/);
  }
});

test('unrelated runtime helpers retain complete source provenance without changing the finite constructor claim', () => {
  for (const [path, change] of [
    [managedPath, source => source + '\n///|\nfn unrelated_runtime_helper() -> Int {\n  0\n}\n'],
    [generatedPath, source => source + '\n///|\nfn unrelated_runtime_helper() -> Int {\n  0\n}\n'],
    [managedPath, source => source.replace('    reported_work: Ok(0L),', '    reported_work: Ok(0L + 0L),')],
  ]) {
    const original = read(path).toString();
    const changed = change(original);
    assert.notEqual(changed, original);
    const bound = providerConstructionBound(file => file === path ? changed : read(file));
    assert.equal(bound.bytes, 2552);
    assert.equal(bound.completeConstructorByteCorrespondence, false);
    assert.equal(bound.completeParentUpper, false);
    assert.equal(bound.completePipelineUpper, false);
    const key = path === managedPath ? 'managedDigest' : 'generatedDigest';
    assert.equal(bound.sourceReview[key], hash(changed));
    assert.notEqual(bound.sourceReview[key], hash(original));
  }
});

test('borrowed generated inputs and deferred execution are outside the candidate object bound', () => {
  const original = read(generatedPath).toString();
  const changed = original.replace('struct GeneratedSequence {',
    'struct GeneratedSequence {\n  unrelated_borrowed_field : Int');
  assert.notEqual(changed, original);
  const bound = providerConstructionBound(path => path === generatedPath ? changed : read(path));
  assert.equal(bound.bytes, 2552);
  assert.equal(bound.sourceReview.generatedDigest, hash(changed));
  assert.equal(bound.completeConstructorByteCorrespondence, false);
  assert.equal(bound.completeParentUpper, false);
  assert.equal(bound.completePipelineUpper, false);
  const source = read(selectedPath).toString();
  const brokenCleanup = source.replace('        if reclaimed.val {', '        if true {');
  assert.notEqual(brokenCleanup, source);
  assert.equal(providerConstructionBound(path => path === selectedPath ? brokenCleanup : read(path)).bytes, 2552);
  assert.throws(() => checkParentCensus(path => path === selectedPath ? brokenCleanup : read(path)),
    /Unreviewed .* source captures|Changed row cleanup stop\/ACK boundary/);
});

test('current construction refuses changed current recipe bytes', () => {
  assert.throws(() => providerConstructionBound(file => file === directory + 'provider-construction-current.json' ?
    Buffer.concat([read(file), Buffer.from(' ')]) : read(file)), /Changed current constructor recipe/);
});

test('current construction requires no historical recipe, review or Git source', () => {
  const current = directory + 'provider-construction-current.json';
  const bound = providerConstructionBound(file => {
    assert(file.startsWith('src/') || file === current, `Unexpected historical input ${file}`);
    return read(file);
  });
  assert.equal(bound.bytes, 2552);
  assert.equal(bound.sourceReview.historicalSourceReview, undefined);
  assert.equal(bound.sourceReview.retainedSourceReview, undefined);
});

test('literal reversal refuses omitted or changed historical preimages', () => {
  const entry = currentConstructionReview.sources[0];
  const source = beforeAdoptedConstructionSource(adoptedConstructionFixtureRead(entry.path).toString(), entry.path);
  assert.throws(() => historicalConstructionSource(source, {...entry, hunks: entry.hunks.slice(1)}),
    /Changed historical constructor preimage/);
  const hunks = structuredClone(entry.hunks);
  hunks[0].before += 'unreviewed historical bytes';
  assert.throws(() => historicalConstructionSource(source, {...entry, hunks}),
    /Changed historical constructor preimage/);
});

test('literal reversal refuses duplicate current occurrences even with a substituted input digest', () => {
  const entry = currentConstructionReview.sources[0];
  const source = beforeAdoptedConstructionSource(adoptedConstructionFixtureRead(entry.path).toString(), entry.path) + entry.hunks[0].after;
  assert.throws(() => historicalConstructionSource(source, {...entry, currentSha256: hash(source)}),
    /Changed reviewed constructor delta/);
});

// Capacity and execution callback bodies do not run during candidate creation.
// Their actual current bytes remain in the compiled source/artifact boundary.
test('deferred callback implementation changes retain current construction provenance', () => {
  const path = 'src/connectors/local/cross_join_provider.mbt';
  const source = read(path).toString();
  const changed = source.replace('bounded_cross_join_issue(issue, step)', 'bounded_cross_join_issue(issue, step + 0)');
  assert.notEqual(changed, source);
  const bound = providerConstructionBound(file => file === path ? changed : read(file));
  assert.equal(bound.bytes, 2552);
  assert.equal(bound.completeConstructorByteCorrespondence, false);
});

test('constructor census refuses eager allocations and replacement callback owners', () => {
  const source = read(managedPath).toString();
  const changed = source.replace('    accepts,\n    capacity,\n    bounded_relation_capacity,',
    '    accepts: sequence => true,\n    capacity,\n    bounded_relation_capacity,');
  assert.notEqual(changed, source);
  assert.throws(() => providerConstructionBound(file => file === managedPath ? changed : read(file)),
    /construction wrapper accepts/);
  const path = 'src/connectors/local/cross_join_provider.mbt';
  const factory = read(path).toString();
  const allocated = factory.replace(') -> ManagedProvider {\n  managed_provider(',
    ') -> ManagedProvider {\n  let extra = Array::make(100, None)\n  managed_provider(');
  assert.notEqual(allocated, factory);
  assert.throws(() => providerConstructionBound(file => file === path ? allocated : read(file)),
    /constructor source allocations/);
});
