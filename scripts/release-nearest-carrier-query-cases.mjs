import assert from 'node:assert/strict';
import {nearestCarrierPublicFixtures} from './fixtures/nearest-carrier-public-input.mjs';

export async function selectReleaseNearestCarrierCases(directory) {
  const original = await nearestCarrierPublicFixtures(directory);
  const normalNames = ['relation-relation', 'relation-vectors', 'vectors-relation',
    'vectors-vectors', 'vectors-restated'].flatMap(name => ['sql', 'aql-text']
    .map(format => `nearest-carrier-${name}-${format}`));
  const refusalNames = ['query-role', 'query-component', 'candidate-role',
    'candidate-component', 'old-output-scope'].map(name => `nearest-carrier-refusal-${name}`);
  assert.deepEqual(original.successes.map(item => item.name), normalNames);
  assert.deepEqual(original.refusals.map(item => item.name), refusalNames);
  // Counters are test observations only and are excluded from the submitted
  // Client input by the original public reader. Both original Sources are
  // acquired once; unused WITH checks cannot acquire another copy.
  return {successes: original.successes.map(item => ({...item,
    sourceReadCount: 2, sourceReadSessionCount: 2})), refusals: original.refusals};
}
