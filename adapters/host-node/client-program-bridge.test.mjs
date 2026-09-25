import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {applyCapturedEffectSet, applyRecoveredEffectSet} from
  './effect-run-apply.mjs';
import {accountEntry, FIXTURE_CONTEXT, fixtureAuthorization} from
  './authorization-fixture.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';
import {captureSalesforceCollectionEffectWrite,
  captureSalesforceSingleEffectWrite,
  recoverPreparedSalesforceSingleRequests,
  recoverCapturedSalesforceSingleRequests} from
  './salesforce-effect-write.mjs';
import {authorObservedSalesforceEffectPreview} from
  './salesforce-effect-preview.mjs';
import {openSalesforceEffectSiteFixture} from
  '../site-node/salesforce-effect-site.fixture.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site-node/salesforce-catalog-recovery.mjs';
import {refreshSalesforceEffectWriteCatalogs} from
  '../site-node/salesforce-effect-current-catalog.mjs';
import {observeSalesforceTargetSet} from
  '../site-node/salesforce-target-observation.mjs';
import * as salesforceMoon from
  '../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {issueAuthorizedEffectSetReceipt} from
  './effect-response-recovery.mjs';
import {commitPinnedEffectSourceHolding, exportPinnedEffectInput,
  preparePinnedEffectSourcePayload} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientEffectProgramPreparation,
  installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {completeCapturedEffectRun, runCapturedEffectComputation,
  runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from
  '../host-common/publication-contract-control.fixture.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueCompletedEffectfulComputationEvidence,
  prepareCompletedEffectfulPublication,
  publishCompletedEffectfulRun,
  recoverCompletedEffectfulComputation,
  releaseCompletedRunPreparedPayloads,
  storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority,
  installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';

const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../_build/client-program-bridge-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
const runChildWithLiveSite = (script, input) => new Promise((resolve,
  reject) => {
  const child = spawn(process.execPath, [fileURLToPath(new URL(script,
    import.meta.url))], {stdio: ['pipe', 'pipe', 'pipe']});
  const stdout = [];
  const stderr = [];
  const timeout = setTimeout(() => child.kill(), 20_000);
  child.stdout.on('data', chunk => stdout.push(Buffer.from(chunk)));
  child.stderr.on('data', chunk => stderr.push(Buffer.from(chunk)));
  child.once('error', reject);
  child.once('close', status => {
    clearTimeout(timeout);
    resolve({status, stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: Buffer.concat(stderr).toString('utf8')});
  });
  child.stdin.on('error', reject);
  child.stdin.end(JSON.stringify(input));
});
const effectParametersCid = prepared => moon.clientRequestParametersCid(
  moon.clientProgramEffectRequestIdentity(
    prepared, cid('a'), 'effect-fixture', cid('b')));
const hashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(JSON.stringify(body))
    .digest('hex')}`;
};
const canonicalHashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(canonicalJson(body))
    .digest('hex')}`;
};
const evidenceCid =
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904';
const programCid =
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c';
const parametersCid =
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52';
const publicationLimits = Object.freeze({
  maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64,
});
const previewPlanLimits = Object.freeze({
  maxFields: 10, maxWork: 100, maxBytes: 20000,
  maxNodes: 1000, maxDepth: 20,
});
const outputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 100, maxValueNodes: 10000, maxValueTextBytes: 100000,
  maxValueDepth: 64, maxValueWork: 100000, maxWireBytes: 100000,
  maxWireNodes: 10000, maxWireDepth: 64, maxColumns: 10,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003, maxLogicalWireDepth: 66,
  maxSchemaFields: 10, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 4096,
});
const effectInputExportArgs = limits => [
  limits.maxResultFields, limits.maxResultMappingWork,
  limits.maxResultOrderWork, limits.maxResultWorkspaceEntries,
  limits.maxRows, limits.maxValueNodes, limits.maxValueTextBytes,
  limits.maxValueDepth, limits.maxValueWork, limits.maxWireBytes,
  limits.maxWireNodes, limits.maxWireDepth, limits.maxColumns,
  limits.maxOrderWork, limits.maxLogicalWireBytes,
  limits.maxLogicalWireNodes, limits.maxLogicalWireDepth,
  limits.maxSchemaFields, limits.maxSchemaBytes, limits.maxSchemaNodes,
  limits.maxSchemaDepth, limits.maxBatchBytes,
];

async function checkedFixture() {
  const [document, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const environment = moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(), evidenceCid,
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  return {document, environment};
}

async function effectFixture({splitSource = false,
  splitEffectSource = 'consumer', writeKind = 'create',
  memberIds = ['save'], target = 'connector://crm/account',
  mappingRef = 'mapping:crm.account.v1', sourceIds,
  continueMembers = []} = {}) {
  const [documentBody, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const targetSchema = {
    additional_properties: false,
    fields: {
      Id: {nullable: false, type: sourceIds || writeKind === 'create' ?
        'string' : 'number'},
      Name: {nullable: true, type: sourceIds ? 'string' : 'number'},
    },
    nullable: false,
    type: 'object',
  };
  if (writeKind === 'create' && sourceIds) {
    targetSchema.fields.External_Key__c = {nullable: false,
      type: 'string'};
  }
  const mapping = {
    connector_manifest_cid: cid('a'),
    conversions: [],
    mapping_contract_cid: '',
    mapping_ref: mappingRef,
    minimum_approval: 'none',
    permission_rules: [{
      effect_kind: writeKind, permissions: ['scope:' + writeKind],
      selector_class: writeKind === 'create' ? 'none' :
        writeKind === 'upsert' ? 'key' : 'id',
      write_fields: writeKind === 'create' && sourceIds ?
        ['Name', 'External_Key__c'] : ['Name'],
    }],
    primary_identity: 'Id',
    required_fields: writeKind === 'create' && sourceIds ?
      ['External_Key__c'] : [],
    required_permissions: [],
    resource_identity_cid: cid('b'),
    row_mapping: writeKind === 'create' && sourceIds ? {
      Name: {field: 'id', null_behavior: 'reject'},
      External_Key__c: {field: 'id', null_behavior: 'reject'},
    } : {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1',
    target_ref: target,
    target_schema: targetSchema,
    target_schema_identity: `sha256:${createHash('sha256')
      .update(canonicalJson(targetSchema)).digest('hex')}`,
    version: 'salesforce-v1',
    writable_fields: writeKind === 'create' && sourceIds ?
      ['Name', 'External_Key__c'] : ['Name'],
  };
  mapping.mapping_contract_cid = writeKind === 'create' && sourceIds
    ? canonicalHashWithoutSelf(mapping, 'mapping_contract_cid')
    : hashWithoutSelf(mapping, 'mapping_contract_cid');
  const environmentDocument = JSON.parse(environmentBody);
  environmentDocument.mapping_contracts = [mapping];
  if (splitSource) {
    environmentDocument.host_policy_profile.capacity = JSON.parse(
      canonicalJson({
        ...environmentDocument.host_policy_profile.capacity,
        max_graph_construction_edges: 1000,
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000,
      }));
  }
  environmentDocument.evidence_bundle_cid = writeKind === 'create' &&
    sourceIds ? canonicalHashWithoutSelf(environmentDocument,
      'evidence_bundle_cid') : hashWithoutSelf(
      environmentDocument, 'evidence_bundle_cid');
  const environment = moon.clientProgramCheckEnvironment(
    writeKind === 'create' && sourceIds ?
      canonicalJson(environmentDocument) :
      JSON.stringify(environmentDocument),
    environmentDocument.evidence_bundle_cid,
    false, false, true, splitSource, false, false, false,
  );
  assert.ok(environment);
  const document = JSON.parse(documentBody);
  if (sourceIds) {
    document.stages[0].steps[0].values.schema.id.type = 'string';
    document.stages[0].steps[0].values.rows = sourceIds.map(id => ({id}));
  }
  const write = writeKind === 'create'
    ? {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'}}
    : {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'},
      [writeKind === 'upsert' ? 'key' : 'id']: 'id',
      set: {Name: {field: 'id'}}};
  const effects = Object.fromEntries(memberIds.map(id =>
    [id, {[writeKind]: continueMembers.includes(id)
      ? {...write, on_item_failure: 'continue'} : write}]));
  document.stages[0].effects = effects;
  if (splitSource) {
    delete document.stages[0].effects;
    document.stages.push({
      id: 'middle',
      inputs: {rows: {result: {stage: 'source', result: 'rows'}}},
      steps: [
        {graph: {
          nodes: {from: 'rows', id: 'id', fields: []},
          edges: {from: 'rows', source: 'id', target: 'id', fields: []},
        }, as: 'g'},
        {from: 'g', normalize_graph: true, as: 'normalized'},
        {from: 'normalized', node_rows: true, as: 'projected'},
        {from: 'projected', take: 2, as: 'selected'},
      ],
      results: {
        rows: {from: 'selected', fields: ['id']},
        early: {from: 'projected', fields: ['id']},
      },
    }, {
      id: 'consumer',
      inputs: {rows: {result: {stage: 'middle', result: 'rows'}}},
      steps: [{take: 2, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects,
    });
    document.results.answer.from.stage = 'consumer';
    if (splitEffectSource !== 'consumer') {
      document.stages.pop();
      document.results.answer.from.stage = 'middle';
      document.stages[1].effects = Object.fromEntries(memberIds.map(id =>
        [id, {[writeKind]: {
          ...write,
          from: {result: splitEffectSource === 'early' ? 'early' : 'rows'},
        }}]));
    }
  }
  return {document: JSON.stringify(document), environment,
    mappingCid: mapping.mapping_contract_cid};
}

function effectInputPreview(prepared, evidence, definition, invocation,
  mappingCid, artifactCid, writeKind = 'create',
  approvedValues = [], targetRows = approvedValues.map((_, index) =>
    index + 1), memberIds = ['save'],
  memberBoundaries = memberIds.map((_, index) => cid(String(index))),
  scope, {target = 'connector://crm/account',
    mapping = 'mapping:crm.account.v1', resourceKind = 'Account',
    footprints, continueMembers = [], guardVersions,
    templateOnly = false} = {}) {
  const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = {
    version: 'actql-authoring-context/0.1',
    program_definition_cid: definitionCid, annotations: [],
  };
  authoring.authoring_context_cid = `sha256:${createHash('sha256')
    .update(canonicalJson(authoring)).digest('hex')}`;
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: definitionCid,
    invocation_cid: moon.strategyPublicationContractIdentity(invocation),
    run_identity_cid: moon.strategyPublicationContractIdentity(definition),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(evidence[3]),
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: authoring, barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [],
    model_invocation_evidence_cids: [], model_response_artifact_cids: [],
    effects: memberIds.map((effectId, memberIndex) => ({
      effect_id: effectId, effect_kind: writeKind,
      target, mapping,
      resolved_mapping_contract_cid: mappingCid,
      effect_identity_cid: cid(String(memberIndex + 1)),
      source_result: 'rows',
      result_artifact_cid: artifactCid, preview_strength: 'full_diff',
      source_binding_cid: cid('c'), capability_evidence_cid: cid('d'),
      authority_scope_cid: cid('e'),
      write_footprint: footprints?.[memberIndex] ?? {
        kind: 'collection', resource_identity_scheme_cid: cid('f'),
        provider_namespace: 'salesforce',
        provider_boundary_cid: memberBoundaries[memberIndex],
        resource_kind: resourceKind, provider_object_identity_cids: [],
      },
      count: approvedValues.length, max_items: 2,
      required_permissions: ['write'],
      approval: 'none', on_item_failure:
        continueMembers.includes(effectId) ? 'continue' : 'halt',
      changes: approvedValues.map((value, index) => ({
        target_row_identity: targetRows[index],
        target_guard: writeKind === 'create'
          ? {state: 'not_applicable'}
          : {state: 'version', version_cid:
            guardVersions?.[memberIndex]?.[index] ?? cid('6')},
        intended_changes: {state: 'present', value: writeKind === 'create'
          ? {Name: value, External_Key__c: value} : {Name: value}},
        before: writeKind === 'create' ? {state: 'absent'}
          : {state: 'present', value: {Name: typeof value === 'string'
            ? 'before' : 0}},
        after: {state: 'present', value: writeKind === 'create'
          ? {Name: value, External_Key__c: value} : {Name: value}},
        row_preview_cid: cid('1'), row_idempotency_key: cid('8'),
      })),
      row_order: [],
      effect_member_preview_cid: cid('1'), executed: false,
    })),
    executed: false, effect_preview_cid: cid('2'),
  };
  if (writeKind !== 'create') {
    for (const [index, member] of preview.effects.entries()) {
      member.effect_plan_logical_cid = checked(
        moon.clientProgramEffectPlanCid(prepared, index, 10, 100,
          20000, 1000, 20));
    }
  }
  if (templateOnly) {
    return {wire: canonicalJson(preview),
      authoringCid: authoring.authoring_context_cid};
  }
  if (scope !== undefined) {
    const authored = checked(moon.clientProgramAuthorEffectPreview(
      canonicalJson(preview), preview.run_identity_cid,
      authoring.authoring_context_cid, scope, 20000, 1000, 20,
      memberIds.length, approvedValues.length * memberIds.length,
      128, 8, 3));
    return {wire: authored._0,
      authoringCid: authoring.authoring_context_cid, keys: authored._1};
  }
  if (approvedValues.length > 0) {
    const rowsByMember = checked(moon.strategyEffectPreviewRowIdentities(
      canonicalJson(preview), 20000, 1000, 20));
    for (const [memberIndex, member] of preview.effects.entries()) {
      const rows = rowsByMember[memberIndex];
      member.changes.forEach((change, index) => {
        change.row_preview_cid = rows[index];
        change.row_idempotency_key = cid(String(index + 7));
      });
      member.row_order = rows;
    }
  }
  const identities = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20));
  preview.effects.forEach((member, index) => {
    member.effect_member_preview_cid = identities[index + 1];
  });
  preview.effect_preview_cid = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20))[0];
  const keys = scope === undefined ? undefined : preview.effects.map(member =>
    member.changes.map(change => {
      const key = checked(moon.strategyEffectDispatchKey(
        scope, preview.effect_preview_cid,
        canonicalJson(change.target_row_identity), 128, 8, 3));
      change.row_idempotency_key = moon.strategyEffectDispatchKeyCid(key);
      return key;
    }));
  return {wire: canonicalJson(preview), authoringCid:
    authoring.authoring_context_cid, keys};
}

test('internal Client bridge retains Effect closure without public apply',
  async () => {
    const {document, environment} = await effectFixture();
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const localInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    const localInvocationBody = JSON.parse(
      moon.clientProgramLocalEffectInvocationJson(localInvocation));
    assert.equal(localInvocationBody.self_cid,
      moon.clientProgramLocalEffectInvocationCid(localInvocation));
    assert.equal(localInvocationBody.observation_cids.length, 0);
    const localResult = checked(
      moon.clientProgramIssueLocalEffectResultDefinition(
        prepared, 0, 'rows', 4096, 16, 4));
    const localResultBody = JSON.parse(
      moon.clientProgramLocalEffectResultDefinitionJson(localResult));
    assert.equal(localResultBody.version,
      'actql-local-result-definition/0.1');
    assert.equal(localResultBody.result_name, 'rows');
    assert.equal(localResultBody.self_cid,
      moon.clientProgramLocalEffectResultDefinitionCid(localResult));
    assert.equal('program_definition_cid' in localResultBody, false);
    assert.equal('invocation_cid' in localResultBody, false);
    assert.equal(moon.clientProgramIssueLocalEffectResultDefinition(
      prepared, 0, 'other', 4096, 16, 4).$tag, 0);
    assert.equal(moon.clientProgramEffectPreparationIssue(outcome), undefined);
    assert.equal(moon.clientProgramPrepareEffectFree(
      document, 'json', environment), undefined);
    const foreign = moon.clientProgramPrepareEffectComputationWithParameters(
      document.replace('mapping:crm.account.v1', 'mapping:crm.foreign.v1'),
      'json', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationReady(foreign), undefined);
    assert.ok(moon.clientProgramEffectPreparationIssueCode(foreign));
    const invalidFormat = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'text', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidFormat),
      'invalid_format');
    const invalidParameters = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, '{', []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidParameters),
      'supplied_syntax');
    assert.equal(checked(moon.clientProgramEffectPlanCid(
      prepared, 0, 10, 100, 10000, 1000, 20)), undefined);
    const update = await effectFixture({writeKind: 'update'});
    const updateOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        update.document, 'json', update.environment, undefined, []);
    const updatePrepared = moon.clientProgramEffectPreparationReady(
      updateOutcome);
    assert.ok(updatePrepared,
      moon.clientProgramEffectPreparationIssueCode(updateOutcome));
    assert.match(checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 0, 10, 100, 10000, 1000, 20)),
    /^sha256:[0-9a-f]{64}$/);
    assert.throws(() => checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 1, 10, 100, 10000, 1000, 20)),
    {code: 'MoonBitHostFailure'});
  });

test('installed Effect preparation retains the checked Program owner',
  async () => {
    const {document, environment} = await effectFixture();
    const prepare = installNodeClientEffectProgramPreparation({
      moon, environment, evidence: [],
    });
    const owned = prepare({kind: 'program', input: JSON.parse(document),
      parameters: null});
    const direct = moon.clientProgramEffectPreparationReady(
      moon.clientProgramPrepareEffectComputationWithParameters(
        document, 'json', environment, undefined, []));
    assert.ok(owned && direct);
    assert.equal(moon.clientProgramEffectDefinitionCid(owned),
      moon.clientProgramEffectDefinitionCid(direct));
    assert.equal(moon.clientProgramEffectEnvironmentCid(owned),
      moon.clientProgramEffectEnvironmentCid(direct));
    assert.throws(() => prepare({kind: 'aql',
      input: {text: document, format: 'auto'}, parameters: null}),
    {code: 'ClientProgramInvalidInput'});
    assert.throws(() => prepare({kind: 'aql',
      input: {text: document.replace('mapping:crm.account.v1',
        'mapping:crm.foreign.v1'), format: 'json'}, parameters: null}),
    {code: 'ClientProgramRejected'});
    assert.throws(() => installNodeClientProgramPreparation({
      moon, environment,
    })({kind: 'program', input: JSON.parse(document), parameters: null}),
    {code: 'ClientProgramUnsupported'});
  });

test('checked Effect member resolution is Stage-scoped', async () => {
  const fixture = await effectFixture({splitSource: true,
    memberIds: ['late'], sourceIds: ['record-a', 'record-b']});
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    fixture.document, 'json', fixture.environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared,
    moon.clientProgramEffectPreparationIssueCode(outcome));
  const late = checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 2, 'late', 100));
  assert.equal(late._0, 0);
  assert.equal(late._1, 'late');
  assert.equal(late._3, 'connector://crm/account');
  assert.equal(late._5, fixture.mappingCid);
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 0, 'late', 100)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 2, 'foreign', 100)), {code: 'MoonBitHostFailure'});
});

test('Effectful Client request identity binds checked intent before Run',
  async t => {
    const create = await effectFixture({writeKind: 'create'});
    const update = await effectFixture({writeKind: 'update'});
    const prepare = fixture => {
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        fixture.document, 'json', fixture.environment, undefined, []);
      const value = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(value,
        moon.clientProgramEffectPreparationIssueCode(outcome));
      return value;
    };
    const original = prepare(create);
    const changed = prepare(update);
    const request = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', cid('b'));
    const replay = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', cid('b'));
    const conflict = moon.clientProgramEffectRequestIdentity(
      changed, cid('a'), 'write-request', cid('b'));
    const next = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'another-request', cid('b'));
    assert.ok(request && replay && conflict && next);
    assert.equal(moon.clientRequestProgramCid(request),
      moon.clientProgramEffectDefinitionCid(original));
    const expectedIntent = `sha256:${createHash('sha256').update(JSON.stringify({
      caller_input_intent_cid: cid('b'),
      parameter_values_cid: moon.clientRequestParametersCid(request),
      program_definition_cid: moon.clientProgramEffectDefinitionCid(original),
      version: 'actql-logical-request-intent/0.1',
    })).digest('hex')}`;
    assert.equal(moon.clientRequestIntentCid(request), expectedIntent);
    assert.equal(moon.clientRequestRelation(request, replay), 1);
    assert.equal(moon.clientRequestRelation(request, conflict), 2);
    assert.equal(moon.clientRequestRelation(request, next), 0);
    assert.equal(moon.clientProgramEffectRequestIdentity(
      original, cid('a'), '', cid('b')), undefined);
    assert.equal(moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', 'foreign'), undefined);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'effect-request-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const admission = {tenantId: 'tenant-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    const journal = openClientRequestJournal(path);
    assert.equal(journal.accept(request, admission, moon).inserted, true);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.accept(replay, {...admission,
      runDefinitionCid: cid('e')}, moon).inserted, false);
    assert.throws(() => reopened.accept(conflict, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    assert.equal(reopened.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: 'write-request'}, moon)
      .ref.runDefinitionCid, cid('d'));
  });

