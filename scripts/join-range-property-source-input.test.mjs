import assert from 'node:assert/strict';
import test from 'node:test';
import {joinPropertySuccesses, joinPropertyRefusals, joinRangeOrderProgram}
  from './fixtures/join-property-source-input.mjs';

const find = name => {
  const fixture = joinPropertySuccesses.find(item => item.name === 'join-property-range-' + name);
  assert.ok(fixture, name);
  return fixture;
};

test('range ordering preserves distinct independently authored input and output orders', () => {
  const input = find('order-qualified-input');
  const output = find('order-output-receiver');
  assert.deepEqual(input.expected.map(row => row.id), [2, 2, 1, 3]);
  assert.deepEqual(output.expected.map(row => row.id), [1, 3, 2, 2]);
  assert.deepEqual(input.columns.map(column => column.name), ['id', 'original_score', 'payload']);
  assert.equal(input.columns[1].contract.nullable, true);
  assert.equal(input.columns[2].contract.nullable, false);
  assert.deepEqual(find('independent-json').expected, input.expected);
  const steps = joinRangeOrderProgram.stages[0].steps;
  assert.equal(steps[2].join.max_output_rows, 12);
  assert.deepEqual(steps[2].join.on, [{left: 'id', right: 'id'}]);
  assert.deepEqual(steps[4].sort.map(term => term.field), ['original_score', 'peer_score']);
  assert.deepEqual(steps[5].select, ['id', 'original_score', {payload: 'other'}]);
});

test('same-named range and object fixtures have different values and nullability', () => {
  const object = find('value-range-collision');
  const range = find('dotted-range-collision-control');
  assert.deepEqual(object.expected.map(row => row.score), [20, 10, 10, null]);
  assert.deepEqual(range.expected.map(row => row.score), [90, 90, 90, 90]);
  assert.equal(object.columns[1].contract.nullable, true);
  assert.equal(range.columns[1].contract.nullable, false);
  assert.match(object.text, /SELECT payload\.id AS id, \(payload\.payload\)\.score AS score/u);
});

test('range fixtures retain duplicate, empty and left-extension obligations', () => {
  assert.deepEqual(find('typed-empty').expected, []);
  assert.deepEqual(find('left-null-extension').expected,
    [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: null}]);
  assert.equal(find('left-null-extension').columns[1].contract.nullable, true);
  assert.deepEqual(find('current-range-order').expected.map(row => row.id), [2, 2, 1, 3]);
  assert.deepEqual(find('ordinary-scoped-order').expected.map(row => row.id), [2, 1, 3]);
  const ordinary = find('ordinary-scoped-order');
  assert.doesNotMatch(ordinary.text, /others AS/u);
  assert.deepEqual(Object.keys(ordinary.parameterDeclarations), ['a', 'b', 'c']);
  assert.deepEqual(Object.keys(ordinary.parameters), ['a', 'b', 'c']);
  assert.equal(joinPropertySuccesses.length, 34);
});

test('missing members and displaced range fixtures retain exact pre-admission codes', () => {
  const refusals = joinPropertyRefusals.filter(item => item.name.startsWith('join-property-range-'));
  assert.equal(refusals.length, 4);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.match(refusals[3].text, /AS current \|> ORDER BY \(\(l\)\)\.payload\.score/u);
  assert.equal(joinPropertyRefusals.length, 15);
  const removed = joinPropertyRefusals.find(item => item.name === 'join-property-invalid-4');
  assert.match(removed.text, /SELECT DISTINCT l\.id .* ORDER BY payload\.score/u);
  assert.equal(removed.expectedCode, 'ClientProgramInvalidInput');
});
