import {withFixtureConnector} from '../../../host-common/connector-manifest.fixture.mjs';
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
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {installNodeClientEffectRun} from '../../../host-node/client-effect-run.mjs';
import {openClientRequestJournal} from '../../../host-node/client-request-journal.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import {applyCapturedEffectSet, applyRecoveredEffectSet} from
  '../../../host-node/effect-run-apply.mjs';
import {accountConfiguration, accountEntry, FIXTURE_CONTEXT,
  fixtureAuthorization} from
  '../../../host-node/authorization-fixture.mjs';
import {createLocalAuthorizationGate} from
  '../../../host-node/local-account-config.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from
  '../../../host-node/sqlite-checkpoint-journal.mjs';
import {captureSalesforceCollectionEffectWrite,
  captureSalesforceSingleEffectWrite,
  recoverPreparedSalesforceSingleRequests,
  recoverCapturedSalesforceSingleRequests} from
  '../host/salesforce-effect-write.mjs';
import {authorObservedSalesforceEffectPreview} from
  '../host/salesforce-effect-preview.mjs';
import {installSalesforceEffectCurrentUse} from
  '../host/salesforce-effect-current-use.mjs';
import {installSalesforceEffectDispatch} from
  '../host/salesforce-effect-dispatch.mjs';
import {installSalesforceEffectRoute} from
  '../host/salesforce-effect-route.mjs';
import {issueSalesforceEffectCapability, inspectSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';
import {installSalesforceAuthorization} from
  '../host/installed-salesforce-site.mjs';
import {fixtureWrites, openSalesforceEffectSiteFixture,
  salesforceSiteAccountConfiguration} from
  './salesforce-effect-site.fixture.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site/salesforce-catalog-recovery.mjs';
import {observeSalesforceTargetSet} from
  '../site/salesforce-target-observation.mjs';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {issueAuthorizedEffectSetReceipt} from
  '../../../host-node/effect-response-recovery.mjs';
import {exportPinnedEffectInput, preparePinnedEffectSourceHoldings,
  preparePinnedEffectSourceSet} from '../../../host-node/effect-input-export.mjs';
import {verifyPinnedEffectPlan} from '../../../host-node/effect-plan-verify.mjs';
import {createClientHttpHandler} from '../../../host-node/client-http.mjs';
import {installNodeClientEffectProgramPreparation,
  installNodeClientProgramPreparation} from
  '../../../host-node/client-program-preparation.mjs';
import {completeCapturedEffectRun, runCapturedEffectComputation,
  runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from '../../../host-node/entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from '../../../host-node/result-access.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from
  '../../../host-common/publication-contract-control.fixture.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {sourceFreeEffectPublicationPlan} from
  '../../../host-node/local-values-plan.mjs';
import {issueCompletedEffectfulComputationEvidence,
  prepareCompletedEffectfulPublication,
  publishCompletedEffectfulRun,
  recoverCompletedEffectfulComputation,
  releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation,
  storeCompletedRunResultSet} from
  '../../../host-common/completed-run-publication.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority,
  installRunStateService} from '../../../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../../../store-local/publication-store.mjs';
import {connect as connectClient} from '../../../../packages/sdk/index.mjs';
import {validRunState} from '../../../../packages/client-wire/index.mjs';

const fixture = new URL('../../../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../../../_build/client-program-bridge-tests/', import.meta.url);
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
const canonicalHash = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
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
  continueMembers = [], generated, labels} = {}) {
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
  if (generated === undefined) {
    mapping.connector_manifest_cid = withFixtureConnector(environmentDocument,
      mapping.target_ref);
    mapping.mapping_contract_cid = canonicalHashWithoutSelf(mapping,
      'mapping_contract_cid');
  } else {
    // A Site-generated execution Mapping with its declaration's Catalog and
    // manifest entry; no hand-written Mapping.
    Object.assign(mapping, JSON.parse(generated.body));
    for (const key of Object.keys(mapping)) {
      if (!(key in JSON.parse(generated.body))) delete mapping[key];
    }
    const byBody = texts => texts.map(text => JSON.parse(text)).sort(
      (a, b) => canonicalHash(a) < canonicalHash(b) ? -1 : 1);
    environmentDocument.connector_catalogs = [
      JSON.parse(generated.declared.catalog)];
    environmentDocument.source_views = byBody(
      generated.declared.source_views);
    environmentDocument.contract_registry = byBody(
      generated.declared.contracts);
    environmentDocument.connector_manifest = {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(generated.declared.manifest_entry)]};
  }
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
  environmentDocument.evidence_bundle_cid = canonicalHashWithoutSelf(
    environmentDocument, 'evidence_bundle_cid');
  const environment = moon.clientProgramCheckEnvironment(
    canonicalJson(environmentDocument),
    environmentDocument.evidence_bundle_cid,
    false, false, true, splitSource, false, false, false,
  );
  assert.ok(environment);
  const document = JSON.parse(documentBody);
  if (sourceIds) {
    document.stages[0].steps[0].values.schema.id.type = 'string';
    document.stages[0].steps[0].values.rows = sourceIds.map(id => ({id}));
  }
  if (labels) {
    // A nullable label beside each id: some rows carry null.
    document.stages[0].steps[0].values.schema.label = {type: 'string',
      nullable: true};
    document.stages[0].steps[0].values.rows = sourceIds.map((id, index) =>
      ({id, label: labels[index]}));
    document.stages[0].results.rows.fields = ['id', 'label'];
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
    environmentWire: canonicalJson(environmentDocument),
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
    templateOnly = false, createChanges} = {}) {
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
        intended_changes: {state: 'present', value: createChanges?.[index] ??
          (writeKind === 'create'
            ? {Name: value, External_Key__c: value} : {Name: value})},
        before: writeKind === 'create' ? {state: 'absent'}
          : {state: 'present', value: {Name: typeof value === 'string'
            ? 'before' : 0}},
        after: {state: 'present', value: createChanges?.[index] ??
          (writeKind === 'create'
            ? {Name: value, External_Key__c: value} : {Name: value})},
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

// One create request of the fixture Site, projected from `observation`.
function capabilityRequest(site, observation = site.catalog.observation) {
  const binding = JSON.parse(
    salesforceMoon.salesforceCatalogObservationJson(observation)).binding;
  const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
    observation, binding.tenant, binding.principal, binding.environment,
    binding.connection_revision, binding.org_id, binding.site_key,
    binding.site_generation, binding.connector_registration,
    binding.connector_revision, binding.resource_origin,
    binding.run_invocation_cid, binding.dispatch_request_cid,
    binding.sync_occurrence,
    'Test_Record__c', 0, '', ['Name', 'External_Key__c'], 2));
  const body = checked(salesforceMoon.salesforcePrepareWriteBody(projection,
    Buffer.from('{"Name":"value","External_Key__c":"value"}'), 1024, 32, 5));
  return checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
    body, 'v62.0', 0, '', 0, 256, 128, 1024));
}

async function capabilitySite(t) {
  const site = await openSalesforceEffectSiteFixture(t, {
    commonMoon: moon, salesforceMoon, runInvocationCid: cid('b'),
    dispatchRequestCid: cid('c'), writeOperation: 'create',
  });
  const request = capabilityRequest(site);
  const options = {moon: salesforceMoon, requests: [request],
    currentObservation: site.catalog.observation,
    authorization: site.write, credential: site.credential,
    mapping: site.executionMapping(fixtureWrites.create).mapping,
    maxRows: 2, maxBytes: 20000};
  return {site, request, options};
}

