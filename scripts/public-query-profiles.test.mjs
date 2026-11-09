import './unnest-source-input.test.mjs';
import {encodeRetainedFixture, decodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
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
import {sourceGraphMemberSuccesses, sourceGraphMemberRefusals}
  from './fixtures/source-graph-member-input.mjs';

import {unnestRefusals} from './fixtures/unnest-source-input.mjs';
import {windowScalarRefusals} from './fixtures/window-scalar-source-input.mjs';
import {groupSelectScopeRefusals} from './fixtures/group-select-scope-source-input.mjs';
import {distinctOrderRefusals} from './fixtures/distinct-order-source-input.mjs';
import {distinctOrderMemberRefusals} from './fixtures/distinct-order-member-source-input.mjs';

const inputs = {successes: [...analyticOrderSuccesses, ...analyticPropertySuccesses],
  refusals: [...analyticOrderRefusals, ...analyticPropertyRefusals],
  executionFailures: analyticOrderExecutionFailures};
const capacity = bytes => ({max_analytic_frame_memberships: 10000,
  max_analytic_input_wire_bytes: bytes, max_analytic_output_wire_bytes: bytes,
  max_analytic_partition_wire_bytes: bytes});

test('Source Graph member strict comparison refines its empty output without changing nullable inputs', () => {
  const empty = sourceGraphMemberSuccesses.find(item => item.name === 'source-graph-member-typed-empty');
  assert.match(empty.text, /WHERE a\.payload\.SCORE > 100 \|> SELECT/u);
  assert.deepEqual(empty.results.matched, {rows: [], columns: [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'score', contract: {type: 'number', nullable: false}},
  ]});
  assert.equal(empty.parameterDeclarations.p3.nullable, true);
  assert.equal(empty.parameterDeclarations.p4.fields.score.nullable, true);
  assert.equal(empty.parameters.p3, null);
  assert.deepEqual(empty.parameters.p4, {score: null});
  for (const item of sourceGraphMemberSuccesses.filter(item => item !== empty)) {
    assert.equal(item.results.matched.columns[1].contract.nullable, true, item.name);
  }
  const nulls = sourceGraphMemberSuccesses.find(item =>
    item.name === 'source-graph-member-null-receiver-and-member');
  assert.deepEqual(nulls.results.matched.rows, [{id: 3, score: null}, {id: 4, score: null}]);
});

test('Source Graph member refinement preserves the original Source inventory and refusal coordinates', () => {
  assert.equal(sourceGraphMemberSuccesses.length, 7);
  const originalRows = [{id: 2, amount: 10}, {id: 1, amount: 20},
    {id: 3, amount: null}, {id: 4, amount: 40}, {id: 0, amount: 99}];
  for (const item of sourceGraphMemberSuccesses) {
    assert.deepEqual(item.sourceRows, originalRows);
    assert.equal(item.sourceReadSessionCount, 1);
  }
  assert.deepEqual(sourceGraphMemberRefusals.map(item => item.name), [
    'source-graph-member-invalid-missing-member', 'source-graph-member-invalid-scalar-receiver',
    'source-graph-member-invalid-removed-receiver', 'source-graph-member-invalid-same-select-alias',
  ]);
  for (const item of sourceGraphMemberRefusals) assert.deepEqual(item.sourceRows, originalRows);
});

test('Source Graph member selection is narrow while the normal corpus retains its cases', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const start = driver.indexOf('const narrowPublicQuery =');
  const end = driver.indexOf('.includes(flag));', start);
  assert.ok(start >= 0 && end > start);
  assert.ok(driver.slice(start, end).includes("'--source-graph-member-only'"),
    'the explicit selection must not start the independent Planner/Effect campaigns');
  const sourceEnd = driver.indexOf("if (process.argv.includes('--source-graph-member-only')) return;", end);
  // Defining the shared restart helper performs no I/O. Pin its actual
  // unrelated String invocation, not the retained Graph helper's definition.
  const restart = driver.indexOf('await exerciseRetainedQueryRestart();', end);
  const acceptance = driver.indexOf("['packed-query-transports.mjs']", end);
  assert.ok(acceptance >= 0 && sourceEnd > acceptance && restart > sourceEnd,
    'finish Source acceptance before any unrelated retained String restart');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('scopeInputs.successes.push(...sourceGraphMemberSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...sourceGraphMemberRefusals)'));
  assert.ok(driver.includes("['scripts/fixtures/source-graph-member-input.mjs', 'source-graph-member-input.mjs']"));
});

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
  const start = fixture.indexOf('analyticProfilesOnly ? {');
  const end = fixture.indexOf(': analyticOrderOnly', start);
  assert.ok(start >= 0 && end > start, 'combined analytic branch must exist');
  const selected = fixture.slice(start, end);
  for (const name of ['analyticOrderInputs', 'analyticPropertySuccesses', 'analyticOffsetSuccesses',
    'analyticOrderRefusals', 'analyticPropertyRefusals', 'analyticOffsetRefusals',
    'analyticOrderExecutionFailures']) assert.ok(selected.includes(name), name);
  for (const path of ['local-state${suffix}', 'remote-state${suffix}']) {
    assert.ok(fixture.includes('resolve(`' + path + '`)'), path);
  }
  assert.ok(fixture.includes("profileName === 'standard' ? '' : `-${profileName}`"));
  assert.ok(fixture.includes('const {database, sourceProfilePath} = sourceFixturePaths(transport, profileName);'));
  assert.ok(fixture.includes('...base.host_policy_profile.capacity, ...analyticCapacity'));
  for (const suite of ['analytic-offset-profiles', 'public-query-profiles']) {
    assert.ok(driver.includes(`'scripts/${suite}.test.mjs'`), suite);
  }
});


