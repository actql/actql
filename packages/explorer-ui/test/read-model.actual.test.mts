import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';
import {canonicalJson, connectInProcess} from '../../sdk/host-port.mjs';
import {renderStaticExplanationNarrative} from '../../local-node/explanation-narrative.mjs';
import {startExplorerGateway} from '../../explorer/gateway.mjs';
import {createExplorerBrowserSource} from '../../explorer/browser-source.mjs';
import {createReadEpoch, describeExistingResult, explanationStoryModel, planReadModel, planStoryModel,
  readExistingRun, readExistingRunPlan, readExistingRunExplanation, readExistingRunPresentation, readExistingRunStory,
  readStaticPlan, staticExplanationReadModel, expectedStoryPortColumns, sampleCaptureCaption, sampleCellPreview, storySamplePorts} from '../read-model.mjs';
import {effectfulStaticExplanationFixture} from '../../../scripts/fixtures/effectful-static-plan-vectors.mjs';
import {runExplanation, unprojectedRunExplanation, explanationLeakageVectors}
  from '../../../scripts/fixtures/explanation-facts-vectors.mjs';
import type {WireEffectfulStaticPlanView, WireExplanationFacts, WirePlanView, WireStaticExplanationView}
  from '../../client-wire/index.mjs';
import type {Client, Execution} from '../../sdk/index.mjs';

type Mutable<Value> = {-readonly [Key in keyof Value]: Mutable<Value[Key]>};
type Plan = Mutable<WirePlanView>;
type Step = Plan['logical_map']['steps'][number];
type Port = Step['ports'][number];
type Facts = Mutable<WireExplanationFacts>;
type Meaning = Facts['steps'][number]['meaning'];
type ProjectedPredicate = Extract<Extract<Meaning, {kind: 'filter'}>['predicate'], {state: 'projected'}>;
type PredicateNode = ProjectedPredicate['nodes'][number];
type Locale = NonNullable<Parameters<typeof planStoryModel>[1]>['locale'];
type PlanOptions = Parameters<Client['plan']>[1];
type ReadOptions = Parameters<Execution['plan']>[0];
type RunRef = Parameters<Client['attach']>[0];
type FixtureMethod<Method extends (...args: never[]) => unknown> =
  (...args: Parameters<Method>) => unknown;
type FixtureExecution = {
  [Method in 'inspect' | 'plan' | 'explain']?: FixtureMethod<Execution[Method]>;
} & {result?(name: string): {describe(): unknown; rows?(): unknown}};
type FixtureClient = {attach(ref: RunRef): FixtureExecution | Promise<FixtureExecution>;
  start?(): unknown; plan?(): unknown; close?(): unknown};

// These doubles implement only the calls under test. Their responses also
// include intentionally missing and malformed wire data for the read guards.
const attachedClient = (client: FixtureClient) => client as unknown as Client;
const planningClient = (client: {plan?: FixtureMethod<Client['plan']>}) =>
  client as unknown as Pick<Client, 'plan'>;

// Independent semantic fixture, not compiler output or public acceptance.
const cid = (unit: string) => `sha256:${unit.repeat(64)}`;
const sealed = <Body extends object,>(body: Body) => ({...body, self_cid: `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`});
const renderFacts: Parameters<typeof explanationStoryModel>[2]['render'] = (facts, locale) =>
  renderStaticExplanationNarrative(canonicalJson(facts, {dataKeys: true}), locale);
const presentFacts = (view: Plan, facts: Facts, locale?: Locale) =>
  explanationStoryModel(view, facts, {locale, render: renderFacts});
