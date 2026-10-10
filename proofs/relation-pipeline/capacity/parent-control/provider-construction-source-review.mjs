import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {hash} from '../../inventory.mjs';

const reviewBytes = readFileSync(new URL('./provider-construction-source-review.json', import.meta.url));
export const constructionSourceReview = JSON.parse(reviewBytes);
const recipePath = 'proofs/relation-pipeline/capacity/parent-control/provider-construction.json';

// Extract only these pinned declarations. This is an exact reviewed source
// correspondence, not a general MoonBit parser or a proof of capture inference.
export function reviewedFunction(source, name) {
  const pattern = new RegExp(`^(?:pub )?fn ${name}\\(`, 'gm');
  const starts = [...source.matchAll(pattern)];
  assert.equal(starts.length, 1, `Changed reviewed function ${name}`);
  const start = starts[0].index;
  const end = source.indexOf('\n///|', start);
  return source.slice(start, end < 0 ? source.length : end);
}

export function selectedFactoryOutsideAccepts(source) {
  const factory = reviewedFunction(source, 'selected_relation_provider');
  const start = factory.indexOf('    sequence => {');
  const end = factory.indexOf('\n    sequence => {', start + 1);
  assert(start >= 0 && end > start, 'Changed reviewed selected callbacks');
  return factory.slice(0, start) + '    REVIEWED_ACCEPTS_CALLBACK,\n' + factory.slice(end);
}

const replaceOnce = (source, from, to = '') => {
  assert.equal(source.split(from).length, 2, 'Changed reviewed representation delta');
  return source.replace(from, to);
};

export function managedBeforePausePolls(source) {
  let prior = replaceOnce(source,
    '  Waiting(progress~ : Int64, work~ : Int64)\n  Settling(Int, progress~ : Int64, work~ : Int64)\n');
  const start = prior.indexOf('///|\n/// No Compute is ready until the existing Host supplies current authority.');
  const end = prior.indexOf('///|\npub fn managed_provider_complete(', start);
  assert(start >= 0 && end > start, 'Changed reviewed pause helpers');
  const helpers = prior.slice(start, end);
  assert.equal(reviewedFunction(helpers, 'managed_provider_waiting'),
    'pub fn managed_provider_waiting(\n  progress : Int64,\n  work : Int64,\n) -> ManagedProviderPoll {\n  Waiting(progress~, work~)\n}\n');
  assert.equal(reviewedFunction(helpers, 'managed_provider_settling'),
    'pub fn managed_provider_settling(\n  slot : Int,\n  progress : Int64,\n  work : Int64,\n) -> ManagedProviderPoll {\n  Settling(slot, progress~, work~)\n}\n\n');
  prior = prior.slice(0, start) + prior.slice(end);
  return replaceOnce(prior,
    '      | Waiting(progress~, work~)\n      | Settling(_, progress~, work~)\n');
}

// These are exact historical source comparisons, never runtime fallbacks.
// The lower cleanup Bool reports a transition; the managed Bool reports completion.
// Values/Append/analytic/UNPIVOT/UNNEST extend private-scratch eligibility without changing the factory,
// parent state or capture roles. Their accepted output lifetime remains separate.
export function selectedBeforeReviewedLifecycle(source) {
  const execution = reviewedFunction(source, 'selected_binding_rows_execution');
  const currentCleanup = `          Ok(_) => {
            reclaimed.val = !@execution.bounded_binding_rows_cleanup_pending(
              active,
            )
            Ok(reclaimed.val)
          }`;
  const previousCleanup = `          Ok(true) => {
            reclaimed.val = true
            Ok(true)
          }
          Ok(false) => Ok(false)`;
  const priorExecution = replaceOnce(execution, currentCleanup, previousCleanup);
  let prior = replaceOnce(source, execution, priorExecution);
  const currentHelper = `fn relation_chain_reclaims_completed_scratch(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.JoinStep(_)) => ()
      // These built-ins detach their accepted completion before cleanup.
      // Cleanup releases only private scratch; downstream ports keep the
      // original output generation, including duplicate expansion rows.
      Some(@lower.ValuesStep(_)) => ()
      Some(@lower.AppendStep(_)) => ()
      Some(@lower.RowStep(kernel)) =>
        if !selected_binding_rows_supported(kernel) &&
          !(@lower.kernel_body(kernel) is @lower.Groups(_)) &&
          !(@lower.kernel_body(kernel) is @lower.CountGroups(_)) &&
          !(@lower.kernel_body(kernel) is @lower.AnalyticRows(_)) &&
          !(@lower.kernel_body(kernel) is @lower.Unpivot(_, _, _, _)) &&
          !(@lower.kernel_body(kernel) is @lower.Unnest(_, _, _, _, _)) {
          return false
        }
      _ => return false
    }
  }
  true
}
`;
  const previousHelper = `fn relation_chain_reclaims_completed_scratch(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.JoinStep(_)) => ()
      Some(@lower.RowStep(kernel)) =>
        if !selected_binding_rows_supported(kernel) &&
          !(@lower.kernel_body(kernel) is @lower.Groups(_)) &&
          !(@lower.kernel_body(kernel) is @lower.CountGroups(_)) {
          return false
        }
      _ => return false
    }
  }
  true
}
`;
  assert.equal(reviewedFunction(source, 'relation_chain_reclaims_completed_scratch'), currentHelper,
    'Changed detached-completion scratch eligibility');
  prior = replaceOnce(prior, currentHelper, previousHelper);
  assert.equal(hash(prior), constructionSourceReview.lifecycleReview.previousSelectedDigest,
    'Lifecycle changes exceeded the reviewed cleanup and detached-completion bodies');
  return prior;
}