test('packed analytic profiles are selected explicitly by both Host entrances', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('const hostCapacityPolicy = {...base.host_policy_profile.capacity, ...analyticCapacity};'));
  assert.ok(fixture.includes('environment.host_policy_profile = {...base.host_policy_profile, capacity: hostCapacityPolicy};'));
  assert.ok(fixture.includes('installation: {directory: localDirectory, sourceProfilePath, hostCapacityPolicy}'));
  assert.ok(fixture.includes('const directory = cohortDirectory(localDirectory, index);'));
  assert.ok(fixture.includes('const directory = cohortDirectory(remoteDirectory, index);'));
  assert.ok(fixture.includes('installation: {directory,\n      sourceProfilePath, hostCapacityPolicy,'));
  assert.equal(fixture.match(/const authorization = graphRemainingOperationsOnly \|\| inputStageResultOnly \|\| typedSubscriptOnly\s*\? createRetainedGraphAuthorization\(\) : undefined;/g)?.length, 2,
    'observer credentials are limited to explicit Graph, input-only or typed-subscript cohorts on both Hosts');
  assert.ok(fixture.includes('directory, sourceProfilePath, hostCapacityPolicy,'));
});

// This independent Carrier refusal policy runs in ordinary packed preflight.
import './graph-invalid-carrier-source-input.test.mjs';


test('semantic refusal fixtures retain 21 exact invalid-input policies', () => {
  const refusals = [...unnestRefusals, ...windowScalarRefusals, ...joinPropertyRefusals,
    ...groupSelectScopeRefusals, ...distinctOrderRefusals, ...distinctOrderMemberRefusals];
  // These names are independently authored from the scope and offset contracts.
  // The normal packed preflight checks them without running the product lowerer.
  const invalid = [
    'unnest-refusal-ordinal-outside-actual-columns',
    'unnest-refusal-ordinal-without-offset',
    'unnest-refusal-ordinal-after-drop',
    'window-scalar-refuse-aggregate-operand-row-offset',
    'join-property-invalid-4',
    'group-select-scope-numeric-distinct-unselected',
    'distinct-order-unselected-0',
    'distinct-order-unselected-1',
    'distinct-order-unselected-2',
    'distinct-order-join-unselected-0',
    'distinct-order-join-unselected-1',
    'distinct-order-join-unselected-2',
    'order-receiver-unselected-0',
    'order-receiver-unselected-1',
    'order-receiver-unselected-2',
    'order-receiver-unselected-3',
    'distinct-order-member-unselected-0',
    'distinct-order-member-unselected-1',
    'distinct-order-member-unselected-2',
    'distinct-order-member-unselected-3',
    'distinct-order-member-unselected-4',
  ];
  assert.equal(invalid.length, 21);
  assert.equal(new Set(invalid).size, 21);
  for (const name of invalid) {
    const matches = refusals.filter(value => value.name === name);
    assert.equal(matches.length, 1, name);
    assert.equal(matches[0].expectedCode, 'ClientProgramInvalidInput', name);
  }
  assert.equal(windowScalarRefusals.find(value => value.name ===
    'window-scalar-refuse-aggregate-operand-missing-frame').expectedCode,
  'ClientProgramImplementationLimit', 'the valid missing-frame connection remains unsupported');
  const unsafe = groupSelectScopeRefusals.find(value => value.name ===
    'group-select-scope-numeric-unsafe-integer');
  assert.equal(Object.hasOwn(unsafe, 'expectedCode'), false,
    'the unrelated unsafe-integer refusal policy remains unchanged');
});

