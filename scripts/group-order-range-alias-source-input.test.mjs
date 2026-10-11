import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {groupOrderRangeAliasProgram, groupOrderRangeAliasSuccesses,
  groupOrderRangeAliasRefusals} from './fixtures/group-order-range-alias-source-input.mjs';

test('GROUP ORDER alias and range controls have independently opposite ordered keys', () => {
  assert.equal(groupOrderRangeAliasSuccesses.length, 6);
  assert.equal(groupOrderRangeAliasRefusals.length, 3);
  const dotted = groupOrderRangeAliasSuccesses.find(item => item.name.endsWith('dotted-shadow'));
  const original = groupOrderRangeAliasSuccesses.find(item => item.name.endsWith('qualified-input-control'));
  assert.deepEqual(dotted.expected.map(row => row.bucket), [20, 10, null]);
  assert.deepEqual(original.expected.map(row => row.bucket), [10, 20, null]);
  assert.deepEqual(dotted.columns.map(column => column.name), ['bucket', 'payload', 'n']);
  assert.deepEqual(dotted.expected.map(row => row.n), [1, 2, 1]);
  const steps = groupOrderRangeAliasProgram.stages[1].steps;
  assert.deepEqual(steps[3].derive, {order_score: {property: {name: 'score', value: {field: 'evaluated'}}}});
  assert.deepEqual(steps[5].select, [{bucket: 'score'}, {payload: 'evaluated'}, 'n']);
  for (const item of [...groupOrderRangeAliasSuccesses, ...groupOrderRangeAliasRefusals]) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.equal(Object.hasOwn(item, 'capacity'), false);
  }
});

test('GROUP ORDER receiver regressions are normal registered cases and a narrow existing-driver selection', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...groupOrderRangeAliasSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...groupOrderRangeAliasRefusals)'));
  assert.ok(packed.includes('ACTQL_TEST_GROUP_ORDER_RANGE_ALIAS_ONLY'));
  assert.ok(driver.includes("['scripts/fixtures/group-order-range-alias-source-input.mjs', 'group-order-range-alias-source-input.mjs']"));
  const start = driver.indexOf('const narrowPublicQuery =');
  const end = driver.indexOf('.includes(flag));', start);
  assert.ok(driver.slice(start, end).includes("'--group-order-range-alias-only'"));
  const publicEnd = driver.indexOf("if (process.argv.includes('--group-order-range-alias-only')) return;");
  assert.ok(publicEnd > driver.indexOf("['packed-query-transports.mjs']"));
  assert.ok(publicEnd < driver.indexOf('await exerciseRetainedQueryRestart();'));
});