test('Salesforce capability requires the exact execution Mapping before any use',
  async t => {
    const {site, options} = await capabilitySite(t);
    const other = await openSalesforceEffectSiteFixture(t, {
      commonMoon: moon, salesforceMoon, runInvocationCid: cid('b'),
      dispatchRequestCid: cid('c'), writeOperation: 'create',
      orgId: '00D000000000002EAA'});
    // A later declaration that no longer allows creating Name cannot even
    // prepare this write's Mapping.
    site.setNameCreateable(false);
    const narrowed = await site.refreshDeclaration();
    site.setNameCreateable(true);
    assert.equal(narrowed.writables[0].create_fields.includes('Name'), false);
    assert.throws(() => site.executionMapping(fixtureWrites.create,
      narrowed.declaration), {code: 'MoonBitHostFailure'});
    // The schema changes under the same Site binding: a request projected
    // from the new describe no longer matches what was declared.
    site.setNameUpdateable(false);
    const changed = await site.refreshCatalog();
    const drifted = capabilityRequest(site, changed.observation);
    site.setNameUpdateable(true);
    const uses = site.journal.recover().length;
    const sent = site.seen.length;
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: undefined}), {code: 'InvalidSalesforceEffectCapability'});
    // Same connection id and schema, another org: a foreign Mapping.
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: other.executionMapping(fixtureWrites.create).mapping}),
    {code: 'MoonBitHostFailure'});
    // Another write's Mapping: an update of Name is not this create.
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: site.executionMapping(fixtureWrites.update).mapping}),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      requests: [drifted], currentObservation: changed.observation}),
    {code: 'MoonBitHostFailure'});
    // Refused before any credential use or request.
    assert.equal(site.journal.recover().length, uses);
    assert.equal(site.seen.length, sent);
    assert.ok(issueSalesforceEffectCapability(options).identity);
  });

test('Salesforce capability requires current signed authority without a use',
  async t => {
    const {site, request, options} = await capabilitySite(t);
    const uses = site.journal.recover().length;
    const sent = site.seen.length;
    const capability = issueSalesforceEffectCapability(options);
    assert.equal(inspectSalesforceEffectCapability(capability, [request]).route, 0);
    assert.equal(JSON.parse(capability.wire).binding.runtime_bundle_cid, cid('a'));
    assert.throws(() => inspectSalesforceEffectCapability({...capability},
      [request]), {code: 'InvalidSalesforceEffectCapability'});
    assert.throws(() => inspectSalesforceEffectCapability(capability,
      [request], {collection: true}), {code: 'InvalidSalesforceEffectCapability'});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      credential: {...site.credential, now: () => 2_000_000_000_000}}));
    for (const changed of [{tenant: 'foreign'}, {siteGeneration: 5},
      {runtimeBundleCid: cid('f')}]) {
      assert.throws(() => issueSalesforceEffectCapability({...options,
        authorization: {...site.write, scope: {...site.write.scope, ...changed}}}));
    }
    const unsigned = site.credential.control.prepare({...site.write.scope,
      dispatchRequestCid: cid('f')});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      authorization: {...site.write, grant: unsigned}}),
    {code: 'RemoteCredentialGrantMissing'});
    assert.equal(site.journal.recover().length, uses);
    assert.equal(site.seen.length, sent);
    const refreshed = await site.refreshCatalog();
    assert.equal(issueSalesforceEffectCapability({...options,
      currentObservation: refreshed.observation}).identity, capability.identity);
    site.setNameUpdateable(false);
    const changed = await site.refreshCatalog();
    assert.throws(() => inspectSalesforceEffectCapability(capability, [request],
      {currentObservation: changed.observation}));
    const beforeRevoke = site.journal.recover().length;
    site.journal.revoke(site.credential.control.identity(site.write.grant));
    assert.throws(() => inspectSalesforceEffectCapability(capability, [request]));
    assert.equal(site.journal.recover().length, beforeRevoke);
  });

test('Salesforce current-use catalogs belong to one exact refresh',
  async t => {
    const {site, request, options} = await capabilitySite(t);
    const requests = [request];
    const capability = issueSalesforceEffectCapability(options);
    const firstCatalog = site.catalog;
    const secondCatalog = await site.refreshCatalog();
    let revision = 0;
    let firstRefreshStarted;
    let finishFirstRefresh;
    const started = new Promise(resolve => { firstRefreshStarted = resolve; });
    const firstGate = new Promise(resolve => { finishFirstRefresh = resolve; });
    const currentUse = installSalesforceEffectCurrentUse({
      moon: salesforceMoon, commonMoon: moon,
      members: [{requests, capability, refreshCatalog: async () => {
        const current = ++revision;
        if (current === 1) {
          firstRefreshStarted();
          await firstGate;
        }
        return current === 1 ? firstCatalog : secondCatalog;
      }}],
      observedRows: [], maxMembers: 1, maxRows: 1,
      maxTotalResponseBytes: 1024,
    });
    requests[0] = 'foreign';
    assert.throws(() => currentUse.catalogAt({}, 0),
      {code: 'InvalidSalesforceEffectCurrentUse'});
    const firstFlight = currentUse.refreshPreflight({preflight: {marker: 1}});
    await started;
    const second = await currentUse.refreshPreflight({preflight: {marker: 2}});
    finishFirstRefresh();
    const first = await firstFlight;
    assert.equal(currentUse.catalogAt(first, 0), firstCatalog.observation);
    assert.equal(currentUse.catalogAt(second, 0), secondCatalog.observation);
    assert.deepEqual(first.capabilities, [capability.identity]);
    assert.deepEqual(second.capabilities, [capability.identity]);
    assert.throws(() => currentUse.catalogAt({...first}, 0),
      {code: 'InvalidSalesforceEffectCurrentUse'});
  });

