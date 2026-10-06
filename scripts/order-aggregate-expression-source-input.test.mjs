import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {orderAggregateExpressionProgram, orderAggregateExpressionSuccesses,
  orderAggregateExpressionRefusals, orderAggregateExpressionExecutionFailures}
  from './fixtures/order-aggregate-expression-source-input.mjs';

test('ordered aggregate expectations distinguish alias input, NULL and multiplicity', () => {
  const cases = new Map(orderAggregateExpressionSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('order-aggregate-expression-independent-json').text), orderAggregateExpressionProgram);
  assert.deepEqual(orderAggregateExpressionProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(cases.get('order-aggregate-expression-hidden-count-limit').expected,
    [{id: 1}, {id: 4}, {id: 2}]);
  assert.deepEqual(cases.get('order-aggregate-expression-alias-argument-collision').expected,
    [{id: -3, total: 6}, {id: -4, total: 4}, {id: -2, total: 2}, {id: -1, total: 2}]);
  assert.deepEqual(cases.get('order-aggregate-expression-qualified-argument-control').expected,
    [{id: -1, total: 2}, {id: -2, total: 2}, {id: -4, total: 4}, {id: -3, total: 6}]);
  assert.deepEqual(cases.get('order-aggregate-expression-distinct-selected-expression').expected,
    [{n: 3}, {n: 2}]);
  assert.deepEqual(cases.get('order-aggregate-expression-nullable-sort').expected,
    [{id: 4}, {id: 2}, {id: 3}, {id: 1}]);
  assert.deepEqual(cases.get('order-aggregate-expression-empty-global').expected, [{marker: 1}]);
});

test('ordered aggregate cases join normal packed acceptance and its narrow selection', async () => {
  const all = [...orderAggregateExpressionSuccesses, ...orderAggregateExpressionRefusals,
    ...orderAggregateExpressionExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'orderAggregateExpressionSuccesses'],
    ['refusals', 'orderAggregateExpressionRefusals'], ['executionFailures', 'orderAggregateExpressionExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.includes('orderAggregateExpressionOnly ? {successes: orderAggregateExpressionSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ORDER_AGGREGATE_EXPRESSION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/order-aggregate-expression-source-input.mjs', 'order-aggregate-expression-source-input.mjs']"));
  assert.ok(driver.includes("process.argv.includes('--order-aggregate-expression-only')"));
});
