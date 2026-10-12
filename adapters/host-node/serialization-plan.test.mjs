// Actual common compilation and opaque owner binding. This is not public
// dispatch or generation acceptance; no Store bytes or execution are invented.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {serializationTaskRunAdmission} from './local-values-plan.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {fileListingDeclaration} from './fixtures/file-listing-source.fixture.mjs';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';

const control = runtimeCore(moon).publicationControl;
const environmentWire = (await readFile(new URL('../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trim();
const environment = moon.clientProgramCheckEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
const token = digit => `sha256:${digit.repeat(64)}`;
const dataPolicy = Object.freeze({kind: 'data_policy',
  cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
  wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'});
const policy = {executionContextCid: token('a'), hostPolicyCid: token('b'),
  expiresAt: '2099-01-01T00:00:00.000Z'};
const acquiredEnvironmentWire = canonicalJson(JSON.parse(await readFile(new URL(
  './fixtures/two-source/left.environment.json', import.meta.url), 'utf8')));
const acquiredEnvironment = moon.clientProgramCheckEnvironment(acquiredEnvironmentWire,
  JSON.parse(acquiredEnvironmentWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert.ok(acquiredEnvironment, 'The existing Source environment must be admitted before Program checking');

test('public LIST_FILES SERIALIZE retains its acquired Content Plan', async () => {
  const fixture = fileListingDeclaration(moon, environmentWire);
  const environmentCid = JSON.parse(fixture.environment.wire).evidence_bundle_cid;
  const checkedEnvironment = moon.clientProgramCheckEnvironment(fixture.environment.wire,
    environmentCid, false, false, true, false, false, false, false);
  const preparation = installNodePublicSourcePreparation({moon, environment: checkedEnvironment,
    publication: {environmentCid, aliases: fixture.aliases}}).prepare({format: 'sql',
      document: "SELECT name, media_type FROM LIST_FILES(docs.invoices, glob => '**/*.csv') " +
        "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'listed.jsonl', max_rows = 3, max_bytes = 256) |> RESULT file"});
  const program = moon.clientProgramPreparationReady(preparation.outcome);
  assert.ok(program, moon.clientProgramPreparationIssueCode(preparation.outcome));
  const occurrences = moon.clientProgramSerializationOccurrences(program);
  assert.equal(occurrences.length, 1);
  const coordinates = {task: occurrences[0]._0, step: occurrences[0]._1,
    maxRows: 100, maxBytes: 1000000};
  try {
    const graph = control.prepareCheckedClientAcquiredSerializationGraph(program, coordinates);
    const compiled = control.prepareCheckedClientCompiledRun(program, 'serialization', policy, graph);
    const originalSourcePolicy = JSON.parse(fixture.environment.wire).schema_snapshots[0].source_data_policy_cid;
    const selected = control.compiledSerializationPolicy(compiled);
    assert.deepEqual(JSON.parse(selected.wire).source_data_policy_cids, [originalSourcePolicy]);
    assert.equal(control.compiledSourceFreeResultPolicy(compiled), undefined);
    assert.doesNotMatch(graph.wire, /REL\.values/u);
    assert.throws(() => control.prepareCheckedClientAcquiredSerializationGraph(program,
      {...coordinates, task: 0}), {code: 'RunHostContentPlanRejected'});
  } catch (cause) {
    throw new Error(JSON.stringify({coordinates, tasks: moon.clientProgramTaskCount(program),
      acquisitions: moon.clientProgramAcquisitionCount(program)}), {cause});
  }
});
function prepare() {
  const document = {version: 'actql/0.1', id: 'content-plan', stages: [{id: 'main',
    inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 2}, {id: 1}]}, as: 'seed'},
      {serialize: {format: 'jsonl', fields: ['id'], name: 'out.jsonl',
        preserve_order: true}, as: 'attachment'},
    ], results: {file: {from: 'attachment', fields: ['name', 'content']}}}],
  results: {file: {from: {stage: 'main', result: 'file'}}}};
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify(document), 'json', environment, undefined);
  const value = moon.clientProgramPreparationReady(preparation);
  assert.ok(value, moon.clientProgramPreparationIssueCode(preparation));
  return value;
}

function prepareAcquired() {
  const document = {version: 'actql/0.1', id: 'acquired-content-plan',
    stages: [{id: 'main', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{filter: 'id >= 0', as: 'filtered'},
        {select: ['id', 'amount'], as: 'captured'},
        {assert_rows: {unique_by: ['id']}, as: 'unique'},
        {serialize: {format: 'jsonl', fields: ['id', 'amount'], name: 'out.jsonl',
          order_by: [{id: 'asc'}]}, as: 'attachment'}],
      results: {file: {from: 'attachment', fields: ['name', 'content']}}}],
    results: {file: {from: {stage: 'main', result: 'file'}}}};
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify(document), 'json', acquiredEnvironment, undefined);
  const value = moon.clientProgramPreparationReady(preparation);
  assert.ok(value, moon.clientProgramPreparationIssueCode(preparation));
  return value;
}

