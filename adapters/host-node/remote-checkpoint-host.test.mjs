import {writeSyntheticHistoricalHeldQuery} from '../../scripts/fixtures/synthetic-historical-held-query.mjs';
import {writeSyntheticHistoricalHeldValues} from '../../scripts/fixtures/synthetic-historical-held-values.mjs';
// The installed Remote Host with Run-acceptance protection, driven through
// the public Client over HTTPS: allow, deny and missing configuration,
// immediate Host answers, and a held request that is reviewed, answered and
// resumed by the Host. The packed, multi-process acceptance is
// scripts/test-packed-client-checkpoint.mjs.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {nodeTestArguments} from '../../scripts/test-execution.mjs';
import {assertPartialEffectSeedExit} from './fixtures/effect-crash-evidence.mjs';
import {referenceEffectManagedFixture} from './fixtures/reference-effect-managed.fixture.mjs';
import {checkpointEffectReviewDouble} from './fixtures/checkpoint-effect-review.fixture.mjs';
import {createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign} from 'node:crypto';
import {chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from
  'node:fs/promises';
import {writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {fileURLToPath} from 'node:url';
import {types as utilTypes} from 'node:util';
import {errorMonitor} from 'node:events';
import {connect, RequestHeld, explainRequestLookup, explainSubmission, explainRequestCancellation,
  getSubmissionOutcome, getSubmissionAttempt} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {localContractLimits, localOutputLimits} from './local-values-plan.mjs';
import {exportPinnedEffectInput, preparePinnedEffectSourceHoldings,
  preparePinnedEffectSourceSet, retainPinnedEffectDependencyPayloads}
  from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issuedEffectSetReceiptWires} from '../host-common/effect-receipt-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueCompletedEffectfulComputationEvidence,
  storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {exercisePublicQueryInput} from '../../scripts/fixtures/public-query-input.mjs';
import {loadTwoSourceFixtures, installTwoSourceFixtures, observeTwoSourceProvider}
  from '../../scripts/fixtures/two-source-public-query.mjs';

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
const duckdb = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');
const {DuckDBInstance, DuckDBPreparedStatement} = duckdb;
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
  // This installed adapter supports the bounded broad-receipt realization
  // as well as native two-receipt acquisition. Do not infer that capability
  // from a native-only saved declaration.
  environment.connector_capabilities[0].capability_contract_cids.push(
    'sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d');
  environment.connector_capabilities[0].capability_contract_cids.sort();
  environment.evidence_bundle_cid = withoutCid(environment,
    'evidence_bundle_cid');
  const profilePath = join(directory, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify({
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
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

// A valid non-DuckDB installation that needs no process, Catalog read or
// credentials until selected. The absent interpreter makes accidental reads
// fail; successful selected-source tests cannot silently use this member.
async function unusedTableFixture(directory, name = 'unused-table') {
  const schemaWire = '{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}}';
  const catalogCid = contentCid({fixture: name});
  const path = join(directory, `${name}.json`);
  await writeFile(path, JSON.stringify({
    version: 'actql-installed-local-table-source/0.1', connectorId: name, connection: name,
    python: join(directory, 'uninstalled-python'),
    catalog: {database: join(directory, `${name}.db`), warehouse: join(directory, name),
      catalogCid, limits: {bytes: 1048576, files: 16, operations: 8}},
    accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: name, entries: [{entry_id: 'read', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
    targets: [{resource: 'rows', schemaWire, selector: {
      catalog_identity_cid: catalogCid, namespace: ['unused'], table_name: 'rows',
      table_uuid: '00000000-0000-0000-0000-000000000000',
      schema_cid: 'sha256:' + createHash('sha256').update(schemaWire).digest('hex')}}],
    limits: {maxPages: 1, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16},
  }));
  return path;
}

test('public HTTP source text uses the installed alias and existing Run owner', async t => {
  const directory = await mkdtemp(join(scratch, 'source-text-'));
  const profilePath = await installedReadFixture(directory);
  const profile = JSON.parse(await readFile(profilePath, 'utf8'));
  const environment = JSON.parse(profile.checkEnvironmentWire);
  const view = environment.source_views[0];
  profile.queryAliases = [{name: 'records', sourceRef: profile.sourceRef,
    sourceViewContractCid: view.contract_cid,
    schemaContractCid: view.output.schema.cid}];
  await writeFile(profilePath, JSON.stringify(profile));
  const authorization = protectedHost('allow');
  const account = JSON.parse(authorization.accountConfiguration);
  account.entries.find(entry => entry.entry_id === 'run-acceptance')
    .resource.any_of = ['duckdb-acquired'];
  account.entries.find(entry => entry.entry_id === 'owner-read')
    .resource.any_of = ['result/main', 'run'];
  authorization.accountConfiguration = canonicalJson(account);
  const host = await remoteHost(t, authorization,
    {directory, sourceProfilePath: profilePath,
      hostCapacityPolicy: environment.host_policy_profile.capacity}).catch(error => {
      t.diagnostic(String(error.cause?.stack ?? error));
      throw error;
    });
  t.after(async () => { await host.close(); await rm(directory, {recursive: true, force: true}); });
  // Count actual native query execution, not a best-effort diagnostic or
  // dispatch reservation. This also catches any extra DuckDB computation.
  let sourceIo = 0;
  const stream = DuckDBPreparedStatement.prototype.stream;
  t.mock.method(DuckDBPreparedStatement.prototype, 'stream', function(...args) {
    sourceIo++;
    return Reflect.apply(stream, this, args);
  });
  const journal = new DatabaseSync(join(directory, 'state', 'requests',
    'client-requests.sqlite3'), {readOnly: true});
  try {
    const observe = () => ({sourceIo, acceptedRuns:
      journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count});
    await exercisePublicQueryInput(connect, host.options('owner-token'),
      {requestPrefix: 'source', observe, primaryResultName: 'main'});
    assert.equal(observe().acceptedRuns, 5);
    assert.ok(sourceIo >= 5, 'successful queries must exercise the I/O probe');
  } finally {
    journal.close();
  }
});
async function effectFixture({twoMembers = false} = {}) {
  const environment = JSON.parse(await readFile(join(repository,
    'packages/sdk/fixtures/values.environment.json'), 'utf8'));
  const base = JSON.parse(await readFile(join(repository,
    'spec/local-check-environment.json'), 'utf8'));
  environment.host_policy_profile.text_time_evaluation = base.host_policy_profile.text_time_evaluation;
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
  return {document: canonicalJson(program), effectIds: Object.keys(program.stages[0].effects), mappingCid:
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

function referenceDispatch({ledger, preview, sends, loseReply, failRow, physical, completed, stopped}) {
  return async ({memberIndex, rowIndex, claim}) => {
    sends.push([memberIndex, rowIndex]);
    const failed = failRow?.(memberIndex, rowIndex) === true;
    try {
      await captureClaimedEffectResponse({ledger, claim,
      requestCid: claim.canonicalRequestCid,
      execute: () => {
        const invoke = async () => {
          if (loseReply?.(memberIndex, rowIndex)) {
            throw new Error('ReferenceEffectReplyLost');
          }
          return {observation: {useCid: referenceCid('use'),
            statusCode: failed ? 422 : 204, body: Buffer.alloc(0)}};
        };
        return physical === undefined ? invoke() : physical({memberIndex, rowIndex}, invoke);
      }});
    } finally {
      // The bridge has ended this SAME ledger physical flight, including a
      // lost response. This reference callback launches no detached I/O.
      stopped?.({memberIndex, rowIndex});
    }
    ledger.recordAdmittedRowOutcome({claim, preview,
      memberIndex, previewRowIndex: rowIndex,
      outcomeWire: canonicalJson(failed
        ? {state: 'failed', error: {code: 'REFERENCE_REJECTED',
          message: 'Reference row rejected'}}
        : {state: 'applied',
          result: {record_id: `reference-${rowIndex}`}})});
    ledger.commitAdmittedRowOutcome({claim, preview,
      memberIndex, previewRowIndex: rowIndex});
    completed?.({memberIndex, rowIndex});
  };
}

function referenceLedger(directory, moon, requestIdentity, controlConstruction) {
  return openEffectLedger({moon, root: join(directory, 'effect-ledger'),
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(requestIdentity),
    callerRequestId: moon.clientRequestCallerId(requestIdentity),
    maxEntryBytes: 4096, controlConstruction});
}

async function prepareReferenceCapture(facts, {directory, mappingCids,
  sends, loseReply, failRow, physical, completed, stopped, controlConstruction,
  retainInputCleanup, retainStageCleanup, beginConstruction, maxInputPins = 2,
  expectedDependencyCount = maxInputPins === 3 ? 2 : undefined}) {
  const {moon, control, store, execution, publicationPlan: plan,
    prepared, checkedHost, identity} = facts;
  const storedResults = await storeCompletedRunResultSet({execution,
    store, control, runDefinition: plan.runDefinition,
    invocation: plan.invocation, results: plan.results,
    outputLimits: plan.outputLimits,
    contractLimits: plan.contractLimits});
  // Completed-output storage has its original managed Result-import owner.
  // Match captureStage: retain actual input inventory after storage, then
  // enter each capture constructor before asynchronous Source export/Preview.
  const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, maxInputPins));
  const releaseInputs = () => {moon.clientProgramReleaseEffectInputs(inputs);};
  retainInputCleanup?.(releaseInputs);
  if (beginConstruction !== undefined) {
    controlConstruction.retainInputs(inputs);
    beginConstruction();
  }
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
  if (expectedDependencyCount !== undefined) {
    // Independently specified by the fixture's Source/Result dependency
    // inventory; a separate ordered public Result is not an Effect dependency.
    assert.equal(sourceSet.dependencies.length, expectedDependencyCount);
    assert.equal(sourceSet.payloads.length, expectedDependencyCount);
  }
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
  const ledger = referenceLedger(directory, moon, identity, controlConstruction);
  const dispose = () => ledger.close();
  retainStageCleanup?.(dispose);
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
        sends, loseReply, failRow, physical, completed, stopped})},
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
    // Match the installed Site's consumer ownership: durable capture no
    // longer needs these in-process Preview pins when the Host stops.
    releaseInputs, dispose};
}

function prepareReferenceRecovery(facts, {directory, mappingCids, sends,
  loseReply, failRow, physical, completed, stopped, physicalOwner, controlConstruction,
  retainStageCleanup, afterConstruction}) {
  const {moon, control, store, recovered, continuation} = facts;
  const {requestIdentity, requestScope, computation: durable} = recovered;
  const {computation, preview, storedResults} = durable;
  const ledger = referenceLedger(directory, moon, requestIdentity, controlConstruction);
  const dispose = () => ledger.close();
  retainStageCleanup?.(dispose);
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
  const preflight = referencePreflight({moon, preview: {wire: previewWire},
    mappingCids, requestScope, keys});
  const stage = {preview, computation, storedResults,
    apply: {moon, store, publicationControl: control, computation, preview,
      ledger, requestScope, programId: 'client-values', nodeId: 'source',
      maxRows: effectLimits.maxRows,
      maxFrontierWork: effectLimits.maxFrontierWork,
      maxRecoveryWork: effectLimits.maxWork,
      keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
        maxWork: effectLimits.maxWork},
      refreshPreflight: async () => preflight,
      dispatchRow: referenceDispatch({ledger, preview: applyPreview,
        sends, loseReply, failRow, physical, completed, stopped})},
    receipt: {ledger, preview: applyPreview, commonMoon: moon,
      publicationPreview: preview,
      authorizeEvidenceRead: async () => true,
      members: undefined,
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
    cleanupOwner: physicalOwner ?? {async close() {}, async cleanup() { return true; },
      cleanupPending: () => false},
    dispose};
  // The same Ledger read has its own existing control frame. It follows
  // completed Preview/apply/preflight construction, before this Stage escapes.
  afterConstruction(() => {
    const recorded = ledger.recoverClaimFacts({preview: admitted,
      scope: requestScope, programId: 'client-values', nodeId: 'source',
      maxRows: effectLimits.maxRows, maxWork: effectLimits.maxWork});
    stage.receipt.members = recorded.members.map(member => ({rowOwners:
      member.claims.map(claim => ({claim})), replayed: true}));
  });
  return stage;
}
const owner = userInfo().username;
const crashFixtureKeys = process.env.ACTQL_TEST_HOST_CRASH_KEYS === undefined
  ? undefined : JSON.parse(await readFile(process.env.ACTQL_TEST_HOST_CRASH_KEYS, 'utf8'));
const fixtureKeyPair = name => {
  if (crashFixtureKeys === undefined) return generateKeyPairSync('ed25519');
  const privateKey = createPrivateKey(crashFixtureKeys[name]);
  return {privateKey, publicKey: createPublicKey(privateKey)};
};
const reviewerKeys = fixtureKeyPair('reviewer');
const hostKeys = fixtureKeyPair('host');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});

export function runAcceptanceConfiguration(outcome, {siteKey =
  'actql-remote-host'} = {}) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'remote-account',
    entries: [{entry_id: 'owner-read', outcome: 'allow',
      principal: {any_of: [owner]}, connection: {any_of: [siteKey]},
      resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'run-acceptance', outcome,
      principal: {all: true}, connection: {any_of: [siteKey]},
      resource: {any_of: ['source-free-values']},
      operation: {any_of: ['write']}, exclusions: []}],
  });
}

function effectCommitConfiguration(targetRead = 'allow', commit = 'delegate', resultNames = ['answer']) {
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
      {entry_id: 'terminal-owner-read', outcome: 'allow',
        principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
        resource: {any_of: [...resultNames.map(name => `result/${name}`), 'run']},
        operation: {any_of: ['read']}, exclusions: []},
    ]});
}

