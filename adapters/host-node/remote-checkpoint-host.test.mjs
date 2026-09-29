// The installed Remote Host with Run-acceptance protection, driven through
// the public Client over HTTPS: allow, deny and missing configuration,
// immediate Host answers, and a held request that is reviewed, answered and
// resumed by the Host. The packed, multi-process acceptance is
// scripts/test-packed-client-checkpoint.mjs.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from
  'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {fileURLToPath} from 'node:url';
import {connect, RequestHeld} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {localContractLimits, localOutputLimits} from './local-values-plan.mjs';
import {exportPinnedEffectInput, preparePinnedEffectSourceHoldings,
  preparePinnedEffectSourceSet, retainPinnedEffectDependencyPayloads}
  from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueCompletedEffectfulComputationEvidence,
  storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson} from './local-account-config.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build', 'remote-checkpoint-host');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));
const document = await readFile(join(repository,
  'packages/sdk/fixtures/values.json'), 'utf8');
const readDocument = await readFile(join(repository,
  'adapters/connectors/duckdb/node/examples/program.json'), 'utf8');
const {DuckDBInstance} = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');
const contentCid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const withoutCid = (value, key) => {
  const body = {...value};
  delete body[key];
  return contentCid(body);
};
async function installedReadFixture(directory, outcome = 'allow') {
  const database = join(directory, 'records.duckdb');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),' +
      '(2,20),(3,30)');
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
  const environment = JSON.parse(await readFile(join(repository,
    'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8'));
  const base = JSON.parse(await readFile(join(repository,
    'spec/local-check-environment.json'), 'utf8'));
  environment.host_policy_profile = base.host_policy_profile;
  environment.evidence_bundle_cid = withoutCid(environment,
    'evidence_bundle_cid');
  const profilePath = join(directory, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify({
    version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records',
    sourceRef: 'connector://crm/main/r#v',
    checkEnvironmentWire: canonicalJson(environment),
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'coinstalled-read-account',
      entries: [{entry_id: 'read', outcome,
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read']},
        exclusions: []}],
    }),
  }));
  return profilePath;
}
async function effectFixture({twoMembers = false} = {}) {
  const environment = JSON.parse(await readFile(join(repository,
    'packages/sdk/fixtures/values.environment.json'), 'utf8'));
  const target = 'connector://crm/account';
  const schema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'number'},
    Name: {nullable: true, type: 'number'},
  }, nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: withFixtureConnector(environment,
    target), conversions: [], mapping_contract_cid: '',
    mapping_ref: 'mapping:crm.account.v1', minimum_approval: 'none',
    permission_rules: [{effect_kind: 'update', permissions: ['scope:update'],
      selector_class: 'id', write_fields: ['Name']}],
    primary_identity: 'Id', required_fields: [], required_permissions: [],
    resource_identity_cid: contentCid({resource: target}),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: target,
    target_schema: schema, target_schema_identity: contentCid(schema),
    version: 'fixture-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = withoutCid(mapping,
    'mapping_contract_cid');
  const secondTarget = 'connector://crm/secondary';
  const secondMapping = twoMembers ? {...mapping,
    connector_manifest_cid: withFixtureConnector(environment, secondTarget),
    mapping_ref: 'mapping:crm.secondary.v1',
    resource_identity_cid: contentCid({resource: secondTarget}),
    target_ref: secondTarget, mapping_contract_cid: ''} : undefined;
  if (secondMapping !== undefined) {
    secondMapping.mapping_contract_cid = withoutCid(secondMapping,
      'mapping_contract_cid');
  }
  environment.mapping_contracts = secondMapping === undefined
    ? [mapping] : [mapping, secondMapping];
  environment.evidence_bundle_cid = withoutCid(environment,
    'evidence_bundle_cid');
  const program = JSON.parse(document);
  program.stages[0].effects = {save: {update: {target,
    mapping: mapping.mapping_ref, from: {result: 'rows'}, id: 'id',
    set: {Name: {field: 'id'}}}}};
  if (secondMapping !== undefined) {
    program.stages[0].effects.save_again = {update: {
      target: secondTarget, mapping: secondMapping.mapping_ref,
      from: {result: 'rows'}, id: 'id',
      set: {Name: {field: 'id'}}}};
  }
  return {document: canonicalJson(program), mappingCid:
    mapping.mapping_contract_cid,
    mappingCids: environment.mapping_contracts.map(value =>
      value.mapping_contract_cid),
    environmentWire: canonicalJson(environment)};
}
const referenceCid = name => contentCid({reference_effect: name});
const effectLimits = Object.freeze({maxMembers: 2, maxRows: 4,
  maxWork: 100, maxFrontierWork: 64});
const sourceExportLimits = limits => [limits.maxResultFields,
  limits.maxResultMappingWork, limits.maxResultOrderWork,
  limits.maxResultWorkspaceEntries, limits.maxRows, limits.maxValueNodes,
  limits.maxValueTextBytes, limits.maxValueDepth, limits.maxValueWork,
  limits.maxWireBytes, limits.maxWireNodes, limits.maxWireDepth,
  limits.maxColumns, limits.maxOrderWork, limits.maxLogicalWireBytes,
  limits.maxLogicalWireNodes, limits.maxLogicalWireDepth,
  limits.maxSchemaFields, limits.maxSchemaBytes, limits.maxSchemaNodes,
  limits.maxSchemaDepth, limits.maxBatchBytes];

function referencePreview({moon, prepared, publicationPlan: plan},
  artifactCid, mappingCids, requestScope) {
  const programDefinitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = JSON.parse(plan.authoringContext.wire);
  const changes = () => [1, 2].map(id => ({target_row_identity: id,
    target_guard: {state: 'version', version_cid: referenceCid('guard')},
    intended_changes: {state: 'present', value: {Name: id}},
    before: {state: 'present', value: {Name: 0}},
    after: {state: 'present', value: {Name: id}},
    row_preview_cid: referenceCid('placeholder-row'),
    row_idempotency_key: referenceCid('placeholder-key')}));
  const draft = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: programDefinitionCid,
    invocation_cid: plan.invocation.identity,
    run_identity_cid: plan.runDefinition.identity,
    compiled_plan_cid:
      plan.results[0].evidenceContext.computationContractCid,
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: authoring, barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [],
    model_invocation_evidence_cids: [], model_response_artifact_cids: [],
    effects: mappingCids.map((mappingCid, memberIndex) => ({
      effect_id: memberIndex === 0 ? 'save' : 'save_again',
      effect_kind: 'update',
      target: memberIndex === 0 ? 'connector://crm/account'
        : 'connector://crm/secondary',
      mapping: memberIndex === 0 ? 'mapping:crm.account.v1'
        : 'mapping:crm.secondary.v1',
      resolved_mapping_contract_cid: mappingCid,
      effect_identity_cid: referenceCid(`effect-identity-${memberIndex}`),
      source_result: 'rows', result_artifact_cid: artifactCid,
      preview_strength: 'full_diff',
      source_binding_cid: referenceCid('source-binding'),
      capability_evidence_cid: referenceCid('capability'),
      authority_scope_cid: referenceCid('effect-authority'),
      write_footprint: {kind: 'collection',
        resource_identity_scheme_cid: referenceCid('scheme'),
        provider_namespace: 'reference',
        provider_boundary_cid: referenceCid(`boundary-${memberIndex}`),
        resource_kind: memberIndex === 0 ? 'Account' : 'Secondary',
        provider_object_identity_cids: []},
      count: 2, max_items: 2, required_permissions: ['write'],
      approval: 'none', on_item_failure: 'halt', changes: changes(),
      row_order: [],
      effect_member_preview_cid: referenceCid('placeholder-member'),
      effect_plan_logical_cid: checked(moon.clientProgramEffectPlanCid(
        prepared, memberIndex, 10, 100, 20000, 1000, 20)),
      executed: false})),
    executed: false, effect_preview_cid: referenceCid('placeholder-set'),
  };
  const authored = checked(moon.clientProgramAuthorEffectPreview(
    canonicalJson(draft), plan.runDefinition.identity,
    plan.authoringContext.identity, requestScope,
    20000, 1000, 20, mappingCids.length,
    mappingCids.length * 2, 128, 8, 3));
  return {wire: authored._0, keys: authored._1,
    authoringCid: plan.authoringContext.identity};
}

function referenceEffectClaims({moon, scope, preview, keys}) {
  const effect = runtimeCore(moon).effectApplicationControl;
  return JSON.parse(preview.wire).effects.map((member, memberIndex) => ({claims:
    member.changes.map((change, rowIndex) => {
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(scope, 'client-values',
        'source', member.effect_id,
        canonicalJson(change.target_row_identity), 64, 128, 8, 3);
      const path = `/reference-effect/${member.effect_id}/${rowIndex}`;
      const canonicalRequestCid = contentCid({path,
        row: change.row_preview_cid});
      const basis = effect.ledgerBasis(scope, locator, key,
        referenceCid('target-policy'), member.effect_member_preview_cid,
        change.row_preview_cid, canonicalRequestCid,
        referenceCid('dispatch-fence'), 'unavailable',
        referenceCid('request-authority'), referenceCid('request-use'));
      return {scope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid,
        canonicalRequestCid, path};
    })}));
}

function referencePreflight({moon, preview, mappingCids, requestScope,
  keys, proofs = []}) {
  const body = JSON.parse(preview.wire);
  const effects = body.effects;
  const routes = effects.map(effect => checked(
    moon.clientProgramEffectApplyCapabilityFromCodes(
      effect.capability_evidence_cid, 0, 0, 0, true, true, 2, 1)));
  return {proofs,
    sources: effects.map(effect => effect.source_binding_cid),
    contracts: mappingCids,
    capabilities: effects.map(effect => effect.capability_evidence_cid),
    authorities: effects.map(effect => effect.authority_scope_cid),
    observedRows: effects.flatMap(effect => effect.row_order),
    guardVersions: effects.flatMap(effect => effect.changes.map(change =>
      change.target_guard.version_cid)),
    routes, risk: undefined,
    reviewProjectionCid: referenceCid('review'),
    authorityScopeCid: effects[0].authority_scope_cid,
    policyCid: referenceCid('policy'),
    validityCid: referenceCid('validity'),
    issuerCid: referenceCid('issuer'),
    authenticationCid: referenceCid('authentication'),
    issuerKind: 'policy', decision: 'allow', requestScope, keys,
    maxMembers: effects.length,
    maxRows: effects.reduce((sum, effect) => sum + effect.changes.length, 0),
    maxFootprintWork: 4, maxWork: effectLimits.maxWork};
}

function referenceDispatch({ledger, preview, sends, loseReply, failRow}) {
  return async ({memberIndex, rowIndex, claim}) => {
    sends.push([memberIndex, rowIndex]);
    const failed = failRow?.(memberIndex, rowIndex) === true;
    await captureClaimedEffectResponse({ledger, claim,
      requestCid: claim.canonicalRequestCid,
      execute: async () => {
        if (loseReply?.(memberIndex, rowIndex)) {
          throw new Error('ReferenceEffectReplyLost');
        }
        return {observation: {useCid: referenceCid('use'),
          statusCode: failed ? 422 : 204, body: Buffer.alloc(0)}};
      }});
    ledger.recordAdmittedRowOutcome({claim, preview,
      memberIndex, previewRowIndex: rowIndex,
      outcomeWire: canonicalJson(failed
        ? {state: 'failed', error: {code: 'REFERENCE_REJECTED',
          message: 'Reference row rejected'}}
        : {state: 'applied',
          result: {record_id: `reference-${rowIndex}`}})});
    ledger.commitAdmittedRowOutcome({claim, preview,
      memberIndex, previewRowIndex: rowIndex});
  };
}

function referenceLedger(directory, moon, requestIdentity) {
  return openEffectLedger({moon, root: join(directory, 'effect-ledger'),
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(requestIdentity),
    callerRequestId: moon.clientRequestCallerId(requestIdentity),
    maxEntryBytes: 4096});
}

