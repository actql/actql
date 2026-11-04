// Synthetic historical-format Salesforce read originals for current public recovery.
// This is not old-public-producer acceptance. Only the existing local HTTPS
// mock publication is used; no live provider, read, approval or Run is seeded.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';

const wire = value => value === null || typeof value !== 'object'
  ? JSON.stringify(value) : Array.isArray(value) ? `[${value.map(wire).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${wire(value[key])}`).join(',')}}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid = value => hash(wire(value));
const identityWire = wire, dataCid = cid;

// Finite independent declaration for the mock's exact three string fields.
// The installed publisher must produce this Catalog; no returned compiler,
// prepare, sealer or acceptance identity supplies these expected bodies.
async function declaredSource(runtimeRootUrl, publication) {
  const connectorId = 'crm-main', revision = 'salesforce/0.1';
  const sourceRef = 'connector://crm-main/Test_Record__c#records';
  const fields = {External_Key__c: {nullable: false, type: 'string'},
    Id: {nullable: false, type: 'string'}, Name: {nullable: false, type: 'string'}};
  const envelopes = [];
  const envelope = (name, kind, body) => {
    const entry = {schema: 'actql.contract/0.1', id: `${connectorId}/Test_Record__c/records/${name}`,
      version: revision, kind, body};
    const sealed = {...entry, cid: cid(entry)};
    envelopes.push(sealed);
    return {id: entry.id, version: revision, cid: sealed.cid};
  };
  const request = envelope('request', 'request_schema', {type: 'object', nullable: false,
    additional_properties: false, fields: {}});
  const schema = envelope('row', 'carrier_schema', {type: 'object', nullable: false,
    additional_properties: false, fields});
  const facts = envelope('facts', 'carrier_facts', {});
  const policy = envelope('policy', 'data_policy', {version: 'actql-source-data-policy/0.1',
    source_ref: sourceRef, classification: 'unknown'});
  const pushdown = envelope('pushdown', 'pushdown', {version: 'actql-source-view-pushdown/0.1',
    carrier: 'relation', operations: ['filter', 'projection']});
  const sourceBody = {schema: 'actql.source_view/0.1', connector_id: connectorId,
    connector_version: revision, resource_kind: 'sobject', view_id: 'records', view_version: revision,
    acquisition: {kind: 'scan', authority: 'read_content', request_schema: request,
      modes: [{mode: 'snapshot', bounded: true}], default_mode: 'snapshot'},
    request_processing: {mutates_business_state: false},
    output: {carrier: 'relation', schema, facts, data_policy: policy},
    pushdown: {contract: pushdown, operations: ['filter', 'projection']},
    resource_identity: {version: 'actql.resource_identity/0.1', provider_namespace: 'salesforce',
      resource_kind: 'sobject', provider_id_field: 'Id', output_field: 'Id', boundary_topology: 'connector_connection'}};
  const source = {...sourceBody, contract_cid: cid(sourceBody)};
  envelopes.sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
  const catalogBody = {schema: 'actql.connector_catalog/0.1', connector_id: connectorId,
    connector_version: revision, source_views: [source], commands: [], contracts: envelopes};
  const catalog = {...catalogBody, catalog_cid: cid(catalogBody)};
  assert.equal(publication.catalog_cid, catalog.catalog_cid,
    'The published mock Catalog must match the independently authored declaration');
  assert.equal(publication.connector_id, connectorId);
  assert.deepEqual(publication.resources, ['Test_Record__c']);
  const {evidence_bundle_cid: _, ...base} = JSON.parse(await readFile(new URL(
    'spec/local-check-environment.json', runtimeRootUrl), 'utf8'));
  void _;
  const evidenceContractCid = cid(JSON.parse(await readFile(new URL(
    'spec/contracts/actql-query-process-evidence.json', runtimeRootUrl), 'utf8')));
  const environment = {...base, source_views: [source], contract_registry: [...envelopes].sort((a, b) =>
    cid(a) < cid(b) ? -1 : cid(a) > cid(b) ? 1 : 0),
    connector_catalogs: [catalog], connector_manifest: {version: 'actql-connectors/0.1',
      connectors: [{connector: 'salesforce', connector_id: connectorId, connector_version: revision}]},
    schema_snapshots: [{carrier_schema_contract_cid: schema.cid, data_classification: 'unknown',
      output_carrier: 'relation', read_mode: 'snapshot', source_contract_cid: source.contract_cid,
      source_data_policy_cid: policy.cid, source_ref: sourceRef, source_view_contract_cid: source.contract_cid}],
    connector_capabilities: [{capability_contract_cids: [evidenceContractCid], read_mode: 'snapshot',
      source_contract_cid: source.contract_cid, source_ref: sourceRef, source_view_contract_cid: source.contract_cid}]};
  return {environment, source, sourceRef, fields, catalogCid: catalog.catalog_cid};
}

