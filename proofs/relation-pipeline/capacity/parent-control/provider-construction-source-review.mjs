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