const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal'],
  ['reader-token', 'reader-principal'],
  ['stranger-token', 'stranger-principal']]);

const historicalFixtureWriters = new WeakMap();

// Fixture server shutdown does not acknowledge its Host's physical cleanup.
// Retain the same Host after refusal and join overlapping calls to its flight.
function remoteHostClose(server, selectHost) {
  let serverClosed = false, closed = false, flight, selectedHost;
  return () => {
    if (closed) return Promise.resolve();
    // Historical seeding replaces the fixture Host before teardown begins.
    // Select once, then keep that exact owner through pending close retries.
    selectedHost ??= selectHost();
    flight ??= (async () => {
      if (!serverClosed) {
        server.closeAllConnections?.();
        await new Promise(resolve => server.close(resolve));
        serverClosed = true;
      }
      const result = await selectedHost.close();
      closed = true;
      return result;
    })().finally(() => {flight = undefined;});
    return flight;
  };
}

// Closed diagnostic DATA from the original close carrier, never its payload,
// message, stack, references or replacement cleanup owner.
function firstHostCloseFailureDiagnostic(error) {
  const owners = new Set(['stop', 'drain', 'retire', 'checkpoint', 'journal',
    'source', 'effect', 'store', 'publicationOwnership', 'ownerViews',
    'diagnostic', 'observation', 'initialControl', 'finalize']);
  const codes = new Set(['InstalledHostCleanupPending', 'PublicationStoreCleanupPending',
    'ClientDispatchCleanupPending', 'InstalledHostJournalCleanupPending',
    'InstalledHostPublicationOwnershipCleanupPending', 'EffectCaptureCleanupPending',
    'InstalledEffectConstructionCleanupPending']);
  const own = (value, key) => {
    if (value === null || typeof value !== 'object' || utilTypes.isProxy(value)) return undefined;
    const field = Object.getOwnPropertyDescriptor(value, key);
    return field && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  const closed = (value, allowed) => allowed.has(value) ? value : 'unrecognized';
  const bounded = (value, project) => Array.isArray(value) && !utilTypes.isProxy(value)
    ? Array.from({length: Math.min(value.length, 16)}, (_, index) => project(own(value, String(index))))
    : null;
  let pendingOwners = null;
  try {
    const original = own(error, 'cleanupHandle'), status = own(original, 'status');
    if (typeof status === 'function') pendingOwners = bounded(
      own(Reflect.apply(status, original, []), 'pending'), name => closed(name, owners));
  } catch { /* Unavailable diagnostics never replace the original close failure. */ }
  return {phase: 'original_host_first_close_failure',
    code: closed(own(error, 'code'), codes),
    cleanupPending: own(error, 'cleanupPending') === true,
    storeCleanupPending: own(error, 'storeCleanupPending') === true,
    cleanupErrors: bounded(own(error, 'cleanupErrors'), entry => ({
      owner: closed(own(entry, 'owner'), owners),
      code: closed(own(own(entry, 'error'), 'code'), codes),
    })), pendingOwners};
}

async function closeRetainedStoreFixtureHost(host, t, observeFirstClose = false) {
  try { return await host.close(); }
  catch (original) {
    if (observeFirstClose) {
      try { t.diagnostic(JSON.stringify(firstHostCloseFailureDiagnostic(original))); }
      catch { /* Diagnostics cannot replace the original close failure. */ }
    }
    const pendingStore = error => error?.code === 'InstalledHostCleanupPending' &&
      error.cleanupPending === true && error.storeCleanupPending === true &&
      Array.isArray(error.cleanupErrors) && error.cleanupErrors.length === 1 &&
      error.cleanupErrors[0].owner === 'store' &&
      error.cleanupErrors[0].error?.code === 'PublicationStoreCleanupPending';
    if (!pendingStore(original)) throw original;
    t.diagnostic(JSON.stringify({phase: 'original_host_close_pending',
      owner: 'store', code: 'PublicationStoreCleanupPending'}));
    // Continue only this retained Store cleanup, never reopen or resend.
    const cleanup = original.cleanupHandle;
    try {
      assert.equal(typeof cleanup?.retry, 'function');
      assert.equal(typeof cleanup?.status, 'function');
      await waitFor(async () => {
        try { await cleanup.retry(); }
        catch (error) {
          if (!pendingStore(error)) throw error;
          return undefined;
        }
        return cleanup.status().pending.length === 0;
      });
      assert.deepEqual(cleanup.status().pending, []);
      t.diagnostic(JSON.stringify({phase: 'original_host_close_confirmed', pendingOwners: []}));
    } catch (cause) {
      // Keep the first refusal if its SAME owner cannot confirm cleanup.
      throw new AggregateError([original, cause], 'OriginalHostCleanupUnconfirmed',
        {cause: original});
    }
  }
}

test('Remote Host fixture retains its same close owner after refusal and joins one flight', async t => {
  const child = Object.assign(new Error('PublicationStoreCleanupPending'), {code: 'PublicationStoreCleanupPending'});
  let released = false, retries = 0, privateReads = 0;
  Object.defineProperty(child, 'privatePayload', {get() {privateReads++; throw new Error('PRIVATE');}});
  const cleanup = Object.freeze({
    status() {return {pending: released ? [] : ['store']};},
    async retry() {
      assert.equal(this, cleanup, 'retry must retain its original cleanup receiver');
      if (++retries === 1) throw original;
      released = true;
    },
  });
  const original = Object.freeze(Object.assign(new AggregateError([child], 'InstalledHostCleanupPending'), {
    code: 'InstalledHostCleanupPending', cleanupPending: true, storeCleanupPending: true,
    cleanupErrors: [{owner: 'store', error: child}], cleanupHandle: cleanup,
  }));
  const confirmed = Object.freeze({pendingRetention: []});
  let servers = 0, connections = 0, closes = 0;
  const close = remoteHostClose({
    closeAllConnections() {connections++;},
    close(done) {servers++; queueMicrotask(done);},
  }, () => ({async close() {closes++; if (!released) throw original; return confirmed;}}));
  const first = close();
  assert.equal(close(), first, 'overlapping close must join the original flight');
  await assert.rejects(first, error => error === original);
  assert.deepEqual(cleanup.status().pending, ['store']);
  const observations = [];
  await closeRetainedStoreFixtureHost({close}, {diagnostic(value) {
    observations.push(JSON.parse(value)); t.diagnostic(value);
  }}, true);
  assert.deepEqual(observations[0], {phase: 'original_host_first_close_failure',
    code: 'InstalledHostCleanupPending', cleanupPending: true, storeCleanupPending: true,
    cleanupErrors: [{owner: 'store', code: 'PublicationStoreCleanupPending'}], pendingOwners: ['store']});
  assert.equal(privateReads, 0);
  assert(!JSON.stringify(observations).includes('PRIVATE'));
  assert.deepEqual(firstHostCloseFailureDiagnostic({code: 'private-run-id',
    cleanupErrors: [{owner: 'private-key', error: {code: 'private-payload'}}]}), {
    phase: 'original_host_first_close_failure', code: 'unrecognized', cleanupPending: false,
    storeCleanupPending: false, cleanupErrors: [{owner: 'unrecognized', code: 'unrecognized'}], pendingOwners: null});
  assert.equal(retries, 2, 'pending retries must continue the same original handle to its ACK');
  assert.equal(original.cleanupHandle, cleanup);
  assert.equal(original.errors[0], child);
  assert.deepEqual(cleanup.status().pending, []);
  assert.equal(await close(), confirmed, 'Host cleanup must remain callable after the first refusal');
  await close();
  assert.equal(closes, 3, 'a confirmed Host must not close twice');
  assert.equal(servers, 1);
  assert.equal(connections, 1);

  const foreign = Object.assign(new Error('InstalledHostCleanupPending'), {
    ...original, cleanupErrors: [{owner: 'source', error: child}],
  });
  await assert.rejects(closeRetainedStoreFixtureHost({async close() {throw foreign;}},
    {diagnostic() {throw new Error('DiagnosticUnavailable');}}, true), error => error === foreign);
  assert.equal(retries, 2, 'a different owner must never enter the Store continuation');
  const retryFailure = new Error('OriginalRetryFailed');
  const failing = Object.assign(new Error('InstalledHostCleanupPending'), {...original,
    cleanupHandle: {status: cleanup.status, async retry() {throw retryFailure;}},
  });
  await assert.rejects(closeRetainedStoreFixtureHost({async close() {throw failing;}}, t), error =>
    error instanceof AggregateError && error.cause === failing &&
    error.errors[0] === failing && error.errors[1] === retryFailure);
});

test('Remote Host fixture selects the seeded replacement once and retains it through pending close', async () => {
  const original = new Error('OriginalReplacementCleanupPending');
  const confirmed = Object.freeze({pending: []});
  const events = [];
  let initialCloses = 0, replacementCloses = 0, selections = 0, acknowledged = false;
  const initial = {async close() {initialCloses++; events.push('initial-close');}};
  const replacement = {async close() {
    assert.equal(this, replacement);
    replacementCloses++; events.push('replacement-close');
    if (!acknowledged) throw original;
    return confirmed;
  }};
  const foreign = {async close() {assert.fail('A pending original must not switch Hosts');}};
  let current = initial;
  const close = remoteHostClose({
    closeAllConnections() {events.push('connections-close');},
    close(done) {events.push('server-close'); queueMicrotask(done);},
  }, () => {selections++; return current;});
  // The real historical writer closes its first Host before opening its
  // replacement. The fixture's eventual close must select that replacement.
  await current.close();
  current = replacement;
  const first = close();
  assert.equal(close(), first);
  await assert.rejects(first, error => error === original);
  assert.equal(initialCloses, 1);
  assert.equal(replacementCloses, 1);
  assert.deepEqual(events,
    ['initial-close', 'connections-close', 'server-close', 'replacement-close']);
  current = foreign;
  acknowledged = true;
  const retry = close();
  assert.equal(close(), retry);
  assert.equal(await retry, confirmed);
  await close();
  assert.equal(selections, 1);
  assert.equal(initialCloses, 1);
  assert.equal(replacementCloses, 2);
  assert.deepEqual(events,
    ['initial-close', 'connections-close', 'server-close', 'replacement-close', 'replacement-close']);
});

async function remoteHost(t, authorization, {directory,
  effectInstallation, sourceProfilePath, sourceProfilePaths, resolveSourceSecret, beforeDispatch,
  hostCapacityPolicy, httpObserver, singleRequestConnections = false} = {}) {
  const root = directory ?? await mkdtemp(join(scratch, 'host-'));
  let dispatches = 0;
  const openHost = () => openInstalledRemoteHttpHost({
    directory: join(root, 'state'),
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    beforeDispatch: async ref => {
      dispatches++;
      await beforeDispatch?.(ref);
    },
    authorization, effectInstallation, sourceProfilePath, sourceProfilePaths, resolveSourceSecret,
    hostCapacityPolicy,
  });
  let host = await openHost().catch(error => {
    const failure = error.primaryFailure ?? error.cause ?? error;
    t.diagnostic(JSON.stringify({phase: 'open_host', code: error.code,
      primaryCode: failure.code, primaryName: failure.name,
      primaryMessage: /^[A-Za-z][A-Za-z0-9_ ]{0,100}$/u.test(failure.message ?? '')
        ? failure.message : undefined,
      frames: failure.stack?.split('\n').slice(1, 5)}));
    throw error;
  });
  const seedHistorical = async originals => {
    assert.equal(sourceProfilePaths, undefined);
    await host.close();
    const authored = [];
    for (const [index, original] of originals.entries()) {
      if (sourceProfilePath !== undefined) {
        assert.equal(originals.length, 1, 'Only one finite historical Source original is authored');
        authored.push(await writeSyntheticHistoricalHeldQuery({directory: join(root, 'state'),
          document: original.document, requestId: original.requestId, authorization,
          sourceProfile: JSON.parse(await readFile(sourceProfilePath, 'utf8')),
          runtimeRootUrl: new URL('../../', import.meta.url),
          effectEnvironmentWire: effectInstallation?.environmentWire}));
        continue;
      }
      authored.push(await writeSyntheticHistoricalHeldValues({directory: join(root, 'state'),
        document: original.document, requestId: original.requestId, authorization, mode: 'remote',
        append: index !== 0, runtimeRootUrl: new URL('../../', import.meta.url),
        effectEnvironmentWire: effectInstallation?.environmentWire}));
    }
    host = await openHost();
    return authored;
  };
  const responses = [];
  const server = createServer({key: tlsKey, cert: tlsCertificate},
    (request, response) => {
      try { httpObserver?.response(request, response); }
      catch { /* Optional diagnostics do not change the original handler. */ }
      response.once('finish', () => responses.push({
        path: request.url, status: response.statusCode}));
      return host.handler(request, response);
    });
  if (singleRequestConnections) server.maxRequestsPerSocket = 1;
  try { httpObserver?.server(server); }
  catch { /* Optional diagnostics do not change the original server. */ }
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const close = remoteHostClose(server, () => host);
  // Close the Host (and its Store owner) before removing its state.
  t.after(async () => {
    await close();
    if (directory === undefined) {
      await rm(root, {recursive: true, force: true});
    }
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const options = token => ({mode: 'remote', endpoint, token,
    durability: 'durable'});
  const as = async token => {
    const client = await connect(options(token));
    if (token === 'owner-token') historicalFixtureWriters.set(client, seedHistorical);
    return client;
  };
  return {as, options, dispatches: () => dispatches, responses, close};
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

async function assertPreparationRefused(client, text, submissionRef, code, options = {}, lookupDenied = false) {
  let outcome;
  await assert.rejects(client.startSource(text, {format: 'json', ...options, submissionRef}), error => {
    assert.equal(error.code, 'SubmissionPreparationFailed');
    outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'preparation_failed');
    assert.deepEqual(outcome.submissionRef, submissionRef);
    assert.equal(outcome.problem.code, code);
    assert.equal(Object.hasOwn(outcome, 'admission'), false);
    return true;
  });
  if (lookupDenied) {
    // Without a valid Account the current Host must deny Journal observation,
    // even when this Client already knows its original preparation refusal.
    await assert.rejects(client.lookupSubmission(submissionRef), {code: 'ClientConnectionDenied'});
  } else assert.deepEqual(await client.lookupSubmission(submissionRef), outcome);
}

test('allow runs without a Checkpoint; deny and missing configuration start nothing',
  async t => {
    const allowed = await remoteHost(t, protectedHost('allow'));
    const client = await allowed.as('owner-token');
    const execution = await client.startSource(document, {format: 'json',
      submissionRef: client.newSubmission({nonce: 'allow-a'})});
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await (await allowed.as('reviewer-token'))
      .checkpoints()).items, []);
    for (const [label, authorization, code, lookupDenied = false] of [
      ['deny', protectedHost('deny'), 'ACTQL_E_ACCOUNT_DENIED'],
      ['missing', protectedHost(undefined), 'ACTQL_E_ACCOUNT_CONFIG_INVALID', true],
    ]) {
      const host = await remoteHost(t, authorization);
      const denied = await host.as('owner-token');
      const submissionRef = denied.newSubmission({nonce: `${label}-a`});
      await assertPreparationRefused(denied, document, submissionRef, code, {}, lookupDenied);
      assert.equal(host.dispatches(), 0, label);
    }
  });

test('a claimed start with lost execution observation reconciles after restart',
  async t => {
    const childDirectory = process.env.ACTQL_TEST_CLAIMED_START_CRASH_DIRECTORY;
    const directory = childDirectory ?? await mkdtemp(join(scratch, 'unknown-run-'));
    if (childDirectory !== undefined) {
      const first = await remoteHost(t, protectedHost('allow', {
        faultInjection(name, detail) {
          if (name === 'physical_start_reserved') {
            writeFileSync(join(directory, 'reserved-run.json'), JSON.stringify(detail.ref));
            // A real process loss leaves the durable reservation unresolved.
            // Throwing here instead lets the setup owner confirm cleanup.
            process.exit(77);
          }
        },
      }), {directory});
      const client = await first.as('owner-token');
      const submissionRef = client.newSubmission({nonce: 'unknown-start'});
      writeFileSync(join(directory, 'original-submission.json'), JSON.stringify(submissionRef));
      await client.startSource(document, {format: 'json', submissionRef});
      await new Promise(resolve => setTimeout(resolve, 20000));
      assert.fail('The child must terminate at the physical reservation');
    }
    t.after(() => rm(directory, {recursive: true, force: true}));
    const file = fileURLToPath(import.meta.url);
    const keyFile = join(directory, 'host-crash-keys.json');
    await writeFile(keyFile, JSON.stringify({host: pem(hostKeys.privateKey),
      reviewer: pem(reviewerKeys.privateKey)}), {mode: 0o600});
    const {NODE_TEST_CONTEXT: _outerContext, ...environment} = process.env;
    const crashed = spawnSync(process.execPath, nodeTestArguments([
      '--test-name-pattern', '^a claimed start with lost execution observation reconciles after restart$', file]),
    {cwd: repository, encoding: 'utf8', timeout: 90000, killSignal: 'SIGKILL',
      maxBuffer: 4 * 1024 * 1024,
      env: {...environment, ACTQL_TEST_CLAIMED_START_CRASH_DIRECTORY: directory,
        ACTQL_TEST_HOST_CRASH_KEYS: keyFile}});
    assertPartialEffectSeedExit(crashed, file);
    const ref = JSON.parse(await readFile(join(directory, 'reserved-run.json'), 'utf8'));
    const submissionRef = JSON.parse(await readFile(join(directory, 'original-submission.json'), 'utf8'));
    const db = new DatabaseSync(join(directory, 'state/requests/client-requests.sqlite3'), {readOnly: true});
    try {
      const rows = db.prepare('SELECT run_definition_cid, physical_start_reserved, physical_close_confirmed FROM client_requests').all();
      assert.deepEqual(rows.map(row => ({...row})), [{run_definition_cid: ref.runDefinitionCid,
        physical_start_reserved: 1, physical_close_confirmed: 0}]);
    } finally {db.close();}
    const restarted = await remoteHost(t, protectedHost('allow'), {directory});
    const client = await restarted.as('owner-token');
    const original = await client.lookupSubmission(submissionRef);
    assert.equal(original.kind, 'ready');
    assert.deepEqual(original.admission.ref, ref);
    const attached = await client.attach(ref);
    const unknown = await attached.status();
    assert.equal(unknown.status, 'needs_reconciliation');
    assert.deepEqual(unknown.next_action,
      {kind: 'reconcile_run', reason: 'execution_unknown'});
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
    const execution = await client.startSource(document, {format: 'json',
      submissionRef: client.newSubmission({nonce: 'late-observation'})});
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
      const submissionRef = client.newSubmission({nonce: requestId});
      await assertPreparationRefused(client, document, submissionRef, 'ACTQL_E_DELEGATION_UNAVAILABLE');
    }
    assert.equal(calls, 1);
    assert.equal(host.dispatches(), 0);
    finish({decision: 'unavailable'});
    await new Promise(resolve => setImmediate(resolve));
    await assertPreparationRefused(client, document,
      client.newSubmission({nonce: 'unfinished-three'}), 'ACTQL_E_DELEGATION_UNAVAILABLE');
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
    const permitted = await client.startSource(document, {format: 'json',
      submissionRef: client.newSubmission({nonce: 'permit-a'})});
    assert.equal((await permitted.wait()).status, 'succeeded');
    answer = 'reject';
    await assertPreparationRefused(client, document,
      client.newSubmission({nonce: 'reject-a'}), 'ACTQL_E_DELEGATION_REJECTED');
    assert.deepEqual((await (await host.as('reviewer-token'))
      .checkpoints()).items, []);
  });

