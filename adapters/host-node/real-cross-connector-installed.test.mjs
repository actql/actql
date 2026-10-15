// Opt-in real-system acceptance. The parent installs normal release packages
// and copies only this authored harness/oracle closure into a fresh application.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {promisify} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';
import {tableTestModule} from './fixtures/table-test-modules.mjs';
import {selectRealCrossConnectorControl} from '../../scripts/fixtures/real-cross-connector-control.mjs';
import {checkRealRoutePreview} from '../../scripts/fixtures/real-cross-connector-preview.mjs';
import {observeInstalledGcsMetadata, observeInstalledDuckDbReads}
  from '../../scripts/fixtures/real-cross-connector-observation.mjs';
import {checkGcsMetadataAcceptanceEnvironment, createGcsMetadataAcceptanceCredential}
  from '../../scripts/gcs-files-content-credential.mjs';

const application = process.env.ACTQL_TEST_TABLE_PACKED_APPLICATION;
const control = selectRealCrossConnectorControl(process.env.ACTQL_REAL_CONNECTOR_FORMAT);
assert(application, 'Normal installed application is required');
const require = createRequire(join(application, 'package.json'));
const {connect} = await import(require.resolve('@actql/node'));
const moon = await import(require.resolve('@actql/local-node/runtime'));
const {canonicalJson, contentCid} = await tableTestModule(null, 'adapters/host-node/local-account-config.mjs');
const {rowSourceCheckEnvironment} = await tableTestModule(null, 'adapters/host-node/installed-row-source.mjs');
const {restoreGcsSourceDeclaration} = await tableTestModule(null,
  'adapters/connectors/gcs/host/gcs-source-declaration.mjs');
const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const tableContract = JSON.parse(await readFile(new URL('../../spec/contracts/actql-table-effect.json', import.meta.url), 'utf8'));
const duckdb = require('@duckdb/node-api');
const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
const account = () => canonicalJson({version: 'actql-execution-account-config/0.1',
  account_id: 'real-cross-connector', entries: [
    {entry_id: 'effect', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['table-local']}, resource: {any_of: ['rows']},
      operation: {any_of: ['effect']}, exclusions: []},
    {entry_id: 'run', outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []},
  ]});
function tableDeclaration() {
  const body = JSON.parse(baseWire), manifest = withFixtureConnector(body, targetRef);
  const targetSchema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}}, nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: manifest, conversions: [], mapping_ref: mappingRef,
    minimum_approval: 'required', permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id', required_fields: [],
    required_permissions: [], resource_identity_cid: contentCid(tableContract),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}}, schema: 'actql.mapping_contract/0.1',
    target_ref: targetRef, target_schema: targetSchema, target_schema_identity: contentCid(targetSchema),
    version: 'reference-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = contentCid(mapping); body.mapping_contracts = [mapping];
  delete body.evidence_bundle_cid;
  return {mapping, wire: canonicalJson({...body, evidence_bundle_cid: contentCid(body)})};
}
function commits(catalog) {
  const db = new DatabaseSync(catalog.database, {readOnly: true});
  try { return db.prepare('SELECT request_wire,receipt_wire FROM actql_table_commits ORDER BY request_cid').all()
    .map(value => ({operation: JSON.parse(value.request_wire), receipt: JSON.parse(value.receipt_wire)})); }
  finally { db.close(); }
}
async function waitForApproval(run, signal) {
  for (;;) {
    signal.throwIfAborted(); const state = await run.status({signal});
    if (state.status === 'waiting_checkpoint') return state;
    assert(!['failed', 'cancelled', 'needs_reconciliation', 'succeeded'].includes(state.status),
      'Expected original approval checkpoint');
    await delay(20, undefined, {signal});
  }
}

