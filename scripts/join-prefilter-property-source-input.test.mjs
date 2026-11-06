import assert from 'node:assert/strict';
import test from 'node:test';
import {joinPropertySuccesses, joinPropertyRefusals, joinPrefilterPropertyProgram}
  from './fixtures/join-property-source-input.mjs';

const find = name => {
  const fixture = joinPropertySuccesses.find(item => item.name === 'join-property-prefilter-' + name);
  assert.ok(fixture, name);
  return fixture;
};

test('prefilter has an independent ordinary filter-before-JOIN control', () => {
  const steps = joinPrefilterPropertyProgram.stages[0].steps;
  assert.deepEqual(steps[2].filter, {gt: [
    {property: {value: {field: 'payload'}, name: 'score'}}, {literal: 15}]});
  assert.equal(steps[3].from, 'filtered');
  assert.equal(steps[3].join.max_output_rows, 1);
  assert.deepEqual(steps[3].join.on, [{left: 'id', right: 'id'}]);
  assert.deepEqual(find('independent-json').expected, [{id: 1, score: 5}]);
  assert.deepEqual(find('range').expected, find('independent-json').expected);
  assert.deepEqual(find('range').columns.map(column => column.name), ['id', 'score']);
  assert.ok(find('range').columns.every(column => column.contract.nullable === false));
});

test('parameter ceiling and original input remain explicit in submitted source', () => {
  const fixture = find('quoted-parameter-tight-ceiling');
  assert.match(fixture.text, /WHERE \(\(`L`\)\)\.`payload`\.score > @minimum/u);
  assert.match(fixture.text, /MAX_OUTPUT_ROWS 1 \|> SELECT/u);
  assert.equal(fixture.parameters.minimum, 15);
  assert.deepEqual(fixture.parameterDeclarations.minimum, {type: 'number', nullable: false});
  assert.deepEqual(find('input-before-output-alias').expected, [{id: 1, payload: {score: 5}}]);
});

test('value and range collisions distinguish filtering, NULL and multiplicity', () => {
  assert.deepEqual(find('same-named-value').expected, [{id: 1, score: 5}]);
  assert.match(find('same-named-value').text, /AS payload \|> WHERE \(payload\.payload\)\.score > 15/u);
  assert.deepEqual(find('same-named-qualified-range').expected,
    [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: 15}]);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.deepEqual(find('typed-empty').columns, find('range').columns);
  assert.equal(joinPropertySuccesses.filter(item => item.name.startsWith('join-property-prefilter-')).length, 7);
});

test('future range and scalar receiver require exact pre-admission input refusals', () => {
  const refusals = joinPropertyRefusals.filter(item => item.name.startsWith('join-property-prefilter-'));
  assert.equal(refusals.length, 2);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.match(refusals[0].text, /WHERE \(\(r\)\)\.other\.score > 0 \|> JOIN/u);
  const removed = joinPropertyRefusals.find(item => item.name === 'join-property-invalid-4');
  assert.equal(removed.expectedCode, 'ClientProgramInvalidInput');
});
