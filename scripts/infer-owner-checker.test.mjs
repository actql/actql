import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {inspect} from 'node:util';

import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

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

function ownedInfer(source = program(), onInvoke, options = {}) {
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
      canonicalText(source), 'json', environment(true, options.hostItems, task,
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
        '{"reason":null,"risk":"high"}', 'fixture-risk-model', 'request-1',
        1n, 2n, '2026-10-01T00:00:00.000Z');
    });
  active = checked(moon.clientProgramStartInferExecution(
    prepared, 2, registry, values, provider, `sha256:${'1'.repeat(64)}`));
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

async function ownedInferTerminal(active, atYield) {
  let lastWork = 0n;
  for (let poll = 0; poll < 2000; poll++) {
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
