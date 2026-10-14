// Test-only delivery; product files come only from the normal release archives.
export {releaseVectorScalarEnvironment as releaseCompositeVectorEnvironment}
  from './release-vector-scalar-fixtures.mjs';
export const releaseCompositeVectorFixturePaths = Object.freeze([
  'scripts/fixtures/release-composite-vector-worker.mjs',
  'scripts/fixtures/packed-composite-vector.mjs',
  'scripts/fixtures/composite-vector-installed-source.mjs',
  'scripts/fixtures/composite-vector-source-input.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/cte-value-table-receipts.mjs',
  'scripts/fixtures/retained-fixture-values.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
]);
