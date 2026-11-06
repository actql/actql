import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {joinedUnnestStarProgram, joinedUnnestAcquiredStarProgram,
  joinedUnnestStarSuccesses as successes, joinedUnnestStarRefusals as refusals}
  from './fixtures/joined-unnest-star-source-input.mjs';
import {correlatedUnnestSuccesses, correlatedUnnestRefusals}
  from './fixtures/correlated-unnest-source-input.mjs';

test('JOIN star controls preserve the exact predicate ceiling and nullable duplicate rows', () => {
  const control = successes.find(item => item.name === 'joined-unnest-star-json-control');
  assert.deepEqual(JSON.parse(control.text), joinedUnnestStarProgram);
  assert.deepEqual(control.expected, [{id: 1, code: 10, label: 'a', position: 0},
    {id: 2, code: 20, label: null, position: 0}, {id: 2, code: null, label: null, position: 1},
    {id: 2, code: 20, label: null, position: 2}]);
  assert.deepEqual(control.columns.map(column => [column.name, column.contract]),
    [['id', {type: 'number', nullable: false}], ['code', {type: 'number', nullable: true}],
      ['label', {type: 'string', nullable: true}], ['position', {type: 'number', nullable: false}]]);
  for (const program of [joinedUnnestStarProgram, joinedUnnestAcquiredStarProgram]) {
    const main = program.stages.find(stage => stage.id === 'main');
    const joined = main.steps.find(step => step.join);
    assert.equal(joined.join.max_output_rows, 4);
    assert.deepEqual(joined.join.on, [{left: 'id', right: joined.join.with === 'keys' ? 'key' : 'id'}]);
    assert.deepEqual(main.results.rows.fields, control.columns.map(column => column.name));
    assert.equal(program.params.parents.items.fields.items.items.nullable, true);
    assert.equal(program.params.parents.items.fields.items.items.fields.code.nullable, false);
  }
  const empty = successes.find(item => item.name === 'joined-unnest-star-empty');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, control.columns);
});

test('current and original JOIN columns remain separate with acquired source lifecycle checks', () => {
  const original = successes.find(item => item.name === 'joined-unnest-star-original-range');
  const current = successes.find(item => item.name === 'joined-unnest-star-current-column');
  assert.match(original.text, /SET items = \[9\].*UNNEST\(p\.items\)/u);
  assert.match(current.text, /SET items = \[9\].*UNNEST\(items\)/u);
  assert.deepEqual(current.expected, [{id: 1, items: [9], key: 1, e: 9, position: 0},
    {id: 2, items: [9], key: 2, e: 9, position: 0}]);
  const acquired = successes.find(item => item.name === 'joined-unnest-star-acquired-data');
  const control = successes.find(item => item.name === 'joined-unnest-star-acquired-json-control');
  assert.deepEqual(JSON.parse(control.text), joinedUnnestAcquiredStarProgram);
  for (const field of ['expected', 'columns', 'sourceRows', 'sourceReadCount', 'sourceReadSessionCount']) {
    assert.deepEqual(acquired[field], control[field]);
  }
  assert.equal(acquired.sourceReadCount, 1);
  assert.equal(acquired.sourceReadSessionCount, 1);
  const value = successes.find(item => item.name === 'joined-unnest-star-value-receiver-contrast');
  const valueControl = successes.find(item => item.name === 'joined-unnest-star-value-receiver-json-control');
  assert.deepEqual(value.expected, [{value: 10}]);
  assert.deepEqual(value.expected, valueControl.expected);
  assert.deepEqual(value.columns, valueControl.columns);
  assert.equal(value.parameters.objects[0].score, 90);
  assert.equal(value.parameters.objects[0].payload.score, 10);
  assert.match(value.text, /AS payload \|> SELECT \(payload\.payload\)\.score AS value/u);
});

test('joined star cases use the normal correlated cohort and precise pre-admission refusals', () => {
  for (const item of successes) assert.equal(correlatedUnnestSuccesses.filter(value => value === item).length, 1);
  for (const item of refusals) {
    assert.equal(correlatedUnnestRefusals.filter(value => value === item).length, 1);
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size,
    successes.length + refusals.length);
  assert.ok(readFileSync('scripts/test-packed-public-query.mjs', 'utf8').includes(
    "['scripts/fixtures/joined-unnest-star-source-input.mjs', 'joined-unnest-star-source-input.mjs']"));
});
