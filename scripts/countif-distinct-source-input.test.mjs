import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {countifDistinctProgram, countifDistinctSuccesses, countifDistinctRefusals}
  from './fixtures/countif-distinct-source-input.mjs';

test('independent Boolean counts distinguish distinct TRUE from ordinary occurrence counts', () => {
  const cases = new Map(countifDistinctSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('countif-distinct-sql-duplicates-and-null').expected,
    [{unique_true: 1, every_true: 3, observed: 5, total: 3}]);
  assert.deepEqual(cases.get('countif-distinct-no-true').expected,
    [{unique_true: 0, every_true: 0, observed: 4, total: -2}]);
  assert.deepEqual(cases.get('countif-distinct-typed-empty').expected,
    [{unique_true: 0, every_true: 0, observed: 0, total: null}]);
  assert.deepEqual(cases.get('countif-distinct-all-null').expected,
    [{unique_true: 0, every_true: 0, observed: 1, total: null}]);
  assert.deepEqual(cases.get('countif-distinct-source-free').expected, [{one: 1, zero: 0, none: 0}]);
  assert.deepEqual(cases.get('countif-distinct-filter-demand').expected, [{n: 0}]);
  assert.deepEqual(countifDistinctProgram.stages[1].steps[0].group.aggregates.unique_true,
    {fn: 'count', expr: {if: [{gt: [{field: 'amount'}, {literal: 0}]}, {literal: true}, {literal: null}]}, distinct: true});
  assert.deepEqual(cases.get('countif-distinct-sql-duplicates-and-null').columns.map(column => [column.name, column.contract.nullable]),
    [['unique_true', false], ['every_true', false], ['observed', false], ['total', true]]);
  assert.equal(countifDistinctSuccesses.length, 12);
  assert.equal(countifDistinctRefusals.length, 8);
  assert.equal(new Set([...countifDistinctSuccesses, ...countifDistinctRefusals].map(item => item.name)).size, 20);
});

test('COUNTIF DISTINCT is included in ordinary and narrow public acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'countifDistinctSuccesses'], ['refusals', 'countifDistinctRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('countifDistinctOnly'));
  assert.ok(fixture.includes('countifDistinctOnly ? {successes: countifDistinctSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_COUNTIF_DISTINCT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/countif-distinct-source-input.mjs', 'countif-distinct-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--countif-distinct-only'"));
  assert.ok(driver.includes("if (process.argv.includes('--countif-distinct-only')) return;"));
});
