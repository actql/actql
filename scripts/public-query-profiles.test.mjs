import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticOrderSuccesses, analyticOrderRefusals, analyticOrderExecutionFailures}
  from './fixtures/analytic-order-source-input.mjs';
import {analyticPropertySuccesses, analyticPropertyRefusals}
  from './fixtures/analytic-property-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

const inputs = {successes: [...analyticOrderSuccesses, ...analyticPropertySuccesses],
  refusals: [...analyticOrderRefusals, ...analyticPropertyRefusals],
  executionFailures: analyticOrderExecutionFailures};
const capacity = bytes => ({max_analytic_frame_memberships: 10000,
  max_analytic_input_wire_bytes: bytes, max_analytic_output_wire_bytes: bytes,
  max_analytic_partition_wire_bytes: bytes});

test('combined analytic corpora retain their independent installed ceilings', () => {
  const before = structuredClone(inputs);
  const groups = publicQueryProfiles(inputs);
  assert.equal(groups.length, 2);
  const order = groups.find(item => item.name === 'analytic-order');
  const property = groups.find(item => item.name === 'analytic-property');
  assert.deepEqual(order.capacity, capacity(1048576));
  assert.deepEqual(property.capacity, capacity(10000));
  for (const [group, counts] of [[order, [10, 6, 1]], [property, [12, 7, 0]]]) {
    assert.deepEqual(['successes', 'refusals', 'executionFailures']
      .map(kind => group.inputs[kind].length), counts);
    for (const kind of ['successes', 'refusals', 'executionFailures']) {
      for (const item of group.inputs[kind]) {
        assert.equal(item.hostProfile, group.name);
        assert.ok(inputs[kind].includes(item), 'keep the original independent fixture');
      }
    }
    assert.equal(Object.hasOwn(group.capacity, 'max_execution_bytes'), false);
  }
  assert.ok(order.inputs.successes.some(item => item.name === 'analytic-order-nullable-property-input'));
  assert.deepEqual(inputs, before, 'grouping must not change fixture inputs or expectations');
  assert.deepEqual(publicQueryProfiles(inputs), groups);
});

test('default cases retain main ceilings without inheriting an analytic order profile', () => {
  const ordinary = {name: 'ordinary'};
  const groups = publicQueryProfiles({successes: [ordinary, analyticOrderSuccesses[0]]});
  assert.deepEqual(groups.map(item => [item.name, item.capacity]), [
    ['standard', capacity(10000)], ['analytic-order', capacity(1048576)],
  ]);
  assert.equal(groups[0].inputs.successes[0], ordinary);
  assert.deepEqual(publicQueryProfiles({successes: []}), []);
});

test('unknown profile fails rather than silently using a different envelope', () => {
  assert.throws(() => publicQueryProfiles({refusals: [{name: 'bad', hostProfile: 'typo'}]}),
    /Unknown public query profile: typo/u);
});

test('packed driver retains analytic order, analytic property, aggregate and Subgraph routes', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const stem of ['analytic-order', 'analytic-property', 'aggregate-property', 'subgraph']) {
    assert.ok(driver.includes(`['scripts/fixtures/${stem}-source-input.mjs', '${stem}-source-input.mjs']`));
    assert.ok(driver.includes(`process.argv.includes('--${stem}-only')`));
    assert.ok(fixture.includes(`ACTQL_TEST_${stem.replaceAll('-', '_').toUpperCase()}_ONLY`));
  }
  assert.ok(driver.includes("['scripts/fixtures/public-query-profiles.mjs', 'public-query-profiles.mjs']"));
  assert.ok(fixture.includes('of publicQueryProfiles(scopeInputs)'));
  assert.ok(driver.includes("process.argv.includes('--analytic-profiles-only')"));
  assert.ok(fixture.includes('ACTQL_TEST_ANALYTIC_PROFILES_ONLY'));
});
