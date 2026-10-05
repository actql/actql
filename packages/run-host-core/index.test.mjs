import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import './retained-input.test.mjs';
import {valuesUnitIdentity, valuesResultPlan} from
  '../../scripts/fixtures/string-contract-identities.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {residentSourceEnvironment, sourceProgram, sourceRef, sourceContractCid}
  from '../../scripts/fixtures/resident-source.mjs';
import {fileURLToPath} from 'node:url';
import {valuesDependencyOracle} from '../../scripts/client-values-dependency-oracle.mjs';
import {validRunState} from '../client-wire/index.mjs';
import {admitDispatchJson, dispatchCid, createJournal, prepareIntent,
  admissionDurableJson, admitDurableJson, commitIntent, admitResponseJson,
  prepareResponseObservation, responseDurableJson}
  from '../coordinator-core/index.mjs';
import {admitEnvironment, admitProfileSelection, admitRequestFields, admitRunDefinition,
  admitSourceFreeRunDefinition,
  issueSourceFreeRunMaterials, issueTaskRunMaterials,
  admitPublicationContract, admitRunEvidenceValue, sealRunEvidenceValue,
  validatePublicationChain,
  validatePublicationRecordTransition,
  issueResultManifest,
  issueResultOccurrenceEvidence, issueCompleteResultArtifact,
  issueCheckedValuesResultOccurrenceEvidence,
  issueDurableResultBinding,
  issuePublicationRequest, issuePublicationAttempt,
  issuePublicIndexEntry, issuePublicationRecord,
  validateEffectFreePublicationCommit,
  issueEffectFreeRunReceipt, admitCapturedResultSnapshot,
  issueSourceFreeCapturedRun,
  openResultDeliveryControl,
  beginResultMaterialHolds, admitResultMaterialHolds,
  resultMaterialHoldsWire, resultMaterialHoldsFacts,
  prepareResultMaterialHoldsStep,
  projectPublicationSnapshot,
  publicationIndexScopeKey,
  inspectCanonicalResultRows,
  admitSourceFreeRequestFields, admitRun, compileValues, compileTasks,
  privateTaskCompilationWires, taskResultNames,
  taskResultDefinitions, taskResultSchema, taskExecutionShape, taskKeys,
  sourceEvidenceFacts, taskInputBinding, prepareTaskRequest, issueTaskDispatch,
  issueAllowedTaskRun, admitTaskRun, issueTaskRunDefinition,
  admitTaskRunDefinition,
  checkRunBinding, issueAllowedRun, issueRunDefinition,
  issueSourceFreeRunDefinition, prepare, prepareRequest,
  issueSourceFreeDispatch,
  executionShape,
  resultDefinitions, resultSchema,
  issueSourceFreeInvocation, issueSourceFreeTaskInvocation,
  admitCompletedSourceObservation,
  issueTaskInvocation,
  issueUnpublishedRunStateWire, issueSucceededRunStateWire, projectSiteRun,
  resultReadAvailability, describeCommittedResult,
  prepareRunStart, prepareRunPhysicalStart, prepareRunCancellation,
  prepareRunPreStartFailure,
  issueRunControlObservation,
  prepareSourceFreeRequest,
  privateCompilationWires, compiledPlanCid,
  privateRunDefinition, requestFields, requestRelation} from './index.mjs';

const read = name => readFileSync(new URL(`../sdk/fixtures/${name}`,
  import.meta.url), 'utf8');