async function prepareReferenceCapture(facts, {directory, mappingCids,
  sends, loseReply, failRow}) {
  const {moon, control, store, execution, publicationPlan: plan,
    prepared, checkedHost, identity} = facts;
  const storedResults = await storeCompletedRunResultSet({execution,
    store, control, runDefinition: plan.runDefinition,
    invocation: plan.invocation, results: plan.results,
    outputLimits: plan.outputLimits,
    contractLimits: plan.contractLimits});
  const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, 2));
  const sourceSet = await preparePinnedEffectSourceSet({moon,
    checkedOwner: prepared, execution, inputs,
    maxMembers: mappingCids.length,
    maxGroupingWork: 100,
    limits: moon.clientProgramEffectInputExportLimits(
      ...sourceExportLimits(localOutputLimits)),
    store, maxBytes: localOutputLimits.maxWireBytes, control,
    invocation: plan.invocation, retention: plan.results[0].retention,
    sourceBindingCid: referenceCid('source-binding'),
    contractLimits: localContractLimits,
    localEvidenceContext: plan.localEvidenceContext});
  const requestScope = moon.clientProgramEffectRequestScope(prepared,
    identity);
  if (sourceSet.dependencies !== undefined) {
    retainPinnedEffectDependencyPayloads({sources: sourceSet, execution,
      store, storedResults, control, runDefinition: plan.runDefinition});
  }
  const authored = referencePreview(facts,
    sourceSet.members[0].payload.summary.artifact.identity, mappingCids,
    requestScope);
  const preview = control.admitEffectComputationPreview(authored.wire,
    plan.runDefinition, plan.authoringContext, plan.contractLimits);
  const holdings = await preparePinnedEffectSourceHoldings({sources:
    sourceSet, store, control, preview, invocation: plan.invocation}).commit();
  const previewInputs = checked(moon.clientProgramBindEffectPreviewInputs(
    checkedHost, inputs, plan.invocationOwner,
    moon.clientProgramEffectInputStage(
      moon.clientProgramEffectInputAt(inputs, 0)), authored.wire,
    authored.authoringCid,
    moon.clientProgramEffectPreviewInputLimits(
      20000, 1000, 20, 1000, 100, 20000, 1000, 20,
      mappingCids.length, mappingCids.length * 2, 100, 100)));
  const plans = [];
  for (let memberIndex = 0; memberIndex < mappingCids.length;
    memberIndex++) {
    const chunks = [];
    const verified = await verifyPinnedEffectPlan({moon, execution,
      previewInputs, previewIndex: memberIndex,
      limits: moon.clientProgramEffectInputExportLimits(
        ...sourceExportLimits(localOutputLimits)),
      planLimits: {maxFields: 10, maxWork: 100, maxBytes: 20000,
        maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000},
      onChunk: chunk => chunks.push(chunk)});
    plans.push({name: memberIndex === 0 ? 'save' : 'save_again',
      wire: chunks.join(''), proof: verified.proof});
  }
  const computation = await issueCompletedEffectfulComputationEvidence({
    execution, store, storedResults, control,
    admission: plan.admission, runDefinition: plan.runDefinition,
    invocation: plan.invocation, observation: plan.observation,
    normalizationJournal: plan.normalizationJournal,
    authoringContext: plan.authoringContext,
    receiptEvidence: plan.receiptEvidence,
    captureEvidence: plan.captureEvidence, preview,
    plans: plans.map(({name, wire}) => ({name, wire})),
    effectSourceHoldings: holdings, connectorRecovery: [],
    contractLimits: plan.contractLimits});
  if (sourceSet.payloads[0].prepared.status().pending) {
    await sourceSet.payloads[0].prepared.release();
  }
  const ledger = referenceLedger(directory, moon, identity);
  const effect = runtimeCore(moon).effectApplicationControl;
  const applyPreview = effect.admitPreviewIdentity(authored.wire,
    plan.runDefinition.identity, authored.authoringCid, requestScope,
    authored.keys, plan.contractLimits.maxWireBytes,
    plan.contractLimits.maxNodes, plan.contractLimits.maxDepth);
  const members = referenceEffectClaims({moon, scope: requestScope,
    preview: authored, keys: authored.keys});
  const preflight = referencePreflight({moon, preview: authored,
    mappingCids, requestScope, keys: authored.keys,
    proofs: plans.map(plan => plan.proof)});
  return {preview, computation, storedResults,
    apply: {moon, capturedInputs: previewInputs, preflight,
      ledger, members, maxFrontierWork: effectLimits.maxFrontierWork,
      refreshPreflight: async () => preflight,
      dispatchRow: referenceDispatch({ledger, preview: applyPreview,
        sends, loseReply, failRow})},
    receipt: {ledger, preview: applyPreview, commonMoon: moon,
      publicationPreview: preview,
      authorizeEvidenceRead: async () => true,
      members: members.map(member => ({rowOwners:
        member.claims.map(claim => ({claim})), replayed: false})),
      limits: plan.contractLimits},
    publication: {execution, store, storedResults, control, computation,
      preview, ledger, request: plan.request, attempt: plan.attempt,
      contractLimits: plan.contractLimits, now: plan.now},
    scopes: mappingCids.map(() => ({connection: 'reference',
      resource: 'records'})),
    continuationWire: canonicalJson({request: plan.request,
      attempt: plan.attempt}),
    dispose: () => ledger.close()};
}

function prepareReferenceRecovery(facts, {directory, mappingCids, sends,
  loseReply, failRow}) {
  const {moon, control, store, recovered, continuation} = facts;
  const {requestIdentity, requestScope, computation: durable} = recovered;
  const {computation, preview, storedResults} = durable;
  const ledger = referenceLedger(directory, moon, requestIdentity);
  const effect = runtimeCore(moon).effectApplicationControl;
  const previewWire = control.effectComputationPreviewWire(preview);
  const body = JSON.parse(previewWire);
  const admitted = control.effectComputationPreviewLedgerIdentity(preview);
  const keys = effect.recoveredPreviewKeys(admitted, requestScope,
    effectLimits.maxMembers, effectLimits.maxRows, effectLimits.maxWork,
    128, 8, 3);
  const applyPreview = effect.admitPreviewIdentity(previewWire,
    body.run_identity_cid,
    body.authoring_context.authoring_context_cid, requestScope, keys,
    localContractLimits.maxWireBytes, localContractLimits.maxNodes,
    localContractLimits.maxDepth);
  const recorded = ledger.recoverClaimFacts({preview: admitted,
    scope: requestScope, programId: 'client-values', nodeId: 'source',
    maxRows: effectLimits.maxRows, maxWork: effectLimits.maxWork});
  const preflight = referencePreflight({moon, preview: {wire: previewWire},
    mappingCids, requestScope, keys});
  return {preview, computation, storedResults,
    apply: {moon, store, publicationControl: control, computation, preview,
      ledger, requestScope, programId: 'client-values', nodeId: 'source',
      maxRows: effectLimits.maxRows,
      maxFrontierWork: effectLimits.maxFrontierWork,
      maxRecoveryWork: effectLimits.maxWork,
      keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
        maxWork: effectLimits.maxWork},
      refreshPreflight: async () => preflight,
      dispatchRow: referenceDispatch({ledger, preview: applyPreview,
        sends, loseReply, failRow})},
    receipt: {ledger, preview: applyPreview, commonMoon: moon,
      publicationPreview: preview,
      authorizeEvidenceRead: async () => true,
      members: recorded.members.map(member => ({rowOwners:
        member.claims.map(claim => ({claim})), replayed: true})),
      limits: localContractLimits},
    publication: {execution: null, store, storedResults, control,
      computation, preview, ledger, request: continuation.provider.request,
      attempt: {...continuation.provider.attempt,
        externalIdempotencyKey:
          continuation.provider.attempt.externalIdempotencyKey},
      contractLimits: localContractLimits,
      now: () => new Date().toISOString()},
    scopes: mappingCids.map(() => ({connection: 'reference',
      resource: 'records'})),
    continuationWire: canonicalJson(continuation.provider),
    cleanupOwner: {async close() {}, async cleanup() { return true; },
      cleanupPending: () => false},
    dispose: () => ledger.close()};
}
const owner = userInfo().username;
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});

export function runAcceptanceConfiguration(outcome, {siteKey =
  'actql-remote-host'} = {}) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'remote-account',
    entries: [{entry_id: 'run-acceptance', outcome,
      principal: {all: true}, connection: {any_of: [siteKey]},
      resource: {any_of: ['source-free-values']},
      operation: {any_of: ['write']}, exclusions: []}],
  });
}

function effectCommitConfiguration(targetRead = 'allow', commit = 'delegate') {
  return canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'remote-effect-account', entries: [
      {entry_id: 'effect-commit', outcome: commit,
        principal: {all: true}, connection: {any_of: ['reference']},
        resource: {any_of: ['records']},
        operation: {any_of: ['effect']}, exclusions: []},
      {entry_id: 'run-acceptance', outcome: 'allow',
        principal: {all: true},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['source-free-values']},
        operation: {any_of: ['write']}, exclusions: []},
      {entry_id: 'target-read', outcome: targetRead,
        principal: {all: true}, connection: {any_of: ['reference']},
        resource: {any_of: ['records']},
        operation: {any_of: ['read']}, exclusions: []},
    ]});
}

const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal'],
  ['reader-token', 'reader-principal'],
  ['stranger-token', 'stranger-principal']]);

async function remoteHost(t, authorization, {directory,
  effectInstallation, sourceProfilePath, beforeDispatch} = {}) {
  const root = directory ?? await mkdtemp(join(scratch, 'host-'));
  let dispatches = 0;
  const host = await openInstalledRemoteHttpHost({
    directory: join(root, 'state'),
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    beforeDispatch: async ref => {
      dispatches++;
      await beforeDispatch?.(ref);
    },
    authorization, effectInstallation, sourceProfilePath,
  });
  const server = createServer({key: tlsKey, cert: tlsCertificate},
    host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    server.closeAllConnections?.();
    await new Promise(resolve => server.close(resolve));
    return host.close();
  };
  // Close the Host (and its Store owner) before removing its state.
  t.after(async () => {
    await close();
    if (directory === undefined) {
      await rm(root, {recursive: true, force: true});
    }
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const as = token => connect({mode: 'remote', endpoint, token,
    durability: 'durable'});
  return {as, dispatches: () => dispatches, close};
}

const reviewers = [{keyId: 'reviewer-key', reviewerId: 'reviewer',
  principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}];
const hostKey = {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)};
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const protectedHost = (outcome, extra = {}) => ({
  ...(outcome === undefined ? {} :
    {accountConfiguration: runAcceptanceConfiguration(outcome)}),
  reviewers, reviewReaders: ['reader-principal'], hostKey, ...extra,
});

// A bounded wait for a Host-driven outcome (lease retries and restarts take
// real time on a loaded machine). This bounds waiting, never a count.
async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Timeout');
}

test('allow runs without a Checkpoint; deny and missing configuration start nothing',
  async t => {
    const allowed = await remoteHost(t, protectedHost('allow'));
    const client = await allowed.as('owner-token');
    const execution = await client.aql(document, {format: 'json',
      requestId: 'allow-a'});
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await (await allowed.as('reviewer-token'))
      .checkpoints()).items, []);
    for (const [label, authorization, code] of [
      ['deny', protectedHost('deny'), 'ACTQL_E_ACCOUNT_DENIED'],
      ['missing', protectedHost(undefined), 'ACTQL_E_ACCOUNT_CONFIG_INVALID'],
    ]) {
      const host = await remoteHost(t, authorization);
      const denied = await host.as('owner-token');
      await assert.rejects(denied.aql(document, {format: 'json',
        requestId: `${label}-a`}), {code}, label);
      assert.equal(host.dispatches(), 0, label);
      assert.deepEqual(await denied.lookupRequest(`${label}-a`),
        {kind: 'not_found'}, label);
    }
  });

test('a claimed start with lost execution observation reconciles after restart',
  async t => {
    const directory = await mkdtemp(join(scratch, 'unknown-run-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const first = await remoteHost(t, protectedHost('allow', {
      faultInjection(name) {
        if (name === 'physical_start_reserved') {
          throw new Error('LostExecutionObservation');
        }
      },
    }), {directory});
    const client = await first.as('owner-token');
    const execution = await client.aql(document, {format: 'json',
      requestId: 'unknown-start'});
    const unknown = await waitFor(async () => {
      const state = await execution.status();
      return state.status === 'needs_reconciliation' ? state : undefined;
    });
    assert.deepEqual(unknown.next_action,
      {kind: 'reconcile_run', reason: 'execution_unknown'});
    assert.equal(first.dispatches(), 1);
    await first.close();
    const restarted = await remoteHost(t, protectedHost('allow'),
      {directory});
    const attached = await (await restarted.as('owner-token'))
      .attach(execution.ref);
    assert.equal((await attached.status()).status, 'needs_reconciliation');
    assert.equal(restarted.dispatches(), 0);
    await restarted.close();
  });

test('a late Host observation failure does not overwrite publication',
  async t => {
    const host = await remoteHost(t, protectedHost('allow', {
      faultInjection(name) {
        if (name === 'computed') throw new Error('LateObservationFailure');
      },
    }));
    const client = await host.as('owner-token');
    const execution = await client.aql(document, {format: 'json',
      requestId: 'late-observation'});
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.equal(host.dispatches(), 1);
  });

test('installed Host bounds unfinished decisions across distinct requests',
  async t => {
    let finish;
    let calls = 0;
    const host = await remoteHost(t, protectedHost('delegate', {
      decisionTimeoutMs: 10, maxInFlightDecisions: 1,
      decide: () => {
        calls++;
        return new Promise(resolve => { finish = resolve; });
      },
    }));
    const client = await host.as('owner-token');
    for (const requestId of ['unfinished-one', 'unfinished-two']) {
      await assert.rejects(client.aql(document, {format: 'json', requestId}),
        {code: 'ACTQL_E_DELEGATION_UNAVAILABLE'});
    }
    assert.equal(calls, 1);
    assert.equal(host.dispatches(), 0);
    finish({decision: 'unavailable'});
    await new Promise(resolve => setImmediate(resolve));
    await assert.rejects(client.aql(document, {format: 'json',
      requestId: 'unfinished-three'}),
    {code: 'ACTQL_E_DELEGATION_UNAVAILABLE'});
    assert.equal(calls, 2);
    finish({decision: 'unavailable'});
  });

test('delegate immediate permit runs and immediate reject records nothing',
  async t => {
    const decide = view => ({decision: view.subject.subject_cid ===
      undefined ? 'reject' : 'permit', subject: view.subject,
    authority: 'host-policy'});
    let answer = 'permit';
    const host = await remoteHost(t, protectedHost('delegate', {
      decide: view => ({...decide(view), decision: answer}),
      answeringAuthorities: ['host-policy']}));
    const client = await host.as('owner-token');
    const permitted = await client.aql(document, {format: 'json',
      requestId: 'permit-a'});
    assert.equal((await permitted.wait()).status, 'succeeded');
    answer = 'reject';
    await assert.rejects(client.aql(document, {format: 'json',
      requestId: 'reject-a'}), {code: 'ACTQL_E_DELEGATION_REJECTED'});
    assert.deepEqual(await client.lookupRequest('reject-a'),
      {kind: 'not_found'});
    assert.deepEqual((await (await host.as('reviewer-token'))
      .checkpoints()).items, []);
  });

