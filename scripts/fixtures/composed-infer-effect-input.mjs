// Independent acceptance input for #182. One Program owns every operation;
// the harness installs fixtures and submits it, never runs its stages itself.
import assert from 'node:assert/strict';
import {providerBindingOriginals} from './model-provider-binding-fixture.mjs';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonical, cid} from './installed-infer-fixture.mjs';

const fixture = name => JSON.parse(readFileSync(new URL(name, import.meta.url), 'utf8'));
export const compositionTemplate = fixture('./composed-infer-effect.program.template.json');
export const compositionExpectations = fixture('./composed-infer-effect.expected.json');
export const databaseRows = compositionExpectations.databaseRows;
export const expectedClassified = compositionExpectations.classified;
export const expectedUpdates = compositionExpectations.updates;
export const expectedWrites = compositionExpectations.writes;
export const expectedModelInputs = compositionExpectations.modelInputs;
export const classifiedColumns = compositionExpectations.classifiedColumns;
export const updateColumns = compositionExpectations.updateColumns;

// Only the newly published Effect MappingRef is installation-specific.
// Bind that one field; retain every authored expression and literal verbatim.
export function compositionProgram(mappingRef) {
  assert.equal(typeof mappingRef, 'string');
  assert.ok(mappingRef.length > 0);
  const program = structuredClone(compositionTemplate);
  const update = program.stages.find(stage => stage.id === 'apply').effects.save.update;
  assert.equal(update.mapping, '__PUBLICATION_MAPPING_REF__');
  update.mapping = mappingRef;
  return program;
}

// Independently authored text: bind only the installed MappingRef, never a
// generated Program, operation or Effect. Exact bytes are persisted on submit.
export const compositionTextTemplate = readFileSync(new URL(
  './composed-infer-effect.aql.template', import.meta.url), 'utf8');
const nullAssertionText = readFileSync(new URL(
  './composed-infer-effect-null-assert.aql.template', import.meta.url), 'utf8');