test('Host admits and retains the exact checked Effect Run Definition',
  async t => {
    const first = await effectFixture({writeKind: 'create'});
    const second = await effectFixture({writeKind: 'update'});
    const prepare = fixture => {
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        fixture.document, 'json', fixture.environment, undefined, []);
      const value = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(value, moon.clientProgramEffectPreparationIssueCode(outcome));
      return value;
    };
    const prepared = prepare(first);
    const changed = prepare(second);
    const request = moon.clientProgramEffectRequestIdentity(
      prepared, cid('a'), 'effect-run-request', cid('b'));
    const changedRequest = moon.clientProgramEffectRequestIdentity(
      changed, cid('a'), 'effect-run-request', cid('b'));
    const control = runtimeCore(moon).publicationControl;
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(request),
      moon.clientRequestParametersCid(request),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), publicationLimits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]),
      publicationLimits);
    const admission = control.admitCheckedClientEffectRunPublication(
      prepared, ...bound, plan);
    assert.equal(admission.kind, 'run-publication-admission');
    assert.throws(() => control.admitCheckedClientEffectRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Effect/u);
    const definition = control.issueRunDefinition(admission, {
      scopeId: 'tenant-a-scope', runId: 'checked-effect-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, publicationLimits);
    const boundRun = control.bindCheckedClientEffectRun(
      prepared, admission, definition);
    assert.ok(boundRun);
    assert.throws(() => control.bindCheckedClientEffectRun(
      changed, admission, definition),
    /Run Definition differs from checked Effect/u);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const host = moon.clientProgramOpenSourceFreeLocalEffectHost(
      boundRun, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(host);
    await assert.rejects(runCapturedEffectComputation({}),
      {name: 'TypeError', message: 'InvalidCapturedEffectComputation'});
    const execution = await runCapturedEffectComputation(host);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.equal(moon.clientProgramLocalEffectSourceCount(host), 1);
    } finally {
      await execution.close();
    }
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'effect-admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    assert.equal(journal.acceptDefinition(request, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control).inserted, true);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.resolveDefinition(request,
      {tenantId: 'tenant-a'}, moon, control).runDefinition.wire,
    definition.wire);
    assert.throws(() => reopened.resolveDefinition(changedRequest,
      {tenantId: 'tenant-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
  });

test('admitted source-free Effect Run computes through the installed Host',
  async t => {
    const {document, environment, mappingCid} = await effectFixture({
      writeKind: 'update',
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const semanticInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    assert.equal(JSON.parse(moon.clientProgramLocalEffectInvocationJson(
      semanticInvocation)).self_cid,
      moon.clientProgramLocalEffectInvocationCid(semanticInvocation));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared),
      effectParametersCid(prepared),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    assert.ok(admission);
    for (const changed of [
      publicationEvidence(cid('f'), effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        cid('f'), moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared), cid('f'),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared), cid('f')),
    ]) {
      assert.equal(moon.clientProgramAdmitEffectPublication(
        prepared, ...changed), undefined);
    }
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'tenant-a-scope', 'effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    assert.notEqual(moon.clientProgramLocalEffectInvocationCid(
      semanticInvocation), moon.strategyPublicationContractIdentity(invocation));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const foreignDocument = JSON.parse(document);
    foreignDocument.id = 'foreign-effect-compute';
    const foreignOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        JSON.stringify(foreignDocument), 'json', environment, undefined, []);
    const foreign = moon.clientProgramEffectPreparationReady(foreignOutcome);
    assert.ok(foreign);
    assert.equal(moon.clientProgramBindEffectRun(
      foreign, admission, definition), undefined);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
    const execution = await runCapturedEffectComputation(owned);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'effect-result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const runDefinitionContract = control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), publicationLimits);
    const invocationContract = control.admit('run_invocation',
      moon.strategyPublicationContractJson(invocation), publicationLimits);
    const localEvidenceContext = admittedLocalEffectEvidenceContext(
      control, prepared, evidence, definition, invocation, observation);
    const store = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
      privateEvidenceKey: Buffer.alloc(32, 4),
    }, control);
    let storedResults, committedPublicationKey, effectLedger;
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].outputRows, 2);
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control, runDefinition: runDefinitionContract,
        invocation: invocationContract,
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      assert.equal(storedResults.artifacts.length, 1);
      assert.equal(storedResults.results[0].orderedRows.rows, 2);
      assert.equal(storedResults.definitions[0].identity,
        execution.publicationInventory.occurrences[0]
          .definitionContract.identity);
      assert.equal(JSON.parse(storedResults.artifacts[0].wire)
        .actual_row_count, 2);
      const payload = [];
      await store.consumeObject(storedResults.results[0].physical.cid,
        chunk => payload.push(Buffer.from(chunk)));
      const bytes = Buffer.concat(payload);
      assert.equal(bytes.byteLength,
        storedResults.results[0].physical.bytes);
      assert.equal(`sha256:${createHash('sha256').update(bytes)
        .digest('hex')}`, storedResults.results[0].physical.cid);
      const binding = JSON.parse(storedResults.results[0].publication
        .durableBinding.wire);
      assert.equal(binding.logical_result_cid,
        storedResults.results[0].orderedRows.logicalRelationCid);
      assert.equal(binding.run_definition_cid,
        runDefinitionContract.identity);
      assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 0)), {code: 'MoonBitHostFailure'});
      const inputs = checked(moon.clientProgramPinEffectSources(owned, 1));
      let previewInputs;
      let sourcePayload;
      let sourceHoldingCid;
      try {
        assert.equal(moon.clientProgramEffectInputCount(inputs), 1);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 1), false);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.throws(() => checked(moon.clientProgramPinEffectSources(
          owned, 1)), {code: 'MoonBitHostFailure'});
        const input = moon.clientProgramEffectInputAt(inputs, 0);
        assert.ok(input);
        const capturedDefinition = checked(
          moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
            prepared, inputs, 0, 4096, 16, 4));
        assert.equal(JSON.parse(moon.clientProgramLocalEffectResultDefinitionJson(
          capturedDefinition)).result_name, 'rows');
        const foreignPrepared = moon.clientProgramEffectPreparationReady(
          moon.clientProgramPrepareEffectComputationWithParameters(
            document, 'json', environment, undefined, []));
        assert.ok(foreignPrepared);
        assert.throws(() => checked(
          moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
            foreignPrepared, inputs, 0, 4096, 16, 4)),
        {code: 'MoonBitHostFailure'});
        const beforeSource = store.status();
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: 1, control, invocation: invocationContract,
          retention, sourceBindingCid: cid('c'),
          contractLimits: publicationLimits,
          localEvidenceContext,
        }), {message: 'EffectSourceByteLimit'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().objectCount, beforeSource.objectCount);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {issueEffectSourceArtifactFromExport() {
            throw new Error('SourceArtifactRejected');
          }, issueSourceFreeLocalEffectResultArtifact:
            control.issueSourceFreeLocalEffectResultArtifact,
          issueLocalEffectResultManifest:
            control.issueLocalEffectResultManifest},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {message: 'SourceArtifactRejected'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {...control,
            issueSourceFreeLocalEffectResultArtifact(...args) {
              moon.clientProgramEffectInputExportReleaseReceipt(args[6]);
              return control.issueSourceFreeLocalEffectResultArtifact(...args);
            }},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {code: 'MoonBitHostFailure'});
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        const foreignLocalDefinition = checked(
          moon.clientProgramIssueLocalEffectResultDefinition(
            foreignPrepared, 0, 'rows', 4096, 16, 4));
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {...control,
            issueSourceFreeLocalEffectResultArtifact(...args) {
              args[4] = foreignLocalDefinition;
              return control.issueSourceFreeLocalEffectResultArtifact(...args);
            }},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {code: 'MoonBitHostFailure'});
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control, invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
          proposalLimits: {maxFields: 10, maxWork: 100,
            maxBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxUtf16Units: 20000},
          onProposalRow() { throw new Error('ProposalConsumerStopped'); },
        }), {message: 'ProposalConsumerStopped'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        let sourceWriters = 0;
        let holdingCommits = 0;
        const sourceStore = {
          storeAuthorityCid: store.storeAuthorityCid,
          createPreparedObjectWriter(maxBytes) {
            sourceWriters++;
            return store.createPreparedObjectWriter(maxBytes);
          },
          async commitPhysicalHolding(...args) {
            holdingCommits++;
            const result = await store.commitPhysicalHolding(...args);
            if (holdingCommits === 1) {
              throw new Error('LostEffectSourceCommitAck');
            }
            return result;
          },
        };
        sourcePayload = await preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store: sourceStore, maxBytes: outputLimits.maxWireBytes,
          control, invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        });
        const exportLimits = moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits));
        const capturedInvocation = checked(
          moon.clientProgramIssueCapturedEffectInputLocalInvocation(
            prepared, inputs, 0, publicationLimits.maxWireBytes,
            publicationLimits.maxNodes, publicationLimits.maxDepth));
        await exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 0, limits: exportLimits,
          onChunk() {},
          async onReceipt(firstInput, firstReceipt, firstImporting) {
            await exportPinnedEffectInput({
              moon, execution, inputs, memberIndex: 0,
              limits: exportLimits, onChunk() {},
              onReceipt(secondInput, secondReceipt, secondImporting) {
                assert.equal(firstInput, secondInput);
                assert.notEqual(firstImporting, secondImporting);
                assert.throws(() => control
                  .issueSourceFreeLocalEffectResultArtifact(
                    prepared, inputs, 0, secondImporting,
                    capturedDefinition, capturedInvocation, firstReceipt,
                    retention, localEvidenceContext, publicationLimits),
                {code: 'MoonBitHostFailure'});
                assert.throws(() => control
                  .issueSourceFreeLocalEffectResultArtifact(
                    foreignPrepared, inputs, 0, secondImporting,
                    capturedDefinition, capturedInvocation, secondReceipt,
                    retention, localEvidenceContext, publicationLimits),
                {code: 'MoonBitHostFailure'});
                assert.ok(control.issueSourceFreeLocalEffectResultArtifact(
                  prepared, inputs, 0, secondImporting,
                  capturedDefinition, capturedInvocation, secondReceipt,
                  retention, localEvidenceContext, publicationLimits));
              },
            });
          },
        });
        const sourceArtifact = sourcePayload.summary.artifact;
        assert.equal(JSON.parse(sourceArtifact.wire).source_result, 'rows');
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .result_name, 'rows');
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .self_cid, sourcePayload.localResultDefinition.identity);
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .version, 'actql-local-result-definition/0.1');
        const localArtifact = JSON.parse(sourcePayload.localResultArtifact.wire);
        assert.equal(localArtifact.version, 'actql-result-artifact/0.1');
        assert.equal(localArtifact.result_definition_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localArtifact.invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.notEqual(localArtifact.invocation_cid,
          invocationContract.identity);
        assert.equal(localArtifact.logical_result_cid,
          sourcePayload.summary.logicalCid);
        assert.equal(localArtifact.result_schema_cid,
          sourcePayload.summary.schemaCid);
        assert.equal(localArtifact.actual_row_count,
          sourcePayload.summary.rowCount);
        const localManifest = JSON.parse(sourcePayload.localManifest.wire);
        assert.equal(localManifest.version,
          'actql-local-result-manifest/0.1');
        assert.equal(localManifest.self_cid,
          sourcePayload.localManifest.identity);
        assert.equal(localManifest.local_invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.deepEqual(localManifest.results,
          {rows: sourcePayload.localResultArtifact.identity});
        const localManifestPreimage = {...localManifest};
        delete localManifestPreimage.self_cid;
        assert.equal(sourcePayload.localManifest.identity,
          `sha256:${createHash('sha256')
            .update(JSON.stringify(localManifestPreimage))
            .digest('hex')}`);
        assert.throws(() => control.issueLocalEffectResultManifest(
          prepared, capturedInvocation, [], publicationLimits),
        {name: 'TypeError'});
        assert.throws(() => control.issueLocalEffectResultManifest(
          foreignPrepared, capturedInvocation,
          [sourcePayload.localResultArtifact], publicationLimits),
        {code: 'MoonBitHostFailure'});
        const localIdentity = control.issueSourceFreeLocalEffectIdentity(
          prepared, inputs, 0, sourcePayload.localResultArtifact,
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10});
        const localIdentityBody = JSON.parse(localIdentity.wire);
        assert.equal(localIdentityBody.self_cid, localIdentity.identity);
        assert.equal(localIdentityBody.result_artifact_cid,
          sourcePayload.localResultArtifact.identity);
        assert.equal(localIdentityBody.local_invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.throws(() => control.issueSourceFreeLocalEffectIdentity(
          foreignPrepared, inputs, 0, sourcePayload.localResultArtifact,
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10}), {code: 'MoonBitHostFailure'});
        assert.throws(() => control.issueSourceFreeLocalEffectIdentity(
          prepared, inputs, 0, {...sourcePayload.localResultArtifact},
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10}), {name: 'TypeError'});
        const localDerivation = JSON.parse(
          sourcePayload.localResultArtifact.derivationWire);
        const localOrdering = JSON.parse(
          sourcePayload.localResultArtifact.orderingWire);
        assert.equal(localDerivation.producer_contract_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localOrdering.producer_contract_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localArtifact.ordering_evidence_cid,
          localOrdering.self_cid);
        assert.deepEqual(localArtifact.provenance_evidence_cids,
          [localDerivation.self_cid]);
        assert.equal(JSON.parse(storedResults.artifacts[0].wire)
          .result_definition_cid, storedResults.definitions[0].identity);
        assert.equal(storedResults.results[0].occurrence.name, 'answer');
        const effect = runtimeCore(moon).effectApplicationControl;
        const requestScope = effect.logicalRequestScope(
          cid('e'), 'effect-compute-request', 128);
        const preview = effectInputPreview(
          prepared, evidence, definition, invocation, mappingCid,
          sourceArtifact.identity, 'update', [1, 2], [1, 2],
          ['save'], [cid('0')], requestScope);
        const authoringContext = control.admitRunEvidence(
          'authoring_context',
          canonicalJson(JSON.parse(preview.wire).authoring_context),
          publicationLimits);
        const admittedPreview = control.admitEffectComputationPreview(
          preview.wire, runDefinitionContract, authoringContext,
          publicationLimits);
        const capturePreviewInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, preview.wire,
            preview.authoringCid,
            moon.clientProgramEffectPreviewInputLimits(
              20000, 1000, 20, 1000, 100, 20000, 1000, 20,
              1, 2, 100, 100)));
        const planChunks = [];
        await verifyPinnedEffectPlan({
          moon, execution, previewInputs: capturePreviewInputs,
          previewIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          planLimits: {maxFields: 10, maxWork: 100, maxBytes: 20000,
            maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000},
          onChunk: chunk => { planChunks.push(chunk); },
        });
        let matchedSource;
        const sourceControl = {...control,
          localEffectSourceMatches(...args) {
            matchedSource = args;
            return control.localEffectSourceMatches(...args);
          }};
        const commitSource = () => commitPinnedEffectSourceHolding({
          payload: sourcePayload, store: sourceStore, control: sourceControl,
          preview: admittedPreview,
          memberIndex: 0, invocation: invocationContract,
        });
        await assert.rejects(commitPinnedEffectSourceHolding({
          payload: sourcePayload, store: sourceStore,
          control: {...control, localEffectSourceMatches: () => false},
          preview: admittedPreview,
          memberIndex: 0, invocation: invocationContract,
        }), {message: 'ForeignLocalEffectSource'});
        assert.equal(holdingCommits, 0);
        await assert.rejects(commitSource(),
          {message: 'LostEffectSourceCommitAck'});
        const sourceHolding = await commitSource();
        assert.equal(sourceWriters, 1);
        assert.equal(holdingCommits, 2);
        assert.equal(sourceHolding.localResultArtifact,
          sourcePayload.localResultArtifact);
        assert.equal(sourceHolding.localManifest, sourcePayload.localManifest);
        assert.equal(control.localEffectSourceMatches(...matchedSource), true);
        assert.equal(control.localEffectSourceMatches(
          foreignPrepared, ...matchedSource.slice(1)), false);
        assert.throws(() => control.localEffectSourceMatches(
          ...matchedSource.slice(0, 3), {...sourceHolding.localManifest},
          ...matchedSource.slice(4)), {name: 'TypeError'});
        sourceHoldingCid = sourceHolding.holdingCid;
        assert.deepEqual(await store.inspectPhysicalHolding(
          sourceHoldingCid), sourceHolding.record);
        const runEvidence = evidence.slice(0, 3).map((value, index) =>
          control.admitRunEvidence(
            ['bound_invocation_template', 'prepared_invocation',
              'run_authorization'][index],
            moon.strategyRunEvidenceJson(value), publicationLimits));
        const compiledPlan = control.admit('compiled_plan',
          moon.strategyPublicationContractJson(evidence[3]),
          publicationLimits);
        const runAdmission = control.admitCheckedClientEffectRunPublication(
          prepared, ...runEvidence, compiledPlan);
        const normalizationJournal = control.sealRunEvidence(
          'normalization_journal', JSON.stringify({
            version: 'actql-normalization-journal/0.1',
            rule_catalog_cid: cid('1'), entries: [],
          }), publicationLimits);
        const captureOptions = {
          execution, store, storedResults, control, admission: runAdmission,
          runDefinition: runDefinitionContract,
          invocation: invocationContract,
          observation: control.admitRunEvidence('observation_set',
            moon.strategyRunEvidenceJson(observation), publicationLimits),
          normalizationJournal, authoringContext,
          receiptEvidence: {bindings: [], sourceEvidence: [],
            modelEvidence: [], barrierAttemptReceiptCids: []},
          captureEvidence: {pendingSourceStateAdvances: [],
            modelEvidence: []},
          preview: admittedPreview,
          plans: [{name: 'save', wire: planChunks.join('')}],
          effectSourceHoldings: [sourceHolding],
          connectorRecovery: [],
          contractLimits: publicationLimits,
        };
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          store: {...store,
            async commitPhysicalHolding() {
              throw new Error('EffectSourceSyncFailed');
            }},
        }), {message: 'EffectSourceSyncFailed'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          effectSourceHoldings: [{...sourceHolding,
            record: {...sourceHolding.record, manifest_cid: cid('9')}}],
        }), {code: 'InvalidCompletedEffectSourceHolding'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          effectSourceHoldings: [{...sourceHolding,
            artifact: {...sourceArtifact, identity: cid('9')}}],
        }), {code: 'InvalidCompletedEffectSourceHolding'});
        let captureCommits = 0;
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          store: {...store,
            async commitPhysicalHolding(...args) {
              const committed = await store.commitPhysicalHolding(...args);
              captureCommits++;
              if (captureCommits === 2) {
                throw new Error('LostCaptureHoldingCommitAck');
              }
              return committed;
            }},
        }), {message: 'LostCaptureHoldingCommitAck'});
        assert.ok(await store.inspectPhysicalHolding(
          control.effectComputationCaptureHoldingCid(
            runDefinitionContract, store.storeAuthorityCid)));
        const computation = await issueCompletedEffectfulComputationEvidence(
          captureOptions);
        assert.equal(sourceWriters, 1);
        const finalInventory = prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation, preview: admittedPreview,
        });
        assert.equal(finalInventory.chain.capturedRun.identity,
          computation.capturedRun.identity);
        assert.equal(finalInventory.chain.artifacts[0].identity,
          storedResults.artifacts[0].identity);
        assert.equal(finalInventory.sourceArtifacts[0].identity,
          sourceArtifact.identity);
        assert.equal(finalInventory.effectSources[0], sourceHolding.source);
        const mutableArtifact = {...sourceArtifact};
        const mutableComputation =
          await issueCompletedEffectfulComputationEvidence({
            ...captureOptions,
            effectSourceHoldings: [{...sourceHolding,
              artifact: mutableArtifact}],
          });
        mutableArtifact.identity = cid('9');
        assert.equal(prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation: mutableComputation, preview: admittedPreview,
        }).sourceArtifacts[0].identity, sourceArtifact.identity);
        assert.throws(() => prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation: {...computation}, preview: admittedPreview,
        }), {code: 'InvalidCompletedEffectfulRunOwner'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions, storedResults: {...storedResults},
        }), {code: 'InvalidCompletedEffectfulComputationOptions'});
        assert.equal(computation.manifest.name, 'result_manifest');
        assert.equal(computation.computationReceipt.name, 'run_receipt');
        assert.equal(computation.capturedRun.name, 'captured_run');
        const capturedBody = JSON.parse(computation.capturedRun.wire);
        assert.deepEqual(capturedBody.receipt,
          JSON.parse(computation.computationReceipt.wire));
        assert.equal(capturedBody.effect_context.effect_source_artifacts.save
          .result_artifact_cid, sourceArtifact.identity);
        assert.equal(capturedBody.effect_context.effect_source_artifacts.save
          .source_result,
          'rows');
        assert.equal(capturedBody.effect_context.effect_source_holding_cids.save,
          sourceHoldingCid);
        assert.deepEqual(Object.keys(capturedBody.effect_context
          .result_artifacts), ['answer']);
        const foreignArtifactPreview = effectInputPreview(
          prepared, evidence, definition, invocation, mappingCid, cid('9'));
        const foreignAdmittedPreview =
          control.admitEffectComputationPreview(
            foreignArtifactPreview.wire, runDefinitionContract,
            authoringContext, publicationLimits);
        assert.throws(() => prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation, preview: foreignAdmittedPreview,
        }), {code: 'InvalidCompletedEffectfulRunOwner'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          preview: foreignAdmittedPreview, plans: [],
        }), {code: 'MoonBitHostFailure'});
        const previewLimits = moon.clientProgramEffectPreviewInputLimits(
          20000, 1000, 20, 1000, 100, 20000, 1000, 20,
          1, 2, 100, 100);
        assert.ok(previewLimits);
        const foreignPreview = effectInputPreview(
          prepared, evidence, definition, invocation, cid('9'),
          sourceArtifact.identity);
        assert.throws(() => checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, foreignPreview.wire,
            foreignPreview.authoringCid, previewLimits)),
        {code: 'MoonBitHostFailure'});
        previewInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, preview.wire,
            preview.authoringCid, previewLimits));
        assert.equal(moon.clientProgramEffectPreviewInputAt(
          previewInputs, 0), input);
        assert.equal(checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, 10, 100)).operation, 'update');
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, -1, 100)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 1, 10, 100)),
        {code: 'MoonBitHostFailure'});
        const previewRows = JSON.parse(preview.wire).effects[0].row_order;
        assert.doesNotThrow(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, previewRows, previewRows.map(() => cid('6')),
            2, 4)));
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [], 1, 2)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [cid('2')], 1, 2)),
        {code: 'MoonBitHostFailure'});
        const other = moon.clientProgramOpenSourceFreeLocalEffectHost(
          bound, registry, values, 1n, 0n, 0n, 0n);
        assert.ok(other);
        const otherExecution = await runCapturedEffectComputation(other);
        try {
          await assert.rejects(issueCompletedEffectfulComputationEvidence({
            ...captureOptions, execution: otherExecution,
          }), {code: 'InvalidCompletedEffectfulComputationOptions'});
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              other, inputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
        } finally {
          await otherExecution.close();
        }
        const limits = moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits));
        assert.ok(limits);
        assert.throws(() => checked(moon.clientProgramEffectInputExportStart(
          input, limits)), {code: 'MoonBitHostFailure'});
        const physical = execution.effectPhysicalSource(0);
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 1, limits,
          onChunk() { throw new Error('UnexpectedEffectChunk'); },
        }), {message: 'MissingEffectInput'});
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 0, limits,
          onChunk() { throw new Error('StoppedEffectConsumer'); },
        }), {message: 'StoppedEffectConsumer'});
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        const observed = {
          effectPhysicalSource(task) {
            assert.equal(task, 0);
            return {
              ...physical,
              withRows(...args) {
                limits.max_rows = 0;
                limits.values.max_nodes = 0;
                return physical.withRows(...args);
              },
            };
          },
        };
        const chunks = [];
        const exported = await exportPinnedEffectInput({
          moon, execution: observed, inputs, memberIndex: 0,
          task: 999,
          limits,
          onChunk: async chunk => { chunks.push(chunk); },
        });
        assert.deepEqual(JSON.parse(chunks.join('')),
          [{id: 1}, {id: 2}]);
        assert.deepEqual(exported.fields, ['id']);
        assert.match(exported.logicalCid, /^sha256:[0-9a-f]{64}$/);
        assert.match(exported.schemaCid, /^sha256:[0-9a-f]{64}$/);
        assert.equal(exported.rowCount, 2);
        assert.equal(sourcePayload.summary.logicalCid, exported.logicalCid);
        assert.equal(sourcePayload.summary.schemaCid, exported.schemaCid);
        assert.equal(sourcePayload.summary.rowCount, exported.rowCount);
        assert.equal(sourcePayload.physical.cid,
          `sha256:${createHash('sha256')
            .update(chunks.join('')).digest('hex')}`);
        const storedChunks = [];
        await store.consumePhysicalHolding(sourceHoldingCid, 0,
          chunk => storedChunks.push(Buffer.from(chunk)));
        assert.equal(Buffer.concat(storedChunks).toString('utf8'),
          chunks.join(''));
        const previewBody = JSON.parse(preview.wire);
        const applyPreview = effect.admitPreviewIdentity(
          preview.wire, previewBody.run_identity_cid,
          preview.authoringCid, requestScope, preview.keys,
          publicationLimits.maxWireBytes, publicationLimits.maxNodes,
          publicationLimits.maxDepth);
        const ledgerRoot = join(directory, 'effect-ledger');
        await mkdir(ledgerRoot);
        effectLedger = openEffectLedger({moon, root: ledgerRoot,
          authorityScopeCid: cid('e'),
          callerRequestId: 'effect-compute-request',
          maxEntryBytes: 4096});
        const rowOwners = [];
        let physicalSends = 0;
        for (const [rowIndex, change] of
          previewBody.effects[0].changes.entries()) {
          const correlation = canonicalJson(change.target_row_identity);
          const key = preview.keys[0][rowIndex];
          const locator = effect.logicalItemLocator(
            requestScope, 'program-1', 'node-1', 'save', correlation,
            64, 128, 8, 3);
          const requestWire = canonicalJson({operation: 'update',
            row: change.row_preview_cid});
          const canonicalRequestCid = `sha256:${createHash('sha256')
            .update(requestWire).digest('hex')}`;
          const basis = effect.ledgerBasis(
            requestScope, locator, key, cid('6'),
            previewBody.effects[0].effect_member_preview_cid,
            change.row_preview_cid, canonicalRequestCid, cid('0'),
            'unavailable', cid('1'), cid('2'));
          const claim = {scope: requestScope, locator, key, basis,
            intentFingerprintCid: change.row_preview_cid,
            canonicalRequestCid};
          const captured = await captureClaimedEffectResponse({
            ledger: effectLedger, claim, requestCid: canonicalRequestCid,
            execute: async () => {
              physicalSends++;
              return {observation: {useCid: cid('4'),
                statusCode: 204, body: Buffer.alloc(0)}};
            },
          });
          assert.equal(captured.claimed, true);
          const recorded = effectLedger.recordAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex: 0,
            previewRowIndex: rowIndex,
            outcomeWire: canonicalJson({result: {
              record_id: `row-${rowIndex + 1}`}, state: 'applied'}),
          });
          assert.equal(recorded.custody.created, true);
          assert.equal(effectLedger.commitAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex: 0,
            previewRowIndex: rowIndex,
          }).transition.created, true);
          rowOwners.push({claim});
        }
        assert.equal(physicalSends, 2);
        effectLedger.close();
        effectLedger = openEffectLedger({moon, root: ledgerRoot,
          authorityScopeCid: cid('e'),
          callerRequestId: 'effect-compute-request',
          maxEntryBytes: 4096});
        for (const {claim} of rowOwners) {
          const replay = await captureClaimedEffectResponse({
            ledger: effectLedger, claim,
            requestCid: claim.canonicalRequestCid,
            execute: async () => { throw new Error('EffectResent'); },
          });
          assert.equal(replay.claimed, false);
        }
        assert.equal(physicalSends, 2);
        await assert.rejects(issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: Object.freeze({}),
        }), /Foreign Effect computation Preview/u);
        await assert.rejects(issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: foreignAdmittedPreview,
        }), {code: 'MoonBitHostFailure'});
        const issuedSet = await issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: admittedPreview,
        });
        assert.equal(issuedSet.members.length, 1);
        const memberRows = JSON.parse(issuedSet.members[0].wire).rows;
        assert.equal(memberRows.length, 2);
        assert.deepEqual(memberRows.map(row => row.row_preview_cid),
          previewBody.effects[0].row_order);
        assert.equal(memberRows.every(row =>
          typeof row.outcome_receipt_cid === 'string'), true);
        const publicationOptions = {
          execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger: effectLedger, issuedSet,
          request: {
            tenantId: 'tenant-a', authorityScopeCid: cid('a'),
            publicationPolicyCid: cid('e'),
            publicationTargetCid: cid('f'),
            requestedAt: '2026-09-24T00:00:01.000Z',
          },
          attempt: {attemptId: 'effect-compute-attempt',
            fenceCid: cid('0'), externalIdempotencyKey: undefined,
            startedAt: '2026-09-24T00:00:02.000Z'},
          contractLimits: publicationLimits,
          now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
        };
        const published = await publishCompletedEffectfulRun(
          publicationOptions);
        assert.equal(published.publication.committed, true);
        assert.equal(published.publication.state, 'succeeded');
        const indexBody = JSON.parse(published.publication.index.wire);
        const finalReceipt = await store.readPublicationContract(
          indexBody.run_receipt_cid, 'run_receipt');
        assert.equal(JSON.parse(finalReceipt.wire)
          .effect_set_apply_receipt_cid, issuedSet.set.identity);
        committedPublicationKey = {
          tenantId: 'tenant-a', authorityScopeCid: cid('a'),
          runDefinitionCid: runDefinitionContract.identity,
        };
        assert.notEqual(await store.inspectCommittedIndex(
          committedPublicationKey), undefined);
        const replay = await publishCompletedEffectfulRun(
          publicationOptions);
        assert.equal(replay.publication.idempotent, true);
        assert.equal(physicalSends, 2);
      } finally {
        if (committedPublicationKey !== undefined) {
          assert.equal((await store.retireCommittedResult(
            committedPublicationKey,
            storedResults.definitions[0].identity,
          )).cleanup.status().pending, false);
          const retired = await store.retireCommittedPublicationMetadata(
            committedPublicationKey, '2026-09-24T00:00:04.000Z',
          );
          assert.equal(retired.deleted, true);
        } else if (sourceHoldingCid !== undefined) {
          assert.equal((await store.retirePhysicalHolding(
            sourceHoldingCid)).deleted, true);
        }
        if (sourcePayload?.prepared.status().pending === true) {
          await sourcePayload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramEffectPreviewPlanTerminal(
          previewInputs, 0, 10, 100)),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramCheckEffectPreviewTargetGuards(
          previewInputs, [], [], 0, 1)),
      {code: 'MoonBitHostFailure'});
    } finally {
      effectLedger?.close();
      if (storedResults !== undefined) {
        await releaseCompletedRunPreparedPayloads(storedResults, control);
        if (committedPublicationKey !== undefined) {
          assert.equal(store.status().storedBytes, 0);
          assert.equal(store.status().objectCount, 0);
        }
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('owned update Plan matches approved rows and rejects altered intent',
  async t => {
    const memberIds = ['save', 'save_again'];
    const {document, environment, mappingCid} = await effectFixture({
      writeKind: 'update', memberIds,
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared),
      effectParametersCid(prepared),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    assert.ok(admission);
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'tenant-a-scope', 'update-effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    const execution = await runCapturedEffectComputation(owned);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'update-plan-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const localEvidenceContext = admittedLocalEffectEvidenceContext(
      control, prepared, evidence, definition, invocation, observation);
    const store = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
      privateEvidenceKey: Buffer.alloc(32, 4),
    }, control);
    let storedResults, inputs, privateHoldingCid;
    const sourcePayloads = [];
    const sourceHoldings = [];
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control,
        runDefinition: control.admit('run_definition',
          moon.strategyPublicationContractJson(definition),
          publicationLimits),
        invocation: control.admit('run_invocation',
          moon.strategyPublicationContractJson(invocation),
          publicationLimits),
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
      const invocationContract = control.admit('run_invocation',
        moon.strategyPublicationContractJson(invocation),
        publicationLimits);
      sourcePayloads.push(await preparePinnedEffectSourcePayload({
        moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
        limits: moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits)),
        store, maxBytes: outputLimits.maxWireBytes, control,
        invocation: invocationContract, retention,
        sourceBindingCid: cid('c'),
        contractLimits: publicationLimits,
        localEvidenceContext,
      }));
      assert.notEqual(sourcePayloads[0].summary.artifact.identity,
        storedResults.artifacts[0].identity);
      const requestScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'two-effect-request', 128));
      const previewFor = (values, targets = values.map((_, index) =>
        index + 1)) => effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        sourcePayloads[0].summary.artifact.identity, 'update', values,
        targets, memberIds, memberIds.map((_, index) =>
          cid(String(index))), requestScope);
      const preview = previewFor([1, 2]);
      const alternateScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'two-effect-request-alternate', 128));
      const alternatePreview = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        sourcePayloads[0].summary.artifact.identity, 'update', [1, 2],
        [1, 2], memberIds, memberIds.map((_, index) =>
          cid(String(index))), alternateScope);
      assert.equal(JSON.parse(preview.wire).effect_preview_cid,
        JSON.parse(alternatePreview.wire).effect_preview_cid);
      assert.notEqual(JSON.parse(preview.wire).effects[0].changes[0]
        .row_idempotency_key,
      JSON.parse(alternatePreview.wire).effects[0].changes[0]
        .row_idempotency_key);
      const runDefinitionContract = control.admit('run_definition',
        moon.strategyPublicationContractJson(definition),
        publicationLimits);
      const authoringContext = control.admitRunEvidence(
        'authoring_context',
        canonicalJson(JSON.parse(preview.wire).authoring_context),
        publicationLimits);
      const admittedPreview = control.admitEffectComputationPreview(
        preview.wire, runDefinitionContract, authoringContext,
        publicationLimits);
      privateHoldingCid = control.effectPrivateEvidenceBinding(
        admittedPreview, store.storeAuthorityCid).holdingCid;
      for (let memberIndex = 0; memberIndex < memberIds.length;
        memberIndex++) {
        if (memberIndex === 1) {
          await assert.rejects(commitPinnedEffectSourceHolding({
            payload: sourcePayloads[0], store, control,
            preview: admittedPreview, memberIndex,
            invocation: invocationContract,
            shareFromHoldingCid: cid('9'),
          }), {code: 'PublicationPhysicalHoldingUnavailable'});
        }
        sourceHoldings.push(await commitPinnedEffectSourceHolding({
          payload: sourcePayloads[0], store, control,
          preview: admittedPreview, memberIndex,
          invocation: invocationContract,
          ...(memberIndex === 0 ? {} : {
            shareFromHoldingCid: sourceHoldings[0].holdingCid,
          }),
        }));
      }
      assert.notEqual(sourceHoldings[0].holdingCid,
        sourceHoldings[1].holdingCid);
      assert.equal(sourceHoldings[0].localManifest,
        sourceHoldings[1].localManifest);
      const duplicateIdentity = JSON.parse(preview.wire);
      duplicateIdentity.effects[1].effect_identity_cid =
        duplicateIdentity.effects[0].effect_identity_cid;
      assert.throws(() => checked(moon.strategyEffectPreviewIdentities(
        canonicalJson(duplicateIdentity), 20000, 1000, 20)),
      {code: 'MoonBitHostFailure'});
      const previewLimits = moon.clientProgramEffectPreviewInputLimits(
        20000, 1000, 20, 1000, 100, 20000, 1000, 20,
        2, 2, 100, 100);
      const foreignOwned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        bound, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(foreignOwned);
      const foreignExecution = await runCapturedEffectComputation(
        foreignOwned);
      try {
        assert.equal(foreignExecution.status, 'host-tasks-completed');
        const foreignInputs = checked(moon.clientProgramPinEffectSources(
          foreignOwned, 2));
        try {
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              owned, foreignInputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              foreignOwned, inputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
        } finally {
          assert.equal(moon.clientProgramReleaseEffectInputs(
            foreignInputs), true);
        }
      } finally {
        await foreignExecution.close();
        assert.equal(foreignExecution.cleanupPending(), false);
      }
      const conflicting = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        storedResults.artifacts[0].identity, 'update', [1, 2],
        [1, 2], memberIds, [cid('0'), cid('0')]);
      assert.throws(() => checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, conflicting.wire,
          conflicting.authoringCid, previewLimits)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0,
          canonicalJson(duplicateIdentity), preview.authoringCid,
          previewLimits)),
      {code: 'MoonBitHostFailure'});
      const previewInputs = checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, preview.wire,
          preview.authoringCid, previewLimits));
      const checkCurrent = ({sources = [cid('c'), cid('c')],
        contracts = [mappingCid, mappingCid],
        capabilities = [cid('d'), cid('d')],
        authorities = [cid('e'), cid('e')]} = {}) => checked(
        moon.clientProgramCheckEffectPreviewCurrentBindings(
          previewInputs, sources, contracts, capabilities, authorities,
          2, 8));
      assert.doesNotThrow(() => checkCurrent());
      const capability = (evidence = cid('d'), route = 0,
        reconciliation = 1) => checked(
        moon.clientProgramEffectApplyCapabilityFromCodes(
          evidence, route, 0, 0, true, true, 2, reconciliation));
      const selectedRoutes = [capability(), capability()];
      assert.equal(moon.clientProgramEffectApplyCapabilityIdempotencyMode(
        selectedRoutes[0]), 'unavailable');
      assert.equal(moon.clientProgramEffectApplyCapabilityReconciliationMode(
        selectedRoutes[0]), 'manual');
      const checkRoutes = routes => checked(
        moon.clientProgramCheckEffectPreviewCapabilities(
          previewInputs, routes, 2, 2));
      assert.doesNotThrow(() => checkRoutes(selectedRoutes));
      assert.throws(() => checkRoutes([selectedRoutes[0]]),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('f')),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('d'), 1),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('d'), 0, 2),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      const riskFor = (claims, previewCid =
        JSON.parse(preview.wire).effect_preview_cid) => {
        const body = {
          version: 'actql-effect-risk-acceptance/0.1',
          issuer_kind: 'policy', issuer_evidence_cid: cid('a'),
          policy_cid: cid('a'), decision: 'allow',
          effect_preview_cid: previewCid,
          review_projection_cid: cid('a'), authority_scope_cid: cid('e'),
          validity_evidence_cid: cid('a'), claims,
          authentication_evidence_cid: cid('a'),
        };
        return canonicalJson({...body,
          self_cid: `sha256:${createHash('sha256')
            .update(canonicalJson(body)).digest('hex')}`});
      };
      const admittedRisk = wire => checked(
        moon.clientProgramAdmitEffectRiskAcceptanceBody(
          wire, 8192, 256, 12));
      const risk = admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted']));
      const unsignedRisk = JSON.parse(riskFor(
        ['effect_scope_approved', 'partial_application_accepted']));
      delete unsignedRisk.self_cid;
      delete unsignedRisk.authentication_evidence_cid;
      assert.equal(moon.clientProgramEffectRiskUnsignedPayloadCid(risk),
        `sha256:${createHash('sha256')
          .update(canonicalJson(unsignedRisk)).digest('hex')}`);
      const checkRisk = (body, {
        projection = cid('a'), authority = cid('e'), policy = cid('a'),
        validity = cid('a'), issuer = cid('a'), authentication = cid('a'),
        issuerKind = 'policy', decision = 'allow',
        requirePartialApplication = false,
      } = {}) => checked(
        moon.clientProgramCheckEffectRiskAcceptanceBody(
          previewInputs, body, projection, authority,
          policy, validity, issuer, authentication,
          issuerKind, decision, requirePartialApplication));
      assert.doesNotThrow(() => checkRisk(risk));
      assert.doesNotThrow(() => checkRisk(risk,
        {requirePartialApplication: true}));
      // D2.multi-delegate-deferred: two members, [effect_scope_approved]
      // alone is admissible unless the Host policy requires the risk claim.
      const scopeOnlyRisk = admittedRisk(riskFor(['effect_scope_approved']));
      assert.doesNotThrow(() => checkRisk(scopeOnlyRisk));
      // D2.host-required-claim: the Host-declared requirement is enforced.
      assert.throws(() => checkRisk(scopeOnlyRisk,
        {requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(admittedRisk(riskFor(
        ['partial_application_accepted']))), {code: 'MoonBitHostFailure'});
      for (const field of ['projection', 'authority', 'policy', 'validity',
        'issuer', 'authentication']) {
        assert.throws(() => checkRisk(risk, {[field]: cid('f')}),
          {code: 'MoonBitHostFailure'});
      }
      assert.throws(() => checkRisk(risk, {issuerKind: 'human'}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(risk, {decision: 'approved'}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted'],
        cid('f')))), {code: 'MoonBitHostFailure'});
      assert.throws(() => admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted'])
        .replace('"decision":"allow"', '"decision":"approved"')),
      {code: 'MoonBitHostFailure'});
      const checkKeys = keys => checked(
        moon.clientProgramCheckEffectPreviewApplyKeys(
          previewInputs, requestScope, keys, 4, 10));
      assert.doesNotThrow(() => checkKeys(preview.keys));
      assert.throws(() => checked(
        moon.clientProgramCheckEffectPreviewApplyKeys(
          previewInputs, requestScope, preview.keys, 4, 5)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkKeys(preview.keys.slice(0, 1)),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkKeys(preview.keys.map(rows =>
        [rows[1], rows[0]])), {code: 'MoonBitHostFailure'});
      const foreignScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'foreign-request', 128));
      const foreignKey = checked(moon.strategyEffectDispatchKey(
        foreignScope, JSON.parse(preview.wire).effect_preview_cid,
        canonicalJson(1), 128, 8, 3));
      assert.throws(() => checkKeys([
        [foreignKey, preview.keys[0][1]], preview.keys[1],
      ]), {code: 'MoonBitHostFailure'});
      const progressRoot = join(directory, 'effect-ledger');
      await mkdir(progressRoot);
      const openProgress = () => openEffectLedger({moon,
        root: progressRoot, authorityScopeCid: cid('e'),
        callerRequestId: 'two-effect-request', maxEntryBytes: 4096});
      const effect = runtimeCore(moon).effectApplicationControl;
      const progressMembers = JSON.parse(preview.wire).effects.map(
        (member, memberIndex) => ({claims: member.changes.map(
          (change, rowIndex) => {
            const correlation = canonicalJson(change.target_row_identity);
            const key = preview.keys[memberIndex][rowIndex];
            const locator = effect.logicalItemLocator(
              requestScope, 'program-1', 'node-1', member.effect_id,
              correlation, 64, 128, 8, 3);
            const requestPath = `/effect/${member.effect_id}/${rowIndex}`;
            const requestBody = canonicalJson({
              row_preview_cid: change.row_preview_cid,
            });
            const canonicalRequestCid = `sha256:${createHash('sha256')
              .update(canonicalJson({method: 'PATCH', path: requestPath,
                body: requestBody})).digest('hex')}`;
            const intentFingerprintCid = change.row_preview_cid;
            const basis = effect.ledgerBasis(
              requestScope, locator, key, cid('6'),
              member.effect_member_preview_cid, intentFingerprintCid,
              canonicalRequestCid, cid('0'), 'unavailable', cid('1'), cid('2'));
            return {scope: requestScope, locator, key, basis,
              intentFingerprintCid, canonicalRequestCid,
              requestPath, requestBody};
          })}));
      const ready = ledger => {
        const frontier = ledger.frontierFromCapturedHeads(
          previewInputs, progressMembers, 64);
        return Array.from({length: effect.setFrontierReadyCount(frontier)},
          (_, index) => [effect.setFrontierReadyMember(frontier, index),
            effect.setFrontierReadyRow(frontier, index)]);
      };
      assert.throws(() => checkCurrent({capabilities: [cid('d')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({sources: [cid('c'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({contracts: [mappingCid, cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({capabilities: [cid('d'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({authorities: [cid('e'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const planLimits = {
        maxFields: 10, maxWork: 100, maxBytes: 20000,
        maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000,
      };
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0, limits,
        planLimits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.match(verified.logicalCid, /^sha256:[0-9a-f]{64}$/);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), true);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 1), false);
      const secondChunks = [];
      const second = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 1, limits,
        planLimits,
        onChunk: async chunk => { secondChunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(secondChunks.join('')),
        [{id: 1}, {id: 2}]);
      assert.notEqual(second.proof, verified.proof);
      assert.doesNotThrow(() => checked(
        moon.clientProgramCheckEffectPlanProofs(
          previewInputs, [second.proof, verified.proof], 2, 4)));
      const guardRows = JSON.parse(preview.wire).effects.flatMap(member =>
        member.changes.map(change => change.row_preview_cid));
      const preflight = ({proofs = [second.proof, verified.proof],
        sources = [cid('c'), cid('c')],
        contracts = [mappingCid, mappingCid],
        capabilities = [cid('d'), cid('d')],
        authorities = [cid('e'), cid('e')],
        observedRows = guardRows,
        guardVersions = guardRows.map(() => cid('6')),
        routes = selectedRoutes, riskBody = risk,
        requirePartialApplication = false,
        keys = preview.keys} = {}) => {
        const result = moon.clientProgramCheckEffectApplyPreflight(
          previewInputs, proofs, sources, contracts, capabilities,
          authorities, observedRows, guardVersions, routes,
          riskBody ?? undefined, requirePartialApplication,
          cid('a'), cid('e'), cid('a'), cid('a'), cid('a'), cid('a'),
          'policy', 'allow', requestScope, keys, 2, 4, 4, 100);
        return checked(result);
      };
      assert.doesNotThrow(() => preflight());
      const recoveredPreflight = ({sources = [cid('c'), cid('c')],
        observedRows = guardRows,
        guardVersions = guardRows.map(() => cid('6')),
        keys = preview.keys} = {}) => checked(
        moon.clientProgramCheckRecoveredEffectApplySemantics(
          moon.clientProgramEffectPreviewLedgerIdentity(previewInputs),
          sources, [mappingCid, mappingCid], [cid('d'), cid('d')],
          [cid('e'), cid('e')], observedRows, guardVersions,
          selectedRoutes, risk ?? undefined, false,
          cid('a'), cid('e'), cid('a'), cid('a'),
          cid('a'), cid('a'), 'policy', 'allow', requestScope, keys,
          2, 4, 4, 100));
      assert.doesNotThrow(() => recoveredPreflight());
      assert.throws(() => recoveredPreflight({
        sources: [cid('c'), cid('f')],
      }), {code: 'MoonBitHostFailure'});
      assert.throws(() => recoveredPreflight({
        guardVersions: guardRows.map(() => cid('9')),
      }), {code: 'MoonBitHostFailure'});
      const runEvidence = evidence.slice(0, 3).map((value, index) =>
        control.admitRunEvidence(
          ['bound_invocation_template', 'prepared_invocation',
            'run_authorization'][index],
          moon.strategyRunEvidenceJson(value), publicationLimits));
      const compiledPlan = control.admit('compiled_plan',
        moon.strategyPublicationContractJson(evidence[3]),
        publicationLimits);
      const runAdmission = control.admitCheckedClientEffectRunPublication(
        prepared, ...runEvidence, compiledPlan);
      const normalizationJournal = control.sealRunEvidence(
        'normalization_journal', JSON.stringify({
          version: 'actql-normalization-journal/0.1',
          rule_catalog_cid: cid('1'), entries: [],
        }), publicationLimits);
      const computation = await issueCompletedEffectfulComputationEvidence({
        execution, store, storedResults, control, admission: runAdmission,
        runDefinition: runDefinitionContract,
        invocation: invocationContract,
        observation: control.admitRunEvidence('observation_set',
          moon.strategyRunEvidenceJson(observation), publicationLimits),
        normalizationJournal, authoringContext,
        receiptEvidence: {bindings: [], sourceEvidence: [],
          modelEvidence: [], barrierAttemptReceiptCids: []},
        captureEvidence: {pendingSourceStateAdvances: [],
          modelEvidence: []},
        preview: admittedPreview,
        plans: [{name: memberIds[0], wire: chunks.join('')},
          {name: memberIds[1], wire: secondChunks.join('')}],
        effectSourceHoldings: sourceHoldings,
        connectorRecovery: [],
        contractLimits: publicationLimits,
      });
      const captured = JSON.parse(computation.capturedRun.wire);
      assert.deepEqual(Object.keys(captured.effect_context
        .effect_source_holding_cids).sort(), memberIds);
      assert.deepEqual(Object.keys(captured.effect_context
        .result_artifacts), ['answer']);
      assert.deepEqual(memberIds.map(id => captured.effect_context
        .effect_source_artifacts[id].source_result), ['rows', 'rows']);
      assert.throws(() => preflight({proofs: [verified.proof]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({sources: [cid('c'), cid('f')]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({observedRows: [cid('1')]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({routes: [selectedRoutes[0]]}),
        {code: 'MoonBitHostFailure'});
      // D2.multi-allow / D2.no-contract-floor: an account allow carries no
      // risk body and the two-member set passes whole-set preflight.
      // `null` means the Host holds no risk body (passed as absent).
      assert.doesNotThrow(() => preflight({riskBody: null}));
      assert.doesNotThrow(() => preflight({riskBody: scopeOnlyRisk}));
      // D2.host-required-claim: only a Host-declared policy requires it.
      assert.throws(() => preflight({riskBody: null,
        requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({riskBody: scopeOnlyRisk,
        requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.doesNotThrow(() => preflight({requirePartialApplication: true}));
      assert.throws(() => preflight({riskBody: admittedRisk(riskFor(
        ['effect_scope_approved'], cid('f')))}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({keys: preview.keys.slice(0, 1)}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const altered = previewFor([1, 99]);
      const alteredInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, altered.wire,
        altered.authoringCid, previewLimits));
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, alteredInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        alteredInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const partial = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: alteredInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { partial.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(partial.length, 1);
      const swapped = previewFor([1, 2], [2, 1]);
      const swappedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, swapped.wire,
        swapped.authoringCid, previewLimits));
      const swappedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: swappedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { swappedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(swappedChunks, []);
      const omitted = previewFor([]);
      const omittedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, omitted.wire,
        omitted.authoringCid, previewLimits));
      const omittedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: omittedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { omittedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(omittedChunks, []);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
      // Explicit Host account for this Effect commit: allow the Effect
      // operation on the Host-derived connection/resource. No risk claim is
      // fabricated.
      const effectAuthorization = {
        gate: await fixtureAuthorization([accountEntry('crm-effect',
          'allow', {connection: 'crm', resource: 'Account',
            operation: 'effect'}),
        accountEntry('crm-target-read', 'allow', {connection: 'crm',
          resource: 'Account', operation: 'read'})]),
        scopes: [{connection: 'crm', resource: 'Account'},
          {connection: 'crm', resource: 'Account'}],
      };
      const applyOptions = {
        moon, capturedInputs: previewInputs, members: progressMembers,
        maxFrontierWork: 64,
        refreshPreflight: async ({preflight}) => preflight,
        authorization: effectAuthorization,
        preflight: {
          proofs: [second.proof, verified.proof],
          sources: [cid('c'), cid('c')],
          contracts: [mappingCid, mappingCid],
          capabilities: [cid('d'), cid('d')],
          authorities: [cid('e'), cid('e')],
          observedRows: guardRows,
          guardVersions: guardRows.map(() => cid('6')),
          routes: selectedRoutes, risk,
          reviewProjectionCid: cid('a'),
          authorityScopeCid: cid('e'), policyCid: cid('a'),
          validityCid: cid('a'), issuerCid: cid('a'),
          authenticationCid: cid('a'), issuerKind: 'policy',
          decision: 'allow', requestScope, keys: preview.keys,
          maxMembers: 2, maxRows: 4, maxFootprintWork: 4,
          maxWork: 100,
        },
      };
      const firstProgress = openProgress();
      try {
        assert.deepEqual(ready(firstProgress), [[0, 0], [1, 0]]);
        // Effect commit is protected: no Host gate, no dispatch.
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress, authorization: undefined,
          dispatchRow: () => assert.fail('unauthorized commit sent a row'),
        }), {code: 'EffectApplyAuthorizationRequired'});
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          authorization: {...effectAuthorization,
            gate: await fixtureAuthorization([accountEntry('read-only',
              'allow', {operation: 'read'})])},
          dispatchRow: () => assert.fail('no-match commit sent a row'),
        }), error => error.code === 'ExecutionAuthorizationDenied' &&
          error.authorization.boundary === 'effect_commit' &&
          error.authorization.tuple.operation === 'effect');
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          preflight: {...applyOptions.preflight,
            sources: [cid('c'), cid('f')]},
          dispatchRow: () => assert.fail('stale preflight sent a row'),
        }), {code: 'MoonBitHostFailure'});
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          dispatchRow: async () => {},
        }), {code: 'EffectApplyDidNotAdvance'});
        for (const member of progressMembers) {
          for (const claim of member.claims) {
            assert.equal(effect.ledgerEntryStateCode(
              firstProgress.currentAdmitted(
                effect.logicalItemLocatorCid(claim.locator))), 0);
          }
        }
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          dispatchRow: ({memberIndex, rowIndex, claim}) => {
            assert.deepEqual([memberIndex, rowIndex], [0, 0]);
            assert.equal(firstProgress.claimDispatch(claim).claimed, true);
            throw new Error('LostEffectResponse');
          },
        }), {message: 'LostEffectResponse'});
        assert.deepEqual(ready(firstProgress), [[1, 0]]);
      } finally {
        firstProgress.close();
      }
      const reopenedProgress = openProgress();
      try {
        assert.deepEqual(ready(reopenedProgress), [[1, 0]]);
        assert.equal(reopenedProgress.claimDispatch(
          progressMembers[0].claims[0]).claimed, false);
      } finally {
        reopenedProgress.close();
      }
      const applyPreview = effect.admitPreviewIdentity(
        preview.wire, JSON.parse(preview.wire).run_identity_cid,
        preview.authoringCid, requestScope, preview.keys,
        20000, 1000, 20);
      const seenRequests = [];
      const endpoint = createServer(async (request, response) => {
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        seenRequests.push({method: request.method, path: request.url,
          body: Buffer.concat(chunks).toString('utf8')});
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(canonicalJson({ok: true}));
      });
      await new Promise(resolve => endpoint.listen(0, '127.0.0.1', resolve));
      t.after(() => new Promise(resolve => endpoint.close(resolve)));
      const sendRow = (ledger, claim) => captureClaimedEffectResponse({
        ledger, claim, requestCid: claim.canonicalRequestCid,
        execute: async () => {
          const reply = await fetch(
            `http://127.0.0.1:${endpoint.address().port}` +
              claim.requestPath,
            {method: 'PATCH', body: claim.requestBody});
          return {observation: {useCid: cid('4'),
            statusCode: reply.status,
            body: Buffer.from(await reply.arrayBuffer())}};
        },
      });
      const beforeProjection = openProgress();
      try {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: beforeProjection,
          dispatchRow: async ({memberIndex, rowIndex, claim}) => {
            assert.deepEqual([memberIndex, rowIndex], [1, 0]);
            assert.equal((await sendRow(beforeProjection, claim)).claimed,
              true);
            throw new Error('CrashAfterSavedEffectResponse');
          },
        }), {message: 'CrashAfterSavedEffectResponse'});
        assert.equal(seenRequests.length, 1);
      } finally {
        beforeProjection.close();
      }
      const resumedProgress = openProgress();
      try {
        const possible = progressMembers[0].claims[0];
        const replay = await captureClaimedEffectResponse({
          ledger: resumedProgress, claim: possible,
          requestCid: possible.canonicalRequestCid,
          execute: async () => { throw new Error('UnknownRowResent'); },
        });
        assert.equal(replay.claimed, false);
        const savedClaim = progressMembers[1].claims[0];
        const saved = resumedProgress.readClaimedResponse(savedClaim);
        assert.equal(saved.statusCode, 200);
        assert.equal(saved.responseBytes.toString('utf8'),
          canonicalJson({ok: true}));
        const savedReplay = await captureClaimedEffectResponse({
          ledger: resumedProgress, claim: savedClaim,
          requestCid: savedClaim.canonicalRequestCid,
          execute: async () => { throw new Error('SavedRowResent'); },
        });
        assert.equal(savedReplay.claimed, false);
        assert.deepEqual(ready(resumedProgress), []);
        resumedProgress.recordAdmittedRowOutcome({
          claim: savedClaim, preview: applyPreview, memberIndex: 1,
          previewRowIndex: 0,
          outcomeWire: canonicalJson({state: 'applied',
            result: {record_id: 'row-1'}}),
        });
        resumedProgress.commitAdmittedRowOutcome({
          claim: savedClaim, preview: applyPreview, memberIndex: 1,
          previewRowIndex: 0,
        });
        const advanced = await applyCapturedEffectSet({
          ...applyOptions, ledger: resumedProgress,
          dispatchRow: async ({memberIndex, rowIndex, claim}) => {
            assert.equal(memberIndex, 1);
            assert.deepEqual(ready(resumedProgress), [[1, rowIndex]]);
            const response = await sendRow(resumedProgress, claim);
            assert.equal(response.claimed, true);
            resumedProgress.recordAdmittedRowOutcome({
              claim, preview: applyPreview, memberIndex,
              previewRowIndex: rowIndex,
              outcomeWire: canonicalJson({state: 'applied',
                result: {record_id: `row-${rowIndex + 1}`}}),
            });
            resumedProgress.commitAdmittedRowOutcome({
              claim, preview: applyPreview, memberIndex,
              previewRowIndex: rowIndex,
            });
          },
        });
        assert.equal(advanced.dispatched, 1);
        assert.deepEqual(ready(resumedProgress), []);
        assert.deepEqual(seenRequests, progressMembers[1].claims.map(
          claim => ({method: 'PATCH', path: claim.requestPath,
            body: claim.requestBody})));
        const settled = await applyCapturedEffectSet({
          ...applyOptions, ledger: resumedProgress,
          authorization: undefined, refreshPreflight: undefined,
          dispatchRow: () => assert.fail('settled or unknown row resent'),
        });
        assert.equal(settled.status, 'applied');
        assert.equal(settled.dispatched, 0);
        const issued = await issueAuthorizedEffectSetReceipt({
          ledger: resumedProgress, preview: applyPreview,
          commonMoon: moon, authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: progressMembers.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: false,
          })),
          limits: publicationLimits,
        });
        assert.equal(JSON.parse(issued.set.wire).status,
          'unknown_outcome');
        assert.deepEqual(JSON.parse(issued.set.wire).effects.map(
          member => member.state), ['unknown', 'applied']);
        await assert.rejects(publishCompletedEffectfulRun({
          execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger: resumedProgress,
          issuedSet: issued,
          request: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
            publicationPolicyCid: cid('e'),
            publicationTargetCid: cid('f'),
            requestedAt: '2026-09-24T00:00:01.000Z'},
          attempt: {attemptId: 'two-effect-attempt',
            fenceCid: cid('0'), externalIdempotencyKey: undefined,
            startedAt: '2026-09-24T00:00:02.000Z'},
          contractLimits: publicationLimits,
          now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
        }), {code: 'EffectfulRunNeedsReconciliation'});
        assert.equal(await store.inspectCommittedIndex({tenantId: 'tenant-a',
          authorityScopeCid: cid('a'),
          runDefinitionCid: runDefinitionContract.identity}), undefined);
        assert.ok(await store.inspectPhysicalHolding(privateHoldingCid));
        for (const holding of sourceHoldings) {
          assert.ok(await store.inspectPhysicalHolding(holding.holdingCid));
        }
      } finally {
        resumedProgress.close();
      }
      const releasedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => {
          releasedChunks.push(chunk);
          if (releasedChunks.length === 1) {
            assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
          }
        },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(releasedChunks.length, 1);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      const historicalProgress = openProgress();
      try {
        assert.deepEqual(ready(historicalProgress), []);
        assert.equal(historicalProgress.claimDispatch(
          progressMembers[1].claims[0]).claimed, false);
      } finally {
        historicalProgress.close();
      }
      assert.throws(() => checkKeys(preview.keys),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes(selectedRoutes),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(risk),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent(),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight(), {code: 'MoonBitHostFailure'});
    } finally {
      if (inputs !== undefined) {
        moon.clientProgramReleaseEffectInputs(inputs);
      }
      if (storedResults !== undefined) {
        await releaseCompletedRunPreparedPayloads(storedResults, control);
        if (privateHoldingCid !== undefined) {
          assert.equal((await store.retirePhysicalHolding(
            privateHoldingCid)).deleted, true);
        }
        for (const holding of sourceHoldings) {
          assert.equal((await store.retirePhysicalHolding(
            holding.holdingCid)).deleted, true);
        }
        for (const payload of sourcePayloads) {
          if (payload.prepared.status().pending) {
            await payload.prepared.release();
          }
        }
        assert.equal(store.status().storedBytes, 0);
        assert.equal(store.status().objectCount, 0);
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

async function verifySharedEffectSource({splitSource, expectedTask}) {
  const {document, environment} = await effectFixture({
    splitSource, splitEffectSource: 'middle',
  });
  const source = JSON.parse(document);
  const effectStage = source.stages[splitSource ? 1 : 0];
  effectStage.effects.save_again = structuredClone(effectStage.effects.save);
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(source), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
  const evidence = publicationEvidence(
    moon.clientProgramEffectDefinitionCid(prepared),
    effectParametersCid(prepared),
    moon.clientProgramEffectSemanticsCid(prepared),
    moon.clientProgramEffectEnvironmentCid(prepared));
  const admission = moon.clientProgramAdmitEffectPublication(
    prepared, ...evidence);
  assert.ok(admission);
  const definition = checked(moon.strategyIssueRunDefinition(
    admission, 'tenant-a-scope', 'two-effect-compute', cid('c'),
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
    100000, 10000, 64));
  const bound = moon.clientProgramBindEffectRun(
    prepared, admission, definition);
  assert.ok(bound);
  const [registry, contract] = await Promise.all([
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
      import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json',
      import.meta.url), 'utf8'),
  ]);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
    bound, registry, values, 1n, 0n, 0n, 0n);
  assert.ok(owned);
  assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 2);
  assert.throws(() => checked(moon.clientProgramPinEffectSources(
    owned, 2)), {code: 'MoonBitHostFailure'});
  const execution = await runCapturedInternalStrategy(
    moon.clientProgramLocalEffectHostRuntime(owned));
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.throws(() => checked(moon.clientProgramPinEffectSources(
      owned, 1)), {code: 'MoonBitHostFailure'});
    const inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
    try {
      assert.equal(moon.clientProgramEffectInputCount(inputs), 2);
      const first = moon.clientProgramEffectInputAt(inputs, 0);
      const second = moon.clientProgramEffectInputAt(inputs, 1);
      assert.ok(first);
      assert.ok(second);
      assert.notEqual(first, second);
      assert.equal(moon.clientProgramEffectInputsShareView(inputs, 0, 1),
        true);
      assert.equal(moon.clientProgramEffectInputTask(first), expectedTask);
      assert.equal(moon.clientProgramEffectInputTask(second), expectedTask);
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
      assert.equal(moon.clientProgramReleaseEffectInput(first), true);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), true);
      assert.equal(moon.clientProgramEffectInputsShareView(inputs, 0, 1),
        false);
      const chunks = [];
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const exported = await exportPinnedEffectInput({
        moon, execution, inputs, memberIndex: 1, limits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.deepEqual(exported.fields, ['id']);
      assert.equal(moon.clientProgramReleaseEffectInput(first), false);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 2)), {code: 'MoonBitHostFailure'});
    } finally {
      assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
    }
    assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), false);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
}

