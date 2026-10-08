import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {orderReceiverProgram, distinctOrderSuccesses, distinctOrderRefusals}
  from './fixtures/distinct-order-source-input.mjs';

test('receiver control projects once and deduplicates before sorting the public value', () => {
  const control = distinctOrderSuccesses.find(value => value.name === 'order-receiver-independent-json');
  assert.deepEqual(JSON.parse(control.text), orderReceiverProgram);
  assert.deepEqual(orderReceiverProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  const steps = orderReceiverProgram.stages[1].steps;
  assert.deepEqual(steps[2], {derive: {selected_score: {property: {name: 'score', value: {field: 'payload'}}}}});
  assert.deepEqual(steps.slice(3), [{select: [{score: 'selected_score'}]},
    {distinct: ['score']}, {sort: [{field: 'score', dir: 'asc', nulls: 'last'}], as: 'ordered'}]);
  assert.deepEqual(control.expected, [{score: 10}, {score: 20}, {score: null}]);
  assert.deepEqual(control.columns, [{name: 'score', contract: {type: 'number', nullable: true}}]);
  assert.equal(control.parameterDeclarations, undefined);
});

test('authored receiver obligations preserve duplicates, NULL, LIMIT and distinct scope refusals', () => {
  const cases = new Map(distinctOrderSuccesses.map(value => [value.name, value]));
  assert.deepEqual(cases.get('order-receiver-distinct-computed').expected,
    [{score: 11}, {score: 21}, {score: null}]);
  assert.deepEqual(cases.get('order-receiver-distinct-limited').expected,
    [{score: 20}, {score: null}]);
  assert.deepEqual(cases.get('order-receiver-distinct-empty').expected, []);
  assert.deepEqual(cases.get('order-receiver-ordinary-reuse').expected,
    [{score: 10}, {score: 20}, {score: 20}, {score: null}, {score: null}]);
  const newRefusals = distinctOrderRefusals.filter(value => value.name.startsWith('order-receiver-'));
  assert.equal(newRefusals.length, 4);
  assert.equal(distinctOrderRefusals.length, 10);
  assert.ok(distinctOrderRefusals.every(value => value.expectedCode === 'ClientProgramImplementationLimit'));
  assert.ok(newRefusals.every(value => value.expectedCode === 'ClientProgramImplementationLimit'));
  const newCases = distinctOrderSuccesses.filter(value => value.name.startsWith('order-receiver-'));
  assert.equal(newCases.length, 9);
  assert.ok(newCases.every(value => value.sourceReadSessionCount === 1));
  assert.equal(new Set([...distinctOrderSuccesses, ...distinctOrderRefusals].map(value => value.name)).size,
    distinctOrderSuccesses.length + distinctOrderRefusals.length);
});

test('receiver obligations retain the existing normal and selected packed routes', () => {
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(app.includes('scopeInputs.successes.push(...distinctOrderSuccesses)'));
  assert.ok(app.includes('scopeInputs.refusals.push(...distinctOrderRefusals)'));
  assert.ok(app.includes('distinctOrderOnly ? {successes: distinctOrderSuccesses, refusals: distinctOrderRefusals}'));
  assert.ok(driver.includes("['scripts/fixtures/distinct-order-source-input.mjs', 'distinct-order-source-input.mjs']"));
});
