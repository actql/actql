import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticOrderObjectReproduction, analyticOrderSuccesses, analyticOrderRefusals, analyticOrderExecutionFailures}
  from './fixtures/analytic-order-source-input.mjs';
import {analyticPropertySuccesses, analyticPropertyRefusals}
  from './fixtures/analytic-property-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';
import {analyticOffsetSuccesses, analyticOffsetRefusals}
  from './fixtures/analytic-offset-source-input.mjs';
import {aggregatePropertySuccesses, aggregatePropertyRefusals}
  from './fixtures/aggregate-property-source-input.mjs';
import {joinPropertySuccesses, joinPropertyRefusals}
  from './fixtures/join-property-source-input.mjs';

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
  for (const stem of ['analytic-order', 'analytic-property', 'aggregate-property', 'subgraph', 'join-property']) {
    assert.ok(driver.includes(`['scripts/fixtures/${stem}-source-input.mjs', '${stem}-source-input.mjs']`));
    assert.ok(driver.includes(`process.argv.includes('--${stem}-only')`));
    assert.ok(fixture.includes(`ACTQL_TEST_${stem.replaceAll('-', '_').toUpperCase()}_ONLY`));
  }
  assert.ok(driver.includes("['scripts/fixtures/public-query-profiles.mjs', 'public-query-profiles.mjs']"));
  assert.ok(fixture.includes('of publicQueryProfiles(scopeInputs)'));
  assert.ok(driver.includes("process.argv.includes('--analytic-profiles-only')"));
  assert.ok(fixture.includes('ACTQL_TEST_ANALYTIC_PROFILES_ONLY'));
});

test('original object JSON reproduction retains independent rows, types and declared profile', async () => {
  const text = await readFile(new URL('../docs/reviews/fixtures/analytic-order-property-repro.program.json', import.meta.url), 'utf8');
  const expected = JSON.parse(await readFile(new URL('../docs/reviews/fixtures/analytic-order-property-repro.expected.json', import.meta.url), 'utf8'));
  const input = JSON.parse(await readFile(new URL('../docs/reviews/fixtures/analytic-order-property-repro.input.json', import.meta.url), 'utf8'));
  const fixture = analyticOrderObjectReproduction(text);
  assert.equal(fixture.text, text, 'the original emitted Program must not be rewritten');
  assert.equal(fixture.format, 'json');
  assert.equal(fixture.hostProfile, 'analytic-order');
  assert.equal(fixture.parameterDeclarations, undefined, 'machine Program owns its declarations');
  assert.deepEqual(fixture.parameters, input.parameters);
  assert.deepEqual(fixture.expected, expected.rows);
  assert.deepEqual(fixture.columns, expected.columns);
  assert.equal(JSON.parse(text).stages[0].steps.length, 17);
  const groups = publicQueryProfiles({...inputs, successes: [...inputs.successes, fixture]});
  const order = groups.find(item => item.name === 'analytic-order');
  assert.equal(order.inputs.successes.length, 11);
  assert.deepEqual(order.capacity, capacity(1048576));
});


test('ORDER OFFSET and property corpora stay independent in one mixed run', () => {
  const combined = {
    successes: [...inputs.successes, ...analyticOffsetSuccesses,
      ...aggregatePropertySuccesses, ...joinPropertySuccesses],
    refusals: [...inputs.refusals, ...analyticOffsetRefusals,
      ...aggregatePropertyRefusals, ...joinPropertyRefusals],
    executionFailures: [...inputs.executionFailures],
  };
  const before = structuredClone(combined);
  const groups = publicQueryProfiles(combined);
  assert.deepEqual(groups.map(group => group.name), [
    'analytic-order', 'analytic-property', 'analytic-offset', 'standard',
  ]);
  for (const group of groups) {
    const wide = group.name === 'analytic-order' || group.name === 'analytic-offset';
    assert.deepEqual(group.capacity, capacity(wide ? 1048576 : 10000));
    assert.equal(Object.isFrozen(group.capacity), true);
    assert.throws(() => { group.capacity.max_analytic_input_wire_bytes = 1048576; }, TypeError);
    assert.equal(Object.hasOwn(group.capacity, 'max_execution_bytes'), false);
    for (const kind of ['successes', 'refusals', 'executionFailures']) {
      assert.deepEqual(group.inputs[kind], combined[kind]
        .filter(item => (item.hostProfile ?? 'standard') === group.name));
    }
  }
  for (const kind of ['successes', 'refusals', 'executionFailures']) {
    const selected = groups.flatMap(group => group.inputs[kind]);
    assert.equal(selected.length, combined[kind].length);
    for (const item of combined[kind]) assert.equal(selected.filter(x => x === item).length, 1);
  }
  assert.deepEqual(combined, before, 'profile grouping cannot rewrite expected rows or inputs');
});

test('combined packed selection registers every analytic corpus and isolates mutable state', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const selected = fixture.slice(fixture.indexOf('const scopeInputs = analyticProfilesOnly'),
    fixture.indexOf(': analyticOrderOnly'));
  for (const name of ['analyticOrderInputs', 'analyticPropertySuccesses', 'analyticOffsetSuccesses',
    'analyticOrderRefusals', 'analyticPropertyRefusals', 'analyticOffsetRefusals',
    'analyticOrderExecutionFailures']) assert.ok(selected.includes(name), name);
  for (const path of ['local-state${suffix}', 'remote-state${suffix}',
    'records${suffix}.duckdb', 'source-profile${suffix}.json']) {
    assert.ok(fixture.includes('resolve(`' + path + '`)'), path);
  }
  assert.ok(fixture.includes("profileName === 'standard' ? '' : `-${profileName}`"));
  assert.ok(fixture.includes('...base.host_policy_profile.capacity, ...analyticCapacity'));
  for (const suite of ['analytic-offset-profiles', 'public-query-profiles']) {
    assert.ok(driver.includes(`'scripts/${suite}.test.mjs'`), suite);
  }
});
