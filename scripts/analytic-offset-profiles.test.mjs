import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticOffsetProgram, analyticOffsetSuccesses, analyticOffsetRefusals}
  from './fixtures/analytic-offset-source-input.mjs';
import {analyticPropertySuccesses, analyticPropertyRefusals}
  from './fixtures/analytic-property-source-input.mjs';
import {aggregatePropertySuccesses, aggregatePropertyRefusals}
  from './fixtures/aggregate-property-source-input.mjs';
import {joinPropertySuccesses, joinPropertyRefusals}
  from './fixtures/join-property-source-input.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

const capacity = bytes => ({max_analytic_frame_memberships: 10000,
  max_analytic_input_wire_bytes: bytes, max_analytic_output_wire_bytes: bytes,
  max_analytic_partition_wire_bytes: bytes});
const standard = {
  successes: [...analyticPropertySuccesses, ...aggregatePropertySuccesses,
    ...joinPropertySuccesses],
  refusals: [...analyticPropertyRefusals, ...aggregatePropertyRefusals,
    ...joinPropertyRefusals],
};
const combined = {
  successes: [...standard.successes, ...analyticOffsetSuccesses],
  refusals: [...standard.refusals, ...analyticOffsetRefusals],
};

test('OFFSET and existing analytic aggregate JOIN cases retain separate installed ceilings', () => {
  const before = structuredClone(combined);
  const groups = publicQueryProfiles(combined);
  assert.equal(groups.length, 3);
  const ordinary = groups.find(item => item.name === 'standard');
  const offset = groups.find(item => item.name === 'analytic-offset');
  const property = groups.find(item => item.name === 'analytic-property');
  assert.deepEqual(ordinary.capacity, capacity(10000));
  assert.deepEqual(offset.capacity, capacity(1048576));
  assert.deepEqual(property.capacity, capacity(10000));
  assert.deepEqual(property.inputs, {successes: analyticPropertySuccesses,
    refusals: analyticPropertyRefusals, executionFailures: []});
  assert.deepEqual(ordinary.inputs, {
    successes: [...aggregatePropertySuccesses, ...joinPropertySuccesses],
    refusals: [...aggregatePropertyRefusals, ...joinPropertyRefusals],
    executionFailures: []});
  assert.deepEqual(offset.inputs, {successes: analyticOffsetSuccesses,
    refusals: analyticOffsetRefusals, executionFailures: []});
  assert.equal(offset.inputs.successes.length, 5);
  assert.equal(offset.inputs.refusals.length, 9);
  for (const group of groups) {
    assert.equal(Object.hasOwn(group.capacity, 'max_execution_bytes'), false);
    for (const kind of ['successes', 'refusals']) {
      for (const item of group.inputs[kind]) assert.ok(combined[kind].includes(item));
    }
  }
  assert.deepEqual(combined, before, 'grouping preserves authored inputs and expectations');
  for (const kind of ['successes', 'refusals']) {
    const selected = groups.flatMap(group => group.inputs[kind]);
    assert.equal(new Set(selected).size, combined[kind].length);
    for (const item of combined[kind]) assert.equal(selected.filter(x => x === item).length, 1);
  }
});

test('OFFSET-only selection never brings unrelated cases or an execution budget override', () => {
  const [group] = publicQueryProfiles({successes: analyticOffsetSuccesses,
    refusals: analyticOffsetRefusals});
  assert.equal(group.name, 'analytic-offset');
  assert.deepEqual(group.capacity, capacity(1048576));
  assert.deepEqual(publicQueryProfiles({successes: []}), []);
  assert.throws(() => publicQueryProfiles({refusals: [{hostProfile: 'typo'}]}),
    /Unknown public query profile: typo/u);
});

test('machine control and authored result contracts remain independent fixed fixtures', async () => {
  const expectedProgram = JSON.parse(await readFile(new URL(
    '../docs/reviews/fixtures/analytic-offset.expected.program.json', import.meta.url), 'utf8'));
  assert.deepEqual(analyticOffsetProgram, expectedProgram);
  const fixtures = JSON.parse(await readFile(new URL(
    '../docs/reviews/fixtures/analytic-offset.expected.json', import.meta.url), 'utf8'));
  for (const fixture of analyticOffsetSuccesses) {
    const expected = fixtures.find(item => item.name === fixture.name);
    assert.ok(expected, fixture.name);
    assert.deepEqual(fixture.expected, expected.expected);
    assert.deepEqual(fixture.columns, expected.columns);
  }
});

test('packed selection and normal corpus retain OFFSET plus current main routes', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [stem, variable] of [['analytic-offset', 'analyticOffset'],
    ['analytic-frame-parameter', 'analyticFrameParameter'], ['grouped-in', 'groupedIn'],
    ['analytic-property', 'analyticProperty'], ['aggregate-property', 'aggregateProperty'],
    ['join-property', 'joinProperty']]) {
    assert.ok(driver.includes(`['scripts/fixtures/${stem}-source-input.mjs', '${stem}-source-input.mjs']`));
    assert.ok(driver.includes(`process.argv.includes('--${stem}-only')`));
    assert.ok(fixture.includes(`ACTQL_TEST_${stem.replaceAll('-', '_').toUpperCase()}_ONLY`));
    assert.match(fixture, new RegExp(`const scopeOnly = .*${variable}Only`));
    assert.ok(fixture.includes(`${variable}Only ? {successes: ${variable}Successes, refusals: ${variable}Refusals}`));
    assert.ok(fixture.includes(`scopeInputs.successes.push(...${variable}Successes)`));
    assert.ok(fixture.includes(`scopeInputs.refusals.push(...${variable}Refusals)`));
  }
  assert.ok(driver.includes("['scripts/fixtures/public-query-profiles.mjs', 'public-query-profiles.mjs']"));
  assert.ok(fixture.includes('of publicQueryProfiles(scopeInputs)'));
  assert.ok(fixture.includes("profileName === 'standard' ? '' : `-${profileName}`"));
});
