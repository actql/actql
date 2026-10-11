import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {positiveLimitSuccesses, positiveLimitRefusals}
  from './fixtures/positive-limit-source-input.mjs';
import {limitParameterProgram} from './fixtures/limit-parameter-source-input.mjs';

test('positive take fixtures retain independent rows, column order and parameters', () => {
  assert.equal(positiveLimitSuccesses.length, 7);
  const cases = new Map(positiveLimitSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('positive-limit-independent-json').text), limitParameterProgram);
  assert.deepEqual(limitParameterProgram.stages[1].steps[2].take,
    {count: {$param: 'count'}, offset: {$param: 'skip'}});
  const literal = cases.get('positive-limit-literal-operands');
  assert.equal(literal.text, 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT +((2)) OFFSET (++1)');
  assert.deepEqual(literal.expected, [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.deepEqual(literal.columns, [
    {name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'id', contract: {type: 'number', nullable: false}},
  ]);
  assert.deepEqual(cases.get('positive-limit-zero-offset-null-and-duplicates').expected,
    [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(cases.get('positive-limit-pipe-mixed').parameters, {skip: 2});
  assert.deepEqual(cases.get('positive-limit-pipe-mixed').expected, [{amount: 30, id: 3}]);
  assert.deepEqual(cases.get('positive-limit-typed-empty').expected, []);
  assert.ok(positiveLimitSuccesses.every(item => item.sourceReadSessionCount === 1));
  assert.equal(positiveLimitRefusals.length, 6);
  assert.ok(positiveLimitRefusals.some(item => item.parameters.count === null));
});

test('positive take selection is also present in the ordinary public registration', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...positiveLimitSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...positiveLimitRefusals)'));
  assert.ok(packed.includes('positiveLimitOnly ? {successes: positiveLimitSuccesses, refusals: positiveLimitRefusals}'));
  assert.ok(driver.includes('--positive-limit-only'));
  assert.ok(driver.includes('ACTQL_TEST_POSITIVE_LIMIT_ONLY'));
});
