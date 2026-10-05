import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {havingAggregateProgram, havingSingleJoinProgram, havingPropertyOrderProgram, havingAggregateSuccesses, havingAggregateRefusals,
  havingAggregateExecutionFailures} from './fixtures/having-aggregate-source-input.mjs';

test('HAVING fixtures distinguish input multiplicity, NULL and pre-group alias values', () => {
  const cases = new Map(havingAggregateSuccesses.map(item => [item.name, item]));
  const hidden = cases.get('having-aggregate-hidden-count-star');
  assert.deepEqual(hidden.expected, [{id: 1}, {id: 3}]);
  assert.deepEqual(cases.get('having-aggregate-alias-input-collision').expected,
    [{id: -3, total: 6}]);
  assert.deepEqual(cases.get('having-aggregate-qualified-input-control').expected, []);
  assert.deepEqual(cases.get('having-aggregate-null-and-distinct').expected, [{id: 2}, {id: 3}]);
  assert.deepEqual(cases.get('having-aggregate-empty-grouped').columns, hidden.columns);
  assert.deepEqual(cases.get('having-aggregate-empty-global').expected, [{n: 0}]);
  assert.deepEqual(cases.get('having-aggregate-scoped-cte-join-chain').expected,
    [{id: 1, n: 2}]);
  const gap = havingAggregateRefusals.find(item => item.knownImplementationGap);
  assert.deepEqual(gap.intendedExpected, [{id: 1, n: 2}]);
  assert.match(gap.text, /HAVING COUNT\(\*\) > 1/u);
  assert.deepEqual(JSON.parse(cases.get('having-aggregate-single-join-json-control').text),
    havingSingleJoinProgram);
  assert.equal(havingSingleJoinProgram.stages[2].steps[0].join.max_output_rows, 10);
  assert.deepEqual(havingSingleJoinProgram.stages[2].steps[1].group,
    {by: ['id'], aggregates: {n: {fn: 'count'}}});
  const control = JSON.parse(cases.get('having-aggregate-independent-json').text);
  assert.deepEqual(control, havingAggregateProgram);
  assert.deepEqual(control.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(control.stages[1].steps[0].group,
    {by: ['id'], aggregates: {cardinality: {fn: 'count'}}});
  assert.deepEqual(control.stages[1].steps[2], {select: ['id']});
});

test('HAVING aggregate cases join the ordinary packed corpus and a focused selection', async () => {
  const all = [...havingAggregateSuccesses, ...havingAggregateRefusals,
    ...havingAggregateExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'havingAggregateSuccesses'],
    ['refusals', 'havingAggregateRefusals'], ['executionFailures', 'havingAggregateExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.includes('havingAggregateOnly ? {successes: havingAggregateSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_HAVING_AGGREGATE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/having-aggregate-source-input.mjs', 'having-aggregate-source-input.mjs']"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--having-aggregate-only'\).*?return;/su);
});

test('hidden property order distinguishes HAVING aliases from selected input slots', () => {
  const cases = new Map(havingAggregateSuccesses.map(item => [item.name, item]));
  const alias = cases.get('having-aggregate-property-alias-input-collision');
  assert.deepEqual(alias.expected, [{n: 5, payload: {score: 5}, original: 'b|b|a|c'}]);
  assert.deepEqual(cases.get('having-aggregate-property-qualified-input-control').expected, []);
  assert.deepEqual(alias.parameters.o1, {score: 5});
  assert.equal(alias.parameters.p3, null);
  assert.equal(alias.parameters.p4.score, null);
  assert.deepEqual(JSON.parse(cases.get('having-aggregate-property-independent-json').text), havingPropertyOrderProgram);
  assert.deepEqual(havingPropertyOrderProgram.stages[1].steps[3].group.aggregates.n, {fn: 'count'});
  assert.deepEqual(havingPropertyOrderProgram.stages[1].steps[4].filter,
    {eq: [{field: 'hidden'}, {literal: 'b|b|a|c'}]});
  assert.deepEqual(havingPropertyOrderProgram.stages[1].steps[5], {select: ['n'], as: 'out'});
  assert.deepEqual(havingPropertyOrderProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
});
