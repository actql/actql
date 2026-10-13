// Test-only payload. Product files are exclusively the normal fixed RC.
export {releaseVectorScalarEnvironment as releaseSourceRankingEnvironment}
  from './release-vector-scalar-fixtures.mjs';
export const releaseSourceRankingFixturePaths = Object.freeze([
  'scripts/fixtures/release-source-ranking-worker.mjs',
  'scripts/fixtures/packed-source-ranking.mjs',
  'scripts/fixtures/source-ranking-installed-source.mjs',
  'scripts/fixtures/source-ranking-public-input.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/cte-value-table-receipts.mjs',
  'scripts/fixtures/retained-fixture-values.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
]);
