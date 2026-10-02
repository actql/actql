import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {mkdtemp, open, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';

import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../adapters/store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../adapters/host-common/publication-contract-control.fixture.mjs';
import {openNodeInferOperation} from '../adapters/host-node/infer-operation.mjs';
import {installNodeClientDispatchOwner} from
  '../adapters/host-node/client-dispatch-owner.mjs';
import {inferTaskRunAdmission, inferTaskPublicationPlan} from
  '../adapters/host-node/local-values-plan.mjs';
import {inferPublicationExecution} from
  '../adapters/host-node/infer-result-publication.mjs';
import {publishCompletedEffectFreeRun} from
  '../adapters/host-common/completed-run-publication.mjs';

// Reuse the independently hashed typing vector, not an execution result.
const taskSource = readFileSync(new URL(
  '../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
const {evidence_bundle_cid: ignored, ...baseEnvironment} = JSON.parse(
  readFileSync(new URL('../spec/local-check-environment.json',
    import.meta.url), 'utf8'));
void ignored;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;

function environment(installTask = true, hostItems, installedTask = task,
  capacityOverrides = {}) {
  const body = {...baseEnvironment,
    model_task_contracts: installTask ? [installedTask] : []};
  if (hostItems !== undefined || Object.keys(capacityOverrides).length > 0) {
    body.host_policy_profile = {...body.host_policy_profile,
      capacity: {...body.host_policy_profile.capacity, ...capacityOverrides,
        ...(hostItems === undefined ? {} : {max_infer_items: hostItems})}};
  }
  const evidenceCid = cid(body);
  return moon.clientProgramCheckEnvironment(
    canonicalText({...body, evidence_bundle_cid: evidenceCid}), evidenceCid,
    false, false, true, false, false, false, false);
}

function program() {
  return {version: 'actql/0.1', id: 'infer-owner-checker', stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {
        id: {type: 'string', nullable: false},
        text: {type: 'string', nullable: true},
      }, rows: [{id: 'a', text: 'hello'}]}, as: 'input'},
      {assert_rows: {unique_by: ['id']}, as: 'unique'},
      {infer: {contract: 'model-task:risk-score.v1', key: 'id',
        input: {text: {field: 'text'}}}, as: 'captured'},
    ], results: {captured: {from: 'captured',
      fields: ['id', 'outcome', 'value']}},
  }], results: {answer: {from: {stage: 'main', result: 'captured'}}}};
}

const prepare = (source, owner) =>
  moon.clientProgramPrepareEffectFreeWithParameters(
    canonicalText(source), 'json', owner, undefined);

