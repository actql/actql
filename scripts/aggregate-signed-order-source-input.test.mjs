import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {aggregateSignedOrderProgram, aggregateSignedArrayOrderProgram,
  aggregateSignedOrderSuccesses as successes, aggregateSignedOrderRefusals as refusals}
  from './fixtures/aggregate-signed-order-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('signed order has independent scalar and keyed-array JSON controls', () => {
  assert.deepEqual(successes.filter(item => item.format === 'json').map(item => JSON.parse(item.text)),
    [aggregateSignedOrderProgram, aggregateSignedArrayOrderProgram]);
  const negative = {negate: {property: {name: 'score', value: {field: 'payload'}}}};
  assert.deepEqual(aggregateSignedOrderProgram.stages[1].steps[2], {derive: {key: negative}});
  assert.deepEqual(aggregateSignedArrayOrderProgram.stages[1].steps[5], {derive: {key: negative}});
  assert.deepEqual(aggregateSignedArrayOrderProgram.stages[1].steps[2], {assert_rows: {unique_by: ['id']}});
  assert.deepEqual(aggregateSignedArrayOrderProgram.stages[1].steps[4], {take: 4});
  assert.deepEqual(aggregateSignedOrderProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  for (const item of successes.filter(item => item.format === 'json')) assert.equal(item.parameterDeclarations, undefined);
});

test('expected signed order distinguishes sign removal, NULL placement and snapshot receivers', () => {
  const get = name => successes.find(item => item.name === 'aggregate-signed-order-' + name);
  assert.deepEqual(get('sql').expected, [{names: 'a|b|b|c'}]);
  assert.notDeepEqual(get('sql').expected, get('positive-qualified-pipe').expected);
  assert.deepEqual(get('nested-signs').expected, [{names: 'b|b|a|c'}]);
  assert.deepEqual(get('direct-column').expected, [{names: 'c|b|b|a'}]);
  assert.deepEqual(get('nulls-first').expected, [{names: 'c|a|b|b'}]);
  assert.deepEqual(get('current-and-snapshot').expected, [{current: 'b|b|c|a', previous: 'a|b|b|c'}]);
  assert.deepEqual(get('input-over-sibling').expected, [{payload: 5, names: 'a|b|b|c'}]);
  assert.deepEqual(get('filtered-argument').expected, [{names: 'a|b|b'}]);
  assert.deepEqual(get('keyed-array').expected, [{ids: [1, 2, 3, 4]}]);
  assert.deepEqual(get('keyed-array').columns, [{name: 'ids', contract: {type: 'array', nullable: false,
    items: {type: 'number', nullable: false}}}]);
  for (const name of ['empty', 'masked-argument']) assert.deepEqual(get(name).expected, [{names: null}]);
  assert.ok(get('masked-argument').text.includes('id / (id - id)'));
  assert.ok(get('masked-argument').text.includes('WHERE FALSE ORDER BY -payload.score'));
  assert.equal(get('nullable-parameter').parameters.key, null);
  for (const item of successes) assert.equal(item.sourceReadSessionCount, 1);
  assert.equal(get('sql').sourceRows.filter(row => row.id === 2).length, 2);
});

test('normal and focused packed routes include signed inputs without altering capacity or refusal semantics', async () => {
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['aggregateSignedOrderSuccesses', 'aggregateSignedOrderRefusals']) {
    assert.ok(app.includes('push(...' + name + ')'));
    assert.ok(app.includes('...aggregatePropertyOrder' + (name.endsWith('Successes') ? 'Successes' : 'Refusals') + ', ...' + name));
  }
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/aggregate-signed-order-source-input.mjs', 'aggregate-signed-order-source-input.mjs']"));
  const groups = publicQueryProfiles({successes, refusals});
  assert.equal(groups.length, 1);
  assert.equal(groups[0].name, 'standard');
  assert.equal(Object.hasOwn(groups[0].capacity, 'max_execution_bytes'), false);
  assert.deepEqual([successes.length, refusals.length], [14, 7]);
  for (const name of ['binary-expression', 'numeric-ordinal', 'distinct-different-argument']) {
    assert.equal(refusals.find(item => item.name.endsWith(name)).expectedCode, 'ClientProgramImplementationLimit');
  }
});