function fixture(): Plan {
  const plan = cid('a'), carrier = cid('b');
  const key = (ordinal: number): Step['key'] => sealed({version: 'actql-logical-step-key/0.1',
    compiled_plan_cid: plan, stage_ordinal: 0,
    occurrence: {kind: 'operation', operation_ordinal: ordinal}});
  const step = (ordinal: number, operator: Step['operator']): Step => ({step_id: key(ordinal).self_cid,
    key: key(ordinal), names: [`e\u0301\r\n-${ordinal}`], operator, ports: [],
    can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed'});
  const producer = step(0, 'values'), join = step(1, 'join');
  const port = <Source extends Port['source'],>(node: Step, role: Port['role'], ordinal: number, source: Source):
  Port & {source: Source} => ({port_id: sealed({
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

test('static Story renders EN/JA from the same original Plan and logical ports', () => {
  const view = fixture(), before = structuredClone(view);
  const en = planStoryModel(view), ja = planStoryModel(view, {locale: 'ja'});
  assert.deepEqual(planStoryModel(view), en);
  assert.equal(en.compiledPlanCid, cid('a'));
  assert.equal(en.logicalMapCid, view.logical_map.self_cid);
  assert.equal(en.programDefinitionCid, cid('e'));
  assert.equal(en.occurrences[1].text, 'Logical operation: join');
  assert.equal(ja.occurrences[1].text, '論理演算: join');
  assert.equal(en.ordering.kind, 'logical_dependencies');
  assert.equal(ja.ordering.text, '論理的な依存関係。実行順序ではありません');
  assert.deepEqual(en.occurrences.map(({stepId, key, ports}) => ({stepId, key, ports})),
    view.logical_map.steps.map(({step_id, key, ports}) => ({stepId: step_id, key, ports})));
  assert.deepEqual(ja.occurrences.map(({stepId, key, ports}) => ({stepId, key, ports})),
    en.occurrences.map(({stepId, key, ports}) => ({stepId, key, ports})));
  assert.deepEqual(view, before);
});

test('static Story keeps both Join input occurrences and unresolved Stage inputs separate', () => {
  const view = fixture(), first = planStoryModel(view);
  assert.deepEqual(first.dependencies.map(e => e.targetPortOrdinal), [0, 1]);
  assert.equal(first.dependencies[0].sourcePortId, first.dependencies[1].sourcePortId);
  assert.notEqual(first.dependencies[0].targetPortId, first.dependencies[1].targetPortId);
  view.logical_map.steps[1].ports[0].source = {
    kind: 'stage_input', stage_ordinal: 3, input_port_ordinal: 7};
  const story = planStoryModel(view);
  assert.equal(story.occurrences.length, 2);
  assert.equal(story.dependencies.length, 1);
  assert.deepEqual(story.stageInputs, [{stepId: view.logical_map.steps[1].step_id,
    inputPortId: view.logical_map.steps[1].ports[0].port_id,
    locator: {kind: 'stage_input', stage_ordinal: 3, input_port_ordinal: 7},
    text: 'Stage input 3:7 · Origin not represented'}]);
});

test('static Story input-only occurrence does not acquire a synthetic operation or Source', () => {
  const plan = cid('a'), key: Step['key'] = sealed({version: 'actql-logical-step-key/0.1',
    compiled_plan_cid: plan, stage_ordinal: 0,
    occurrence: {kind: 'input_output', input_port_ordinal: 0}});
  const port = (role: Port['role']): Port => ({port_id: sealed({version: 'actql-logical-port-key/0.1',
    compiled_plan_cid: plan, step_id: key.self_cid, role, port_ordinal: 0}).self_cid,
    role, port_ordinal: 0, carrier: 'relation', carrier_contract_cid: cid('b'),
    source: {kind: 'stage_input', stage_ordinal: 0, input_port_ordinal: 0},
    can_sample: false, sample_reason: 'not_installed'});
  const input = port('input'), output = port('output');
  output.source = {kind: 'logical_output', step_id: key.self_cid, output_port_id: output.port_id};
  const view = fixture();
  view.logical_map = sealed({version: 'actql-logical-map/0.1', compiled_plan_cid: plan,
    program_definition_cid: cid('e'), steps: [{step_id: key.self_cid, key, names: [],
      operator: null, ports: [input, output], can_stop_before: false,
      can_stop_after: false, stop_reason: 'not_installed'}]});
  const story = planStoryModel(view);
  assert.equal(story.occurrences.length, 1);
  assert.equal(story.occurrences[0].kind, 'input_output');
  assert.equal(story.occurrences[0].operator, null);
  assert.equal(story.occurrences[0].text, 'Input/output occurrence');
  assert.equal(planStoryModel(view, {locale: 'ja'}).occurrences[0].text, '入力の出力');
  assert.equal(story.stageInputs.length, 1);
  assert.deepEqual(story.dependencies, []);
});

test('static Story preserves exact, bound, estimate and unknown quantities without summation', () => {
  const view = fixture();
  view.quantities = (['exact', 'bound', 'estimate'] as const).map(kind => ({kind,
    value: '9007199254740993', unit: 'rows', scope_cid: cid('a'), basis_cid: cid('b')}));
  view.quantities.push({kind: 'unknown', unit: 'model_calls', reason: 'not_observed'});
  const story = planStoryModel(view);
  assert.deepEqual(story.quantities, view.quantities);
  assert.deepEqual(story.capabilities, view.capabilities);
  assert.equal(story.capabilities.durable_control, false);
  assert.deepEqual(story.capabilities.sample_capture, []);
  assert.deepEqual(story.sourceOrigins, {state: 'unavailable', reason: 'not_in_projection'});
  const quantity = view.quantities[0], observed = story.quantities[0];
  assert(quantity.kind === 'exact' && observed.kind === 'exact');
  quantity.value = '0'; view.capabilities.sample_capture.push('relation');
  assert.equal(observed.value, '9007199254740993');
  assert.deepEqual(story.capabilities.sample_capture, []);
  assert(Object.isFrozen(story.quantities[0]));
});

test('static Story retains authored text and falls back to the original identity without labels', () => {
  const view = fixture(); view.logical_map.steps[0].names = ['e\u0301\r\n<script>data</script>'];
  view.logical_map.steps[1].names = [];
  const story = planStoryModel(view, {locale: 'ja'});
  assert.equal(story.occurrences[0].title, 'e\u0301\r\n<script>data</script>');
  assert.equal(story.occurrences[1].title, view.logical_map.steps[1].step_id);
  assert(Object.isFrozen(story.occurrences[0].ports[0].source));
  view.logical_map.steps[0].names[0] = 'changed';
  assert.equal(story.occurrences[0].names[0], 'e\u0301\r\n<script>data</script>');
});

test('static Story retains Effect declarations outside the computation dependency graph', async () => {
  const {effectfulStaticPlan} = await import('../../../scripts/fixtures/effectful-static-plan-vectors.mjs');
  const plan = effectfulStaticPlan as WireEffectfulStaticPlanView;
  const story = planStoryModel(plan);
  assert.equal(story.scope, 'computation_component');
  assert.deepEqual(story.dependencies, planReadModel(effectfulStaticPlan.computation.plan_view).edges);
  assert(story.declaredEffects);
  assert.deepEqual(story.declaredEffects.members, effectfulStaticPlan.effect_set.members);
  assert.deepEqual(story.declaredEffects.observations, effectfulStaticPlan.observations);
  assert.equal(story.declaredEffects.observations.permission.state, 'unknown');
  assert.equal(story.declaredEffects.observations.preview.state, 'unavailable');
});

test('static Story refuses unsupported locale and foreign producer without repairing the Plan', () => {
  assert.throws(() => planStoryModel(fixture(), {locale: 'fr' as Locale}), {code: 'ExplorerUnsupportedLocale'});
  const view = fixture(), source = view.logical_map.steps[1].ports[0].source;
  assert(source.kind === 'logical_output');
  source.step_id = cid('0');
  assert.throws(() => planStoryModel(view), {code: 'ExplorerUnresolvedPort'});
});

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

for (const field of ['step_id', 'output_port_id', 'carrier_contract_cid'] as const) {
  test(`foreign ${field} refuses instead of inventing an edge`, () => {
    const view = fixture(), input = view.logical_map.steps[1].ports[0];
    if (field === 'carrier_contract_cid') input[field] = cid('0');
    else {
      assert(input.source.kind === 'logical_output');
      input.source[field] = cid('0');
    }
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
  const calls: unknown[] = [], client = {plan(input: Parameters<Client['plan']>[0], options: PlanOptions) {
    calls.push({input, options}); return fixture();
  }};
  await readStaticPlan(planningClient(client), 'SELECT 1 AS n', {format: 'sql'}, ticket());
  assert.deepEqual(calls, [{input: 'SELECT 1 AS n', options: {
    format: 'sql', maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}}]);
});

test('static read preserves tighter caller bounds and unrelated Plan options', async () => {
  const signal = new AbortController().signal;
  const options: NonNullable<PlanOptions> = {format: 'sql', maxWireBytes: 1024, maxNodes: 32,
    maxDepth: 4, signal, parameters: {n: 1}};
  const before = {...options}, calls: unknown[] = [];
  await readStaticPlan(planningClient({plan(input, selected) {
    calls.push(selected); return fixture();
  }}), 'SELECT 1 AS n', options, ticket());
  assert.deepEqual(calls, [before]);
  assert.deepEqual(options, before);
});

test('static read caps larger caller bounds at the finite projection ceilings', async () => {
  const calls: unknown[] = [];
  await readStaticPlan(planningClient({plan(input, options) {
    calls.push(options); return fixture();
  }}), 'SELECT 1 AS n', {maxWireBytes: 65537, maxNodes: 10001,
    maxDepth: 65}, ticket());
  assert.deepEqual(calls, [{maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]);
});

test('static read never coerces invalid bounds before existing SDK admission', async () => {
  for (const value of [null, '4', NaN, Infinity, 1.5, -1, 0]) {
    const options = {maxWireBytes: value, maxNodes: value, maxDepth: value};
    const calls: unknown[] = [];
    await readStaticPlan(planningClient({plan(input, selected) {
      calls.push(selected); return fixture();
    }}), 'SELECT 1 AS n', options as PlanOptions, ticket());
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
    await assert.rejects(readStaticPlan(planningClient(client), {}, {}, original), {code: 'ExplorerStaleScope'});
    epoch.capture().assertCurrent();
  }
});

test('old installed cohort without Plan capability remains unavailable without fallback', async () => {
  await assert.rejects(readStaticPlan(planningClient({}), {}, {}, ticket()), {code: 'ExplorerCapabilityUnavailable'});
});

test('existing Run reads only original attach and inspect, with immutable requested reference', async () => {
  const original = ref(), expected = {...original}, calls: unknown[] = [], view = {marker: 'fixture'};
  const client = {async attach(selected: RunRef) {
    original.runDefinitionCid = cid('f');
    calls.push(['attach', selected]);
    return {inspect(limits: ReadOptions) {calls.push(['inspect', limits]); return view;}};
  }};
  assert.equal(await readExistingRun(attachedClient(client), original, ticket()), view);
  assert.deepEqual(calls, [['attach', expected], ['inspect', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
});

test('scope switch during attach prevents any following inspect', async () => {
  const epoch = createReadEpoch(); let inspections = 0;
  const client = {async attach() {epoch.invalidate();
    return {inspect() {inspections++;}};
  }};
  await assert.rejects(readExistingRun(attachedClient(client), ref(), epoch.capture()), {code: 'ExplorerStaleScope'});
  assert.equal(inspections, 0);
});

test('saved Run Plan uses only exact original attach and Run.plan with frozen reference', async () => {
  const original = ref(), expected = {...original}, calls: unknown[] = [], view = fixture();
  const client = {attach(selected: RunRef) {
    calls.push(['attach', selected]); original.namespaceId = 'changed';
    return {plan(limits: ReadOptions) {calls.push(['run-plan', limits]);
      return {version: 'actql-run-plan-view/0.1', run_ref: expected, plan_view: view};}};
  }, plan() {assert.fail('no recompile fallback');}, start() {assert.fail('no Run');}};
  const observed = await readExistingRunPlan(attachedClient(client), original, ticket());
  assert.deepEqual(observed.runRef, expected);
  assert(Object.isFrozen(observed.runRef));
  assert.equal(observed.plan.compiledPlanCid, view.compiled_plan_cid);
  assert.equal(observed.plan.logicalMapCid, view.logical_map.self_cid);
  assert.equal(observed.plan.nodes[0].id, view.logical_map.steps[0].step_id);
  assert.deepEqual(calls, [['attach', expected], ['run-plan', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
});

test('original explanation read uses only same Execution and preserves projected or absent retained Facts', async () => {
  for (const value of [runExplanation, unprojectedRunExplanation]) {
    const view = structuredClone(value), original = {...view.run_ref}, expected = {...original}, calls: unknown[] = [];
    const execution = {explain(options: ReadOptions) {
      assert.equal(this, execution); calls.push(['explain', options]); return view;
    }, plan() {assert.fail('no replacement Plan');}, inspect() {assert.fail('no permission inference');}};
    const client = {attach(selected: RunRef) {
      assert(Object.isFrozen(selected)); calls.push(['attach', selected]);
      original.namespaceId = 'changed-after-capture'; return execution;
    }, start() {assert.fail('no Run');}, plan() {assert.fail('no recompile');}};
    const result = await readExistingRunExplanation(attachedClient(client), original, ticket());
    assert.deepEqual(result, value); assert(Object.isFrozen(result.explanation));
    assert.deepEqual(calls, [['attach', expected], ['explain', {
      maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  }
});

test('original explanation read refuses stale scope and propagates original Owner refusal without repair', async () => {
  for (const boundary of ['attach', 'explain']) {
    const epoch = createReadEpoch(); let explained = 0;
    const client = {async attach() {
      if (boundary === 'attach') epoch.invalidate();
      return {async explain() {explained++; epoch.invalidate(); return structuredClone(runExplanation);}};
    }};
    await assert.rejects(readExistingRunExplanation(attachedClient(client), runExplanation.run_ref, epoch.capture()),
      {code: 'ExplorerStaleScope'});
    assert.equal(explained, boundary === 'attach' ? 0 : 1);
  }
  const primary = Object.assign(new Error('original read refusal'), {code: 'RunObservationAccessDenied'});
  await assert.rejects(readExistingRunExplanation(attachedClient({attach: () => ({explain() {throw primary;},
    plan() {assert.fail('no fallback');}})}), runExplanation.run_ref, ticket()), cause => cause === primary);
  await assert.rejects(readExistingRunExplanation(attachedClient({attach: () => ({})}), runExplanation.run_ref, ticket()),
    {code: 'ExplorerCapabilityUnavailable'});
});

test('original explanation read rejects foreign bindings, disclosure additions and oversized DTOs', async () => {
  const foreign = structuredClone(runExplanation); foreign.run_ref.namespaceId = 'foreign';
  const oversized = structuredClone(runExplanation);
  oversized.explanation.facts.steps[0].meaning.predicate.nodes[1].name = 'x'.repeat(65536);
  const leaked = explanationLeakageVectors.map(({value}) => ({...structuredClone(runExplanation),
    explanation: {state: 'projected', facts: value}}));
  for (const view of [foreign, oversized, ...leaked]) {
    await assert.rejects(readExistingRunExplanation(attachedClient({attach: () => ({explain: () => view})}),
      runExplanation.run_ref, ticket()), {code: 'ExplorerInvalidExplanation'});
  }
});

test('original presentation derives both models from the same Execution originals and captured locale', async () => {
  const view = fixture(), facts = explanationFixture(view), original = ref(), expected = {...original};
  const options: {locale: Locale; render: typeof renderFacts} = {locale: 'ja', render: renderFacts}, calls: unknown[] = [];
  const execution = {explain(limits: ReadOptions) {
    calls.push(['explain', limits]); assert.equal(this, execution);
    return {version: 'actql-run-explanation-view/0.1', run_ref: expected,
      explanation: {state: 'projected', facts}};
  }, plan(limits: ReadOptions) {
    calls.push(['plan', limits]); assert.equal(this, execution);
    return {version: 'actql-run-plan-view/0.1', run_ref: expected, plan_view: view};
  }};
  const client = {attach(selected: RunRef) {
    calls.push(['attach', selected]); original.namespaceId = 'changed'; options.locale = 'en'; return execution;
  }, start() {assert.fail('no new Run');}};
  const model = await readExistingRunPresentation(attachedClient(client), original, options, ticket());
  assert(model.plan && model.explanation.state === 'projected');
  assert.deepEqual(model.runRef, expected); assert.equal(model.plan.logicalMapCid, view.logical_map.self_cid);
  assert.equal(model.explanation.story.locale, 'ja');
  assert.equal(model.explanation.story.occurrences[1].explanation.text,
    '内部結合のキー "id"（入力の参照は未提供）; NULLキー: 一致させない');
  assert.equal(model.explanation.story.factsCid, facts.self_cid);
  assert.deepEqual(model.explanation.story.dependencies, model.plan.edges);
  assert(Object.isFrozen(model.explanation.story.occurrences));
  assert.deepEqual(calls, [['attach', expected], ['explain', {maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}],
    ['plan', {maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
});

test('original presentation keeps absence and Owner failure separate without a Plan repair', async () => {
  const absent = structuredClone(unprojectedRunExplanation);
  const model = await readExistingRunPresentation(attachedClient({attach: () => ({explain: () => absent,
    plan() {assert.fail('absence does not request another original or compile a replacement');}})}),
    absent.run_ref, {render: renderFacts}, ticket());
  assert.deepEqual(model, {runRef: absent.run_ref, plan: null, explanation: absent.explanation});
  const primary = Object.assign(new Error('original egress refused'), {code: 'RunObservationAccessDenied'});
  await assert.rejects(readExistingRunPresentation(attachedClient({attach: () => ({explain() {throw primary;},
    plan() {assert.fail('denial is not absence');}})}), absent.run_ref, {render: renderFacts}, ticket()), cause => cause === primary);
});

test('original presentation rejects changed map ports and late scopes across its two reads', async () => {
  for (const mode of ['map', 'ports', 'scope-after-explain', 'scope-after-plan', 'plan-denied']) {
    const view = fixture(), facts = explanationFixture(view), original = ref(), epoch = createReadEpoch();
    if (mode === 'map') facts.logical_map_cid = cid('f');
    if (mode === 'ports') facts.steps[1].input_ports[0] = cid('f');
    const primary = Object.assign(new Error('original Plan refused'), {code: 'RunObservationAccessDenied'});
    let planCalls = 0;
    const client = {attach: () => ({async explain() {
      if (mode === 'scope-after-explain') epoch.invalidate();
      return {version: 'actql-run-explanation-view/0.1', run_ref: original, explanation: {state: 'projected', facts}};
    }, async plan() {
      planCalls++;
      if (mode === 'scope-after-plan') epoch.invalidate();
      if (mode === 'plan-denied') throw primary;
      return {version: 'actql-run-plan-view/0.1', run_ref: original, plan_view: view};
    }})};
    await assert.rejects(readExistingRunPresentation(attachedClient(client), original, {render: renderFacts}, epoch.capture()),
      mode === 'plan-denied' ? cause => cause === primary
        : {code: mode.startsWith('scope') ? 'ExplorerStaleScope' : 'ExplorerInvalidExplanation'});
    assert.equal(planCalls, mode === 'scope-after-explain' ? 0 : 1);
  }
});

test('original presentation BrowserSource traverses one bounded Gateway slot through both original reads', async () => {
  const original = ref(), view = fixture(), facts = explanationFixture(view), calls: unknown[] = [];
  let blockPlan = false, gatewayClosed = false;
  const started = Promise.withResolvers<void>();
  const pending = Promise.withResolvers<void>();
  const execution = {explain() {
    calls.push('explain'); return {version: 'actql-run-explanation-view/0.1', run_ref: original,
      explanation: {state: 'projected', facts}};
  }, async plan() {
    calls.push('plan'); if (blockPlan) {started.resolve(); await pending.promise;}
    return {version: 'actql-run-plan-view/0.1', run_ref: original, plan_view: view};
  }};
  const gateway = await startExplorerGateway({client: attachedClient({attach(selected) {
    calls.push('attach'); assert.deepEqual(selected, original); return execution;
  }, close() {assert.fail('borrowed Client is not closed by Gateway');}})});
  let cookie: string | undefined;
  const source = createExplorerBrowserSource({origin: gateway.origin, async fetch(url, options) {
    const reply = await fetch(url, {...options, headers: {...options?.headers, Origin: gateway.origin,
      ...(cookie ? {Cookie: cookie} : {})}});
    cookie = reply.headers.get('set-cookie')?.split(';')[0] ?? cookie; return reply;
  }});
  try {
    await source.connect(gateway.issueBootstrap().bootstrap);
    const model = await source.runPresentation(original, {locale: 'en'});
    assert(model.plan && model.explanation.state === 'projected');
    assert.equal(model.explanation.story.occurrences[1].explanation.text,
      'Match rows on "id" (input origins not projected); Null keys: do not match');
    assert.deepEqual(model.plan.edges, model.explanation.story.dependencies);
    assert.deepEqual(calls, ['attach', 'explain', 'plan']);
    blockPlan = true;
    const reading = source.runPresentation(original, {locale: 'ja'})
      .then(value => ({value}), cause => ({cause}));
    await started.promise;
    const closing = gateway.close().then(() => {gatewayClosed = true;});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(gatewayClosed, false);
    pending.resolve(); await closing;
    // Actual server close may terminate its HTTP connection before an error
    // reply arrives. Assert non-disclosure, not an invented authorization or
    // Run outcome classification for that transport loss.
    assert(Object.hasOwn(await reading, 'cause'));
    assert.deepEqual(calls, ['attach', 'explain', 'plan', 'attach', 'explain', 'plan']);
  } finally {source.close(); pending.resolve(); await gateway.close();}
});

test('saved Story uses the same original Run without recompilation and captures locale once', async () => {
  const original = ref(), expected = {...original}, calls: unknown[] = [], options: {locale: Locale} = {locale: 'ja'};
  const client = {async attach(selected: RunRef) {
    calls.push(['attach', selected]); original.namespaceId = 'changed'; options.locale = 'en';
    return {plan(limits: ReadOptions) {calls.push(['run-plan', limits]);
      return {version: 'actql-run-plan-view/0.1', run_ref: expected, plan_view: fixture()};}};
  }, plan() {assert.fail('no compile');}, start() {assert.fail('no submit');}};
  const read = await readExistingRunStory(attachedClient(client), original, options, ticket());
  assert.deepEqual(read.runRef, expected);
  assert.equal(read.story.locale, 'ja');
  assert.equal(read.story.occurrences[1].text, '論理演算: join');
  assert.deepEqual(calls, [['attach', expected], ['run-plan', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  assert(Object.isFrozen(read.runRef));
});

test('saved Story refuses missing or foreign originals without compile or submit fallback', async () => {
  let calls = 0;
  const client: FixtureClient = {attach() {calls++;return {};}, plan() {assert.fail('no compile');}};
  await assert.rejects(readExistingRunStory(attachedClient(client), ref(), undefined, ticket()),
    {code: 'ExplorerCapabilityUnavailable'});
  const before = calls;
  await assert.rejects(readExistingRunStory(attachedClient(client), ref(), {locale: 'fr' as Locale}, ticket()),
    {code: 'ExplorerUnsupportedLocale'});
  assert.equal(calls, before);
  for (const dimension of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
    client.attach = () => ({plan() {return {version: 'actql-run-plan-view/0.1',
      run_ref: {...ref(), [dimension]: dimension === 'namespaceId' ? 'foreign' : cid('c')},
      plan_view: fixture()};}});
    await assert.rejects(readExistingRunStory(attachedClient(client), ref(), undefined, ticket()),
      {code: 'ExplorerInvalidRunPlan'});
  }
});

test('saved Story discards a delayed read or failure after its presentation scope changes', async () => {
  for (const failure of [false, true]) {
    const epoch = createReadEpoch();
    const client = {attach() {return {async plan() {
      epoch.invalidate();
      if (failure) throw new Error('old scope');
      return {version: 'actql-run-plan-view/0.1', run_ref: ref(), plan_view: fixture()};
    }};}};
    await assert.rejects(readExistingRunStory(attachedClient(client), ref(), undefined, epoch.capture()),
      {code: 'ExplorerStaleScope'});
  }
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
    await assert.rejects(readExistingRunPlan(attachedClient({attach() {return {plan() {return bad;}};}}),
      expected, ticket()), error => error instanceof Error && 'code' in error &&
        (error.code === 'ExplorerInvalidRunPlan' || error.code === 'ExplorerInvalidPlan'));
  }
});

test('old missing saved plan never recompiles or starts replacement business work', async () => {
  let replans = 0;
  const client: FixtureClient = {attach() {return {};}, plan() {replans++;}};
  await assert.rejects(readExistingRunPlan(attachedClient(client), ref(), ticket()),
    {code: 'ExplorerCapabilityUnavailable'});
  const unavailable = Object.assign(new Error('LegacyMissing'), {code: 'OriginalPlanUnavailable'});
  client.attach = () => ({plan() {throw unavailable;}});
  await assert.rejects(readExistingRunPlan(attachedClient(client), ref(), ticket()), error => error === unavailable);
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
    await assert.rejects(readExistingRunPlan(attachedClient(client), ref(), original), {code: 'ExplorerStaleScope'});
    epoch.capture().assertCurrent();
  }
});

test('Named Result description uses no payload reader or grant/open operation', async () => {
  const calls: unknown[] = [], description = {marker: 'independent metadata fixture'};
  const client = {attach(original: RunRef) {calls.push(['attach', original]);
    return {result(name: string) {calls.push(['result', name]);
      return {describe() {calls.push(['describe']); return description;},
        rows() {assert.fail('no payload open');}};}};
  }};
  assert.equal(await describeExistingResult(attachedClient(client), ref(), 'e\u0301\r\n', ticket()), description);
  assert.deepEqual(calls, [['attach', ref()], ['result', 'e\u0301\r\n'], ['describe']]);
});

test('public SDK facade admits original Plan and Run wire without submitting any business work', async t => {
  // The actual SDK/wire boundary is used; the endpoint remains a semantic
  // fixture, not a Compiler/Run Owner or a packed public Host acceptance.
  const calls: unknown[] = [], reference = ref(), view = fixture();
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
        {format: 'sql', [name]: value} as PlanOptions, ticket()),
      Number.isNaN(value) || value === Infinity
        ? {name: 'TypeError', message: 'UnrepresentableClientNumber'}
        : {code: 'InvalidClientPlanRequest'});
    }
  }
  assert.deepEqual(calls, ['connect', 'plan', 'attach', 'inspect-run', 'attach', 'run-plan']);
  const gateway = await startExplorerGateway({client}); let cookie: string | undefined;
  const browser = createExplorerBrowserSource({origin: gateway.origin,
    async fetch(url, options) {
      const response = await fetch(url, {...options, headers: {...options?.headers,
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

test('Effectful static declarations retain unknowns without adding computation edges', async () => {
  const {effectfulStaticPlan, commandMember} = await import('../../../scripts/fixtures/effectful-static-plan-vectors.mjs');
  const {planReadModel} = await import('../read-model.mjs');
  const plan = effectfulStaticPlan as WireEffectfulStaticPlanView;
  const model = planReadModel(plan);
  assert.deepEqual(model.nodes, planReadModel(plan.computation.plan_view).nodes);
  assert.deepEqual(model.edges, planReadModel(plan.computation.plan_view).edges);
  assert(model.effectful);
  assert.equal(model.effectful.scope, 'computation_component');
  assert.deepEqual(model.effectful.members[0].minimum_approval, {kind: 'contract_minimum', value: 'required'});
  assert.equal(model.effectful.observations.permission.state, 'unknown');
  assert.equal(model.effectful.observations.preview.state, 'unavailable');
  const command = structuredClone(effectfulStaticPlan);
  command.effect_set.members = [commandMember];
  const commandView = planReadModel(command as WireEffectfulStaticPlanView);
  assert(commandView.effectful);
  assert.equal(commandView.effectful.members[0].minimum_approval.kind, 'not_represented');
  const foreign = structuredClone(effectfulStaticPlan);
  foreign.program_definition_cid = 'sha256:' + 'f'.repeat(64);
  assert.throws(() => planReadModel(foreign as WireEffectfulStaticPlanView), {code: 'ExplorerInvalidPlan'});
});

test('Static Context refuses mixed bindings, foreign ports, and substituted Effect declarations', () => {
  const mutations: ((view: ReturnType<typeof effectfulStaticExplanationFixture>) => void)[] = [
    view => {view.context.binding.check_environment_cid = cid('f');},
    view => {
      const source = view.context.items[0];
      assert(source.kind === 'source');
      source.consuming_ports[0].port_id = cid('f');
    },
    view => {view.context.items.unshift(structuredClone(view.context.items[0]));},
    view => {
      const task = view.context.items[1];
      assert(task.kind === 'model_task' && task.producer.state === 'projected');
      task.producer.port_id = cid('f');
    },
    view => {
      const effect = view.context.items[3];
      assert(effect.kind === 'effect_set');
      const contract = effect.members[0].declaration.contract;
      assert(contract.kind === 'mapping');
      contract.declared_target = 'connector://foreign/account';
    },
  ];
  for (const mutate of mutations) {
    const original = effectfulStaticExplanationFixture();
    mutate(original);
    assert.throws(() => staticExplanationReadModel(original as WireStaticExplanationView, {render() {
      assert.fail('refuse the mismatched original before rendering');
    }}), {code: 'ExplorerInvalidExplanation'});
  }
});

// Independently authored semantic projection DATA, not a compiler/Host grant.
const explanationType = (kind: PredicateNode['type']['kind']): PredicateNode['type'] =>
  ({projection: 'shape_and_nullability', kind, nullable: false});
const explanationValues: Extract<Meaning, {kind: 'values'}> = {kind: 'values', schema: {fields: [
  {name: 'id', presence: 'required', type: explanationType('number')},
  {name: 'label', presence: 'conditional', type: explanationType('string')},
]}};
const explanationJoin: Extract<Meaning, {kind: 'join'}> = {
  kind: 'join', join_kind: 'inner', null_key: 'no_match', keys: [{left: 'id', right: 'id'}]};
function explanationFixture(view: Plan, meaning: Meaning = explanationJoin): Facts {
  return sealed({version: 'actql-explanation-facts/0.1', disclosure: 'structural',
    program_definition_cid: view.logical_map.program_definition_cid,
    parameter_values_cid: cid('9'), compiled_plan_cid: view.compiled_plan_cid,
    logical_map_cid: view.logical_map.self_cid,
    steps: view.logical_map.steps.map((step, index) => ({step_id: step.step_id,
      key: structuredClone(step.key), operator: step.operator,
      input_ports: step.ports.filter(port => port.role === 'input').map(port => port.port_id),
      output_ports: step.ports.filter(port => port.role === 'output').map(port => port.port_id),
      meaning: structuredClone(index === 0 ? explanationValues : meaning)}))});
}
function valuesMeaning(facts: Pick<Facts, 'steps'>) {
  const meaning = facts.steps[0].meaning;
  assert(meaning.kind === 'values');
  return meaning;
}
function projectedPredicate(facts: Pick<Facts, 'steps'>) {
  const meaning = facts.steps[1].meaning;
  assert(meaning.kind === 'filter' && meaning.predicate.state === 'projected');
  return meaning.predicate;
}
function explanationUnary(operator: Step['operator']) {
  const view = fixture(), {self_cid, ...map} = view.logical_map;
  map.steps[1].operator = operator;
  map.steps[1].ports.splice(1, 1);
  view.logical_map = sealed(map);
  return view;
}
const explanationPredicate = (tail: PredicateNode): Meaning =>
  ({kind: 'filter', predicate: {state: 'projected', root: 0, nodes: [
  {form: 'operation', operator: 'gt', children: [1, 2], type: explanationType('boolean')},
  {form: 'field', scope: 'fields', name: 'id', type: explanationType('number')},
  tail,
]}});

test('Step data offers exact inputs and the single addressable Relation output', () => {
  const view = fixture();
  const {occurrences} = presentFacts(view, explanationFixture(view));
  const step = occurrences[1];
  const output = step.ports.find(port => port.role === 'output');
  assert(output);
  const inputs = step.ports.filter(port => port.role === 'input');
  assert.deepEqual(storySamplePorts(step), [...inputs, output]);
  assert.deepEqual(storySamplePorts({ports: [...step.ports,
    {...output, port_ordinal: 1, port_id: cid('f')}]}), inputs);
});

test('Sample table captions distinguish complete captures, prefixes, and count-only evidence', () => {
  const total = {kind: 'exact', value: '38', unit: 'rows', scope_cid: cid('a'), basis_cid: cid('b')} as const;
  const capture = {strategy: 'execution_prefix', sampled_items: '38', total,
    completeness: 'complete', truncation: 'not_truncated', sample_ref_cid: cid('c'),
    receipt_cid: cid('d'), emission_provenance_cid: cid('e')} as const;
  const prefix = {...capture, sampled_items: '50', total: {...total, value: '112'},
    completeness: 'partial', truncation: 'confirmed'} as const;
  const unknown = {kind: 'unknown', unit: 'rows', reason: 'not_observed'} as const;
  assert.equal(sampleCaptureCaption(capture), 'All 38 rows captured');
  assert.equal(sampleCaptureCaption(prefix), 'First 50 of 112 rows captured');
  assert.equal(sampleCaptureCaption({...prefix, total: unknown}), 'First 50 rows captured · total unknown');
  assert.equal(sampleCaptureCaption({...capture, completeness: 'unknown'}), '38 rows captured · 38 total rows');
  assert.equal(sampleCaptureCaption({...capture, truncation: 'confirmed'}), '38 rows captured · 38 total rows');
  assert.equal(sampleCaptureCaption({...prefix, total: {...total, value: '49'}}),
    '50 rows captured · Reported total is below captured rows');
  assert.equal(sampleCaptureCaption({...prefix, total: {...total, kind: 'estimate'}}),
    '50 rows captured · Exact total rows not observed');
  assert.equal(sampleCaptureCaption({...prefix, total: unknown, completeness: 'unknown', truncation: 'unknown'}),
    '50 rows captured · Exact total rows not observed');
  assert.equal(sampleCaptureCaption({...prefix, total: {...unknown, unit: 'items'}}),
    '50 rows captured · Exact total rows not observed');
});

test('collapsed Sample cells preserve the first 200 Unicode code points', () => {
  const preview = '😀'.repeat(199) + '漢';
  assert.equal(sampleCellPreview(preview), preview);
  assert.equal(sampleCellPreview(preview + '👩' + 'not shown'), preview);
  assert.equal(sampleCellPreview('ordinary'), 'ordinary');
});

test('expected columns use the checked output and its exact consumer links', () => {
  const view = fixture();
  const {occurrences} = presentFacts(view, explanationFixture(view));
  const [values, join] = occurrences;
  const steps = new Map(occurrences.map(step => [step.stepId, step]));
  assert.deepEqual(expectedStoryPortColumns(steps, values, values.ports[0]), ['id', 'label']);
  assert.deepEqual(expectedStoryPortColumns(steps, join, join.ports[0]), ['id', 'label']);
  assert.equal(expectedStoryPortColumns(steps, join, join.ports.find(port => port.role === 'output')), undefined,
    'JOIN keys do not describe its output columns');
  assert.equal(expectedStoryPortColumns(steps, join, values.ports[0]), undefined,
    'a port from a different step does not supply fields');
});

test('structural Story explains original fields and JOIN keys in EN/JA with unprojected input origins', () => {
  const view = fixture(), facts = explanationFixture(view), before = structuredClone(facts);
  const en = presentFacts(view, facts), ja = presentFacts(view, facts, 'ja');
  assert.equal(en.occurrences[0].explanation.text,
    'Declared input fields: "id":number, "label":string (conditional)');
  assert.equal(en.occurrences[1].explanation.text,
    'Match rows on "id" (input origins not projected); Null keys: do not match');
  assert.equal(ja.occurrences[1].explanation.text,
    '内部結合のキー "id"（入力の参照は未提供）; NULLキー: 一致させない');
  assert.equal(en.factsCid, facts.self_cid); assert.equal(en.parameterValuesCid, cid('9'));
  assert.deepEqual(en.occurrences.map(step => step.stepId), view.logical_map.steps.map(step => step.step_id));
  assert.deepEqual(en.dependencies, planReadModel(view).edges);
  assert.deepEqual(en.occurrences[1].explanation.meaning, explanationJoin);
  const joined = en.occurrences[1].explanation.meaning;
  assert(joined.kind === 'join');
  assert.equal(Object.isFrozen(joined.keys), true);
  assert.deepEqual(facts, before); assert.deepEqual(en.capabilities.sample_capture, []);
  assert.equal(Object.hasOwn(en.occurrences[1].explanation, 'executed'), false);
});

test('structural Story renders original typed parameter and redacted literal without reconstructing values', () => {
  const view = explanationUnary('filter');
  const parameter = explanationPredicate({form: 'parameter', name: 'threshold', type: explanationType('number')});
  assert.equal(presentFacts(view, explanationFixture(view, parameter)).occurrences[1].explanation.text,
    'Keep rows where: (fields."id":number) > ($threshold:number)');
  const literal = explanationPredicate({form: 'literal_redacted', type: explanationType('number')});
  assert.equal(presentFacts(view, explanationFixture(view, literal)).occurrences[1].explanation.text,
    'Keep rows where: (fields."id":number) > ([redacted number])');
  assert.equal(presentFacts(view, explanationFixture(view, literal), 'ja').occurrences[1].explanation.text,
    'この条件を満たす行を残す: (fields."id":number) > ([非開示 number])');
});

test('structural Story renders a singleton AND or OR and refuses an absent operand', () => {
  const view = explanationUnary('filter');
  for (const operator of ['and', 'or'] as const) {
    const type = explanationType('boolean');
    const meaning = {kind: 'filter', predicate: {state: 'projected', root: 0, nodes: [
      {form: 'operation', operator, children: [1], type},
      {form: 'field', scope: 'fields', name: 'flag', type: {...type}},
    ]}} satisfies Meaning;
    const facts = explanationFixture(view, meaning);
    assert.equal(presentFacts(view, facts).occurrences[1].explanation.text,
      'Keep rows where: (fields."flag":boolean)');
    assert.equal(presentFacts(view, facts, 'ja').occurrences[1].explanation.text,
      'この条件を満たす行を残す: (fields."flag":boolean)');
    meaning.predicate.nodes[0].children = [];
    assert.throws(() => presentFacts(view, explanationFixture(view, meaning)), {code: 'ExplorerInvalidExplanation'});
  }
});

test('structural Story keeps ordered projection semantics and explicit unprojected meaning', () => {
  for (const [operation, prefix] of [['select', 'Select output fields'], ['rename', 'Rename output fields'], ['drop', 'Output fields after dropping']] as const) {
    const view = explanationUnary(operation), meaning: Meaning = {kind: 'projection', operation,
      fields: [{input: 'é', output: 'renamed'}, {input: 'id', output: 'id'}]};
    assert.equal(presentFacts(view, explanationFixture(view, meaning)).occurrences[1].explanation.text,
      `${prefix}: "renamed" ← "é", "id" ← "id"`);
  }
  const view = fixture(), missing = explanationFixture(view, {kind: 'not_projected', reason: 'operation_facts_not_projected'});
  const explanation = presentFacts(view, missing).occurrences[1].explanation;
  assert.equal(explanation.state, 'not_projected'); assert.equal(explanation.text, 'Meaning not projected');
  const filter = explanationUnary('filter');
  const predicateMissing = explanationFixture(filter, {kind: 'filter', predicate: {state: 'not_projected', reason: 'expression_form_not_projected'}});
  assert.equal(presentFacts(filter, predicateMissing).occurrences[1].explanation.text,
    'Keep rows where: Predicate form not projected');
});

test('structural Story refuses foreign bindings keys port occurrences and raw disclosure fields', () => {
  const view = fixture(), original = explanationFixture(view);
  const mutations: ((facts: Facts) => void)[] = [
    f => {f.compiled_plan_cid = cid('0');}, f => {f.program_definition_cid = cid('0');},
    f => {f.logical_map_cid = cid('0');}, f => {f.steps.reverse();},
    f => {f.steps[1].key.stage_ordinal++;}, f => {f.steps[1].input_ports.reverse();},
    f => {Object.assign(valuesMeaning(f).schema.fields[0].type, {max_utf8_bytes: 7});},
    f => {Object.assign(valuesMeaning(f), {rows: [{id: 'private'}]});},
  ];
  for (const mutate of mutations) {
    const changed = structuredClone(original); mutate(changed);
    assert.throws(() => presentFacts(view, changed), {code: 'ExplorerInvalidExplanation'});
  }
  const filtered = explanationUnary('filter'), literal = explanationFixture(filtered,
    explanationPredicate({form: 'literal_redacted', type: explanationType('number')}));
  Object.assign(projectedPredicate(literal).nodes[2], {value: 'PRIVATE'});
  assert.throws(() => presentFacts(filtered, literal), {code: 'ExplorerInvalidExplanation'});
});

test('structural Story refuses malformed local references and finite predicate presentation overflow', () => {
  const view = explanationUnary('filter');
  const original = explanationFixture(view, explanationPredicate({form: 'literal_redacted', type: explanationType('number')}));
  const mutations: ((nodes: PredicateNode[]) => void)[] = [
    nodes => {assert(nodes[0].form === 'operation'); nodes[0].children[0] = 0;},
    nodes => {assert(nodes[0].form === 'operation'); nodes[0].children[0] = 9;},
    nodes => {nodes.push({form: 'literal_redacted', type: explanationType('number')});},
  ];
  for (const mutate of mutations) {
    const {self_cid: _, ...changed} = structuredClone(original);
    mutate(projectedPredicate(changed).nodes);
    assert.throws(() => presentFacts(view, sealed(changed)), {code: 'ExplorerInvalidExplanation'});
  }
  const expanded = structuredClone(original);
  const root = projectedPredicate(expanded).nodes[0];
  assert(root.form === 'operation');
  root.children = Array<number>(1025).fill(1);
  assert.throws(() => presentFacts(view, expanded), {code: 'ExplorerExplanationLimit'});
  const {self_cid: _, ...deep} = structuredClone(original);
  const predicate = projectedPredicate(deep);
  predicate.nodes = Array.from({length: 66}, (_, index) =>
    ({form: 'operation', operator: 'not', children: [index + 1], type: explanationType('boolean')}));
  predicate.nodes.push({form: 'literal_redacted', type: explanationType('boolean')});
  assert.throws(() => presentFacts(view, sealed(deep)), {code: 'ExplorerExplanationLimit'});
});

test('structural construction admits long field and parameter text before quote or output allocation', () => {
  const view = fixture(), facts = explanationFixture(view), name = 'x'.repeat(70_000);
  valuesMeaning(facts).schema.fields[0].name = name;
  const stringify = JSON.stringify; let oversizedQuoteCalls = 0;
  try {
    JSON.stringify = function(value, ...options) {
      if (value === name) {oversizedQuoteCalls++; throw new Error('Quote called before admission');}
      return Reflect.apply(stringify, this, [value, ...options]);
    };
    assert.throws(() => presentFacts(view, facts), {code: 'ExplorerExplanationLimit'});
    assert.equal(oversizedQuoteCalls, 0);
  } finally {JSON.stringify = stringify;}
  const filtered = explanationUnary('filter');
  const parameter = explanationFixture(filtered,
    explanationPredicate({form: 'parameter', name, type: explanationType('number')}));
  assert.throws(() => presentFacts(filtered, parameter), {code: 'ExplorerExplanationLimit'});
});

test('structural construction admits shared-child copies before a large joined predicate exists', () => {
  const view = explanationUnary('filter');
  const meaning: Meaning = {kind: 'filter', predicate: {state: 'projected', root: 0, nodes: [
    {form: 'operation', operator: 'and', children: Array<number>(80).fill(1), type: explanationType('boolean')},
    {form: 'field', scope: 'fields', name: 'f'.repeat(5000), type: explanationType('number')},
  ]}};
  const facts = explanationFixture(view, meaning);
  const join = Array.prototype.join; let oversizedJoins = 0;
  try {
    Array.prototype.join = function(separator = ',') {
      if (this.every(value => typeof value === 'string')) {
        const length = this.reduce((sum, value) => sum + value.length, 0) +
          Math.max(0, this.length - 1) * separator.length;
        if (length > 65_536) {oversizedJoins++; throw new Error('Join called before admission');}
      }
      return Reflect.apply(join, this, [separator]);
    };
    assert.throws(() => presentFacts(view, facts), {code: 'ExplorerExplanationLimit'});
    assert.equal(oversizedJoins, 0);
  } finally {Array.prototype.join = join;}
});

test('structural construction admits escaped expansion before the native quote call', () => {
  const view = fixture(), facts = explanationFixture(view), name = '\u0001'.repeat(12_000);
  // Each code unit needs six escaped characters, before the two quote marks.
  assert(6 * name.length + 2 > 65_536);
  const joined = facts.steps[1].meaning;
  assert(joined.kind === 'join');
  joined.keys[0].left = name;
  const stringify = JSON.stringify; let escapedQuoteCalls = 0;
  try {
    JSON.stringify = function(value, ...options) {
      if (value === name) {escapedQuoteCalls++; throw new Error('Escaping called before admission');}
      return Reflect.apply(stringify, this, [value, ...options]);
    };
    assert.throws(() => presentFacts(view, facts), {code: 'ExplorerExplanationLimit'});
    assert.equal(escapedQuoteCalls, 0);
  } finally {JSON.stringify = stringify;}
});
