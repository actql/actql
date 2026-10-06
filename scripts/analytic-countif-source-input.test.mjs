import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticCountifProgram, analyticCountifSuccesses, analyticCountifRefusals,
  analyticCountifExecutionFailures} from './fixtures/analytic-countif-source-input.mjs';

test('COUNTIF fixtures retain FALSE, NULL, duplicate occurrences and empty-frame zero', () => {
  const byName = new Map(analyticCountifSuccesses.map(item => [item.name, item]));
  const normal = byName.get('analytic-countif-sql-true-only');
  assert.deepEqual(normal.expected, [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 2},
    {id: 4, n: 1}, {id: 5, n: 1}, {id: 6, n: 0}]);
  assert.deepEqual(normal.columns, ['id', 'n'].map(name =>
    ({name, contract: {type: 'number', nullable: false}})));
  assert.deepEqual(byName.get('analytic-countif-typed-empty').columns, normal.columns);
  assert.deepEqual(byName.get('analytic-countif-typed-empty').expected, []);
  assert.deepEqual(byName.get('analytic-countif-pipe-following-empty-frame').expected.at(-1),
    {id: 6, n: 0});
  assert.deepEqual(byName.get('analytic-countif-partition-duplicates').expected[3], {id: 4, n: 2});
  const control = JSON.parse(byName.get('analytic-countif-independent-json').text);
  assert.deepEqual(control, analyticCountifProgram);
  assert.deepEqual(control.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(control.stages[1].steps[0].analytic.functions.n,
    {fn: 'count_if', expr: {gt: [{field: 'amount'}, {$param: 'threshold'}]}});
  assert.deepEqual(control.stages[1].steps[0].analytic.frame,
    {start: {preceding: 1}, end: {following: 1}});
  const cases = [...analyticCountifSuccesses, ...analyticCountifRefusals,
    ...analyticCountifExecutionFailures];
  assert.equal(new Set(cases.map(item => item.name)).size, cases.length);
});

test('ordinary packed corpus includes COUNTIF and narrow acceptance excludes unrelated campaigns', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'analyticCountifSuccesses'],
    ['refusals', 'analyticCountifRefusals'], ['executionFailures', 'analyticCountifExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  const scopes = fixture.match(/const scopeOnly = ([^;]+);/u)?.[1];
  assert.ok(scopes?.split(' || ').includes('analyticCountifOnly'));
  assert.ok(fixture.includes('analyticCountifOnly ? {successes: analyticCountifSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_COUNTIF_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-countif-source-input.mjs', 'analytic-countif-source-input.mjs']"));
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0];
  assert.ok(narrow.includes("'--analytic-countif-only'"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--analytic-countif-only'\).*?return;/su);
});
