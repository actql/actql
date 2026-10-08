import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctArrayReferenceKeyProgram as program,
  distinctArrayReferenceKeySuccesses as successes,
  distinctArrayReferenceKeyRefusals as refusals}
  from './fixtures/distinct-array-reference-key-source-input.mjs';
import {distinctAggregateOrderSuccesses, distinctAggregateOrderRefusals}
  from './fixtures/distinct-aggregate-order-source-input.mjs';

test('independent ARRAY Program derives x uniqueness after preserving the input bound', () => {
  const steps = program.stages[1].steps;
  assert.deepEqual(program.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(steps[0], {from: 'records', assert_rows: {unique_by: ['id']}});
  assert.deepEqual(steps[1], {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]});
  assert.deepEqual(steps[2], {take: {count: 4, offset: 0}});
  assert.deepEqual(steps[3], {derive: {x: {coalesce: [{field: 'amount'}, {literal: 0}]}}});
  assert.deepEqual(steps[4], {select: ['x']});
  assert.deepEqual(steps[5], {distinct: ['x']});
  assert.deepEqual(steps[6].group.aggregates.items,
    {fn: 'array_agg', field: 'x', distinct: true, max_items: 1000000,
      order_by: [{field: 'x', dir: 'desc', nulls: 'last'}]});
  assert.deepEqual(JSON.parse(successes[0].text), program);
  assert.deepEqual(successes[0].expected, [{items: [20, 10, 0]}]);
  // The source deliberately contains two different IDs with amount=20.
  assert.deepEqual(successes[0].sourceRows.filter(row => row.amount === 20),
    [{id: 4, amount: 20}, {id: 1, amount: 20}]);
});

test('source obligations include equivalent references, distinct order inputs and visible schema', () => {
  assert.equal(successes.length, 7);
  const cases = new Map(successes.map(item => [item.name, item]));
  assert.deepEqual(cases.get('distinct-array-reference-key-ascending').expected,
    [{items: [0, 10, 20]}]);
  assert.deepEqual(cases.get('distinct-array-reference-key-filtered').expected,
    [{items: [20, 10]}]);
  assert.match(cases.get('distinct-array-reference-key-filtered').text, /WHERE x >= 10$/u);
  for (const item of successes) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.deepEqual(item.columns, [{name: 'items', contract: {type: 'array',
      nullable: false, items: {type: 'number', nullable: false}}}]);
    assert.ok(distinctAggregateOrderSuccesses.includes(item));
    if (item.format === 'aql-text') {
      assert.match(item.text, /WHERE id > 0 .*ASSERT UNIQUE BY \(id\).*ORDER BY id.*LIMIT 4/u);
      assert.doesNotMatch(item.text, /ASSERT UNIQUE BY \(x\)/u);
    }
  }
  assert.equal(refusals.length, 2);
  assert.match(refusals[0].text, /ORDER BY p\.id\)/u);
  assert.match(refusals[1].text, /ORDER BY -p\.x\)/u);
  for (const item of refusals) {
    assert.equal(item.expectedCode, 'ClientProgramImplementationLimit');
    assert.ok(distinctAggregateOrderRefusals.includes(item));
  }
  const all = [...successes, ...refusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('the existing packed consumer copies the ARRAY fixture into its external install', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/distinct-array-reference-key-source-input.mjs', 'distinct-array-reference-key-source-input.mjs']"));
});
