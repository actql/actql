// Actual checked Core originals with explicit synthetic physical allowances.
// This is not a normal numerical layout, Provider transport or public startup.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
const source = readFileSync(new URL('../../src/client_infer_host/fixture.generated_wbtest.mbt', import.meta.url), 'utf8');
const input = name => source.match(new RegExp(`let ${name} : String =\\n\\s+#\\|([^\\n]+)`, 'u'))[1];
const cid = c => `sha256:${c.repeat(64)}`;
const identity = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;

export async function currentResourceFixture(moon, control, runId = 'current-resource') {
  const environment = moon.clientProgramCheckEnvironment(input('infer_fixture_environment'),
    input('infer_fixture_environment_cid'), false, false, true, false, false, false, false);
  const prepared = moon.clientProgramPreparationReady(moon.clientProgramPrepareEffectFreeWithParameters(
    input('infer_fixture_program'), 'json', environment, undefined));
  const task = JSON.parse(input('infer_fixture_environment')).model_task_contracts[0];
  const step = moon.clientProgramSelectedInferStep(prepared);
  const executionBody = {version: 'actql-model-execution-contract/0.1', model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: cid('a'), backoff_contract_cid: cid('a'),
    max_attempts_per_slot: 2, max_total_attempts: 4, max_total_cost_units: 0,
    max_total_duration_ms: 1000, max_total_wire_bytes: 133072, max_total_token_reservation: 128,
    media_input_contracts: {}, default_publication: 'outcomes'};
  const executionCid = identity(executionBody);
  const execution = checked(moon.clientProgramReadInferModelExecution(prepared, step,
    canonicalText({...executionBody, self_cid: executionCid}), executionCid));
  const graph = checked(moon.clientProgramInferPlanGraph(prepared, step, execution, cid('b'), cid('c')));
  const policy = {version: 'actql-effective-data-policy/0.1', classification: 'unknown',
    source_data_policy_cids: [], source_response_policy_cids: [], unknown_provenance: true};
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer',
    {executionContextCid: cid('d'), hostPolicyCid: cid('d'), expiresAt: '2099-01-01T00:00:00.000Z',
      resultDataPolicy: {kind: 'data_policy', cid: identity(policy), wire: canonicalText(policy)}}, graph);
  const runDefinition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'scope', runId, createdAt: '2026-10-02T00:00:00.000Z', validUntil: '2099-01-01T00:00:00.000Z'});
  const template = JSON.parse(compiled.template.wire);
  const profileWire = readFileSync(new URL('../../src/run_publication_host/client_model_preparation_layout_wbtest.mbt', import.meta.url), 'utf8')
    .match(/#\|(\{[^\n]+\})/u)[1];
  const profileBody = JSON.parse(profileWire);
  const profile = control.readInstalledModelResponseProfile(profileWire, profileBody.self_cid,
    {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 30, maxMembers: 1000, maxWork: 100000});
  const installation = {...profileBody.adapter,
    sdk: undefined, endpoint: profileBody.operation.endpoint, http_method: profileBody.operation.method,
    streaming: profileBody.operation.streaming, validator_id: profileBody.completion.validator_id,
    validator_revision: profileBody.completion.validator_revision,
    validator_artifact_cid: profileBody.completion.validator_artifact_cid,
    completion_basis: profileBody.completion.basis};
  delete installation.port_abi;
  const selected = {layout: {response_profile: profile, runtime_artifact_cid: cid('d'), layout_artifact_cid: cid('e'),
    program_definition_cid: template.program_definition_cid, parameter_values_cid: template.parameter_values_cid,
    barrier_cid: moon.clientProgramInferPlanBoundary(graph)._3,
    prepared_rows: 2n, retained_bytes: 7000n, execution_bytes: 3000n},
  installation, runtimeArtifactCid: cid('d'), layoutArtifactCid: cid('e'), probability: undefined};
  const scope = control.beginCheckedClientInferOriginalReadScope(compiled, runDefinition, graph,
    {bootstrapRetainedBytes: 100000n, bootstrapExecutionBytes: 100000n,
      maxReservations: 8, maxHoldings: 8, maxDelegations: 8});
  const read = control.prepareCheckedClientInferNodeReadLayout(compiled, runDefinition, graph, scope, selected);
  let sends = 0;
  const provider = moon.clientProgramInstallModelProvider('models/fixture', () => {sends++; return undefined;});
  const originalPreparation = {scope, read, control, compiled, runDefinition, nodeInstallation: selected,
    readRetainedBytes: 7000n, readExecutionBytes: 3000n, modelRetainedBytes: 100000n, modelExecutionBytes: 3000n};
  const operation = openNodeInferOperation({moon, preparedProgram: prepared, step, graph,
    registry: input('infer_fixture_registry'), values: input('infer_fixture_values'),
    provider, originalPreparation, durableCalls: true});
  operation.bindRun(control, {compiled, runDefinition});
  await operation.run();
  const preparedCallSet = operation.preparedCallSet();
  return {operation, scope, read, graph, compiled, runDefinition, selected, originalPreparation,
    preparedCallSet, sends: () => sends};
}
