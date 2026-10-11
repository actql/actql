import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctOrderReceiverProgram, distinctOrderReceiverInvalidProgram,
  distinctOrderReceiverSuccesses, distinctOrderReceiverRefusals}
  from './fixtures/distinct-order-receiver-source-input.mjs';

test('DISTINCT receiver controls pin numeric outputs and an independent invalid property', () => {
  assert.equal(distinctOrderReceiverSuccesses.length, 5);
  assert.equal(distinctOrderReceiverRefusals.length, 5);
  const input = distinctOrderReceiverSuccesses.find(item => item.name.endsWith('unshadowed-input'));
  const output = distinctOrderReceiverSuccesses.find(item => item.name.endsWith('numeric-output'));
  assert.deepEqual(input.expected.map(row => row.original_score), [10, 20, null]);
  assert.deepEqual(output.expected.map(row => row.original_score), [20, 10, null]);
  assert.deepEqual(input.columns, [
    {name: 'original_score', contract: {type: 'number', nullable: true}},
    {name: 'payload', contract: {type: 'number', nullable: true}},
  ]);
  const valid = distinctOrderReceiverProgram.stages[1].steps;
  const invalid = distinctOrderReceiverInvalidProgram.stages[1].steps;
  assert.deepEqual(valid[2], {distinct: ['original_score', 'payload']});
  assert.deepEqual(invalid[3].derive.order_only, {add: [
    {property: {name: 'score', value: {field: 'payload'}}}, {literal: 1},
  ]});
  for (const index of [0, 1, 2, 4, 5]) assert.deepEqual(invalid[index], valid[index]);
  for (const item of [...distinctOrderReceiverSuccesses, ...distinctOrderReceiverRefusals]) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.equal(Object.hasOwn(item, 'capacity'), false);
  }
  assert.ok(distinctOrderReceiverRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('DISTINCT receiver cases participate in normal registration and the bounded existing driver', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...distinctOrderReceiverSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...distinctOrderReceiverRefusals)'));
  assert.ok(packed.includes('ACTQL_TEST_DISTINCT_ORDER_RECEIVER_ONLY'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_DISTINCT_ORDER_RECEIVER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/distinct-order-receiver-source-input.mjs', 'distinct-order-receiver-source-input.mjs']"));
  const start = driver.indexOf('const narrowPublicQuery =');
  const end = driver.indexOf('.includes(flag));', start);
  assert.ok(driver.slice(start, end).includes("'--distinct-order-receiver-only'"));
  const publicEnd = driver.indexOf("if (process.argv.includes('--distinct-order-receiver-only')) return;");
  assert.ok(publicEnd > driver.indexOf("['packed-query-transports.mjs']"));
  assert.ok(publicEnd < driver.indexOf('await exerciseRetainedQueryRestart();'));
});