const environmentWire = read('values.environment.json').trimEnd();
const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
const cid = body => `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;
const without = (value, key) => {
  const body = {...value};
  delete body[key];
  return cid(body);
};

const noProfiles = Object.freeze({textTime: false, veca: false, rela: false,
  sga: false, tea: false, calendar: false, textRank: false});

test('profile admission preserves omitted and explicit false selections', () => {
  assert.deepEqual(admitProfileSelection({}), noProfiles);
  assert.deepEqual(admitProfileSelection(noProfiles), noProfiles);
  for (const key of ['textTime', 'veca', 'rela', 'sga', 'tea', 'calendar', 'textRank']) {
    const input = {[key]: true};
    const admitted = admitProfileSelection(input);
    assert.deepEqual(admitted, {...noProfiles, [key]: true});
    assert.ok(Object.isFrozen(admitted));
    assert.notEqual(admitted, input);
    input[key] = false;
    assert.equal(admitted[key], true);
    assert.deepEqual(admitProfileSelection({[key]: false}), noProfiles);
  }
});

test('profile admission and environment refuse the same malformed selections', () => {
  const malformed = [null, undefined, [], true, false, 0, 'rela',
    {unknown: false}, {rela: true, unknown: true}];
  for (const key of ['textTime', 'veca', 'rela', 'sga', 'tea', 'calendar', 'textRank']) {
    for (const value of [undefined, null, 0, 1, 'true', [], {}]) {
      malformed.push({[key]: value});
    }
  }
  for (const input of malformed) {
    assert.throws(() => admitProfileSelection(input),
      {name: 'TypeError', message: 'InvalidRunHostProfileSelection'});
    assert.throws(() => admitEnvironment(environmentWire, evidenceCid, input),
      {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
  }
});

test('profile admission retains environment and prepared request identities', () => {
  const document = read('values.json');
  const scope = 'sha256:' + 'a'.repeat(64);
  const inputCid = 'sha256:' + 'b'.repeat(64);
  const identity = profiles => requestFields(prepareRequest(
    prepare(document, 'json', admitEnvironment(environmentWire, evidenceCid, profiles)),
    scope, 'retained-profile', inputCid));
  const expected = identity({rela: true});
  const persisted = {textTime: false, veca: false, rela: true, sga: false,
    tea: false, calendar: false, textRank: false};
  assert.deepEqual(admitProfileSelection({rela: true}), persisted);
  assert.deepEqual(identity(persisted), expected);
  assert.deepEqual(identity(admitProfileSelection({rela: true})), expected);
  assert.deepEqual(identity(admitProfileSelection(persisted)), expected);
  assert.throws(() => admitEnvironment(null, evidenceCid, {}),
    {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
  assert.throws(() => admitEnvironment(environmentWire, null, {}),
    {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
});

test('Run materials project the original owner and retained input, not new authority', () => {
  const document = read('values.json');
  const environment = admitEnvironment(environmentWire, evidenceCid, {rela: true});
  const prepared = prepare(document, 'json', environment);
  const compilation = compileValues(prepared);
  const authority = {executionContextCid: 'sha256:' + 'a'.repeat(64),
    hostPolicyCid: 'sha256:' + 'b'.repeat(64), expiresAt: '2099-01-01T00:00:00.000Z'};
  const allowed = issueAllowedRun(prepared, compilation, authority);
  const definition = issueSourceFreeRunDefinition(prepared, compilation,
    allowed.admission, 'original-scope', 'original-run',
    '2026-09-30T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const retained = {document, format: 'json', environment, environmentWire};
  const emit = (input = retained, run = definition) => issueSourceFreeRunMaterials(
    prepared, compilation, allowed.admission, run, input);
  const expected = {check_environment: environmentWire,
    check_environment_cid: evidenceCid, created_at: '2026-09-30T00:00:00.000Z',
    parameters: null, prepared_invocation: allowed.preparedInvocationWire,
    program: document, program_format: 'json',
    run_authorization: allowed.authorizationWire, run_id: 'original-run',
    scope_id: 'original-scope', valid_until: '2098-01-01T00:00:00.000Z',
    version: 'actql-remote-run-materials/0.1'};
  assert.deepEqual(JSON.parse(emit()), expected);
  const before = privateRunDefinition(definition);
  assert.equal(emit(), emit());
  assert.deepEqual(privateRunDefinition(definition), before);
  const changedInput = JSON.parse(document);
  changedInput.stages[0].steps[0].values.rows[1].id = 3;
  assert.throws(() => emit({...retained, document: JSON.stringify(changedInput)}),
    {code: 'RunHostRunMaterialsRejected'});
  assert.throws(() => emit({...retained, environmentWire: '{}'}),
    {code: 'RunHostRunMaterialsRejected'});
  assert.throws(() => emit({...retained, parametersWire: ' '.repeat(65537)}),
    {code: 'RunHostRunMaterialsRejected'});
  assert.throws(() => emit({...retained, format: 'yaml'}),
    {message: 'InvalidRunHostRunMaterialsInput'});
  assert.throws(() => emit({...retained, run_id: 'replacement'}),
    {message: 'InvalidRunHostRunMaterialsInput'});
  const other = prepare(document, 'json', environment);
  assert.throws(() => issueSourceFreeRunMaterials(other, compilation,
    allowed.admission, definition, retained), {message: 'ForeignRunHostCompilation'});
  // Both raw bodies fit their individual 64KiB bounds. Outer JSON quoting
  // nevertheless exceeds 262144 bytes and must be bounded by the issuer.
  const parametersWire = '\t'.repeat(65534) + '{}';
  const paddedDocument = '\t'.repeat(65536 - Buffer.byteLength(document)) + document;
  const paddedInput = {...retained, document: paddedDocument, parametersWire};
  // Establish that input/parameters are individually admitted and unchanged.
  assert.deepEqual(requestFields(prepareRequest(prepare(paddedDocument, 'json',
    environment, parametersWire), 'sha256:' + 'c'.repeat(64), 'padding',
  'sha256:' + 'd'.repeat(64))),
  requestFields(prepareRequest(prepared, 'sha256:' + 'c'.repeat(64), 'padding',
    'sha256:' + 'd'.repeat(64))));
  assert.ok(Buffer.byteLength(JSON.stringify({...expected,
    program: paddedDocument, parameters: parametersWire})) > 262144);
  assert.throws(() => emit(paddedInput), {code: 'RunHostRunMaterialsRejected'});
});

test('Run materials preserve separately supplied parameter identity', () => {
  const document = read('parameter-values.json');
  const environment = admitEnvironment(environmentWire, evidenceCid, {rela: true});
  const parametersWire = '{"n":3}';
  const prepared = prepare(document, 'json', environment, parametersWire);
  const compilation = compileValues(prepared);
  const allowed = issueAllowedRun(prepared, compilation, {
    executionContextCid: 'sha256:' + 'a'.repeat(64),
    hostPolicyCid: 'sha256:' + 'b'.repeat(64), expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueSourceFreeRunDefinition(prepared, compilation,
    allowed.admission, 'original-scope', 'parameter-run',
    '2026-09-30T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const retained = {document, format: 'json', environment, environmentWire, parametersWire};
  const emit = input => issueSourceFreeRunMaterials(prepared, compilation,
    allowed.admission, definition, input);
  assert.equal(JSON.parse(emit(retained)).parameters, parametersWire);
  assert.throws(() => emit({...retained, parametersWire: '{"n":4}'}),
    {code: 'RunHostRunMaterialsRejected'});
  assert.throws(() => emit({...retained, parametersWire: undefined}),
    {code: 'RunHostRunMaterialsRejected'});
});

test('acquired observation binds the checked source and completed input',
  () => {
    const sourceContractCid = cid({source: 'checked'});
    const authorityScopeCid = cid({scope: 'local'});
    const other = cid({fixture: 'evidence'});
    const sourceRef = 'connector://crm/main/r#v';
    const limits = {maxWireBytes: 8192, maxNodes: 256, maxDepth: 16};
    const ordering = {stable: false, keys: []};
    const logical = sealRunEvidenceValue('source_input_logical',
      JSON.stringify({version: 'actql-source-input-logical/0.1',
        logical_relation_cid: other, relation_schema_cid: other,
        source_contract_cid: sourceContractCid, completeness: 'complete',
        ordering_evidence: ordering}), limits);
    const evidence = sealRunEvidenceValue('source_evidence', JSON.stringify({
      version: 'actql-source-evidence/0.1', source_ref: sourceRef,
      input_logical_cid: logical.cid, source_contract_cid: sourceContractCid,
      schema_evidence_cid: other, capability_evidence_cid: other,
      authority_scope_cid: authorityScopeCid,
      source_data_policy_cid: other, effective_data_policy_cid: other,
      data_classification: 'internal', source_view_contract_cid: other,
      output_carrier: 'relation', read_mode: 'snapshot',
      observed_at: '2026-09-26T00:00:00.000Z', snapshot_ref: 'snapshot-1',
      completeness: 'complete', ordering_evidence: ordering,
      consistency_level: 'snapshot',
    }), limits);
    const facts = {sourceEvidenceWire: evidence.wire,
      inputLogicalWire: logical.wire, sourceRef, sourceContractCid,
      authorityScopeCid, effectiveDataPolicyCid: other, limits};
    assert.equal(admitCompletedSourceObservation(facts), evidence.cid);
    assert.throws(() => admitCompletedSourceObservation({...facts,
      sourceRef: 'connector://foreign'}),
    {code: 'RunHostSourceObservationRejected'});
    assert.throws(() => admitCompletedSourceObservation({...facts,
      authorityScopeCid: other}),
    {code: 'RunHostSourceObservationRejected'});
    assert.throws(() => admitCompletedSourceObservation({...facts,
      effectiveDataPolicyCid: sourceContractCid}),
    {code: 'RunHostSourceObservationRejected'});
    const foreignInput = sealRunEvidenceValue('source_input_logical',
      JSON.stringify({...JSON.parse(logical.wire),
        input_logical_cid: undefined,
        logical_relation_cid: cid({rows: 'foreign'})}), limits);
    assert.throws(() => admitCompletedSourceObservation({...facts,
      inputLogicalWire: foreignInput.wire}),
    {code: 'RunHostSourceObservationRejected'});
    const partial = sealRunEvidenceValue('source_evidence', JSON.stringify({
      ...JSON.parse(evidence.wire), source_evidence_cid: undefined,
      completeness: 'partial',
    }), limits);
    assert.throws(() => admitCompletedSourceObservation({...facts,
      sourceEvidenceWire: partial.wire}),
    {code: 'RunHostSourceObservationRejected'});
  });

test('checked acquired Program issues and re-admits its task Run', () => {
  const source = readFileSync(new URL(
    '../../src/query_integration/query_amount_catalog_wbtest.mbt',
    import.meta.url), 'utf8');
  const catalog = source.slice(source.indexOf(
    'fn query_amount_nullable_catalog')).match(
    /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/u);
  assert.ok(catalog);
  const environment = admitEnvironment(JSON.parse(catalog[1]),
    catalog[2], {rela: true});
  const document = readFileSync(new URL(
    '../../adapters/connectors/duckdb/node/examples/program.json',
    import.meta.url), 'utf8');
  const parameters = readFileSync(new URL(
    '../../adapters/connectors/duckdb/node/examples/parameters.json',
    import.meta.url), 'utf8');
  const prepared = prepare(document, 'json', environment, parameters);
  const compilation = compileTasks(prepared);
  assert.deepEqual(taskResultNames(compilation), ['b', 'c']);
  const definitions = taskResultDefinitions(prepared, compilation);
  assert.deepEqual(definitions.map(item => item.name), ['b', 'c']);
  assert.notEqual(definitions[0].cid, definitions[1].cid);
  assert.deepEqual(taskResultSchema(prepared, compilation, 'b').fields,
    ['id']);
  assert.deepEqual(taskResultSchema(prepared, compilation, 'c').fields,
    ['id']);
  const wires = privateTaskCompilationWires(compilation);
  const plan = JSON.parse(wires.executablePlan);
  assert.equal(plan.nodes.length, 4);
  assert.equal(plan.data_edges.length, 3);
  assert.deepEqual(plan.root_refs.map(root => root.name), ['b', 'c']);
  const allowed = issueAllowedTaskRun(prepared, compilation, {
    executionContextCid: `sha256:${'a'.repeat(64)}`,
    hostPolicyCid: `sha256:${'b'.repeat(64)}`,
    expiresAt: '2026-10-01T00:00:00.000Z',
  });
  const definition = issueTaskRunDefinition(prepared, compilation,
    allowed.admission, 'task-scope', 'task-run',
    '2026-09-26T00:00:00.000Z', '2026-09-27T00:00:00.000Z');
  const retained = {document, format: 'json', environment,
    environmentWire: JSON.parse(catalog[1]), parametersWire: parameters};
  const materials = issueTaskRunMaterials(prepared, compilation,
    allowed.admission, definition, retained);
  const projected = JSON.parse(materials);
  assert.equal(projected.program, document);
  assert.equal(projected.parameters, parameters);
  assert.equal(projected.check_environment, retained.environmentWire);
  assert.equal(projected.prepared_invocation, allowed.preparedInvocationWire);
  assert.equal(projected.run_authorization, allowed.authorizationWire);
  assert.equal(projected.run_id, 'task-run');
  assert.equal(projected.valid_until, '2026-09-27T00:00:00.000Z');
  assert.equal(issueTaskRunMaterials(prepared, compilation,
    allowed.admission, definition, retained), materials);
  assert.throws(() => issueTaskRunMaterials(prepared, compilation,
    allowed.admission, definition, {...retained, parametersWire: '{"minimum":7}'}),
  {code: 'RunHostRunMaterialsRejected'});
  assert.throws(() => issueTaskRunMaterials(prepared, compilation,
    allowed.admission, definition, {...retained, databasePath: '/forbidden.db'}),
  {message: 'InvalidRunHostRunMaterialsInput'});
  assert.throws(() => issueTaskRunMaterials(prepare(document, 'json',
    environment, parameters), compilation, allowed.admission, definition, retained),
  {message: 'ForeignRunHostCompilation'});
  const limits = {maxWireBytes: 8192, maxNodes: 256, maxDepth: 16};
  assert.throws(() => issueSourceFreeTaskInvocation(prepared, compilation,
    allowed.admission, definition, `sha256:${'d'.repeat(64)}`, limits),
  {code: 'RunHostTaskInvocationRejected'});
  const sourceContractCid =
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3';
  const sourceRef = 'connector://crm/main/r#v';
  const authorityScopeCid = cid({scope: 'task'});
  const dataPolicyCid = cid({policy: 'task'});
  const other = cid({evidence: 'task'});
  const ordering = {stable: false, keys: []};
  const input = sealRunEvidenceValue('source_input_logical',
    JSON.stringify({version: 'actql-source-input-logical/0.1',
      logical_relation_cid: other, relation_schema_cid: other,
      source_contract_cid: sourceContractCid, completeness: 'complete',
      ordering_evidence: ordering}), limits);
  const sourceEvidence = sealRunEvidenceValue('source_evidence',
    JSON.stringify({version: 'actql-source-evidence/0.1',
      source_ref: sourceRef, input_logical_cid: input.cid,
      source_contract_cid: sourceContractCid, schema_evidence_cid: other,
      capability_evidence_cid: other,
      authority_scope_cid: authorityScopeCid,
      source_data_policy_cid: other,
      effective_data_policy_cid: dataPolicyCid,
      data_classification: 'internal', source_view_contract_cid: other,
      output_carrier: 'relation', read_mode: 'snapshot',
      observed_at: '2026-09-26T00:00:01.000Z', snapshot_ref: 'read-view-1',
      completeness: 'complete', ordering_evidence: ordering,
      consistency_level: 'snapshot'}), limits);
  const sourceFacts = {sourceEvidenceWire: sourceEvidence.wire,
    inputLogicalWire: input.wire, sourceRef, sourceContractCid,
    authorityScopeCid, dataPolicyCid,
    captureStartedAt: '2026-09-26T00:00:00.000Z',
    captureCompletedAt: '2026-09-26T00:00:01.000Z'};
  const issued = issueTaskInvocation(prepared, compilation,
    allowed.admission, definition, sourceFacts, limits);
  assert.deepEqual(JSON.parse(issued.observation.wire)
    .source_evidence_cids, [sourceEvidence.cid]);
  assert.equal(JSON.parse(issued.invocation.wire).observation_set_cid,
    issued.observation.cid);
  assert.throws(() => issueTaskInvocation(prepared, compilation,
    allowed.admission, definition, {...sourceFacts,
      dataPolicyCid: other}, limits),
  {code: 'RunHostTaskInvocationRejected'});
  assert.throws(() => issueTaskInvocation(prepared, compilation,
    allowed.admission, definition, {...sourceFacts,
      captureCompletedAt: '2026-09-25T00:00:00.000Z'}, limits),
  {name: 'TypeError', message: 'InvalidRunHostTaskObservation'});
  const wire = privateRunDefinition(definition).wire;
  const restoredAdmission = admitTaskRun(prepared, compilation,
    allowed.preparedInvocationWire, allowed.authorizationWire);
  assert.equal(privateRunDefinition(admitTaskRunDefinition(prepared,
    compilation, restoredAdmission, wire)).wire, wire);
  assert.equal(privateRunDefinition(admitTaskRunDefinition(prepared,
    compilation, allowed.admission, wire)).wire, wire);
  const changed = prepare(document, 'json', environment,
    JSON.stringify({minimum: 7}));
  assert.throws(() => admitTaskRunDefinition(changed, compileTasks(changed),
    issueAllowedTaskRun(changed, compileTasks(changed), {
      executionContextCid: `sha256:${'a'.repeat(64)}`,
      hostPolicyCid: `sha256:${'b'.repeat(64)}`,
      expiresAt: '2026-10-01T00:00:00.000Z',
    }).admission, wire), {code: 'RunHostTaskDefinitionRejected'});
});

test('resident Source dispatch preserves checked task and logical input identity', async () => {
  const fixture = await residentSourceEnvironment(fileURLToPath(new URL('../../', import.meta.url)));
  const environment = admitEnvironment(fixture.wire, fixture.cid, {rela: true});
  const prepared = prepare(sourceProgram, 'json', environment);
  const compilation = compileTasks(prepared);
  assert.deepEqual(taskExecutionShape(prepared, compilation), {taskCount: 1, acquisitionCount: 1});
  assert.deepEqual(taskKeys(prepared, compilation), ['task_0']);
  // The extra Plan node is a publication transform, not another task claim.
  assert.equal(JSON.parse(privateTaskCompilationWires(compilation).executablePlan).nodes.length, 2);
  assert.deepEqual(taskResultSchema(prepared, compilation, 'answer').fields, ['id']);
  const facts = sourceEvidenceFacts(prepared, 0, 0);
  assert.equal(facts.sourceRef, sourceRef);
  assert.equal(facts.sourceContractCid, sourceContractCid);
  assert.equal(facts.sourceDataPolicyCid,
    'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf');
  assert.equal(sourceEvidenceFacts(prepared, 1, 0), undefined);
  const binding = taskInputBinding(prepared, 0);
  assert.deepEqual(JSON.parse(binding), {source_contract_cid: sourceContractCid, source_ref: sourceRef});
  assert.throws(() => taskInputBinding(prepared, 1), {code: 'RunHostTaskBindingRejected'});
  const scope = cid({authority: 'Source'});
  const allowed = issueAllowedTaskRun(prepared, compilation, {
    executionContextCid: cid({context: 'Source'}), hostPolicyCid: cid({policy: 'Source'}),
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = issueTaskRunDefinition(prepared, compilation, allowed.admission,
    'Source-scope', 'original-Source-run', '2026-10-03T00:00:00.000Z', '2026-10-04T00:00:00.000Z');
  const request = prepareTaskRequest(prepared, compilation, scope, 'Source-request');
  const unpublished = issueUnpublishedRunStateWire(prepared, compilation, allowed.admission,
    definition, '2026-10-03T00:00:01.000Z', {dispatchReserved: false, preDispatchFailureConfirmed: false});
  assert(validRunState(JSON.parse(unpublished)));
  assert.equal(JSON.parse(unpublished).status, 'preparing');
  const succeeded = issueSucceededRunStateWire(prepared, compilation, allowed.admission,
    definition, '2026-10-03T00:00:02.000Z', [{name: 'answer', state: 'available', reason: 'confirmed_present',
      observedAt: '2026-10-03T00:00:02.000Z'}]);
  assert(validRunState(JSON.parse(succeeded)));
  assert.equal(JSON.parse(succeeded).status, 'succeeded');
  const selected = {taskAttempt: 1, dispatchId: 'Source-dispatch', siteKey: 'Source-site', siteGeneration: 1,
    runtimeBundleCid: cid({bundle: 'Source'}), connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', obligationsCid: cid({obligations: 'Source'}), budgetCid: cid({budget: 'Source'}),
    evidenceIssuerCapabilityCid: cid({issuer: 'Source'}), grantCid: cid({grant: 'Source'})};
  const issued = issueTaskDispatch(prepared, compilation, allowed.admission, definition, request, 0, selected);
  const dispatch = JSON.parse(issued.wire);
  assert.equal(dispatch.run_definition_cid, privateRunDefinition(definition).cid);
  assert.equal(dispatch.coordinator_authority, scope);
  assert.equal(dispatch.task_key, taskKeys(prepared, compilation)[0]);
  assert.equal(dispatch.input_binding_cid, `sha256:${createHash('sha256').update(binding).digest('hex')}`);
  assert.deepEqual(issueTaskDispatch(prepared, compilation, allowed.admission, definition, request, 0, selected), issued);
  for (const [execution, cleanup, nextWork] of [[3, 0, 'publication'], [3, 2, 'publication'],
    [4, 2, 'none'], [4, 1, 'cleanup'], [6, 3, 'reconcile']]) {
    const admittedDispatch = admitDispatchJson(issued.wire, issued.cid);
    const intent = prepareIntent(createJournal(scope), admittedDispatch);
    const durable = admitDurableJson(admissionDurableJson(intent));
    const record = commitIntent(intent);
    const response = admitResponseJson(JSON.stringify({
      version: 'actql-remote-dispatch-response/0.1', dispatch_request_cid: issued.cid,
      revision: 2, state: [execution, 0, cleanup, 0, 0],
    }), admittedDispatch, false);
    const saved = responseDurableJson(durable, prepareResponseObservation(record, response), response);
    const projection = projectSiteRun(prepared, compilation, allowed.admission, definition,
      scope, saved, '2026-10-03T00:00:01.000Z');
    assert.equal(projection.nextWork, nextWork);
    assert(validRunState(JSON.parse(projection.stateWire)));
    assert.deepEqual(projectSiteRun(prepared, compilation, allowed.admission, definition,
      scope, saved, '2026-10-03T00:00:01.000Z'), projection);
    assert.throws(() => projectSiteRun(prepared, compilation, allowed.admission, definition,
      cid({authority: 'foreign'}), saved, '2026-10-03T00:00:01.000Z'),
    {code: 'RunHostSiteProjectionRejected'});
  }
  assert.throws(() => issueTaskDispatch(prepared, compilation, allowed.admission, definition, request, 1, selected),
    {code: 'RunHostDispatchRejected'});
  const foreign = prepare(sourceProgram.replace('id > 1', 'id > 2'), 'json', environment);
  assert.throws(() => issueTaskDispatch(prepared, compilation, allowed.admission, definition,
    prepareTaskRequest(foreign, compileTasks(foreign), scope, 'Source-request'), 0, selected),
    {code: 'RunHostDispatchRejected'});
});

test('portable delivery control keeps progress and serializer opaque', () => {
  const control = openResultDeliveryControl();
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const progress = control.beginResultAccessProgress();
  assert.equal(control.resultAccessProgressAction(progress),
    'authorize_request');
  assert.equal(control.recordResultAccessRequestAuthorization(progress,
    true), true);
  assert.equal(control.resultAccessProgressAction(progress),
    'resolve_committed_result');
  assert.throws(() => control.resultAccessProgressAction({}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.equal(control.deliveryFailureTerminalAction(false), 'failed');
  assert.equal(control.deliveryFailureTerminalAction(true), 'cancelled');
  assert.equal(control.deliveryRecordRetryAction(0, 1),
    'append_next_record');
  assert.equal(control.deliveryRecordRetryAction(1, 1), 'finished');
  assert.equal(control.deliveryRecordRetryAction(2, 1), 'invalid');
  const schema = '{"id":{"nullable":false,"type":"number"}}';
  const serializer = control.prepareResultDeliverySerializer('jsonl',
    schema, ['id'], limits);
  assert.equal(control.beginResultDelivery(serializer), '');
  assert.equal(control.nextResultDeliveryRow(serializer, '{"id":1}'),
    '{"id":1}\n');
  assert.equal(control.finishResultDelivery(serializer), '');
  assert.throws(() => control.finishResultDelivery({}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.equal(control.trustedClockNotBefore(undefined,
    '2026-09-24T00:00:00.000Z'), true);
  assert.equal(control.trustedClockNotBefore(
    '2026-09-24T00:00:01.000Z', '2026-09-24T00:00:00.000Z'), false);
  const frames = control.prepareDurableResultRowFrames({maxBytes: 2,
    maxRows: 0, maxRowBytes: 1024, maxDepth: 16, maxFrameBytes: 1024});
  assert.deepEqual(control.feedDurableResultRowFrames(frames,
    new TextEncoder().encode('[]')), []);
  assert.deepEqual(control.finishDurableResultRowFrames(frames),
    {bytes: 2, rows: 0});
  assert.throws(() => control.feedDurableResultRowFrames({},
    new Uint8Array()),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('captured completion requires owner-admitted handles', () => {
  const limits = {maxWireBytes: 4096, maxNodes: 128, maxDepth: 16};
  assert.throws(() => admitCapturedResultSnapshot({}, {}, '[]', [],
    limits), {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.throws(() => issueEffectFreeRunReceipt({}, {}, {}, {}, [], [],
    {}, {}, {bindingNames: [], bindingDigests: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}, limits),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.throws(() => issueSourceFreeCapturedRun({}, {}, [], [], {}, {},
    [], {}, [], limits),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('portable Host re-admits exact publication evidence', () => {
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const definition = resultDefinitions(prepared, compileValues(prepared))[0];
  const admitted = admitPublicationContract('result_definition',
    definition.wire, limits);
  assert.equal(admitted.cid, definition.cid);
  assert.equal(admitted.wire, definition.wire);
  const altered = JSON.parse(definition.wire);
  altered.result_name = 'different';
  assert.throws(() => admitPublicationContract('result_definition',
    JSON.stringify(altered), limits),
  {code: 'RunHostPublicationContractRejected'});
  assert.throws(() => admitPublicationContract('result_artifact',
    definition.wire, limits),
  {code: 'RunHostPublicationContractRejected'});
  assert.throws(() => validatePublicationChain(admitted, admitted,
    [admitted], [admitted], admitted, limits),
  {code: 'RunHostPublicationChainRejected'});
  assert.throws(() => validatePublicationRecordTransition(undefined,
    admitted, false),
  {code: 'RunHostPublicationTransitionRejected'});
  assert.throws(() => admitPublicationContract('result_definition',
    definition.wire, {maxWireBytes: 0, maxNodes: 100, maxDepth: 10}),
  {name: 'TypeError', message: 'InvalidRunHostPublicationLimits'});
});

test('portable Host keeps publication absence and uncertainty distinct',
  () => {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const fixed = value => `sha256:${value.repeat(64)}`;
    const admit = (name, body, identityField) => {
      const complete = {...body, [identityField]: cid(body)};
      return admitPublicationContract(name, JSON.stringify(complete), limits);
    };
    assert.deepEqual(projectPublicationSnapshot(undefined, {kind: 'absent'}),
      {state: 'not_started', evidenceCid: undefined});
    assert.throws(() => projectPublicationSnapshot(undefined,
      {kind: 'unknown'}), {code: 'RunHostPublicationSnapshotRejected'});
    const record = admit('publication_record', {
      version: 'actql-publication-record/0.1',
      publication_attempt_cid: fixed('a'), sequence: 0,
      state: 'publication_unknown',
      observed_at: '2026-09-24T00:00:00.000Z', cleanup_owner_cids: [],
    }, 'publication_record_cid');
    assert.deepEqual(projectPublicationSnapshot(record, {kind: 'absent'}),
      {state: 'publication_unknown', evidenceCid: record.cid});
    assert.throws(() => projectPublicationSnapshot(record,
      {kind: 'unknown'}), {code: 'RunHostPublicationSnapshotRejected'});
    const index = admit('public_index_entry', {
      version: 'actql-public-index-entry/0.1', namespace_id: 'namespace-a',
      authority_scope_cid: fixed('b'), run_definition_cid: fixed('c'),
      invocation_cid: fixed('d'), result_manifest_cid: fixed('e'),
      run_receipt_cid: fixed('f'), captured_run_cid: fixed('0'),
      durable_result_binding_cids: [fixed('1')],
      publication_request_cid: fixed('2'),
      publication_attempt_cid: fixed('a'),
      committed_at: '2026-09-24T00:01:00.000Z',
    }, 'public_index_entry_cid');
    assert.deepEqual(projectPublicationSnapshot(record,
      {kind: 'committed', entry: index}),
    {state: 'succeeded', evidenceCid: index.cid});
    assert.throws(() => projectPublicationSnapshot(undefined,
      {kind: 'committed', entry: index}),
    {code: 'RunHostPublicationSnapshotRejected'});
    assert.throws(() => projectPublicationSnapshot(record,
      {kind: 'committed', entry: record}),
    {code: 'RunHostPublicationSnapshotRejected'});
  });

test('portable Host uses the registered one-index-per-Run Store key', () => {
  const limits = {maxWireBytes: 4096, maxNodes: 128, maxDepth: 16};
  const ref = {namespaceId: 'namespace-a',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  const expected = cid({version: 'actql-public-index-key/0.1',
    namespace_id: ref.namespaceId,
    authority_scope_cid: ref.authorityScopeCid,
    run_definition_cid: ref.runDefinitionCid}).slice(7);
  assert.equal(publicationIndexScopeKey(ref, limits), expected);
  assert.notEqual(publicationIndexScopeKey({...ref,
    namespaceId: 'namespace-b'}, limits), expected);
  assert.throws(() => publicationIndexScopeKey({...ref,
    runDefinitionCid: 'invalid'}, limits),
  {code: 'RunHostPublicationIndexScopeRejected'});
});

test('portable Host derives logical identity from exact ordered rows', () => {
  const limits = {maxWireBytes: 4096, maxNodes: 100, maxDepth: 16};
  const rows = '[{"id":1},{"id":2}]';
  assert.deepEqual(inspectCanonicalResultRows(rows, ['id'], limits), {
    logicalRelationCid:
      'sha256:ffd3ea44b8fb5324bbdc17735e31f10e00f60e5debddd3be1957f712204f331f',
    rowCount: 2,
  });
  for (const body of ['[{"id":1}, {"id":2}]',
    '[{"id":1},{"other":2}]', '{"id":1}']) {
    assert.throws(() => inspectCanonicalResultRows(body, ['id'], limits),
    {code: 'RunHostResultRowsRejected'});
  }
  assert.throws(() => inspectCanonicalResultRows(rows, ['other'], limits),
    {code: 'RunHostResultRowsRejected'});
});

test('portable Host exposes the checked Values schema for row custody',
  () => {
    const environment = admitEnvironment(environmentWire, evidenceCid,
      {rela: true});
    const prepared = prepare(read('values.json'), 'json', environment);
    const compilation = compileValues(prepared);
    assert.deepEqual(resultSchema(prepared, compilation), {
      cid:
        'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513',
      wire: '{"id":{"nullable":false,"type":"number"}}',
      fields: ['id'],
    });
    const foreign = prepare(read('values.json').replace('"id": 2',
      '"id": 3'), 'json', environment);
    assert.throws(() => resultSchema(foreign, compilation),
      {name: 'TypeError', message: 'ForeignRunHostCompilation'});
  });

test('source-free Invocation binds checked Template and Host data policy',
  () => {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const environment = admitEnvironment(environmentWire, evidenceCid,
      {rela: true});
    const prepared = prepare(read('values.json'), 'json', environment);
    const compilation = compileValues(prepared);
    const allowed = issueAllowedRun(prepared, compilation, {
      executionContextCid: `sha256:${'a'.repeat(64)}`,
      hostPolicyCid: `sha256:${'b'.repeat(64)}`,
      expiresAt: '2099-01-01T00:00:00.000Z',
    });
    const definition = issueRunDefinition(allowed.admission,
      'namespace-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z');
    const dataPolicyCid = `sha256:${'d'.repeat(64)}`;
    const issued = issueSourceFreeInvocation(prepared, compilation,
      allowed.admission, definition, dataPolicyCid, limits);
    const templateCid = JSON.parse(privateCompilationWires(compilation)
      .boundTemplate).bound_invocation_template_cid;
    const observation = {
      version: 'actql-observation-set/0.1',
      invocation_template_cid: templateCid,
      source_evidence_cids: [], captured_input_artifact_cids: [],
      consistency: 'no_external_sources', capture_started_at: null,
      capture_completed_at: null,
      replayability: {materialized: false,
        availability_evidence_cids: []},
      data_policy_cid: dataPolicyCid,
    };
    assert.equal(issued.observation.cid, cid(observation));
    assert.equal(issued.invocation.cid, cid({
      version: 'actql-run-invocation/0.1',
      invocation_template_cid: templateCid,
      observation_set_cid: issued.observation.cid,
    }));
    assert.deepEqual(admitRunEvidenceValue('observation_set',
      issued.observation.wire, limits).cid, issued.observation.cid);
    assert.throws(() => issueSourceFreeInvocation(prepared, compilation,
      allowed.admission, definition, 'not-a-cid', limits),
    {code: 'RunHostInvocationRejected'});
    assert.throws(() => admitRunEvidenceValue('observation_set',
      issued.observation.wire.replace(dataPolicyCid,
        `sha256:${'e'.repeat(64)}`), limits),
    {code: 'RunHostEvidenceRejected'});
    const foreign = prepare(read('values.json').replace('"id": 2',
      '"id": 3'), 'json', environment);
    assert.throws(() => issueSourceFreeInvocation(foreign, compilation,
      allowed.admission, definition, dataPolicyCid, limits),
    {name: 'TypeError', message: 'ForeignRunHostCompilation'});
  });

test('portable Host issues a Manifest for exact admitted Result evidence',
  () => {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const fixed = value => `sha256:${value.repeat(64)}`;
    const admit = (name, body, identityField) => {
      const complete = {...body, [identityField]: cid(body)};
      return admitPublicationContract(name, JSON.stringify(complete), limits);
    };
    const run = admit('run_definition', {
      version: 'actql-run-definition/0.1', scope_id: 'scope', run_id: 'run',
      compiled_plan_cid: fixed('3'), invocation_template_cid: fixed('1'),
      authorization_context_cid: fixed('4'),
      input_artifact_set_cid: fixed('5'),
      created_at: '2026-09-18T00:00:00.000Z',
      valid_until: '2026-09-18T01:00:00.000Z',
    }, 'run_definition_cid');
    const invocation = admit('run_invocation', {
      version: 'actql-run-invocation/0.1',
      invocation_template_cid: fixed('1'),
      observation_set_cid: fixed('2'),
    }, 'invocation_cid');
    const definition = admit('result_definition', {
      version: 'actql-result-definition/0.1',
      program_definition_cid: fixed('6'), result_name: 'answer',
    }, 'result_definition_cid');
    const schemaWire = JSON.stringify({value: {nullable: false,
      type: 'integer'}});
    const schemaCid = cid(JSON.parse(schemaWire));
    const occurrence = issueResultOccurrenceEvidence(definition, {
      logicalValueCid: fixed('7'), resultSchemaCid: schemaCid,
      computationContractCid: fixed('3'), inputRelationCids: [],
      scopeCid: fixed('5'),
      effectiveDataPolicyCid: fixed('a'),
      issuerId: 'common-host', authorityScopeCid: fixed('d'),
    }, limits);
    const retention = admit('result_retention_policy', {
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: fixed('b'),
      effective_data_policy_cid: fixed('a'),
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T02:00:00.000Z',
      extension_ceiling_at: '2026-09-18T03:00:00.000Z',
      metadata_retention_policy_cid: fixed('c'),
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
      clock_contract_cid: fixed('d'),
    }, 'effective_retention_policy_cid');
    const artifact = issueCompleteResultArtifact(definition, invocation,
      occurrence, retention, 1, limits);
    assert.equal(JSON.parse(artifact.wire).ordering_evidence_cid,
      occurrence.ordering.cid);
    const physical = {codecContractCid: fixed('d'),
      resultFields: ['value'], resultSchemaWire: schemaWire,
      materialGenerationCid: fixed('e'), storeAuthorityCid: fixed('f'),
      rowCount: 1, byteCount: 10, physicalSha256: 'e'.repeat(64)};
    const binding = issueDurableResultBinding(run, definition,
      invocation, artifact, occurrence.ordering, retention, physical, limits);
    assert.equal(JSON.parse(binding.wire).run_definition_cid, run.cid);
    assert.equal(JSON.parse(binding.wire).logical_result_cid, fixed('7'));
    assert.throws(() => issueDurableResultBinding(run, definition,
      invocation, artifact, occurrence.ordering, retention,
      {...physical, rowCount: 2}, limits),
    {code: 'RunHostDurableBindingRejected'});
    const {effective_retention_policy_cid: _identity,
      ...retentionBody} = JSON.parse(retention.wire);
    assert.throws(() => issueCompleteResultArtifact(definition, invocation,
      occurrence, admit('result_retention_policy', {
        ...retentionBody, effective_data_policy_cid: fixed('f'),
      }, 'effective_retention_policy_cid'), 1, limits),
    {code: 'RunHostResultArtifactRejected'});
    const manifest = issueResultManifest(run, invocation, [definition],
      [artifact], limits);
    const readControl = openResultDeliveryControl();
    const publicIndex = readControl.admit('public_index_entry', JSON.stringify({
      version: 'actql-public-index-entry/0.1',
      namespace_id: 'namespace-a', authority_scope_cid: fixed('d'),
      run_definition_cid: run.cid, invocation_cid: invocation.cid,
      result_manifest_cid: manifest.cid, run_receipt_cid: fixed('1'),
      captured_run_cid: fixed('2'),
      durable_result_binding_cids: [binding.cid],
      publication_request_cid: fixed('8'),
      publication_attempt_cid: fixed('9'),
      committed_at: '2026-09-18T00:03:00.000Z',
      public_index_entry_cid: cid({
        version: 'actql-public-index-entry/0.1',
        namespace_id: 'namespace-a', authority_scope_cid: fixed('d'),
        run_definition_cid: run.cid, invocation_cid: invocation.cid,
        result_manifest_cid: manifest.cid, run_receipt_cid: fixed('1'),
        captured_run_cid: fixed('2'),
        durable_result_binding_cids: [binding.cid],
        publication_request_cid: fixed('8'),
        publication_attempt_cid: fixed('9'),
        committed_at: '2026-09-18T00:03:00.000Z',
      }),
    }), limits);
    const readManifest = readControl.admit('result_manifest',
      manifest.wire, limits);
    const retainedDescription = {
      programDefinitionCid: fixed('6'), resultDefinitionCid: definition.cid,
      resultArtifactCid: artifact.cid, resultSchemaCid: schemaCid,
      resultName: 'answer',
      columns: [{name: 'value', contract: {nullable: false, type: 'integer'}}],
      serialization: {format: 'jsonl', version: 'actql-jsonl/0.1',
        contractCid: cid({version: 'actql-jsonl/0.1'})},
    };
    assert.deepEqual(readControl.describeCommittedResult(publicIndex,
      readManifest, 'answer', [readControl.admit('durable_result_binding',
        binding.wire, limits)], readControl.admit('result_definition',
        definition.wire, limits), schemaWire, 'jsonl', limits),
    retainedDescription);
    const indexContract = admitPublicationContract('public_index_entry',
      publicIndex.wire, limits);
    assert.deepEqual(describeCommittedResult(indexContract, manifest,
      'answer', [binding], definition, schemaWire, 'jsonl', limits),
    retainedDescription);
    assert.throws(() => describeCommittedResult(indexContract, manifest,
      'answer', [], definition, schemaWire, 'jsonl', limits),
    {code: 'RunHostResultDescriptionRejected'});
    assert.throws(() => describeCommittedResult(indexContract, manifest,
      'answer', [binding], definition, '{}', 'jsonl', limits),
    {code: 'RunHostResultDescriptionRejected'});
    const metadataRetention = readControl.admit('result_retention_policy',
      retention.wire, limits);
    assert.equal(readControl.resultMetadataRetentionState(metadataRetention,
      '2026-09-18T02:30:00.000Z'), 'retained');
    assert.equal(readControl.resultMetadataRetentionState(metadataRetention,
      '2026-09-18T04:00:00.000Z'), 'delete_due');
    const metadataGrant = readControl.issueManifestReadGrant(publicIndex,
      readManifest, {principalId: 'reader', purpose: 'inspect',
        dataCeilingCid: fixed('a'), maxBytes: 1024, maxUses: 1,
        expiresAt: '2026-09-18T00:45:00.000Z',
        authorizationContextCid: fixed('4')}, limits);
    assert.equal(metadataGrant.name, 'manifest_read_grant');
    assert.equal(readControl.manifestReadGrantValidAt(metadataGrant,
      '2026-09-18T00:30:00.000Z'), true);
    assert.equal(readControl.manifestReadGrantValidAt(metadataGrant,
      '2026-09-18T00:45:00.001Z'), false);
    assert.equal(readControl.manifestReadGrantAllowsBytes(metadataGrant, 1024), true);
    assert.equal(readControl.manifestReadGrantAllowsBytes(metadataGrant, 1025), false);
    assert.throws(() => readControl.resultReadDefinitionCid({
      ...readManifest,
    }, 'answer'), {name: 'TypeError', message: 'ForeignRunHostDelivery'});
    assert.throws(() => readControl.resultReadDefinitionCid(publicIndex,
      'answer'), {code: 'RunHostDeliveryRejected'});
    const grant = readControl.issueResultReadGrant(publicIndex,
      readManifest, {resultNames: ['answer'], formats: ['jsonl'],
        principalId: 'reader', purpose: 'download',
        dataCeilingCid: fixed('a'), maxBytes: 1024, maxUses: 1,
        expiresAt: '2026-09-18T00:45:00.000Z',
        authorizationContextCid: fixed('4'),
        egressAdmissionCid: fixed('b')}, limits);
    assert.equal(grant.name, 'result_read_grant');
    assert.equal(readControl.resultReadGrantValidAt(grant,
      '2026-09-18T00:30:00.000Z'), true);
    const delivery = readControl.issueDeliveryAttempt(publicIndex,
      readManifest, grant, {resultName: 'answer', format: 'jsonl',
        attemptId: 'reader-1', requestedAt: '2026-09-18T00:31:00.000Z'},
      limits);
    assert.equal(delivery.name, 'delivery_attempt');
    const usage = readControl.prepareDeliveryGrantUsageClaim(grant,
      undefined, delivery, limits);
    assert.equal(usage.newlyClaimed, true);
    assert.equal(readControl.prepareDeliveryGrantUsageClaim(grant,
      usage.wire, delivery, limits).newlyClaimed, false);
    const another = readControl.issueDeliveryAttempt(publicIndex,
      readManifest, grant, {resultName: 'answer', format: 'jsonl',
        attemptId: 'reader-2', requestedAt: '2026-09-18T00:32:00.000Z'},
      limits);
    assert.throws(() => readControl.prepareDeliveryGrantUsageClaim(grant,
      usage.wire, another, limits), {code: 'RunHostDeliveryRejected'});
    assert.equal(readControl.deliveryResultDefinitionCid(readManifest,
      delivery), definition.cid);
    assert.throws(() => readControl.issueDeliveryAttempt(publicIndex,
      readManifest, grant, {resultName: 'foreign', format: 'jsonl',
        attemptId: 'reader-2', requestedAt: '2026-09-18T00:31:00.000Z'},
      limits), {code: 'RunHostDeliveryRejected'});
    assert.equal(resultReadAvailability(manifest, 'answer', retention,
      '2026-09-18T00:30:00.000Z'), 'available');
    assert.equal(resultReadAvailability(manifest, 'answer', retention,
      '2026-09-18T01:30:00.000Z'), 'retention_expired');
    assert.throws(() => resultReadAvailability(manifest, 'foreign',
      retention, '2026-09-18T00:30:00.000Z'),
    {code: 'RunHostAvailabilityRejected'});
    validatePublicationChain(run, invocation, [definition], [artifact],
      manifest, limits);
    assert.equal(JSON.parse(manifest.wire).results.answer
      .result_artifact_cid, artifact.cid);
    assert.throws(() => issueResultManifest(run, invocation, [definition],
      [], limits), {code: 'RunHostResultManifestRejected'});
    assert.throws(() => validatePublicationChain(run, invocation,
      [definition], [], manifest, limits),
    {code: 'RunHostPublicationChainRejected'});
    assert.throws(() => validatePublicationChain(run, invocation,
      [definition], [artifact], definition, limits),
    {code: 'RunHostPublicationChainRejected'});
    const request = issuePublicationRequest(run, [definition], {
      namespaceId: 'namespace-a', authorityScopeCid: fixed('d'),
      publicationPolicyCid: fixed('8'),
      publicationTargetCid: fixed('9'),
      requestedAt: '2026-09-18T00:01:00.000Z',
    }, limits);
    const requestBody = JSON.parse(request.wire);
    assert.deepEqual(requestBody.inventory, [{result_name: 'answer',
      result_definition_cid: definition.cid}]);
    assert.equal(requestBody.run_definition_cid, run.cid);
    const attempt = issuePublicationAttempt(request, run, {
      attemptId: 'attempt-1', fenceCid: fixed('a'),
      startedAt: '2026-09-18T00:02:00.000Z',
    }, limits);
    assert.equal(JSON.parse(attempt.wire).publication_request_cid,
      request.cid);
    const preparing = issuePublicationRecord(attempt, undefined, {
      state: 'preparing', observedAt: '2026-09-18T00:02:00.000Z',
      cleanupOwnerCids: [], uncommittedConfirmed: false,
    }, limits);
    assert.equal(JSON.parse(preparing.wire).sequence, 0);
    assert.equal(JSON.parse(preparing.wire).publication_attempt_cid,
      attempt.cid);
    assert.throws(() => issuePublicationAttempt(attempt, run, {
      attemptId: 'attempt-2', fenceCid: fixed('a'),
      startedAt: '2026-09-18T00:02:00.000Z',
    }, limits));
    assert.throws(() => issuePublicationRecord(request, undefined, {
      state: 'preparing', observedAt: '2026-09-18T00:02:00.000Z',
      cleanupOwnerCids: [], uncommittedConfirmed: false,
    }, limits));
    assert.throws(() => issuePublicationAttempt({
      token: {}, cid: request.cid, wire: request.wire,
    }, run, {
      attemptId: 'attempt-2', fenceCid: fixed('a'),
      startedAt: '2026-09-18T00:02:00.000Z',
    }, limits));
    assert.throws(() => issuePublicationRequest(run, [definition], {
      namespaceId: 'namespace-a', authorityScopeCid: fixed('d'),
      publicationPolicyCid: 'invalid', publicationTargetCid: fixed('9'),
      requestedAt: '2026-09-18T00:01:00.000Z',
    }, limits), {code: 'RunHostPublicationRequestRejected'});
    assert.throws(() => issuePublicationAttempt(request, definition, {
      attemptId: 'attempt-1', fenceCid: fixed('a'),
      startedAt: '2026-09-18T00:02:00.000Z',
    }, limits), {code: 'RunHostPublicationAttemptRejected'});
    assert.throws(() => issuePublicIndexEntry(run, invocation, manifest,
      artifact, artifact, [binding], request, attempt,
      '2026-09-18T00:03:00.000Z', limits),
    {code: 'RunHostPublicIndexEntryRejected'});
    assert.throws(() => validateEffectFreePublicationCommit({
      runDefinition: run, invocation, definitions: [definition],
      artifacts: [artifact], derivations: [occurrence.derivation],
      orderings: [occurrence.ordering], retentions: [retention],
      durableBindings: [binding], manifest, receipt: artifact,
      capturedRun: artifact,
    }, request, attempt, manifest, limits),
    {code: 'RunHostPublicationCommitRejected'});
  });

test('portable Host package compiles the ordinary Values Program', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  assert.deepEqual(executionShape(compilation), {
    planNodeId: 'values_0',
    outputContractCid:
      'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c',
    resultNames: ['answer'],
  });
  const definitions = resultDefinitions(prepared, compilation);
  const programCid = requestFields(prepareSourceFreeRequest(prepared,
    compilation, `sha256:${'a'.repeat(64)}`, 'inventory-request'))
    .programDefinitionCid;
  const definitionCid = cid({version: 'actql-result-definition/0.1',
    program_definition_cid: programCid, result_name: 'answer'});
  assert.deepEqual(definitions, [{
    name: 'answer',
    cid: definitionCid,
    wire: JSON.stringify({program_definition_cid: programCid,
      result_definition_cid: definitionCid,
      result_name: 'answer', version: 'actql-result-definition/0.1'}),
  }]);
  assert.throws(() => resultDefinitions(prepare(read('values.json'),
    'json', environment), compilation),
  {name: 'TypeError', message: 'ForeignRunHostCompilation'});
  const wires = privateCompilationWires(compilation);
  const plan = JSON.parse(wires.executablePlan);
  const facts = JSON.parse(wires.factManifest);
  const template = JSON.parse(wires.boundTemplate);
  const compiled = JSON.parse(wires.compiledPlan);
  assert.equal(plan.version, 'actql-executable-plan/0.1');
  assert.equal(plan.executable_plan_cid, without(plan, 'executable_plan_cid'));
  assert.equal(facts.plan_fact_manifest_cid,
    without(facts, 'plan_fact_manifest_cid'));
  assert.deepEqual(plan.plan_facts, facts.plan_facts);
  assert.deepEqual(plan.root_refs.map(root => root.name), ['answer']);
  const source = JSON.parse(read('values.json'));
  assert.equal(valuesResultPlan(valuesUnitIdentity(source, true)).result_plan_logical_cid,
    'sha256:8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38');
  assert.deepEqual(plan.execution_material.result_plan_logical_cids,
    {answer: valuesDependencyOracle().resultPlan});
  assert.equal(template.bound_invocation_template_cid,
    without(template, 'bound_invocation_template_cid'));
  assert.equal(compiled.compiled_plan_cid,
    without(compiled, 'compiled_plan_cid'));
  assert.equal(compiledPlanCid(compilation), compiled.compiled_plan_cid);
  assert.throws(() => compiledPlanCid({kind: 'values-compilation'}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.equal(compiled.executable_plan_cid, plan.executable_plan_cid);
  const aoaContract = JSON.parse(readFileSync(new URL(
    '../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  assert.equal(compiled.aoa_contract_cid,
    cid(aoaContract));
  assert.throws(() => compileValues({kind: 'prepared-program'}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('portable Host seals and admits exact Run evidence bodies', () => {
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const body = {version: 'actql-normalization-journal/0.1',
    rule_catalog_cid: `sha256:${'a'.repeat(64)}`, entries: []};
  const sealed = sealRunEvidenceValue('normalization_journal',
    JSON.stringify(body), limits);
  assert.equal(sealed.cid, cid(body));
  assert.equal(admitRunEvidenceValue('normalization_journal',
    sealed.wire, limits).cid, sealed.cid);
  assert.throws(() => sealRunEvidenceValue('normalization_journal',
    sealed.wire, limits), {code: 'RunHostEvidenceRejected'});
  assert.throws(() => sealRunEvidenceValue('normalization_journal',
    JSON.stringify({...body, entries: [{unexpected: true}]}), limits),
  {code: 'RunHostEvidenceRejected'});
});

test('checked Values Derivation binds the declared Result and Plan', () => {
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const result = resultDefinitions(prepared, compilation)[0];
  const definition = admitPublicationContract('result_definition',
    result.wire, limits);
  const schema = resultSchema(prepared, compilation);
  const fixed = digit => `sha256:${digit.repeat(64)}`;
  const facts = {logicalValueCid: fixed('1'), resultSchemaCid: schema.cid,
    scopeCid: fixed('2'), effectiveDataPolicyCid: fixed('3'),
    issuerId: 'common-host', authorityScopeCid: fixed('4')};
  const issued = issueCheckedValuesResultOccurrenceEvidence(prepared,
    compilation, definition, facts, limits);
  const derivation = JSON.parse(issued.derivation.wire);
  assert.equal(derivation.computation_contract_cid,
    compiledPlanCid(compilation));
  assert.equal(derivation.producer_contract_cid, definition.cid);
  assert.deepEqual(derivation.input_relation_cids, []);
  assert.equal(derivation.relation_schema_cid, schema.cid);
  assert.throws(() => issueCheckedValuesResultOccurrenceEvidence(prepared,
    compilation, definition, {...facts, resultSchemaCid: fixed('5')},
    limits), {code: 'RunHostCheckedResultEvidenceRejected'});
  const foreign = prepare(read('values.json').replace('"id": 2',
    '"id": 3'), 'json', environment);
  const foreignCompilation = compileValues(foreign);
  assert.notEqual(compiledPlanCid(foreignCompilation),
    compiledPlanCid(compilation));
  const foreignResult = resultDefinitions(foreign, foreignCompilation)[0];
  const foreignDefinition = admitPublicationContract('result_definition',
    foreignResult.wire, limits);
  assert.throws(() => issueCheckedValuesResultOccurrenceEvidence(prepared,
    compilation, foreignDefinition, facts, limits),
  {code: 'RunHostCheckedResultEvidenceRejected'});
  const wrongName = admitPublicationContract('result_definition',
    JSON.stringify({version: 'actql-result-definition/0.1',
      program_definition_cid: JSON.parse(definition.wire)
        .program_definition_cid,
      result_name: 'other',
      result_definition_cid: cid({version: 'actql-result-definition/0.1',
        program_definition_cid: JSON.parse(definition.wire)
          .program_definition_cid, result_name: 'other'})}), limits);
  assert.throws(() => issueCheckedValuesResultOccurrenceEvidence(prepared,
    compilation, wrongName, facts, limits),
  {code: 'RunHostCheckedResultEvidenceRejected'});
  assert.throws(() => issueCheckedValuesResultOccurrenceEvidence(prepared,
    foreignCompilation, definition, facts, limits),
  {name: 'TypeError', message: 'ForeignRunHostCompilation'});
});

test('portable Host rejects unadmitted environment and invalid Program', () => {
  assert.throws(() => admitEnvironment(environmentWire, evidenceCid,
    {rela: true, future: true}),
  {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
  assert.throws(() => admitEnvironment(environmentWire,
    `sha256:${'0'.repeat(64)}`, {rela: true}),
  {code: 'RunHostEnvironmentRejected'});
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  assert.throws(() => prepare('{"version":"actql/0.1"}', 'json',
    environment), {code: 'RunHostPreparationRejected'});
  assert.throws(() => prepare(read('values.json'), 'future', environment),
    {name: 'TypeError', message: 'InvalidRunHostPreparation'});
});

test('portable Host owns the exact checked logical request relation', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const document = read('values.json');
  const prepared = prepare(document, 'json', environment);
  const scope = `sha256:${'a'.repeat(64)}`;
  const input = `sha256:${'b'.repeat(64)}`;
  const first = prepareRequest(prepared, scope, 'saved-request', input);
  const fields = requestFields(first);
  assert.equal(fields.authorityScopeCid, scope);
  assert.equal(fields.requestId, 'saved-request');
  assert.equal(fields.callerInputIntentCid, input);
  assert.equal(fields.logicalRequestScopeCid, cid({
    version: 'actql-logical-request/0.1',
    authority_scope_cid: scope, caller_request_id: 'saved-request',
  }));
  assert.equal(fields.intentFingerprintCid, cid({
    version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: input,
    parameter_values_cid: fields.parameterValuesCid,
    program_definition_cid: fields.programDefinitionCid,
  }));
  const restored = admitRequestFields(fields);
  assert.equal(requestRelation(first, restored), 'same_request');
  assert.deepEqual(requestFields(restored), fields);
  const changed = prepare(document.replace('"id": 2', '"id": 3'),
    'json', environment);
  assert.equal(requestRelation(prepareRequest(changed, scope,
    'saved-request', input), restored), 'changed_intent');
  assert.equal(requestRelation(prepareRequest(prepared, scope,
    'other-request', input), restored), 'different_request');
  assert.throws(() => admitRequestFields({...fields,
    intentFingerprintCid: `sha256:${'0'.repeat(64)}`}),
  {code: 'RunHostRequestRecordRejected'});
  assert.throws(() => admitRequestFields({...fields, extra: true}),
    {name: 'TypeError', message: 'InvalidRunHostRequestRecord'});
  assert.throws(() => requestRelation({}, restored),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('source-free request admission pins no input, not explicit empty', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const scope = `sha256:${'a'.repeat(64)}`;
  const request = prepareSourceFreeRequest(prepared, compilation,
    scope, 'no-input-request');
  const fields = requestFields(request);
  assert.equal(fields.callerInputIntentCid, cid({
    version: 'actql-caller-input-intent/0.1', selection: 'none',
  }));
  assert.equal(requestRelation(request,
    admitSourceFreeRequestFields(prepared, compilation, fields)),
  'same_request');
  const explicitEmpty = cid({version: 'actql-caller-input-intent/0.1',
    selection: 'explicit', inputs: []});
  const altered = prepareRequest(prepared, scope, fields.requestId,
    explicitEmpty);
  assert.equal(requestRelation(request, altered), 'changed_intent');
  assert.throws(() => admitSourceFreeRequestFields(prepared, compilation,
    requestFields(altered)),
    {code: 'RunHostRequestRecordRejected'});
  const otherProgram = prepare(read('values.json').replace('"id": 2',
    '"id": 3'), 'json', environment);
  assert.throws(() => admitSourceFreeRequestFields(otherProgram,
    compileValues(otherProgram), fields),
  {code: 'RunHostRequestRecordRejected'});
  assert.throws(() => prepareSourceFreeRequest(prepared,
    compileValues(prepare(read('values.json'), 'json', environment)),
    scope, 'no-input-request'),
  {name: 'TypeError', message: 'ForeignRunHostCompilation'});
});

test('portable Host admits exact policy evidence before Run Definition', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const wires = privateCompilationWires(compilation);
  const template = JSON.parse(wires.boundTemplate);
  const compiled = JSON.parse(wires.compiledPlan);
  // The test Host supplies bounded policy evidence. This fixture does not
  // establish a product authorization policy or input selection contract.
  const contextCid = `sha256:${'a'.repeat(64)}`;
  const policyCid = `sha256:${'b'.repeat(64)}`;
  const evidence = (body, self) => JSON.stringify({...body,
    [self]: cid(body)});
  const preparedBody = {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: template.bound_invocation_template_cid,
    compiled_plan_cid: compiled.compiled_plan_cid,
    execution_context_cid: contextCid,
    host_policy_cid: policyCid,
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  };
  const authorizationBody = {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: cid(preparedBody),
    execution_context_cid: contextCid,
    host_policy_cid: policyCid,
    decision: 'allowed',
  };
  const admit = (p = preparedBody, a = authorizationBody) => admitRun(
    prepared, compilation, evidence(p, 'prepared_invocation_cid'),
    evidence(a, 'run_authorization_cid'));
  const admission = admit();
  const issued = issueAllowedRun(prepared, compilation, {
    executionContextCid: contextCid, hostPolicyCid: policyCid,
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  assert.deepEqual(JSON.parse(issued.preparedInvocationWire),
    JSON.parse(evidence(preparedBody, 'prepared_invocation_cid')));
  assert.deepEqual(JSON.parse(issued.authorizationWire),
    JSON.parse(evidence(authorizationBody, 'run_authorization_cid')));
  assert.deepEqual(privateRunDefinition(issueRunDefinition(issued.admission,
    'namespace-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')),
  privateRunDefinition(issueRunDefinition(admission,
    'namespace-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')));
  assert.throws(() => issueAllowedRun(prepared, compilation, {
    executionContextCid: `sha256:${'0'.repeat(64)}`,
    hostPolicyCid: 'not-a-cid',
    expiresAt: '2099-01-01T00:00:00.000Z',
  }), {code: 'RunHostAdmissionRejected'});
  const definition = privateRunDefinition(issueRunDefinition(admission,
    'namespace-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z'));
  const body = JSON.parse(definition.wire);
  assert.equal(body.run_id, 'values-run');
  assert.equal(body.compiled_plan_cid, compiled.compiled_plan_cid);
  assert.equal(body.invocation_template_cid,
    template.bound_invocation_template_cid);
  assert.equal(definition.cid, without(body, 'run_definition_cid'));
  const restoredDefinition = admitRunDefinition(definition.wire);
  assert.deepEqual(privateRunDefinition(restoredDefinition), definition);
  checkRunBinding(prepared, admission, restoredDefinition);
  assert.throws(() => checkRunBinding(
    prepare(read('values.json'), 'json', environment), admission,
    restoredDefinition),
  {name: 'TypeError', message: 'ForeignRunHostAdmission'});
  const request = prepareSourceFreeRequest(prepared, compilation, contextCid,
    'durable-run-request');
  const restoredRequest = admitSourceFreeRequestFields(prepared, compilation,
    requestFields(request));
  assert.equal(prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, false, true), 'reserve_dispatch');
  assert.equal(prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, true, true),
  'reconcile_reserved_dispatch');
  assert.throws(() => prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, false, false),
  {code: 'RunHostStartRejected'});
  assert.throws(() => prepareRunStart(request, restoredRequest,
    restoredDefinition, `sha256:${'0'.repeat(64)}`, false, true),
  {code: 'RunHostStartRejected'});
  assert.throws(() => admitRunDefinition(JSON.stringify({...body,
    run_id: 'foreign'})), {code: 'RunHostDefinitionRejected'});
  assert.throws(() => admit({...preparedBody,
    compiled_plan_cid: `sha256:${'0'.repeat(64)}`}),
  {code: 'RunHostAdmissionRejected'});
  assert.throws(() => admit(preparedBody, {...authorizationBody,
    decision: 'denied'}), {code: 'RunHostAdmissionRejected'});
  assert.throws(() => issueRunDefinition(admission,
    'namespace-scope', 'late-run', `sha256:${'c'.repeat(64)}`,
    '2099-01-01T00:00:00.000Z', '2100-01-01T00:00:00.000Z'),
  {code: 'RunHostDefinitionRejected'});
  assert.throws(() => issueRunDefinition({}, 'namespace-scope', 'foreign',
    `sha256:${'c'.repeat(64)}`, '2026-09-24T00:00:00.000Z',
    '2027-01-01T00:00:00.000Z'),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('checked Run issues one source-free Site dispatch identity', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const scope = `sha256:${'a'.repeat(64)}`;
  const policy = {executionContextCid: `sha256:${'b'.repeat(64)}`,
    hostPolicyCid: `sha256:${'c'.repeat(64)}`,
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const admission = issueAllowedRun(prepared, compilation, policy).admission;
  const definition = issueSourceFreeRunDefinition(prepared, compilation,
    admission, 'site-scope', 'site-run', '2026-09-25T00:00:00.000Z',
    '2027-01-01T00:00:00.000Z');
  assert.equal(JSON.parse(privateRunDefinition(definition).wire)
    .input_artifact_set_cid, cid({
    version: 'actql-initial-input-artifact-set/0.1',
    captured_artifact_cids: [],
  }));
  assert.deepEqual(privateRunDefinition(admitSourceFreeRunDefinition(
    prepared, compilation, admission, privateRunDefinition(definition).wire)),
  privateRunDefinition(definition));
  const substituted = issueRunDefinition(admission, 'site-scope',
    'substituted-run', `sha256:${'d'.repeat(64)}`,
    '2026-09-25T00:00:00.000Z', '2027-01-01T00:00:00.000Z');
  assert.throws(() => admitSourceFreeRunDefinition(prepared, compilation,
    admission, privateRunDefinition(substituted).wire),
  {code: 'RunHostSourceFreeAdmissionRejected'});
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, substituted, prepareSourceFreeRequest(prepared, compilation,
      scope, 'substituted-request'), {
      taskAttempt: 1, dispatchId: 'substituted-dispatch',
      siteKey: 'site-a', siteGeneration: 1,
      runtimeBundleCid: `sha256:${'1'.repeat(64)}`,
      connectorRegistration: 'local', connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
      obligationsCid: `sha256:${'2'.repeat(64)}`,
      budgetCid: `sha256:${'3'.repeat(64)}`,
      evidenceIssuerCapabilityCid: `sha256:${'4'.repeat(64)}`,
      grantCid: `sha256:${'5'.repeat(64)}`,
    }), {code: 'RunHostDispatchRejected'});
  const request = prepareSourceFreeRequest(prepared, compilation,
    scope, 'site-request');
  const selection = {taskAttempt: 1, dispatchId: 'site-dispatch',
    siteKey: 'site-a', siteGeneration: 1,
    runtimeBundleCid: `sha256:${'1'.repeat(64)}`,
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    obligationsCid: `sha256:${'2'.repeat(64)}`,
    budgetCid: `sha256:${'3'.repeat(64)}`,
    evidenceIssuerCapabilityCid: `sha256:${'4'.repeat(64)}`,
    grantCid: `sha256:${'5'.repeat(64)}`};
  const issued = issueSourceFreeDispatch(prepared, compilation, admission,
    definition, request, selection);
  {
    const dispatch = admitDispatchJson(issued.wire, issued.cid);
    const intent = prepareIntent(createJournal(scope), dispatch);
    const saved = admissionDurableJson(intent);
    const unstarted = projectSiteRun(prepared, compilation, admission,
      definition, scope, saved, '2026-09-25T00:00:01.000Z', false, false);
    assert.equal(unstarted.execution, 'unobserved');
    const started = projectSiteRun(prepared, compilation, admission,
      definition, scope, saved, '2026-09-25T00:00:01.000Z', false, true);
    assert.equal(started.execution, 'unknown');
    assert.equal(JSON.parse(started.stateWire).status, 'needs_reconciliation');
    assert.deepEqual(JSON.parse(started.stateWire).next_action,
      {kind: 'reconcile_run', reason: 'execution_unknown'});
  }
  for (const [execution, cleanup, outcome, work] of [
    [4, 2, 'failed', 'none'], [4, 1, 'failed', 'cleanup'],
    [5, 2, 'cancelled', 'none'], [6, 3, 'needs_reconciliation', 'reconcile'],
    [3, 0, 'running', 'publication'], [3, 2, 'running', 'publication'],
  ]) {
    const dispatch = admitDispatchJson(issued.wire, issued.cid);
    const intent = prepareIntent(createJournal(scope), dispatch);
    const durable = admitDurableJson(admissionDurableJson(intent));
    const record = commitIntent(intent);
    const response = admitResponseJson(JSON.stringify({
      version: 'actql-remote-dispatch-response/0.1',
      dispatch_request_cid: issued.cid, revision: 2,
      state: [execution, 0, cleanup, 0, 0],
    }), dispatch, false);
    const saved = responseDurableJson(durable,
      prepareResponseObservation(record, response), response);
    const observe = authority => projectSiteRun(prepared, compilation,
      admission, definition, authority, saved, '2026-09-25T00:00:01.000Z');
    const result = observe(scope);
    assert.equal(result.nextWork, work);
    assert.equal(JSON.parse(result.stateWire).status, outcome);
    assert(validRunState(JSON.parse(result.stateWire)));
    if (execution === 6) assert.deepEqual(JSON.parse(result.stateWire).next_action,
      {kind: 'reconcile_run', reason: 'execution_unknown'});
    const cancelled = projectSiteRun(prepared, compilation, admission,
      definition, scope, saved, '2026-09-25T00:00:01.000Z', true);
    if (execution === 3) {
      assert.equal(cancelled.nextWork, cleanup === 2 ? 'none' : 'release');
      assert.equal(JSON.parse(cancelled.stateWire).status,
        cleanup === 2 ? 'cancelled' : 'running');
    } else if (execution === 6) {
      assert.equal(cancelled.nextWork, 'cancel');
      assert.equal(cancelled.execution, 'unknown');
    }
    assert.deepEqual(observe(scope), result);
    assert.throws(() => observe(`sha256:${'f'.repeat(64)}`),
      {code: 'RunHostSiteProjectionRejected'});
    assert.throws(() => projectSiteRun(prepared, compilation, admission,
      substituted, scope, saved, '2026-09-25T00:00:01.000Z'));
  }
  const wire = JSON.parse(issued.wire);
  assert.equal(wire.run_definition_cid,
    privateRunDefinition(definition).cid);
  assert.equal(wire.task_key, 'values_0');
  assert.equal(wire.coordinator_authority, scope);
  assert.equal(wire.input_binding_cid, cid({}));
  assert.equal(dispatchCid(admitDispatchJson(issued.wire, issued.cid)),
    issued.cid);
  assert.throws(() => admitDispatchJson(issued.wire,
    `sha256:${'f'.repeat(64)}`), {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, definition, prepareRequest(prepared, scope, 'site-request',
      `sha256:${'e'.repeat(64)}`), selection),
  {code: 'RunHostDispatchRejected'});
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, definition, request,
    {...selection, connectorRegistration: 'duckdb'}),
  {code: 'RunHostDispatchRejected'});
  const foreign = prepare(read('values.json').replace('"id": 2', '"id": 3'),
    'json', environment);
  const foreignCompilation = compileValues(foreign);
  const foreignAdmission = issueAllowedRun(foreign, foreignCompilation,
    policy).admission;
  const foreignDefinition = issueSourceFreeRunDefinition(foreign,
    foreignCompilation, foreignAdmission, 'site-scope', 'foreign-run',
    '2026-09-25T00:00:00.000Z', '2027-01-01T00:00:00.000Z');
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, foreignDefinition, request, selection),
  {code: 'RunHostDispatchRejected'});
});

test('accepted unpublished Run state uses the common owner', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const admission = issueAllowedRun(prepared, compilation, {
    executionContextCid: `sha256:${'b'.repeat(64)}`,
    hostPolicyCid: `sha256:${'c'.repeat(64)}`,
    expiresAt: '2099-01-01T00:00:00.000Z',
  }).admission;
  const definition = issueSourceFreeRunDefinition(prepared, compilation,
    admission, 'site-scope', 'state-run', '2026-09-25T00:00:00.000Z',
    '2027-01-01T00:00:00.000Z');
  const request = prepareSourceFreeRequest(prepared, compilation,
    `sha256:${'a'.repeat(64)}`, 'cancel-request');
  const definitionCid = privateRunDefinition(definition).cid;
  assert.equal(prepareRunCancellation(definition, definitionCid,
    true, false, false), 'accepted');
  assert.equal(prepareRunCancellation(definition, definitionCid,
    true, false, true), 'already_requested');
  assert.equal(prepareRunCancellation(definition, definitionCid,
    true, true, true), 'already_terminal');
  assert.throws(() => prepareRunCancellation(definition, definitionCid,
    false, false, false), {code: 'RunHostCancellationRejected'});
  assert.throws(() => prepareRunCancellation(definition,
    `sha256:${'f'.repeat(64)}`, true, false, false),
  {code: 'RunHostCancellationRejected'});
  assert(prepareRunPhysicalStart(request, request, definition,
    definitionCid, true, true, true, false));
  assert(prepareRunPreStartFailure(request, request, definition,
    definitionCid, true, true, true, false));
  assert.equal(prepareRunPhysicalStart(request, request, definition,
    definitionCid, true, true, true, false, true), false);
  for (const [reserved, unstarted, denied, cancelled] of [
    [false, true, true, false], [true, false, true, false],
    [true, true, false, false], [true, true, true, true],
  ]) assert.equal(prepareRunPreStartFailure(request, request, definition,
    definitionCid, reserved, unstarted, denied, cancelled), false);
  assert.throws(() => prepareRunPreStartFailure(request, request, definition,
    `sha256:${'f'.repeat(64)}`, true, true, true, false),
  {code: 'RunHostStartRejected'});
  for (const [reserved, unstarted, cancelled] of [
    [true, true, true], [true, false, false], [false, true, false],
  ]) assert.equal(prepareRunPhysicalStart(request, request, definition,
    definitionCid, reserved, unstarted, true, cancelled), false);
  assert.deepEqual(issueRunControlObservation(3,
    {requested: true, unstarted: false, stopped: false}),
    {revision: 3, cancellation_requested: true, physical_stop: 'unknown'});
  assert.equal(issueRunControlObservation(4,
    {requested: true, unstarted: true, stopped: false}).physical_stop,
    'confirmed');
  assert.equal(JSON.parse(issueUnpublishedRunStateWire(prepared,
    compilation, admission, definition, '2026-09-25T00:00:01.000Z',
    {dispatchReserved: false, preDispatchFailureConfirmed: false,
      cancelledBeforeStart: true})).status, 'cancelled');
  const at = '2026-09-25T00:00:01.000Z';
  const projection = (reserved, failed) => JSON.parse(
    issueUnpublishedRunStateWire(prepared, compilation, admission,
      definition, at, {dispatchReserved: reserved,
        preDispatchFailureConfirmed: failed}));
  const preparing = projection(false, false);
  assert(validRunState(preparing));
  assert.equal(preparing.run_id, 'state-run');
  assert.equal(preparing.status, 'preparing');
  assert.equal(preparing.result_availability.answer.reason, 'not_published');
  assert.equal(projection(true, false).status, 'running');
  assert.equal(projection(true, true).status, 'failed');
  assert.throws(() => projection(false, true),
    {code: 'RunHostStateProjectionRejected'});
  assert.throws(() => issueUnpublishedRunStateWire(prepared, compilation,
    admission, definition, 'invalid', {dispatchReserved: false,
      preDispatchFailureConfirmed: false}),
  {code: 'RunHostStateProjectionRejected'});
  assert.throws(() => issueUnpublishedRunStateWire(prepared, compilation,
    admission, {}, at, {dispatchReserved: false,
      preDispatchFailureConfirmed: false}),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
  const succeeded = JSON.parse(issueSucceededRunStateWire(prepared,
    compilation, admission, definition, at, [{name: 'answer',
      state: 'unknown', reason: 'verification_pending', observedAt: at}]));
  assert(validRunState(succeeded));
  assert.equal(succeeded.status, 'succeeded');
  assert.equal(succeeded.result_availability.answer.state, 'unknown');
  assert.throws(() => issueSucceededRunStateWire(prepared, compilation,
    admission, definition, at, [{name: 'other', state: 'available',
      reason: 'confirmed_present', observedAt: at}]),
  {code: 'RunHostStateProjectionRejected'});
});

test('unresolved starting input cannot use the empty captured set', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const program = JSON.parse(read('values.json'));
  program.stages[0].inputs.required = 'relation';
  assert.throws(() => compileValues(prepare(JSON.stringify(program),
    'json', environment)), {code: 'RunHostPreparationRejected'});
});

test('Result generation holds retain two consumers and an active reader', () => {
  const binding = `sha256:${'a'.repeat(64)}`;
  const material = `sha256:${'b'.repeat(64)}`;
  const second = `sha256:${'c'.repeat(64)}`;
  const reader = `sha256:${'d'.repeat(64)}`;
  const begin = beginResultMaterialHolds(binding, material);
  const restored = admitResultMaterialHolds(resultMaterialHoldsWire(begin));
  assert.deepEqual(resultMaterialHoldsFacts(restored), {
    bindingCid: binding, materialGenerationCid: material,
    revision: 0, reclaimable: false});
  const two = prepareResultMaterialHoldsStep(restored,
    'add_consumer', second);
  const active = prepareResultMaterialHoldsStep(two,
    'begin_reader', reader);
  const one = prepareResultMaterialHoldsStep(active,
    'release_consumer', binding);
  const stopped = prepareResultMaterialHoldsStep(one,
    'stop_readers', '');
  assert.equal(resultMaterialHoldsFacts(stopped).reclaimable, false);
  assert.throws(() => prepareResultMaterialHoldsStep(stopped,
    'begin_reader', second), {code: 'RunHostDeliveryRejected'});
  const released = prepareResultMaterialHoldsStep(stopped,
    'release_consumer', second);
  assert.equal(resultMaterialHoldsFacts(released).reclaimable, false);
  const ended = prepareResultMaterialHoldsStep(released,
    'end_reader', reader);
  assert.equal(resultMaterialHoldsFacts(ended).reclaimable, true);
  assert.equal(resultMaterialHoldsWire(
    prepareResultMaterialHoldsStep(ended, 'end_reader', reader)),
  resultMaterialHoldsWire(ended));
});
