// Real normal-package A-save / B-cold-approve / C-Saved qualification. The only
// direct physical operations are synthetic Table setup and read-only oracles.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import {access, mkdir, readFile, readdir, stat, unlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {pathToFileURL} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as delay} from 'node:timers/promises';
import {tableTestAsset, tableTestModule} from '../../adapters/host-node/fixtures/table-test-modules.mjs';
import {withFixtureConnector} from '../../adapters/host-common/connector-manifest.fixture.mjs';
import {tableDependencyWidthCase, tableDependencyWidthAccount, observeTableWidthDataRecord,
  tableDependencyWidthProfiles} from './table-dependency-width-cases.mjs';
import {observeProjectEffectDependencies, dependencyBoundaryFailureData} from './project-effect-dependency-observation.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';

const [phase, handoffPath] = process.argv.slice(2);
assert(['capture', 'approve', 'saved'].includes(phase));
assert.equal(typeof handoffPath, 'string');
const selected = tableDependencyWidthCase();
const directory = process.cwd(), stateDir = join(directory, 'state');
const observationPath = join(directory, `width-${phase}.observation.json`);
const pendingPath = join(directory, `width-${phase}.pending.json`);
const censusPath = join(directory, 'width-dependencies.capture.json');
const sourceProgressPath = join(directory, `width-${phase}.source-progress.json`);
const programPath = join(directory, 'program.actql');
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const report = {phase, pid: process.pid, complete: false, submits: 0, approvals: 0,
  firstClose: 'unobserved', firstCloseCalls: 0, diagnostics: [],
  requestMemory: selected.requestMemory, sourceFreeMaxWork: selected.sourceFreeMaxWork};
const prefix = {scope: 'Observed Source event prefix; nextDeclaredSource is the authored expected order',
  started: 0, completed: 0, history: [], current: null, nextDeclaredSource: selected.resources[0]};
