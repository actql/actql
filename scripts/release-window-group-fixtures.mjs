// Test-only inputs. Execution uses only the normal fixed release packages.
import assert from 'node:assert/strict';
import {windowGroupSourceSuccesses, windowGroupSourceRefusals}
  from './fixtures/window-group-source-input.mjs';
export {releaseVectorScalarEnvironment as releaseWindowGroupEnvironment}
  from './release-vector-scalar-fixtures.mjs';

const normal = ['field', 'expression-filter-distinct', 'empty'].flatMap(variant =>
  ['json', 'sql', 'aql-text'].map(format => `window-group-${format}-${variant}`));
const refusal = ['missing-window', 'fake-window-fields', 'fn-enum-case', 'literal-field',
  'nonboolean-filter', 'unknown-expression', 'field-and-expression', 'fn-option',
  'unresolved-order'].map(name => `window-group-${name}`);
export function selectReleaseWindowGroupCases({successes = windowGroupSourceSuccesses,
  refusals = windowGroupSourceRefusals} = {}) {
  assert.deepEqual(successes.map(item => item.name), normal);
  assert.deepEqual(refusals.map(item => item.name), refusal);
  for (const item of successes) {
    const resultName = item.format === 'json' ? 'answer' : 'main';
    assert.equal(item.sourceReadSessionCount, 1);
    assert.ok(Array.isArray(item.sourceRows));
    assert.ok(Array.isArray(item.results[resultName].rows));
    assert.ok(Array.isArray(item.results[resultName].columns));
  }
  return {successes, refusals};
}
export const releaseWindowGroupFixturePaths = Object.freeze([
  'scripts/fixtures/release-window-group-worker.mjs',
  'scripts/fixtures/packed-window-group-source.mjs',
  'scripts/fixtures/window-group-installed-source.mjs',
  'scripts/fixtures/window-group-source-input.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/cte-value-table-receipts.mjs',
  'scripts/fixtures/retained-fixture-values.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
]);
