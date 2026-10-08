import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticStringAggProgram, analyticStringAggSuccesses, analyticStringAggRefusals,
  analyticStringAggExecutionFailures} from './fixtures/analytic-string-agg-source-input.mjs';

test('analytic STRING_AGG obligations preserve NULLs, duplicates and empty-frame NULL', () => {
  const cases = new Map(analyticStringAggSuccesses.map(item => [item.name, item]));
  const prefix = cases.get('analytic-string-agg-sql-prefix-null-duplicates');
  assert.deepEqual(prefix.expected, [{id: 1, names: null}, {id: 2, names: 'b'},
    {id: 3, names: 'b|a'}, {id: 4, names: 'b|a|b'}, {id: 5, names: 'b|a|b'}]);
  assert.deepEqual(prefix.columns, [{name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'names', contract: {type: 'string', nullable: true}}]);
  const empty = cases.get('analytic-string-agg-typed-empty');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, prefix.columns);
  assert.deepEqual(cases.get('analytic-string-agg-pipe-following-empty-frame').expected.slice(-2),
    [{id: 4, names: null}, {id: 5, names: null}]);
  assert.deepEqual(cases.get('analytic-string-agg-partition-duplicate-values').expected[3],
    {id: 4, names: 'b|b'});
  const control = JSON.parse(cases.get('analytic-string-agg-independent-json').text);
  assert.deepEqual(control, analyticStringAggProgram);
  const aggregate = control.stages[1].steps[0].analytic.functions.names;
  assert.equal(aggregate.fn, 'string_agg');
  assert.equal(aggregate.max_bytes, 65536);
  assert.equal(aggregate.delimiter, '|');
  assert.equal(Object.hasOwn(aggregate, 'order_by'), false);
  assert.deepEqual(control.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  const all = [...analyticStringAggSuccesses, ...analyticStringAggRefusals,
    ...analyticStringAggExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('ordinary and selected packed acceptance share the STRING_AGG obligations', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'analyticStringAggSuccesses'],
    ['refusals', 'analyticStringAggRefusals'], ['executionFailures', 'analyticStringAggExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('analyticStringAggOnly'));
  assert.ok(fixture.includes('analyticStringAggOnly ? {successes: analyticStringAggSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_STRING_AGG_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-string-agg-source-input.mjs', 'analytic-string-agg-source-input.mjs']"));
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0];
  assert.ok(narrow.includes("'--analytic-string-agg-only'"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--analytic-string-agg-only'\).*?return;/su);
});