test('a synthetic historical held request is reviewed, answered and resumed by the Host',
  async t => {
    const resumeFailures = [];
    const host = await remoteHost(t, protectedHost('delegate', {faultInjection(name, detail) {
      if (name === 'resume_failed' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(detail?.code ?? '')) {
        resumeFailures.push(detail.code);
      }
    }}));
    const client = await host.as('owner-token');
    await historicalFixtureWriters.get(client)([{requestId: 'held-a', document}]);
    const held = await client.lookupRequest('held-a');
    assert.equal(held.kind, 'held');
    assert.equal(held.state, 'waiting_checkpoint');
    assert.equal(host.dispatches(), 0);
    // The original can be observed repeatedly. This historical observation
    // cannot authorize risk restart without a current submitted reference;
    // the SDK's separate public-name domain does not relabel its identity.
    assert.deepEqual(await client.lookupRequest('held-a'), held);
    await assert.rejects(client.startSource(document, {format: 'json', requestId: 'held-a', unresolvedHistory: held}),
      {code: 'SubmissionReferenceRequired'});
    // The separate same-submitted-identity test below preserves the actual
    // changed-intent conflict control; missing restart reference is not that evidence.
    const changed = JSON.parse(document);
    changed.stages[0].steps[0].values.rows = [{id: 9}];
    await assert.rejects(client.startSource(JSON.stringify(changed), {format: 'json', requestId: 'held-a', unresolvedHistory: held}),
      {code: 'SubmissionReferenceRequired'});
    const waitingLookup = await client.lookupRequest('held-a');
    assert.equal(waitingLookup.state, 'waiting_checkpoint');
    const waitingExplanation = explainRequestLookup(waitingLookup);
    assert.equal(waitingExplanation.preparationState, 'waiting_checkpoint', '[check-mutation:request-held-public]');
    assert.equal(explainRequestLookup(held).preparationState, 'waiting_checkpoint');
    assert.deepEqual(waitingExplanation.next, {operation: 'lookupRequest', requestId: 'held-a',
      lookupContext: {endpoint: host.options('owner-token').endpoint, scopeRef: client.profile.scopeRef}});
    assert.equal(explainRequestLookup({...waitingLookup}), undefined);

    const reviewer = await host.as('reviewer-token');
    const reader = await host.as('reader-token');
    const {items: [summary]} = await reviewer.checkpoints();
    assert.equal(summary.checkpointCid, held.checkpoint.checkpointCid);
    assert.equal(summary.subject.requestId, 'held-a');
    assert.equal(JSON.stringify(summary).includes('"rows"'), false);
    // Status, review and answer permissions are separate.
    await assert.rejects(host.as('stranger-token'), {code:
      'ClientConnectionDenied'});
    // A reviewer is not the request owner: no Run operation.
    const reviewerRef = client.newSubmission({nonce: 'reviewer-own'});
    await assert.rejects(reviewer.startSource(document, {format: 'json',
      submissionRef: reviewerRef}), error => {
      assert.equal(error.code, 'SubmissionUnknown');
      assert.equal(error.cause?.code, 'ClientConnectionDenied');
      assert.equal(error.cause?.status, undefined);
      assert.deepEqual(host.responses.at(-1), {
        path: '/actql/client/0.1/submit-intent', status: 403});
      assert.deepEqual(error.submissionRef, reviewerRef);
      return true;
    });
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
    }).catch(cause => {throw new Error(JSON.stringify({phase: 'historical_resume', resumeFailures}), {cause});});
    assert.equal(explainRequestLookup(found).observation, 'run_reference_received');
    assert.equal(waitingExplanation.preparationState, 'waiting_checkpoint');
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
    // Recovery returns the existing Run without authorizing another start.
    assert.deepEqual((await client.lookupRequest('held-a')).ref, found.ref);
    assert.deepEqual((await client.attach(found.ref)).ref, found.ref);
    assert.equal(host.dispatches(), 1);
    assert.deepEqual((await reviewer.checkpoints()).items, []);
  });