test('acquired Content Plan uses checked Source policy and refuses fabricated source-free publication', () => {
  const program = prepareAcquired();
  const options = {task: 0, step: 3, maxRows: 3, maxBytes: 256};
  const graph = control.prepareCheckedClientAcquiredSerializationGraph(program, options);
  const compiled = control.prepareCheckedClientCompiledRun(program, 'serialization', policy, graph);
  assert.equal(control.compiledSourceFreeResultPolicy(compiled), undefined);
  const selected = control.compiledSerializationPolicy(compiled);
  const body = JSON.parse(selected.wire);
  assert.deepEqual(body.source_data_policy_cids,
    ['sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf']);
  assert.notEqual(selected.cid, dataPolicy.cid);
  const barrier = JSON.parse(graph.wire).nodes.find(node => node.kind === 'content_barrier');
  assert.equal(barrier.barrier.effective_output_data_policy_cid, selected.cid);
  assert.equal(barrier.barrier.serialization.preserve_order, true);
  assert.match(graph.wire, /REL\.orderByStable/u);
  assert.doesNotMatch(graph.wire, /REL\.values/u);
  const definition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'local', runId: 'acquired-content-plan-run',
      createdAt: '2026-10-10T00:00:00.000Z', validUntil: policy.expiresAt});
  assert.throws(() => control.issueCheckedClientCompiledInvocation(compiled,
    definition, {dataPolicyCid: selected.cid},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}), /RunHostInvocationRejected/u);
  assert.throws(() => control.prepareCheckedClientSerializationGraph(program,
    {...options, resultDataPolicy: dataPolicy}), /RunHostContentPlanRejected/u);
  assert.throws(() => control.prepareCheckedClientCompiledRun(prepareAcquired(),
    'serialization', policy, graph), /RunHostTaskCompilationRejected/u);
  assert.throws(() => control.prepareCheckedClientAcquiredSerializationGraph(prepare(),
    {...options, step: 1}), /RunHostContentPlanRejected/u);
});

