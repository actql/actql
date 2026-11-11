import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {checkedRequestProgramPreparation} from '../adapters/host-node/client-program-preparation.mjs';
import {statisticalAggregateProgram, statisticalAliasProgram, statisticalAggregateSuccesses, statisticalAggregateRefusals, statisticalAggregateExecutionFailures} from './fixtures/statistical-aggregate-source-input.mjs';

test('default analytic frames retain the explicit implementation-limit refusal', () => {
  const text = 'SELECT VAR_POP(amount) OVER (ORDER BY id) AS v FROM records';
  const defaultFrame = statisticalAggregateRefusals.filter(x => x.text === text);
  assert.equal(defaultFrame.length, 1);
  assert.equal(defaultFrame[0].expectedCode, 'ClientProgramImplementationLimit');
  assert.deepEqual(statisticalAggregateRefusals.filter(x => x.expectedCode !== undefined)
    .map(x => [x.text, x.expectedCode]), [
    [text, 'ClientProgramImplementationLimit'],
    ['SELECT DISTINCT VARIANCE(amount) AS v FROM records ORDER BY VAR_POP(amount)', 'ClientProgramInvalidInput'],
    ['SELECT DISTINCT VARIANCE(amount) AS v FROM records ORDER BY VAR_SAMP(amount + 1)', 'ClientProgramInvalidInput'],
  ]);
  assert.ok(statisticalAggregateRefusals.some(x =>
    x.text === 'SELECT VAR_SAMP(DISTINCT amount) AS v FROM records' &&
    x.expectedCode === undefined));
  assert.equal(statisticalAggregateRefusals.length, 10);
  assert.equal(statisticalAggregateSuccesses.length, 20);
  assert.equal(statisticalAggregateExecutionFailures.length, 1);
  assert.deepEqual(statisticalAggregateSuccesses.find(x =>
    x.name === 'statistical-aggregate-analytic-prefix').expected,
  [{id: 1, v: null}, {id: 2, v: 0}, {id: 3, v: 1}]);
});

test('unselected DISTINCT statistical ordering retains the original invalid-input projection', () => {
  for (const index of [8, 9]) {
    const fixture = statisticalAggregateRefusals[index];
    assert.equal(fixture.name, 'statistical-aggregate-refuse-' + index);
    const issue = {original:fixture.text}, result = {$tag:0, _0:issue};
    let projections = 0;
    const moon = {clientProgramRequestPreparationIssueCode(original) {
      assert.equal(this, moon); assert.equal(original, result); projections++;
      return 'source_invalid_input';
    }};
    assert.throws(() => checkedRequestProgramPreparation(moon, result), error =>
      error.code === fixture.expectedCode && error.cause === issue);
    assert.equal(projections, 1);
  }
});

test('statistical aliases retain one group result through DISTINCT and ordered publication', () => {
  const cases = new Map(statisticalAggregateSuccesses.map(x => [x.name, x]));
  const json = cases.get('statistical-aggregate-alias-independent-json');
  assert.deepEqual(JSON.parse(json.text), statisticalAliasProgram);
  assert.deepEqual(json.expected, [{v: 2}, {v: 8}, {v: null}]);
  assert.deepEqual(statisticalAliasProgram.stages[1].steps, [
    {from: 'records', group: {by: ['id'], aggregates: {v: {fn: 'var_samp', field: 'amount'}}}},
    {select: ['v']}, {distinct: ['v']},
    {sort: [{field: 'v', dir: 'asc', nulls: 'last'}], as: 'statistics'},
  ]);
  for (const name of ['variance-order-sample', 'sample-order-variance', 'quoted-variance-order-sample']) {
    const item = cases.get('statistical-aggregate-' + name);
    assert.deepEqual(item.expected, json.expected);
    assert.deepEqual(item.columns, [{name: 'v', contract: {type: 'number', nullable: true}}]);
    assert.equal(item.sourceReadSessionCount, 1);
    assert.deepEqual(item.sourceRows, json.sourceRows);
  }
  assert.ok(statisticalAggregateRefusals.some(x => x.text.endsWith('ORDER BY VAR_POP(amount)')));
  assert.ok(statisticalAggregateRefusals.some(x => x.text.endsWith('ORDER BY VAR_SAMP(amount + 1)')));
});

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
