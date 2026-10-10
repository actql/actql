import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setJoinProgram, setJoinSuccesses, setJoinRefusals} from './fixtures/set-join-source-input.mjs';

test('JOIN set controls preserve duplicate multiplication, NULL and exact arguments', () => {
  assert.equal(setJoinSuccesses.length, 13);
  assert.equal(setJoinRefusals.length, 6);
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

test('anonymous JOIN controls keep ordinal output NULL multiplicity and exact refusal reasons', () => {
  const cases = new Map(setJoinSuccesses.map(input => [input.name, input]));
  const control = cases.get('set-join-anonymous-json-control');
  assert.deepEqual(control.expected, [{id: 1, amount: 10}, {id: 4, amount: 20},
    {id: 4, amount: 20}, {id: 4, amount: 20}, {id: 4, amount: 20}, {id: 6, amount: null}]);
  for (const name of ['set-join-anonymous-named-control', 'set-join-anonymous-positional',
    'set-join-anonymous-cte-output']) {
    assert.deepEqual(cases.get(name).expected, control.expected);
    assert.deepEqual(cases.get(name).columns, control.columns);
    assert.equal(cases.get(name).sourceReadSessionCount, 1);
  }
  assert.deepEqual(cases.get('set-join-anonymous-typed-empty').expected, []);
  const program = JSON.parse(control.text);
  assert.equal(program.stages[1].steps[3].join.max_output_rows, 10);
  assert.deepEqual(program.stages[1].steps[3].join.on, [{left: 'id', right: 'id'}]);
  assert.deepEqual(program.stages[1].steps[4].derive.id,
    {add: [{field: 'left_id'}, {field: 'right_id'}]});
  assert.equal(setJoinRefusals.find(input => input.name.endsWith('anonymous-by-name')).expectedCode,
    'ClientProgramImplementationLimit');
  assert.equal(setJoinRefusals.find(input => input.name.endsWith('anonymous-private-field')).expectedCode,
    'ClientProgramInvalidInput');
});
