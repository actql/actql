// Synthetic historical-format exact typed-value originals for current public recovery tests.
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
const cid = value => hash(wire(value));

const typedValuesProgram = {
  version: 'actql/0.1', id: 'held-exact-values', params: {suffix: {type: 'string'}},
  stages: [{id: 's', inputs: {}, steps: [
    {as: 'seed', values: {schema: {id: {type: 'number', nullable: false}, label: {type: 'string', nullable: false}},
      rows: [{id: 1, label: 'e\u0301'}, {id: 2, label: 'é'}, {id: 3, label: 'a\rb'},
        {id: 4, label: 'a\nb'}, {id: 5, label: 'a\r\nb'}]}},
    {as: 'out', derive: {supplied: '$suffix', nested: {typed_literal: {type: 'json',
      value: '{"outer":[{"é":"é","é":"é","line":"a\\r\\nb"}]}'}}}},
  ], results: {out: {from: 'out', fields: ['id', 'label', 'supplied', 'nested']}}}],
  results: {answer: {from: {stage: 's', result: 'out'}}},
};
const typedValuesParameters = {suffix: 'e\u0301\r\n'};

export async function writeSyntheticHistoricalHeldTypedValues({directory, document,
  parameters, requestId, authorization, runtimeRootUrl, now = Date.now(), mode = 'local',
  expressionContractUrl = new URL('spec/contracts/actql-expressions.json', runtimeRootUrl)}) {
  const program = JSON.parse(document);
  assert.deepEqual(program, typedValuesProgram,
    'This independent identity vector supports only the fixed exact typed-value original');
  assert.deepEqual(parameters, typedValuesParameters);
  assert.ok(mode === 'local' || mode === 'remote');
  assert.equal(typeof requestId, 'string');
  const root = resolve(directory);
  const principalId = userInfo().username;
  const namespaceId = 'local', siteKey = 'actql-remote-host', realizationKey = 'source-free-values';
  assert.equal(authorization.siteKey ?? siteKey, siteKey);
  const account = JSON.parse(authorization.accountConfiguration);
  const delegates = account.entries.filter(entry => entry.entry_id === 'acceptance');
  assert.equal(delegates.length, 1);
  assert.equal(delegates[0].outcome, 'delegate');
  assert.deepEqual(delegates[0].operation, {any_of: ['write']});
  const configurationCid = cid(account);
  const contextCid = cid({host: 'actql-local-host', principal: principalId, account_id: account.account_id});
  // This existing Host identity uses its original ordered JSON preimage, not
  // sorted artifact encoding or a realpath rewrite of the selected root.
  const authorityScopeCid = hash(JSON.stringify({version: 'actql-local-owner-scope/0.1', root, principalId}));
  const logicalRequestScopeCid = cid({authority_scope_cid: authorityScopeCid,
    caller_request_id: requestId, version: 'actql-logical-request/0.1'});
  // Independently authored finite semantic preimages for this exact typed-value input.
  // Contract pins come from the selected source's normative input, never
  // compiler output. Packed callers carry its exact bytes with the fixture.
  const expressionCid = cid(JSON.parse(await readFile(new URL(expressionContractUrl), 'utf8')));
  const stage = program.stages[0];
  const parameterReferences = [{name: 'suffix', path: '/steps/1/derive/supplied',
    type: {type: 'string'}}];
  const stageSemantics = {version: 'actql-stage-semantics/0.1',
    binding_references: [], bindings: {}, parameter_references: parameterReferences, parameters: program.params,
    expression_contract_cid: expressionCid,
    local_body: {effects: {}, inputs: {}, results: stage.results,
      steps: [stage.steps[0], {...stage.steps[1], derive: {...stage.steps[1].derive, supplied: {$param: 'suffix'}}}]}};
  const semantics = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
    expression_contract_cid: expressionCid, parameters: program.params,
    parameter_references: parameterReferences.map(value => ({...value, path: `/stages/0${value.path}`})),
    bindings: {}, binding_references: [], program_template: {stages: [{id: 's',
      after: 'initial', imports: {}, stage_semantics_cid: cid(stageSemantics)}], exports: program.results}};
  const programDefinitionCid = cid({version: 'actql-program-definition/0.1', id: program.id,
    program_semantics_cid: cid(semantics)});
  const parameterValuesCid = cid({values: parameters, version: 'actql-parameter-values/0.1'});
  assert.notEqual(parameterValuesCid, cid({values: {suffix: parameters.suffix.normalize('NFC')},
    version: 'actql-parameter-values/0.1'}), 'NFC must not rewrite parameter data');
  assert.notEqual(parameterValuesCid, cid({values: {suffix: parameters.suffix.replace(/\r\n/g, '\n')},
    version: 'actql-parameter-values/0.1'}), 'CRLF must not rewrite parameter data');
  const callerInputIntentCid = cid({selection: 'none', version: 'actql-caller-input-intent/0.1'});
  const intentFingerprintCid = cid({caller_input_intent_cid: callerInputIntentCid,
    parameter_values_cid: parameterValuesCid, program_definition_cid: programDefinitionCid,
    version: 'actql-logical-request-intent/0.1'});
  const prepareAttemptId = `prepare-${cid({authority_scope_cid: authorityScopeCid,
    namespace_id: namespaceId, request_id: requestId}).slice(7, 47)}`;
  const captured = {version: 'actql-remote-captured-submission/0.1', requestId,
    principalId, connection: {mode, owner: mode, durability: 'durable', consentRefs: [], runners: []},
    kind: 'aql', input: {format: 'json', text: document}, parameters, resultNames: ['answer']};
  const subject = {version: 'actql-remote-run-acceptance-request/0.1',
    authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
    logical_request_scope_cid: logicalRequestScopeCid, intent_fingerprint_cid: intentFingerprintCid,
    site_key: siteKey, realization_key: realizationKey};
  const request = {version: 'actql-remote-invocation-request/0.1', subject, subject_cid: cid(subject)};
  const requestCid = cid(request);
  const invocation = {version: 'actql-remote-prepared-invocation/0.1', request_cid: requestCid,
    captured_submission_cid: cid(captured), site_key: siteKey, realization_key: realizationKey};
  const invocationCid = cid(invocation);
  const createdAt = new Date(now).toISOString(), expiresAt = new Date(now +
    (authorization.checkpointTtlMs ?? 86400000)).toISOString();
  const reviewBody = {version: 'actql-run-review-projection/0.1', prepared_invocation_cid: invocationCid,
    execution_context_cid: contextCid, host_policy_cid: configurationCid,
    approval_claims: ['invocation_scope_approved'],
    authoring_context_cid: cid({principal: principalId, request_id: requestId}),
    redaction_policy_cid: cid({version: 'actql-remote-review-redaction/0.1', redacted: []}),
    sensitivity: 'restricted', retention_class: 'approval-evidence', encryption_required: true,
    expires_at: expiresAt, displayed_scope: {request_id: requestId, kind: 'aql', format: 'json',
      document, parameters, site_key: siteKey, realization_key: realizationKey, operation: 'write'},
    displayed_authoring_context: [{principal: principalId}]};
  const review = {...reviewBody, review_projection_cid: cid(reviewBody)};
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
    {name: 'invocation_request', wire: wire(request)},
    {name: 'prepared_invocation', wire: wire(invocation)},
    {name: 'review_projection', wire: reviewWire}];
  const decisionSubject = {account_id: account.account_id, configuration_cid: configurationCid,
    entry_id: account.entries[0].entry_id, principal: principalId, connection: siteKey,
    resource: realizationKey, operation: 'write', boundary: 'preparation', subject_cid: cid(subject),
    context_cid: contextCid};
  const continuation = {version: 'actql-remote-continuation/0.1', prepare_attempt_id: prepareAttemptId,
    boundary: 'preparation', invocation_cid: invocationCid, request_subject_cid: cid(subject),
    request_id: requestId, delegated_subject: decisionSubject,
    answering_authorities: authorization.reviewers.map(item => item.reviewerId),
    evidence: items.map(item => reference(item.name, item.wire))};
  items.push({name: 'continuation_record', wire: wire(continuation)});
  const checkpointBody = {version: 'actql-execution-checkpoint/0.1', phase: 'preflight', kind: 'run_scope',
    requirements: ['invocation_scope_approved'], reason_code: 'delegated_decision_deferred',
    checkpoint_id: `${prepareAttemptId}-preparation`, continuation_state_cid: cid(continuation),
    subject: {kind: 'prepare_attempt', prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
    required_artifact: {artifact_type: 'prepared_invocation', artifact_cid: invocationCid},
    review_projection_cid: reviewCid, human_summary: `Run request ${requestId} on ${siteKey}`,
    created_at: createdAt, expires_at: expiresAt};
  const checkpointCid = cid(checkpointBody);
  const checkpointWire = wire({...checkpointBody, checkpoint_cid: checkpointCid});
  const {evidence_bundle_cid: _ignored, ...environmentBody} = JSON.parse(await readFile(
    new URL('spec/local-check-environment.json', runtimeRootUrl), 'utf8'));
  void _ignored;
  // This is the selected installation's declared environment input, not a
  // returned acceptance result; the original binding is independently hashed.
  environmentBody.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...environmentBody.host_policy_profile.capacity,
    // Same declared Local materialization windows as the ordinary Values
    // historical fixture, independently authored before current acceptance.
    max_relation_output_rows: 536870912 / 256,
    max_artifact_rows: 536870912 / 256,
    // The current Local factory selects this optional ceiling from the same
    // nominal row policy. It does not turn this synthetic historical-format
    // input into evidence that an earlier Host selected that Environment.
    max_file_listing_items: 536870912 / 256,
    max_model_request_bytes_per_item: 65536};
  const binding = {authorization_context_cid: cid({principal: principalId,
    account_id: account.account_id, configuration_cid: configurationCid, source_configuration_cid: null}),
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
    for (const table of ['runs', 'resolutions', 'resume_intents', 'resume_admissions',
      'preparations', 'checkpoints']) {
      assert.equal(database.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
    }
    assert.deepEqual(database.prepare("SELECT status FROM preparations WHERE status != 'waiting_checkpoint'").all(), []);
    database.exec('BEGIN IMMEDIATE');
    database.prepare(`INSERT INTO preparations (prepare_attempt_id, status, version,
      updated_at, declared_results_json, checkpoint_cid) VALUES (?, 'waiting_checkpoint', 1, ?, ?, ?)`)
      .run(prepareAttemptId, createdAt, '["answer"]', checkpointCid);
    database.prepare(`INSERT INTO checkpoints (checkpoint_cid, checkpoint_id, run_id,
      prepare_attempt_id, checkpoint_wire, expires_at, authorities_json, binding_json,
      decision_subject_cid, requested_claims_json, configuration_cid, closure, persisted_at)
      VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, '[]', ?, 'open', ?)`)
      .run(checkpointCid, checkpointBody.checkpoint_id, prepareAttemptId, checkpointWire, expiresAt,
        JSON.stringify(authorization.reviewers.map(item => ({key_id: item.keyId, reviewer_id: item.reviewerId}))),
        JSON.stringify(binding), cid(decisionSubject), configurationCid, createdAt);
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
