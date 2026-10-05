import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {computedObjectPropertyProgram, computedObjectPropertySuccesses as successes,
  computedObjectPropertyRefusals as refusals, computedObjectPropertyExecutionFailures as failures}
  from './fixtures/computed-object-property-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('computed receiver fixtures distinguish ORDER output aliases from selected inputs', () => {
  const alias = successes.find(item => item.name.endsWith('order-receiver-alias'));
  const input = successes.find(item => item.name.endsWith('order-qualified-control'));
  assert.deepEqual(alias.expected.map(row => row.id), [1, 3, 4, 2, 2]);
  assert.deepEqual(input.expected.map(row => row.id), [2, 2, 3, 1, 4]);
  // These independent keys are computed directly from the authored parameters,
  // not by a Frontend or runtime expression evaluator.
  const original = [alias.parameters.p1.score, alias.parameters.p2.score,
    alias.parameters.o3.score, alias.parameters.p4.score];
  const replaced = [alias.parameters.o1.score, alias.parameters.o2.score,
    alias.parameters.o3.score, alias.parameters.o4.score];
  assert.deepEqual(original, [20, 10, 15, null]);
  assert.deepEqual(replaced, [5, 30, 15, 25]);
  assert.deepEqual(alias.columns.map(column => column.name), ['id', 'original_score', 'payload']);
});

test('computed receiver controls retain member NULL, duplicate JOIN rows and empty types', () => {
  const sql = successes.find(item => item.name.endsWith('sql-coalesce'));
  assert.deepEqual(sql.expected, [{id: 1, score: 20}, {id: 2, score: 10},
    {id: 2, score: 10}, {id: 3, score: 15}, {id: 4, score: null}]);
  assert.equal(sql.parameters.p3, null);
  assert.equal(sql.parameters.p4.score, null);
  assert.equal(sql.parameters.o4.score, 25);
  const join = successes.find(item => item.name.endsWith('join-receiver-inputs'));
  assert.deepEqual(join.expected.map(row => row.id), [1, 2, 2, 2, 2, 3, 4]);
  const empty = successes.find(item => item.name.endsWith('empty-typed'));
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.sourceRows, []);
  assert.deepEqual(empty.columns, sql.columns);
  for (const item of successes) assert.equal(item.sourceReadSessionCount, 1);
});

test('independent machine control uses existing typed property and checked parameter contracts', () => {
  const control = successes.find(item => item.format === 'json');
  assert.deepEqual(JSON.parse(control.text), computedObjectPropertyProgram);
  assert.equal(control.parameterDeclarations, undefined);
  assert.deepEqual(computedObjectPropertyProgram.params.p1,
    {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: true},
      nested: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: true}}}}});
  assert.deepEqual(computedObjectPropertyProgram.stages[1].steps[2],
    {derive: {score: {property: {name: 'score',
      value: {coalesce: [{field: 'payload'}, {field: 'other'}]}}}}});
  assert.deepEqual(computedObjectPropertyProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  const groups = publicQueryProfiles({successes, refusals, executionFailures: failures});
  assert.equal(groups.length, 1);
  assert.equal(groups[0].name, 'standard');
  assert.deepEqual(['successes', 'refusals', 'executionFailures']
    .map(kind => groups[0].inputs[kind].length), [9, 5, 1]);
});

test('computed receiver corpus runs in the ordinary packed route as well as a focused selection', async () => {
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['computedObjectPropertySuccesses', 'computedObjectPropertyRefusals',
    'computedObjectPropertyExecutionFailures']) {
    assert.ok(app.includes('push(...' + name + ')'));
  }
  assert.ok(app.includes('ACTQL_TEST_COMPUTED_OBJECT_PROPERTY_ONLY'));
  assert.ok(driver.includes('computed-object-property-source-input.mjs'));
  assert.ok(driver.includes('--computed-object-property-only'));
});
