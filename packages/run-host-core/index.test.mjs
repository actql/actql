import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {validRunState} from '../client-wire/index.mjs';
import {admitDispatchJson, dispatchCid} from '../coordinator-core/index.mjs';
import {admitEnvironment, admitRequestFields, admitRunDefinition,
  admitSourceFreeRunDefinition,
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
  taskResultDefinitions, taskResultSchema,
  issueAllowedTaskRun, admitTaskRun, issueTaskRunDefinition,
  admitTaskRunDefinition,
  checkRunBinding, issueAllowedRun, issueRunDefinition,
  issueSourceFreeRunDefinition, prepare, prepareRequest,
  issueSourceFreeDispatch,
  executionShape,
  resultDefinitions, resultSchema,
  issueSourceFreeInvocation,
  admitCompletedSourceObservation,
  issueTaskInvocation,
  issueUnpublishedRunStateWire, issueSucceededRunStateWire,
  resultReadAvailability,
  prepareRunStart,
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
  const limits = {maxWireBytes: 8192, maxNodes: 256, maxDepth: 16};
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

test('portable delivery control keeps progress and serializer opaque', () => {
  const control = openResultDeliveryControl();
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const progress = control.beginResultAccessProgress();
  assert.equal(control.resultAccessProgressAction(progress), 0);
  assert.equal(control.recordResultAccessRequestAuthorization(progress,
    true), true);
  assert.equal(control.resultAccessProgressAction(progress), 1);
  assert.throws(() => control.resultAccessProgressAction({}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
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
      version: 'actql-public-index-entry/0.1', tenant_id: 'tenant-a',
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
  const ref = {tenantId: 'tenant-a',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  const expected = cid({version: 'actql-public-index-key/0.1',
    tenant_id: ref.tenantId,
    authority_scope_cid: ref.authorityScopeCid,
    run_definition_cid: ref.runDefinitionCid}).slice(7);
  assert.equal(publicationIndexScopeKey(ref, limits), expected);
  assert.notEqual(publicationIndexScopeKey({...ref,
    tenantId: 'tenant-b'}, limits), expected);
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
      'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
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
      tenant_id: 'tenant-a', authority_scope_cid: fixed('d'),
      run_definition_cid: run.cid, invocation_cid: invocation.cid,
      result_manifest_cid: manifest.cid, run_receipt_cid: fixed('1'),
      captured_run_cid: fixed('2'),
      durable_result_binding_cids: [binding.cid],
      publication_request_cid: fixed('8'),
      publication_attempt_cid: fixed('9'),
      committed_at: '2026-09-18T00:03:00.000Z',
      public_index_entry_cid: cid({
        version: 'actql-public-index-entry/0.1',
        tenant_id: 'tenant-a', authority_scope_cid: fixed('d'),
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
      tenantId: 'tenant-a', authorityScopeCid: fixed('d'),
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
    assert.throws(() => issuePublicationRequest(run, [definition], {
      tenantId: 'tenant-a', authorityScopeCid: fixed('d'),
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
  assert.deepEqual(plan.execution_material.result_plan_logical_cids,
    {answer: 'sha256:d55633378a13c8b55ac9dcd275459728a00e837f365dbc315cd6a865d583426e'});
  assert.equal(template.bound_invocation_template_cid,
    without(template, 'bound_invocation_template_cid'));
  assert.equal(compiled.compiled_plan_cid,
    without(compiled, 'compiled_plan_cid'));
  assert.equal(compiledPlanCid(compilation), compiled.compiled_plan_cid);
  assert.throws(() => compiledPlanCid({kind: 'values-compilation'}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
  assert.equal(compiled.executable_plan_cid, plan.executable_plan_cid);
  assert.equal(compiled.aoa_contract_cid,
    'sha256:4b6f51d57ca1d3cb16e28e04eeef20bebee34d4d3b89271de84b982a8ac74005');
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
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')),
  privateRunDefinition(issueRunDefinition(admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')));
  assert.throws(() => issueAllowedRun(prepared, compilation, {
    executionContextCid: `sha256:${'0'.repeat(64)}`,
    hostPolicyCid: 'not-a-cid',
    expiresAt: '2099-01-01T00:00:00.000Z',
  }), {code: 'RunHostAdmissionRejected'});
  const definition = privateRunDefinition(issueRunDefinition(admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
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
    'tenant-scope', 'late-run', `sha256:${'c'.repeat(64)}`,
    '2099-01-01T00:00:00.000Z', '2100-01-01T00:00:00.000Z'),
  {code: 'RunHostDefinitionRejected'});
  assert.throws(() => issueRunDefinition({}, 'tenant-scope', 'foreign',
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
  const at = '2026-09-25T00:00:01.000Z';
  const projection = (reserved, failed) => JSON.parse(
    issueUnpublishedRunStateWire(prepared, compilation, admission,
      definition, at, reserved, failed));
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
    admission, definition, 'invalid', false, false),
  {code: 'RunHostStateProjectionRejected'});
  assert.throws(() => issueUnpublishedRunStateWire(prepared, compilation,
    admission, {}, at, false, false),
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
