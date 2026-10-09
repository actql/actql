import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregateConditionalOrderProgram as program, distinctConditionalOrderProgram, distinctConditionalMemberProgram,
  aggregateConditionalOrderSuccesses as successes,
  aggregateConditionalOrderRefusals as refusals}
  from './fixtures/aggregate-conditional-order-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('conditional order has an independent complete JSON control and discriminating rows', () => {
  assert.deepEqual(JSON.parse(successes.find(item => item.format === 'json').text), program);
  assert.deepEqual(program.stages[1].steps[2], {derive: {key: {coalesce: [
    {property: {name: 'score', value: {field: 'payload'}}}, {literal: 0}]}}});
  assert.deepEqual(program.stages[1].steps[3].group.aggregates.names.order_by,
    [{field: 'key', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]);
  assert.deepEqual(program.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  const get = name => successes.find(item => item.name.endsWith('-' + name));
  assert.deepEqual(get('sql').expected, [{names: 'c|b|b|a'}]);
  assert.deepEqual(get('computed-receiver').expected, [{names: 'b|b|c|a'}]);
  assert.deepEqual(get('current-and-snapshot').expected,
    [{current: 'a|c|b|b', previous: 'c|b|b|a'}]);
  assert.deepEqual(get('per-call-orders').expected,
    [{names: 'c|b|b|a', reverse: 'a|b|b|c'}]);
  for (const name of ['empty', 'masked-argument']) assert.deepEqual(get(name).expected, [{names: null}]);
  assert.ok(get('masked-argument').text.includes('id / (id - id)'));
  assert.ok(get('masked-argument').text.includes('WHERE FALSE'));
  assert.equal(get('sql').sourceRows.filter(row => row.id === 2).length, 2);
  assert.deepEqual(get('sql').columns, [{name: 'names', contract: {type: 'string', nullable: true}}]);
  assert.equal(get('typed-parameter').parameters.fallback, 0);
  assert.deepEqual(get('distinct-same-argument').expected, [{names: 'a|b|c|missing'}]);
  for (const item of successes) assert.equal(item.sourceReadSessionCount, 1);
});

test('normal and focused public routes retain conditional inputs and existing limits', async () => {
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['aggregateConditionalOrderSuccesses', 'aggregateConditionalOrderRefusals']) {
    assert.ok(app.includes('push(...' + name + ')'));
    assert.ok(app.includes('...aggregateSignedOrder' + (name.endsWith('Successes') ? 'Successes' : 'Refusals') + ', ...' + name));
  }
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/aggregate-conditional-order-source-input.mjs', 'aggregate-conditional-order-source-input.mjs']"));
  const groups = publicQueryProfiles({successes, refusals});
  assert.deepEqual(groups.map(group => group.name), ['standard']);
  assert.equal(Object.hasOwn(groups[0].capacity, 'max_execution_bytes'), false);
  assert.deepEqual([successes.length, refusals.length], [21, 9]);
  assert.equal(refusals.find(item => item.name.endsWith('unsafe-demand')).expectedCode, 'ClientProgramImplementationLimit');
});


test('DISTINCT qualified conditional keys retain independent Programs values and exact refusals', () => {
  const get = name => successes.find(item => item.name === 'aggregate-conditional-order-' + name);
  assert.deepEqual(JSON.parse(get('distinct-independent-json').text), distinctConditionalOrderProgram);
  assert.deepEqual(distinctConditionalOrderProgram.stages[1].steps[3].group.aggregates.names, {
    fn: 'string_agg', expr: {coalesce: [{field: 'name'}, {literal: 'missing'}]},
    distinct: true, max_bytes: 65536, delimiter: '|',
    order_by: [{field: 'key', dir: 'asc', nulls: 'first'}],
  });
  for (const name of ['distinct-qualified-sql', 'distinct-quoted-pipe']) {
    assert.deepEqual(get(name).expected, [{names: 'a|b|c|missing'}]);
    assert.deepEqual(get(name).sourceRows.filter(row => row.id === 2),
      [{id: 2, amount: 10}, {id: 2, amount: 10}]);
  }
  assert.deepEqual(get('distinct-empty').expected, [{names: null}]);
  assert.deepEqual(get('qualified-shared-key').expected,
    [{names: 'a|b|b|c', reverse: 'c|b|b|a'}]);
  assert.deepEqual(get('distinct-case-qualified').expected, [{names: 'a|b|missing|third'}]);
  assert.deepEqual(JSON.parse(get('distinct-member-independent-json').text), distinctConditionalMemberProgram);
  const member = distinctConditionalMemberProgram.stages[1].steps;
  assert.deepEqual(member[2], {assert_rows: {unique_by: ['id']}});
  assert.deepEqual(member[4], {take: 4});
  assert.deepEqual(member[6].group.aggregates.ids.order_by,
    [{field: 'key', dir: 'desc', nulls: 'last'}]);
  assert.equal(member[6].group.aggregates.ids.distinct, true);
  assert.equal(member[6].group.aggregates.ids.max_items, 1000000);
  assert.deepEqual(get('distinct-member-pipe').expected, [{ids: [20, 10, 0]}]);
  assert.deepEqual(get('distinct-member-pipe').columns, [{name: 'ids', contract: {
    type: 'array', nullable: false, items: {type: 'number', nullable: false}}}]);
  for (const name of ['distinct-literal-mismatch', 'distinct-current-snapshot',
    'distinct-member-mismatch', 'distinct-explicit-receiver']) {
    assert.equal(refusals.find(item => item.name === 'aggregate-conditional-order-refuse-' + name).expectedCode,
      'ClientProgramImplementationLimit');
  }
});
