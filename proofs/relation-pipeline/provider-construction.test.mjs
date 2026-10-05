import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hash } from './inventory.mjs';
import { providerConstructionBound, inspectProviderConstruction } from './capacity/parent-control/provider-construction.mjs';
import {constructionSourceReview, reviewedFunction, selectedFactoryOutsideAccepts,
  managedBeforePausePolls} from './capacity/parent-control/provider-construction-source-review.mjs';
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

// The actual recipe-introduction sources remain the review baseline. These
// checks distinguish the reviewed source changes from arbitrary digest refresh.
const recipeIntroduction = '58fd19eade59cf3bcbf6a859c9821471346e3b41';
const historical = (path, revision = recipeIntroduction) => execFileSync('git', ['--no-replace-objects', 'show',
  `${revision}:${path}`], {cwd:fileURLToPath(new URL('../../',import.meta.url))});
test('historical reviewed handoff helper leaves provider fields and constructor bodies unchanged', () => {
  const path = 'src/connectors/local/managed_provider.mbt';
  const before = historical(path), reviewed = historical(path, constructionSourceReview.historicalReviewRevision);
  const source = reviewed.toString();
  assert.equal(hash(reviewed), '40b1b803e586d1dbce5eb0dabc9888d57ae0eb28bebbcee7e0d3b4fd5fa00950');
  assert.equal(hash(before), '8d00f3fb875d1523796a13ae5ac67906fb16f9ee64f67cd85205bc0544ca3f2e');
  const start = source.indexOf('///|\n/// Charge a validated handoff delta to the SAME provider accounting owner.');
  const end = source.indexOf('///|\npub fn cancel_managed_provider(',start);
  assert(start >= 0 && end > start);
  // The whole remaining file, including all fields, wrappers, captures and
  // accounting/lifecycle functions, must equal the original source bytes.
  assert.equal(source.slice(0,start) + source.slice(end), before.toString());
  assert.throws(() => providerConstructionBound(p => p === path ? before : read(p)),
    /Changed provider representation premise src\/connectors\/local\/managed_provider\.mbt/);
});
test('historical reviewed Graph rejection branches and traversal ledger preserve Relation candidate construction', () => {
  const path = 'src/execution_relation/generated_sequence.mbt';
  const before = historical(path), reviewed = historical(path, constructionSourceReview.historicalReviewRevision);
  const source = reviewed.toString();
  assert.equal(hash(reviewed), '1a2df7350b1227ede42556733faf8ecd22abd77919b946ce47848f196d5aec69');
  assert.equal(hash(before), '3a2c83c19c767b0f160afde6b85fe84ab87e3a0a391dc95a52be98edae760981');
  const oldBranch = [
    '      | @lower.GraphBasicStep(_)',
    '      | @lower.GraphStructuralStep(_)',
    '      | @lower.GraphUnionStep(_)',
    '      | @lower.GraphMeanStep(_)',
    '      | @lower.GraphMatchStep(_)',
    '      | @lower.GraphReachStep(_)',
    '      | @lower.GraphSubgraphStep(_)',
    '      | @lower.GraphTraverseStep(_)',
    '      | @lower.GraphShortestStep(_)',
    '      | @lower.GraphRelationStep(_)',
    '      | @lower.GraphConstructionStep(_)',
  ].join('\n');
  const newBranch = [
    '      | @lower.GraphMatchStep(_)',
    '      | @lower.GraphTraverseStep(_)',
    '      | @lower.GraphDiagnosticStep(_)',
    '      | @lower.GraphEqualityStep(_)',
    '      | @lower.GraphNormalizeStep(_)',
    '      | @lower.PropertyGraphConstructionStep(_)',
  ].join('\n');
  assert.equal(before.toString().split(oldBranch).length,2);
  // GraphNormalizeStep only joins the row-kernel exclusion branch; it does
  // not change the candidate factory count, callback shape or live captures.
  // Compare the entire original source outside these exact reviewed changes.
  // The new ledger belongs to the prepared configuration, not to the eleven
  // candidate factories or the retained parent-core component. Its allocation
  // and old/new lifetime overlap remain explicit unresolved census obligations.
  const replaceOnce = (text, from, to) => {
    assert.equal(text.split(from).length, 2, 'Changed reviewed traversal ledger premise');
    return text.replace(from, to);
  };
  let withoutLedger = replaceOnce(source,
    '  traversal_ceilings : Array[(Int, Int64, Int64)]\n', '');
  withoutLedger = replaceOnce(withoutLedger, '        traversal_ceilings: [],\n', '');
  withoutLedger = replaceOnce(withoutLedger,
    '    !generated.session_output_ceilings.is_empty() ||\n    !generated.traversal_ceilings.is_empty() {',
    '    !generated.session_output_ceilings.is_empty() {');
  const helpers = `///|
/// Bind independent search-path and output-row envelopes to the checked
/// traversal occurrence. Neither quantity is inferred from the other.
pub fn constrain_generated_traversal(
  generated : GeneratedSequence,
  step : Int,
  paths : Int64,
  rows : Int64,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if paths < 0L || rows < 0L {
    return Err(InvalidLimits)
  }
  guard @lower.sequence_step(generated.sequence, step)
    is Some(@lower.GraphTraverseStep(_)) else {
    return Err(InputSet)
  }
  let ceilings = generated.traversal_ceilings.copy()
  for index, (prior_step, prior_paths, prior_rows) in ceilings {
    if prior_step == step {
      ceilings[index] = (
        step,
        Int64::min(paths, prior_paths),
        Int64::min(rows, prior_rows),
      )
      return Ok({ ..generated, traversal_ceilings: ceilings, })
    }
  }
  ceilings.push((step, paths, rows))
  Ok({ ..generated, traversal_ceilings: ceilings, })
}

///|
pub fn generated_traversal_ceilings(
  generated : GeneratedSequence,
  step : Int,
) -> (Int64, Int64)? {
  for (candidate, paths, rows) in generated.traversal_ceilings {
    if candidate == step {
      return Some((paths, rows))
    }
  }
  None
}

`;
  withoutLedger = replaceOnce(withoutLedger, helpers, '');
  assert.equal(before.toString().replace(oldBranch,newBranch),withoutLedger);
  assert.throws(() => providerConstructionBound(p => p === path ? before : read(p)),
    /Changed provider representation premise src\/execution_relation\/generated_sequence\.mbt/);
});

