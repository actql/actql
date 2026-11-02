import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {hash} from '../../inventory.mjs';
import {checkConstructionSourceReview, constructionSourceReview,
  reviewedFunction, selectedBeforeInputOnly,
  selectedFactoryOutsideAccepts} from './provider-construction-source-review.mjs';

const directory = 'proofs/relation-pipeline/capacity/parent-control/';
const historicalRecipePath = directory + 'provider-construction.json';
const currentRecipePath = directory + 'provider-construction-current.json';
const historicalReviewPath = directory + 'provider-construction-source-review.json';
const reviewBytes = readFileSync(new URL('./provider-construction-current-review.json', import.meta.url));
export const currentConstructionReview = JSON.parse(reviewBytes);
const paths = ['src/connectors/local/selected_relation_provider.mbt',
  'src/connectors/local/managed_provider.mbt',
  'src/execution_relation/generated_sequence.mbt'];

// Archived source correspondence only. Current constructor admission uses the
// direct census in provider-construction.mjs, without these reverse deltas.

// Reverse only the independently reviewed literal deltas. Both complete blobs
// are pinned: an unknown change, absent hunk or duplicate occurrence refuses.
// Reconstructed text is evidence for the old checker, never runtime code.
export function historicalConstructionSource(source, entry) {
  assert.equal(hash(source), entry.currentSha256, `Unreviewed current constructor source ${entry.path}`);
  let previous = source;
  for (const {before, after} of entry.hunks) {
    assert(before && after && before !== after, 'Invalid reviewed constructor delta');
    assert.equal(previous.split(after).length, 2, 'Changed reviewed constructor delta');
    previous = previous.replace(after, before);
  }
  assert.equal(hash(previous), entry.previousSha256, `Changed historical constructor preimage ${entry.path}`);
  return previous;
}

export function checkCurrentConstructionSourceReview(profile, read) {
  const review = currentConstructionReview;
  assert.deepEqual(review.sources.map(entry => entry.path), paths);
  const recipe = read(currentRecipePath).toString();
  const historicalRecipe = read(historicalRecipePath).toString();
  assert.equal(hash(recipe), review.currentRecipeSha256, 'Changed current constructor recipe');
  assert.equal(hash(historicalRecipe), review.historicalRecipeSha256, 'Changed historical constructor recipe');
  assert.equal(hash(read(historicalReviewPath)), review.historicalReviewSha256,
    'Changed historical constructor review');
  assert.deepEqual(profile, JSON.parse(recipe), 'Constructor consumer did not bind the current recipe');
  const current = new Map(), historical = new Map();
  let previousRecipe = recipe;
  for (const entry of review.sources) {
    const source = read(entry.path).toString();
    current.set(entry.path, source);
    historical.set(entry.path, historicalConstructionSource(source, entry));
    assert.equal(previousRecipe.split(entry.currentSha256).length, 2,
      'Missing or duplicate current constructor premise');
    previousRecipe = previousRecipe.replace(entry.currentSha256, entry.previousSha256);
  }
  assert.equal(previousRecipe, historicalRecipe,
    'Constructor recipe changed beyond the three reviewed source premises');
  const selected = current.get(paths[0]), managed = current.get(paths[1]);
  assert.equal(hash(selectedFactoryOutsideAccepts(selectedBeforeInputOnly(selected))),
    constructionSourceReview.selectedFactoryOutsideAcceptsDigest,
    'Changed current candidate constructor outside accepts');
  for (const [name, digest] of Object.entries(constructionSourceReview.wrapperDigests)) {
    assert.equal(hash(reviewedFunction(managed, name)), digest,
      `Changed current candidate construction wrapper ${name}`);
  }
  // All original source, exact historical normalization and refusal checks run.
  // This adapter adds no constructor bound, capture or callback lifetime law.
  const historicalRead = path => historical.has(path) ? historical.get(path) : read(path);
  const prior = checkConstructionSourceReview(JSON.parse(historicalRecipe), historicalRead);
  return {...prior, historicalSourceReview: prior,
    reviewDigest: hash(reviewBytes), recipeDigest: hash(recipe),
    selectedDigest: hash(selected), managedDigest: hash(managed),
    generatedDigest: hash(current.get(paths[2])),
    reviewedGeneratedRevision: review.currentSourceRevision,
    scope: review.constructionScope,
    completeConstructorByteCorrespondence: false,
    completeParentUpper: false, completePipelineUpper: false};
}
