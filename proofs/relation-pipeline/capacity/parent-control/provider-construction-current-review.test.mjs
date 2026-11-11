import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash} from '../../inventory.mjs';
import {providerConstructionBound} from './provider-construction.mjs';
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
  assert.equal(bound.bytes, 2432);
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
  ['prefix substituted by full count', selectedPath,
    '            let reclaims_scratch = state.position <= reclaimed_prefix',
    '            let reclaims_scratch = state.position <= count'],
  ['missing cleanup ACK', selectedPath, '        if reclaimed.val {', '        if true {'],
  ['Calendar accepted as a row kernel', generatedPath,
    '      | @lower.CalendarStep(_)\n', ''],
  ['unaccounted Calendar owner', generatedPath,
    '  calendar_output_ceilings : Array[(Int, Int64)]\n',
    '  calendar_output_ceilings : Array[(Int, Int64)]\n  extra_owner : Array[Int]\n'],
  ['changed constructor callback field', managedPath,
    '  accepts : ', '  extra_capture : Int\n  accepts : '],
  ['unknown whole-source change', generatedPath, 'struct GeneratedSequence {',
    'struct GeneratedSequence {\n  unknown : Int'],
]) {
  test(`current construction refuses ${name}`, () => {
    const original = read(path).toString();
    assert(original.includes(before), `Missing independent negative target ${name}`);
    const changed = original.replace(before, after);
    assert.notEqual(changed, original);
    assert.throws(() => providerConstructionBound(file => file === path ? changed : read(file)),
      /Unreviewed current constructor source/);
  });
}

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
  assert.equal(bound.bytes, 2432);
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
