import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hash } from './inventory.mjs';
import { retainedProviderConstructionBound as providerConstructionBound, inspectProviderConstruction as inspectConstruction } from './capacity/parent-control/provider-construction.mjs';
import {constructionSourceReview, reviewedFunction, selectedFactoryOutsideAccepts,
  managedBeforePausePolls, selectedBeforeInputOnly, selectedBeforeReviewedLifecycle, providerBeforeReviewedCleanup,
  selectedBeforeBoundaryDispatch, generatedBeforeBoundaryExclusions} from './capacity/parent-control/provider-construction-source-review.mjs';
import {retainedConstructionFixtureRead} from './fixtures/retained-construction-source.mjs';
// These retained historical laws validate their exact reconstructed source, not
// current Native records. Current source admission is tested independently.
const reconstructedRead = retainedConstructionFixtureRead;
// Boundary-specific laws below refer to the independently pinned final Graph
// variant, not the older generated premise in the Calendar reverse-delta proof.
const read = path => path === 'src/execution_relation/generated_sequence.mbt'
  ? execFileSync('git', ['--no-replace-objects', 'show',
    `2bff752cb0eef171aa8f7ba614b301e052b7dff3:${path}`],
    {cwd: fileURLToPath(new URL('../../', import.meta.url))})
  : reconstructedRead(path);
