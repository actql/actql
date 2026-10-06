import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {selectAggregateExpressionProgram, selectAggregateExpressionSuccesses,
  selectAggregateExpressionRefusals, selectAggregateExpressionExecutionFailures}
  from './fixtures/select-aggregate-expression-source-input.mjs';

test('selected aggregate expectations retain multiplicity, NULL and input scope', () => {
  const cases = new Map(selectAggregateExpressionSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('select-aggregate-expression-independent-json').text), selectAggregateExpressionProgram);
  assert.deepEqual(selectAggregateExpressionProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(cases.get('select-aggregate-expression-repeated-distinct-limit').expected,
    [{id: 3, n: 2, next: 3, doubled: 2}, {id: 2, n: 1, next: 2, doubled: 2}, {id: 1, n: 2, next: 3, doubled: 0}]);
  assert.deepEqual(cases.get('select-aggregate-expression-alias-input-collision').expected,
    [{id: -4, total: 8}, {id: -3, total: 12}]);
  assert.deepEqual(cases.get('select-aggregate-expression-empty-global').expected, [{next: 1, total: null}]);
  assert.deepEqual(cases.get('select-aggregate-expression-empty-global').columns,
    [{name: 'next', contract: {type: 'number', nullable: false}}, {name: 'total', contract: {type: 'number', nullable: true}}]);
  assert.equal(cases.get('select-aggregate-expression-source-free').sourceReadSessionCount, 0);
});

test('selected aggregate inputs join the normal packed corpus and narrow selection', async () => {
  const all = [...selectAggregateExpressionSuccesses, ...selectAggregateExpressionRefusals,
    ...selectAggregateExpressionExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'selectAggregateExpressionSuccesses'],
    ['refusals', 'selectAggregateExpressionRefusals'], ['executionFailures', 'selectAggregateExpressionExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.includes('selectAggregateExpressionOnly ? {successes: selectAggregateExpressionSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SELECT_AGGREGATE_EXPRESSION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/select-aggregate-expression-source-input.mjs', 'select-aggregate-expression-source-input.mjs']"));
  assert.ok(driver.includes("process.argv.includes('--select-aggregate-expression-only')"));
});