test('current wrappers and selected construction outside accepts equal the original bodies', () => {
  const managedPath = 'src/connectors/local/managed_provider.mbt';
  const managed = read(managedPath).toString(), original = historical(managedPath).toString();
  for (const name of Object.keys(constructionSourceReview.wrapperDigests)) {
    assert.equal(reviewedFunction(managed, name), reviewedFunction(original, name));
  }
  const selectedPath = 'src/connectors/local/selected_relation_provider.mbt';
  assert.equal(selectedFactoryOutsideAccepts(read(selectedPath).toString()),
    selectedFactoryOutsideAccepts(historical(selectedPath).toString()));
  assert.equal(managedBeforePausePolls(managed),
    historical(managedPath, constructionSourceReview.historicalReviewRevision).toString());
  assert.equal(providerConstructionBound(read).sourceReview.completeParentUpper, false);
});

test('current Graph variants are only reviewed row-kernel exclusions, without factory changes', () => {
  const path = 'src/execution_relation/generated_sequence.mbt';
  for (const variant of constructionSourceReview.generatedVariants) {
    const source = historical(path, variant.revision);
    assert.equal(hash(source), variant.digest);
    const bound = providerConstructionBound(p => p === path ? source : read(p));
    assert.equal(bound.sourceReview.generatedDigest, variant.digest);
    assert.equal(bound.bytes, 2344);
    assert.equal(bound.completeConstructorByteCorrespondence, false);
  }
});

test('current construction does not accept a historical pin as a current-source fallback', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const original = historical(path);
  assert.throws(() => providerConstructionBound(p => p === path ? original : read(p)),
    /Unreviewed provider constructor/);
  const recipe = 'proofs/relation-pipeline/capacity/parent-control/provider-construction.json';
  const changed = JSON.parse(read(recipe));
  changed.bounds.callbackReferenceCaptures++;
  assert.throws(() => providerConstructionBound(p => p === recipe ? Buffer.from(JSON.stringify(changed)) : read(p)),
    /Changed original provider recipe/);
});

test('new fields, captures and pause work branches remain unreviewed source changes', () => {
  for (const [path, from, to] of [
    ['src/connectors/local/managed_provider.mbt', 'struct ManagedProvider {',
      'struct ManagedProvider {\n  additional : String'],
    ['src/connectors/local/managed_provider.mbt', '| Settling(_, progress~, work~)',
      '| Settling(_, progress~, work~) => (progress, 0L)'],
    ['src/connectors/local/selected_relation_provider.mbt',
      'fn selected_relation_provider(\n  limits : @execution.SequenceExecutionLimits,',
      'fn selected_relation_provider(\n  extra : String,\n  limits : @execution.SequenceExecutionLimits,'],
  ]) {
    const source = read(path).toString();
    assert.equal(source.split(from).length, 2);
    assert.throws(() => providerConstructionBound(p => p === path ? Buffer.from(source.replace(from, to)) : read(p)),
      /Unreviewed provider constructor|Changed provider representation premise/);
  }
});
