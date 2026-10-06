import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctJoinOrderSuccesses as successes, distinctJoinOrderRefusals as refusals,
  distinctJoinOrderExecutionFailures as failures} from './fixtures/distinct-join-order-source-input.mjs';

test('DISTINCT JOIN fixtures distinguish alias and input meanings independently', () => {
  assert.deepEqual(successes.find(x => x.name.endsWith('sql-alias-collision')).expected,
    [{amount: null}, {amount: -1}, {amount: -2}]);
  assert.deepEqual(successes.find(x => x.name.endsWith('selected-qualified-input')).expected,
    [{score: 1}, {score: 2}, {score: null}]);
  const program = JSON.parse(successes[0].text);
  const steps = program.stages[1].steps;
  assert.deepEqual(steps[3], {distinct: ['amount']});
  assert.deepEqual(steps[4], {derive: {sort_only: {negate: {field: 'amount'}}}});
  assert.deepEqual(program.stages[1].inputs.l, program.stages[1].inputs.r);
  const empty = successes.find(x => x.name.endsWith('typed-empty'));
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, [{name: 'amount', contract: {type: 'number', nullable: true}}]);
  assert.equal(successes.length, 7);
  assert.equal(refusals.length, 3);
  assert.equal(failures.length, 1);
});

test('DISTINCT JOIN corpus participates exactly once in normal public acceptance', async () => {
  const text = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const group of ['Successes', 'Refusals', 'ExecutionFailures']) {
    assert.equal(text.split(`.push(...distinctJoinOrder${group});`).length - 1, 1);
  }
  const harness = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(harness.includes("runtimeEnvironment.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY = '1'"));
  assert.ok(harness.includes("['scripts/fixtures/distinct-join-order-source-input.mjs', 'distinct-join-order-source-input.mjs']"));
});
