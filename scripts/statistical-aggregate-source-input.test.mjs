import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {statisticalAggregateProgram, statisticalAggregateSuccesses, statisticalAggregateRefusals, statisticalAggregateExecutionFailures} from './fixtures/statistical-aggregate-source-input.mjs';

test('independent statistics retain NULL, duplicate occurrences and sample cardinality', () => {
  const byName = new Map(statisticalAggregateSuccesses.map(x => [x.name, x]));
  assert.deepEqual(byName.get('statistical-aggregate-sql-null-exclusion').expected, [{population: 1, sample: 2, population_sd: 1, sample_sd: Math.SQRT2}]);
  assert.deepEqual(byName.get('statistical-aggregate-singleton').expected, [{population: 0, sample: null, population_sd: 0, sample_sd: null}]);
  assert.equal(byName.get('statistical-aggregate-empty-typed').columns.length, 4);
  assert.ok(byName.get('statistical-aggregate-empty-typed').columns.every(x => x.contract.type === 'number' && x.contract.nullable));
  assert.deepEqual(JSON.parse(byName.get('statistical-aggregate-independent-json').text), statisticalAggregateProgram);
  assert.deepEqual(statisticalAggregateProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(Object.values(statisticalAggregateProgram.stages[1].steps[0].group.aggregates).map(x => x.fn), ['var_pop', 'var_samp', 'stddev_pop', 'stddev_samp']);
  const cases = [...statisticalAggregateSuccesses, ...statisticalAggregateRefusals, ...statisticalAggregateExecutionFailures];
  assert.equal(new Set(cases.map(x => x.name)).size, cases.length);
});

test('ordinary packed corpus includes statistical aggregates and narrow acceptance excludes unrelated campaigns', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'statisticalAggregateSuccesses'],
    ['refusals', 'statisticalAggregateRefusals'], ['executionFailures', 'statisticalAggregateExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  const scopes = fixture.match(/const scopeOnly = ([^;]+);/u)?.[1];
  assert.ok(scopes?.split(' || ').includes('statisticalAggregateOnly'));
  assert.ok(fixture.includes('statisticalAggregateOnly ? {successes: statisticalAggregateSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_STATISTICAL_AGGREGATE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/statistical-aggregate-source-input.mjs', 'statistical-aggregate-source-input.mjs']"));
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0];
  assert.ok(narrow.includes("'--statistical-aggregate-only'"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--statistical-aggregate-only'\).*?return;/su);
});
