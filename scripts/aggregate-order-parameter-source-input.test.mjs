import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregateOrderParameterProgram, aggregateOrderObjectParameterProgram,
  aggregateOrderParameterSuccesses as successes, aggregateOrderParameterRefusals as refusals}
  from './fixtures/aggregate-order-parameter-source-input.mjs';
import {aggregatePropertyOrderSuccesses, aggregatePropertyOrderRefusals}
  from './fixtures/aggregate-property-order-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('independent scalar and object Programs preserve source predicate, order fields and projection', () => {
  const controls = successes.filter(item => item.format === 'json');
  assert.deepEqual(controls.map(item => JSON.parse(item.text)),
    [aggregateOrderParameterProgram, aggregateOrderObjectParameterProgram]);
  for (const item of controls) assert.equal(item.parameterDeclarations, undefined);
  assert.deepEqual(aggregateOrderParameterProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(aggregateOrderParameterProgram.stages[1].steps[2], {derive: {key: {$param: 'key'}}});
  assert.deepEqual(aggregateOrderObjectParameterProgram.stages[1].steps[2],
    {derive: {key: {property: {name: 'rank', value: {$param: 'cfg'}}}}});
  for (const program of [aggregateOrderParameterProgram, aggregateOrderObjectParameterProgram]) {
    assert.deepEqual(program.stages[1].steps[3].group.aggregates.names.order_by,
      [{field: 'key', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]);
    assert.deepEqual(program.stages[1].results.rows.fields, ['names']);
  }
});

test('parameter and input-column collisions produce different order, while nullable keys retain duplicates', () => {
  const get = name => successes.find(item => item.name.endsWith(name));
  const collision = get('column-name-collision');
  assert.ok(collision.text.includes('ORDER BY @NAME DESC NULLS LAST, id'));
  assert.deepEqual(collision.parameterDeclarations, {name: {type: 'number', nullable: true}});
  assert.deepEqual(collision.parameters, {name: 7});
  assert.deepEqual(collision.expected, [{names: 'z|a|a|m'}]);
  // Resolving @NAME as the string input column would concatenate z|m|a|a.
  assert.notDeepEqual(collision.expected, [{names: 'z|m|a|a'}]);
  for (const name of ['sql', 'quoted-pipe', 'nullable-scalar', 'object-member', 'nullable-object', 'nullable-member']) {
    assert.deepEqual(get(name).expected, [{names: 'z|a|a|m'}]);
  }
  assert.deepEqual(get('filtered-argument').expected, [{names: 'z|a|a'}]);
  assert.deepEqual(get('typed-empty').expected, [{names: null}]);
  assert.deepEqual(get('distinct-same-parameter').expected, [{names: 'kept'}]);
  assert.deepEqual(get('distinct-null-parameter').expected, [{names: null}]);
  for (const item of successes) {
    assert.deepEqual(item.columns, [{name: 'names', contract: {type: 'string', nullable: true}}]);
    assert.equal(item.sourceReadSessionCount, 1);
  }
  assert.equal(collision.sourceRows.filter(row => row.id === 2).length, 2);
});

test('ordinary packed registration includes parameter cases without raising installed capacity', async () => {
  for (const item of successes) assert.ok(aggregatePropertyOrderSuccesses.includes(item));
  for (const item of refusals) assert.ok(aggregatePropertyOrderRefusals.includes(item));
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['aggregatePropertyOrderSuccesses', 'aggregatePropertyOrderRefusals']) {
    assert.ok(app.includes('push(...' + name + ')'));
  }
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/aggregate-order-parameter-source-input.mjs', 'aggregate-order-parameter-source-input.mjs']"));
  const profiles = publicQueryProfiles({successes, refusals});
  assert.equal(profiles.length, 1);
  assert.equal(profiles[0].name, 'standard');
  assert.equal(Object.hasOwn(profiles[0].capacity, 'max_execution_bytes'), false);
  assert.deepEqual([successes.length, refusals.length], [13, 10]);
  for (const name of ['distinct-different-argument', 'numeric-ordinal']) {
    assert.equal(refusals.find(item => item.name.endsWith(name)).expectedCode, 'ClientProgramImplementationLimit');
  }
});