test('a held request is reviewed, answered and resumed by the Host',
  async t => {
    const host = await remoteHost(t, protectedHost('delegate'));
    const client = await host.as('owner-token');
    let held;
    try {
      await client.aql(document, {format: 'json', requestId: 'held-a'});
    } catch (error) { held = error; }
    assert.equal(held instanceof RequestHeld, true);
    assert.equal(held.held.state, 'waiting_checkpoint');
    assert.equal(host.dispatches(), 0);
    // The same request again is the same held request, not a new one.
    await assert.rejects(client.aql(document, {format: 'json',
      requestId: 'held-a'}), error => error instanceof RequestHeld &&
      error.held.checkpoint.checkpointCid ===
        held.held.checkpoint.checkpointCid);
    // The same request ID with another intent conflicts.
    const changed = JSON.parse(document);
    changed.stages[0].steps[0].values.rows = [{id: 9}];
    await assert.rejects(client.aql(JSON.stringify(changed),
      {format: 'json', requestId: 'held-a'}),
    {code: 'ClientRequestIntentConflict'});
    assert.equal((await client.lookupRequest('held-a')).state,
      'waiting_checkpoint');

    const reviewer = await host.as('reviewer-token');
    const reader = await host.as('reader-token');
    const {items: [summary]} = await reviewer.checkpoints();
    assert.equal(summary.checkpointCid, held.held.checkpoint.checkpointCid);
    assert.equal(summary.subject.requestId, 'held-a');
    assert.equal(JSON.stringify(summary).includes('"rows"'), false);
    // Status, review and answer permissions are separate.
    await assert.rejects(host.as('stranger-token'), {code:
      'ClientConnectionDenied'});
    // A reviewer is not the request owner: no Run operation.
    await assert.rejects(reviewer.aql(document, {format: 'json',
      requestId: 'reviewer-own'}), {code: 'ClientConnectionDenied'});
    await assert.rejects(reviewer.lookupRequest('held-a'),
      {code: 'ClientConnectionDenied'});
    await assert.rejects(reviewer.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(client.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint(`sha256:${'0'.repeat(64)}`),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint(summary, {maxBytes: 16}),
      {code: 'CheckpointReviewTooLarge'});
    const review = await reader.reviewCheckpoint(summary);
    const projection = JSON.parse(new TextDecoder().decode(review.bytes));
    assert.equal(projection.version, 'actql-run-review-projection/0.1');
    assert.equal(projection.displayed_scope.request_id, 'held-a');
    assert.equal(projection.displayed_scope.site_key, 'actql-remote-host');
    await assert.rejects(reader.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer}), {code: 'CheckpointAnswerDenied'});
    // Still nothing ran.
    assert.equal(host.dispatches(), 0);

    const answered = await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    // A resend of the identical signed answer is a duplicate.
    const again = await reviewer.resolveCheckpoints(answered.signed);
    assert.deepEqual(again.results.map(item => item.status), ['duplicate']);
    const found = await waitFor(async () => {
      const lookup = await client.lookupRequest('held-a');
      return lookup.kind === 'found' ? lookup : undefined;
    });
    const execution = await client.attach(found.ref);
    // wait() returns the current state; a Client waits again until the Run
    // is terminal.
    assert.equal((await waitFor(async () => {
      const state = await execution.wait();
      return ['succeeded', 'failed', 'cancelled'].includes(state.status)
        ? state : undefined;
    })).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.equal(host.dispatches(), 1);
    // The submit is now the existing Run.
    assert.deepEqual((await client.aql(document, {format: 'json',
      requestId: 'held-a'})).ref, found.ref);
    assert.deepEqual((await reviewer.checkpoints()).items, []);
  });

test('installed Effect owner resumes one approved Run acceptance',
  async t => {
    const fixture = await effectFixture();
    const registry = await readFile(join(repository,
      'spec/dependencies/aoa-pipeline-registry.json'), 'utf8');
    const aoa = JSON.parse(await readFile(join(repository,
      'spec/contracts/actql-aoa.json'), 'utf8'));
    const values = JSON.stringify(aoa.execution_contracts['REL.values']);
    let starts = 0;
    const effectInstallation = {
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async execute({owner: checkedOwner, moon, retainExecution}) {
        starts++;
        const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
          checkedOwner, registry, values, 1n, 0n, 0n, 0n);
        assert.ok(setup);
        const execution = await runCapturedEffectComputation(setup);
        retainExecution(execution);
        return {status: 'captured_without_apply'};
      },
      resume() { assert.fail('Run acceptance cannot resume an Effect apply'); },
    };
    const directory = await mkdtemp(join(scratch, 'effect-acceptance-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const first = await remoteHost(t, protectedHost('delegate',
      {resumeAfterAnswer: false}), {directory, effectInstallation});
    const client = await first.as('owner-token');
    await assert.rejects(client.aql(fixture.document, {format: 'json',
      requestId: 'effect-held-a'}), error => error instanceof RequestHeld);
    assert.equal(starts, 0);
    assert.equal((await client.lookupRequest('effect-held-a')).state,
      'waiting_checkpoint');
    await first.close();
    const restarted = await remoteHost(t, protectedHost('delegate'),
      {directory, effectInstallation});
    const reviewer = await restarted.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    assert.equal(checkpoint.subject.requestId, 'effect-held-a');
    await approveAll(reviewer, [checkpoint]);
    const ownerClient = await restarted.as('owner-token');
    const found = await waitFor(async () => {
      const value = await ownerClient.lookupRequest('effect-held-a');
      return value.kind === 'found' ? value : undefined;
    });
    const execution = await ownerClient.attach(found.ref);
    await waitFor(async () => (await execution.status()).status ===
      'needs_reconciliation');
    assert.equal(starts, 1);
    assert.deepEqual((await ownerClient.aql(fixture.document,
      {format: 'json', requestId: 'effect-held-a'})).ref, found.ref);
    assert.equal(starts, 1);
    await restarted.close();
});

test('installed Effect factory resumes an approved captured Set',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-factory-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const diagnostics = [];
    const installed = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async prepareCaptured(facts) {
        try {
          return await prepareReferenceCapture(facts,
            {directory, mappingCids: fixture.mappingCids, sends});
        } catch (error) {
          diagnostics.push({name: 'capture_stack', detail: error.stack});
          throw error;
        }
      },
      prepareRecovered: facts => prepareReferenceRecovery(facts,
        {directory, mappingCids: fixture.mappingCids, sends}),
    });
    const effectInstallation = {...installed,
      async resume(facts) {
        try { return await installed.resume(facts); }
        catch (error) {
          diagnostics.push({name: 'resume_stack', detail: {
            stack: error.stack, authorization: error.authorization}});
          throw error;
        }
      }};
    const host = await remoteHost(t, protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration(),
        observe: (name, detail) => diagnostics.push({name, detail})}),
    {directory, effectInstallation});
    const client = await host.as('owner-token');
    const execution = await client.aql(fixture.document, {format: 'json',
      requestId: 'effect-factory-a'});
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint').catch(async error => {
      error.message = JSON.stringify({state: await execution.status(),
        diagnostics});
      throw error;
    });
    assert.deepEqual(sends, []);
    const reviewer = await host.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    assert.equal(checkpoint.phase, 'commit');
    await host.close();
    const awaitingAnswer = await remoteHost(t, protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration(),
        resumeAfterAnswer: false,
        observe: (name, detail) => diagnostics.push({name, detail})}),
    {directory, effectInstallation});
    const answerer = await awaitingAnswer.as('reviewer-token');
    const [pending] = (await answerer.checkpoints()).items;
    assert.equal(pending.checkpointCid, checkpoint.checkpointCid);
    const answer = await answerer.resolveCheckpoints([
      {checkpoint: pending, decision: 'approved'}],
    {signer: {...signer,
      authorityScopeCid: execution.ref.authorityScopeCid}});
    assert.deepEqual(answer.results.map(item => item.status),
      ['committed']);
    assert.deepEqual(sends, []);
    await awaitingAnswer.close();
    let releaseResume;
    let barrierReached = false;
    const resumeBarrier = new Promise(resolve => { releaseResume = resolve; });
    const opening = remoteHost(t, protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration(),
        observe: (name, detail) => diagnostics.push({name, detail})}),
    {directory, effectInstallation, async beforeDispatch() {
      barrierReached = true;
      await resumeBarrier;
    }});
    await waitFor(() => barrierReached);
    assert.deepEqual(sends, []);
    releaseResume();
    const resumed = await opening.catch(error => {
      throw new Error(JSON.stringify({code: error.code,
        primaryCode: error.primaryFailure?.code,
        primaryMessage: error.primaryFailure?.message,
        primaryStack: error.primaryFailure?.stack,
        cleanupPending: error.cleanupPending}), {cause: error});
    });
    const resumedClient = await resumed.as('owner-token');
    const attached = await resumedClient.attach(execution.ref);
    await waitFor(async () => (await attached.status()).status ===
      'succeeded').catch(async error => {
      error.message = JSON.stringify({state: await attached.status(),
        sends, diagnostics});
      throw error;
    });
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    assert.deepEqual(await attached.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await resumedClient.aql(fixture.document,
      {format: 'json', requestId: 'effect-factory-a'})).ref,
    execution.ref);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    const duplicate = await (await resumed.as('reviewer-token'))
      .resolveCheckpoints(answer.signed);
    assert.deepEqual(duplicate.results.map(item => item.status),
      ['duplicate']);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    try {
      await resumed.close();
    } catch (error) {
      // Check the first failure before retrying its exact Store owner.
      // Unexpected owners retain their complete cause in CI diagnostics.
      const detail = {code: error.code,
        cleanupPending: error.cleanupPending,
        pendingOwners: error.cleanupHandle?.status?.().pending,
        cleanupErrors: (error.cleanupErrors ?? []).map(item => ({
          owner: item.owner, code: item.error?.code,
          message: item.error?.message,
          causeCode: item.error?.cause?.code,
          causeMessage: item.error?.cause?.message,
        }))};
      const pending = error.cleanupErrors?.map(item => ({
        owner: item.owner, code: item.error?.code,
      }));
      try {
        assert.deepEqual(pending,
          [{owner: 'store', code: 'PublicationStoreCleanupPending'}]);
      } catch {
        throw new Error(JSON.stringify(detail), {cause: error});
      }
      // A completed read can leave an independently owned Store deletion in
      // progress. Retry that exact retained owner before reopening the Host.
      await waitFor(async () => {
        try { return await error.cleanupHandle.retry(); }
        catch (retryError) {
          assert.deepEqual(retryError.cleanupErrors?.map(item => ({
            owner: item.owner, code: item.error?.code,
          })), pending);
          return undefined;
        }
      });
    }
    const finalHost = await remoteHost(t, protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration()}),
    {directory, effectInstallation}).catch(error => {
      // The direct cause, the primary failure and each initialization
      // cleanup failure are kept apart; none replaces another.
      throw new Error(JSON.stringify({code: error.code,
        causeCode: error.cause?.code, causeMessage: error.cause?.message,
        primaryCode: error.primaryFailure?.code,
        primaryMessage: error.primaryFailure?.message,
        primaryStack: error.primaryFailure?.stack,
        cleanupPending: error.cleanupPending,
        cleanupErrors: (error.cleanupErrors ?? []).map(item => ({
          owner: item.owner, code: item.error?.code,
          message: item.error?.message}))}), {cause: error});
    });
    const finalExecution = await (await finalHost.as('owner-token'))
      .attach(execution.ref);
    assert.equal((await finalExecution.status()).status, 'succeeded');
    assert.deepEqual(await finalExecution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    await finalHost.close();
  });

test('installed Effect retries a transient capture read without recompute',
  async t => {
    const fixture = await effectFixture();
    const directory = await mkdtemp(join(scratch, 'effect-read-retry-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    let captures = 0;
    let recoveryReads = 0;
    let busyClaims = 0;
    let preparationFailures = 0;
    let preparationCleanups = 0;
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const installed = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 13), leaseMs: 1000,
      prepareCaptured(facts) {
        captures++;
        return prepareReferenceCapture(facts, hooks);
      },
      prepareRecovered(facts) {
        if (preparationFailures === 0) {
          preparationFailures++;
          facts.retainRecoveryOwner({async close() {},
            async cleanup() { preparationCleanups++; return true; },
            cleanupPending: () => false});
          throw new Error('TemporaryProviderPreparationFailure');
        }
        return prepareReferenceRecovery(facts, hooks);
      },
    });
    const effectInstallation = {...installed, resume(facts) {
      return installed.resume({...facts,
        checkpointJournal: busyClaims === 0 && recoveryReads >= 1
          ? {claimResume() {
            busyClaims++;
            return {action: 'busy'};
          }} : facts.checkpointJournal,
        recoverCapture: async options => {
          recoveryReads++;
          if (recoveryReads === 1) {
            throw new Error('TemporaryCaptureStoreFailure');
          }
          return facts.recoverCapture(options);
        }});
    }};
    const account = (extra = {}) => protectedHost(undefined, {
      accountConfiguration: effectCommitConfiguration(), leaseMs: 1000,
      ...extra,
    });
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submitted = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json',
        requestId: 'effect-read-retry'});
    await waitFor(async () => (await submitted.status()).status ===
      'waiting_checkpoint');
    await first.close();
    const answering = await remoteHost(t,
      account({resumeAfterAnswer: false}), {directory, effectInstallation});
    const reviewer = await answering.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    const answer = await reviewer.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer: {...signer,
        authorityScopeCid: submitted.ref.authorityScopeCid}});
    assert.deepEqual(answer.results.map(item => item.status), ['committed']);
    await answering.close();
    const resumed = await remoteHost(t, account(), {directory,
      effectInstallation});
    const same = await (await resumed.as('owner-token'))
      .attach(submitted.ref);
    await waitFor(async () => (await same.status()).status === 'succeeded');
    assert.equal(captures, 1);
    assert.ok(recoveryReads >= 4);
    assert.equal(busyClaims, 1);
    assert.equal(preparationFailures, 1);
    assert.equal(preparationCleanups, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await resumed.close();
  });