// These source comparisons cover only the existing cleanup-completion adapters.
// Result.map callbacks in set/Nest execute during cleanup, outside the eleven
// candidate constructors. No temporary execution/cleanup allocation is charged
// to the conditional construction component by this correspondence.
export function providerBeforeReviewedCleanup(source, name) {
  const direct = ['cross_join', 'append', 'global_count', 'group', 'row_window',
    'unpivot', 'unnest', 'values'];
  const kernel = name.replace(/_provider$/u, '');
  if (direct.includes(kernel)) {
    const current = `              Ok(_) => {
                reclaimed.val = !@execution.bounded_${kernel}_cleanup_pending(
                  active,
                )
                Ok(reclaimed.val)
              }`;
    const previous = `              Ok(true) => {
                reclaimed.val = true
                Ok(true)
              }
              Ok(false) => Ok(false)`;
    return replaceOnce(source, current, previous);
  }
  assert(['set', 'nest'].includes(kernel), 'Unreviewed cleanup provider');
  const current = `            @execution.cleanup_bounded_${kernel}(active)
            .map(_ => !@execution.bounded_${kernel}_cleanup_pending(active))
            .map_err(issue => bounded_${kernel}_issue(issue, step))`;
  const previous = `            @execution.cleanup_bounded_${kernel}(active).map_err(issue => {
              bounded_${kernel}_issue(issue, step)
            })`;
  return replaceOnce(source, current, previous);
}

export function checkConstructionSourceReview(profile, read) {
  const review = constructionSourceReview;
  assert.equal(review.version, 'actql-provider-construction-source-review/0.1');
  assert.equal(hash(read(recipePath)), review.currentRecipeDigest, 'Changed current provider recipe');
  const selectedPath = 'src/connectors/local/selected_relation_provider.mbt';
  const managedPath = 'src/connectors/local/managed_provider.mbt';
  const generatedPath = 'src/execution_relation/generated_sequence.mbt';
  const selected = read(selectedPath).toString();
  const managed = read(managedPath).toString();
  const generated = read(generatedPath).toString();
  assert.equal(hash(selected), review.selectedDigest, 'Unreviewed provider constructor selected_relation_provider');
  for (const provider of profile.providers.slice(1)) {
    const prior = providerBeforeReviewedCleanup(read(provider.path).toString(), provider.name);
    assert.equal(hash(prior), review.lifecycleReview.previousProviderDigests[provider.path],
      `Provider lifecycle changed outside reviewed cleanup completion: ${provider.name}`);
  }
  assert.equal(hash(replaceOnce(selectedBeforeReviewedLifecycle(selected),
    '  if @lower.kernel_json_pick(kernel) is Some(_) ||\n    @lower.kernel_bindings(kernel) is Some(_) ||\n    @lower.kernel_unique_keys(kernel) is Some(_) ||\n    @lower.kernel_is_projection(kernel) {\n    return true\n  }\n')),
    '4f02d43052c899c9105574f72dd17cda04caa3695390d93ef73e972bf4cb8227',
    'Borrowed JSON path changed more than the reviewed support guard');
  assert.equal(hash(managed), review.managedDigest, `Changed provider representation premise ${managedPath}`);
  for (const [name, digest] of Object.entries(review.wrapperDigests)) {
    assert.equal(hash(reviewedFunction(managed, name)), digest, `Changed construction wrapper ${name}`);
  }
  assert.equal(hash(selectedFactoryOutsideAccepts(selected)), review.selectedFactoryOutsideAcceptsDigest,
    'Changed selected construction outside accepts');
  assert.equal(profile.sourcePremises[managedPath], review.managedDigest, 'Recipe does not bind current managed source');
  assert.equal(profile.sourcePremises[generatedPath], review.generatedVariants[0].digest,
    'Recipe does not bind the reviewed main generated source');
  assert.equal(hash(managedBeforePausePolls(managed)), review.historicalSourcePremises[managedPath],
    'Waiting/Settling changed more than the reviewed poll representation');
  const variant = review.generatedVariants.find(item => item.digest === hash(generated));
  assert(variant, `Changed provider representation premise ${generatedPath}`);
  let priorGenerated = generated;
  if (variant.constructorRename) {
    // Only the already integrated Graph constructor spelling changed. This
    // comparison preserves the historical blob; it creates no runtime alias.
    priorGenerated = replaceOnce(priorGenerated,
      '      | @lower.GraphConstructionStep(_)\n',
      '      | @lower.PropertyGraphConstructionStep(_)\n');
  }
  for (const name of ['GraphSubgraphStep', 'GraphDeltaStep', ...variant.additionalExclusions]) {
    priorGenerated = replaceOnce(priorGenerated, `      | @lower.${name}(_)\n`);
  }
  assert.equal(hash(priorGenerated), review.historicalSourcePremises[generatedPath],
    'Graph exclusions changed Relation preparation outside the reviewed false branch');
  return {reviewDigest: hash(reviewBytes), recipeDigest: review.currentRecipeDigest,
    historicalRecipeDigest: review.originalRecipeDigest,
    selectedDigest: hash(selected), managedDigest: hash(managed), generatedDigest: hash(generated),
    reviewedGeneratedRevision: variant.revision,
    scope: 'exact current construction source correspondence; callback execution and completed-output custody excluded',
    completeConstructorByteCorrespondence: false, completeParentUpper: false, completePipelineUpper: false};
}
