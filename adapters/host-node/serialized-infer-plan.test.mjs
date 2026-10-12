// Real common compilation behind the installing Host boundary. This selection
// test grants no Model dispatch, media egress, Store completion or publication.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {inferTaskRunAdmission} from './local-values-plan.mjs';

const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const token = digit => `sha256:${digit.repeat(64)}`;
const canonical = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
  : JSON.stringify(value);

async function fixture({acquired = false} = {}) {
  // Reuse input vectors, not an oracle calculated from the product's Plan.
  const vectors = await readFile(new URL('../../src/client_infer_host/serialization_input_wbtest.mbt', import.meta.url), 'utf8');
  const task = JSON.parse(vectors.match(/let task =\s+#\|([^\n]+)/u)[1]);
  let document = vectors.match(/let source =\s+#\|([^\n]+)/u)[1];
  const executionWire = vectors.match(/let execution_wire =\s+#\|([^\n]+)/u)[1];
  const base = acquired
    ? JSON.parse((await readFile(new URL('../../src/run_publication_host/client_multi_source_wbtest.mbt',
      import.meta.url), 'utf8')).match(/let multi_source_environment : String =\s+#\|([^\n]+)/u)[1])
    : JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  if (acquired) {
    const program = JSON.parse(document);
    const stage = program.stages[0];
    stage.inputs = {remote: {connector: 'crm/main', resource: 'r'}};
    // Do not introduce an unattested literal threshold: this case separates
    // original Source provenance from the later Model response's provenance.
    stage.steps[0] = {from: 'remote', filter: 'id IS NOT NULL', as: 'filtered'};
    delete stage.steps[1].serialize.preserve_order;
    stage.steps[1].serialize.order_by = [{id: 'asc'}];
    // The installed acquisition boundary requires its checked filter/select
    // pair before the consumer. Keep it; Serialize is not a replacement scan.
    stage.steps.splice(1, 0, {select: ['id', 'amount'], as: 'captured'});
    stage.steps.splice(2, 0, {assert_rows: {unique_by: ['id']}, as: 'unique_input'});
    document = canonical(program);
  }
  const {evidence_bundle_cid: _, ...body} = base;
  body.model_task_contracts = [task];
  body.host_policy_profile.capacity.max_model_request_bytes_per_item = 4096;
  const evidenceCid = hash(canonical(body));
  const environment = moon.clientProgramCheckEnvironment(canonical({...body,
    evidence_bundle_cid: evidenceCid}), evidenceCid, false, false, true, false, false, false, false);
  assert.notEqual(environment, undefined);
  const prepared = moon.clientProgramPrepareEffectFree(document, 'json', environment);
  assert.notEqual(prepared, undefined, prepared === undefined
    ? inspect(moon.clientProgramPrepareEffectFreeWithParameters(document, 'json', environment, undefined),
      {depth: 12}) : undefined);
  const occurrence = checked(moon.clientProgramComposedInferOccurrences(prepared))[0];
  assert.notEqual(occurrence, undefined);
  const execution = checked(moon.clientProgramReadInferModelExecution(prepared,
    acquired ? 5 : 3, executionWire, JSON.parse(executionWire).self_cid));
  const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  const policy = {kind: 'data_policy', cid: hash(policyWire), wire: policyWire};
  return {prepared, occurrence, execution, policy};
}

test('Host selects the real Content component in a mixed Model Plan without invented public roots', async () => {
  const f = await fixture();
  const control = runtimeCore(moon).publicationControl;
  const options = {task: 0, step: 1, maxRows: 2, maxBytes: 18, resultDataPolicy: f.policy};
  assert.throws(() => control.prepareCheckedClientSerializationGraph(f.prepared, options),
    error => error.code === 'RunHostContentPlanRejected');
  const component = control.prepareCheckedClientSerializationComponent(f.prepared, options);
  assert.deepEqual(JSON.parse(component.wire).root_refs, []);
  const graph = control.prepareCheckedClientSerializedInferGraph(f.occurrence, component, f.execution);
  const plan = JSON.parse(moon.clientProgramInferPlanGraphWire(graph));
  assert.deepEqual(plan.nodes.map(node => node.node_id), [
    'task_0_before_serialize_1', 'task_0_serialize_1',
    'task_0_after_serialize_2', 'task_0_infer_3',
  ]);
  assert.equal(plan.data_edges.length, 3);
  assert.equal(plan.root_refs.length, 1);
  assert.equal(JSON.stringify(plan).includes('REL.serialize'), false);
  const admitted = inferTaskRunAdmission({control, preparedProgram: f.prepared,
    inferGraph: graph, resultDataPolicy: f.policy,
    authorityScopeCid: token('a'), namespaceId: 'mixed-content',
    now: () => '2026-10-10T00:00:00.000Z'});
  assert.equal(admitted.kind, 'infer');
  assert.deepEqual(control.compiledSerializationPolicy(admitted.compiled), f.policy);
  assert.match(control.checkedClientSerializationByteHoldingCid(admitted.compiled,
    admitted.runDefinition, token('b')), /^sha256:[0-9a-f]{64}$/u);
  assert.equal(JSON.parse(admitted.template.wire).required_profile_contracts.length, 2);
  assert.throws(() => control.startCheckedClientContentInferObservation(admitted.compiled,
    [], [{}], {}, {maxSlots: 2, maxWireBytes: 4096, maxWork: 4}),
  /Foreign Client Content generation/u);
  assert.throws(() => control.compiledSerializationPolicy({...admitted.compiled}),
    /Foreign Client compiled Content Run/u);
  assert.throws(() => control.startCheckedClientGeneratedInferExecution(
    admitted.compiled, {}, f.prepared, graph, {}), /Foreign Client Content generation/u);
  assert.throws(() => control.startCheckedClientGeneratedInferExecution(
    {...admitted.compiled}, {}, f.prepared, graph, {}), /Foreign Client compiled Content Run/u);
});

test('Host rejects copied Content selection and equal-but-foreign prepared owners', async () => {
  const f = await fixture();
  const other = await fixture();
  const control = runtimeCore(moon).publicationControl;
  const component = control.prepareCheckedClientSerializationComponent(f.prepared,
    {task: 0, step: 1, maxRows: 2, maxBytes: 18, resultDataPolicy: f.policy});
  assert.throws(() => control.prepareCheckedClientSerializedInferGraph(f.occurrence,
    {...component}, f.execution), /Foreign Content compilation graph/u);
  assert.throws(() => control.prepareCheckedClientSerializedInferGraph(other.occurrence,
    component, other.execution), error => error.code === 'RunHostContentInferPlanRejected');
});

test('Host retains the checked acquired policy and Source port in an intermediate Content Model Plan', async () => {
  const f = await fixture({acquired: true});
  const control = runtimeCore(moon).publicationControl;
  const options = {task: 0, step: 3, maxRows: 2, maxBytes: 18};
  assert.throws(() => control.prepareCheckedClientAcquiredSerializationGraph(f.prepared, options),
    error => error.code === 'RunHostContentPlanRejected');
  assert.throws(() => control.prepareCheckedClientSerializationComponent(f.prepared,
    {...options, resultDataPolicy: f.policy}), error => error.code === 'RunHostContentPlanRejected');
  const component = control.prepareCheckedClientAcquiredSerializationComponent(f.prepared, options);
  const prefix = JSON.parse(component.wire);
  assert.deepEqual(prefix.root_refs, []);
  const input = prefix.nodes.find(node => node.node_id === 'task_0_before_serialize_3');
  assert.deepEqual(input.pipeline.sources, {remote: {sort: 'relation'}});
  assert.deepEqual(input.input_contracts,
    {remote: 'sha256:9acb07a25a365ae4cc47286f663bea8727eea912cdc188cddb55ca136c38c163'});
  const graph = control.prepareCheckedClientSerializedInferGraph(f.occurrence, component, f.execution);
  const plan = JSON.parse(moon.clientProgramInferPlanGraphWire(graph));
  assert.equal(plan.root_refs.length, 1);
  // Acquired task completion needs the existing explicit Result projection,
  // rather than treating its capture target as the Model's completed port.
  assert.deepEqual(plan.nodes.map(node => node.node_id), [
    'task_0_before_serialize_3', 'task_0_serialize_3',
    'task_0_after_serialize_4', 'task_0_infer_5', 'result_0',
  ]);
  assert.equal(plan.data_edges.length, 4);
  assert.equal(plan.root_refs[0].ref.node_id, 'result_0');
  assert.equal(JSON.stringify(plan).includes('REL.values'), false);
  const barrier = prefix.nodes.find(node => node.kind === 'content_barrier').barrier;
  assert.notEqual(barrier.effective_output_data_policy_cid, f.policy.cid,
    'an acquired Source cannot adopt the empty unknown-provenance Host policy');
  assert.deepEqual(barrier.input_data_policy_cids, [barrier.effective_output_data_policy_cid]);
  const admitted = inferTaskRunAdmission({control, preparedProgram: f.prepared,
    inferGraph: graph, resultDataPolicy: f.policy,
    authorityScopeCid: token('a'), namespaceId: 'acquired-mixed-content',
    now: () => '2026-10-10T00:00:00.000Z'});
  const original = control.compiledSerializationPolicy(admitted.compiled);
  assert.equal(original.cid, barrier.effective_output_data_policy_cid);
  const policy = JSON.parse(original.wire);
  assert.equal(policy.unknown_provenance, false,
    'Serialize bytes retain the Source provenance, not the later Model response');
  assert.deepEqual(policy.source_data_policy_cids,
    ['sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf']);
  assert.equal(policy.source_response_policy_cids.length, 1);
  assert.notEqual(original.cid, moon.clientProgramPublicationDataPolicyCid(f.prepared),
    'Content and final Model output have different original policies');
  assert.throws(() => control.prepareCheckedClientSerializedInferGraph(f.occurrence,
    {...component}, f.execution), /Foreign Content compilation graph/u);
  assert.throws(() => control.prepareCheckedClientAcquiredSerializationComponent(f.prepared,
    {...options, maxBytes: -1}), /Invalid acquired Content compilation options/u);
});