test('installed Effect allow publishes without a commit Checkpoint',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-direct-allow-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 8),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = () => protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration('allow', 'allow')});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const client = await first.as('owner-token');
    const submitted = await client.aql(fixture.document, {format: 'json',
      requestId: 'effect-direct-allow-a'});
    await waitFor(async () => (await submitted.status()).status ===
      'succeeded');
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    assert.deepEqual(await submitted.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await (await first.as('reviewer-token'))
      .checkpoints()).items, []);
    await first.close();
    const restarted = await remoteHost(t, account(), {directory,
      effectInstallation});
    const sameRun = await (await restarted.as('owner-token'))
      .attach(submitted.ref);
    assert.equal((await sameRun.status()).status, 'succeeded');
    assert.deepEqual(await sameRun.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    await restarted.close();
  });

for (const readDecision of ['deny', 'delegate']) {
  test(`acquired Effect read ${readDecision} ends without Preview or write`,
    async t => {
      const directory = await mkdtemp(join(scratch, 'acquired-effect-refusal-'));
      t.after(() => rm(directory, {recursive: true, force: true}));
      const sourceProfilePath = await installedReadFixture(directory,
        readDecision);
      const fixture = await effectFixture();
      const program = JSON.parse(readDocument);
      delete program.params;
      program.stages = program.stages.slice(0, 2);
      program.stages[0].steps[0].filter = 'id > 1';
      program.stages[1].effects = JSON.parse(fixture.document).stages[0].effects;
      program.stages[1].effects.save.update.from.result = 'r';
      program.results = {answer: {from: {stage: 'compute_a', result: 'r'}}};
      let providerPreparations = 0;
      const effectInstallation = createInstalledEffectSite({
        environmentWire: fixture.environmentWire,
        prepareCaptured() {
          providerPreparations++;
          assert.fail('Read refusal must precede Effect preparation');
        },
        prepareRecovered() { assert.fail('No resumable captured Effect'); },
      });
      const diagnostics = [];
      const configuration = JSON.parse(effectCommitConfiguration());
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      const authorization = () => protectedHost(undefined, {
        accountConfiguration: canonicalJson(configuration),
        observe: (name, detail) => diagnostics.push({name, detail}),
      });
      const options = {directory, sourceProfilePath, effectInstallation};
      const first = await remoteHost(t, authorization(), options);
      const client = await first.as('owner-token');
      const submitted = await client.aql(canonicalJson(program), {
        format: 'json', requestId: `acquired-effect-${readDecision}`});
      await waitFor(async () => (await submitted.status()).status === 'failed');
      assert.equal(providerPreparations, 0);
      assert.deepEqual((await (await first.as('reviewer-token'))
        .checkpoints()).items, []);
      assert.ok(diagnostics.some(({name, detail}) =>
        name === 'effect_start_failed' && detail.code ===
          (readDecision === 'deny' ? 'ExecutionAuthorizationDenied'
            : 'ExecutionAuthorizationDeferralUnsupported')),
      JSON.stringify(diagnostics));
      await first.close();
      const restarted = await remoteHost(t, authorization(), options);
      const retained = await (await restarted.as('owner-token'))
        .attach(submitted.ref);
      assert.equal((await retained.status()).status, 'failed');
      assert.equal(providerPreparations, 0);
      await restarted.close();
    });
}

for (const outcome of ['success', 'unknown', 'cancel', 'reject']) {
const lostReply = outcome === 'unknown';
test(outcome === 'cancel' || outcome === 'reject'
  ? `acquired Effect ${outcome} retires upstream payloads after restart`
  : lostReply ? 'acquired Effect preserves unknown across Host restart'
    : 'acquired Effect waits durably and resumes through the public Host',
  async t => {
    const directory = await mkdtemp(join(scratch, 'acquired-effect-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory);
    const fixture = await effectFixture({twoMembers: true});
    const program = JSON.parse(readDocument);
    delete program.params;
    program.stages = program.stages.slice(0, 2);
    program.stages[0].steps[0].filter = 'id > 0';
    program.stages[1].steps[0].filter = 'id < 3';
    program.stages[1].results = {rows: {from: 'out', fields: ['id']}};
    program.stages[1].effects = JSON.parse(fixture.document).stages[0].effects;
    program.results = {answer: {from: {stage: 'compute_a', result: 'rows'}}};
    const sends = [];
    const diagnostics = [];
    let captures = 0;
    let recoveries = 0;
    const hooks = {directory, mappingCids: fixture.mappingCids, sends,
      // The final response is lost after three durable successes. This is
      // interrupted-Host recovery, not an adapter's handled row-failure case.
      loseReply: (member, row) => lostReply && member === 1 && row === 1};
    const installed = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 24),
      async prepareCaptured(facts) {
        captures++;
        try { return await prepareReferenceCapture(facts, hooks); }
        catch (error) {
          diagnostics.push({name: 'capture_failure', stack: error.stack});
          throw error;
        }
      },
      prepareRecovered(facts) {
        recoveries++;
        return prepareReferenceRecovery(facts, hooks);
      },
    });
    const checkedUnitFacts = facts => ({...facts,
      effectAuthorization(options) {
        assert.equal(options.unitId, 'compute_a');
        return facts.effectAuthorization(options);
      }});
    const effectInstallation = {...installed,
      execute: facts => installed.execute(checkedUnitFacts(facts)),
      resume: facts => installed.resume(checkedUnitFacts(facts))};
    const options = {directory, sourceProfilePath, effectInstallation};
    const account = () => {
      const configuration = JSON.parse(effectCommitConfiguration());
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      return protectedHost(undefined, {
        accountConfiguration: canonicalJson(configuration),
        observe: (name, detail) => diagnostics.push({name, detail}),
      });
    };
    const first = await remoteHost(t, account(), options);
    const execution = await (await first.as('owner-token')).aql(
      canonicalJson(program), {format: 'json', requestId: 'acquired-effect'});
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint').catch(async error => {
      error.message = JSON.stringify({state: await execution.status(), diagnostics});
      throw error;
    });
    assert.equal(captures, 1);
    assert.deepEqual(sends, []);
    const [checkpoint] = (await (await first.as('reviewer-token'))
      .checkpoints()).items;
    await first.close();
    const resumed = await remoteHost(t, account(), options);
    const reviewer = await resumed.as('reviewer-token');
    const [pending] = (await reviewer.checkpoints()).items;
    assert.equal(pending.checkpointCid, checkpoint.checkpointCid);
    if (outcome === 'cancel' || outcome === 'reject') {
      const attached = await (await resumed.as('owner-token')).attach(execution.ref);
      const publication = join(directory, 'state', 'publication');
      assert.ok((await readdir(join(publication, 'physical-holdings'))).length > 0);
      if (outcome === 'cancel') await attached.cancel();
      else await reviewer.resolveCheckpoints([{checkpoint: pending,
        decision: 'rejected'}], {signer: {...signer,
        authorityScopeCid: execution.ref.authorityScopeCid}});
      // Existing waiting-exit semantics: rejecting a never-dispatched
      // continuation cancels it; it is not an attempted Effect failure.
      const terminal = 'cancelled';
      await waitFor(async () => (await attached.status()).status === terminal);
      await resumed.close();
      const finalHost = await remoteHost(t, account(), options);
      const finalExecution = await (await finalHost.as('owner-token'))
        .attach(execution.ref);
      assert.equal((await finalExecution.status()).status, terminal);
      await finalHost.close();
      assert.deepEqual(await readdir(join(publication, 'physical-holdings')), []);
      assert.deepEqual(await readdir(join(publication, 'objects')), []);
      assert.equal(captures, 1);
      assert.equal(recoveries, 0);
      assert.deepEqual(sends, []);
      return;
    }
    await reviewer.resolveCheckpoints([{checkpoint: pending,
      decision: 'approved'}], {signer: {...signer,
      authorityScopeCid: execution.ref.authorityScopeCid}});
    const attached = await (await resumed.as('owner-token')).attach(execution.ref);
    const expectedStatus = lostReply ? 'needs_reconciliation' : 'succeeded';
    await waitFor(async () => (await attached.status()).status ===
      expectedStatus).catch(async error => {
      error.message = JSON.stringify({state: await attached.status(), diagnostics});
      throw error;
    });
    assert.equal(captures, 1);
    assert.equal(recoveries, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    if (!lostReply) {
      assert.deepEqual(await attached.result('answer').all(), [{id: 1}, {id: 2}]);
    } else {
      assert.equal((await attached.status()).result_available, false);
    }
    await resumed.close();
    const finalHost = await remoteHost(t, account(), options);
    const finalExecution = await (await finalHost.as('owner-token'))
      .attach(execution.ref);
    assert.equal((await finalExecution.status()).status, expectedStatus);
    if (!lostReply) {
      assert.deepEqual(await finalExecution.result('answer').all(),
        [{id: 1}, {id: 2}]);
    } else {
      assert.equal((await finalExecution.status()).result_available, false);
    }
    assert.equal(captures, 1);
    assert.equal(recoveries, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    await finalHost.close();
  });
}

for (const damage of ['missing', 'corrupt']) {
test(`a ${damage} acquired input rejects only its Run after Host restart`,
  async t => {
    const directory = await mkdtemp(join(scratch, 'damaged-acquired-effect-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory);
    const fixture = await effectFixture({twoMembers: true});
    const program = JSON.parse(readDocument);
    delete program.params;
    program.stages = program.stages.slice(0, 2);
    program.stages[0].steps[0].filter = 'id > 0';
    program.stages[1].steps[0].filter = 'id < 3';
    program.stages[1].results = {rows: {from: 'out', fields: ['id']}};
    program.stages[1].effects = JSON.parse(fixture.document).stages[0].effects;
    program.results = {answer: {from: {stage: 'compute_a', result: 'rows'}}};
    const sends = [];
    let captures = 0;
    let recoveries = 0;
    let reportRecoveryFailure;
    const recoveryFailure = new Promise(resolve => { reportRecoveryFailure = resolve; });
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const installed = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 24),
      prepareCaptured(facts) {
        captures++;
        return prepareReferenceCapture(facts, hooks);
      },
      prepareRecovered(facts) {
        recoveries++;
        return prepareReferenceRecovery(facts, hooks);
      },
    });
    const effectInstallation = {...installed, async resume(facts) {
      try { return await installed.resume(facts); }
      catch (error) { reportRecoveryFailure(error); throw error; }
    }};
    const options = {directory, sourceProfilePath, effectInstallation};
    const account = () => {
      const configuration = JSON.parse(effectCommitConfiguration());
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      return protectedHost(undefined, {accountConfiguration: canonicalJson(configuration)});
    };
    const first = await remoteHost(t, account(), options);
    const client = await first.as('owner-token');
    const healthy = await client.aql(document, {format: 'json', requestId: 'healthy'});
    assert.equal((await healthy.wait()).status, 'succeeded');
    const expectedRows = await healthy.result('answer').all();
    const damaged = await client.aql(canonicalJson(program),
      {format: 'json', requestId: 'damaged'});
    await waitFor(async () => (await damaged.status()).status === 'waiting_checkpoint');
    await first.close();
    const publication = join(directory, 'state', 'publication');
    const holdingPath = join(publication, 'physical-holdings');
    const holdings = await Promise.all((await readdir(holdingPath))
      .map(async name => JSON.parse(await readFile(join(holdingPath, name)))));
    const memberObjects = new Set(holdings.filter(x => x.namespace === 'effect-source')
      .flatMap(x => x.objects.map(object => object.cid)));
    const upstream = holdings.find(x => x.namespace === 'effect-capture')
      .objects.find(object => !memberObjects.has(object.cid));
    assert.ok(upstream, 'damage an upstream-only dependency, not the member output');
    const objectPath = join(publication, 'objects', upstream.cid.slice(7));
    if (damage === 'missing') await rm(objectPath);
    else {
      const bytes = await readFile(objectPath);
      bytes[0] ^= 1;
      await writeFile(objectPath, bytes);
    }
    const resumed = await remoteHost(t, account(), options);
    const attached = await (await resumed.as('owner-token')).attach(healthy.ref);
    assert.equal((await attached.status()).status, 'succeeded');
    assert.deepEqual(await attached.result('answer').all(), expectedRows);
    const reviewer = await resumed.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    await reviewer.resolveCheckpoints([{checkpoint, decision: 'approved'}],
      {signer: {...signer, authorityScopeCid: damaged.ref.authorityScopeCid}});
    const error = await recoveryFailure;
    assert.equal(error.code, damage === 'missing'
      ? 'PublicationObjectMissing' : 'PublicationObjectCorrupt');
    assert.equal(captures, 1);
    assert.equal(recoveries, 0, 'reject damaged custody before provider recovery');
    assert.deepEqual(sends, []);
    assert.deepEqual(await attached.result('answer').all(), expectedRows);
    await resumed.close();
    assert.ok((await readdir(holdingPath)).length > 0,
      'unavailable input must not erase its recovery responsibility');
  });
}