// Independent fixed vectors for persisted authored inputs/oracles. These do not
// use observed product rows, the cohort partition helper or generated expected wire.
test('retained fixture transport preserves explicit undefined and literal tag-shaped values', () => {
  const source = {parameterDeclarations: undefined, parameters: {x: undefined},
    expected: [{tag: ['undefined'], value: {type: 'undefined'}}]};
  const wire = '[["parameterDeclarations",["undefined"]],["parameters",["object",[["x",["undefined"]]]]],["expected",["array",[["object",[["tag",["array",[["string","undefined"]]]],["value",["object",[["type",["string","undefined"]]]]]]]]]]]';
  const expectedWire = '["retained-fixture-values/0.1",["object",' + wire + ']]';
  assert.equal(encodeRetainedFixture(source), expectedWire);
  assert.deepEqual(decodeRetainedFixture(expectedWire), source);
  assert.equal(Object.hasOwn(decodeRetainedFixture(expectedWire), 'parameterDeclarations'), true);
});

test('retained fixture transport preserves numeric values, array undefined and own prototype-shaped keys', () => {
  const source = [undefined, null, -0, NaN, Infinity, -Infinity, 4n,
    Object.fromEntries([['__proto__', {x: undefined}]])];
  const restored = decodeRetainedFixture(encodeRetainedFixture(source));
  assert.deepEqual(restored, source);
  assert.equal(Object.is(restored[2], -0), true);
  assert.equal(Object.hasOwn(restored[7], '__proto__'), true);
  assert.equal(Object.getPrototypeOf(restored[7]), Object.prototype);
});

test('retained fixture transport rejects hooks without invoking them', () => {
  let reads = 0;
  const getter = {get field() { reads++; return 1; }};
  const hook = {toJSON() { reads++; return {}; }};
  assert.throws(() => encodeRetainedFixture(getter), {message: 'InvalidRetainedFixtureValue'});
  assert.throws(() => encodeRetainedFixture(hook), {message: 'InvalidRetainedFixtureValue'});
  assert.equal(reads, 0);
  assert.throws(() => decodeRetainedFixture('["retained-fixture-values/0.1",["object",[["x",["null"]],["x",["null"]]]]]'),
    {message: 'InvalidRetainedFixtureValue'});
});


test('full corpus pins every authored occurrence independently of worker selection', async () => {
  const pin = JSON.parse(await readFile(new URL('./fixtures/public-query-inventory.json', import.meta.url), 'utf8'));
  assert.equal(pin.sourceBaseline, '76916b2b57ca8e06d9e74099349b17c263ccb411');
  // Retain the accepted 4,221-case corpus, including its five cases missing
  // from the previous pin, then register eleven whole-ARRAY successes, seven
  // refusals and one demanded failure through the active membership selection.
  // SQL signed-zero grouping, membership and ABS follow the canonical-zero rule:
  // each original occurrence moves from refusal to an independent success.
  // All other complete payloads and their relative order remain unchanged.
  // Seven negated-predicate, six membership and four CONCAT DISTINCT scope
  // refusals retain InvalidInput; no refusal predicate or bound is widened.
  // The two invalid statistical forms retain their authored SQL and refusal;
  // their reviewed InvalidInput projection updates only those corpus preimages.
  // The complete Graph WALK keeps its original Program, parameters and twenty-row
  // oracle as a success. Storage sizing does not select a cumulative output cap.
  assert.equal(pin.totalCases, 4240);
  assert.deepEqual(pin.counts, {"successes":2656,"executionFailures":53,"refusals":1531});
  assert.deepEqual(pin.profiles.map(profile => [profile.name, profile.counts]), [["standard",{"successes":2602,"executionFailures":51,"refusals":1492}],["analytic-offset",{"successes":6,"executionFailures":0,"refusals":13}],["analytic-property",{"successes":13,"executionFailures":0,"refusals":7}],["analytic-order",{"successes":35,"executionFailures":2,"refusals":19}]]);
  assert.deepEqual(pin.repeatedFailures, [
    {name: 'graph-subtraction-null-is-not-zero', positions: [29, 49]},
    {name: 'graph-subtraction-conflict-needs-policy', positions: [30, 50]},
  ]);
  const {registeredPublicQueryInventory} = await import('./public-query-inventory.mjs');
  const actual = await registeredPublicQueryInventory();
  for (const key of ['totalCases', 'inventorySha256', 'counts', 'profiles', 'repeatedFailures']) {
    assert.deepEqual(actual[key], pin[key], key);
  }
  const coordinator = await readFile(new URL('./fixtures/packed-query-transports.mjs', import.meta.url), 'utf8');
  assert.ok(coordinator.includes("registered.inventorySha256, 'full worker inventory must match the independent authored pin'"));
});
import './public-query-refusal-classifications.test.mjs';

// These independent fixture policies run in the ordinary packed preflight.
import './graph-refusal-classification-source-input.test.mjs';
import './full-join-scope-source-input.test.mjs';
import './pipe-join-input.test.mjs';

import './unpivot-multicolumn-source-input.test.mjs';

import './group-order-range-alias-source-input.test.mjs';
import './distinct-order-receiver-source-input.test.mjs';