test('Salesforce dispatcher rejects a foreign frontier claim before I/O',
  async () => {
    let catalogReads = 0;
    const scope = {}, locator = {}, key = {}, basis = {};
    const claim = {scope, locator, key, basis,
      intentFingerprintCid: cid('1'), canonicalRequestCid: cid('2')};
    const dispatch = installSalesforceEffectDispatch({
      commonMoon: {strategyEffectPreviewOrderedRowCid() {
        assert.fail('foreign claim reached the Preview');
      }}, moon: {}, ledger: {}, admittedPreview: {},
      currentUse: {catalogAt() { catalogReads++; return {}; }},
      members: [{requests: [{}], claims: [claim],
        authorizationForRow() {
          assert.fail('foreign claim requested a grant');
        }, credential: {}, limits: {}}],
    });
    await assert.rejects(dispatch({memberIndex: 0, rowIndex: 0,
      claim: {...claim, key: {}}, currentPreflight: {}}),
    {code: 'InvalidSalesforceEffectDispatch'});
    assert.equal(catalogReads, 0);
  });

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
  const commitGate = (entries, options) => createLocalAuthorizationGate({
    accountConfiguration: accountConfiguration([
      ...entries,
      accountEntry('scenario-target-read', 'allow', {operation: 'read'}),
    ]),
    context: FIXTURE_CONTEXT,
    ...options,
  });
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
  'salesforce-create-duplicates', 'salesforce-create-omit',
  'salesforce-publication-restart',
  'salesforce-overlap', 'salesforce-stale-target',
  'salesforce-schema-drift',
  'salesforce-unknown', 'salesforce-lost-http-reply',
  'salesforce-rate-limit',
  'salesforce-create-lost-http-reply',
  'salesforce-collection-partial', 'salesforce-collection-recovered',
  'salesforce-preapply-restart',
  'salesforce-prepared-intent-restart',
  'salesforce-client-reply-lost',
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
    physical === 'salesforce-client-reply-lost' ||
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
    const loseClientReply = physical === 'salesforce-client-reply-lost';
    const rateLimitWrite = physical === 'salesforce-rate-limit';
    const unknownAfterClaim = physical.startsWith('salesforce-unknown') ||
      loseHttpReply || loseClientReply;
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
    // A Named Result with a null and a present label, written through a
    // Site-generated Mapping that omits the null.
    const omitNull = physical === 'salesforce-create-omit';
    const labels = omitNull ? [null, 'two'] : undefined;
    const generated = omitNull ? await (async () => {
      const site = await openSalesforceEffectSiteFixture(t, {
        commonMoon: moon, salesforceMoon, runInvocationCid: cid('b'),
        dispatchRequestCid: cid('c'), optionalText: true,
        connectorId: 'salesforce'});
      const mapping = site.executionMapping(fixtureWrites.createOmit);
      return {body: mapping.body, ref: mapping.mappingRef,
        cid: mapping.mappingCid, declared: site.declared};
    })() : undefined;
    const mappingRef = generated?.ref ?? (siteRun
      ? 'mapping:salesforce.test-record.v1' : 'mapping:crm.account.v1');
    const {document, environment, mappingCid} = await effectFixture({
      writeKind, memberIds, target, mappingRef, sourceIds,
      continueMembers, generated, labels,
    });
    if (generated) assert.equal(mappingCid, generated.cid);
    const expectedCreate = sourceIds?.map((id, index) => ({
      Name: id, External_Key__c: id,
      ...(labels?.[index] == null ? {} : {Optional_Text__c: labels[index]}),
    }));
    const prepareProgram = installNodeClientEffectProgramPreparation({
      moon, environment,
    });
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-two-published-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let control = runtimeCore(moon).publicationControl;
    const requestJournalRoot = join(directory, 'client-requests');
    const requestJournal = openClientRequestJournal(requestJournalRoot);
    let physicalStarts = 0;
    let publishedRunDefinitionCid;
    // The owner-issued reconciliation state of an unknown Run, and the
    // provider writes observed when it was recorded.
    let reconciled;
    let observedWrites;
    const executeEffectRun = async ({owner: bound, prepared,
      compilation: effectCompilation, allowed, definition,
      identity: clientRequest, ref: clientRef}) => {
    physicalStarts++;
    if (physical === 'simulated') {
      const noRecompile = {...moon,
        clientProgramCompileLocalEffects() {
          assert.fail('publication plan compiled the Effect Program again');
        },
        clientProgramPrepareEffectComputationWithParameters() {
          assert.fail('publication plan prepared the Effect Program again');
        }};
      const installedPlan = sourceFreeEffectPublicationPlan({
        moon: noRecompile, control, prepared,
        compilation: effectCompilation, allowed, definition,
        authorityScopeCid: cid('a'), tenantId: 'tenant-a',
        storeAuthorityCid: cid('7'),
        now: () => '2026-09-24T00:00:00.000Z',
      });
      assert.equal(installedPlan.runDefinition.identity,
        moon.strategyPublicationContractIdentity(definition));
      assert.equal(installedPlan.results.length,
        moon.clientProgramEffectCompilationResultNames(effectCompilation)
          .length);
      assert.ok(Date.parse(JSON.parse(installedPlan.results[0].retention.wire)
        .available_until) >= Date.parse(JSON.parse(
        installedPlan.runDefinition.wire).valid_until));
      assert.equal(installedPlan.localEvidenceContext.runDefinition,
        installedPlan.runDefinition);
    }
    const semanticInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    assert.equal(JSON.parse(moon.clientProgramLocalEffectInvocationJson(
      semanticInvocation)).self_cid,
      moon.clientProgramLocalEffectInvocationCid(semanticInvocation));
    const evidence = [
      checked(moon.strategyRunEvidenceAdmit('bound_invocation_template',
        moon.clientProgramEffectCompilationTemplateWire(effectCompilation),
        1000000, 100000, 100)),
      moon.clientProgramAllowedEffectRunPrepared(allowed),
      moon.clientProgramAllowedEffectRunAuthorization(allowed),
      checked(moon.strategyPublicationAdmit('compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(effectCompilation),
        1000000, 100000, 100)),
    ];
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    assert.ok(admission);
    const sourceFree = checked(moon.clientProgramIssueEffectSourceFreeInvocation(
      effectCompilation, cid('d'), 100000, 10000, 64));
    const observation = sourceFree._0;
    const invocation = sourceFree._1;
    assert.equal(JSON.parse(moon.strategyRunEvidenceJson(observation))
      .invocation_template_cid,
    moon.strategyRunEvidenceIdentity(evidence[0]));
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    const execution = await runCapturedEffectComputation(owned);
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
    let holdingCommitCalls = 0;
    let onHoldingCommit;
    let store = Object.freeze({...physicalStore,
      async commitPhysicalHolding(...args) {
        holdingCommitCalls++;
        await onHoldingCommit?.();
        return physicalStore.commitPhysicalHolding(...args);
      },
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
      const sourceSet = await preparePinnedEffectSourceSet({
        moon, checkedOwner: prepared, execution, inputs,
        maxMembers: memberIds.length, maxGroupingWork: 4,
        limits: moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits)),
        store, maxBytes: outputLimits.maxWireBytes, control,
        invocation: runInvocation, retention,
        sourceBindingCid: cid('c'),
        contractLimits: publicationLimits,
        localEvidenceContext,
        ...(siteRun ? {
          proposalLimits: {maxFields: 10, maxWork: 100,
            maxBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxUtf16Units: 20000},
          onProposalRow(memberIndex, rowIndex, proposal) {
            assert.equal(rowIndex, proposedRows[memberIndex].length);
            proposedRows[memberIndex].push(proposal);
          },
        } : {}),
      });
      assert.equal(sourceSet.payloads.length, 1);
      assert.equal(sourceSet.members.length, memberIds.length);
      sourcePayload = sourceSet.payloads[0];
      for (const member of sourceSet.members) {
        assert.equal(member.payload, sourcePayload);
      }
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
          writeKind === 'create' ? expectedCreate
            : sourceIds.map(Name => ({Name})));
        }
      }
      const effect = runtimeCore(moon).effectApplicationControl;
      // One Host account gate for both installed Sites; it also decides the
      // Effect commit below.
      const siteAuthorization = siteRun
        ? await installSalesforceAuthorization({
          accountConfiguration: salesforceSiteAccountConfiguration([
            '00D000000000001EAA', '00D000000000002EAA']),
          principalId: 'principal-a', root: directory})
        : undefined;
      const sites = siteRun ? await Promise.all(memberIds.map((_, index) =>
        openSalesforceEffectSiteFixture(t, {
          authorization: siteAuthorization,
          commonMoon: moon, salesforceMoon,
          runInvocationCid: runInvocation.identity,
          dispatchRequestCid: cid('c'),
          orgId: index === 0 || overlappingMembers ? '00D000000000001EAA'
            : '00D000000000002EAA',
          loseWriteReplyOnce: loseHttpReply && index === 0,
          rateLimitWriteOnce: rateLimitWrite && index === 0,
          collectionPartial: collectionPartial && index === 0,
          writeOperation: writeKind,
          optionalText: omitNull,
          connectorId: omitNull ? 'salesforce' : 'crm-main',
        }))) : undefined;
      // The write each member's Site executes, and its execution Mapping.
      const siteWrite = omitNull ? fixtureWrites.createOmit
        : fixtureWrites[writeKind];
      const siteMappings = sites?.map(site =>
        site.executionMapping(siteWrite));
      if (omitNull) {
        for (const mapping of siteMappings) {
          assert.equal(mapping.mappingCid, generated.cid);
        }
      }
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
          omitNull ? ['External_Key__c', 'Name', 'Optional_Text__c'] :
          writeKind === 'create' ? ['Name', 'External_Key__c'] :
            ['Name'], 3));
      };
      const siteProjections = sites?.map(site => prepareSiteProjection(site));
      if (siteRun && writeKind !== 'create') {
        sites.forEach((site, index) =>
          site.setTargetName(`observed-before-${index}`));
      }
      const siteBodies = siteRun ? memberIds.map((_, memberIndex) =>
        sourceIds.map((value, rowIndex) => checked(
          salesforceMoon.salesforcePrepareExecutionWriteBody(
          siteMappings[memberIndex].mapping,
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
      const currentCatalogs = sites?.map(site => site.catalog.observation);
      const productCapabilities = sites?.map((site, index) =>
        issueSalesforceEffectCapability({moon: salesforceMoon,
          requests: siteRequests[index],
          currentObservation: currentCatalogs[index],
          authorization: site.write, credential: site.credential,
          mapping: siteMappings[index].mapping,
          collection: collectionMode && index === 0,
          maxRows: 4, maxBytes: 20000}));
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
      const requestScope = moon.clientProgramEffectRequestScope(
        prepared, clientRequest);
      assert.ok(requestScope);
      assert.equal(effect.logicalRequestScopeCid(requestScope),
        moon.clientRequestScopeCid(clientRequest));
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
          templateOnly: siteRun,
          createChanges: omitNull ? expectedCreate : undefined});
      const productMembers = siteRun ? siteRequests.map((requests, index) => ({
        stageIndex: 0, effectId: memberIds[index], requests,
        observations: previewTargetObservations?.[index],
        localResultArtifact: sourcePayload.localResultArtifact,
        sourceArtifact: sourcePayload.summary.artifact,
        capability: productCapabilities[index],
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
      const holdingOwner = preparePinnedEffectSourceHoldings({
        sources: sourceSet, store, control, preview: admittedPreview,
        invocation: runInvocation,
      });
      const [firstHolding, secondHolding] = await holdingOwner.commit();
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
      const captureOptions = {
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
      };
      if (physical === 'salesforce') {
        const before = holdingCommitCalls;
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          effectSourceHoldings: [firstHolding, {...secondHolding,
            record: {...secondHolding.record, manifest_cid: cid('9')},
          }],
        }), {code: 'InvalidCompletedEffectSourceHolding'});
        assert.equal(holdingCommitCalls, before);
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions, plans: [],
        }));
        assert.equal(holdingCommitCalls, before);
        // Mutate caller containers during the first asynchronous Store sync.
        // The admitted capture and its saved wire must already be owned.
        onHoldingCommit = async () => {
          onHoldingCommit = undefined;
          await Promise.resolve();
          captureOptions.plans.length = 0;
          captureOptions.captureEvidence.pendingSourceStateAdvances
            .push({foreign: true});
          captureOptions.receiptEvidence.bindings.push({foreign: true});
          captureOptions.connectorRecovery.length = 0;
        };
      }
      let computation = await issueCompletedEffectfulComputationEvidence(
        captureOptions);
      if (physical === 'salesforce') {
        assert.equal(onHoldingCommit, undefined);
        assert.equal(captureOptions.plans.length, 0);
      }
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
        const suspended = {execution, store, storedResults, control,
          computation, preview: admittedPreview};
        await assert.rejects(suspendCompletedEffectfulComputation({
          ...suspended, computation: {...computation}}),
        {code: 'InvalidCompletedEffectfulRunOwner'});
        assert.equal(await suspendCompletedEffectfulComputation(suspended),
          true);
        assert.equal(await suspendCompletedEffectfulComputation(suspended),
          false);
        assert.throws(() => releaseCompletedRunPreparedPayloads(
          storedResults, control),
        {code: 'CompletedRunResultSetReleaseModeConflict'});
        assert.equal(JSON.stringify(await store.inspectPhysicalHolding(
          control.effectComputationCaptureHoldingCid(
            runDefinition, store.storeAuthorityCid))), before);
        if (sourcePayload.prepared.status().pending) {
          await sourcePayload.prepared.release();
        }
        await store.close();
        const child = spawnSync(process.execPath, [fileURLToPath(new URL(
          '../../../host-node/fixtures/recover-effect-capture.mjs', import.meta.url,
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
      const routes = body.effects.map((member, index) => checked(
        moon.clientProgramEffectApplyCapabilityFromCodes(
          member.capability_evidence_cid,
          collectionMode && index === 0 ? 1 : 0, 0, 0, true,
          !(collectionMode && index === 0), 2, 1)));
      const sent = [];
      const preflight = {
        proofs: plans.map(plan => plan.proof),
        sources: [cid('c'), cid('c')],
        contracts: [mappingCid, mappingCid],
        capabilities: body.effects.map(member => member.capability_evidence_cid),
        authorities: [cid('e'), cid('e')],
        observedRows, guardVersions: writeKind === 'create' ? [] :
          previewGuardVersions?.flat() ?? observedRows.map(() => cid('6')),
        // D2.multi-allow: an account allow commits the two-member set
        // after whole-set preflight without a fabricated risk claim.
        routes,
        risk: undefined,
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
          gate: siteRun ? siteAuthorization : await fixtureAuthorization([
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
      const productRouteCases = [
        'salesforce', 'salesforce-upsert', 'salesforce-create',
        'salesforce-create-duplicates', 'salesforce-publication-restart',
        'salesforce-preapply-restart', 'salesforce-prepared-intent-restart',
        'salesforce-collection-partial',
        'salesforce-terminal-store-restart',
        'salesforce-terminal-process-publication',
      ];
      const useProductRoute = productRouteCases.includes(physical);
      const routeMembers = siteRun ? sites.map((site, index) => ({
        requests: siteRequests[index],
        capability: productCapabilities[index],
        refreshCatalog: site.refreshCatalog,
        target: writeKind === 'create' ? undefined : {
          authorizationForRow: async () => ({...site.observe,
            useId: `target-read-${targetRead++}`}),
          credential: site.credential,
          limits: {maxResponseBytes: 1024, maxNodes: 32,
            maxDepth: 5, maxIdentityBytes: 1024},
        },
        authorizationForRow: rowIndex => ({...site.write,
          useId: `write-${index}-${rowIndex}`}),
        credential: site.credential,
        limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
          maxNodes: 32, maxDepth: 5},
        collection: collectionMode && index === 0 ? {
          request: collectionRequest,
          authorization: () => ({...site.write,
            useId: 'partial-collection'}),
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 64, maxDepth: 6, maxRows: 2},
        } : undefined,
      })) : undefined;
      const makeProductRoute = () => installSalesforceEffectRoute({
        commonMoon: moon, moon: salesforceMoon, ledger,
        admittedPreview: applyPreview, observedRows, members: routeMembers,
        maxMembers: 2, maxRows: 4, maxTotalResponseBytes: 4096,
      });
      let productRoute = useProductRoute ? makeProductRoute() : undefined;
      if (physical === 'salesforce') {
        const before = sites.map(site => site.seen.length);
        assert.throws(() => productRoute.bindDispatch({members,
          subjectCid: cid('9')}), {code: 'InvalidSalesforceEffectRoute'});
        assert.deepEqual(sites.map(site => site.seen.length), before);
      }
      const currentUse = siteRun && !productRoute
        ? installSalesforceEffectCurrentUse({
          moon: salesforceMoon, commonMoon: moon, observedRows,
          members: routeMembers.map(member => ({
            requests: member.requests, capability: member.capability,
            collectionRequest: member.collection?.request,
            refreshCatalog: member.refreshCatalog, target: member.target,
          })), maxMembers: 2, maxRows: 4,
          maxTotalResponseBytes: 4096,
        }) : undefined;
      if (productRoute || currentUse) {
        applyOptions.refreshPreflight = (productRoute ?? currentUse)
          .refreshPreflight;
      }
      if (physical === 'salesforce') {
        const foreignAuthored = checked(
          moon.clientProgramAuthorEffectPreview(
            previewDraft.wire, body.run_identity_cid,
            previewDraft.authoringCid, requestScope,
            20000, 1000, 20, 2, 4, 128, 8, 3));
        const foreignReceiptPreview = effect.admitPreviewIdentity(
          foreignAuthored._0, body.run_identity_cid,
          previewDraft.authoringCid, requestScope, foreignAuthored._1,
          20000, 1000, 20);
        assert.notEqual(moon.strategyEffectPreviewSemanticCid(
          foreignReceiptPreview), body.effect_preview_cid);
        const writesBefore = sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length;
        await assert.rejects(completeCapturedEffectRun({
          apply: {...applyOptions, ledger,
            dispatchRow: () => assert.fail('foreign Set sent a row')},
          receipt: {ledger, preview: foreignReceiptPreview,
            commonMoon: moon, publicationPreview: admittedPreview,
            authorizeEvidenceRead: async () => true,
            members: members.map(member => ({
              rowOwners: member.claims.map(claim => ({claim})),
              replayed: false,
            }))},
          publication: {ledger, preview: admittedPreview, control},
        }), {code: 'InvalidCapturedEffectRunCompletion'});
        const foreignInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, foreignAuthored._0,
            previewDraft.authoringCid,
            moon.clientProgramEffectPreviewInputLimits(
              20000, 1000, 20, 1000, 100, 20000, 1000, 20,
              2, 4, 100, 100)));
        await assert.rejects(completeCapturedEffectRun({
          apply: {...applyOptions, ledger, capturedInputs: foreignInputs,
            dispatchRow: () => assert.fail('foreign apply sent a row')},
          receipt: {ledger, preview: applyPreview,
            commonMoon: moon, publicationPreview: admittedPreview,
            authorizeEvidenceRead: async () => true,
            members: members.map(member => ({
              rowOwners: member.claims.map(claim => ({claim})),
              replayed: false,
            }))},
          publication: {ledger, preview: admittedPreview, control},
        }), {code: 'InvalidCapturedEffectRunCompletion'});
        assert.equal(sites.flatMap(site => site.seen)
          .filter(item => item.method === 'PATCH').length, writesBefore);
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
            ledgerRoot, requestJournalRoot, authorityScopeCid: cid('e'),
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
                writes: sites.map(() => fixtureWrites[writeKind]),
              } : {}),
            },
          };
        if (processPreparedIntent) {
          const beforeDenied = sites.map(site => site.seen.length);
          const deniedRecovery = await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs',
            {...childInput, denyEvidence: true});
          assert.notEqual(deniedRecovery.status, 0);
          assert.match(deniedRecovery.stderr, /EffectEvidenceAccessDenied/);
          assert.deepEqual(sites.map(site => site.seen.length), beforeDenied);
          const foreignRequest = await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs',
            {...childInput, callerRequestId: 'another-business-request'});
          assert.notEqual(foreignRequest.status, 0);
          assert.deepEqual(sites.map(site => site.seen.filter(
            item => item.method === 'PATCH' || item.method === 'POST').length),
          [0, 0]);
          const foreignSite = structuredClone(childInput);
          foreignSite.salesforceRecovery.sites[0].authorityPublicKey =
            sites[1].recoveryConnection.authorityPublicKey;
          const rejected = await runChildWithLiveSite(
            './fixtures/recover-effect-outcomes.mjs',
            foreignSite);
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
        if (productRoute) {
          productRoute = makeProductRoute();
          applyOptions.refreshPreflight = productRoute.refreshPreflight;
        }
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
          refreshPreflight: async ({signal}) =>
            applyOptions.refreshPreflight({signal, preflight}),
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
          // Setup sync, setup declaration and the drift recheck.
          assert.deepEqual(sites.map(site => site.seen.filter(item =>
            item.path.endsWith('/describe')).length), [3, 3]);
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
      const bindDispatch = productRoute ? ({members: activeMembers,
        subjectCid, signal}) => {
        assert.equal(subjectCid, body.effect_preview_cid);
        const dispatch = productRoute.bindDispatch({members: activeMembers,
          subjectCid, signal});
        return row => dispatchRow(row, dispatch);
      } : undefined;
      const dispatchRow = async ({memberIndex, rowIndex, claim,
        currentPreflight}, productDispatch) => {
          sent.push([memberIndex, rowIndex]);
          if (sent.length === 1) {
            for (const pending of members.flatMap(member => member.claims)) {
              assert.equal(effect.ledgerEntryStateCode(
              ledger.currentAdmitted(effect.logicalItemLocatorCid(
                  pending.locator))), 0);
            }
          }
          if (productDispatch) {
            const received = await productDispatch({memberIndex, rowIndex,
              claim, currentPreflight});
            assert.equal(received.claimed, true);
            if (collectionMode && memberIndex === 0) {
              assert.equal(received.outcomeReceipts.length, 2);
            } else {
              assert.equal(received.terminal.created, true);
            }
            return;
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
                currentObservation: currentUse.catalogAt(currentPreflight,
                  memberIndex),
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
              currentObservation: currentUse.catalogAt(currentPreflight,
                memberIndex),
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
        if (code === 'EffectfulRunNeedsReconciliation') {
          // The Host records the owner's state for the public Client.
          reconciled = runs.recordReconciliation(clientRef, {issuedSet,
            ledger, preview: admittedPreview,
            updatedAt: '2026-09-24T00:00:03.000Z'});
          observedWrites = () => sites?.map(site => site.seen.filter(item =>
            item.method !== 'GET').length) ?? [];
        }
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
              authorization: undefined, refreshPreflight: undefined,
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
        if (loseClientReply) throw new Error('LostEffectExecutionReply');
        return;
      }
      const dispatchOptions = bindDispatch === undefined ? {dispatchRow} :
        {bindDispatch};
      const applied = restartPreparedIntent
        ? await applyRecoveredEffectSet({
          ...recoveredApplyOptions,
          ...(processPreparedIntent ? {dispatchRow: () =>
            assert.fail('fresh-process write resent')} : dispatchOptions),
          ...(processPreparedIntent ? {refreshPreflight: () =>
            assert.fail('settled process replay refreshed Site')} : {}),
        })
        : await applyCapturedEffectSet({
          ...applyOptions, ledger, ...dispatchOptions,
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
            ledgerRoot, requestJournalRoot, authorityScopeCid: cid('e'),
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
        JSON.stringify(siteRun ? sourceIds.map((id, index) =>
          labels ? {id, label: labels[index]} : {id})
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
            siteRun ? sourceIds.map((id, index) =>
              labels ? {id, label: labels[index]} : {id}) :
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
      if (omitNull) {
        // The provider received each row as its Mapping wrote it: the null
        // label omitted, the present one written.
        for (const site of sites) {
          assert.deepEqual(site.seen.filter(item => item.method === 'POST')
            .map(item => JSON.parse(item.body)), expectedCreate);
        }
      }
      publishedRunDefinitionCid = definition.identity;
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
    return published;
    };
    // One installation of the public Host over a request journal. A later
    // installation over the reopened journal plays a fresh Host process.
    const installPublicHost = journal => {
      const installed = installNodeClientEffectRun({
        moon, publicationControl: control, journal,
        authorizeRequest: async ({principalId, connection}) =>
          principalId === 'principal-before-restart' &&
          connection.mode === 'local' && connection.owner === 'local'
            ? {executionContextCid: cid('a'), hostPolicyCid: cid('b'),
              createdAt: '2026-09-24T00:00:00.000Z',
              expiresAt: '2027-01-01T00:00:00.000Z'} : undefined,
        authorizeRunStart: async ({principalId, connection}) =>
          principalId === 'principal-before-restart' &&
          connection.mode === 'local' && connection.owner === 'local',
        execute: executeEffectRun,
      });
      // Status and reconcile of an unpublished Run answer only from the
      // recorded owner state; they never start, send or relabel anything.
      const recorded = async ({ref}) => {
        const state = installed.reconciliation(ref);
        if (state === undefined) {
          throw Object.assign(new Error('ResultUnavailable'),
            {code: 'ResultUnavailable'});
        }
        return state;
      };
      const server = createServer(createClientHttpHandler({
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
        prepareSubmit: prepareProgram,
        submit: async ({preparedProgram, requestId, principalId,
          connection}) => {
          const accepted = await installed.accept({
            prepared: preparedProgram, authorityScopeCid: cid('e'),
            requestId, tenantId: 'tenant-a', principalId, connection,
            lookupExpiresAt: '2027-01-01T00:00:00.000Z',
          });
          const started = await installed.start(accepted);
          assert.ok(started.kind === 'started' ||
            started.kind === 'reconcile');
          return {ref: accepted.ref, durability: accepted.durability,
            revision: accepted.revision};
        },
        observeRun: recorded, reconcile: recorded,
      }));
      return {installed, server};
    };
    const serve = async server => {
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      return await connectClient({mode: 'local', owner: 'local',
        endpoint: `http://127.0.0.1:${server.address().port}/`,
        token: 'scoped-token', durability: 'durable'});
    };
    const {installed: runs, server: clientServer} =
      installPublicHost(requestJournal);
    let reconcileRef;
    try {
      const client = await serve(clientServer);
      try {
        let run;
        if (loseClientReply) {
          await assert.rejects(client.aql(document, {format: 'json',
            requestId: 'complete-two-effects-request'}),
          {code: 'SubmissionUnknown'});
        } else {
          run = await client.aql(document, {format: 'json',
            requestId: 'complete-two-effects-request'});
        }
        run ??= await client.aql(document, {format: 'json',
          requestId: 'complete-two-effects-request'});
        assert.equal(run.ref.tenantId, 'tenant-a');
        if (publishedRunDefinitionCid !== undefined) {
          assert.equal(run.ref.runDefinitionCid, publishedRunDefinitionCid);
        }
        const replay = await client.aql(document, {format: 'json',
          requestId: 'complete-two-effects-request'});
        assert.deepEqual(replay.ref, run.ref);
        assert.equal(physicalStarts, 1);
        if (reconciled !== undefined) {
          // An unknown Effect outcome is reported, never success or failure,
          // and neither status nor reconcile sends a write.
          const writes = observedWrites();
          const state = await run.status();
          assert.equal(state.status, 'needs_reconciliation');
          assert.equal(state.result_available, false);
          assert.deepEqual(state.next_action, reconciled.next_action);
          assert.ok(state.next_action.effects.length > 0);
          assert.deepEqual(await run.reconcile(), state);
          assert.deepEqual(observedWrites(), writes);
          reconcileRef = run.ref;
        }
      } finally { client.close(); }
    } finally {
      await new Promise(resolve => clientServer.close(resolve));
      requestJournal.close();
    }
    // Every Run that kept an unknown outcome was reported through the Client.
    assert.equal(reconcileRef !== undefined, reconciled !== undefined);
    if (unknownAfterClaim || processUnknownIntent || rateLimitWrite) {
      assert.notEqual(reconciled, undefined);
    }
    if (reconcileRef !== undefined) {
      // A fresh Host over the reopened journal answers the same state for
      // the same request without starting or sending anything.
      const writes = observedWrites();
      const reopened = openClientRequestJournal(requestJournalRoot);
      const {server} = installPublicHost(reopened);
      try {
        const client = await serve(server);
        try {
          const run = await client.aql(document, {format: 'json',
            requestId: 'complete-two-effects-request'});
          assert.deepEqual(run.ref, reconcileRef);
          const state = await run.status();
          assert.equal(state.status, 'needs_reconciliation');
          assert.deepEqual(state.next_action, reconciled.next_action);
          assert.deepEqual(await run.reconcile(), state);
          assert.equal(physicalStarts, 1);
          assert.deepEqual(observedWrites(), writes);
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => server.close(resolve));
        reopened.close();
      }
    }
  });
}

