import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticPartitionExpressionProgram as program,
  analyticPartitionExpressionSuccesses as successes,
  analyticPartitionExpressionRefusals as refusals,
  analyticPartitionExpressionExecutionFailures as failures}
  from './fixtures/analytic-partition-expression-source-input.mjs';

test('independent partition obligations distinguish NULL, alias, snapshot and demand', () => {
  const cases = new Map(successes.map(item => [item.name, item]));
  const get = suffix => cases.get('analytic-partition-expression-' + suffix);
  assert.deepEqual(get('sql-null-keys').expected.map(row => row.pos), [1, 2, 1, 1, 2, 2]);
  assert.deepEqual(get('case-key').expected.map(row => row.pos), [1, 2, 3, 1, 2, 4]);
  assert.notDeepEqual(get('case-key').expected, get('sql-null-keys').expected);
  assert.deepEqual(get('pipe-current-snapshot').expected.map(row => row.current), [1, 2, 1, 3, 4, 2]);
  assert.deepEqual(get('select-alias-collision').expected.map(row => row.pos), [1, 2, 1, 1, 2, 2]);
  assert.deepEqual(get('typed-empty').columns, get('sql-null-keys').columns);
  assert.deepEqual(get('typed-empty').expected, []);
  assert.deepEqual(JSON.parse(successes[0].text), program);
  assert.deepEqual(program.stages[1].steps[0], {from: 'records',
    derive: {partition: {gt: [{field: 'amount'}, {literal: 25}]}}});
  assert.equal(new Set([...successes, ...refusals, ...failures].map(item => item.name)).size,
    successes.length + refusals.length + failures.length);
  assert.equal(successes.length, 11);
  assert.equal(refusals.length, 8);
  assert.equal(failures.length, 1);
});

test('partition expressions enter the ordinary packed corpus and existing narrow driver', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'analyticPartitionExpressionSuccesses'],
    ['refusals', 'analyticPartitionExpressionRefusals'],
    ['executionFailures', 'analyticPartitionExpressionExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('analyticPartitionExpressionOnly ? {successes: analyticPartitionExpressionSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_PARTITION_EXPRESSION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-partition-expression-source-input.mjs', 'analytic-partition-expression-source-input.mjs']"));
});
