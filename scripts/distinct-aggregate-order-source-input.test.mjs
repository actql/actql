import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctAggregateOrderProgram, distinctAggregateOrderSuccesses,
  distinctAggregateOrderRefusals} from './fixtures/distinct-aggregate-order-source-input.mjs';

test('DISTINCT aggregate order obligations distinguish multiplicity and input snapshots', () => {
  const cases = new Map(distinctAggregateOrderSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('distinct-aggregate-order-sql').expected, [{names: '10|20'}]);
  assert.deepEqual(cases.get('distinct-aggregate-order-ordinary-other-key').expected,
    [{names: '20|10|20'}]);
  assert.deepEqual(cases.get('distinct-aggregate-order-typed-empty').expected, [{names: null}]);
  assert.deepEqual(cases.get('distinct-aggregate-order-pipe-descending').expected, [{names: '20|10'}]);
  assert.deepEqual(cases.get('distinct-aggregate-order-static-property').expected, [{names: 'kept'}]);
  assert.deepEqual(cases.get('distinct-aggregate-order-keyed-array-qualified').expected,
    [{ids: [4, 3, 2, 1]}]);
  assert.deepEqual(JSON.parse(cases.get('distinct-aggregate-order-independent-json').text),
    distinctAggregateOrderProgram);
  const call = distinctAggregateOrderProgram.stages[1].steps[1].group.aggregates.names;
  assert.equal(call.distinct, true);
  assert.deepEqual(call.order_by, [{field: 'name', dir: 'asc', nulls: 'first'}]);
  for (const item of distinctAggregateOrderRefusals) {
    assert.equal(item.expectedCode, 'ClientProgramImplementationLimit');
  }
  const all = [...distinctAggregateOrderSuccesses, ...distinctAggregateOrderRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('normal packed acceptance and selected cohort share DISTINCT aggregate order cases', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'distinctAggregateOrderSuccesses'],
    ['refusals', 'distinctAggregateOrderRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('distinctAggregateOrderOnly'));
  assert.ok(fixture.includes('distinctAggregateOrderOnly ? {successes: distinctAggregateOrderSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_DISTINCT_AGGREGATE_ORDER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/distinct-aggregate-order-source-input.mjs', 'distinct-aggregate-order-source-input.mjs']"));
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0];
  assert.ok(narrow.includes("'--distinct-aggregate-order-only'"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--distinct-aggregate-order-only'\).*?return;/su);
});