test('installed Effect owner recovers one synthetic historical Run acceptance',
  async t => {
    const fixture = await effectFixture();
    let starts = 0;
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = {
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async execute({openComputation, retainExecution}) {
        starts++;
        const {execution} = await openComputation();
        retainExecution(execution);
        return {status: 'captured_without_apply'};
      },
      resume() { assert.fail('Run acceptance cannot resume an Effect apply'); },
    };
    const directory = await mkdtemp(join(scratch, 'effect-acceptance-'));
    let currentHost;
    t.after(async () => {
      await currentHost?.close();
      await rm(directory, {recursive: true, force: true});
    });
    const first = currentHost = await remoteHost(t, protectedHost('delegate',
      {resumeAfterAnswer: false}), {directory, effectInstallation});
    const client = await first.as('owner-token');
    const [original] = await historicalFixtureWriters.get(client)([
      {requestId: 'effect-held-a', document: fixture.document}]);
    assert.equal(starts, 0);
    assert.equal((await client.lookupRequest('effect-held-a')).state,
      'waiting_checkpoint');
    await first.close();
    const diagnostics = [];
    const restarted = currentHost = await remoteHost(t, protectedHost('delegate', {observe(name, detail) {
      diagnostics.push({name, code: detail.code});
    }}),
      {directory, effectInstallation});
    const reviewer = await restarted.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    assert.equal(checkpoint.subject.requestId, 'effect-held-a');
    await approveAll(reviewer, [checkpoint]);
    const ownerClient = await restarted.as('owner-token');
    const found = await waitFor(async () => {
      const value = await ownerClient.lookupRequest('effect-held-a');
      if (value.kind === 'held' && value.state === 'ended') {
        assert.fail(JSON.stringify({state: value.state, endReason: value.endReason,
          terminalErrorCode: value.terminalErrorCode, diagnostics}));
      }
      return value.kind === 'found' ? value : undefined;
    }).catch(error => {
      error.message += ` ${JSON.stringify({diagnostics, starts})}`;
      throw error;
    });
    const execution = await ownerClient.attach(found.ref);
    await waitFor(async () => (await execution.status()).status ===
      'needs_reconciliation');
    assert.equal(starts, 1);
    assert.equal(found.ref.authorityScopeCid, original.authorityScopeCid);
    assert.deepEqual((await ownerClient.lookupRequest('effect-held-a')).ref, found.ref);
    assert.deepEqual((await ownerClient.attach(found.ref)).ref, found.ref);
    await assert.rejects(ownerClient.startSource(fixture.document,
      {format: 'json', requestId: 'effect-held-a', unresolvedHistory: found}),
    {code: 'SubmissionReferenceRequired'});
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
    const account = JSON.parse(effectCommitConfiguration());
    account.entries.push({entry_id: 'owner-read', outcome: 'allow',
      principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []});
    account.entries.sort((a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0);
    const accountConfiguration = canonicalJson(account);
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async prepareCaptured(facts) {
        try {
          return await managed.stage(facts, false, owned => prepareReferenceCapture(facts,
            {directory, mappingCids: fixture.mappingCids, sends, ...owned}));
        } catch (error) {
          diagnostics.push({name: 'capture_stack', detail: error.stack});
          throw error;
        }
      },
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts,
        {directory, mappingCids: fixture.mappingCids, sends, ...owned})),
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
      {accountConfiguration,
        observe: (name, detail) => diagnostics.push({name, detail})}),
    {directory, effectInstallation});
    const client = await host.as('owner-token');
    const submissionRef = client.newSubmission({nonce: 'effect-factory-a'});
    const execution = await client.startSource(fixture.document, {format: 'json',
      submissionRef});
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
      {accountConfiguration,
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
      {accountConfiguration,
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
    assert.deepEqual((await resumedClient.startSource(fixture.document,
      {format: 'json', submissionRef})).ref,
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
      {accountConfiguration}),
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 13), leaseMs: 1000,
      prepareCaptured(facts) {
        captures++;
        return managed.stage(facts, false,
          owned => prepareReferenceCapture(facts, {...hooks, ...owned}));
      },
      prepareRecovered(facts) {
        if (preparationFailures === 0) {
          preparationFailures++;
          facts.retainRecoveryOwner({async close() {},
            async cleanup() { preparationCleanups++; return true; },
            cleanupPending: () => false});
          throw new Error('TemporaryProviderPreparationFailure');
        }
        return managed.stage(facts, true,
          owned => prepareReferenceRecovery(facts, {...hooks, ...owned}));
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
    const submissionClient = await first.as('owner-token');
    const submitted = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'effect-read-retry'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 8),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const sourceProfilePaths = await Promise.all(['unused-first', 'unused-second', 'unused-third']
      .map(name => unusedTableFixture(directory, name)));
    const configuration = JSON.parse(effectCommitConfiguration('allow', 'allow'));
    configuration.entries[1].resource = {any_of: ['installed-multi-acquired']};
    const account = () => protectedHost(undefined,
      {accountConfiguration: canonicalJson(configuration)});
    const options = {directory, effectInstallation, sourceProfilePaths,
      resolveSourceSecret() { assert.fail('SourceFreeEffectMustNotResolveSourceSecret'); }};
    const first = await remoteHost(t, account(), options);
    const client = await first.as('owner-token');
    const submissionRef = client.newSubmission({nonce: 'effect-direct-allow-a'});
    const submitted = await client.startSource(fixture.document, {format: 'json',
      submissionRef});
    await waitFor(async () => (await submitted.status()).status ===
      'succeeded');
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    assert.deepEqual(await submitted.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await (await first.as('reviewer-token'))
      .checkpoints()).items, []);
    try { await first.close(); }
    catch (error) {
      try {
        const label = value => typeof value === 'string' &&
          /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(value) ? value : undefined;
        t.diagnostic(JSON.stringify({phase: 'first_effect_host_close', code: label(error?.code),
          owners: Array.isArray(error?.cleanupErrors) ? error.cleanupErrors.slice(0, 12)
            .map(item => ({owner: label(item.owner), code: label(item.error?.code),
              name: label(item.error?.name), cleanupPending: item.error?.cleanupPending === true,
              storeCleanupPending: item.error?.storeCleanupPending === true})) : undefined}));
      } catch {
        // Diagnostics must not replace the original cleanup failure.
      }
      throw error;
    }
    const restarted = await remoteHost(t, account(), options);
    const restoredClient = await restarted.as('owner-token');
    const original = await restoredClient.lookupSubmission(submissionRef);
    assert.equal(original.kind, 'ready');
    assert.deepEqual(original.submissionRef, submissionRef);
    assert.deepEqual(original.admission.ref, submitted.ref);
    const sameRun = await restoredClient.attach(original.admission.ref);
    assert.equal((await sameRun.status()).status, 'succeeded');
    assert.deepEqual(await sameRun.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual(sends, [[0, 0], [0, 1], [1, 0], [1, 1]]);
    await restarted.close();
  });

for (const readDecision of ['deny']) {
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
      const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
        'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds,
      program.stages.findIndex(stage => stage.effects !== undefined));
      const effectInstallation = createInstalledEffectSite({
        prepareManagedPlan: managed.prepareManagedPlan,
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
      const submitted = await client.startSource(canonicalJson(program), {
        format: 'json', submissionRef: client.newSubmission({nonce: `acquired-effect-${readDecision}`})});
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

for (const uncertain of [false, true]) {
test(uncertain
  ? 'acquired Effect Source resume preserves recorded uncertain Effect after lost completion'
  : 'acquired Effect Source approval renews its active lease across two approval restarts',
  async t => {
    const directory = await mkdtemp(join(scratch, 'source-effect-approval-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory, 'delegate');
    const sourceProfilePaths = [await unusedTableFixture(directory, 'unused-first'),
      sourceProfilePath, await unusedTableFixture(directory, 'unused-last')];
    const fixture = await effectFixture();
    const program = JSON.parse(readDocument);
    delete program.params;
    program.stages = program.stages.slice(0, 2);
    program.stages[0].steps[0].filter = 'id > 0';
    program.stages[1].steps[0].filter = 'id < 3';
    program.stages[1].results = {rows: {from: 'out', fields: ['id']}};
    program.stages[1].effects = JSON.parse(fixture.document).stages[0].effects;
    program.results = {answer: {from: {stage: 'compute_a', result: 'rows'}}};
    const sends = [], diagnostics = [];
    let sourceCalls = 0, captures = 0;
    const create = DuckDBInstance.create;
    const sourceDatabase = JSON.parse(await readFile(sourceProfilePath, 'utf8')).database;
    DuckDBInstance.create = async function(database, ...args) {
      if (database === sourceDatabase) {
        sourceCalls++;
        await new Promise(resolve => setTimeout(resolve, 1300));
      }
      return create.call(this, database, ...args);
    };
    t.after(() => { DuckDBInstance.create = create; });
    const hooks = {directory, mappingCids: fixture.mappingCids, sends, maxInputPins: 2,
      loseReply: (member, row) => uncertain && member === 0 && row === 0};
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds,
    program.stages.findIndex(stage => stage.effects !== undefined));
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 61),
      prepareCaptured(facts) { captures++; return managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})); },
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const effectInstallation = {...installed, async execute(facts) {
      const result = await installed.execute(facts);
      if (uncertain && result.status === 'needs_reconciliation') {
        throw Object.assign(new Error('SourceCompletionLost'), {code: 'ResumeClaimStale'});
      }
      return result;
    }};
    const configuration = JSON.parse(effectCommitConfiguration('allow',
      uncertain ? 'allow' : 'delegate'));
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {any_of: ['installed-multi-acquired']};
    const account = () => protectedHost(undefined, {
      accountConfiguration: canonicalJson(configuration), resumeAfterAnswer: false,
      leaseMs: 1000,
      observe: (name, detail) => diagnostics.push({name, detail}),
    });
    const options = {directory, sourceProfilePaths, effectInstallation,
      resolveSourceSecret() { assert.fail('UnusedSourceSecret'); }};
    let host = await remoteHost(t, account(), options).catch(error => {
      t.diagnostic(String(error.cause?.stack ?? error));
      throw error;
    });
    const client = await host.as('owner-token');
    const submissionRef = client.newSubmission({nonce: 'source-effect-approval'});
    const submitted = await client.startSource(JSON.stringify(program),
      {format: 'json', submissionRef});
    const wait = async (execution, expected) => waitFor(async () =>
      (await execution.status()).status === expected).catch(async error => {
      error.message = JSON.stringify({state: await execution.status(), diagnostics});
      throw error;
    });
    await wait(submitted, 'waiting_checkpoint');
    const [read] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(read.kind, 'read_access');
    assert.equal(sourceCalls, 0);
    assert.equal(captures, 0);
    assert.deepEqual(sends, []);
    await host.close();
    host = await remoteHost(t, account(), options);
    let reviewer = await host.as('reviewer-token');
    const [sameRead] = (await reviewer.checkpoints()).items;
    assert.equal(sameRead.checkpointCid, read.checkpointCid);
    await reviewer.resolveCheckpoints([{checkpoint: sameRead, decision: 'approved'}], {signer});
    assert.equal(sourceCalls, 0, 'persisting approval alone does not read');
    await host.close();
    host = await remoteHost(t, account(), options);
    let attached = await (await host.as('owner-token')).attach(submitted.ref);
    if (uncertain) {
      await waitFor(async () => {
        const state = await attached.status();
        return state.status === 'needs_reconciliation' && state.next_action.kind === 'reconcile';
      }).catch(async error => {
        error.message = JSON.stringify({state: await attached.status(), diagnostics});
        throw error;
      });
      const observed = await attached.status();
      assert.deepEqual(sends, [[0, 0]]);
      assert.equal(sourceCalls, 1);
      assert.equal(captures, 1);
      await host.close();
      host = await remoteHost(t, account(), options);
      attached = await (await host.as('owner-token')).attach(submitted.ref);
      const original = await (await host.as('owner-token')).lookupSubmission(submissionRef);
      assert.equal(original.kind, 'ready');
      assert.deepEqual(original.submissionRef, submissionRef);
      assert.deepEqual(original.admission.ref, submitted.ref);
      assert.deepEqual((await attached.status()).next_action, observed.next_action);
      assert.equal(sourceCalls, 1);
      assert.equal(captures, 1);
      assert.deepEqual(sends, [[0, 0]]);
      await host.close();
      return;
    }
    await wait(attached, 'waiting_checkpoint');
    reviewer = await host.as('reviewer-token');
    const [effect] = (await reviewer.checkpoints()).items;
    assert.equal(effect.kind, 'effect_set');
    assert.notEqual(effect.checkpointCid, read.checkpointCid);
    assert.equal(sourceCalls, 1);
    assert.equal(captures, 1);
    assert.deepEqual(sends, []);
    const original = await (await host.as('owner-token')).lookupSubmission(submissionRef);
    assert.equal(original.kind, 'ready');
    assert.deepEqual(original.submissionRef, submissionRef);
    assert.deepEqual(original.admission.ref, submitted.ref);
    await reviewer.resolveCheckpoints([{checkpoint: effect, decision: 'approved'}], {
      signer: {...signer, authorityScopeCid: submitted.ref.authorityScopeCid}});
    await host.close();
    host = await remoteHost(t, account(), options);
    attached = await (await host.as('owner-token')).attach(submitted.ref);
    await wait(attached, 'succeeded');
    assert.deepEqual(await attached.result('answer').all(), [{id: 1}, {id: 2}]);
    assert.deepEqual((await attached.result('answer').describe()).columns,
      [{name: 'id', contract: {type: 'number', nullable: false}}]);
    assert.equal(sourceCalls, 1);
    assert.equal(captures, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await host.close();
  });

}

// Observe this fixture's original HTTP failures before the SDK redacts their
// borrowed causes. Keep only finite route/phase metadata and Error data fields;
// never record a URL origin, headers, body, message, stack or Run identity.
function observeSecondSourceApprovalHttp(t) {
  const original = globalThis.fetch;
  const events = [];
  const routes = new Set(['connect', 'submit-intent', 'attach', 'status',
    'checkpoints', 'checkpoint-review', 'resolve', 'lookup-submission', 'read']);
  let phase = 'initial';
  const field = (value, key) => {
    for (let depth = 0; depth < 4 && value !== null &&
        typeof value === 'object' && !utilTypes.isProxy(value); depth++) {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (descriptor !== undefined) {
        return Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
      }
      value = Object.getPrototypeOf(value);
    }
  };
  const token = value => typeof value === 'string' &&
    /^[A-Za-z][A-Za-z0-9_]{0,79}$/u.test(value) ? value : undefined;
  const record = value => {
    events.push(value);
    if (events.length > 8) events.shift();
  };
  const requestFields = (method, path) => {
    const route = typeof path === 'string' && path.startsWith('/actql/client/0.1/')
      ? path.slice('/actql/client/0.1/'.length) : undefined;
    return {phase, method: ['GET', 'POST'].includes(method) ? method : 'other',
      route: routes.has(route) ? route : 'other'};
  };
  const errorFields = error => ({name: token(field(error, 'name')),
    code: token(field(error, 'code')),
    causeCode: token(field(field(error, 'cause'), 'code'))});
  const observe = action => { try { action(); } catch { /* Observers cannot replace original errors. */ } };
  const sockets = new WeakMap();
  const observer = Object.assign(next => { phase = next; }, {
    server(server) {
      server.on('secureConnection', socket => observe(() => {
        const state = {lastReply: performance.now(), request: {phase}};
        sockets.set(socket, state);
        // errorMonitor observes without consuming an unhandled error. No
        // timeout/clientError listener changes Node's default socket policy.
        socket.on(errorMonitor, error => observe(() => record({event: 'server_socket_error',
          ...state.request, ...errorFields(error)})));
        socket.once('close', hadError => observe(() => record({event: 'server_socket_close',
          ...state.request, hadError,
          idleMilliseconds: Math.max(0, Math.floor(performance.now() - state.lastReply))})));
      }));
    },
    response(request, response) {
      const summary = requestFields(request.method, request.url);
      const state = sockets.get(request.socket);
      if (state) state.request = summary;
      const started = performance.now();
      response.on(errorMonitor, error => observe(() => record({event: 'server_response_error',
        ...summary, status: response.statusCode, headersSent: response.headersSent,
        ...errorFields(error)})));
      response.once('finish', () => observe(() => {
        if (state) state.lastReply = performance.now();
        record({event: 'server_reply', ...summary, status: response.statusCode,
          durationMilliseconds: Math.max(0, Math.floor(performance.now() - started))});
      }));
    },
    failure(error, summary, diagnostics) {
      try {
        t.diagnostic(JSON.stringify({phase: 'second_source_approval_failure',
          ...summary, ...errorFields(error),
          hostEvents: diagnostics.slice(-8).map(({name, detail}) => ({name: token(name),
            code: token(field(detail, 'code')), boundary: token(field(detail, 'boundary')),
            causeCode: token(field(field(detail, 'cause'), 'code'))})), events}));
      } catch { /* Preserve the same original failure even if diagnostics fail. */ }
    },
  });
  globalThis.fetch = async function(input, init) {
    let request;
    try {
      request = requestFields(init?.method, new URL(input).pathname);
    } catch { /* Optional diagnostics cannot change the original request. */ }
    try {
      const response = await Reflect.apply(original, this, [input, init]);
      try {
        if (request !== undefined) record({event: 'client_response', ...request, status: response.status});
      } catch { /* Keep the original response authoritative. */ }
      return response;
    } catch (error) {
      try {
        record({event: 'client_error', ...request, status: null, ...errorFields(error)});
        t.diagnostic(JSON.stringify({phase: 'second_source_approval_http', events}));
      } catch { /* Keep the same original failure and its SDK classification. */ }
      throw error;
    }
  };
  t.after(() => { globalThis.fetch = original; });
  return observer;
}