test('Content selection compiles through the common Run and retains the policy original', () => {
  const program = prepare();
  assert.deepEqual(moon.clientProgramSerializationOccurrences(program), [{_0: 0, _1: 1}]);
  const graph = control.prepareCheckedClientSerializationGraph(program,
    {task: 0, step: 1, maxRows: 2, maxBytes: 18, resultDataPolicy: dataPolicy});
  const body = JSON.parse(graph.wire);
  const node = body.nodes.find(value => value.kind === 'content_barrier');
  assert.deepEqual(node.barrier.serialization, {bounds: {max_bytes: 18, max_rows: 2},
    encoding: 'utf-8', fields: ['id'], format: 'jsonl', line_ending: 'lf',
    name: 'out.jsonl', preserve_order: true});
  assert.equal(node.barrier.effective_output_data_policy_cid, dataPolicy.cid);
  assert.deepEqual(body.root_refs, [{name: 'file',
    ref: {node_id: 'result_0', port: 'projected'}, role: 'requested_result'}]);
  const compiled = control.prepareCheckedClientCompiledRun(program,
    'serialization', policy, graph);
  assert.deepEqual(control.compiledSourceFreeResultPolicy(compiled), dataPolicy);
  const template = JSON.parse(compiled.template.wire);
  assert.deepEqual(template.required_profile_contracts,
    [{contract_cid: node.barrier_contract_cid, profile_id: 'actql-content/0.1'}]);
  const changed = control.prepareCheckedClientSerializationGraph(program,
    {task: 0, step: 1, maxRows: 2, maxBytes: 19, resultDataPolicy: dataPolicy});
  assert.notEqual(control.prepareCheckedClientCompiledRun(program,
    'serialization', policy, changed).compiledPlan.identity, compiled.compiledPlan.identity);
  const definition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'local', runId: 'content-plan-run',
      createdAt: '2026-10-09T00:00:00.000Z', validUntil: policy.expiresAt});
  assert.throws(() => control.issueCheckedClientCompiledInvocation(compiled,
    definition, {dataPolicyCid: dataPolicy.cid},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
  /RunHostInvocationRejected/, 'A Content Plan is not evidence of generated bytes');
});

test('Content compilation rejects forged selection foreign owner and invalid policy before execution', () => {
  const program = prepare();
  const options = {task: 0, step: 1, maxRows: 2, maxBytes: 18, resultDataPolicy: dataPolicy};
  const graph = control.prepareCheckedClientSerializationGraph(program, options);
  assert.throws(() => control.prepareCheckedClientCompiledRun(program,
    'serialization', policy, {...graph}), /Foreign Content compilation graph/);
  assert.throws(() => control.prepareCheckedClientCompiledRun(prepare(),
    'serialization', policy, graph), /RunHostTaskCompilationRejected/);
  assert.throws(() => control.prepareCheckedClientSerializationGraph(program,
    {...options, maxBytes: 2147483648}), /Invalid Content compilation options/);
  assert.throws(() => control.prepareCheckedClientSerializationGraph(program,
    {...options, resultDataPolicy: {...dataPolicy, cid: token('c')}}), /RunHostContentPlanRejected/);
});

test('installed Host admission retains the Content component and original Definition without pure fallback', () => {
  const preparedProgram = prepare();
  const options = {moon, control, preparedProgram, authorityScopeCid: token('a'),
    namespaceId: 'local', now: () => '2026-10-09T00:00:00.000Z'};
  const first = serializationTaskRunAdmission(options);
  assert.equal(first.kind, 'serialization');
  const graph = JSON.parse(first.serializationGraph.wire);
  const barrier = graph.nodes.find(node => node.kind === 'content_barrier');
  assert.deepEqual(barrier.barrier.serialization.bounds,
    {max_bytes: 10000000, max_rows: 10000});
  assert.equal(barrier.barrier.effective_output_data_policy_cid, dataPolicy.cid);
  assert.deepEqual(control.compiledSourceFreeResultPolicy(first.compiled), dataPolicy);
  const restored = serializationTaskRunAdmission({...options,
    now: () => '2026-10-09T01:00:00.000Z',
    retainedDefinitionWire: first.runDefinition.wire});
  assert.equal(restored.runDefinition.wire, first.runDefinition.wire);
  assert.equal(restored.compiledPlan.identity, first.compiledPlan.identity);
  assert.equal(restored.preparedEvidence.wire, first.preparedEvidence.wire);
  assert.equal(restored.authorization.wire, first.authorization.wire);
  assert.throws(() => control.issueCheckedClientCompiledInvocation(first.compiled,
    first.runDefinition, {dataPolicyCid: dataPolicy.cid},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
  /RunHostInvocationRejected/u);
});
