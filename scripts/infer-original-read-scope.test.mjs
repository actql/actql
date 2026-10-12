import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {checked} from '../adapters/host-common/runtime-result.mjs';

// Existing independently authored admission inputs, never expected outputs.
const source = readFileSync(new URL(
  '../src/client_infer_host/fixture.generated_wbtest.mbt', import.meta.url), 'utf8');
const fixture = name => source.match(new RegExp(
  `let ${name} : String =\\n\\s+#\\|([^\\n]+)`, 'u'))[1];
const identity = body => `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;

function original() {
  const environment = moon.clientProgramCheckEnvironment(
    fixture('infer_fixture_environment'), fixture('infer_fixture_environment_cid'),
    false, false, true, false, false, false, false);
  const prepared = moon.clientProgramPreparationReady(
    moon.clientProgramPrepareEffectFreeWithParameters(
      fixture('infer_fixture_program'), 'json', environment, undefined));
  assert.ok(prepared);
  const task = JSON.parse(fixture('infer_fixture_environment')).model_task_contracts[0];
  const step = moon.clientProgramSelectedInferStep(prepared);
  // Binding-only existing execution vector. No executable retry/egress policy
  // or physical numerical layout is asserted by this read-only connection.
  const executionBody = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: `sha256:${'a'.repeat(64)}`,
    backoff_contract_cid: `sha256:${'a'.repeat(64)}`,
    max_attempts_per_slot: 2, max_total_attempts: 4,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_wire_bytes: 133072, max_total_token_reservation: 128,
    media_input_contracts: {}, default_publication: 'outcomes'};
  const executionCid = identity(executionBody);
  const execution = checked(moon.clientProgramReadInferModelExecution(prepared,
    step, canonicalText({...executionBody, self_cid: executionCid}), executionCid));
  const graph = checked(moon.clientProgramInferPlanGraph(prepared, step,
    execution, `sha256:${'b'.repeat(64)}`, `sha256:${'c'.repeat(64)}`));
  const calls = {begin: [], read: [], finish: [], settle: []};
  const consumingMoon = {...moon};
  for (const [name, kind] of [
    ['clientProgramBeginInferOriginalReadScope', 'begin'],
    ['clientProgramPrepareInferNodeReadLayout', 'read'],
    ['clientProgramFinishInferOriginalReadScope', 'finish'],
    ['clientProgramSettleInferOriginalReadPreparation', 'settle'],
  ]) consumingMoon[name] = (...args) => {
    calls[kind].push(args);
    return moon[name](...args);
  };
  const control = runtimeCore(consumingMoon).publicationControl;
  const foreign = runtimeCore(moon).publicationControl;
  const root = identity({fixture: 'original read scope'});
  const data = {version: 'actql-effective-data-policy/0.1', classification: 'unknown',
    source_data_policy_cids: [], source_response_policy_cids: [], unknown_provenance: true};
  const policy = {executionContextCid: root, hostPolicyCid: root,
    expiresAt: '2099-01-01T00:00:00.000Z',
    resultDataPolicy: {kind: 'data_policy', cid: identity(data), wire: canonicalText(data)}};
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', policy, graph);
  const foreignCompiled = foreign.prepareCheckedClientCompiledRun(prepared, 'infer', policy, graph);
  const define = (owner, run, runId) => owner.defineCheckedClientCompiledRun(run,
    {namespaceId: 'scope', runId, createdAt: '2026-10-02T00:00:00.000Z',
      validUntil: policy.expiresAt});
  return {control, compiled, prepared, definition: define(control, compiled, 'original'),
    foreignCompiled, foreignDefinition: define(foreign, foreignCompiled, 'foreign'),
    graph, calls, root};
}

const bootstrap = Object.freeze({quantityCapacity: undefined,
  bootstrapRetainedBytes: 3n, bootstrapExecutionBytes: 2n,
  maxReservations: 4, maxHoldings: 2, maxDelegations: 0});
const unavailable = root => ({layout: undefined, installation: undefined,
  runtimeArtifactCid: root, layoutArtifactCid: root, probability: undefined});
const ownerRefusal = error => error.code === 'MoonBitHostFailure';

test('original read scope control uses nominal tokens and keeps failed read cleanup custody', () => {
  const f = original();
  const scope = f.control.beginCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, bootstrap);
  assert.notEqual(f.calls.begin[0][0], f.compiled);
  assert.notEqual(f.calls.begin[0][1], f.definition);
  assert.throws(() => f.control.prepareCheckedClientInferNodeReadLayout(
    f.compiled, f.definition, f.graph, scope, unavailable(f.root)), ownerRefusal);
  assert.equal(f.calls.read.length, 1);
  assert.equal(f.calls.read[0][0], scope);
  assert.equal(f.calls.read[0][1], f.calls.begin[0][0]);
  assert.equal(f.calls.read[0][2], f.calls.begin[0][1]);
  // A read refusal is not the whole-Run physical-cleanup acknowledgement.
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, false), false);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
  assert.throws(() => f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), ownerRefusal);
  assert.equal(f.calls.begin.length, 1, 'no replacement scope or Ledger');
});

test('original read scope control rejects foreign owners before the Common bridge', () => {
  const f = original();
  for (const [compiled, definition] of [
    [f.foreignCompiled, f.definition], [f.compiled, f.foreignDefinition],
  ]) {
    assert.throws(() => f.control.beginCheckedClientInferOriginalReadScope(
      compiled, definition, f.graph, bootstrap), TypeError);
    assert.throws(() => f.control.prepareCheckedClientInferNodeReadLayout(
      compiled, definition, f.graph, undefined, unavailable(f.root)), TypeError);
    assert.throws(() => f.control.finishCheckedClientInferOriginalReadScope(
      compiled, definition, f.graph, undefined, true), TypeError);
  }
  assert.deepEqual(f.calls, {begin: [], read: [], finish: [], settle: []});
});

test('original read scope control refuses absent cleanup without changing original custody', () => {
  const f = original();
  const scope = f.control.beginCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, bootstrap);
  for (const missing of [undefined, null, 0, 'true', {}]) {
    assert.throws(() => f.control.finishCheckedClientInferOriginalReadScope(
      f.compiled, f.definition, f.graph, scope, missing),
    /Invalid original Run cleanup observation/u);
  }
  assert.equal(f.calls.finish.length, 0);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
  assert.equal(f.calls.begin.length, 1);
});

test('original read scope maps installed quantities into the exact Common ABI', () => {
  const f = original();
  const capacity = {limits: {tokens: 10000n, costUnits: 10000n, durationMs: 10000n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}};
  const scope = f.control.beginCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, {...bootstrap, quantityCapacity: capacity});
  assert.deepEqual(f.calls.begin[0][3], {
    limits: {tokens: 10000n, cost_units: 10000n, duration_ms: 10000n},
    per_attempt: {tokens: 33n, cost_units: 0n, duration_ms: 500n},
  });
  assert.notEqual(f.calls.begin[0][3], capacity);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
  assert.deepEqual(capacity, {
    limits: {tokens: 10000n, costUnits: 10000n, durationMs: 10000n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n},
  }, 'installed values are not mutated or replaced by the Common ceiling');
});

test('original read scope rejects invalid installed quantities before bootstrap', () => {
  const f = original();
  const valid = {limits: {tokens: 66n, costUnits: 0n, durationMs: 1000n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}};
  const malformed = [null, {}, {limits: valid.limits},
    {...valid, extra: true},
    {...valid, limits: {...valid.limits, tokens: 66}},
    {...valid, limits: {...valid.limits, tokens: -1n}},
    {...valid, limits: {...valid.limits, tokens: 9007199254740992n}},
    {...valid, perAttempt: {...valid.perAttempt, costUnits: undefined}},
    {...valid, perAttempt: {...valid.perAttempt, durationMs: null}},
    {limits: {tokens: 66n, cost_units: 0n, duration_ms: 1000n},
      per_attempt: {tokens: 33n, cost_units: 0n, duration_ms: 500n}},
  ];
  for (const quantityCapacity of malformed) {
    assert.throws(() => f.control.beginCheckedClientInferOriginalReadScope(
      f.compiled, f.definition, f.graph, {...bootstrap, quantityCapacity}),
    /InvalidInstalledInferQuantityCapacity/u);
  }
  assert.equal(f.calls.begin.length, 0);
});

function admittedOriginalRead(f) {
  // Existing independently sealed input vector, not a numerical Node profile
  // or an expected output derived from the implementation under test.
  const source = readFileSync(new URL(
    '../src/run_publication_host/client_model_preparation_layout_wbtest.mbt',
    import.meta.url), 'utf8');
  const profileWire = source.match(/let wire =\n\s+#\|([^\n]+)/u)[1];
  const profileBody = JSON.parse(profileWire);
  const profile = f.control.readInstalledModelResponseProfile(profileWire,
    profileBody.self_cid, {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 30,
      maxMembers: 1000, maxWork: 100000});
  const installation = {builder_id: 'fixture/http-builder', builder_revision: '1',
    codec_id: 'fixture/chat-one', codec_revision: '1',
    build_artifact_cid: 'sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2',
    sdk: undefined, endpoint: 'https://fixture.invalid/v1/chat/completions',
    http_method: 'POST', streaming: false, validator_id: 'fixture/chat-envelope',
    validator_revision: '1',
    validator_artifact_cid: 'sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd',
    completion_basis: 'generation_finish'};
  const graph = JSON.parse(moon.clientProgramInferPlanGraphWire(f.graph));
  const barrier = graph.nodes.find(node => node.barrier !== undefined).barrier;
  const request = moon.clientProgramRequestIdentity(f.prepared, f.root,
    'read-retirement', f.root);
  const layout = {response_profile: profile, runtime_artifact_cid: f.root,
    layout_artifact_cid: f.root,
    program_definition_cid: moon.clientRequestProgramCid(request),
    parameter_values_cid: moon.clientRequestParametersCid(request),
    barrier_cid: barrier.barrier_cid, prepared_rows: 2n,
    retained_bytes: 7000n, execution_bytes: 3000n};
  const selected = {layout, installation, runtimeArtifactCid: f.root,
    layoutArtifactCid: f.root, probability: undefined};
  const scope = f.control.beginCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, bootstrap);
  const read = f.control.prepareCheckedClientInferNodeReadLayout(
    f.compiled, f.definition, f.graph, scope, selected);
  return {scope, read, selected};
}

test('original read retirement keeps failed cleanup separate from original Run finalization', () => {
  const f = original();
  const {scope, read, selected} = admittedOriginalRead(f);
  // The actual one-shot read consumer is stopped, not a recreated input owner.
  f.control.claimCheckedClientInferNodePreparationLayout(
    f.compiled, f.definition, f.graph, read, selected);
  assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, false), ownerRefusal);
  assert.throws(() => f.control.claimCheckedClientInferNodePreparationLayout(
    f.compiled, f.definition, f.graph, read, selected), ownerRefusal);
  f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, true);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, false), false);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
  assert.equal(f.calls.begin.length, 1);
  assert.equal(f.calls.read.length, 1);
  assert.equal(f.calls.settle.length, 2);
});

test('original read retirement rejects foreign and same-Program different Run originals', () => {
  const f = original();
  const {scope, read} = admittedOriginalRead(f);
  assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
    f.foreignCompiled, f.definition, f.graph, read, true), TypeError);
  assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.foreignDefinition, f.graph, read, true), TypeError);
  assert.equal(f.calls.settle.length, 0);
  const otherRun = f.control.defineCheckedClientCompiledRun(f.compiled,
    {namespaceId: 'scope', runId: 'other', createdAt: '2026-10-02T00:00:00.000Z',
      validUntil: '2099-01-01T00:00:00.000Z'});
  for (const complete of [false, true]) {
    assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
      f.compiled, otherRun, f.graph, read, complete), ownerRefusal);
  }
  f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, true);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
});

test('original read retirement requires explicit physical cleanup and refuses duplicate settlement', () => {
  const f = original();
  const {scope, read} = admittedOriginalRead(f);
  for (const missing of [undefined, null, 0, 'true', {}]) {
    assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
      f.compiled, f.definition, f.graph, read, missing),
    /Invalid original read cleanup observation/u);
  }
  assert.equal(f.calls.settle.length, 0);
  f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, true);
  assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, true), ownerRefusal);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
});

test('original read stop authenticates its own scope before physical cleanup', () => {
  const f = original();
  const {scope, read, selected} = admittedOriginalRead(f);
  const otherScope = f.control.beginCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, bootstrap);
  assert.throws(() => f.control.stopCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, otherScope, read), ownerRefusal);
  f.control.claimCheckedClientInferNodePreparationLayout(
    f.compiled, f.definition, f.graph, read, selected);
  f.control.stopCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, scope, read);
  assert.throws(() => f.control.claimCheckedClientInferNodePreparationLayout(
    f.compiled, f.definition, f.graph, read, selected), ownerRefusal);
  assert.throws(() => f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, false), ownerRefusal);
  f.control.settleCheckedClientInferOriginalReadPreparation(
    f.compiled, f.definition, f.graph, read, true);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, scope, true), true);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(
    f.compiled, f.definition, f.graph, otherScope, true), true);
});
