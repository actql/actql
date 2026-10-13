import assert from 'node:assert/strict';
import {nearestRequiredSuccesses, nearestRequiredRefusals}
  from './fixtures/nearest-required-public-input.mjs';
export function selectReleaseNearestRequiredCases() {
  assert.deepEqual(nearestRequiredSuccesses.map(item => item.name),
    ['ties', 'empty', 'shared-producer'].flatMap(name =>
      ['json', 'sql', 'aql-text'].map(format => `nearest-required-${name}-${format}`)));
  assert.deepEqual(nearestRequiredRefusals.map(item => item.name),
    ['missing-query-vector', 'missing-candidate-vector', 'relation-roles-omitted',
      'nullable-query-key', 'dimension-mismatch'].flatMap(name =>
      ['sql', 'aql-text'].map(format => `nearest-required-${name}-${format}`)));
  assert.equal(nearestRequiredSuccesses.reduce((n, item) => n + item.sourceReadSessionCount, 0), 10);
  return {successes: nearestRequiredSuccesses, refusals: nearestRequiredRefusals};
}