test('public Effect submit rejects an unsupported checked Program before acceptance',
  async t => {
    const unsupported = await effectFixture({splitSource: true,
      writeKind: 'create', memberIds: ['save', 'save_again'],
      sourceIds: ['001000000000001', '001000000000002']});
    const prepare = installNodeClientEffectProgramPreparation({
      moon, environment: unsupported.environment,
    });
    const prepared = prepare({kind: 'aql',
      input: {text: unsupported.document, format: 'json'},
      parameters: null});
    assert.equal(moon.clientProgramEffectCompilationIssueCode(
      moon.clientProgramCompileLocalEffects(prepared)),
    'unsupported_program');
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'unsupported-effect-submit-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const journal = openClientRequestJournal(directory);
    const runs = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({
        executionContextCid: cid('a'), hostPolicyCid: cid('b'),
        createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z',
      }),
      authorizeRunStart: async () => true,
      execute: () => assert.fail('unsupported Program started execution'),
    });
    const server = createServer(createClientHttpHandler({
      authenticate: header => header === 'Bearer scoped-token'
        ? 'principal-a' : undefined,
      authorizeConnection: () => true,
      negotiate: () => ({
        version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'principal-a',
        capabilities: ['result-jsonl'],
        limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
          maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
          maxRows: 100, maxBatchRows: 10,
          maxBatchRetainedValueBytes: 2048},
      }),
      prepareSubmit: prepare,
      submit: async ({preparedProgram, requestId, principalId,
        connection}) => {
        const accepted = await runs.accept({prepared: preparedProgram,
          authorityScopeCid: cid('e'), requestId, tenantId: 'tenant-a',
          principalId, connection,
          lookupExpiresAt: '2027-01-01T00:00:00.000Z'});
        await runs.start(accepted);
        return {ref: accepted.ref, durability: accepted.durability,
          revision: accepted.revision};
      },
    }));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const client = await connectClient({mode: 'local', owner: 'local',
        endpoint: `http://127.0.0.1:${server.address().port}/`,
        token: 'scoped-token', durability: 'durable'});
      try {
        await assert.rejects(client.aql(unsupported.document,
          {format: 'json', requestId: 'unsupported-effect-request'}),
        {code: 'ClientProgramUnsupported'});
      } finally { client.close(); }
    } finally {
      await new Promise(resolve => server.close(resolve));
      journal.close();
    }
    const database = new DatabaseSync(join(directory,
      'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(database.prepare('SELECT COUNT(*) AS n FROM client_requests')
        .get().n, 0);
    } finally { database.close(); }
  });

