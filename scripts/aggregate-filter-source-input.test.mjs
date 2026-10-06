import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregateFilterProgram, aggregateFilterSuccesses, aggregateFilterRefusals, aggregateFilterExecutionFailures}
  from './fixtures/aggregate-filter-source-input.mjs';

test('aggregate filters keep independently authored contributors, NULLs and demand expectations', () => {
  const aggs = aggregateFilterProgram.stages[1].steps[0].group.aggregates;
  assert.deepEqual(aggs.positive.filter, {gt: [{field: 'amount'}, {literal: 0}]});
  assert.deepEqual(aggs.null_rows.filter, {is_null: {field: 'amount'}});
  assert.equal(aggs.all_rows.filter, undefined);
  assert.equal(aggs.total.distinct, true);
  const cases = new Map(aggregateFilterSuccesses.map(value => [value.name, value]));
  assert.deepEqual(cases.get('aggregate-filter-sql-independent-filters').expected,
    [{positive: 2, total: 2, null_rows: 1, all_rows: 4}]);
  assert.deepEqual(cases.get('aggregate-filter-empty-global').expected,
    [{positive: 0, total: null, null_rows: 0, all_rows: 0}]);
  assert.deepEqual(cases.get('aggregate-filter-skipped-argument').expected, [{n: 1, total: null}]);
  assert.deepEqual(cases.get('aggregate-filter-filtered-keyed-array').expected, [{ids: [1, 2]}]);
  assert.equal(aggregateFilterRefusals.length, 5);
  assert.equal(aggregateFilterExecutionFailures.length, 1);
});

test('aggregate WHERE cases participate in normal packed acceptance and an isolated selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'aggregateFilterSuccesses'], ['refusals', 'aggregateFilterRefusals'],
    ['executionFailures', 'aggregateFilterExecutionFailures']]) assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  assert.ok(fixture.includes('aggregateFilterOnly ? {successes: aggregateFilterSuccesses'));
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('aggregateFilterOnly'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_AGGREGATE_FILTER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/aggregate-filter-source-input.mjs', 'aggregate-filter-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--aggregate-filter-only'/u);
  assert.ok(driver.includes("process.argv.includes('--aggregate-filter-only')) return;"));
});