report.sourceProgress = prefix;
let sourceProgressFailure;
const processStartedAt = Date.now();
const retainSourceProgress = (name, detail) => {
  if (name === 'acquisition_started' || name === 'acquisition_completed') {
    const field = Object.getOwnPropertyDescriptor(detail ?? {}, 'task');
    const task = Number.isSafeInteger(field?.value) && field.value >= 0 ? field.value : undefined;
    if (name === 'acquisition_started') {
      prefix.started++;
      prefix.current = {task, declaredOrdinal: prefix.started - 1,
        expectedResource: selected.resources[prefix.started - 1] ?? null,
        startedAt: new Date().toISOString()};
    } else {prefix.completed++; prefix.current = null;}
    if (prefix.history.length < 2 * selected.expectedSourceStarts) prefix.history.push({
      event: name, task, elapsedMs: Date.now() - processStartedAt,
      started: prefix.started, completed: prefix.completed});
    prefix.nextDeclaredSource = selected.resources[prefix.completed] ?? null;
  }
  try {
    const wire = JSON.stringify({...prefix, activePhase: report.activePhase,
      observedAt: new Date().toISOString(), elapsedMs: Date.now() - processStartedAt});
    assert(Buffer.byteLength(wire) <= 16384);
    writeFileSync(sourceProgressPath, wire + '\n', {mode: 0o600});
  } catch (error) {sourceProgressFailure ??= error;}
};
const safe = value => dependencyBoundaryFailureData(value, 10);
const progress = async name => {
  report.activePhase = name; report.phaseStartedAt = new Date().toISOString();
  await save(pendingPath, report);
  retainSourceProgress();
  if (name === 'startSource') process.emit('actql-dependency-start-source-diagnostic');
};
const absent = path => assert.rejects(access(path), {code: 'ENOENT'});
const work = workflowWorkObservation({trackOriginal: true});
let original, client, primary, bridge, canonicalJson, contentCid;
const cleanup = [];
const commits = () => {
  const db = new DatabaseSync(original.catalog.database, {readOnly: true});
  try {
    return db.prepare('SELECT request_wire,receipt_wire FROM actql_table_commits ORDER BY request_cid').all()
      .map(row => ({operation: JSON.parse(row.request_wire), receipt: JSON.parse(row.receipt_wire)}));
  } finally {db.close();}
};
const census = async () => {
  const observed = await observeProjectEffectDependencies(stateDir, original.ref,
    selected.requestMemory.retainedBytes);
  assert(observed.summary.canonicalDataBodyBytes > 16 * 1024 * 1024,
    'The complete actually retained dependency DATA bodies must exceed 16 MiB after deduplication');
  assert((observed.summary.counts.relation_value ?? 0) >= selected.expectedSourceStarts);
  const values = observed.snapshot.entries.filter(entry => entry.kind === 'relation_value')
    .map(entry => ({entry, body: JSON.parse(entry.wire)}));
  const wholeSources = [];
  for (let table = 0; table < selected.expectedSourceStarts; table++) {
    const expected = new Map(selected.rowsForSource(table).map(row => [row.id, row.document]));
    const matches = values.filter(({body}) => {
      return body.sort === 'relation' && Array.isArray(body.value) && body.value.length === expected.size &&
        body.value.every(row => row && Object.keys(row).sort().join(',') === 'document,id' &&
          expected.get(row.id) === row.document) && new Set(body.value.map(row => row.id)).size === expected.size;
    });
    assert.equal(matches.length, 1, 'Every entire actual Source relation must match its independent literal dataset');
    const {entry} = matches[0];
    assert.equal(entry.cid, hash(entry.wire), 'Relation DATA preserves its canonical body identity');
    const roots = observed.snapshot.references.filter(ref => ref.kind === 'source_input_logical' &&
      ref.pointer === '/logical_relation_cid' && ref.target === entry.cid);
    assert.equal(roots.length, 1, 'Each raw relation remains referenced by its genuine Source input');
    wholeSources.push({resource: selected.resources[table], relationCid: entry.cid,
      sourceInputCid: roots[0].cid, canonicalBodyBytes: Buffer.byteLength(entry.wire)});
  }
  assert.equal(new Set(wholeSources.map(source => source.relationCid)).size, selected.expectedSourceStarts);
  report.wholeSources = wholeSources;
  if (phase === 'capture') {
    await save(censusPath, observed.snapshot); original.dependencies = observed.summary;
  } else {
    assert(isDeepStrictEqual(observed.snapshot, JSON.parse(await readFile(censusPath, 'utf8'))),
      'Every original kind/CID/canonical DATA body and CID-valued reference must survive');
    assert.deepEqual(observed.summary, original.dependencies);
  }
  report.dependencies = observed.summary;
};
const parquetFiles = async (root, result = []) => {
  for (const entry of await readdir(root, {withFileTypes: true})) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) await parquetFiles(path, result);
    else if (entry.isFile() && entry.name.endsWith('.parquet')) result.push(path);
  }
  return result.sort();
};
const summaryObservation = async () => {
  const records = commits(), summary = records.filter(row => row.operation.table_name === 'summary');
  assert.equal(summary.length, 1);
  const actual = summary[0];
  assert.equal(actual.operation.action, 'create'); assert.equal(actual.receipt.row_count, 1);
  const selector = {catalog_identity_cid: original.catalog.catalogCid, namespace: ['test'],
    table_name: 'summary', table_uuid: actual.receipt.table_uuid, schema_cid: actual.receipt.schema_cid};
  const frozen = await bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  const read = await bridge.read(frozen.result.receipt, frozen.result.mapping);
  assert.equal(read.ok, true); assert(Array.isArray(read.result));
  assert.equal(read.result.length, selected.expected.length);
  const rows = read.result.map((row, index) =>
    observeTableWidthDataRecord(row, selected.expected[index]));
  return {record: actual, rows,
    generation: observeTableWidthDataRecord(frozen.result.receipt, actual.receipt)};
};
try {
  const local = await tableTestModule(new URL('../../packages/local-node/index.mjs', import.meta.url), '@actql/local-node');
  ({canonicalJson, contentCid} = await tableTestModule(
    new URL('../../adapters/host-node/local-account-config.mjs', import.meta.url),
    'adapters/host-node/local-account-config.mjs'));
  const {createIcebergPhysicalBridge} = await tableTestModule(
    new URL('../../adapters/connectors/local/host/iceberg-process.mjs', import.meta.url),
    'adapters/connectors/local/host/iceberg-process.mjs');
  const physicalDirectory = await tableTestAsset(
    new URL('../../adapters/connectors/local/iceberg/', import.meta.url), 'adapters/connectors/local/iceberg');
  if (phase === 'capture') {
    await progress('seed-namespace');
    const python = process.env.ACTQL_TABLE_PYTHON;
    assert.equal(typeof python, 'string');
    const catalog = {database: join(directory, 'catalog.db'), warehouse: join(directory, 'warehouse'),
      catalogCid: hash('actual table dependency width catalog'), limits: selected.catalogLimits};
    const setup = spawnSync(python, ['-c',
      'import json,sys; from catalog import TableCatalog; c=json.loads(sys.argv[1]); t=TableCatalog(c["database"],c["warehouse"],c["catalogCid"],c["limits"]); t.create_namespace("test"); t.engine.dispose()',
      JSON.stringify(catalog)], {cwd: physicalDirectory, encoding: 'utf8', timeout: 20000});
    report.namespaceSetup = {status: setup.status, signal: setup.signal,
      errorCode: setup.error?.code, stderrBytes: Buffer.byteLength(setup.stderr ?? '')};
    if (setup.status !== 0) await writeFile(join(directory, 'namespace-setup.stderr'),
      setup.stderr ?? '', {mode: 0o600});
    assert.ifError(setup.error); assert.equal(setup.status, 0, 'The real fixture Catalog namespace must initialize');
    bridge = createIcebergPhysicalBridge({python: pathToFileURL(python), run: 'width-physical-setup', catalog});
    const selectors = [], seedRecords = [];
    // Physical fixture setup does not confer Program or Effect authority.
    // All Source observations are issued later by the real installed reader.
    for (let table = 0; table < selected.resources.length; table++) {
      await progress(`seed-table-${table}`);
      const rows = selected.rowsForSource(table), rowsCid = contentCid(rows);
      const body = {version: 'actql-table-operation/0.1',
        logical_request_scope_cid: hash(`physical-setup-scope-${table}`),
        effect_identity_cid: hash(`physical-setup-effect-${table}`), action: 'create',
        catalog_identity_cid: catalog.catalogCid, namespace: ['test'], table_name: selected.resources[table],
        expected_table: null, input_artifact_cid: rowsCid,
        input_carrier: {kind: 'relation', cid: rowsCid}, schema_cid: selected.schemaCid,
        storage_mapping_cid: selected.mapping.mapping_cid, data_policy_cid: hash('physical-setup-data-policy')};
      const operation = {...body, request_cid: contentCid(body)};
      const result = await bridge.execute(bridge.prepareWrite({operation, mapping: selected.mapping, rows,
        schemaWire: selected.schemaWire, reservation: selected.seedReservation}), {useCid: operation.request_cid});
      const reply = JSON.parse(result.observation.body);
      assert.equal(reply.ok, true); const receipt = reply.result;
      assert.equal(receipt.row_count, rows.length);
      seedRecords.push({operation, receipt});
      report.seededTables = seedRecords.length;
      selectors.push({catalog_identity_cid: catalog.catalogCid, namespace: ['test'],
        table_name: selected.resources[table], table_uuid: receipt.table_uuid, schema_cid: receipt.schema_cid});
    }
    const base = JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
    const tableContract = JSON.parse(await readFile(new URL('../../spec/contracts/actql-table-effect.json', import.meta.url), 'utf8'));
    const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
    const manifest = withFixtureConnector(base, targetRef);
    // Same installed Table store declaration as table-public-commit. The
    // actual whole Result schema/rows remain the Table operation's input.
    const targetSchema = {additional_properties: false,
      fields: {Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}},
      nullable: false, type: 'object'};
    const mappingBody = {connector_manifest_cid: manifest, conversions: [], mapping_ref: mappingRef,
      minimum_approval: 'required', permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
        selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id', required_fields: [],
      required_permissions: [], resource_identity_cid: contentCid(tableContract),
      row_mapping: {Name: {field: 'document_chars', null_behavior: 'reject'}},
      schema: 'actql.mapping_contract/0.1', target_ref: targetRef, target_schema: targetSchema,
      target_schema_identity: contentCid(targetSchema), version: 'reference-v1', writable_fields: ['Name']};
    const declared = {...mappingBody, mapping_contract_cid: contentCid(mappingBody)};
    base.mapping_contracts = [declared]; delete base.evidence_bundle_cid;
    const environmentWire = canonicalJson({...base, evidence_bundle_cid: contentCid(base)});
    const accountConfiguration = tableDependencyWidthAccount(userInfo().username, selected.resources);
    const profiles = tableDependencyWidthProfiles(selected, {python, catalog, selectors,
      accountConfigurationWire: accountConfiguration, environmentWire,
      mappingCid: declared.mapping_contract_cid, tableEffectContractCid: contentCid(tableContract)});
    const sourceProfilePath = join(directory, 'source.json'), effectProfilePath = join(directory, 'effect.json');
    await save(sourceProfilePath, profiles.source); await save(effectProfilePath, profiles.effect);
    const keys = generateKeyPairSync('ed25519');
    original = {case: 'table-width', catalog, python, seedRecords, sourceProfilePath, effectProfilePath,
      authorization: {accountConfiguration,
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}], reviewReaders: [userInfo().username]}};
    await writeFile(programPath, selected.source, {flag: 'wx', mode: 0o600});
    await save(handoffPath, original);
    assert.equal(commits().length, selected.resources.length);
  } else {
    original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.case, 'table-width'); assert.equal(original.captureComplete, true);
    assert.notEqual(process.pid, original.capturePid);
    if (phase === 'saved') {assert.equal(original.approveComplete, true); assert.notEqual(process.pid, original.approvePid);}
    await absent(programPath);
    for (const supplier of original.unavailableDataFiles) await absent(supplier.path);
    await census();
    assert.deepEqual(commits(), phase === 'approve' ? original.seedRecords.slice().sort(
      (a, b) => a.operation.request_cid.localeCompare(b.operation.request_cid)) : original.allCommits);
    bridge = createIcebergPhysicalBridge({python: pathToFileURL(original.python),
      run: 'width-result-oracle', catalog: original.catalog});
  }
  await progress('open');
  client = await (local.connectEmbeddedLocal ?? local.connect)({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: stateDir, sourceProfilePath: original.sourceProfilePath,
      effectProfilePath: original.effectProfilePath, observation: work.connection,
      requestMemory: selected.requestMemory, sourceFreeMaxWork: selected.sourceFreeMaxWork,
      authorization: {...original.authorization, observe(name, detail) {
        retainSourceProgress(name, detail);
        if (report.diagnostics.length < 2 * selected.expectedSourceStarts + 16) {
          report.diagnostics.push({name, detail: safe(detail)});
        }
      }}}});
  let run;
  if (phase === 'capture') {
    await progress('startSource'); report.submits++;
    run = await client.startSource(await readFile(programPath, 'utf8'),
      {format: 'json', signal: AbortSignal.timeout(180000)});
    original.ref = run.ref; await save(handoffPath, original);
    await progress('wait-checkpoint');
    report.state = await run.wait({signal: AbortSignal.timeout(180000)});
    assert.equal(report.state.status, 'waiting_checkpoint');
    const checkpoints = (await client.checkpoints()).items.filter(item => item.kind === 'effect_set');
    assert.equal(checkpoints.length, 1);
    original.checkpoint = checkpoints[0]; original.runId = report.state.run_id;
    const review = await client.reviewCheckpoint(original.checkpoint, {maxBytes: 1024 * 1024});
    original.reviewBase64 = Buffer.from(review.bytes).toString('base64');
    assert.equal(commits().length, selected.expectedSourceStarts); report.zeroWritesBeforeApproval = true;
    await census();
  } else {
    await progress('attach');
    run = await client.attach(original.ref); assert.deepEqual(run.ref, original.ref);
    let state = await run.status(); assert.equal(state.run_id, original.runId);
    if (phase === 'approve') {
      assert.equal(state.status, 'waiting_checkpoint');
      const review = await client.reviewCheckpoint(original.checkpoint, {maxBytes: 1024 * 1024});
      assert.equal(Buffer.from(review.bytes).toString('base64'), original.reviewBase64);
      await progress('approve'); report.approvals++;
      const resolved = await client.resolveCheckpoints([{checkpoint: original.checkpoint, decision: 'approved'}],
        {signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: original.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, original.authorization.hostKey.privateKey)}});
      assert.deepEqual(resolved.results.map(result => result.status), ['committed']);
      const signal = AbortSignal.timeout(180000);
      do {state = await run.status({signal});
        if (!['waiting_checkpoint', 'running', 'resuming'].includes(state.status)) break;
        await delay(20, undefined, {signal});
      } while (true);
    }
    assert.equal(state.status, 'succeeded');
    report.results = {};
    for (const name of Object.keys(selected.program.results)) {
      const expected = name === 'answer' ? selected.expected : (() => {
        const value = selected.expectedSources[Number(name.slice('source'.length))];
        return [{document_chars: value.document_chars, id_sum: value.id_sum, row_count: value.rows}];
      })();
      const rows = await run.result(name).all(); assert.deepEqual(rows, expected); report.results[name] = rows;
    }
    if (phase === 'saved') assert.deepEqual(report.results, original.results);
    await census();
    await progress('actual-table-read');
    report.target = await summaryObservation();
    assert.equal(commits().length, selected.expectedSourceStarts + 1);
    if (phase === 'saved') assert.deepEqual(report.target, original.target);
  }
} catch (error) {
  primary = error; report.failedAt = report.activePhase; report.primary = safe(error);
} finally {
  report.ref = original?.ref;
  report.workObservation = original?.ref ? work.forOriginal(original.ref) : work.snapshot();
  report.firstClose = client ? 'pending' : 'not-attempted';
  try {await progress('firstClose');} catch (error) {cleanup.push(error);}
  if (client) try {report.firstCloseCalls++; await client.close(); report.firstClose = 'returned';}
  catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  if (report.firstClose === 'returned') try {
    // Scope live product assets, not this process's cwd: lsof also lists cwd
    // and that directory is intentionally alive throughout the fixture.
    const roots = [stateDir, original.catalog.database, original.catalog.warehouse,
      original.sourceProfilePath, original.effectProfilePath];
    const before = await observeRecordApprovalDescriptors(roots); await delay(100);
    const after = await observeRecordApprovalDescriptors(roots);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (!primary && cleanup.length === 0) try {
    assert.equal(sourceProgressFailure, undefined);
    report.workObservation = work.forOriginal(original.ref);
    assert.equal(report.workObservation.complete, true);
    assert.equal(report.workObservation.sourceAcquisitionStarts,
      phase === 'capture' ? selected.expectedSourceStarts : 0);
    assert.equal(report.workObservation.modelCallStarts, 0);
    // Returned File/row replacements are not Table commit observations. The
    // actual Catalog baseline, one target publication and full physical read
    // above establish Table apply and Saved's unchanged original generation.
    assert.deepEqual(report.workObservation.unbound,
      {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
    await census();
    if (phase === 'capture') {
      original.capturePid = process.pid;
      const paths = await parquetFiles(original.catalog.warehouse);
      assert.equal(paths.length, selected.expectedSourceStarts);
      original.unavailableDataFiles = [];
      for (const path of paths) {
        const bytes = await readFile(path), metadata = await stat(path);
        original.unavailableDataFiles.push({path, bytes: metadata.size, sha256: hash(bytes)});
        await unlink(path); await absent(path);
      }
      await unlink(programPath); original.captureComplete = true;
      report.unavailableDataEntryPoint = 'All actual source generation Parquet data files removed after first close; original Catalog, metadata, profiles, schema and keys retained';
    } else if (phase === 'approve') {
      original.approvePid = process.pid; original.approveComplete = true;
      original.target = report.target; original.results = report.results; original.allCommits = commits();
    } else assert.deepEqual(commits(), original.allCommits);
    await save(handoffPath, original); report.complete = true;
  } catch (error) {cleanup.push(error);}
  report.cleanup = cleanup.map(error => safe(error));
  report.sourceProgress = prefix;
  try {await save(observationPath, report);} catch (error) {cleanup.push(error);}
}
if (primary || cleanup.length) throw Object.assign(new Error('TableDependencyWidthFailed'),
  {code: 'TableDependencyWidthFailed', primaryCode: primary?.code,
    cleanupCodes: cleanup.map(error => error?.code ?? error?.name)});
console.log(JSON.stringify({phase,complete:report.complete,dependencies:report.dependencies,
  firstClose:report.firstClose,workObservation:report.workObservation}));