test('Effect publication preparation failure reserves no physical start',
  async t => {
    const fixture = await effectFixture();
    const prepare = installNodeClientEffectProgramPreparation({moon,
      environment: fixture.environment});
    const prepared = prepare({kind: 'aql', input: {text: fixture.document,
      format: 'json'}, parameters: null});
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-plan-failure-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const journal = openClientRequestJournal(directory);
    t.after(() => journal.close());
    let physicalStarts = 0;
    const runs = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z'}),
      authorizeRunStart: async () => true,
      prepareExecution() { throw new Error('PlanIssuanceFailed'); },
      execute() { physicalStarts++; },
    });
    const accepted = await runs.accept({prepared,
      authorityScopeCid: cid('e'), requestId: 'effect-plan-failure',
      tenantId: 'tenant-a', principalId: 'principal-a',
      connection: {mode: 'local', owner: 'local'},
      lookupExpiresAt: '2027-01-01T00:00:00.000Z'});
    await assert.rejects(runs.start(accepted), /PlanIssuanceFailed/);
    const retained = journal.lookupRunDefinition(accepted.ref, moon,
      runtimeCore(moon).publicationControl);
    assert.equal(retained.preDispatchFailureConfirmed, true);
    assert.equal(retained.physicalStartReserved, false);
    assert.equal(physicalStarts, 0);
    assert.equal((await runs.start(accepted)).kind, 'reconcile');
    assert.equal(physicalStarts, 0);
    const asyncRuns = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z'}),
      authorizeRunStart: async () => true,
      async prepareExecution() { throw new Error('LatePlanFailure'); },
      execute() { physicalStarts++; },
    });
    const asynchronous = await asyncRuns.accept({prepared,
      authorityScopeCid: cid('e'), requestId: 'effect-async-plan-failure',
      tenantId: 'tenant-a', principalId: 'principal-a',
      connection: {mode: 'local', owner: 'local'},
      lookupExpiresAt: '2027-01-01T00:00:00.000Z'});
    await assert.rejects(asyncRuns.start(asynchronous),
      {name: 'TypeError', message: 'AsyncClientEffectPreparation'});
    assert.equal(journal.lookupRunDefinition(asynchronous.ref, moon,
      runtimeCore(moon).publicationControl).physicalStartReserved, false);
    assert.equal(physicalStarts, 0);
  });

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


