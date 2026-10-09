import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregateConditionalOrderProgram as program, aggregatePredicateOrderProgram, aggregatePredicateArrayOrderProgram, aggregateMembershipOrderProgram, aggregateMembershipArrayOrderProgram,
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
  assert.deepEqual([successes.length, refusals.length], [43, 13]);
  assert.equal(refusals.find(item => item.name.endsWith('unsafe-demand')).expectedCode, 'ClientProgramImplementationLimit');
});

test('Boolean order uses an independent Program and NULL/multiplicity counterexamples', () => {
  assert.deepEqual(JSON.parse(successes.find(item => item.name.endsWith('predicate-independent-json')).text), aggregatePredicateOrderProgram);
  assert.deepEqual(aggregatePredicateOrderProgram.stages[1].steps[2],
    {derive: {key: {is_null: {property: {name: 'score', value: {field: 'payload'}}}}}});
  assert.deepEqual(JSON.parse(successes.find(item => item.name.endsWith('predicate-independent-array-json')).text), aggregatePredicateArrayOrderProgram);
  assert.deepEqual(aggregatePredicateArrayOrderProgram.stages[1].steps[2], {assert_rows: {unique_by: ['id']}});
  const get = name => successes.find(item => item.name.endsWith('-predicate-' + name));
  assert.deepEqual(get('keyed-array').expected, [{ids: [1, 2, 3, 4]}]);
  assert.deepEqual(get('is-null').expected, [{names: 'a|b|b|c'}]);
  assert.deepEqual(get('comparison-pipe').expected, [{names: 'b|b|a|c'}]);
  assert.deepEqual(get('not').expected, [{names: 'a|b|b|c'}]);
  assert.deepEqual(get('and').expected, [{names: 'b|b|c|a'}]);
  assert.deepEqual(get('current-and-snapshot').expected, [{current: 'a|c|b|b', previous: 'b|b|a|c'}]);
  assert.deepEqual(get('per-call').expected, [{names: 'a|b|b|c', reverse: 'c|a|b|b'}]);
  assert.deepEqual(get('parameter').parameterDeclarations.selected, {type: 'number', nullable: false});
  assert.equal(get('parameter').parameters.selected, 2);
  for (const name of ['empty', 'masked']) assert.deepEqual(get(name).expected, [{names: null}]);
  assert.ok(get('masked').text.includes('WHERE FALSE'));
  for (const item of successes.filter(item => item.name.includes('-predicate-'))) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.equal(item.columns.some(column => column.name.startsWith('aql_')), false);
  }
  for (const [name, code] of [['operand-type', 'ClientProgramInvalidInput'],
    ['missing-member', 'ClientProgramInvalidInput'], ['removed-range', 'ClientProgramInvalidInput'],
    ['unsafe-demand', 'ClientProgramImplementationLimit']]) {
    assert.equal(refusals.find(item => item.name.endsWith('predicate-' + name)).expectedCode, code);
  }
});

test('membership order fixes NULL, intervals and null-safe ordering independently', () => {
  const get = name => successes.find(item => item.name.endsWith('-membership-' + name));
  assert.deepEqual(JSON.parse(get('independent-json').text), aggregateMembershipOrderProgram);
  assert.deepEqual(aggregateMembershipOrderProgram.stages[1].steps[2], {derive: {key: {
    in: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: [20, null]}]}}});
  assert.deepEqual(JSON.parse(get('independent-array-json').text), aggregateMembershipArrayOrderProgram);
  assert.deepEqual(aggregateMembershipArrayOrderProgram.stages[1].steps[2], {assert_rows: {unique_by: ['id']}});
  assert.deepEqual(get('keyed-array').expected, [{ids: [2, 1, 3, 4]}]);
  assert.deepEqual(get('in-pipe').expected, [{names: 'b|b|a|c'}]);
  assert.deepEqual(get('null-list').expected, [{names: 'a|b|b|c'}]);
  assert.deepEqual(get('not-between').expected, [{names: 'b|b|a|c'}]);
  assert.deepEqual(get('null-safe').expected, [{names: 'b|b|c|a'}]);
  assert.deepEqual(get('null-safe-null').expected, [{names: 'c|a|b|b'}]);
  assert.deepEqual(get('current-and-snapshot').expected, [{current: 'a|c|b|b', previous: 'a|b|b|c'}]);
  assert.equal(get('parameter').parameters.wanted, 20);
  assert.deepEqual(get('parameter').parameterDeclarations.wanted, {type: 'number', nullable: true});
  assert.deepEqual(get('masked').expected, [{names: null}]);
  for (const item of successes.filter(item => item.name.includes('-membership-'))) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.equal(item.columns.some(column => column.name.startsWith('aql_')), false);
  }
  for (const [name, code] of [['operand-type', 'ClientProgramInvalidInput'],
    ['removed-range', 'ClientProgramInvalidInput'], ['unsafe-bound', 'ClientProgramImplementationLimit'],
    ['distinct-key', 'ClientProgramImplementationLimit']]) {
    assert.equal(refusals.find(item => item.name.endsWith('membership-' + name)).expectedCode, code);
  }
});