for (const realization of ['native', 'broad']) {
test(`acquired Effect second Source approval restores the first ${realization} capture`,
  async t => {
    const httpPhase = observeSecondSourceApprovalHttp(t);
    const directory = await mkdtemp(join(scratch, 'second-source-approval-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const inputs = await loadTwoSourceFixtures(join(repository, 'adapters/host-node/fixtures/two-source'));
    inputs.rows = {left: [{id: 1, amount: 10}, {id: 2, amount: 20}],
      right: [{id: 2, amount: 200}, {id: 1, amount: 100}], equal_content: []};
    const installation = await installTwoSourceFixtures({root: join(directory, 'sources'),
      fixture: inputs, duckdb});
    const sourceProfilePaths = realization === 'broad'
      ? [installation.profiles.left_broad, installation.profiles.right_broad]
      : [installation.profiles.left, installation.profiles.right];
    const second = JSON.parse(await readFile(sourceProfilePaths[1], 'utf8'));
    const readAccount = JSON.parse(second.accountConfigurationWire);
    readAccount.entries[0].outcome = 'delegate';
    second.accountConfigurationWire = canonicalJson(readAccount);
    await writeFile(sourceProfilePaths[1], JSON.stringify(second));
    sourceProfilePaths.splice(1, 0, await unusedTableFixture(directory));
    const fixture = await effectFixture();
    const program = JSON.parse(inputs.program);
    program.stages[2].effects = JSON.parse(fixture.document).stages[0].effects;
    program.results = {answer: {from: {stage: 'join_sources', result: 'rows'}}};
    const sends = [], diagnostics = [];
    let captures = 0;
    const provider = observeTwoSourceProvider(duckdb, installation.databases);
    t.after(() => provider.restore());
    const hooks = {directory, mappingCids: fixture.mappingCids, sends,
      maxInputPins: 3, expectedDependencyCount: 3};
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds,
    program.stages.findIndex(stage => stage.effects !== undefined));
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire, privateEvidenceKey: Buffer.alloc(32, 63),
      // Keep the optional target binding identical through Source restoration
      // and the later Effect-commit restoration, without changing read counts.
      targetReadAuthorization: {accountConfiguration: effectCommitConfiguration(),
        context: {principal: owner, contextCid: contentCid({targetFixture: directory})}},
      targetReadInventory: () => [{readTuple: {connection: 'reference',
        resource: 'records', operation: 'read'}, physicalBinding: {
        version: 'fixture-effect-target/0.1', mappings: [...fixture.mappingCids]}}],
      prepareCaptured(facts) { captures++; return managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})); },
      prepareRecovered: facts => {
        assert.deepEqual(facts.targetReads.captureBinding(), facts.continuation.target_read_binding);
        return managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned}));
      },
    });
    const configuration = JSON.parse(effectCommitConfiguration());
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {all: true};
    const account = () => protectedHost(undefined, {
      accountConfiguration: canonicalJson(configuration), resumeAfterAnswer: false,
      observe: (name, detail) => diagnostics.push({name, detail}),
    });
    // Host execution and the client share this event loop. Keep idle socket expiry
    // out of these Source-restoration assertions when synchronous execution is slow.
    const options = {directory, sourceProfilePaths, effectInstallation, httpObserver: httpPhase,
      singleRequestConnections: true,
      resolveSourceSecret() { assert.fail('UnusedSourceSecret'); }};
    let host = await remoteHost(t, account(), options);
    const client = await host.as('owner-token');
    // The unused Table now has the supported row-source-acquired realization.
    // Unsupported realizations retain their exact inert-selector controls;
    // this installed boundary refuses a duplicate original owner before I/O.
    for (const fault of ['duplicate-owner']) {
      const rejected = structuredClone(program);
      rejected.stages[1].inputs.remote = {...rejected.stages[0].inputs.remote};
      const rejectedRef = client.newSubmission({nonce: `second-source-${realization}-${fault}`});
      let rejectedOutcome;
      await assert.rejects(client.startSource(JSON.stringify(rejected),
        {format: 'json', submissionRef: rejectedRef}), error => {
        // The inert selector refuses before the first durable acceptance.
        assert.equal(error.code, 'SubmissionNotAccepted');
        rejectedOutcome = getSubmissionOutcome(error);
        assert.equal(rejectedOutcome.kind, 'not_accepted');
        assert.deepEqual(rejectedOutcome.submissionRef, rejectedRef);
        assert.deepEqual(rejectedOutcome.problem,
          {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
        assert.equal(rejectedOutcome.admission, undefined);
        return true;
      });
      assert.deepEqual(await client.lookupSubmission(rejectedRef), rejectedOutcome);
      assert.deepEqual(provider.snapshot().sourceProviderOpens, []);
      assert.equal(captures, 0);
      assert.deepEqual(sends, []);
    }
    const submissionRef = client.newSubmission({nonce: `second-source-${realization}`});
    const submitted = await client.startSource(JSON.stringify(program),
      {format: 'json', submissionRef});
    const wait = async (execution, expected) => {
      let lastStatus;
      return waitFor(async () => {
        const state = await execution.status();
        lastStatus = state.status;
        if (['failed', 'cancelled', 'succeeded', 'needs_reconciliation'].includes(state.status) &&
            state.status !== expected) throw new Error('UnexpectedEffectTerminalState');
        return state.status === expected;
      }).catch(error => {
        try {
          httpPhase.failure(error, {expected, lastStatus, captures, sends: sends.length,
            sourceOpens: provider.snapshot().sourceProviderOpens.length}, diagnostics);
        } catch { /* Reporting must not replace the original observation failure. */ }
        throw error;
      });
    };
    await wait(submitted, 'waiting_checkpoint');
    const [read] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(read.kind, 'read_access');
    assert.deepEqual(provider.snapshot().sourceProviderOpens, [installation.databases.left]);
    assert.equal(captures, 0);
    assert.deepEqual(sends, []);
    await host.close();
    httpPhase('read_review');
    host = await remoteHost(t, account(), options);
    let reviewer = await host.as('reviewer-token');
    const [sameRead] = (await reviewer.checkpoints()).items;
    assert.equal(sameRead.checkpointCid, read.checkpointCid);
    await reviewer.resolveCheckpoints([{checkpoint: sameRead, decision: 'approved'}], {signer});
    assert.deepEqual(provider.snapshot().sourceProviderOpens, [installation.databases.left]);
    await host.close();
    httpPhase('source_restore');
    host = await remoteHost(t, account(), options);
    let attached = await (await host.as('owner-token')).attach(submitted.ref);
    await wait(attached, 'waiting_checkpoint');
    reviewer = await host.as('reviewer-token');
    const [effect] = (await reviewer.checkpoints()).items;
    assert.equal(effect.kind, 'effect_set');
    assert.deepEqual(provider.snapshot().sourceProviderOpens,
      [installation.databases.left, installation.databases.right]);
    assert.equal(captures, 1);
    assert.deepEqual(sends, []);
    httpPhase('effect_review');
    await reviewer.resolveCheckpoints([{checkpoint: effect, decision: 'approved'}], {
      signer: {...signer, authorityScopeCid: submitted.ref.authorityScopeCid}});
    await host.close();
    httpPhase('effect_restore');
    host = await remoteHost(t, account(), options);
    attached = await (await host.as('owner-token')).attach(submitted.ref);
    await wait(attached, 'succeeded');
    const original = await (await host.as('owner-token')).lookupSubmission(submissionRef);
    assert.equal(original.kind, 'ready');
    assert.deepEqual(original.submissionRef, submissionRef);
    assert.deepEqual(original.admission.ref, submitted.ref);
    assert.deepEqual(await attached.result('answer').all(), [
      {id: 1, left_amount: 10, right_amount: 100},
      {id: 2, left_amount: 20, right_amount: 200}]);
    assert.deepEqual((await attached.result('answer').describe()).columns, [
      {name: 'id', contract: {type: 'number', nullable: false}},
      {name: 'left_amount', contract: {type: 'number', nullable: true}},
      {name: 'right_amount', contract: {type: 'number', nullable: true}}]);
    assert.deepEqual(provider.snapshot().sourceProviderOpens,
      [installation.databases.left, installation.databases.right]);
    assert.equal(captures, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await host.close();
  });
}

for (const outcome of ['success', 'ordered', 'unknown', 'cancel', 'reject']) {
const lostReply = outcome === 'unknown';
test(outcome === 'cancel' || outcome === 'reject'
  ? `acquired Effect ${outcome} retires upstream payloads after restart`
  : lostReply ? 'acquired Effect preserves unknown across Host restart'
    : outcome === 'ordered' ? 'acquired Effect publishes a transformed Result after restart'
    : 'acquired Effect waits durably and resumes through the public Host',
  async t => {
    const crashRecovery = process.env.ACTQL_TEST_HOST_CRASH_PHASE === 'recover';
    const directory = process.env.ACTQL_TEST_HOST_CRASH_ROOT ??
      await mkdtemp(join(scratch, 'acquired-effect-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = crashRecovery ? join(directory, 'source-profile.json')
      : await installedReadFixture(directory);
    const fixture = await effectFixture({twoMembers: true});
    const program = JSON.parse(readDocument);
    delete program.params;
    program.stages = program.stages.slice(0, 2);
    program.stages[0].steps[0].filter = 'id > 0';
    program.stages[1].steps[0].filter = 'id < 3';
    program.stages[1].results = {rows: {from: 'out', fields: ['id']}};
    program.stages[1].effects = JSON.parse(fixture.document).stages[0].effects;
    program.results = {answer: {from: {stage: 'compute_a', result: 'rows'}}};
    if (outcome === 'ordered') {
      program.stages[1].results.ordered = {
        from: 'out', fields: ['id'], order_by: [{id: 'desc'}],
      };
      program.results.answer.from.result = 'ordered';
    }
    const expectedRows = outcome === 'ordered'
      ? [{id: 2}, {id: 1}] : [{id: 1}, {id: 2}];
    const sends = [];
    const diagnostics = [];
    let captures = 0;
    let recoveries = 0;
    const hooks = {directory, mappingCids: fixture.mappingCids, sends,
      // This case retains the acquired Result and two local Results. Keep
      // the common owner limit explicit rather than bypassing admission.
      maxInputPins: outcome === 'ordered' ? 3 : 2,
      // The final response is lost after three durable successes. This is
      // interrupted-Host recovery, not an adapter's handled row-failure case.
      loseReply: (member, row) => lostReply && member === 1 && row === 1};
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds,
    program.stages.findIndex(stage => stage.effects !== undefined));
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 24),
      async prepareCaptured(facts) {
        captures++;
        try { return await managed.stage(facts, false,
          owned => prepareReferenceCapture(facts, {...hooks, ...owned})); }
        catch (error) {
          diagnostics.push({name: 'capture_failure', stack: error.stack,
            cause: error.cause});
          throw error;
        }
      },
      prepareRecovered(facts) {
        recoveries++;
        return managed.stage(facts, true,
          owned => prepareReferenceRecovery(facts, {...hooks, ...owned}));
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
    const options = {directory, effectInstallation,
      ...(outcome === 'cancel' ? {sourceProfilePaths: [await unusedTableFixture(directory, 'unused-first'),
        sourceProfilePath, await unusedTableFixture(directory, 'unused-last')],
      resolveSourceSecret() { assert.fail('UnusedSourceSecret'); }} : {sourceProfilePath})};
    const account = () => {
      const configuration = JSON.parse(effectCommitConfiguration());
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      configuration.entries.push({entry_id: 'owner-read', outcome: 'allow',
        principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []});
      configuration.entries.sort((a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0);
      return protectedHost(undefined, {
        accountConfiguration: canonicalJson(configuration),
        observe: (name, detail) => diagnostics.push({name, detail}),
      });
    };
    const first = await remoteHost(t, account(), options);
    const client = await first.as('owner-token');
    const originalSubmissionPath = join(directory, 'original-submission.json');
    const submissionRef = crashRecovery
      ? JSON.parse(await readFile(originalSubmissionPath, 'utf8'))
      : client.newSubmission({nonce: 'acquired-effect'});
    if (!crashRecovery) await writeFile(originalSubmissionPath, JSON.stringify(submissionRef));
    if (crashRecovery) {
      const found = await client.lookupSubmission(submissionRef);
      assert.equal(found.kind, 'ready');
      assert.deepEqual(found.submissionRef, submissionRef);
      const execution = await client.attach(found.admission.ref);
      const state = await execution.status();
      assert.equal(state.status, 'needs_reconciliation');
      assert.deepEqual(state.next_action,
        {kind: 'reconcile_run', reason: 'execution_unknown'});
      assert.deepEqual((await (await first.as('reviewer-token')).checkpoints()).items, []);
      const publication = join(directory, 'state', 'publication');
      await waitFor(async () => (await readdir(join(publication,
        'effect-capture-custody'))).length === 0);
      assert.deepEqual(await readdir(join(publication, 'physical-holdings')), []);
      assert.deepEqual(await readdir(join(publication, 'objects')), []);
      const duplicate = await client.startSource(canonicalJson(program),
        {format: 'json', submissionRef});
      assert.deepEqual(duplicate.ref, found.admission.ref);
      assert.equal((await duplicate.status()).status, 'needs_reconciliation');
      assert.equal(captures, 0);
      assert.equal(recoveries, 0);
      assert.deepEqual(sends, []);
      await first.close();
      const reopened = await remoteHost(t, account(), options);
      const repeated = await reopened.as('owner-token');
      const original = await repeated.lookupSubmission(submissionRef);
      assert.equal(original.kind, 'ready');
      assert.deepEqual(original.submissionRef, submissionRef);
      assert.deepEqual(original.admission.ref, found.admission.ref);
      assert.equal((await (await repeated.attach(original.admission.ref)).status()).status,
        'needs_reconciliation');
      await reopened.close();
      return;
    }
    const execution = await client.startSource(
      canonicalJson(program), {format: 'json', submissionRef});
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
      const original = await (await finalHost.as('owner-token')).lookupSubmission(submissionRef);
      assert.equal(original.kind, 'ready');
      assert.deepEqual(original.submissionRef, submissionRef);
      assert.deepEqual(original.admission.ref, execution.ref);
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
      assert.deepEqual(await attached.result('answer').all(), expectedRows);
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
        expectedRows);
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds,
    program.stages.findIndex(stage => stage.effects !== undefined));
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 24),
      prepareCaptured(facts) {
        captures++;
        return managed.stage(facts, false,
          owned => prepareReferenceCapture(facts, {...hooks, ...owned}));
      },
      prepareRecovered(facts) {
        recoveries++;
        return managed.stage(facts, true,
          owned => prepareReferenceRecovery(facts, {...hooks, ...owned}));
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
      configuration.entries.push({entry_id: 'owner-read', outcome: 'allow',
        principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []});
      configuration.entries.sort((a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0);
      return protectedHost(undefined, {accountConfiguration: canonicalJson(configuration)});
    };
    const first = await remoteHost(t, account(), options);
    const client = await first.as('owner-token');
    const healthy = await client.startSource(document, {format: 'json', submissionRef: client.newSubmission({nonce: 'healthy'})});
    assert.equal((await healthy.wait()).status, 'succeeded');
    const expectedRows = await healthy.result('answer').all();
    const damaged = await client.startSource(canonicalJson(program),
      {format: 'json', submissionRef: client.newSubmission({nonce: 'damaged'})});
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
    const damagedRun = await (await resumed.as('owner-token')).attach(damaged.ref);
    await waitFor(async () => (await damagedRun.status()).status === 'failed');
    assert.equal(captures, 1);
    assert.equal(recoveries, 0, 'reject damaged custody before provider recovery');
    assert.deepEqual(sends, []);
    assert.deepEqual(await attached.result('answer').all(), expectedRows);
    await resumed.close();
    const remaining = await Promise.all((await readdir(holdingPath))
      .map(async name => JSON.parse(await readFile(join(holdingPath, name)))));
    assert.equal(remaining.some(holding =>
      ['effect-source', 'effect-capture'].includes(holding.namespace)), false,
    'the failed unsent capture is retired without consuming damaged bytes');
  });
}