// Effect commit authorization over the real two-member captured Effect Run.
// Offline: the provider is a local HTTP mock that counts PATCH requests per
// row path, the Effect ledger and the Checkpoint journal are real SQLite
// stores reopened to model process restarts, and reviewer/Host signatures are
// test Ed25519 keys behind the journal's Host ports.
const commitReviewer = generateKeyPairSync('ed25519');
const commitHost = generateKeyPairSync('ed25519');
const commitCid = value =>
  `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const commitIso = ms => new Date(ms).toISOString();
const commitBinding = Object.freeze({
  authorizationContextCid: FIXTURE_CONTEXT.contextCid,
  environmentBindingCid: cid('e'),
});
const commitRunDefinitionCid = cid('1');

async function openCommitJournal(root, clock) {
  return openSqliteCheckpointJournal(root, {
    runtime: await loadCheckpointRuntime(),
    authorizeResolution({resolutionWire, proofPreimage}) {
      const resolution = JSON.parse(resolutionWire);
      if (resolution.proof.key_id !== 'reviewer-key' ||
          !verify(null, Buffer.from(proofPreimage, 'utf8'),
            commitReviewer.publicKey,
            Buffer.from(resolution.proof.signature, 'base64'))) {
        throw new Error('UntrustedResolution');
      }
      return {keyId: 'reviewer-key', reviewerId: 'reviewer',
        authorityContextCid: cid('c'), policyCid: cid('d'),
        verifiedPreimage: proofPreimage};
    },
    attestResolution: preimage => ({hostKeyId: 'host-key',
      signature: sign(null, Buffer.from(preimage, 'utf8'),
        commitHost.privateKey).toString('base64')}),
    now: () => clock.ms,
  });
}

// Host deferral: persist one Effect Commit Checkpoint that seals the exact
// Effect Set Preview (the gate supplies the subject CID). A Host policy that
// requires the risk claim adds it to the Checkpoint requirements.
function commitDeferral(journal, clock, runId, requirements) {
  return {
    journal,
    authorities: [{keyId: 'reviewer-key', reviewerId: 'reviewer'}],
    binding: commitBinding,
    describe: view => ({
      priorStatus: 'running',
      declaredResults: ['answer'],
      body: {
        checkpoint_id: `${runId}-commit`,
        run_id: runId,
        run_definition_cid: commitRunDefinitionCid,
        continuation_state_cid: cid('2'),
        subject: {kind: 'run_unit', run_id: runId, unit_id: 'effect-commit',
          continuation: 'resume_unit'},
        ...(requirements === undefined ? {} : {requirements}),
        required_artifact: {artifact_cid: view.subject.subject_cid},
        review_projection_cid: cid('4'),
        human_summary: 'Apply the two-member Effect Set',
        created_at: commitIso(clock.ms),
        expires_at: commitIso(clock.ms + 86_400_000),
      },
    }),
  };
}

async function answerCommitCheckpoint(journal, checkpointCid, decision,
  clock, {unknownEffects} = {}) {
  const view = journal.inspect(checkpointCid);
  let evidence;
  if (decision === 'approved') {
    const attestation = {
      version: 'actql-approval-attestation/0.1',
      effect_preview_cid: view.requiredArtifact.cid,
      review_projection_cid: view.reviewProjectionCid,
      approver: 'reviewer', approved_at: commitIso(clock.ms),
      authority_scope_cid: cid('5'), claims: [...view.requirements],
      proof: {scheme: 'ed25519-v1', key_id: 'reviewer-key',
        signature: 'c2lnbmF0dXJl'},
    };
    attestation.attestation_cid = commitCid(attestation);
    evidence = {
      version: 'actql-checkpoint-approval-evidence/0.1', kind: 'effect_set',
      checkpoint_cid: view.checkpointCid,
      review_projection_cid: view.reviewProjectionCid,
      compatibility_approval: attestation,
    };
  }
  const body = {
    version: 'actql-checkpoint-resolution/0.1',
    resolution_id: `resolution-${decision}`,
    checkpoint_id: view.checkpointId, checkpoint_cid: view.checkpointCid,
    run_id: view.runId, run_definition_cid: commitRunDefinitionCid,
    decision, actor: 'reviewer', decided_at: commitIso(clock.ms),
    required_artifact_cid: view.requiredArtifact.cid,
    review_projection_cid: view.reviewProjectionCid,
    ...(evidence ? {approval_evidence_cid: commitCid(evidence)} : {}),
  };
  body.proof = {scheme: 'ed25519-v1', key_id: 'reviewer-key',
    signature: sign(null, Buffer.from(commitCid(body), 'utf8'),
      commitReviewer.privateKey).toString('base64')};
  body.resolution_cid = commitCid(body);
  const answer = {checkpointCid, resolutionWire: JSON.stringify(body),
    approvalEvidenceWire: evidence ? JSON.stringify(evidence) : '',
    ...(unknownEffects === undefined ? {} : {unknownEffects})};
  // The committed result carries the verified Resolution the Host presents
  // on resume; after a restart the same answer is resubmitted and the
  // journal returns the stored Resolution as a duplicate.
  return {...await journal.submitResolution(answer), answer};
}

async function openCountingProvider(t) {
  const requests = [];
  const loseReply = new Set();
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    requests.push({method: request.method, path: request.url});
    // The provider applied the write; only its reply is lost.
    if (loseReply.delete(request.url)) {
      request.socket.destroy();
      return;
    }
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(canonicalJson({ok: true}));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => {
    server.closeAllConnections();
    server.close(resolve);
  }));
  return Object.freeze({
    requests, loseReply,
    origin: `http://127.0.0.1:${server.address().port}`,
    // PATCH writes observed by the provider since `since`, optionally for
    // one row path.
    mark: () => requests.length,
    writes: (since = 0, path) => requests.slice(since).filter(item =>
      item.method === 'PATCH' &&
      (path === undefined || item.path === path)).length,
  });
}

function ledgerEntryCount(root) {
  const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'),
    {readOnly: true});
  try {
    return database.prepare(
      'SELECT count(*) AS n FROM effect_ledger_entries').get().n;
  } finally {
    database.close();
  }
}

