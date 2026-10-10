import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {distinctOrderMemberProgram, distinctOrderMemberSuccesses, distinctOrderMemberRefusals, distinctOrderMemberOwnerCases, distinctOrderMemberOwnerProgram}
  from './fixtures/distinct-order-member-source-input.mjs';

test('independent member control derives before DISTINCT and sorts only its evaluated output', () => {
  const control = distinctOrderMemberSuccesses[0];
  assert.deepEqual(JSON.parse(control.text), distinctOrderMemberProgram);
  assert.deepEqual(distinctOrderMemberProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(distinctOrderMemberProgram.stages[1].steps.slice(2), [
    {derive: {selected_score: {property: {name: 'score', value: {field: 'payload'}}}}},
    {select: [{score: 'selected_score'}]}, {distinct: ['score']},
    {derive: {order_only: {negate: {field: 'score'}}}},
    {sort: [{field: 'order_only', dir: 'asc', nulls: 'last'}]},
    {select: ['score'], as: 'ordered'},
  ]);
  assert.deepEqual(control.expected, [{score: 20}, {score: 10}, {score: null}]);
  assert.deepEqual(control.columns, [{name: 'score', contract: {type: 'number', nullable: true}}]);
});

test('receiver collisions reverse the expected order and NULL and multiplicity remain explicit', () => {
  const cases = new Map([...distinctOrderMemberSuccesses, ...distinctOrderMemberOwnerCases].map(value => [value.name, value]));
  const output = cases.get('distinct-order-member-output-receiver');
  const input = cases.get('distinct-order-member-input-receiver');
  assert.deepEqual(output.expected, [{original_score: 10, payload: {score: 20}},
    {original_score: 20, payload: {score: 10}}, {original_score: null, payload: {score: 10}}]);
  assert.deepEqual(input.expected, [output.expected[1], output.expected[0], output.expected[2]]);
  assert.deepEqual(output.columns, [{name: 'original_score', contract: {type: 'number', nullable: true}},
    {name: 'payload', contract: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: true}}}}]);
  assert.deepEqual(cases.get('distinct-order-member-limited').expected, [{score: 10}, {score: null}]);
  assert.deepEqual(cases.get('distinct-order-member-empty').expected, []);
  assert.equal(distinctOrderMemberSuccesses.length, 7);
  assert.equal(distinctOrderMemberOwnerCases.length, 2);
  assert.deepEqual(distinctOrderMemberOwnerProgram.stages[1].steps[4], {distinct: ['original_score', 'payload']});
  assert.deepEqual(distinctOrderMemberOwnerProgram.stages[1].results.rows.fields, ['original_score', 'payload']);
  assert.equal(distinctOrderMemberRefusals.length, 5);
  assert.ok(distinctOrderMemberRefusals.every(value => value.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(distinctOrderMemberSuccesses.every(value => value.sourceReadSessionCount === 1));
});

test('member fixtures reach the existing selected and normal packed entrances', () => {
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(app.includes('scopeInputs.successes.push(...distinctOrderMemberSuccesses)'));
  assert.ok(app.includes('scopeInputs.refusals.push(...distinctOrderMemberRefusals)'));
  assert.ok(app.includes('successes: [...distinctOrderSuccesses, ...distinctOrderMemberSuccesses]'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/distinct-order-member-source-input.mjs', 'distinct-order-member-source-input.mjs']"));
});
