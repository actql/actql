// Synthetic historical-format four-stage DuckDB originals for current public recovery tests.
// This is not evidence that an earlier public Host produced these records.
// The fixture writes no Run, resolution, resume claim, admission or approval.
// A newly opened installed Host must admit every original through its normal
// root, journal, encrypted-evidence and current-authorization owners.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';

// Independent finite fixture encoder. No product sealer or acceptance output
// supplies the expected identities. The selected inputs use canonical names;
// document text is deliberately retained byte-for-byte as a JSON string.
const wire = value => value === null || typeof value !== 'object'
  ? JSON.stringify(value) : Array.isArray(value)
    ? `[${value.map(wire).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${wire(value[key])}`).join(',')}}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const normalized = value => typeof value === 'string' ? value.normalize('NFC')
  : Array.isArray(value) ? value.map(normalized) : value && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).map(([key, child]) => [key.normalize('NFC'), normalized(child)])) : value;
const identityWire = value => wire(normalized(value));
const cid = value => hash(identityWire(value));
const dataCid = value => hash(wire(value));

// Meaning authored independently from the fixed four-stage example. The
// Program Definition uses the independently authored finite preimage, never a
// runtime compiler or an executed Result. Parameter and query preimages are
// independently authored below from this exact source meaning.
export async function writeSyntheticHistoricalHeldQuery({directory, document,
  requestId, authorization, sourceProfile, runtimeRootUrl, now = Date.now(), mode = 'remote', runHeld, effectEnvironmentWire, modelEnvironmentWire,
  hostCapacityPolicy,
  expressionContractUrl = new URL('spec/contracts/actql-expressions.json', runtimeRootUrl)}) {
  const program = JSON.parse(document);
  const model = modelEnvironmentWire !== undefined;
  assert.ok(!model || effectEnvironmentWire === undefined);
  const expectedProgram = model
    ? {version: 'actql/0.1', id: 'public-model-resume', stages: [{id: 'main',
      inputs: {source: {connector: 'crm/main', resource: 'r'}}, steps: [
        {filter: 'id = id'}, {select: ['id', 'amount']}, {assert_rows: {unique_by: ['id']}},
        {infer: {contract: 'model-task:packed-risk.v1', key: 'id', input: {text: {field: 'amount'}},
          on_non_success: 'outcomes'}, as: 'captured'}],
      results: {captured: {from: 'captured', fields: ['id', 'outcome', 'value']}}}],
      results: {answer: {from: {stage: 'main', result: 'captured'}}}}
    : {version: 'actql/0.1', id: 'physical-example', params: {minimum: {type: 'number', nullable: false}},
      stages: [
        {id: 'acquire', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
          steps: [{filter: 'id > $minimum', as: 'filtered'}, {select: ['id'], as: 'captured'}],
          results: {r: {from: 'captured', fields: ['id']}}},
        ...[['compute_a', 'acquire', 'id > 2'], ['compute_b', 'acquire', 'id > 0'],
          ['compute_c', 'compute_a', 'id < 9']].map(([id, producer, filter]) => ({id,
          inputs: {x: {result: {stage: producer, result: 'r'}}},
          steps: [{filter}, {select: ['id'], as: 'out'}], results: {r: {from: 'out', fields: ['id']}}})),
      ], results: {b: {from: {stage: 'compute_b', result: 'r'}}, c: {from: {stage: 'compute_c', result: 'r'}}}};
  assert.deepEqual(program, expectedProgram);
  assert.ok(mode === 'local' || mode === 'remote');
  assert.equal(typeof requestId, 'string');
  assert.equal(sourceProfile.version, 'actql-installed-duckdb-source/0.1');
  assert.equal(sourceProfile.sourceRef, 'connector://crm/main/r#v');
  const root = resolve(directory);
  const principalId = userInfo().username;
  const namespaceId = 'local', siteKey = 'actql-remote-host', realizationKey = 'duckdb-acquired';
  assert.equal(authorization.siteKey ?? siteKey, siteKey);
  const account = JSON.parse(authorization.accountConfiguration);
  const writeEntries = account.entries.filter(entry => entry.operation.any_of?.includes('write'));
  assert.equal(writeEntries.length, 1);
  const [runEntry] = writeEntries;
  assert.ok(['allow', 'delegate'].includes(runEntry.outcome));
  const runHold = runHeld ?? runEntry.outcome === 'delegate';
  const sourceAccount = JSON.parse(sourceProfile.accountConfigurationWire);
  assert.equal(sourceAccount.entries.length, 1);
  if (!runHold) assert.equal(sourceAccount.entries[0].outcome, 'delegate');
  const sourceConfigurationCid = cid(sourceAccount);
  const sourceContextCid = hash(JSON.stringify({version: 'actql-installed-source-context/0.1',
    root, principalId}));
  const configurationCid = cid(account);
  const contextCid = cid({host: 'actql-local-host', principal: principalId, account_id: account.account_id});
  // This existing Host identity uses its original ordered JSON preimage, not
  // sorted artifact encoding or a realpath rewrite of the selected root.
  // Its effective policy also includes the existing graph-construction
  // defaults already authored for this fixture's environment below.
  const effectiveHostCapacityPolicy = hostCapacityPolicy === undefined ? undefined : {
    max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000, ...hostCapacityPolicy};
  const authorityScopeCid = hash(JSON.stringify({version: 'actql-local-owner-scope/0.1', root, principalId,
    ...(effectiveHostCapacityPolicy === undefined ? {} : {hostCapacityPolicyCid: cid(effectiveHostCapacityPolicy)})}));
  const logicalRequestScopeCid = cid({authority_scope_cid: authorityScopeCid,
    caller_request_id: requestId, version: 'actql-logical-request/0.1'});
  let programDefinitionCid;
  if (model) {
    const expressionCid = cid(JSON.parse(await readFile(new URL(expressionContractUrl), 'utf8')));
    const stage = program.stages[0];
    const local = {version: 'actql-stage-semantics/0.1', binding_references: [], bindings: {},
      parameter_references: [], parameters: {}, expression_contract_cid: expressionCid,
      local_body: {effects: {}, inputs: stage.inputs, results: stage.results,
        steps: [{filter: {eq: [{field: 'id'}, {field: 'id'}]}}, ...stage.steps.slice(1)]}};
    const semantics = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
      expression_contract_cid: expressionCid, parameters: {}, parameter_references: [], bindings: {}, binding_references: [],
      program_template: {stages: [{id: 'main', after: 'initial', imports: {}, stage_semantics_cid: cid(local)}],
        exports: program.results}};
    programDefinitionCid = cid({version: 'actql-program-definition/0.1', id: program.id, program_semantics_cid: cid(semantics)});
  } else {
    // The same finite normative Program preimage as tasksDependencyOracle,
    // kept portable for a package-external consumer. No runtime issuer runs.
    const expressionCid = cid(JSON.parse(await readFile(new URL(expressionContractUrl), 'utf8')));
    const parameterReferences = [{name: 'minimum', path: '/steps/0/filter/gt/1', type: program.params.minimum}];
    const stages = program.stages.map((stage, index) => {
      const expression = {[index === 3 ? 'lt' : 'gt']: [{field: 'id'},
        index === 0 ? {$param: 'minimum'} : {literal: [null, 2, 0, 9][index]}]};
      const local = {version: 'actql-stage-semantics/0.1', binding_references: [], bindings: {},
        expression_contract_cid: expressionCid, parameters: index === 0 ? program.params : {},
        parameter_references: index === 0 ? parameterReferences : [],
        local_body: {effects: {}, inputs: stage.inputs, results: stage.results,
          steps: [{...stage.steps[0], filter: expression}, stage.steps[1]]}};
      return {id: stage.id, after: index === 0 ? 'initial' : 'completed',
        imports: index === 0 ? {} : stage.inputs, stage_semantics_cid: cid(local)};
    });
    const semantics = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
      expression_contract_cid: expressionCid, parameters: program.params, bindings: {}, binding_references: [],
      parameter_references: parameterReferences.map(value => ({...value, path: `/stages/0${value.path}`})),
      program_template: {stages, exports: program.results}};
    programDefinitionCid = cid({version: 'actql-program-definition/0.1', id: program.id, program_semantics_cid: cid(semantics)});
  }
  const parameters = model ? null : {minimum: 1};
  const parameterValuesCid = cid({values: parameters ?? {}, version: 'actql-parameter-values/0.1'});
  assert.equal(parameterValuesCid, model
    ? 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52'
    : 'sha256:4216bc0d81bf191fa09af2befe195403d6a39179e11dd6abc5f137ca2fd4d2f0');
  const callerInputIntentCid = cid({selection: 'none', version: 'actql-caller-input-intent/0.1'});
  const intentFingerprintCid = cid({caller_input_intent_cid: callerInputIntentCid,
    parameter_values_cid: parameterValuesCid, program_definition_cid: programDefinitionCid,
    version: 'actql-logical-request-intent/0.1'});
  const prepareAttemptId = `prepare-${cid({authority_scope_cid: authorityScopeCid,
    namespace_id: namespaceId, request_id: requestId}).slice(7, 47)}`;
  const sourceDeclaration = JSON.parse(sourceProfile.checkEnvironmentWire).source_views[0];
  const {contract_cid: sourceContractCid, ...sourceBody} = sourceDeclaration;
  assert.equal(cid(sourceBody), sourceContractCid);
  if (!model) assert.equal(sourceContractCid, 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3');
  const sourceRef = 'connector://crm/main/r#v';
  const inputSchema = {amount: {nullable: true, type: model ? 'string' : 'number'}, id: {nullable: false, type: 'number'}};
  const outputSchema = model ? inputSchema : {id: {nullable: false, type: 'number'}};
  const requirement = {version: 'actql-query-acquisition/0.1',
    filter: {expression_cid: cid(model ? {eq: [{field: 'id'}, {field: 'id'}]} : {gt: [{field: 'id'}, {$param: 'minimum'}]}), occurrence: '/steps/0/filter'},
    input_contract_cid: cid(inputSchema), logical_guards: {max_rows: 100, max_value_bytes: 10000},
    output_contract_cid: cid(outputSchema),
    owner: {input: model ? 'source' : 'remote', program_source_cid: programDefinitionCid, stage: model ? 'main' : 'acquire'},
    parameter_values_cid: parameterValuesCid, request: {},
    select: {fields: (model ? ['id', 'amount'] : ['id']).map(name => ({input: name, output: name})), occurrence: '/steps/1/select'},
    source_contract_cid: sourceContractCid, source_order_cid: null, source_ref: sourceRef,
    source_validation: {fields: ['amount', 'id'], scope: 'selected_scan'}};
  const checkedSource = {requirementCid: cid(requirement), sourceRef, sourceContractCid,
    carrierSchemaContractCid: sourceDeclaration.output.schema.cid,
    sourceDataPolicyCid: sourceDeclaration.output.data_policy.cid,
    dataClassification: model ? 'public' : 'unknown', sourceViewContractCid: sourceContractCid,
    inputContractCid: cid(inputSchema), outputContractCid: cid(outputSchema)};
  const {database: sourceDatabase, schema, table} = sourceProfile;
  const acquisition = {checkedSource,
    readTuple: {connection: 'local-database', resource: sourceDatabase, operation: 'read'},
    physicalBinding: {version: 'actql-installed-duckdb-target/0.1', database: sourceDatabase, schema, table,
      utf8_hex: Object.fromEntries(Object.entries({database: sourceDatabase, schema, table})
        .map(([name, value]) => [name, Buffer.from(value, 'utf8').toString('hex')]))}};
  const captured = {version: 'actql-remote-captured-submission/0.1', requestId,
    principalId, connection: {mode, owner: mode, durability: 'durable', consentRefs: [], runners: []},
    kind: model ? 'program' : 'aql', input: model ? program : {format: 'json', text: document}, parameters,
    resultNames: model ? ['answer'] : ['b', 'c'], acquisition};
  const subject = {version: 'actql-remote-run-acceptance-request/0.1',
    authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
    logical_request_scope_cid: logicalRequestScopeCid, intent_fingerprint_cid: intentFingerprintCid,
    site_key: siteKey, realization_key: realizationKey};
  const request = {version: 'actql-remote-invocation-request/0.1', subject, subject_cid: cid(subject)};
  const requestCid = cid(request);
  const invocation = runHold
    ? {version: 'actql-remote-prepared-invocation/0.1', request_cid: requestCid,
      captured_submission_cid: dataCid(captured), site_key: siteKey, realization_key: realizationKey}
    : {version: 'actql-remote-acquisition-intent/0.1', request_cid: requestCid,
      captured_submission_cid: dataCid(captured), checked_source: checkedSource,
      read_tuple: acquisition.readTuple, physical_binding: acquisition.physicalBinding};
  const invocationCid = cid(invocation);
  const createdAt = new Date(now).toISOString(), expiresAt = new Date(now +
    (authorization.checkpointTtlMs ?? 86400000)).toISOString();
  const reviewBody = {version: 'actql-run-review-projection/0.1', prepared_invocation_cid: invocationCid,
    execution_context_cid: runHold ? contextCid : sourceContextCid,
    host_policy_cid: runHold ? configurationCid : sourceConfigurationCid,
    approval_claims: ['invocation_scope_approved'],
    authoring_context_cid: cid({principal: principalId, request_id: requestId}),
    redaction_policy_cid: cid({version: 'actql-remote-review-redaction/0.1', redacted: []}),
    sensitivity: 'restricted', retention_class: 'approval-evidence', encryption_required: true,
    expires_at: expiresAt, displayed_scope: {request_id: requestId, kind: captured.kind, format: 'json',
      document: model ? program : document, parameters, ...(runHold
        ? {site_key: siteKey, realization_key: realizationKey, operation: 'write'}
        : {source: checkedSource, read_tuple: acquisition.readTuple, physical_binding: acquisition.physicalBinding})},
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
  const decisionSubject = runHold
    ? {account_id: account.account_id, configuration_cid: configurationCid,
      entry_id: runEntry.entry_id, principal: principalId, connection: siteKey,
      resource: realizationKey, operation: 'write', boundary: 'preparation', subject_cid: cid(subject),
      context_cid: contextCid}
    : {account_id: sourceAccount.account_id, configuration_cid: sourceConfigurationCid,
      entry_id: sourceAccount.entries[0].entry_id, principal: principalId,
      ...acquisition.readTuple, boundary: 'acquisition', subject_cid: invocationCid, context_cid: sourceContextCid};
  const continuation = {version: 'actql-remote-continuation/0.1', prepare_attempt_id: prepareAttemptId,
    boundary: runHold ? 'preparation' : 'acquisition', invocation_cid: invocationCid, request_subject_cid: cid(subject),
    request_id: requestId, delegated_subject: decisionSubject,
    ...(runHold ? {} : {earlier_approvals: []}),
    answering_authorities: authorization.answeringAuthorities ?? authorization.reviewers.map(item => item.reviewerId),
    evidence: items.map(item => reference(item.name, item.wire))};
  items.push({name: 'continuation_record', wire: identityWire(continuation)});
  const checkpointBody = {version: 'actql-execution-checkpoint/0.1', phase: 'preflight', kind: runHold ? 'run_scope' : 'read_access',
    requirements: ['invocation_scope_approved'], reason_code: 'delegated_decision_deferred',
    checkpoint_id: `${prepareAttemptId}-${runHold ? 'preparation' : 'acquisition'}`, continuation_state_cid: cid(continuation),
    subject: {kind: 'prepare_attempt', prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
    required_artifact: {artifact_type: runHold ? 'prepared_invocation' : 'read_scope', artifact_cid: invocationCid},
    review_projection_cid: reviewCid, human_summary: `Run request ${requestId} on ${siteKey}`,
    created_at: createdAt, expires_at: expiresAt};
  const checkpointCid = cid(checkpointBody);
  const checkpointWire = identityWire({...checkpointBody, checkpoint_cid: checkpointCid});
  const {evidence_bundle_cid: _ignored, ...sourceEnvironment} = JSON.parse(sourceProfile.checkEnvironmentWire);
  void _ignored;
  let environmentBody = sourceEnvironment;
  const additionalEnvironmentWire = modelEnvironmentWire ?? effectEnvironmentWire;
  if (additionalEnvironmentWire !== undefined) {
    const {evidence_bundle_cid: _effectIgnored, ...effectEnvironment} = JSON.parse(additionalEnvironmentWire);
    void _effectIgnored;
    assert.deepEqual(effectEnvironment.host_policy_profile, sourceEnvironment.host_policy_profile);
    assert.equal(effectEnvironment.version, sourceEnvironment.version);
    const sections = ['command_contracts', 'connector_capabilities', 'connector_catalogs',
      'contract_registry', 'mapping_contracts', 'model_task_contracts', 'schema_snapshots', 'source_views'];
    const merge = (left, right) => [...new Map([...left, ...right].map(value => [identityWire(value), value])).values()]
      .sort((left, right) => cid(left) < cid(right) ? -1 : cid(left) > cid(right) ? 1 : 0);
    environmentBody = {...sourceEnvironment};
    for (const section of sections) environmentBody[section] = merge(sourceEnvironment[section], effectEnvironment[section]);
    if (sourceEnvironment.connector_manifest || effectEnvironment.connector_manifest) {
      const left = sourceEnvironment.connector_manifest, right = effectEnvironment.connector_manifest;
      if (left && right) assert.equal(left.version, right.version);
      environmentBody.connector_manifest = {version: (left ?? right).version,
        connectors: merge(left?.connectors ?? [], right?.connectors ?? [])};
    }
  }
  // This is the selected installation's declared environment input, not a
  // returned acceptance result; the original binding is independently hashed.
  environmentBody.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...environmentBody.host_policy_profile.capacity};
  if (hostCapacityPolicy !== undefined) {
    assert.deepEqual(environmentBody.host_policy_profile.capacity, effectiveHostCapacityPolicy,
      'The authored historical scope uses the SAME explicit installed Host policy');
  }
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
        JSON.stringify(binding), cid(decisionSubject), runHold ? configurationCid : sourceConfigurationCid, createdAt);
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