async function verifyEffectCommitAuthorization(t, {
  moon, previewInputs, members, preflight, applyPreview, body, directory,
  memberIds,
}) {
  const provider = await openCountingProvider(t);
  const rowPaths = members.flatMap(member =>
    member.claims.map(claim => claim.path));
  const totalRows = rowPaths.length;
  const subjectCid = moon.clientProgramEffectApplySubjectCid(previewInputs);
  // The decision subject is the sealed Set Preview semantic identity.
  assert.equal(subjectCid, body.effect_preview_cid);
  assert.equal(moon.clientProgramEffectApplyMemberCount(previewInputs),
    memberIds.length);
  const scopes = memberIds.map(() => ({connection: 'crm',
    resource: 'Account'}));
  // Operation dimension: the Effect class of the Read/Write/Effect
  // operation classification.
  const allowAccount = [accountEntry('crm-effect', 'allow',
    {connection: 'crm', resource: 'Account', operation: 'effect'})];
  const delegateAccount = [accountEntry('crm-effect', 'delegate',
    {connection: 'crm', resource: 'Account', operation: 'effect'})];
  const commitGate = (entries, options) => fixtureAuthorization([
    ...entries,
    accountEntry('scenario-target-read', 'allow', {operation: 'read'}),
  ], options);
  // The reviewer answering a deferred decision is one of the Host's
  // answering authorities; its committed approval is admitted as the permit.
  const hostOptions = (answer, extra = {}) => ({
    answeringAuthorities: ['host-policy', 'reviewer'],
    decide: view => answer === 'defer'
      ? {decision: 'defer', subject: view.subject}
      : {decision: answer, subject: view.subject, authority: 'host-policy',
        claims: []},
    ...extra,
  });
  let rootSequence = 0;
  const workspace = async () => {
    const root = join(directory, `commit-authorization-${++rootSequence}`);
    await mkdir(root);
    return {ledgerRoot: join(root, 'ledger'),
      journalRoot: join(root, 'journal')};
  };
  const openScenarioLedger = root => openEffectLedger({moon, root,
    authorityScopeCid: cid('e'),
    callerRequestId: 'complete-two-effects-request', maxEntryBytes: 4096});
  // Mock provider dispatch through the durable ledger claim.
  const dispatcher = (ledger, calls, {loseReplyAt} = {}) =>
    async ({memberIndex, rowIndex, claim}) => {
      calls.push([memberIndex, rowIndex]);
      if (loseReplyAt?.(calls.length)) provider.loseReply.add(claim.path);
      const response = await captureClaimedEffectResponse({
        ledger, claim, requestCid: claim.canonicalRequestCid,
        execute: async () => {
          const reply = await fetch(provider.origin + claim.path,
            {method: 'PATCH', body: claim.path});
          return {observation: {useCid: cid('4'), statusCode: reply.status,
            body: Buffer.from(await reply.arrayBuffer())}};
        },
      });
      assert.equal(response.claimed, true);
      ledger.recordAdmittedRowOutcome({
        claim, preview: applyPreview, memberIndex, previewRowIndex: rowIndex,
        outcomeWire: canonicalJson({state: 'applied',
          result: {record_id: `member-${memberIndex}-row-${rowIndex}`}}),
      });
      ledger.commitAdmittedRowOutcome({claim, preview: applyPreview,
        memberIndex, previewRowIndex: rowIndex});
    };
  const apply = (ledger, gate, dispatchRow, extra = {}) =>
    applyCapturedEffectSet({moon, capturedInputs: previewInputs,
      preflight: {...preflight, ...extra.preflight}, ledger, members,
      maxFrontierWork: 64, dispatchRow, signal: undefined,
      refreshPreflight: async ({preflight}) => preflight,
      authorization: {gate, scopes, resume: extra.resume}});
  const refused = (gate, code, check = () => true) => async () => {
    const {ledgerRoot} = await workspace();
    const ledger = openScenarioLedger(ledgerRoot);
    const writesBefore = provider.mark();
    const calls = [];
    try {
      await assert.rejects(apply(ledger, gate, dispatcher(ledger, calls)),
        error => error.code === code && check(error));
      return {calls: calls.length, writes: provider.writes(writesBefore),
        entries: ledgerEntryCount(ledgerRoot)};
    } finally {
      ledger.close();
    }
  };
  const counts = {};

  // (a) D2.multi-allow: account allow, no delegated call, no Checkpoint and
  // no risk claim; every row is dispatched once.
  {
    const {ledgerRoot} = await workspace();
    const ledger = openScenarioLedger(ledgerRoot);
    const gate = await commitGate(allowAccount);
    const calls = [];
    const writesBefore = provider.mark();
    try {
      const applied = await apply(ledger, gate, dispatcher(ledger, calls));
      assert.equal(applied.status, 'applied');
      assert.equal(applied.dispatched, totalRows);
      assert.equal(applied.subjectCid, subjectCid);
      assert.equal(applied.authorization[0].basis, 'account_allow');
      assert.equal(preflight.risk, undefined);
      const counters = gate.counters();
      assert.equal(counters.hostDecisionCalls, 0);
      assert.equal(counters.checkpointsPersisted, 0);
      counts.a = {dispatched: applied.dispatched,
        writes: provider.writes(writesBefore),
        entries: ledgerEntryCount(ledgerRoot)};
      assert.equal(counts.a.writes, totalRows);
    } finally {
      ledger.close();
    }
  }

  // (b) D2.account-deny: explicit deny and no-match dispatch nothing.
  counts.b = await refused(await commitGate([accountEntry(
    'crm-effect', 'deny', {connection: 'crm', resource: 'Account',
      operation: 'effect'})], hostOptions('permit')),
  'ExecutionAuthorizationDenied',
  error => error.authorization.boundary === 'effect_commit' &&
    error.authorization.basis === 'account' &&
    error.authorization.reason === 'explicit')();
  counts.bNoMatch = await refused(await commitGate([accountEntry(
    'crm-read', 'allow', {operation: 'read'})]),
  'ExecutionAuthorizationDenied',
  error => error.authorization.reason === 'no_match')();

  // (c) D2.multi-delegate-immediate: immediate permit, no claim required.
  {
    const {ledgerRoot} = await workspace();
    const ledger = openScenarioLedger(ledgerRoot);
    const gate = await commitGate(delegateAccount,
      hostOptions('permit'));
    const calls = [];
    const writesBefore = provider.mark();
    try {
      const applied = await apply(ledger, gate, dispatcher(ledger, calls));
      assert.equal(applied.dispatched, totalRows);
      assert.equal(applied.authorization[0].basis, 'host_permit');
      assert.equal(gate.counters().hostDecisionCalls, 1);
      assert.equal(gate.counters().checkpointsPersisted, 0);
      counts.c = {dispatched: applied.dispatched,
        writes: provider.writes(writesBefore),
        entries: ledgerEntryCount(ledgerRoot)};
    } finally {
      ledger.close();
    }
  }

  // (d) Immediate reject: a recorded Host rejection, nothing dispatched.
  counts.d = await refused(await commitGate(delegateAccount,
    hostOptions('reject')), 'ExecutionAuthorizationDenied',
  error => error.authorization.basis === 'rejected_by_host')();

  // (e) D2.host-required-claim: the Host policy requires
  // partial_application_accepted; a permit without it is not an accepted
  // delegation, and preflight alone also refuses a missing required claim.
  counts.e = await refused(await commitGate(delegateAccount,
    hostOptions('permit',
      {requiredClaims: ['partial_application_accepted']})),
  'ExecutionAuthorizationDecisionFailed',
  error => /MissingRequiredClaim/.test(error.authorization.detail))();
  {
    const {ledgerRoot} = await workspace();
    const ledger = openScenarioLedger(ledgerRoot);
    try {
      await assert.rejects(apply(ledger,
        await commitGate(allowAccount),
        () => assert.fail('required claim missing but dispatched'),
        {preflight: {requirePartialApplication: true}}),
      {code: 'MoonBitHostFailure'});
      counts.ePreflight = {entries: ledgerEntryCount(ledgerRoot)};
      assert.equal(counts.ePreflight.entries, 0);
    } finally {
      ledger.close();
    }
  }

  // D2.decision-failure: an unavailable Host answer is not a rejection.
  counts.failure = await refused(await commitGate(delegateAccount,
    {answeringAuthorities: ['host-policy'],
      decide: () => ({decision: 'unavailable'})}),
  'ExecutionAuthorizationDecisionFailed')();
  // Defer without a durable journal is unsupported, never a permit.
  counts.unsupported = await refused(await commitGate(
    delegateAccount, hostOptions('defer')),
  'ExecutionAuthorizationDeferralUnsupported')();
  for (const name of ['b', 'bNoMatch', 'd', 'e', 'failure',
    'unsupported']) {
    assert.deepEqual(counts[name], {calls: 0, writes: 0, entries: 0}, name);
  }

  // Deferred commit: persist one Checkpoint for the complete Set Preview,
  // restart, answer, restart, then resume through the journal claim.
  const deferred = async ({runId, requirements, loseReplyAt,
    requiredClaims = []}) => {
    const deferGate = journal => commitGate(delegateAccount,
      hostOptions('defer', {requiredClaims,
        deferral: commitDeferral(journal, clock, runId, requirements)}));
    const clock = {ms: Date.parse('2026-09-24T00:00:00.000Z')};
    const {ledgerRoot, journalRoot} = await workspace();
    let journal = await openCommitJournal(journalRoot, clock);
    let ledger = openScenarioLedger(ledgerRoot);
    const calls = [];
    const writesBefore = provider.mark();
    const gate = await deferGate(journal);
    const waiting = await apply(ledger, gate, dispatcher(ledger, calls));
    // (i) Waiting holds no provider flight, no ledger entry and no claim.
    assert.equal(waiting.status, 'waiting');
    assert.equal(waiting.dispatched, 0);
    assert.equal(calls.length, 0);
    assert.equal(provider.writes(writesBefore), 0);
    assert.equal(ledgerEntryCount(ledgerRoot), 0);
    assert.equal(gate.counters().checkpointsPersisted, 1);
        assert.equal(gate.counters().protectedDispatches, 1);
    assert.equal(journal.getRunState(runId).status, 'waiting_checkpoint');
    const [pending] = journal.listPending();
    assert.equal(pending.checkpointCid, waiting.checkpoint.checkpointCid);
    assert.equal(pending.kind, 'effect_set');
    assert.equal(pending.phase, 'commit');
    assert.equal(waiting.authorization[0].subjectCid, subjectCid);
    // The Checkpoint's required artifact is the sealed Set Preview itself;
    // the decision-subject digest is kept as a separate exact binding.
    assert.equal(waiting.checkpoint.requiredArtifactCid, subjectCid);
    assert.match(waiting.checkpoint.decisionSubjectCid,
      /^sha256:[0-9a-f]{64}$/);
    assert.notEqual(waiting.checkpoint.decisionSubjectCid, subjectCid);
    assert.deepEqual(pending.requiredArtifact,
      {type: 'effect_set_preview', cid: subjectCid});
    assert.equal(pending.decisionSubjectCid,
      waiting.checkpoint.decisionSubjectCid);
    // The gate asks for partial_application_accepted only when the Host
    // requires it.
    assert.deepEqual(pending.requirements, requirements ??
      (requiredClaims.includes('partial_application_accepted')
        ? ['effect_scope_approved', 'partial_application_accepted']
        : ['effect_scope_approved']));
    // A second attempt while waiting re-derives the same sealed Checkpoint,
    // persists nothing new and sends nothing.
    const again = await apply(ledger, gate, dispatcher(ledger, calls));
    assert.equal(again.status, 'waiting');
    assert.equal(again.checkpoint.checkpointCid,
      waiting.checkpoint.checkpointCid);
    assert.equal(journal.listPending().length, 1);
    assert.equal(calls.length, 0);
    assert.equal(ledgerEntryCount(ledgerRoot), 0);
    // Process restart while waiting.
    journal.close();
    ledger.close();
    journal = await openCommitJournal(journalRoot, clock);
    ledger = openScenarioLedger(ledgerRoot);
    return {clock, ledgerRoot, journalRoot, calls, writesBefore,
      checkpointCid: waiting.checkpoint.checkpointCid,
      get journal() { return journal; },
      set journal(value) { journal = value; },
      get ledger() { return ledger; },
      set ledger(value) { ledger = value; },
      runId,
      // The Resolution is read by the gate from the journal; the caller
      // only names or takes the claim.
      resume: claimant => ({journal, runId, claimant, leaseMs: 60_000,
        binding: commitBinding}),
      claim: (claimant, leaseMs = 60_000) => journal.claimResume(runId,
        {claimant, leaseMs, binding: commitBinding}),
      gate: (over = journal) => deferGate(over),
      dispatch: (options = {}) => dispatcher(ledger, calls,
        {loseReplyAt, ...options}),
    };
  };

  // (f) D2.multi-delegate-deferred: defer -> Checkpoint -> restart ->
  // approve -> restart -> resume: every row exactly once.
  {
    const run = await deferred({runId: 'commit-run-f'});
    try {
      run.clock.ms += 60_000;
      const approved = await answerCommitCheckpoint(run.journal,
        run.checkpointCid, 'approved', run.clock);
      assert.equal(approved.decision, 'approved');
      assert.equal(approved.runState.status, 'resuming');
      run.journal.close();
      run.ledger.close();
      run.journal = await openCommitJournal(run.journalRoot, run.clock);
      run.ledger = openScenarioLedger(run.ledgerRoot);
      const stored = await run.journal.submitResolution(approved.answer);
      assert.equal(stored.outcome, 'duplicate');
      assert.equal(stored.verifiedResolutionWire,
        approved.verifiedResolutionWire);
      const gate = await run.gate();
      const applied = await apply(run.ledger, gate, run.dispatch(),
        {resume: run.resume('worker-f')});
      assert.equal(applied.status, 'applied');
      // The admission was entered once, as a fresh start, before the first
      // send, with the durable Effect Set apply identity.
      assert.equal(applied.admission.mode, 'start');
      assert.equal(applied.admission.dispatchIdentity, applied.identity);
      assert.ok(applied.identity.endsWith(`:${subjectCid}`));
      assert.equal(applied.dispatched, totalRows);
      assert.equal(applied.authorization[0].basis, 'resumed');
      assert.equal(applied.authorization[0].checkpointCid, run.checkpointCid);
      assert.equal(gate.counters().hostDecisionCalls, 0);
      assert.ok(applied.resume.generation >= 1);
      for (const path of rowPaths) {
        assert.equal(provider.writes(run.writesBefore, path), 1, path);
      }
      const done = run.journal.completeResume(applied.resume, {
        runStateWire: JSON.stringify({
          version: 'actql-run-state/0.1', run_id: 'commit-run-f',
          status: 'succeeded', updated_at: commitIso(run.clock.ms),
          next_action: {kind: 'read_result', results: ['answer']},
          result_available: true,
          result_availability: {answer: {state: 'available',
            observed_at: commitIso(run.clock.ms),
            reason: 'confirmed_present'}},
        })});
      assert.equal(done.status, 'succeeded');
      // Every row is settled: a later resume has nothing to send and takes
      // no claim; the completed intent cannot be claimed again.
      const settled = await apply(run.ledger, gate,
        () => assert.fail('completed resume resent a row'),
        {resume: run.resume('worker-f2')});
      assert.equal(settled.dispatched, 0);
      assert.deepEqual(run.claim('worker-f3'), {action: 'completed'});
      const replay = await apply(run.ledger,
        await commitGate(allowAccount),
        () => assert.fail('terminal row resent'));
      assert.equal(replay.dispatched, 0);
      counts.f = {dispatched: applied.dispatched,
        writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot),
        calls: run.calls.length};
      assert.equal(counts.f.writes, totalRows);
      assert.equal(counts.f.calls, totalRows);
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }

  // Host-required partial_application_accepted on a deferred decision:
  // (j1) the gate asks the reviewer for it and the committed evidence
  // establishes it: dispatch.
  {
    const run = await deferred({runId: 'commit-run-claim',
      requiredClaims: ['partial_application_accepted']});
    try {
      run.clock.ms += 60_000;
      const approved = await answerCommitCheckpoint(run.journal,
        run.checkpointCid, 'approved', run.clock);
      assert.equal(approved.decision, 'approved');
      const applied = await apply(run.ledger, await run.gate(),
        run.dispatch(), {resume: run.resume('worker-claim')});
      assert.equal(applied.dispatched, totalRows);
      assert.deepEqual(applied.authorization[0].claims,
        ['partial_application_accepted']);
      counts.j1 = {dispatched: applied.dispatched,
        writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot)};
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }
  // (j2) The Host requires the claim but its Checkpoint asked only for
  // effect_scope_approved: the approval evidence does not establish it, so
  // the resume is refused with 0 writes and 0 ledger appends.
  {
    const run = await deferred({runId: 'commit-run-claim-missing',
      requiredClaims: ['partial_application_accepted'],
      requirements: ['effect_scope_approved']});
    try {
      run.clock.ms += 60_000;
      await answerCommitCheckpoint(run.journal, run.checkpointCid,
        'approved', run.clock);
      await assert.rejects(apply(run.ledger, await run.gate(),
        () => assert.fail('unestablished claim dispatched'),
        {resume: run.resume('worker-claim-missing')}),
      error => error.code === 'ExecutionAuthorizationDecisionFailed' &&
        error.authorization.detail === 'RequiredClaimNotEstablished');
      counts.j2 = {writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot), calls: run.calls.length};
      assert.deepEqual(counts.j2, {writes: 0, entries: 0, calls: 0});
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }
  // (j3) A Host-required claim no Effect Set approval can establish is
  // refused at defer: no Checkpoint, no Run state, no write.
  {
    const clock = {ms: Date.parse('2026-09-24T00:00:00.000Z')};
    const {ledgerRoot, journalRoot} = await workspace();
    const journal = await openCommitJournal(journalRoot, clock);
    const ledger = openScenarioLedger(ledgerRoot);
    const writesBefore = provider.mark();
    try {
      const gate = await commitGate(delegateAccount,
        hostOptions('defer', {requiredClaims: ['invocation_scope_approved'],
          deferral: commitDeferral(journal, clock, 'commit-run-claim-bad')}));
      await assert.rejects(apply(ledger, gate,
        () => assert.fail('unrepresentable claim dispatched')),
      error => error.code === 'ExecutionAuthorizationDecisionFailed' &&
        error.authorization.detail === 'RequiredClaimUnrepresentable');
      assert.equal(gate.counters().checkpointsPersisted, 0);
      assert.deepEqual(journal.listPending(), []);
      counts.j3 = {checkpoints: journal.listPending().length,
        writes: provider.writes(writesBefore),
        entries: ledgerEntryCount(ledgerRoot)};
      assert.deepEqual(counts.j3, {checkpoints: 0, writes: 0, entries: 0});
    } finally {
      ledger.close();
      journal.close();
    }
  }

  // (k) Stale claimant: generation 1's lease lapses and generation 2 claims;
  // a resume presenting generation 1 is refused before any claim or send,
  // while generation 2 dispatches every row once.
  {
    const run = await deferred({runId: 'commit-run-stale'});
    try {
      run.clock.ms += 60_000;
      await answerCommitCheckpoint(run.journal, run.checkpointCid,
        'approved', run.clock);
      const first = run.claim('worker-k1', 1_000);
      assert.equal(first.claim.generation, 1);
      run.clock.ms += 2_000;
      const second = run.claim('worker-k2');
      assert.equal(second.claim.generation, 2);
      await assert.rejects(apply(run.ledger, await run.gate(),
        () => assert.fail('stale claimant dispatched'),
        {resume: {claim: first}}),
      error => error.code === 'ExecutionAuthorizationDecisionFailed' &&
        error.authorization.detail === 'ResumeClaimStale');
      counts.kStale = {writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot), calls: run.calls.length};
      assert.deepEqual(counts.kStale, {writes: 0, entries: 0, calls: 0});
      const current = await apply(run.ledger, await run.gate(),
        run.dispatch(), {resume: {claim: second}});
      assert.equal(current.dispatched, totalRows);
      assert.equal(current.admission.generation, 2);
      counts.kCurrent = {dispatched: current.dispatched,
        writes: provider.writes(run.writesBefore)};
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }

  // (m) D-R5: the account now allows the commit tuple. An allow asks no
  // approval but does not make the continuation anyone's to resume: a stale
  // claim is refused, the changed configuration is refused, and a resumed
  // dispatch decision without its admission sends nothing.
  {
    const run = await deferred({runId: 'commit-run-allow-resume'});
    try {
      run.clock.ms += 60_000;
      await answerCommitCheckpoint(run.journal, run.checkpointCid,
        'approved', run.clock);
      const first = run.claim('worker-m1', 1_000);
      run.clock.ms += 2_000;
      const second = run.claim('worker-m2');
      const allowGate = await commitGate(allowAccount,
        hostOptions('permit', {deferral: commitDeferral(run.journal,
          run.clock, 'commit-run-allow-resume')}));
      await assert.rejects(apply(run.ledger, allowGate,
        () => assert.fail('stale claimant dispatched under allow'),
        {resume: {claim: first}}),
      error => error.code === 'ExecutionAuthorizationDecisionFailed' &&
        error.authorization.detail === 'ResumeClaimStale');
      await assert.rejects(apply(run.ledger, allowGate,
        () => assert.fail('changed configuration dispatched'),
        {resume: {claim: second}}),
      error => error.code === 'ExecutionAuthorizationDecisionFailed' &&
        error.authorization.detail === 'ResumeConfigurationChanged');
      const gate = await run.gate();
      const stripped = Object.freeze({...gate,
        async resume(...args) {
          const {admission, ...decision} = await gate.resume(...args);
          assert.equal(typeof admission.enter, 'function');
          return Object.freeze(decision);
        }});
      await assert.rejects(apply(run.ledger, stripped,
        () => assert.fail('resumed commit without admission dispatched'),
        {resume: {claim: second}}),
      {code: 'EffectApplyResumeAdmissionUnavailable'});
      counts.mAllow = {writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot), calls: run.calls.length};
      assert.deepEqual(counts.mAllow, {writes: 0, entries: 0, calls: 0});
      // The unchanged configuration with the live claim dispatches once.
      const current = await apply(run.ledger, gate, run.dispatch(),
        {resume: {claim: second}});
      assert.equal(current.dispatched, totalRows);
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }

  // (l) The claim lapses after gate.resume and before the first write: the
  // synchronous admission entry at the send fences again at the Host trusted
  // time and refuses, so nothing is claimed in the ledger or sent. (An
  // Effect Set approval carries no expiry of its own; the claim lease is the
  // time bound that can lapse here.)
  {
    const run = await deferred({runId: 'commit-run-lapsed'});
    try {
      run.clock.ms += 60_000;
      await answerCommitCheckpoint(run.journal, run.checkpointCid,
        'approved', run.clock);
      const journal = run.journal;
      // Time passes between the decision and the send.
      const lapsing = Object.freeze({...journal,
        enterResumedDispatch: (...args) => {
          run.clock.ms += 120_000;
          return journal.enterResumedDispatch(...args);
        }});
      await assert.rejects(apply(run.ledger, await run.gate(lapsing),
        () => assert.fail('lapsed claim dispatched'),
        {resume: {claim: run.claim('worker-l', 60_000)}}),
      {code: 'ResumeClaimStale'});
      counts.lLapsed = {writes: provider.writes(run.writesBefore),
        entries: ledgerEntryCount(run.ledgerRoot), calls: run.calls.length};
      assert.deepEqual(counts.lLapsed, {writes: 0, entries: 0, calls: 0});
    } finally {
      run.ledger.close();
      run.journal.close();
    }
  }

  // (g) Lost HTTP reply after the approved resume: the row is Unknown, the
  // Run restarts and resumes again, and the Unknown row is never resent.
  let lost;
  {
    const run = await deferred({runId: 'commit-run-g',
      loseReplyAt: count => count === 1});
    run.clock.ms += 60_000;
    const approved = await answerCommitCheckpoint(run.journal,
      run.checkpointCid, 'approved', run.clock);
    const firstAttempt = apply(run.ledger, await run.gate(), run.dispatch(),
      {resume: run.resume('worker-g1')});
    await assert.rejects(firstAttempt);
    const [lostMember, lostRow] = run.calls[0];
    const lostPath = members[lostMember].claims[lostRow].path;
    assert.equal(provider.writes(run.writesBefore, lostPath), 1);
    // Restart; the first claimant's lease expires before re-claim.
    run.journal.close();
    run.ledger.close();
    run.clock.ms += 120_000;
    run.journal = await openCommitJournal(run.journalRoot, run.clock);
    run.ledger = openScenarioLedger(run.ledgerRoot);
    assert.equal((await run.journal.submitResolution(approved.answer))
      .outcome, 'duplicate');
    const resumed = await apply(run.ledger, await run.gate(),
      run.dispatch({loseReplyAt: undefined}),
      {resume: run.resume('worker-g2')});
    assert.equal(resumed.status, 'applied');
    assert.equal(resumed.resume.generation, 2);
    // Generation 1 already started this set: generation 2 continues only
    // through reconciliation of the same durable Effect Set identity.
    assert.equal(resumed.admission.mode, 'reconcile');
    assert.equal(resumed.admission.dispatchIdentity, resumed.identity);
    assert.equal(resumed.admission.priorAdmission.generation, 1);
    // Count PATCH requests per row: the Unknown row was sent exactly once.
    assert.equal(provider.writes(run.writesBefore, lostPath), 1);
    for (const path of rowPaths) {
      assert.ok(provider.writes(run.writesBefore, path) <= 1, path);
    }
    assert.equal(run.calls.filter(([member, row]) =>
      member === lostMember && row === lostRow).length, 1);
    const noReplay = await apply(run.ledger,
      await commitGate(allowAccount),
      () => assert.fail('unknown or terminal row resent'));
    assert.equal(noReplay.dispatched, 0);
    run.journal.completeResume(resumed.resume, {runStateWire: JSON.stringify({
      version: 'actql-run-state/0.1', run_id: 'commit-run-g',
      status: 'needs_reconciliation', updated_at: commitIso(run.clock.ms),
      next_action: {kind: 'reconcile', effects: [memberIds[lostMember]]},
      result_available: false,
      result_availability: {answer: {state: 'unavailable',
        observed_at: commitIso(run.clock.ms), reason: 'not_published'}},
    })});
    assert.equal(run.journal.getRunState('commit-run-g').status,
      'needs_reconciliation');
    counts.g = {dispatchedAfterRestart: resumed.dispatched,
      lostRowWrites: provider.writes(run.writesBefore, lostPath),
      writes: provider.writes(run.writesBefore),
      calls: run.calls.length, entries: ledgerEntryCount(run.ledgerRoot)};
    run.journal.close();
    run.ledger.close();
    lost = {ledgerRoot: run.ledgerRoot, lostMember};
  }

  // (h) Delayed rejection after prior effects: rows committed under an
  // earlier allow (one applied, one with a lost reply) stay recorded; the
  // later delegated decision is deferred and rejected with the Unknown
  // Effect reported, so the Run needs reconciliation and nothing more is
  // sent.
  {
    const clock = {ms: Date.parse('2026-09-24T00:00:00.000Z')};
    const {ledgerRoot, journalRoot} = await workspace();
    let ledger = openScenarioLedger(ledgerRoot);
    const calls = [];
    const writesBefore = provider.mark();
    await assert.rejects(apply(ledger,
      await commitGate(allowAccount),
      dispatcher(ledger, calls, {loseReplyAt: count => count === 2})));
    assert.equal(calls.length, 2);
    const entriesBefore = ledgerEntryCount(ledgerRoot);
    const writesPrior = provider.writes(writesBefore);
    ledger.close();
    ledger = openScenarioLedger(ledgerRoot);
    const journal = await openCommitJournal(journalRoot, clock);
    try {
      const waiting = await apply(ledger,
        await commitGate(delegateAccount, hostOptions('defer', {
          deferral: commitDeferral(journal, clock, 'commit-run-h')})),
        dispatcher(ledger, calls));
      assert.equal(waiting.status, 'waiting');
      clock.ms += 60_000;
      const [unknownMember] = calls[1];
      const rejected = await answerCommitCheckpoint(journal,
        waiting.checkpoint.checkpointCid, 'rejected', clock,
        {unknownEffects: [memberIds[unknownMember]]});
      assert.equal(rejected.decision, 'rejected');
      assert.equal(rejected.resumeIntentId, null);
      assert.equal(rejected.runState.status, 'needs_reconciliation');
      assert.deepEqual(rejected.runState.runState.next_action,
        {kind: 'reconcile', effects: [memberIds[unknownMember]]});
      await assert.rejects(apply(ledger,
        await commitGate(delegateAccount, hostOptions('defer')),
        () => assert.fail('rejected commit sent a row'),
        {resume: {journal, runId: 'commit-run-h', claimant: 'worker-h',
          leaseMs: 60_000, binding: commitBinding, resolution: rejected}}),
      {code: 'ResumeIntentNotFound'});
      assert.equal(calls.length, 2);
      assert.equal(provider.writes(writesBefore), writesPrior);
      assert.equal(ledgerEntryCount(ledgerRoot), entriesBefore);
      const [first, second] = calls.map(([member, row]) =>
        members[member].claims[row]);
      assert.ok(ledger.readClaimedOutcome(first));
      assert.equal(ledger.readClaimedResponse(second), undefined);
      assert.ok(ledger.current(runtimeCore(moon).effectApplicationControl
        .logicalItemLocatorCid(second.locator)));
      counts.h = {priorCalls: 2, priorWrites: writesPrior,
        entries: entriesBefore,
        runStatus: rejected.runState.status};
    } finally {
      journal.close();
      ledger.close();
    }
  }
  t.diagnostic(`effect commit authorization counts ${JSON.stringify(counts)}`);
  return lost;
}

