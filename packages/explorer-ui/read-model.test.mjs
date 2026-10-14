import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {connectInProcess} from '../sdk/host-port.mjs';
import {startExplorerGateway} from '../explorer/gateway.mjs';
import {createExplorerBrowserSource} from '../explorer/browser-source.mjs';
import {createReadEpoch, describeExistingResult, planReadModel,
  readExistingRun, readExistingRunPlan, readStaticPlan} from './read-model.mjs';

// Independent semantic fixture, not compiler output or public acceptance.
const cid = unit => `sha256:${unit.repeat(64)}`;
const sealed = body => ({...body, self_cid: `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`});
function fixture() {
  const plan = cid('a'), carrier = cid('b');
  const key = ordinal => sealed({version: 'actql-logical-step-key/0.1',
    compiled_plan_cid: plan, stage_ordinal: 0,
    occurrence: {kind: 'operation', operation_ordinal: ordinal}});
  const step = (ordinal, operator) => ({step_id: key(ordinal).self_cid,
    key: key(ordinal), names: [`e\u0301\r\n-${ordinal}`], operator, ports: [],
    can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed'});
  const producer = step(0, 'values'), join = step(1, 'join');
  const port = (node, role, ordinal, source) => ({port_id: sealed({
    version: 'actql-logical-port-key/0.1', compiled_plan_cid: plan,
    step_id: node.step_id, role, port_ordinal: ordinal}).self_cid,
  role, port_ordinal: ordinal, carrier: 'relation', carrier_contract_cid: carrier,
  source, can_sample: false, sample_reason: 'not_installed'});
  const output = port(producer, 'output', 0, {kind: 'logical_output',
    step_id: producer.step_id, output_port_id: cid('c')});
  // Bind the output's self locator to the exact original port.
  output.source.output_port_id = output.port_id;
  producer.ports.push(output);
  for (const ordinal of [0, 1]) join.ports.push(port(join, 'input', ordinal,
    {kind: 'logical_output', step_id: producer.step_id,
      output_port_id: output.port_id}));
  const joined = port(join, 'output', 0,
    {kind: 'logical_output', step_id: join.step_id, output_port_id: cid('d')});
  joined.source.output_port_id = joined.port_id;
  join.ports.push(joined);
  return {version: 'actql-plan-view/0.1', compiled_plan_cid: plan,
    logical_map: sealed({version: 'actql-logical-map/0.1', compiled_plan_cid: plan,
      program_definition_cid: cid('e'), steps: [producer, join]}),
    observation: 'static', provider_io: 0, quantities: [], capabilities: {
      static_plan: true, inspect: true, durable_control: false,
      sample_capture: [], full_intermediate_retention: [], cost_guard: false,
      execution_batch: false, policy_revision_cid: cid('f')}};
}
const ticket = () => createReadEpoch().capture();
const ref = () => ({namespaceId: 'original', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')});

test('both Join roles retain exact original ports when one producer is shared', () => {
  const view = fixture(), [producer, join] = view.logical_map.steps;
  const model = planReadModel(view);
  assert.deepEqual(model.edges, [0, 1].map(ordinal => ({
    id: join.ports[ordinal].port_id, sourceStepId: producer.step_id,
    sourcePortId: producer.ports[0].port_id, targetStepId: join.step_id,
    targetPortId: join.ports[ordinal].port_id, targetPortOrdinal: ordinal})));
  assert.equal(model.logicalMapCid, view.logical_map.self_cid);
  assert.equal(model.nodes[0].names[0], 'e\u0301\r\n-0');
  assert.equal(model.providerIO, 0);
  assert.deepEqual(model.sourceOrigins, {state: 'unavailable', reason: 'not_in_projection'});
});

test('array order is not a producer relation or execution order', () => {
  const view = fixture(), before = planReadModel(view).edges;
  view.logical_map.steps.reverse();
  assert.deepEqual(planReadModel(view).edges, before);
});

test('equal operator labels retain distinct original occurrence identities', () => {
  const view = fixture();
  view.logical_map.steps[1].operator = 'values';
  const model = planReadModel(view);
  assert.equal(model.nodes.length, 2);
  assert.notEqual(model.nodes[0].id, model.nodes[1].id);
});

test('Stage input remains its exact unresolved locator without fabricated Source or Compute', () => {
  const view = fixture(), input = view.logical_map.steps[1].ports[0];
  input.source = {kind: 'stage_input', stage_ordinal: 3, input_port_ordinal: 7};
  const model = planReadModel(view);
  assert.deepEqual(model.inputs, [{stepId: view.logical_map.steps[1].step_id,
    inputPortId: input.port_id, locator: input.source}]);
  assert.equal(model.nodes.length, 2);
  assert.equal(model.edges.length, 1);
});

for (const field of ['step_id', 'output_port_id', 'carrier_contract_cid']) {
  test(`foreign ${field} refuses instead of inventing an edge`, () => {
    const view = fixture(), input = view.logical_map.steps[1].ports[0];
    if (field === 'carrier_contract_cid') input[field] = cid('0');
    else input.source[field] = cid('0');
    assert.throws(() => planReadModel(view), {code: 'ExplorerUnresolvedPort'});
  });
}

test('finite presentation overflow refuses the complete map instead of truncation', () => {
  const view = fixture();
  view.logical_map.steps = Array(257).fill(view.logical_map.steps[0]);
  assert.throws(() => planReadModel(view), {code: 'ExplorerMapLimit'});
});

test('a returned read model cannot be changed by later caller mutation', () => {
  const view = fixture(), model = planReadModel(view), original = model.nodes[0].names[0];
  view.logical_map.steps[0].names[0] = 'changed';
  assert.equal(model.nodes[0].names[0], original);
  assert(Object.isFrozen(model.nodes[0].ports[0].source));
});

test('static read calls only the public Plan API with unchanged Host projection limits', async () => {
  const calls = [], client = {plan(input, options) {
    calls.push({input, options}); return fixture();
  }};
  await readStaticPlan(client, 'SELECT 1 AS n', {format: 'sql'}, ticket());
  assert.deepEqual(calls, [{input: 'SELECT 1 AS n', options: {
    format: 'sql', maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}}]);
});

test('static read preserves tighter caller bounds and unrelated Plan options', async () => {
  const signal = new AbortController().signal;
  const options = {format: 'sql', maxWireBytes: 1024, maxNodes: 32,
    maxDepth: 4, signal, parameters: {n: 1}};
  const before = {...options}, calls = [];
  await readStaticPlan({plan(input, selected) {
    calls.push(selected); return fixture();
  }}, 'SELECT 1 AS n', options, ticket());
  assert.deepEqual(calls, [before]);
  assert.deepEqual(options, before);
});

test('static read caps larger caller bounds at the finite projection ceilings', async () => {
  const calls = [];
  await readStaticPlan({plan(input, options) {
    calls.push(options); return fixture();
  }}, 'SELECT 1 AS n', {maxWireBytes: 65537, maxNodes: 10001,
    maxDepth: 65}, ticket());
  assert.deepEqual(calls, [{maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]);
});

test('static read never coerces invalid bounds before existing SDK admission', async () => {
  for (const value of [null, '4', NaN, Infinity, 1.5, -1, 0]) {
    const options = {maxWireBytes: value, maxNodes: value, maxDepth: value};
    const calls = [];
    await readStaticPlan({plan(input, selected) {
      calls.push(selected); return fixture();
    }}, 'SELECT 1 AS n', options, ticket());
    assert.deepEqual(calls, [options]);
  }
});

test('a delayed old-scope Plan reply and old-scope 401 are both discarded', async () => {
  for (const failed of [false, true]) {
    const epoch = createReadEpoch(), original = epoch.capture();
    const client = {async plan() {
      epoch.invalidate();
      if (failed) throw Object.assign(new Error('OldSessionEnded'), {status: 401});
      return fixture();
    }};
    await assert.rejects(readStaticPlan(client, {}, {}, original), {code: 'ExplorerStaleScope'});
    epoch.capture().assertCurrent();
  }
});

test('old installed cohort without Plan capability remains unavailable without fallback', async () => {
  await assert.rejects(readStaticPlan({}, {}, {}, ticket()), {code: 'ExplorerCapabilityUnavailable'});
});

test('existing Run reads only original attach and inspect, with immutable requested reference', async () => {
  const original = ref(), expected = {...original}, calls = [], view = {marker: 'fixture'};
  const client = {async attach(selected) {
    original.runDefinitionCid = cid('f');
    calls.push(['attach', selected]);
    return {inspect(limits) {calls.push(['inspect', limits]); return view;}};
  }};
  assert.equal(await readExistingRun(client, original, ticket()), view);
  assert.deepEqual(calls, [['attach', expected], ['inspect', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
});

test('scope switch during attach prevents any following inspect', async () => {
  const epoch = createReadEpoch(); let inspections = 0;
  const client = {async attach() {epoch.invalidate();
    return {inspect() {inspections++;}};
  }};
  await assert.rejects(readExistingRun(client, ref(), epoch.capture()), {code: 'ExplorerStaleScope'});
  assert.equal(inspections, 0);
});

test('saved Run Plan uses only exact original attach and Run.plan with frozen reference', async () => {
  const original = ref(), expected = {...original}, calls = [], view = fixture();
  const client = {attach(selected) {
    calls.push(['attach', selected]); original.namespaceId = 'changed';
    return {plan(limits) {calls.push(['run-plan', limits]);
      return {version: 'actql-run-plan-view/0.1', run_ref: expected, plan_view: view};}};
  }, plan() {assert.fail('no recompile fallback');}, start() {assert.fail('no Run');}};
  const observed = await readExistingRunPlan(client, original, ticket());
  assert.deepEqual(observed.runRef, expected);
  assert(Object.isFrozen(observed.runRef));
  assert.equal(observed.plan.compiledPlanCid, view.compiled_plan_cid);
  assert.equal(observed.plan.logicalMapCid, view.logical_map.self_cid);
  assert.equal(observed.plan.nodes[0].id, view.logical_map.steps[0].step_id);
  assert.deepEqual(calls, [['attach', expected], ['run-plan', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
});

test('saved Run Plan refuses each foreign Run reference dimension and malformed envelope', async () => {
  const expected = ref();
  const good = {version: 'actql-run-plan-view/0.1', run_ref: expected, plan_view: fixture()};
  for (const bad of [
    {...good, run_ref: {...expected, namespaceId: 'foreign'}},
    {...good, run_ref: {...expected, authorityScopeCid: cid('c')}},
    {...good, run_ref: {...expected, runDefinitionCid: cid('c')}},
    {...good, version: 'foreign'},
    {...good, extra: true},
    {...good, plan_view: {...good.plan_view, compiled_plan_cid: cid('c')}},
  ]) {
    await assert.rejects(readExistingRunPlan({attach() {return {plan() {return bad;}};}},
      expected, ticket()), error => ['ExplorerInvalidRunPlan', 'ExplorerInvalidPlan'].includes(error.code));
  }
});

test('old missing saved plan never recompiles or starts replacement business work', async () => {
  let replans = 0;
  const client = {attach() {return {};}, plan() {replans++;}};
  await assert.rejects(readExistingRunPlan(client, ref(), ticket()),
    {code: 'ExplorerCapabilityUnavailable'});
  const unavailable = Object.assign(new Error('LegacyMissing'), {code: 'OriginalPlanUnavailable'});
  client.attach = () => ({plan() {throw unavailable;}});
  await assert.rejects(readExistingRunPlan(client, ref(), ticket()), error => error === unavailable);
  assert.equal(replans, 0);
});

test('saved plan discards delayed old-scope success and denial', async () => {
  for (const failed of [false, true]) {
    const epoch = createReadEpoch(), original = epoch.capture();
    const client = {attach() {return {async plan() {
      epoch.invalidate();
      if (failed) throw Object.assign(new Error('old scope'), {status: 401});
      return {version: 'actql-run-plan-view/0.1', run_ref: ref(), plan_view: fixture()};
    }};}};
    await assert.rejects(readExistingRunPlan(client, ref(), original), {code: 'ExplorerStaleScope'});
    epoch.capture().assertCurrent();
  }
});

test('Named Result description uses no payload reader or grant/open operation', async () => {
  const calls = [], description = {marker: 'independent metadata fixture'};
  const client = {attach(original) {calls.push(['attach', original]);
    return {result(name) {calls.push(['result', name]);
      return {describe() {calls.push(['describe']); return description;},
        rows() {assert.fail('no payload open');}};}};
  }};
  assert.equal(await describeExistingResult(client, ref(), 'e\u0301\r\n', ticket()), description);
  assert.deepEqual(calls, [['attach', ref()], ['result', 'e\u0301\r\n'], ['describe']]);
});

test('public SDK facade admits original Plan and Run wire without submitting any business work', async t => {
  // The actual SDK/wire boundary is used; the endpoint remains a semantic
  // fixture, not a Compiler/Run Owner or a packed public Host acceptance.
  const calls = [], reference = ref(), view = fixture();
  view.logical_map.steps[0].names = ['producer'];
  view.logical_map.steps[1].names = ['joined'];
  const {self_cid: _previous, ...map} = view.logical_map;
  view.logical_map = sealed(map);
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'explorer-fixture', capabilities: [], limits: {
      maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 2048}};
  const runView = {version: 'actql-run-view/0.1', run_ref: reference,
    run_state: {version: 'actql-controlled-run-state/0.1', run_id: 'original',
      status: 'succeeded', updated_at: '2026-10-11T00:00:00.000Z', control_revision: 1},
    compiled_plan_cid: null, logical_map_cid: null, consistency: 'non_atomic',
    observation_scope: 'owner_local', components: [], quantities: [],
    sample: {state: 'unavailable', reason: 'not_supported'},
    available_operations: ['inspect'], capabilities: view.capabilities};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'plan') return view;
      if (operation === 'attach') return {ref: reference, durability: 'volatile', revision: 1};
      if (operation === 'inspect-run') return runView;
      if (operation === 'run-plan') return {version: 'actql-run-plan-view/0.1',
        run_ref: reference, plan_view: view};
      assert.fail(`Unexpected business operation: ${operation}`);
    },
  });
  t.after(() => client.close());
  const model = await readStaticPlan(client, 'SELECT 1 AS n', {format: 'sql'}, ticket());
  assert.equal(model.logicalMapCid, view.logical_map.self_cid);
  assert.equal(model.providerIO, 0);
  assert.deepEqual(await readExistingRun(client, reference, ticket()), runView);
  const saved = await readExistingRunPlan(client, reference, ticket());
  assert.equal(saved.plan.logicalMapCid, view.logical_map.self_cid);
  assert.deepEqual(calls, ['connect', 'plan', 'attach', 'inspect-run', 'attach', 'run-plan']);
  for (const name of ['maxWireBytes', 'maxNodes', 'maxDepth']) {
    for (const value of ['4', NaN, Infinity, 1.5, -1, 0]) {
      await assert.rejects(readStaticPlan(client, 'SELECT 1 AS n',
        {format: 'sql', [name]: value}, ticket()),
      Number.isNaN(value) || value === Infinity
        ? {name: 'TypeError', message: 'UnrepresentableClientNumber'}
        : {code: 'InvalidClientPlanRequest'});
    }
  }
  assert.deepEqual(calls, ['connect', 'plan', 'attach', 'inspect-run', 'attach', 'run-plan']);
  const gateway = await startExplorerGateway({client}); let cookie;
  const browser = createExplorerBrowserSource({origin: gateway.origin,
    async fetch(url, options) {
      const response = await fetch(url, {...options, headers: {...options.headers,
        Origin: gateway.origin, ...(cookie ? {Cookie: cookie} : {})}});
      const installed = response.headers.get('set-cookie');
      if (installed) cookie = installed.split(';')[0];
      return response;
    }});
  try {
    await browser.connect(gateway.issueBootstrap().bootstrap);
    const throughGateway = await browser.runPlan(reference);
    assert.deepEqual(throughGateway.runRef, reference);
    assert.equal(throughGateway.plan.logicalMapCid, view.logical_map.self_cid);
    assert.deepEqual(throughGateway.plan.edges, saved.plan.edges);
    assert.deepEqual(calls.slice(6), ['attach', 'run-plan']);
  } finally {browser.close(); await gateway.close();}
});