test('one installed Host reads and applies independent Effects', async t => {
  const directory = await mkdtemp(join(scratch, 'source-effect-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const sourceProfilePath = await installedReadFixture(directory);
  const fixture = await effectFixture({twoMembers: true});
  const sends = [];
  const hooks = {directory, mappingCids: fixture.mappingCids, sends};
  const effectInstallation = createInstalledEffectSite({
    environmentWire: fixture.environmentWire,
    privateEvidenceKey: Buffer.alloc(32, 16),
    prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
    prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
  });
  const options = {directory, sourceProfilePath, effectInstallation};
  const account = () => {
    const configuration = JSON.parse(effectCommitConfiguration(
      'allow', 'allow'));
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {all: true};
    return protectedHost(undefined,
      {accountConfiguration: canonicalJson(configuration)});
  };
  const first = await remoteHost(t, account(), options);
  const client = await first.as('owner-token');
  const read = await client.aql(readDocument, {format: 'json',
    requestId: 'coinstalled-read', parameters: {minimum: 1}});
  assert.equal((await read.wait()).status, 'succeeded');
  assert.deepEqual((await read.result('b').all()).map(row => row.id)
    .sort(), [2, 3, 3]);
  const effect = await client.aql(fixture.document, {format: 'json',
    requestId: 'coinstalled-effect'});
  await waitFor(async () => (await effect.status()).status === 'succeeded');
  assert.deepEqual(await effect.result('answer').all(),
    [{id: 1}, {id: 2}]);
  assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
  await first.close();
  const restarted = await remoteHost(t, account(), options);
  const attached = await (await restarted.as('owner-token'))
    .attach(effect.ref);
  assert.equal((await attached.status()).status, 'succeeded');
  assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
  await restarted.close();
});

test('coinstalled read and commit approvals survive the same Host restart',
  async t => {
    const directory = await mkdtemp(join(scratch, 'source-effect-held-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory,
      'delegate');
    const fixture = await effectFixture();
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 17),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const options = {directory, sourceProfilePath, effectInstallation};
    const account = (extra = {}) => {
      const configuration = JSON.parse(effectCommitConfiguration());
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      return protectedHost(undefined, {...extra,
        accountConfiguration: canonicalJson(configuration)});
    };
    const first = await remoteHost(t, account({resumeAfterAnswer: false}),
      options);
    const client = await first.as('owner-token');
    await assert.rejects(client.aql(readDocument, {format: 'json',
      requestId: 'coinstalled-held-read', parameters: {minimum: 1}}),
    RequestHeld);
    const effect = await client.aql(fixture.document, {format: 'json',
      requestId: 'coinstalled-held-effect'});
    await waitFor(async () => (await effect.status()).status ===
      'waiting_checkpoint');
    assert.deepEqual(sends, []);
    const reviewer = await first.as('reviewer-token');
    const checkpoints = (await reviewer.checkpoints()).items;
    assert.deepEqual(checkpoints.map(item => item.kind).sort(),
      ['effect_set', 'read_access']);
    await first.close();
    const answering = await remoteHost(t, account({resumeAfterAnswer: false}),
      options);
    const resumedReviewer = await answering.as('reviewer-token');
    for (const checkpoint of checkpoints) {
      const approved = await resumedReviewer.resolveCheckpoints([
        {checkpoint, decision: 'approved'}], {signer: {...signer,
          ...(checkpoint.kind === 'effect_set'
            ? {authorityScopeCid: effect.ref.authorityScopeCid} : {})}});
      assert.deepEqual(approved.results.map(item => item.status),
        ['committed']);
    }
    assert.deepEqual(sends, []);
    await answering.close();
    const resumed = await remoteHost(t, account(), options);
    const resumedClient = await resumed.as('owner-token');
    const readLookup = await waitFor(async () => {
      const found = await resumedClient.lookupRequest('coinstalled-held-read');
      return found.kind === 'found' ? found : undefined;
    });
    const read = await resumedClient.attach(readLookup.ref);
    assert.equal((await read.wait()).status, 'succeeded');
    assert.deepEqual((await read.result('b').all()).map(row => row.id)
      .sort(), [2, 3, 3]);
    const applied = await resumedClient.attach(effect.ref);
    await waitFor(async () => (await applied.status()).status ===
      'succeeded');
    assert.deepEqual(await applied.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await resumed.close();
  });

test('coinstalled read denial cannot authorize or suppress independent commit',
  async t => {
    const directory = await mkdtemp(join(scratch, 'source-effect-deny-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory, 'deny');
    const fixture = await effectFixture();
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 18),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const configuration = JSON.parse(effectCommitConfiguration(
      'allow', 'allow'));
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {all: true};
    const host = await remoteHost(t, protectedHost(undefined,
      {accountConfiguration: canonicalJson(configuration)}),
    {directory, sourceProfilePath, effectInstallation});
    const client = await host.as('owner-token');
    await assert.rejects(client.aql(readDocument, {format: 'json',
      requestId: 'coinstalled-denied-read', parameters: {minimum: 1}}),
    {code: 'ACTQL_E_ACCOUNT_DENIED'});
    assert.deepEqual(await client.lookupRequest('coinstalled-denied-read'),
      {kind: 'not_found'});
    const applied = await client.aql(fixture.document, {format: 'json',
      requestId: 'coinstalled-allowed-effect'});
    await waitFor(async () => (await applied.status()).status ===
      'succeeded');
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await host.close();
  });

test('public Effect dispatch waits for and obeys the Host barrier',
  async t => {
    const fixture = await effectFixture();
    const directory = await mkdtemp(join(scratch, 'effect-barrier-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    let captures = 0;
    let release;
    const barrier = new Promise(resolve => { release = resolve; });
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const installed = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 10),
      prepareCaptured(facts) {
        captures++;
        return prepareReferenceCapture(facts, hooks);
      },
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration('allow', 'allow')});
    const first = await remoteHost(t, account, {directory,
      effectInstallation: installed, beforeDispatch: () => barrier});
    const run = await (await first.as('owner-token')).aql(fixture.document,
      {format: 'json', requestId: 'effect-barrier-wait'});
    assert.equal(captures, 0);
    assert.deepEqual(sends, []);
    release();
    await waitFor(async () => (await run.status()).status === 'succeeded');
    assert.equal(captures, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await first.close();

    let refusedCaptures = 0;
    const refused = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 10),
      prepareCaptured() {
        refusedCaptures++;
        assert.fail('A rejected barrier cannot start Compute');
      },
      prepareRecovered() {
        assert.fail('A rejected barrier cannot resume Effects');
      },
    });
    const denied = await remoteHost(t, account, {directory,
      effectInstallation: refused, beforeDispatch() {
        throw new Error('ExecutionBarrierDenied');
      }});
    const rejected = await (await denied.as('owner-token'))
      .aql(fixture.document, {format: 'json',
        requestId: 'effect-barrier-refused'});
    await waitFor(async () => (await rejected.status()).status === 'failed');
    assert.equal(refusedCaptures, 0);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await denied.close();
  });

test('installed Effect deny sends nothing and reclaims captured inputs',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-direct-deny-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 9),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = () => protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration('allow', 'deny')});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submitted = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json',
        requestId: 'effect-direct-deny-a'});
    await waitFor(async () => (await submitted.status()).status === 'failed');
    assert.deepEqual(sends, []);
    assert.deepEqual((await (await first.as('reviewer-token'))
      .checkpoints()).items, []);
    assert.equal((await first.close()).storeCleanupPending, false);
    assert.deepEqual(await readdir(join(directory, 'state', 'publication',
      'physical-holdings')), []);
    const restarted = await remoteHost(t, account(), {directory,
      effectInstallation});
    const sameRun = await (await restarted.as('owner-token'))
      .attach(submitted.ref);
    assert.equal((await sameRun.status()).status, 'failed');
    assert.deepEqual(sends, []);
    await restarted.close();
  });

test('terminal Checkpoints retire captured Effect payloads after restart',
  async t => {
    for (const outcome of ['cancel', 'reject', 'approved-cancel']) {
      await t.test(outcome, async child => {
        const fixture = await effectFixture({twoMembers: true});
        const directory = await mkdtemp(join(scratch,
          `effect-retirement-${outcome}-`));
        child.after(() => rm(directory, {recursive: true, force: true}));
        const sends = [];
        const hooks = {directory, mappingCids: fixture.mappingCids, sends};
        const effectInstallation = createInstalledEffectSite({
          environmentWire: fixture.environmentWire,
          privateEvidenceKey: Buffer.alloc(32, 11),
          prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
          prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
        });
        const account = () => protectedHost(undefined, {
          accountConfiguration: effectCommitConfiguration(),
          resumeAfterAnswer: false,
        });
        const first = await remoteHost(child, account(), {directory,
          effectInstallation});
        const run = await (await first.as('owner-token'))
          .aql(fixture.document, {format: 'json',
            requestId: `effect-retire-${outcome}`});
        await waitFor(async () => (await run.status()).status ===
          'waiting_checkpoint');
        const publication = join(directory, 'state', 'publication');
        const holdings = join(publication, 'physical-holdings');
        assert.ok((await readdir(holdings)).length > 0);
        assert.ok((await readdir(join(publication, 'objects'))).length > 0);
        const reviewer = await first.as('reviewer-token');
        const [checkpoint] = (await reviewer.checkpoints()).items;
        if (outcome !== 'cancel') {
          const answered = await reviewer.resolveCheckpoints([
            {checkpoint, decision: outcome === 'reject'
              ? 'rejected' : 'approved'}], {signer: {...signer,
                authorityScopeCid: run.ref.authorityScopeCid}});
          assert.deepEqual(answered.results.map(item => item.status),
            ['committed']);
        }
        if (outcome !== 'reject') await run.cancel();
        await waitFor(async () => ['failed', 'cancelled'].includes(
          (await run.status()).status));
        await first.close();
        const restarted = await remoteHost(child, account(), {directory,
          effectInstallation});
        const same = await (await restarted.as('owner-token'))
          .attach(run.ref);
        assert.ok(['failed', 'cancelled'].includes(
          (await same.status()).status));
        assert.deepEqual(await readdir(holdings), []);
        assert.deepEqual(await readdir(join(publication, 'objects')), []);
        assert.deepEqual(sends, []);
        await restarted.close();
      });
    }
  });

test('an expired Effect Checkpoint retires the captured payload',
  async t => {
    const fixture = await effectFixture();
    const directory = await mkdtemp(join(scratch, 'effect-expiry-retire-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 12),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = () => protectedHost(undefined, {
      accountConfiguration: effectCommitConfiguration(),
      checkpointTtlMs: 1000, leaseMs: 1000,
    });
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const run = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json',
        requestId: 'effect-expiry-retirement'});
    await waitFor(async () => (await run.status()).status ===
      'waiting_checkpoint');
    const publication = join(directory, 'state', 'publication');
    assert.ok((await readdir(join(publication,
      'physical-holdings'))).length > 0);
    const [checkpoint] = (await (await first.as('reviewer-token'))
      .checkpoints()).items;
    await first.close();
    await new Promise(resolve => setTimeout(resolve,
      Math.max(0, Date.parse(checkpoint.expiresAt) - Date.now() + 100)));
    const restarted = await remoteHost(t, account(), {directory,
      effectInstallation});
    const same = await (await restarted.as('owner-token'))
      .attach(run.ref);
    await waitFor(async () => {
      const state = await same.status();
      return ['failed', 'cancelled'].includes(state.status) ? state : undefined;
    }).catch(async error => {
      error.message = JSON.stringify({state: await same.status(),
        checkpoint, sends});
      throw error;
    });
    await restarted.close();
    assert.deepEqual(await readdir(join(publication,
      'physical-holdings')), []);
    assert.deepEqual(await readdir(join(publication, 'objects')), []);
    assert.deepEqual(sends, []);
  });

test('installed Effect rechecks account denial after an approved answer',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-current-deny-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 6),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = (commit = 'delegate', extra = {}) =>
      protectedHost(undefined, {...extra,
        accountConfiguration: effectCommitConfiguration('allow', commit)});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submitted = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json', requestId: 'current-deny-a'});
    await waitFor(async () => (await submitted.status()).status ===
      'waiting_checkpoint');
    assert.deepEqual(sends, []);
    await first.close();
    const answering = await remoteHost(t, account('delegate', {
      resumeAfterAnswer: false}), {directory, effectInstallation});
    const [checkpoint] = (await (await answering.as('reviewer-token'))
      .checkpoints()).items;
    const answered = await (await answering.as('reviewer-token'))
      .resolveCheckpoints([{checkpoint, decision: 'approved'}],
        {signer: {...signer,
          authorityScopeCid: submitted.ref.authorityScopeCid}});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    await answering.close();
    const denied = await remoteHost(t, account('deny'), {directory,
      effectInstallation});
    const resumed = await (await denied.as('owner-token'))
      .attach(submitted.ref);
    await waitFor(async () => (await resumed.status()).status === 'failed');
    assert.deepEqual(sends, []);
    assert.deepEqual((await (await denied.as('reviewer-token'))
      .checkpoints()).items, []);
    assert.equal((await denied.close()).storeCleanupPending, false);
    const holdingRoot = join(directory, 'state', 'publication',
      'physical-holdings');
    const holdingFiles = await readdir(holdingRoot);
    assert.deepEqual(await Promise.all(holdingFiles.map(async file =>
      JSON.parse(await readFile(join(holdingRoot, file), 'utf8')))), []);
    const restarted = await remoteHost(t, account('deny'), {directory,
      effectInstallation});
    const sameRun = await (await restarted.as('owner-token'))
      .attach(submitted.ref);
    assert.equal((await sameRun.status()).status, 'failed');
    assert.deepEqual(sends, []);
    await restarted.close();
  });

