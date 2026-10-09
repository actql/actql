import assert from 'node:assert/strict';
import test from 'node:test';
import {limitParameterProgram, joinLimitTailProgram, limitParameterSuccesses, limitParameterRefusals}
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
  assert.equal(limitParameterSuccesses.length, 21);
  assert.equal(limitParameterRefusals.length, 16);
  assert.ok(limitParameterRefusals.some(item => item.parameters?.count === 0));
  assert.ok(limitParameterRefusals.some(item => item.parameters?.skip === null));
});

test('source parameter lookup does not rewrite machine declaration or value keys', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const quoted = cases.get('limit-parameter-quoted-parameter-names');
  assert.ok(quoted.text.includes('@`COUNT`'));
  assert.ok(quoted.text.includes('@`\\x53kip`'));
  const exact = cases.get('limit-parameter-exact-declaration-spelling');
  assert.deepEqual(Object.keys(exact.parameterDeclarations), ['COUNT', 'SKIP']);
  assert.deepEqual(exact.parameters, {COUNT: 2, SKIP: 1});
  assert.deepEqual(exact.expected, [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.ok(limitParameterRefusals.some(item => item.name.endsWith('wrong-machine-value-case')));
});


test('JOIN continuation retains both take operand pairs and independent multiplicity', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const control = cases.get('limit-parameter-join-tail-independent-json');
  assert.deepEqual(JSON.parse(control.text), joinLimitTailProgram);
  assert.deepEqual(joinLimitTailProgram.stages[1].steps[3].take,
    {count: {$param: 'first_count'}, offset: {$param: 'first_skip'}});
  assert.deepEqual(joinLimitTailProgram.stages[1].steps[4].take,
    {count: {$param: 'count'}, offset: {$param: 'skip'}});
  assert.equal(joinLimitTailProgram.stages[1].steps[1].join.max_output_rows, 10);
  assert.deepEqual(control.expected, [{amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(cases.get('limit-parameter-join-tail-pipe').expected, control.expected);
  assert.deepEqual(cases.get('limit-parameter-join-tail-pipe').columns, control.columns);
  assert.deepEqual(cases.get('limit-parameter-join-tail-empty').expected, []);
  assert.deepEqual(cases.get('limit-parameter-join-tail-where-projection').columns.map(column => column.name), ['id', 'amount']);
  assert.deepEqual(cases.get('limit-parameter-join-tail-different-operands').expected, [{amount: null, id: 1}]);
  assert.ok(limitParameterRefusals.some(item => item.parameters?.first_count === 0));
  assert.ok(limitParameterRefusals.some(item => item.name.endsWith('join-tail-removed-input-range')));
  assert.ok(limitParameterRefusals.filter(item => item.name.includes('join-tail-'))
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});
