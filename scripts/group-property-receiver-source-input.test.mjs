import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {groupPropertyReceiverProgram, groupPropertyReceiverSuccesses,
  groupPropertyReceiverRefusals} from './fixtures/group-property-receiver-source-input.mjs';

test('receiver control preserves input filter, object projection and both independent grouping keys', () => {
  assert.deepEqual(JSON.parse(groupPropertyReceiverSuccesses[0].text), groupPropertyReceiverProgram);
  const [capture, main] = groupPropertyReceiverProgram.stages;
  assert.deepEqual(capture.steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(main.steps[2].derive.object_score, {property: {name: 'score', value: {field: 'payload'}}});
  assert.deepEqual(main.steps[3].group.by, ['score', 'object_score']);
  assert.deepEqual(groupPropertyReceiverSuccesses[1].expected,
    [{input_score: 10, object_score: 20, n: 2},
      {input_score: 10, object_score: 30, n: 1}, {input_score: 20, object_score: null, n: 1}]);
  assert.deepEqual(groupPropertyReceiverSuccesses[1].columns.map(column => column.name),
    ['input_score', 'object_score', 'n']);
  assert.deepEqual(groupPropertyReceiverSuccesses[1].columns.map(column => column.contract.nullable), [true, true, false]);
});

test('receiver cases distinguish scopes, computed subtrees, NULL, duplicates and empty schema', () => {
  const cases = new Map(groupPropertyReceiverSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('group-property-receiver-computed-both-keys').expected,
    [{input_score: 11, object_score: 21, n: 2},
      {input_score: 11, object_score: 31, n: 1}, {input_score: 21, object_score: null, n: 1}]);
  assert.deepEqual(cases.get('group-property-receiver-empty-typed-result').expected, []);
  assert.ok(groupPropertyReceiverRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(new Set([...groupPropertyReceiverSuccesses, ...groupPropertyReceiverRefusals]
    .map(item => item.name)).size, 12);
});

test('receiver source cases are copied and registered in normal and selected public cohorts', () => {
  const fixture = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...groupPropertyReceiverSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...groupPropertyReceiverRefusals)'));
  assert.ok(fixture.includes('groupByAllOnly ? {successes: [...groupByAllSuccesses, ...groupPropertyReceiverSuccesses]'));
  assert.ok(driver.includes("['scripts/fixtures/group-property-receiver-source-input.mjs', 'group-property-receiver-source-input.mjs']"));
});
