import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctSignedOrderProgram, distinctSignedOrderSuccesses as successes,
  distinctSignedOrderRefusals as refusals} from './fixtures/distinct-signed-order-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

test('signed DISTINCT control retains explicit key, bound, argument, order and duplicate observations', () => {
  const [control] = successes;
  assert.deepEqual(JSON.parse(control.text), distinctSignedOrderProgram);
  const steps = distinctSignedOrderProgram.stages[1].steps;
  assert.deepEqual(steps[2], {assert_rows: {unique_by: ['id']}});
  assert.deepEqual(steps[4], {take: 4});
  const argument = {negate: {property: {name: 'score', value: {field: 'payload'}}}};
  assert.deepEqual(steps[5], {derive: {key: argument}});
  assert.deepEqual(steps[6].group.aggregates.items, {fn: 'array_agg', expr: argument,
    distinct: true, max_items: 1000000, order_by: [{field: 'key', dir: 'asc', nulls: 'first'}]});
  assert.equal(control.parameters.p2.score, control.parameters.p4.score);
  assert.equal(control.parameters.p3, null);
  assert.deepEqual(control.expected, [{items: [-20, -10]}]);
  assert.equal(control.parameterDeclarations, undefined);
});

test('authored expectations distinguish signs, filtering and empty output while preserving typed order', () => {
  const get = name => successes.find(item => item.name === 'distinct-signed-order-' + name);
  assert.deepEqual(get('positive-qualified').expected, [{items: [10, 20]}]);
  assert.deepEqual(get('nested-signs').expected, get('positive-qualified').expected);
  assert.deepEqual(get('descending').expected, [{items: [-10, -20]}]);
  assert.deepEqual(get('direct-id').expected, [{items: [-1, -2, -3, -4]}]);
  assert.deepEqual(get('filtered').expected, [{items: [-20]}]);
  assert.deepEqual(get('empty').expected, [{items: []}]);
  for (const item of successes) {
    assert.deepEqual(item.columns, [{name: 'items', contract: {type: 'array', nullable: false,
      items: {type: 'number', nullable: false}}}]);
    assert.equal(item.sourceReadSessionCount, 1);
  }
  assert.equal(publicQueryProfiles({successes, refusals})[0].name, 'standard');
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramImplementationLimit'));
});

test('normal and focused existing packed routes retain signed DISTINCT obligations', async () => {
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const name of ['distinctSignedOrderSuccesses', 'distinctSignedOrderRefusals']) {
    assert.ok(app.includes('push(...' + name + ')'));
    assert.ok(app.includes('...distinctAggregateOrder' + (name.endsWith('Successes') ? 'Successes' : 'Refusals') + ', ...' + name));
  }
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/distinct-signed-order-source-input.mjs', 'distinct-signed-order-source-input.mjs']"));
  assert.deepEqual([successes.length, refusals.length], [10, 5]);
});
