import assert from 'node:assert/strict';
import {quotedIdentifierSuccesses, quotedIdentifierRefusals}
  from './fixtures/quoted-identifier-source-input.mjs';
export {releaseVectorScalarEnvironment as releaseIdentifierEnvironment}
  from './release-vector-scalar-fixtures.mjs';

const normal = [
  ...['json-control', 'octal', 'hex-unicode', 'physical-newline', 'quote-and-control',
    'sql-input-range', 'pipe-input-range', 'quoted-parameter', 'empty-schema-retained']
    .map(name => `quoted-identifier-${name}`),
  ...['json-control', 'escaped-names', 'physical-names', 'sql-order',
    'pipe-rename-filter-order', 'parameter', 'exact-string-values', 'empty', 'range', 'cte']
    .map(name => `quoted-identifier-canonical-${name}`),
  ...['id', 'ROWS', 'offset'].map(name => `identifier-role-json-${name}`),
  ...['quoted-with', 'ordinary-with', 'quoted-range', 'quoted-output', 'quoted-element',
    'quoted-offset', 'quoted-pipe-alias', 'quoted-unpivot-alias'].flatMap(name =>
    ['sql', 'aql-text'].map(format => `identifier-role-${format}-${name}`)),
];
const refusal = [
  ...Array.from({length: 8}, (_, index) => `quoted-identifier-invalid-${index}`),
  'quoted-identifier-empty',
  ...Array.from({length: 3}, (_, index) => `quoted-identifier-canonical-invalid-${index}`),
  ...['with', 'with-case', 'output', 'range', 'element', 'offset', 'pipe-alias', 'unpivot-alias']
    .flatMap(name => ['sql', 'aql-text'].map(format => `identifier-role-${format}-invalid-${name}`)),
];
export function selectReleaseIdentifierCases({successes = quotedIdentifierSuccesses,
  refusals = quotedIdentifierRefusals} = {}) {
  assert.deepEqual(successes.map(item => item.name), normal);
  assert.deepEqual(refusals.map(item => item.name), refusal);
  assert.equal(successes.filter(item => item.sourceReadSessionCount === 1).length, 6);
  for (const item of successes) {
    assert.ok(Array.isArray(item.expected) && Array.isArray(item.columns));
    assert.ok(item.sourceReadSessionCount === 1 || item.sourceReadCount === 0);
  }
  return {successes, refusals};
}
export const releaseIdentifierFixturePaths = Object.freeze([
  'scripts/fixtures/release-identifier-worker.mjs',
  'scripts/fixtures/packed-identifier-source.mjs',
  'scripts/fixtures/identifier-installed-source.mjs',
  'scripts/fixtures/quoted-identifier-source-input.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/cte-value-table-receipts.mjs',
  'scripts/fixtures/retained-fixture-values.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
]);