test('one installed Host reads and applies independent Effects', async t => {
  const directory = await mkdtemp(join(scratch, 'source-effect-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const sourceProfilePath = await installedReadFixture(directory);
  const fixture = await effectFixture({twoMembers: true});
  const sends = [];
  const hooks = {directory, mappingCids: fixture.mappingCids, sends};
  const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
    'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
  const effectInstallation = createInstalledEffectSite({
    prepareManagedPlan: managed.prepareManagedPlan,
    environmentWire: fixture.environmentWire,
    privateEvidenceKey: Buffer.alloc(32, 16),
    prepareCaptured: facts => managed.stage(facts, false,
      owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
    prepareRecovered: facts => managed.stage(facts, true,
      owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
  });
  const options = {directory, sourceProfilePath, effectInstallation};
  const account = () => {
    const configuration = JSON.parse(effectCommitConfiguration(
      'allow', 'allow', ['answer', 'b']));
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {all: true};
    return protectedHost(undefined,
      {accountConfiguration: canonicalJson(configuration)});
  };
  const first = await remoteHost(t, account(), options);
  const client = await first.as('owner-token');
  const read = await client.startSource(readDocument, {format: 'json',
    submissionRef: client.newSubmission({nonce: 'coinstalled-read'}), parameters: {minimum: 1}});
  assert.equal((await read.wait()).status, 'succeeded');
  assert.deepEqual((await read.result('b').all()).map(row => row.id)
    .sort(), [2, 3, 3]);
  const effect = await client.startSource(fixture.document, {format: 'json',
    submissionRef: client.newSubmission({nonce: 'coinstalled-effect'})});
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

test('coinstalled historical read and current commit approvals survive the same Host restart',
  async t => {
    const directory = await mkdtemp(join(scratch, 'source-effect-held-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const sourceProfilePath = await installedReadFixture(directory,
      'delegate');
    const fixture = await effectFixture();
    const sends = [];
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 17),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const options = {directory, sourceProfilePath, effectInstallation};
    const account = (extra = {}) => {
      const configuration = JSON.parse(effectCommitConfiguration(
        'allow', 'delegate', ['answer', 'b']));
      configuration.entries[1].connection = {all: true};
      configuration.entries[1].resource = {all: true};
      return protectedHost(undefined, {...extra,
        accountConfiguration: canonicalJson(configuration)});
    };
    const first = await remoteHost(t, account({resumeAfterAnswer: false}),
      options);
    const client = await first.as('owner-token');
    const [historicalRead] = await historicalFixtureWriters.get(client)([
      {requestId: 'coinstalled-held-read', document: readDocument}]);
    const waitingRead = await client.lookupRequest(historicalRead.requestId);
    assert.equal(waitingRead.state, 'waiting_checkpoint');
    assert.equal(waitingRead.checkpoint.checkpointCid, historicalRead.checkpointCid);
    assert.deepEqual(journalRows(directory, 'SELECT run_id FROM runs'), []);
    const effectSubmissionRef = client.newSubmission({nonce: 'coinstalled-held-effect'});
    const effect = await client.startSource(fixture.document, {format: 'json', submissionRef: effectSubmissionRef});
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
    assert.equal(readLookup.ref.authorityScopeCid, historicalRead.authorityScopeCid);
    assert.deepEqual((await resumedClient.lookupSubmission(effectSubmissionRef)).admission.ref, effect.ref);
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 18),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const configuration = JSON.parse(effectCommitConfiguration(
      'allow', 'allow'));
    configuration.entries[1].connection = {all: true};
    configuration.entries[1].resource = {all: true};
    const host = await remoteHost(t, protectedHost(undefined,
      {accountConfiguration: canonicalJson(configuration)}),
    {directory, sourceProfilePath, effectInstallation});
    const client = await host.as('owner-token');
    await assertPreparationRefused(client, readDocument,
      client.newSubmission({nonce: 'coinstalled-denied-read'}), 'ACTQL_E_ACCOUNT_DENIED',
      {parameters: {minimum: 1}});
    const applied = await client.startSource(fixture.document, {format: 'json',
      submissionRef: client.newSubmission({nonce: 'coinstalled-allowed-effect'})});
    await waitFor(async () => (await applied.status()).status ===
      'succeeded');
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await closeRetainedStoreFixtureHost(host, t);
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 10),
      prepareCaptured(facts) {
        captures++;
        return managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned}));
      },
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration('allow', 'allow')});
    const first = await remoteHost(t, account, {directory,
      effectInstallation: installed, beforeDispatch: () => barrier});
    const submissionClient = await first.as('owner-token');
    const run = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'effect-barrier-wait'})});
    assert.equal(captures, 0);
    assert.deepEqual(sends, []);
    release();
    await waitFor(async () => (await run.status()).status === 'succeeded');
    assert.equal(captures, 1);
    assert.deepEqual(sends, [[0, 0], [0, 1]]);
    await closeRetainedStoreFixtureHost(first, t, true);

    let refusedCaptures = 0;
    const refused = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
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
    const deniedClient = await denied.as('owner-token');
    const rejected = await deniedClient.startSource(fixture.document, {format: 'json',
      submissionRef: deniedClient.newSubmission({nonce: 'effect-barrier-refused'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 9),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = () => protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration('allow', 'deny')});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submissionClient = await first.as('owner-token');
    const submitted = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'effect-direct-deny-a'})});
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
        const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
          'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
        const effectInstallation = createInstalledEffectSite({
          prepareManagedPlan: managed.prepareManagedPlan,
          environmentWire: fixture.environmentWire,
          privateEvidenceKey: Buffer.alloc(32, 11),
          prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
          prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
        });
        const account = () => protectedHost(undefined, {
          accountConfiguration: effectCommitConfiguration(),
          resumeAfterAnswer: false,
        });
        const first = await remoteHost(child, account(), {directory,
          effectInstallation});
        const submissionClient = await first.as('owner-token');
        const run = await submissionClient.startSource(fixture.document, {format: 'json',
          submissionRef: submissionClient.newSubmission({nonce: `effect-retire-${outcome}`})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 12),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = () => protectedHost(undefined, {
      accountConfiguration: effectCommitConfiguration(),
      checkpointTtlMs: 1000, leaseMs: 1000,
    });
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submissionClient = await first.as('owner-token');
    const run = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'effect-expiry-retirement'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 6),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = (commit = 'delegate', extra = {}) =>
      protectedHost(undefined, {...extra,
        accountConfiguration: effectCommitConfiguration('allow', commit)});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submissionClient = await first.as('owner-token');
    const submitted = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'current-deny-a'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 5),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = () => protectedHost(undefined, {
      accountConfiguration: effectCommitConfiguration(),
      observe: (name, detail) => diagnostics.push({name, detail}),
    });
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submissionClient = await first.as('owner-token');
    const submitted = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'effect-reply-loss-a'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 7),
      prepareCaptured: facts => managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned})),
      prepareRecovered: facts => managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned})),
    });
    const account = () => protectedHost(undefined,
      {accountConfiguration: effectCommitConfiguration()});
    const first = await remoteHost(t, account(), {directory,
      effectInstallation});
    const submissionClient = await first.as('owner-token');
    const submitted = await submissionClient.startSource(fixture.document, {format: 'json',
      submissionRef: submissionClient.newSubmission({nonce: 'row-failure-a'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = {
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 4),
      async execute({openComputation, control, ref, runDefinition,
        publicationPlan, effectAuthorization, retainExecution}) {
        computes++;
        assert.equal(publicationPlan.runDefinition.identity,
          runDefinition.identity);
        assert.equal(publicationPlan.results.length, 1);
        assert.ok(publicationPlan.invocation.identity);
        const subjectCid = subjectFor(ref);
        const {execution} = await openComputation();
        retainExecution(execution);
        const runId = control.runDefinitionRunId(runDefinition);
        const gate = await effectAuthorization({runId,
          runDefinitionCid: runDefinition.identity, unitId: 'values',
          declaredResults: ['answer'],
          reviewWire: canonicalJson({effect: 'save', rows: 2}),
          projectReview: checkpointEffectReviewDouble(control,subjectCid),
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
    const submissionRef = client.newSubmission({nonce: 'effect-commit-a'});
    const execution = await client.startSource(fixture.document, {format: 'json',
      submissionRef});
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
    const found = await restartedClient.lookupSubmission(submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.submissionRef, submissionRef);
    assert.deepEqual(found.admission.ref, originalRef);
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
    assert.deepEqual((await restartedClient.startSource(fixture.document,
      {format: 'json', submissionRef})).ref, originalRef);
    await third.close();
    const fourth = await remoteHost(t, authorization,
      {directory, effectInstallation});
    const lastClient = await fourth.as('owner-token');
    assert.equal((await (await lastClient.attach(originalRef)).status()).status,
      'needs_reconciliation');
    assert.equal(sends, 1);
    assert.equal(computes, 1);
    const cancelledRun = await lastClient.startSource(fixture.document,
      {format: 'json', submissionRef: lastClient.newSubmission({nonce: 'effect-cancel-a'})});
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
    const approvedThenCancelled = await lastClient.startSource(fixture.document,
      {format: 'json', submissionRef: lastClient.newSubmission({nonce: 'effect-approved-cancel-a'})});
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
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)), fixture.effectIds);
    const effectInstallation = {
      prepareManagedPlan: managed.prepareManagedPlan,
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
    const run = await client.startSource(fixture.document,
      {format: 'json', submissionRef: client.newSubmission({nonce: 'effect-target-read-deferred'})});
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
    await heldRequests(client, ['batch-a', 'batch-b']);
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
      const explanation = explainRequestLookup(lookup);
      assert.equal(explanation.preparationState, 'ended', '[check-mutation:request-ended-public]');
      assert.equal(explanation.summary, 'The Host reports that preparation of this held request ended. No Run reference was returned.');
      assert.equal(explanation.next.requestId, summary.subject.requestId);
      for (const field of ['runStatus', 'stopped', 'notAccepted', 'endReason', 'terminalErrorCode']) {
        assert.equal(Object.hasOwn(explanation, field), false);
      }
    }
    assert.equal(host.dispatches(), 0);
  });

// These finite originals are synthetic historical-format recovery inputs.
// Current public ingress cannot produce a new pre-Run hold from a bare ID.
async function heldRequests(client, ids) {
  const seed = historicalFixtureWriters.get(client);
  assert.equal(typeof seed, 'function');
  await seed(ids.map(requestId => {
    const changed = JSON.parse(document);
    changed.id = requestId;
    return {requestId, document: JSON.stringify(changed)};
  }));
  for (const requestId of ids) {
    const original = await client.lookupRequest(requestId);
    assert.equal(original.kind, 'held');
    assert.equal(original.state, 'waiting_checkpoint');
    assert.equal(Object.hasOwn(original, 'ref'), false);
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

// DCI-R7 current recovery: observing and attaching the historical original
// never starts it outside resumed authorization. A restart claiming that
// unresolved history needs its original Ref; ordinary named submission is
// a separate domain, not legacy submission acceptance.
async function resubmittedWhileStalled(t, {leaseMs = 60_000,
  checkpointTtlMs, wait = 0, untilExpired = false}) {
  const steps = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  t.after(() => released());
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
  const historical = await client.lookupRequest('again-a');
  assert.equal(historical.kind, 'held');
  const items = await allCheckpoints(reviewer);
  await approveAll(reviewer, items);
  await waitFor(() => steps.includes('definition_admitted'));
  // Past the Checkpoint's own answer deadline (which bounds the approval),
  // measured from the Host's record rather than from test start.
  const until = untilExpired ? Date.parse(items[0].expiresAt) + 300
    : Date.now() + wait;
  await new Promise(resolve => setTimeout(resolve,
    Math.max(0, until - Date.now())));
  const found = await client.lookupRequest('again-a');
  assert.equal(found.kind, 'found');
  const again = await client.attach(found.ref);
  await assert.rejects(client.startSource(document, {format: 'json', requestId: 'again-a',
    unresolvedHistory: historical}),
    {code: 'SubmissionReferenceRequired'});
  // Original lookup/attach starts nothing outside the approved resume claim.
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

test('historical lookup after approval expiry starts nothing',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t,
      {checkpointTtlMs: 8000, untilExpired: true});
    assert.equal(starts, 0);
    assert.equal(state.status, 'failed');
  });

test('historical lookup during a valid resume starts the Run at most once',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t, {});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
  });

test('historical lookup while the resuming claim lapses starts the Run once',
  async t => {
    const {state, starts, steps} = await resubmittedWhileStalled(t,
      {leaseMs: 1000, wait: 1300});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
    // The lapsed claim started nothing; a later claim did.
    assert.ok(steps.filter(name => name === 'resume_claimed').length >= 2);
  });

// DCI-R8 intent conflict belongs to the supported epoch-bound operation.
// Historical bare lookup is observation only and cannot replace this control.
test('same submitted identity preserves one Run and refuses changed intent', async t => {
  const host = await remoteHost(t, protectedHost('allow'));
  const client = await host.as('owner-token');
  const submissionRef = client.newSubmission({nonce: 'same-original-intent'});
  const first = await client.startSource(document, {format: 'json', submissionRef});
  assert.equal((await first.wait()).status, 'succeeded');
  assert.deepEqual(await first.result('answer').all(), [{id: 1}, {id: 2}]);
  const original = await client.lookupSubmission(submissionRef);
  assert.equal(original.kind, 'ready');
  assert.deepEqual(original.admission.ref, first.ref);
  assert.deepEqual((await client.startSource(document, {format: 'json', submissionRef})).ref, first.ref);
  const changed = JSON.parse(document);
  changed.stages[0].steps[0].values.rows = [{id: 999}];
  const changedText = JSON.stringify(changed);
  const changedAttempt = {operation: 'submit', attemptId: 'changed-intent-attempt'};
  const changedIntentCid = contentCid({version: 'actql-submitted-intent/0.1',
    intent: {kind: 'aql', input: {text: changedText, format: 'json'}, parameters: null}});
  await assert.rejects(client.startSource(changedText,
    {format: 'json', submissionRef, attemptId: changedAttempt.attemptId}), error => {
    // The Owner's invocation-bound conflict is distinct from transport
    // uncertainty and leaves the original durable submission untouched.
    assert.equal(error.code, 'SubmissionConflict');
    assert.equal(error.cause, undefined);
    assert.deepEqual(getSubmissionAttempt(error), {
      kind: 'conflict', reason: 'intent', attemptRef: changedAttempt,
      submissionRef, intentCid: changedIntentCid});
    assert.deepEqual(error.attemptRef, changedAttempt);
    assert.notEqual(changedIntentCid, original.intentCid);
    assert.equal(getSubmissionOutcome(error), undefined);
    // The closed typed response uses the ordinary control transport; an HTTP
    // success status does not convert its conflict into submission acceptance.
    assert.deepEqual(host.responses.at(-1), {
      path: '/actql/client/0.1/submit-intent', status: 200});
    assert.deepEqual(error.submissionRef, submissionRef);
    return true;
  });
  assert.deepEqual(await client.lookupSubmission(submissionRef), original);
  assert.deepEqual(await (await client.attach(first.ref)).result('answer').all(), [{id: 1}, {id: 2}]);
  assert.equal(host.dispatches(), 1);
});

test('historical original recovery refuses damaged private evidence without dispatch', async t => {
  const directory = await mkdtemp(join(scratch, 'intent-'));
  const host = await remoteHost(t, protectedHost('delegate'), {directory});
  t.after(() => rm(directory, {recursive: true, force: true}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  const reader = await host.as('reader-token');
  await heldRequests(client, ['done-a', 'held-b']);
  const items = await allCheckpoints(reviewer);
  await approveAll(reviewer, items.filter(item => item.subject.requestId === 'done-a'));
  assert.equal(await succeeded(client, 'done-a'), true);
  const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
  const ledgerOf = requestId => join(ledgers, `${items.find(item =>
    item.subject.requestId === requestId).subject.prepareAttemptId}.json`);
  const found = await client.lookupRequest('done-a');
  assert.deepEqual(await (await client.attach(found.ref)).result('answer').all(), [{id: 1}, {id: 2}]);
  // This completed Run retains its original request journal identity; private
  // continuation evidence is no longer needed to observe the published Run.
  const completedLedger = await readFile(ledgerOf('done-a'));
  await writeFile(ledgerOf('done-a'), '{broken');
  assert.deepEqual((await client.lookupRequest('done-a')).ref, found.ref);
  assert.deepEqual(await (await client.attach(found.ref)).result('answer').all(), [{id: 1}, {id: 2}]);
  await writeFile(ledgerOf('done-a'), completedLedger);
  const heldPath = ledgerOf('held-b');
  const original = await readFile(heldPath);
  const summary = items.find(item => item.subject.requestId === 'held-b');
  const review = await reader.reviewCheckpoint(summary);
  const heldOriginal = await client.lookupRequest('held-b');
  try {
    for (const [label, damage] of [
      ['corrupt', () => writeFile(heldPath, '{broken')],
      ['missing', () => rm(heldPath)],
      ['unreadable', async () => {await writeFile(heldPath, original); await chmod(heldPath, 0o000);}],
    ]) {
      await damage();
      await assert.rejects(reader.reviewCheckpoint(summary),
        {code: 'CheckpointReviewUnavailable', status: 410}, label);
      assert.equal(host.dispatches(), 1, label);
      assert.equal((await client.lookupRequest('held-b')).state, 'waiting_checkpoint', label);
      // No supplied alternate intent may become a new submission from this ID.
      const changed = JSON.parse(document);
      changed.stages[0].steps[0].values.rows = [{id: 999}];
      for (const text of [document, JSON.stringify(changed)]) {
        await assert.rejects(client.startSource(text, {format: 'json', requestId: 'held-b',
            unresolvedHistory: heldOriginal}),
          {code: 'SubmissionReferenceRequired'});
      }
    }
  } finally {
    await chmod(heldPath, 0o600).catch(() => {});
    await writeFile(heldPath, original);
  }
  assert.deepEqual((await reader.reviewCheckpoint(summary)).bytes, review.bytes);
  await approveAll(reviewer, [summary]);
  assert.equal(await succeeded(client, 'held-b'), true);
  const restored = await client.lookupRequest('held-b');
  assert.deepEqual(await (await client.attach(restored.ref)).result('answer').all(), [{id: 1}, {id: 2}]);
  assert.equal(host.dispatches(), 2);
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
    let lost;
    try {
      await assert.rejects(x.client.cancelRequest('cancel-a'), error => {
        lost = error;
        return error.code === 'CancellationUnknown' && error.requestId === 'cancel-a';
      });
    } finally { globalThis.fetch = real; }
    const lostExplanation = explainRequestCancellation(lost);
    assert.equal(lostExplanation.observation, 'outcome_unknown');
    assert.equal(lostExplanation.next.operation, 'lookupRequest');
    assert.equal(lostExplanation.next.requestId, 'cancel-a');
    const repeated = await x.client.cancelRequest('cancel-a');
    assert.deepEqual(repeated, {requestId: 'cancel-a', kind: 'already_requested'});
    const explanation = explainRequestCancellation(repeated);
    assert.equal(explanation.observation, 'already_requested');
    assert.equal(explanation.summary, 'The Host reports a previously recorded cancellation of this request. This response does not establish physical stop or resource release.');
    assert.equal(explanation.next.operation, 'lookupRequest');
    assert.equal(explanation.next.requestId, 'cancel-a');
    assert.equal(explainRequestCancellation(structuredClone(repeated)), undefined);
    assert.equal(explainRequestCancellation(lost), lostExplanation);
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
    let cancelled;
    try {
      cancelled = await x.client.cancelRequest('started-a');
      assert.equal(cancelled.kind, 'accepted');
      assert.ok(cancelled.ref !== undefined);
      const explanation = explainRequestCancellation(cancelled);
      assert.deepEqual({observation: explanation.observation, next: explanation.next,
        revision: explanation.revision}, {observation: 'accepted',
        next: {operation: 'status', ref: cancelled.ref}, revision: cancelled.revision},
      '[check-mutation:request-cancel-preparation]');
      for (const field of ['physicalStop', 'stopped', 'resourcesReleased', 'cleanupComplete']) {
        assert.equal(Object.hasOwn(explanation, field), false);
      }
      // The start was reserved first: the Run is not settled or released by
      // the request alone.
      await new Promise(resolve => setTimeout(resolve, 300));
      assert.deepEqual(journalRows(x.directory,
        'SELECT status FROM preparations'), [{status: 'run_created'}]);
      assert.deepEqual(journalRows(x.directory, 'SELECT status FROM runs'),
        [{status: 'running'}]);
      assert.deepEqual(await holdingStates(x.directory), ['held']);
    } finally { x.release(); }
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

// Child-only crash fixture. The parent chooses an exact durable row boundary;
// process.exit bypasses the installed Site's catch/finally and every normal
// cleanup path. Recovery uses the same journal, capture and approved Run.
if (process.env.ACTQL_TEST_PARTIAL_EFFECT_PHASE !== undefined) {
  test('partial Effect historical refusal crash fixture', async t => {
    const phase = process.env.ACTQL_TEST_PARTIAL_EFFECT_PHASE;
    const rowState = process.env.ACTQL_TEST_PARTIAL_EFFECT_ROW;
    const refusal = process.env.ACTQL_TEST_PARTIAL_EFFECT_REFUSAL;
    const directory = process.env.ACTQL_TEST_HOST_CRASH_ROOT;
    const recordPath = join(directory, 'partial-effect-observation.json');
    const fixture = await effectFixture();
    const sends = [], diagnostics = [], receipts = [], memberReceipts = [];
    let captureCount = 0;
    let targetInventories = 0;
    let recoveredStage;
    const constructorFailure = phase === 'constructor_failure';
    const constructorPrimary = new Error('ReferenceCaptureUnavailable');
    let commonCustody, constructorOwner, constructorRun, constructorRejected, retirement;
    let allowInputRelease = false, allowDispose = false, inputReleases = 0, ledgerCloses = 0;
    const hooks = {directory, mappingCids: fixture.mappingCids, sends};
    const managed = referenceEffectManagedFixture(await import(new URL('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js', import.meta.url)));
    let liveStage;
    const installed = createInstalledEffectSite({
      prepareManagedPlan: managed.prepareManagedPlan,
      environmentWire: fixture.environmentWire,
      privateEvidenceKey: Buffer.alloc(32, 74),
      leaseMs: 1000,
      targetReadAuthorization: {accountConfiguration: effectCommitConfiguration(),
        context: {principal: owner, contextCid: contentCid({targetFixture: directory})}},
      targetReadInventory: () => {
        targetInventories++;
        return [{readTuple: {connection: 'reference', resource: 'records', operation: 'read'},
          physicalBinding: {version: 'fixture-effect-target/0.1', mappings: [...fixture.mappingCids]}}];
      },
      async prepareCaptured(facts) {
        captureCount++;
        if (constructorFailure) {
          constructorRun = facts.managedEffect;
          try {
            return await managed.stage({...facts, retainConstructionOwner(owner) {
              constructorOwner = owner;
              facts.retainConstructionOwner({...owner, async close() {
                const before = checked(facts.moon.clientProgramInstalledManagedRunAccounting(constructorRun.value));
                const closed = await owner.close();
                if (closed) retirement = {before,
                  after: checked(facts.moon.clientProgramInstalledManagedRunAccounting(constructorRun.value))};
                return closed;
              }});
            }}, false, async owned => {
              const inputs = checked(facts.moon.clientProgramPinEffectSources(facts.checkedHost, 2));
              owned.retainInputCleanup(() => {
                inputReleases++;
                if (!allowInputRelease) return false;
                facts.moon.clientProgramReleaseEffectInputs(inputs);
                return true;
              });
              owned.controlConstruction.retainInputs(inputs);
              owned.beginConstruction();
              const ledger = referenceLedger(directory, facts.moon, facts.identity, owned.controlConstruction);
              owned.retainStageCleanup(() => {
                ledgerCloses++;
                if (!allowDispose) return false;
                ledger.close();return true;
              });
              throw constructorPrimary;
            });
          } catch (error) {constructorRejected = error;throw error;}
        }
        return managed.stage(facts, false, owned => prepareReferenceCapture(facts, {...hooks, ...owned}));
      },
      async prepareRecovered(facts) {
        assert.ok(facts.continuation.target_read_binding,
          'recovery retains the authenticated original target binding');
        if (phase === 'recover' && (refusal === 'read' || refusal === 'commit')) {
          assert.equal(facts.targetReads, undefined,
            'settlement never opens a fresh target-read authorization owner');
        } else {
          assert.deepEqual(facts.targetReads.captureBinding(), facts.continuation.target_read_binding);
        }
        const stage = await managed.stage(facts, true, owned => prepareReferenceRecovery(facts, {...hooks, ...owned}),
          () => liveStage === undefined);
        recoveredStage = liveStage = stage;
        if (phase === 'seed') {
          const dispatch = stage.apply.dispatchRow;
          const crash = () => {
            const effect = runtimeCore(facts.moon).effectApplicationControl;
            const states = stage.receipt.members.flatMap(member => member.rowOwners.map(owner =>
              effect.ledgerEntryStateCode(stage.apply.ledger.currentAdmitted(
                effect.logicalItemLocatorCid(owner.claim.locator)))));
            const locators = stage.receipt.members.flatMap(member => member.rowOwners.map(owner =>
              effect.logicalItemLocatorCid(owner.claim.locator)));
            writeFileSync(join(directory, 'partial-effect-seed.json'), JSON.stringify({states, locators,
              started: facts.checkpointJournal.hasStartedResume(facts.view.checkpointCid),
              resume: facts.checkpointJournal.currentResume(facts.view.checkpointCid)}));
            process.exit(77);
          };
          stage.apply.dispatchRow = async row => {
            if (rowState === 'prepared') crash();
            if (rowState === 'accepted' || rowState === 'unknown') {
              sends.push([row.memberIndex, row.rowIndex]);
              try {
                await captureClaimedEffectResponse({ledger: stage.apply.ledger, claim: row.claim,
                  requestCid: row.claim.canonicalRequestCid, execute: () => stage.referencePhysical(row, async () => {
                    if (rowState === 'unknown') throw new Error('ReferenceEffectReplyLost');
                    return {observation: {useCid: referenceCid('use'), statusCode: 202, body: Buffer.alloc(0)}};
                  })});
              } catch (error) {
                if (rowState !== 'unknown' || error.message !== 'ReferenceEffectReplyLost') throw error;
                const effect = runtimeCore(facts.moon).effectApplicationControl;
                const head = stage.apply.ledger.currentAdmitted(effect.logicalItemLocatorCid(row.claim.locator));
                stage.apply.ledger.append(effect.ledgerEntryWire(
                  effect.issueNextLedgerEntry(head, 'unknown', '', 4096, 64, 4)));
                crash();
              }
              const contract = {id: 'reference-operation', version: '0.1', cid: referenceCid('operation-contract')};
              stage.apply.ledger.recordAdmittedRowOutcome({claim: row.claim, preview: stage.receipt.preview,
                memberIndex: row.memberIndex, previewRowIndex: row.rowIndex, outcomeWire: canonicalJson({
                  state: 'accepted', operation_ref: {$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
                    resource_kind: 'operation', provider_namespace: 'reference',
                    provider_identity_cid: referenceCid('provider'), authority_scope_cid: referenceCid('authority'),
                    boundary_cid: referenceCid('operation-boundary'), identity_cid: referenceCid('operation')},
                  poll_contract: contract, result_schema: contract, reconciliation_contract: contract,
                  cancel_capability: 'unsupported',
                })});
              stage.apply.ledger.commitAdmittedRowOutcome({claim: row.claim, preview: stage.receipt.preview,
                memberIndex: row.memberIndex, previewRowIndex: row.rowIndex});
              stage.referenceCompleted(row);
            } else {
              await dispatch(row);
            }
            crash();
          };
        } else if (refusal === 'guard') {
          const refresh = stage.apply.refreshPreflight;
          stage.apply.refreshPreflight = async facts => ({
            ...await refresh(facts), guardVersions: [referenceCid('changed'), referenceCid('changed')],
          });
        }
        return stage;
      },
    });
    const effectInstallation = {...installed, execute(facts) {
      return installed.execute({...facts, retainExecution(owner) {
        commonCustody = owner;facts.retainExecution(owner);
      }});
    }, async resume(facts) {
      const result = await installed.resume(facts);
      if (result.result?.issuedSet !== undefined) {
        const wires = issuedEffectSetReceiptWires(result.result.issuedSet,
          recoveredStage.apply.ledger, recoveredStage.preview);
        receipts.push(JSON.parse(wires.setWire));
        memberReceipts.push(...wires.memberWires.map(wire => JSON.parse(wire)));
      }
      liveStage = recoveredStage = undefined;
      return result;
    }};
    const observationConfiguration = (read, commit) => {
      const body = JSON.parse(effectCommitConfiguration(read, commit));
      body.entries.push({entry_id: 'partial-run-observation', outcome: 'allow',
        principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/rows', 'run']}, operation: {any_of: ['read']}, exclusions: []});
      body.entries.sort((left, right) => left.entry_id < right.entry_id ? -1 : left.entry_id > right.entry_id ? 1 : 0);
      return canonicalJson(body);
    };
    const account = () => protectedHost(undefined, {
      accountConfiguration: observationConfiguration(
        phase === 'recover' && refusal === 'read' ? 'deny' : 'allow',
        phase === 'recover' && refusal === 'commit' ? 'deny' : 'delegate'),
      checkpointTtlMs: refusal === 'answer_deadline' ? 3000 : 30000,
      leaseMs: 1000, resumeAfterAnswer: false,
      observe: (name, detail) => diagnostics.push({name, detail}),
    });
    if (phase === 'seed' || constructorFailure) {
      let host = await remoteHost(t, account(), {directory, effectInstallation});
      const client = await host.as('owner-token');
      const submissionRef = client.newSubmission({nonce: 'partial-effect-refusal'});
      writeFileSync(join(directory, 'partial-effect-submission.json'), JSON.stringify(submissionRef));
      const run = await client.startSource(fixture.document,
        {format: 'json', submissionRef});
      if (constructorFailure) {
        await waitFor(() => constructorRejected !== undefined);
        assert.equal(constructorRejected, constructorPrimary);
        assert.equal(constructorOwner.status().pending, true);
        await assert.rejects(commonCustody.cleanup(), {code: 'InstalledEffectConstructionCleanupPending'});
        assert.equal(ledgerCloses, 0, 'live input pins precede physical/ledger cleanup');
        allowInputRelease = true;
        assert.equal(await commonCustody.cleanup(), false);
        assert.equal(constructorOwner.status().pending, true);
        assert.equal(retirement, undefined, 'a false ledger close never refunds the real constructor');
        allowDispose = true;
        assert.equal(await commonCustody.cleanup(), true);
        assert.equal(constructorOwner.status().pending, false);
        assert.equal(inputReleases >= 2, true);
        assert.equal(ledgerCloses, 2, 'the same original ledger is retried, never reopened');
        // Construction owns CapacityReservation, not a published Holding:
        // retire_installed_effect_operation -> settle_capacity -> settle_reservation.
        assert.equal(retirement.after[10], retirement.before[10] - 1n,
          'exactly the original constructor reservation retired');
        assert.equal(retirement.before[9], retirement.after[9], 'cleanup does not rewrite actual Holding count');
        assert(retirement.before[15] + retirement.before[16] > retirement.after[15] + retirement.after[16],
          'its retained backing retired');
        assert(retirement.before[17] > retirement.after[17], 'its execution backing retired');
        assert.deepEqual(retirement.before.slice(6, 8), retirement.after.slice(6, 8),
          'cleanup never resets cumulative planning or attempts');
        const settled = checked(constructorRun.runtime.clientProgramInstalledManagedRunAccounting(constructorRun.value));
        assert.equal(await commonCustody.cleanup(), true);
        assert.deepEqual(checked(constructorRun.runtime.clientProgramInstalledManagedRunAccounting(constructorRun.value)), settled);
        assert.deepEqual(sends, []);
        await host.close();
        return;
      }
      await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
      const [checkpoint] = (await (await host.as('reviewer-token')).checkpoints()).items;
      await (await host.as('reviewer-token')).resolveCheckpoints([
        {checkpoint, decision: 'approved'}], {signer: {...signer,
        authorityScopeCid: run.ref.authorityScopeCid}});
      writeFileSync(recordPath, JSON.stringify({ref: run.ref, checkpoint}));
      await host.close();
      host = await remoteHost(t, {...account(), resumeAfterAnswer: true}, {directory, effectInstallation});
      const resumed = await (await host.as('owner-token')).attach(run.ref);
      await waitFor(async () => (await resumed.status()).status === 'succeeded');
      assert.fail('the resumed physical dispatch must terminate the child at the chosen durable row boundary');
    }
    const saved = JSON.parse(await readFile(recordPath, 'utf8'));
    const seeded = JSON.parse(await readFile(join(directory, 'partial-effect-seed.json'), 'utf8'));
    const readyAt = Math.max(seeded.resume.leaseExpiresMs + 50,
      refusal === 'answer_deadline' ? Date.parse(saved.checkpoint.expiresAt) + 50 : Date.now());
    await new Promise(resolve => setTimeout(resolve, Math.max(0, readyAt - Date.now())));
    const host = await remoteHost(t, {...account(), resumeAfterAnswer: true}, {directory, effectInstallation});
    const client = await host.as('owner-token');
    const submissionRef = JSON.parse(await readFile(join(directory, 'partial-effect-submission.json'), 'utf8'));
    const original = await client.lookupSubmission(submissionRef);
    assert.equal(original.kind, 'ready');
    assert.deepEqual(original.submissionRef, submissionRef);
    assert.deepEqual(original.admission.ref, saved.ref);
    const run = await client.attach(saved.ref);
    let state;
    await waitFor(async () => {
      state = await run.status();
      return ['succeeded', 'failed', 'needs_reconciliation'].includes(state.status);
    }).catch(async error => {
      error.message = JSON.stringify({state: await run.status(), sends, receipts, diagnostics});
      throw error;
    });
    await host.close();
    const ledgerDatabase = new DatabaseSync(join(directory, 'effect-ledger', 'effect-ledger.sqlite3'), {readOnly: true});
    let durableStates;
    try {
      const current = ledgerDatabase.prepare(`SELECT e.entry_json FROM effect_ledger_heads h
        JOIN effect_ledger_entries e ON e.entry_cid = h.entry_cid WHERE h.logical_item_locator_cid = ?`);
      durableStates = seeded.locators.map(locator => JSON.parse(current.get(locator).entry_json).state);
    } finally { ledgerDatabase.close(); }
    const restarted = await remoteHost(t, {...account(), resumeAfterAnswer: true}, {directory, effectInstallation});
    const again = await (await restarted.as('owner-token')).attach(saved.ref);
    const restartedState = await again.status();
    assert.equal(restartedState.status, state.status, 'the same durable Run outcome survives another restart');
    if (refusal === 'read' || refusal === 'commit') {
      assert.equal(state.terminal_error?.code, 'ACTQL_E_RESUME_REVALIDATION_FAILED');
      assert.equal(restartedState.terminal_error?.code, 'ACTQL_E_RESUME_REVALIDATION_FAILED');
      assert.equal(targetInventories, 0, 'settlement never restores a live target-read inventory');
    }
    await restarted.close();
    const result = {state, sends, receipts, memberReceipts, durableStates, captureCount, diagnostics};
    writeFileSync(join(directory, 'partial-effect-result.json'), JSON.stringify(result));
    assert.equal(captureCount, 0, 'recovery never recomputes the original input');
    // Effect attestations have no expiry field. The resolved Checkpoint's
    // answer deadline is not a revocation of its already committed approval.
    if (refusal === 'none' || refusal === 'answer_deadline') {
      assert.equal(state.status, 'succeeded');
      assert.deepEqual(sends, [[0, 1]], 'only the original proven-unsent row may continue');
      assert.equal(receipts.length, 1);
      assert.equal(receipts[0].status, 'applied');
      assert.deepEqual(durableStates, ['applied', 'applied']);
      return;
    }
    assert.deepEqual(sends, [], 'recovery never resends an applied or refused row');
    assert.deepEqual(durableStates, [rowState, 'prepared'], 'previous sends and unsent intents remain distinct');
    assert.equal(state.status, rowState === 'unknown' ? 'needs_reconciliation' : 'failed');
    if (rowState === 'prepared' && refusal === 'guard') {
      assert.deepEqual(receipts, []);
    } else {
      assert.equal(receipts.length, 1, 'the common owner must issue the complete row partition');
      assert.equal(receipts[0].status, rowState === 'unknown' ? 'unknown_outcome'
        : rowState === 'prepared' ? 'failed' : 'partial_failure');
      assert.equal(memberReceipts.length, 1);
      assert.deepEqual(memberReceipts[0].rows.map(row => row.state),
        [rowState === 'prepared' ? 'unattempted' : rowState, 'unattempted']);
    }
  });
}
