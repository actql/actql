import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});
const protocolSchemas = JSON.parse(readFileSync(new URL(
  '../../spec/contracts/actql-protocol-schemas.json', import.meta.url,
), 'utf8')).artifact_schemas;
const embeddedIdentity = Object.freeze({
  'actql-prepared-invocation/0.1': 'prepared_invocation_cid',
  'actql-run-authorization/0.1': 'run_authorization_cid',
  'actql-observation-set/0.1': 'observation_set_cid',
  'actql-result-artifact/0.1': 'result_artifact_cid',
  'actql-result-manifest/0.1': 'result_manifest_cid',
  'actql-source-evidence/0.1': 'source_evidence_cid',
  'actql-authoring-context/0.1': 'authoring_context_cid',
  'actql-model-invocation-evidence/0.1':
    'model_invocation_evidence_cid',
  'actql-run-effect-context/0.1': 'effect_context_cid',
});

const canonical = value => Array.isArray(value)
  ? value.map(canonical)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort()
      .map(key => [key, canonical(value[key])]))
    : value;
const canonicalCid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(canonical(value))).digest('hex')}`;
function sealEmbedded(value) {
  if (Array.isArray(value)) return value.map(sealEmbedded);
  if (value === null || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value)
    .map(([name, child]) => [name, sealEmbedded(child)]));
  const identity = embeddedIdentity[result.version];
  if (identity !== undefined) {
    delete result[identity];
    result[identity] = canonicalCid(result);
  }
  return result;
}
function minimumValue(schema) {
  if (schema.oneOf !== undefined) return minimumValue(schema.oneOf[0]);
  if (schema.const !== undefined) return schema.const;
  if (schema.enum !== undefined) return schema.enum[0];
  if (schema.type === undefined) return null;
  if (schema.type === 'null') return null;
  if (schema.type === 'boolean') return false;
  if (schema.type === 'integer') return schema.minimum ?? 0;
  if (schema.type === 'array') {
    return Array.from({length: schema.minItems ?? 0}, () =>
      minimumValue(schema.items ?? {}));
  }
  if (schema.type === 'object') {
    return Object.fromEntries((schema.required ?? []).map(name => [
      name, minimumValue(schema.properties[name]),
    ]));
  }
  if (schema.type === 'string') {
    if (schema.format === 'date-time' || schema.pattern?.includes('\\d{4}')) {
      return '2026-09-18T00:00:00.000Z';
    }
    if (schema.pattern?.startsWith('^sha256:')) return cid('c');
    if (schema.pattern === '^[0-9a-f]{64}$') return 'd'.repeat(64);
    return 'x'.repeat(Math.max(1, schema.minLength ?? 0));
  }
  throw new TypeError(`Unsupported fixture schema: ${schema.type}`);
}

function invocation(control) {
  return control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
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
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: cid('7'),
    relation_schema_cid: cid('8'),
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
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: cid('7'),
    result_schema_cid: cid('8'),
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
  const observation = sealEmbedded(minimumValue(
    protocolSchemas.run_receipt.properties.observation_set,
  ));
  observation.invocation_template_cid = cid('1');
  delete observation.observation_set_cid;
  observation.observation_set_cid = canonicalCid(observation);
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
  const invoked = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: observation.observation_set_cid,
  }), limits);
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
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: cid('7'),
    relation_schema_cid: cid('8'),
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
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: cid('7'),
    result_schema_cid: cid('8'),
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const artifactValue = JSON.parse(artifact.wire);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  const receiptValue = minimumValue(protocolSchemas.run_receipt);
  const prepared = receiptValue.prepared_invocation;
  prepared.invocation_template_cid = cid('1');
  prepared.compiled_plan_cid = cid('3');
  receiptValue.prepared_invocation = sealEmbedded(prepared);
  const authorization = receiptValue.run_authorization;
  authorization.prepared_invocation_cid =
    receiptValue.prepared_invocation.prepared_invocation_cid;
  authorization.execution_context_cid =
    receiptValue.prepared_invocation.execution_context_cid;
  authorization.host_policy_cid =
    receiptValue.prepared_invocation.host_policy_cid;
  receiptValue.run_authorization = sealEmbedded(authorization);
  receiptValue.program_definition_cid = cid('6');
  receiptValue.invocation_cid = invoked.identity;
  receiptValue.compiled_plan_cid = cid('3');
  receiptValue.observation_set = observation;
  receiptValue.observation_set_cid = observation.observation_set_cid;
  receiptValue.result_manifest = JSON.parse(manifest.wire);
  receiptValue.result_manifest_cid = manifest.identity;
  receiptValue.result_artifacts = {answer: artifactValue};
  receiptValue.source_evidence = [];
  receiptValue.source_evidence_cids = [];
  delete receiptValue.receipt_identity_cid;
  const receipt = control.seal(
    'run_receipt', JSON.stringify(receiptValue), limits,
  );
  const capturedValue = minimumValue(protocolSchemas.captured_run);
  capturedValue.receipt = JSON.parse(receipt.wire);
  const effect = capturedValue.effect_context;
  effect.effects = {};
  effect.effect_plans = {};
  effect.effect_plan_logical_cids = {};
  effect.result_values = {answer: null};
  effect.result_artifacts = {answer: artifactValue};
  effect.result_fields = {answer: []};
  effect.authoring_context.program_definition_cid = cid('6');
  effect.authoring_context = sealEmbedded(effect.authoring_context);
  effect.model_invocation_evidence = [];
  effect.model_invocation_evidence_cids = [];
  capturedValue.effect_context = sealEmbedded(effect);
  delete capturedValue.captured_run_cid;
  const captured = control.seal(
    'captured_run', JSON.stringify(capturedValue), limits,
  );
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
    manifest,
    receipt,
    captured,
    request,
    foreignDefinition,
  ]) {
    await store.putPublicationContract(contract.name, contract.wire);
  }
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
  const committed = await store.commitIndex(
    indexEntry.wire, required, evidence,
  );
  assert.equal(committed.committed, true);
  assert.deepEqual(await store.inspectCommittedIndex({
    tenantId: 'tenant-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), JSON.parse(indexEntry.wire));
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
