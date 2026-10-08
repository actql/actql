import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {minMaxDistinctProgram, minMaxDistinctSuccesses, minMaxDistinctRefusals}
  from './fixtures/min-max-distinct-source-input.mjs';

test('extrema fixtures distinguish duplicate-insensitivity from input deduplication', () => {
  const cases = new Map(minMaxDistinctSuccesses.map(item => [item.name, item]));
  const sql = cases.get('min-max-distinct-sql-duplicates-and-null');
  assert.deepEqual(sql.expected, [{low: 2, high: 4, total: 5, observed: 4}]);
  assert.deepEqual(sql.sourceRows.filter(row => row.id === 1), [{id: 1, amount: 1}, {id: 1, amount: 1}]);
  assert.deepEqual(cases.get('min-max-distinct-per-call-filter').expected, [{low: 4, high: 4, total: 5, observed: 4}]);
  assert.deepEqual(cases.get('min-max-distinct-typed-empty').expected,
    [{low: null, high: null, total: null, observed: 0}]);
  assert.deepEqual(cases.get('min-max-distinct-all-null').expected,
    [{low: null, high: null, total: null, observed: 1}]);
  assert.deepEqual(sql.columns.map(column => [column.name, column.contract.nullable]),
    [['low', true], ['high', true], ['total', true], ['observed', false]]);
  assert.deepEqual(minMaxDistinctProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(Object.values(minMaxDistinctProgram.stages[1].steps[0].group.aggregates).map(call => call.fn),
    ['min', 'max', 'sum', 'count']);
  assert.equal(minMaxDistinctSuccesses.length, 11);
  assert.equal(minMaxDistinctRefusals.length, 7);
  assert.equal(new Set([...minMaxDistinctSuccesses, ...minMaxDistinctRefusals].map(item => item.name)).size, 18);
});

test('grouped extrema are registered in the ordinary packed corpus and narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'minMaxDistinctSuccesses'], ['refusals', 'minMaxDistinctRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('minMaxDistinctOnly'));
  assert.ok(fixture.includes('minMaxDistinctOnly ? {successes: minMaxDistinctSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_MIN_MAX_DISTINCT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/min-max-distinct-source-input.mjs', 'min-max-distinct-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--min-max-distinct-only'"));
  assert.ok(driver.includes("if (process.argv.includes('--min-max-distinct-only')) return;"));
});
