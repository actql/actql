import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {publishEffectFreeRun} from './run-publication.mjs';
import {publishCompletedEffectFreeRun} from
  './completed-run-publication.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});
const canonical = value => Array.isArray(value)
  ? value.map(canonical)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort()
      .map(key => [key, canonical(value[key])]))
    : value;
const canonicalCid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(canonical(value))).digest('hex')}`;

function invocation(control) {
  return control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
}

function deliveryRoot(control) {
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: cid('1'),
    invocation_cid: cid('2'),
    logical_result_cid: cid('3'),
    result_schema_cid: cid('4'),
    ordering_evidence_cid: cid('5'),
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('6'),
    effective_retention_policy_cid: cid('7'),
    provenance_evidence_cids: [cid('8')],
  }), limits);
  const manifest = control.seal('result_manifest', JSON.stringify({
    version: 'actql-result-manifest/0.1',
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    results: {answer: JSON.parse(artifact.wire)},
  }), limits);
  const index = control.seal('public_index_entry', JSON.stringify({
    version: 'actql-public-index-entry/0.1',
    tenant_id: 'tenant',
    authority_scope_cid: cid('a'),
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    result_manifest_cid: manifest.identity,
    run_receipt_cid: cid('b'),
    captured_run_cid: cid('c'),
    durable_result_binding_cids: [cid('d')],
    publication_request_cid: cid('e'),
    publication_attempt_cid: cid('f'),
    committed_at: '2026-09-18T00:00:00.000Z',
  }), limits);
  return {artifact, manifest, index};
}

test('installed publication control uses the portable contract owner', () => {
  const control = runtimeCore(moon).publicationControl;
  const sealed = invocation(control);
  assert.deepEqual(sealed, {
    name: 'run_invocation',
    identityField: 'invocation_cid',
    identity:
      'sha256:49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18',
    wire: '{"invocation_cid":"sha256:' +
      '49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18' +
      '","invocation_template_cid":"' + cid('1') +
      '","observation_set_cid":"' + cid('2') +
      '","version":"actql-run-invocation/0.1"}',
  });
  assert.deepEqual(
    control.admit('run_invocation', sealed.wire, limits),
    sealed,
  );
  assert.throws(
    () => control.recordAllowsCommit(Object.freeze({...sealed})),
    /Foreign publication contract/u,
  );
});

test('portable delivery owner binds grants attempts and receipts', () => {
  const control = runtimeCore(moon).publicationControl;
  const {artifact, manifest, index} = deliveryRoot(control);
  assert.equal(
    control.resultSerializationContractCid('json', limits),
    'sha256:f8a9922a194323d7b0f33733eb29753a6b68b48becee913cedb30a23a97cedf8',
  );
  const grant = control.issueResultReadGrant(index, manifest, {
    resultNames: ['answer'],
    formats: ['json', 'jsonl', 'csv'],
    principalId: 'principal',
    purpose: 'download',
    dataCeilingCid: cid('1'),
    maxBytes: 4096,
    maxUses: 2,
    expiresAt: '2026-09-19T00:00:00.000Z',
    authorizationContextCid: cid('2'),
    egressAdmissionCid: cid('3'),
  }, limits);
  assert.deepEqual(JSON.parse(grant.wire).results, [{
    result_artifact_cid: artifact.identity,
    result_name: 'answer',
  }]);
  const attempt = control.issueDeliveryAttempt(
    index,
    manifest,
    grant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'attempt-1',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  const streaming = control.issueDeliveryRecord(attempt, undefined, {
    state: 'streaming',
    confirmedByteCount: 0,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: undefined,
    receipt: undefined,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:00.000Z',
    cleanupOwnerCids: [],
  }, limits);
  const receipt = control.issueResultDeliveryReceipt(
    index,
    manifest,
    grant,
    attempt,
    {byteCount: 2, sha256: '0'.repeat(64)},
    limits,
  );
  const succeeded = control.issueDeliveryRecord(attempt, streaming, {
    state: 'succeeded',
    confirmedByteCount: 2,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: '0'.repeat(64),
    receipt,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:01.000Z',
    cleanupOwnerCids: [],
  }, limits);
  assert.equal(
    JSON.parse(succeeded.wire).result_delivery_receipt_cid,
    receipt.identity,
  );
});

test('portable delivery serializer owns the three canonical formats', () => {
  const control = runtimeCore(moon).publicationControl;
  const schema = JSON.stringify({
    amount: {nullable: false, precision: 4, scale: 2, type: 'decimal'},
    enabled: {nullable: false, type: 'boolean'},
    meta: {
      additional_properties: false,
      fields: {k: {nullable: false, type: 'string'}},
      nullable: false,
      type: 'object',
    },
    missing: {nullable: true, type: 'number'},
    name: {nullable: false, type: 'string'},
    score: {nullable: false, type: 'number'},
  });
  const fields = ['name', 'score', 'amount', 'enabled', 'missing', 'meta'];
  const row = JSON.stringify({
    amount: '2.30',
    enabled: false,
    meta: {k: 'é'},
    missing: null,
    name: 'x,"y',
    score: 1.5,
  });
  const expected =
    '{"name":"x,\\"y","score":1.5,"amount":"2.30",' +
    '"enabled":false,"missing":null,"meta":{"k":"é"}}';

  const serialize = format => {
    const serializer = control.prepareResultDeliverySerializer(
      format,
      schema,
      fields,
      limits,
    );
    return control.beginResultDelivery(serializer) +
      control.nextResultDeliveryRow(serializer, row) +
      control.finishResultDelivery(serializer);
  };

  assert.equal(serialize('json'), `[${expected}]`);
  assert.equal(serialize('jsonl'), `${expected}\n`);
  assert.equal(
    serialize('csv'),
    '"name","score","amount","enabled","missing","meta"\n' +
      '"x,""y",1.5,2.30,false,\\N,"{""k"":""é""}"\n',
  );
});

test('portable evidence owner issues Invocation after exact capture', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: cid('7'),
    }),
    limits,
  );
  assert.deepEqual(
    control.admitRunEvidence(template.name, template.wire, limits),
    template,
  );
  const issued = control.issueRunInvocation(template, observation, limits);
  assert.deepEqual(JSON.parse(issued.wire), {
    invocation_cid: issued.identity,
    invocation_template_cid: template.identity,
    observation_set_cid: observation.identity,
    version: 'actql-run-invocation/0.1',
  });
  const foreign = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      ...JSON.parse(template.wire),
      bound_invocation_template_cid: undefined,
      program_definition_cid: cid('8'),
    }),
    limits,
  );
  assert.throws(
    () => control.issueRunInvocation(foreign, observation, limits),
    {code: 'MoonBitHostFailure'},
  );
});

test('portable admission issues Run Definition from exact authority', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('1'),
    program_semantics_cid: cid('a'),
    aoa_contract_cid: cid('b'),
    aoa_logical_cid: cid('c'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const definition = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('a'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z',
  }, limits);
  assert.deepEqual(JSON.parse(definition.wire), {
    authorization_context_cid: cid('8'),
    compiled_plan_cid: compiledPlan.identity,
    created_at: '2026-09-18T00:00:00.000Z',
    input_artifact_set_cid: cid('a'),
    invocation_template_cid: template.identity,
    run_definition_cid: definition.identity,
    run_id: 'run',
    scope_id: 'scope',
    valid_until: '2026-09-18T02:00:00.000Z',
    version: 'actql-run-definition/0.1',
  });
  assert.throws(
    () => control.issueRunDefinition(
      Object.freeze({kind: 'run-publication-admission'}),
      {
        scopeId: 'scope',
        runId: 'run',
        inputArtifactSetCid: cid('a'),
        createdAt: '2026-09-18T00:00:00.000Z',
        validUntil: '2026-09-18T02:00:00.000Z',
      },
      limits,
    ),
    /Foreign Run publication admission/u,
  );
});

test('portable control validates the exact Run Result publication chain', () => {
  const control = runtimeCore(moon).publicationControl;
  const run = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1',
    scope_id: 'scope',
    run_id: 'run',
    compiled_plan_cid: cid('3'),
    invocation_template_cid: cid('1'),
    authorization_context_cid: cid('4'),
    input_artifact_set_cid: cid('5'),
    created_at: '2026-09-18T00:00:00.000Z',
    valid_until: '2026-09-18T01:00:00.000Z',
  }), limits);
  const invoked = invocation(control);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  assert.equal(control.runChainValid(
    run, invoked, [definition], [artifact], manifest, limits,
  ), true);
  assert.equal(control.runChainValid(
    run, invoked, [definition], [], manifest, limits,
  ), false);
});

test('portable control validates Receipt and Captured Run references',
  async t => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('6'),
      parameter_values_cid: cid('1'),
      invocation_bindings_cid: cid('2'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('7'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('6'),
    program_semantics_cid: cid('e'),
    aoa_contract_cid: cid('d'),
    aoa_logical_cid: cid('f'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const run = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('5'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T01:00:00.000Z',
  }, limits);
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: cid('a'),
    }),
    limits,
  );
  const invoked = control.issueRunInvocation(template, observation, limits);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal',
    JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('c'),
      entries: [],
    }),
    limits,
  );
  const receipt = control.issueEffectFreeRunReceipt({
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
  }, {
    normalizationJournal,
    bindings: [],
    sourceEvidence: [],
    modelEvidence: [],
    barrierAttemptReceiptCids: [],
  }, limits);
  const authoringContext = control.sealRunEvidence(
    'authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('6'),
      annotations: [],
    }),
    limits,
  );
  const snapshot = control.admitCapturedResultSnapshot(
    definition,
    artifact,
    JSON.stringify(resultRows),
    ['value'],
    limits,
  );
  const captured = control.issueEffectFreeCapturedRun({
    runDefinition: run,
    invocation: invoked,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
    receipt,
  }, {
    snapshots: [snapshot],
    pendingSourceStateAdvances: [],
    authoringContext,
    modelEvidence: [],
  }, limits);
  const payloadWire = JSON.stringify(resultRows);
  const payloadBytes = Buffer.byteLength(payloadWire, 'utf8');
  const physicalCid = `sha256:${createHash('sha256')
    .update(payloadWire).digest('hex')}`;
  const binding = control.issueDurableResultBinding({
    runDefinition: run,
    definition,
    invocation: invoked,
    artifact,
    ordering,
    retention,
  }, {
    codecContractCid: cid('b'),
    materialGenerationCid: physicalCid,
    storeAuthorityCid: cid('a'),
    rowCount: 1,
    byteCount: payloadBytes,
    physicalSha256: physicalCid.slice(7),
  }, limits);
  const request = control.issuePublicationRequest(run, [definition], {
    tenantId: 'tenant-a',
    authorityScopeCid: cid('d'),
    publicationPolicyCid: cid('e'),
    publicationTargetCid: cid('f'),
    requestedAt: '2026-09-18T00:00:00.000Z',
  }, limits);
  const attempt = control.issuePublicationAttempt(request, run, {
    attemptId: 'attempt-1',
    fenceCid: cid('0'),
    startedAt: '2026-09-18T00:00:01.000Z',
  }, limits);
  const indexEntry = control.issuePublicIndexEntry({
    runDefinition: run,
    invocation: invoked,
    manifest,
    receipt,
    capturedRun: captured,
    durableBindings: [binding],
    request,
    attempt,
  }, '2026-09-18T00:00:02.000Z', limits);
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), true);
  assert.equal(control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    indexEntry,
    limits,
  ), true);
  const foreignDefinition = control.seal(
    'result_definition',
    JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: cid('f'),
      result_name: 'answer',
    }),
    limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [foreignDefinition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), false);
  const wrongReceiptValue = JSON.parse(receipt.wire);
  delete wrongReceiptValue.receipt_identity_cid;
  wrongReceiptValue.compiled_plan_cid = cid('e');
  const wrongReceipt = control.seal(
    'run_receipt', JSON.stringify(wrongReceiptValue), limits,
  );
  const wrongReceiptCaptureValue = JSON.parse(captured.wire);
  delete wrongReceiptCaptureValue.captured_run_cid;
  wrongReceiptCaptureValue.receipt = JSON.parse(wrongReceipt.wire);
  const wrongReceiptCapture = control.seal(
    'captured_run', JSON.stringify(wrongReceiptCaptureValue), limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    wrongReceipt,
    wrongReceiptCapture,
    limits,
  ), false);
  const wrongInventoryValue = JSON.parse(captured.wire);
  delete wrongInventoryValue.captured_run_cid;
  const wrongEffect = wrongInventoryValue.effect_context;
  delete wrongEffect.effect_context_cid;
  wrongEffect.result_values = {foreign: null};
  wrongEffect.effect_context_cid = canonicalCid(wrongEffect);
  const wrongInventoryCapture = control.seal(
    'captured_run', JSON.stringify(wrongInventoryValue), limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    wrongInventoryCapture,
    limits,
  ), false);
  const wrongIndex = control.seal('public_index_entry', JSON.stringify({
    ...JSON.parse(indexEntry.wire),
    public_index_entry_cid: undefined,
    result_manifest_cid: cid('0'),
  }), limits);
  assert.equal(control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    wrongIndex,
    limits,
  ), false);
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-chain-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  t.after(async () => { await store.close(); });
  for (const contract of [
    run,
    invoked,
    definition,
    artifact,
    derivation,
    ordering,
    retention,
    binding,
    manifest,
    receipt,
    captured,
    request,
    foreignDefinition,
  ]) {
    await store.putPublicationContract(contract.name, contract.wire);
  }
  await store.putSemantic(resultSchemaWire, resultSchemaCid);
  await store.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  await store.createAttempt(attempt.wire);
  const preparing = control.issuePublicationRecord(attempt, undefined, {
    state: 'preparing',
    observedAt: '2026-09-18T00:00:03.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(preparing.wire, {
    uncommittedConfirmed: false,
  });
  const committing = control.issuePublicationRecord(attempt, preparing, {
    state: 'committing',
    observedAt: '2026-09-18T00:00:04.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(committing.wire, {
    uncommittedConfirmed: false,
  });
  const evidence = Object.freeze({
    runDefinition: run,
    invocation: invoked,
    definitions: Object.freeze([definition]),
    artifacts: Object.freeze([artifact]),
    derivations: Object.freeze([derivation]),
    orderings: Object.freeze([ordering]),
    retentions: Object.freeze([retention]),
    durableBindings: Object.freeze([binding]),
    manifest,
    receipt,
    capturedRun: captured,
  });
  const required = [...new Set([
    run.identity,
    invoked.identity,
    definition.identity,
    artifact.identity,
    derivation.identity,
    ordering.identity,
    retention.identity,
    binding.identity,
    manifest.identity,
    receipt.identity,
    captured.identity,
    request.identity,
    attempt.identity,
  ])];
  const foreignEvidence = Object.freeze({
    ...evidence,
    definitions: Object.freeze([foreignDefinition]),
  });
  await assert.rejects(store.commitIndex(
    indexEntry.wire,
    [...new Set([...required, foreignDefinition.identity])],
    foreignEvidence,
  ), error => error?.code === 'InvalidPublicationCommitChain');
  const times = [
    '2026-09-18T00:00:05.000Z',
    '2026-09-18T00:00:06.000Z',
  ];
  const publicationOptions = {
    store,
    control,
    evidence,
    request: {
      tenantId: 'tenant-a',
      authorityScopeCid: cid('d'),
      publicationPolicyCid: cid('e'),
      publicationTargetCid: cid('f'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    },
    attempt: {
      attemptId: 'attempt-1',
      fenceCid: cid('0'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    },
    limits,
    now: () => times.shift() ?? '2026-09-18T00:00:07.000Z',
    signal: undefined,
  };
  let exportedResults = 0;
  const execution = Object.freeze({
    status: 'host-tasks-completed',
    resultInventory: Object.freeze([{name: 'answer', task: 1}]),
    publicationInventory: Object.freeze({
      occurrences: Object.freeze([Object.freeze({
        name: 'answer',
        task: 1,
        definitionContract: definition,
      })]),
    }),
    async storePublicationResult(index, target, supplied) {
      exportedResults++;
      assert.equal(index, 0);
      assert.equal(target, store);
      assert.equal(supplied.runDefinition, run);
      assert.equal(supplied.invocation, invoked);
      assert.equal(supplied.retention, retention);
      return Object.freeze({
        occurrence: Object.freeze({
          name: 'answer', task: 1, definition,
        }),
        physical: Object.freeze({cid: physicalCid, bytes: payloadBytes}),
        orderedRows: Object.freeze({rows: 1}),
        publication: Object.freeze({
          derivation,
          ordering,
          artifact,
          snapshot,
          durableBinding: binding,
        }),
      });
    },
  });
  const completedPublicationOptions = {
    execution,
    store,
    control,
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    normalizationJournal,
    authoringContext,
    results: [{retention, evidenceContext: {}}],
    receiptEvidence: {
      bindings: [],
      sourceEvidence: [],
      modelEvidence: [],
      barrierAttemptReceiptCids: [],
    },
    captureEvidence: {
      pendingSourceStateAdvances: [],
      modelEvidence: [],
    },
    request: publicationOptions.request,
    attempt: publicationOptions.attempt,
    outputLimits: {},
    contractLimits: limits,
    now: () => '2026-09-18T00:00:05.000Z',
    signal: undefined,
  };
  await assert.rejects(publishCompletedEffectFreeRun({
    ...completedPublicationOptions,
    results: [],
  }), {code: 'InvalidCompletedRunPublicationOptions'});
  assert.equal(exportedResults, 0);
  const assembled = await publishCompletedEffectFreeRun(
    completedPublicationOptions,
  );
  assert.equal(exportedResults, 1);
  assert.equal(assembled.evidence.manifest.identity, manifest.identity);
  assert.equal(assembled.evidence.receipt.identity, receipt.identity);
  assert.equal(assembled.evidence.capturedRun.identity, captured.identity);
  const committed = assembled.publication;
  assert.equal(committed.state, 'succeeded');
  assert.equal(committed.committed, true);
  assert.equal(committed.idempotent, false);
  assert.deepEqual(await store.inspectCommittedIndex({
    tenantId: 'tenant-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), JSON.parse(committed.index.wire));
  const retried = await publishEffectFreeRun(publicationOptions);
  assert.equal(retried.state, 'succeeded');
  assert.equal(retried.committed, false);
  assert.equal(retried.idempotent, true);
  assert.equal(retried.index.identity, committed.index.identity);

  const lostDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-lost-response-',
  ));
  t.after(() => rm(lostDirectory, {recursive: true, force: true}));
  const lostBase = await openLocalPublicationStore({
    directory: lostDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await lostBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await lostBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await lostBase.close(); });
  let loseCommitResponse = true;
  const lostStore = Object.freeze({
    ...lostBase,
    async commitIndex(...arguments_) {
      const value = await lostBase.commitIndex(...arguments_);
      if (loseCommitResponse) {
        loseCommitResponse = false;
        throw new Error('simulated lost commit response');
      }
      return value;
    },
  });
  const lost = await publishEffectFreeRun({
    ...publicationOptions,
    store: lostStore,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'lost-response-attempt',
    },
  });
  assert.equal(lost.state, 'succeeded');
  assert.equal(lost.committed, false);
  assert.equal(lost.idempotent, true);
  assert.equal((await lostBase.latestRecord(lost.attempt.identity)).state,
    'succeeded');

  const raceDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-race-',
  ));
  t.after(() => rm(raceDirectory, {recursive: true, force: true}));
  const raceBase = await openLocalPublicationStore({
    directory: raceDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await raceBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await raceBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await raceBase.close(); });
  let commitArrivals = 0;
  let releaseCommits;
  const commitsReady = new Promise(resolve => { releaseCommits = resolve; });
  const raceStore = Object.freeze({
    ...raceBase,
    async commitIndex(...arguments_) {
      commitArrivals++;
      if (commitArrivals === 2) releaseCommits();
      await commitsReady;
      return raceBase.commitIndex(...arguments_);
    },
  });
  const raceAttempts = ['race-a', 'race-b'].map(attemptId => ({
    ...publicationOptions.attempt,
    attemptId,
  }));
  const raced = await Promise.all(raceAttempts.map(attempt =>
    publishEffectFreeRun({...publicationOptions, store: raceStore, attempt})));
  assert.equal(raced.filter(value => value.committed).length, 1);
  assert.equal(raced.filter(value => value.idempotent).length, 1);
  assert.equal(raced[0].index.identity, raced[1].index.identity);
  assert.equal(raced[0].attempt.identity, raced[1].attempt.identity);
  const raceContracts = raceAttempts.map(attempt =>
    control.issuePublicationAttempt(request, run, attempt, limits));
  const raceStates = await Promise.all(raceContracts.map(attempt =>
    raceBase.latestRecord(attempt.identity)));
  assert.deepEqual(
    raceStates.map(value => value.state).sort(),
    ['cancelled', 'succeeded'],
  );

  const unknownDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-unknown-',
  ));
  t.after(() => rm(unknownDirectory, {recursive: true, force: true}));
  const unknownBase = await openLocalPublicationStore({
    directory: unknownDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await unknownBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await unknownBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await unknownBase.close(); });
  let indexInspections = 0;
  const unknownStore = Object.freeze({
    ...unknownBase,
    async confirmCommittedIndex(...arguments_) {
      indexInspections++;
      if (indexInspections > 1) throw new Error('index unavailable');
      return unknownBase.confirmCommittedIndex(...arguments_);
    },
    async commitIndex() { throw new Error('commit outcome unavailable'); },
  });
  const unknownAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'unknown-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: unknownStore,
    attempt: unknownAttempt,
  }), error => error?.code === 'RunPublicationUnknown' &&
    error.publicationState === 'publication_unknown');
  const unknownContract = control.issuePublicationAttempt(
    request, run, unknownAttempt, limits,
  );
  assert.equal((await unknownBase.latestRecord(unknownContract.identity)).state,
    'publication_unknown');
  const reconciled = await publishEffectFreeRun({
    ...publicationOptions,
    store: unknownBase,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'reconciled-attempt',
    },
  });
  assert.equal(reconciled.state, 'succeeded');

  const cancelledDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-cancelled-',
  ));
  t.after(() => rm(cancelledDirectory, {recursive: true, force: true}));
  const cancelledBase = await openLocalPublicationStore({
    directory: cancelledDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await cancelledBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await cancelledBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await cancelledBase.close(); });
  const cancellation = new AbortController();
  const cancelledStore = Object.freeze({
    ...cancelledBase,
    async appendRecord(wire, options) {
      const value = await cancelledBase.appendRecord(wire, options);
      if (value.state === 'preparing') cancellation.abort();
      return value;
    },
  });
  const cancelledAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'cancelled-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: cancelledStore,
    attempt: cancelledAttempt,
    signal: cancellation.signal,
  }), {name: 'AbortError'});
  const cancelledContract = control.issuePublicationAttempt(
    request, run, cancelledAttempt, limits,
  );
  assert.equal((await cancelledBase.latestRecord(
    cancelledContract.identity,
  )).state, 'cancelled');
});

test('local durable Store accepts only MoonBit-admitted contract wire',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-runtime-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cid('a'),
      capacityBytes: 1024 * 1024,
      maxObjectBytes: limits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, control);
    t.after(async () => { await store.close(); });
    const sealed = invocation(control);
    const stored = await store.putPublicationContract(
      sealed.name, sealed.wire,
    );
    assert.equal(stored.semanticCid, sealed.identity);
    assert.deepEqual(
      await store.readJsonObject(sealed.identity, sealed.name),
      JSON.parse(sealed.wire),
    );
  });

test('complete publication reclaims prepared payloads after a later export fails',
  async () => {
    const definition = Object.freeze({
      name: 'result_definition', identity: cid('1'), wire: '{}',
    });
    const runDefinition = Object.freeze({
      name: 'run_definition', identity: cid('2'), wire: '{}',
    });
    const invoked = Object.freeze({
      name: 'run_invocation', identity: cid('3'), wire: '{}',
    });
    const retention = Object.freeze({
      name: 'result_retention_policy', identity: cid('4'), wire: '{}',
    });
    let pending = true;
    let releases = 0;
    const prepared = Object.freeze({
      status: () => Object.freeze({pending, errors: Object.freeze([])}),
      async release() { releases++; pending = false; return true; },
      async retry() { pending = false; return this.status(); },
    });
    const publication = Object.freeze({
      artifact: definition,
      derivation: definition,
      ordering: definition,
      durableBinding: definition,
      snapshot: Object.freeze({}),
    });
    const occurrences = Object.freeze([0, 1].map((_, index) =>
      Object.freeze({
        name: `result-${index}`,
        task: index + 1,
        definitionContract: definition,
      })));
    const execution = Object.freeze({
      status: 'host-tasks-completed',
      resultInventory: occurrences,
      publicationInventory: Object.freeze({occurrences}),
      async storePublicationResult(index) {
        if (index === 1) throw new Error('second export failed');
        return Object.freeze({
          occurrence: Object.freeze({
            name: 'result-0', task: 1, definition,
          }),
          publication,
          prepared,
        });
      },
    });
    const control = Object.freeze({
      issueResultManifest() { assert.fail('Manifest must not be issued'); },
      issueEffectFreeRunReceipt() { assert.fail('Receipt must not be issued'); },
      issueEffectFreeCapturedRun() {
        assert.fail('Captured Run must not be issued');
      },
    });
    await assert.rejects(publishCompletedEffectFreeRun({
      execution,
      store: Object.freeze({}),
      control,
      admission: Object.freeze({}),
      runDefinition,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: [0, 1].map(() => ({
        retention,
        evidenceContext: Object.freeze({}),
      })),
      receiptEvidence: {
        bindings: [], sourceEvidence: [], modelEvidence: [],
        barrierAttemptReceiptCids: [],
      },
      captureEvidence: {
        pendingSourceStateAdvances: [], modelEvidence: [],
      },
      request: Object.freeze({}),
      attempt: Object.freeze({}),
      outputLimits: Object.freeze({}),
      contractLimits: Object.freeze({}),
      now: () => '2026-09-18T00:00:00.000Z',
      signal: undefined,
    }), /second export failed/u);
    assert.equal(releases, 1);
    assert.equal(pending, false);
  });