// This current authored Host has separate observation and Run permissions.
// Keep both exact purposes in the synthetic historical snapshot's real CID.
function assertSyntheticSalesforceHostAccount(account) {
  assert.deepEqual(account.entries.map(entry => entry.entry_id), ['host-results', 'host-run']);
  assert.equal(account.entries.every(entry => entry.outcome === 'allow'), true);
  assert.deepEqual(account.entries[0].operation, {any_of: ['read']});
  assert.deepEqual(account.entries[1].operation, {any_of: ['write']});
}

export async function writeSyntheticHistoricalHeldSalesforce({directory, document,
  requestId, authorization, sourceProfile, siteProfile, runtimeRootUrl,
  expressionContractUrl, now = Date.now()}) {
  const program = JSON.parse(document);
  assert.deepEqual(program, {version: 'actql/0.1', id: 'salesforce-read', stages: [
    {id: 'acquire', inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
      steps: [{filter: "Name <> 'record-2'", as: 'filtered'},
        {select: ['Id', 'Name', 'External_Key__c'], as: 'captured'}],
      results: {r: {from: 'captured', fields: ['Id', 'Name', 'External_Key__c']}}},
    {id: 'compute', inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
      steps: [{select: ['External_Key__c', 'Name'], as: 'out'}],
      results: {r: {from: 'out', fields: ['External_Key__c', 'Name']}}}],
    results: {records: {from: {stage: 'compute', result: 'r'}}}});
  assert.equal(sourceProfile.version, 'actql-installed-salesforce-source/0.1');
  assert.equal(siteProfile.version, 'actql-installed-salesforce-site/0.1');
  assert.equal(siteProfile.orgId, '00D000000000001EAA');
  assert.equal(new URL(siteProfile.instanceOrigin).hostname, '127.0.0.1');
  assert.equal(siteProfile.siteKey, 'salesforce-site');
  assert.equal(siteProfile.siteGeneration, 1);
  assert.equal(siteProfile.connectionRevision, 'connection-revision-a');
  const publication = JSON.parse(await readFile(sourceProfile.publicationPath, 'utf8'));
  const declaration = await declaredSource(runtimeRootUrl, publication);
  const root = resolve(directory), principalId = userInfo().username;
  const namespaceId = 'local', siteKey = 'actql-remote-host', realizationKey = 'salesforce-acquired';
  const account = JSON.parse(authorization.accountConfiguration);
  assertSyntheticSalesforceHostAccount(account);
  const sourceAccount = JSON.parse(sourceProfile.accountConfigurationWire);
  assert.equal(sourceAccount.entries.length, 1);
  assert.equal(sourceAccount.entries[0].outcome, 'delegate');
  const sourceConfigurationCid = cid(sourceAccount), configurationCid = cid(account);
  const sourceContextCid = hash(JSON.stringify({version: 'actql-installed-salesforce-context/0.1', root, principalId}));
  const authorityScopeCid = hash(JSON.stringify({version: 'actql-local-owner-scope/0.1', root, principalId}));
  const logicalRequestScopeCid = cid({authority_scope_cid: authorityScopeCid,
    caller_request_id: requestId, version: 'actql-logical-request/0.1'});
  const expressionCid = cid(JSON.parse(await readFile(expressionContractUrl, 'utf8')));
  const filter = {neq: [{field: 'Name'}, {literal: 'record-2'}]};
  const stages = program.stages.map((stage, index) => {
    const local = {version: 'actql-stage-semantics/0.1', binding_references: [], bindings: {},
      parameter_references: [], parameters: {}, expression_contract_cid: expressionCid,
      local_body: {effects: {}, inputs: stage.inputs, results: stage.results,
        steps: index === 0 ? [{...stage.steps[0], filter}, stage.steps[1]] : stage.steps}};
    return {id: stage.id, after: index === 0 ? 'initial' : 'completed',
      imports: index === 0 ? {} : stage.inputs, stage_semantics_cid: cid(local)};
  });
  const semantics = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
    expression_contract_cid: expressionCid, parameters: {}, parameter_references: [], bindings: {}, binding_references: [],
    program_template: {stages, exports: program.results}};
  const programDefinitionCid = cid({version: 'actql-program-definition/0.1', id: program.id, program_semantics_cid: cid(semantics)});
  const parameters = null;
  const parameterValuesCid = 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52';
  const callerInputIntentCid = cid({selection: 'none', version: 'actql-caller-input-intent/0.1'});
  const intentFingerprintCid = cid({caller_input_intent_cid: callerInputIntentCid,
    parameter_values_cid: parameterValuesCid, program_definition_cid: programDefinitionCid,
    version: 'actql-logical-request-intent/0.1'});
  const prepareAttemptId = `prepare-${cid({authority_scope_cid: authorityScopeCid,
    namespace_id: namespaceId, request_id: requestId}).slice(7, 47)}`;
  const {source: sourceDeclaration, sourceRef, fields: inputSchema, catalogCid} = declaration;
  const sourceContractCid = sourceDeclaration.contract_cid;
  const outputSchema = inputSchema;
  const requirement = {version: 'actql-query-acquisition/0.1',
    filter: {expression_cid: cid(filter), occurrence: '/steps/0/filter'},
    input_contract_cid: cid(inputSchema), logical_guards: {max_rows: 100, max_value_bytes: 10000},
    output_contract_cid: cid(outputSchema), owner: {input: 'remote', program_source_cid: programDefinitionCid, stage: 'acquire'},
    parameter_values_cid: parameterValuesCid, request: {},
    select: {fields: ['Id', 'Name', 'External_Key__c'].map(name => ({input: name, output: name})), occurrence: '/steps/1/select'},
    source_contract_cid: sourceContractCid, source_order_cid: null, source_ref: sourceRef,
    source_validation: {fields: ['External_Key__c', 'Id', 'Name'], scope: 'selected_scan'}};
  const checkedSource = {requirementCid: cid(requirement), sourceRef, sourceContractCid,
    carrierSchemaContractCid: sourceDeclaration.output.schema.cid,
    sourceDataPolicyCid: sourceDeclaration.output.data_policy.cid, dataClassification: 'unknown',
    sourceViewContractCid: sourceContractCid, inputContractCid: cid(inputSchema), outputContractCid: cid(outputSchema)};
  const acquisition = {checkedSource, readTuple: {connection: `salesforce:${siteProfile.orgId}`,
    resource: 'Test_Record__c', operation: 'read'}, physicalBinding: {
    version: 'actql-installed-salesforce-target/0.1', org_id: siteProfile.orgId,
    instance_origin: siteProfile.instanceOrigin, site_key: 'salesforce-site', site_generation: 1,
    connection_revision: 'connection-revision-a', catalog_cid: catalogCid,
    resource: 'Test_Record__c', fields: ['Id', 'Name', 'External_Key__c']}};
  const captured = {version: 'actql-remote-captured-submission/0.1', requestId, principalId,
    connection: {mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []},
    kind: 'aql', input: {format: 'json', text: document}, parameters, resultNames: ['records'], acquisition};
  const subject = {version: 'actql-remote-run-acceptance-request/0.1',
    authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
    logical_request_scope_cid: logicalRequestScopeCid, intent_fingerprint_cid: intentFingerprintCid,
    site_key: siteKey, realization_key: realizationKey};
  const request = {version: 'actql-remote-invocation-request/0.1', subject, subject_cid: cid(subject)};
  const requestCid = cid(request);
  const invocation = {version: 'actql-remote-acquisition-intent/0.1', request_cid: requestCid,
    captured_submission_cid: dataCid(captured), checked_source: checkedSource,
    read_tuple: acquisition.readTuple, physical_binding: acquisition.physicalBinding};
  const invocationCid = cid(invocation);
  const createdAt = new Date(now).toISOString(), expiresAt = new Date(now +
    (authorization.checkpointTtlMs ?? 86400000)).toISOString();
  const reviewBody = {version: 'actql-run-review-projection/0.1', prepared_invocation_cid: invocationCid,
    execution_context_cid: sourceContextCid,
    host_policy_cid: sourceConfigurationCid,
    approval_claims: ['invocation_scope_approved'],
    authoring_context_cid: cid({principal: principalId, request_id: requestId}),
    redaction_policy_cid: cid({version: 'actql-remote-review-redaction/0.1', redacted: []}),
    sensitivity: 'restricted', retention_class: 'approval-evidence', encryption_required: true,
    expires_at: expiresAt, displayed_scope: {request_id: requestId, kind: captured.kind, format: 'json',
      document, parameters, source: checkedSource, read_tuple: acquisition.readTuple,
      physical_binding: acquisition.physicalBinding},
    displayed_authoring_context: [{principal: principalId}]};
  const review = {...reviewBody, review_projection_cid: dataCid(reviewBody)};
  const reviewWire = wire(review), reviewCid = hash(reviewWire);
  const state = join(root, 'checkpoints');
  const key = await readFile(join(state, 'private-evidence.key'));
  const keyId = hash(key);
  const reference = (name, original) => {
    const semanticCid = hash(original);
    return {name, semantic_cid: semanticCid, holding_cid: hash(JSON.stringify({
      version: 'actql-local-continuation-holding/0.1', prepare_attempt_id: prepareAttemptId,
      name, semantic_cid: semanticCid})), key_id: keyId};
  };
  const items = [{name: 'captured_input', wire: wire(captured)},
    {name: 'invocation_request', wire: identityWire(request)},
    {name: 'prepared_invocation', wire: identityWire(invocation)},
    {name: 'review_projection', wire: reviewWire}];
  const decisionSubject = {account_id: sourceAccount.account_id, configuration_cid: sourceConfigurationCid,
    entry_id: sourceAccount.entries[0].entry_id, principal: principalId,
    ...acquisition.readTuple, boundary: 'acquisition', subject_cid: invocationCid, context_cid: sourceContextCid};
  const continuation = {version: 'actql-remote-continuation/0.1', prepare_attempt_id: prepareAttemptId,
    boundary: 'acquisition', invocation_cid: invocationCid, request_subject_cid: cid(subject),
    request_id: requestId, delegated_subject: decisionSubject,
    earlier_approvals: [],
    answering_authorities: authorization.answeringAuthorities ?? authorization.reviewers.map(item => item.reviewerId),
    evidence: items.map(item => reference(item.name, item.wire))};
  items.push({name: 'continuation_record', wire: identityWire(continuation)});
  const checkpointBody = {version: 'actql-execution-checkpoint/0.1', phase: 'preflight', kind: 'read_access',
    requirements: ['invocation_scope_approved'], reason_code: 'delegated_decision_deferred',
    checkpoint_id: `${prepareAttemptId}-acquisition`, continuation_state_cid: cid(continuation),
    subject: {kind: 'prepare_attempt', prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
    required_artifact: {artifact_type: 'read_scope', artifact_cid: invocationCid},
    review_projection_cid: reviewCid, human_summary: `Run request ${requestId} on ${siteKey}`,
    created_at: createdAt, expires_at: expiresAt};
  const checkpointCid = cid(checkpointBody);
  const checkpointWire = identityWire({...checkpointBody, checkpoint_cid: checkpointCid});
  const environmentBody = declaration.environment;
  // This is the selected installation's declared environment input, not a
  // returned acceptance result; the original binding is independently hashed.
  environmentBody.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...environmentBody.host_policy_profile.capacity};
  const binding = {authorization_context_cid: cid({principal: principalId,
    account_id: account.account_id, configuration_cid: configurationCid, source_configuration_cid: sourceConfigurationCid}),
  environment_binding_cid: cid({version: 'actql-remote-run-acceptance-environment/0.1', site_key: siteKey,
    realization_key: realizationKey, environment_cid: cid(environmentBody), authority_scope_cid: authorityScopeCid})};

  // The public initializer has already established an empty owned root. All
  // its handles must be closed before these synthetic original bytes exist.
  const requests = new DatabaseSync(join(root, 'requests/client-requests.sqlite3'));
  try {
    assert.equal(requests.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
    assert.equal(requests.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 0);
  } finally {requests.close();}
  const database = new DatabaseSync(join(state, 'journal/checkpoint-journal.sqlite3'),
    {enableForeignKeyConstraints: true});
  try {
    assert.equal(database.prepare("SELECT value FROM journal_metadata WHERE key = 'schema_version'").get().value,
      'actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1;model-current-cut-link=1;model-current-cut-invalidation=1');
    for (const table of ['runs', 'resolutions', 'resume_intents', 'resume_admissions', 'preparations', 'checkpoints']) {
      assert.equal(database.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
    }
    assert.deepEqual(database.prepare("SELECT status FROM preparations WHERE status != 'waiting_checkpoint'").all(), []);
    database.exec('BEGIN IMMEDIATE');
    database.prepare(`INSERT INTO preparations (prepare_attempt_id, status, version,
      updated_at, declared_results_json, checkpoint_cid) VALUES (?, 'waiting_checkpoint', 1, ?, ?, ?)`)
      .run(prepareAttemptId, createdAt, JSON.stringify(captured.resultNames), checkpointCid);
    database.prepare(`INSERT INTO checkpoints (checkpoint_cid, checkpoint_id, run_id,
      prepare_attempt_id, checkpoint_wire, expires_at, authorities_json, binding_json,
      decision_subject_cid, requested_claims_json, configuration_cid, closure, persisted_at)
      VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, '[]', ?, 'open', ?)`)
      .run(checkpointCid, checkpointBody.checkpoint_id, prepareAttemptId, checkpointWire, expiresAt,
        JSON.stringify(authorization.reviewers.map(item => ({key_id: item.keyId, reviewer_id: item.reviewerId}))),
        JSON.stringify(binding), cid(decisionSubject), sourceConfigurationCid, createdAt);
    database.exec('COMMIT');
  } finally {database.close();}

  // Reuse only physical encryption/holding storage for the authored bytes.
  // No authorization, Checkpoint sealer, acceptRun, or resume operation runs.
  const {openContinuationEvidence} = await import(new URL('adapters/host-node/local-continuation-evidence.mjs', runtimeRootUrl));
  const {runtimeCore} = await import(new URL('adapters/host-common/runtime-core.mjs', runtimeRootUrl));
  const moon = await import(new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', runtimeRootUrl));
  const evidence = openContinuationEvidence({stateDirectory: state, key, keyId,
    contractControl: runtimeCore(moon).publicationControl,
    preparation: () => undefined, isTerminalRunOutcome: () => false});
  try {
    for (const item of items) assert.deepEqual(evidence.reference(prepareAttemptId, item.name, item.wire),
      reference(item.name, item.wire));
    assert.deepEqual(await evidence.hold(prepareAttemptId, requestCid, items), items.map(item => hash(item.wire)));
  } finally {await evidence.close(); key.fill(0);}
  await mkdir(join(state, 'held'), {recursive: true});
  await writeFile(join(state, 'held', `${prepareAttemptId}.json`), JSON.stringify({
    version: 'actql-remote-held-request/0.1', prepare_attempt_id: prepareAttemptId, request_id: requestId}),
  {flag: 'wx', mode: 0o600});
  return Object.freeze({kind: 'synthetic_historical_format', requestId, prepareAttemptId,
    authorityScopeCid, logicalRequestScopeCid, intentFingerprintCid, programDefinitionCid,
    parameterValuesCid, callerInputIntentCid, checkpointCid, reviewCid, reviewWire,
    originalHashes: Object.fromEntries(items.map(item => [item.name, hash(item.wire)]))});
}