test('installed Effect reply loss retains the unknown row after restart',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-reply-loss-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const diagnostics = [];
    let loseFirst = true;
    const hooks = {directory, mappingCids: fixture.mappingCids, sends,
      loseReply(memberIndex, rowIndex) {
        if (memberIndex !== 0 || rowIndex !== 0 || !loseFirst) return false;
        loseFirst = false;
        return true;
      }};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 5),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = () => protectedHost(undefined, {
      accountConfiguration: effectCommitConfiguration(),
      observe: (name, detail) => diagnostics.push({name, detail}),
    });
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submitted = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json',
        requestId: 'effect-reply-loss-a'});
    await waitFor(async () => (await submitted.status()).status ===
      'waiting_checkpoint');
    const [checkpoint] = (await (await first.as('reviewer-token'))
      .checkpoints()).items;
    await first.close();
    const answered = await remoteHost(t, {...account(),
      resumeAfterAnswer: false}, {directory, effectInstallation});
    const reviewer = await answered.as('reviewer-token');
    const result = await reviewer.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer: {...signer,
        authorityScopeCid: submitted.ref.authorityScopeCid}});
    assert.deepEqual(result.results.map(item => item.status), ['committed']);
    await answered.close();
    const active = await remoteHost(t, account(), {directory,
      effectInstallation});
    const activeClient = await active.as('owner-token');
    const activeRun = await activeClient.attach(submitted.ref);
    await waitFor(async () => (await activeRun.status()).status ===
      'needs_reconciliation').catch(async error => {
      error.message = JSON.stringify({state: await activeRun.status(),
        sends, diagnostics: diagnostics.slice(-5)});
      throw error;
    });
    assert.deepEqual(sends, [[0, 0]], JSON.stringify(diagnostics));
    const closedActive = await active.close();
    assert.equal(closedActive.storeCleanupPending, false,
      JSON.stringify(diagnostics.slice(-5)));
    const holdingRoot = join(directory, 'state', 'publication',
      'physical-holdings');
    const holdingFiles = await readdir(holdingRoot);
    const holdings = await Promise.all(holdingFiles.map(async file =>
      JSON.parse(await readFile(join(holdingRoot, file), 'utf8'))));
    assert.ok(holdings.some(item => item.namespace === 'effect-capture'));
    assert.ok(holdings.some(item => item.namespace === 'effect-source'));
    const recovered = await remoteHost(t, account(), {directory,
      effectInstallation}).catch(error => {
        throw error.primaryFailure ?? error;
      });
    const attached = await (await recovered.as('owner-token'))
      .attach(submitted.ref);
    const state = await waitFor(async () => {
      const current = await attached.status();
      return current.status === 'needs_reconciliation' ? current : undefined;
    }).catch(async error => {
      error.message = JSON.stringify({state: await attached.status(),
        sends, diagnostics: diagnostics.slice(-5)});
      throw error;
    });
    assert.equal(state.status, 'needs_reconciliation');
    assert.deepEqual(sends, [[0, 0]]);
    await recovered.close();
  });

test('installed Effect keeps independent members after a halted row',
  async t => {
    const fixture = await effectFixture({twoMembers: true});
    const directory = await mkdtemp(join(scratch, 'effect-row-failure-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends,
      failRow: (memberIndex, rowIndex) => memberIndex === 0 &&
        rowIndex === 0};
    const effectInstallation = createInstalledEffectSite({
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 7),
      prepareCaptured: facts => prepareReferenceCapture(facts, hooks),
      prepareRecovered: facts => prepareReferenceRecovery(facts, hooks),
    });
    const account = () => protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration()});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submitted = await (await first.as('owner-token'))
      .aql(fixture.document, {format: 'json', requestId: 'row-failure-a'});
    await waitFor(async () => (await submitted.status()).status ===
      'waiting_checkpoint');
    assert.deepEqual(sends, []);
    const [checkpoint] = (await (await first.as('reviewer-token'))
      .checkpoints()).items;
    await first.close();
    const answering = await remoteHost(t,
      {...account(), resumeAfterAnswer: false}, {directory,
        effectInstallation});
    const answered = await (await answering.as('reviewer-token'))
      .resolveCheckpoints([{checkpoint, decision: 'approved'}],
        {signer: {...signer,
          authorityScopeCid: submitted.ref.authorityScopeCid}});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    await answering.close();
    const running = await remoteHost(t, account(), {directory,
      effectInstallation});
    const failed = await (await running.as('owner-token'))
      .attach(submitted.ref);
    const state = await waitFor(async () => {
      const current = await failed.status();
      return current.status === 'failed' ? current : undefined;
    });
    assert.equal(state.result_available, false);
    assert.deepEqual(sends, [[0, 0], [1, 0], [1, 1]]);
    assert.equal((await running.close()).storeCleanupPending, false);
    const holdingRoot = join(directory, 'state', 'publication',
      'physical-holdings');
    const holdingFiles = await readdir(holdingRoot);
    assert.deepEqual(await Promise.all(holdingFiles.map(async file =>
      JSON.parse(await readFile(join(holdingRoot, file), 'utf8')))), []);
    const restarted = await remoteHost(t, account(), {directory,
      effectInstallation});
    assert.equal((await (await (await restarted.as('owner-token'))
      .attach(submitted.ref)).status()).status, 'failed');
    assert.deepEqual(sends, [[0, 0], [1, 0], [1, 1]]);
    await restarted.close();
  });

test('installed Effect commit resumes the same Run without resending',
  async t => {
    const fixture = await effectFixture();
    const registry = await readFile(join(repository,
      'spec/dependencies/aoa-pipeline-registry.json'), 'utf8');
    const aoa = JSON.parse(await readFile(join(repository,
      'spec/contracts/actql-aoa.json'), 'utf8'));
    const values = JSON.stringify(aoa.execution_contracts['REL.values']);
    const directory = await mkdtemp(join(scratch, 'effect-commit-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const subjectFor = ref => contentCid({effect: 'save',
      runDefinitionCid: ref.runDefinitionCid});
    const effectScope = {connection: 'reference', resource: 'records',
      operation: 'effect'};
    let computes = 0;
    let sends = 0;
    let resumed = 0;
    const diagnostics = [];
    const effectInstallation = {
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async execute({owner: checkedOwner, moon, control, ref, runDefinition,
        publicationPlan, effectAuthorization, retainExecution}) {
        computes++;
        assert.equal(publicationPlan.runDefinition.identity,
          runDefinition.identity);
        assert.equal(publicationPlan.results.length, 1);
        assert.ok(publicationPlan.invocation.identity);
        const subjectCid = subjectFor(ref);
        const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
          checkedOwner, registry, values, 1n, 0n, 0n, 0n);
        assert.ok(setup);
        const execution = await runCapturedEffectComputation(setup);
        retainExecution(execution);
        const runId = control.runDefinitionRunId(runDefinition);
        const gate = await effectAuthorization({runId,
          runDefinitionCid: runDefinition.identity, unitId: 'values',
          declaredResults: ['answer'],
          reviewWire: canonicalJson({effect: 'save', rows: 2}),
          continuationWire: canonicalJson({subjectCid}),
          beforeDefer: () => execution.close()});
        try {
          const decision = await gate.authorize('effect_commit',
            effectScope, {subjectCid});
          assert.equal(decision.action, 'waiting');
        } finally { gate.close(); }
        return {status: 'waiting_checkpoint'};
      },
      async resume({ref, view, continuation, effectAuthorization,
        recoverCapture,
        checkpointJournal, checkpointBinding, retainExecution}) {
        resumed++;
        retainExecution({async close() {}, async cleanup() { return true; },
          cleanupPending() { return false; }});
        const subjectCid = subjectFor(ref);
        assert.equal(continuation.subjectCid, subjectCid);
        await assert.rejects(recoverCapture(),
          {code: 'CompletedEffectfulCaptureUnavailable'});
        const claimed = checkpointJournal.claimResume(view.runId, {
          claimant: 'installed-effect-host', leaseMs: 60_000,
          binding: checkpointBinding});
        if (claimed.action !== 'claimed') return claimed;
        const gate = await effectAuthorization({runId: view.runId,
          runDefinitionCid: view.runDefinitionCid, unitId: 'values',
          declaredResults: ['answer'], reviewWire: '{}',
          continuationWire: '{}', beforeDefer() {
            assert.fail('A resumed Effect must not create another Checkpoint');
          }});
        try {
          const decision = await gate.resume('effect_commit', effectScope,
            {subjectCid, resumption: {claim: claimed}});
          assert.equal(decision.action, 'dispatch');
          decision.admission.enter(`effect-commit:${view.runId}`);
          sends++;
          const updatedAt = new Date().toISOString();
          checkpointJournal.completeResume(claimed.claim, {
            runStateWire: canonicalJson({version: 'actql-run-state/0.1',
              run_id: view.runId, status: 'needs_reconciliation', updated_at:
                updatedAt, next_action: {kind: 'reconcile', effects: ['save']},
              result_available: false, result_availability: {
                answer: {state: 'unavailable', observed_at: updatedAt,
                  reason: 'not_published'}}}),
          });
          return {status: 'sent_reply_unknown'};
        } finally { gate.close(); }
      },
    };
    const authorization = {...protectedHost(undefined, {
      observe: (name, detail) => {
        diagnostics.push({name, detail});
      }}),
    accountConfiguration: effectCommitConfiguration()};
    const first = await remoteHost(t, authorization,
      {directory, effectInstallation}).catch(error => {
        throw error.primaryFailure ?? error;
      });
    const client = await first.as('owner-token');
    const execution = await client.aql(fixture.document, {format: 'json',
      requestId: 'effect-commit-a'});
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint');
    assert.equal(computes, 1);
    assert.equal(sends, 0);
    const originalRef = execution.ref;
    await first.close();
    const second = await remoteHost(t, {...authorization,
      resumeAfterAnswer: false},
      {directory, effectInstallation});
    const reviewer = await second.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    const answered = await reviewer.resolveCheckpoints([
      {checkpoint, decision: 'approved'}],
    {signer: {...signer, authorityScopeCid: originalRef.authorityScopeCid}});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    assert.equal(sends, 0);
    assert.equal(resumed, 0);
    await second.close();
    const third = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const thirdReviewer = await third.as('reviewer-token');
    const restartedClient = await third.as('owner-token');
    const found = await restartedClient.lookupRequest('effect-commit-a');
    assert.deepEqual(found.ref, originalRef);
    await waitFor(async () => (await (await restartedClient.attach(
      originalRef)).status()).status === 'needs_reconciliation').catch(
      async error => {
        const state = await (await restartedClient.attach(originalRef)).status();
        throw Object.assign(error, {message: JSON.stringify({state,
          computes, sends, resumed, diagnostics})});
      });
    assert.equal(computes, 1);
    assert.equal(sends, 1);
    assert.equal(resumed, 1);
    const duplicate = await thirdReviewer.resolveCheckpoints(answered.signed);
    assert.deepEqual(duplicate.results.map(item => item.status),
      ['duplicate']);
    assert.deepEqual((await restartedClient.aql(fixture.document,
      {format: 'json', requestId: 'effect-commit-a'})).ref, originalRef);
    await third.close();
    const fourth = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const lastClient = await fourth.as('owner-token');
    assert.equal((await (await lastClient.attach(originalRef)).status()).status,
      'needs_reconciliation');
    assert.equal(sends, 1);
    assert.equal(computes, 1);
    const cancelledRun = await lastClient.aql(fixture.document,
      {format: 'json', requestId: 'effect-cancel-a'});
    await waitFor(async () => (await cancelledRun.status()).status ===
      'waiting_checkpoint');
    const waiting = (await (await fourth.as('reviewer-token'))
      .checkpoints()).items;
    assert.equal(waiting.length, 1);
    await cancelledRun.cancel();
    await waitFor(async () => (await cancelledRun.status()).status ===
      'cancelled');
    assert.deepEqual((await (await fourth.as('reviewer-token'))
      .checkpoints()).items, []);
    assert.equal(sends, 1);
    assert.equal(computes, 2);
    const approvedThenCancelled = await lastClient.aql(fixture.document,
      {format: 'json', requestId: 'effect-approved-cancel-a'});
    await waitFor(async () => (await approvedThenCancelled.status()).status ===
      'waiting_checkpoint');
    await fourth.close();
    const fifth = await remoteHost(t, {...authorization,
      resumeAfterAnswer: false}, {directory, effectInstallation});
    const fifthReviewer = await fifth.as('reviewer-token');
    const [approvedCheckpoint] = (await fifthReviewer.checkpoints()).items;
    const approval = await fifthReviewer.resolveCheckpoints([
      {checkpoint: approvedCheckpoint, decision: 'approved'}],
    {signer: {...signer, authorityScopeCid:
      approvedThenCancelled.ref.authorityScopeCid}});
    assert.deepEqual(approval.results.map(item => item.status),
      ['committed']);
    assert.equal(sends, 1);
    const fifthOwner = await fifth.as('owner-token');
    await (await fifthOwner.attach(approvedThenCancelled.ref)).cancel();
    await waitFor(async () => (await (await fifthOwner.attach(
      approvedThenCancelled.ref)).status()).status === 'cancelled');
    await fifth.close();
    const sixth = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const sixthOwner = await sixth.as('owner-token');
    assert.equal((await (await sixthOwner.attach(
      approvedThenCancelled.ref)).status()).status, 'cancelled');
    assert.equal(sends, 1);
    assert.equal(computes, 3);
    await sixth.close();
  });