test('normal installed real DuckDB and GCS metadata JOIN survives approved Iceberg write and separate Host restart', async t => {
  const manifest = checkGcsMetadataAcceptanceEnvironment(JSON.parse(await readFile(
    process.env.ACTQL_REAL_CONNECTOR_SCOPE, 'utf8')));
  const f = await tablePhysicalFixture(t, undefined, {preserve: true});
  const recordPath = join(f.root, 'real-cross-connector-observation.json');
  const record = {name: control.name, format: control.format, pid: process.pid, root: f.root, completed: false,
    externalAuthInternalHttp: 'Unmeasured trusted auth; separate from actual GCS metadata transport',
    submissionCalls: 0, acceptedRunsObserved: 0, independentExpected: control.expected};
  const save = () => writeFile(recordPath, JSON.stringify(record, null, 2)+'\n', {mode: 0o600});
  await save();
  const database = join(f.root, 'source.duckdb');
  const instance = await duckdb.DuckDBInstance.create(database);
  let connection;
  try {
    connection = await instance.connect(); await connection.run(control.duckdbDDL);
    for (const row of control.duckdbRows) await connection.run('INSERT INTO records VALUES (?, ?)', [...row]);
  } finally { connection?.closeSync(); instance.closeSync(); }
  const sourceSchemaWire = canonicalJson(control.sourceSchema);
  const restored = moon.clientProgramRowSourceRestoreRelationDeclaration('duckdb-route', 'duckdb', 'duckdb/0.1',
    JSON.stringify({views: [{resource: 'records', resource_kind: 'table', schema_wire: sourceSchemaWire,
      schema_cid: contentCid(control.sourceSchema), facts_wire: '{}'}]}), undefined);
  assert.equal(restored.$tag, 1);
  const duckDeclaration = JSON.parse(moon.clientProgramRowSourceDeclarationJson(restored._0));
  const view = duckDeclaration.views[0];
  const duckdbProfilePath = join(f.root, 'duckdb-source.json');
  await writeFile(duckdbProfilePath, canonicalJson({version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef: view.source_ref,
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    checkEnvironmentWire: rowSourceCheckEnvironment(baseWire, duckDeclaration).wire,
    accountConfigurationWire: account(), queryAliases: [{name: 'records', sourceRef: view.source_ref,
      sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]}), {flag: 'wx', mode: 0o600});
  // New local proof/signing identity, not a GCP service-account key. The same
  // original bytes are retained privately for the different-process restart.
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const privateKey = keys.privateKey.export({type: 'pkcs8', format: 'pem'});
  const privateKeyPath = join(f.root, 'site-key.pem');
  await writeFile(privateKeyPath, privateKey, {flag: 'wx', mode: 0o600});
  const siteProfilePath = join(f.root, 'gcs-site.json');
  await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-gcs-site/0.1',
    credentialAuthorityId: 'real-route', credentialKeyId: 'real-route', credentialPrivateKeyPath: privateKeyPath,
    environment: 'authorized-real-route', journalRoot: join(f.root, 'credential-journal'),
    namespaceId: 'real-route', siteGeneration: 1, siteKey: 'original-local', tokenEnvironment: 'ACTQL_GCS_UNUSED_TOKEN'}),
  {flag: 'wx', mode: 0o600});
  const gcsProfile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'gcs-route',
    project: manifest.project, bucket: manifest.bucket, prefix: manifest.prefix,
    mediaType: 'text/csv', siteProfilePath, accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'real-route-metadata', entries: [{
        entry_id: 'metadata', outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {any_of: [`gcs:${manifest.project}/${manifest.bucket}`]},
        resource: {any_of: ['files']}, operation: {any_of: ['read']}}]}),
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 2, maxAttempts: 2,
      maxListingBytes: 65536, maxDurationMs: 60000, maxPathBytes: 1024,
      maxPageBytes: 32768, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 1}};
  const gcsDeclared = restoreGcsSourceDeclaration(moon, gcsProfile).declared;
  const files = gcsDeclared.views.find(value => value.resource === 'files');
  const gcsProfilePath = join(f.root, 'gcs-source.json');
  await writeFile(gcsProfilePath, JSON.stringify({...gcsProfile, queryAliases: [{name: 'docs.files',
    sourceRef: files.source_ref, sourceViewContractCid: files.view_cid, schemaContractCid: files.carrier_schema_cid}]}),
  {flag: 'wx', mode: 0o600});
  const declared = tableDeclaration(), effectProfilePath = join(f.root, 'table-effect.json');
  await writeFile(effectProfilePath, JSON.stringify({version: 'actql-installed-local-table-effect/0.1',
    connectorId: 'table', connection: 'table-local', python: process.env.ACTQL_TABLE_PYTHON,
    catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', queryName: 'analytics.report', resource: 'rows', targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create', catalogCid: f.catalog.catalogCid,
      namespace: ['test'], tableName: 'rows', expectedTable: null, permissions: ['scope:store'], footprint: {
        kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract), provider_namespace: 'table',
        provider_boundary_cid: f.catalog.catalogCid, resource_kind: 'Table', provider_object_identity_cids: []}}],
    limits: {reservation: {bytes: 1048576, files: 16}}}), {flag: 'wx', mode: 0o600});
  const diagnostics = [];
  const authorization = {accountConfiguration: account(), reviewReaders: [principalId],
    observe(category, detail) {
      if (diagnostics.length >= 32 || typeof category !== 'string' ||
          !['dispatch_failed', 'effect_start_failed', 'local_compute_failed'].includes(category) &&
          !category.endsWith('_preparation_rejected')) return;
      const item = {category};
      for (const key of ['issueTag', 'nestedIssueTag', 'requirementTag', 'task']) {
        if (Number.isSafeInteger(detail?.[key])) item[key] = detail[key];
      }
      if (typeof detail?.code === 'string' && /^[A-Za-z_]{1,96}$/u.test(detail.code)) item.code = detail.code;
      diagnostics.push(item);
    },
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey}};
  const options = {mode: 'local', owner: 'local', durability: 'durable', installation: {
    directory: join(f.root, 'host'), sourceSelectorNamespace: 'real-route-sources', sourceProfilePaths: [duckdbProfilePath, gcsProfilePath],
    effectProfilePath, authorization}};
  const credential = createGcsMetadataAcceptanceCredential(manifest, {maxResponseBytesPerCall: 32768});
  const signal = AbortSignal.timeout(credential.remainingDurationMs());
  const network = observeInstalledGcsMetadata(manifest, {signal});
  const reads = observeInstalledDuckDbReads(duckdb);
  let client;
  try {
    record.phase = 'connect';
    client = await connect({...options, installation: {...options.installation,
      resolveSourceSecret: credential.resolveSecret}});
    signal.throwIfAborted(); const submissionRef = client.newSubmission({nonce: control.name});
    record.phase = 'submission';
    record.submissionRef = submissionRef; record.submissionCalls++; await save();
    const run = await client.startSource(control.document, {format: control.format, submissionRef});
    record.acceptedRunsObserved++; record.ref = run.ref; await save();
    record.phase = 'await_checkpoint';
    const waitingState = await waitForApproval(run, signal);
    record.preApprovalAvailability = waitingState.result_availability;
    // Captured data and a declared Result are not a grant to publish before
    // the existing Effect/publication Owner completes. Record that boundary.
    await save();
    assert.deepEqual(commits(f.catalog), []);
    const checkpoints = (await client.checkpoints()).items; assert.equal(checkpoints.length, 1);
    record.phase = 'sealed_review';
    const preview = await client.reviewCheckpoint(checkpoints[0], {maxBytes: 1000000});
    const previewExpected = {catalogCid: f.catalog.catalogCid, mappingCid: declared.mapping.mapping_contract_cid};
    record.originalPreview = checkRealRoutePreview(preview, previewExpected);
    assert.equal(preview.artifactCid, checkpoints[0].reviewProjectionCid);
    await save();
    const capturedCounts = {gcs: network.observation(), duckdb: reads.observation()};
    assert.equal(capturedCounts.duckdb.sourceReadSessions, 1);
    assert(capturedCounts.gcs.requests >= 1); network.assertBounds();
    record.phase = 'initial_host_close';
    await client.close(); client = undefined;
    network.assertClosed(); credential.close();
    const restartInput = join(f.root, 'restart-approve-input.json');
    await writeFile(restartInput, JSON.stringify({phase: 'approve', format: control.format, application, options, ref: run.ref,
      principalId, manifest, approval: {checkpointCid: checkpoints[0].checkpointCid,
        previewExpected, originalPreview: record.originalPreview.identity,
        keyId: 'reviewer', reviewerId: 'reviewer', privateKey}}), {flag: 'wx', mode: 0o600});
    record.phase = 'approval_child'; await save();
    await promisify(execFile)(process.execPath, [join(application,
      'scripts/fixtures/real-cross-connector-restart.mjs'), restartInput],
    {timeout: 60000, maxBuffer: 1048576, env: {...process.env}});
    const restart = JSON.parse(await readFile(join(f.root, 'restart-observation.approve.json'), 'utf8'));
    assert.notEqual(restart.pid, process.pid); assert.deepEqual(restart.ref, run.ref);
    assert.equal(restart.format, control.format);
    assert.deepEqual(restart.observedResult, control.expected);
    assert.deepEqual(restart.reviewedPreview, record.originalPreview);
    const committedBeforeTerminalChild = commits(f.catalog);
    assert.equal(committedBeforeTerminalChild.length, 1);
    assert.equal(committedBeforeTerminalChild[0].receipt.row_count, 1);
    const terminalInput = join(f.root, 'restart-terminal-input.json');
    await writeFile(terminalInput, JSON.stringify({phase: 'terminal', format: control.format, application, options,
      ref: run.ref, principalId, manifest}), {flag: 'wx', mode: 0o600});
    record.phase = 'post_commit_terminal_child'; await save();
    await promisify(execFile)(process.execPath, [join(application,
      'scripts/fixtures/real-cross-connector-restart.mjs'), terminalInput],
    {timeout: 60000, maxBuffer: 1048576, env: {...process.env}});
    const terminalRestart = JSON.parse(await readFile(join(f.root, 'restart-observation.terminal.json'), 'utf8'));
    assert.notEqual(terminalRestart.pid, process.pid); assert.notEqual(terminalRestart.pid, restart.pid);
    assert.deepEqual(terminalRestart.ref, run.ref);
    assert.equal(terminalRestart.format, control.format);
    assert.deepEqual(terminalRestart.observedResult, control.expected);
    assert.deepEqual(terminalRestart.physicalTable, {workerStarts: 0});
    record.phase = 'committed_table_read';
    const committed = commits(f.catalog); assert.equal(committed.length, 1);
    assert.equal(committed[0].receipt.row_count, 1);
    const receipt = committed[0].receipt;
    const frozen = await f.bridge.resolveGeneration({catalog_identity_cid: f.catalog.catalogCid,
      namespace: ['test'], table_name: 'rows', table_uuid: receipt.table_uuid, schema_cid: receipt.schema_cid});
    assert.equal(frozen.ok, true);
    const rows = await f.bridge.read(frozen.result.receipt, frozen.result.mapping);
    assert.equal(rows.ok, true); assert.deepEqual(JSON.parse(JSON.stringify(rows.result)), control.expected.rows);
    // Reopen the same original Host and attach. This is not a new submission.
    record.phase = 'original_pid_control';
    client = await connect({...options, installation: {...options.installation,
      resolveSourceSecret() { assert.fail('A terminal original Run must not reacquire GCS'); }}});
    const attached = await client.attach(run.ref);
    assert.equal((await attached.status()).status, 'succeeded');
    assert.deepEqual(await attached.result('joined').all(), control.expected.rows);
    assert.deepEqual(network.observation(), capturedCounts.gcs);
    assert.deepEqual(reads.observation(), capturedCounts.duckdb);
    assert.equal(commits(f.catalog).length, 1);
    record.operationCompleted = true; record.capturedCounts = capturedCounts;
    record.credential = credential.observation(); record.restart = restart; record.terminalRestart = terminalRestart; record.diagnostics = diagnostics;
    record.tableRowCount = 1; record.catalogCommits = 1; record.additionalSourceRequests = 0;
    await save();
  } catch (error) {
    const code = typeof error?.code === 'string' && /^[A-Za-z0-9_]{1,96}$/u.test(error.code)
      ? error.code : 'Unclassified';
    record.failure = {code}; record.gcs = network.observation(); record.duckdb = reads.observation();
    record.credential = credential.observation(); record.diagnostics = diagnostics; await save();
    throw new Error(`RealCrossConnectorAcceptance:${code}`);
  } finally {
    let cleanupError;
    try {
      if (client) await client.close();
      record.clientCloseResolved = true;
    } catch {
      record.clientCloseResolved = false;
      cleanupError = new Error('RealCrossConnectorClientCleanupPending');
    } finally {
      credential.close();
      record.credentialAfterClose = credential.observation();
      try { reads.close(); }
      catch { cleanupError ??= new Error('RealCrossConnectorReadObservationCleanupPending'); }
      try { network.close(); record.physicalRequestCustodyClosed = true; }
      catch { record.physicalRequestCustodyClosed = false;
        cleanupError ??= new Error('RealCrossConnectorRequestCustodyPending'); }
      if (cleanupError) record.cleanupPending = true;
      await save();
    }
    if (cleanupError) throw cleanupError;
  }
  record.completed = true; await save();
  console.log('REAL_CROSS_CONNECTOR_RESULT ' + JSON.stringify({root: f.root,
    completed: record.completed, ref: record.ref, expected: control.expected,
    capturedCounts: record.capturedCounts, restart: record.restart, terminalRestart: record.terminalRestart,
    tableRowCount: 1, catalogCommits: 1, additionalSourceRequests: 0}));
});