for (const physical of ['simulated', 'simulated-authorization',
  'salesforce',
  'salesforce-recovered', 'salesforce-terminal-restart',
  'salesforce-upsert', 'salesforce-create',
  'salesforce-create-duplicates',
  'salesforce-publication-restart',
  'salesforce-overlap', 'salesforce-stale-target',
  'salesforce-schema-drift',
  'salesforce-unknown', 'salesforce-lost-http-reply',
  'salesforce-rate-limit',
  'salesforce-create-lost-http-reply',
  'salesforce-collection-partial', 'salesforce-collection-recovered',
  'salesforce-preapply-restart',
  'salesforce-prepared-intent-restart',
  'salesforce-process-prepared-intent-restart',
  'salesforce-process-unknown-restart',
  'salesforce-process-saved-response-restart',
  'salesforce-terminal-store-restart',
  'salesforce-terminal-process-publication',
  'salesforce-unknown-continue']) {
test(`two-member captured Effect Run ${
  physical === 'simulated-authorization'
    ? 'gates the Effect commit on the sealed Set Preview' :
  physical.startsWith('salesforce-unknown') ||
    physical === 'salesforce-process-unknown-restart' ||
    physical === 'salesforce-rate-limit' ||
    physical.endsWith('lost-http-reply')
    ? 'retains uncertain outcomes' :
    physical === 'salesforce-overlap' ||
      physical === 'salesforce-stale-target' ||
      physical === 'salesforce-schema-drift'
      ? 'rejects stale or overlapping members before send' :
    physical === 'salesforce-publication-restart'
      ? 'reconciles publication after Store restart' :
    physical === 'salesforce-collection-partial'
      ? 'retains partial failure outcomes' :
      'publishes after all rows settle'
} (${physical})`,
  async t => {
    const memberIds = ['save', 'save_again'];
    const siteRun = !physical.startsWith('simulated');
    const authorizationScenarios = physical === 'simulated-authorization';
    const recoverAfterResponse = physical === 'salesforce-recovered';
    const restartAfterTerminal = physical === 'salesforce-terminal-restart';
    const restartAfterPublication =
      physical === 'salesforce-publication-restart';
    const restartBeforeApply = physical === 'salesforce-preapply-restart';
    const processUnknownIntent =
      physical === 'salesforce-process-unknown-restart';
    const processSavedResponse =
      physical === 'salesforce-process-saved-response-restart';
    const processPreparedIntent = processUnknownIntent ||
      processSavedResponse ||
      physical === 'salesforce-process-prepared-intent-restart';
    const restartPreparedIntent = processPreparedIntent ||
      physical === 'salesforce-prepared-intent-restart';
    const processPublication =
      physical === 'salesforce-terminal-process-publication';
    const restartBeforeFinal =
      physical === 'salesforce-terminal-store-restart' ||
      processPublication;
    const loseHttpReply = physical.endsWith('lost-http-reply') ||
      processUnknownIntent;
    const rateLimitWrite = physical === 'salesforce-rate-limit';
    const unknownAfterClaim = physical.startsWith('salesforce-unknown') ||
      loseHttpReply;
    const continueAfterUnknown = physical === 'salesforce-unknown-continue';
    const collectionPartial = physical === 'salesforce-collection-partial';
    const collectionRecovered = physical === 'salesforce-collection-recovered';
    const collectionMode = collectionPartial || collectionRecovered;
    const overlappingMembers = physical === 'salesforce-overlap';
    const writeKind = physical === 'salesforce-upsert' ? 'upsert' :
      physical.startsWith('salesforce-create') ? 'create' : 'update';
    const continueMembers = continueAfterUnknown || collectionMode
      ? ['save'] : [];
    const sourceIds = siteRun
      ? physical === 'salesforce-create-duplicates'
        ? ['001000000000001', '001000000000001']
        : ['001000000000001', '001000000000002']
      : undefined;
    const target = siteRun ? 'connector://salesforce/Test_Record__c'
      : 'connector://crm/account';
    const mappingRef = siteRun ? 'mapping:salesforce.test-record.v1'
      : 'mapping:crm.account.v1';
    const {document, environment, mappingCid} = await effectFixture({
      writeKind, memberIds, target, mappingRef, sourceIds,
      continueMembers,
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const semanticInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    assert.equal(JSON.parse(moon.clientProgramLocalEffectInvocationJson(
      semanticInvocation)).self_cid,
      moon.clientProgramLocalEffectInvocationCid(semanticInvocation));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared),
      effectParametersCid(prepared),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'tenant-a-scope', 'complete-two-effects', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    const execution = await runCapturedEffectComputation(owned);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-two-published-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let control = runtimeCore(moon).publicationControl;
    const configuration = {
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64, privateEvidenceKey: Buffer.alloc(32, 4),
    };
    let physicalStore = await openLocalPublicationStore(
      configuration, control);
    let commitCalls = 0;
    let store = Object.freeze({...physicalStore,
      async commitEffectfulIndex(...args) {
        commitCalls++;
        const result = await physicalStore.commitEffectfulIndex(...args);
        if (commitCalls === 1) throw new Error('LostEffectIndexCommitAck');
        return result;
      },
    });
    if (restartAfterPublication) {
      store = new Proxy({}, {get(_target, property) {
        if (property === 'commitEffectfulIndex') {
          return async (...args) => {
            commitCalls++;
            const result = await physicalStore.commitEffectfulIndex(...args);
            if (commitCalls === 1) {
              await physicalStore.close();
              throw new Error('LostEffectIndexCommitAckAfterStoreClose');
            }
            return result;
          };
        }
        return physicalStore[property];
      }});
    }
    let storedResults, inputs, sourcePayload, ledger;
    let published = false;
    let testFailure;
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      const runDefinition = control.admit('run_definition',
        moon.strategyPublicationContractJson(definition),
        publicationLimits);
      const runInvocation = control.admit('run_invocation',
        moon.strategyPublicationContractJson(invocation),
        publicationLimits);
      const localEvidenceContext = admittedLocalEffectEvidenceContext(
        control, prepared, evidence, definition, invocation, observation);
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control,
        runDefinition, invocation: runInvocation,
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      assert.equal(storedResults.results[0].occurrence.name, 'answer');
      inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
      const proposedRows = memberIds.map(() => []);
      sourcePayload = await preparePinnedEffectSourcePayload({
        moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
        limits: moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits)),
        store, maxBytes: outputLimits.maxWireBytes, control,
        invocation: runInvocation, retention,
        sourceBindingCid: cid('c'),
        contractLimits: publicationLimits,
        localEvidenceContext,
        ...(siteRun ? {
          proposalMemberIndexes: [0, 1],
          proposalLimits: {maxFields: 10, maxWork: 100,
            maxBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxUtf16Units: 20000},
          onProposalRow(memberIndex, rowIndex, proposal) {
            assert.equal(rowIndex, proposedRows[memberIndex].length);
            proposedRows[memberIndex].push(proposal);
          },
        } : {}),
      });
      const custodyInvocationCid = JSON.parse(
        sourcePayload.summary.artifact.wire).invocation_cid;
      assert.equal(custodyInvocationCid, runInvocation.identity);
      assert.notEqual(custodyInvocationCid,
        moon.clientProgramLocalEffectInvocationCid(semanticInvocation));
      if (siteRun) {
        for (const rows of proposedRows) {
          assert.deepEqual(rows.map(row => JSON.parse(row.selectorWire)),
            writeKind === 'create' ? [null, null] : sourceIds);
          assert.deepEqual(rows.map(row =>
            JSON.parse(row.changesWire).value),
          sourceIds.map(Name => writeKind === 'create' ?
            {Name, External_Key__c: Name} : {Name}));
        }
      }
      const effect = runtimeCore(moon).effectApplicationControl;
      const sites = siteRun ? await Promise.all(memberIds.map((_, index) =>
        openSalesforceEffectSiteFixture(t, {
          commonMoon: moon, salesforceMoon,
          runInvocationCid: runInvocation.identity,
          dispatchRequestCid: cid('c'),
          orgId: index === 0 || overlappingMembers ? '00D000000000001EAA'
            : '00D000000000002EAA',
          loseWriteReplyOnce: loseHttpReply && index === 0,
          rateLimitWriteOnce: rateLimitWrite && index === 0,
          collectionPartial: collectionPartial && index === 0,
          writeOperation: writeKind,
        }))) : undefined;
      const prepareSiteProjection = (site,
        observationValue = site.catalog.observation) => {
        const binding = site.write.scope;
        return checked(salesforceMoon.salesforcePrepareWriteProjection(
          observationValue,
          binding.tenant, binding.principal, binding.environment,
          'connection-revision-a', site.orgId,
          binding.siteKey, binding.siteGeneration,
          binding.connectorRegistration, binding.connectorRevision,
          binding.resourceOrigin, binding.runInvocationCid,
          binding.dispatchRequestCid, 'catalog-sync-a',
          'Test_Record__c', writeKind === 'upsert' ? 2 :
            writeKind === 'create' ? 0 : 1,
          writeKind === 'upsert' ? 'External_Key__c' : '',
          writeKind === 'create' ? ['Name', 'External_Key__c'] :
            ['Name'], 2));
      };
      const siteProjections = sites?.map(site => prepareSiteProjection(site));
      if (siteRun && writeKind !== 'create') {
        sites.forEach((site, index) =>
          site.setTargetName(`observed-before-${index}`));
      }
      const siteBodies = siteRun ? memberIds.map((_, memberIndex) =>
        sourceIds.map((value, rowIndex) => checked(
          salesforceMoon.salesforcePrepareWriteBody(
          siteProjections[memberIndex],
          Buffer.from(JSON.stringify(
            JSON.parse(proposedRows[memberIndex][rowIndex].changesWire)
              .value)),
          1024, 32, 5)))) : undefined;
      let siteRequests = siteRun ? memberIds.map((_, memberIndex) =>
        sourceIds.map((value, rowIndex) => {
        return checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
          siteBodies[memberIndex][rowIndex], 'v62.0',
          writeKind === 'upsert' ? 2 :
            writeKind === 'create' ? 0 : 1,
          writeKind === 'create' ? '' :
            JSON.parse(proposedRows[memberIndex][rowIndex].selectorWire), 0,
          256, 128, 1024));
      })) : undefined;
      const siteBoundaries = siteRun ? sites.map((_, memberIndex) => checked(
        salesforceMoon.salesforceSingleWriteRequestBoundaryCid(
          siteRequests[memberIndex][0], 4096))) : undefined;
      const siteFootprints = siteRun ? sites.map((_, memberIndex) => {
        const targets = siteRequests[memberIndex].map(request =>
          salesforceMoon.salesforceSingleWriteRequestTargetIdentity(
            request, 4096));
        return {kind: writeKind === 'create' ? 'collection' : 'exact_targets',
          resource_identity_scheme_cid: writeKind === 'create' ? cid('f') :
            salesforceMoon.salesforceWriteTargetSchemeCid(
              checked(targets[0])),
          provider_namespace: 'salesforce',
          provider_boundary_cid: siteBoundaries[memberIndex],
          resource_kind: 'Test_Record__c',
          provider_object_identity_cids: writeKind === 'create' ? [] :
            targets.map(target => salesforceMoon.salesforceWriteTargetObjectCid(
              checked(target)))};
      }) : undefined;
      let currentCatalogs = sites?.map(site => site.catalog.observation);
      let targetRead = 0;
      const observeCurrentTargets = ({signal} = {}) =>
        observeSalesforceTargetSet({moon: salesforceMoon,
          members: sites.map((site, memberIndex) => ({
            requests: siteRequests[memberIndex],
            currentCatalog: currentCatalogs[memberIndex],
            authorizationForRow: async () => ({...site.observe,
              useId: `target-read-${targetRead++}`}),
            credential: site.credential,
            limits: {maxResponseBytes: 1024, maxNodes: 32,
              maxDepth: 5, maxIdentityBytes: 1024},
          })), maxMembers: 2, maxRows: 4,
          maxTotalResponseBytes: 4096, signal});
      const previewTargetObservations = siteRun && writeKind !== 'create'
        ? await observeCurrentTargets() : undefined;
      const previewGuardVersions = previewTargetObservations?.map(member =>
        member.map(observed => observed.versionCid));
      const requestScope = effect.logicalRequestScope(
        cid('e'), 'complete-two-effects-request', 128);
      const previewDraft = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        sourcePayload.summary.artifact.identity,
        writeKind,
        siteRun ? proposedRows[0].map(row =>
          JSON.parse(row.changesWire).value.Name) :
          [1, 2],
        siteRun && writeKind !== 'create' ? proposedRows[0].map(row =>
          JSON.parse(row.selectorWire)) :
          siteRun ? sourceIds : [1, 2], memberIds,
        siteRun ? siteBoundaries : [cid('0'), cid('1')],
        requestScope, {target, mapping: mappingRef,
          resourceKind: siteRun ? 'Test_Record__c' : 'Account',
          footprints: siteFootprints, continueMembers,
          guardVersions: previewGuardVersions,
          templateOnly: siteRun});
      const productMembers = siteRun ? siteRequests.map((requests, index) => ({
        stageIndex: 0, effectId: memberIds[index], requests,
        observations: previewTargetObservations?.[index],
        localResultArtifact: sourcePayload.localResultArtifact,
        sourceArtifact: sourcePayload.summary.artifact,
        capabilityEvidenceCid: cid('d'),
        requiredPermissions: ['write'],
        maxItems: 2, approval: 'none', previewStrength: 'full_diff',
      })) : undefined;
      const issuedLocalIdentities = [];
      const issuingControl = siteRun ? {
        ...control,
        issueSourceFreeLocalEffectIdentity(...args) {
          const identity = control.issueSourceFreeLocalEffectIdentity(...args);
          issuedLocalIdentities.push(identity);
          return identity;
        },
      } : control;
      const preview = siteRun
        ? authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, control: issuingControl, prepared, inputs,
          context: {runDefinition: definition, runInvocation: invocation,
            compiledPlan: evidence[3],
            storeAuthorityCid: store.storeAuthorityCid, modelDerived: false},
          requestScope, members: productMembers,
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }) : previewDraft;
      if (siteRun) {
        const issuedMembers = JSON.parse(preview.wire).effects;
        assert.equal(issuedLocalIdentities.length, 2);
        assert.doesNotThrow(() =>
          control.checkSourceFreeLocalEffectPreviewIdentities(
            prepared, inputs, preview.wire,
            definition.identity, preview.authoringCid,
            issuedLocalIdentities, publicationLimits));
        assert.throws(() =>
          control.checkSourceFreeLocalEffectPreviewIdentities(
            prepared, inputs, preview.wire,
            definition.identity, preview.authoringCid,
            issuedLocalIdentities.slice(0, 1), publicationLimits));
        assert.throws(() =>
          control.checkSourceFreeLocalEffectPreviewIdentities(
            prepared, inputs, preview.wire,
            definition.identity, preview.authoringCid,
            [{...issuedLocalIdentities[0]}, issuedLocalIdentities[1]],
            publicationLimits), {name: 'TypeError'});
        assert.notEqual(issuedMembers[0].effect_identity_cid,
          issuedMembers[1].effect_identity_cid);
        assert.notEqual(issuedMembers[0].effect_identity_cid,
          JSON.parse(previewDraft.wire).effects[0].effect_identity_cid);
        const forgedFootprint = JSON.parse(preview.wire);
        forgedFootprint.effects[0].write_footprint = {
          kind: 'opaque', provider_boundary_cid: cid('9'),
          provider_namespace: 'foreign', provider_object_identity_cids: [],
          resource_identity_scheme_cid: cid('8'), resource_kind: 'Other',
        };
        forgedFootprint.effects[0].count = 1;
        const restored = authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared,
          templateWire: JSON.stringify(forgedFootprint), requestScope,
          members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[index], requests,
            observations: previewTargetObservations?.[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        });
        assert.equal(restored.wire, preview.wire);
        if (!overlappingMembers) {
          const mixedRequests = [siteRequests[0][0], siteRequests[1][1]];
          assert.throws(() => authorObservedSalesforceEffectPreview({
            moon, salesforceMoon, prepared, templateWire: previewDraft.wire,
            requestScope, members: [{stageIndex: 0,
              effectId: memberIds[0], requests: mixedRequests,
              observations: previewTargetObservations === undefined ? undefined
                : [previewTargetObservations[0][0],
                  previewTargetObservations[1][1]]},
            {stageIndex: 0, effectId: memberIds[1],
              requests: siteRequests[1],
              observations: previewTargetObservations?.[1]}],
            maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
            maxKeyNodes: 8, maxKeyDepth: 3, planLimits: previewPlanLimits,
          }), {code: 'MoonBitHostFailure'});
        }
      }
      if (siteRun && writeKind === 'create') {
        assert.throws(() => checked(moon.clientProgramAuthorEffectPreview(
          previewDraft.wire,
          JSON.parse(previewDraft.wire).run_identity_cid,
          previewDraft.authoringCid, requestScope,
          20000, 1000, 20, 2, 4, 128, 8, 3,
        )), {code: 'MoonBitHostFailure'});
        siteRequests = siteRequests.map((requests, memberIndex) =>
          preview.requestOrder[memberIndex].map(index => requests[index]));
        const fabricated = JSON.parse(preview.wire);
        fabricated.effects[0].changes[0].after =
          {state: 'present', value: {Name: 'fabricated'}};
        fabricated.effects[0].changes[0].target_guard =
          {state: 'version', version_cid: cid('9')};
        const restored = authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared,
          templateWire: JSON.stringify(fabricated),
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[index], requests,
          })),
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        });
        assert.equal(restored.wire, preview.wire);
        if (physical === 'salesforce-create') {
          assert.throws(() => authorObservedSalesforceEffectPreview({
            moon, prepared, salesforceMoon: {...salesforceMoon,
              salesforceSingleWriteRequestBody: () =>
                '{"Name":9007199254740993}'},
            templateWire: previewDraft.wire, requestScope,
            members: siteRequests.map((requests, index) => ({
              stageIndex: 0, effectId: memberIds[index], requests,
            })),
            maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
            maxKeyNodes: 8, maxKeyDepth: 3,
            planLimits: previewPlanLimits,
          }), {code: 'LossySalesforceEffectPreviewProjection'});
        }
        const foreignContent = JSON.parse(preview.wire);
        foreignContent.effects[0].changes[0]
          .target_row_identity.content_cid = cid('9');
        assert.throws(() => effect.derivePreviewIdentities(
          canonicalJson(foreignContent), 20000, 1000, 20),
        {code: 'MoonBitHostFailure'});
        const foreignOrder = JSON.parse(preview.wire);
        foreignOrder.effects[0].changes.reverse();
        assert.throws(() => effect.derivePreviewIdentities(
          canonicalJson(foreignOrder), 20000, 1000, 20),
        {code: 'MoonBitHostFailure'});
        for (const member of JSON.parse(preview.wire).effects) {
          assert.deepEqual(member.changes.map(change =>
            change.target_guard), [
            {state: 'not_applicable'}, {state: 'not_applicable'},
          ]);
          assert.ok(member.changes.every(change =>
            typeof change.target_row_identity.content_cid === 'string' &&
            Number.isInteger(change.target_row_identity.occurrence)));
          if (physical === 'salesforce-create-duplicates') {
            assert.deepEqual(member.changes.map(change =>
              change.target_row_identity.occurrence), [0, 1]);
            assert.equal(member.changes[0].target_row_identity.content_cid,
              member.changes[1].target_row_identity.content_cid);
          }
        }
      }
      if (physical === 'salesforce') {
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, control, prepared, inputs,
          context: {runDefinition: definition, runInvocation: invocation,
            compiledPlan: evidence[3], storeAuthorityCid: cid('9'),
            modelDerived: false},
          requestScope, members: productMembers,
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'MoonBitHostFailure'});
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, control, prepared, inputs,
          context: {runDefinition: definition, runInvocation: invocation,
            compiledPlan: evidence[3],
            storeAuthorityCid: store.storeAuthorityCid,
            modelDerived: false},
          requestScope,
          members: productMembers.map((member, index) => index === 0 ?
            {...member, authorityScopeCid: cid('9')} : member),
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'ForeignSalesforceEffectPreviewAuthority'});
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, control, prepared, inputs,
          context: {runDefinition: definition, runInvocation: invocation,
            compiledPlan: evidence[3],
            storeAuthorityCid: store.storeAuthorityCid, modelDerived: false},
          requestScope,
          members: productMembers.map((member, index) => index === 0 ?
            {...member, sourceArtifact: storedResults.artifacts[0]} :
            member),
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'MoonBitHostFailure'});
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, control, prepared, inputs,
          context: {runDefinition: definition, runInvocation: invocation,
            compiledPlan: evidence[3],
            storeAuthorityCid: store.storeAuthorityCid, modelDerived: false},
          requestScope,
          members: productMembers.map((member, index) => index === 0 ?
            {...member, sourceArtifact: {...member.sourceArtifact}} : member),
          maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {message: 'Foreign publication contract'});
        const alteredTemplate = JSON.parse(preview.wire);
        alteredTemplate.effects[0].changes[0].before =
          {state: 'present', value: {Name: 'fabricated-before'}};
        alteredTemplate.effects[0].changes[0].after =
          {state: 'present', value: {Name: 'fabricated-after'}};
        alteredTemplate.effects[0].changes[0].target_guard =
          {state: 'version', version_cid: cid('9')};
        Object.assign(alteredTemplate.effects[0], {
          effect_kind: 'create', target: 'connector://foreign/resource',
          mapping: 'mapping:foreign', resolved_mapping_contract_cid: cid('9'),
          source_result: 'foreign', on_item_failure: 'continue',
          effect_plan_logical_cid: cid('9'),
        });
        const restored = authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared,
          templateWire: JSON.stringify(alteredTemplate),
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[index], requests,
            observations: previewTargetObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        });
        assert.equal(restored.wire, preview.wire);
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared, templateWire: previewDraft.wire,
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: 0,
            effectId: index === 0 ? 'foreign' : memberIds[index],
            requests, observations: previewTargetObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'MoonBitHostFailure'});
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared, templateWire: previewDraft.wire,
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[1 - index], requests,
            observations: previewTargetObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'ForeignSalesforceEffectPreviewMember'});
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared, templateWire: previewDraft.wire,
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: index === 0 ? 1 : 0,
            effectId: memberIds[index], requests,
            observations: previewTargetObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'MoonBitHostFailure'});
        const foreignProgram = JSON.parse(previewDraft.wire);
        foreignProgram.program_definition_cid = cid('9');
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared,
          templateWire: JSON.stringify(foreignProgram), requestScope,
          members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[index], requests,
            observations: previewTargetObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'InvalidSalesforceEffectPreviewAuthoring'});
        const foreignObservations = previewTargetObservations.map(rows =>
          [...rows]);
        foreignObservations[0][0] = previewTargetObservations[1][0];
        assert.throws(() => authorObservedSalesforceEffectPreview({
          moon, salesforceMoon, prepared, templateWire: previewDraft.wire,
          requestScope, members: siteRequests.map((requests, index) => ({
            stageIndex: 0, effectId: memberIds[index], requests,
            observations: foreignObservations[index],
          })), maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20,
          maxRows: 4, maxIdentityBytes: 4096, maxKeyBytes: 128,
          maxKeyNodes: 8, maxKeyDepth: 3,
          planLimits: previewPlanLimits,
        }), {code: 'ForeignSalesforceEffectPreviewObservation'});
      }
      const authoringContext = control.admitRunEvidence(
        'authoring_context',
        canonicalJson(JSON.parse(preview.wire).authoring_context),
        publicationLimits);
      let admittedPreview = control.admitEffectComputationPreview(
        preview.wire, runDefinition, authoringContext,
        publicationLimits);
      const firstHolding = await commitPinnedEffectSourceHolding({
        payload: sourcePayload, store, control, preview: admittedPreview,
        memberIndex: 0, invocation: runInvocation,
      });
      const secondHolding = await commitPinnedEffectSourceHolding({
        payload: sourcePayload, store, control, preview: admittedPreview,
        memberIndex: 1, invocation: runInvocation,
        shareFromHoldingCid: firstHolding.holdingCid,
      });
      assert.notEqual(firstHolding.holdingCid, secondHolding.holdingCid);
      if (overlappingMembers) {
        const usesBefore = sites.map(site => site.journal.recover().length);
        assert.equal(moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, preview.wire,
          preview.authoringCid,
          moon.clientProgramEffectPreviewInputLimits(
            20000, 1000, 20, 1000, 100, 20000, 1000, 20,
            2, 4, 100, 100)).$tag, 0);
        assert.deepEqual(sites.map(site => site.journal.recover().length),
          usesBefore);
        assert.equal(sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length, 0);
        for (const holdingCid of [firstHolding.holdingCid,
          secondHolding.holdingCid]) {
          assert.equal((await store.retirePhysicalHolding(holdingCid))
            .deleted, true);
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        return;
      }
      const previewInputs = checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, preview.wire,
          preview.authoringCid,
          moon.clientProgramEffectPreviewInputLimits(
            20000, 1000, 20, 1000, 100, 20000, 1000, 20,
            2, siteRun ? 4 : 2, 100, 100)));
      const planLimits = {maxFields: 10, maxWork: 100,
        maxBytes: 20000, maxNodes: 1000, maxDepth: 20,
        maxUtf16Units: 20000};
      const plans = [];
      for (let memberIndex = 0; memberIndex < (writeKind === 'create' ? 0 : 2);
        memberIndex++) {
        const chunks = [];
        const plan = await verifyPinnedEffectPlan({
          moon, execution, previewInputs, previewIndex: memberIndex,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          planLimits, onChunk: chunk => { chunks.push(chunk); },
        });
        plans.push({name: memberIds[memberIndex], wire: chunks.join(''),
          proof: plan.proof});
      }
      const runEvidence = evidence.slice(0, 3).map((value, index) =>
        control.admitRunEvidence(
          ['bound_invocation_template', 'prepared_invocation',
            'run_authorization'][index],
          moon.strategyRunEvidenceJson(value), publicationLimits));
      const compiledPlan = control.admit('compiled_plan',
        moon.strategyPublicationContractJson(evidence[3]),
        publicationLimits);
      const runAdmission = control.admitCheckedClientEffectRunPublication(
        prepared, ...runEvidence, compiledPlan);
      const normalizationJournal = control.sealRunEvidence(
        'normalization_journal', JSON.stringify({
          version: 'actql-normalization-journal/0.1',
          rule_catalog_cid: cid('1'), entries: [],
        }), publicationLimits);
      let computation = await issueCompletedEffectfulComputationEvidence({
        execution, store, storedResults, control,
        admission: runAdmission, runDefinition,
        invocation: runInvocation,
        observation: control.admitRunEvidence('observation_set',
          moon.strategyRunEvidenceJson(observation), publicationLimits),
        normalizationJournal, authoringContext,
        receiptEvidence: {bindings: [], sourceEvidence: [],
          modelEvidence: [], barrierAttemptReceiptCids: []},
        captureEvidence: {pendingSourceStateAdvances: [],
          modelEvidence: []},
        preview: admittedPreview,
        plans: plans.map(({name, wire}) => ({name, wire})),
        effectSourceHoldings: [firstHolding, secondHolding],
        connectorRecovery: siteRun ? sites.map((site, memberIndex) => ({
          memberIndex, kind: 'salesforce-catalog',
          observationCid: site.catalog.observationCid,
          wire: JSON.stringify({
            catalog: site.catalog.retainedResponses,
            apiVersion: 'v62.0', resourceName: 'Test_Record__c',
            operation: writeKind,
            externalTargetField: writeKind === 'upsert'
              ? 'External_Key__c' : '',
            fieldNames: writeKind === 'create'
              ? ['Name', 'External_Key__c'] : ['Name'],
            resourceOrigin: site.origin,
          }),
        })) : [],
        contractLimits: publicationLimits,
      });
      assert.notEqual(control.effectComputationCaptureHoldingCid(
        runDefinition, store.storeAuthorityCid),
      control.effectComputationRecordHoldingCid(
        runDefinition, store.storeAuthorityCid));
      const captureSources = [firstHolding, secondHolding].map(
        value => ({memberIndex: value.memberIndex,
          artifact: value.artifact}));
      assert.equal(control.capturedEffectSourceRecoveryInventoryValid(
        admittedPreview, captureSources), true);
      assert.equal(control.capturedEffectSourceRecoveryInventoryValid(
        admittedPreview, captureSources.slice(1)), false);
      assert.equal(control.capturedEffectSourceRecoveryInventoryValid(
        admittedPreview, [captureSources[0], captureSources[0]]), false);
      if (restartBeforeApply) {
        const before = JSON.stringify(await store.inspectPhysicalHolding(
          control.effectComputationCaptureHoldingCid(
            runDefinition, store.storeAuthorityCid)));
        const encrypted = [];
        await store.consumePhysicalHolding(
          control.effectComputationRecordHoldingCid(
            runDefinition, store.storeAuthorityCid), 0,
          chunk => encrypted.push(Buffer.from(chunk)));
        assert.equal(Buffer.concat(encrypted).toString('utf8')
          .includes('"captured_run"'), false);
        for (const result of storedResults.results) {
          if (result.prepared.status().pending) {
            await result.prepared.release();
          }
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        await store.close();
        const child = spawnSync(process.execPath, [fileURLToPath(new URL(
          './fixtures/recover-effect-capture.mjs', import.meta.url,
        ))], {
          input: JSON.stringify({
            directory, storeAuthorityCid: configuration.storeAuthorityCid,
            capacityBytes: configuration.capacityBytes,
            maxObjectBytes: configuration.maxObjectBytes,
            maxObjects: configuration.maxObjects,
            maxContractNodes: configuration.maxContractNodes,
            maxContractDepth: configuration.maxContractDepth,
            runDefinitionWire: runDefinition.wire,
            limits: publicationLimits,
          }),
          encoding: 'utf8',
          timeout: 20_000,
        });
        assert.equal(child.status, 0, child.stderr);
        assert.deepEqual(JSON.parse(child.stdout), {
          capturedRunCid: computation.capturedRun.identity,
          artifactCids: storedResults.artifacts.map(value => value.identity),
        });
        control = runtimeCore(moon).publicationControl;
        physicalStore = await openLocalPublicationStore(configuration, control);
        store = Object.freeze({...physicalStore,
          async commitEffectfulIndex(...args) {
            commitCalls++;
            const result = await physicalStore.commitEffectfulIndex(...args);
            if (commitCalls === 1) {
              throw new Error('LostEffectIndexCommitAck');
            }
            return result;
          },
        });
        const recovered = await recoverCompletedEffectfulComputation({
          store, control, runDefinition, contractLimits: publicationLimits,
        });
        await assert.rejects(recoverCompletedEffectfulComputation({
          store: Object.freeze({...store, storeAuthorityCid: cid('8')}),
          control, runDefinition, contractLimits: publicationLimits,
        }), {code: 'CompletedEffectfulCaptureUnavailable'});
        assert.equal(JSON.stringify(await store.inspectPhysicalHolding(
          control.effectComputationCaptureHoldingCid(
            runDefinition, store.storeAuthorityCid))), before);
        assert.equal(recovered.computation.capturedRun.identity,
          computation.capturedRun.identity);
        assert.equal(recovered.storedResults.artifacts[0].identity,
          storedResults.artifacts[0].identity);
        storedResults = recovered.storedResults;
        computation = recovered.computation;
        admittedPreview = recovered.preview;
      }
      const captured = JSON.parse(computation.capturedRun.wire);
      assert.deepEqual(Object.keys(captured.effect_context
        .effect_source_artifacts).sort(), memberIds);
      assert.deepEqual(Object.keys(captured.effect_context
        .result_artifacts), ['answer']);
      assert.equal(captured.effect_context.effect_source_artifacts.save
        .source_result, 'rows');
      const body = JSON.parse(preview.wire);
      if (siteRun && writeKind !== 'create') {
        body.effects.forEach((member, memberIndex) =>
          member.changes.forEach(change => assert.deepEqual(
            change.before, {state: 'present',
              value: {Name: `observed-before-${memberIndex}`}})));
      }
      const collectionRequest = collectionMode ? checked(
        salesforceMoon.salesforcePrepareContinueWriteCollection(
          body.effects[0].row_order, siteBodies[0], [1, 1],
          sourceIds, [0, 0], 'v62.0', 256, 128, 1024, 64, 6,
          200)) : undefined;
      let applyPreview = effect.admitPreviewIdentity(
        preview.wire, body.run_identity_cid,
        preview.authoringCid, requestScope, preview.keys,
        publicationLimits.maxWireBytes, publicationLimits.maxNodes,
        publicationLimits.maxDepth);
      const members = body.effects.map((member, memberIndex) => ({
        claims: member.changes.map((change, rowIndex) => {
          const key = preview.keys[memberIndex][rowIndex];
          const locator = effect.logicalItemLocator(
            requestScope, 'program-1', 'node-1', member.effect_id,
            canonicalJson(change.target_row_identity), 64, 128, 8, 3);
          const path = `/effect/${member.effect_id}/${rowIndex}`;
          const requestWire = canonicalJson({path, row: change.row_preview_cid});
          const request = siteRequests?.[memberIndex]?.[rowIndex];
          const canonicalRequestCid = collectionMode && memberIndex === 0
            ? checked(salesforceMoon.salesforceCollectionWriteRequestCid(
              collectionRequest, sites[0].origin, 4096))
            : siteRun ? checked(
            salesforceMoon.salesforceSingleWriteRequestCid(
              request, sites[memberIndex].origin, 4096)) :
            `sha256:${createHash('sha256')
              .update(requestWire).digest('hex')}`;
          const basis = effect.ledgerBasis(
            requestScope, locator, key, cid('6'),
            member.effect_member_preview_cid, change.row_preview_cid,
            canonicalRequestCid, cid('0'), 'unavailable', cid('1'), cid('2'));
          return {scope: requestScope, locator, key, basis,
            intentFingerprintCid: change.row_preview_cid,
            canonicalRequestCid, path};
        }),
      }));
      const ledgerRoot = join(directory, 'effect-ledger');
      await mkdir(ledgerRoot);
      const openLedger = () => openEffectLedger({moon, root: ledgerRoot,
        authorityScopeCid: cid('e'),
        callerRequestId: 'complete-two-effects-request',
        maxEntryBytes: 4096});
      ledger = openLedger();
      const observedRows = writeKind === 'create' ? [] :
        body.effects.flatMap(member => member.row_order);
      const route = checked(
        moon.clientProgramEffectApplyCapabilityFromCodes(
          cid('d'), 0, 0, 0, true, true, 2, 1));
      const sent = [];
      const preflight = {
        proofs: plans.map(plan => plan.proof),
        sources: [cid('c'), cid('c')],
        contracts: [mappingCid, mappingCid],
        capabilities: [cid('d'), cid('d')],
        authorities: [cid('e'), cid('e')],
        observedRows, guardVersions: writeKind === 'create' ? [] :
          previewGuardVersions?.flat() ?? observedRows.map(() => cid('6')),
        // D2.multi-allow: an account allow commits the two-member set
        // after whole-set preflight without a fabricated risk claim.
        routes: [route, route], risk: undefined,
        reviewProjectionCid: cid('a'),
        authorityScopeCid: cid('e'), policyCid: cid('a'),
        validityCid: cid('a'), issuerCid: cid('a'),
        authenticationCid: cid('a'), issuerKind: 'policy',
        decision: 'allow', requestScope, keys: preview.keys,
        maxMembers: 2, maxRows: 4, maxFootprintWork: 4, maxWork: 100,
      };
      // Host-derived Effect commit tuples: each member's connection and
      // resource; the operation is the Effect class of the operation
      // classification.
      const commitScopes = memberIds.map((_, memberIndex) => siteRun
        ? {connection: `salesforce:${sites[memberIndex].orgId}`,
          resource: 'Test_Record__c'}
        : {connection: 'crm', resource: 'Account'});
      const applyOptions = {moon, capturedInputs: previewInputs,
        preflight, ledger, members, maxFrontierWork: 64,
        refreshPreflight: async ({preflight}) => preflight,
        authorization: {
          gate: await fixtureAuthorization([
            accountEntry('effect-allow', 'allow', {operation: 'effect'}),
            accountEntry('target-read-allow', 'allow', {operation: 'read'}),
          ]),
          scopes: commitScopes,
        }};
      const expectedCredentialUses = baseline => baseline.map(
        (count, index) => count + sites[index].seen.filter(item =>
          item.method === 'GET').length);
      if (siteRun && writeKind !== 'create') {
        const usesBefore = sites.map(site => site.journal.recover().length);
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions,
          preflight: {...preflight,
            observedRows: observedRows.slice(1),
            guardVersions: preflight.guardVersions.slice(1)},
          dispatchRow: () => assert.fail('missing guard dispatched'),
        }), {code: 'MoonBitHostFailure'});
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions,
          preflight: {...preflight,
            guardVersions: observedRows.map(() => cid('9'))},
          dispatchRow: () => assert.fail('stale row dispatched'),
        }), {code: 'MoonBitHostFailure'});
        assert.deepEqual(sites.map(site => site.journal.recover().length),
          usesBefore);
        assert.equal(sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length, 0);
      }
      if (siteRun) {
        applyOptions.refreshPreflight = async ({signal, preflight}) => {
          currentCatalogs = await refreshSalesforceEffectWriteCatalogs({
            moon: salesforceMoon,
            members: sites.map((site, index) => ({
              requests: siteRequests[index],
              collectionRequest: collectionMode && index === 0
                ? collectionRequest : undefined,
              refreshCatalog: site.refreshCatalog,
            })), maxMembers: 2, maxRows: 4, signal,
          });
          return {...preflight, observedRows,
            guardVersions: writeKind === 'create' ? [] :
              (await observeCurrentTargets({signal})).flatMap(member =>
                member.map(observed => observed.versionCid))};
        };
      }
      if (physical === 'salesforce') {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, refreshPreflight: undefined,
          dispatchRow: () => assert.fail('missing refresh sent a row'),
        }), {code: 'InvalidCapturedEffectApply'});
        for (const [field, values] of [
          ['capabilities', [cid('9'), cid('d')]],
          ['authorities', [cid('9'), cid('e')]],
        ]) {
          const writesBefore = sites.flatMap(site => site.seen)
            .filter(item => item.method === 'PATCH').length;
          await assert.rejects(applyCapturedEffectSet({
            ...applyOptions,
            refreshPreflight: async args => ({
              ...await applyOptions.refreshPreflight(args), [field]: values,
            }),
            dispatchRow: () => assert.fail('drifted preflight sent a row'),
          }), {code: 'MoonBitHostFailure'});
          assert.equal(sites.flatMap(site => site.seen)
            .filter(item => item.method === 'PATCH').length, writesBefore);
        }
      }
      let recoveredApplyOptions;
      let processUnknownSetCid;
      if (restartPreparedIntent) {
        assert.equal(ledger.prepareCapturedSetIntents(
          previewInputs, members, 64), 4);
        ledger.close();
        for (const result of storedResults.results) {
          if (result.prepared.status().pending) {
            await result.prepared.release();
          }
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        await store.close();
        const childInput = {
            directory, storeAuthorityCid: configuration.storeAuthorityCid,
            capacityBytes: configuration.capacityBytes,
            maxObjectBytes: configuration.maxObjectBytes,
            maxObjects: configuration.maxObjects,
            maxContractNodes: configuration.maxContractNodes,
            maxContractDepth: configuration.maxContractDepth,
            runDefinitionWire: runDefinition.wire,
            ledgerRoot, authorityScopeCid: cid('e'),
            callerRequestId: 'complete-two-effects-request',
            programId: 'program-1', nodeId: 'node-1',
            maxRows: 4, maxWork: 100, limits: publicationLimits,
            prepared: true, applyPrepared: processPreparedIntent,
            preflightContext: {
              review_projection_cid: preflight.reviewProjectionCid,
              authority_scope_cid: preflight.authorityScopeCid,
              policy_cid: preflight.policyCid,
              validity_evidence_cid: preflight.validityCid,
              issuer_evidence_cid: preflight.issuerCid,
              authentication_evidence_cid: preflight.authenticationCid,
              issuer_kind: preflight.issuerKind,
              decision: preflight.decision,
            },
            salesforceRecovery: {
              bodyLimits: {maxBytes: 1024, maxNodes: 32, maxDepth: 5},
              requestLimits: {maxPathBytes: 256, maxTargetBytes: 128,
                maxBodyBytes: 1024},
              maxRetainedBytes: 30000,
              ...(processPreparedIntent ? {
                sites: sites.map(site => site.recoveryConnection),
              } : {}),
            },
          };
        if (processPreparedIntent) {
          const foreignSite = structuredClone(childInput);
          foreignSite.salesforceRecovery.sites[0].authorityPublicKey =
            sites[1].recoveryConnection.authorityPublicKey;
          const rejected = await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs', foreignSite);
          assert.notEqual(rejected.status, 0);
          assert.equal(sites.flatMap(site => site.seen).filter(item =>
            item.method === 'PATCH').length, 0);
        }
        if (processUnknownIntent || processSavedResponse) {
          const lost = await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs',
            {...childInput, recoveryPass: 'first',
              ...(processSavedResponse
                ? {faultAfterSavedResponse: true} : {})});
          assert.notEqual(lost.status, 0);
          if (processSavedResponse) {
            assert.match(lost.stderr, /LostAfterSavedSalesforceResponse/);
          }
          assert.deepEqual(sites.map(site => site.seen.filter(item =>
            item.method === 'PATCH').length), [1, 0]);
        }
        const child = processPreparedIntent
          ? await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs',
            {...childInput, ...(processUnknownIntent || processSavedResponse
              ? {recoveryPass: 'second',
                ...(processSavedResponse
                  ? {reconcileSavedResponse: true} : {})} : {})})
          : spawnSync(process.execPath, [fileURLToPath(new URL(
            './fixtures/recover-effect-outcomes.mjs', import.meta.url,
          ))], {input: JSON.stringify(childInput), encoding: 'utf8',
            timeout: 20_000});
        assert.equal(child.status, 0, child.stderr);
        const fresh = JSON.parse(child.stdout);
        assert.equal(fresh.capturedRunCid, computation.capturedRun.identity);
        assert.deepEqual(fresh.localInventory,
          JSON.parse(computation.capturedRun.wire)
            .effect_source_local_inventory);
        assert.deepEqual(fresh.effectIdentities,
          JSON.parse(preview.wire).effects.map(
            member => member.effect_identity_cid));
        assert.deepEqual(fresh.readyRows, processPreparedIntent
          ? [] : [[0, 0], [1, 0]]);
        assert.deepEqual(fresh.requestCids,
          members.map(member => member.claims.map(
            claim => claim.canonicalRequestCid)));
        assert.deepEqual(fresh.recoveredKeyCids,
          preview.keys.map(member => member.map(key =>
            effect.dispatchKeyCid(key))));
        assert.deepEqual(fresh.recoveredCatalogCids,
          sites.map(site => site.catalog.observationCid));
        assert.equal(fresh.setStatus, processUnknownIntent
          ? 'unknown_outcome' : processPreparedIntent ? 'applied' : null);
        assert.equal(fresh.dispatched, processUnknownIntent ? 2 :
          processSavedResponse ? 3 :
          processPreparedIntent ? 4 : null);
        assert.equal(fresh.reconciledResponse, processSavedResponse
          ? true : null);
        assert.equal(fresh.setReceiptCid === null, !processPreparedIntent);
        if (processUnknownIntent) {
          processUnknownSetCid = fresh.setReceiptCid;
        }
        control = runtimeCore(moon).publicationControl;
        physicalStore = await openLocalPublicationStore(configuration, control);
        store = Object.freeze({...physicalStore,
          async commitEffectfulIndex(...args) {
            commitCalls++;
            const result = await physicalStore.commitEffectfulIndex(...args);
            if (commitCalls === 1) {
              throw new Error('LostEffectIndexCommitAck');
            }
            return result;
          },
        });
        const completed = await recoverCompletedEffectfulComputation({
          store, control, runDefinition, contractLimits: publicationLimits,
        });
        storedResults = completed.storedResults;
        computation = completed.computation;
        admittedPreview = completed.preview;
        ledger = openLedger();
        const recovered = ledger.recoverClaimFacts({
          preview: applyPreview, scope: requestScope,
          programId: 'program-1', nodeId: 'node-1',
          maxRows: 4, maxWork: 100,
        });
        assert.equal(effect.setFrontierReadyCount(recovered.frontier),
          processPreparedIntent ? 0 : 2);
        assert.deepEqual(recovered.members.map(member => member.claims.map(
          claim => claim.canonicalRequestCid)),
        members.map(member => member.claims.map(
          claim => claim.canonicalRequestCid)));
        applyPreview = effect.admitPreviewIdentity(
          control.effectComputationPreviewWire(admittedPreview),
          body.run_identity_cid,
          preview.authoringCid, requestScope, preview.keys,
          publicationLimits.maxWireBytes, publicationLimits.maxNodes,
          publicationLimits.maxDepth);
        assert.equal(completed.connectorRecovery.length, 2);
        const originalCatalogs = completed.connectorRecovery.map(
          (entry, index) => {
            assert.equal(entry.memberIndex, index);
            assert.equal(entry.kind, 'salesforce-catalog');
            return recoverRetainedSalesforceCatalog({
              moon: salesforceMoon,
              retained: JSON.parse(entry.wire).catalog,
              expectedObservationCid: entry.observationCid,
              maxRetainedBytes: 30000,
            }).observation;
          });
        const recoveryRequestOptions = {
          moon: salesforceMoon,
          previewWire: control.effectComputationPreviewWire(admittedPreview),
          runIdentityCid: body.run_identity_cid,
          authoringContextCid: preview.authoringCid,
          members: sites.map((site, memberIndex) => ({
            projection: prepareSiteProjection(site,
              originalCatalogs[memberIndex]), apiVersion: 'v62.0',
            resourceOrigin: site.origin,
            claims: recovered.members[memberIndex].claims,
          })),
          previewLimits: publicationLimits,
          bodyLimits: {maxBytes: 1024, maxNodes: 32, maxDepth: 5},
          requestLimits: {maxPathBytes: 256, maxTargetBytes: 128,
            maxBodyBytes: 1024},
          maxMembers: 2, maxRows: 4,
          maxIdentityBytes: 4096,
        };
        assert.throws(() => recoverPreparedSalesforceSingleRequests({
          ...recoveryRequestOptions,
          members: recoveryRequestOptions.members.slice(0, 1),
        }), {code: 'InvalidSalesforcePreparedRequestRecovery'});
        assert.throws(() => recoverPreparedSalesforceSingleRequests({
          ...recoveryRequestOptions,
          members: recoveryRequestOptions.members.map((member, index) =>
            index === 0 ? {...member, claims: member.claims.slice(0, 1)} :
              member),
        }), {code: 'InvalidSalesforcePreparedRequestRecovery'});
        const reconstructed = recoverCapturedSalesforceSingleRequests({
          moon: salesforceMoon, recovered: completed, recorded: recovered,
          previewWire: recoveryRequestOptions.previewWire,
          runIdentityCid: body.run_identity_cid,
          authoringContextCid: preview.authoringCid,
          previewLimits: publicationLimits,
          bodyLimits: recoveryRequestOptions.bodyLimits,
          requestLimits: recoveryRequestOptions.requestLimits,
          maxMembers: 2, maxRows: 4, maxRetainedBytes: 30000,
        });
        assert.deepEqual(reconstructed.catalogs.map(catalog =>
          salesforceMoon.salesforceCatalogObservationCid(catalog)),
        sites.map(site => site.catalog.observationCid));
        const foreignRecovery = completed.connectorRecovery.map(
          (entry, index) => index === 0 ? {
            ...entry, observationCid: sites[1].catalog.observationCid,
          } : entry);
        assert.throws(() => recoverCapturedSalesforceSingleRequests({
          moon: salesforceMoon,
          recovered: {...completed, connectorRecovery: foreignRecovery},
          recorded: recovered,
          previewWire: recoveryRequestOptions.previewWire,
          runIdentityCid: body.run_identity_cid,
          authoringContextCid: preview.authoringCid,
          previewLimits: publicationLimits,
          bodyLimits: recoveryRequestOptions.bodyLimits,
          requestLimits: recoveryRequestOptions.requestLimits,
          maxMembers: 2, maxRows: 4, maxRetainedBytes: 30000,
        }), {code: 'ForeignRetainedSalesforceCatalog'});
        const invalidOperationRecovery = completed.connectorRecovery.map(
          (entry, index) => index === 0 ? {
            ...entry, wire: JSON.stringify({
              ...JSON.parse(entry.wire), operation: 'toString',
            }),
          } : entry);
        assert.throws(() => recoverCapturedSalesforceSingleRequests({
          moon: salesforceMoon,
          recovered: {...completed,
            connectorRecovery: invalidOperationRecovery},
          recorded: recovered,
          previewWire: recoveryRequestOptions.previewWire,
          runIdentityCid: body.run_identity_cid,
          authoringContextCid: preview.authoringCid,
          previewLimits: publicationLimits,
          bodyLimits: recoveryRequestOptions.bodyLimits,
          requestLimits: recoveryRequestOptions.requestLimits,
          maxMembers: 2, maxRows: 4, maxRetainedBytes: 30000,
        }), {code: 'InvalidSalesforceCapturedRequestRecovery'});
        const recoveryPreview = reconstructed.preview;
        siteRequests = reconstructed.requests;
        sites.forEach((site, memberIndex) => {
          recovered.members[memberIndex].claims.forEach((claim, rowIndex) => {
            assert.equal(checked(salesforceMoon
              .salesforceSingleWriteRequestMatchesPreviewFootprint(
                recoveryPreview, memberIndex, rowIndex,
                siteRequests[memberIndex][rowIndex], 4096)), true);
            assert.equal(checked(
              salesforceMoon.salesforceSingleWriteRequestCid(
                siteRequests[memberIndex][rowIndex], site.origin, 4096)),
            claim.canonicalRequestCid);
          });
        });
        assert.throws(() => checked(
          salesforceMoon.salesforceRecoverSingleWriteRequest(
            recoveryPreview, 0, 0, prepareSiteProjection(sites[1]), 'v62.0',
            1024, 32, 5, 256, 128, 1024, 4096,
            sites[1].origin, recovered.members[0].claims[0]
              .canonicalRequestCid)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          salesforceMoon.salesforceRecoverSingleWriteRequest(
            recoveryPreview, 0, 0, prepareSiteProjection(sites[0]), 'v62.0',
            1024, 32, 5, 256, 128, 1024, 4096,
            sites[0].origin, cid('9'))),
        {code: 'MoonBitHostFailure'});
        recoveredApplyOptions = {
          moon, store, publicationControl: control, computation,
          preview: admittedPreview, ledger, requestScope,
          programId: 'program-1', nodeId: 'node-1', maxRows: 4,
          maxFrontierWork: 64, maxRecoveryWork: 100,
          keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
            maxWork: 100},
          authorization: applyOptions.authorization,
          refreshPreflight: async ({signal}) => {
            const current = await applyOptions.refreshPreflight({signal,
              preflight});
            delete current.proofs;
            delete current.keys;
            return current;
          },
        };
        if (!processPreparedIntent) {
          await assert.rejects(applyRecoveredEffectSet({
            ...recoveredApplyOptions, authorization: undefined,
            refreshPreflight: () =>
              assert.fail('unauthorized recovery refreshed a target'),
            dispatchRow: () =>
              assert.fail('unauthorized recovery sent a row'),
          }), {code: 'EffectApplyAuthorizationRequired'});
          const deniedReads = await fixtureAuthorization([
            accountEntry('recovered-effect-allow', 'allow',
              {operation: 'effect'}),
            accountEntry('recovered-read-deny', 'deny',
              {operation: 'read'}),
          ]);
          await assert.rejects(applyRecoveredEffectSet({
            ...recoveredApplyOptions,
            authorization: {gate: deniedReads, scopes: commitScopes},
            refreshPreflight: () =>
              assert.fail('recovered read denial refreshed a target'),
            dispatchRow: () =>
              assert.fail('recovered read denial sent a row'),
          }), {code: 'ExecutionAuthorizationDenied'});
          await assert.rejects(applyRecoveredEffectSet({
            ...recoveredApplyOptions,
            refreshPreflight: async ({signal}) => ({
              ...await recoveredApplyOptions.refreshPreflight({signal}),
              sources: [cid('9'), cid('c')],
            }),
            dispatchRow: () => assert.fail('foreign recovery sent a row'),
          }), {code: 'MoonBitHostFailure'});
          await assert.rejects(applyRecoveredEffectSet({
            ...recoveredApplyOptions,
            refreshPreflight: async ({signal}) => ({
              ...await recoveredApplyOptions.refreshPreflight({signal}),
              requestScope: effect.logicalRequestScope(
                cid('e'), 'another-effect-request', 256),
            }),
            dispatchRow: () => assert.fail('foreign scope sent a row'),
          }), {code: 'EffectRecoveredRequestScopeChanged'});
        }
        await assert.rejects(applyRecoveredEffectSet({
          ...recoveredApplyOptions,
          computation: {...computation},
          dispatchRow: () => assert.fail('unowned recovery sent a row'),
        }), {code: 'InvalidCompletedEffectfulApplyOwner'});
        applyOptions.ledger = ledger;
        applyOptions.members = recovered.members;
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions,
          preflight: {...preflight, sources: [cid('9'), cid('c')]},
          dispatchRow: () => assert.fail('foreign recovery sent a row'),
        }), {code: 'MoonBitHostFailure'});
        assert.equal(sites.flatMap(site => site.seen).filter(item =>
          item.method === 'PATCH').length,
        processUnknownIntent ? 3 : processPreparedIntent ? 4 : 0);
        if (!processPreparedIntent && !processUnknownIntent) {
        // The guard refresh is a credentialed read of the Effect targets:
        // it is authorized at the acquisition boundary (operation read,
        // Effect target connection/resource, sealed Set Preview subject)
        // before any read, and the commit is authorized separately.
        // Provider reads for the refresh: target record GETs, and the
        // Site's current Catalog recheck (sObject list and describe).
        const record = /^\/services\/data\/v62\.0\/sobjects\/Test_Record__c\/0/u;
        const readsOf = isRecord => () => sites.map(site => site.seen.filter(
          item => item.method === 'GET' &&
            record.test(item.path) === isRecord).length);
        const targetReads = readsOf(true);
        const describeReads = readsOf(false);
        const writes = () => sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length;
        const readCounts = {};
        const tryGate = async (name, entries, code, check) => {
          const readsBefore = targetReads();
          const describesBefore = describeReads();
          const usesBefore = sites.map(site => site.journal.recover().length);
          const writesBefore = writes();
          const ledgerHeadsBefore = members.flatMap(member => member.claims)
            .filter(claim => ledger.current(effect.logicalItemLocatorCid(
              claim.locator)) !== undefined).length;
          const gate = await fixtureAuthorization(entries);
          await assert.rejects(applyCapturedEffectSet({...applyOptions,
            authorization: {gate, scopes: commitScopes},
            dispatchRow: () => assert.fail(`${name} dispatched a row`),
          }), error => error.code === code && check(error.authorization));
          readCounts[name] = {
            targetReads: targetReads().reduce((sum, value, index) =>
              sum + value - readsBefore[index], 0),
            catalogReads: describeReads().reduce((sum, value, index) =>
              sum + value - describesBefore[index], 0),
            credentialUses: sites.reduce((sum, site, index) =>
              sum + site.journal.recover().length - usesBefore[index], 0),
            writes: writes() - writesBefore,
            ledgerHeads: members.flatMap(member => member.claims).filter(
              claim => ledger.current(effect.logicalItemLocatorCid(
                claim.locator)) !== undefined).length - ledgerHeadsBefore,
            counters: gate.counters(),
          };
        };
        // Read denied: no target read, no credential use, no write.
        await tryGate('readDenied', [
          accountEntry('effect-allow', 'allow', {operation: 'effect'}),
          accountEntry('target-read-deny', 'deny', {operation: 'read'}),
        ], 'ExecutionAuthorizationDenied', decision =>
          decision.boundary === 'acquisition' &&
          decision.tuple.operation === 'read' &&
          decision.tuple.resource === 'Test_Record__c' &&
          decision.subjectCid === JSON.parse(preview.wire).effect_preview_cid);
        // Read unmatched (no read entry): denied as no-match, nothing read.
        await tryGate('readNoMatch', [
          accountEntry('effect-allow', 'allow', {operation: 'effect'}),
        ], 'ExecutionAuthorizationDenied', decision =>
          decision.boundary === 'acquisition' &&
          decision.reason === 'no_match');
        // Read allowed, Effect commit denied: target reads happen, no write.
        await tryGate('commitDenied', [
          accountEntry('effect-deny', 'deny', {operation: 'effect'}),
          accountEntry('target-read-allow', 'allow', {operation: 'read'}),
        ], 'ExecutionAuthorizationDenied', decision =>
          decision.boundary === 'effect_commit' &&
          decision.tuple.operation === 'effect');
        for (const name of ['readDenied', 'readNoMatch']) {
          assert.equal(readCounts[name].targetReads, 0, name);
          assert.equal(readCounts[name].catalogReads, 0, name);
          assert.equal(readCounts[name].credentialUses, 0, name);
        }
        // Authorized refresh: one record read per guarded row plus each
        // Site's current Catalog recheck, each a credential use.
        assert.equal(readCounts.commitDenied.targetReads, 4);
        assert.equal(readCounts.commitDenied.catalogReads, 4);
        assert.equal(readCounts.commitDenied.credentialUses, 8);
        for (const counts of Object.values(readCounts)) {
          assert.equal(counts.writes, 0);
          assert.equal(counts.ledgerHeads, 0);
        }
        t.diagnostic(`effect target read authorization counts ${
          JSON.stringify(Object.fromEntries(Object.entries(readCounts).map(
            ([name, {counters, ...rest}]) => [name, {...rest,
              evaluations: counters.evaluations,
              protectedDispatches: counters.protectedDispatches,
              deniedBeforeDispatch: counters.deniedBeforeDispatch}])))}`);
        }
      }
      if (physical === 'salesforce-stale-target' ||
          physical === 'salesforce-schema-drift') {
        if (physical === 'salesforce-schema-drift') {
          sites[1].setNameUpdateable(false);
        }
        if (physical === 'salesforce-stale-target') {
          sites[0].setTargetName('changed-after-preview');
        }
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions,
          dispatchRow: () => assert.fail('stale target dispatched'),
        }), {code: 'MoonBitHostFailure'});
        assert.equal(sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length, 0);
        for (const claim of members.flatMap(member => member.claims)) {
          assert.equal(ledger.current(effect.logicalItemLocatorCid(
            claim.locator)), undefined);
        }
        if (physical === 'salesforce-schema-drift') {
          assert.deepEqual(sites.map(site => site.seen.filter(item =>
            item.path.endsWith('/describe')).length), [2, 2]);
        }
        assert.deepEqual(sites.map(site => site.journal.recover().length),
          expectedCredentialUses([0, 0]));
        const privateHoldingCid = control.effectPrivateEvidenceBinding(
          admittedPreview, store.storeAuthorityCid).holdingCid;
        for (const holdingCid of [privateHoldingCid,
          firstHolding.holdingCid, secondHolding.holdingCid]) {
          assert.equal((await store.retirePhysicalHolding(holdingCid))
            .deleted, true);
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        published = true;
        return;
      }
      let responseFaultPending = recoverAfterResponse;
      let collectionFaultPending = collectionRecovered;
      let terminalFaultPending = restartAfterTerminal;
      let unknownFaultPending = unknownAfterClaim && !loseHttpReply;
      const dispatchRow = async ({memberIndex, rowIndex, claim}) => {
          sent.push([memberIndex, rowIndex]);
          if (sent.length === 1) {
            for (const pending of members.flatMap(member => member.claims)) {
              assert.equal(effect.ledgerEntryStateCode(
                ledger.currentAdmitted(effect.logicalItemLocatorCid(
                  pending.locator))), 0);
            }
          }
          if (siteRun) {
            const site = sites[memberIndex];
            if (collectionMode && memberIndex === 0) {
              assert.equal(rowIndex, 0);
              const collectionFault = collectionFaultPending;
              collectionFaultPending = false;
              const collectionLedger = collectionFault ? Object.freeze({
                ...ledger,
                recordBatchResponse(observation) {
                  ledger.recordBatchResponse(observation);
                  throw new Error('LostAfterSavedCollectionResponse');
                },
              }) : ledger;
              const batch = await captureSalesforceCollectionEffectWrite({
                ledger: collectionLedger, claims: members[0].claims,
                admittedPreview: applyPreview, memberIndex: 0,
                firstRow: 0, commonMoon: moon, moon: salesforceMoon,
                request: collectionRequest,
                currentObservation: currentCatalogs[memberIndex],
                authorization: {...site.write,
                  useId: 'partial-collection'},
                credential: site.credential,
                limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
                  maxNodes: 64, maxDepth: 6, maxRows: 2},
              });
              assert.equal(batch.claimed, true);
              assert.equal(batch.outcomeReceipts.length, 2);
              return;
            }
            const responseFault = responseFaultPending &&
              memberIndex === 0 && rowIndex === 0;
            if (responseFault) responseFaultPending = false;
            const dispatchFault = unknownFaultPending &&
              memberIndex === 0 && rowIndex === 0;
            if (dispatchFault) unknownFaultPending = false;
            const physicalLedger = responseFault ? Object.freeze({
              ...ledger,
              recordResponse(observation) {
                ledger.recordResponse(observation);
                throw new Error('LostAfterSavedSalesforceResponse');
              },
            }) : ledger;
            const received = await captureSalesforceSingleEffectWrite({
              ledger: physicalLedger, commonMoon: moon,
              admittedPreview: applyPreview,
              memberIndex, rowIndex,
              rowPreviewCid: body.effects[memberIndex]
                .changes[rowIndex].row_preview_cid,
              claim, moon: salesforceMoon,
              request: siteRequests[memberIndex][rowIndex],
              currentObservation: currentCatalogs[memberIndex],
              authorization: {...site.write,
                useId: `write-${memberIndex}-${rowIndex}`},
              credential: site.credential,
              limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
                maxNodes: 32, maxDepth: 5},
              callResource: dispatchFault ? async () => {
                throw new Error('LostAfterSalesforceDispatchClaim');
              } : undefined,
            });
            assert.equal(received.claimed, true);
            if (rateLimitWrite && memberIndex === 0 && rowIndex === 0) {
              assert.equal(received.physical.kind, 'provider-response');
              assert.equal(received.physical.observation.statusCode, 403);
              assert.equal(received.terminal, undefined);
              return;
            }
            assert.equal(received.terminal.created, true);
            if (terminalFaultPending && memberIndex === 0 && rowIndex === 0) {
              terminalFaultPending = false;
              throw new Error('LostAfterSalesforceRowTerminal');
            }
            return;
          }
          const response = await captureClaimedEffectResponse({
            ledger, claim, requestCid: claim.canonicalRequestCid,
            execute: async () => ({observation: {useCid: cid('4'),
              statusCode: 204, body: Buffer.alloc(0)}}),
          });
          assert.equal(response.claimed, true);
          ledger.recordAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex,
            previewRowIndex: rowIndex,
            outcomeWire: canonicalJson({state: 'applied',
              result: {record_id: `member-${memberIndex}-row-${rowIndex}`}}),
          });
          ledger.commitAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex,
            previewRowIndex: rowIndex,
          });
      };
      if (recoverAfterResponse) {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, dispatchRow,
        }), {message: 'LostAfterSavedSalesforceResponse'});
        assert.deepEqual(sent, [[0, 0]]);
        ledger.close();
        ledger = openLedger();
        const savedClaim = members[0].claims[0];
        const saved = await captureSalesforceSingleEffectWrite({
          ledger, commonMoon: moon, admittedPreview: applyPreview,
          memberIndex: 0, rowIndex: 0,
          rowPreviewCid: body.effects[0].changes[0].row_preview_cid,
          claim: savedClaim, moon: salesforceMoon,
          request: siteRequests[0][0],
          currentObservation: sites[0].catalog.observation,
          authorization: {...sites[0].write, useId: 'recovery-no-send'},
          credential: sites[0].credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 32, maxDepth: 5},
          authorizeEvidenceRead: async () => true,
        });
        assert.equal(saved.claimed, false);
        assert.equal(saved.terminal.created, true);
        assert.equal(sites[0].seen.filter(item =>
          item.method === 'PATCH').length, 1);
      }
      if (restartAfterTerminal) {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, dispatchRow,
        }), {message: 'LostAfterSalesforceRowTerminal'});
        assert.deepEqual(sent, [[0, 0]]);
        ledger.close();
        ledger = openLedger();
        assert.ok(ledger.readClaimedOutcome(members[0].claims[0]));
      }
      if (collectionRecovered) {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, dispatchRow,
        }), {message: 'LostAfterSavedCollectionResponse'});
        assert.deepEqual(sent, [[0, 0]]);
        assert.equal(sites[0].seen.filter(item =>
          item.method === 'PATCH').length, 1);
        ledger.close();
        ledger = openLedger();
        const saved = await captureSalesforceCollectionEffectWrite({
          ledger, claims: members[0].claims,
          admittedPreview: applyPreview, memberIndex: 0,
          firstRow: 0, commonMoon: moon, moon: salesforceMoon,
          request: collectionRequest,
          currentObservation: sites[0].catalog.observation,
          authorization: {...sites[0].write,
            useId: 'collection-recovery-no-send'},
          credential: sites[0].credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 64, maxDepth: 6, maxRows: 2},
          authorizeEvidenceRead: async () => true,
        });
        assert.equal(saved.claimed, false);
        assert.equal(saved.outcomeReceipts.length, 2);
        assert.equal(sites[0].seen.filter(item =>
          item.method === 'PATCH').length, 1);
        assert.equal(sites[0].journal.recover().length,
          expectedCredentialUses([1, 2])[0]);
      }
      const rejectPublicationAndRetire = async (issuedSet, code,
        attemptId) => {
        const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
          runDefinitionCid: runDefinition.identity};
        await assert.rejects(publishCompletedEffectfulRun({
          execution: restartPreparedIntent ? null : execution,
          store, storedResults, control, computation,
          preview: admittedPreview, ledger, issuedSet,
          request: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
            publicationPolicyCid: cid('e'),
            publicationTargetCid: cid('f'),
            requestedAt: '2026-09-24T00:00:01.000Z'},
          attempt: {attemptId, fenceCid: cid('0'),
            externalIdempotencyKey: undefined,
            startedAt: '2026-09-24T00:00:02.000Z'},
          contractLimits: publicationLimits,
          now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
        }), {code});
        assert.equal(await store.inspectCommittedIndex(key), undefined);
        assert.ok(await store.inspectPhysicalHolding(firstHolding.holdingCid));
        assert.ok(await store.inspectPhysicalHolding(secondHolding.holdingCid));
        const privateHoldingCid = control.effectPrivateEvidenceBinding(
          admittedPreview, store.storeAuthorityCid).holdingCid;
        assert.ok(await store.inspectPhysicalHolding(privateHoldingCid));
        assert.equal((await store.retirePhysicalHolding(
          privateHoldingCid)).deleted, true);
        assert.equal((await store.retirePhysicalHolding(
          firstHolding.holdingCid)).deleted, true);
        assert.equal((await store.retirePhysicalHolding(
          secondHolding.holdingCid)).deleted, true);
        for (const holdingCid of [privateHoldingCid,
          firstHolding.holdingCid, secondHolding.holdingCid]) {
          assert.equal(await store.inspectPhysicalHolding(holdingCid),
            undefined);
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
      };
      if (processUnknownIntent) {
        const noReplay = await applyRecoveredEffectSet({
          ...recoveredApplyOptions,
          refreshPreflight: () =>
            assert.fail('unknown process replay refreshed current Site'),
          dispatchRow: () =>
            assert.fail('unknown or known row resent after process restart'),
        });
        assert.equal(noReplay.dispatched, 0);
        assert.deepEqual(sites.map(site => site.seen.filter(item =>
          item.method === 'PATCH').length), [1, 2]);
        const uncertainSet = await issueAuthorizedEffectSetReceipt({
          ledger, preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: members.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: true,
          })), limits: publicationLimits,
        });
        assert.equal(uncertainSet.set.identity, processUnknownSetCid);
        assert.equal(JSON.parse(uncertainSet.set.wire).status,
          'unknown_outcome');
        assert.deepEqual(JSON.parse(uncertainSet.set.wire).effects.map(
          member => member.state), ['unknown', 'applied']);
        await rejectPublicationAndRetire(uncertainSet,
          'EffectfulRunNeedsReconciliation',
          'process-unknown-two-effects-attempt');
        return;
      }
      if (rateLimitWrite) {
        const first = await applyCapturedEffectSet({...applyOptions,
          dispatchRow});
        assert.equal(first.dispatched, 3);
        assert.deepEqual(sent, [[0, 0], [1, 0], [1, 1]]);
        assert.equal(sites[0].seen.filter(item =>
          item.method === 'PATCH').length, 1);
        ledger.close();
        ledger = openLedger();
        const savedLimitReply = ledger.readClaimedResponse(
          members[0].claims[0]);
        assert.equal(savedLimitReply.statusCode, 403);
        assert.equal(JSON.parse(savedLimitReply.responseBytes.toString('utf8'))
          [0].errorCode, 'REQUEST_LIMIT_EXCEEDED');
        const noReplay = await applyCapturedEffectSet({
          ...applyOptions, ledger,
          refreshPreflight: () =>
            assert.fail('rate-limited replay refreshed current Site'),
          dispatchRow: () => assert.fail('rate-limited row resent'),
        });
        assert.equal(noReplay.dispatched, 0);
        const uncertainSet = await issueAuthorizedEffectSetReceipt({
          ledger, preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: members.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: true,
          })), limits: publicationLimits,
        });
        assert.equal(JSON.parse(uncertainSet.set.wire).status,
          'unknown_outcome');
        assert.deepEqual(JSON.parse(uncertainSet.set.wire).effects.map(
          member => member.state), ['unknown', 'applied']);
        await rejectPublicationAndRetire(uncertainSet,
          'EffectfulRunNeedsReconciliation',
          'rate-limited-two-effects-attempt');
        return;
      }
      if (authorizationScenarios) {
        const lost = await verifyEffectCommitAuthorization(t, {
          moon, previewInputs, members, preflight, applyPreview, body,
          directory, memberIds,
        });
        // The lost-reply Run's durable facts make the set outcome need
        // reconciliation; publication is refused and holdings retired.
        ledger.close();
        ledger = openEffectLedger({moon, root: lost.ledgerRoot,
          authorityScopeCid: cid('e'),
          callerRequestId: 'complete-two-effects-request',
          maxEntryBytes: 4096});
        const uncertainSet = await issueAuthorizedEffectSetReceipt({
          ledger, preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: members.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: true,
          })), limits: publicationLimits,
        });
        const uncertain = JSON.parse(uncertainSet.set.wire);
        assert.equal(uncertain.status, 'unknown_outcome');
        assert.equal(uncertain.effects[lost.lostMember].state, 'unknown');
        await rejectPublicationAndRetire(uncertainSet,
          'EffectfulRunNeedsReconciliation', 'authorization-unknown-attempt');
        return;
      }
      if (unknownAfterClaim) {
        const initial = applyCapturedEffectSet({...applyOptions,
          dispatchRow});
        if (loseHttpReply) {
          await assert.rejects(initial);
        } else {
          await assert.rejects(initial,
            {message: 'LostAfterSalesforceDispatchClaim'});
        }
        assert.deepEqual(sent, [[0, 0]]);
        ledger.close();
        ledger = openLedger();
        const independent = await applyCapturedEffectSet({
          ...applyOptions, ledger, dispatchRow,
        });
        assert.equal(independent.dispatched,
          continueAfterUnknown ? 3 : 2);
        assert.deepEqual(sent, continueAfterUnknown
          ? [[0, 0], [0, 1], [1, 0], [1, 1]]
          : [[0, 0], [1, 0], [1, 1]]);
        ledger.close();
        ledger = openLedger();
        const noReplay = await applyCapturedEffectSet({
          ...applyOptions, ledger,
          refreshPreflight: () =>
            assert.fail('unknown replay refreshed current Site'),
          dispatchRow: () => assert.fail('uncertain or terminal row resent'),
        });
        assert.equal(noReplay.dispatched, 0);
        assert.deepEqual(sites.map(site => site.seen
          .filter(item => item.method === (writeKind === 'create' ?
            'POST' : 'PATCH')).length),
        [continueAfterUnknown || loseHttpReply ? 1 : 0, 2]);
        if (loseHttpReply) {
          const request = sites[0].seen.find(item =>
            item.method === (writeKind === 'create' ? 'POST' : 'PATCH'));
          assert.deepEqual(JSON.parse(request.body), writeKind === 'create'
            ? {Name: sourceIds[0], External_Key__c: sourceIds[0]}
            : {Name: sourceIds[0]});
          assert.deepEqual(sites.map(site => site.journal.recover().length),
            expectedCredentialUses([1, 2]));
        }
        const receiptOptions = {
          ledger, preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: members.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: true,
          })), limits: publicationLimits,
        };
        let uncertainSet;
        if (physical === 'salesforce-unknown') {
          const completed = await completeCapturedEffectRun({
            apply: {...applyOptions, ledger,
              refreshPreflight: () => assert.fail('unknown replay refreshed'),
              dispatchRow: () => assert.fail('unknown row resent')},
            receipt: receiptOptions,
            publication: {execution, store, storedResults, control,
              computation, preview: admittedPreview, ledger,
              request: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
                publicationPolicyCid: cid('e'),
                publicationTargetCid: cid('f'),
                requestedAt: '2026-09-24T00:00:01.000Z'},
              attempt: {attemptId: 'unknown-two-effects-attempt',
                fenceCid: cid('0'), externalIdempotencyKey: undefined,
                startedAt: '2026-09-24T00:00:02.000Z'},
              contractLimits: publicationLimits,
              now: () => '2026-09-24T00:00:03.000Z'},
          });
          assert.equal(completed.status, 'needs_reconciliation');
          assert.equal(completed.progress.dispatched, 0);
          uncertainSet = completed.issuedSet;
        } else {
          uncertainSet = await issueAuthorizedEffectSetReceipt(
            receiptOptions);
        }
        assert.equal(JSON.parse(uncertainSet.set.wire).status,
          'unknown_outcome');
        assert.deepEqual(JSON.parse(uncertainSet.set.wire).effects.map(
          member => member.state), ['unknown', 'applied']);
        await rejectPublicationAndRetire(uncertainSet,
          'EffectfulRunNeedsReconciliation',
          'unknown-two-effects-attempt');
        return;
      }
      const applied = restartPreparedIntent
        ? await applyRecoveredEffectSet({
          ...recoveredApplyOptions,
          dispatchRow: processPreparedIntent
            ? () => assert.fail('fresh-process write resent') : dispatchRow,
          ...(processPreparedIntent ? {refreshPreflight: () =>
            assert.fail('settled process replay refreshed Site')} : {}),
        })
        : await applyCapturedEffectSet({
          ...applyOptions, ledger, dispatchRow,
        });
      assert.equal(applied.dispatched, processPreparedIntent ? 0 :
        collectionRecovered ? 2 :
          recoverAfterResponse || restartAfterTerminal || collectionPartial
            ? 3 : 4);
      if (restartPreparedIntent) {
        const settled = await applyRecoveredEffectSet({
          ...recoveredApplyOptions,
          refreshPreflight: () => assert.fail('settled replay refreshed Site'),
          dispatchRow: () => assert.fail('settled row resent'),
        });
        assert.equal(settled.dispatched, 0);
        await assert.rejects(applyRecoveredEffectSet({
          ...recoveredApplyOptions, computation: {...computation},
          refreshPreflight: () => assert.fail('foreign replay refreshed Site'),
          dispatchRow: () => assert.fail('foreign row sent'),
        }), {code: 'InvalidCompletedEffectfulApplyOwner'});
      }
      if (collectionPartial) {
        assert.deepEqual(sent, [[0, 0], [1, 0], [1, 1]]);
        assert.deepEqual(sites.map(site => site.seen
          .filter(item => item.method === 'PATCH').length), [1, 2]);
        assert.deepEqual(sites.map(site => site.journal.recover().length),
          expectedCredentialUses([1, 2]));
        ledger.close();
        ledger = openLedger();
        const replay = await applyCapturedEffectSet({
          ...applyOptions, ledger,
          refreshPreflight: () =>
            assert.fail('terminal replay refreshed current Site'),
          dispatchRow: () => assert.fail('known row resent'),
        });
        assert.equal(replay.dispatched, 0);
        const partialSet = await issueAuthorizedEffectSetReceipt({
          ledger, preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: members.map((member, memberIndex) => ({
            rowOwners: member.claims.map((claim, rowIndex) =>
              memberIndex === 0
                ? {claims: member.claims, batchRowIndex: rowIndex}
                : {claim}),
            replayed: true,
          })), limits: publicationLimits,
        });
        assert.equal(JSON.parse(partialSet.set.wire).status, 'partial_failure');
        assert.deepEqual(JSON.parse(partialSet.set.wire).effects.map(
          member => member.state), ['failed', 'applied']);
        assert.deepEqual(JSON.parse(partialSet.members[0].wire).rows.map(
          row => row.state), ['failed', 'applied']);
        assert.deepEqual(JSON.parse(partialSet.members[1].wire).rows.map(
          row => row.state), ['applied', 'applied']);
        await rejectPublicationAndRetire(partialSet, 'EffectfulRunFailed',
          'partial-two-effects-attempt');
        return;
      }
      if (siteRun) {
        const writeMethod = writeKind === 'create' ? 'POST' : 'PATCH';
        assert.deepEqual(sites.map(site => site.seen
          .filter(item => item.method === writeMethod).length),
        collectionRecovered ? [1, 2] : [2, 2]);
        assert.deepEqual(sites.map(site => site.journal.recover().length),
          expectedCredentialUses(collectionRecovered ? [1, 2] : [2, 2]));
        if (collectionRecovered) {
          const sentBatch = JSON.parse(sites[0].seen.find(item =>
            item.method === 'PATCH').body);
          assert.deepEqual(sentBatch.records.map(item => item.Name),
            sourceIds);
        } else {
          assert.deepEqual(sites.map(site => site.seen
            .filter(item => item.method === writeMethod)
            .map(item => JSON.parse(item.body).Name)),
          [sourceIds, sourceIds]);
        }
        if (writeKind === 'create') {
          for (const site of sites) {
            assert.equal(site.write.scope.operation,
              'salesforce:record:create');
            assert.deepEqual(site.seen.filter(item =>
              item.method === 'POST').map(item => item.path),
            sourceIds.map(() =>
              '/services/data/v62.0/sobjects/Test_Record__c/'));
          }
        }
        if (writeKind === 'upsert') {
          for (const site of sites) {
            assert.equal(site.write.scope.operation,
              'salesforce:record:upsert');
            assert.deepEqual(site.seen.filter(item =>
              item.method === 'PATCH').map(item => item.path),
            sourceIds.map(id => `/services/data/v62.0/sobjects/` +
              `Test_Record__c/External_Key__c/${id}`));
          }
        }
      }
      if (!processPreparedIntent) {
        for (let memberIndex = 0; memberIndex < 2; memberIndex++) {
          assert.deepEqual(sent.filter(item => item[0] === memberIndex)
            .map(item => item[1]),
          collectionRecovered && memberIndex === 0 ? [0] : [0, 1]);
        }
      }
      ledger.close();
      ledger = openLedger();
      await assert.rejects(applyCapturedEffectSet({
        ...applyOptions, ledger,
        preflight: {...preflight, sources: [cid('c'), cid('f')]},
        refreshPreflight: () =>
          assert.fail('foreign terminal replay refreshed current Site'),
        dispatchRow: () => assert.fail('foreign terminal row resent'),
      }), {code: 'MoonBitHostFailure'});
      const replay = await applyCapturedEffectSet({
        ...applyOptions, ledger,
        refreshPreflight: () =>
          assert.fail('terminal replay refreshed current Site'),
        dispatchRow: () => assert.fail('terminal row resent'),
      });
      assert.equal(replay.dispatched, 0);
      const publicationRequest = {
        tenantId: 'tenant-a', authorityScopeCid: cid('a'),
        publicationPolicyCid: cid('e'),
        publicationTargetCid: cid('f'),
        requestedAt: '2026-09-24T00:00:01.000Z',
      };
      const publicationAttempt = {
        attemptId: 'complete-two-effects-attempt',
        fenceCid: cid('0'), externalIdempotencyKey: undefined,
        startedAt: '2026-09-24T00:00:02.000Z',
      };
      let freshProcessSetCid;
      let freshProcessIndexCid;
      if (restartBeforeFinal) {
        for (const result of storedResults.results) {
          if (result.prepared.status().pending) {
            await result.prepared.release();
          }
        }
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        await store.close();
        const child = spawnSync(process.execPath, [fileURLToPath(new URL(
          './fixtures/recover-effect-outcomes.mjs', import.meta.url,
        ))], {
          input: JSON.stringify({
            directory, storeAuthorityCid: configuration.storeAuthorityCid,
            capacityBytes: configuration.capacityBytes,
            maxObjectBytes: configuration.maxObjectBytes,
            maxObjects: configuration.maxObjects,
            maxContractNodes: configuration.maxContractNodes,
            maxContractDepth: configuration.maxContractDepth,
            runDefinitionWire: runDefinition.wire,
            ledgerRoot, authorityScopeCid: cid('e'),
            callerRequestId: 'complete-two-effects-request',
            programId: 'program-1', nodeId: 'node-1',
            maxRows: 4, maxWork: 100, limits: publicationLimits,
            publish: processPublication,
            request: publicationRequest, attempt: publicationAttempt,
            publicationTime: '2026-09-24T00:00:03.000Z',
          }),
          encoding: 'utf8', timeout: 20_000,
        });
        control = runtimeCore(moon).publicationControl;
        physicalStore = await openLocalPublicationStore(configuration, control);
        store = Object.freeze({...physicalStore,
          async commitEffectfulIndex(...args) {
            commitCalls++;
            const result = await physicalStore.commitEffectfulIndex(...args);
            if (commitCalls === 1) {
              throw new Error('LostEffectIndexCommitAck');
            }
            return result;
          },
        });
        assert.equal(child.status, 0, child.stderr);
        const fresh = JSON.parse(child.stdout);
        assert.equal(fresh.capturedRunCid, computation.capturedRun.identity);
        assert.deepEqual(fresh.localInventory,
          JSON.parse(computation.capturedRun.wire)
            .effect_source_local_inventory);
        assert.deepEqual(fresh.effectIdentities,
          JSON.parse(preview.wire).effects.map(
            member => member.effect_identity_cid));
        assert.equal(fresh.setStatus, 'applied');
        assert.deepEqual(fresh.rowCounts, [2, 2]);
        freshProcessSetCid = fresh.setReceiptCid;
        if (processPublication) {
          assert.equal(fresh.publication.state, 'succeeded');
          freshProcessIndexCid = fresh.publication.indexCid;
        } else {
          assert.equal(fresh.publication, null);
        }
        const recovered = await recoverCompletedEffectfulComputation({
          store, control, runDefinition, contractLimits: publicationLimits,
        });
        storedResults = recovered.storedResults;
        computation = recovered.computation;
        admittedPreview = recovered.preview;
        applyPreview = effect.admitPreviewIdentity(
          preview.wire, body.run_identity_cid,
          preview.authoringCid, requestScope, preview.keys,
          publicationLimits.maxWireBytes, publicationLimits.maxNodes,
          publicationLimits.maxDepth);
      }
      const receiptOptions = {
        ledger, preview: applyPreview, commonMoon: moon,
        authorizeEvidenceRead: async () => true,
        publicationPreview: admittedPreview,
        members: members.map((member, memberIndex) => ({
          rowOwners: member.claims.map((claim, rowIndex) =>
            collectionRecovered && memberIndex === 0
              ? {claims: member.claims, batchRowIndex: rowIndex}
              : {claim}),
          replayed: true,
        })),
        limits: publicationLimits,
      };
      const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
        runDefinitionCid: runDefinition.identity};
      const publicationOptions = {
        execution: restartBeforeApply || restartPreparedIntent ||
          restartBeforeFinal
          ? null : execution,
        store, storedResults, control, computation,
        preview: admittedPreview, ledger,
        request: publicationRequest,
        attempt: publicationAttempt,
        contractLimits: publicationLimits,
        now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
      };
      let result, issuedSet;
      if (physical === 'salesforce') {
        const completed = await completeCapturedEffectRun({
          apply: {...applyOptions, ledger,
            refreshPreflight: () =>
              assert.fail('settled Run refreshed current Site'),
            dispatchRow: () => assert.fail('settled Effect row resent')},
          receipt: receiptOptions, publication: publicationOptions,
        });
        assert.equal(completed.status, 'published');
        assert.equal(completed.progress.dispatched, 0);
        issuedSet = completed.issuedSet;
        result = completed.completed;
      } else {
        issuedSet = await issueAuthorizedEffectSetReceipt(receiptOptions);
      }
      assert.equal(issuedSet.members.length, 2);
      assert.equal(JSON.parse(issuedSet.set.wire).status, 'applied');
      if (freshProcessSetCid !== undefined) {
        assert.equal(issuedSet.set.identity, freshProcessSetCid);
      }
      if (restartAfterPublication) {
        const ownedPublication = {...publicationOptions, issuedSet};
        let unknown;
        try { await publishCompletedEffectfulRun(ownedPublication); }
        catch (error) { unknown = error; }
        assert.equal(unknown?.code, 'RunPublicationUnknown');
        assert.equal(unknown.cleanupHandle.status().pending, true);
        assert.equal(commitCalls, 1);
        physicalStore = await openLocalPublicationStore(
          configuration, control);
        const reconciled = await unknown.cleanupHandle.retry();
        assert.equal(reconciled.pending, false);
        assert.equal(reconciled.outcome, 'committed');
        const afterRestart = await applyCapturedEffectSet({
          ...applyOptions, ledger,
          refreshPreflight: () =>
            assert.fail('publication replay refreshed current Site'),
          dispatchRow: () => assert.fail('committed Effect row resent'),
        });
        assert.equal(afterRestart.dispatched, 0);
        result = await publishCompletedEffectfulRun(ownedPublication);
      } else if (result === undefined) {
        result = await publishCompletedEffectfulRun({
          ...publicationOptions, issuedSet,
        });
      }
      assert.equal(result.publication.committed, false);
      assert.equal(result.publication.idempotent, true);
      assert.equal(result.publication.state, 'succeeded');
      assert.equal(commitCalls, processPublication ? 0 : 1);
      if (processPublication) {
        assert.equal(result.publication.index.identity,
          freshProcessIndexCid);
      }
      const indexBody = JSON.parse(result.publication.index.wire);
      const finalReceipt = await store.readPublicationContract(
        indexBody.run_receipt_cid, 'run_receipt');
      assert.equal(JSON.parse(finalReceipt.wire)
        .effect_set_apply_receipt_cid, issuedSet.set.identity);
      assert.equal(commitCalls, processPublication ? 0 : 1);
      assert.equal(sent.length, processPreparedIntent ? 0 :
        collectionRecovered ? 3 : 4);
      if (siteRun) {
        assert.equal(sites.flatMap(site => site.seen)
          .filter(item => item.method === (writeKind === 'create' ?
            'POST' : 'PATCH')).length,
        collectionRecovered ? 3 : 4);
      }
      await releaseCompletedRunPreparedPayloads(storedResults, control);
      assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      if (siteRun) {
        assert.throws(() =>
          control.checkSourceFreeLocalEffectPreviewIdentities(
            prepared, inputs, preview.wire, definition.identity,
            preview.authoringCid, issuedLocalIdentities,
            publicationLimits));
      }
      inputs = undefined;
      ledger.close();
      ledger = undefined;
      await store.close();
      store = await openLocalPublicationStore(configuration, control);
      assert.ok(await store.inspectCommittedIndex(key));
      const chunks = [];
      await store.consumeCommittedResult(key,
        storedResults.definitions[0].identity, () => true,
        chunk => chunks.push(Buffer.from(chunk)));
      assert.equal(Buffer.concat(chunks).toString('utf8'),
        JSON.stringify(siteRun ? sourceIds.map(id => ({id}))
          : [{id: 1}, {id: 2}]));
      const accessAuthority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: facts => ({
          authorizationContextCid: `sha256:${createHash('sha256')
            .update(facts.attemptId).digest('hex')}`,
          dataCeilingCid: cid('9'), egressAdmissionCid: cid('a'),
          expiresAt: '2026-09-24T01:00:00.000Z',
          maxBytes: 100000, maxUses: 1,
        }),
        authorizeResultRead: () => true,
        authorizeDeliveryAttemptLookup: () => true,
      });
      const resultService = installNodeResultAccessService({
        store, control, authority: accessAuthority,
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      const stateService = installRunStateService({
        store, control,
        authority: installRunStateAuthority({
          authorizeRunState: () => true,
          resultPolicyAvailable: () => true,
        }),
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
      });
      const clientServer = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-after-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local' &&
          (facts.ref === undefined || facts.ref.tenantId === 'tenant-a'),
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-after-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        attach: async ({ref, principalId}) => {
          await inspectAuthorizedRunState(stateService, {
            indexKey: ref, principalId, purpose: 'inspect',
          });
          return {ref, durability: 'durable', revision: 0};
        },
        stateService, resultService,
      }));
      await new Promise(resolve => clientServer.listen(0, '127.0.0.1',
        resolve));
      try {
        const client = await connectClient({mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${clientServer.address().port}/`,
          token: 'scoped-token'});
        try {
          const run = await client.attach(key);
          const state = await run.status();
          assert.equal(validRunState(state), true);
          assert.equal(state.status, 'succeeded');
          const reader = run.result('answer').rows();
          assert.deepEqual(await Array.fromAsync(reader),
            siteRun ? sourceIds.map(id => ({id})) :
              [{id: 1}, {id: 2}]);
          assert.equal(reader.state(), 'complete');
          let attempt = await run.result('answer')
            .deliveryAttempt(reader.attemptId);
          for (let tries = 0; tries < 100 &&
            attempt.record?.state !== 'succeeded'; tries++) {
            await new Promise(resolve => setTimeout(resolve, 10));
            attempt = await run.result('answer')
              .deliveryAttempt(reader.attemptId);
          }
          assert.equal(attempt.record?.state, 'succeeded');
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => clientServer.close(resolve));
      }
      assert.equal((await store.retireCommittedResult(key,
        storedResults.definitions[0].identity)).deleted, true);
      const privateHoldingCid = control.effectPrivateEvidenceBinding(
        admittedPreview, store.storeAuthorityCid).holdingCid;
      for (const holdingCid of [privateHoldingCid,
        firstHolding.holdingCid, secondHolding.holdingCid]) {
        assert.ok(await store.inspectPhysicalHolding(holdingCid));
      }
      assert.ok(store.status().storedBytes > 0);
      assert.equal((await store.retireCommittedPublicationMetadata(
        key, '2026-09-24T00:00:04.000Z')).deleted, true);
      for (const holdingCid of [privateHoldingCid,
        firstHolding.holdingCid, secondHolding.holdingCid]) {
        assert.equal(await store.inspectPhysicalHolding(holdingCid),
          undefined);
      }
      assert.equal(store.status().storedBytes, 0);
      published = true;
    } catch (error) {
      testFailure = error;
      throw error;
    } finally {
      ledger?.close();
      if (inputs !== undefined) {
        moon.clientProgramReleaseEffectInputs(inputs);
      }
      if (storedResults !== undefined) {
        try {
          await releaseCompletedRunPreparedPayloads(storedResults, control);
        } catch (error) {
          if (testFailure === undefined) throw error;
        }
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
    assert.equal(published, true);
  });
}

test('two Effect members hold one completed Result independently', async () => {
  await verifySharedEffectSource({splitSource: false, expectedTask: 0});
  await verifySharedEffectSource({splitSource: true, expectedTask: 4});
});

test('Effect sources retain exact physical producers across split Stages',
  async () => {
    for (const [splitEffectSource, expectedTask] of [
      ['consumer', 5], ['middle', 4], ['early', 3],
    ]) {
      const {document, environment} = await effectFixture({
        splitSource: true, splitEffectSource,
      });
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        document, 'json', environment, undefined, []);
      const prepared = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(prepared,
        `${splitEffectSource}: ${moon.clientProgramEffectPreparationIssueCode(outcome)}`);
      const evidence = publicationEvidence(
        moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared));
      const admission = moon.clientProgramAdmitEffectPublication(
        prepared, ...evidence);
      assert.ok(admission);
      const definition = checked(moon.strategyIssueRunDefinition(
        admission, 'tenant-a-scope', 'split-effect-compute', cid('c'),
        '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
        100000, 10000, 64));
      const bound = moon.clientProgramBindEffectRun(
        prepared, admission, definition);
      assert.ok(bound);
      const [registry, contract] = await Promise.all([
        readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
          import.meta.url), 'utf8'),
        readFile(new URL('../../spec/contracts/actql-aoa.json',
          import.meta.url), 'utf8'),
      ]);
      const values = JSON.stringify(
        JSON.parse(contract).execution_contracts['REL.values']);
      const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        bound, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(owned);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 1)), {code: 'MoonBitHostFailure'});
      const execution = await runCapturedInternalStrategy(
        moon.clientProgramLocalEffectHostRuntime(owned));
      try {
        assert.equal(execution.status, 'host-tasks-completed',
          execution.failure?.stack);
        const inputs = checked(moon.clientProgramPinEffectSources(owned, 1));
        try {
          const input = moon.clientProgramEffectInputAt(inputs, 0);
          assert.ok(input);
          assert.equal(moon.clientProgramEffectInputTask(input), expectedTask);
          assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
          const chunks = [];
          const limits = moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits));
          const exported = await exportPinnedEffectInput({
            moon, execution, inputs, memberIndex: 0, limits,
            onChunk: async chunk => { chunks.push(chunk); },
          });
          assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
          assert.deepEqual(exported.fields, ['id']);
          assert.throws(() => checked(moon.clientProgramPinEffectSources(
            owned, 1)), {code: 'MoonBitHostFailure'});
        } finally {
          assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
        }
      } finally {
        await execution.close();
        assert.equal(execution.cleanupPending(), false);
      }
    }
  });

test('private Plan binding uses the escaped checked Unit Result name', async () => {
  const {document, environment} = await checkedFixture();
  const renamed = JSON.parse(document);
  renamed.stages[0].results['a~/b'] = renamed.stages[0].results.rows;
  delete renamed.stages[0].results.rows;
  renamed.results.answer.from.result = 'a~/b';
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(renamed), 'json', environment);
  assert.ok(prepared);
  const body = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const binding = JSON.parse(body);
  assert.deepEqual([
    binding.target.unit_definition_cid,
    binding.target.result_name,
    binding.subject_ref,
    binding.resolved_limit_cid,
    binding.binding_cid,
  ], [
    'sha256:4339769bea313c9fbdd7e027fef68df7b4e5d966b37fcdea7fcc1973b4c08779',
    'a~/b',
    'unit:sha256:4339769bea313c9fbdd7e027fef68df7b4e5d966b37fcdea7fcc1973b4c08779#/results/a~0~1b/rows',
    'sha256:3040a95286927bb9fef09af584159fcf50a960342abea3a0149febf87f25cb09',
    'sha256:6118084ed8c2229f72262c7da84c2c50307f71f4e8e93867d1c42a0c1e08e0a6',
  ]);
  assert.equal(binding.binding_cid,
    hashWithoutSelf(binding, 'binding_cid'));
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body)));
});

test('binding set covers every checked Unit Result port', async () => {
  const {document, environment} = await checkedFixture();
  const doubled = JSON.parse(document);
  doubled.stages[0].results.second =
    structuredClone(doubled.stages[0].results.rows);
  doubled.results.second = {from: {stage: 'source', result: 'second'}};
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(doubled), 'json', environment);
  assert.ok(prepared);
  const bindings = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsBindingJson(
      prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesBindingJson(
      prepared, 0, index)),
  ]);
  const limits = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsLimitJson(prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesLimitJson(prepared, 0, index)),
  ]);
  const issued = checked(moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issued), limits);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issued),
    bindings);
  const entries = limits.map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issued),
    entries);
  const witnesses = checked(
    moon.clientProgramIssuePublicationWitnesses(prepared));
  const witnessBodies = moon.clientProgramPublicationWitnessBodies(witnesses);
  const witnessCids = moon.clientProgramPublicationWitnessCids(witnesses);
  assert.equal(witnessBodies.length, witnessCids.length);
  assert.ok(witnessBodies.length > 1);
  assert.equal(new Set(witnessCids).size, witnessCids.length);
  for (const body of witnessBodies) {
    const witness = JSON.parse(body);
    assert.ok(witnessCids.includes(witness.witness_cid));
  }
  for (const body of limits) {
    for (const candidate of JSON.parse(body).candidates) {
      assert.ok(witnessCids.includes(candidate.witness_cid));
    }
  }
  assert.deepEqual(moon.clientProgramPublicationWitnessBodies(checked(
    moon.clientProgramAdmitPublicationWitnesses(
      prepared, witnessBodies))), witnessBodies);
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.slice(1))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.toReversed())), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      entries.toReversed())));
  const manifestBody = {
    plan_facts: entries.map(entry => JSON.parse(entry)),
    version: 'actql-plan-fact-manifest/0.1',
  };
  const manifestCid = hashWithoutSelf(manifestBody,
    'plan_fact_manifest_cid');
  const manifest = JSON.stringify({...manifestBody,
    plan_fact_manifest_cid: manifestCid});
  const encodedManifest = checked(
    moon.clientProgramEncodePlanFactManifestIdentity(
      JSON.stringify(manifestBody.plan_facts)));
  assert.equal(moon.clientProgramPlanFactManifestCid(encodedManifest),
    manifestCid);
  assert.deepEqual(JSON.parse(moon.clientProgramPlanFactManifestWire(
    encodedManifest)), JSON.parse(manifest));
  assert.equal(checked(moon.clientProgramCheckPlanFactManifestIdentity(
    manifest, JSON.stringify(manifestBody.plan_facts))), manifestCid);
  assert.throws(() => checked(
    moon.clientProgramCheckPlanFactManifestIdentity(manifest,
      JSON.stringify(manifestBody.plan_facts.slice(1)))),
  {code: 'MoonBitHostFailure'});
  assert.equal(new Set(bindings.map(body => JSON.parse(body).binding_cid))
    .size, 4);
  assert.equal(new Set(limits.map(body => JSON.parse(body).resolved_limit_cid))
    .size, 4);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared,
      bindings.toReversed())));
  const admitFacts = (limitBodies, bindingBodies) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(
      prepared, limitBodies, bindingBodies));
  assert.doesNotThrow(() => admitFacts(
    limits.toReversed(), bindings.toReversed()));
  for (const omitted of [0, 1, 2, 3]) {
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationFactEntries(prepared,
        entries.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits.filter((_, index) => index !== omitted), bindings),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits, bindings.filter((_, index) => index !== omitted)),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationBindingSet(prepared,
        bindings.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
  }
});

// Test-only evidence isolates checked Program binding. Product admission must
// derive every other evidence CID from its real compiler and Host authority.
function publicationEvidence(program, parameters, semantics,
  checkEnvironmentCid, aoaLogicalCid = cid('9')) {
  const limits = [100000, 10000, 64];
  const evidence = (name, body) => checked(moon.strategyRunEvidenceSeal(
    name, JSON.stringify(body), ...limits));
  const template = evidence('bound_invocation_template', {
    version: 'actql-bound-invocation-template/0.1',
    program_definition_cid: program,
    parameter_values_cid: parameters,
    invocation_bindings_cid: cid('3'),
    check_environment_cid: checkEnvironmentCid,
    grammar_manifest_cid: cid('5'),
    required_profile_contracts: [],
    barrier_contract_manifest_cid: cid('6'),
    source_evidence: 'unbound',
  });
  const plan = checked(moon.strategyPublicationSeal('compiled_plan',
    JSON.stringify({
      version: 'actql-compiled-plan/0.1',
      compiler_version: 'compiler-test-0.1',
      aoa_ir_version: 'aoa-ir-test-0.1',
      executable_plan_cid: cid('7'),
      program_definition_cid: program,
      program_semantics_cid: semantics,
      aoa_contract_cid: cid('8'),
      aoa_logical_cid: aoaLogicalCid,
    }), ...limits));
  const prepared = evidence('prepared_invocation', {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: moon.strategyRunEvidenceIdentity(template),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(plan),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  });
  const authorization = evidence('run_authorization', {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: moon.strategyRunEvidenceIdentity(prepared),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    decision: 'allowed',
  });
  return [template, prepared, authorization, plan];
}

function admittedLocalEffectEvidenceContext(control, prepared, evidence,
  definition, invocation, observation) {
  const [template, preparedEvidence, authorization] = evidence
    .slice(0, 3).map((value, index) => control.admitRunEvidence(
      ['bound_invocation_template', 'prepared_invocation',
        'run_authorization'][index],
      moon.strategyRunEvidenceJson(value), publicationLimits));
  const plan = control.admit('compiled_plan',
    moon.strategyPublicationContractJson(evidence[3]), publicationLimits);
  return Object.freeze({
    admission: control.admitCheckedClientEffectRunPublication(
      prepared, template, preparedEvidence, authorization, plan),
    runDefinition: control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), publicationLimits),
    runInvocation: control.admit('run_invocation',
      moon.strategyPublicationContractJson(invocation), publicationLimits),
    observation: control.admitRunEvidence('observation_set',
      moon.strategyRunEvidenceJson(observation), publicationLimits),
  });
}

// This fixture provides missing compiler/Host policy evidence. Its checked
// Program identity and the physical Result bytes come from product owners.
function checkedValuesPublicationPlan(prepared, control) {
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'published-values-request', cid('b'));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  const evidence = publicationEvidence(
    moon.clientRequestProgramCid(request),
    moon.clientRequestParametersCid(request),
    moon.clientProgramSemanticsCid(prepared),
    moon.clientProgramCheckEnvironmentCid(prepared),
    moon.clientProgramLocalValuesAoACid(aoa));
  const [template, preparedEvidence, authorization] = evidence
    .slice(0, 3).map((value, index) => control.admitRunEvidence(
      ['bound_invocation_template', 'prepared_invocation',
        'run_authorization'][index],
      moon.strategyRunEvidenceJson(value), publicationLimits));
  const compiledPlan = control.admit('compiled_plan',
    moon.strategyPublicationContractJson(evidence[3]), publicationLimits);
  const admission = control.admitCheckedClientRunPublication(
    prepared, template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'tenant-a-scope', runId: 'checked-values-published',
    inputArtifactSetCid: cid('c'),
    createdAt: '2026-09-24T00:00:00.000Z',
    validUntil: '2027-01-01T00:00:00.000Z',
  }, publicationLimits);
  const effectiveDataPolicyCid = cid('d');
  const observation = control.sealRunEvidence('observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [], captured_input_artifact_cids: [],
      consistency: 'no_external_sources', capture_started_at: null,
      capture_completed_at: null,
      replayability: {materialized: false, availability_evidence_cids: []},
      data_policy_cid: effectiveDataPolicyCid,
    }), publicationLimits);
  const invocation = control.issueRunInvocation(
    template, observation, publicationLimits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('e'),
    effective_data_policy_cid: effectiveDataPolicyCid,
    available_until: '2026-09-24T01:00:00.000Z',
    delete_by: '2026-09-24T02:00:00.000Z',
    extension_ceiling_at: '2026-09-24T03:00:00.000Z',
    metadata_retention_policy_cid: cid('f'),
    metadata_delete_by: '2026-09-24T04:00:00.000Z',
    clock_contract_cid: cid('0'),
  }), publicationLimits);
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: [],
    }), publicationLimits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: moon.clientRequestProgramCid(request),
      annotations: [],
    }), publicationLimits);
  return Object.freeze({
    admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze([Object.freeze({
      retention,
      evidenceContext: Object.freeze({
        computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid,
        authorityScopeCid: cid('a'),
      }),
    })]),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      publicationPolicyCid: cid('4'), publicationTargetCid: cid('5'),
      requestedAt: '2026-09-24T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId: 'published-values-attempt', fenceCid: cid('6'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-24T00:00:01.000Z',
    }),
    outputLimits, contractLimits: publicationLimits,
    now: () => '2026-09-24T00:02:00.000Z',
  });
}

test('Node ABI derives the checked named Result and request identity', async () => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  assert.ok(prepared);
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
  assert.equal(moon.clientProgramResultName(prepared, 1), undefined);
  assert.equal(moon.clientProgramCheckEnvironmentCid(prepared), evidenceCid);
  const steps = checked(moon.clientProgramLocalAoASteps(prepared, 0));
  assert.deepEqual(JSON.parse(steps), [{
    id: 'values_0', in: [], op: 'REL.values',
    params: {rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}}},
  }]);
  const pipeline = checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 0));
  assert.equal(pipeline, JSON.stringify({
    output: 'values_0', sources: {}, steps: JSON.parse(steps),
    version: 'aoa-pipeline/0.1',
  }));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesAoAWire(aoa), pipeline);
  assert.equal(moon.clientProgramLocalValuesAoACid(aoa),
    'sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723');
  const unitSource = checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 0));
  assert.deepEqual(JSON.parse(unitSource), {
    id: 'source', inputs: {},
    results: {rows: {fields: ['id'], from: 'selected'}},
    steps: [{as: 'selected', values: {
      rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}},
    }}],
    version: 'actql/0.1',
  });
  const outputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesOutputSchemaWire(outputSchema),
    '{"id":{"nullable":false,"type":"number"}}');
  assert.equal(moon.clientProgramLocalValuesOutputSchemaCid(outputSchema),
    'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513');
  const fragment = checked(moon.clientProgramIssueLocalValuesFragment(
    prepared, 0));
  const fragmentWire = moon.clientProgramLocalValuesFragmentWire(fragment);
  assert.equal(moon.clientProgramLocalValuesFragmentOutputContractCid(fragment),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.deepEqual(JSON.parse(fragmentWire), {
    input_contracts: {}, kind: 'aoa_fragment',
    logical_cid: moon.clientProgramLocalValuesAoACid(aoa),
    node_id: 'values_0',
    output_contracts: {values_0:
      moon.clientProgramLocalValuesFragmentOutputContractCid(fragment)},
    pipeline: JSON.parse(pipeline),
  });
  assert.equal(moon.clientProgramLocalValuesFragmentWire(checked(
    moon.clientProgramAdmitLocalValuesFragment(prepared, 0, fragmentWire))),
  fragmentWire);
  const resultRow = checked(moon.clientProgramIssueResultRowContract(
    prepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractName(resultRow), 'rows');
  assert.equal(moon.clientProgramResultRowContractWire(resultRow),
    '{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"}');
  assert.equal(moon.clientProgramResultRowContractCid(resultRow),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.match(moon.clientProgramResultRowContractUnitCid(resultRow),
    /^sha256:[0-9a-f]{64}$/u);
  const resultPlan = checked(moon.clientProgramIssueResultPlan(prepared, 0));
  const resultPlanWire = moon.clientProgramResultPlanWire(resultPlan);
  assert.equal(moon.clientProgramResultPlanName(resultPlan), 'answer');
  assert.equal(moon.clientProgramResultPlanCid(resultPlan),
    'sha256:db7320fcd0090a93ced0c41a6936103a1d2ab02f87beb95d8c99733c95713d53');
  assert.equal(moon.clientProgramResultPlanCid(resultPlan),
    canonicalHashWithoutSelf(JSON.parse(resultPlanWire),
      'result_plan_logical_cid'));
  assert.equal(moon.clientProgramResultPlanRowContractCid(resultPlan),
    moon.clientProgramResultRowContractCid(resultRow));
  assert.deepEqual(JSON.parse(resultPlanWire), {
    version: 'actql-result-plan/0.1', result_name: 'answer',
    unit_definition_cid:
      'sha256:a95a846eda354702da7771206feebfae30ba6814682de74b416ad35c1b467a7b',
    unit_result_name: 'rows', unit_result_ordinal: 0,
    projection: [{input: 'id', output: 'id', value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    order: {strategy: 'inherited', terms: []},
    typed_output_port: {carrier: 'relation', name: 'rows',
      row_contract_cid: moon.clientProgramResultRowContractCid(resultRow)},
    result_plan_logical_cid: moon.clientProgramResultPlanCid(resultPlan),
  });
  assert.equal(moon.clientProgramResultPlanWire(checked(
    moon.clientProgramAdmitResultPlan(prepared, 0, resultPlanWire))),
  resultPlanWire);
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    prepared, 0, resultPlanWire.replace('"result_name":"answer"',
      '"result_name":"foreign"'))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueResultPlan(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const directRoot = checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 0));
  const directRootWire = moon.clientProgramDirectValuesResultRootWire(directRoot);
  assert.deepEqual(JSON.parse(directRootWire), {
    name: 'answer', ref: {node_id: 'values_0', port: 'values_0'},
    role: 'requested_result',
  });
  assert.equal(moon.clientProgramDirectValuesResultRootPlanCid(directRoot),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.equal(moon.clientProgramDirectValuesResultRootRowContractCid(directRoot),
    moon.clientProgramLocalValuesFragmentOutputContractCid(fragment));
  assert.equal(moon.clientProgramDirectValuesResultRootWire(checked(
    moon.clientProgramAdmitDirectValuesResultRoot(
      prepared, 0, directRootWire))), directRootWire);
  assert.throws(() => checked(moon.clientProgramAdmitDirectValuesResultRoot(
    prepared, 0, directRootWire.replace('"answer"', '"foreign"'))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 1)), {code: 'MoonBitHostFailure'});
  const wider = JSON.parse(document);
  const wideValues = wider.stages[0].steps[0].values;
  wideValues.schema.hidden = {nullable: false, type: 'string'};
  wideValues.rows[0].hidden = 'a';
  wideValues.rows[1].hidden = 'b';
  const widePrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(wider), 'json', environment);
  assert.ok(widePrepared);
  const wideResultPlan = checked(
    moon.clientProgramIssueResultPlan(widePrepared, 0));
  assert.notEqual(moon.clientProgramResultPlanCid(wideResultPlan),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    widePrepared, 0, resultPlanWire)), {code: 'MoonBitHostFailure'});
  const wideOutputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesOutputSchemaCid(
    wideOutputSchema), moon.clientProgramLocalValuesOutputSchemaCid(outputSchema));
  const projectedRow = checked(moon.clientProgramIssueResultRowContract(
    widePrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(projectedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const wideFragment = checked(moon.clientProgramIssueLocalValuesFragment(
    widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesFragmentOutputContractCid(
    wideFragment), moon.clientProgramResultRowContractCid(projectedRow));
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    widePrepared, 0)), {code: 'MoonBitHostFailure'});
  assert.deepEqual(JSON.parse(
    moon.clientProgramLocalValuesFragmentOutputContractWire(wideFragment)), {
    additional_properties: false,
    fields: {hidden: {nullable: false, type: 'string'},
      id: {nullable: false, type: 'number'}},
    nullable: false, type: 'object',
  });
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    widePrepared, 0, fragmentWire)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    prepared, 0, JSON.stringify({...JSON.parse(fragmentWire),
    unrecognized: true}))), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline, moon.clientProgramLocalValuesAoACid(aoa))));
  assert.throws(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline.replace('"id":2', '"id":3'),
      moon.clientProgramLocalValuesAoACid(aoa))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesFragment(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueResultRowContract(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramLocalAoASteps(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const semanticDocument = checked(
    moon.clientProgramSemanticDocumentJson(prepared));
  assert.deepEqual(JSON.parse(semanticDocument), JSON.parse(document));
  const annotated = JSON.parse(document);
  annotated.meta = {note: 'root'};
  annotated.stages[0].meta = {note: 'stage'};
  annotated.stages[0].steps[0].meta = {note: 'step'};
  const annotatedPrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(annotated), 'json', environment);
  assert.ok(annotatedPrepared);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(annotatedPrepared)),
  semanticDocument);
  assert.equal(checked(
    moon.clientProgramLocalValuesUnitSourceJson(annotatedPrepared, 0)),
  unitSource);
  const annotatedRow = checked(moon.clientProgramIssueResultRowContract(
    annotatedPrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(annotatedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const semanticsCid = moon.clientProgramSemanticsCid(prepared);
  assert.match(semanticsCid, /^sha256:[a-f0-9]{64}$/u);
  const definition = checked(moon.clientProgramDefinitionJson(prepared));
  assert.deepEqual(JSON.parse(definition), {
    id: 'client-values', program_semantics_cid: semanticsCid,
    version: 'actql-program-definition/0.1',
  });
  assert.equal(`sha256:${createHash('sha256').update(definition)
    .digest('hex')}`, programCid);
  const semantics = checked(moon.clientProgramSemanticsJson(prepared));
  assert.equal(`sha256:${createHash('sha256').update(semantics)
    .digest('hex')}`, semanticsCid);
  const stageSemantics = checked(
    moon.clientProgramStageSemanticsJson(prepared, 0));
  assert.equal(`sha256:${createHash('sha256').update(stageSemantics)
    .digest('hex')}`,
  JSON.parse(semantics).program_template.stages[0].stage_semantics_cid);
  assert.throws(() => checked(
    moon.clientProgramStageSemanticsJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  const rowsLimitBody = checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 0));
  const bytesLimitBody = checked(
    moon.clientProgramPublicationBytesLimitJson(prepared, 0, 0));
  const rowsLimit = JSON.parse(rowsLimitBody);
  const bytesLimit = JSON.parse(bytesLimitBody);
  const unit =
    'unit:sha256:a95a846eda354702da7771206feebfae30ba6814682de74b416ad35c1b467a7b';
  assert.deepEqual([rowsLimit.subject_ref, bytesLimit.subject_ref],
    [`${unit}#/results/rows/rows`, `${unit}#/results/rows/bytes`]);
  assert.deepEqual([rowsLimit.unit, rowsLimit.effective_max,
    bytesLimit.unit, bytesLimit.effective_max],
  ['rows', 2, 'bytes', 1000]);
  assert.deepEqual(rowsLimit.candidates.map(candidate => candidate.role),
    ['host_ceiling', 'proven_upper_bound']);
  for (const limit of [rowsLimit, bytesLimit]) {
    assert.equal(limit.version, 'actql-resolved-limit/0.1');
    assert.equal(limit.resolved_limit_cid,
      hashWithoutSelf(limit, 'resolved_limit_cid'));
    for (const witness of limit.candidates) {
      assert.equal(witness.witness_cid,
        hashWithoutSelf(witness, 'witness_cid'));
    }
  }
  const rowsBindingBody = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const bytesBindingBody = checked(
    moon.clientProgramPublicationBytesBindingJson(prepared, 0, 0));
  const issuedFacts = checked(
    moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issuedFacts),
    [rowsLimitBody, bytesLimitBody]);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issuedFacts),
    [rowsBindingBody, bytesBindingBody]);
  const factEntries = [rowsLimitBody, bytesLimitBody].map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issuedFacts),
    factEntries);
  assert.throws(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      [factEntries[0], factEntries[0]])),
  {code: 'MoonBitHostFailure'});
  const rowsBinding = JSON.parse(rowsBindingBody);
  const bytesBinding = JSON.parse(bytesBindingBody);
  assert.deepEqual([
    rowsLimit.resolved_limit_cid, bytesLimit.resolved_limit_cid,
    rowsBinding.binding_cid, bytesBinding.binding_cid,
  ], [
    'sha256:f8efdbb9bd20c92235643e7b52af77442a4c3a62e01211db4254962aa01bdf43',
    'sha256:69c039d271fd3d3390e9abb0b03acfe18af34e23f5049e1d8f029dca3ce98937',
    'sha256:53799d3278a54895ef07fc1af6206f6f29831387f0e0e917defb4b45476ed753',
    'sha256:aa953d36dc697199be6819028aab771e12d229c7c085d2ec828581067d90baa0',
  ]);
  for (const [binding, limit, measure] of [
    [rowsBinding, rowsLimit, 'rows'],
    [bytesBinding, bytesLimit, 'bytes'],
  ]) {
    assert.deepEqual(binding, {
      binding_cid: binding.binding_cid,
      effective_max: limit.effective_max,
      resolved_limit_cid: limit.resolved_limit_cid,
      subject_ref: `${unit}#/results/rows/${measure}`,
      target: {
        kind: 'result_publication', measure, result_name: 'rows',
        unit_definition_cid: unit.slice('unit:'.length),
      },
      unit: measure,
      version: 'actql-execution-limit-binding/0.1',
    });
    assert.equal(binding.binding_cid, hashWithoutSelf(binding, 'binding_cid'));
    assert.notEqual(binding.binding_cid, hashWithoutSelf({
      ...binding, target: {...binding.target, result_name: 'answer'},
    }, 'binding_cid'));
  }
  const admitRows = body => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body));
  const admitBytes = body => checked(
    moon.clientProgramAdmitPublicationBytesBinding(prepared, 0, 0, body));
  const admitSet = bodies => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared, bodies));
  const admitFacts = (limits, bindings) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(prepared, limits, bindings));
  assert.doesNotThrow(() => admitRows(rowsBindingBody));
  assert.doesNotThrow(() => admitBytes(bytesBindingBody));
  assert.doesNotThrow(() => admitSet([bytesBindingBody, rowsBindingBody]));
  assert.doesNotThrow(() => admitFacts(
    [bytesLimitBody, rowsLimitBody],
    [bytesBindingBody, rowsBindingBody]));
  for (const invalid of [
    [rowsLimitBody],
    [rowsLimitBody, rowsLimitBody],
    [rowsLimitBody, '{}'],
    [rowsLimitBody, JSON.stringify({...bytesLimit,
      effective_max: bytesLimit.effective_max + 1})],
  ]) assert.throws(() => admitFacts(invalid,
    [rowsBindingBody, bytesBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => admitFacts(
    [rowsLimitBody, bytesLimitBody], [rowsBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitSet([JSON.stringify({
    version: rowsBinding.version, target: rowsBinding.target,
    unit: rowsBinding.unit, subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  }), bytesBindingBody]));
  for (const invalid of [
    [rowsBindingBody],
    [rowsBindingBody, rowsBindingBody],
    [rowsBindingBody, JSON.stringify({...bytesBinding,
      binding_cid: cid('f')})],
    [bytesBindingBody, '{}'],
  ]) assert.throws(() => admitSet(invalid),
    {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitRows(JSON.stringify({
    version: rowsBinding.version,
    target: rowsBinding.target,
    unit: rowsBinding.unit,
    subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  })));
  const wrongPort = {
    ...rowsBinding,
    target: {...rowsBinding.target, result_name: 'answer'},
  };
  wrongPort.binding_cid = hashWithoutSelf(wrongPort, 'binding_cid');
  for (const invalid of [
    JSON.stringify(wrongPort),
    JSON.stringify({...rowsBinding, target: {
      ...rowsBinding.target, unit_definition_cid: cid('f'),
    }}),
    JSON.stringify({...rowsBinding, resolved_limit_cid: cid('f')}),
    JSON.stringify({...rowsBinding, binding_cid: cid('f')}),
    JSON.stringify({...rowsBinding, unknown: true}),
    rowsBindingBody.replace('"unit":"rows","version"',
      '"unit":"rows","unit":"rows","version"'),
  ]) assert.throws(() => admitRows(invalid), {code: 'MoonBitHostFailure'});
  assert.throws(() => admitBytes(rowsBindingBody),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  assert.ok(request);
  assert.equal(moon.clientRequestProgramCid(request), programCid);
  assert.equal(moon.clientRequestParametersCid(request), parametersCid);
  assert.equal(moon.clientRequestScopeCid(request),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3');
  assert.equal(moon.clientRequestIntentCid(request),
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const yaml = await readFile(new URL('values.yaml', fixture), 'utf8');
  const yamlPrepared = moon.clientProgramPrepareEffectFree(
    yaml, 'yaml', environment);
  assert.ok(yamlPrepared);
  assert.equal(moon.clientRequestProgramCid(
    moon.clientProgramRequestIdentity(
      yamlPrepared, cid('a'), 'saved-request', cid('b'))),
  programCid);
  assert.equal(moon.clientProgramSemanticsCid(yamlPrepared), semanticsCid);
  assert.equal(checked(moon.clientProgramDefinitionJson(yamlPrepared)),
    definition);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(yamlPrepared)), semanticDocument);
  assert.equal(checked(moon.clientProgramSemanticsJson(yamlPrepared)),
    semantics);
  assert.equal(checked(moon.clientProgramStageSemanticsJson(yamlPrepared, 0)),
    stageSemantics);
  assert.equal(checked(
    moon.clientProgramPublicationRowsLimitJson(yamlPrepared, 0, 0)),
  rowsLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesLimitJson(yamlPrepared, 0, 0)),
  bytesLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationRowsBindingJson(yamlPrepared, 0, 0)),
  rowsBindingBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesBindingJson(yamlPrepared, 0, 0)),
  bytesBindingBody);
  assert.equal(checked(moon.clientProgramLocalAoASteps(yamlPrepared, 0)), steps);
  assert.equal(checked(
    moon.clientProgramLocalValuesPipelineJson(yamlPrepared, 0)), pipeline);
  assert.equal(moon.clientProgramPrepareEffectFree(document, 'auto', environment),
    undefined);
  assert.equal(moon.clientProgramPrepareEffectFree(
    document.replace('actql/0.1', 'actql/9.9'), 'json', environment),
  undefined);
  assert.equal(moon.clientProgramCheckEnvironment(
    '{}', evidenceCid, false, false, true, false, false, false, false),
  undefined);
});

test('Node ABI binds separately supplied Parameters through the shared checker',
  async t => {
    const {environment} = await checkedFixture();
    const [json, yaml] = await Promise.all([
      readFile(new URL('parameter-values.json', fixture), 'utf8'),
      readFile(new URL('parameter-values.yaml', fixture), 'utf8'),
    ]);
    const prepare = (document, format, parameters) =>
      moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, environment, parameters);
    const issue = outcome => moon.clientProgramPreparationIssueCode(outcome);
    const ready = outcome => moon.clientProgramPreparationReady(outcome);
    assert.equal(issue(prepare(json, 'json', undefined)), 'needs_inputs');
    assert.equal(issue(prepare(json, 'json', '{"n":"bad"}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":null}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":2')),
      'supplied_syntax');
    assert.equal(issue(prepare(json, 'json', `{"n":"${'x'.repeat(65536)}"}`)),
      'supplied_too_large');
    assert.equal(issue(prepare(json, 'auto', '{"n":2}')),
      'invalid_format');
    const supplied = ready(prepare(json, 'json', '{"n":2}'));
    const repeated = ready(prepare(json, 'json', '{"n":2}'));
    const yamlSupplied = ready(prepare(yaml, 'yaml', '{"n":2}'));
    const changed = ready(prepare(json, 'json', '{"n":3}'));
    for (const value of [supplied, repeated, yamlSupplied, changed]) {
      assert.ok(value);
      assert.equal(moon.clientProgramResultName(value, 0), 'answer');
    }
    const identity = value => moon.clientProgramRequestIdentity(
      value, cid('a'), 'parameter-request', cid('b'));
    const first = identity(supplied);
    const same = identity(repeated);
    const yamlIdentity = identity(yamlSupplied);
    const other = identity(changed);
    assert.equal(moon.clientRequestProgramCid(first),
      moon.clientRequestProgramCid(yamlIdentity));
    assert.equal(moon.clientProgramSemanticsCid(supplied),
      moon.clientProgramSemanticsCid(yamlSupplied));
    assert.equal(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(yamlIdentity));
    assert.equal(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(same));
    assert.notEqual(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(other));
    assert.notEqual(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(other));
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'parameters-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const admission = {tenantId: 'tenant-a', runDefinitionCid: cid('c'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    assert.equal(journal.accept(first, admission, moon).inserted, true);
    assert.equal(journal.accept(same, admission, moon).inserted, false);
    assert.throws(() => journal.accept(other, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    const withDefault = json.replace('"n": {"type": "number"}',
      '"n": {"type": "number", "default": 5}');
    assert.notEqual(withDefault, json);
    assert.ok(ready(prepare(withDefault, 'json', undefined)));
  });

test('public submit rejects checker failures before Run admission', async () => {
  const {environment} = await checkedFixture();
  const document = await readFile(new URL('parameter-values.json', fixture),
    'utf8');
  const prepareSubmit = installNodeClientProgramPreparation({
    moon, environment});
  let admissions = 0;
  let admittedIdentity;
  const server = createServer(createClientHttpHandler({
    authenticate: header => header === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: () => true,
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'principal-a', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 100, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 2048},
    }),
    prepareSubmit,
    maxRequestBytes: 100000,
    submit: ({preparedProgram, requestId}) => {
      admissions++;
      admittedIdentity = moon.clientProgramRequestIdentity(preparedProgram,
        cid('a'), requestId, cid('b'));
      return {ref: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
        runDefinitionCid: cid('c')}, durability: 'volatile', revision: 0};
    },
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const origin = `http://127.0.0.1:${server.address().port}/`;
    const submit = parameters => fetch(new URL('actql/client/0.1/submit',
      origin), {
      method: 'POST', headers: {authorization: 'Bearer scoped-token',
        'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'local', owner: 'local',
        runners: [], consentRefs: []}, requestId: 'saved-parameter-id',
      kind: 'aql', input: {text: document, format: 'json'}, parameters}),
    });
    for (const [parameters, status, code] of [
      [null, 422, 'ClientProgramNeedsInputs'],
      [{n: null}, 422, 'ClientProgramRejected'],
      [{n: 'bad'}, 422, 'ClientProgramRejected'],
      [{n: 2, extra: true}, 422, 'ClientProgramRejected'],
      [{n: 'x'.repeat(65536)}, 413, 'ClientParametersTooLarge'],
    ]) {
      const response = await submit(parameters);
      assert.equal(response.status, status);
      assert.deepEqual(await response.json(), {code});
    }
    assert.equal(admissions, 0);
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: origin, token: 'scoped-token'});
    try {
      await assert.rejects(client.aql(document, {format: 'json',
        requestId: 'sdk-invalid-parameter', parameters: {n: null}}),
      {code: 'ClientProgramRejected'});
      assert.equal(admissions, 0);
    } finally {
      client.close();
    }
    const prepared = prepareSubmit({kind: 'aql',
      input: {text: document, format: 'json'}, parameters: {n: 2}});
    assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
    const objectPrepared = prepareSubmit({kind: 'program',
      input: JSON.parse(document), parameters: {n: 2}});
    assert.equal(moon.clientProgramSemanticsCid(objectPrepared),
      moon.clientProgramSemanticsCid(prepared));
    const accepted = await submit({n: 2});
    assert.equal(accepted.status, 200);
    assert.equal(admissions, 1);
    assert.equal(moon.clientRequestParametersCid(admittedIdentity),
      moon.clientRequestParametersCid(moon.clientProgramRequestIdentity(
        prepared, cid('a'), 'saved-parameter-id', cid('b'))));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('Node publication admission rejects evidence from another checked Program',
  async t => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'saved-request', cid('b'));
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared),
      moon.clientProgramCheckEnvironmentCid(prepared));
    assert.ok(moon.clientProgramAdmitPublication(prepared, ...evidence));
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), limits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]), limits);
    const admitted = control.admitCheckedClientRunPublication(
      prepared, ...bound, plan);
    assert.equal(admitted.kind, 'run-publication-admission');
    const definition = control.issueRunDefinition(admitted, {
      scopeId: 'tenant-a-scope',
      runId: 'checked-values-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, limits);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    const accepted = journal.acceptDefinition(identity, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    journal.close(); // Lose the acceptance reply before using the Run ref.
    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const retained = restarted.resolveDefinition(identity,
      {tenantId: 'tenant-a'}, moon, control);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const changed = moon.clientProgramPrepareEffectFree(
      document.replace('"id": 2', '"id": 3'), 'json', environment);
    assert.ok(changed);
    assert.equal(moon.clientProgramAdmitPublication(changed, ...evidence),
      undefined);
    assert.throws(() => control.admitCheckedClientRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Program/u);
    const changedRequest = moon.clientProgramRequestIdentity(
      changed, cid('a'), 'saved-request', cid('b'));
    assert.throws(() => restarted.resolveDefinition(changedRequest,
      {tenantId: 'tenant-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => restarted.acceptDefinition(changedRequest, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control), {code: 'ClientRequestIntentConflict'});
    const foreignSemantics = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity), cid('f'), evidenceCid);
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignSemantics), undefined);
    const foreignEnvironment = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared), cid('f'));
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignEnvironment), undefined);
  });