test('deferred target read starts no Effect and leaves no held Checkpoint',
  async t => {
    const fixture = await effectFixture();
    const directory = await mkdtemp(join(scratch, 'effect-read-deferred-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let reads = 0;
    let sends = 0;
    const effectInstallation = {
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async execute({control, runDefinition, effectAuthorization,
        retainExecution}) {
        retainExecution({async close() {}, async cleanup() { return true; },
          cleanupPending() { return false; }});
        const gate = await effectAuthorization({runId:
          control.runDefinitionRunId(runDefinition),
        runDefinitionCid: runDefinition.identity, unitId: 'values',
        declaredResults: ['answer'], reviewWire: '{}',
        continuationWire: '{}', beforeDefer() {
          assert.fail('Target-read deferral must not persist a Checkpoint');
        }});
        try {
          const decision = await gate.authorize('acquisition',
            {connection: 'reference', resource: 'records', operation: 'read'},
            {subjectCid: contentCid({target: 'read-before-effect'})});
          if (decision.action === 'dispatch') {
            reads++;
            sends++;
            assert.fail('Deferred read must not reach the physical Site');
          }
          assert.equal(decision.action, 'unsupported');
          return {status: 'failed_without_effect_dispatch'};
        } finally { gate.close(); }
      },
      async resume() { sends++; assert.fail('No resume is available'); },
    };
    const authorization = {...protectedHost(),
      accountConfiguration: effectCommitConfiguration('delegate')};
    const host = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const client = await host.as('owner-token');
    const run = await client.aql(fixture.document,
      {format: 'json', requestId: 'effect-target-read-deferred'});
    const state = await waitFor(async () => {
      const current = await run.status();
      return current.status === 'running' ? false : current;
    });
    assert.equal(state.status, 'failed');
    assert.equal(reads, 0);
    assert.equal(sends, 0);
    assert.deepEqual((await (await host.as('reviewer-token'))
      .checkpoints()).items, []);
    await host.close();
    const restarted = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const owner = await restarted.as('owner-token');
    assert.equal((await (await owner.attach(run.ref)).status()).status,
      'failed');
    assert.equal(reads, 0);
    assert.equal(sends, 0);
    await restarted.close();
  });

test('rejected answers end the request without a Run; answers are per item',
  async t => {
    const host = await remoteHost(t, protectedHost('delegate'));
    const client = await host.as('owner-token');
    for (const requestId of ['batch-a', 'batch-b']) {
      const changed = JSON.parse(document);
      changed.id = requestId;
      await assert.rejects(client.aql(JSON.stringify(changed),
        {format: 'json', requestId}), error => error instanceof RequestHeld);
    }
    const reviewer = await host.as('reviewer-token');
    const {items} = await reviewer.checkpoints({limit: 1});
    assert.equal(items.length, 1);
    const page = await reviewer.checkpoints({limit: 1});
    const rest = await reviewer.checkpoints({after: page.next, limit: 5});
    const [first, second] = [...page.items, ...rest.items];
    assert.notEqual(first.checkpointCid, second.checkpointCid);
    const rejected = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'rejected'}], {signer});
    assert.deepEqual(rejected.results.map(item => item.status),
      ['committed']);
    // A contradicting answer for the same Checkpoint, and a new one for the
    // second, in one batch: each result stands on its own.
    const mixed = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'approved'},
      {checkpoint: second, decision: 'rejected'}], {signer});
    assert.deepEqual(mixed.results.map(item => item.status),
      ['conflicting', 'committed']);
    for (const summary of [first, second]) {
      const lookup = await client.lookupRequest(summary.subject.requestId);
      assert.equal(lookup.state, 'ended');
      assert.equal(lookup.endReason, 'rejected');
    }
    assert.equal(host.dispatches(), 0);
  });

async function heldRequests(client, ids) {
  for (const requestId of ids) {
    const changed = JSON.parse(document);
    changed.id = requestId;
    await assert.rejects(client.aql(JSON.stringify(changed),
      {format: 'json', requestId}), error => error instanceof RequestHeld);
  }
}
async function allCheckpoints(reviewer) {
  const items = [];
  let after;
  do {
    const page = await reviewer.checkpoints({after, limit: 100});
    items.push(...page.items);
    after = page.next;
  } while (after !== undefined);
  return items;
}
async function approveAll(reviewer, items) {
  for (let index = 0; index < items.length; index += 16) {
    const answered = await reviewer.resolveCheckpoints(items.slice(index,
      index + 16).map(checkpoint => ({checkpoint, decision: 'approved'})),
    {signer});
    assert.ok(answered.results.every(item => item.status === 'committed'));
  }
}
async function succeeded(client, requestId) {
  const found = await waitFor(async () => {
    const lookup = await client.lookupRequest(requestId);
    return lookup.kind === 'found' ? lookup : undefined;
  });
  const execution = await client.attach(found.ref);
  return waitFor(async () => (await execution.wait()).status === 'succeeded');
}

// The first claim stalls while a second request is approved; nothing else
// (no submit, answer, lease retry or restart) wakes the Host afterwards.
async function stalledSweep(t, {leaseMs, stallMs}) {
  const steps = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {
    leaseMs,
    async faultInjection(name) {
      steps.push(name);
      if (name === 'resume_claimed' && stall) {
        stall = false;
        await stalled;
      }
    }}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  await heldRequests(client, ['race-a', 'race-b']);
  const [first, second] = await allCheckpoints(reviewer);
  await approveAll(reviewer, [first]);
  await waitFor(() => steps.includes('resume_claimed'));
  await approveAll(reviewer, [second]);
  await new Promise(resolve => setTimeout(resolve, stallMs));
  released();
  for (const requestId of ['race-a', 'race-b']) {
    assert.equal(await succeeded(client, requestId), true, requestId);
  }
  assert.equal(host.dispatches(), 2);
  assert.equal(steps.filter(name => name === 'computed').length, 2);
}

test('an answer committed during a resume is not lost', async t => {
  // The lease stays live: only the recorded wake continues the second one.
  await stalledSweep(t, {leaseMs: 60_000, stallMs: 100});
});

test('a claim whose lease lapsed sends nothing and is retried by the Host',
  async t => {
    await stalledSweep(t, {leaseMs: 1000, stallMs: 1200});
  });

test('more than one page of approved requests resumes at Host start',
  async t => {
    // Pages of 5 over 12 requests: the same continuation as 101 requests
    // over the default page of 100.
    const count = 12;
    const ids = Array.from({length: count}, (_, index) =>
      `start-${String(index).padStart(3, '0')}`);
    const directory = await mkdtemp(join(scratch, 'restart-'));
    const answering = await remoteHost(t, protectedHost('delegate',
      {resumeAfterAnswer: false, sweepPage: 5}), {directory});
    const client = await answering.as('owner-token');
    const reviewer = await answering.as('reviewer-token');
    await heldRequests(client, ids);
    const items = await allCheckpoints(reviewer);
    assert.equal(items.length, count);
    await approveAll(reviewer, items);
    assert.equal(answering.dispatches(), 0);
    await answering.close();
    const restarted = await remoteHost(t, protectedHost('delegate',
      {sweepPage: 5}), {directory});
    const owner = await restarted.as('owner-token');
    for (const requestId of ids) {
      assert.equal(await succeeded(owner, requestId), true, requestId);
    }
    assert.equal(restarted.dispatches(), count);
    await restarted.close();
    await rm(directory, {recursive: true, force: true});
  });

test('a lost or corrupt request index is rebuilt from the held evidence',
  async t => {
    const directory = await mkdtemp(join(scratch, 'index-'));
    const first = await remoteHost(t, protectedHost('delegate'),
      {directory});
    const client = await first.as('owner-token');
    await heldRequests(client, ['index-a', 'index-b']);
    await first.close();
    const index = join(directory, 'state', 'checkpoints', 'held');
    const files = (await readdir(index)).filter(name =>
      name.endsWith('.json')).sort();
    assert.equal(files.length, 2);
    await rm(join(index, files[0]));
    await writeFile(join(index, files[1]), '{not json');
    const second = await remoteHost(t, protectedHost('delegate'),
      {directory});
    // After both Hosts' own cleanup.
    t.after(() => rm(directory, {recursive: true, force: true}));
    const reviewer = await second.as('reviewer-token');
    const items = await allCheckpoints(reviewer);
    assert.deepEqual(items.map(item => item.subject.requestId).sort(),
      ['index-a', 'index-b']);
    // The rebuilt entries are durable again.
    assert.deepEqual((await readdir(index)).filter(name =>
      name.endsWith('.json')).sort(), files);
    await approveAll(reviewer, items);
    const owner = await second.as('owner-token');
    for (const requestId of ['index-a', 'index-b']) {
      assert.equal(await succeeded(owner, requestId), true, requestId);
    }
    await second.close();
  });

test('closing during a resumed dispatch records its end before releasing',
  async t => {
    const directory = await mkdtemp(join(scratch, 'close-'));
    const steps = [];
    let released;
    const stalled = new Promise(resolve => { released = resolve; });
    const host = await remoteHost(t, protectedHost('delegate', {
      async faultInjection(name) {
        steps.push(name);
        if (name === 'physical_start_reserved') await stalled;
      }}), {directory});
    // After the Host's own cleanup.
    t.after(() => rm(directory, {recursive: true, force: true}));
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    await heldRequests(client, ['close-a']);
    await approveAll(reviewer, await allCheckpoints(reviewer));
    await waitFor(() => steps.includes('physical_start_reserved'));
    const closing = host.close();
    released();
    await closing;
    assert.ok(steps.includes('computed'));
    // The journal Run ended with the dispatch; no later start is needed.
    const database = new DatabaseSync(join(directory, 'state',
      'checkpoints', 'journal', 'checkpoint-journal.sqlite3'),
    {readOnly: true});
    try {
      assert.deepEqual(database.prepare('SELECT status FROM runs').all()
        .map(row => row.status), ['succeeded']);
    } finally { database.close(); }
    const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
    for (const file of await readdir(ledgers)) {
      const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
      assert.ok(ledger.holdings.filter(item =>
        item.name !== 'invocation_request').every(item =>
        item.state === 'retired'), file);
    }
  });

// DCI-R7: submitting a held request again never starts it outside the
// resumed authorization. The Host's resume is stalled after the Run
// Definition exists and before its physical start; meanwhile the owner
// submits the same request.
async function resubmittedWhileStalled(t, {leaseMs = 60_000,
  checkpointTtlMs, wait = 0, untilExpired = false}) {
  const steps = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {
    leaseMs, ...(checkpointTtlMs === undefined ? {} : {checkpointTtlMs}),
    async faultInjection(name) {
      steps.push(name);
      if (name === 'definition_admitted' && stall) {
        stall = false;
        await stalled;
      }
    }}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  await heldRequests(client, ['again-a']);
  const items = await allCheckpoints(reviewer);
  await approveAll(reviewer, items);
  await waitFor(() => steps.includes('definition_admitted'));
  // Past the Checkpoint's own answer deadline (which bounds the approval),
  // measured from the Host's record rather than from test start.
  const until = untilExpired ? Date.parse(items[0].expiresAt) + 300
    : Date.now() + wait;
  await new Promise(resolve => setTimeout(resolve,
    Math.max(0, until - Date.now())));
  const changed = JSON.parse(document);
  changed.id = 'again-a';
  const again = await client.aql(JSON.stringify(changed), {format: 'json',
    requestId: 'again-a'});
  // The resubmit returns the existing Run and starts nothing by itself.
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.equal(steps.filter(name => name === 'physical_start_reserved')
    .length, 0);
  assert.equal(host.dispatches(), 0);
  released();
  const state = await waitFor(async () => {
    const current = await again.wait();
    return ['succeeded', 'failed', 'cancelled'].includes(current.status)
      ? current : undefined;
  });
  return {state, starts: steps.filter(name =>
    name === 'physical_start_reserved').length, steps};
}

test('a resubmit of a held request after its approval expired starts nothing',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t,
      {checkpointTtlMs: 8000, untilExpired: true});
    assert.equal(starts, 0);
    assert.equal(state.status, 'failed');
  });

test('a resubmit during a valid resume starts the Run at most once',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t, {});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
  });

test('a resubmit while the resuming claim lapses starts the Run once',
  async t => {
    const {state, starts, steps} = await resubmittedWhileStalled(t,
      {leaseMs: 1000, wait: 1300});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
    // The lapsed claim started nothing; a later claim did.
    assert.ok(steps.filter(name => name === 'resume_claimed').length >= 2);
  });