export function compositionText(mappingRef, variant = 'normal') {
  assert.equal(typeof mappingRef, 'string');
  assert.ok(mappingRef.length > 0 && !/[`\\\r\n]/u.test(mappingRef));
  assert.ok(['normal', 'duplicate', 'null'].includes(variant));
  const template = variant === 'null' ? nullAssertionText : compositionTextTemplate;
  assert.equal(template.split('__PUBLICATION_MAPPING_REF__').length, 2);
  return template.replace('__PUBLICATION_MAPPING_REF__', mappingRef);
}

// Installed contract and deterministic test provider remain separate from the
// Program. No real service, credential, charge or external write is involved.
export async function modelConfiguration(baseEnvironment) {
  const {canonical, cid} = await import('./installed-infer-fixture.mjs');
  const input = {type: 'object', nullable: false,
    additional_properties: false,
    fields: {score: {type: 'number', nullable: true}}};
  const output = {type: 'object', nullable: false,
    additional_properties: false,
    fields: {risk: {type: 'string', nullable: false}}};
  const bodies = Object.freeze([
    {version: 'actql-model-prompt/0.1', payload: {
      format: 'composition-risk/0.1', instructions: 'Classify the score.'}},
    {version: 'actql-model-retry-policy/0.1', retryable_failures: []},
    {version: 'actql-model-backoff/0.1', delays_ms: []},
  ].map(body => Object.freeze({cid: cid(body),
    bodyWire: canonical({...body, self_cid: cid(body)})})));
  const task = {schema: 'actql.model_task/0.1',
    task_id: 'model-task:composition-risk.v1', version: '1',
    task_kind: 'structured_generate',
    authored_model_selector: 'composition-risk-model',
    connector_id: 'models/composition', input_contract: input,
    input_schema_cid: cid(input), output_contract: output,
    output_schema_cid: cid(output), prompt_template_cid: bodies[0].cid,
    max_items: 2, generation_config: {max_output_tokens: 32,
      seed_requested: -7, temperature: 0, top_p: 1},
    data_handling: {accepted_classifications: ['public', 'internal'],
      allowed_regions: ['fixture-region'],
      contract_cid: `sha256:${'a'.repeat(64)}`,
      retention: 'none', training_use: 'forbidden'},
    retrieval_policy: 'none', streaming: false, tool_policy: 'none'};
  const taskCid = cid(task);
  const {evidence_bundle_cid: ignored, ...environment} = baseEnvironment;
  void ignored;
  environment.model_task_contracts = [{...task, contract_cid: taskCid}];
  const execution = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: taskCid,
    retry_classification_contract_cid: bodies[1].cid,
    backoff_contract_cid: bodies[2].cid,
    max_attempts_per_slot: 1, max_total_attempts: 2,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_wire_bytes: 133072, max_total_token_reservation: 66,
    media_input_contracts: {}, default_publication: 'outcomes'};
  // This authored installation is the supplier's closed DATA original. The
  // Host borrows it; initialization must not freeze or copy a caller's graph.
  return {taskCid, installation: Object.freeze({
    environmentWire: canonical({...environment,
      evidence_bundle_cid: cid(environment)}),
    executionContracts: Object.freeze([Object.freeze({modelTaskCid: taskCid, cid: cid(execution),
      bodyWire: canonical({...execution, self_cid: cid(execution)})})]),
    dependencyBodies: bodies,
  })};
}

export function registerCompositionModel(moon, taskCid, record, {
  cleanup = () => true, installation, runtimeSource, publicationControl,
} = {}) {
  assert(Object.isFrozen(installation), 'Original composition Model installation required');
  assert(runtimeSource instanceof Uint8Array && runtimeSource.byteLength > 0,
    'Original installed Model caller Source required');
  const task = JSON.parse(installation.environmentWire).model_task_contracts
    .find(task => task.contract_cid === taskCid);
  assert(task, 'Same composition Model Task required');
  const bindingOriginals = providerBindingOriginals('models/composition', {
    selector: 'composition-risk-model', revision: 'independent-composition-provider-1'});
  const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const supplierArtifactCid = digest(readFileSync(new URL(import.meta.url)));
  const runtimeArtifactCid = digest(runtimeSource);
  // This is the SAME deterministic physical supplier, not the nominal Mock
  // path. Its response profile names its actual non-SDK implementation and
  // original binding; profile admission never authorizes a Model call.
  const profileBody = {
    version: 'actql-model-response-profile/0.1',
    adapter: {builder_id: 'fixture/composition-risk', builder_revision: '1',
      codec_id: 'fixture/composition-risk', codec_revision: '1',
      build_artifact_cid: supplierArtifactCid, port_abi: 'model-physical-port/1', sdk: null},
    operation: {endpoint: JSON.parse(bindingOriginals.configuration.wire).endpoint,
      method: 'POST', streaming: false},
    task: {contract_cid: taskCid, kind: task.task_kind,
      input_schema_cid: task.input_schema_cid, output_schema_cid: task.output_schema_cid},
    completion: {validator_id: 'fixture/composition-risk', validator_revision: '1',
      validator_artifact_cid: supplierArtifactCid, basis: 'generation_finish',
      transport_eof: true, endpoint_envelope: true, output_contract: true},
    probability: null,
    observations: ['provider_request_id', 'provider_reported_model_id', 'finish_reason',
      'input_tokens', 'output_tokens', 'provider_metadata'],
    // Same finite response/decoder envelope as the existing non-SDK fixture;
    // the request remains the original 1000-byte physical preflight ceiling.
    limits: {request_bytes: 1000, response_bytes: 2048, chunk_bytes: 512, chunks: 16,
      header_bytes: 256, metadata_bytes: 128, metadata_nodes: 16, metadata_depth: 4,
      parse_nodes: 256, parse_depth: 16, parse_work: 8192,
      adapter_holding_bytes: 4096, adapter_workspace_bytes: 2048,
      active_slots: task.max_items, unsettled_slots: task.max_items},
    controls: {model_requests: 1, retry: false, fallback: false, hedging: false,
      tools: false, repair: false, cache: false, media_fetch: false,
      workflow_restore: false, sdk_telemetry: false, redirect: false},
  };
  const profile = publicationControl.readInstalledModelResponseProfile(
    canonical({...profileBody, self_cid: cid(profileBody)}), cid(profileBody),
    {maxWireBytes: 16384, maxNodes: 1000, maxDepth: 30, maxMembers: 1000, maxWork: 100000});
  const node = {...profileBody.adapter, sdk: undefined,
    endpoint: profileBody.operation.endpoint, http_method: profileBody.operation.method,
    streaming: false, validator_id: profileBody.completion.validator_id,
    validator_revision: profileBody.completion.validator_revision,
    validator_artifact_cid: supplierArtifactCid, completion_basis: profileBody.completion.basis};
  delete node.port_abi;
  // Reuse the existing generatedContentModelProviders fixture's conservative
  // Node control/representation envelope. Retain every declared Task row,
  // UTF-8/UTF-16/copy overlap, failed decoder values and response metadata.
  // Native Graph/Model amounts are ADDED by bindInferOriginalReadRecipe;
  // none of these declarations is a resource grant or cleanup receipt.
  const controls = 14464n, rows = BigInt(task.max_items), limits = profileBody.limits;
  const buffers = BigInt(limits.request_bytes + limits.response_bytes + limits.chunk_bytes +
    limits.header_bytes + limits.metadata_bytes);
  const read = rows * (controls + 4n * buffers + 256n * BigInt(limits.parse_nodes + limits.metadata_nodes));
  const layoutArtifactCid = cid({profile: cid(profileBody), preparedRows: task.max_items,
    fixedControls: String(controls), nodeRetained: String(read), nodeExecution: String(read)});
  const originalReadRecipe = {
    bootstrap: {bootstrapRetainedBytes: controls, bootstrapExecutionBytes: controls,
      maxReservations: 12, maxHoldings: 8, maxDelegations: 4},
    modelRetainedBytes: controls, modelExecutionBytes: controls,
    currentStateCodec: {quantum: 64, comparisonWork: 26, decode: {maxWork: 100000,
      parse: {max_input_bytes: 65536, max_nodes: 8192, max_depth: 64},
      tree: {max_nodes: 8192, max_depth: 64, max_string_bytes: 65536, max_total_string_bytes: 65536}}},
    storeBootstrap: {maxWireBytes: 65536, maxDirectoryEntries: 128},
    metadataAcquisition: {metadata: {maxWireBytes: 65536, maxLedgerEntries: 16},
      directory: {maxWireBytes: 65536, maxDirectoryEntries: 128}, retainedBytes: read, workspaceBytes: read},
    publicationCapacity: {retainedBytes: read, workspaceBytes: read},
    nodeInstallation: {layout: {response_profile: profile,
      runtime_artifact_cid: runtimeArtifactCid, layout_artifact_cid: layoutArtifactCid,
      prepared_rows: rows, retained_bytes: read, execution_bytes: read},
    installation: node, runtimeArtifactCid, layoutArtifactCid, probability: undefined},
  };
  const checked = value => {
    if (value?.$tag !== 1) throw new Error('CompositionModelAdmissionFailed');
    return value._0;
  };
  return [{providerId: 'models/composition', originalReadRecipe, bindingOriginals,
    invoke() { throw new Error('UnpreparedCompositionModelCall'); },
    validatePrompt(actual, selector, wire) {
      return actual === taskCid && selector === 'composition-risk-model' &&
        JSON.parse(wire).format === 'composition-risk/0.1';
    },
    quantityCapacity: {
      limits: {tokens: 66n, costUnits: 0n, durationMs: 1000n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: 'public', _1: 'fixture-region',
      _2: false, _3: false}),
    physicalPreflight: request => moon.clientProgramModelRequestPreflight(
      () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
        request, 1000n, 33n, 0n, 500n, () => {
          const score = JSON.parse(moon.clientProgramModelRequestInput(
            request, 'score'));
          record(score);
          return moon.clientProgramModelResponse(request,
            JSON.stringify({risk: score >= 200 ? 'high' : 'low'}),
            'composition-risk-model', 'composition-request-' + score,
            1n, 2n, new Date().toISOString());
        }))}), cleanup),
  }];
}

// These databases contain only this fixture's authored public rows. Reissue
// the declaration graph as a unit; do not relabel a captured provider result.
export async function publicFixtureEnvironment(original, hostPolicyProfile) {
  const {cid} = await import('./installed-infer-fixture.mjs');
  const environment = structuredClone(original);
  const policy = environment.contract_registry.find(item =>
    item.kind === 'data_policy');
  const {cid: oldPolicy, ...policyBody} = policy;
  if (cid(policyBody) !== oldPolicy) throw new Error('InvalidFixturePolicy');
  policy.body.classification = 'public';
  policy.cid = cid({...policyBody, body: policy.body});
  const view = environment.source_views[0];
  const {contract_cid: oldView, ...viewBody} = view;
  if (cid(viewBody) !== oldView) throw new Error('InvalidFixtureView');
  view.output.data_policy.cid = policy.cid;
  view.contract_cid = cid({...viewBody, output: view.output});
  for (const capability of environment.connector_capabilities) {
    if (capability.source_contract_cid !== oldView ||
        capability.source_view_contract_cid !== oldView) {
      throw new Error('InvalidFixtureSourceCapability');
    }
    capability.source_contract_cid = view.contract_cid;
    capability.source_view_contract_cid = view.contract_cid;
  }
  const catalog = environment.connector_catalogs[0];
  catalog.contracts = environment.contract_registry.map(item =>
    structuredClone(item)).sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = cid(catalog);
  for (const snapshot of environment.schema_snapshots) {
    snapshot.source_contract_cid = view.contract_cid;
    snapshot.source_view_contract_cid = view.contract_cid;
    snapshot.source_data_policy_cid = policy.cid;
    snapshot.data_classification = 'public';
  }
  // A newly authored publication uses its installing Host's complete policy.
  // Keep this before the evidence CID and provider installation; never rewrite
  // an admitted publication or infer a policy from its sample rows.
  if (hostPolicyProfile !== undefined) {
    environment.host_policy_profile = structuredClone(hostPolicyProfile);
  }
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = cid(environment);
  return environment;
}

// Isolate the D-owned acquisition-to-Effect handoff while the acquired Infer
// owner is developed by A. This does not stand in for the full Program above.
export function twoSourceEffectProgram(mappingRef) {
  const full = compositionProgram(mappingRef);
  const joined = full.stages[2];
  const apply = full.stages[3];
  return {...full, id: 'fixture.two-source-effect', stages: [
    full.stages[0], full.stages[1],
    {...joined, steps: [joined.steps[0],
      {filter: 'right_amount >= 200'},
      {derive: {risk: {literal: 'high'}}}, ...apply.steps.slice(1)],
    results: apply.results, effects: apply.effects},
  ], results: {updates: {from: {stage: 'classify', result: 'rows'}}}};
}
