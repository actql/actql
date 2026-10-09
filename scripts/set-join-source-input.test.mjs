import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setJoinProgram, setJoinSuccesses, setJoinRefusals} from './fixtures/set-join-source-input.mjs';

test('JOIN set controls preserve duplicate multiplication, NULL and exact arguments', () => {
  assert.equal(setJoinSuccesses.length, 8);
  assert.equal(setJoinRefusals.length, 4);
  assert.deepEqual(setJoinSuccesses[1].expected, [{id: 1, amount: 10},
    {id: 2, amount: 20}, {id: 2, amount: 20}, {id: 2, amount: 20},
    {id: 2, amount: 20}, {id: 3, amount: null}]);
  assert.deepEqual(setJoinProgram.stages[1].steps[0].filter, {eq: [{field: 'id'}, {literal: 1}]});
  assert.deepEqual(setJoinProgram.stages[1].steps[2].filter, {gte: [{field: 'id'}, {literal: 2}]});
  for (const i of [1, 3]) assert.equal(setJoinProgram.stages[1].steps[i].join.max_output_rows, 10);
  assert.deepEqual(setJoinSuccesses[6].parameters, {count: 2, offset: 1});
  assert.deepEqual(setJoinSuccesses[5].expected, []);
  assert.deepEqual(setJoinSuccesses[1].columns.map(x => x.name), ['id', 'amount']);
  assert.equal(setJoinSuccesses[1].columns[1].contract.nullable, true);
});

test('JOIN sets use the existing normal and focused public consumer', () => {
  const consumer = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...setCorrespondingSuccesses, ...setJoinSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...setCorrespondingRefusals, ...setJoinRefusals)'));
  assert.ok(driver.includes("['scripts/fixtures/set-join-source-input.mjs', 'set-join-source-input.mjs']"));
});