test('durable request deduplication uses checked Program identity', async t => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  await mkdir(scratch, {recursive: true});
  const path = await mkdtemp(join(scratch.pathname, 'case-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const admission = {
    tenantId: 'tenant-a',
    runDefinitionCid: cid('d'),
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  };
  assert.equal(journal.accept(request, admission, moon).inserted, true);
  assert.equal(journal.accept(request, {...admission,
    runDefinitionCid: cid('e')}, moon).inserted, false);
  const changed = moon.clientProgramPrepareEffectFree(
    document.replace('"id": 2', '"id": 3'), 'json', environment);
  assert.ok(changed);
  const changedRequest = moon.clientProgramRequestIdentity(
    changed, cid('a'), 'saved-request', cid('b'));
  assert.equal(moon.clientRequestRelation(request, changedRequest), 2);
  assert.throws(() => journal.accept(changedRequest, {...admission,
    runDefinitionCid: cid('e')}, moon),
  {code: 'ClientRequestIntentConflict'});
  assert.equal(journal.lookup({tenantId: 'tenant-a',
    authorityScopeCid: cid('a'), requestId: 'saved-request'}, moon)
    .ref.runDefinitionCid, cid('d'));
});

test('checked source-free Program executes through the standard Local Host',
  async () => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, -1n, 0n, 0n, 0n), undefined);
    const setup = moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const execution = await runCapturedStrategy(setup);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.deepEqual(execution.resultInventory.map(result => result.name),
        ['answer']);
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].task, 0);
      assert.equal(execution.completed[0].outputRows, 2);
      assert.throws(() => execution.effectPhysicalSource(0),
        {code: 'InvalidEffectPhysicalSource'});
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('public Values submit computes and reads its real Local Result',
  async t => {
    const {document, environment} = await checkedFixture();
    const expected = JSON.parse(await readFile(new URL('values.expected.json',
      fixture), 'utf8'));
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const control = runtimeCore(moon).publicationControl;
    let plan;
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    };
    const journalDirectory = join(directory, 'requests');
    await mkdir(journalDirectory);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'published-values-request', cid('b'));
    let store = await openLocalPublicationStore(configuration, control);
    let published;
    try {
      const journal = openClientRequestJournal(journalDirectory);
      let issues = 0;
      let computes = 0;
      const submitServer = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-before-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local',
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-before-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        prepareSubmit: installNodeClientProgramPreparation({
          moon, environment}),
        submit: async ({preparedProgram, requestId}) => {
          const requested = moon.clientProgramRequestIdentity(
            preparedProgram, cid('a'), requestId, cid('b'));
          const accepted = await journal.admitOrLookupDefinition(requested, {
            tenantId: 'tenant-a',
            lookupExpiresAt: '2099-01-01T00:00:00.000Z',
            issueDefinition: () => {
              issues++;
              plan = checkedValuesPublicationPlan(preparedProgram, control);
              return plan.runDefinition;
            },
          }, moon, control);
          if (accepted.inserted) {
            const setup = moon.clientProgramOpenSourceFreeLocalHost(
              preparedProgram, registry, values, 1n, 0n, 0n, 0n);
            assert.ok(setup);
            computes++;
            published = await runPublishedCapturedStrategy(setup,
              {store, plan});
          }
          return {ref: accepted.ref, durability: accepted.durability,
            revision: accepted.revision};
        },
      }));
      await new Promise(resolve => submitServer.listen(0, '127.0.0.1',
        resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${submitServer.address().port}/`,
          token: 'scoped-token', durability: 'durable',
        });
        try {
          const submitted = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.equal(submitted.profile.durability, 'durable');
          assert.equal(submitted.ref.runDefinitionCid,
            plan.runDefinition.identity);
          const repeated = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.deepEqual(repeated.ref, submitted.ref);
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => submitServer.close(resolve));
        journal.close();
      }
      assert.equal(issues, 1);
      assert.equal(computes, 1);
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.deepEqual(published.execution.resultInventory.map(
        result => result.name), ['answer']);
      assert.equal(published.execution.completed[0].outputRows,
        expected.length);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close();
      assert.equal(published.cleanupPending(), false);
      assert.equal(await published.cleanup(), true);
      published = undefined;
      await store.close();
      store = await openLocalPublicationStore(configuration, control);
      const reopened = openClientRequestJournal(journalDirectory);
      let ref;
      try {
        const retained = await reopened.admitOrLookupDefinition(identity, {
          tenantId: 'tenant-a',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z',
          issueDefinition: () => {
            throw new Error('Duplicate request reissued Run authority');
          },
        }, moon, control);
        assert.equal(retained.inserted, false);
        assert.equal(retained.runDefinition.wire, plan.runDefinition.wire);
        ref = retained.ref;
      } finally {
        reopened.close();
      }
      const authority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: facts => ({
          authorizationContextCid: `sha256:${createHash('sha256')
            .update(facts.attemptId).digest('hex')}`,
          dataCeilingCid: cid('9'),
          egressAdmissionCid: cid('a'),
          expiresAt: '2026-09-24T01:00:00.000Z',
          maxBytes: 100000, maxUses: 1,
        }),
        authorizeResultRead: () => true,
        authorizeDeliveryAttemptLookup: () => true,
      });
      const service = installNodeResultAccessService({
        store, control, authority,
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      const stateService = installRunStateService({
        store, control,
        authority: installRunStateAuthority({
          authorizeRunState: () => true,
          resultPolicyAvailable: () => true,
        }),
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
      });
      const server = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-after-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local' &&
          (facts.ref === undefined || facts.ref.tenantId === 'tenant-a'),
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-after-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        attach: async ({ref: requested, principalId}) => {
          await inspectAuthorizedRunState(stateService, {
            indexKey: requested, principalId, purpose: 'inspect',
          });
          return {ref: requested, durability: 'durable', revision: 0};
        },
        stateService, resultService: service,
      }));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${server.address().port}/`,
          token: 'scoped-token',
        });
        const execution = await client.attach(ref);
        assert.equal(execution.profile.durability, 'durable');
        const state = await execution.status();
        assert.equal(validRunState(state), true);
        assert.equal(state.status, 'succeeded');
        assert.deepEqual(await execution.result('answer').all(), expected);
        const reader = execution.result('answer').rows();
        assert.deepEqual(await Array.fromAsync(reader), expected);
        assert.equal(reader.state(), 'complete');
        let attempt = await execution.result('answer')
          .deliveryAttempt(reader.attemptId);
        assert.equal(attempt.kind, 'found');
        for (let tries = 0; tries < 100 &&
          attempt.record?.state !== 'succeeded'; tries++) {
          await new Promise(resolve => setTimeout(resolve, 10));
          attempt = await execution.result('answer')
            .deliveryAttempt(reader.attemptId);
        }
        assert.equal(attempt.record.state, 'succeeded');
        client.close();
      } finally {
        await new Promise(resolve => server.close(resolve));
      }
    } finally {
      await published?.close();
      await store.close();
    }
  });