test('shared Effect Client admission and physical claim survive races and restart', async t => {
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'effect-client-owner-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const {document, environment, environmentWire} = await effectFixture({memberIds: ['save', 'save_again']});
  const prepare = text => {
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      text, 'json', environment, undefined, []);
    const value = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(value, moon.clientProgramEffectPreparationIssueCode(outcome));
    return value;
  };
  const prepared = prepare(document);
  const [registry, contract] = await Promise.all([
    readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
    readFile(new URL('../../../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'),
  ]);
  const values = JSON.stringify(JSON.parse(contract).execution_contracts['REL.values']);
  const control = runtimeCore(moon).publicationControl;
  let starts = 0;
  let failAfterCapture = false;
  let currentAuthorization = true;
  let preflightCompiles = 0;
  const countedMoon = {...moon,
    clientProgramCompileLocalEffects(...args) {
      preflightCompiles++;
      return moon.clientProgramCompileLocalEffects(...args);
    }};
  const install = (journal, runtime = moon) => installNodeClientEffectRun({moon: runtime,
    publicationControl: control, journal,
    authorizeRequest: async () => currentAuthorization ? {
      executionContextCid: cid('a'), hostPolicyCid: cid('b'),
      createdAt: '2026-09-26T00:00:00.000Z',
      expiresAt: '2098-01-01T00:00:00.000Z',
    } : undefined,
    authorizeRunStart: async () => currentAuthorization,
    async execute({owner, prepared: actual, compilation}) {
      assert.equal(actual, prepared);
      assert.ok(JSON.parse(moon.clientProgramEffectCompilationPlanWire(
        compilation)).root_refs.some(root => root.role === 'effect_result'));
      starts++;
      const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
        owner, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(setup);
      const execution = await runCapturedEffectComputation(setup);
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
      if (failAfterCapture) throw new Error('LostEffectExecutionReply');
      return 'captured';
    },
  });
  const request = id => ({prepared, authorityScopeCid: cid('a'), requestId: id,
    tenantId: 'tenant-a', principalId: 'caller', connection: {owner: 'local'},
    lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
  let journal = openClientRequestJournal(directory);
  let other = openClientRequestJournal(directory);
  let host = install(journal, countedMoon);
  let competing = install(other);
  host.checkSupported(prepared);
  assert.equal(preflightCompiles, 1);
  const [first, second] = await Promise.all([
    host.accept(request('race')), competing.accept(request('race')),
  ]);
  assert.equal(preflightCompiles, 1,
    'accepted Run reuses the checked preflight compilation');
  assert.deepEqual(first.ref, second.ref);
  assert.equal(starts, 0, 'acceptance never starts capture');
  assert.deepEqual((await Promise.all([host.start(first), competing.start(second)]))
    .map(value => value.kind).sort(), ['reconcile', 'started']);
  assert.equal(starts, 1);
  assert.equal((await host.start(first)).kind, 'reconcile');
  const changed = JSON.parse(document);
  changed.id = 'changed-effect-intent';
  await assert.rejects(host.accept({...request('race'), prepared: prepare(JSON.stringify(changed))}),
    {code: 'ClientRequestIntentConflict'});
  const unstarted = await host.accept(request('unstarted'));
  // Reserve dispatch, crash before the separate physical-start claim.
  const identity = moon.clientProgramEffectRequestIdentity(prepared, cid('a'),
    'unstarted', moon.clientProgramSourceFreeInputIntentCid());
  journal.reserveDispatch(identity, {tenantId: 'tenant-a', currentAuthorization: true}, moon, control);
  other.close(); journal.close();
  journal = openClientRequestJournal(directory);
  host = install(journal);
  const resumed = await host.accept(request('unstarted'));
  assert.deepEqual(resumed.ref, unstarted.ref);
  assert.equal((await host.start(resumed)).kind, 'started');
  assert.equal(starts, 2);
  const gated = await host.accept(request('gated-start'));
  const gateCalls = [];
  await assert.rejects(host.start(gated, {
    beforePhysicalStart() {
      gateCalls.push('before');
      throw new Error('ResumeClaimStale');
    },
    started() { gateCalls.push('started'); },
  }), /ResumeClaimStale/);
  assert.deepEqual(gateCalls, ['before']);
  assert.equal(starts, 2);
  const gatedIdentity = moon.clientProgramEffectRequestIdentity(prepared,
    cid('a'), 'gated-start', moon.clientProgramSourceFreeInputIntentCid());
  assert.equal(journal.resolveDefinition(gatedIdentity, {tenantId: 'tenant-a'},
    moon, control).physicalStartReserved, false);
  assert.equal((await host.start(gated, {
    beforePhysicalStart() { gateCalls.push('before'); },
    started() { gateCalls.push('started'); },
  })).kind, 'started');
  assert.deepEqual(gateCalls, ['before', 'before', 'started']);
  assert.equal(starts, 3);
  failAfterCapture = true;
  const unknown = await host.accept(request('unknown'));
  await assert.rejects(host.start(unknown), /LostEffectExecutionReply/);
  assert.equal(starts, 4);
  journal.close();
  journal = openClientRequestJournal(directory);
  t.after(() => journal.close());
  host = install(journal);
  const recovered = await host.accept(request('unknown'));
  assert.deepEqual(recovered.ref, unknown.ref);
  assert.equal((await host.start(recovered)).kind, 'reconcile');
  assert.equal(starts, 4, 'unknown Effect outcome never retries capture/apply');
  const pendingProcess = await host.accept(request('process-unstarted'));
  journal.close();
  const child = spawnSync(process.execPath, [fileURLToPath(new URL(
    './fixtures/resume-client-effect-run.mjs', import.meta.url))], {
    input: JSON.stringify({directory, document, environmentWire, registry, values,
      requestId: 'process-unstarted'}), encoding: 'utf8', timeout: 20000,
  });
  assert.equal(child.status, 0, child.stderr);
  const childResult = JSON.parse(child.stdout);
  assert.equal(childResult.kind, 'started');
  assert.equal(childResult.captures, 1);
  assert.deepEqual(childResult.ref, pendingProcess.ref);
  const replayChild = spawnSync(process.execPath, [fileURLToPath(new URL(
    './fixtures/resume-client-effect-run.mjs', import.meta.url))], {
    input: JSON.stringify({directory, document, environmentWire, registry, values,
      requestId: 'unknown'}), encoding: 'utf8', timeout: 20000,
  });
  assert.equal(replayChild.status, 0, replayChild.stderr);
  assert.deepEqual(JSON.parse(replayChild.stdout), {
    kind: 'reconcile', captures: 0, ref: unknown.ref,
  });
  journal = openClientRequestJournal(directory);
  host = install(journal);
  const attached = await host.accept(request('unknown'));
  currentAuthorization = false;
  await assert.rejects(host.start(attached), {code: 'ClientRunStartDenied'});
  await assert.rejects(host.accept(request('unknown')), {code: 'ClientEffectRunDenied'});
});

test('shared Effect start rejects expired saved admission before capture',
  async t => {
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-client-deadline-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const {document, environment} = await effectFixture({
      memberIds: ['save', 'save_again'],
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
    const control = runtimeCore(moon).publicationControl;
    let clock = '2026-09-26T00:00:01.000Z';
    let createdAt = '2026-09-26T00:00:00.000Z';
    let expiresAt = '2026-09-26T00:00:02.000Z';
    let expireDuringAuthorization = false;
    let authorizationCalls = 0;
    let physicalStarts = 0;
    const install = journal => installNodeClientEffectRun({moon,
      publicationControl: control, journal, now: () => clock,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt, expiresAt}),
      authorizeRunStart: async () => {
        authorizationCalls++;
        if (expireDuringAuthorization && authorizationCalls === 2) {
          clock = expiresAt;
        }
        return true;
      },
      execute: async () => { physicalStarts++; return 'captured'; },
    });
    const request = requestId => ({prepared, authorityScopeCid: cid('a'),
      requestId, tenantId: 'tenant-a', principalId: 'caller',
      connection: {owner: 'local'},
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
    let journal = openClientRequestJournal(directory);
    let host = install(journal);
    createdAt = '2020-01-01T00:00:00.000Z';
    expiresAt = '2021-01-01T00:00:00.000Z';
    await assert.rejects(host.accept(request('expired-new')),
      {code: 'ClientEffectRunExpired'});
    createdAt = '2026-09-26T00:00:00.000Z';
    expiresAt = '2026-09-26T00:00:02.000Z';
    const delayed = await host.accept(request('expired-before-start'));
    clock = expiresAt;
    await assert.rejects(host.start(delayed),
      {code: 'ClientEffectRunExpired'});
    assert.equal(journal.resolveDefinition(
      moon.clientProgramEffectRequestIdentity(prepared, cid('a'),
        'expired-before-start', moon.clientProgramSourceFreeInputIntentCid()),
      {tenantId: 'tenant-a'}, moon, control).physicalStartReserved, false);
    clock = '2026-09-26T00:00:01.000Z';
    authorizationCalls = 0;
    expireDuringAuthorization = true;
    const pending = await host.accept(request('expired-during-authority'));
    await assert.rejects(host.start(pending),
      {code: 'ClientEffectRunExpired'});
    expireDuringAuthorization = false;
    authorizationCalls = 0;
    clock = '2026-09-26T00:00:01.000Z';
    const restarting = await host.accept(request('expired-after-restart'));
    journal.close();
    journal = openClientRequestJournal(directory);
    t.after(() => journal.close());
    host = install(journal);
    clock = '2026-09-26T00:00:03.000Z';
    expiresAt = '2098-01-01T00:00:00.000Z';
    const reaccepted = await host.accept(request('expired-after-restart'));
    assert.deepEqual(reaccepted.ref, restarting.ref);
    await assert.rejects(host.start(reaccepted),
      {code: 'ClientEffectRunExpired'});
    assert.equal(physicalStarts, 0);
    clock = '2026-09-26T00:00:01.000Z';
    expiresAt = '2026-09-26T00:00:03.000Z';
    const valid = await host.accept(request('valid-control'));
    assert.equal((await host.start(valid)).kind, 'started');
    assert.equal(physicalStarts, 1);
    clock = '2026-09-26T00:00:04.000Z';
    assert.equal((await host.start(valid)).kind, 'reconcile');
    assert.equal(physicalStarts, 1);
  });