const registry = readFileSync(new URL(
  '../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
const values = canonicalText(JSON.parse(readFileSync(new URL(
  '../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'))
  .execution_contracts['REL.values']);
const checked = value => {
  assert.equal(value?.$tag, 1, inspect(value, {depth: 3}));
  return value._0;
};

test('bounded Infer admission fixtures match their existing checked owners', () => {
  execFileSync(process.execPath, ['scripts/infer-host-fixtures.mjs'],
    {stdio: 'pipe'});
});

test('normal Program emits a model barrier without pretending it is pure AoA', () => {
  const source = program();
  const prepared = moon.clientProgramPreparationReady(
    prepare(source, environment()));
  assert.ok(prepared);
  // These independent dependency pins exercise compilation identity, not
  // current Host authorization or executable retry/egress policy.
  const executionBody = {
    version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: `sha256:${'a'.repeat(64)}`,
    backoff_contract_cid: `sha256:${'a'.repeat(64)}`,
    max_attempts_per_slot: 2, max_total_attempts: 4,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_wire_bytes: 2048, max_total_token_reservation: 128,
    media_input_contracts: {}, default_publication: 'outcomes',
  };
  const executionCid = cid(executionBody);
  const executionWire = canonicalText({...executionBody, self_cid: executionCid});
  const execution = checked(moon.clientProgramReadInferModelExecution(
    prepared, 2, executionWire, executionCid));
  const limitsCid = `sha256:${'b'.repeat(64)}`;
  const egressCid = `sha256:${'c'.repeat(64)}`;
  const compiled = checked(moon.clientProgramInferPlanGraph(
    prepared, 2, execution, limitsCid, egressCid));
  const material = checked(moon.clientProgramInferExecutionMaterial(prepared,
    compiled));
  const template = JSON.parse(
    moon.clientProgramInferExecutionMaterialTemplateWire(material));
  const {bound_invocation_template_cid: templateCid, ...templateBody} = template;
  assert.equal(templateCid, cid(templateBody));
  assert.deepEqual(template.required_profile_contracts, [{
    profile_id: 'actql-infer/0.1',
    contract_cid: 'sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd',
  }]);
  assert.equal(template.source_evidence, 'unbound');
  assert.equal(template.model_invocation_evidence, undefined);
  const executionMaterial = JSON.parse(
    moon.clientProgramInferExecutionMaterialWire(material));
  assert.equal(executionMaterial.invocation_template_cid, templateCid);
  assert.deepEqual(Object.keys(executionMaterial.result_plan_logical_cids),
    ['answer']);
  assert.deepEqual(executionMaterial.program.stages[0].steps[2].infer.input,
    {text: {field: 'text'}});
  assert.equal(executionMaterial.program.stages[0].steps[2].infer.contract,
    'model-task:risk-score.v1');
  const graph = JSON.parse(moon.clientProgramInferPlanGraphWire(compiled));
  assert.deepEqual(graph.nodes.map(node => node.kind),
    ['aoa_fragment', 'acquisition_barrier']);
  const [prefix, acquisition] = graph.nodes;
  const request = {text: {op: 'field', body: 'text'}};
  assert.deepEqual(JSON.parse(moon.clientProgramInferPlanRequestWire(compiled)), request);
  const {barrier_cid: barrierCid, ...barrierBody} = acquisition.barrier;
  assert.equal(barrierCid, cid(barrierBody));
  assert.deepEqual(barrierBody, {
    version: 'actql-inference-barrier/0.1',
    model_execution_contract_cid: executionCid,
    model_task_contract_cid: task.contract_cid,
    request_fragment_cid: cid(request),
    input_contract_cid: prefix.output_contracts[prefix.pipeline.output],
    output_contract_cid: cid({type: 'object', nullable: false,
      additional_properties: false, fields: {
        id: {type: 'string', nullable: false},
        outcome: {type: 'string', nullable: false},
        value: {...task.output_contract, nullable: true},
      }}),
    key_fields: ['id'], input_roles: {text: '/text'}, on_non_success: 'outcomes',
    input_fragment_cid: cid(prefix.pipeline), limits_cid: limitsCid,
    egress_requirements_cid: egressCid,
  });
  assert.equal(acquisition.profile_id, 'actql-infer/0.1');
  assert.deepEqual(graph.data_edges, [{carrier: 'relation',
    contract_cid: barrierBody.input_contract_cid,
    from: {node_id: prefix.node_id, port: prefix.pipeline.output},
    to: {node_id: acquisition.node_id, port: 'input_0'},
  }]);
  assert.deepEqual(graph.root_refs, [{name: 'answer', role: 'requested_result',
    ref: {node_id: acquisition.node_id, port: acquisition.output_ref}}]);
  const foreign = moon.clientProgramPreparationReady(prepare(source, environment()));
  assert.equal(moon.clientProgramInferExecutionMaterial(foreign, compiled).$tag,
    0, 'equal Program bytes do not substitute for the graph owner');
  assert.equal(moon.clientProgramInferPlanGraph(
    foreign, 2, execution, limitsCid, egressCid).$tag, 0);
  assert.equal(moon.clientProgramReadInferModelExecution(
    prepared, 2, executionWire, limitsCid).$tag, 0);
  assert.equal(moon.clientProgramInferPlanGraph(
    prepared, 2, execution, `sha256:${'G'.repeat(64)}`, egressCid).$tag, 0);

  // The ordinary compiled Run owner retains the checked barrier. This is
  // compilation admission only, not provider authorization or publication.
  const control = runtimeCore(moon).publicationControl;
  const policy = {executionContextCid: `sha256:${'d'.repeat(64)}`,
    hostPolicyCid: `sha256:${'e'.repeat(64)}`,
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const run = control.prepareCheckedClientCompiledRun(
    prepared, 'infer', policy, compiled);
  assert.deepEqual(JSON.parse(run.template.wire).required_profile_contracts,
    template.required_profile_contracts);
  const definition = control.defineCheckedClientCompiledRun(run,
    {namespaceId: 'infer-compilation', runId: 'normal-program',
      createdAt: '2026-10-01T00:00:00.000Z', validUntil: policy.expiresAt});
  assert.throws(() => control.issueCheckedClientCompiledInvocation(run,
    definition, {dataPolicyCid: `sha256:${'f'.repeat(64)}`},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
  /RunHostInvocationRejected/u,
  'source-free input cannot erase the containing model observation');
  assert.throws(() => control.prepareCheckedClientCompiledRun(
    prepared, 'infer', policy), /requires its checked graph/u);
  assert.throws(() => control.prepareCheckedClientCompiledRun(
    foreign, 'infer', policy, compiled), /RunHostTaskCompilationRejected/u);
  assert.throws(() => control.prepareCheckedClientCompiledRun(
    prepared, 'tasks', policy, compiled), /requires its checked graph/u);
  const options = {control, preparedProgram: prepared, inferGraph: compiled,
    authorityScopeCid: `sha256:${'d'.repeat(64)}`,
    namespaceId: 'infer-compilation',
    now: () => '2026-10-01T00:00:00.000Z'};
  const admitted = inferTaskRunAdmission(options);
  assert.equal(admitted.kind, 'infer');
  assert.equal(admitted.inferGraph, compiled);
  assert.equal(admitted.compiledPlan.identity, run.compiledPlan.identity);
  assert.equal(admitted.observation, undefined);
  assert.equal(admitted.invocation, undefined);
  control.checkClientCompiledRunOwner(admitted.compiled, prepared);
  const restored = inferTaskRunAdmission({...options,
    now: () => '2026-10-01T00:05:00.000Z',
    retainedDefinitionWire: admitted.runDefinition.wire});
  assert.equal(restored.runDefinition.identity, admitted.runDefinition.identity);
  assert.throws(() => inferTaskRunAdmission({...options,
    preparedProgram: foreign}), /RunHostTaskCompilationRejected/u);
  assert.throws(() => inferTaskRunAdmission({...options,
    inferGraph: undefined}), /MissingInstalledInferGraph/u);
});

test('Infer compilation retains the same pure prefix as bounded execution', () => {
  const source = program();
  const prepared = moon.clientProgramPreparationReady(
    prepare(source, environment()));
  assert.ok(prepared);
  const prefix = JSON.parse(moon.clientProgramTaskFragmentWire(checked(
    moon.clientProgramInferPrefixFragment(prepared, 0, 2))));
  assert.equal(prefix.kind, 'aoa_fragment');
  assert.equal(prefix.node_id, 'task_0_before_infer_2');
  assert.deepEqual(prefix.input_contracts, {});
  assert.equal(prefix.logical_cid, cid(prefix.pipeline));
  assert.equal(prefix.output_contracts[prefix.pipeline.output], cid({
    type: 'object', nullable: false, additional_properties: false,
    fields: {id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true}},
  }));

  // Compile an ordinary pure Program independently, rather than removing
  // nodes from the fragment returned for the Infer Program under test.
  const pure = program();
  pure.stages[0].steps.pop();
  pure.stages[0].results.captured = {from: 'unique', fields: ['id', 'text']};
  const purePrepared = moon.clientProgramPreparationReady(
    prepare(pure, environment()));
  assert.ok(purePrepared);
  const pureFragment = JSON.parse(moon.clientProgramTaskFragmentWire(checked(
    moon.clientProgramIssueTaskFragment(purePrepared, 0))));
  assert.deepEqual(prefix.pipeline, pureFragment.pipeline);
  assert.equal(prefix.logical_cid, pureFragment.logical_cid);
  assert.deepEqual(prefix.output_contracts, pureFragment.output_contracts);

  const strict = program();
  strict.stages[0].steps[2].infer.on_non_success = 'fail';
  const strictPrepared = moon.clientProgramPreparationReady(
    prepare(strict, environment()));
  assert.ok(strictPrepared);
  const strictPrefix = JSON.parse(moon.clientProgramTaskFragmentWire(checked(
    moon.clientProgramInferPrefixFragment(strictPrepared, 0, 2))));
  assert.deepEqual(strictPrefix, prefix,
    'acquisition policy does not change adjacent pure computation identity');

  for (const [taskIndex, step] of [[1, 2], [0, 0], [0, 1], [0, 3]]) {
    assert.equal(moon.clientProgramInferPrefixFragment(
      prepared, taskIndex, step).$tag, 0);
  }
  assert.equal(moon.clientProgramIssueTaskFragment(prepared, 0).$tag, 0,
    'the acquisition cannot be misrepresented as a pure AoA task');
  assert.equal(moon.clientProgramCompileLocalTasks(prepared).$tag, 0,
    'a prefix alone does not authorize a complete acquisition Plan');
});

function startInput(source = program()) {
  const prepared = moon.clientProgramPreparationReady(
    prepare(source, environment()));
  assert.ok(prepared);
  const input = moon.clientProgramStartInferInput(
    prepared, registry, values, 2);
  assert.ok(input);
  return input;
}

async function acceptedModel() {
  const source = program();
  const prepared = moon.clientProgramPreparationReady(
    prepare(source, environment()));
  const input = moon.clientProgramStartInferInput(prepared, registry, values, 2);
  const rows = await mappedRows(input);
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    request => {
      calls++;
      return moon.clientProgramModelResponse(request,
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  const active = checked(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`));
  assert.equal((await modelTerminal(active)).$tag, 1);
  return {prepared, input, rows, active, calls: () => calls};
}

function scopedInferGraph(prepared, installedTask = task, capacity = {}) {
  // Admit a two-request envelope: 2 * (1000 + 65536). Retry/backoff pins
  // still exercise binding only, not executable policy/egress admission.
  const body = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: installedTask.contract_cid,
    retry_classification_contract_cid: `sha256:${'a'.repeat(64)}`,
    backoff_contract_cid: `sha256:${'a'.repeat(64)}`,
    max_attempts_per_slot: 2, max_total_attempts: 4,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_wire_bytes: 133072, max_total_token_reservation: 128,
    media_input_contracts: {}, default_publication: 'outcomes', ...capacity};
  const identity = cid(body);
  const execution = checked(moon.clientProgramReadInferModelExecution(
    prepared, 2, canonicalText({...body, self_cid: identity}), identity));
  return checked(moon.clientProgramInferPlanGraph(prepared, 2,
    execution, `sha256:${'b'.repeat(64)}`, `sha256:${'c'.repeat(64)}`));
}

function ownedInfer(source = program(), onInvoke, options = {}) {
  const installedTask = options.installedTask ?? task;
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
      canonicalText(source), 'json', environment(true, options.hostItems, installedTask,
        options.capacityOverrides),
      options.parameters === undefined ? undefined : canonicalText(options.parameters));
  const prepared = moon.clientProgramPreparationReady(preparation);
  assert.ok(prepared, inspect(preparation, {depth: 4}));
  let active;
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    request => {
      calls++;
      assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
        '"hello"');
      onInvoke?.(active);
      return moon.clientProgramModelResponse(request,
        options.responseBody ?? '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  if (options.scoped === true) {
    const graph = scopedInferGraph(prepared, installedTask);
    active = checked(moon.clientProgramStartScopedInferExecution(
      prepared, 2, graph, registry, values, provider));
  } else {
    active = checked(moon.clientProgramStartInferExecution(
      prepared, 2, registry, values, provider, `sha256:${'1'.repeat(64)}`));
  }
  return {prepared, active, calls: () => calls};
}

async function modelTerminal(active, initialWork = 0n) {
  let lastWork = initialWork;
  for (let poll = 0; poll < 20000; poll++) {
    const value = checked(moon.clientProgramAdvanceModelExecution(active, 1));
    const work = value._2 ?? value._1;
    assert.ok(work >= lastWork && work - lastWork <= 1n);
    lastWork = work;
    if (value.$tag !== 0) return value;
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('model did not reach its independent finite poll ceiling');
}

test('a macrotask cancellation stops nested response admission without replaying dispatch', async () => {
  const arrayTask = structuredClone(task);
  arrayTask.output_contract.fields.risk = {type: 'array', nullable: false,
    max_items: 4096, items: {type: 'number', nullable: false}};
  arrayTask.output_schema_cid = cid(arrayTask.output_contract);
  delete arrayTask.contract_cid;
  arrayTask.contract_cid = cid(arrayTask);
  const prepared = moon.clientProgramPreparationReady(
    prepare(program(), environment(true, undefined, arrayTask)));
  assert.ok(prepared);
  const response = canonicalText({reason: null,
    risk: Array.from({length: 4096}, (_, index) => index)});
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture', request => {
    calls++;
    return moon.clientProgramModelResponse(request, response, 'fixture-array-model',
      'array-response-1', 1n, 4096n, '2026-10-01T00:00:00.000Z');
  });
  const active = checked(moon.clientProgramStartInferExecution(
    prepared, 2, registry, values, provider, `sha256:${'1'.repeat(64)}`));
  for (let poll = 0; poll < 2000 && calls === 0; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 0);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(calls, 1);
  for (let poll = 0; poll < 64; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 0);
    assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferExecution(active), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 3);
  assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
  assert.equal(moon.clientProgramInferExecutionOutput(active), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(calls, 1);
});

async function ownedInferTerminal(active, atYield, maxPolls = 2000) {
  let lastWork = 0n;
  for (let poll = 0; poll < maxPolls; poll++) {
    const value = checked(moon.clientProgramAdvanceInferExecution(active, 1));
    const work = value.$tag === 0 || value.$tag === 3 ? value._0 : value._1;
    assert.ok(work >= lastWork && work - lastWork <= 1n,
      'child transitions preserve cumulative work and the quantum');
    lastWork = work;
    if (value.$tag !== 0) return value;
    atYield?.();
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('owned inference failed to settle within the finite poll bound');
}

test('actual Host request ceilings reject a late row before any dispatch', async () => {
  const source = program();
  const exact = ownedInfer(source, undefined, {capacityOverrides: {
    max_model_request_bytes_per_item: 16,
  }});
  assert.equal((await ownedInferTerminal(exact.active)).$tag, 1);
  assert.equal(exact.calls(), 1);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(exact.active)), true);
  const late = structuredClone(source);
  late.stages[0].steps[0].values.rows.push({id: 'b', text: 'longer'});
  for (const [candidate, requestBytes] of [[source, 15], [late, 16]]) {
    const {active, calls} = ownedInfer(candidate, undefined, {capacityOverrides: {
      max_model_request_bytes_per_item: requestBytes,
    }});
    const failed = await ownedInferTerminal(active);
    assert.equal(failed.$tag, 2, inspect(failed));
    assert.equal(failed._0.$tag, 2, 'the common model owner rejects preflight');
    assert.equal(failed._0._0.$tag, 12, 'exact Model(RequestLimit) cause');
    assert.equal(calls(), 0);
    assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
    assert.equal(moon.clientProgramAcquireInferOutput(active), undefined);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(calls(), 0);
  }
});

test('macrotask cancellation stops nested request preflight before model access', async () => {
  const source = program();
  const arrayTask = structuredClone(task);
  const inputType = {type: 'array', nullable: true, max_items: 1024,
    items: {type: 'number', nullable: false}};
  source.stages[0].steps[0].values.schema.text = inputType;
  source.stages[0].steps[0].values.rows[0].text =
    Array.from({length: 1024}, (_, index) => index);
  arrayTask.input_contract.fields.text = inputType;
  arrayTask.input_schema_cid = cid(arrayTask.input_contract);
  delete arrayTask.contract_cid;
  arrayTask.contract_cid = cid(arrayTask);
  const preparation = prepare(source, environment(true, undefined, arrayTask, {
    max_model_request_bytes_per_item: 65536, max_nested_value_bytes: 10000,
  }));
  const prepared = moon.clientProgramPreparationReady(preparation);
  assert.ok(prepared, inspect(preparation, {depth: 4}));
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture', request => {
    calls++;
    return moon.clientProgramModelResponse(request,
      '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
      1n, 2n, '2026-10-01T00:00:00.000Z');
  });
  const active = checked(moon.clientProgramStartInferExecution(
    prepared, 2, registry, values, provider, `sha256:${'1'.repeat(64)}`));
  let reached = false;
  let last = 0n;
  for (let poll = 0; poll < 50000; poll++) {
    const observation = checked(moon.clientProgramAdvanceInferExecution(active, 1));
    assert.equal(observation.$tag, 0, inspect(observation));
    assert.ok(observation._0 >= last && observation._0 - last <= 1n);
    last = observation._0;
    if (moon.clientProgramInferRequestPreflightPending(active)) {
      reached = true;
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(reached, true, 'the normal Program reached model preflight');
  for (let poll = 0; poll < 64; poll++) {
    const observation = checked(moon.clientProgramAdvanceInferExecution(active, 1));
    assert.equal(observation.$tag, 0);
    assert.ok(observation._0 >= last && observation._0 - last <= 1n);
    last = observation._0;
    assert.equal(moon.clientProgramInferRequestPreflightPending(active), true);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(calls, 0);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferExecution(active), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false,
    'a cancellation request is not physical stop confirmation');
  const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
  assert.equal(stopped.$tag, 3);
  assert.equal(moon.clientProgramInferRequestPreflightPending(active), false);
  assert.equal(moon.clientProgramInferExecutionOutput(stopped), undefined);
  assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(calls, 0);
});

test('one MoonBit owner executes the checked prefix, model and Result output', async () => {
  const {prepared, active, calls} = ownedInfer(undefined, owner => {
    assert.equal(moon.clientProgramAdvanceInferExecution(owner, 1).$tag, 0,
      'reentrant advance cannot dispatch another request');
  });
  assert.equal(calls(), 0);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  const terminal = await ownedInferTerminal(active);
  assert.equal(terminal.$tag, 1, inspect(terminal));
  const completed = moon.clientProgramInferExecutionOutput(terminal);
  assert.ok(completed);
  const a = moon.clientProgramAcquireInferOutput(active);
  const b = moon.clientProgramAcquireInferOutput(active);
  assert.ok(a && b);
  assert.equal(moon.clientProgramInferOutputUse(a), completed);
  assert.equal(moon.clientProgramInferOutputUse(b), completed);
  const transform = checked(moon.clientProgramInferResultExportBegin(
    prepared, 0, moon.clientProgramInferOutputUse(a)));
  for (let poll = 0; poll < 200; poll++) {
    if (checked(moon.clientProgramInferResultExportAdvance(transform, 1))._0) break;
    await new Promise(resolve => setImmediate(resolve));
  }
  const stream = checked(moon.clientProgramInferResultExportFinish(transform));
  let wire = '';
  for (let chunk = 0; chunk < 20; chunk++) {
    const next = checked(moon.clientProgramInferResultExportNext(stream));
    if (next === undefined) break;
    wire += next;
  }
  wire += checked(moon.clientProgramInferResultExportSeal(stream));
  assert.deepEqual(JSON.parse(wire), [
    {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
  ]);
  const capture = moon.clientProgramInferExecutionCapture(active);
  assert.equal(JSON.parse(moon.clientProgramModelCaptureJson(capture))
    .captures.length, 1);
  moon.clientProgramInferResultExportClose(stream);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  assert.equal(moon.clientProgramReleaseInferOutput(a), true);
  assert.equal(moon.clientProgramReleaseInferOutput(a), false);
  assert.equal(moon.clientProgramInferOutputUse(a), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  assert.equal(moon.clientProgramInferOutputUse(b), completed);
  assert.equal(moon.clientProgramReleaseInferOutput(b), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(moon.clientProgramAcquireInferOutput(active), undefined);
  assert.equal(calls(), 1);
});

test('scoped normal inference reconstructs a stable slot from its completed input', async () => {
  const slots = [];
  for (let reconstruction = 0; reconstruction < 2; reconstruction++) {
    const {active, calls} = ownedInfer(undefined, undefined, {scoped: true});
    const terminal = await ownedInferTerminal(active);
    assert.equal(terminal.$tag, 1, inspect(terminal));
    assert.equal(calls(), 1);
    const capture = JSON.parse(moon.clientProgramModelCaptureJson(
      moon.clientProgramInferExecutionCapture(active)));
    assert.equal(capture.captures.length, 1);
    assert.equal(capture.captures[0].input_key_cid,
      'sha256:042a400915c1e3c348ec713c0e6b496f28dcde211e33c64fbada352b6e6e7011');
    const admittedEvidence = moon.clientProgramInferInvocationEvidence(active, 0);
    assert.ok(admittedEvidence);
    const evidence = JSON.parse(moon.strategyRunEvidenceJson(admittedEvidence));
    const {model_invocation_evidence_cid: evidenceCid, ...preimage} = evidence;
    assert.equal(evidenceCid, cid(preimage));
    assert.equal(evidence.model_task_contract_cid, task.contract_cid);
    assert.equal(evidence.semantic_request_cid, capture.fixed_request_cid);
    assert.equal(evidence.model_call_slot_cid, capture.captures[0].slot_cid);
    assert.equal(evidence.input_row_identity_cid, capture.captures[0].input_key_cid);
    assert.equal(evidence.input_row_identity, 'a');
    assert.equal(evidence.authored_model_selector, 'fixture-risk-model');
    assert.equal(evidence.provider_reported_model_id, 'fixture-risk-model');
    assert.equal(evidence.provider_request_id, 'request-1');
    assert.equal(evidence.attempt, 1);
    assert.equal(evidence.structured_response_artifact_cid,
      cid({reason: null, risk: 'high'}));
    assert.equal(evidence.validated_structured_output_cid,
      cid({reason: null, risk: 'high'}));
    assert.equal(evidence.input_tokens, 1);
    assert.equal(evidence.output_tokens, 2);
    assert.equal(evidence.finish_reason, 'stop');
    assert.equal(evidence.observed_at, '2026-10-01T00:00:00.000Z');
    assert.equal(moon.clientProgramInferInvocationEvidence(active, 1), undefined);
    slots.push(capture.captures[0].slot_cid);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(moon.clientProgramInferInvocationEvidence(active, 0), undefined);
    assert.equal(calls(), 1);
  }
  assert.equal(slots[0], slots[1]);
});

async function inferExportRows(prepared, completed) {
  const transform = checked(moon.clientProgramInferResultExportBegin(
    prepared, 0, completed));
  let ready = false;
  for (let poll = 0; poll < 2000; poll++) {
    if (checked(moon.clientProgramInferResultExportAdvance(transform, 1))._0) {
      ready = true;
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(ready, true);
  const stream = checked(moon.clientProgramInferResultExportFinish(transform));
  try {
    let wire = '';
    let next;
    while ((next = checked(moon.clientProgramInferResultExportNext(stream))) !== undefined) {
      wire += next;
    }
    wire += checked(moon.clientProgramInferResultExportSeal(stream));
    return JSON.parse(wire);
  } finally {
    moon.clientProgramInferResultExportClose(stream);
  }
}

function supervisedInferFixture(signal, onInvoke, responseBody = '{"reason":null,"risk":"high"}',
  source = program(), quantityCapacity) {
  const preparation = prepare(source, environment());
  const prepared = moon.clientProgramPreparationReady(preparation);
  assert.ok(prepared, inspect(preparation));
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    request => {
      calls++;
      onInvoke?.();
      assert.equal(moon.clientProgramModelRequestInput(request, 'text'), '"hello"');
      return moon.clientProgramModelResponse(request,
        responseBody, 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  const graph = scopedInferGraph(prepared);
  const operation = openNodeInferOperation({moon, preparedProgram: prepared,
    step: 2, graph, registry, values, provider,
    signal, quantum: 1, quantityCapacity});
  return {prepared, graph, operation, calls: () => calls};
}

// Component harness for the common bounded issuer. This is not a replacement
// for installed Host dispatch, capture custody or committed Result publication.
async function issueOwnedInferObservation(operation, control, compiled,
  runDefinition) {
  const ledger = checked(moon.clientProgramInferPublicationLedger(262272n, 3));
  const active = operation.startObservation({ledger, maxSlots: 1,
    maxWireBytes: 16384, maxWork: 3});
  try {
    for (let poll = 0; poll < 3; poll++) {
      const progress = checked(moon.clientProgramAdvanceInferObservationIssuance(
        active, 1));
      assert.equal(progress._1, BigInt(poll + 1));
      if (progress._0) {
        const issued = operation.bindIssuedInvocation(control,
          {compiled, runDefinition, issued: active});
        return {...issued, active, ledger};
      }
      await new Promise(resolve => setImmediate(resolve));
    }
    assert.fail('the declared three-step observation did not complete');
  } catch (error) {
    moon.clientProgramCancelInferObservationIssuance(active);
    try { moon.clientProgramAdvanceInferObservationIssuance(active, 1); }
    finally { checked(moon.clientProgramCleanupInferObservationIssuance(active)); }
    throw error;
  }
}

test('issued INFER output uses the ordinary retained Result exporter', async t => {
  const fixture = supervisedInferFixture();
  const {prepared, graph, operation} = fixture;
  const core = runtimeCore(moon);
  const control = core.publicationControl;
  const scope = cid({fixture: 'retained-infer-output'});
  const now = () => '2026-10-02T00:00:00.000Z';
  const options = {moon, control, preparedProgram: prepared, inferGraph: graph,
    namespaceId: 'infer-store', authorityScopeCid: scope,
    storeAuthorityCid: scope, now};
  const admitted = inferTaskRunAdmission(options);
  const account = moon.executionAuthorizationAdmit(canonicalText({
    version: 'actql-execution-account-config/0.1', account_id: 'model-account',
    entries: [{entry_id: 'infer-policy', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['infer']}, exclusions: []}],
  }));
  const directory = await mkdtemp(join(tmpdir(), 'actql-infer-result-'));
  let issued, publication, store, stored;
  try {
    operation.bindRun(control, admitted);
    operation.bindDispatch(control, {...admitted, account,
      principalId: 'fixture-principal', at: now(),
      observeAccount: () => account, observeAt: now});
    await operation.run();
    issued = await issueOwnedInferObservation(operation, control,
      admitted.compiled, admitted.runDefinition);
    const evidence = control.admitRunEvidence('model_invocation_evidence',
      moon.strategyRunEvidenceJson(operation.invocationEvidence(0)),
      {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
    publication = inferTaskPublicationPlan({...options, admitted, operation,
      issuance: issued.active, modelEvidence: [evidence]});
    const execution = inferPublicationExecution({moon, core, operation,
      binding: publication.binding, compiled: admitted.compiled,
      preparedProgram: prepared});
    assert.deepEqual(execution.resultInventory.map(item => item.name), ['answer']);
    store = await openLocalPublicationStore({directory, storeAuthorityCid: scope,
      capacityBytes: 20 * 1024 * 1024, maxObjectBytes: 10000000, maxObjects: 100,
      maxContractNodes: 100000, maxContractDepth: 100}, control);
    const plan = publication.plan;
    stored = await execution.storePublicationResult(0, store, {
      ...plan.results[0], outputLimits: plan.outputLimits,
      contractLimits: plan.contractLimits, runDefinition: plan.runDefinition,
      invocation: plan.invocation});
    let text = '';
    await store.consumeObject(stored.physical.cid, chunk => {
      text += Buffer.from(chunk).toString('utf8');
    });
    assert.deepEqual(JSON.parse(text),
      [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
    assert.equal(stored.occurrence.name, 'answer');
    assert.equal(stored.publication.artifact.name, 'result_artifact');
    await stored.prepared.release();
    stored = undefined;
    const published = await publishCompletedEffectFreeRun({
      ...plan, execution, store, control, signal: undefined});
    assert.equal(published.results.length, 1);
    const key = {namespaceId: 'infer-store', authorityScopeCid: scope,
      runDefinitionCid: admitted.runDefinition.identity};
    assert.notEqual(await store.confirmCommittedIndex(key), undefined);
    const definitionCid = published.evidence.definitions[0].identity;
    const chunks = [];
    const consumed = await store.consumeCommittedResult(key, definitionCid,
      request => request.runDefinitionCid === key.runDefinitionCid &&
        request.resultDefinitionCid === definitionCid,
      chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(consumed.rowCount, 1);
    assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')),
      [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
    assert.equal(fixture.calls(), 1);
  } catch (error) {
    t.diagnostic(inspect(error, {depth: 5}));
    await error.cleanupHandle?.retry();
    throw error;
  } finally {
    await stored?.prepared.release();
    if (publication) moon.clientProgramReleaseInferInvocationBinding(publication.binding);
    if (issued) {
      moon.clientProgramReleaseInferInvocationBinding(issued.binding);
      assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(
        issued.active)), true);
    }
    await operation.close();
    await store?.close();
    await rm(directory, {recursive: true, force: true});
  }
});

test('Node Infer binds existing account authority and reads common issued attempt proofs', async () => {
  for (const outcome of ['allow', 'deny']) {
    const fixture = supervisedInferFixture(undefined, undefined, undefined,
      program(), {limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
        perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}});
    const {prepared, graph, operation} = fixture;
    const control = runtimeCore(moon).publicationControl;
    const root = cid({fixture: 'infer-component-policy'});
    const policy = {executionContextCid: root, hostPolicyCid: root,
      expiresAt: '2099-01-01T00:00:00.000Z'};
    const compiled = control.prepareCheckedClientCompiledRun(prepared,
      'infer', policy, graph);
    const runDefinition = control.defineCheckedClientCompiledRun(compiled,
      {namespaceId: 'infer-proof-test', runId: outcome,
        createdAt: '2026-10-02T00:00:00.000Z', validUntil: policy.expiresAt});
    const account = moon.executionAuthorizationAdmit(canonicalText({
      version: 'actql-execution-account-config/0.1',
      account_id: 'model-account', entries: [{entry_id: 'infer-policy',
        outcome, principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['infer']}, exclusions: []}],
    }));
    try {
      operation.bindRun(control, {compiled, runDefinition});
      const bind = () => operation.bindDispatch(control, {compiled,
        runDefinition, account, principalId: 'fixture-principal',
        at: '2026-10-02T00:00:00.000Z', observeAccount: () => account,
        observeAt: () => '2026-10-02T00:00:00.000Z'});
      if (outcome === 'deny') {
        assert.throws(bind, /MoonBitHostFailure/u);
        assert.equal(fixture.calls(), 0);
        assert.equal(operation.acquireOutput(), undefined);
        continue;
      }
      bind();
      const completed = await operation.run();
      assert.deepEqual(await inferExportRows(prepared, completed),
        [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
      const proof = operation.attemptEvidence(0);
      const leaves = Object.fromEntries(
        ['attempt', 'accounting', 'outcome', 'authority'].map(kind => [kind,
          JSON.parse(moon.strategyRunEvidenceJson(
            moon.clientProgramInferAttemptLeaf(proof, kind)))]));
      const capture = JSON.parse(moon.strategyRunEvidenceJson(
        operation.issuedSlotCapture(0)));
      assert.deepEqual(capture.ordered_attempt_cids, [leaves.attempt.self_cid]);
      assert.equal(capture.accounting_evidence_cid, leaves.accounting.self_cid);
      assert.equal(capture.authority_evidence_cid, leaves.authority.self_cid);
      assert.equal(capture.outcome_evidence_cid, leaves.outcome.self_cid);
      assert.equal(leaves.authority.basis, 'account_allow');
      assert.deepEqual(leaves.authority.satisfied_claims, []);
      assert.equal(leaves.authority.principal, 'fixture-principal');
      assert.equal(leaves.accounting.input_tokens, 1);
      assert.equal(leaves.accounting.output_tokens, 2);
      assert.equal(leaves.accounting.cost_units, null);
      assert.equal(leaves.accounting.duration_ms, null);
      assert.deepEqual(leaves.accounting.reservation,
        {tokens: 33, cost_units: 0, duration_ms: 500});
      assert.ok(leaves.accounting.cumulative_work > 0);
      assert.equal(leaves.outcome.category, 'ok');
      assert.equal(fixture.calls(), 1);
    } finally {
      if (operation.cleanupPending()) await operation.close();
      assert.equal(operation.physicalStopped(), true);
      assert.equal(operation.cleanupPending(), false);
      assert.equal(fixture.calls(), outcome === 'allow' ? 1 : 0);
      if (outcome === 'allow') {
        const usage = operation.quantityUsage();
        assert.equal(usage.consumed.tokens, 3n);
        assert.equal(usage.uncertain.duration_ms, 500n);
        assert.equal(usage.reserved.tokens, 0n);
      }
    }
  }
});

test('Node Infer rechecks account and clock observations immediately before model I/O', async () => {
  for (const changed of ['account', 'expiry']) {
    const fixture = supervisedInferFixture();
    const {prepared, graph, operation} = fixture;
    const control = runtimeCore(moon).publicationControl;
    const root = cid({fixture: 'infer-component-policy'});
    const policy = {executionContextCid: root, hostPolicyCid: root,
      expiresAt: '2099-01-01T00:00:00.000Z'};
    const compiled = control.prepareCheckedClientCompiledRun(prepared,
      'infer', policy, graph);
    const runDefinition = control.defineCheckedClientCompiledRun(compiled,
      {namespaceId: 'infer-refresh-test', runId: changed,
        createdAt: '2026-10-02T00:00:00.000Z', validUntil: policy.expiresAt});
    const account = outcome => moon.executionAuthorizationAdmit(canonicalText({
      version: 'actql-execution-account-config/0.1', account_id: 'model-account',
      entries: [{entry_id: 'infer-policy', outcome, principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['infer']}, exclusions: []}],
    }));
    let refreshes = 0;
    try {
      operation.bindRun(control, {compiled, runDefinition});
      operation.bindDispatch(control, {compiled, runDefinition,
        account: account('allow'), principalId: 'fixture-principal',
        at: '2026-10-02T00:00:00.000Z',
        observeAccount: () => {
          refreshes++;
          return account(changed === 'account' ? 'deny' : 'allow');
        },
        observeAt: () => changed === 'expiry'
          ? '2100-01-01T00:00:00.000Z' : '2026-10-02T00:00:00.000Z'});
      await assert.rejects(operation.run(), failure => {
        assert.equal(failure.code, 'MoonBitHostFailure');
        assert.equal(failure.cause?.$tag, 2, 'Host Model issue');
        assert.equal(failure.cause?._0?.$tag, 14, 'Model Authorization issue');
        assert.equal(failure.cause?._0?._0?.$tag,
          changed === 'expiry' ? 1 : 2, 'expiry or changed configuration');
        return true;
      });
      assert.equal(refreshes, 1);
      assert.equal(fixture.calls(), 0);
      assert.equal(operation.acquireOutput(), undefined);
      assert.equal(operation.acquireCapture(), undefined);
    } finally {
      if (operation.cleanupPending()) await operation.close();
      assert.equal(operation.cleanupPending(), false);
      assert.equal(fixture.calls(), 0);
    }
  }
});

test('issued Infer Result custody outlives Store cancellation and cleanup retry', async t => {
  // Component evidence for the installed adapter boundary, not a claim that
  // ordinary public submit has already connected its ModelTask installation.
  const fixture = supervisedInferFixture();
  const {prepared, graph, operation} = fixture;
  const control = runtimeCore(moon).publicationControl;
  const root = cid({fixture: 'infer-result-custody'});
  const policy = {executionContextCid: root, hostPolicyCid: root,
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const compiled = control.prepareCheckedClientCompiledRun(prepared,
    'infer', policy, graph);
  const runDefinition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'infer-result-test', runId: 'one-row',
      createdAt: '2026-10-02T00:00:00.000Z', validUntil: policy.expiresAt});
  const account = moon.executionAuthorizationAdmit(canonicalText({
    version: 'actql-execution-account-config/0.1', account_id: 'model-account',
    entries: [{entry_id: 'infer-policy', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['infer']}, exclusions: []}],
  }));
  operation.bindRun(control, {compiled, runDefinition});
  operation.bindDispatch(control, {compiled, runDefinition, account,
    principalId: 'fixture-principal', at: '2026-10-02T00:00:00.000Z',
    observeAccount: () => account,
    observeAt: () => '2026-10-02T00:00:00.000Z'});
  await operation.run();
  const issued = await issueOwnedInferObservation(operation, control,
    compiled, runDefinition);
  let pendingCleanup;
  t.after(async () => {
    await pendingCleanup?.retry();
    moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    checked(moon.clientProgramCleanupInferObservationIssuance(issued.active));
    await operation.close();
  });
  await assert.rejects(operation.withResult(issued.binding, 1, () => {
    assert.fail('unknown Result cannot enter Store');
  }), /MoonBitHostFailure/u);
  const cancelled = new AbortController();
  cancelled.abort(new Error('cancelled before export'));
  await assert.rejects(operation.withResult(issued.binding, 0, () => {
    assert.fail('cancelled Result cannot enter Store');
  }, cancelled.signal), /cancelled before export/u);
  assert.deepEqual(await operation.withResult(issued.binding, 0,
    async ({selection, exported}) => {
      assert.equal(moon.clientProgramInferResultName(selection), 'answer');
      assert.equal(moon.clientProgramInferResultTask(selection), 0);
      let wire = '';
      let chunk;
      while ((chunk = checked(moon.clientProgramInferResultExportNext(exported)))
        !== undefined) wire += chunk;
      wire += checked(moon.clientProgramInferResultExportSeal(exported));
      return JSON.parse(wire);
    }), [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);

  let entered;
  const reached = new Promise(resolve => { entered = resolve; });
  let settle;
  const physicalEnd = new Promise(resolve => { settle = resolve; });
  const stop = new AbortController();
  let storePending = true;
  let retryCount = 0;
  const storeFailure = Object.assign(new Error('Store close failed'), {
    code: 'EIO', cleanupPending: true,
    cleanupHandle: {
      status: () => ({pending: storePending}),
      async retry() {
        retryCount++;
        if (retryCount === 1) throw new Error('temporary cleanup failure');
        storePending = false;
        return true;
      },
    },
  });
  const exporting = operation.withResult(issued.binding, 0, async () => {
    entered();
    await physicalEnd;
    throw storeFailure;
  }, stop.signal);
  await reached;
  moon.clientProgramReleaseInferInvocationBinding(issued.binding);
  stop.abort(new Error('cancelled Store'));
  assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(
    issued.active)), false, 'abort is not permission to release Store custody');
  settle();
  await assert.rejects(exporting, failure => {
    assert.equal(failure.cause, storeFailure);
    assert.equal(failure.code, 'EIO');
    pendingCleanup = failure.cleanupHandle;
    return true;
  });
  assert.equal(pendingCleanup.status().pending, true);
  await assert.rejects(pendingCleanup.retry(), /temporary cleanup failure/u);
  assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(
    issued.active)), false);
  assert.equal(fixture.calls(), 1);
  assert.equal(await pendingCleanup.retry(), true);
  assert.equal(pendingCleanup.status().pending, false);
  assert.equal(await pendingCleanup.retry(), false);
  assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(
    issued.active)), true);
  assert.equal(fixture.calls(), 1, 'Store cleanup never re-enters Model dispatch');
});

test('physical Infer preflight enforces the selected contract before dispatch', async t => {
  for (const [capacity, ledgerIssue] of [
    [{max_total_attempts: 2, max_total_wire_bytes: 133072}, undefined],
    [{max_total_attempts: 1, max_total_wire_bytes: 133072}, 2],
    [{max_total_attempts: 2, max_total_wire_bytes: 133071}, 4],
  ]) {
    const source = program();
    source.stages[0].steps[0].values.rows.push({id: 'b', text: 'hello'});
    const prepared = moon.clientProgramPreparationReady(prepare(source, environment()));
    assert.ok(prepared);
    const graph = scopedInferGraph(prepared, task, capacity);
    let calls = 0;
    const provider = moon.clientProgramInstallModelProvider('models/fixture', request => {
      calls++;
      return moon.clientProgramModelResponse(request,
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', `response-${calls}`,
        1n, 2n, '2026-10-02T00:00:00.000Z');
    });
    const operation = openNodeInferOperation({moon, preparedProgram: prepared,
      step: 2, graph, registry, values, provider, quantum: 1});
    t.after(async () => { if (operation.cleanupPending()) await operation.close(); });
    if (ledgerIssue === undefined) {
      const completed = await operation.run();
      assert.deepEqual(await inferExportRows(prepared, completed), [
        {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
        {id: 'b', outcome: 'ok', value: {reason: null, risk: 'high'}},
      ]);
      assert.equal(calls, 2);
    } else {
      await assert.rejects(operation.run(), error => {
        assert.equal(error.code, 'MoonBitHostFailure');
        assert.equal(error.cause?.$tag, 2, 'Host Model issue');
        assert.equal(error.cause?._0?.$tag, 9, 'Model Ledger issue');
        assert.equal(error.cause?._0?._0, ledgerIssue,
          ledgerIssue === 2 ? 'AttemptLimit' : 'TransferLimit');
        return true;
      });
      assert.equal(calls, 0);
      assert.equal(operation.acquireOutput(), undefined);
      assert.equal(operation.acquireCapture(), undefined);
    }
    assert.equal(operation.physicalStopped(), true);
    await operation.close();
    assert.equal(operation.cleanup(), true);
    assert.equal(operation.cleanupPending(), false);
    assert.equal(calls, ledgerIssue === undefined ? 2 : 0);
  }
});

test('compiled Run binding retains the actual Infer output without preparing or compiling again', async t => {
  // This checks the normal compiled owner and physical operation boundary,
  // not external authority/accounting admission or a public Named Result.
  for (const failed of [false, true]) {
    const fixture = supervisedInferFixture(undefined, undefined, failed
      ? '{"reason":null,"risk":123}' : '{"reason":null,"risk":"high"}');
    const {operation, prepared, graph} = fixture;
    let compiles = 0;
    const control = runtimeCore({...moon,
      clientProgramCompileLocalInfer(...args) {
        compiles++;
        return moon.clientProgramCompileLocalInfer(...args);
      },
    }).publicationControl;
    const root = cid({fixture: 'symbolic-invocation-external-root'});
    const policy = {executionContextCid: root, hostPolicyCid: root,
      expiresAt: '2099-01-01T00:00:00.000Z'};
    const compiled = control.prepareCheckedClientCompiledRun(prepared,
      'infer', policy, graph);
    const runDefinition = control.defineCheckedClientCompiledRun(compiled,
      {namespaceId: 'infer-compilation', runId: failed ? 'failure' : 'success',
        createdAt: '2026-10-02T00:00:00.000Z', validUntil: policy.expiresAt});
    operation.bindRun(control, {compiled, runDefinition});
    operation.bindRun(control, {compiled, runDefinition});
    const completed = await operation.run();
    const capture = operation.acquireCapture();
    let verification, binding, consumer;
    t.after(async () => {
      if (verification !== undefined) {
        moon.clientProgramCancelInferObservationVerification(verification);
        // Cleanup cannot release a still-running verification session.
        try { checked(moon.clientProgramAdvanceInferObservationVerification(
          verification, 1)); } catch { /* Already terminal or stopped. */ }
        checked(moon.clientProgramCleanupInferObservationVerification(verification));
      }
      moon.clientProgramReleaseInferCapture(capture);
      if (binding !== undefined) moon.clientProgramReleaseInferInvocationBinding(binding);
      if (consumer !== undefined) moon.clientProgramReleaseInferOutput(consumer);
      if (operation.cleanupPending()) await operation.close();
    });
    const call = JSON.parse(moon.strategyRunEvidenceJson(
      moon.clientProgramInferCaptureCall(capture, 0)));
    const success = failed ? undefined : JSON.parse(moon.strategyRunEvidenceJson(
      operation.invocationEvidence(0)));
    const slotBody = {
      version: 'actql-model-slot-capture/0.1',
      slot_cid: call.model_call_slot_cid, model_task_cid: call.model_task_cid,
      fixed_request_cid: call.fixed_request_cid,
      input_artifact_cid: call.input_artifact_cid,
      input_key_cid: call.input_key_cid,
      ordered_attempt_cids: [root], adopted_attempt_cid: root,
      outcome: failed ? 'failed:provider_error' : 'ok',
      typed_value_artifact_cid: success?.validated_structured_output_cid ?? null,
      accounting_evidence_cid: root, authority_evidence_cid: root,
      policy_cid: root, outcome_evidence_cid: root,
      response_artifact_cid: success?.structured_response_artifact_cid ?? null,
      response_issuer_evidence_cid: failed ? null : root,
      attachment_admission_cids: [],
    };
    const slotCid = cid(slotBody);
    const slot = checked(moon.strategyRunEvidenceAdmit('model_slot_capture',
      canonicalText({...slotBody, self_cid: slotCid}), 16384, 1024, 20));
    const observationBody = {
      version: 'actql-observation-set/0.1',
      invocation_template_cid: compiled.template.identity,
      captured_input_artifact_cids: [call.input_artifact_cid],
      source_evidence_cids: [], data_policy_cid: root,
      consistency: 'independent_snapshots',
      capture_started_at: '2026-10-02T00:00:00.000Z',
      capture_completed_at: '2026-10-02T00:00:00.000Z',
      replayability: {materialized: false, availability_evidence_cids: []},
      model_slot_capture_cids: [slotCid],
    };
    const observationCid = cid(observationBody);
    const observation = checked(moon.strategyRunEvidenceAdmit('observation_set',
      canonicalText({...observationBody, observation_set_cid: observationCid}),
      16384, 1024, 20));
    // The common binding checks an already admitted Invocation. This fixture
    // issues identity bytes only, not authority to publish those bytes.
    const invocationBody = {version: 'actql-run-invocation/0.1',
      invocation_template_cid: compiled.template.identity,
      observation_set_cid: observationCid};
    const invocation = control.seal('run_invocation',
      canonicalText(invocationBody), {maxWireBytes: 16384, maxNodes: 1024,
        maxDepth: 20});
    assert.equal(invocation.identity, cid(invocationBody));
    verification = checked(moon.clientProgramStartInferObservationVerification(
      capture, observation, [slot], 1, 16384, 2));
    const args = {compiled, runDefinition, verification, invocation,
      dataPolicyCid: root};
    assert.throws(() => operation.bindInvocation(control, args), error =>
      error.code === 'MoonBitHostFailure' && error.cause?.$tag === 2);
    assert.equal(checked(moon.clientProgramAdvanceInferObservationVerification(
      verification, 1))._0, false);
    assert.equal(checked(moon.clientProgramAdvanceInferObservationVerification(
      verification, 1))._0, true);
    assert.throws(() => operation.bindInvocation(control,
      {...args, compiled: {...compiled}}), /Foreign Client compiled Infer Run/u);
    binding = operation.bindInvocation(control, args);
    consumer = operation.acquireOutput();
    assert.equal(moon.clientProgramInferInvocationBindingOutput(binding), completed);
    assert.equal(checked(moon.clientProgramCleanupInferObservationVerification(
      verification)), true);
    assert.equal(moon.clientProgramReleaseInferCapture(capture), true);
    assert.equal(operation.cleanup(), false);
    assert.deepEqual(await inferExportRows(prepared,
      moon.clientProgramInferInvocationBindingOutput(binding)), failed
      ? [{id: 'a', outcome: 'failed:provider_error', value: null}]
      : [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
    assert.equal(moon.clientProgramReleaseInferInvocationBinding(binding), true);
    assert.equal(moon.clientProgramInferInvocationBindingOutput(binding), undefined);
    assert.equal(operation.cleanup(), false);
    assert.equal(moon.clientProgramInferOutputUse(consumer), completed);
    assert.equal(moon.clientProgramReleaseInferOutput(consumer), true);
    await operation.close();
    assert.equal(operation.cleanupPending(), false);
    assert.equal(fixture.calls(), 1);
    assert.equal(compiles, 1);
  }
});

test('the existing Host dispatch owner retains Infer custody and never reruns cleanup', async () => {
  const supervisor = installNodeClientDispatchOwner({});
  const ref = {runDefinitionCid: cid({fixture: 'supervised-infer'})};
  let fixture;
  let saved;
  let rows;
  let runEntries = 0;
  const stopped = [];
  const execution = supervisor.track(ref, {
    async run(physical) {
      runEntries++;
      fixture = supervisedInferFixture(physical.signal);
      const {operation, prepared} = fixture;
      assert.equal(fixture.calls(), 0, 'opening performs no physical model call');
      physical.retainExecution(operation);
      physical.beginPhysicalWork();
      assert.equal(operation.physicalStopped(), false);
      const first = operation.run();
      assert.equal(operation.run(), first, 'one physical stepping flight');
      const completed = await first;
      assert.equal(operation.physicalStopped(), true);
      const a = operation.acquireOutput();
      const b = operation.acquireOutput();
      assert.ok(a && b);
      assert.equal(moon.clientProgramInferOutputUse(a), completed);
      assert.equal(moon.clientProgramInferOutputUse(b), completed);
      rows = await inferExportRows(prepared, moon.clientProgramInferOutputUse(a));
      assert.equal(moon.clientProgramReleaseInferOutput(a), true);
      assert.equal(operation.cleanup(), false);
      assert.equal(moon.clientProgramInferOutputUse(b), completed);
      saved = operation.acquireCapture();
      assert.ok(saved);
      assert.equal(moon.clientProgramInferCaptureCallCount(saved), 1);
      const call = moon.clientProgramInferCaptureCall(saved, 0);
      assert.ok(call);
      const body = JSON.parse(moon.strategyRunEvidenceJson(call));
      const observation = JSON.parse(moon.strategyRunEvidenceJson(
        operation.invocationEvidence(0)));
      assert.equal(body.model_call_slot_cid, observation.model_call_slot_cid);
      assert.equal(body.input_artifact_cid,
        observation.input_result_artifact_cid);
      assert.equal(moon.clientProgramInferCaptureCall(saved, 1), undefined);
      assert.equal(moon.clientProgramReleaseInferOutput(b), true);
      return rows;
    },
    async observeStopped(outcome) { stopped.push(outcome); },
  });
  assert.equal(supervisor.track(ref, {
    run() { assert.fail('a second caller cannot dispatch the same Run'); },
    observeStopped() { assert.fail('the original observer retains custody'); },
  }), execution);
  await assert.rejects(execution, /ClientDispatchCleanupPending/u);
  assert.deepEqual(rows, [{id: 'a', outcome: 'ok',
    value: {reason: null, risk: 'high'}}]);
  assert.equal(runEntries, 1);
  assert.equal(fixture.calls(), 1);
  assert.equal(fixture.operation.physicalStopped(), true);
  assert.equal(fixture.operation.cleanupPending(), true);
  assert.equal(supervisor.live(ref), false);
  assert.equal(supervisor.operation(ref), execution);
  await assert.rejects(supervisor.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(fixture.calls(), 1);
  assert.equal(runEntries, 1);
  assert.deepEqual(stopped, []);
  assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
  assert.equal(moon.clientProgramInferCaptureCallCount(saved), undefined);
  assert.equal(moon.clientProgramInferCaptureCall(saved, 0), undefined);
  await supervisor.drain();
  assert.equal(fixture.operation.cleanupPending(), false);
  assert.deepEqual(stopped, [null]);
  assert.equal(supervisor.operation(ref), undefined);
  assert.equal(fixture.calls(), 1);
  assert.equal(runEntries, 1);
  await assert.rejects(fixture.operation.run(), /InferOperationClosed/u);
});

test('Host cancellation is delivered after a model response and before output handoff', async () => {
  const supervisor = installNodeClientDispatchOwner({});
  const ref = {runDefinitionCid: cid({fixture: 'supervised-infer-cancel'})};
  let fixture;
  let cancellationObserved;
  const delivered = new Promise(resolve => { cancellationObserved = resolve; });
  let stopped = 0;
  const execution = supervisor.track(ref, {
    async run(physical) {
      fixture = supervisedInferFixture(physical.signal, () => {
        setImmediate(() => {
          assert.equal(fixture.operation.physicalStopped(), false);
          supervisor.cancel(ref);
          assert.equal(fixture.operation.physicalStopped(), false,
            'request delivery is not physical settlement');
          assert.equal(fixture.operation.cleanup(), false);
          cancellationObserved();
        });
      });
      physical.retainExecution(fixture.operation);
      physical.beginPhysicalWork();
      return fixture.operation.run();
    },
    async observeStopped() {
      assert.equal(fixture.operation.physicalStopped(), true);
      stopped++;
    },
  });
  await delivered;
  await assert.rejects(execution, /ClientRunCancellationRequested/u);
  assert.equal(fixture.operation.acquireOutput(), undefined);
  assert.equal(fixture.operation.acquireCapture(), undefined);
  assert.equal(fixture.operation.physicalStopped(), true);
  assert.equal(fixture.operation.cleanupPending(), false);
  await supervisor.drain();
  assert.equal(stopped, 1);
  assert.equal(fixture.calls(), 1);
});

test('closing an unstarted physical Infer owner cannot dispatch or report request as stop', async () => {
  const fixture = supervisedInferFixture();
  assert.equal(fixture.operation.cleanup(), false);
  assert.equal(fixture.operation.physicalStopped(), false);
  await fixture.operation.close();
  assert.equal(fixture.operation.physicalStopped(), true);
  assert.equal(fixture.operation.cleanupPending(), false);
  assert.equal(fixture.calls(), 0);
  await assert.rejects(fixture.operation.run(), /InferOperationClosed/u);
  assert.equal(fixture.calls(), 0);
});

test('the physical Infer wrapper preserves a typed model failure and cleans without redispatch', async () => {
  const source = program();
  source.stages[0].steps[2].infer.on_non_success = 'fail';
  const fixture = supervisedInferFixture(undefined, undefined,
    '{"reason":null,"risk":123}', source);
  await assert.rejects(fixture.operation.run(), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.cause?.$tag, 2, 'Host Model issue');
    assert.equal(error.cause?._0?.$tag, 4, 'Model Provider issue');
    assert.equal(error.cause?._0?._0, 2, 'ProviderError from invalid response');
    return true;
  });
  assert.equal(fixture.operation.physicalStopped(), true);
  assert.equal(fixture.operation.acquireOutput(), undefined);
  assert.equal(fixture.operation.acquireCapture(), undefined);
  const outcomes = fixture.operation.acquireOutcomes();
  assert.ok(outcomes);
  assert.equal(moon.clientProgramInferOutcomesAccepted(outcomes), false);
  assert.equal(moon.clientProgramInferOutcomesCount(outcomes), 1);
  assert.equal(moon.clientProgramInferOutcomesOutcome(outcomes, 0),
    'failed:provider_error');
  assert.ok(moon.clientProgramInferOutcomesCall(outcomes, 0));
  assert.equal(moon.clientProgramInferOutcomesCall(outcomes, 1), undefined);
  await assert.rejects(fixture.operation.close(),
    {code: 'ClientDispatchCleanupPending'});
  assert.equal(fixture.operation.physicalStopped(), true);
  assert.equal(fixture.operation.cleanupPending(), true);
  assert.equal(fixture.calls(), 1);
  assert.equal(moon.clientProgramReleaseInferOutcomes(outcomes), true);
  assert.equal(moon.clientProgramReleaseInferOutcomes(outcomes), false);
  assert.equal(moon.clientProgramInferOutcomesCount(outcomes), undefined);
  assert.equal(fixture.operation.cleanup(), true);
  assert.equal(fixture.operation.cleanupPending(), false);
  assert.equal(fixture.calls(), 1);
  assert.equal(fixture.operation.cleanup(), true);
  assert.equal(fixture.calls(), 1);
});

test('outcome-mode failures retain a real key and NULL value without a success response', async () => {
  const fixture = supervisedInferFixture(undefined, undefined,
    '{"reason":null,"risk":123}');
  const completed = await fixture.operation.run();
  assert.deepEqual(await inferExportRows(fixture.prepared, completed),
    [{id: 'a', outcome: 'failed:provider_error', value: null}]);
  assert.equal(fixture.calls(), 1);
  const capture = fixture.operation.acquireCapture();
  assert.ok(capture);
  assert.equal(moon.clientProgramInferCaptureCallCount(capture), 1);
  assert.equal(moon.clientProgramInferCaptureOutcome(capture, 0),
    'failed:provider_error');
  assert.ok(moon.clientProgramInferCaptureCall(capture, 0));
  assert.equal(fixture.operation.invocationEvidence(0), undefined);
  assert.equal(fixture.operation.cleanup(), false);
  assert.equal(moon.clientProgramReleaseInferCapture(capture), true);
  await fixture.operation.close();
  assert.equal(fixture.operation.cleanupPending(), false);
  assert.equal(fixture.calls(), 1);
});

test('invalid or already cancelled opening performs no physical Infer start', () => {
  const controller = new AbortController();
  const cause = new Error('CancelledBeforePhysicalStart');
  controller.abort(cause);
  assert.throws(() => openNodeInferOperation({moon: {}, provider: {},
    signal: controller.signal}), error => error === cause);
  for (const quantum of [0, -1, 0.5, NaN, Infinity, 2147483648]) {
    assert.throws(() => openNodeInferOperation({moon: {}, provider: {}, quantum}),
      /InvalidInstalledInferOperation/u);
  }
  for (const inputs of [{}, {provider: {}, savedCapture: {}},
    {provider: {}, savedSlots: {}}, {savedCapture: {}, savedSlots: {}}]) {
    assert.throws(() => openNodeInferOperation({moon: {}, ...inputs}),
      /InvalidInstalledInferOperation/u);
  }
});

test('failed slot custody survives encrypted Store reopen and replays without dispatch', async t => {
  // The component capture owner issues all proofs. Reopening authenticated
  // holdings verifies that chain; this is not public Named Result completion.
  const original = supervisedInferFixture(undefined, undefined,
    '{"reason":null,"risk":123}');
  const control = runtimeCore(moon).publicationControl;
  const root = cid({fixture: 'stored-infer-component-policy'});
  const policy = {executionContextCid: root, hostPolicyCid: root,
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const compiled = control.prepareCheckedClientCompiledRun(original.prepared,
    'infer', policy, original.graph);
  const runDefinition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'stored-infer', runId: 'failed-slot',
      createdAt: '2026-10-02T00:00:00.000Z', validUntil: policy.expiresAt});
  const account = moon.executionAuthorizationAdmit(canonicalText({
    version: 'actql-execution-account-config/0.1', account_id: 'model-account',
    entries: [{entry_id: 'infer-policy', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['infer']}, exclusions: []}],
  }));
  original.operation.bindRun(control, {compiled, runDefinition});
  original.operation.bindDispatch(control, {compiled, runDefinition, account,
    principalId: 'fixture-principal', at: '2026-10-02T00:00:00.000Z',
    observeAccount: () => account,
    observeAt: () => '2026-10-02T00:00:00.000Z'});
  const completed = await original.operation.run();
  assert.deepEqual(await inferExportRows(original.prepared, completed),
    [{id: 'a', outcome: 'failed:provider_error', value: null}]);
  const saved = original.operation.acquireCapture();
  let publication;
  t.after(async () => {
    if (publication !== undefined) {
      moon.clientProgramReleaseInferInvocationBinding(publication.binding);
      checked(moon.clientProgramCleanupInferObservationIssuance(publication.active));
    }
    moon.clientProgramReleaseInferCapture(saved);
    if (original.operation.cleanupPending()) await original.operation.close();
  });
  const call = JSON.parse(moon.strategyRunEvidenceJson(
    moon.clientProgramInferCaptureCall(saved, 0)));
  const slot = original.operation.issuedSlotCapture(0);
  const slotWire = moon.strategyRunEvidenceJson(slot);
  const identity = JSON.parse(slotWire).self_cid;
  const issued = original.operation.attemptEvidence(0);
  const leaves = ['attempt', 'accounting', 'outcome', 'authority'].map(kind => {
    const wire = moon.strategyRunEvidenceJson(
      moon.clientProgramInferAttemptLeaf(issued, kind));
    return {kind, wire, body: JSON.parse(wire)};
  });
  checked(moon.clientProgramBindInferSlotCapture(saved, 0, slot));
  const exported = await exportedModelCapture(saved);
  const bundleBody = {version: 'actql-model-capture-bundle/0.1',
    barrier_receipts: [], captures: []};
  assert.equal(exported.identity, cid(bundleBody));
  assert.equal(exported.wire, canonicalText({...bundleBody,
    bundle_cid: cid(bundleBody)}));
  const observationBody = {
    version: 'actql-observation-set/0.1',
    invocation_template_cid: compiled.template.identity,
    captured_input_artifact_cids: [call.input_artifact_cid], source_evidence_cids: [],
    data_policy_cid: task.data_handling.contract_cid, consistency: 'no_external_sources',
    capture_started_at: null, capture_completed_at: null,
    replayability: {materialized: false, availability_evidence_cids: []},
    model_slot_capture_cids: [identity],
  };
  publication = await issueOwnedInferObservation(original.operation, control,
    compiled, runDefinition);
  const observationWire = publication.observation.wire;
  assert.equal(observationWire, canonicalText({...observationBody,
    observation_set_cid: cid(observationBody)}));
  assert.equal(publication.invocation.identity, cid({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: compiled.template.identity,
    observation_set_cid: cid(observationBody)}));
  const directory = await mkdtemp(join(tmpdir(), 'actql-failed-slot-'));
  const configuration = {
    directory, storeAuthorityCid: cid({fixture: 'failed-slot-store'}),
    capacityBytes: 1024 * 1024, maxObjectBytes: 100000, maxObjects: 100,
    maxContractNodes: 20000, maxContractDepth: 100,
    privateEvidenceKey: Buffer.alloc(32, 17),
  };
  let rejectConfirmationSync = false;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === join(directory, 'physical-holdings') && rejectConfirmationSync) {
        rejectConfirmationSync = false;
        throw Object.assign(new Error('injected slot confirmation failure'),
          {code: 'EIO'});
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  let store;
  try {
    store = await openLocalPublicationStore(configuration,
      createPublicationContractControlFixture(), durability);
    const bindings = [];
    for (const [name, wire, semanticCid] of [
      ['model_slot_capture', slotWire, identity],
      ['model_capture_bundle', exported.wire, exported.identity],
      ['observation_set', observationWire, publication.observation.identity],
      ['run_invocation', publication.invocation.wire, publication.invocation.identity],
      ...leaves.map(({kind, body, wire}) => [
        {attempt: 'model_call_attempt', accounting: 'model_attempt_accounting',
          outcome: 'model_attempt_outcome', authority: 'model_dispatch_authority'}[
          kind], wire, body.self_cid]),
    ]) {
      const prepared = await store.preparePrivateEvidence(name, wire, semanticCid);
      const holdingCid = cid({fixture: 'saved-slot-holding', name, semanticCid});
      await store.commitPhysicalHolding({
        version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
        holding_cid: holdingCid, manifest_cid: semanticCid,
        objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
      }, [prepared.prepared]);
      const binding = {name, wire, semanticCid, holdingCid};
      if (name === 'model_slot_capture') {
        rejectConfirmationSync = true;
        await assert.rejects(store.confirmPrivateEvidence(binding),
          {code: 'EIO'});
        assert.equal(original.operation.cleanup(), false);
        assert.equal(original.calls(), 1);
      }
      await store.confirmPrivateEvidence(binding);
      bindings.push(binding);
    }
    await assert.rejects(store.confirmPrivateEvidence({...bindings[0], wire: '{}'}),
      {code: 'PublicationPrivateEvidenceConflict'});
    await assert.rejects(store.readPrivateEvidence('model_capture_bundle',
      identity, bindings[0].holdingCid),
    {code: 'PublicationPrivateEvidenceCorrupt'});
    await assert.rejects(store.readPrivateEvidence('model_slot_capture',
      identity, bindings[1].holdingCid),
    {code: 'PublicationPrivateEvidenceUnavailable'});
    assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exported.active)), true);
    assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
    assert.equal(moon.clientProgramReleaseInferInvocationBinding(publication.binding), true);
    assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(publication.active)), true);
    assert.deepEqual(moon.clientProgramInferPublicationUsage(publication.ledger),
      {_0: 3, _1: 0n});
    await original.operation.close();
    assert.equal(original.operation.cleanupPending(), false);
    assert.equal(original.calls(), 1);
    await store.close();
    store = undefined;
    // A fresh process cannot retain the original capture/execution. Each slot
    // and the separate success bundle come from authenticated exact holdings.
    const childSource = `
      import assert from 'node:assert/strict';
      import {createHash} from 'node:crypto';
      import {readFileSync} from 'node:fs';
      import {inspect} from 'node:util';
      import * as moon from ${JSON.stringify(new URL(
        '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
        import.meta.url).href)};
      import {canonicalText} from ${JSON.stringify(new URL(
        './check-canonical-json.mjs', import.meta.url).href)};
      import {openLocalPublicationStore} from ${JSON.stringify(new URL(
        '../adapters/store-local/publication-store.mjs', import.meta.url).href)};
      import {openNodeInferOperation} from ${JSON.stringify(new URL(
        '../adapters/host-node/infer-operation.mjs', import.meta.url).href)};
      import {runtimeCore} from ${JSON.stringify(new URL(
        '../adapters/host-common/runtime-core.mjs', import.meta.url).href)};
      import {createPublicationContractControlFixture} from ${JSON.stringify(new URL(
        '../adapters/host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
      const fixture = JSON.parse(readFileSync(0, 'utf8'));
      const {task, baseEnvironment, registry, values} = fixture;
      const cid = ${cid.toString()};
      const checked = ${checked.toString()};
      const environment = ${environment.toString()};
      const prepare = ${prepare.toString()};
      const program = ${program.toString()};
      const scopedInferGraph = ${scopedInferGraph.toString()};
      const inferExportRows = ${inferExportRows.toString()};
      const store = await openLocalPublicationStore({...fixture.configuration,
        privateEvidenceKey: Buffer.alloc(32, 17)},
        createPublicationContractControlFixture());
      try {
        const records = [];
        const leaves = {};
        let bundle;
        let observation;
        let invocation;
        for (const binding of fixture.bindings) {
          const bytes = await store.readPrivateEvidence(binding.name,
            binding.semanticCid, binding.holdingCid);
          const wire = bytes.toString('utf8');
          await store.confirmPrivateEvidence({...binding, wire});
          if (binding.name === 'model_slot_capture') {
            records.push(checked(moon.strategyRunEvidenceAdmit(binding.name, wire,
              16384, 1024, 20)));
          } else if (binding.name === 'model_capture_bundle') {
            bundle = checked(moon.clientProgramReadInferCaptureBundle(wire,
              binding.semanticCid));
          } else if (binding.name === 'observation_set') {
            observation = runtimeCore(moon).publicationControl.admitRunEvidence(
              binding.name, wire,
              {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
          } else if (binding.name === 'run_invocation') {
            invocation = runtimeCore(moon).publicationControl.admit(binding.name,
              wire, {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
          } else {
            leaves[binding.name] = checked(moon.strategyRunEvidenceAdmit(
              binding.name, wire, 16384, 1024, 20));
          }
        }
        const prepared = moon.clientProgramPreparationReady(prepare(program(), environment()));
        const graph = scopedInferGraph(prepared);
        const control = runtimeCore(moon).publicationControl;
        const compiled = control.prepareCheckedClientCompiledRun(prepared,
          'infer', fixture.policy, graph);
        const definition = control.defineCheckedClientCompiledRun(compiled,
          {retainedDefinitionWire: fixture.runDefinitionWire});
        assert.ok(observation);
        assert.ok(invocation);
        assert.equal(JSON.parse(invocation.wire).observation_set_cid,
          observation.identity);
        const proofs = [moon.clientProgramInferAttemptRecords(
          leaves.model_call_attempt, leaves.model_attempt_accounting,
          leaves.model_attempt_outcome, leaves.model_dispatch_authority)];
        const read = control.readCheckedClientInferSlotReplay(compiled,
          definition, observation, records, bundle, proofs,
          {maxSlots: 1, maxSlotWireUnits: 16384});
        assert.equal(moon.clientProgramReleaseInferCaptureBundle(bundle), true);
        const replay = openNodeInferOperation({moon, preparedProgram: prepared,
          step: 2, graph, registry, values,
          savedSlots: read, quantum: 1});
        replay.bindRun(control, {compiled, runDefinition: definition});
        assert.equal(moon.clientProgramReleaseInferSlotReplay(read), true);
        const output = await replay.run();
        const rows = await inferExportRows(prepared, output);
        const issueOwnedInferObservation = ${issueOwnedInferObservation.toString()};
        const reissued = await issueOwnedInferObservation(replay, control,
          compiled, definition);
        assert.equal(reissued.observation.identity, observation.identity);
        assert.equal(reissued.invocation.identity, invocation.identity);
        assert.equal(moon.clientProgramReleaseInferInvocationBinding(reissued.binding), true);
        assert.equal(checked(moon.clientProgramCleanupInferObservationIssuance(reissued.active)), true);
        assert.deepEqual(moon.clientProgramInferPublicationUsage(reissued.ledger), {_0: 3, _1: 0n});
        assert.equal(replay.invocationEvidence(0), undefined);
        assert.equal(replay.physicalStopped(), true);
        await replay.close();
        assert.equal(replay.cleanupPending(), false);
        process.stdout.write(JSON.stringify(rows));
      } finally { await store.close(); }
    `;
    const restarted = JSON.parse(execFileSync(process.execPath,
      ['--input-type=module', '-e', childSource], {encoding: 'utf8',
        input: JSON.stringify({task, baseEnvironment, registry, values,
          configuration: {...configuration, privateEvidenceKey: undefined},
          bindings, policy, runDefinitionWire: runDefinition.wire})}));
    assert.deepEqual(restarted,
      [{id: 'a', outcome: 'failed:provider_error', value: null}]);
    assert.equal(original.calls(), 1);
    store = await openLocalPublicationStore(configuration,
      createPublicationContractControlFixture());
    for (const binding of bindings) {
      assert.equal((await store.retirePhysicalHolding(binding.holdingCid)).deleted,
        true);
    }
    assert.equal(store.status().storedBytes, 0);
  } finally {
    if (store !== undefined) await store.close();
    await rm(directory, {recursive: true, force: true});
  }
});

async function exportedModelCapture(saved, {maxBytes = 100000, maxWork = 10000} = {}) {
  const active = checked(moon.clientProgramStartInferCaptureExport(saved, maxBytes, maxWork));
  let wire = '';
  let work = 0n;
  for (let poll = 0; poll < 10000; poll++) {
    const step = moon.clientProgramAdvanceInferCaptureExport(active, 1);
    if (step.$tag === 0) return {active, failure: step._0, wire};
    const value = checked(step);
    assert.equal(value._2 - work, 1n);
    work = value._2;
    wire += value._1;
    if (value._0) {
      return {active, wire, identity: moon.clientProgramInferCaptureExportIdentity(active)};
    }
    assert.equal(moon.clientProgramInferCaptureExportIdentity(active), undefined);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('capture export exceeded its independent finite poll ceiling');
}

test('checked capture serializes its formal bundle and survives encrypted Store reopen', async t => {
  const original = ownedInfer(undefined, undefined, {scoped: true});
  assert.equal((await ownedInferTerminal(original.active)).$tag, 1);
  const saved = moon.clientProgramAcquireInferCapture(original.active);
  assert.ok(saved);
  const exported = await exportedModelCapture(saved);
  assert.equal(exported.failure, undefined);
  assert.ok(exported.identity);
  const observation = JSON.parse(moon.strategyRunEvidenceJson(
    moon.clientProgramInferInvocationEvidence(original.active, 0)));
  const expectedBody = {
    version: 'actql-model-capture-bundle/0.1', barrier_receipts: [], captures: [{
      model_call_slot_cid: observation.model_call_slot_cid,
      semantic_request_cid: observation.semantic_request_cid,
      structured_response: {reason: null, risk: 'high'}, evidence: observation,
    }],
  };
  assert.equal(exported.identity, cid(expectedBody));
  const expectedWire = canonicalText({...expectedBody, bundle_cid: cid(expectedBody)});
  assert.equal(exported.wire, expectedWire);
  assert.equal(moon.clientProgramCancelInferCaptureExport(exported.active), false);

  // An independent canonical encoding supplies the exact full-wire boundary.
  const exactBytes = Buffer.byteLength(expectedWire);
  const exact = await exportedModelCapture(saved, {maxBytes: exactBytes});
  assert.equal(exact.identity, cid(expectedBody));
  assert.equal(exact.wire, expectedWire);
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exact.active)), true);
  const oneShort = await exportedModelCapture(saved, {maxBytes: exactBytes - 1});
  assert.equal(oneShort.failure.$tag, 5, 'exact OutputValue serialization failure');
  assert.equal(moon.clientProgramInferCaptureExportIdentity(oneShort.active), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(oneShort.active)), true);

  const directory = await mkdtemp(join(tmpdir(), 'actql-model-capture-'));
  const configuration = {
    directory, storeAuthorityCid: cid({fixture: 'model-capture-store'}),
    capacityBytes: 1024 * 1024, maxObjectBytes: 100000, maxObjects: 100,
    maxContractNodes: 20000, maxContractDepth: 100,
    privateEvidenceKey: Buffer.alloc(32, 17),
  };
  const control = createPublicationContractControlFixture();
  let rejectConfirmationSync = false;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === join(directory, 'physical-holdings') && rejectConfirmationSync) {
        rejectConfirmationSync = false;
        const error = new Error('injected model capture confirmation failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  let store;
  try {
    store = await openLocalPublicationStore(configuration, control, durability);
    const prepared = await store.preparePrivateEvidence(
      'model_capture_bundle', exported.wire, exported.identity);
    const holdingCid = cid({fixture: 'capture-holding', bundle: exported.identity});
    const record = {
      version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
      holding_cid: holdingCid, manifest_cid: exported.identity,
      objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
    };
    await store.commitPhysicalHolding(record, [prepared.prepared]);
    assert.equal(prepared.prepared.status().pending, false);
    const ciphertext = [];
    await store.consumeObject(prepared.physicalCid, chunk => ciphertext.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(ciphertext).includes(Buffer.from('fixture-risk-model')), false);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), false,
      'serialization and Store I/O retain their checked capture owner');
    await store.close();
    store = undefined;
    store = await openLocalPublicationStore(configuration, control);
    const recovered = await store.readPrivateEvidence(
      'model_capture_bundle', exported.identity, holdingCid);
    assert.equal(recovered.toString('utf8'), expectedWire);
    const binding = {name: 'model_capture_bundle', semanticCid: exported.identity,
      holdingCid, wire: expectedWire};
    await store.close();
    store = undefined;
    store = await openLocalPublicationStore(configuration, control, durability);
    rejectConfirmationSync = true;
    await assert.rejects(store.confirmPrivateEvidence(binding),
      error => error?.code === 'EIO');
    assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), false,
      'uncertain durability retains the existing capture owner');
    assert.equal(original.calls(), 1, 'confirmation failure cannot redispatch');
    assert.deepEqual(await store.confirmPrivateEvidence(binding), record);
    await assert.rejects(store.confirmPrivateEvidence({...binding, wire: '{}'}),
      error => error?.code === 'PublicationPrivateEvidenceConflict');
    assert.equal(original.calls(), 1);
    assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exported.active)), true);
    assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
    assert.equal(original.calls(), 1);
    const recoveredCapture = checked(moon.clientProgramReadInferCaptureBundle(
      recovered.toString('utf8'), exported.identity));
    const fresh = moon.clientProgramPreparationReady(prepare(program(), environment()));
    const replay = openNodeInferOperation({moon, preparedProgram: fresh, step: 2,
      graph: scopedInferGraph(fresh), registry, values, savedCapture: recoveredCapture,
      quantum: 1});
    assert.equal(moon.clientProgramReleaseInferCaptureBundle(recoveredCapture), true);
    assert.equal(moon.clientProgramReleaseInferCaptureBundle(recoveredCapture), false);
    const completed = await replay.run();
    assert.equal(replay.physicalStopped(), true);
    assert.deepEqual(await inferExportRows(fresh, completed), [
      {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
    ]);
    assert.equal(moon.strategyRunEvidenceJson(
      replay.invocationEvidence(0)), canonicalText(observation));
    await replay.close();
    assert.equal(replay.cleanupPending(), false);
    assert.equal(original.calls(), 1, 'restored replay has no provider fallback');
    assert.equal(moon.clientProgramStartRestoredInferReplay(fresh, 2,
      scopedInferGraph(fresh), registry, values, recoveredCapture).$tag, 0);

    await store.close();
    store = undefined;
    // A fresh VM cannot retain the original execution, capture read or module
    // state. It authenticates the physical holding and prepares the Program
    // itself. This remains a component replay, not public Run publication.
    const childSource = `
      import assert from 'node:assert/strict';
      import {createHash} from 'node:crypto';
      import {readFileSync} from 'node:fs';
      import {inspect} from 'node:util';
      import * as moon from ${JSON.stringify(new URL(
        '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
        import.meta.url).href)};
      import {canonicalText} from ${JSON.stringify(new URL(
        './check-canonical-json.mjs', import.meta.url).href)};
      import {openLocalPublicationStore} from ${JSON.stringify(new URL(
        '../adapters/store-local/publication-store.mjs', import.meta.url).href)};
      import {openNodeInferOperation} from ${JSON.stringify(new URL(
        '../adapters/host-node/infer-operation.mjs', import.meta.url).href)};
      import {createPublicationContractControlFixture} from ${JSON.stringify(new URL(
        '../adapters/host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
      const fixture = JSON.parse(readFileSync(0, 'utf8'));
      const {task, baseEnvironment, registry, values} = fixture;
      const cid = ${cid.toString()};
      const checked = ${checked.toString()};
      const environment = ${environment.toString()};
      const prepare = ${prepare.toString()};
      const program = ${program.toString()};
      const scopedInferGraph = ${scopedInferGraph.toString()};
      const inferExportRows = ${inferExportRows.toString()};
      const configuration = {...fixture.configuration,
        privateEvidenceKey: Buffer.alloc(32, 17)};
      const store = await openLocalPublicationStore(configuration,
        createPublicationContractControlFixture());
      try {
        const bytes = await store.readPrivateEvidence('model_capture_bundle',
          fixture.identity, fixture.holdingCid);
        await store.confirmPrivateEvidence({name: 'model_capture_bundle',
          semanticCid: fixture.identity, holdingCid: fixture.holdingCid,
          wire: bytes.toString('utf8')});
        const saved = checked(moon.clientProgramReadInferCaptureBundle(
          bytes.toString('utf8'), fixture.identity));
        const prepared = moon.clientProgramPreparationReady(prepare(program(), environment()));
        const replay = openNodeInferOperation({moon, preparedProgram: prepared,
          step: 2, graph: scopedInferGraph(prepared), registry, values,
          savedCapture: saved, quantum: 1});
        assert.equal(moon.clientProgramReleaseInferCaptureBundle(saved), true);
        const completed = await replay.run();
        assert.equal(replay.physicalStopped(), true);
        const rows = await inferExportRows(prepared, completed);
        const evidenceWire = moon.strategyRunEvidenceJson(
          replay.invocationEvidence(0));
        await replay.close();
        assert.equal(replay.cleanupPending(), false);
        process.stdout.write(JSON.stringify({rows, evidenceWire}));
      } finally { await store.close(); }
    `;
    const restarted = JSON.parse(execFileSync(process.execPath,
      ['--input-type=module', '-e', childSource], {encoding: 'utf8',
        input: JSON.stringify({task, baseEnvironment, registry, values,
          configuration: {...configuration, privateEvidenceKey: undefined},
          identity: exported.identity, holdingCid})}));
    assert.deepEqual(restarted.rows, [
      {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
    ]);
    assert.equal(restarted.evidenceWire, canonicalText(observation));
    assert.equal(original.calls(), 1);
  } finally {
    if (store !== undefined) await store.close();
    await rm(directory, {recursive: true, force: true});
  }
  // This proves authenticated restoration and component replay after restart,
  // not yet a committed Named Result through the public Run owner.
});

test('a macrotask stops nested capture serialization without releasing its owner early', async () => {
  const installedTask = structuredClone(task);
  installedTask.output_contract.fields.risk = {
    type: 'array', nullable: false, max_items: 1024,
    items: {type: 'number', nullable: false},
  };
  installedTask.output_schema_cid = cid(installedTask.output_contract);
  delete installedTask.contract_cid;
  installedTask.contract_cid = cid(installedTask);
  const original = ownedInfer(undefined, undefined, {
    scoped: true, installedTask,
    responseBody: canonicalText({reason: null, risk: Array(512).fill(0)}),
  });
  assert.equal((await ownedInferTerminal(original.active, undefined, 100000)).$tag, 1);
  const saved = moon.clientProgramAcquireInferCapture(original.active);
  const stream = checked(moon.clientProgramStartInferCaptureExport(saved, 100000, 10000));
  assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
  let reached = false;
  for (let poll = 0; poll < 100; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferCaptureExport(stream, 1))._0, false);
    if (moon.clientProgramInferCaptureExportResponsePending(stream)) {
      reached = true;
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(reached, true);
  for (let poll = 0; poll < 64; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferCaptureExport(stream, 1))._0, false);
    assert.equal(moon.clientProgramInferCaptureExportResponsePending(stream), true);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(moon.clientProgramInferCaptureExportIdentity(stream), undefined);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferCaptureExport(stream), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(stream)), false);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), false);
  const stopped = moon.clientProgramAdvanceInferCaptureExport(stream, 1);
  assert.equal(stopped.$tag, 0);
  assert.equal(stopped._0.$tag, 7, 'exact Cancelled cause');
  assert.equal(moon.clientProgramInferCaptureExportIdentity(stream), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(stream)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
  assert.equal(original.calls(), 1);
});

test('restored replay validates records and typed responses rather than accepting a matching slot', async () => {
  const original = ownedInfer(undefined, undefined, {scoped: true});
  assert.equal((await ownedInferTerminal(original.active)).$tag, 1);
  const capture = moon.clientProgramAcquireInferCapture(original.active);
  const exported = await exportedModelCapture(capture);
  const baseline = JSON.parse(exported.wire);
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exported.active)), true);
  assert.equal(moon.clientProgramReleaseInferCapture(capture), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
  assert.equal(moon.clientProgramReadInferCaptureBundle(exported.wire,
    cid({foreign: 'holding'})).$tag, 0);

  const cases = [
    ['raw response', slot => { slot.structured_response.risk = 'low'; }, false, 6],
    ['typed response', slot => { slot.structured_response.risk = 42; }, false, 5],
    ['key payload', slot => { slot.evidence.input_row_identity = 'b'; }, true, 6],
    ['slot', slot => {
      slot.model_call_slot_cid = cid({foreign: 'slot'});
      slot.evidence.model_call_slot_cid = slot.model_call_slot_cid;
    }, true, 6],
    ['request', slot => {
      slot.semantic_request_cid = cid({foreign: 'request'});
      slot.evidence.semantic_request_cid = slot.semantic_request_cid;
    }, true, 6],
    ['task', slot => { slot.evidence.model_task_contract_cid = cid({foreign: 'task'}); }, true, 6],
    ['artifact', slot => { slot.evidence.input_result_artifact_cid = cid({foreign: 'input'}); }, true, 6],
    ['unsealed observation', slot => { slot.evidence.provider_request_id = 'altered'; }, false, 13],
  ];
  for (const [name, mutate, reseal, cause] of cases) {
    const body = structuredClone(baseline);
    delete body.bundle_cid;
    mutate(body.captures[0]);
    if (reseal) {
      const {model_invocation_evidence_cid: ignored, ...evidence} = body.captures[0].evidence;
      void ignored;
      body.captures[0].evidence.model_invocation_evidence_cid = cid(evidence);
    }
    const identity = cid(body);
    // Transport/self integrity alone is valid, deliberately. The common
    // model owner must still reject inconsistent execution observations.
    const read = checked(moon.clientProgramReadInferCaptureBundle(
      canonicalText({...body, bundle_cid: identity}), identity));
    const prepared = moon.clientProgramPreparationReady(prepare(program(), environment()));
    const replay = checked(moon.clientProgramStartRestoredInferReplay(prepared, 2,
      scopedInferGraph(prepared), registry, values, read));
    assert.equal(moon.clientProgramReleaseInferCaptureBundle(read), true);
    const terminal = await ownedInferTerminal(replay);
    assert.equal(terminal.$tag, 2, name);
    assert.equal(terminal._0.$tag, 2, `${name}: model cause`);
    assert.equal(terminal._0._0.$tag, cause, `${name}: exact typed cause`);
    assert.equal(moon.clientProgramInferExecutionOutput(terminal), undefined);
    assert.equal(moon.clientProgramAcquireInferCapture(replay), undefined);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), true);
    assert.equal(original.calls(), 1, name);
  }
});

test('restored nested response remains private and cancellable during reconstruction', async () => {
  const installedTask = structuredClone(task);
  installedTask.output_contract.fields.risk = {
    type: 'array', nullable: false, max_items: 1024,
    items: {type: 'number', nullable: false},
  };
  installedTask.output_schema_cid = cid(installedTask.output_contract);
  delete installedTask.contract_cid;
  installedTask.contract_cid = cid(installedTask);
  const original = ownedInfer(undefined, undefined, {scoped: true, installedTask,
    responseBody: canonicalText({reason: null, risk: Array(512).fill(0)})});
  assert.equal((await ownedInferTerminal(original.active, undefined, 100000)).$tag, 1);
  const capture = moon.clientProgramAcquireInferCapture(original.active);
  const exported = await exportedModelCapture(capture);
  const saved = checked(moon.clientProgramReadInferCaptureBundle(exported.wire, exported.identity));
  assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exported.active)), true);
  assert.equal(moon.clientProgramReleaseInferCapture(capture), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
  const prepared = moon.clientProgramPreparationReady(prepare(program(),
    environment(true, undefined, installedTask)));
  const replay = checked(moon.clientProgramStartRestoredInferReplay(prepared, 2,
    scopedInferGraph(prepared, installedTask), registry, values, saved));
  assert.equal(moon.clientProgramReleaseInferCaptureBundle(saved), true);
  let reached = false;
  for (let poll = 0; poll < 2000; poll++) {
    const observed = checked(moon.clientProgramAdvanceInferExecution(replay, 1));
    assert.equal(observed.$tag, 0);
    if (moon.clientProgramInferExecutionRestoring(replay)) { reached = true; break; }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(reached, true);
  for (let poll = 0; poll < 64; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(replay, 1)).$tag, 0);
    assert.equal(moon.clientProgramInferExecutionRestoring(replay), true);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(moon.clientProgramAcquireInferCapture(replay), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), false);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferExecution(replay), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), false);
  const stopped = checked(moon.clientProgramAdvanceInferExecution(replay, 1));
  assert.equal(stopped.$tag, 3);
  assert.equal(moon.clientProgramInferExecutionOutput(stopped), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), true);
  assert.equal(original.calls(), 1);
});

test('a fresh normal preparation replays opaque checked observations without dispatch', async () => {
  const original = ownedInfer(undefined, undefined, {scoped: true});
  assert.equal(moon.clientProgramAcquireInferCapture(original.active), undefined);
  assert.equal((await ownedInferTerminal(original.active)).$tag, 1);
  const saved = moon.clientProgramAcquireInferCapture(original.active);
  assert.ok(saved);
  const prepared = moon.clientProgramPreparationReady(prepare(program(), environment()));
  assert.ok(prepared);
  assert.notEqual(prepared, original.prepared);
  // No physical provider is installed or accepted by this replay API.
  const replay = checked(moon.clientProgramStartInferReplay(prepared, 2,
    scopedInferGraph(prepared), registry, values, saved));
  assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
  assert.equal(moon.clientProgramReleaseInferCapture(saved), false);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), false);
  const terminal = await ownedInferTerminal(replay);
  assert.equal(terminal.$tag, 1, inspect(terminal));
  assert.deepEqual(await inferExportRows(prepared,
    moon.clientProgramInferExecutionOutput(terminal)), [
    {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
  ]);
  assert.equal(original.calls(), 1);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), false);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
  assert.equal(original.calls(), 1);
  assert.equal(moon.clientProgramStartInferReplay(prepared, 2,
    scopedInferGraph(prepared), registry, values, saved).$tag, 0);
});

test('replay rejects changed input and task instead of redispatching a model', async () => {
  const original = ownedInfer(undefined, undefined, {scoped: true});
  assert.equal((await ownedInferTerminal(original.active)).$tag, 1);
  const saved = moon.clientProgramAcquireInferCapture(original.active);
  assert.ok(saved);
  const changedTask = structuredClone(task);
  changedTask.authored_model_selector = 'fixture-other-model';
  delete changedTask.contract_cid;
  changedTask.contract_cid = cid(changedTask);
  const changedInput = program();
  changedInput.stages[0].steps[0].values.rows[0].text = 'changed';
  for (const [source, installedTask] of [[changedInput, task], [program(), changedTask]]) {
    const prepared = moon.clientProgramPreparationReady(
      prepare(source, environment(true, undefined, installedTask)));
    assert.ok(prepared);
    const replay = checked(moon.clientProgramStartInferReplay(prepared, 2,
      scopedInferGraph(prepared, installedTask), registry, values, saved));
    const terminal = await ownedInferTerminal(replay);
    assert.equal(terminal.$tag, 2, inspect(terminal));
    assert.equal(terminal._0.$tag, 2, 'Model issue');
    assert.equal(terminal._0._0.$tag, 6, 'exact OutputIdentity cause');
    assert.equal(moon.clientProgramAcquireInferOutput(replay), undefined);
    assert.equal(moon.clientProgramAcquireInferCapture(replay), undefined);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(replay)), true);
    assert.equal(original.calls(), 1);
  }
  assert.equal(moon.clientProgramReleaseInferCapture(saved), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)), true);
});

test('stopping between checked response and sealed observation issues no completed evidence', async () => {
  const {active, calls} = ownedInfer(undefined, undefined, {scoped: true});
  let reached = false;
  for (let poll = 0; poll < 20000; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 0);
    if (moon.clientProgramInferObservationPending(active)) {
      reached = true;
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(reached, true);
  assert.equal(calls(), 1);
  assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
  assert.equal(moon.clientProgramInferInvocationEvidence(active, 0), undefined);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferExecution(active), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 3);
  assert.equal(moon.clientProgramAcquireInferOutput(active), undefined);
  assert.equal(moon.clientProgramInferInvocationEvidence(active, 0), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(calls(), 1, 'cleanup must not repeat a physically completed call');
});

test('a macrotask stops unused nested input identity before scoped model dispatch', async () => {
  const source = program();
  source.stages[0].steps[0].values.schema.payload = {
    type: 'array', nullable: false,
    items: {type: 'number', nullable: false}};
  source.stages[0].steps[0].values.rows[0].payload = Array(500).fill(0);
  const {active, calls} = ownedInfer(source, undefined, {scoped: true,
    capacityOverrides: {max_nested_value_bytes: 10000, max_artifact_bytes: 10000}});
  let reached = false;
  for (let poll = 0; poll < 20000; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 0);
    if (moon.clientProgramInferIdentityPending(active)) {
      reached = true;
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(reached, true);
  for (let poll = 0; poll < 100; poll++) {
    assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 0);
    assert.equal(moon.clientProgramInferIdentityPending(active), true);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(calls(), 0);
  await new Promise(resolve => setImmediate(() => {
    assert.equal(moon.clientProgramCancelInferExecution(active), true);
    resolve();
  }));
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
  assert.equal(checked(moon.clientProgramAdvanceInferExecution(active, 1)).$tag, 3);
  assert.equal(moon.clientProgramAcquireInferOutput(active), undefined);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(calls(), 0);
});

test('owned inference observes cancellation at model and output handoffs', async () => {
  for (const where of ['input', 'response', 'output', 'handoff']) {
    let requested = false;
    const {active, calls} = ownedInfer(undefined, owner => {
      if (where === 'response') {
        requested = moon.clientProgramCancelInferExecution(owner);
      }
    });
    if (where === 'input') {
      requested = moon.clientProgramCancelInferExecution(active);
    }
    const terminal = await ownedInferTerminal(active, () => {
      if (!requested && (where === 'output' && calls() === 1 ||
          where === 'handoff' &&
            moon.clientProgramInferExecutionHandoffPending(active))) {
        assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), false);
        requested = moon.clientProgramCancelInferExecution(active);
      }
    });
    assert.equal(requested, true, where);
    assert.equal(terminal.$tag, 3, `${where}: ${inspect(terminal)}`);
    assert.equal(moon.clientProgramAcquireInferOutput(active), undefined);
    assert.equal(moon.clientProgramInferExecutionCapture(active), undefined);
    const stoppedCalls = calls();
    assert.equal(stoppedCalls, where === 'input' ? 0 : 1);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(calls(), stoppedCalls, 'cleanup cannot dispatch the model');
  }
});

test('owned inference closes an empty checked input without model dispatch', async () => {
  const source = program();
  source.stages[0].steps[0].values.rows = [];
  const {active, calls} = ownedInfer(source);
  assert.equal((await ownedInferTerminal(active)).$tag, 1);
  assert.equal(calls(), 0);
  assert.deepEqual(JSON.parse(moon.clientProgramModelCaptureJson(
    moon.clientProgramInferExecutionCapture(active))).captures, []);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
});

test('normal Infer dispatch respects actual Host and bound author item ceilings', async () => {
  const two = program();
  two.stages[0].steps[0].values.rows.push({id: 'b', text: 'hello'});
  const guarded = structuredClone(two);
  guarded.stages[0].steps[2].infer.max_items = 1;
  const parameterized = structuredClone(two);
  parameterized.params = {limit: {type: 'number', nullable: false}};
  parameterized.stages[0].steps[2].infer.max_items = {$param: 'limit'};
  for (const [source, options] of [
    [two, {hostItems: 1}],
    [guarded, {}],
    [parameterized, {parameters: {limit: 1}}],
  ]) {
    const {active, calls} = ownedInfer(source, undefined, options);
    const terminal = await ownedInferTerminal(active);
    assert.equal(terminal.$tag, 2, inspect(terminal, {depth: 4}));
    // Exact typed Model(ItemLimit), not a coincidental downstream failure.
    assert.equal(terminal._0.$tag, 2);
    assert.equal(terminal._0._0.$tag, 2);
    assert.equal(calls(), 0);
    assert.equal(moon.clientProgramInferExecutionOutput(terminal), undefined);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
    assert.equal(calls(), 0);
  }
  const {active, calls} = ownedInfer(two, undefined, {hostItems: 2});
  assert.equal((await ownedInferTerminal(active)).$tag, 1);
  assert.equal(calls(), 2);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(active)), true);
  assert.equal(calls(), 2);
});

test('only accepted model output enters the original checked Result transform', async () => {
  const {prepared, input, rows, active, calls} = await acceptedModel();
  const output = checked(moon.clientProgramStartModelOutput(input, rows, active));
  assert.equal(moon.clientProgramCompleteModelOutput(output).$tag, 0,
    'unsealed imported rows are not successful output');
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), false,
    'output owns the model capture and mapped input');
  let last = 0n;
  let complete = false;
  for (let poll = 0; poll < 200; poll++) {
    const observation = checked(moon.clientProgramAdvanceModelOutput(output, 1));
    const work = observation.$tag === 0 ? observation._0 : observation._1;
    assert.equal(work - last, 1n);
    last = work;
    if (observation.$tag === 1) { complete = true; break; }
    assert.equal(observation.$tag, 0, inspect(observation));
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.ok(complete);
  const completed = checked(moon.clientProgramCompleteModelOutput(output));
  assert.equal(checked(moon.clientProgramCompleteModelOutput(output)), completed,
    'repeated access retains one completion identity');
  const transform = checked(moon.clientProgramInferResultExportBegin(
    prepared, 0, completed));
  let ready = false;
  for (let poll = 0; poll < 200; poll++) {
    const state = checked(moon.clientProgramInferResultExportAdvance(transform, 1));
    assert.equal(typeof state._0, 'boolean', inspect(state));
    if (state._0) { ready = true; break; }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.ok(ready);
  const stream = checked(moon.clientProgramInferResultExportFinish(transform));
  let wire = '';
  for (let chunk = 0; chunk < 20; chunk++) {
    const next = checked(moon.clientProgramInferResultExportNext(stream));
    if (next === undefined) break;
    wire += next;
  }
  wire += checked(moon.clientProgramInferResultExportSeal(stream));
  // The existing publication payload contract is a row-object array.
  assert.deepEqual(JSON.parse(wire), [
    {id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}},
  ]);
  assert.equal(calls(), 1);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), false);
  moon.clientProgramInferResultExportClose(stream);
  assert.equal(checked(moon.clientProgramCleanupModelOutput(output)), true);
  assert.equal(checked(moon.clientProgramCleanupModelOutput(output)), true);
  assert.equal(moon.clientProgramCompleteModelOutput(output).$tag, 0);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(calls(), 1, 'export and cleanup never call the model again');
});

test('model output cancellation retains its capture until physical stop and cleanup', async () => {
  const {input, rows, active, calls} = await acceptedModel();
  const output = checked(moon.clientProgramStartModelOutput(input, rows, active));
  // This reaches admission of the nested ModelTask value, not prefix execution.
  for (let step = 0; step < 15; step++) {
    assert.equal(checked(moon.clientProgramAdvanceModelOutput(output, 1)).$tag, 0);
  }
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), false);
  assert.equal(moon.clientProgramCancelModelOutput(output), true);
  assert.equal(checked(moon.clientProgramAdvanceModelOutput(output, 1)).$tag, 3);
  assert.equal(moon.clientProgramCompleteModelOutput(output).$tag, 0);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), false);
  assert.equal(checked(moon.clientProgramCleanupModelOutput(output)), true);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(calls(), 1);
});

test('model output refuses unaccepted executions and a foreign prepared input owner', async () => {
  const input = startInput();
  const rows = await mappedRows(input);
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    request => {
      calls++;
      return moon.clientProgramModelResponse(request,
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  const active = checked(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`));
  assert.equal(moon.clientProgramStartModelOutput(input, rows, active).$tag, 0);
  assert.equal(calls, 0);
  assert.equal((await modelTerminal(active)).$tag, 1);
  const foreignInput = startInput();
  const foreignRows = await mappedRows(foreignInput);
  assert.equal(moon.clientProgramStartModelOutput(foreignInput,
    foreignRows, active).$tag, 0,
  'equal source, task, schema and values do not replace the exact owner');
  assert.equal(checked(moon.clientProgramCleanupInferInput(foreignInput)), true);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(calls, 1);
});

test('a response arriving after cancellation cannot authorize model output', async () => {
  const input = startInput();
  const rows = await mappedRows(input);
  let active;
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    request => {
      calls++;
      assert.equal(moon.clientProgramCancelModelExecution(active), true);
      return moon.clientProgramModelResponse(request,
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  active = checked(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`));
  const reservation = checked(moon.clientProgramAdvanceModelExecution(active, 1));
  assert.equal(reservation.$tag, 0,
    'reserve attempts in bounded steps before the first call');
  assert.equal(calls, 0);
  assert.equal((await modelTerminal(active, reservation._2 ?? reservation._1)).$tag, 3,
    'preflight reaches the provider before its cancellation stops the owner');
  assert.equal(moon.clientProgramStartModelOutput(input, rows, active).$tag, 0);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), false,
    'stop does not release mapped input before model cleanup');
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(calls, 1);
});

async function mappedRows(input) {
  let lastWork = 0n;
  for (let poll = 0; poll < 2000; poll++) {
    const value = checked(moon.clientProgramAdvanceInferInput(input, 1));
    const work = value.$tag === 0 ? value._0 : value._1;
    assert.ok(work >= lastWork && work - lastWork <= 1n);
    lastWork = work;
    const rows = moon.clientProgramInferInputRows(value);
    if (rows !== undefined) return rows;
    assert.equal(value.$tag, 0, inspect(value, {depth: 3}));
    // A macrotask boundary can deliver cancellation, unlike a microtask loop.
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('input did not reach a terminal outcome');
}

test('normal checked Relation completion feeds a registered ModelTask', async () => {
  const input = startInput();
  const rows = await mappedRows(input);
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider(
    'models/fixture', request => {
      calls++;
      assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
        '"hello"');
      return moon.clientProgramModelResponse(request,
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  assert.ok(provider);
  assert.equal(calls, 0, 'preparation must not call the provider');
  const active = checked(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`));
  assert.equal(moon.clientProgramCleanupModelExecution(active).$tag, 0,
    'the common session refuses cleanup before physical stop');
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), false,
    'the live ModelTask must retain its mapped input and prefix');
  assert.equal(calls, 0);
  let bundle;
  for (let poll = 0; poll < 20; poll++) {
    const observation = checked(moon.clientProgramAdvanceModelExecution(
      active, 1));
    bundle = moon.clientProgramModelCapture(observation);
    if (bundle !== undefined) break;
    assert.equal(observation.$tag, 0, inspect(observation, {depth: 5}));
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.ok(bundle);
  const captured = JSON.parse(moon.clientProgramModelCaptureJson(bundle));
  assert.equal(calls, 1);
  assert.equal(captured.task_cid, task.contract_cid);
  assert.equal(captured.captures.length, 1);
  assert.deepEqual(captured.captures[0].value, {reason: null, risk: 'high'});
  assert.equal(captured.captures[0].provider_model, 'fixture-risk-model');
  assert.equal(captured.captures[0].input_tokens, 1);
  assert.equal(captured.captures[0].output_tokens, 2);
  assert.equal(captured.captures[0].observed_at, '2026-10-01T00:00:00.000Z');
  assert.equal(moon.clientProgramReplayModelCapture(rows,
    `sha256:${'1'.repeat(64)}`, bundle), true);
  assert.equal(moon.clientProgramReplayModelCapture(rows,
    `sha256:${'2'.repeat(64)}`, bundle), false);
  const changed = program();
  changed.stages[0].steps[0].values.rows[0].id = 'b';
  const changedInput = startInput(changed);
  const changedRows = await mappedRows(changedInput);
  assert.equal(moon.clientProgramReplayModelCapture(changedRows,
    `sha256:${'1'.repeat(64)}`, bundle), false,
  'equal task and request identities cannot substitute a different key');
  assert.equal(checked(moon.clientProgramCleanupInferInput(changedInput)), true);
  assert.equal(calls, 1, 'replay must not dispatch the provider');
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(moon.clientProgramReplayModelCapture(rows,
    `sha256:${'1'.repeat(64)}`, bundle), false,
  'reclaimed input cannot be used to admit replay');
  assert.deepEqual(JSON.parse(moon.clientProgramModelCaptureJson(bundle))
    .captures[0].value, {reason: null, risk: 'high'},
  'transferred capture material survives releasing the execution owner');
  assert.equal(calls, 1, 'cleanup must not dispatch again');
});

test('a foreign physical provider is refused before invocation', async () => {
  const input = startInput();
  const rows = await mappedRows(input);
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/foreign',
    () => { calls++; return undefined; });
  assert.ok(provider);
  assert.equal(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`).$tag, 0);
  assert.equal(calls, 0);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
});

test('empty completed input captures no slots and invokes no provider', async () => {
  const source = program();
  source.stages[0].steps[0].values.rows = [];
  const input = startInput(source);
  const rows = await mappedRows(input);
  let calls = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture',
    () => { calls++; return undefined; });
  const active = checked(moon.clientProgramStartModelExecution(rows, provider,
    `sha256:${'1'.repeat(64)}`));
  const observation = await modelTerminal(active);
  const bundle = moon.clientProgramModelCapture(observation);
  assert.ok(bundle);
  assert.deepEqual(JSON.parse(moon.clientProgramModelCaptureJson(bundle))
    .captures, []);
  assert.equal(calls, 0);
  assert.equal(checked(moon.clientProgramCleanupModelExecution(active)), true);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
  assert.equal(moon.clientProgramReplayModelCapture(rows,
    `sha256:${'1'.repeat(64)}`, bundle), false);
});

test('the actual prefix key assertion runs before any model dispatch', async () => {
  const source = program();
  source.stages[0].steps[0].values.rows.push({id: 'a', text: 'duplicate'});
  const input = startInput(source);
  let failed = false;
  for (let poll = 0; poll < 2000; poll++) {
    const value = checked(moon.clientProgramAdvanceInferInput(input, 1));
    assert.equal(moon.clientProgramInferInputRows(value), undefined);
    if (value.$tag === 3) {
      failed = true;
      break;
    }
    assert.equal(value.$tag, 0);
  }
  assert.ok(failed);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
});

test('started prefix cancellation stops without producing mapped rows', async () => {
  const input = startInput();
  const first = checked(moon.clientProgramAdvanceInferInput(input, 1));
  assert.equal(first.$tag, 0);
  assert.ok(first._0 > 0n);
  assert.equal(moon.clientProgramCancelInferInput(input), true);
  let stopped = false;
  for (let poll = 0; poll < 20; poll++) {
    const value = checked(moon.clientProgramAdvanceInferInput(input, 1));
    assert.equal(moon.clientProgramInferInputRows(value), undefined);
    if (value.$tag === 2) {
      stopped = true;
      break;
    }
    assert.equal(value.$tag, 0);
  }
  assert.ok(stopped);
  assert.equal(checked(moon.clientProgramCleanupInferInput(input)), true);
});

test('normal Program checking retains the installed model acquisition', () => {
  const owner = environment();
  assert.ok(owner);
  const outcome = prepare(program(), owner);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.ok(prepared, String(moon.clientProgramPreparationIssueCode(outcome)));
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
});

test('normal INFER still requires installation and an actual key proof', () => {
  const absent = prepare(program(), environment(false));
  assert.equal(moon.clientProgramPreparationReady(absent), undefined);
  const unkeyed = program();
  unkeyed.stages[0].steps.splice(1, 1);
  const outcome = prepare(unkeyed, environment());
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
});
