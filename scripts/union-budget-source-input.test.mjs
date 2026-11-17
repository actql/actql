import assert from 'node:assert/strict';
import test from 'node:test';
import {unionBudgetCases} from './fixtures/union-budget-source-input.mjs';
import {validatePackedPublicQueryArguments} from './packed-public-query-options.mjs';

test('normal UNION inventory retains both exact authored shapes at every boundary', () => {
  assert.deepEqual(unionBudgetCases.map(item => item.name),
    ['direct-10', 'cte-10', 'direct-11', 'cte-11', 'direct-24', 'cte-24',
      'direct-25', 'cte-25', 'direct-40', 'cte-40']);
  for (const fixture of unionBudgetCases) {
    assert.equal(fixture.format, 'sql');
    assert.equal(fixture.text.split(' UNION ALL ').length, fixture.branches);
    assert.equal(fixture.text.startsWith('WITH all_rows AS ('), fixture.cte);
    if (!fixture.cte) assert(fixture.text.startsWith('SELECT 0 AS n UNION ALL SELECT 1 AS n'));
  }
});

test('independent complete rows preserve duplicates and nonnullable Number schema', () => {
  const expected = {10: [4, 3, 3], 11: [4, 4, 3], 24: [8, 8, 8],
    25: [9, 8, 8], 40: [14, 13, 13]};
  for (const fixture of unionBudgetCases) {
    assert.equal(fixture.expected.length, fixture.branches);
    assert.deepEqual([0, 1, 2].map(n => fixture.expected.filter(row => row.n === n).length),
      expected[fixture.branches]);
    assert(fixture.expected.every(row => Object.keys(row).join() === 'n'));
    assert.deepEqual(fixture.columns, [{name: 'n', contract: {type: 'number', nullable: false}}]);
  }
});

test('finite packed selector cannot broaden to another campaign or narrow CI', () => {
  assert.doesNotThrow(() => validatePackedPublicQueryArguments(['--union-budget-only'], {}));
  assert.doesNotThrow(() => validatePackedPublicQueryArguments(['--union-budget-only', '--keep-artifacts'], {}));
  assert.throws(() => validatePackedPublicQueryArguments(['--union-budget-onyl'], {}), /UnknownPackedPublicQueryArgument/);
  assert.throws(() => validatePackedPublicQueryArguments(['--union-budget-only', '--ci-part=portable-1'], {}));
  assert.throws(() => validatePackedPublicQueryArguments(['--union-budget-only', '--source-free-only'], {}));
  assert.throws(() => validatePackedPublicQueryArguments(['--union-budget-only'], {ACTQL_TEST_SOURCE_FREE_ONLY: '1'}));
});
