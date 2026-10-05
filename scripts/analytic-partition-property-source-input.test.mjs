import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticPartitionPropertyProgram as program, analyticPartitionPropertySuccesses as successes,
  analyticPartitionPropertyRefusals as refusals} from './fixtures/analytic-partition-property-source-input.mjs';

test('partition obligations distinguish input, SELECT alias, NULL and current Pipe values', () => {
  const cases = new Map(successes.map(item => [item.name, item]));
  const plain = cases.get('analytic-partition-property-sql-null-keys');
  assert.deepEqual(plain.expected, [{id: 1, pos: 1}, {id: 2, pos: 1},
    {id: 3, pos: 1}, {id: 4, pos: 2}, {id: 5, pos: 2}]);
  const snapshots = cases.get('analytic-partition-property-pipe-current-and-snapshot');
  assert.deepEqual(snapshots.expected.map(row => row.current), [1, 1, 2, 2, 3]);
  assert.notDeepEqual(snapshots.expected.map(row => row.before), snapshots.expected.map(row => row.current));
  const empty = cases.get('analytic-partition-property-typed-empty');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, plain.columns);
  assert.deepEqual(JSON.parse(successes[0].text), program);
  assert.deepEqual(program.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(program.stages[1].steps[1],
    {derive: {partition: {property: {value: {field: 'payload'}, name: 'bucket'}}}});
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size, successes.length + refusals.length);
});

test('partition properties are in the normal packed corpus as well as the focused selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...analyticPartitionPropertySuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...analyticPartitionPropertyRefusals)'));
  assert.ok(fixture.includes('analyticPartitionPropertyOnly ? {successes: analyticPartitionPropertySuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_PARTITION_PROPERTY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-partition-property-source-input.mjs', 'analytic-partition-property-source-input.mjs']"));
});