// DCI-R8: a held request's intent is always compared before its held state
// or Run is returned, and unavailable evidence is an error, never a pass.
test('a held request resubmit is matched to its intent, whatever the evidence',
  async t => {
    const directory = await mkdtemp(join(scratch, 'intent-'));
    const host = await remoteHost(t, protectedHost('delegate'),
      {directory});
    // Registered after the Host's own cleanup, so it runs after close.
    t.after(async () => {
      await chmod(join(directory, 'state', 'checkpoints', 'attempts'), 0o700)
        .catch(() => {});
      await rm(directory, {recursive: true, force: true});
    });
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    const variant = (id, rows) => {
      const value = JSON.parse(document);
      value.id = id;
      if (rows !== undefined) value.stages[0].steps[0].values.rows = rows;
      return JSON.stringify(value);
    };
    await heldRequests(client, ['done-a', 'held-b']);
    const items = await allCheckpoints(reviewer);
    await approveAll(reviewer, items.filter(item =>
      item.subject.requestId === 'done-a'));
    assert.equal(await succeeded(client, 'done-a'), true);
    const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
    const ledgerOf = async requestId => {
      for (const file of await readdir(ledgers)) {
        const summary = items.find(item =>
          item.subject.requestId === requestId);
        if (file === `${summary.subject.prepareAttemptId}.json`) {
          return join(ledgers, file);
        }
      }
      throw new Error('LedgerNotFound');
    };
    // Normal: the same request returns the same Run; another intent conflicts.
    const found = await client.lookupRequest('done-a');
    const again = await client.aql(variant('done-a'), {format: 'json',
      requestId: 'done-a'});
    assert.deepEqual(again.ref, found.ref);
    await assert.rejects(client.aql(variant('done-a', [{id: 999}]),
      {format: 'json', requestId: 'done-a'}),
    {code: 'ClientRequestIntentConflict'});
    // A Run exists: the request journal's identity decides, even with the
    // held evidence ledger corrupt.
    await writeFile(await ledgerOf('done-a'), '{broken');
    await assert.rejects(client.aql(variant('done-a', [{id: 999}]),
      {format: 'json', requestId: 'done-a'}),
    {code: 'ClientRequestIntentConflict'});
    assert.deepEqual((await client.aql(variant('done-a'), {format: 'json',
      requestId: 'done-a'})).ref, found.ref);
    // No Run yet: the held request's durable fingerprint must be readable.
    const held = await ledgerOf('held-b');
    const original = await readFile(held);
    await assert.rejects(client.aql(variant('held-b', [{id: 999}]),
      {format: 'json', requestId: 'held-b'}),
    {code: 'ClientRequestIntentConflict'});
    const unavailable = error => error.code === 'SubmissionUnknown' &&
      error.cause?.code === 'HeldRequestEvidenceUnavailable';
    for (const [label, damage] of [
      ['corrupt', () => writeFile(held, '{broken')],
      ['missing', () => rm(held)],
      ['unreadable', async () => {
        await writeFile(held, original);
        await chmod(held, 0o000);
      }],
    ]) {
      await damage();
      for (const text of [variant('held-b'), variant('held-b', [{id: 999}])]) {
        await assert.rejects(client.aql(text, {format: 'json',
          requestId: 'held-b'}), unavailable, label);
      }
    }
    await chmod(held, 0o600);
    await writeFile(held, original);
    await assert.rejects(client.aql(variant('held-b'), {format: 'json',
      requestId: 'held-b'}), error => error instanceof RequestHeld);
    // Nothing was started by any of these submits.
    assert.equal(host.dispatches(), 1);
  });

// DCI-R9: a Run from a held request cancelled through the public Client
// before its physical start ends the held request too: no start, no more
// claims, retention released.
async function cancelledBeforeStart(t, stallAt) {
  const directory = await mkdtemp(join(scratch, 'cancel-'));
  const steps = [];
  const failures = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {
    leaseMs: 1000,
    async faultInjection(name, detail) {
      steps.push(name);
      if (name.endsWith('_failed')) failures.push({name, detail});
      if (name === stallAt && stall) {
        stall = false;
        await stalled;
      }
    }}), {directory});
  t.after(() => rm(directory, {recursive: true, force: true}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  await heldRequests(client, ['cancel-a']);
  await approveAll(reviewer, await allCheckpoints(reviewer));
  await waitFor(() => steps.includes(stallAt));
  const found = await waitFor(async () => {
    const lookup = await client.lookupRequest('cancel-a');
    return lookup.kind === 'found' ? lookup : undefined;
  });
  const execution = await client.attach(found.ref);
  await execution.cancel();
  released();
  const state = await waitFor(async () => {
    const current = await execution.status();
    return current.status === 'cancelled' ? current : undefined;
  });
  assert.equal(state.status, 'cancelled');
  // Claims stop: nothing is retried after the request settled.
  let lastPreparation;
  await waitFor(async () => {
    const database = new DatabaseSync(join(directory, 'state',
      'checkpoints', 'journal', 'checkpoint-journal.sqlite3'),
    {readOnly: true});
    try {
      lastPreparation = {...database.prepare(
        'SELECT status, end_reason FROM preparations').get()};
      return lastPreparation.status === 'ended';
    } finally { database.close(); }
  }).catch(cause => {
    throw new Error(`Cancelled preparation did not settle: ${JSON.stringify({
      preparation: lastPreparation, steps, failures})}`, {cause});
  });
  const claims = steps.filter(name => name === 'resume_claimed').length;
  await new Promise(resolve => setTimeout(resolve, 2500));
  assert.equal(steps.filter(name => name === 'resume_claimed').length,
    claims);
  assert.equal(steps.filter(name =>
    name === 'physical_start_reserved').length, 0);
  assert.equal(host.dispatches(), stallAt === 'dispatch_reserved' ? 1 : 0);
  await host.close();
  const database = new DatabaseSync(join(directory, 'state', 'checkpoints',
    'journal', 'checkpoint-journal.sqlite3'), {readOnly: true});
  try {
    assert.deepEqual({...database.prepare(
      'SELECT status, end_reason FROM preparations').get()},
    {status: 'ended', end_reason: 'cancelled'});
    assert.deepEqual(database.prepare(
      'SELECT state FROM resume_intents').all().map(row => row.state),
    ['completed']);
    assert.equal(database.prepare('SELECT COUNT(*) AS n FROM runs').get().n,
      0);
  } finally { database.close(); }
  const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
  for (const file of await readdir(ledgers)) {
    const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
    assert.ok(ledger.holdings.filter(item =>
      item.name !== 'invocation_request').every(item =>
      item.state === 'retired'), file);
  }
}

test('a Run cancelled after its definition ends the held request', async t => {
  await cancelledBeforeStart(t, 'definition_admitted');
});

test('a Run cancelled after its dispatch reservation ends the held request',
  async t => {
    await cancelledBeforeStart(t, 'dispatch_reserved');
  });

// D-next-1: cancelling a held request by its ID through the public Client.
function journalRows(directory, sql) {
  const database = new DatabaseSync(join(directory, 'state', 'checkpoints',
    'journal', 'checkpoint-journal.sqlite3'), {readOnly: true});
  try { return database.prepare(sql).all().map(row => ({...row})); }
  finally { database.close(); }
}
async function holdingStates(directory) {
  const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
  const states = [];
  // Ledgers are replaced by atomic rename; a temporary file is not one.
  for (const file of (await readdir(ledgers)).filter(name =>
    name.endsWith('.json'))) {
    const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
    states.push(...ledger.holdings.filter(item =>
      item.name !== 'invocation_request').map(item => item.state));
  }
  return [...new Set(states)];
}
async function stalledHost(t, {stallAt, extra = {}} = {}) {
  const directory = await mkdtemp(join(scratch, 'cancel-request-'));
  const steps = [];
  let stall = stallAt !== undefined;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {leaseMs: 1000,
    ...extra,
    async faultInjection(name) {
      steps.push(name);
      if (name === stallAt && stall) {
        stall = false;
        await stalled;
      }
    }}), {directory});
  t.after(() => rm(directory, {recursive: true, force: true}));
  return {directory, steps, host, release: () => released(),
    client: await host.as('owner-token'),
    reviewer: await host.as('reviewer-token')};
}

test('C1/C2: a held request is cancelled by its owner and resends match',
  async t => {
    const x = await stalledHost(t);
    await heldRequests(x.client, ['cancel-a']);
    const [summary] = await allCheckpoints(x.reviewer);
    // C2: not the owner, not a request of this scope, or no such request.
    await assert.rejects(x.reviewer.cancelRequest('cancel-a'),
      {code: 'ClientConnectionDenied'});
    await assert.rejects(x.client.cancelRequest('no-such-request'),
      {code: 'ClientRequestNotFound'});
    assert.equal((await x.client.lookupRequest('cancel-a')).state,
      'waiting_checkpoint');
    // C1: durable cancellation; a lost reply is resent and matched.
    const real = globalThis.fetch;
    let dropped = false;
    globalThis.fetch = async (url, init) => {
      const response = await real(url, init);
      if (!dropped && String(url).endsWith('/cancel-request')) {
        dropped = true;
        await response.body?.cancel();
        throw new TypeError('reply lost');
      }
      return response;
    };
    try {
      await assert.rejects(x.client.cancelRequest('cancel-a'), error =>
        error.code === 'CancellationUnknown' &&
          error.requestId === 'cancel-a');
    } finally { globalThis.fetch = real; }
    assert.deepEqual(await x.client.cancelRequest('cancel-a'),
      {requestId: 'cancel-a', kind: 'already_requested'});
    const lookup = await x.client.lookupRequest('cancel-a');
    assert.equal(lookup.state, 'ended');
    assert.equal(lookup.endReason, 'cancelled');
    // A late answer does not resume it.
    const late = await x.reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    assert.equal(late.results[0].status, 'cancelled');
    await waitFor(async () => (await holdingStates(x.directory))
      .every(state => state === 'retired'));
    assert.equal(x.steps.filter(name => name === 'resume_claimed').length, 0);
    assert.equal(x.host.dispatches(), 0);
  });

// C3: cancellation racing the resume: after the claim (no Run yet), after
// the Run Definition exists, and after the dispatch reservation.
for (const [label, stallAt, withRun] of [
  ['after the claim', 'resume_claimed', false],
  ['after the Run Definition', 'definition_admitted', true],
  ['after the dispatch reservation', 'dispatch_reserved', true],
]) {
  test(`C3: a request cancelled ${label} never starts`, async t => {
    const x = await stalledHost(t, {stallAt});
    await heldRequests(x.client, ['race-a']);
    await approveAll(x.reviewer, await allCheckpoints(x.reviewer));
    await waitFor(() => x.steps.includes(stallAt));
    const cancelled = await x.client.cancelRequest('race-a');
    assert.equal(cancelled.kind, 'accepted');
    // With a Run the cancellation names it: the same Run is cancelled.
    assert.equal(cancelled.ref !== undefined, withRun);
    x.release();
    await waitFor(() => journalRows(x.directory,
      'SELECT status FROM preparations')[0].status === 'ended');
    assert.deepEqual(journalRows(x.directory,
      'SELECT status, end_reason FROM preparations'),
    [{status: 'ended', end_reason: 'cancelled'}]);
    const claims = x.steps.filter(name => name === 'resume_claimed').length;
    await new Promise(resolve => setTimeout(resolve, 1500));
    assert.equal(x.steps.filter(name => name === 'resume_claimed').length,
      claims);
    assert.equal(x.steps.filter(name =>
      name === 'physical_start_reserved').length, 0);
    if (withRun) {
      const execution = await x.client.attach(cancelled.ref);
      assert.equal((await execution.status()).status, 'cancelled');
    }
    await waitFor(async () => (await holdingStates(x.directory))
      .every(state => state === 'retired'));
  });
}

test('C4: a cancellation recorded before a restart settles on the next start',
  async t => {
    const directory = await mkdtemp(join(scratch, 'cancel-restart-'));
    const answering = await remoteHost(t, protectedHost('delegate',
      {resumeAfterAnswer: false, leaseMs: 1000}), {directory});
    const client = await answering.as('owner-token');
    const reviewer = await answering.as('reviewer-token');
    await heldRequests(client, ['restart-a']);
    await approveAll(reviewer, await allCheckpoints(reviewer));
    assert.equal((await client.cancelRequest('restart-a')).kind, 'accepted');
    // Resuming and cancel-requested: recorded, not yet settled.
    assert.deepEqual(journalRows(directory,
      'SELECT status, cancel_requested FROM preparations'),
    [{status: 'resuming', cancel_requested: 1}]);
    await answering.close();
    const steps = [];
    const restarted = await remoteHost(t, protectedHost('delegate', {
      leaseMs: 1000, faultInjection: name => { steps.push(name); }}), {directory});
    t.after(() => rm(directory, {recursive: true, force: true}));
    await waitFor(() => journalRows(directory,
      'SELECT status FROM preparations')[0].status === 'ended');
    assert.deepEqual(journalRows(directory,
      'SELECT end_reason FROM preparations'), [{end_reason: 'cancelled'}]);
    assert.deepEqual(journalRows(directory,
      'SELECT state FROM resume_intents').map(row => row.state),
    ['completed']);
    await waitFor(async () => (await holdingStates(directory))
      .every(state => state === 'retired'));
    const claims = steps.filter(name => name === 'resume_claimed').length;
    await new Promise(resolve => setTimeout(resolve, 1500));
    assert.equal(steps.filter(name => name === 'resume_claimed').length,
      claims);
    assert.equal(restarted.dispatches(), 0);
  });

test('C5: a cancellation after the physical start reservation releases nothing early',
  async t => {
    const x = await stalledHost(t, {stallAt: 'physical_start_reserved'});
    await heldRequests(x.client, ['started-a']);
    await approveAll(x.reviewer, await allCheckpoints(x.reviewer));
    await waitFor(() => x.steps.includes('physical_start_reserved'));
    const cancelled = await x.client.cancelRequest('started-a');
    assert.equal(cancelled.kind, 'accepted');
    assert.ok(cancelled.ref !== undefined);
    // The start was reserved first: the Run is not settled or released by
    // the request alone.
    await new Promise(resolve => setTimeout(resolve, 300));
    assert.deepEqual(journalRows(x.directory,
      'SELECT status FROM preparations'), [{status: 'run_created'}]);
    assert.deepEqual(journalRows(x.directory, 'SELECT status FROM runs'),
      [{status: 'running'}]);
    assert.deepEqual(await holdingStates(x.directory), ['held']);
    x.release();
    // The existing stop and publication owners decide its end. The held
    // request's journal Run ends and its evidence is released only when the
    // Run is observed terminal; with its physical stop unknown both stay.
    const execution = await x.client.attach(cancelled.ref);
    await new Promise(resolve => setTimeout(resolve, 1500));
    const current = await execution.status();
    const [run] = journalRows(x.directory, 'SELECT status FROM runs');
    if (['succeeded', 'failed', 'cancelled'].includes(current.status)) {
      await waitFor(async () => (await holdingStates(x.directory))
        .every(item => item === 'retired'));
      assert.equal(journalRows(x.directory, 'SELECT status FROM runs')[0]
        .status, current.status);
    } else {
      assert.equal(current.control.physical_stop, 'unknown');
      assert.equal(run.status, 'running');
      assert.deepEqual(await holdingStates(x.directory), ['held']);
    }
  });
