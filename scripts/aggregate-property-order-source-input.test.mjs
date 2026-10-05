import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregatePropertyOrderProgram, aggregatePropertyOrderArrayProgram,
  aggregatePropertyOrderSuccesses as successes, aggregatePropertyOrderRefusals as refusals,
  aggregatePropertyOrderExecutionFailures as failures}
  from './fixtures/aggregate-property-order-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('collection orders discriminate input properties, current slots and independent per-call order', () => {
  const expected = name => successes.find(item => item.name.endsWith(name)).expected;
  assert.deepEqual(expected('-sql'), [{names: 'b|b|a|c'}]);
  assert.deepEqual(expected('per-call-opposite-order'), [{names: 'b|b|a|c', reverse: 'c|a|b|b'}]);
  assert.deepEqual(expected('current-and-snapshot'), [{current: 'a|c|b|b', previous: 'b|b|a|c'}]);
  assert.deepEqual(expected('input-over-sibling'), [{payload: 5, names: 'b|b|a|c'}]);
  assert.deepEqual(expected('filtered-input'), [{names: 'b|b|a'}]);
  assert.deepEqual(expected('empty-global'), [{names: null}]);
  const sql = successes.find(item => item.name.endsWith('-sql'));
  assert.deepEqual([sql.parameters.p1.score, sql.parameters.p2.score, sql.parameters.p3], [20, 10, null]);
  assert.deepEqual([sql.parameters.o1.score, sql.parameters.o2.score, sql.parameters.o3.score], [5, 30, 15]);
  assert.equal(sql.parameters.p4.score, null);
  assert.equal(sql.sourceRows.filter(row => row.id === 2).length, 2);
});

test('independent JSON controls preserve predicate, scalar aggregate argument and actual array key assertion', () => {
  const controls = successes.filter(item => item.format === 'json');
  assert.deepEqual(controls.map(item => JSON.parse(item.text)),
    [aggregatePropertyOrderProgram, aggregatePropertyOrderArrayProgram]);
  for (const item of controls) assert.equal(item.parameterDeclarations, undefined);
  assert.deepEqual(aggregatePropertyOrderProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(aggregatePropertyOrderProgram.stages[1].steps[3].group.aggregates.names,
    {fn: 'string_agg', field: 'name', order_by: [{field: 'key', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], max_bytes: 65536, delimiter: '|'});
  const array = successes.find(item => item.name.endsWith('keyed-array'));
  assert.ok(array.text.includes('ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4'));
  assert.deepEqual(aggregatePropertyOrderArrayProgram.stages[1].steps[2], {assert_rows: {unique_by: ['id']}});
  assert.deepEqual(aggregatePropertyOrderArrayProgram.stages[1].steps[4], {take: 4});
  assert.deepEqual(array.expected, [{ids: [2, 1, 3, 4]}]);
  assert.deepEqual(array.columns, [{name: 'ids', contract: {type: 'array', nullable: false,
    items: {type: 'number', nullable: false}}}]);
});

test('collection order cases retain one source acquisition and standard installed ceilings', () => {
  for (const item of successes) assert.equal(item.sourceReadSessionCount, 1);
  for (const item of successes) assert.deepEqual(Object.keys(item.parameters).sort(),
    Object.keys(aggregatePropertyOrderProgram.params).sort());
  const groups = publicQueryProfiles({successes, refusals, executionFailures: failures});
  assert.equal(groups.length, 1);
  assert.equal(groups[0].name, 'standard');
  assert.equal(Object.hasOwn(groups[0].capacity, 'max_execution_bytes'), false);
  assert.deepEqual(['successes', 'refusals', 'executionFailures']
    .map(kind => groups[0].inputs[kind].length), [10, 4, 1]);
});

test('ordinary packed route and focused selection both include collection property order cases', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['aggregatePropertyOrderSuccesses', 'aggregatePropertyOrderRefusals',
    'aggregatePropertyOrderExecutionFailures']) assert.ok(app.includes('push(...' + name + ')'));
  assert.ok(app.includes('ACTQL_TEST_AGGREGATE_PROPERTY_ORDER_ONLY'));
  assert.ok(driver.includes('--aggregate-property-order-only'));
  assert.ok(driver.includes('aggregate-property-order-source-input.mjs'));
});