const inspectProviderConstruction = (facts, read, target) => inspectConstruction(facts, read, target, {retained: true});
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
test('input-only support changes only the exact acceptance and execution branches', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const current = read(path).toString();
  const previous = historical(path, 'fdb902734d253cc171fa2c0c7e478f8611064de2').toString();
  assert.equal(hash(previous), '3fed93a0919b10bc204c93d90d8e217344dc44831c87b6337cfdb7f08e168d4a');
  assert.equal(selectedBeforeInputOnly(current), previous);
  for (const [from, to] of [
    ['@lower.preparation_input_count(prepared) == 1', '@lower.preparation_input_count(prepared) >= 1'],
    ['sequence, input, execution, max_value_bytes, -1,', 'sequence, input, execution, max_value_bytes, 0,'],
  ]) {
    assert.equal(current.split(from).length, 2);
    assert.throws(() => selectedBeforeInputOnly(current.replace(from, to)),
      /reviewed representation delta/u);
  }
});
test('retained historical lifecycle review changes only cleanup completion and detached built-in eligibility', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const source = read(path).toString();
  const previous = historical(path, constructionSourceReview.lifecycleReview.previousRevision).toString();
  assert.equal(hash(previous), constructionSourceReview.lifecycleReview.previousSelectedDigest);
  assert.equal(selectedBeforeReviewedLifecycle(source), previous);
  for (const name of ['selected_relation_provider', 'bounded_relation_chain_execution_state',
    'bounded_relation_chain_capacity']) {
    assert.equal(reviewedFunction(selectedBeforeInputOnly(source), name), reviewedFunction(previous, name),
      `Unreviewed factory/state/capacity change: ${name}`);
  }
  const bound = providerConstructionBound(read);
  assert.equal(bound.bytes, 2344);
  assert.equal(bound.completeConstructorByteCorrespondence, false);
  assert.equal(bound.completeParentUpper, false);
  assert.equal(bound.completePipelineUpper, false);
});
test('all eleven candidate providers retain exact constructor grounds through cleanup completion adaptation', () => {
  const recipe = JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/provider-construction.json'));
  assert.equal(recipe.providers.length, 11);
  for (const provider of recipe.providers.slice(1)) {
    const source = read(provider.path).toString();
    const previous = historical(provider.path, constructionSourceReview.lifecycleReview.previousRevision).toString();
    assert.equal(providerBeforeReviewedCleanup(source, provider.name), previous);
    assert.equal(hash(previous), constructionSourceReview.lifecycleReview.previousProviderDigests[provider.path]);
    const kernel = provider.name.replace(/_provider$/u, '');
    const needle = `!@execution.bounded_${kernel}_cleanup_pending(`;
    assert.equal(source.split(needle).length, 2, 'Missing unique cleanup witness');
    assert.throws(() => providerBeforeReviewedCleanup(source.replace(needle, needle.slice(1)), provider.name),
      /reviewed representation delta/u);
  }
});
for (const [name, from, to] of [
  ['transition treated as completion', 'reclaimed.val = !@execution.bounded_binding_rows_cleanup_pending(', 'reclaimed.val = @execution.bounded_binding_rows_cleanup_pending('],
  ['pending responsibility dropped', 'Ok(reclaimed.val)', 'Ok(true)'],
  ['cleanup error hidden', 'Err(issue) => Err(selected_binding_rows_issue(issue, step))', 'Err(_) => Ok(true)'],
  ['Values completion excluded', '      Some(@lower.ValuesStep(_)) => ()\n', ''],
  ['UNNEST completion excluded', ' &&\n          !(@lower.kernel_body(kernel) is @lower.Unnest(_, _, _, _, _))', ''],
  ['Append completion excluded', '      Some(@lower.AppendStep(_)) => ()\n', ''],
  ['analytic completion excluded', '          !(@lower.kernel_body(kernel) is @lower.AnalyticRows(_)) &&\n', ''],
  ['UNPIVOT completion excluded', '          !(@lower.kernel_body(kernel) is @lower.Unpivot(_, _, _, _)) &&\n', ''],
  ['unreviewed family admitted', '      _ => return false\n', '      _ => ()\n'],
]) test(`lifecycle source review refuses ${name}`, () => {
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
  const functionName = name.includes('completion') || name.startsWith('pending') || name.startsWith('cleanup')
    ? (name.startsWith('Values') || name.startsWith('UNNEST') || name.startsWith('Append') ||
        name.startsWith('analytic') || name.startsWith('UNPIVOT')
      ? 'relation_chain_reclaims_completed_scratch' : 'selected_binding_rows_execution')
    : 'relation_chain_reclaims_completed_scratch';
  const body = reviewedFunction(source, functionName);
  assert.equal(body.split(from).length, 2, 'Missing unique mutation target');
  const mutated = source.replace(body, body.replace(from, to));
  assert.throws(() => selectedBeforeReviewedLifecycle(mutated),
    /reviewed representation delta|scratch eligibility|Lifecycle changes/u);
});
test('Append, analytic and UNPIVOT scratch eligibility leaves every construction and capture byte unchanged', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const previous = historical(path, 'eb3a7a78a7426a9be397b62545e76984a25aba43').toString();
  assert.equal(hash(previous), '40dbff3cc79f6d83d2dffd2f2d41bf514738bcaa5c1a728b810fcf6d343b892f');
  const current = selectedBeforeInputOnly(read(path).toString());
  let remaining = current;
  for (const addition of [
    '      Some(@lower.AppendStep(_)) => ()\n',
    '          !(@lower.kernel_body(kernel) is @lower.AnalyticRows(_)) &&\n',
    '          !(@lower.kernel_body(kernel) is @lower.Unpivot(_, _, _, _)) &&\n',
  ]) {
    assert.equal(remaining.split(addition).length, 2, 'Missing unique scratch-eligibility extension');
    remaining = remaining.replace(addition, '');
  }
  assert.equal(remaining, previous, 'Unreviewed change outside the three pure eligibility branches');
  for (const name of ['selected_relation_provider', 'bounded_relation_chain_execution_state',
    'bounded_relation_chain_capacity', 'selected_binding_rows_execution']) {
    assert.equal(reviewedFunction(current, name), reviewedFunction(previous, name),
      `Construction, captures, capacity or cleanup changed: ${name}`);
  }
  const bound = providerConstructionBound(read);
  assert.equal(bound.bytes, 2344);
  assert.equal(bound.completeConstructorByteCorrespondence, false);
  assert.equal(bound.completeParentUpper, false);
  assert.equal(bound.completePipelineUpper, false);
});
test('reviewed composition adds only typed Graph row-kernel exclusions to the integrated source premise', () => {
  const path = 'src/execution_relation/generated_sequence.mbt';
  const integratedMain = 'eb74d7b65d0f338ef5862a7d9cd7397744a08eaa';
  const before = execFileSync('git', ['--no-replace-objects', 'show',
    `${integratedMain}:${path}`], {cwd:fileURLToPath(new URL('../../',import.meta.url))});
  assert.equal(hash(before), '689b1f1eaef074e44132348bf9927349324c94325fb10ebf304191e6cb7b6ac3');
  const source = generatedBeforeBoundaryExclusions(read(path).toString());
  let remaining = source.replace('      | @lower.GraphConstructionStep(_)\n',
    '      | @lower.PropertyGraphConstructionStep(_)\n');
  for (const operation of ['GraphUnionStep', 'GraphSubtractionStep', 'GraphMeanStep']) {
    const branch = `      | @lower.${operation}(_)\n`;
    assert.equal(remaining.split(branch).length, 2, `Missing or duplicated ${operation} exclusion`);
    remaining = remaining.replace(branch, '');
  }
  assert.equal(remaining, before.toString(),
    'Composition changed a GeneratedSequence field, constructor, callback or unrelated execution path');
  // This exact delta check does not refresh the older recipe's source pins or
  // certify the inherited main changes. Those original checks stay mandatory.
});

