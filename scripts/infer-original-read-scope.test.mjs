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
  const calls = {begin: [], read: [], finish: []};
  const consumingMoon = {...moon};
  for (const [name, kind] of [
    ['clientProgramBeginInferOriginalReadScope', 'begin'],
    ['clientProgramPrepareInferNodeReadLayout', 'read'],
    ['clientProgramFinishInferOriginalReadScope', 'finish'],
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
  return {control, compiled, definition: define(control, compiled, 'original'),
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
  assert.deepEqual(f.calls, {begin: [], read: [], finish: []});
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
