import assert from 'node:assert/strict';
import test from 'node:test';
import {analyticPartitionExpressionSuccesses as corpus,
  windowKeyReceiverProgram as program, windowKeyReceiverSuccesses as cases}
  from './fixtures/analytic-partition-expression-source-input.mjs';

test('window key control computes once and preserves repeated keys and distinct order', () => {
  const steps = program.stages[1].steps;
  assert.deepEqual(steps[0], {from: 'records',
    derive: {key: {gt: [{field: 'amount'}, {literal: 25}]}}});
  assert.deepEqual(steps[1].analytic.partition_by, ['key', 'key']);
  assert.deepEqual(steps[2].analytic.partition_by, ['key']);
  assert.equal(steps[1].analytic.order_by[1].dir, 'asc');
  assert.equal(steps[2].analytic.order_by[0].dir, 'desc');
  assert.deepEqual(JSON.parse(cases[0].text), program);
  assert.deepEqual(cases[0].expected.map(row => [row.pos, row.ranking]),
    [[1, 2], [2, 1], [1, 2], [1, 2], [2, 1], [2, 1]]);
});

test('nullable object controls detect receiver collapse and preserve typed empty output', () => {
  assert.deepEqual(cases[4].expected.map(row => row.ranking), [1, 1, 4, 3, 2, 1]);
  assert.deepEqual(cases[5].expected.map(row => row.ranking), [6, 5, 4, 3, 2, 1]);
  assert.notDeepEqual(cases[4].expected, cases[5].expected);
  assert.equal(cases[4].parameters.c, null);
  assert.deepEqual(cases[4].parameters.e, {bucket: null});
  assert.deepEqual(cases[3].expected, []);
  assert.deepEqual(cases[3].columns, cases[1].columns);
  assert.equal(cases.length, 6);
  for (const item of cases) {
    assert.ok(corpus.includes(item));
    assert.equal(item.sourceReadSessionCount, 1);
    assert.equal(item.hostProfile, 'analytic-order');
  }
});