test('Mean exclusion preserves the complete integrated construction source and byte model', () => {
  const path = 'src/execution_relation/generated_sequence.mbt';
  const before = historical(path, 'ba0779ad8551bb06476c275cc74cebeef4463751').toString();
  assert.equal(hash(before), '7e71c827d4004e769a22891f97dba162e7854a87f45e081dcb9a5c50bbbc460a');
  const source = generatedBeforeBoundaryExclusions(read(path).toString());
  const branch = '      | @lower.GraphMeanStep(_)\n';
  assert.equal(source.split(branch).length, 2, 'Mean is one reviewed false-branch alternative');
  assert.equal(source.replace(branch, ''), before,
    'Mean changed construction, records, callbacks, captures, arrays or unrelated paths');
  const bound = providerConstructionBound(read);
  assert.equal(bound.bytes, 2344);
  assert.equal(bound.completeConstructorByteCorrespondence, false);
  assert.equal(bound.completeParentUpper, false);
  assert.equal(bound.completePipelineUpper, false);
});

test('receiving metadata and reviewed input-only callback delta preserve constructor grounds', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const before = historical(path, 'b98a50ff763d1367e344fdfa8aea380ec8749132').toString();
  const current = selectedBeforeInputOnly(read(path).toString());
  assert.equal(reviewedFunction(current, 'selected_relation_provider'),
    reviewedFunction(before, 'selected_relation_provider'));
  assert.equal(hash(reviewedFunction(current, 'selected_relation_provider')),
    'f2fb44c23c59859a7c4324684c7afe3b50218ebe287d8e7e9ce62c9ff5e94256');
  assert(current.includes('advance_relation_chain_inputs(cursor)'));
  assert(current.includes('cancel_relation_chain_inputs(cursor)'));
});
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

test('retained historical wrappers and selected construction outside accepts equal the original bodies', () => {
  const managedPath = 'src/connectors/local/managed_provider.mbt';
  const managed = read(managedPath).toString(), original = historical(managedPath).toString();
  for (const name of Object.keys(constructionSourceReview.wrapperDigests)) {
    assert.equal(reviewedFunction(managed, name), reviewedFunction(original, name));
  }
  const selectedPath = 'src/connectors/local/selected_relation_provider.mbt';
  assert.equal(selectedFactoryOutsideAccepts(selectedBeforeInputOnly(read(selectedPath).toString())),
    selectedFactoryOutsideAccepts(historical(selectedPath).toString()));
  assert.equal(managedBeforePausePolls(managed),
    historical(managedPath, constructionSourceReview.historicalReviewRevision).toString());
  assert.equal(providerConstructionBound(read).sourceReview.completeParentUpper, false);
});

