import assert from 'node:assert/strict';
import test from 'node:test';
import {limitParameterProgram, limitParameterSuccesses, limitParameterRefusals}
  from './fixtures/limit-parameter-source-input.mjs';

test('LIMIT fixture binds different take roles in an independent Program', () => {
  assert.deepEqual(limitParameterProgram.stages[1].steps[2].take,
    {count: {$param: 'count'}, offset: {$param: 'skip'}});
  assert.deepEqual(limitParameterSuccesses[1].expected,
    [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.deepEqual(limitParameterSuccesses[2].parameters, {count: 1, skip: 2});
  assert.deepEqual(limitParameterSuccesses[2].expected, [{amount: 30, id: 3}]);
});
test('LIMIT fixture keeps NULL duplicates column order and empty schemas', () => {
  const item = limitParameterSuccesses.find(item => item.name.endsWith('zero-offset-null-and-duplicates'));
  assert.deepEqual(item.expected, [{amount: null, id: 1}, {amount: 20, id: 2},
    {amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(item.columns.map(column => column.name), ['amount', 'id']);
  assert.equal(item.columns[0].contract.nullable, true);
  assert.deepEqual(limitParameterSuccesses.find(item => item.name.endsWith('typed-empty')).expected, []);
});
test('LIMIT public cases have distinct names and ordinary refusal inputs', () => {
  const cases = [...limitParameterSuccesses, ...limitParameterRefusals];
  assert.equal(new Set(cases.map(item => item.name)).size, cases.length);
  assert.equal(limitParameterSuccesses.length, 11);
  assert.equal(limitParameterRefusals.length, 11);
  assert.ok(limitParameterRefusals.some(item => item.parameters?.count === 0));
  assert.ok(limitParameterRefusals.some(item => item.parameters?.skip === null));
});