test('retained historical Graph variants are only reviewed row-kernel exclusions, without factory changes', () => {
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

test('retained historical construction does not accept a historical pin as a current-source fallback', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const original = historical(path);
  assert.throws(() => providerConstructionBound(p => p === path ? original : read(p)),
    /Unreviewed provider constructor/);
  const recipe = 'proofs/relation-pipeline/capacity/parent-control/provider-construction.json';
  const oldRecipe = historical(recipe, constructionSourceReview.historicalReviewRevision);
  assert.equal(hash(oldRecipe), constructionSourceReview.originalRecipeDigest);
  assert.throws(() => providerConstructionBound(p => p === recipe ? oldRecipe : read(p)),
    /Changed current provider recipe/);
  const current = JSON.parse(read(recipe));
  const bound = providerConstructionBound(read);
  assert.equal(current.providers[0].sourceDigest, bound.sourceReview.selectedDigest);
  assert.equal(current.sourcePremises['src/connectors/local/managed_provider.mbt'], bound.sourceReview.managedDigest);
  assert.equal(bound.sourceReview.recipeDigest, hash(read(recipe)));
  const changed = JSON.parse(read(recipe));
  changed.bounds.callbackReferenceCaptures++;
  assert.throws(() => providerConstructionBound(p => p === recipe ? Buffer.from(JSON.stringify(changed)) : read(p)),
    /Changed current provider recipe/);
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

// These use immutable Git sources as independent expectations; current output
// or an updated digest alone does not establish construction correspondence.
test('boundary dispatch reconstructs the complete reviewed constructor source',()=>{
  const path='src/connectors/local/selected_relation_provider.mbt';
  const current=read(path).toString();
  const prior=historical(path,'10ad17b09e17d7696e664c90dc88d98f1b7d0c73').toString();
  assert.equal(selectedBeforeBoundaryDispatch(current),prior);
  assert.equal(hash(prior),constructionSourceReview.selectedDigest);
  for(const name of ['selected_relation_provider','bounded_relation_chain_execution_state','bounded_relation_chain_capacity']) {
    assert.equal(reviewedFunction(current,name),reviewedFunction(prior,name));
  }
  const recipe=read('proofs/relation-pipeline/capacity/parent-control/provider-construction.json').toString();
  const oldRecipe=recipe.replace(constructionSourceReview.boundaryDispatchReview.selectedDigest,
    constructionSourceReview.selectedDigest);
  assert.equal(hash(oldRecipe),constructionSourceReview.currentRecipeDigest);
  assert.equal(providerConstructionBound(read).bytes,2344);
});
test('boundary exclusions reconstruct the complete reviewed generated source',()=>{
  const path='src/execution_relation/generated_sequence.mbt';
  const current=read(path).toString();
  const prior=historical(path,'4fd03c918b8e125fd712904c58dbef9fbc1dbe82').toString();
  assert.equal(generatedBeforeBoundaryExclusions(current),prior);
  assert.equal(hash(prior),'4fe922203e2da77f52d97d6e2e4467cf4859c8a63302d4e01b3bd3d7098f5cfd');
});
for(const [name,path,normalizer,from,to] of [
  ['missing Infer dispatch','src/connectors/local/selected_relation_provider.mbt',selectedBeforeBoundaryDispatch,
    '    | Some(@lower.InferBoundary(_))\n',''],
  ['extra serialization dispatch','src/connectors/local/selected_relation_provider.mbt',selectedBeforeBoundaryDispatch,
    '    | Some(@lower.SerializationBoundary(_)) => true','    | Some(@lower.SerializationBoundary(_))\n    | Some(@lower.SerializationBoundary(_)) => true'],
  ['unexpected completed-producer eligibility','src/connectors/local/selected_relation_provider.mbt',selectedBeforeBoundaryDispatch,
    '    | Some(@lower.SerializationBoundary(_)) => true','    | Some(@lower.SerializationBoundary(_))\n    | Some(@lower.CompletedProducerBoundary(_)) => true'],
  ['serialization treated as row kernel','src/execution_relation/generated_sequence.mbt',generatedBeforeBoundaryExclusions,
    '      | @lower.CompletedProducerBoundary(_) => false','      | @lower.CompletedProducerBoundary(_) => true'],
  ['missing completed-producer exclusion','src/execution_relation/generated_sequence.mbt',generatedBeforeBoundaryExclusions,
    '      | @lower.SerializationBoundary(_)\n',''],
]) test('boundary source review rejects '+name,()=>{
  const source=read(path).toString();assert.equal(source.split(from).length,2);
  assert.throws(()=>normalizer(source.replace(from,to)),/reviewed representation delta/);
});
