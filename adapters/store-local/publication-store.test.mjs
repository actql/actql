import './owner-atomic-publication.test.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {buildNodeDirectoryNative} from '../../scripts/build-node-directory-native.mjs';
import {
  chmod,
  link,
  mkdir,
  mkdtemp,
  open,
  readdir,
  readFile,
  rm,
  stat,
  unlink,
  utimes,
  writeFile,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve, sep} from 'node:path';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import fsPromises from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';
import {canonicalCid, createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore as openActualLocalPublicationStore,
  prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership,
  captureOriginalLocalExecutionOwner}
  from './publication-store.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {definition as captureCustodyRunFixture} from
  '../host-node/fixtures/original-plan-journal.mjs';

const fixtureStores = new Map();
async function openLocalPublicationStore(configuration, ...arguments_) {
  const store = await openActualLocalPublicationStore(configuration, ...arguments_);
  const directory = resolve(configuration.directory);
  const stores = fixtureStores.get(directory) ?? new Set();
  stores.add(store);
  fixtureStores.set(directory, stores);
  return store;
}

// Node runs registered after hooks in order. Close each original or reopened
// Store before removing its directory, rather than erasing its live lock first.
// A refused close retains the fixture and still fails the test.
async function removeFixtureDirectory(directory) {
  const root = resolve(directory);
  const owned = [...fixtureStores].filter(([path]) =>
    path === root || path.startsWith(root + sep));
  for (const [, stores] of owned) {
    for (const store of stores) {
      if (!store.status().closed) await store.close();
    }
  }
  await rm(directory, {recursive: true, force: true});
  for (const [path] of owned) fixtureStores.delete(path);
}

const contractControl = createPublicationContractControlFixture();
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});
const seal = (name, value) => JSON.parse(
  contractControl.seal(name, JSON.stringify(value), limits).wire,
);
const wire = value => JSON.stringify(value);

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const resultSchemaWire =
  '{"answer":{"nullable":false,"type":"string"}}';
const cids = Object.freeze({
  authority: digest('authority'),
  scope: digest('scope'),
  run: digest('run'),
  template: digest('template'),
  observations: digest('observations'),
  policy: digest('policy'),
  target: digest('target'),
  result: digest('result'),
  schema: digest(resultSchemaWire),
  manifest: digest('manifest'),
  receipt: digest('receipt'),
  captured: digest('captured'),
  fence: digest('fence'),
});
const code = expected => error => error?.code === expected;

// Execute the existing publication caller's exact append step with real
// Store/SQLite and explicit immutable-contract ports. This is not complete
// Common-chain or ordinary installed SDK acceptance.
const publicationSource = readFileSync(new URL('../host-common/run-publication.mjs', import.meta.url), 'utf8');
const publicationAst = parse(publicationSource, {ecmaVersion: 'latest', sourceType: 'module'});
const publicationAppend = publicationAst.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'appendState');
const publicationMember = publicationAst.body.find(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(item => item.id.name === 'member'));
assert.ok(publicationAppend); assert.ok(publicationMember);
const appendOriginalPublicationState = compileFunction(
  publicationSource.slice(publicationMember.start, publicationMember.end) + '\n' +
  publicationSource.slice(publicationAppend.start, publicationAppend.end) + '\nreturn appendState;', [])();
const publicationPersist = publicationAst.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'persistContracts');
assert.ok(publicationPersist);
const persistOriginalPublicationSetup = compileFunction(
  publicationSource.slice(publicationMember.start, publicationMember.end) + '\n' +
  publicationSource.slice(publicationPersist.start, publicationPersist.end) + '\nreturn persistContracts;', [])();
const publicationCommitLookup = publicationAst.body.find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'lookupOriginalCommit');
assert.ok(publicationCommitLookup);
const lookupOriginalPublicationCommit = compileFunction(
  publicationSource.slice(publicationMember.start, publicationMember.end) + '\n' +
  publicationSource.slice(publicationCommitLookup.start, publicationCommitLookup.end) +
  '\nreturn lookupOriginalCommit;', [])();
const publicationInitial = publicationAst.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'appendInitialStates');
const publicationInitialValues = publicationAst.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'initialPublicationStates');
assert.ok(publicationInitial); assert.ok(publicationInitialValues);
const appendOriginalInitialStates = compileFunction(
  publicationSource.slice(publicationMember.start, publicationMember.end) + '\n' +
  publicationSource.slice(publicationInitialValues.start, publicationInitialValues.end) + '\n' +
  publicationSource.slice(publicationInitial.start, publicationInitial.end) + '\nreturn appendInitialStates;', ['fail'])(code => {
    throw Object.assign(new Error(code), {code});
  });

async function runStoreChild(source) {
  const child = spawn(process.execPath, [
    '--input-type=module', '--eval', source,
  ], {stdio: ['ignore', 'pipe', 'pipe']});
  const stdout = [];
  const stderr = [];
  child.stdout.on('data', chunk => stdout.push(chunk));
  child.stderr.on('data', chunk => stderr.push(chunk));
  const [exitCode, signal] = await once(child, 'exit');
  return Object.freeze({
    exitCode,
    signal,
    stdout: Buffer.concat(stdout).toString('utf8'),
    stderr: Buffer.concat(stderr).toString('utf8'),
  });
}

async function fixture(t, options = {}, control = contractControl, physicalIO) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-store-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    ...options,
  };
  const store = await openLocalPublicationStore(configuration, control, physicalIO);
  t.after(async () => { await store.close(); });
  return {
    directory,
    configuration,
    store,
  };
}

test('fresh Store coverage shares its original native schema commit', async t => {
  const exec = DatabaseSync.prototype.exec;
  let commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT') commits++;
    return result;
  });
  const {directory, configuration, store} = await fixture(t);
  assert.equal(commits, 1, 'empty coverage belongs to the actual schema creation transaction');
  const database = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'), {readOnly: true});
  try {
    for (const table of ['coverage', 'physical_object_usage', 'publication_recovery',
      'metadata_deletion_fence_coverage']) {
      assert.equal(database.prepare(`SELECT complete FROM ${table} WHERE id=1`).get().complete, 1);
    }
    assert.equal(database.prepare('SELECT dirty FROM result_deletion_recovery WHERE id=1').get().dirty, 0);
  } finally { database.close(); }
  assert.deepEqual(JSON.parse(await readFile(join(directory, 'delivery-attempts-index.json'), 'utf8')),
    {version: 1, phase: 'ready'});
  await store.close();
  commits = 0;
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.equal(commits, 0, 'unchanged reopening neither recreates coverage nor commits a migration');
  await reopened.close();
});

test('fresh Store coverage uses the same actual prepared owner creation', async t => {
  buildNodeDirectoryNative();
  const directory = await mkdtemp(join(tmpdir(), 'actql-prepared-empty-store-'));
  let store, original;
  t.after(async () => {
    if (store !== undefined && !store.status().closed) await store.close();
    if (original !== undefined) assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
    await removeFixtureDirectory(directory);
  });
  const configuration = {directory, storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024,
    maxObjects: 100, maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
  original = await prepareLocalPublicationStoreOwnership(directory,
    {maxWireBytes: 64 * 1024, maxDirectoryEntries: 100});
  const ownerPath = join(directory, 'owner', 'owner.json');
  const owner = JSON.parse(await readFile(ownerPath, 'utf8'));
  const ownerState = await stat(ownerPath);
  let commits = 0;
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT') commits++;
    return result;
  });
  store = await openLocalPublicationStore(configuration, contractControl,
    undefined, undefined, original);
  assert.equal(commits, 1);
  const receipt = captureOriginalLocalExecutionOwner(original);
  assert.notEqual(receipt, undefined, 'adoption qualifies the original native lease');
  assert.equal(receipt.token, owner.token);
  assert.deepEqual(JSON.parse(await readFile(ownerPath, 'utf8')),
    {...owner, leaseAnchor: receipt.anchor});
  const adoptedState = await stat(ownerPath);
  assert.equal(adoptedState.dev, ownerState.dev);
  assert.notEqual(adoptedState.ino, ownerState.ino, 'lease qualification atomically replaces only its own prepared owner metadata');
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, true);
  await store.close();
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
});

for (const afterCommit of [false, true]) {
  test(`fresh Store schema keeps its ${afterCommit ? 'committed' : 'rolled-back'} initialization Unknown`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-store-initialization-unknown-'));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {directory, storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024,
      maxObjects: 100, maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
    const exec = DatabaseSync.prototype.exec;
    const originalFailure = Object.assign(new Error('initial schema COMMIT reply unavailable'), {code: 'EIO'});
    let schema = false, lost = false, creations = 0;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql.startsWith('CREATE TABLE coverage (')) {schema = true; creations++;}
      if (schema && !lost && sql === 'COMMIT') {
        lost = true;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw originalFailure;
      }
      return Reflect.apply(exec, this, [sql]);
    });
    let unknown;
    await assert.rejects(openLocalPublicationStore(configuration, contractControl), error => {
      unknown = error;
      return error.code === 'DeliveryAttemptIndexCommitOutcomeUnknown' &&
        error.outcome === 'unknown' && error.cause === originalFailure;
    });
    assert.equal(lost, true);
    assert.equal(creations, 1);
    assert.deepEqual(JSON.parse(await readFile(join(directory, 'delivery-attempts-index.json'), 'utf8')),
      {version: 1, phase: 'building'});
    await assert.rejects(stat(join(directory, 'owner')), code('ENOENT'));
    const database = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'), {readOnly: true});
    try {
      const names = database.prepare("SELECT name FROM sqlite_schema WHERE type='table'").all();
      assert.equal(names.some(row => row.name === 'coverage'), afterCommit,
        'the native transition is either wholly committed or absent');
      if (afterCommit) {
        for (const table of ['coverage', 'physical_object_usage', 'publication_recovery',
          'metadata_deletion_fence_coverage']) {
          assert.equal(database.prepare(`SELECT complete FROM ${table} WHERE id=1`).get().complete, 1);
        }
      }
    } finally {database.close();}
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    assert.equal(creations, afterCommit ? 1 : 2,
      'an already committed schema is never inserted again; a rolled-back schema keeps legacy adoption');
    assert.equal(unknown.outcome, 'unknown', 'later format completion never rewrites the original failure');
    await reopened.close();
  });
}

async function legacyInventoryFixture(directory, publicIndexCid) {
  // Compatibility-only fixture for the prior file representation. Transfer
  // this new disposable fixture's exact body before dropping its native copy;
  // production never rewrites an independently adopted representation.
  const path=join(directory,'metadata-inventories',publicIndexCid.slice(7)+'.json');
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {
    const row=database.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?').get(publicIndexCid);
    if(row!==undefined) {
      await writeFile(path,row.inventory_wire,{mode:0o600});
      const file=await open(path,'r');try{await file.sync();}finally{await file.close();}
      const parent=await open(join(directory,'metadata-inventories'),'r');
      try{await parent.sync();}finally{await parent.close();}
      database.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; BEGIN IMMEDIATE');
      assert.equal(database.prepare('DELETE FROM native_publication_inventories WHERE public_index_cid=?').run(publicIndexCid).changes,1);
      database.exec('UPDATE native_publication_inventory_usage SET entries=entries-1,ack_revision=ack_revision+1 WHERE id=1; COMMIT');
    }
  } finally {database.close();}
  return path;
}

test('unmarked and prior-format Stores are refused without changing files',
  async t => {
    const parent = await mkdtemp(join(tmpdir(), 'actql-store-format-'));
    t.after(() => removeFixtureDirectory(parent));
    const configuration = directory => ({
      directory, storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024,
      maxObjects: 100, maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    });
    for (const [name, entry, content, expected] of [
      ['prior', 'store.json', JSON.stringify({
        version: 'actql-local-publication-store/0.1',
        store_authority_cid: cids.authority,
      }), 'LegacyPublicationStoreFormat'],
      ['unmarked', 'other-file', 'unrecognized-content',
        'UnknownPublicationStoreFormat'],
    ]) {
      const directory = join(parent, name);
      await mkdir(directory);
      await writeFile(join(directory, entry), content);
      const original = await readFile(join(directory, entry));
      const names = await readdir(directory);
      await assert.rejects(openLocalPublicationStore(configuration(directory),
        contractControl), error => error.code === expected &&
          error.target === directory);
      assert.deepEqual(await readFile(join(directory, entry)), original);
      assert.deepEqual(await readdir(directory), names);
    }
  });

function invocation() {
  return seal('run_invocation', {
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cids.template,
    observation_set_cid: cids.observations,
  });
}

function resultDefinition(name = 'answer') {
  const identities = Object.freeze({
    answer:
      'sha256:74499be8f8edb305751bf9d6e4416221358fdf4ebfaf0622fcd6b42a5f7ecfea',
    other:
      'sha256:754a2835ca0889f487152547a046ef480a1adc94d5370f6836acc9f9e98d91da',
  });
  return Object.freeze({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cids.run,
    result_name: name,
    result_definition_cid: identities[name],
  });
}

function publicationRequest(result = resultDefinition(),
  runDefinitionCid = cids.run) {
  return seal('publication_request', {
    version: 'actql-publication-request/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: runDefinitionCid,
    inventory: [{
      result_name: result.result_name,
      result_definition_cid: result.result_definition_cid,
    }],
    publication_policy_cid: cids.policy,
    publication_target_cid: cids.target,
    requested_at: '2026-09-18T00:00:00.000Z',
  });
}

function publicationAttempt(request, attemptId = 'attempt-1') {
  return seal('publication_attempt', {
    version: 'actql-publication-attempt/0.1',
    publication_request_cid: request.publication_request_cid,
    run_definition_cid: request.run_definition_cid,
    attempt_id: attemptId,
    fence_cid: cids.fence,
    started_at: '2026-09-18T00:00:01.000Z',
  });
}

function publicationRecord(attempt, sequence, state, prior, extra = {}) {
  return seal('publication_record', {
    version: 'actql-publication-record/0.1',
    publication_attempt_cid: attempt.publication_attempt_cid,
    ...(prior === undefined ? {} : {
      prior_record_cid: prior.publication_record_cid,
    }),
    sequence,
    state,
    observed_at: `2026-09-18T00:00:0${sequence + 2}.000Z`,
    cleanup_owner_cids: [],
    ...extra,
  });
}

function deliveryFixture(maxUses = 2) {
  const artifactCid = digest('delivery artifact');
  const manifestCid = digest('delivery manifest');
  const grant = seal('result_read_grant', {
    version: 'actql-result-read-grant/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    principal_id: 'principal-a',
    run_definition_cid: cids.run,
    result_manifest_cid: manifestCid,
    purpose: 'download',
    data_ceiling_cid: cids.policy,
    max_bytes: 4096,
    max_uses: maxUses,
    expires_at: '2026-09-19T00:00:00.000Z',
    authorization_context_cid: cids.scope,
    results: [{
      result_name: 'answer',
      result_artifact_cid: artifactCid,
    }],
    formats: ['json', 'jsonl', 'csv'],
    egress_admission_cid: cids.target,
  });
  return {artifactCid, manifestCid, grant};
}

function manifestReadGrant(maxUses = 2) {
  return seal('manifest_read_grant', {
    version: 'actql-manifest-read-grant/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    principal_id: 'principal-a',
    run_definition_cid: cids.run,
    result_manifest_cid: cids.manifest,
    purpose: 'inspect',
    data_ceiling_cid: cids.policy,
    max_bytes: 4096,
    max_uses: maxUses,
    expires_at: '2026-09-19T00:00:00.000Z',
    authorization_context_cid: cids.scope,
  });
}

function deliveryAttempt(root, attemptId) {
  return seal('delivery_attempt', {
    version: 'actql-delivery-attempt/0.1',
    attempt_id: attemptId,
    result_read_grant_cid: root.grant.result_read_grant_cid,
    run_definition_cid: cids.run,
    result_manifest_cid: root.manifestCid,
    result_name: 'answer',
    result_artifact_cid: root.artifactCid,
    serialization_contract_cid: cids.captured,
    requested_at: '2026-09-18T01:00:00.000Z',
  });
}

function deliveryRecord(attempt, sequence, state, prior, extra = {}) {
  return seal('delivery_record', {
    version: 'actql-delivery-record/0.1',
    delivery_attempt_cid: attempt.delivery_attempt_cid,
    ...(prior === undefined ? {} : {
      prior_record_cid: prior.delivery_record_cid,
    }),
    sequence,
    state,
    confirmed_byte_count: extra.confirmed_byte_count ?? 0,
    exposure: extra.exposure ?? 'exact',
    observed_at: `2026-09-18T01:00:0${sequence}.000Z`,
    cleanup_owner_cids: [],
    ...extra,
  });
}

function indexEntry(request, attempt, invocationValue, values = {}) {
  const artifacts = physicalCapturedArtifacts(invocationValue, request);
  return seal('public_index_entry', {
    version: 'actql-public-index-entry/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: request.run_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    result_manifest_cid: artifacts.manifest.identity,
    run_receipt_cid: artifacts.receipt.identity,
    captured_run_cid: artifacts.capturedRun.identity,
    durable_result_binding_cids: values.durable_result_binding_cids ??
      [invocationValue.invocation_cid],
    publication_request_cid: request.publication_request_cid,
    publication_attempt_cid: attempt.publication_attempt_cid,
    committed_at: '2026-09-18T00:00:09.000Z',
    ...values,
  });
}

const indexKey = Object.freeze({
  namespaceId: 'namespace-a',
  authorityScopeCid: cids.scope,
  runDefinitionCid: cids.run,
});

const indexKeyFor = request => Object.freeze({
  namespaceId: request.namespace_id,
  authorityScopeCid: request.authority_scope_cid,
  runDefinitionCid: request.run_definition_cid,
});

function physicalCapturedArtifacts(invocationValue, request) {
  // Independent normative shape and canonical identity, not a Core-issued
  // authorization. The containing chain remains an explicit adapter double.
  const identified = (field, body) => ({...body, [field]: canonicalCid(body)});
  const prepared = identified('prepared_invocation_cid', {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: cids.template,
    compiled_plan_cid: cids.run,
    execution_context_cid: cids.scope,
    host_policy_cid: cids.policy,
    policy_decision: 'allow',
    expires_at: '2026-09-19T00:00:00.000Z',
  });
  const authorization = identified('run_authorization_cid', {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: prepared.prepared_invocation_cid,
    execution_context_cid: cids.scope,
    host_policy_cid: cids.policy,
    decision: 'allowed',
  });
  const observation = identified('observation_set_cid', {
    version: 'actql-observation-set/0.1',
    invocation_template_cid: cids.template,
    source_evidence_cids: [],
    captured_input_artifact_cids: [],
    consistency: 'no_external_sources',
    capture_started_at: null,
    capture_completed_at: null,
    replayability: {materialized: true, availability_evidence_cids: []},
    data_policy_cid: cids.policy,
  });
  const selected = request.inventory[0];
  const artifact = identified('result_artifact_cid', {
    version: 'actql-result-artifact/0.1',
    result_definition_cid: selected.result_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    logical_result_cid: cids.result,
    result_schema_cid: cids.schema,
    ordering_evidence_cid: cids.receipt,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cids.policy,
    effective_retention_policy_cid: cids.policy,
    provenance_evidence_cids: [],
  });
  const manifest = identified('result_manifest_cid', {
    version: 'actql-result-manifest/0.1',
    run_definition_cid: request.run_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    results: {[selected.result_name]: artifact},
  });
  const receipt = identified('receipt_identity_cid', {
    version: 'actql-run-receipt/0.1',
    compiler_version: 'fixture-0.1',
    aoa_ir_version: '0.1',
    prepared_invocation: prepared,
    run_authorization: authorization,
    program_semantics_cid: cids.run,
    program_definition_cid: cids.run,
    invocation_cid: invocationValue.invocation_cid,
    compiled_plan_cid: cids.run,
    check_environment_cid: cids.scope,
    observation_set: observation,
    observation_set_cid: observation.observation_set_cid,
    normalization_journal_cid: cids.receipt,
    aoa_logical_cid: cids.result,
    bindings: [],
    result_manifest: manifest,
    result_manifest_cid: manifest.result_manifest_cid,
    result_artifacts: {[selected.result_name]: artifact},
    source_evidence: [],
    source_evidence_cids: [],
    external_observation_evidence: [],
    barrier_attempt_receipt_cids: [],
    artifact_derivation_evidence_cids: [],
    cross_source_consistency: 'no_external_sources',
  });
  const authoring = identified('authoring_context_cid', {
    version: 'actql-authoring-context/0.1',
    program_definition_cid: cids.run,
    annotations: [],
  });
  const context = identified('effect_context_cid', {
    version: 'actql-run-effect-context/0.1',
    effects: {}, effect_plans: {}, effect_plan_logical_cids: {},
    result_values: {[selected.result_name]: [{answer: 'fixture durable Result payload'}]},
    result_artifacts: {[selected.result_name]: artifact},
    result_fields: {[selected.result_name]: ['answer']},
    pending_source_state_advances: [], authoring_context: authoring,
    model_invocation_evidence: [], model_invocation_evidence_cids: [],
    effect_source_artifacts: {}, effect_source_holding_cids: {},
    effect_source_local_inventory: {}, effect_dependency_inventory: [],
  });
  const captured = identified('captured_run_cid', {
    version: 'actql-captured-run/0.1',
    sensitivity: 'private', retention_class: 'run-evidence',
    encryption_required: true, receipt, effect_context: context,
  });
  return Object.freeze({
    manifest: contractControl.admitArtifactFixture('result_manifest', wire(manifest)),
    receipt: contractControl.admitArtifactFixture('run_receipt', wire(receipt)),
    capturedRun: contractControl.admitArtifactFixture('captured_run', wire(captured)),
  });
}

function physicalCommitEvidence(invocationValue, binding, request) {
  // This suite isolates filesystem durability and CAS behavior with the
  // independent contract-control fixture. The product integration suite uses
  // distinct real contracts and the MoonBit commit-chain verdict.
  const contract = contractControl.admit(
    'run_invocation', wire(invocationValue), limits,
  );
  return Object.freeze({
    runDefinition: contract,
    invocation: contract,
    definitions: Object.freeze([contract]),
    artifacts: Object.freeze([contract]),
    derivations: Object.freeze([contract]),
    orderings: Object.freeze([contract]),
    retentions: Object.freeze([contract]),
    durableBindings: Object.freeze([binding]),
    ...physicalCapturedArtifacts(invocationValue, request),
  });
}

test('physical commit fixture carries distinct normative CapturedRun identities', () => {
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const artifacts = physicalCapturedArtifacts(invocationValue, request);
  const captured = JSON.parse(artifacts.capturedRun.wire);
  const entry = indexEntry(request, publicationAttempt(request), invocationValue);
  assert.equal(entry.captured_run_cid, artifacts.capturedRun.identity);
  assert.equal(entry.result_manifest_cid, artifacts.manifest.identity);
  assert.equal(entry.run_receipt_cid, artifacts.receipt.identity);
  assert.equal(captured.receipt.receipt_identity_cid, artifacts.receipt.identity);
  assert.equal(captured.receipt.result_manifest_cid, artifacts.manifest.identity);
  assert.equal(captured.receipt.invocation_cid, invocationValue.invocation_cid);
  assert.equal(captured.receipt.result_manifest.run_definition_cid, request.run_definition_cid);
  assert.deepEqual(Object.keys(captured.effect_context.result_artifacts), ['answer']);
  const otherRequest = publicationRequest(resultDefinition('other'), cids.run);
  const other = physicalCapturedArtifacts(invocationValue, otherRequest);
  const otherCaptured = JSON.parse(other.capturedRun.wire);
  assert.equal(otherCaptured.receipt.result_manifest.run_definition_cid, cids.run);
  assert.deepEqual(Object.keys(otherCaptured.receipt.result_manifest.results), ['other']);
  assert.equal(otherCaptured.effect_context.result_artifacts.other.result_definition_cid,
    otherRequest.inventory[0].result_definition_cid);
  assert.notEqual(other.capturedRun.identity, artifacts.capturedRun.identity);
  assert.equal(captured.effect_context.version, 'actql-run-effect-context/0.1');
  assert.equal(new Set([invocationValue.invocation_cid, artifacts.manifest.identity,
    artifacts.receipt.identity, artifacts.capturedRun.identity]).size, 4);
  const {effect_context: omitted, captured_run_cid: priorCid, ...missing} = captured;
  assert(omitted);
  assert(priorCid);
  assert.throws(() => contractControl.admitArtifactFixture('captured_run',
    wire({...missing, captured_run_cid: canonicalCid(missing)})),
  error => error.code === 'PublicationContractRequired' && error.path === '$.effect_context');
  assert.throws(() => contractControl.admitArtifactFixture('captured_run',
    wire({...captured, captured_run_cid: invocationValue.invocation_cid})),
  code('PublicationIdentityMismatch'));
  assert.throws(() => contractControl.admitArtifactFixture('run_invocation',
    wire(invocationValue)), code('UnknownPublicationFixtureArtifact'));
});

const fixturePreparedHandles = new WeakMap();
// Fixture authority follows the exact prepareCommit result, never a CID lookup.
function commitFixtureIndex(store, wire, inventory, evidence, original, handles) {
  return store.commitIndex(wire, inventory, evidence, original,
    handles ?? fixturePreparedHandles.get(evidence) ?? []);
}

async function prepareCommit(
  store,
  request,
  attempt,
  invocationValue,
  retentionPolicyCid = cids.policy,
  preparedSchema = false,
  nativeProgress = false,
) {
  await store.putPublicationContract(
    'run_invocation', wire(invocationValue),
  );
  const schema = preparedSchema
    ? await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, request.run_definition_cid,
    )
    : await store.putSemantic(resultSchemaWire, cids.schema);
  const payload = Buffer.from('fixture durable Result payload', 'utf8');
  const writer = store.createPreparedObjectWriter(payload.byteLength);
  await writer.append(payload);
  const physical = await writer.seal(digest(payload));
  const bindingValue = seal('durable_result_binding', {
    version: 'actql-durable-result-binding/0.1',
    run_definition_cid: request.run_definition_cid,
    result_definition_cid: request.inventory[0].result_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    logical_result_cid: cids.result,
    result_schema_cid: cids.schema,
    ordering_evidence_cid: cids.receipt,
    codec_contract_cid: cids.captured,
    result_fields: ['answer'],
    material_generation_cid: physical.cid,
    store_authority_cid: store.storeAuthorityCid,
    effective_retention_policy_cid: retentionPolicyCid,
    row_count: 1,
    byte_count: physical.bytes,
    physical_sha256: physical.cid.slice('sha256:'.length),
  });
  const binding = contractControl.admit(
    'durable_result_binding', wire(bindingValue), limits,
  );
  await store.putPublicationContract(
    'durable_result_binding', wire(bindingValue),
  );
  const evidence = physicalCommitEvidence(invocationValue, binding, request);
  fixturePreparedHandles.set(evidence, Object.freeze([physical.prepared]));
  for (const contract of [evidence.manifest, evidence.receipt, evidence.capturedRun]) {
    await store.putSemantic(contract.wire, contract.identity);
  }
  await store.putPublicationContract('publication_request', wire(request));
  // Preserve the legacy file-original vectors below. Native progress has
  // separate real commit/recovery/retirement coverage, not a fixture issuer.
  if (!nativeProgress) await store.putPublicationContract('publication_attempt',wire(attempt));
  await store.createAttempt(wire(attempt));
  const preparing = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(wire(preparing), {uncommittedConfirmed: false});
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  await store.appendRecord(wire(committing), {uncommittedConfirmed: false});
  return {
    preparing,
    committing,
    evidence,
    required: [...new Set([
      invocationValue.invocation_cid,
      binding.identity,
      evidence.manifest.identity,
      evidence.receipt.identity,
      evidence.capturedRun.identity,
      request.publication_request_cid,
      attempt.publication_attempt_cid,
    ])],
    binding,
    prepared: physical.prepared,
    schemaPrepared: schema.prepared,
  };
}

test('one publication commit acquires each unchanged semantic original once', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const selected = new Map([...prepared.required, cids.schema].map(cid =>
    [join(directory, 'contracts', cid.slice(7) + '.json'), cid]));
  const originalOpen = fsPromises.open;
  const acquisitions = new Map();
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (selected.has(path)) {
      const cid = selected.get(path);
      acquisitions.set(cid, (acquisitions.get(cid) ?? 0) + 1);
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
    assert.deepEqual([...acquisitions].sort(), [...selected.values()].map(cid => [cid, 1]).sort(),
      'one commit shares its selected originals across inventory and evidence');
    acquisitions.clear();
    const repeated = await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
    assert.equal(repeated.idempotent, true);
    assert.deepEqual([...acquisitions].sort(), [...selected.values()].map(cid => [cid, 1]).sort(),
      'a distinct operation acquires its own originals');
  } finally {
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('publication commit never reuses a prior operation semantic original after mutation', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const borrowed = await store.readSemanticBytes(invocationValue.invocation_cid);
  borrowed.fill(0);
  // The public mutable allocation is not this later commit's private original.
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  const selected = join(directory, 'contracts', invocationValue.invocation_cid.slice(7) + '.json');
  const original = await readFile(selected);
  const changed = Buffer.from(original);
  changed[0] ^= 1;
  await writeFile(selected, changed);
  await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
    error => error?.code === 'PublicationContractCorrupt' ||
      error?.code === 'ENOENT' && error.syscall === 'lstat' &&
        error.path?.startsWith(join(directory, 'objects') + sep));
  assert.deepEqual(await readFile(selected), changed, 'refusal does not repair or replace the original');
  await store.close();
});

test('publication commit admits its exact Index once before durable staging', async t => {
  let selectedWire, admissions = 0;
  const control = {...contractControl, admit(name, value, bounds) {
    if (name === 'public_index_entry' && value === selectedWire) admissions++;
    return contractControl.admit(name, value, bounds);
  }};
  const {store} = await fixture(t, {}, control);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  selectedWire = wire(entry);
  assert.equal((await commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence)).committed, true);
  assert.equal(admissions, 1, 'the already admitted immutable Index needs no second admission to persist');
  await assert.rejects(commitFixtureIndex(store, '{}', prepared.required, prepared.evidence),
    code('InvalidPublicationContract'));
});

test('publication commit consumes its same-owner issued Index without raw readmission', async t => {
  let original, selectedWire, rawAdmissions = 0, originalObservations = 0;
  const control = {...contractControl,
    admit(name, value, bounds) {
      if (name === 'public_index_entry' && value === selectedWire) rawAdmissions++;
      return contractControl.admit(name, value, bounds);
    },
    admitOriginal(value, bounds) {
      assert.equal(bounds.maxWireBytes, limits.maxWireBytes);
      if (value !== original) return undefined;
      originalObservations++;
      return original;
    },
  };
  const {store} = await fixture(t, {}, control);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  selectedWire = wire(entry);
  // This explicit contract-control fixture recognizes one exact immutable
  // original. It is not an ordinary Common issuer or a physical ACK.
  original = contractControl.admit('public_index_entry', selectedWire, limits);
  assert(Object.isFrozen(original));
  let result, failure;
  try {result = await commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence, original);}
  catch (error) {failure = error;}
  assert.equal(rawAdmissions, 0, 'the issued original is not decoded/admitted/hashed again at this entry');
  if (failure !== undefined) throw failure;
  assert.equal(originalObservations, 1);
  assert.equal(result.committed, true);
});

test('publication Index original reuse keeps copied and omitted-port full admission', async t => {
  for (const kind of ['legacy', 'copy', 'omitted-port']) {
    let original, selectedWire, admissions = 0;
    const control = {...contractControl, admit(name, value, bounds) {
      if (name === 'public_index_entry' && value === selectedWire) admissions++;
      return contractControl.admit(name, value, bounds);
    }, ...(kind === 'omitted-port' ? {} : {admitOriginal(value) {
      return value === original ? original : undefined;
    }})};
    const {store} = await fixture(t, {}, control);
    const invocationValue = invocation();
    const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    selectedWire = wire(entry);
    original = contractControl.admit('public_index_entry', selectedWire, limits);
    const args = kind === 'legacy' ? [] : [kind === 'copy' ? Object.freeze({...original}) : original];
    assert.equal((await commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence, ...args)).committed, true);
    assert.equal(admissions, 1, kind + ' performs the existing full wire admission');
  }
});

test('publication Index original refuses conflicting body and invalid nominal control', async t => {
  let original, selectedWire, mode = 'original';
  const control = {...contractControl, admitOriginal(value) {
    if (value !== original) return undefined;
    if (mode === 'throw') throw Object.assign(new Error('original refused'), {code:'OriginalRefused'});
    return mode === 'copy' ? Object.freeze({...value}) : original;
  }};
  const {store} = await fixture(t, {}, control);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  selectedWire = wire(entry);
  original = contractControl.admit('public_index_entry', selectedWire, limits);
  await assert.rejects(commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence,
    Object.freeze({...original, wire:'{}'})), code('InvalidPublicationCommitEvidence'));
  mode = 'copy';
  await assert.rejects(commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence, original),
    code('InvalidPublicationContractControlResult'));
  mode = 'throw';
  await assert.rejects(commitFixtureIndex(store, selectedWire, prepared.required, prepared.evidence, original),
    error => error.code === 'InvalidPublicationContract' && error.cause?.code === 'OriginalRefused');
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined);
  // All refusals precede commit custody. This fixture still owns the original
  // uncommitted payload preparation and must release it before Store close.
  assert.equal(await prepared.prepared.release(), true);
});

test('Effectful commit inspection consumes only its original private Index observation', async () => {
  // Execute the real inspector's pre-I/O admission prefix and its actual
  // helpers. This is not complete Effect evidence or physical commit coverage.
  const text = readFileSync(new URL('./publication-store.mjs', import.meta.url), 'utf8');
  const wanted = new Set(['exactKeys', 'admitContract', 'parseContract', 'inspectEffectfulStoredEvidence']);
  const declarations = new Map();
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration') for (const value of node.declarations) {
      if (wanted.has(value.id.name)) {
        assert(!declarations.has(value.id.name)); declarations.set(value.id.name, {node,value});
      }
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(parse(text, {ecmaVersion:'latest',sourceType:'module'}));
  assert.equal(declarations.size, wanted.size);
  const inspector = declarations.get('inspectEffectfulStoredEvidence').value.init;
  const boundary = inspector.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'request'));
  assert(boundary);
  const helpers = ['exactKeys','admitContract','parseContract'].map(name => {
    const node = declarations.get(name).node; return text.slice(node.start,node.end);
  }).join('\n');
  let admissions = 0, active = 0;
  const control = {...contractControl, admit(...args) {admissions++;return contractControl.admit(...args);},
    ...Object.fromEntries(['effectfulCommitValid','effectPrivateEvidenceBinding',
      'capturedEffectSourceHoldingCid','capturedEffectSourceArtifactCid','capturedEffectSourceStoreAuthorityCid']
      .map(name=>[name,()=>assert.fail('No semantic or physical callback in the admission prefix')]))};
  const prefix = compileFunction(helpers + '\nreturn (' + text.slice(inspector.start,inspector.body.start+1) +
    text.slice(inspector.body.start+1,boundary.start) + '\nreturn {contract:admittedIndex,entry};});',
    ['configuration','contractControl','contractLimits','fail','active','readSemanticOriginal','cidPattern'])(
    {maxObjectBytes:limits.maxWireBytes}, control, limits,
    code=>{throw Object.assign(new Error(code),{code});}, ()=>{active++;},
    ()=>assert.fail('No physical read in the admission prefix'), /^sha256:[a-f0-9]{64}$/u);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const original = contractControl.admit('public_index_entry', wire(indexEntry(request, attempt, invocationValue)), limits);
  const observation = Object.freeze({contract:original,entry:JSON.parse(original.wire)});
  const chain = Object.fromEntries(['runDefinition','invocation','definitions','artifacts','derivations',
    'orderings','retentions','durableBindings','manifest','computationReceipt','capturedRun'].map(name=>
    [name,['definitions','artifacts','derivations','orderings','retentions','durableBindings'].includes(name)?[]:{}]));
  const args = {index:original,chain,preview:{},receipts:{setWire:'',memberWires:[],finalWire:''},
    privateBinding:{name:'',semanticCid:'',holdingCid:'',wire:''},effectSources:[]};
  const retained = await prefix(args, undefined, observation);
  assert.strictEqual(retained.contract, original); assert.strictEqual(retained.entry, observation.entry);
  assert.equal(admissions, 0); assert.equal(active, 1);
  const external = await prefix(args);
  assert.equal(external.contract.wire, original.wire); assert.notStrictEqual(external.entry, observation.entry);
  assert.equal(admissions, 1, 'an external stored-evidence inspection keeps its full admission');
  await assert.rejects(prefix({...args,index:Object.freeze({...original})},undefined,observation),
    code('InvalidEffectfulStoredEvidence'));
  assert.equal(admissions, 1, 'foreign private observation refuses rather than admitting it as an original');
});

test('independent publication reader defaults never interpret a contract as generation retention', async () => {
  // Execute the actual default-parameter entrances, not full evidence/FS.
  const text = readFileSync(new URL('./publication-store.mjs', import.meta.url), 'utf8');
  const selected = new Set(['verifyCommitEvidence', 'inspectEffectfulStoredEvidence']);
  const functions = new Map();
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && selected.has(node.id.name)) {
      assert(!functions.has(node.id.name)); functions.set(node.id.name, node.init);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(functions.size, 2);
  for (const [name, node] of functions) {
    const calls = [];
    const readSemanticOriginal = async (...args) => {calls.push(args);return {bytes: Buffer.from('legacy')};};
    const enter = compileFunction('return (' + text.slice(node.start, node.body.start) +
      '{return readOriginal;});', ['readSemanticOriginal'])(readSemanticOriginal);
    const args = name === 'verifyCommitEvidence' ? [undefined, undefined, undefined, undefined] : [{}];
    const original = Object.freeze({name: 'run_invocation', wire: 'same original'});
    const reader = await enter(...args);
    const value = await reader(cids.run, false, original);
    assert.equal(value.bytes.toString('utf8'), 'legacy');
    assert.deepEqual(calls, [[cids.run, false]], `${name} independent default ignores the private contract argument`);
    const privateCalls = [];
    const privateReader = async (...args) => {privateCalls.push(args);return value;};
    const retainedReader = await enter(...args, privateReader);
    assert.strictEqual(retainedReader, privateReader);
    await retainedReader(cids.run, true, original);
    assert.deepEqual(privateCalls, [[cids.run, true, original]], `${name} preserves the actual private reader's original forwarding`);
  }
});

test('independent Effect inspection ignores caller supplied private Index observations', async t => {
  let admissions = 0;
  const control = {...contractControl,
    admit(name, value, bounds) {
      if (name === 'public_index_entry') admissions++;
      return contractControl.admit(name, value, bounds);
    },
    ...Object.fromEntries(['effectfulCommitValid', 'effectPrivateEvidenceBinding',
      'capturedEffectSourceHoldingCid', 'capturedEffectSourceArtifactCid',
      'capturedEffectSourceStoreAuthorityCid'].map(name => [name,
        () => assert.fail('No semantic verdict before the selected reader')])),
  };
  const {store} = await fixture(t, {}, control);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const original = contractControl.admit('public_index_entry',
    wire(indexEntry(request, attempt, invocationValue)), limits);
  const chain = Object.fromEntries(['runDefinition', 'invocation', 'definitions',
    'artifacts', 'derivations', 'orderings', 'retentions', 'durableBindings',
    'manifest', 'computationReceipt', 'capturedRun'].map(name => [name,
    ['definitions', 'artifacts', 'derivations', 'orderings', 'retentions',
      'durableBindings'].includes(name) ? [] : {}]));
  const preparation = {index: original, chain, preview: {},
    receipts: {setWire: '', memberWires: [], finalWire: ''},
    privateBinding: {name: '', semanticCid: '', holdingCid: '', wire: ''}, effectSources: []};
  const reads = [];
  const selectedRead = new Error('SelectedEvidenceRead');
  const reader = async cid => {reads.push(cid);throw selectedRead;};
  const callerEntry = {publication_request_cid: digest('caller substituted request')};
  const malformed = Object.freeze({...original, wire: '{}'});
  await assert.rejects(store.inspectEffectfulStoredEvidence(
    {...preparation, index: malformed}, reader, {contract: malformed, entry: callerEntry},
  ), code('InvalidPublicationContract'));
  assert.equal(admissions, 1, 'an extra argument cannot bypass incoming Index admission');
  assert.deepEqual(reads, [], 'malformed Index refuses before any selected evidence read');
  await assert.rejects(store.inspectEffectfulStoredEvidence(
    preparation, reader, {contract: original, entry: callerEntry},
  ), error => error === selectedRead);
  assert.equal(admissions, 2, 'a separate supported inspection admits its actual input');
  assert.deepEqual(reads, [request.publication_request_cid],
    'the supported reader receives the actually parsed entry, not the extra caller body');
});

test('publication commit reuses the exact issued original for its selected native row', async t => {
  let original, selectedWire, rawAdmissions = 0, observations = 0;
  const control = {...contractControl, admit(name, value, bounds) {
    if (name === 'run_invocation' && value === selectedWire) rawAdmissions++;
    return contractControl.admit(name, value, bounds);
  }, admitOriginal(value, bounds) {
    if (value !== original) return undefined;
    assert.equal(bounds.maxWireBytes, limits.maxWireBytes);
    assert.equal(bounds.maxNodes, limits.maxNodes);
    observations++;
    return original;
  }};
  const {store, directory} = await fixture(t, {}, control);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  // Use the real existing native writer before any legacy file adoption.
  // The explicit contract-control fixture is not actual Common issuance.
  await store.putOriginalPublicationContracts([
    contractControl.admit('run_invocation', wire(invocationValue), limits),
  ]);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  original = prepared.evidence.invocation;
  selectedWire = original.wire;
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const committed = await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  assert.equal(committed.committed, true);
  assert.equal(rawAdmissions, 0, 'the actual selected native wire equals the same issued original');
  assert.equal(observations, 1, 'the original is observed once inside this commit');
  assert.equal((await store.readPublicationContract(original.identity, original.name)).wire, selectedWire);
  assert.equal(rawAdmissions, 1, 'a separate public reader admits its own native row');
  const database = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'));
  try {
    assert.equal(database.prepare('UPDATE publication_contracts SET wire=? WHERE semantic_cid=?')
      .run('{}', original.identity).changes, 1);
  } finally { database.close(); }
  await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
    error => ['InvalidPublicationContract','InvalidDeliveryAttemptIndex'].includes(error?.code));
  assert.equal(observations, 1, 'changed native bytes cannot reuse the old original');
});

test('publication native original reuse retains copied and omitted-control admission', async t => {
  for (const kind of ['copy', 'unrecognized', 'omitted-port']) {
    let original, selectedWire, rawAdmissions = 0;
    const control = {...contractControl, admit(name, value, bounds) {
      if (name === 'run_invocation' && value === selectedWire) rawAdmissions++;
      return contractControl.admit(name, value, bounds);
    }, ...(kind === 'omitted-port' ? {} : {admitOriginal(value) {
      return kind !== 'unrecognized' && value === original ? original : undefined;
    }})};
    const {store} = await fixture(t, {}, control);
    const value = invocation(), request = publicationRequest(resultDefinition(), value.invocation_cid);
    const attempt = publicationAttempt(request);
    await store.putOriginalPublicationContracts([
      contractControl.admit('run_invocation', wire(value), limits),
    ]);
    const prepared = await prepareCommit(store, request, attempt, value);
    original = prepared.evidence.invocation;
    selectedWire = original.wire;
    const evidence = kind === 'copy'
      ? {...prepared.evidence, runDefinition: Object.freeze({...original})}
      : prepared.evidence;
    const entry = indexEntry(request, attempt, value, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    if (kind === 'copy') {
      await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, evidence),
        code('InvalidPublicationCommitChain'));
      // Full row admission cannot make an arbitrary copied evidence wrapper
      // nominal for the unchanged final chain Owner. Custody has not begun.
      assert.equal(await prepared.prepared.release(), true);
    } else {
      assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, evidence)).committed, true);
    }
    assert.equal(rawAdmissions, 1, `${kind} keeps the selected native row's full admission`);
  }
});

test('publication inventory reuses only its newly acknowledged Index write within the commit', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const path = join(directory, 'contracts', entry.public_index_entry_cid.slice(7) + '.json');
  const actualOpen = fsPromises.open;
  let reads = 0;
  t.mock.method(fsPromises, 'open', function(selected, ...args) {
    if (String(selected) === path) reads++;
    return Reflect.apply(actualOpen, this, [selected, ...args]);
  });
  syncBuiltinESMExports();
  try {
    assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
    assert.equal(reads, 0, 'same-commit inventory consumes the actual acknowledged writer, not a second reader/hash');
    assert.deepEqual(await store.inspectCommittedIndex(indexKeyFor(request)), entry);
    assert.equal(reads, 1, 'the next public operation acquires its own actual original');
    const physical = join(directory, 'objects', digest(wire(entry)).slice(7));
    assert.equal((await stat(path)).ino, (await stat(physical)).ino);
    await unlink(path);
    await writeFile(path, wire(entry), {mode: 0o600});
    await assert.rejects(store.inspectCommittedIndex(indexKeyFor(request)),
      code('PublicationContractCorrupt'));
    assert.equal(reads, 2, 'a byte-identical replacement alias does not reuse the earlier write');
  } finally { t.mock.restoreAll(); syncBuiltinESMExports(); }
});

test('publication inventory acquires an existing Index alias instead of treating it as a new write', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await store.putSemantic(wire(entry), entry.public_index_entry_cid);
  const path = join(directory, 'contracts', entry.public_index_entry_cid.slice(7) + '.json');
  await unlink(path);
  await writeFile(path, wire(entry), {mode: 0o600});
  await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
    code('PublicationContractCorrupt'));
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined);
  assert.equal(await prepared.prepared.release(), true);
});

test('publication inventory retains failed Index alias durability before a fresh acquisition', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const alias = join(directory, 'contracts', entry.public_index_entry_cid.slice(7) + '.json');
  const actualOpen = fsPromises.open;
  const primary = new Error('Index alias durability unavailable');
  let refuse = true, reads = 0, failure;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    if (String(path) === alias) reads++;
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === join(directory, 'contracts')) {
      const sync = handle.sync;
      t.mock.method(handle, 'sync', function(...values) {
        if (refuse) throw primary;
        return Reflect.apply(sync, this, values);
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence), error => {
      failure = error;
      return error.primaryFailure === primary && error.cleanupHandle.status().pending;
    });
    assert.equal(reads, 0, 'failed durability cannot proceed to inventory acquisition');
    assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined);
    await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
    refuse = false;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
    assert.equal(reads, 2, 'a new attempt checks both its existing alias and its original reader');
  } finally {
    refuse = false;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});

test('selected publication observation returns its one admitted Index original and reacquires the next read', async t => {
  let armed = false, admissions = 0, original;
  const counted = {...contractControl, admit(name, ...args) {
    const value = contractControl.admit(name, ...args);
    if (armed && name === 'public_index_entry') { admissions++; original = value; }
    return value;
  }};
  const {store, directory} = await fixture(t, {}, counted);
  const invocationValue = invocation(), request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {durable_result_binding_cids: [prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  armed = true;
  const selected = await store.readCommittedPublication(indexKeyFor(request));
  assert.strictEqual(selected.index, original); assert.equal(admissions, 1);
  assert.equal(selected.entry.public_index_entry_cid, entry.public_index_entry_cid);
  assert(Object.isFrozen(selected)); assert(Object.isFrozen(selected.entry));
  assert(Object.isFrozen(selected.entry.durable_result_binding_cids));
  assert.throws(() => selected.entry.durable_result_binding_cids.push(cids.schema), TypeError);
  assert.deepEqual(Object.keys(selected).sort(), ['entry', 'index']);
  const next = await store.readCommittedPublication(indexKeyFor(request));
  assert.equal(admissions, 2); assert.notStrictEqual(next.index, selected.index);
  const alias = join(directory, 'contracts', entry.public_index_entry_cid.slice(7) + '.json');
  const bytes = await readFile(alias); await unlink(alias); await writeFile(alias, bytes, {mode: 0o600});
  await assert.rejects(store.readCommittedPublication(indexKeyFor(request)), code('PublicationContractCorrupt'));
});

test('selected publication observation preserves missing metadata and original close refusals', async t => {
  const {store} = await fixture(t);
  assert.equal(await store.readCommittedPublication(indexKey), undefined);
  await store.close();
  await assert.rejects(store.readCommittedPublication(indexKey), code('PublicationStoreClosed'));
});

test('publication completion batch avoids a separate post-Index native commit', async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql, ...args) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql, ...args]);
  });
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  armed = true;
  const outcome = await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  assert.equal(outcome.committed, true);
  assert.equal(commits, 1, 'inventory staging is durable; completion joins a later necessary transaction');
  assert.equal((await store.inspectCommittedIndex(indexKeyFor(request))).public_index_entry_cid, entry.public_index_entry_cid);
  const observed = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'), {readOnly: true});
  try { assert.equal(observed.prepare('SELECT count(*) AS n FROM pending_publications').get().n, 1); }
  finally { observed.close(); }
  await store.close();
  assert.equal(commits, 2, 'the existing physical-lifetime seal also completes the recovery row');
  armed = false;
});

for (const afterCommit of [false, true]) {
test(`publication inventory staging retains its ${afterCommit ? 'committed' : 'rolled-back'} Unknown acknowledgement at the Store boundary`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-inventory-stage-unknown-'));
  let store, failure, settled = false, armed = false, staged = false, lost = false, commits = 0;
  t.after(async () => {
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    if (store && !store.status().closed) await store.close();
    if (settled) await removeFixtureDirectory(directory);
    else t.diagnostic(`Unconfirmed original fixture retained: ${directory}`);
  });
  const stagedWrites = [];
  const prepare = DatabaseSync.prototype.prepare, exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql, ...args) {
    const statement = Reflect.apply(prepare, this, [sql, ...args]);
    if (sql === 'INSERT INTO native_publication_inventories VALUES(?,?)') {
      const run = statement.run;
      t.mock.method(statement, 'run', function(...values) {
        if (armed) {staged = true; stagedWrites.push([...values]);}
        return Reflect.apply(run, this, values);
      });
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql, ...args) {
    if (armed && staged && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        lost = true;
        if (afterCommit) Reflect.apply(exec, this, [sql, ...args]);
        throw Object.assign(new Error('lost inventory staging COMMIT reply'), {code: 'EIO'});
      }
    }
    return Reflect.apply(exec, this, [sql, ...args]);
  });
  store = await openLocalPublicationStore({directory, storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth}, contractControl);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  armed = true;
  await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence), error => {
    failure = error;
    return (error.primaryFailure ?? error).outcome === 'unknown';
  });
  assert.equal(lost, true);
  assert.equal(commits, 1);
  assert.equal(failure.cleanupHandle?.status().pending, true,
    'the same original native staging ACK must remain reachable from the Store failure');
  await assert.rejects(store.inspectCommittedIndex(indexKeyFor(request)),
    code('DeliveryAttemptIndexCommitOutcomeUnknown'));
  assert.equal(failure.cleanupHandle.status().pending, true);
  const originalCleanup = failure.cleanupHandle;
  await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
  // close intentionally retries the SAME failed native writer before its
  // independent prepared-holder fence refuses close. This is confirmation,
  // not a fresh publication attempt or permission to report success.
  assert.strictEqual(failure.cleanupHandle, originalCleanup);
  assert.equal(commits, 2);
  assert.equal(stagedWrites.length, afterCommit ? 1 : 2,
    'committed staging is confirmed without replaying its INSERT');
  if (!afterCommit) assert.deepEqual(stagedWrites[1], stagedWrites[0]);
  assert.equal(originalCleanup.status().pending, false);
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined);
  const first = failure.cleanupHandle.retry(), concurrent = failure.cleanupHandle.retry();
  assert.equal(first, concurrent, 'concurrent finalization owns one original write');
  assert.equal((await first).pending, false);
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(commits, 2, 'same-original confirmation is one real native write, not a probe ACK');
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined,
    'staging acknowledgement is not publication success');
  assert.equal((await store.latestRecord(attempt.publication_attempt_cid)).state, 'committing');
  assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
  assert.equal(prepared.prepared.status().pending, false);
  settled = true;
});
}

test('publication commit parses its Binding once across evidence and metadata inventory', async t => {
  const {store} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  const parse = JSON.parse;
  let bindingParses = 0, schemaParses = 0;
  t.mock.method(JSON, 'parse', function(value, ...rest) {
    if (value === prepared.binding.wire || value === resultSchemaWire) {
      // Count direct Store DATA parsing only, not fixture/Core admission
      // internals or cache-entry calls. This instrumentation is not timing.
      // Node's test mock adds an apply frame; identify the actual Store
      // function, not a fixed stack depth in the instrumentation wrapper.
      const stack = new Error().stack;
      if (value === prepared.binding.wire && /at parseContract \(file:.*publication-store\.mjs:/u.test(stack)) bindingParses++;
      if (value === resultSchemaWire && /at verifyDurableResultBinding \(file:.*publication-store\.mjs:/u.test(stack)) schemaParses++;
    }
    return Reflect.apply(parse, this, [value, ...rest]);
  });
  assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
  assert.equal(bindingParses, 1, 'schema selection consumes the same parsed Binding');
  assert.equal(schemaParses, 1, 'the selected schema still receives its actual shape check');
  bindingParses = schemaParses = 0;
  assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).idempotent, true);
  assert.equal(bindingParses, 1, 'a distinct idempotent operation validates its own Binding once');
  assert.equal(schemaParses, 1, 'a distinct operation rechecks the same selected schema');
});

test('committed evidence validation retains its actual payload and next-operation mutation check', async t => {
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  const index = contractControl.admit('public_index_entry', wire(entry), limits);
  assert.equal(await store.validateCommittedEvidence(index, prepared.evidence), true);
  const path = join(directory, 'objects', JSON.parse(prepared.binding.wire).material_generation_cid.slice(7));
  const changed = await readFile(path);
  changed[0] ^= 1;
  await writeFile(path, changed);
  await assert.rejects(store.validateCommittedEvidence(index, prepared.evidence),
    code('PublicationObjectCorrupt'));
  assert.deepEqual(await readFile(path), changed, 'validation refuses instead of repairing the original');
});

test('known file-backed Result metadata performs no unrelated native delivery probe', async t => {
  const prepare = DatabaseSync.prototype.prepare;
  const probes = [];
  let observing = false;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql, ...rest) {
    const statement = Reflect.apply(prepare, this, [sql, ...rest]);
    if (sql.startsWith("SELECT 'delivery_attempt' AS name,attempt_wire AS wire")) {
      const get = statement.get;
      t.mock.method(statement, 'get', function(...args) {
        if (observing) probes.push([...args]);
        return Reflect.apply(get, this, args);
      });
    }
    return statement;
  });
  const {store, directory} = await fixture(t);
  const invocationValue = invocation();
  const definition = resultDefinition();
  const request = publicationRequest(definition, invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue);
  await store.putPublicationContract('result_definition', wire(definition));
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  observing = true;
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  assert.deepEqual(probes, [], 'typed commit evidence selects its representation before generic inventory');
  assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).idempotent, true);
  assert.deepEqual(probes, [], 'a distinct operation reacquires typed evidence without unrelated native probes');
  const description = await store.readCommittedResultDescriptionEvidence(
    indexKeyFor(request), definition.result_definition_cid);
  assert.equal(description.schemaWire, resultSchemaWire);
  assert.equal(description.definition.identity, definition.result_definition_cid);
  assert.deepEqual(probes, [], 'known Index and schema bodies are file-backed, not delivery metadata');
  const chunks = [];
  await store.consumeCommittedResult(indexKeyFor(request), definition.result_definition_cid,
    () => true, chunk => chunks.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(chunks).toString('utf8'), 'fixture durable Result payload');
  assert.deepEqual(probes, [], 'actual payload/schema consumption uses the same selected representation');
  await unlink(join(directory, 'contracts', cids.schema.slice(7) + '.json'));
  await assert.rejects(store.readCommittedResultDescriptionEvidence(
    indexKeyFor(request), definition.result_definition_cid), code('PublicationContractMissing'));
  assert.deepEqual(probes, [], 'a missing selected schema refuses without a different representation');
  assert.equal((await store.readSemanticBytes(invocationValue.invocation_cid)).toString('utf8'),
    contractControl.admit('run_invocation', wire(invocationValue), limits).wire);
  assert.equal(probes.length, 1, 'an untyped public read retains the generic native lookup and file fallback');
  assert.deepEqual(probes[0], Array(5).fill(invocationValue.invocation_cid));
});

test('publication inventory still acquires additional untyped originals and refuses missing ones', async t => {
  for (const missing of [false, true]) {
    await t.test(missing ? 'missing original' : 'stored original', async t => {
      const {store} = await fixture(t);
      const invocationValue = invocation();
      const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
      const attempt = publicationAttempt(request);
      const prepared = await prepareCommit(store, request, attempt, invocationValue);
      const entry = indexEntry(request, attempt, invocationValue, {
        durable_result_binding_cids: [prepared.binding.identity],
      });
      const extraWire = '{"auxiliary":true}', extraCid = digest(extraWire);
      if (!missing) await store.putSemantic(extraWire, extraCid);
      const commit = commitFixtureIndex(store, wire(entry), [...prepared.required, extraCid], prepared.evidence);
      if (missing) {
        await assert.rejects(commit, code('PublicationContractMissing'));
        assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)), undefined);
        assert.equal((await store.latestRecord(attempt.publication_attempt_cid)).state, 'committing');
        assert.equal(await prepared.prepared.release(), true);
      } else {
        assert.equal((await commit).committed, true);
        assert.equal((await store.readSemanticBytes(extraCid)).toString('utf8'), extraWire);
      }
    });
  }
});

test('bounded object writes are durable, streamed, and physically addressed',
  async t => {
    const {store, configuration} = await fixture(t);
    const writer = store.createObjectWriter(6);
    await writer.append('abc');
    await writer.append(Buffer.from('def'));
    await assert.rejects(writer.append('g'), code('PublicationObjectLimit'));
    const stored = await writer.seal(digest('abcdef'));
    assert.deepEqual(stored, {
      cid: digest('abcdef'), bytes: 6, created: true,
    });
    assert.equal(store.status().reservedBytes, 0);
    const chunks = [];
    await store.consumeObject(stored.cid, chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'abcdef');
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.verifyObject(stored.cid), {
      cid: stored.cid, bytes: 6,
    });
    assert.equal(reopened.status().storedBytes, 6);
  });

async function privateReadFixture(t) {
  const setup = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
  const wire = '{"private":"selected-evidence-body"}';
  const semanticCid = digest('selected-private-evidence');
  const holdingCid = digest('selected-private-evidence-holding');
  const prepared = await setup.store.preparePrivateEvidence('effect_preview', wire, semanticCid);
  await setup.store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holdingCid, manifest_cid: semanticCid,
    objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}]}, [prepared.prepared]);
  return {...setup, wire, semanticCid, holdingCid, prepared,
    payloadPath: join(setup.directory, 'objects', prepared.physicalCid.slice(7)),
    holdingPath: join(setup.directory, 'physical-holdings', holdingCid.slice(7) + '.json')};
}

test('private evidence selected read acquires one holding and ciphertext and rechecks the next operation', async t => {
  const f = await privateReadFixture(t);
  const original = await readFile(f.payloadPath), actualOpen = fsPromises.open;
  let payloadOpens = 0, holdingOpens = 0, payloadBytes = 0;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === f.holdingPath) holdingOpens++;
    if (String(path) === f.payloadPath) {
      payloadOpens++;
      const read = handle.read;
      t.mock.method(handle, 'read', async function(...parameters) {
        const result = await Reflect.apply(read, this, parameters);
        payloadBytes += result.bytesRead;
        return result;
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    assert.deepEqual(await f.store.readPrivateEvidence('effect_preview', f.semanticCid, f.holdingCid), Buffer.from(f.wire));
    assert.equal(payloadOpens, 1, 'one selected ciphertext FD, not inspect/inspect/consume');
    assert.equal(holdingOpens, 1, 'one selected immutable holding body in this private operation');
    assert.equal(payloadBytes, original.byteLength, 'one full ciphertext hash/transfer');
    const changed = Buffer.from(original); changed[0] ^= 1;
    await writeFile(f.payloadPath, changed);
    await assert.rejects(f.store.readPrivateEvidence('effect_preview', f.semanticCid, f.holdingCid),
      code('PublicationObjectCorrupt'));
    assert.equal(payloadOpens, 2, 'a new operation reacquires its own payload rather than retaining an admission');
    assert.equal(holdingOpens, 2);
  } finally {t.mock.restoreAll(); syncBuiltinESMExports();}
});

test('private evidence selected read retains its consuming FD through failed close and retirement', async t => {
  const f = await privateReadFixture(t), actualOpen = fsPromises.open;
  let allowClose = false, opens = 0, closes = 0, failure;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === f.payloadPath) {
      opens++;
      const close = handle.close;
      t.mock.method(handle, 'close', async function(...parameters) {
        closes++;
        if (!allowClose) return false;
        return Reflect.apply(close, this, parameters);
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(f.store.readPrivateEvidence('effect_preview', f.semanticCid, f.holdingCid), error => {
      failure = error;
      return error.cleanupPending === true && error.cleanupHandle.status().pending === true;
    });
    assert.equal(opens, 1);
    const retiring = await f.store.retirePhysicalHolding(f.holdingCid);
    assert.equal(retiring.cleanup.status().pending, true);
    assert.equal((await stat(f.payloadPath)).size, f.prepared.bytes);
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    await assert.rejects(failure.cleanupHandle.retry(), code('PublicationStoreCleanupPending'));
    assert.equal(failure.cleanupHandle.status().pending, true, 'false close is not ACK');
    allowClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(opens, 1, 'close-only retries keep the same original FD');
    assert.equal(closes, 3);
    await retiring.cleanup.retry();
    assert.equal(retiring.cleanup.status().pending, false);
    assert.equal(f.store.status().storedBytes, 0);
    await assert.rejects(stat(f.payloadPath), code('ENOENT'));
  } finally {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});

test('private evidence selected extent and missing payload keep their original refusals', async t => {
  const f = await privateReadFixture(t);
  const bytes = await readFile(f.holdingPath), record = JSON.parse(bytes);
  try {
    for (const delta of [-1, 1]) {
      await writeFile(f.holdingPath, JSON.stringify({...record,
        objects: record.objects.map(object => ({...object, byte_count: object.byte_count + delta}))}));
      await assert.rejects(f.store.readPrivateEvidence('effect_preview', f.semanticCid, f.holdingCid),
        code('InvalidPublicationPhysicalHoldingStore'));
    }
  } finally {await writeFile(f.holdingPath, bytes);}
  await unlink(f.payloadPath);
  await assert.rejects(f.store.readPrivateEvidence('effect_preview', f.semanticCid, f.holdingCid),
    code('PublicationObjectMissing'));
  assert.deepEqual(await readFile(f.holdingPath), bytes,
    'A selected unavailable payload never repairs or retires its original ownership');
});

function countPrivateReads(t, directory, objectCids, holdingCid) {
  const actualOpen = fsPromises.open, payloads = new Map(objectCids.map(cid =>
    [join(directory, 'objects', cid.slice(7)), 0]));
  const holdingPath = join(directory, 'physical-holdings', holdingCid.slice(7) + '.json');
  const counts = {payloads, holdings: 0, directoryAcks: 0};
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === holdingPath) counts.holdings++;
    if (payloads.has(String(path))) payloads.set(String(path), payloads.get(String(path)) + 1);
    if (String(path) === join(directory, 'physical-holdings')) {
      const sync = handle.sync;
      t.mock.method(handle, 'sync', async function(...parameters) {
        const result = await Reflect.apply(sync, this, parameters);
        counts.directoryAcks++;
        return result;
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  return counts;
}

test('private evidence confirmation reuses its one operation read before the real directory ACK', async t => {
  const f = await privateReadFixture(t);
  const counts = countPrivateReads(t, f.directory, [f.prepared.physicalCid], f.holdingCid);
  try {
    const binding = {name: 'effect_preview', semanticCid: f.semanticCid,
      holdingCid: f.holdingCid, wire: f.wire};
    const confirmed = f.store.confirmPrivateEvidence(binding);
    binding.wire = '{"later":"not the submitted body"}';
    const record = await confirmed;
    assert.equal(record.holding_cid, f.holdingCid);
    assert.deepEqual([...counts.payloads.values()], [1]);
    assert.equal(counts.holdings, 1);
    assert.equal(counts.directoryAcks, 1, 'Readable bytes are not a durable confirmation');
    await f.store.confirmPrivateEvidence({...binding, wire: f.wire});
    assert.deepEqual([...counts.payloads.values()], [2], 'A new confirmation reacquires its own original');
    assert.equal(counts.holdings, 2);
    assert.equal(counts.directoryAcks, 2);
  } finally {t.mock.restoreAll(); syncBuiltinESMExports();}
});

test('Model raw confirmation reads each selected ciphertext once with the same descriptor and holding', async t => {
  const {store, directory} = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
  const bytes = Uint8Array.of(0, 255, 13, 10, 97);
  const binding = {semanticCid: digest('single raw descriptor'), holdingCid: digest('single raw holding'),
    wire: '{"descriptor":"original raw cell"}', contentCid: digest(bytes), byteCount: bytes.byteLength};
  const prepared = await store.prepareModelRawEvidence(binding, bytes);
  const record = {version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
    holding_cid: binding.holdingCid, manifest_cid: binding.semanticCid,
    objects: prepared.map(value => ({cid: value.physicalCid, byte_count: value.bytes}))};
  await store.commitPhysicalHolding(record, prepared.map(value => value.prepared));
  const counts = countPrivateReads(t, directory, record.objects.map(value => value.cid), record.holding_cid);
  try {
    const pending = store.confirmModelRawEvidence(binding);
    binding.wire = '{"descriptor":"later mutation"}';
    const confirmed = await pending;
    assert.deepEqual(confirmed.bytes, Buffer.from(bytes));
    assert.deepEqual(confirmed.record, record);
    assert.deepEqual([...counts.payloads.values()], [1, 1]);
    assert.equal(counts.holdings, 1);
    assert.equal(counts.directoryAcks, 1);
    await assert.rejects(store.readModelRawEvidence(binding), code('PublicationPrivateEvidenceConflict'));
  } finally {t.mock.restoreAll(); syncBuiltinESMExports();}
});

test('private confirmation keeps the existing reader and retirement scope through its real directory ACK', async t => {
  const f = await privateReadFixture(t), actualOpen = fsPromises.open;
  let reached, resume;
  const atSync = new Promise(resolve => {reached = resolve;});
  const paused = new Promise(resolve => {resume = resolve;});
  let block = true, pending;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === join(f.directory, 'physical-holdings')) {
      const sync = handle.sync;
      t.mock.method(handle, 'sync', async function(...parameters) {
        if (block) {block = false; reached(); await paused;}
        return Reflect.apply(sync, this, parameters);
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    pending = f.store.confirmPrivateEvidence({name: 'effect_preview', semanticCid: f.semanticCid,
      holdingCid: f.holdingCid, wire: f.wire});
    await atSync;
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    let retired = false;
    const retirement = f.store.retirePhysicalHolding(f.holdingCid).then(value => {retired = true; return value;});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(retired, false, 'The same retention queue excludes retirement before confirmation ACK');
    assert.equal((await stat(f.payloadPath)).size, f.prepared.bytes);
    resume();
    assert.equal((await pending).holding_cid, f.holdingCid);
    const result = await retirement;
    if (result.cleanup.status().pending) await result.cleanup.retry();
    assert.equal(result.cleanup.status().pending, false);
    assert.equal(f.store.status().storedBytes, 0);
  } finally {
    resume();
    if (pending !== undefined) await pending.catch(() => {});
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});

for (const raw of [false, true]) {
test(`private confirmation retains a failed original directory close (${raw ? 'raw' : 'single'})`, async t => {
  let f, binding;
  if (!raw) {
    f = await privateReadFixture(t);
    binding = {name: 'effect_preview', semanticCid: f.semanticCid, holdingCid: f.holdingCid, wire: f.wire};
  } else {
    f = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
    const bytes = Uint8Array.of(0, 255, 97);
    binding = {semanticCid: digest('pending raw directory envelope'), holdingCid: digest('pending raw directory holding'),
      wire: '{"descriptor":"same original"}', contentCid: digest(bytes), byteCount: bytes.byteLength};
    const prepared = await f.store.prepareModelRawEvidence(binding, bytes);
    await f.store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
      holding_cid: binding.holdingCid, manifest_cid: binding.semanticCid,
      objects: prepared.map(value => ({cid: value.physicalCid, byte_count: value.bytes}))}, prepared.map(value => value.prepared));
  }
  const actualOpen = fsPromises.open, ownerPath = join(f.directory, 'owner', 'owner.json');
  const token = await readFile(ownerPath);
  let allowClose = false, opens = 0, syncs = 0, closes = 0, failure;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === join(f.directory, 'physical-holdings')) {
      opens++;
      const sync = handle.sync, close = handle.close;
      t.mock.method(handle, 'sync', async function(...parameters) {
        syncs++;
        return Reflect.apply(sync, this, parameters);
      });
      t.mock.method(handle, 'close', async function(...parameters) {
        closes++;
        if (!allowClose) return false;
        return Reflect.apply(close, this, parameters);
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(raw ? f.store.confirmModelRawEvidence(binding) : f.store.confirmPrivateEvidence(binding), error => {
      failure = error;
      return error.cleanupHandle?.status().pending === true;
    });
    assert.equal(opens, 1); assert.equal(syncs, 1);
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    assert.equal(f.store.status().closed, false);
    assert.deepEqual(await readFile(ownerPath), token);
    const retirement = await f.store.retirePhysicalHolding(binding.holdingCid);
    assert.equal(retirement.cleanup.status().pending, true);
    const before = closes;
    allowClose = true;
    const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
    assert.strictEqual(first, second, 'Same retained child cleanup is single-flight');
    assert.equal((await first).pending, false);
    assert.equal(closes, before + 1);
    assert.equal(opens, 1); assert.equal(syncs, 1, 'Cleanup does not reopen, resync, reread or return a saved observation');
    await retirement.cleanup.retry();
    assert.equal(retirement.cleanup.status().pending, false);
    assert.equal(f.store.status().storedBytes, 0);
    await f.store.close();
  } finally {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});
}

for (const existing of [false, true]) {
test(`holding commit retains its original failed directory close after reconciliation (${existing ? 'existing' : 'new'})`, async t => {
  let f, record, prepared;
  if (existing) {
    f = await privateReadFixture(t);
    record = await f.store.inspectPhysicalHolding(f.holdingCid);
    prepared = [];
  } else {
    f = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
    f.semanticCid = digest('new original holding close'); f.holdingCid = digest('new holding close custody');
    f.wire = '{"private":"new holding"}';
    const payload = await f.store.preparePrivateEvidence('effect_preview', f.wire, f.semanticCid);
    prepared = [payload.prepared];
    record = {version: 'actql-local-physical-holding/0.1', namespace: 'publication-private',
      holding_cid: f.holdingCid, manifest_cid: f.semanticCid,
      objects: [{cid: payload.physicalCid, byte_count: payload.bytes}]};
  }
  const ownerPath = join(f.directory, 'owner', 'owner.json'), token = await readFile(ownerPath);
  const actualOpen = fsPromises.open;
  let original, allowClose = false, opens = 0, syncs = 0, originalCloses = 0, failure;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === join(f.directory, 'physical-holdings')) {
      opens++;
      const sync = handle.sync;
      t.mock.method(handle, 'sync', async function(...parameters) {
        syncs++; return Reflect.apply(sync, this, parameters);
      });
      if (original === undefined) {
        original = handle;
        const close = handle.close;
        t.mock.method(handle, 'close', async function(...parameters) {
          assert.equal(this, original); originalCloses++;
          if (!allowClose) return false;
          return Reflect.apply(close, this, parameters);
        });
      }
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(f.store.commitPhysicalHolding(record, prepared), error => {
      failure = error; return error.cleanupHandle?.status().pending === true;
    });
    assert.equal(opens, 1); assert.equal(syncs, 1);
    assert.deepEqual(await f.store.confirmPrivateEvidence({name: 'effect_preview', semanticCid: f.semanticCid,
      holdingCid: f.holdingCid, wire: f.wire}), record);
    assert.equal(prepared.every(handle => handle.status().pending === false), true);
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    assert.equal(f.store.status().closed, false);
    assert.deepEqual(await readFile(ownerPath), token);
    const retirement = await f.store.retirePhysicalHolding(f.holdingCid);
    assert.equal(retirement.cleanup.status().pending, true);
    const before = {opens, syncs, closes: originalCloses};
    allowClose = true;
    const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
    assert.strictEqual(first, second);
    assert.equal((await first).pending, false);
    assert.equal(originalCloses, before.closes + 1);
    assert.equal(opens, before.opens); assert.equal(syncs, before.syncs);
    await retirement.cleanup.retry();
    assert.equal(retirement.cleanup.status().pending, false);
    assert.equal(f.store.status().storedBytes, 0);
    await f.store.close();
  } finally {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});
}

for (const phase of ['share-new', 'share-existing', 'borrowed-before-link']) {
test(`holding directory custody preserves shared publication boundaries (${phase})`, async t => {
  const f = await privateReadFixture(t), source = await f.store.inspectPhysicalHolding(f.holdingCid);
  const target = {...source, holding_cid: digest('holding directory custody ' + phase)};
  if (phase === 'share-existing') await f.store.sharePhysicalHolding(f.holdingCid, target);
  const physical = await stat(f.payloadPath), bytes = await readFile(f.payloadPath);
  const ownerPath = join(f.directory, 'owner', 'owner.json'), token = await readFile(ownerPath);
  const actualOpen = fsPromises.open;
  let original, allowClose = false, opens = 0, syncs = 0, closes = 0, failure;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(actualOpen, this, [path, ...args]);
    if (String(path) === join(f.directory, 'physical-holdings')) {
      opens++;
      const sync = handle.sync, close = handle.close;
      t.mock.method(handle, 'sync', async function(...parameters) {
        syncs++; return Reflect.apply(sync, this, parameters);
      });
      if (original === undefined) {
        original = handle;
        t.mock.method(handle, 'close', async function(...parameters) {
          assert.equal(this, original); closes++;
          if (!allowClose) return false;
          return Reflect.apply(close, this, parameters);
        });
      }
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(phase === 'borrowed-before-link'
      ? f.store.commitPhysicalHolding(target, [], [f.holdingCid])
      : f.store.sharePhysicalHolding(f.holdingCid, target), error => {
      failure = error; return error.cleanupHandle?.status().pending === true;
    });
    assert.equal(opens, 1); assert.equal(syncs, 1);
    const targetPath = join(f.directory, 'physical-holdings', target.holding_cid.slice(7) + '.json');
    if (phase === 'borrowed-before-link') await assert.rejects(stat(targetPath), {code: 'ENOENT'});
    else assert.deepEqual(await f.store.inspectPhysicalHolding(target.holding_cid), target);
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    assert.deepEqual(await readFile(ownerPath), token);
    assert.deepEqual(await readFile(f.payloadPath), bytes);
    const retained = await stat(f.payloadPath);
    assert.equal(retained.dev, physical.dev); assert.equal(retained.ino, physical.ino);
    const before = {opens, syncs, closes}; allowClose = true;
    const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
    assert.strictEqual(first, second); assert.equal((await first).pending, false);
    assert.deepEqual({opens, syncs, closes}, {...before, closes: before.closes + 1});
    if (phase !== 'borrowed-before-link') {
      const retired = await f.store.retirePhysicalHolding(target.holding_cid);
      if (retired.cleanup.status().pending) await retired.cleanup.retry();
      assert.equal(retired.cleanup.status().pending, false);
      assert.deepEqual(await readFile(f.payloadPath), bytes);
      assert.equal((await stat(f.payloadPath)).ino, physical.ino);
    }
    await f.store.close();
  } finally {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});
}

test('private evidence is encrypted, bound, and readable after restart',
  async t => {
    const suppliedKey = Buffer.alloc(32, 7);
    const {store, configuration} = await fixture(t, {
      privateEvidenceKey: suppliedKey,
    });
    const cid = digest('private-effect-preview');
    const holdingCid = digest('private-effect-preview-holding');
    const wire = '{"sensitivity":"private","value":"secret-marker"}';
    suppliedKey.fill(0);
    const prepared = await store.preparePrivateEvidence(
      'effect_preview', wire, cid,
    );
    const stored = await store.verifyObject(prepared.physicalCid);
    assert.equal(stored.bytes, prepared.bytes);
    const ciphertext = [];
    await store.consumeObject(prepared.physicalCid,
      chunk => ciphertext.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(ciphertext).includes(
      Buffer.from('secret-marker')), false);
    assert.equal(prepared.prepared.status().pending, true);
    await assert.rejects(store.readSemanticBytes(cid),
      code('PublicationContractMissing'));
    await store.commitPhysicalHolding({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private',
      holding_cid: holdingCid,
      manifest_cid: cid,
      objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
    }, [prepared.prepared]);
    assert.equal(prepared.prepared.status().pending, false);
    assert.deepEqual(await store.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), Buffer.from(wire));
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', digest('foreign-preview'), holdingCid,
    ), code('PublicationPrivateEvidenceUnavailable'));
    await assert.rejects(store.readPrivateEvidence(
      'review_projection', cid, holdingCid,
    ), code('PublicationPrivateEvidenceCorrupt'));
    await store.close();

    const reopened = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 7),
    }, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), Buffer.from(wire));
    const binding = Object.freeze({
      name: 'effect_preview', semanticCid: cid, holdingCid, wire,
    });
    assert.deepEqual(await reopened.confirmPrivateEvidence(binding), {
      version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private',
      holding_cid: holdingCid,
      manifest_cid: cid,
      objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
    });
    await assert.rejects(reopened.confirmPrivateEvidence({
      ...binding, wire: '{"value":"different"}',
    }), code('PublicationPrivateEvidenceConflict'));
    assert.equal((await reopened.inspectPhysicalHolding(holdingCid))
      .objects[0].cid, prepared.physicalCid);
    await reopened.close();

    let rejectConfirmationSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(configuration.directory, 'physical-holdings') &&
            rejectConfirmationSync) {
          rejectConfirmationSync = false;
          const error = new Error('injected private holding sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const uncertain = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 7),
    }, contractControl, durability);
    t.after(async () => { await uncertain.close(); });
    rejectConfirmationSync = true;
    await assert.rejects(uncertain.confirmPrivateEvidence(binding),
      code('EIO'));
    assert.equal((await uncertain.confirmPrivateEvidence(binding))
      .objects[0].cid, prepared.physicalCid);
    await uncertain.close();

    const wrongKey = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 8),
    }, contractControl);
    t.after(async () => { await wrongKey.close(); });
    await assert.rejects(wrongKey.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ),
      code('PublicationPrivateEvidenceCorrupt'));
    await wrongKey.close();
    const withoutKey = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: undefined,
    }, contractControl);
    t.after(async () => { await withoutKey.close(); });
    await assert.rejects(withoutKey.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), code('PublicationPrivateEvidenceKeyUnavailable'));
    const retired = await withoutKey.retirePhysicalHolding(holdingCid);
    assert.equal(retired.deleted, true);
    assert.equal(withoutKey.status().storedBytes, 0);
  });

test('Local continuation evidence has its own private holding namespace',
  async t => {
    const {store} = await fixture(t, {
      privateEvidenceKey: Buffer.alloc(32, 6),
    });
    const wire = '{"minimum":"local-secret-marker"}';
    const semanticCid = digest(wire);
    const hold = async (name, namespace, holdingCid) => {
      const prepared = await store.preparePrivateEvidence(
        name, wire, semanticCid,
      );
      await store.commitPhysicalHolding({
        version: 'actql-local-physical-holding/0.1',
        namespace,
        holding_cid: holdingCid,
        manifest_cid: semanticCid,
        objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
      }, [prepared.prepared]);
      return prepared;
    };
    const local = digest('local-continuation-holding');
    const prepared = await hold('captured_input',
      'local-continuation-private', local);
    assert.deepEqual(await store.readPrivateEvidence(
      'captured_input', semanticCid, local,
    ), Buffer.from(wire));
    const ciphertext = [];
    await store.consumeObject(prepared.physicalCid,
      chunk => ciphertext.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(ciphertext).includes(
      Buffer.from('local-secret-marker')), false);
    // A shared holding of the same ciphertext keeps it through one retirement.
    const shared = digest('local-continuation-shared');
    await store.sharePhysicalHolding(local, {
      ...(await store.inspectPhysicalHolding(local)), holding_cid: shared,
    });
    assert.equal((await store.retirePhysicalHolding(local)).deleted, true);
    assert.deepEqual(await store.readPrivateEvidence(
      'captured_input', semanticCid, shared,
    ), Buffer.from(wire));
    // Publication evidence names are not admitted in the Local namespace.
    const foreign = digest('local-continuation-foreign');
    await hold('effect_preview', 'local-continuation-private', foreign);
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', semanticCid, foreign,
    ), code('PublicationPrivateEvidenceUnavailable'));
    assert.equal((await store.retirePhysicalHolding(foreign)).deleted, true);
    assert.equal((await store.retirePhysicalHolding(shared)).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });

test('Model raw custody preserves invalid UTF8 bytes and immutable descriptor after restart',
  async t => {
    const {store, configuration} = await fixture(t, {
      privateEvidenceKey: Buffer.alloc(32, 7),
    });
    // Physical Store test only: these authored bindings do not issue a Core
    // registration, saved receipt, retention permission or completion fact.
    const bytes = Uint8Array.of(0x7b, 0xc3, 0x28, 0x7d);
    const binding = Object.freeze({name: 'model_raw_response',
      semanticCid: digest('independent-raw-envelope'),
      holdingCid: digest('independent-raw-cell'),
      wire: '{"independent":"descriptor"}', contentCid: digest(bytes),
      byteCount: bytes.byteLength});
    let writes = 0;
    const physical = Object.freeze({
      ...store,
      async prepareModelRawEvidence(...args) {
        writes++;
        return store.prepareModelRawEvidence(...args);
      },
    });
    const owner = preparePrivatePublicationHolding(physical, binding, bytes);
    const record = await owner.commit();
    assert.equal(owner.status().committed, true);
    assert.equal(record.objects.length, 2);
    assert.equal(writes, 1);
    await owner.retry();
    assert.equal(writes, 1);
    const {name, ...readBinding} = binding;
    assert.deepEqual(await store.readModelRawEvidence(readBinding), Buffer.from(bytes));
    assert.throws(() => new TextDecoder('utf-8', {fatal: true}).decode(bytes));
    for (const object of record.objects) {
      const encrypted = [];
      await store.consumeObject(object.cid, chunk => encrypted.push(Buffer.from(chunk)));
      assert.equal(Buffer.concat(encrypted).includes(Buffer.from(bytes)), false);
    }
    await store.close();
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    t.after(() => reopened.close());
    assert.deepEqual((await reopened.confirmModelRawEvidence(readBinding)).bytes,
      Buffer.from(bytes));
    for (const changed of [
      {...readBinding, semanticCid: digest('other-entry-envelope')},
      {...readBinding, wire: '{"independent":"changed"}'},
      {...readBinding, contentCid: digest('other-body')},
      {...readBinding, byteCount: 3},
    ]) await assert.rejects(reopened.confirmModelRawEvidence(changed));
    const restored = preparePrivatePublicationHolding(reopened, binding, bytes);
    assert.equal((await restored.commit()).holding_cid, binding.holdingCid);
    assert.equal(await restored.abort(), false);
    const retirement = await reopened.retirePhysicalHolding(binding.holdingCid);
    assert.equal(retirement.deleted, true);
  });

test('Model raw lost commit response reconciles the same cell without new encryption',
  async t => {
    const {store} = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
    const bytes = Buffer.from('{"answer":"e\u0301\\r\\n"}', 'utf8');
    const binding = Object.freeze({name: 'model_raw_response',
      semanticCid: digest('lost-commit-envelope'), holdingCid: digest('lost-commit-cell'),
      wire: '{"independent":"lost-commit-descriptor"}',
      contentCid: digest(bytes), byteCount: bytes.byteLength});
    let writes = 0, commits = 0, confirmations = 0;
    const physical = Object.freeze({...store,
      async prepareModelRawEvidence(...args) {
        writes++;
        return store.prepareModelRawEvidence(...args);
      },
      async commitPhysicalHolding(...args) {
        commits++;
        await store.commitPhysicalHolding(...args);
        throw Object.assign(new Error('lost commit response'), {code: 'InjectedLoss'});
      },
      async confirmModelRawEvidence(...args) {
        confirmations++;
        // Initial lookup is absent. The first reconciliation is unknown.
        if (confirmations === 2) throw Object.assign(
          new Error('unavailable confirmation'), {code: 'InjectedUnknown'});
        return store.confirmModelRawEvidence(...args);
      },
    });
    const owner = preparePrivatePublicationHolding(physical, binding, bytes);
    await assert.rejects(owner.commit(), error => {
      assert.equal(error.code, 'InjectedLoss');
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle, owner);
      return true;
    });
    assert.equal(owner.status().committed, false);
    const record = await owner.retry();
    assert.equal(record.holding_cid, binding.holdingCid);
    assert.equal(owner.status().committed, true);
    assert.equal(writes, 1);
    assert.equal(commits, 1);
    const {name, ...readBinding} = binding;
    assert.deepEqual(await store.readModelRawEvidence(readBinding), bytes);
  });

test('Model raw selected originals require exact same Store availability', async t => {
  const {store, configuration} = await fixture(t);
  // This physical test does not admit these bodies as policy or issue a grant.
  const originals = ['retention_contract', 'metadata_retention_policy',
    'clock_contract', 'data_policy'].map(kind => {
    const wire = JSON.stringify({independent: kind, text: 'e\u0301\r\n'});
    return Object.freeze({kind, cid: digest(wire), wire});
  });
  await assert.rejects(store.confirmModelRawCaptureOriginals(
    originals, configuration.storeAuthorityCid,
  ), {code: 'PublicationContractMissing'});
  for (const original of originals) await store.putSemantic(original.wire, original.cid);
  assert.equal(await store.confirmModelRawCaptureOriginals(
    originals, configuration.storeAuthorityCid,
  ), true);
  for (let index = 0; index < originals.length; index++) {
    const changed = originals.map((original, ordinal) => ordinal === index
      ? {...original, wire: original.wire.replace('e\u0301', '\u00e9')}
      : original);
    await assert.rejects(store.confirmModelRawCaptureOriginals(
      changed, configuration.storeAuthorityCid,
    ), {code: 'PublicationModelRawOriginalMismatch'});
  }
  for (const changed of [originals.slice(0, 3), [...originals, originals[0]],
    [...originals].reverse(), originals.map(original => ({...original, extra: true})),
    originals.map(original => ({...original, cid: digest('absent original')}))]) {
    await assert.rejects(store.confirmModelRawCaptureOriginals(
      changed, configuration.storeAuthorityCid,
    ));
  }
  await assert.rejects(store.confirmModelRawCaptureOriginals(
    originals, digest('foreign Store'),
  ), {code: 'InvalidPublicationModelRawOriginals'});
});

for (const action of ['retry', 'abort']) {
  test(`Model raw ${action} retains failed partial construction cleanup after reconciliation`,
    async t => {
      const {store} = await fixture(t, {privateEvidenceKey: Buffer.alloc(32, 7)});
      const bytes = Uint8Array.of(0, 1, 2);
      const binding = Object.freeze({name: 'model_raw_response',
        semanticCid: digest(`partial-${action}-envelope`),
        holdingCid: digest(`partial-${action}-cell`),
        wire: '{"independent":"partial-construction"}',
        contentCid: digest(bytes), byteCount: bytes.byteLength});
      const orphan = await store.preparePrivateEvidence(
        'model_raw_content', 'orphan backing', binding.semanticCid,
      );
      let releases = 0, preparations = 0;
      const pending = {
        status() { return orphan.prepared.status(); },
        async release() {
          if (++releases === 1) throw Object.assign(
            new Error('partial cleanup unavailable'), {code: 'InjectedCleanup'});
          return orphan.prepared.release();
        },
      };
      const observed = {...store,
        async prepareModelRawEvidence() {
          preparations++;
          throw Object.assign(new Error('second object construction failed'), {
            code: 'InjectedConstruction', cleanupPending: true, cleanupHandle: pending,
          });
        },
      };
      const owner = preparePrivatePublicationHolding(observed, binding, bytes);
      await assert.rejects(owner.commit(), {code: 'InjectedConstruction'});
      assert.equal(owner.status().preparedPending, true);
      // Another durable observation of the same immutable cell does not erase
      // this owner's still-pending partial construction responsibility.
      const completed = preparePrivatePublicationHolding(store, binding, bytes);
      await completed.commit();
      await assert.rejects(owner[action](), {code: 'InjectedCleanup'});
      assert.equal(owner.status().preparedPending, true);
      assert.equal(owner.status().committed, false);
      assert.equal(orphan.prepared.status().pending, true);
      const result = await owner[action]();
      assert.equal(action === 'abort' ? result : result.holding_cid,
        action === 'abort' ? false : binding.holdingCid);
      assert.equal(owner.status().committed, true);
      assert.equal(owner.status().preparedPending, false);
      assert.equal(orphan.prepared.status().pending, false);
      assert.equal(preparations, 1);
      assert.equal(releases, 2);
      await store.retirePhysicalHolding(binding.holdingCid);
      assert.equal(store.status().storedBytes, 0);
    });
}

test('uncommitted private evidence retains a recoverable prepared owner',
  async t => {
    const {store, configuration} = await fixture(t, {
      privateEvidenceKey: Buffer.alloc(32, 5),
    });
    const semanticCid = digest('uncommitted-private-preview');
    const first = await store.preparePrivateEvidence(
      'effect_preview', '{"value":"private"}', semanticCid,
    );
    assert.equal(first.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, first.bytes);
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', semanticCid, digest('no-holding'),
    ), code('PublicationPrivateEvidenceUnavailable'));
    await first.prepared.release();
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    await store.close();
    const reopened = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 5),
    }, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 0);
  });

test('clean Store opening defers immutable clock file observations to selected use', async t => {
  const {store, directory, configuration} = await fixture(t);
  const floor = '2026-09-18T01:00:00.000Z';
  const clocks = [cids.scope, ...Array.from({length: 8}, (_, n) => digest('unrelated-clock-' + n))];
  for (const cid of clocks) await store.observeTrustedClock(cid, floor);
  await store.close();
  const clockDirectory = join(directory, 'clocks');
  const original = fsPromises.lstat, observed = [];
  let reopened, opening = true;
  t.mock.method(fsPromises, 'lstat', async function(path, ...args) {
    if (opening && typeof path === 'string' && path.startsWith(clockDirectory + sep)) observed.push(path);
    return Reflect.apply(original, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  try {
    reopened = await openLocalPublicationStore(configuration, contractControl);
    opening = false;
    assert.equal(observed.length, 0, 'opening does not stat unrelated immutable clock records');
    assert.deepEqual(await reopened.readClockObservation(cids.scope), {clockContractCid:cids.scope, observedAt:floor});
    await assert.rejects(reopened.observeTrustedClock(cids.scope, '2026-09-18T00:59:59.999Z'), code('PublicationClockUncertain'));
  } finally {
    opening = false;
    if (reopened !== undefined) await reopened.close();
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});

for (const type of ['directory', 'symlink']) {
test(`selected clock admission refuses a deferred ${type} before sampling`, async t => {
  const {store, directory, configuration} = await fixture(t);
  const floor = '2026-09-18T01:00:00.000Z';
  await store.observeTrustedClock(cids.scope, floor);
  await store.close();
  const path = join(directory, 'clocks', cids.scope.slice(7) + '.json');
  await unlink(path);
  if (type === 'directory') await mkdir(path);
  else {
    const target = join(directory, 'foreign-clock-target');
    await writeFile(target, JSON.stringify({clockContractCid:cids.scope, observedAt:floor}));
    await fsPromises.symlink(target, path);
  }
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  try {
    await assert.rejects(reopened.readClockObservation(cids.scope), code('InvalidPublicationStoreObject'));
    let samples = 0;
    await assert.rejects(reopened.sampleTrustedClock(cids.scope, () => {samples++; return floor;}), code('InvalidPublicationStoreObject'));
    assert.equal(samples, 0, 'the original unavailable floor is not a fresh clock');
  } finally {await reopened.close();}
});
}

test('trusted clock high-water mark survives restart and rejects rollback',
  async t => {
    const {store, configuration} = await fixture(t);
    assert.deepEqual(await store.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.000Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.000Z',
    });
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.observeTrustedClock(
      cids.scope, '2026-09-18T00:59:59.999Z',
    ), code('PublicationClockUncertain'));
    assert.deepEqual(await reopened.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.000Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.000Z',
    });
    assert.deepEqual(await reopened.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.001Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.001Z',
    });
  });

test('trusted clock retains its confirmed floor after an on-disk rollback', async t => {
  const {store, directory} = await fixture(t);
  await store.observeTrustedClock(cids.scope, '2026-09-18T01:00:00.002Z');
  await writeFile(join(directory, 'clocks', `${cids.scope.slice(7)}.json`), JSON.stringify({
    clockContractCid: cids.scope, observedAt: '2026-09-18T01:00:00.000Z',
  }));
  await assert.rejects(store.observeTrustedClock(
    cids.scope, '2026-09-18T01:00:00.001Z',
  ), code('PublicationClockUncertain'));
});

test('trusted clock does not recreate a lost confirmed observation', async t => {
  const {store, directory} = await fixture(t);
  await store.observeTrustedClock(cids.scope, '2026-09-18T01:00:00.000Z');
  const path = join(directory, 'clocks', `${cids.scope.slice(7)}.json`);
  await unlink(path);
  await assert.rejects(store.observeTrustedClock(
    cids.scope, '2026-09-18T01:00:00.001Z',
  ), code('PublicationClockUncertain'));
  await assert.rejects(stat(path), {code: 'ENOENT'});
});

test('trusted clock notices same-sized changes with restored modification time', async t => {
  const {store, directory} = await fixture(t);
  const earlier = '2026-09-18T01:00:00.000Z';
  await store.observeTrustedClock(cids.scope, earlier);
  const path = join(directory, 'clocks', `${cids.scope.slice(7)}.json`);
  const fixedTime = new Date('2026-09-18T00:00:00.000Z');
  await utimes(path, fixedTime, fixedTime);
  await store.observeTrustedClock(cids.scope, earlier);
  const before = await stat(path, {bigint: true});
  const replacement = {clockContractCid: cids.scope,
    observedAt: '2026-09-18T01:00:00.002Z'};
  // Exercise a valid same-length physical replacement in either supported
  // clock format, rather than making checksum rejection the tested boundary.
  const original = JSON.parse(await readFile(path, 'utf8'));
  if (original.contentSha256 !== undefined) {
    replacement.contentSha256 = createHash('sha256')
      .update(JSON.stringify(replacement), 'utf8').digest('hex');
  }
  await writeFile(path, JSON.stringify(replacement));
  await utimes(path, fixedTime, fixedTime);
  const after = await stat(path, {bigint: true});
  assert.equal(after.ino, before.ino);
  assert.equal(after.size, before.size);
  assert.equal(after.mtimeNs, before.mtimeNs);
  assert.notEqual(after.ctimeNs, before.ctimeNs);
  await assert.rejects(store.observeTrustedClock(
    cids.scope, '2026-09-18T01:00:00.001Z',
  ), code('PublicationClockUncertain'));
});

test('trusted clock cache does not confirm a failed directory sync', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.close();
  let clockSyncs = 0;
  let rejectClockSync = false;
  const reopened = await openLocalPublicationStore(configuration, contractControl, {
    async syncDirectory(path) {
      if (path === join(directory, 'clocks')) {
        clockSyncs++;
        if (rejectClockSync) {
          const error = new Error('injected clock directory sync failure');
          error.code = 'EIO';
          throw error;
        }
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  t.after(async () => { await reopened.close(); });
  clockSyncs = 0;
  rejectClockSync = true;
  const time = '2026-09-18T01:00:00.000Z';
  await assert.rejects(reopened.observeTrustedClock(cids.scope, time), code('EIO'));
  await assert.rejects(reopened.observeTrustedClock(cids.scope, time), code('EIO'));
  assert.equal(clockSyncs, 2);
  rejectClockSync = false;
  assert.deepEqual(await reopened.observeTrustedClock(cids.scope, time), {
    clockContractCid: cids.scope, observedAt: time,
  });
  assert.equal(clockSyncs, 3);
  await reopened.observeTrustedClock(cids.scope, time);
  assert.equal(clockSyncs, 3);
});

test('trusted clock cache revalidates corrupt replacements', async t => {
  const {store, directory} = await fixture(t);
  const time = '2026-09-18T01:00:00.000Z';
  await store.observeTrustedClock(cids.scope, time);
  const path = join(directory, 'clocks', `${cids.scope.slice(7)}.json`);
  await unlink(path);
  await writeFile(path, JSON.stringify({clockContractCid: cids.scope,
    observedAt: 'not-a-timestamp'}));
  await assert.rejects(store.observeTrustedClock(cids.scope, time),
    code('InvalidPublicationClockObservation'));
});

test('trusted clock warm write consumes its typed value without reopening its own body',async t=>{
  const {store,directory,configuration}=await fixture(t);
  const first='2026-09-18T01:00:00.000Z',next='2026-09-18T01:00:00.001Z';
  await store.observeTrustedClock(cids.scope,first);
  const path=join(directory,'clocks',cids.scope.slice(7)+'.json');
  let opens=0,reads=0,syncs=0,closes=0;
  const actualOpen=fsPromises.open;
  t.mock.method(fsPromises,'open',async function(file,...args){
    const handle=await Reflect.apply(actualOpen,this,[file,...args]);
    if(String(file)===path) {
      opens++;
      const read=handle.read,readFile=handle.readFile,sync=handle.sync,close=handle.close;
      handle.read=function(...values){reads++;return Reflect.apply(read,this,values);};
      handle.readFile=function(...values){reads++;return Reflect.apply(readFile,this,values);};
      handle.sync=function(...values){syncs++;return Reflect.apply(sync,this,values);};
      handle.close=function(...values){closes++;return Reflect.apply(close,this,values);};
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    assert.equal(await store.sampleTrustedClock(cids.scope,()=>next),next);
    assert.equal(reads,0,'the same successful write is not a second wire admission');
    assert.equal(opens,1);assert.equal(syncs,1);assert.equal(closes,1);
    assert.deepEqual(await store.readClockObservation(cids.scope),{clockContractCid:cids.scope,observedAt:next});
    assert.equal(reads,0,'the unchanged private snapshot remains typed after the write');
  } finally {t.mock.restoreAll();syncBuiltinESMExports();}
  const written=JSON.parse(await readFile(path,'utf8'));
  assert.equal(written.observedAt,next);
  assert.equal(written.contentSha256,createHash('sha256').update(JSON.stringify({clockContractCid:cids.scope,observedAt:next}),'utf8').digest('hex'));
  await store.close();const reopened=await openLocalPublicationStore(configuration,contractControl);
  await assert.rejects(reopened.observeTrustedClock(cids.scope,first),code('PublicationClockUncertain'));
  assert.equal((await reopened.readClockObservation(cids.scope)).observedAt,next);await reopened.close();
});

test('trusted clock warm write refuses a changed original before accepting close',async t=>{
  const {store,directory}=await fixture(t);
  const first='2026-09-18T01:00:00.000Z',next='2026-09-18T01:00:00.001Z',changed='2026-09-18T01:00:00.002Z';
  await store.observeTrustedClock(cids.scope,first);
  const path=join(directory,'clocks',cids.scope.slice(7)+'.json');
  let changedOnce=false;const actualOpen=fsPromises.open;
  t.mock.method(fsPromises,'open',async function(file,...args){
    const handle=await Reflect.apply(actualOpen,this,[file,...args]);
    if(String(file)===path&&!changedOnce) {
      const close=handle.close;
      handle.close=async function(...values){
        const result=await Reflect.apply(close,this,values);
        if(!changedOnce) {
          changedOnce=true;
          const value={clockContractCid:cids.scope,observedAt:changed};
          await writeFile(path,JSON.stringify({...value,contentSha256:createHash('sha256').update(JSON.stringify(value),'utf8').digest('hex')}));
        }
        return result;
      };
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {await assert.rejects(store.observeTrustedClock(cids.scope,next),code('PublicationClockUncertain'));}
  finally {t.mock.restoreAll();syncBuiltinESMExports();}
  assert.equal(changedOnce,true);
  await assert.rejects(store.observeTrustedClock(cids.scope,next),code('PublicationClockUncertain'));
});

test('trusted clock warm write retains its original failed close and floor',async t=>{
  const {store,directory}=await fixture(t);
  const first='2026-09-18T01:00:00.000Z',next='2026-09-18T01:00:00.001Z';
  await store.observeTrustedClock(cids.scope,first);
  const path=join(directory,'clocks',cids.scope.slice(7)+'.json');
  let original,closes=0,failClose=true;const actualOpen=fsPromises.open;
  t.mock.method(fsPromises,'open',async function(file,...args){
    const handle=await Reflect.apply(actualOpen,this,[file,...args]);
    if(String(file)===path) {
      original=handle;const close=handle.close;
      handle.close=function(...values){closes++;return failClose?false:Reflect.apply(close,this,values);};
    }
    return handle;
  });
  syncBuiltinESMExports();let failure;
  try {
    await assert.rejects(store.observeTrustedClock(cids.scope,next),error=>{
      failure=error;return error.code==='PublicationStoreCleanupPending'&&error.cleanupHandle.status().pending===true;
    });
    assert(original);assert.equal(closes,2,'original attempt and original cleanup attempt both refuse');
    await assert.rejects(store.sampleTrustedClock(cids.scope,()=>next),code('PublicationStoreCleanupPending'));
    failClose=false;assert.equal((await failure.cleanupHandle.retry()).pending,false);
    assert.equal(closes,3);
  } finally {failClose=false;t.mock.restoreAll();syncBuiltinESMExports();}
  assert.equal(await store.sampleTrustedClock(cids.scope,()=>next),next);
  assert.equal((await store.readClockObservation(cids.scope)).observedAt,next);
});

test('sealed new objects need only their actual final directory ACK, not a staging alias ACK',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-sealed-staging-'));
  t.after(()=>removeFixtureDirectory(directory));
  const events=[];let selectedTemporary,removedSelectedTemporary=false;
  const configuration={directory,storeAuthorityCid:cids.authority,capacityBytes:1024*1024,
    maxObjectBytes:65536,maxObjects:100,maxContractNodes:4096,maxContractDepth:64};
  const durability={async syncDirectory(path){
    events.push({path,afterSelectedRemoval:removedSelectedTemporary});
    const fd=await open(path,'r');try{await fd.sync();}finally{await fd.close();}
  }};
  const store=await openLocalPublicationStore(configuration,contractControl,durability);
  const actualOpen=fsPromises.open,actualUnlink=fsPromises.unlink;
  t.mock.method(fsPromises,'open',function(file,...args){
    if(selectedTemporary===undefined&&String(file).startsWith(join(directory,'staging')+sep))selectedTemporary=String(file);
    return Reflect.apply(actualOpen,this,[file,...args]);
  });
  t.mock.method(fsPromises,'unlink',async function(file,...args){
    const result=await Reflect.apply(actualUnlink,this,[file,...args]);
    if(String(file)===selectedTemporary)removedSelectedTemporary=true;
    return result;
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const bytes=Buffer.from('one durable allocation with two temporary aliases');
  const cid=digest(bytes),path=join(directory,'objects',cid.slice(7));
  const writer=store.createObjectWriter(bytes.length);await writer.append(bytes);events.length=0;
  assert.equal((await writer.seal(cid)).created,true);
  assert(selectedTemporary);assert.equal(removedSelectedTemporary,true);
  assert.equal(events.filter(x=>x.path===join(directory,'objects')).length,1);
  // Other custody writers keep their own ACKs. Count only this payload
  // alias's cleanup, after its actual selected unlink completed.
  assert.equal(events.filter(x=>x.path===join(directory,'staging')&&x.afterSelectedRemoval).length,0);
  assert.deepEqual(await readdir(join(directory,'staging')),[]);
  const before=await stat(path);
  assert.deepEqual(await readFile(path),bytes);
  assert.equal(store.status().objectCount,1);assert.equal(store.status().storedBytes,bytes.length);
  assert.equal(writer.status().reservationHeld,false);
  // A duplicate has a DIFFERENT temporary allocation. It must retain its
  // original staging-unlink ACK before that temporary reservation retires.
  selectedTemporary=undefined;removedSelectedTemporary=false;
  const duplicate=store.createObjectWriter(bytes.length);await duplicate.append(bytes);events.length=0;
  assert.equal((await duplicate.seal(cid)).created,false);
  assert.equal(events.filter(x=>x.path===join(directory,'staging')&&x.afterSelectedRemoval).length,1);
  const after=await stat(path);assert.equal(after.dev,before.dev);assert.equal(after.ino,before.ino);
  assert.equal(store.status().objectCount,1);assert.equal(store.status().storedBytes,bytes.length);
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl,durability);
  assert.deepEqual(await reopened.verifyObject(cid),{cid,bytes:bytes.length});
  assert.deepEqual(await readFile(path),bytes);
  assert.equal(reopened.status().objectCount,1);assert.equal(reopened.status().storedBytes,bytes.length);
});

test('opening removes a reappeared sealed staging alias without losing or recharging the final object',async t=>{
  const {store,directory,configuration}=await fixture(t);
  const bytes=Buffer.from('same physical object after alias recovery'),cid=digest(bytes);
  const writer=store.createObjectWriter(bytes.length);await writer.append(bytes);await writer.seal(cid);
  const path=join(directory,'objects',cid.slice(7)),before=await stat(path);
  // Simulate only the possible reappeared directory entry, not a crash or
  // an allocation ACK: this is another link to the SAME actual inode.
  const alias=join(directory,'staging','object-00000000-0000-0000-0000-000000000001');
  await link(path,alias);const aliasState=await stat(alias);
  assert.equal(aliasState.dev,before.dev);assert.equal(aliasState.ino,before.ino);
  assert.equal((await stat(path)).nlink,2);
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await readdir(join(directory,'staging')),[]);
  assert.deepEqual(await reopened.verifyObject(cid),{cid,bytes:bytes.length});
  const after=await stat(path);assert.equal(after.dev,before.dev);assert.equal(after.ino,before.ino);assert.equal(after.nlink,1);
  assert.deepEqual(await readFile(path),bytes);
  assert.equal(reopened.status().objectCount,1);assert.equal(reopened.status().storedBytes,bytes.length);
});

test('prepared payload cleanup reuses installed directory acknowledgement before its real unlink ACK',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-prepared-capacity-ack-'));
  t.after(()=>removeFixtureDirectory(directory));
  let objectAcks=0;
  const store=await openLocalPublicationStore({directory,storeAuthorityCid:cids.authority,
    capacityBytes:1024,maxObjectBytes:1024,maxObjects:10,
    maxContractNodes:limits.maxNodes,maxContractDepth:limits.maxDepth},contractControl,{
    async syncDirectory(path){
      if(path===join(directory,'objects'))objectAcks++;
      const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
    },
  });
  objectAcks=0;
  const writer=store.createPreparedObjectWriter(7);await writer.append('payload');
  const prepared=await writer.seal(digest('payload'));assert.equal(objectAcks,1);
  await prepared.prepared.release();
  assert.equal(store.status().storedBytes,0);
  assert.equal(objectAcks,2,'the known installation ACK is not repeated before the separate unlink ACK');
  await store.close();
});

test('prepared payload holdings reclaim only the final uncommitted owner',
  async t => {
    const {store} = await fixture(t);
    const firstWriter = store.createPreparedObjectWriter(7);
    await firstWriter.append('payload');
    const first = await firstWriter.seal(digest('payload'));
    const secondWriter = store.createPreparedObjectWriter(7);
    await secondWriter.append('payload');
    const second = await secondWriter.seal(digest('payload'));
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await first.prepared.release(), true);
    assert.equal(first.prepared.status().pending, false);
    assert.equal(second.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await second.prepared.release(), true);
    assert.equal(second.prepared.status().pending, false);
    assert.equal(store.status().storedBytes, 0);
    await assert.rejects(
      store.verifyObject(digest('payload')),
      code('PublicationObjectMissing'),
    );
  });

test('prepared Result schemas retain independent owners and shared bytes',
  async t => {
    const {store} = await fixture(t);
    const first = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    const second = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    assert.equal(store.status().objectCount, 1);
    assert.equal(await first.prepared.release(), true);
    assert.equal(second.prepared.status().pending, true);
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.equal(await second.prepared.release(), true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    await assert.rejects(store.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('prepared schema release preserves an existing semantic owner',
  async t => {
    const {store} = await fixture(t);
    await store.putSemantic(resultSchemaWire, cids.schema);
    const prepared = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    assert.equal(prepared.created, false);
    assert.equal(await prepared.prepared.release(), true);
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
  });

test('existing prepared schemas retain real readers and owners without new durable metadata', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-existing-schema-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory, storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
  };
  const directories = [];
  let observing = false;
  const durability = Object.freeze({async syncDirectory(path) {
    if (observing) directories.push(path);
    const handle = await open(path, 'r');
    try { await handle.sync(); }
    finally { await handle.close(); }
  }});
  const store = await openLocalPublicationStore(configuration, contractControl, durability);
  await store.putSemantic(resultSchemaWire, cids.schema);
  const originalOpen = fsPromises.open;
  const opens = [];
  fsPromises.open = async function(path, ...args) {
    opens.push({path, flags: args[0]});
    return Reflect.apply(originalOpen, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  let first, second;
  observing = true;
  try {
    first = await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.run);
    second = await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.result);
    assert.equal(first.created, false);
    assert.equal(second.created, false);
    assert.equal(first.prepared.status().pending, true);
    assert.equal(second.prepared.status().pending, true);
    await assert.rejects(store.close(), error => {
      assert.equal(error.code, 'PublicationStoreCleanupPending');
      assert.equal(error.cleanupDiagnostic.kind, 'publication-store-close');
      assert.equal(error.cleanupDiagnostic.resources.preparedSchemas, 1);
      assert(Object.isFrozen(error.cleanupDiagnostic.resources));
      assert.equal(store.status().closed, false);
      return true;
    });
    await first.prepared.release();
    assert.equal(second.prepared.status().pending, true);
    await second.prepared.release();
  } finally {
    observing = false;
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
    if (first?.prepared.status().pending) await first.prepared.release();
    if (second?.prepared.status().pending) await second.prepared.release();
  }
  const semantic = join(directory, 'contracts', cids.schema.slice(7) + '.json');
  assert.equal(opens.filter(value => value.path === semantic).length, 2,
    'each distinct preparation acquires its own selected schema original');
  assert.deepEqual(opens.filter(value => value.path.startsWith(join(directory, 'prepared-schemas'))), [],
    'an existing durable body needs no new crash-reclamation marker');
  assert.deepEqual(directories, [], 'unchanged durable bytes require no new directory ACK');
  assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
  assert.equal(store.status().objectCount, 1);
  assert.equal(store.status().storedBytes, Buffer.byteLength(resultSchemaWire));
  assert.equal((await store.readSemanticBytes(cids.schema)).toString(), resultSchemaWire);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl, durability);
  assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(), resultSchemaWire);
  await reopened.close();
});

test('existing schema preparation reuses its actual read generation without repeated pathname observations', async t => {
  const {store,directory}=await fixture(t);
  await store.putSemantic(resultSchemaWire,cids.schema);
  const semantic=join(directory,'contracts',cids.schema.slice(7)+'.json');
  const physical=join(directory,'objects',cids.schema.slice(7));
  const originalLstat=fsPromises.lstat,counts={semantic:0,physical:0};
  fsPromises.lstat=async function(path,...args){
    if(path===semantic)counts.semantic++;
    if(path===physical)counts.physical++;
    return Reflect.apply(originalLstat,this,[path,...args]);
  };
  syncBuiltinESMExports();
  const prepared=[];
  try{
    prepared.push(await store.putPreparedResultSchema(resultSchemaWire,cids.schema,cids.run));
    assert.deepEqual(counts,{semantic:1,physical:1},
      'one existing-name selection and the actual reader link check, not post-read repeats');
    prepared.push(await store.putPreparedResultSchema(resultSchemaWire,cids.schema,cids.result));
    assert.deepEqual(counts,{semantic:1,physical:2},
      'a second preparation reacquires its own original without repeating the retained group selection');
    assert(prepared.every(value=>value.created===false&&value.prepared.status().pending));
    await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
  }finally{
    fsPromises.lstat=originalLstat;syncBuiltinESMExports();
    for(const value of prepared)await value.prepared.release();
  }
  assert.equal(store.status().objectCount,1);
  assert.equal((await store.readSemanticBytes(cids.schema)).toString(),resultSchemaWire);
});

test('existing schema preparation refuses a replacement generation while its original holder is live', async t => {
  const {store,directory}=await fixture(t);
  await store.putSemantic(resultSchemaWire,cids.schema);
  const semantic=join(directory,'contracts',cids.schema.slice(7)+'.json');
  const physical=join(directory,'objects',cids.schema.slice(7));
  const first=await store.putPreparedResultSchema(resultSchemaWire,cids.schema,cids.run);
  let failure;
  try{
    const before=await stat(physical),replacement=join(directory,'schema-replacement');
    await writeFile(replacement,resultSchemaWire);
    const after=await stat(replacement);
    assert.notEqual(String(before.dev)+':'+before.ino,String(after.dev)+':'+after.ino);
    await unlink(semantic);await unlink(physical);
    await fsPromises.link(replacement,physical);await fsPromises.link(replacement,semantic);
    await unlink(replacement);
    // Equal valid bytes are not the original prepared holder's generation.
    await assert.rejects(store.putPreparedResultSchema(resultSchemaWire,cids.schema,cids.result),error=>{
      failure=error;return error.code==='PublicationPreparedSchemaGenerationMismatch'&&error.cleanupPending===true;
    });
    assert.equal((await failure.cleanupHandle.retry()).pending,false);
    assert.equal(first.prepared.status().pending,true);
    await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
    assert.equal(store.status().objectCount,1);
  }finally{
    if(failure?.cleanupHandle.status().pending)await failure.cleanupHandle.retry();
    await first.prepared.release();
  }
});

test('existing schema preparation retains the same failed reader close', async t => {
  const {store, directory} = await fixture(t);
  await store.putSemantic(resultSchemaWire, cids.schema);
  const semantic = join(directory, 'contracts', cids.schema.slice(7) + '.json');
  const originalOpen = fsPromises.open;
  let original, closes = 0, liveCloseAttempts = 0, acquisitions = 0, allowClose = false;
  const closeFailure = Object.assign(new Error('original schema close'), {code: 'EIO'});
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (path === semantic) {
      acquisitions++;
      original = handle;
      const close = handle.close;
      handle.close = function() {
        assert.equal(this, original);
        closes++;
        if (this.fd !== -1) liveCloseAttempts++;
        if (!allowClose) throw closeFailure;
        return Reflect.apply(close, this, []);
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    let failure;
    try { await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.run); }
    catch (error) { failure = error; }
    assert.equal(failure?.primaryFailure, closeFailure);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
    await assert.rejects(failure.cleanupHandle.retry(), error => error === closeFailure);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(closes, 2);
    allowClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    // Node's stream can also observe close on the already retired wrapper.
    // Count only attempts while this original still owns its numeric FD.
    assert.equal(liveCloseAttempts, 3);
    assert.equal(original.fd, -1);
    assert.equal(acquisitions, 1, 'cleanup never acquires a replacement reader');
    assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
    assert.equal(store.status().objectCount, 1);
  } finally {
    allowClose = true;
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('existing schema preparation reacquires and refuses changed bytes', async t => {
  const {store, directory} = await fixture(t);
  await store.putSemantic(resultSchemaWire, cids.schema);
  const first = await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.run);
  await first.prepared.release();
  await writeFile(join(directory, 'contracts', cids.schema.slice(7) + '.json'), 'changed');
  let failure;
  try { await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.result); }
  catch (error) { failure = error; }
  assert.equal(failure?.cleanupPending, true);
  await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
  assert.equal(store.status().objectCount, 1, 'a failed observation does not refund stored bytes');
});

test('existing schema preparation never substitutes a visible link for a pending original ACK', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-schema-pending-ack-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory, storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
  };
  let refuse = false;
  const failure = Object.assign(new Error('original alias ACK'), {code: 'EIO'});
  const durability = Object.freeze({async syncDirectory(path) {
    if (refuse && path === join(directory, 'contracts')) throw failure;
    const handle = await open(path, 'r');
    try { await handle.sync(); }
    finally { await handle.close(); }
  }});
  const store = await openLocalPublicationStore(configuration, contractControl, durability);
  refuse = true;
  let originalFailure, prepared, preparationFailure;
  try {
    try { await store.putSemantic(resultSchemaWire, cids.schema); }
    catch (error) { originalFailure = error; }
    assert.equal(originalFailure?.cleanupHandle.status().pending, true);
    try { prepared = await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.run); }
    catch (error) { preparationFailure = error; }
    if (prepared !== undefined) await prepared.prepared.release();
    assert.equal(preparationFailure?.code, 'PublicationStoreCleanupPending');
    assert.equal(originalFailure.cleanupHandle.status().pending, true);
  } finally {
    refuse = false;
    if (prepared?.prepared.status().pending) await prepared.prepared.release();
    if (preparationFailure?.cleanupHandle.status().pending) await preparationFailure.cleanupHandle.retry();
    if (originalFailure?.cleanupHandle.status().pending) await originalFailure.cleanupHandle.retry();
  }
  assert.equal(store.status().objectCount, 1);
  const confirmed = await store.putPreparedResultSchema(resultSchemaWire, cids.schema, cids.result);
  await confirmed.prepared.release();
});

test('publication commit adopts an existing schema holder without rewriting its metadata', async t => {
  const {store, directory} = await fixture(t);
  await store.putSemantic(resultSchemaWire, cids.schema);
  const invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invocationValue, cids.policy, true);
  assert.equal(prepared.schemaPrepared.status().pending, true);
  assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
  const originalOpen = fsPromises.open;
  const schemaOpens = [];
  fsPromises.open = async function(path, ...args) {
    if (path === join(directory, 'prepared-schemas') ||
        path.startsWith(join(directory, 'prepared-schemas') + sep)) schemaOpens.push(path);
    return Reflect.apply(originalOpen, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  try {
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    assert.equal((await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence)).committed, true);
    assert.equal(prepared.schemaPrepared.status().pending, false);
  } finally {
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
    if (prepared.schemaPrepared.status().pending) await prepared.schemaPrepared.release();
    if (prepared.prepared.status().pending) await prepared.prepared.release();
  }
  assert.deepEqual(schemaOpens, [], 'the actual commit adopts only the live holder');
  assert.equal((await store.readSemanticBytes(cids.schema)).toString(), resultSchemaWire);
});

test('ordinary opening observes unchanged namespaces without directory acknowledgements', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.close();
  const observed = ['prepared-custody','physical-holdings','physical-holding-deletions','retention-extensions','deletions']
    .map(name=>join(directory,name));
  const acknowledgements = [];
  const reopened = await openLocalPublicationStore(configuration,contractControl,{async syncDirectory(path) {
    acknowledgements.push(path);
    const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
  }});
  assert.deepEqual(acknowledgements.filter(path=>observed.includes(path)),[],
    'read-only opening observations do not create a durability transition');
  await reopened.close();
});

test('unchanged opening staging and clock directories require no new durability acknowledgement', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.close();
  const selected = ['staging', 'prepared-schemas', 'metadata-deletions', 'clocks']
    .map(name => join(directory, name));
  const acknowledgements = [];
  const reopened = await openLocalPublicationStore(configuration, contractControl, {async syncDirectory(path) {
    acknowledgements.push(path);
    const handle = await open(path, 'r');
    try {await handle.sync();} finally {await handle.close();}
  }});
  try {
    assert.deepEqual(acknowledgements.filter(path => selected.includes(path)), [],
      'unchanged private directories do not create a durable transition');
  } finally {await reopened.close();}
});

test('opening staging cleanup still acknowledges each actual directory mutation', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.close();
  const selected = [
    ['staging', 'object-00000000-0000-0000-0000-000000000001'],
    ['prepared-schemas', '.staging-00000000-0000-0000-0000-000000000001.json'],
    ['metadata-deletions', '.staging-original'],
    ['clocks', '.staging-original'],
  ];
  for (const [name, temporary] of selected) {
    await writeFile(join(directory, name, temporary), 'interrupted private preparation');
  }
  const acknowledgements = [];
  const reopened = await openLocalPublicationStore(configuration, contractControl, {async syncDirectory(path) {
    const selectedDirectory = selected.find(([name]) => join(directory, name) === path);
    if (selectedDirectory !== undefined) {
      await assert.rejects(stat(join(path, selectedDirectory[1])), code('ENOENT'));
      acknowledgements.push(path);
    }
    const handle = await open(path, 'r');
    try {await handle.sync();} finally {await handle.close();}
  }});
  try {
    assert.deepEqual(acknowledgements, selected.map(([name]) => join(directory, name)),
      'each actual unlink still precedes its real directory acknowledgement');
  } finally {await reopened.close();}
});

test('opening staging cleanup does not return a Store after its directory acknowledgement fails', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.close();
  const clockDirectory = join(directory, 'clocks');
  const temporary = join(clockDirectory, '.staging-original');
  await writeFile(temporary, 'interrupted private clock preparation');
  const primary = Object.assign(new Error('lost original clock-directory acknowledgement'), {code: 'EIO'});
  let acknowledged = 0;
  await assert.rejects(openLocalPublicationStore(configuration, contractControl, {async syncDirectory(path) {
    const handle = await open(path, 'r');
    try {
      await handle.sync();
      if (path === clockDirectory) {
        acknowledged++;
        await assert.rejects(stat(temporary), code('ENOENT'));
        throw primary;
      }
    } finally {await handle.close();}
  }}), error => error === primary);
  assert.equal(acknowledged, 1);
  await assert.rejects(stat(join(directory, 'owner')), code('ENOENT'));
});

test('ordinary opening retains an existing holding without ACK and selected writes still require their own ACK', async t => {
  const {store,directory,configuration}=await fixture(t);
  const bytes=Buffer.from('same holding through read-only open');
  const payload=await preparePhysical(store,bytes);
  const holding=physicalHolding(digest('opening holding'),digest('opening manifest'),
    [{cid:payload.cid,byte_count:payload.bytes}]);
  await store.commitPhysicalHolding(holding,[payload.prepared]);
  const path=join(directory,'objects',payload.cid.slice(7)),before=await stat(path);
  await store.close();
  const acknowledgements=[];let failHoldingAck=false;
  const reopened=await openLocalPublicationStore(configuration,contractControl,{async syncDirectory(path) {
    acknowledgements.push(path);
    if(failHoldingAck&&path===join(directory,'physical-holdings'))throw Object.assign(new Error('selected holding ACK unavailable'),{code:'EIO'});
    const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
  }});
  assert.equal(acknowledgements.includes(join(directory,'physical-holdings')),false);
  assert.deepEqual(await reopened.inspectPhysicalHolding(holding.holding_cid),holding);
  const after=await stat(path);assert.equal(after.dev,before.dev);assert.equal(after.ino,before.ino);
  assert.deepEqual(await readFile(path),bytes);
  const alias={...holding,holding_cid:digest('opening selected alias')};
  failHoldingAck=true;
  await assert.rejects(reopened.sharePhysicalHolding(holding.holding_cid,alias),code('EIO'));
  failHoldingAck=false;
  const count=acknowledgements.length;
  assert.deepEqual((await reopened.sharePhysicalHolding(holding.holding_cid,alias)).record,alias);
  assert(acknowledgements.slice(count).includes(join(directory,'physical-holdings')),
    'an earlier failed ACK never becomes a successful write observation');
  assert.equal(reopened.status().objectCount,1);
  await reopened.close();
});

test('ordinary opening pending holding recovery retains its actual directory ACK and same cleanup', async t => {
  const {store,directory,configuration}=await fixture(t);
  const payload=await preparePhysical(store,'pending selected deletion');
  const holding=physicalHolding(digest('opening pending holding'),digest('opening pending manifest'),
    [{cid:payload.cid,byte_count:payload.bytes}]);
  await store.commitPhysicalHolding(holding,[payload.prepared]);
  await store.close();
  // A new disposable fixture models the original persisted deletion record;
  // it does not mutate or replay any previous Run or failed Store state.
  const marker=join(directory,'physical-holding-deletions',holding.holding_cid.slice(7)+'.json');
  await writeFile(marker,wire(holding));
  let failRecovery=true,attempts=0;
  const reopened=await openLocalPublicationStore(configuration,contractControl,{async syncDirectory(path) {
    if(path===join(directory,'physical-holding-deletions')) {
      attempts++;
      if(failRecovery)throw Object.assign(new Error('original pending deletion ACK unavailable'),{code:'EIO'});
    }
    const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
  }});
  assert(attempts>0,'actual pending recovery still reaches its own required ACK');
  assert.equal(await reopened.inspectPhysicalHolding(holding.holding_cid),undefined);
  const retired=await reopened.retirePhysicalHolding(holding.holding_cid);
  assert.equal(retired.cleanup.status().pending,true);
  await assert.rejects(reopened.close(),code('PublicationStoreCleanupPending'));
  failRecovery=false;
  const previous=attempts;
  assert.equal((await retired.cleanup.retry()).pending,false);
  assert(attempts>previous);
  assert.deepEqual(await readdir(join(directory,'physical-holding-deletions')),[]);
  await assert.rejects(reopened.verifyObject(payload.cid),code('PublicationObjectMissing'));
  await reopened.close();
});

test('empty prepared schema recovery performs no payload or contract directory ACK', async t => {
  const {store, directory, configuration} = await fixture(t);
  await store.putSemantic(resultSchemaWire, cids.schema);
  await store.close();
  assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
  const acknowledgements = [];
  const durability = Object.freeze({async syncDirectory(path) {
    acknowledgements.push(path);
    const handle = await open(path, 'r');
    try { await handle.sync(); }
    finally { await handle.close(); }
  }});
  const reopened = await openLocalPublicationStore(configuration, contractControl, durability);
  assert.deepEqual(acknowledgements.filter(path =>
    path === join(directory, 'objects') || path === join(directory, 'contracts')), [],
  'no pending schema or physical mutation needs these acknowledgements');
  assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(), resultSchemaWire);
  const before = acknowledgements.length;
  const other = 'another selected semantic body';
  await reopened.putSemantic(other, digest(other));
  assert(acknowledgements.slice(before).includes(join(directory, 'objects')),
    'new physical bytes retain their actual containing-directory ACK');
  assert(acknowledgements.slice(before).includes(join(directory, 'contracts')),
    'new semantic alias retains its separate actual directory ACK');
  await reopened.close();
});

test('restart reclaims an unpublished prepared Result schema', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-schema-crash-',
  ));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
  const controlUrl = new URL(
    '../host-common/publication-contract-control.fixture.mjs',
    import.meta.url,
  ).href;
  const child = await runStoreChild(`
    import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
    import {createPublicationContractControlFixture} from
      ${JSON.stringify(controlUrl)};
    const store = await openLocalPublicationStore(
      ${JSON.stringify(configuration)},
      createPublicationContractControlFixture(),
    );
    await store.putPreparedResultSchema(
      ${JSON.stringify(resultSchemaWire)}, ${JSON.stringify(cids.schema)},
      ${JSON.stringify(cids.run)},
    );
  `);
  assert.equal(child.exitCode, 0, child.stderr);
  const reopened = await openLocalPublicationStore(
    configuration, contractControl,
  );
  t.after(async () => { await reopened.close(); });
  assert.equal(reopened.status().storedBytes, 0);
  assert.equal(reopened.status().objectCount, 0);
  await assert.rejects(reopened.readSemanticBytes(cids.schema),
    code('PublicationContractMissing'));
});

test('restart resumes schema cleanup after alias unlink before sync',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-unlink-crash-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const child = await runStoreChild(`
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const configuration = ${JSON.stringify(configuration)};
      let armed = false;
      const durability = Object.freeze({async syncDirectory(path) {
        if (armed && path === join(configuration.directory, 'contracts')) {
          process.exit(43);
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      }});
      const store = await openLocalPublicationStore(
        configuration, createPublicationContractControlFixture(),
        durability,
      );
      const schema = await store.putPreparedResultSchema(
        ${JSON.stringify(resultSchemaWire)}, ${JSON.stringify(cids.schema)},
        ${JSON.stringify(cids.run)},
      );
      armed = true;
      await schema.prepared.release();
    `);
    assert.equal(child.exitCode, 43, child.stderr);
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
    await assert.rejects(reopened.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('restart settles prepared schema physical capacity after unlink before directory ACK', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-schema-physical-unlink-crash-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory, storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
  };
  const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
  const controlUrl = new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href;
  const child = await runStoreChild(`
    import {open} from 'node:fs/promises';
    import {join} from 'node:path';
    import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(controlUrl)};
    const configuration = ${JSON.stringify(configuration)};
    let armed = false;
    const durability = Object.freeze({async syncDirectory(path) {
      if (armed && path === join(configuration.directory, 'objects')) process.exit(44);
      const handle = await open(path, 'r');
      try {await handle.sync();} finally {await handle.close();}
    }});
    const store = await openLocalPublicationStore(configuration, createPublicationContractControlFixture(), durability);
    const schema = await store.putPreparedResultSchema(${JSON.stringify(resultSchemaWire)},
      ${JSON.stringify(cids.schema)}, ${JSON.stringify(cids.run)});
    armed = true;
    await schema.prepared.release();
  `);
  assert.equal(child.exitCode, 44, child.stderr);
  assert.deepEqual(await readdir(join(directory, 'objects')), []);
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.equal(reopened.status().storedBytes, 0);
  assert.equal(reopened.status().objectCount, 0);
  assert.deepEqual(await readdir(join(directory, 'prepared-schemas')), []);
  await reopened.close();
});

test('prepared schema cleanup retains capacity across sync failure',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-sync-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    let failContractSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failContractSync && path === join(directory, 'contracts')) {
          failContractSync = false;
          const error = new Error('injected contract sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const schema = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    failContractSync = true;
    await assert.rejects(schema.prepared.release(), code('EIO'));
    assert.equal(schema.prepared.status().pending, true);
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal((await schema.prepared.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.equal(await store.close(), true);
  });

test('schema preparation failure keeps exact retryable cleanup custody',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-prepare-fault-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    let failContractSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failContractSync && path === join(directory, 'contracts')) {
          failContractSync = false;
          const error = new Error('injected contract sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    failContractSync = true;
    let failure;
    try {
      await store.putPreparedResultSchema(
        resultSchemaWire, cids.schema, cids.run,
      );
    } catch (error) { failure = error; }
    assert.equal(failure?.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.equal(await store.close(), true);
  });

test('schema cleanup retry never deletes a replacement allocation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-replacement-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    let failObjectSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failObjectSync && path === join(directory, 'objects')) {
          failObjectSync = false;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const old = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    failObjectSync = true;
    await assert.rejects(old.prepared.release(), code('EIO'));
    const replacement = await store.putSemantic(resultSchemaWire, cids.schema);
    assert.equal(replacement.created, true);
    assert.equal((await old.prepared.retry()).pending, false);
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.equal(await store.close(), true);
  });

test('prepared payload cleanup retains ownership and capacity until retry',
  async t => {
    const {store, directory} = await fixture(t);
    const writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    const stored = await writer.seal(digest('payload'));
    const objects = join(directory, 'objects');
    await chmod(objects, 0o500);
    try {
      await assert.rejects(stored.prepared.release());
      assert.equal(stored.prepared.status().pending, true);
      assert.equal(store.status().storedBytes, 7);
      await assert.rejects(
        store.close(),
        code('PublicationStoreCleanupPending'),
      );
    } finally {
      await chmod(objects, 0o700);
    }
    const retried = await stored.prepared.retry();
    assert.equal(retried.pending, false);
    assert.equal(retried.errors.length, 1);
    assert.equal(retried.errors[0].code, 'EACCES');
    assert.equal(store.status().storedBytes, 0);
    assert.equal(await store.close(), true);
  });

test('prepared cleanup resumes directory sync after its exact unlink',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-cleanup-sync-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const objects = join(directory, 'objects');
    let failObjectSync = false;
    let objectSyncs = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === objects) {
          objectSyncs++;
          if (failObjectSync) {
            failObjectSync = false;
            const error = new Error('injected object directory sync failure');
            error.code = 'EIO';
            throw error;
          }
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    const stored = await writer.seal(digest('payload'));
    const beforeReleaseSyncs = objectSyncs;
    failObjectSync = true;
    await assert.rejects(stored.prepared.release(), code('EIO'));
    assert.equal(stored.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    await assert.rejects(
      store.verifyObject(digest('payload')),
      code('PublicationObjectMissing'),
    );
    const replacementWriter = store.createPreparedObjectWriter(7);
    await replacementWriter.append('payload');
    const replacement = await replacementWriter.seal(digest('payload'));
    assert.equal(replacement.created, true);
    assert.equal(store.status().storedBytes, 14);
    const beforeRetrySyncs = objectSyncs;
    const retried = await stored.prepared.retry();
    assert.equal(retried.pending, false);
    assert.equal(objectSyncs, beforeRetrySyncs + 1);
    assert.equal(objectSyncs > beforeReleaseSyncs + 2, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(store.status().objectCount, 1);
    assert.equal(await replacement.prepared.release(), true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(await store.close(), true);
  });

test('seal failure removes its staging alias before reclaiming custody',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-seal-custody-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const objects = join(directory, 'objects');
    let remainingObjectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === objects && remainingObjectSyncFailures > 0) {
          remainingObjectSyncFailures--;
          const error = new Error('injected object directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);

    const recoveredWriter = store.createPreparedObjectWriter(7);
    await recoveredWriter.append('payload');
    remainingObjectSyncFailures = 1;
    await assert.rejects(
      recoveredWriter.seal(digest('payload')),
      code('EIO'),
    );
    assert.equal(recoveredWriter.status().custodyPending, false);
    assert.equal(recoveredWriter.status().reservationHeld, false);
    assert.equal(store.status().storedBytes, 0);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(objects), []);

    const retriedWriter = store.createPreparedObjectWriter(7);
    await retriedWriter.append('payload');
    remainingObjectSyncFailures = 2;
    await assert.rejects(
      retriedWriter.seal(digest('payload')),
      code('EIO'),
    );
    assert.equal(retriedWriter.status().custodyPending, true);
    assert.equal(retriedWriter.status().cleanupPending, true);
    assert.equal(retriedWriter.status().reservationHeld, false);
    assert.equal(store.status().storedBytes, 7);
    assert.equal((await readdir(join(
      directory, 'prepared-custody',
    ))).length, 1);
    // The second failure is the SAME possible installation's confirmation
    // before indexed-reference reads, not its later unlink acknowledgement.
    // Keep that exact allocation/charge until the original retry confirms it.
    assert.deepEqual(await readdir(objects), [digest('payload').slice(7)]);
    const retained=await stat(join(objects,digest('payload').slice(7)));
    const [custodyName]=await readdir(join(directory,'prepared-custody'));
    const custody=JSON.parse(await readFile(join(directory,'prepared-custody',custodyName),'utf8'));
    assert.equal(String(retained.dev),custody.device);assert.equal(String(retained.ino),custody.inode);
    assert.deepEqual(await readFile(join(objects,digest('payload').slice(7))),Buffer.from('payload'));
    assert.equal(await retriedWriter.cancel(), true);
    assert.equal(retriedWriter.status().custodyPending, false);
    assert.equal(retriedWriter.status().cleanupPending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.deepEqual(await readdir(objects), []);
    assert.deepEqual(await readdir(join(
      directory, 'prepared-custody',
    )), []);
    assert.equal(await store.close(), true);
  });

test('writer retains capacity and cleanup identity until unlink succeeds',
  async t => {
    const {store, directory} = await fixture(t, {
      capacityBytes: 8,
      maxObjectBytes: 8,
    });
    const staging = join(directory, 'staging');
    let temporary;
    const originalUnlink = fsPromises.unlink;
    let refuse = true;
    t.mock.method(fsPromises, 'unlink', function(path, ...args) {
      if (refuse && path === temporary) {
        throw Object.assign(new Error('original writer staging unlink'), {code: 'EACCES'});
      }
      return Reflect.apply(originalUnlink, this, [path, ...args]);
    });
    syncBuiltinESMExports();
    const writer = store.createObjectWriter(8);
    await writer.append('retained');
    const names = await readdir(staging);
    assert.equal(names.length, 1);
    temporary = join(staging, names[0]);
    try {
      await assert.rejects(writer.seal(digest('retained')));
    } finally {
      refuse = false;
    }
    assert.deepEqual(store.status(), {
      storedBytes: 8,
      reservedBytes: 8,
      objectCount: 1,
      reservedObjects: 1,
      capacityBytes: 8,
      closed: false,
    });
    assert.equal(writer.status().cleanupPending, true);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal(await writer.cancel(), true);
    assert.equal(writer.status().cleanupPending, false);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.deepEqual(await readdir(staging), []);
    assert.deepEqual(await store.verifyObject(digest('retained')), {
      cid: digest('retained'), bytes: 8,
    });
  });

test('concurrent writers share one Store capacity and release exactly once',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 10,
      maxObjectBytes: 10,
      maxObjects: 3,
    });
    const first = store.createObjectWriter(6);
    const second = store.createObjectWriter(4);
    assert.equal(store.status().reservedBytes, 10);
    assert.equal(store.status().reservedObjects, 2);
    assert.throws(() => store.createObjectWriter(1),
      code('PublicationStoreCapacity'));
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    await Promise.all([first.append('aaaaaa'), second.append('bbbb')]);
    assert.deepEqual(await first.seal(digest('aaaaaa')), {
      cid: digest('aaaaaa'), bytes: 6, created: true,
    });
    assert.equal(await first.cancel(), false);
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().reservedBytes, 4);
    assert.throws(() => store.createObjectWriter(1),
      code('PublicationStoreCapacity'));
    assert.equal(await second.cancel(), true);
    assert.equal(await second.cancel(), false);
    assert.equal(store.status().reservedBytes, 0);
    const third = store.createObjectWriter(4);
    await third.append('cccc');
    await third.seal(digest('cccc'));
    assert.equal(store.status().storedBytes, 10);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal(await store.close(), true);
  });

test('writer checks exact byte length before copying caller-owned input',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 16,
      maxObjectBytes: 16,
    });
    const writer = store.createObjectWriter(16);
    const oversized = Buffer.alloc(2 * 1024 * 1024, 7);
    const originalFrom = Buffer.from;
    let copied = false;
    Buffer.from = function(value, ...arguments_) {
      if (value === oversized) copied = true;
      return Reflect.apply(originalFrom, Buffer, [value, ...arguments_]);
    };
    try {
      await assert.rejects(writer.append(oversized),
        code('PublicationObjectLimit'));
    } finally {
      Buffer.from = originalFrom;
    }
    assert.equal(copied, false);
    assert.equal(writer.status().bytes, 0);
    assert.equal(writer.status().reservationHeld, true);
    assert.equal(await writer.cancel(), true);

    const snapshot = store.createObjectWriter(3);
    const mutable = new Uint8Array([97, 98, 99]);
    const appended = snapshot.append(mutable);
    mutable.fill(120);
    await appended;
    assert.deepEqual(await snapshot.seal(digest('abc')), {
      cid: digest('abc'), bytes: 3, created: true,
    });
  });

test('one live Store owns the complete directory capacity authority',
  async t => {
    const {store, configuration} = await fixture(t, {
      capacityBytes: 1024,
      maxObjectBytes: 1024,
    });
    await store.putBytes(Buffer.alloc(600));
    await assert.rejects(
      openLocalPublicationStore(configuration, contractControl),
      code('PublicationStoreBusy'),
    );
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 600);
    await assert.rejects(reopened.putBytes(Buffer.alloc(600, 1)),
      code('PublicationStoreCapacity'));
  });

test('physical object capacity survives reopen without inspecting unrelated payload history', async t => {
  const {store, configuration, directory} = await fixture(t);
  const originals = [];
  for (let index = 0; index < 8; index++) {
    const bytes = Buffer.from(`retained physical capacity ${index}`);
    const object = await store.putBytes(bytes);
    const path = join(directory, 'objects', object.cid.slice(7));
    originals.push({path, bytes, state: await stat(path)});
  }
  const before = store.status();
  await store.close();
  const lstatOriginal = fsPromises.lstat, inspected = [];
  t.mock.method(fsPromises, 'lstat', function(path, ...args) {
    if (String(path).startsWith(join(directory, 'objects') + sep)) inspected.push(String(path));
    return Reflect.apply(lstatOriginal, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  let reopened;
  try {reopened = await openLocalPublicationStore(configuration, contractControl);}
  finally {t.mock.restoreAll(); syncBuiltinESMExports();}
  const after = reopened.status();
  assert.equal(after.storedBytes, before.storedBytes, 'Reopen cannot reset retained physical charges');
  assert.equal(after.objectCount, before.objectCount);
  assert.equal(reopened.publicationCapacitySupports({requiredBytes: configuration.capacityBytes,
    objectCount: 0, maxObjectBytes: configuration.maxObjectBytes}), false);
  await reopened.close();
  for (const original of originals) {
    assert.deepEqual(await readFile(original.path), original.bytes);
    const current = await stat(original.path);
    assert.equal(current.dev, original.state.dev); assert.equal(current.ino, original.state.ino);
  }
  assert.equal(inspected.length, 0,
    'A complete retained accounting index must not re-inspect every historical payload on ordinary open');
});

for (const afterCommit of [false, true]) {
test(`physical quota close retains ${afterCommit ? 'committed' : 'rolled-back'} seal Unknown until same-original cleanup`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      if (!lost) {
        lost = true;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
      }
      throw Object.assign(new Error('original physical accounting COMMIT reply unavailable'), {code: 'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, directory, configuration} = await fixture(t);
  const writer = store.createObjectWriter(7);
  await writer.append('payload');
  await writer.seal(digest('payload'));
  const original=await stat(join(directory,'objects',digest('payload').slice(7)));
  armed = true;
  try {
    await assert.rejects(store.close(), error => error.outcome === 'unknown');
    assert.equal(lost,true,'the actual original close-seal transaction was reached');
    assert.equal(store.status().closed,false);
    assert.equal(store.status().storedBytes, 7, 'uncertain Native accounting cannot reset the physical charge');
    await assert.rejects(store.close(),error=>error.outcome==='unknown');
    assert.deepEqual(await readdir(join(directory,'prepared-custody')),[]);
  } finally {
    armed = false;
  }
  assert.equal(writer.status().custodyPending, false);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.equal(reopened.status().storedBytes, 7);
  assert.equal(reopened.status().objectCount, 1);
  const current=await stat(join(directory,'objects',digest('payload').slice(7)));
  assert.equal(current.dev,original.dev);assert.equal(current.ino,original.ino);
  assert.deepEqual(await readFile(join(directory,'objects',digest('payload').slice(7))),Buffer.from('payload'));
  await reopened.close();
});
}

test('physical writer observes a lost link reply without replaying the link or leaking its charge', async t => {
  const {store, directory} = await fixture(t);
  const originalLink = fsPromises.link;
  const target = join(directory, 'objects', digest('payload').slice(7));
  let links = 0;
  t.mock.method(fsPromises, 'link', async function(from, to, ...args) {
    if (to === target) {
      links++;
      await Reflect.apply(originalLink, this, [from, to, ...args]);
      throw Object.assign(new Error('original installed link reply lost'), {code: 'EIO'});
    }
    return Reflect.apply(originalLink, this, [from, to, ...args]);
  });
  syncBuiltinESMExports();
  const writer = store.createObjectWriter(7);
  await writer.append('payload');
  await assert.rejects(writer.seal(digest('payload')), code('EIO'));
  assert.equal(links, 1);
  assert.equal(writer.status().custodyPending, false);
  assert.equal(store.status().storedBytes, 0);
  assert.deepEqual(await readdir(join(directory, 'objects')), []);
  await assert.rejects(writer.seal(digest('payload')), code('PublicationObjectWriterClosed'));
  assert.equal(links, 1);
});

test('concurrent equal payload writers charge only the winning physical generation', async t => {
  const {store, configuration} = await fixture(t);
  const first = store.createObjectWriter(7), second = store.createObjectWriter(7);
  await Promise.all([first.append('payload'), second.append('payload')]);
  const results = await Promise.all([first.seal(digest('payload')), second.seal(digest('payload'))]);
  assert.equal(results.filter(result => result.created).length, 1);
  assert.equal(store.status().storedBytes, 7);
  assert.equal(store.status().objectCount, 1);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.equal(reopened.status().storedBytes, 7);
  assert.equal(reopened.status().objectCount, 1);
  assert.deepEqual(await reopened.verifyObject(digest('payload')), {cid: digest('payload'), bytes: 7});
  await reopened.close();
});

for(const afterLink of [false,true]) {
test(`unclean physical quota recovery retains ${afterLink?'installed':'unlinked'} generation within the supported census`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-native-physical-crash-'));
  t.after(()=>removeFixtureDirectory(directory));
  const configuration={directory,storeAuthorityCid:cids.authority,capacityBytes:1024*1024,
    maxObjectBytes:64*1024,maxObjects:100,maxContractNodes:limits.maxNodes,maxContractDepth:limits.maxDepth};
  const storeUrl=new URL('./publication-store.mjs',import.meta.url).href;
  const controlUrl=new URL('../host-common/publication-contract-control.fixture.mjs',import.meta.url).href;
  const child=await runStoreChild(`
    import fs from 'node:fs/promises';import {syncBuiltinESMExports} from 'node:module';
    import {join} from 'node:path';
    import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(controlUrl)};
    const configuration=${JSON.stringify(configuration)},link=fs.link;
    const store=await openLocalPublicationStore(configuration,createPublicationContractControlFixture());
    fs.link=async function(from,to,...args){
      if(String(to).startsWith(join(configuration.directory,'objects')+'/')) {
        if(!${afterLink})process.exit(45);
      }
      return Reflect.apply(link,this,[from,to,...args]);
    };syncBuiltinESMExports();
    const writer=store.createObjectWriter(${Buffer.byteLength(resultSchemaWire)});
    await writer.append(${JSON.stringify(resultSchemaWire)});
    await writer.seal();
    process.exit(45);
  `);
  assert.equal(child.exitCode,45,child.stderr);
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.equal(reopened.status().storedBytes,afterLink?Buffer.byteLength(resultSchemaWire):0);
  assert.equal(reopened.status().objectCount,afterLink?1:0);
  if(afterLink)assert.deepEqual(await reopened.verifyObject(digest(resultSchemaWire)),
    {cid:digest(resultSchemaWire),bytes:Buffer.byteLength(resultSchemaWire)});
  await assert.rejects(reopened.readSemanticBytes(cids.schema),code('PublicationContractMissing'));
  await reopened.close();
  const db=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'),{readOnly:true});
  try{assert.equal(db.prepare('SELECT count(*) AS n FROM physical_object_preparations').get().n,0);}
  finally{db.close();}
});
}

for(const phase of ['dirty','seal'])for(const afterCommit of [false,true]) {
test(`owned physical quota ${phase} retains ${afterCommit?'committed':'rolled-back'} Unknown cleanup`,async t=>{
  const exec=DatabaseSync.prototype.exec;
  let armed=false,commits=0,lost=false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT'){
      commits++;
      if(lost||commits===1){
        if(!lost){lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);}
        throw Object.assign(new Error('original native batch reply unavailable'),{code:'EIO'});
      }
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,directory,configuration}=await fixture(t);
  if(phase==='seal')await store.putSemantic(resultSchemaWire,cids.schema);
  armed=true;
  try {
    await assert.rejects(phase==='dirty'?store.putSemantic(resultSchemaWire,cids.schema):store.close(),
      error=>error.code==='DeliveryAttemptIndexCommitOutcomeUnknown'&&error.outcome==='unknown');
    assert.equal(lost,true,'the selected first-mutation or final-seal COMMIT was reached');
    assert.equal(store.status().storedBytes,phase==='dirty'?0:Buffer.byteLength(resultSchemaWire));
  }finally{
    armed=false;
  }
  assert.equal((await readdir(join(directory,'objects'))).length,phase==='dirty'?0:1);
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.equal(reopened.status().storedBytes,phase==='dirty'?0:Buffer.byteLength(resultSchemaWire));
  if(phase==='dirty')await assert.rejects(reopened.readSemanticBytes(cids.schema),code('PublicationContractMissing'));
  else assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(),resultSchemaWire);
  await reopened.close();
});
}

test('a dead local Store owner is reclaimed without weakening live exclusion',
  async t => {
    const {store, configuration, directory} = await fixture(t);
    await store.close();
    const owner = join(directory, 'owner');
    await mkdir(owner, {mode: 0o700});
    await writeFile(join(owner, 'owner.json'), JSON.stringify({
      version: 'actql-local-publication-store-owner/0.1',
      pid: 2_147_483_647,
      token: 'dead-owner',
    }));
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(
      openLocalPublicationStore(configuration, contractControl),
      code('PublicationStoreBusy'),
    );
  });

test('restart reclaims a prepared payload abandoned by process exit',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-prepared-crash-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const payload = 'prepared payload abandoned by process exit';
    const child = await runStoreChild(`
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
      );
      const writer = store.createPreparedObjectWriter(
        Buffer.byteLength(${JSON.stringify(payload)}, 'utf8'),
      );
      await writer.append(${JSON.stringify(payload)});
      const sealed = await writer.seal();
      process.stdout.write(sealed.cid);
    `);
    assert.equal(child.exitCode, 0, child.stderr);
    assert.equal(child.signal, null);
    const abandonedCid = child.stdout;
    const store = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await store.close(); });
    await assert.rejects(
      store.verifyObject(abandonedCid),
      code('PublicationObjectMissing'),
    );
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
  });

test('restart reclaims a semantic object from a pre-link process crash',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-semantic-crash-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const value = invocation();
    const admitted = contractControl.admit(
      'run_invocation', wire(value), limits,
    );
    const physicalCid = digest(admitted.wire);
    const child = await runStoreChild(`
      import {constants} from 'node:fs';
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const directory = ${JSON.stringify(directory)};
      const durability = Object.freeze({async syncDirectory(path) {
        const handle = await open(path, constants.O_RDONLY);
        try { await handle.sync(); } finally { await handle.close(); }
        if (path === join(directory, 'objects')) process.exit(73);
      }});
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
        durability,
      );
      await store.putPublicationContract(
        'run_invocation', ${JSON.stringify(admitted.wire)},
      );
    `);
    assert.equal(child.exitCode, 73, child.stderr);
    assert.equal(child.signal, null);
    const store = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await store.close(); });
    await assert.rejects(
      store.verifyObject(physicalCid),
      code('PublicationObjectMissing'),
    );
    await assert.rejects(
      store.readJsonObject(value.invocation_cid, 'run_invocation'),
      code('PublicationContractMissing'),
    );
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
  });

test('restart retains the original semantic alias across a lost directory reply', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-semantic-alias-crash-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {directory, storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
  const value = invocation();
  const admitted = contractControl.admit('run_invocation', wire(value), limits);
  const physicalCid = digest(admitted.wire);
  const child = await runStoreChild(`
    import {constants} from 'node:fs';
    import {open} from 'node:fs/promises';
    import {join} from 'node:path';
    import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
    const directory = ${JSON.stringify(directory)};
    const durability = Object.freeze({async syncDirectory(path) {
      const handle = await open(path, constants.O_RDONLY);
      try { await handle.sync(); } finally { await handle.close(); }
      if (path === join(directory, 'contracts')) process.exit(73);
    }});
    const store = await openLocalPublicationStore(${JSON.stringify(configuration)},
      createPublicationContractControlFixture(), durability);
    await store.putPublicationContract('run_invocation', ${JSON.stringify(admitted.wire)});
  `);
  assert.equal(child.exitCode, 73, child.stderr);
  assert.equal(child.signal, null);
  const objectBefore = await stat(join(directory, 'objects', physicalCid.slice(7)));
  const aliasBefore = await stat(join(directory, 'contracts', value.invocation_cid.slice(7) + '.json'));
  assert.equal(objectBefore.ino, aliasBefore.ino);
  const store = await openLocalPublicationStore(configuration, contractControl);
  t.after(() => store.close());
  assert.equal((await store.verifyObject(physicalCid)).bytes, Buffer.byteLength(admitted.wire));
  assert.deepEqual(await store.readJsonObject(value.invocation_cid, 'run_invocation'), value);
  assert.equal((await stat(join(directory, 'objects', physicalCid.slice(7)))).ino, objectBefore.ino);
  assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  assert.deepEqual(await readdir(join(directory, 'staging')), []);
});

test('an unknown extra link retains the original semantic cleanup until its borrower leaves', async t => {
  const {store, directory} = await fixture(t);
  const value = invocation();
  const admitted = contractControl.admit('run_invocation', wire(value), limits);
  const physicalCid = digest(admitted.wire);
  const target = join(directory, 'contracts', value.invocation_cid.slice(7) + '.json');
  const borrowed = join(directory, 'unconfirmed-borrower');
  const originalLink = fsPromises.link;
  const primary = Object.assign(new Error('semantic alias failed with an unknown borrower'), {code: 'EIO'});
  let failure;
  fsPromises.link = async function(from, to) {
    if (to !== target) return Reflect.apply(originalLink, fsPromises, [from, to]);
    await Reflect.apply(originalLink, fsPromises, [from, borrowed]);
    throw primary;
  };
  syncBuiltinESMExports();
  const restore = () => {fsPromises.link = originalLink; syncBuiltinESMExports();};
  t.after(async () => {
    restore();
    try { await unlink(borrowed); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
  });
  await assert.rejects(store.putPublicationContract('run_invocation', admitted.wire), error => {
    failure = error;
    return error.primaryFailure === primary && error.cleanupPending === true;
  });
  restore();
  assert.equal((await store.verifyObject(physicalCid)).bytes, Buffer.byteLength(admitted.wire));
  assert.equal(failure.cleanupHandle.status().pending, true);
  await unlink(borrowed);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  await assert.rejects(store.verifyObject(physicalCid), code('PublicationObjectMissing'));
});

for (const afterCommit of [false, true]) {
test(`semantic cleanup retains its ${afterCommit ? 'committed' : 'rolled-back'} native settlement reply`, async t => {
  let store, directory, target;
  const value = invocation(), admitted = contractControl.admit('run_invocation', wire(value), limits);
  const physicalCid = digest(admitted.wire);
  const link = fsPromises.link, prepare = DatabaseSync.prototype.prepare, exec = DatabaseSync.prototype.exec;
  const primary = Object.assign(new Error('original semantic alias refused'), {code:'EIO'});
  let deleting = false, lost = false, failure;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql, ...args) {
    const statement = Reflect.apply(prepare, this, [sql, ...args]);
    if (sql === 'DELETE FROM physical_object_preparations WHERE cid=? AND device=? AND inode=?') {
      const run = statement.run;
      t.mock.method(statement, 'run', function(...values) {
        deleting = true;
        return Reflect.apply(run, this, values);
      });
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql, ...args) {
    if (deleting && !lost && sql === 'COMMIT') {
      lost = true;
      if (afterCommit) Reflect.apply(exec, this, [sql, ...args]);
      throw Object.assign(new Error('original native settlement reply lost'), {code:'EIO'});
    }
    return Reflect.apply(exec, this, [sql, ...args]);
  });
  t.mock.method(fsPromises, 'link', function(from, to, ...args) {
    if (to === target) throw primary;
    return Reflect.apply(link, this, [from, to, ...args]);
  });
  syncBuiltinESMExports();
  ({store, directory} = await fixture(t));
  target = join(directory, 'contracts', value.invocation_cid.slice(7) + '.json');
  await assert.rejects(store.putPublicationContract('run_invocation', admitted.wire), error => {
    failure = error;
    return error.primaryFailure === primary && error.cleanupPending === true;
  });
  assert.equal(lost, true);
  const first = failure.cleanupHandle.retry(), concurrent = failure.cleanupHandle.retry();
  assert.strictEqual(first, concurrent);
  assert.equal((await first).pending, false);
  assert.equal(failure.cleanupHandle.status().pending, false);
  await assert.rejects(store.verifyObject(physicalCid), code('PublicationObjectMissing'));
});
}

test('an independently adopted physical body survives a failed semantic alias', async t => {
  const {store, directory} = await fixture(t);
  const value = invocation();
  const admitted = contractControl.admit('run_invocation', wire(value), limits);
  const physicalCid = digest(admitted.wire);
  const target = join(directory, 'contracts', value.invocation_cid.slice(7) + '.json');
  const originalLink = fsPromises.link;
  const primary = Object.assign(new Error('semantic alias failed after independent physical adoption'), {code: 'EIO'});
  let adopted;
  fsPromises.link = async function(from, to) {
    if (to !== target) return Reflect.apply(originalLink, fsPromises, [from, to]);
    const writer = store.createObjectWriter(Buffer.byteLength(admitted.wire));
    await writer.append(admitted.wire);
    adopted = await writer.seal();
    throw primary;
  };
  syncBuiltinESMExports();
  const restore = () => {fsPromises.link = originalLink; syncBuiltinESMExports();};
  t.after(restore);
  await assert.rejects(store.putPublicationContract('run_invocation', admitted.wire), error => error === primary);
  restore();
  assert.equal(adopted.cid, physicalCid);
  assert.equal((await store.verifyObject(physicalCid)).bytes, Buffer.byteLength(admitted.wire));
  await assert.rejects(store.readJsonObject(value.invocation_cid, 'run_invocation'), code('PublicationContractMissing'));
  assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  assert.deepEqual(await readdir(join(directory, 'staging')), []);
});

test('crash custody cannot reclaim a committed shared allocation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-shared-custody-crash-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const initial = await openLocalPublicationStore(
      configuration, contractControl,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      initial, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(initial,
      wire(entry), prepared.required, prepared.evidence,
    );
    const materialCid = JSON.parse(
      prepared.binding.wire,
    ).material_generation_cid;
    await initial.close();

    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const payload = 'fixture durable Result payload';
    const child = await runStoreChild(`
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
      );
      const writer = store.createPreparedObjectWriter(
        Buffer.byteLength(${JSON.stringify(payload)}, 'utf8'),
      );
      await writer.append(${JSON.stringify(payload)});
      await writer.seal(${JSON.stringify(materialCid)});
    `);
    assert.equal(child.exitCode, 0, child.stderr);
    assert.equal(child.signal, null);

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal((await reopened.verifyObject(materialCid)).cid, materialCid);
    const consumed = [];
    await reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      chunk => consumed.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(consumed).toString('utf8'), payload);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  });

test('semantic contract identity remains distinct from physical body digest',
  async t => {
    const {store} = await fixture(t);
    const value = invocation();
    const stored = await store.putPublicationContract(
      'run_invocation', wire(value),
    );
    assert.equal(stored.semanticCid, value.invocation_cid);
    assert.notEqual(stored.physical.cid, stored.semanticCid);
    assert.deepEqual(await store.readJsonObject(
      value.invocation_cid, 'run_invocation',
    ), value);
    await assert.rejects(store.putSemantic(
      wire({...value, observation_set_cid: cids.result}),
      value.invocation_cid,
    ), code('PublicationSemanticIdentityConflict'));
  });

test('Store persists admitted Result Definition wire without reimplementing it',
  async t => {
    const {store} = await fixture(t);
    const definition = resultDefinition();
    const stored = await store.putPublicationContract(
      'result_definition', wire(resultDefinition()),
    );
    assert.equal(stored.semanticCid, definition.result_definition_cid);
    assert.deepEqual(await store.readJsonObject(
      definition.result_definition_cid, 'result_definition',
    ), definition);
  });

test('publication records are append-only and sequence creation is CAS',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', wire(request));
    await store.createAttempt(wire(attempt));
    const first = publicationRecord(attempt, 0, 'preparing');
    await store.appendRecord(wire(first), {uncommittedConfirmed: false});
    const committing = publicationRecord(attempt, 1, 'committing', first);
    const cancelled = publicationRecord(attempt, 1, 'cancelled', first);
    const results = await Promise.allSettled([
      store.appendRecord(wire(committing), {uncommittedConfirmed: false}),
      store.appendRecord(wire(cancelled), {uncommittedConfirmed: false}),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.filter(result => result.status === 'rejected').length, 1);
    const latest = await store.latestRecord(attempt.publication_attempt_cid);
    assert.equal(latest.sequence, 1);
    assert.ok(['committing', 'cancelled'].includes(latest.state));
  });

test('native publication preflight selects its exact supplied body keys in bounded blocks', async t => {
  let armed = false, commits = 0;
  const reads = [], prepare = DatabaseSync.prototype.prepare, exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]);
    if (/^SELECT \* FROM publication_contracts WHERE semantic_cid(?:=| IN )/u.test(sql)) {
      for (const method of ['get', 'all']) {
        const original = statement[method];
        t.mock.method(statement, method, function(...args) {
          const result = Reflect.apply(original, this, args);
          if (armed) reads.push({args, rows: method === 'all' ? result : result === undefined ? [] : [result]});
          return result;
        });
      }
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') commits++;
    return result;
  });
  const {store} = await fixture(t);
  const original = n => contractControl.admit('run_invocation', wire(seal('run_invocation', {
    version: 'actql-run-invocation/0.1', invocation_template_cid: cids.template,
    observation_set_cid: digest('preflight-original-' + n),
  })), limits);
  const selected = Array.from({length: 8}, (_, n) => original(n));
  const unrelated = Array.from({length: 24}, (_, n) => original(n + 100));
  await store.putOriginalPublicationContracts([...selected.slice(0, 2), ...unrelated]);
  const before = store.status();
  armed = true;
  const stored = await store.putOriginalPublicationContracts(selected);
  armed = false;
  assert.deepEqual(stored.map(value => value.created), [false, false, true, true, true, true, true, true]);
  assert.equal(store.status().objectCount, before.objectCount + 6);
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(commits, 1);
  const keys = new Set(selected.map(value => value.identity));
  assert(reads.every(read => read.rows.every(row => keys.has(row.semantic_cid))), 'unrelated history is not acquired');
  assert.equal(reads.length, 1, 'same synchronous operation consumes its original bounded quota selection');
  assert(reads.every(read => read.args.length === 8));
  for (const value of selected) assert.equal((await store.readPublicationContract(value.identity, value.name)).wire, value.wire);
});

test('publication setup commits its immutable bodies and initial attempt in one native transaction', async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, 'joint-publication-setup');
  const originals = [contractControl.admit('publication_request', wire(request), limits)];
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  armed = true;
  assert.equal(await persistOriginalPublicationSetup(store, originals, originalAttempt), true);
  assert.equal(commits, 1);
  assert.equal(store.status().objectCount, 2);
  assert.equal((await store.createAttempt(wire(attempt))).created, false);
  assert.equal(commits, 1, 'An already committed attempt does not create another barrier');
  assert.equal(await persistOriginalPublicationSetup(store, originals, originalAttempt), true);
  assert.equal(commits, 1, 'Repeated exact setup does not rewrite its committed metadata');
  assert.equal(store.status().objectCount, 2);
  assert.equal((await store.readPublicationContract(request.publication_request_cid, 'publication_request')).wire, wire(request));
  const preparing = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(wire(preparing), {uncommittedConfirmed: false});
  assert.equal(commits, 2, 'A later progress transition remains a distinct actual mutation');
  armed = false;
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), preparing);
});

test('joint publication setup refuses its full capacity before installing any body or attempt', async t => {
  const {store} = await fixture(t, {maxObjects: 1});
  const request = publicationRequest(), attempt = publicationAttempt(request, 'joint-publication-capacity');
  await assert.rejects(store.beginPublicationAttempt([
    contractControl.admit('publication_request', wire(request), limits)],
  contractControl.admit('publication_attempt', wire(attempt), limits)), code('PublicationStoreObjectLimit'));
  assert.equal(store.status().objectCount, 0);
  assert.equal(store.status().reservedObjects, 0);
  await assert.rejects(store.readPublicationContract(request.publication_request_cid, 'publication_request'), code('PublicationContractMissing'));
});

for (const terminal of ['committing', 'cancelled']) {
test(`publication start retains setup and initial progress in one transaction: ${terminal}`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, `publication-start-${terminal}`);
  const original = contractControl.admit('publication_request', wire(request), limits);
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const next = publicationRecord(attempt, 1, terminal, preparing);
  const records = [preparing, next].map(value => contractControl.admit('publication_record', wire(value), limits));
  armed = true;
  if (typeof store.beginPublicationAttemptWithRecords === 'function') {
    await store.beginPublicationAttemptWithRecords([original], originalAttempt, records);
  } else {
    // The original supported path has the same bodies and transitions, but
    // performs two FULL transactions without a protected action between them.
    await store.beginPublicationAttempt([original], originalAttempt);
    await store.appendInitialPublicationRecords(records);
  }
  armed = false;
  assert.equal(commits, 1);
  assert.equal(store.status().objectCount, 4);
  assert.deepEqual(await store.latestRecord(originalAttempt.identity), next);
  for (const item of [original, originalAttempt, ...records]) {
    assert.equal((await store.readPublicationContract(item.identity, item.name)).wire, item.wire);
  }
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity), next);
});
}

test('joint publication setup releases partial reservations without altering retained payload capacity', async t => {
  const {store} = await fixture(t, {capacityBytes: 8192, maxObjectBytes: 8192});
  const request = publicationRequest(), attempt = publicationAttempt(request, 'joint-retained-capacity');
  const bodyBytes = Buffer.byteLength(wire(request)) + Buffer.byteLength(wire(attempt));
  assert.ok(bodyBytes < 8192);
  const bytes = Buffer.alloc(8192 - bodyBytes + 1, 7);
  const payload = await store.putBytes(bytes), before = store.status();
  await assert.rejects(store.beginPublicationAttempt([
    contractControl.admit('publication_request', wire(request), limits)],
  contractControl.admit('publication_attempt', wire(attempt), limits)), code('PublicationStoreCapacity'));
  assert.equal(store.status().storedBytes, before.storedBytes);
  assert.equal(store.status().objectCount, before.objectCount);
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(await store.verifyObject(payload.cid), {cid: payload.cid, bytes: bytes.byteLength});
  await assert.rejects(store.readPublicationContract(request.publication_request_cid, 'publication_request'), code('PublicationContractMissing'));
});

for (const afterCommit of [false, true]) {
test(`publication start caller confirms its original ${afterCommit ? 'committed' : 'rolled-back'} group without reissuing it`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, commits = 0, begins = 0, database;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        lost = true; database = this;
        if (afterCommit) Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('publication start COMMIT reply unavailable'), {code:'EIO'});
      }
      assert.equal(this,database);
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, `start-unknown-${afterCommit}`);
  const original = contractControl.admit('publication_request',wire(request),limits);
  const originalAttempt = contractControl.admit('publication_attempt',wire(attempt),limits);
  const preparing = publicationRecord(attempt,0,'preparing');
  const committing = publicationRecord(attempt,1,'committing',preparing);
  const records = [preparing,committing].map(value => contractControl.admit('publication_record',wire(value),limits));
  const selected = {...store, async beginPublicationAttemptWithRecords(...args) {
    assert.equal(this,selected); begins++;
    return Reflect.apply(store.beginPublicationAttemptWithRecords,store,args);
  }};
  armed = true;
  assert.equal(await persistOriginalPublicationSetup(selected,[original],originalAttempt,records),true);
  armed = false;
  assert.equal(begins,1);
  assert.equal(commits,2,'one lost reply plus one real same-database confirmation');
  assert.equal(store.status().reservedObjects,0);
  assert.equal(store.status().objectCount,4);
  assert.deepEqual(await store.latestRecord(originalAttempt.identity),committing);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity),committing);
});
}

for (const file of [false,true]) for (const state of ['preparing','committing']) {
test(`publication start preserves existing ${file ? 'file' : 'native'} ${state} progress without replacing it`, async t => {
  const {store,configuration} = await fixture(t,{maxObjects:state==='preparing'?3:4});
  const request = publicationRequest(), attempt = publicationAttempt(request,`prior-start-${file}-${state}`);
  const original = contractControl.admit('publication_request',wire(request),limits);
  const originalAttempt = contractControl.admit('publication_attempt',wire(attempt),limits);
  if(file) await store.putSemantic(wire(attempt),originalAttempt.identity);
  await store.beginPublicationAttempt([original],originalAttempt);
  const preparing = publicationRecord(attempt,0,'preparing');
  await store.appendRecord(wire(preparing),{uncommittedConfirmed:false});
  const prior = state === 'preparing' ? preparing : publicationRecord(attempt,1,'committing',preparing);
  if(state === 'committing') await store.appendRecord(wire(prior),{uncommittedConfirmed:false});
  const first = publicationRecord(attempt,0,'preparing',undefined,{observed_at:'2026-09-18T00:00:10.000Z'});
  const next = publicationRecord(attempt,1,'committing',first,{observed_at:'2026-09-18T00:00:11.000Z'});
  const records = [first,next].map(value=>contractControl.admit('publication_record',wire(value),limits));
  assert.notEqual(records[0].identity,preparing.publication_record_cid);
  const before=store.status();
  await store.beginPublicationAttemptWithRecords([original],originalAttempt,records);
  assert.deepEqual(await store.latestRecord(originalAttempt.identity),prior);
  assert.equal(store.status().storedBytes,before.storedBytes);
  assert.equal(store.status().objectCount,before.objectCount);
  for(const record of records) await assert.rejects(store.readPublicationContract(record.identity,'publication_record'),code('PublicationContractMissing'));
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity),prior);
});
}

for (const file of [false,true]) for (const afterCommit of [false,true]) {
test(`existing publication start confirms only its ${file?'file':'native'} ${afterCommit?'committed':'rolled-back'} setup group`, async t => {
  const exec=DatabaseSync.prototype.exec;
  let armed=false,lost=false,commits=0,begins=0,database,failure;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if(armed&&sql==='COMMIT') {
      commits++;
      if(!lost) {
        lost=true;database=this;
        if(afterCommit)Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('existing setup COMMIT reply unavailable'),{code:'EIO'});
      }
      assert.equal(this,database);
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,configuration}=await fixture(t);
  const request=publicationRequest(),attempt=publicationAttempt(request,`prior-start-unknown-${file}-${afterCommit}`);
  const original=contractControl.admit('publication_request',wire(request),limits);
  const originalAttempt=contractControl.admit('publication_attempt',wire(attempt),limits);
  if(file)await store.putSemantic(wire(attempt),originalAttempt.identity);
  await store.beginPublicationAttempt([original],originalAttempt);
  const prior=publicationRecord(attempt,0,'preparing');
  await store.appendRecord(wire(prior),{uncommittedConfirmed:false});
  const first=publicationRecord(attempt,0,'preparing',undefined,{observed_at:'2026-09-18T00:00:10.000Z'});
  const next=publicationRecord(attempt,1,'committing',first,{observed_at:'2026-09-18T00:00:11.000Z'});
  const records=[first,next].map(value=>contractControl.admit('publication_record',wire(value),limits));
  const extra=seal('run_invocation',{version:'actql-run-invocation/0.1',
    invocation_template_cid:cids.template,observation_set_cid:digest(`setup-extra-${file}-${afterCommit}`)});
  const extraOriginal=contractControl.admit('run_invocation',wire(extra),limits);
  const selected={...store,async beginPublicationAttemptWithRecords(...args) {
    assert.equal(this,selected);begins++;
    try{return await Reflect.apply(store.beginPublicationAttemptWithRecords,store,args);}
    catch(error){failure=error;throw error;}
  }};
  armed=true;
  assert.equal(await persistOriginalPublicationSetup(selected,[original,extraOriginal],originalAttempt,records),true);
  armed=false;
  assert.equal(begins,1);assert.equal(commits,2);
  assert.equal(failure.publicationStartKind,'setup');
  assert.equal(failure.cleanupHandle.status().pending,false);
  assert.deepEqual(await store.latestRecord(originalAttempt.identity),prior);
  assert.equal((await store.readPublicationContract(extraOriginal.identity,extraOriginal.name)).wire,extraOriginal.wire);
  for(const record of records)await assert.rejects(store.readPublicationContract(record.identity,'publication_record'),code('PublicationContractMissing'));
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity),prior);
});
}

test('initial publication caller consumes its already issued cancellation pair without reissuing', async t => {
  const {store}=await fixture(t);
  const attempt=publicationAttempt(publicationRequest(),'prepared-cancellation-pair');
  const originalAttempt=contractControl.admit('publication_attempt',wire(attempt),limits);
  await store.createAttempt(wire(attempt));
  const first=publicationRecord(attempt,0,'preparing');
  const next=publicationRecord(attempt,1,'cancelled',first);
  const records=Object.freeze([first,next].map(value=>contractControl.admit('publication_record',wire(value),limits)));
  const reason=new Error('OriginalPreparedCancellation');
  const prepared=Object.freeze({records,next:records[1],cancelled:true,cancellation:reason});
  const control={issuePublicationRecord(){assert.fail('No repeated issuance for the same initial pair');}};
  await assert.rejects(appendOriginalInitialStates(store,control,originalAttempt,undefined,
    ()=>assert.fail('No repeated clock sample for immutable prepared records'),limits,prepared),error=>error===reason);
  assert.deepEqual(await store.latestRecord(originalAttempt.identity),next);
});

test('publication start refuses capacity and foreign progress before any mutation', async t => {
  const {store} = await fixture(t,{maxObjects:3});
  const request = publicationRequest(), attempt = publicationAttempt(request,'start-capacity');
  const original = contractControl.admit('publication_request',wire(request),limits);
  const originalAttempt = contractControl.admit('publication_attempt',wire(attempt),limits);
  const preparing = publicationRecord(attempt,0,'preparing');
  const committing = publicationRecord(attempt,1,'committing',preparing);
  const records = [preparing,committing].map(value=>contractControl.admit('publication_record',wire(value),limits));
  await assert.rejects(store.beginPublicationAttemptWithRecords([original],originalAttempt,records),code('PublicationStoreObjectLimit'));
  assert.equal(store.status().objectCount,0);
  assert.equal(store.status().reservedObjects,0);
  const {store:roomy} = await fixture(t);
  const foreignAttempt = publicationAttempt(request,'foreign-start');
  const foreign = publicationRecord(foreignAttempt,0,'preparing');
  await assert.rejects(roomy.beginPublicationAttemptWithRecords([original],originalAttempt,
    [contractControl.admit('publication_record',wire(foreign),limits),records[1]]),code('PublicationAttemptMismatch'));
  assert.equal(roomy.status().objectCount,0);
  assert.equal(roomy.status().reservedObjects,0);
});

test('joint publication setup rejects a non-attempt original before persistence', async t => {
  const {store} = await fixture(t);
  const request = publicationRequest();
  const wrong = contractControl.admit('publication_request', wire(request), limits);
  await assert.rejects(store.beginPublicationAttempt([], wrong), code('InvalidPublicationContract'));
  assert.equal(store.status().storedBytes, 0);
  assert.equal(store.status().objectCount, 0);
});

for (const afterCommit of [false, true]) {
test(`publication caller confirms its same ${afterCommit ? 'committed' : 'rolled-back'} setup and continues without reissuing it`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, database, confirmations = 0, begins = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      if (!lost) {
        lost = true; database = this;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('setup reply unavailable'), {code: 'EIO'});
      }
      assert.equal(this, database); confirmations++;
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, `caller-setup-${afterCommit}`);
  const original = contractControl.admit('publication_request', wire(request), limits);
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  const selected = {...store, async beginPublicationAttempt(...args) {
    assert.equal(this, selected); begins++;
    return Reflect.apply(store.beginPublicationAttempt, store, args);
  }};
  armed = true;
  assert.equal(await persistOriginalPublicationSetup(selected, [original], originalAttempt), true);
  assert.equal(begins, 1, 'Confirmation never invokes setup or issues an attempt again');
  assert.equal(confirmations, 1);
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(store.status().objectCount, 2);
  assert.equal(await store.latestRecordContract(originalAttempt.identity), undefined);
  armed = false;
  const preparing = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(wire(preparing), {uncommittedConfirmed: false});
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity), preparing);
});
}

for (const afterCommit of [false, true]) {
test(`joint publication setup retains the same ${afterCommit ? 'committed' : 'rolled-back'} Unknown body group and attempt`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, originalDatabase, confirmations = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      if (!lost) {
        lost = true; originalDatabase = this;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('joint publication setup reply unavailable'), {code: 'EIO'});
      }
      assert.equal(this, originalDatabase); confirmations++;
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, `joint-unknown-${afterCommit}`);
  const originals = [contractControl.admit('publication_request', wire(request), limits)];
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  let failure;
  armed = true;
  await assert.rejects(store.beginPublicationAttempt(originals, originalAttempt), error => {
    failure = error; return error.outcome === 'unknown' && error.cleanupHandle.status().pending;
  });
  assert.equal(store.status().reservedObjects, 2);
  await assert.rejects(store.createAttempt(wire(attempt)), code('DeliveryAttemptIndexCommitOutcomeUnknown'));
  await failure.cleanupHandle.retry();
  assert.equal(confirmations, 1);
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(store.status().objectCount, 2);
  assert.equal((await store.createAttempt(wire(attempt))).created, false);
  assert.equal(confirmations, 1);
  armed = false;
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.equal((await reopened.createAttempt(wire(attempt))).created, false);
  assert.equal((await reopened.readPublicationContract(request.publication_request_cid, 'publication_request')).wire, wire(request));
});
}

test('joint publication setup preserves an independently adopted file attempt and its progress', async t => {
  const {store, directory, configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request, 'joint-legacy-attempt');
  await store.putSemantic(wire(attempt), attempt.publication_attempt_cid);
  await store.createAttempt(wire(attempt));
  const record = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(wire(record), {uncommittedConfirmed: false});
  const path = join(directory, 'attempts', attempt.publication_attempt_cid.slice(7), 'attempt.json');
  const original = await stat(path);
  await persistOriginalPublicationSetup(store, [contractControl.admit('publication_request', wire(request), limits)],
    contractControl.admit('publication_attempt', wire(attempt), limits));
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), record);
  assert.equal((await stat(path)).ino, original.ino);
  assert.equal((await stat(path)).dev, original.dev);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), record);
});

test('publication setup keeps omitted joint support and refuses a failed explicit joint port without fallback', async () => {
  const original = {identity: digest('setup-original')}, attempt = {};
  let oldCalls = 0;
  const legacy = {async putOriginalPublicationContracts(items) {
    assert.equal(this, legacy); assert.deepEqual(items, [original]); oldCalls++;
  }};
  assert.equal(await persistOriginalPublicationSetup(legacy, [original, original], attempt), false);
  assert.equal(oldCalls, 1);
  const primary = new Error('OriginalJointSetupUnavailable');
  const selected = {...legacy, async beginPublicationAttempt() {assert.equal(this, selected); throw primary;}};
  await assert.rejects(persistOriginalPublicationSetup(selected, [original], attempt), error => error === primary);
  assert.equal(oldCalls, 1, 'A refused joint operation never falls back to another persistence attempt');
});

test('publication setup confirmation retains the original failure without complete same-Store acknowledgement', async t => {
  for (const boundary of ['pending', 'retry-failure', 'different-wire', 'different-kind', 'different-identity', 'different-identity-field', 'missing-locator', 'missing-reader']) {
    await t.test(boundary, async () => {
      const original = Object.freeze({name: 'publication_request', identity: digest('setup-request'), identityField: 'publication_request_cid', wire: 'request'});
      const attempt = Object.freeze({name: 'publication_attempt', identity: digest('setup-attempt'), identityField: 'publication_attempt_cid', wire: 'attempt'});
      let retries = 0, begins = 0, reads = 0;
      const secondary = new Error('SecondaryFailure');
      const cleanup = {status() {assert.equal(this, cleanup); return {pending: boundary === 'pending'};},
        async retry() {assert.equal(this, cleanup); retries++; if (boundary === 'retry-failure') throw secondary;}};
      const primary = Object.assign(new Error('OriginalSetupUnknown'), {code: 'PublicationMetadataCommitOutcomeUnknown', outcome: 'unknown', cleanupHandle: cleanup});
      const store = {async beginPublicationAttempt() {begins++; throw primary;},
        async readPublicationContract(cid, name) {
          assert.equal(this, store); reads++;
          const value = cid === attempt.identity ? attempt : original;
          assert.equal(name, value.name);
          if (boundary === 'different-wire') return {...value, wire: 'other'};
          if (boundary === 'different-kind') return {...value, name: 'other'};
          if (boundary === 'different-identity') return {...value, identity: digest('other')};
          if (boundary === 'different-identity-field') return {...value, identityField: 'other'};
          return value;
        }, async latestRecordContract(cid) {assert.equal(this, store); assert.equal(cid, attempt.identity); throw secondary;}};
      if (boundary === 'missing-reader') delete store.readPublicationContract;
      await assert.rejects(persistOriginalPublicationSetup(store, [original], attempt), error => error === primary);
      assert.equal(begins, 1);
      assert.equal(retries, boundary === 'missing-reader' ? 0 : 1);
      if (['pending', 'retry-failure', 'missing-reader'].includes(boundary)) assert.equal(reads, 0);
    });
  }
});

test('publication setup confirmation captures original methods and receivers before cleanup callbacks', async () => {
  const request = Object.freeze({name: 'publication_request', identity: digest('captured-setup-request'), identityField: 'publication_request_cid', wire: 'request'});
  const attempt = Object.freeze({name: 'publication_attempt', identity: digest('captured-setup-attempt'), identityField: 'publication_attempt_cid', wire: 'attempt'});
  let begins = 0, reads = 0, locators = 0, pending = true;
  const replaced = () => {throw new Error('ReplacementMustNotRun');};
  const cleanup = {status() {assert.equal(this, cleanup); return {pending};}, async retry() {
    assert.equal(this, cleanup); pending = false;
    cleanup.status = replaced; store.readPublicationContract = replaced; store.latestRecordContract = replaced;
  }};
  const primary = Object.assign(new Error('OriginalSetupUnknown'), {code: 'PublicationMetadataCommitOutcomeUnknown', outcome: 'unknown', cleanupHandle: cleanup});
  const store = {async beginPublicationAttempt() {assert.equal(this, store); begins++; throw primary;},
    async readPublicationContract(cid) {assert.equal(this, store); reads++; return cid === attempt.identity ? attempt : request;},
    async latestRecordContract(cid) {assert.equal(this, store); assert.equal(cid, attempt.identity); locators++;}};
  assert.equal(await persistOriginalPublicationSetup(store, [request], attempt), true);
  assert.deepEqual({begins, reads, locators}, {begins: 1, reads: 2, locators: 1});
});

test('healthy publication setup performs no confirmation reads or cleanup', async () => {
  const original = {identity: digest('healthy-setup-request')}, attempt = {};
  let calls = 0;
  const unexpected = () => {throw new Error('HealthySetupNeedsNoConfirmation');};
  const store = {async beginPublicationAttempt(items, supplied) {
    assert.equal(this, store); assert.deepEqual(items, [original]); assert.equal(supplied, attempt); calls++;
  }, readPublicationContract: unexpected, latestRecordContract: unexpected};
  assert.equal(await persistOriginalPublicationSetup(store, [original], attempt), true);
  assert.equal(calls, 1);
});

test('publication progress uses one native commit and no shadow file ACKs per transition',async t=>{
  const request=publicationRequest(),attempt=publicationAttempt(request,'native-progress');
  const preparing=publicationRecord(attempt,0,'preparing');
  const committing=publicationRecord(attempt,1,'committing',preparing);
  let commits=0,syncs=0,armed=false;
  const exec=DatabaseSync.prototype.exec, originalOpen=fsPromises.open;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT')commits++;
    return Reflect.apply(exec,this,[sql]);
  });
  fsPromises.open=async function(...args){
    const handle=await Reflect.apply(originalOpen,this,args),sync=handle.sync;
    handle.sync=function(...values){if(armed)syncs++;return Reflect.apply(sync,this,values);};
    return handle;
  };
  syncBuiltinESMExports();
  try{
    const {store,directory,configuration}=await fixture(t);
    armed=true;
    assert.equal((await store.createAttempt(wire(attempt))).created,true);
    assert.equal(commits,1);assert.equal(syncs,0);
    for(const record of[preparing,committing]){
      await store.appendRecord(wire(record),{uncommittedConfirmed:false});
      assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid),record);
    }
    assert.equal(commits,3);assert.equal(syncs,0);
    assert.deepEqual(await readdir(join(directory,'attempts')),[]);
    assert.deepEqual(await readdir(join(directory,'contracts')),[]);
    assert.deepEqual(await readdir(join(directory,'objects')),[]);
    assert.equal(store.status().objectCount,3);
    assert.equal(store.status().storedBytes,[attempt,preparing,committing].reduce((n,v)=>n+Buffer.byteLength(wire(v)),0));
    assert.equal((await store.createAttempt(wire(attempt))).created,false);
    assert.equal(commits,3,'an unchanged committed attempt is an observation, not another durable transition');
    await store.close();armed=false;
    const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid),committing);
  for(const value of[attempt,preparing,committing]){
    const name=value===attempt?'publication_attempt':'publication_record';
    const identity=value===attempt?value.publication_attempt_cid:value.publication_record_cid;
    assert.equal((await reopened.readPublicationContract(identity,name)).wire,wire(value));
  }
  await assert.rejects(reopened.appendRecord(wire(preparing),{uncommittedConfirmed:false}),
    code('InvalidPublicationRecordTransition'));
  }finally{armed=false;fsPromises.open=originalOpen;syncBuiltinESMExports();}
});

for (const terminal of ['committing', 'cancelled']) {
test(`initial publication group durably retains both originals with one commit: ${terminal}`, async t => {
  const attempt = publicationAttempt(publicationRequest(), `initial-group-${terminal}`);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const next = publicationRecord(attempt, 1, terminal, preparing);
  const originals = [preparing, next].map(value => contractControl.admit('publication_record', wire(value), limits));
  const exec = DatabaseSync.prototype.exec;
  let armed = false, commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, directory, configuration} = await fixture(t);
  await store.createAttempt(wire(attempt));
  armed = true;
  await store.appendInitialPublicationRecords(originals);
  armed = false;
  assert.equal(commits, 1);
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), next);
  assert.equal(store.status().objectCount, 3);
  assert.deepEqual(await readdir(join(directory, 'contracts')), []);
  assert.deepEqual(await readdir(join(directory, 'attempts')), []);
  for (const original of originals) {
    assert.equal((await store.readPublicationContract(original.identity, original.name)).wire, original.wire);
  }
  await assert.rejects(store.appendInitialPublicationRecords(originals), code('InvalidPublicationRecordTransition'));
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), next);
});
}

for (const afterCommit of [false, true]) {
test(`initial publication group confirms only its original ${afterCommit ? 'committed' : 'rolled-back'} Unknown`, async t => {
  const attempt = publicationAttempt(publicationRequest(), `group-unknown-${afterCommit}`);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  const originals = [preparing, committing].map(value => contractControl.admit('publication_record', wire(value), limits));
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, commits = 0, database, failure;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        database = this; lost = true;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('lost initial progress group COMMIT reply'), {code: 'EIO'});
      }
      assert.equal(this, database);
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  await store.createAttempt(wire(attempt));
  armed = true;
  await assert.rejects(store.appendInitialPublicationRecords(originals), error => {
    failure = error;
    return error.code === 'PublicationMetadataCommitOutcomeUnknown' && error.outcome === 'unknown' && error.cleanupHandle.status().pending;
  });
  assert.equal(lost, true);
  assert.equal(store.status().reservedObjects, 2);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(commits, 2, 'one original transaction plus one real same-original confirmation');
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(store.status().objectCount, 3);
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), committing);
  for (const original of originals) assert.equal((await store.readPublicationContract(original.identity, original.name)).wire, original.wire);
  armed = false;
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), committing);
});
}

test('initial publication group refuses incomplete foreign and over-quota originals before any progress', async t => {
  const {store} = await fixture(t, {maxObjects: 2});
  const attempt = publicationAttempt(publicationRequest(), 'group-quota');
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const next = publicationRecord(attempt, 1, 'committing', preparing);
  const originals = [preparing, next].map(value => contractControl.admit('publication_record', wire(value), limits));
  await store.createAttempt(wire(attempt));
  await assert.rejects(store.appendInitialPublicationRecords([originals[0]]), code('InvalidPublicationRecord'));
  const other = publicationAttempt(publicationRequest(), 'group-foreign');
  const foreign = contractControl.admit('publication_record', wire(publicationRecord(other, 1, 'committing', preparing)), limits);
  await assert.rejects(store.appendInitialPublicationRecords([originals[0], foreign]), code('PublicationAttemptMismatch'));
  await assert.rejects(store.appendInitialPublicationRecords(originals), code('PublicationStoreObjectLimit'));
  assert.equal(await store.latestRecord(attempt.publication_attempt_cid), undefined);
  assert.equal(store.status().objectCount, 1);
  assert.equal(store.status().reservedObjects, 0);
});

for (const afterCommit of [false, true]) {
test(`initial progress caller keeps its two originals through ${afterCommit ? 'committed' : 'rolled-back'} confirmation`, async t => {
  const attempt = publicationAttempt(publicationRequest(), `caller-group-${afterCommit}`);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  const originals = [preparing, committing].map(record => contractControl.admit('publication_record', wire(record), limits));
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, issued = 0, writes = 0, failure;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT' && !lost) {
      lost = true;
      if (afterCommit) Reflect.apply(exec, this, [sql]);
      throw Object.assign(new Error('caller initial group reply lost'), {code:'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store} = await fixture(t);
  await store.createAttempt(wire(attempt));
  const selected = {...store, async appendInitialPublicationRecords(records) {
    assert.equal(this, selected); writes++;
    assert.equal(records[0], originals[0]); assert.equal(records[1], originals[1]);
    try { return await store.appendInitialPublicationRecords(records); }
    catch (error) {failure = error; throw error;}
  }};
  const control = {
    issuePublicationRecord(selectedAttempt, previous, options) {
      assert.equal(selectedAttempt, originalAttempt);
      assert.equal(previous, issued === 0 ? undefined : originals[0]);
      assert.equal(options.state, issued === 0 ? 'preparing' : 'committing');
      return originals[issued++];
    },
    publicationAttemptAction(record, active, indexed) {
      assert.equal(record, originals[0]); assert.equal(indexed, false);
      return active ? 'append_committing' : 'check_active';
    },
  };
  armed = true;
  const actual = await appendOriginalInitialStates(selected, control, originalAttempt, undefined, () => committing.observed_at, limits);
  armed = false;
  assert.equal(actual, originals[1]); assert.equal(issued, 2); assert.equal(writes, 1);
  assert.equal(lost, true); assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), committing);
});
}

test('initial progress caller persists cancellation without a committing original or healthy confirmation reads', async t => {
  const {store} = await fixture(t);
  const attempt = publicationAttempt(publicationRequest(), 'caller-group-cancel');
  const originalAttempt = contractControl.admit('publication_attempt', wire(attempt), limits);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const cancelled = publicationRecord(attempt, 1, 'cancelled', preparing);
  const originals = [preparing, cancelled].map(record => contractControl.admit('publication_record', wire(record), limits));
  await store.createAttempt(wire(attempt));
  let issued = 0, writes = 0;
  const reason = new Error('OriginalCancellation');
  const selected = {async appendInitialPublicationRecords(records) {
    assert.equal(this, selected); writes++; return store.appendInitialPublicationRecords(records);
  }, latestRecordContract() {assert.fail('Healthy grouped append requires no confirmation reads');},
  readPublicationContract() {assert.fail('Healthy grouped append requires no confirmation reads');}};
  const control = {issuePublicationRecord(selectedAttempt, previous, options) {
    assert.equal(selectedAttempt, originalAttempt); assert.equal(previous, issued === 0 ? undefined : originals[0]);
    assert.equal(options.state, issued === 0 ? 'preparing' : 'cancelled'); return originals[issued++];
  }, publicationAttemptAction: () => 'check_active', publicationCancellationAction(record) {
    assert.equal(record, originals[0]); return 'cancel_preparing';
  }};
  await assert.rejects(appendOriginalInitialStates(selected, control, originalAttempt,
    {throwIfAborted() {throw reason;}}, () => cancelled.observed_at, limits), error => error === reason);
  assert.equal(writes, 1); assert.equal(issued, 2);
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), cancelled);
});

test('initial publication group keeps legacy file-backed attempt acknowledgements', async t => {
  const {store, directory, configuration} = await fixture(t);
  const attempt = publicationAttempt(publicationRequest(), 'file-group');
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  await store.putSemantic(wire(attempt), attempt.publication_attempt_cid);
  await store.createAttempt(wire(attempt));
  await store.appendInitialPublicationRecords([preparing, committing].map(value => contractControl.admit('publication_record', wire(value), limits)));
  for (const record of [preparing, committing]) {
    assert.equal(await readFile(join(directory, 'attempts', attempt.publication_attempt_cid.slice(7), `${record.sequence}.json`), 'utf8'), wire(record));
  }
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), committing);
});

for (const boundary of ['pending', 'retry-failure', 'first-body-changed', 'latest-kind-changed']) {
test(`initial progress caller preserves its original Unknown at ${boundary}`, async () => {
  const attempt = publicationAttempt(publicationRequest(), `group-refusal-${boundary}`);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  const originals = [preparing, committing].map(record => contractControl.admit('publication_record', wire(record), limits));
  const cleanup = {status:()=>({pending:boundary === 'pending'}), async retry() {
    assert.equal(this, cleanup);
    if (boundary === 'retry-failure') throw new Error('OriginalConfirmationFailure');
  }};
  const primary = Object.assign(new Error('OriginalInitialProgressUnknown'), {
    code:'PublicationMetadataCommitOutcomeUnknown',outcome:'unknown',cleanupHandle:cleanup,
  });
  let issued = 0, writes = 0;
  const store = {async appendInitialPublicationRecords() {assert.equal(this,store);writes++;throw primary;},
    async readPublicationContract(identity) {
      assert.equal(this,store);
      const original = originals.find(record=>record.identity===identity);
      return boundary === 'first-body-changed' ? {...original,wire:original.wire+' '} : original;
    }, async latestRecordContract() {
      assert.equal(this,store);
      return boundary === 'latest-kind-changed' ? {...originals[1],name:'other'} : originals[1];
    }};
  const control = {issuePublicationRecord:()=>originals[issued++],
    publicationAttemptAction:(_record,active)=>active?'append_committing':'check_active'};
  await assert.rejects(appendOriginalInitialStates(store,control,{identity:attempt.publication_attempt_cid},
    undefined,()=>committing.observed_at,limits),error=>error===primary);
  assert.equal(writes,1);assert.equal(issued,2);
});
}

test('initial publication port keeps omitted compatibility and rejects explicit invalid capabilities', () => {
  const declaration = publicationAst.body.find(node=>node.type==='FunctionDeclaration' && node.id.name==='validateStore');
  const validate = compileFunction(publicationSource.slice(declaration.start,declaration.end)+'\nreturn validateStore;', ['fail'])(
    code=>{throw Object.assign(new Error(code),{code});});
  const legacy = Object.fromEntries(['putPublicationContract','createAttempt','latestRecordContract','appendRecord','commitIndex',
    'inspectCommittedIndex','confirmCommittedIndex','readPublicationContract','validateCommittedEvidence','retireUncommittedPublication']
    .map(name=>[name,()=>{}]));
  assert.equal(validate(legacy),undefined);
  for (const invalid of [null,false,{},'missing']) assert.throws(
    ()=>validate({...legacy,appendInitialPublicationRecords:invalid}),code('InvalidRunPublicationStore'));
  for (const invalid of [null,false,{},'missing']) assert.throws(
    ()=>validate({...legacy,beginPublicationAttemptWithRecords:invalid}),code('InvalidRunPublicationStore'));
});

test('publication start preserves the independently adopted file attempt and record acknowledgements', async t => {
  const {store,directory,configuration} = await fixture(t);
  const request = publicationRequest(), attempt = publicationAttempt(request,'file-publication-start');
  const original = contractControl.admit('publication_request',wire(request),limits);
  const originalAttempt = contractControl.admit('publication_attempt',wire(attempt),limits);
  const preparing = publicationRecord(attempt,0,'preparing');
  const committing = publicationRecord(attempt,1,'committing',preparing);
  const records = [preparing,committing].map(value=>contractControl.admit('publication_record',wire(value),limits));
  await store.putSemantic(wire(attempt),originalAttempt.identity);
  const before = await stat(join(directory,'contracts',originalAttempt.identity.slice(7)+'.json'));
  await store.beginPublicationAttemptWithRecords([original],originalAttempt,records);
  const after = await stat(join(directory,'attempts',originalAttempt.identity.slice(7),'attempt.json'));
  assert.equal(after.dev,before.dev); assert.equal(after.ino,before.ino);
  for (const record of [preparing,committing]) assert.equal(await readFile(
    join(directory,'attempts',originalAttempt.identity.slice(7),`${record.sequence}.json`),'utf8'),wire(record));
  await store.close();
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(originalAttempt.identity),committing);
});

test('prepared publication bodies do not advance native progress and existing file bodies remain owned',async t=>{
  const {store,directory}=await fixture(t);
  const attempt=publicationAttempt(publicationRequest(),'prepared-native-progress');
  const preparing=publicationRecord(attempt,0,'preparing');
  await store.putOriginalPublicationContracts([contractControl.admit('publication_attempt',wire(attempt),limits)]);
  assert.equal((await store.createAttempt(wire(attempt))).created,true);
  await store.putPublicationContract('publication_record',wire(preparing));
  const path=join(directory,'contracts',preparing.publication_record_cid.slice(7)+'.json');
  const before=await stat(path);
  assert.equal(await store.latestRecord(attempt.publication_attempt_cid),undefined);
  await store.appendRecord(wire(preparing),{uncommittedConfirmed:false});
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid),preparing);
  assert.equal((await stat(path)).ino,before.ino);
  assert.equal(store.status().objectCount,2);
});

test('native publication progress commits a real Index and retires only the selected Run metadata',async t=>{
  const {store,configuration}=await fixture(t);
  const value=invocation(),request=publicationRequest(resultDefinition(),value.invocation_cid);
  const attempt=publicationAttempt(request,'native-index');
  const prepared=await prepareCommit(store,request,attempt,value,cids.policy,false,true);
  const entry=indexEntry(request,attempt,value,{durable_result_binding_cids:[prepared.binding.identity]});
  assert.equal((await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence)).committed,true);
  const committed=publicationRecord(attempt,2,'succeeded',prepared.committing,{
    public_index_entry_cid:entry.public_index_entry_cid,
  });
  await store.appendRecord(wire(committed),{uncommittedConfirmed:false});
  const other=publicationAttempt(publicationRequest(resultDefinition(),digest('other native Run')),'other');
  await store.createAttempt(wire(other));
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid),committed);
  assert.equal((await reopened.inspectCommittedIndex(indexKeyFor(request))).public_index_entry_cid,entry.public_index_entry_cid);
  const retired=await reopened.retireCommittedPublicationMetadata(indexKeyFor(request),'2026-09-19T00:00:00.000Z');
  assert.equal(retired.deleted,true);
  await assert.rejects(reopened.createAttempt(wire(attempt)),code('PublicationMetadataDeleted'));
  assert.equal((await reopened.createAttempt(wire(other))).created,false);
  assert.equal((await reopened.readPublicationContract(other.publication_attempt_cid,'publication_attempt')).wire,wire(other));
});

test('native publication progress keeps sequence CAS and capacity refusals',async t=>{
  const {store}=await fixture(t,{maxObjects:3});
  const attempt=publicationAttempt(publicationRequest(),'native-CAS');
  const preparing=publicationRecord(attempt,0,'preparing');
  await store.createAttempt(wire(attempt));
  await store.appendRecord(wire(preparing),{uncommittedConfirmed:false});
  const committing=publicationRecord(attempt,1,'committing',preparing);
  const cancelled=publicationRecord(attempt,1,'cancelled',preparing);
  const results=await Promise.allSettled([committing,cancelled].map(record=>
    store.appendRecord(wire(record),{uncommittedConfirmed:false})));
  assert.equal(results.filter(result=>result.status==='fulfilled').length,1);
  assert.equal(results.filter(result=>result.status==='rejected').length,1);
  assert.equal(store.status().objectCount,3);
  const latest=await store.latestRecord(attempt.publication_attempt_cid);
  assert.equal([committing.publication_record_cid,cancelled.publication_record_cid].includes(latest.publication_record_cid),true);
  await assert.rejects(store.createAttempt(wire(publicationAttempt(publicationRequest(),'over-quota'))),
    code('PublicationStoreObjectLimit'));
  assert.equal(store.status().objectCount,3);
});

for(const afterCommit of[false,true])for(const phase of['attempt','record']){
test(`native publication progress retains its ${phase} ${afterCommit?'committed':'rolled-back'} Unknown original`,async t=>{
  const attempt=publicationAttempt(publicationRequest(),`unknown-${phase}-${afterCommit}`);
  const record=publicationRecord(attempt,0,'preparing');
  const exec=DatabaseSync.prototype.exec;
  let armed=false,lost=false,failure;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT'){
      if(!lost){lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);}
      throw Object.assign(new Error('lost original publication progress COMMIT reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,configuration}=await fixture(t);
  if(phase==='record')await store.createAttempt(wire(attempt));
  armed=true;
  const operation=()=>phase==='attempt'?store.createAttempt(wire(attempt)):
    store.appendRecord(wire(record),{uncommittedConfirmed:false});
  await assert.rejects(operation(),error=>{failure=error;return error.outcome==='unknown'&&error.cleanupHandle?.status().pending===true;});
  assert.equal(lost,true);
  await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
  await assert.rejects(operation());
  armed=false;
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  assert.equal((await store.createAttempt(wire(attempt))).created,false);
  assert.equal(store.status().objectCount,phase==='attempt'?1:2);
  assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid),phase==='attempt'?undefined:record);
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid),phase==='attempt'?undefined:record);
});
}

for (const afterCommit of [false, true]) {
test(`Store close confirms its original ${afterCommit ? 'committed' : 'rolled-back'} publication writer before retiring capacity`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, failed = false, commits = 0, originalDatabase;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!failed) {
        failed = true;
        originalDatabase = this;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('publication COMMIT reply unavailable'), {code: 'EIO'});
      }
      assert.equal(this, originalDatabase);
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const attempt = publicationAttempt(publicationRequest(), `close-unknown-${afterCommit}`);
  await store.createAttempt(wire(attempt));
  const record = publicationRecord(attempt, 0, 'preparing');
  let failure;
  armed = true;
  await assert.rejects(store.appendRecord(wire(record), {uncommittedConfirmed: false}), error => {
    failure = error;
    return error.outcome === 'unknown' && error.cleanupHandle.status().pending;
  });
  assert.equal(store.status().reservedObjects, 1);
  try {
    const closing = store.close();
    assert.equal(store.close(), closing, 'Concurrent close shares the same original cleanup flight');
    await closing;
    assert.equal(store.status().closed, true);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.ok(commits >= 2, 'Closing confirms the same original with an actual later COMMIT');
  } finally {
    // Failed baseline evidence still owns this fixture. Test teardown uses its
    // actual original cleanup, never an ACK inferred from process exit.
    armed = false;
    if (!store.status().closed) await failure.cleanupHandle.retry();
    await store.close();
  }
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), record);
});
}

test('Store close confirms failed metadata without releasing an independent live payload', async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, failed = false;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && !failed && sql === 'COMMIT') {
      failed = true;
      throw Object.assign(new Error('publication COMMIT reply unavailable'), {code: 'EIO'});
    }
    return result;
  });
  const {store} = await fixture(t);
  const payload = store.createObjectWriter(7);
  await payload.append('payload');
  const attempt = publicationAttempt(publicationRequest(), 'close-with-live-payload');
  let failure;
  armed = true;
  await assert.rejects(store.createAttempt(wire(attempt)), error => {
    failure = error;
    return error.outcome === 'unknown';
  });
  assert.equal(store.status().reservedObjects, 2);
  await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(store.status().closed, false);
  assert.equal(store.status().reservedObjects, 1);
  assert.equal(payload.status().reservationHeld, true);
  await payload.cancel();
  await store.close();
  assert.equal(store.status().closed, true);
});

for (const afterCommit of [false, true]) {
test(`publication caller continues its exact ${afterCommit ? 'committed' : 'rolled-back'} progress original after real confirmation`, async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false, originalDatabase, confirmations = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      if (!lost) {
        lost = true; originalDatabase = this;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('publication progress reply unavailable'), {code: 'EIO'});
      }
      assert.equal(this, originalDatabase);
      confirmations++;
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const {store, configuration} = await fixture(t);
  const attempt = publicationAttempt(publicationRequest(), `same-caller-confirmation-${afterCommit}`);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  const attemptContract = contractControl.admit('publication_attempt', wire(attempt), limits);
  const previousContract = contractControl.admit('publication_record', wire(preparing), limits);
  const expected = contractControl.admit('publication_record', wire(committing), limits);
  await store.createAttempt(wire(attempt));
  await store.appendRecord(wire(preparing), {uncommittedConfirmed: false});
  let issued = 0, failure;
  const callerStore = {...store, async appendRecord(...args) {
    try { return await store.appendRecord(...args); }
    catch (error) {failure = error; throw error;}
  }};
  armed = true;
  try {
    const actual = await appendOriginalPublicationState(callerStore, {
      issuePublicationRecord(selectedAttempt, selectedPrevious) {
        issued++; assert.equal(selectedAttempt, attemptContract);
        assert.equal(selectedPrevious, previousContract); return expected;
      }}, attemptContract, previousContract, 'committing', committing.observed_at, limits);
    assert.equal(actual, expected, 'Continue with the original issued record, not a replacement Receipt');
    assert.equal(issued, 1);
    assert.equal(lost, true);
    assert.equal(confirmations, 1, 'Exactly one original mutation confirmation, not publication replay');
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(store.status().reservedObjects, 0);
    assert.deepEqual(await store.latestRecord(attempt.publication_attempt_cid), committing);
  } finally {
    armed = false;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    await store.close();
  }
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid), committing);
});
}

for (const boundary of ['generic-error', 'missing-cleanup', 'retry-failure', 'still-pending', 'missing-record', 'foreign-record', 'changed-wire']) {
test(`publication progress confirmation preserves the original failure for ${boundary}`, async () => {
  const attempt = publicationAttempt(publicationRequest(), `confirmation-${boundary}`);
  const record = publicationRecord(attempt, 0, 'preparing');
  const original = contractControl.admit('publication_record', wire(record), limits);
  let retries = 0, reads = 0;
  const cleanup = {status: () => ({pending: boundary === 'still-pending'}), async retry() {
    assert.equal(this, cleanup); retries++;
    if (boundary === 'retry-failure') throw new Error('OriginalConfirmationUnavailable');
  }};
  const primary = Object.assign(new Error('OriginalProgressFailure'), {
    code: boundary === 'generic-error' ? 'EIO' : 'PublicationMetadataCommitOutcomeUnknown',
    outcome: 'unknown', cleanupPending: true,
    ...(boundary === 'missing-cleanup' ? {} : {cleanupHandle: cleanup})});
  const store = {async appendRecord() {throw primary;}, async latestRecordContract() {
    assert.equal(this, store); reads++;
    if (boundary === 'missing-record') return undefined;
    return {...original, ...(boundary === 'foreign-record' ? {identity: digest('foreign')} : {}),
      ...(boundary === 'changed-wire' ? {wire: original.wire + ' '} : {})};
  }};
  await assert.rejects(appendOriginalPublicationState(store,
    {issuePublicationRecord: () => original}, {identity: attempt.publication_attempt_cid},
    undefined, 'preparing', record.observed_at, limits), error => error === primary);
  assert.equal(retries, ['generic-error', 'missing-cleanup'].includes(boundary) ? 0 : 1);
  assert.equal(reads, ['missing-record', 'foreign-record', 'changed-wire'].includes(boundary) ? 1 : 0);
});
}

test('healthy publication progress needs no cleanup retry or confirming reread', async () => {
  const attempt = publicationAttempt(publicationRequest(), 'healthy-original-caller');
  const record = publicationRecord(attempt, 0, 'preparing');
  const original = contractControl.admit('publication_record', wire(record), limits);
  let writes = 0, issued = 0;
  const result = await appendOriginalPublicationState({
    async appendRecord(body) {writes++; assert.equal(body, original.wire);},
    latestRecordContract() {assert.fail('No extra selected read after a healthy append');}},
  {issuePublicationRecord() {issued++; return original;}}, {identity: attempt.publication_attempt_cid},
  undefined, 'preparing', record.observed_at, limits);
  assert.equal(result, original); assert.equal(writes, 1); assert.equal(issued, 1);
});

test('publication progress persists its incoming admitted contract once per operation',async t=>{
  const admissions=new Map();
  const control={...contractControl,admit(name,body,bounds){
    admissions.set(body,(admissions.get(body)??0)+1);
    return contractControl.admit(name,body,bounds);
  }};
  const{store,directory,configuration}=await fixture(t,{},control);
  const request=publicationRequest(),attempt=publicationAttempt(request,'single-admission');
  const attemptWire=wire(attempt);
  // An independently prepared file original keeps its legacy physical path.
  await store.putPublicationContract('publication_attempt',attemptWire);admissions.clear();
  assert.equal((await store.createAttempt(attemptWire)).created,true);
  assert.equal(admissions.get(attemptWire),1,'The incoming original is not sent through raw admission again');
  admissions.clear();
  assert.equal((await store.createAttempt(attemptWire)).created,false);
  assert.equal(admissions.get(attemptWire),1,'A new operation still admits its supplied wire');
  const preparing=publicationRecord(attempt,0,'preparing');
  const committing=publicationRecord(attempt,1,'committing',preparing);
  for(const record of[preparing,committing]){
    admissions.clear();const body=wire(record);
    await store.appendRecord(body,{uncommittedConfirmed:false});
    assert.equal(admissions.get(body),1,'Only the same incoming record is reused; selected prior rows remain independent');
  }
  const semantic=join(directory,'contracts',committing.publication_record_cid.slice(7)+'.json');
  const selected=join(directory,'attempts',attempt.publication_attempt_cid.slice(7),'1.json');
  const[left,right]=await Promise.all([stat(semantic),stat(selected)]);
  assert.equal(left.dev,right.dev);assert.equal(left.ino,right.ino);
  assert.equal(await readFile(selected,'utf8'),wire(committing));
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,control);
  assert.deepEqual(await reopened.latestRecord(attempt.publication_attempt_cid),committing);
  await assert.rejects(reopened.appendRecord(wire(preparing),{uncommittedConfirmed:false}),
    code('InvalidPublicationRecordTransition'));
  await reopened.close();
});

test('publication progress still rejects incoming wire before acquiring storage',async t=>{
  let reject=false;
  const control={...contractControl,admit(name,body,bounds){
    if(reject)throw new Error('Incoming contract unavailable');
    return contractControl.admit(name,body,bounds);
  }};
  const{store,directory}=await fixture(t,{},control);
  const attempt=publicationAttempt(publicationRequest(),'refused-incoming');
  reject=true;const before=store.status();
  await assert.rejects(store.createAttempt(wire(attempt)),code('InvalidPublicationContract'));
  assert.deepEqual(store.status(),before);assert.deepEqual(await readdir(join(directory,'attempts')),[]);
  reject=false;await store.createAttempt(wire(attempt));
  reject=true;const admitted=store.status();
  await assert.rejects(store.appendRecord(wire(publicationRecord(attempt,0,'preparing')),
    {uncommittedConfirmed:false}),code('InvalidPublicationContract'));
  assert.deepEqual(store.status(),admitted);
  assert.equal(await store.latestRecord(attempt.publication_attempt_cid),undefined);
});

test('publication metadata shares actual directory ACKs across its bounded contract group', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-contract-group-'));
  t.after(() => removeFixtureDirectory(directory));
  const syncs = [], admissions = [];
  const control = {...contractControl, admit(name, body, limits) {
    admissions.push(body);
    return contractControl.admit(name, body, limits);
  }};
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64}, control, {
    async syncDirectory(path) {
      syncs.push(path);
      const handle = await open(path, 'r');
      try {await handle.sync();} finally {await handle.close();}
    },
  });
  const contracts = [0, 1, 2].map(index => ({name: 'run_invocation', wire: wire(seal('run_invocation', {
    version: 'actql-run-invocation/0.1', invocation_template_cid: cids.template,
    observation_set_cid: digest('contract-group-'+index),
  }))}));
  syncs.length = 0; admissions.length = 0;
  const stored = await store.putPublicationContracts(contracts);
  assert.equal(stored.length, 3);
  assert.deepEqual(admissions, contracts.map(contract => contract.wire));
  assert.equal(syncs.filter(path => path === join(directory, 'objects')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'contracts')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'prepared-custody')).length, 0);
  assert.equal(syncs.filter(path => path === join(directory, 'staging')).length, 0);
  assert.equal(store.status().objectCount, 3);
  for (const [index, original] of stored.entries()) {
    assert.equal((await store.readPublicationContract(original.semanticCid, 'run_invocation')).wire,
      contracts[index].wire);
  }
  assert.deepEqual(await readdir(join(directory, 'staging')), []);
  assert.equal(await store.close(), true);
});

test('physical metadata batch retains existing semantic-member deduplication and one installed charge',async t=>{
  const {store,configuration}=await fixture(t);
  const original={name:'run_invocation',wire:wire(seal('run_invocation',{
    version:'actql-run-invocation/0.1',invocation_template_cid:cids.template,
    observation_set_cid:digest('repeated physical metadata'),
  }))};
  const stored=await store.putPublicationContracts([original,original]);
  // The unchanged putPublicationContractBatch owner deduplicates identical
  // name/wire pairs before the physical batch, including in the predecessor.
  assert.equal(stored.length,1);
  assert.equal(store.status().objectCount,1);
  assert.equal(store.status().storedBytes,Buffer.byteLength(original.wire));
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.equal(reopened.status().objectCount,1);
  assert.equal((await reopened.readPublicationContract(stored[0].semanticCid,original.name)).wire,original.wire);
  await reopened.close();
});

test('publication metadata group retains the same physical ACK after partial failure', async t => {
  for (const failed of ['objects', 'contracts']) await t.test(failed, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-publication-contract-group-ack-'));
    t.after(() => removeFixtureDirectory(directory));
    let armed = false;
    const configuration = {directory, storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
      maxContractNodes: 4096, maxContractDepth: 64};
    const store = await openLocalPublicationStore(configuration, contractControl, {
      async syncDirectory(path) {
        if (armed && path === join(directory, failed)) throw Object.assign(new Error('original directory ACK'), {code: 'EIO'});
        const handle = await open(path, 'r');
        try {await handle.sync();} finally {await handle.close();}
      },
    });
    const contract = {name: 'run_invocation', wire: wire(invocation())};
    armed = true;
    let original;
    await assert.rejects(store.putPublicationContracts([contract]), error => {
      original = error;
      return error.code === 'EIO' && error.cleanupHandle.status().pending === true;
    });
    await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
    assert.equal(store.status().objectCount, 1);
    armed = false;
    assert.equal((await original.cleanupHandle.retry()).pending, false);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal(await store.close(), true);
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    const [stored] = await reopened.putPublicationContracts([contract]);
    assert.equal((await reopened.readPublicationContract(stored.semanticCid, contract.name)).wire, contract.wire);
    assert.equal(reopened.status().objectCount, 1, 'same original metadata is not allocated again');
    assert.equal(await reopened.close(), true);
  });
});

test('publication metadata group rejects invalid or excessive inputs before physical acquisition', async t => {
  const {store, directory} = await fixture(t, {maxObjects: 2});
  const valid = {name: 'run_invocation', wire: wire(invocation())};
  for (const [input, expected] of [
    [undefined, 'InvalidPublicationContractWire'],
    [new Array(3), 'PublicationStoreObjectLimit'],
    [[{name: undefined, wire: undefined}], 'InvalidPublicationContractWire'],
    [[valid, {name: 'run_invocation', wire: '{}'}], 'InvalidPublicationContract'],
  ]) {
    await assert.rejects(store.putPublicationContracts(input), code(expected));
    assert.equal(store.status().objectCount, 0);
    assert.equal(store.status().reservedObjects, 0);
    for (const name of ['objects', 'contracts', 'staging']) {
      assert.deepEqual(await readdir(join(directory, name)), []);
    }
  }
  const limited = await fixture(t, {capacityBytes: 1});
  await assert.rejects(limited.store.putPublicationContracts([valid]), code('PublicationStoreCapacity'));
  assert.equal(limited.store.status().objectCount, 0);
  assert.equal(limited.store.status().reservedObjects, 0);
});

test('publication metadata group owns its inputs before callbacks and deduplicates exact bodies', async t => {
  const first = {name: 'run_invocation', wire: wire(invocation())};
  const second = {name: 'run_invocation', wire: wire(seal('run_invocation', {
    version: 'actql-run-invocation/0.1', invocation_template_cid: cids.template,
    observation_set_cid: digest('second-group-input'),
  }))};
  const inputs = [first, {...first}, second];
  let admissions = 0;
  const control = {...contractControl, admit(name, body, limits) {
    admissions++;
    inputs[2].wire = '{}';
    return contractControl.admit(name, body, limits);
  }};
  const expected = [first.wire, second.wire];
  const {store} = await fixture(t, {}, control);
  const stored = await store.putPublicationContracts(inputs);
  assert.equal(admissions, 2);
  assert.equal(stored.length, 2);
  assert.deepEqual(stored.map(original => original.contract.wire), expected);
  assert.equal(store.status().objectCount, 2);
});

test('delivery admission batches its immutable contracts and validates each once', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-batch-'));
  t.after(() => removeFixtureDirectory(directory));
  const synced = [];
  const admissions = new Map();
  const control = {...contractControl,
    admit(name, value, limits) {
      admissions.set(name, (admissions.get(name) ?? 0) + 1);
      return contractControl.admit(name, value, limits);
    }};
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64}, control, {
    async syncDirectory(path) {
      synced.push(path);
      const handle = await open(path, 'r');
      try {await handle.sync();} finally {await handle.close();}
    },
  });
  const root = deliveryFixture(1), attempt = deliveryAttempt(root, 'batched-delivery');
  synced.length = 0; admissions.clear();
  assert.deepEqual(await store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
    {attempt, created: true});
  assert.equal(admissions.get('result_read_grant'), 1);
  assert.equal(admissions.get('delivery_attempt'), 1);
  assert.equal(synced.filter(path => path === join(directory, 'contracts')).length, 1,
    'both independent immutable links share one actual containing-directory ACK');
  assert.equal(synced.filter(path => path === join(directory, 'objects')).length, 1,
    'both closed payloads share one actual object-directory ACK');
  assert.equal(synced.filter(path => path === join(directory, 'prepared-custody')).length, 0,
    'no prepared holder escapes this final semantic publication');
  assert.equal(synced.filter(path => path === join(directory, 'staging')).length, 0,
    'transient staging deletion is not a separate logical commit');
  assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
});

test('delivery contract batches retain the same directory ACK after partial failure', async t => {
  for (const failedDirectory of ['contracts', 'objects']) {
    await t.test(failedDirectory, async t => {
      const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-batch-ack-'));
      t.after(() => removeFixtureDirectory(directory));
      let armed = false, selectedSyncs = 0, failures = 0;
      const store = await openLocalPublicationStore({directory,
        storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
        maxObjectBytes: 65536, maxObjects: 100,
        maxContractNodes: 4096, maxContractDepth: 64}, contractControl, {
        async syncDirectory(path) {
          if (armed && path === join(directory, failedDirectory)) {
            selectedSyncs++;
            failures++;
            throw Object.assign(new Error('batch directory ACK'), {code: 'EIO'});
          }
          const handle = await open(path, 'r');
          try {await handle.sync();} finally {await handle.close();}
        },
      });
      const root = deliveryFixture(1), attempt = deliveryAttempt(root, failedDirectory);
      armed = true;
      let original;
      await assert.rejects(store.createDeliveryAttempt(wire(attempt), wire(root.grant)), error => {
        original = error;
        return error.code === 'EIO' && error.cleanupHandle.status().pending === true;
      });
      assert.equal(failures, 2);
      await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
      assert.deepEqual(await readdir(join(directory, 'deliveries')), []);
      assert.equal(store.status().objectCount, 2);
      assert.equal(store.status().reservedObjects, 0);
      armed = false;
      assert.equal((await original.cleanupHandle.retry()).pending, false);
      assert.equal(original.cleanupPending, false);
      assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
      assert.equal(await store.close(), true);
      const reopened = await openLocalPublicationStore({directory,
        storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
        maxObjectBytes: 65536, maxObjects: 2,
        maxContractNodes: 4096, maxContractDepth: 64}, contractControl);
      assert.deepEqual(await reopened.createDeliveryAttempt(wire(attempt), wire(root.grant)),
        {attempt, created: false});
      assert.equal(reopened.status().objectCount, 2, 'cleanup neither reseals nor allocates replacements');
      assert.equal(await reopened.close(), true);
    });
  }
});

test('delivery contract batch reclaims its first preparation if the second refuses', async t => {
  const {store, directory} = await fixture(t, {maxObjects: 1});
  const root = deliveryFixture(1), attempt = deliveryAttempt(root, 'second-preparation-refusal');
  await assert.rejects(store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
    code('PublicationStoreObjectLimit'));
  assert.equal(store.status().objectCount, 0);
  assert.equal(store.status().reservedObjects, 0);
  for (const name of ['contracts', 'deliveries', 'prepared-custody', 'staging', 'objects']) {
    assert.deepEqual(await readdir(join(directory, name)), []);
  }
  assert.equal(await store.close(), true);
});

test('delivery contract batch cleans the first staging file while retaining a failed second writer', async t => {
  const {store, directory} = await fixture(t);
  const originalOpen = fsPromises.open;
  const stagingOpens = [];
  let acquisitions = 0, refuseClose = true, retained, retainedFd;
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (String(path).startsWith(join(directory, 'staging') + sep)) stagingOpens.push({path, flags: args[0]});
    if (String(path).startsWith(join(directory, 'staging') + sep) && ++acquisitions === 2) {
      retained = handle; retainedFd = handle.fd;
      const close = handle.close;
      handle.close = function() {
        return refuseClose ? Promise.resolve(false) : Reflect.apply(close, this, []);
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  let original;
  try {
    const root = deliveryFixture(1), attempt = deliveryAttempt(root, 'second-writer-close');
    await assert.rejects(store.createDeliveryAttempt(wire(attempt), wire(root.grant)), error => {
      original = error;
      return error.code === 'PublicationStoreCleanupPending' && error.cleanupHandle.status().pending;
    });
    assert.equal(retained.fd, retainedFd);
    assert.equal(store.status().reservedObjects, 1);
    // Independent cleanup may already reclaim the first unpublished payload.
    // That real ACK cannot discharge the second writer's still-open original FD.
    assert.equal((await readdir(join(directory, 'prepared-custody'))).length, 0,
      JSON.stringify({stagingOpens, status: store.status()}));
    assert.equal(store.status().objectCount, 0);
    await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
    refuseClose = false;
    assert.equal((await original.cleanupHandle.retry()).pending, false);
    assert.equal(retained.fd, -1);
    assert.equal(acquisitions, 2, 'cleanup never opens a replacement writer');
    assert.equal(store.status().objectCount, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  } finally {
    refuseClose = false;
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
    if (original?.cleanupHandle.status().pending) await original.cleanupHandle.retry();
  }
});

test('delivery attempts and records remain append-only after restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const root = deliveryFixture();
    const attempt = deliveryAttempt(root, 'delivery-1');
    assert.deepEqual(
      await store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
      {attempt, created: true},
    );
    assert.deepEqual(
      await store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
      {attempt, created: false},
    );
    const streaming = deliveryRecord(attempt, 0, 'streaming');
    await store.appendDeliveryRecord(wire(streaming));
    const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
      confirmed_byte_count: 7,
      failure_cid: digest('delivery failure'),
    });
    await store.appendDeliveryRecord(wire(failed));
    await store.close();

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(
      await reopened.latestDeliveryRecord(attempt.delivery_attempt_cid),
      failed,
    );
    const lookup = {
      indexKey: {namespaceId: 'namespace-a',
        authorityScopeCid: cids.scope, runDefinitionCid: cids.run},
      principalId: 'principal-a', purpose: 'download',
      resultName: 'answer', attemptId: 'delivery-1',
    };
    assert.deepEqual(await reopened.lookupDeliveryAttempt(lookup),
      {attempt, record: failed, hostReleaseReceipt: undefined});
    assert.equal(await reopened.lookupDeliveryAttempt({...lookup,
      principalId: 'different-principal'}), undefined);
    assert.equal(await reopened.lookupDeliveryAttempt({...lookup,
      attemptId: 'missing'}), undefined);
    assert.deepEqual(
      await reopened.appendDeliveryRecord(wire(failed)),
      failed,
    );
  });

test('delivery record append and confirmation admit each unchanged original once', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-record-once-'));
  t.after(() => removeFixtureDirectory(directory));
  const admissions = new Map();
  const control = {...contractControl, admit(name, value, limits) {
    const admitted = contractControl.admit(name, value, limits);
    admissions.set(admitted.identity, (admissions.get(admitted.identity) ?? 0) + 1);
    return admitted;
  }};
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64}, control);
  const root = deliveryFixture(), attempt = deliveryAttempt(root, 'record-once');
  await store.createDeliveryAttempt(wire(attempt), wire(root.grant));
  const streaming = deliveryRecord(attempt, 0, 'streaming');
  admissions.clear();
  assert.deepEqual(await store.appendDeliveryRecord(wire(streaming)), streaming);
  assert.equal(admissions.get(streaming.delivery_record_cid), 1);
  assert.equal(admissions.get(attempt.delivery_attempt_cid), 1);
  const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 7, failure_cid: digest('record once failure'),
  });
  admissions.clear();
  assert.deepEqual(await store.appendDeliveryRecord(wire(failed)), failed);
  assert.equal(admissions.get(failed.delivery_record_cid), 1);
  assert.equal(admissions.get(streaming.delivery_record_cid), 1,
    'the distinct previous revision still requires its own admission');
  admissions.clear();
  assert.deepEqual(await store.appendDeliveryRecord(wire(failed)), failed);
  assert.equal(admissions.get(failed.delivery_record_cid), 1,
    'an exact same-operation retained wire reuses its admitted input');
  admissions.clear();
  assert.deepEqual(await store.confirmDeliveryRecord(wire(failed)), failed);
  assert.equal(admissions.get(failed.delivery_record_cid), 1,
    'a new confirmation admits its input once, not once per trusted read');
  admissions.clear();
  const foreign = {get contract() { throw new Error('foreign retained input'); }};
  const latest = await store.latestDeliveryRecordContract(attempt.delivery_attempt_cid, foreign);
  assert.equal(latest.identity, failed.delivery_record_cid);
  assert.equal(admissions.get(failed.delivery_record_cid), 1,
    'the public reader cannot accept a caller-supplied retained admission');
  const target = join(directory, 'deliveries', attempt.delivery_attempt_cid.slice(7), '1.json');
  await writeFile(target, JSON.stringify(failed, null, 2));
  admissions.clear();
  assert.deepEqual(await store.confirmDeliveryRecord(wire(failed)), failed);
  assert.equal(admissions.get(failed.delivery_record_cid), 2,
    'the distinct valid spelling is admitted once and its reread is reused');
  admissions.clear();
  assert.deepEqual(await store.appendDeliveryRecord(wire(failed)), failed);
  assert.equal(admissions.get(failed.delivery_record_cid), 2);
  const changed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 8, failure_cid: digest('record once failure'),
  });
  await writeFile(target, wire(changed));
  await assert.rejects(store.confirmDeliveryRecord(wire(failed)), code('DeliveryRecordConflict'));
});

test('delivery confirmation reuses its real immutable record ACK but reacquires each input', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-ack-reuse-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {directory, storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64};
  let selectedDirectory, syncs = 0, admissions = 0;
  const control = {...contractControl, admit(name, value, bounds) {
    if (name === 'delivery_record') admissions++;
    return contractControl.admit(name, value, bounds);
  }};
  const durability = {async syncDirectory(path) {
    const handle = await open(path, 'r');
    try { await handle.sync(); } finally { await handle.close(); }
    if (path === selectedDirectory) syncs++;
  }};
  const store = await openLocalPublicationStore(configuration, control, durability);
  const root = deliveryFixture(), attempt = deliveryAttempt(root, 'ack-reuse');
  await store.createDeliveryAttempt(wire(attempt), wire(root.grant));
  selectedDirectory = join(directory, 'deliveries', attempt.delivery_attempt_cid.slice(7));
  const streaming = deliveryRecord(attempt, 0, 'streaming');
  syncs = 0;
  await store.appendDeliveryRecord(wire(streaming));
  assert.equal(syncs, 1, 'a newly installed record requires its real directory ACK');
  syncs = admissions = 0;
  for (let operation = 0; operation < 3; operation++) {
    assert.deepEqual(await store.confirmDeliveryRecord(wire(streaming)), streaming);
  }
  assert.equal(syncs, 0, 'the same durable immutable record needs no repeated ACK');
  assert.equal(admissions, 3, 'each public confirmation still admits its own input');
  const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
    failure_cid: digest('ack reuse failure'),
  });
  await store.appendDeliveryRecord(wire(failed));
  assert.equal(syncs, 1, 'a distinct record cannot borrow the previous record ACK');
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, control, durability);
  syncs = admissions = 0;
  assert.deepEqual(await reopened.confirmDeliveryRecord(wire(failed)), failed);
  assert.equal(syncs, 1, 'a new Store has not confirmed this original directory');
  assert.deepEqual(await reopened.confirmDeliveryRecord(wire(failed)), failed);
  assert.equal(syncs, 1);
  assert.equal(admissions, 2);
  await writeFile(join(selectedDirectory, '1.json'), '{}');
  await assert.rejects(reopened.confirmDeliveryRecord(wire(failed)),
    code('InvalidPublicationContract'));
  assert.equal(syncs, 1, 'changed bytes refuse despite a prior real ACK');
});

test('delivery record confirmation refuses changed original bytes after its ACK', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-confirm-change-'));
  t.after(() => removeFixtureDirectory(directory));
  let replace;
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64}, contractControl, {
    async syncDirectory(path) {
      const handle = await open(path, 'r');
      try { await handle.sync(); } finally { await handle.close(); }
      if (replace !== undefined && path === replace.directory) {
        const original = replace;
        replace = undefined;
        await writeFile(original.path, original.wire);
      }
    },
  });
  const root = deliveryFixture(), attempt = deliveryAttempt(root, 'confirm-change');
  await store.createDeliveryAttempt(wire(attempt), wire(root.grant));
  const streaming = deliveryRecord(attempt, 0, 'streaming');
  await store.appendDeliveryRecord(wire(streaming));
  const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 7, failure_cid: digest('confirmation change'),
  });
  const changed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 8, failure_cid: digest('confirmation change'),
  });
  const records = join(directory, 'deliveries', attempt.delivery_attempt_cid.slice(7));
  replace = {directory: records, path: join(records, '1.json'), wire: wire(changed)};
  await assert.rejects(store.appendDeliveryRecord(wire(failed)),
    code('DeliveryRecordDurabilityMismatch'));
  assert.deepEqual(await store.latestDeliveryRecord(attempt.delivery_attempt_cid), changed);
});

test('delivery record durability retries the exact visible record', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-delivery-record-durability-',
  ));
  t.after(() => removeFixtureDirectory(directory));
  const deliveries = join(directory, 'deliveries');
  let failRecordSync = false;
  let recordSyncFailures = 0;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (failRecordSync && path.startsWith(`${deliveries}/`)) {
        failRecordSync = false;
        recordSyncFailures++;
        const error = new Error('injected delivery directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, contractControl, durability);
  t.after(async () => { await store.close(); });
  const root = deliveryFixture();
  const attempt = deliveryAttempt(root, 'delivery-durability-retry');
  await store.createDeliveryAttempt(wire(attempt), wire(root.grant));
  const streaming = deliveryRecord(attempt, 0, 'streaming');
  await store.appendDeliveryRecord(wire(streaming));
  const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 7,
    failure_cid: digest('delivery failure'),
  });
  failRecordSync = true;
  await assert.rejects(
    store.appendDeliveryRecord(wire(failed)),
    code('EIO'),
  );
  assert.equal(recordSyncFailures, 1);
  assert.deepEqual(
    await store.latestDeliveryRecord(attempt.delivery_attempt_cid),
    failed,
  );
  assert.deepEqual(
    await store.appendDeliveryRecord(wire(failed)),
    failed,
  );
  assert.deepEqual(
    await store.confirmDeliveryRecord(wire(failed)),
    failed,
  );
});

test('delivery grant use limit is durable and concurrent attempts are CAS',
  async t => {
    const {store, configuration} = await fixture(t);
    const root = deliveryFixture(1);
    const attempts = [
      deliveryAttempt(root, 'delivery-a'),
      deliveryAttempt(root, 'delivery-b'),
    ];
    const outcomes = await Promise.allSettled(attempts.map(attempt =>
      store.createDeliveryAttempt(wire(attempt), wire(root.grant))));
    assert.equal(
      outcomes.filter(outcome => outcome.status === 'fulfilled').length,
      1,
    );
    assert.equal(
      outcomes.filter(outcome => outcome.status === 'rejected' &&
        outcome.reason?.code === 'DeliveryGrantUseLimit').length,
      1,
    );
    const accepted = attempts[outcomes.findIndex(
      outcome => outcome.status === 'fulfilled',
    )];
    assert.equal((await store.createDeliveryAttempt(
      wire(accepted), wire(root.grant),
    )).created, false);
    await store.close();

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.createDeliveryAttempt(
      wire(deliveryAttempt(root, 'delivery-c')),
      wire(root.grant),
    ), code('DeliveryGrantUseLimit'));
  });

test('delivery admission reads no unrelated attempts and admits its selected original once',
  async t => {
    // Synthetic adapter fixtures, not retained public publication history.
    const {store, configuration} = await fixture(t);
    const root = deliveryFixture(2);
    const other = deliveryFixture(1);
    const retained = [
      deliveryAttempt(root, 'retained-same-grant'),
      deliveryAttempt(other, 'retained-other-grant'),
    ];
    await store.createDeliveryAttempt(wire(retained[0]), wire(root.grant));
    await store.createDeliveryAttempt(wire(retained[1]), wire(other.grant));
    await store.close();

    const admissions = new Map(retained.map(attempt =>
      [attempt.delivery_attempt_cid, 0]));
    const independentControl = createPublicationContractControlFixture();
    const suppliedControl = {
      ...independentControl,
      admit(name, suppliedWire, suppliedLimits) {
        const admitted = independentControl.admit(
          name, suppliedWire, suppliedLimits,
        );
        if (name === 'delivery_attempt' && admissions.has(admitted.identity)) {
          admissions.set(admitted.identity, admissions.get(admitted.identity) + 1);
        }
        return admitted;
      },
    };
    const reopened = await openLocalPublicationStore(configuration, suppliedControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual([...admissions.values()], [0, 0],
      'ready coverage does not re-admit history on ordinary reopen');
    for (const identity of admissions.keys()) admissions.set(identity, 0);
    const selected = deliveryAttempt(root, 'new-same-grant');
    assert.deepEqual(await reopened.createDeliveryAttempt(
      wire(selected), wire(root.grant),
    ), {attempt: selected, created: true});
    assert.deepEqual([...admissions.values()], [0, 0]);

    const lookup = {
      indexKey: {namespaceId: 'namespace-a',
        authorityScopeCid: cids.scope, runDefinitionCid: cids.run},
      principalId: 'principal-a', purpose: 'download',
      resultName: 'answer', attemptId: selected.attempt_id,
    };
    for (const identity of admissions.keys()) admissions.set(identity, 0);
    assert.deepEqual(await reopened.lookupDeliveryAttempt(lookup),
      {attempt: selected, record: undefined, hostReleaseReceipt: undefined});
    assert.deepEqual([...admissions.values()], [0, 0]);
    assert.equal(await reopened.lookupDeliveryAttempt({...lookup,
      principalId: 'different-principal'}), undefined);

    const replayBody = {...selected, requested_at: '2026-09-18T01:00:01.000Z'};
    delete replayBody.delivery_attempt_cid;
    const replay = seal('delivery_attempt', replayBody);
    admissions.set(selected.delivery_attempt_cid, 0);
    assert.deepEqual(await reopened.createDeliveryAttempt(
      wire(replay), wire(root.grant),
    ), {attempt: selected, created: false});
    // A differently born input is separate; the selected stored original is
    // admitted once, with no restored-identity hash or repeated wire reread.
    assert.equal(admissions.get(selected.delivery_attempt_cid), 1);
    admissions.delete(selected.delivery_attempt_cid);
    const conflicting = seal('delivery_attempt', {...replayBody,
      serialization_contract_cid: cids.policy});
    await assert.rejects(reopened.createDeliveryAttempt(
      wire(conflicting), wire(root.grant),
    ), code('DeliveryAttemptConflict'));

    for (const identity of admissions.keys()) admissions.set(identity, 0);
    await assert.rejects(reopened.createDeliveryAttempt(
      wire(deliveryAttempt(root, 'one-too-many')), wire(root.grant),
    ), code('DeliveryGrantUseLimit'));
    assert.deepEqual([...admissions.values()], [0, 0]);
  });

test('delivery admission retains corruption and metadata deletion refusals',
  async t => {
    // Synthetic adapter corruption and a durable same-Store retirement fence,
    // not public history or an issued delivery permission.
    const {store, directory} = await fixture(t);
    const root = deliveryFixture(1);
    const other = deliveryFixture(2);
    const retained = deliveryAttempt(root, 'valid-retained-attempt');
    const damaged = deliveryAttempt(other, 'unrelated-damaged-attempt');
    await store.createDeliveryAttempt(wire(retained), wire(root.grant));
    await store.createDeliveryAttempt(wire(damaged), wire(other.grant));
    await writeFile(join(directory, 'deliveries',
      damaged.delivery_attempt_cid.slice(7), 'attempt.json'),
    wire({...damaged, attempt_id: 'changed-without-updating-identity'}));
    assert.equal((await store.createDeliveryAttempt(
      wire(retained), wire(root.grant))).created, false);
    await assert.rejects(store.createDeliveryAttempt(
      wire(deliveryAttempt(root, 'over-limit')), wire(root.grant)), code('DeliveryGrantUseLimit'));
    const query = {
      indexKey: {namespaceId: 'namespace-a',
        authorityScopeCid: cids.scope, runDefinitionCid: cids.run},
      principalId: 'principal-a', purpose: 'download',
      resultName: 'answer', attemptId: retained.attempt_id,
    };
    assert.deepEqual((await store.lookupDeliveryAttempt(query)).attempt, retained);
    await assert.rejects(store.lookupDeliveryAttempt({...query,
      attemptId: damaged.attempt_id}), code('InvalidDeliveryAttempt'));

    const native=await openDeliveryAttemptIndex(join(directory,'delivery-attempts.sqlite3'),
      {create:false,maxEntries:100,maxWireBytes:limits.maxWireBytes});
    try {native.retireNativePublicationInventory(undefined,
      {metadata_key:digest('synthetic retired Run').slice(7),run_cid:cids.run});}
    finally{native.close();}
    for (const attempt of [retained, deliveryAttempt(root, 'after-retirement')]) {
      await assert.rejects(store.createDeliveryAttempt(
        wire(attempt), wire(root.grant),
      ), code('PublicationMetadataDeleted'));
    }
  });

test('ready delivery coverage opens and looks up without unrelated history reads', async t => {
  const {store, directory, configuration} = await fixture(t);
  const root = deliveryFixture(14);
  const attempts = Array.from({length: 12}, (_, index) => deliveryAttempt(root, `history-${index}`));
  for (const attempt of attempts) await store.createDeliveryAttempt(wire(attempt),wire(root.grant));
  await store.close();
  const originalOpen = fsPromises.open;
  const originalReaddir = fsPromises.readdir;
  const attemptReads = [];
  let deliveryEnumerations = 0;
  let grantAdmissions = 0, attemptAdmissions = 0;
  const supplied = {...contractControl, admit(name,...args) {
    if (name === 'delivery_attempt') attemptAdmissions++;
    if (name === 'result_read_grant') grantAdmissions++;
    return contractControl.admit(name,...args);
  }};
  fsPromises.open = async function(path,...args) {
    if (String(path).startsWith(join(directory,'deliveries') + sep) &&
        String(path).endsWith('/attempt.json')) attemptReads.push(String(path));
    return Reflect.apply(originalOpen,this,[path,...args]);
  };
  fsPromises.readdir = function(path,...args) {
    if (String(path) === join(directory,'deliveries')) deliveryEnumerations++;
    return Reflect.apply(originalReaddir,this,[path,...args]);
  };
  syncBuiltinESMExports();
  try {
    const reopened = await openLocalPublicationStore(configuration,supplied);
    assert.deepEqual(attemptReads,[]);
    assert.equal(deliveryEnumerations,0,'ready cold open does not enumerate historical delivery names');
    assert.equal(attemptAdmissions,0);
    assert.equal(grantAdmissions,0);
    const selected = attempts[7];
    const query = {indexKey:{namespaceId:'namespace-a',authorityScopeCid:cids.scope,
      runDefinitionCid:cids.run},principalId:'principal-a',purpose:'download',
      resultName:'answer',attemptId:selected.attempt_id};
    assert.deepEqual((await reopened.lookupDeliveryAttempt(query)).attempt,selected);
    assert.deepEqual(attemptReads,[join(directory,'deliveries',selected.delivery_attempt_cid.slice(7),'attempt.json')]);
    assert.equal(attemptAdmissions,1);
    assert.equal(grantAdmissions,1);
    attemptReads.length = 0;
    const newAttempt = deliveryAttempt(root,'new-after-history');
    await reopened.createDeliveryAttempt(wire(newAttempt),wire(root.grant));
    assert.deepEqual(attemptReads,[join(directory,'deliveries',newAttempt.delivery_attempt_cid.slice(7),'attempt.json')],
      'only the new target is checked; indexed grant usage does not inspect previous attempts');
    await reopened.close();
    assert.equal(deliveryEnumerations,0);
  } finally {
    fsPromises.open = originalOpen;
    fsPromises.readdir = originalReaddir;
    syncBuiltinESMExports();
  }
});

test('legacy delivery coverage migrates once and missing adopted database refuses', async t => {
  const {store,directory,configuration} = await fixture(t);
  const root = deliveryFixture(2), attempt = deliveryAttempt(root,'legacy-index');
  await store.createDeliveryAttempt(wire(attempt),wire(root.grant));
  await store.close();
  // This disposable fixture models the old on-disk layout, not a lost live DB.
  await unlink(join(directory,'delivery-attempts.sqlite3'));
  await unlink(join(directory,'delivery-attempts-index.json'));
  let attemptAdmissions = 0;
  const supplied = {...contractControl,admit(name,...args) {
    if (name === 'delivery_attempt') attemptAdmissions++;
    return contractControl.admit(name,...args);
  }};
  const migrated = await openLocalPublicationStore(configuration,supplied);
  assert.equal(attemptAdmissions,1);
  assert.deepEqual(JSON.parse(await readFile(join(directory,'delivery-attempts-index.json'),'utf8')),
    {version:1,phase:'ready'});
  await migrated.close();
  attemptAdmissions = 0;
  const reopened = await openLocalPublicationStore(configuration,supplied);
  assert.equal(attemptAdmissions,0);
  await reopened.close();
  await unlink(join(directory,'delivery-attempts.sqlite3'));
  await assert.rejects(openLocalPublicationStore(configuration,supplied),code('DeliveryAttemptIndexUnavailable'));
  assert.equal(attemptAdmissions,0, 'missing adopted coverage never silently rebuilds from history');
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});

test('legacy delivery building refuses a missing original grant without adopting empty coverage', async t => {
  const {store,directory,configuration}=await fixture(t);
  const root=deliveryFixture(2),attempt=deliveryAttempt(root,'missing-legacy-grant');
  await store.createDeliveryAttempt(wire(attempt),wire(root.grant));await store.close();
  // Dedicated old-layout fixture; no live or uncertain business state is reused.
  await unlink(join(directory,'delivery-attempts.sqlite3'));
  await unlink(join(directory,'delivery-attempts-index.json'));
  await unlink(join(directory,'contracts',root.grant.result_read_grant_cid.slice(7)+'.json'));
  await assert.rejects(openLocalPublicationStore(configuration,contractControl),code('PublicationContractMissing'));
  assert.deepEqual(JSON.parse(await readFile(join(directory,'delivery-attempts-index.json'),'utf8')),
    {version:1,phase:'building'});
  const native=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'),{readOnly:true});
  try{
    assert.deepEqual({...native.prepare('SELECT complete,entries FROM coverage WHERE id=1').get()},
      {complete:0,entries:0});
    assert.equal(native.prepare('SELECT count(*) AS n FROM grant_uses').get().n,0);
  }finally{native.close();}
  assert.equal(await readFile(join(directory,'deliveries',attempt.delivery_attempt_cid.slice(7),'attempt.json'),'utf8'),wire(attempt));
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});

test('pending delivery claim restores only its same originals and retains quota', async t => {
  const {store,directory,configuration} = await fixture(t);
  await store.close();
  let refuse = false;
  const selected = await openLocalPublicationStore(configuration,contractControl,{
    async syncDirectory(path) {
      if (refuse && path === join(directory,'deliveries')) {
        throw Object.assign(new Error('delivery directory ACK unavailable'),{code:'EIO'});
      }
      const fd = await open(path,'r');
      try { await fd.sync(); } finally { await fd.close(); }
    },
  });
  const root = deliveryFixture(1), attempt = deliveryAttempt(root,'pending-original');
  refuse = true;
  await assert.rejects(selected.createDeliveryAttempt(wire(attempt),wire(root.grant)),code('EIO'));
  await assert.rejects(selected.createDeliveryAttempt(wire(deliveryAttempt(root,'not-refunded')),
    wire(root.grant)),code('DeliveryGrantUseLimit'));
  await selected.close();
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.createDeliveryAttempt(wire(attempt),wire(root.grant)),
    {attempt,created:false});
  await assert.rejects(reopened.createDeliveryAttempt(wire(deliveryAttempt(root,'still-not-refunded')),
    wire(root.grant)),code('DeliveryGrantUseLimit'));
  assert.equal(reopened.status().objectCount,2);
  await reopened.close();
});

test('Store exclusion waits for its captured native delivery index close', async t => {
  const {store,directory,configuration} = await fixture(t);
  await store.close();
  const original = DatabaseSync.prototype.close;
  let refuse = true, acquired;
  DatabaseSync.prototype.close = function() {
    acquired = this;
    if (refuse) return false;
    return Reflect.apply(original,this,[]);
  };
  let reopened;
  try { reopened = await openLocalPublicationStore(configuration,contractControl); }
  finally { DatabaseSync.prototype.close = original; }
  t.after(async () => { refuse = false; await reopened.close(); });
  const before = await readFile(join(directory,'owner','owner.json'),'utf8');
  await assert.rejects(reopened.close(),code('DeliveryAttemptIndexCleanupPending'));
  assert.equal(acquired.isOpen,true);
  assert.equal(await readFile(join(directory,'owner','owner.json'),'utf8'),before);
  assert.equal(reopened.status().closed,false);
  refuse = false;
  assert.equal(await reopened.close(),true);
  assert.equal(acquired.isOpen,false);
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});

test('delivery index preserves an actual committed claim after its reply is lost', async t => {
  const {store,directory,configuration} = await fixture(t);
  await store.close();
  const originalExec = DatabaseSync.prototype.exec;
  let armed = false, lost = false;
  DatabaseSync.prototype.exec = function(sql) {
    const value = Reflect.apply(originalExec,this,[sql]);
    if (armed && !lost && sql === 'COMMIT') {
      lost = true;
      throw Object.assign(new Error('lost original COMMIT reply'),{code:'EIO'});
    }
    return value;
  };
  let selected;
  try { selected = await openLocalPublicationStore(configuration,contractControl); }
  finally { DatabaseSync.prototype.exec = originalExec; }
  t.after(async () => { await selected.close(); });
  const root = deliveryFixture(1), attempt = deliveryAttempt(root,'original-commit-unknown');
  armed = true;
  await assert.rejects(selected.createDeliveryAttempt(wire(attempt),wire(root.grant)),
    error => error.code === 'DeliveryAttemptIndexCommitOutcomeUnknown' && error.outcome === 'unknown');
  assert.equal(lost,true);
  assert.deepEqual(await readdir(join(directory,'deliveries')),[]);
  await assert.rejects(selected.createDeliveryAttempt(wire(attempt),wire(root.grant)),
    code('DeliveryAttemptIndexCommitOutcomeUnknown'));
  await selected.close();
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.createDeliveryAttempt(wire(attempt),wire(root.grant)),
    {attempt,created:false});
  await assert.rejects(reopened.createDeliveryAttempt(wire(deliveryAttempt(root,'replacement-after-unknown')),
    wire(root.grant)),code('DeliveryGrantUseLimit'));
  await reopened.close();
});

test('pending delivery directory FD keeps Store ownership until original close', async t => {
  const {store,directory,configuration} = await fixture(t);
  const originalOpen = fsPromises.open;
  let refuse = true, retained, acquisitions = 0;
  fsPromises.open = async function(path,...args) {
    const handle = await Reflect.apply(originalOpen,this,[path,...args]);
    if (String(path).startsWith(join(directory,'deliveries','.staging-'))) {
      acquisitions++;
      retained = handle;
      const close = handle.close;
      handle.close = function() { return refuse ? Promise.resolve(false) : Reflect.apply(close,this,[]); };
    }
    return handle;
  };
  syncBuiltinESMExports();
  const root = deliveryFixture(1), attempt = deliveryAttempt(root,'pending-stage-original');
  let failure;
  try {
    await assert.rejects(store.createDeliveryAttempt(wire(attempt),wire(root.grant)),
      error => { failure = error; return error.cleanupHandle?.status().pending === true; });
    const before = await readFile(join(directory,'owner','owner.json'),'utf8');
    await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
    assert.equal(await readFile(join(directory,'owner','owner.json'),'utf8'),before);
    assert.ok(retained.fd >= 0);
    refuse = false;
    assert.equal(await store.close(),true);
    assert.equal(retained.fd,-1);
    assert.equal(acquisitions,1,'close retries neither stage sync nor a replacement FD');
    assert.equal(failure.cleanupHandle.status().pending,false);
  } finally { refuse = false; fsPromises.open = originalOpen; syncBuiltinESMExports(); }
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  assert.deepEqual(await reopened.createDeliveryAttempt(wire(attempt),wire(root.grant)),
    {attempt,created:false});
  assert.equal((await readdir(join(directory,'deliveries'))).some(name => name.startsWith('.staging-')),false);
  await reopened.close();
});

test('legacy delivery migration refuses duplicate complete logical keys', async t => {
  const {store,directory,configuration} = await fixture(t);
  const root = deliveryFixture(2), first = deliveryAttempt(root,'duplicate-legacy-key');
  await store.createDeliveryAttempt(wire(first),wire(root.grant));
  await store.close();
  const body = {...first,requested_at:'2026-09-18T01:00:01.000Z'};
  delete body.delivery_attempt_cid;
  const second = seal('delivery_attempt',body);
  const secondPath = join(directory,'deliveries',second.delivery_attempt_cid.slice(7));
  // A disposable old-layout corruption fixture: two independently valid
  // originals are not permission to choose one by filesystem enumeration order.
  await mkdir(secondPath);
  await writeFile(join(secondPath,'attempt.json'),wire(second));
  await unlink(join(directory,'delivery-attempts-index.json'));
  await unlink(join(directory,'delivery-attempts.sqlite3'));
  await assert.rejects(openLocalPublicationStore(configuration,contractControl),
    code('AmbiguousDeliveryAttemptLookup'));
  assert.deepEqual(JSON.parse(await readFile(join(directory,'delivery-attempts-index.json'),'utf8')),
    {version:1,phase:'building'});
  assert.equal(await readFile(join(secondPath,'attempt.json'),'utf8'),wire(second));
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});

test('index opening cleanup retains native and failed metadata FD independently', async t => {
  const {store,directory,configuration} = await fixture(t);
  await store.close();
  const originalClose = DatabaseSync.prototype.close;
  let refuseNative = true, refuseReader = true, native;
  DatabaseSync.prototype.close = function() {
    native = this;
    if (refuseNative) return false;
    return Reflect.apply(originalClose,this,[]);
  };
  let reader;
  // Fail the ready-marker directory ACK after acquiring the actual native DB.
  await unlink(join(directory,'delivery-attempts-index.json'));
  await unlink(join(directory,'delivery-attempts.sqlite3'));
  let originalFailure;
  try {
    await assert.rejects(openLocalPublicationStore(configuration,contractControl,{
      async syncDirectory(path) {
        const fd = await open(path,'r');
        const close = fd.close;
        let ready = false;
        if (path === directory) {
          try { ready = JSON.parse(await readFile(join(directory,'delivery-attempts-index.json'),'utf8')).phase === 'ready'; }
          catch (error) { if (error.code !== 'ENOENT') throw error; }
        }
        if (ready) {
          // This existing directory-sync protocol supplies its own actual FD
          // cleanup carrier, not a synthetic acknowledgement.
          reader = fd;
          fd.close = function() { return refuseReader ? Promise.resolve(false) : Reflect.apply(close,this,[]); };
        }
        try { await fd.sync(); } finally {
          if (await fd.close() === false) {
            const status = () => Object.freeze({pending:fd.fd !== -1});
            const error = Object.assign(new Error('pending original directory close'),{code:'EIO'});
            error.cleanupHandle = Object.freeze({status,async retry() { await fd.close(); return status(); }});
            throw error;
          }
        }
      },
    }),error => { originalFailure = error; return error.cleanupHandle?.status().pending === true; });
    assert.ok(native?.isOpen);
    assert.ok(reader.fd >= 0);
    refuseNative = false;
    await assert.rejects(originalFailure.cleanupHandle.retry());
    assert.equal(native.isOpen,false,'native cleanup progresses independently of the failed FD');
    assert.equal(originalFailure.cleanupHandle.status().pending,true);
    assert.ok(reader.fd >= 0);
    refuseReader = false;
    assert.equal((await originalFailure.cleanupHandle.retry()).pending,false);
    assert.equal(reader.fd,-1);
    await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
  } finally {
    refuseNative = refuseReader = false;
    await originalFailure?.cleanupHandle.retry();
    DatabaseSync.prototype.close = originalClose;
  }
});

test('Manifest selection leaves unrelated committed history out of ordinary Store opening', async t => {
  const setup = await fixture(t), grants = [];
  for (let n = 0; n < 3; n++) {
    const grant = seal('manifest_read_grant', {...manifestReadGrant(3),
      manifest_read_grant_cid: undefined, principal_id: `history-${n}`});
    await setup.store.consumeManifestReadGrant(wire(grant), 'first');
    await setup.store.consumeManifestReadGrant(wire(grant), 'second');
    grants.push(grant);
  }
  await setup.store.close();
  const root = join(setup.directory, 'manifest-reads'), enumerations = [], stats = [];
  const originalReaddir = fsPromises.readdir, originalLstat = fsPromises.lstat;
  t.mock.method(fsPromises, 'readdir', function(path, ...args) {
    if (String(path) === root || String(path).startsWith(root + sep)) enumerations.push(String(path));
    return Reflect.apply(originalReaddir, this, [path, ...args]);
  });
  t.mock.method(fsPromises, 'lstat', function(path, ...args) {
    if (String(path).startsWith(root + sep)) stats.push(String(path));
    return Reflect.apply(originalLstat, this, [path, ...args]);
  });
  syncBuiltinESMExports(); t.after(() => {t.mock.restoreAll(); syncBuiltinESMExports();});
  const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
  assert.deepEqual({enumerations, stats}, {enumerations: [], stats: []});
  const selected = join(root, grants[1].manifest_read_grant_cid.slice(7));
  const staging = join(selected, '.staging-original-interrupted-use');
  await writeFile(staging, 'incomplete private metadata');
  assert.equal((await reopened.consumeManifestReadGrant(wire(grants[1]), 'third')).created, true);
  assert.deepEqual(enumerations, [selected]);
  assert(stats.length > 0 && stats.every(path => path === selected || path.startsWith(selected + sep)));
  await assert.rejects(stat(staging), code('ENOENT'));
  await assert.rejects(reopened.consumeManifestReadGrant(wire(grants[1]), 'fourth'), code('ManifestReadGrantUseLimit'));
});

test('Manifest selection requires its actual directory ACK after a lost use acknowledgement', async t => {
  const setup = await fixture(t); await setup.store.close();
  const grant = manifestReadGrant(1), directory = join(setup.directory, 'manifest-reads', grant.manifest_read_grant_cid.slice(7));
  const primary = Object.assign(new Error('lost selected Manifest directory ACK'), {code: 'InjectedManifestAck'});
  let refuse = true, attempts = 0;
  t.after(() => {refuse = false;});
  const store = await openLocalPublicationStore(setup.configuration, contractControl, {
    async syncDirectory(path) {
      if (path === directory) {attempts++; if (refuse) throw primary;}
      const handle = await open(path, 'r'); try {await handle.sync();} finally {await handle.close();}
    },
  });
  await assert.rejects(store.consumeManifestReadGrant(wire(grant), 'same'), error => error === primary);
  const target = join(directory, createHash('sha256').update('same').digest('hex') + '.json');
  const before = await stat(target), bytes = await readFile(target);
  await assert.rejects(store.consumeManifestReadGrant(wire(grant), 'same'), error => error === primary);
  assert.equal(attempts, 2, 'Visible same bytes are not a lost directory ACK');
  refuse = false;
  assert.equal((await store.consumeManifestReadGrant(wire(grant), 'same')).idempotent, true);
  assert.equal(attempts, 3);
  assert.deepEqual(await readFile(target), bytes);
  const after = await stat(target); assert.equal(after.dev, before.dev); assert.equal(after.ino, before.ino);
  assert.equal((await store.consumeManifestReadGrant(wire(grant), 'same')).idempotent, true);
  assert.equal(attempts, 3, 'This same Store retains only the actual successful ACK');
  await assert.rejects(store.consumeManifestReadGrant(wire(grant), 'different'), code('ManifestReadGrantUseLimit'));
});

test('Manifest selection retains the original failed directory FD close before Store retirement', async t => {
  let failure, directoryHandle, refuse = true, armed = false;
  t.after(async () => {
    armed = refuse = false;
    await failure?.cleanupHandle?.retry();
    if (directoryHandle?.fd >= 0) await directoryHandle.close();
  });
  const setup = await fixture(t), grant = manifestReadGrant(1);
  const directory = join(setup.directory, 'manifest-reads', grant.manifest_read_grant_cid.slice(7));
  const originalOpen = fsPromises.open;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (armed && String(path) === directory) {
      directoryHandle = handle; const close = handle.close;
      handle.close = function(...values) {
        assert.strictEqual(this, handle);
        return refuse ? false : Reflect.apply(close, this, values);
      };
    }
    return handle;
  });
  syncBuiltinESMExports(); t.after(() => {t.mock.restoreAll(); syncBuiltinESMExports();});
  armed = true;
  await assert.rejects(setup.store.consumeManifestReadGrant(wire(grant), 'same'), error => {
    failure = error; return error.cleanupHandle?.status().pending === true;
  });
  assert.ok(directoryHandle.fd >= 0);
  await assert.rejects(setup.store.close(), code('PublicationStoreCleanupPending'));
  assert.equal(setup.store.status().closed, false);
  refuse = false; armed = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(directoryHandle.fd, -1);
  assert.equal((await setup.store.consumeManifestReadGrant(wire(grant), 'same')).idempotent, true);
});

test('Manifest selected use reuses admission but still refuses changed target bytes', async t => {
  let admissions = 0;
  const control = {...contractControl, admit(name, ...args) {
    if (name === 'manifest_read_grant') admissions++;
    return Reflect.apply(contractControl.admit, contractControl, [name, ...args]);
  }};
  const setup = await fixture(t, {}, control), grant = manifestReadGrant(1);
  await setup.store.consumeManifestReadGrant(wire(grant), 'same');
  assert.equal(admissions, 1, 'One contract-control admission, not another admission for persistence');
  const target = join(setup.directory, 'manifest-reads', grant.manifest_read_grant_cid.slice(7),
    createHash('sha256').update('same').digest('hex') + '.json');
  await writeFile(target, JSON.stringify({manifestReadGrantCid: grant.manifest_read_grant_cid, attemptId: 'foreign'}));
  await assert.rejects(setup.store.consumeManifestReadGrant(wire(grant), 'same'), code('ManifestReadAttemptConflict'));
  assert.equal(admissions, 2, 'A new operation admits its actual input; the ACK observation is not authority');
});

test('Manifest grant use is durable idempotent and bounded across restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const grant = manifestReadGrant(1);
    assert.deepEqual(
      await store.consumeManifestReadGrant(wire(grant), 'manifest-read-a'),
      {grant, created: true, idempotent: false},
    );
    assert.deepEqual(
      await store.consumeManifestReadGrant(wire(grant), 'manifest-read-a'),
      {grant, created: false, idempotent: true},
    );
    await assert.rejects(
      store.consumeManifestReadGrant(wire(grant), 'manifest-read-b'),
      code('ManifestReadGrantUseLimit'),
    );
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal((await reopened.consumeManifestReadGrant(
      wire(grant), 'manifest-read-a',
    )).idempotent, true);
    await assert.rejects(
      reopened.consumeManifestReadGrant(wire(grant), 'manifest-read-c'),
      code('ManifestReadGrantUseLimit'),
    );
  });

test('unknown publication cannot become failed without confirmed non-commit',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', wire(request));
    await store.createAttempt(wire(attempt));
    const first = publicationRecord(attempt, 0, 'preparing');
    const second = publicationRecord(attempt, 1, 'committing', first);
    const unknown = publicationRecord(attempt, 2, 'publication_unknown', second);
    for (const record of [first, second, unknown]) {
      await store.appendRecord(wire(record), {uncommittedConfirmed: false});
    }
    const failed = publicationRecord(attempt, 3, 'failed', unknown, {
      failure_cid: digest('failure'),
    });
    await assert.rejects(store.appendRecord(
      wire(failed), {uncommittedConfirmed: false},
    ), code('InvalidPublicationRecordTransition'));
    await store.appendRecord(wire(failed), {uncommittedConfirmed: true});
  });

test('public index is invisible before commit and survives a lost response',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    assert.equal(await store.inspectCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const committed = await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(committed.committed, true);
    assert.equal(prepared.prepared.status().pending, false);
    // Simulate losing the response after the durable commit by closing without
    // appending the terminal attempt record, then reconcile after restart.
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectCommittedIndex(
      indexKeyFor(request),
    ), entry);
    const chunks = [];
    let authorizationChecks = 0;
    const consumed = await reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      authorization => {
        authorizationChecks++;
        return authorization.resultDefinitionCid ===
          request.inventory[0].result_definition_cid;
      },
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(authorizationChecks, 2);
    assert.equal(Buffer.concat(chunks).toString('utf8'),
      'fixture durable Result payload');
    assert.deepEqual(consumed, {
      durableResultBindingCid: prepared.binding.identity,
      logicalResultCid: cids.result,
      resultSchemaCid: cids.schema,
      resultSchemaWire,
      resultFields: ['answer'],
      rowCount: 1,
      bytes: Buffer.byteLength('fixture durable Result payload', 'utf8'),
    });
    const succeeded = publicationRecord(attempt, 2, 'succeeded',
      prepared.committing, {public_index_entry_cid: entry.public_index_entry_cid});
    await reopened.appendRecord(
      wire(succeeded), {uncommittedConfirmed: false},
    );
    assert.equal((await reopened.latestRecord(
      attempt.publication_attempt_cid,
    )).state, 'succeeded');
  });

test('durable commit adopts prepared schema without deleting shared bytes',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue, cids.policy, true,
    );
    const otherRun = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    assert.equal(prepared.schemaPrepared.status().pending, true);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const committed = await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(committed.committed, true);
    assert.equal(prepared.schemaPrepared.status().pending, false);
    assert.equal(otherRun.prepared.status().pending, true);
    assert.equal(await otherRun.prepared.release(), true);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    const before = store.status().storedBytes;
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, before);
    assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.deepEqual(await reopened.inspectCommittedIndex(
      indexKeyFor(request),
    ), entry);
  });

test('metadata retirement preserves a second Run prepared schema owner',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue, cids.policy, true,
    );
    const otherRun = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store, wire(entry), prepared.required,
      prepared.evidence);
    assert.equal(otherRun.prepared.status().pending, true);
    const result = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(result.cleanup.status().pending, false);
    const metadata = await store.retireCommittedPublicationMetadata(
      indexKeyFor(request), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(metadata.cleanup.status().pending, false);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    await otherRun.prepared.release();
    await assert.rejects(store.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('Result reader consumes its already parsed Binding once while retaining physical validation',async t=>{
  const {store,directory}=await fixture(t);
  const invocationValue=invocation(),request=publicationRequest(resultDefinition(),invocationValue.invocation_cid);
  const attempt=publicationAttempt(request),prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);
  const parse=JSON.parse;let bindingParses=0;
  t.mock.method(JSON,'parse',function(value,...rest){
    // Count only direct Store DATA interpretation, separately from the
    // actual contract-control admission and its own canonical validation.
    if(value===prepared.binding.wire&&/at parseContract \(file:.*publication-store\.mjs:/u.test(new Error().stack))bindingParses++;
    return Reflect.apply(parse,this,[value,...rest]);
  });
  for(let operation=0;operation<2;operation++) {
    bindingParses=0;
    const received=[];
    await store.consumeCommittedResult(indexKeyFor(request),request.inventory[0].result_definition_cid,
      ()=>true,chunk=>received.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(received).toString(),'fixture durable Result payload');
    assert.equal(bindingParses,1,'one selected original, not read + selection + verifier reparsing');
  }
  const binding=parse(prepared.binding.wire),path=join(directory,'objects',binding.material_generation_cid.slice(7));
  const changed=await readFile(path);changed[0]^=1;await writeFile(path,changed);
  await assert.rejects(store.consumeCommittedResult(indexKeyFor(request),binding.result_definition_cid,
    ()=>true,()=>assert.fail('changed physical bytes exposed')),code('PublicationObjectCorrupt'));
  assert.deepEqual(await readFile(path),changed,'no own-output reuse skips next-operation physical validation');
});

test('Result consumption retains its reader until the same failed FD close acknowledges',async t=>{
  const {store,directory}=await fixture(t);
  const invocationValue=invocation(),request=publicationRequest(resultDefinition(),invocationValue.invocation_cid);
  const attempt=publicationAttempt(request),prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);
  const binding=JSON.parse(prepared.binding.wire),path=join(directory,'objects',binding.material_generation_cid.slice(7));
  const actualOpen=fsPromises.open;
  let opens=0,streamCloseCalls=0,allowClose=false,failure;
  t.mock.method(fsPromises,'open',async function(file,...args){
    const handle=await Reflect.apply(actualOpen,this,[file,...args]);
    if(String(file)===path&&++opens===2) {
      // The first actual FD verifies the binding. This second original is
      // the consuming FD whose failed close must retain the Result reader.
      const close=handle.close;
      handle.close=function(...values){streamCloseCalls++;return allowClose?Reflect.apply(close,this,values):false;};
    }
    return handle;
  });
  syncBuiltinESMExports();
  try {
    await assert.rejects(store.consumeCommittedResult(indexKeyFor(request),binding.result_definition_cid,
      ()=>true,()=>{}),error=>{
      failure=error;return error.code==='PublicationStoreCleanupPending'&&error.cleanupHandle?.status().pending===true;
    });
    assert.equal(streamCloseCalls,1);assert.equal(opens,2);
    await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
    assert.equal(store.status().closed,false);
    assert.equal(failure.cleanupHandle.status().pending,true);
    allowClose=true;assert.equal((await failure.cleanupHandle.retry()).pending,false);
    assert.equal(streamCloseCalls,2);assert.equal(opens,2,'retry never reopens the generation');
    assert.equal(await store.close(),true);
  } finally {
    // Even the original red assertion must close its real consuming FD
    // before fixture directory teardown; this is test-owned cleanup only.
    allowClose=true;if(failure?.cleanupHandle?.status().pending)await failure.cleanupHandle.retry();
    t.mock.restoreAll();syncBuiltinESMExports();
  }
});

test('durable Result retirement blocks new reads and waits for active readers',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    let enterReader;
    const readerEntered = new Promise(resolve => { enterReader = resolve; });
    let finishReader;
    const readerFinished = new Promise(resolve => { finishReader = resolve; });
    const reading = store.withCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      async () => {
        enterReader();
        await readerFinished;
      },
    );
    await readerEntered;
    const retired = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retired.cleanup.status().pending, true);
    await assert.rejects(store.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result exposed bytes'),
    ), code('PublicationObjectMissing'));
    await assert.rejects(
      store.close(), code('PublicationStoreCleanupPending'),
    );
    finishReader();
    await reading;
    assert.deepEqual(await retired.cleanup.retry(), {
      pending: false,
      errors: [],
    });
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result survived restart'),
    ), code('PublicationObjectMissing'));
  });

test('clean Store reopening does not rescan settled Result deletion history', async t => {
  const {store, configuration, directory} = await fixture(t);
  const invoked = invocation();
  const request = publicationRequest(resultDefinition(), invoked.invocation_cid);
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(store, request, attempt, invoked);
  const entry = indexEntry(request, attempt, invoked, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  const retired = await store.retireCommittedResult(indexKeyFor(request),
    request.inventory[0].result_definition_cid);
  assert.equal(retired.deleted, true);
  await store.close();
  const deletionRoot = join(directory, 'deletions');
  let historyReads = 0, historyLists = 0;
  const originalOpen = fsPromises.open, originalReaddir = fsPromises.readdir;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    if (String(path).startsWith(deletionRoot + sep) &&
        String(path).endsWith('.json') && typeof args[0] === 'number') historyReads++;
    return Reflect.apply(originalOpen, this, [path, ...args]);
  });
  t.mock.method(fsPromises, 'readdir', async function(path, ...args) {
    if (String(path) === deletionRoot || String(path).startsWith(deletionRoot + sep)) historyLists++;
    return Reflect.apply(originalReaddir, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  try {
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    try {
      assert.equal(historyReads, 0, 'settled deletion bodies are selected-use data, not ordinary open work');
      assert.equal(historyLists, 0, 'clean opening does not enumerate completed Result retirements');
      await assert.rejects(reopened.consumeCommittedResult(indexKeyFor(request),
        request.inventory[0].result_definition_cid, () => true,
        () => assert.fail('retired Result exposed bytes')), code('PublicationObjectMissing'));
      assert(historyReads > 0, 'selected use still reads the actual deletion marker');
    } finally {await reopened.close();}
  } finally {t.mock.restoreAll(); syncBuiltinESMExports();}
});

for (const phase of ['begin', 'seal']) for (const afterCommit of [false, true]) {
test(`Result cleanup ${phase} ${afterCommit ? 'committed' : 'rolled-back'} lost COMMIT reply keeps the same Store duty`, async t => {
  let armed = false, lost = false;
  const originalExec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && !lost && sql === 'COMMIT') {
      lost = true; if (afterCommit) Reflect.apply(originalExec, this, [sql]);
      throw Object.assign(new Error('lost same Result cleanup commit reply'), {code: 'EIO'});
    }
    return Reflect.apply(originalExec, this, [sql]);
  });
  const {store, directory} = await fixture(t);
  const invoked = invocation(), request = publicationRequest(resultDefinition(), invoked.invocation_cid);
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invoked);
  const entry = indexEntry(request, attempt, invoked, {durable_result_binding_cids: [prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  if (phase === 'begin') armed = true;
  const retired = await store.retireCommittedResult(indexKeyFor(request), request.inventory[0].result_definition_cid);
  if (phase === 'begin') {
    assert.equal(lost, true);
    assert.equal(retired.deleted, false);
    assert.equal(retired.cleanup.status().pending, true);
    await assert.rejects(store.close(), code('PublicationStoreCleanupPending'));
    assert.equal((await retired.cleanup.retry()).pending, false,
      'same original cleanup confirms its native intent before writing the marker');
  } else {
    assert.equal(retired.deleted, true);
    armed = true;
    await assert.rejects(store.close(), error => error.outcome === 'unknown');
    assert.equal(lost, true);
  }
  assert.equal(store.status().closed, false, 'visible native state is not the original close ACK');
  assert((await stat(join(directory, 'owner'))).isDirectory());
  await store.close();
  assert.equal(store.status().closed, true);
});
}

test('Result cleanup seal shares physical quota COMMIT and keeps the original native close ACK separate', async t => {
  let armed = false, refuse = false, commits = 0, closes = 0;
  const exec = DatabaseSync.prototype.exec, close = DatabaseSync.prototype.close;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  t.mock.method(DatabaseSync.prototype, 'close', function() {
    if (armed) closes++;
    return refuse ? false : Reflect.apply(close, this, []);
  });
  const {store, directory} = await fixture(t);
  const invoked = invocation(), request = publicationRequest(resultDefinition(), invoked.invocation_cid);
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invoked);
  const entry = indexEntry(request, attempt, invoked, {durable_result_binding_cids: [prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  assert.equal((await store.retireCommittedResult(indexKeyFor(request), request.inventory[0].result_definition_cid)).deleted, true);
  armed = refuse = true;
  try {
    await assert.rejects(store.close(), code('DeliveryAttemptIndexCleanupPending'));
    assert.equal(commits, 1, 'Result seal and original physical-quota close share the real commit');
    assert.equal(store.status().closed, false);
    assert((await stat(join(directory, 'owner'))).isDirectory());
    refuse = false;
    await store.close();
    assert.equal(commits, 1, 'same original native close retry does not repeat the committed seal');
    assert.equal(closes, 2);
  } finally {refuse = false; armed = false; await store.close();}
});

test('a new process recovers only after an actual interrupted Result cleanup lifecycle', async t => {
  const {store, configuration, directory} = await fixture(t);
  const invoked = invocation(), request = publicationRequest(resultDefinition(), invoked.invocation_cid);
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invoked);
  const entry = indexEntry(request, attempt, invoked, {durable_result_binding_cids: [prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  await store.close();
  const child = await runStoreChild(`
    import assert from 'node:assert/strict';
    import {open} from 'node:fs/promises';
    import {join} from 'node:path';
    import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
    import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
    const configuration = ${JSON.stringify(configuration)};
    let armed = false;
    const store = await openLocalPublicationStore(configuration, createPublicationContractControlFixture(), {
      async syncDirectory(path) {
        if (armed && path === join(configuration.directory,'objects')) {
          throw Object.assign(new Error('interrupted actual object directory ACK'), {code:'EIO'});
        }
        const handle = await open(path,'r'); try {await handle.sync();} finally {await handle.close();}
      }
    });
    armed = true;
    const retired = await store.retireCommittedResult(${JSON.stringify(indexKeyFor(request))},
      ${JSON.stringify(request.inventory[0].result_definition_cid)});
    assert.equal(retired.cleanup.status().pending,true);
    process.stdout.write(JSON.stringify({pending:true}), () => process.exit(0));
  `);
  assert.equal(child.exitCode, 0, child.stderr);
  assert.deepEqual(JSON.parse(child.stdout), {pending: true});
  // Process exit is not a product ACK. The new Owner must recover the durable
  // intent and acknowledge the actual object directory, without old callbacks.
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  try {
    await assert.rejects(reopened.consumeCommittedResult(indexKeyFor(request),
      request.inventory[0].result_definition_cid, () => true, () => assert.fail('interrupted retirement resurrected Result')),
    code('PublicationObjectMissing'));
  } finally {await reopened.close();}
});

test('description evidence admits each selected immutable contract once per read',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-description-once-'));
    t.after(() => removeFixtureDirectory(directory));
    const admissions = new Map();
    const control = {...contractControl, admit(name, value, bounds) {
      const admitted = contractControl.admit(name, value, bounds);
      admissions.set(admitted.identity, (admissions.get(admitted.identity) ?? 0) + 1);
      return admitted;
    }};
    const store = await openLocalPublicationStore({directory,
      storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
      maxObjectBytes: 65536, maxObjects: 100,
      maxContractNodes: 4096, maxContractDepth: 64}, control);
    const invocationValue = invocation();
    const definition = resultDefinition();
    const request = publicationRequest(definition, invocationValue.invocation_cid);
    await store.putPublicationContract('result_definition', wire(definition));
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
    for (let operation = 0; operation < 2; operation++) {
      admissions.clear();
      const result = await store.readCommittedResultDescriptionEvidence(
        indexKeyFor(request), definition.result_definition_cid,
      );
      assert.equal(result.definition.identity, definition.result_definition_cid);
      assert.deepEqual(result.bindings.map(binding => binding.identity),
        [prepared.binding.identity]);
      assert.equal(admissions.get(entry.public_index_entry_cid), 1,
        'the selected Index is admitted once, including its contract alias');
      assert.equal(admissions.get(prepared.binding.identity), 1,
        'the selected Binding is reused by the retention lookup');
      assert.equal(admissions.get(definition.result_definition_cid), 1);
    }
    // A later operation must acquire and reject the changed target, not reuse
    // a successful description across public calls.
    const names = await readdir(join(directory, 'indexes'));
    assert.equal(names.length, 1);
    await writeFile(join(directory, 'indexes', names[0]), '{}');
    await assert.rejects(store.readCommittedResultDescriptionEvidence(
      indexKeyFor(request), definition.result_definition_cid,
    ), code('InvalidPublicationContract'));
  });

async function selectedMetadataFixture(t, label) {
  const admissions = new Map();
  const control = {...contractControl, admit(name, body, bounds) {
    const original = contractControl.admit(name, body, bounds);
    admissions.set(original.identity, (admissions.get(original.identity) ?? 0) + 1);
    return original;
  }};
  const setup = await fixture(t, {}, control);
  const invocationValue = invocation();
  const definition = resultDefinition();
  const request = publicationRequest(definition, digest(label));
  await setup.store.putPublicationContract('result_definition', wire(definition));
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(setup.store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await commitFixtureIndex(setup.store, wire(entry), prepared.required, prepared.evidence);
  admissions.clear();
  return {...setup, admissions, entry, key: indexKeyFor(request), definitionCid: definition.result_definition_cid};
}

for (const kind of ['description', 'retention']) {
  test(`selected ${kind} metadata consumes its own publication observation without another Index acquisition`, async t => {
    const setup = await selectedMetadataFixture(t, `selected ${kind} observation`);
    const {store, key, definitionCid, entry, admissions, directory} = setup;
    const method = kind === 'description' ? 'readCommittedResultDescriptionEvidence'
      : 'readCommittedResultRetentionExtension';
    const originalOpen = fsPromises.open;
    let indexReads = 0;
    fsPromises.open = async (...args) => {
      if (typeof args[0] === 'string' && args[0].startsWith(join(directory, 'indexes') + sep)) indexReads++;
      return originalOpen(...args);
    };
    syncBuiltinESMExports();
    try {
      const selected = await store.readCommittedPublication(key);
      const answer = await store[method](key, definitionCid, selected);
      if (kind === 'description') assert.equal(answer.definition.identity, definitionCid);
      else assert.equal(answer, undefined);
      assert.equal(indexReads, 1, 'A trusted nested metadata lookup consumes the already acquired original');
      assert.equal(admissions.get(entry.public_index_entry_cid), 1);
      await assert.rejects(store[method](key, definitionCid, selected), code('PublicationLookupDenied'),
        'The operation-local observation cannot become a reusable public read cache');
      assert.equal(indexReads, 1, 'An already consumed original refuses before another acquisition');
      const fresh = await store.readCommittedPublication(key);
      assert.notStrictEqual(fresh, selected);
      await store[method](key, definitionCid, fresh);
      assert.equal(indexReads, 2, 'A later operation acquires its own selected Index');
      const [name] = await readdir(join(directory, 'indexes'));
      await writeFile(join(directory, 'indexes', name), '{}');
      await assert.rejects(store.readCommittedPublication(key), code('InvalidPublicationContract'));
    } finally {
      fsPromises.open = originalOpen; syncBuiltinESMExports();
    }
  });
}

test('selected metadata refuses copied foreign and wrong-Run observations without treating them as omitted', async t => {
  const left = await selectedMetadataFixture(t, 'left selected observation');
  const right = await selectedMetadataFixture(t, 'right selected observation');
  const selected = await left.store.readCommittedPublication(left.key);
  const foreign = await right.store.readCommittedPublication(right.key);
  for (const original of [null, {...selected}, foreign]) {
    await assert.rejects(left.store.readCommittedResultDescriptionEvidence(
      left.key, left.definitionCid, original), code('PublicationLookupDenied'));
  }
  await assert.rejects(left.store.readCommittedResultDescriptionEvidence(
    {...left.key, runDefinitionCid: digest('wrong selected Run')}, left.definitionCid, selected),
  code('PublicationLookupDenied'));
  assert.equal((await left.store.readCommittedResultDescriptionEvidence(
    left.key, left.definitionCid, selected)).definition.identity, left.definitionCid);
  assert.equal((await left.store.readCommittedResultDescriptionEvidence(
    left.key, left.definitionCid)).definition.identity, left.definitionCid,
  'The omitted legacy path retains its independent acquisition');
});

test('same-Store metadata retirement invalidates an unused selected publication observation', async t => {
  const {store, key, definitionCid} = await selectedMetadataFixture(t, 'retired selected observation');
  const selected = await store.readCommittedPublication(key);
  const retired = await store.retireCommittedPublicationMetadata(key, '2026-09-18T04:00:00.000Z');
  assert.equal(retired.cleanup.status().pending, false);
  await assert.rejects(store.readCommittedResultDescriptionEvidence(
    key, definitionCid, selected), code('PublicationLookupDenied'));
});

test('description evidence survives payload deletion and restart, not metadata deletion',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
    await store.putPublicationContract('result_definition', wire(resultDefinition()));
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
    const key = indexKeyFor(request);
    const definitionCid = request.inventory[0].result_definition_cid;
    const before = await store.readCommittedResultDescriptionEvidence(key, definitionCid);
    assert.equal(before.schemaWire, resultSchemaWire);
    assert.equal(before.definition.identity, definitionCid);
    assert.deepEqual(before.bindings.map(value => value.identity), [prepared.binding.identity]);
    const retired = await store.retireCommittedResult(key, definitionCid);
    assert.equal(retired.cleanup.status().pending, false);
    assert.deepEqual(await store.readCommittedResultDescriptionEvidence(key, definitionCid), before);
    await store.close();
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.readCommittedResultDescriptionEvidence(key, definitionCid), before);
    await assert.rejects(reopened.consumeCommittedResult(key, definitionCid,
      () => true, () => assert.fail('deleted payload was reopened')),
    code('PublicationObjectMissing'));
    await reopened.retireCommittedPublicationMetadata(key, '2026-09-18T04:00:00.000Z');
    await assert.rejects(reopened.readCommittedResultDescriptionEvidence(key, definitionCid),
      code('PublicationLookupDenied'));
  });

test('cold index confirmation reuses unchanged admission and checks post-ACK mutation',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(resultDefinition(), invocationValue.invocation_cid);
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
    await store.close();
    let admissions = 0, indexSyncs = 0, replace = false;
    const control = {...contractControl, admit(name, value, bounds) {
      const admitted = contractControl.admit(name, value, bounds);
      if (admitted.identity === entry.public_index_entry_cid) admissions++;
      return admitted;
    }};
    const indexes = join(configuration.directory, 'indexes');
    const [name] = await readdir(indexes);
    const durability = {async syncDirectory(path) {
      const handle = await open(path, 'r');
      try { await handle.sync(); } finally { await handle.close(); }
      if (path === indexes) {
        indexSyncs++;
        if (replace) await writeFile(join(indexes, name), '{}');
      }
    }};
    const reopened = await openLocalPublicationStore(configuration, control, durability);
    admissions = indexSyncs = 0;
    assert.deepEqual(await reopened.confirmCommittedIndex(indexKeyFor(request)), entry);
    assert.equal(admissions, 1);
    assert.equal(indexSyncs, 1, 'cold confirmation still requires a real directory ACK');
    admissions = indexSyncs = 0;
    assert.deepEqual(await reopened.confirmCommittedIndex(indexKeyFor(request)), entry);
    assert.equal(admissions, 1, 'a later public call admits its own acquired original');
    assert.equal(indexSyncs, 0, 'an already confirmed immutable entry needs no new ACK');
    await reopened.close();
    const changed = await openLocalPublicationStore(configuration, control, durability);
    replace = true;
    await assert.rejects(changed.confirmCommittedIndex(indexKeyFor(request)),
      code('InvalidPublicationContract'));
    await changed.close();
  });

test('metadata retirement hides the Run and reclaims its durable chain',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    // Independently admitted semantic fixtures and the real same-Store native
    // index exercise retirement; this is not a nominal delivery permission or
    // a full Host/Common execution fixture.
    const delivery=deliveryFixture(1);
    const {result_read_grant_cid:oldGrant,...grantBody}=delivery.grant;
    delivery.grant=seal('result_read_grant',{...grantBody,run_definition_cid:request.run_definition_cid});
    const {delivery_attempt_cid:oldAttempt,...attemptBody}=deliveryAttempt(delivery,'native-retirement');
    const started=seal('delivery_attempt',{...attemptBody,run_definition_cid:request.run_definition_cid});
    const initial=deliveryRecord(started,0,'streaming',undefined);
    const native=await openDeliveryAttemptIndex(join(configuration.directory,'delivery-attempts.sqlite3'),
      {create:false,maxEntries:configuration.maxObjects,maxWireBytes:configuration.maxObjectBytes});
    try {native.claim({logical_key:JSON.stringify(['namespace-a',cids.scope,request.run_definition_cid,
      'principal-a','download','answer','native-retirement']),
    attempt_cid:started.delivery_attempt_cid,grant_cid:delivery.grant.result_read_grant_cid,
    run_cid:request.run_definition_cid,attempt_wire:wire(started),grant_wire:wire(delivery.grant)},1,
    wire(initial),initial.delivery_record_cid);} finally {native.close();}
    assert.equal((await store.latestDeliveryRecord(started.delivery_attempt_cid)).state,'streaming');
    assert.deepEqual(await readdir(join(configuration.directory,'deliveries')),[]);
    const retiredResult = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retiredResult.cleanup.status().pending, false);
    const retiredMetadata = await store.retireCommittedPublicationMetadata(
      indexKeyFor(request), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(retiredMetadata.cleanup.status().pending, false);
    for(const [cid,name] of [[started.delivery_attempt_cid,'delivery_attempt'],
      [delivery.grant.result_read_grant_cid,'result_read_grant'],[initial.delivery_record_cid,'delivery_record']]) {
      await assert.rejects(store.readPublicationContract(cid,name),code('PublicationContractMissing'));
    }
    const retiredDatabase=new DatabaseSync(join(configuration.directory,'delivery-attempts.sqlite3'),{readOnly:true});
    try {
      assert.equal(retiredDatabase.prepare('SELECT count(*) AS n FROM attempts WHERE run_cid=?').get(request.run_definition_cid).n,0);
      assert.equal(retiredDatabase.prepare('SELECT count(*) AS n FROM initial_records').get().n,0);
    } finally {retiredDatabase.close();}
    const deletionNames = await readdir(join(
      configuration.directory, 'metadata-deletions',
    ));
    assert.deepEqual(deletionNames, []);
    const fences=new DatabaseSync(join(configuration.directory,'delivery-attempts.sqlite3'),{readOnly:true});
    try{assert.deepEqual({...fences.prepare('SELECT run_cid,retired FROM metadata_deletion_fences').get()},
      {run_cid:request.run_definition_cid,retired:1});}finally{fences.close();}
    assert.equal(await store.inspectCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ), code('PublicationContractMissing'));
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(await reopened.confirmCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(reopened.createAttempt(wire(
      publicationAttempt(request, 'after-metadata-deletion'),
    )), code('PublicationMetadataDeleted'));
  });

test('metadata retirement retains capacity until durability retry', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-metadata-retry-',
  ));
  t.after(() => removeFixtureDirectory(directory));
  const objects = join(directory, 'objects');
  let objectSyncFailures = 0;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === objects && objectSyncFailures > 0) {
        objectSyncFailures--;
        const error = new Error('injected object directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  const store = await openLocalPublicationStore(
    configuration, contractControl, durability,
  );
  t.after(async () => { await store.close(); });
  const invocationValue = invocation();
  const request = publicationRequest(
    resultDefinition(), invocationValue.invocation_cid,
  );
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(
    store, request, attempt, invocationValue,
  );
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await commitFixtureIndex(store,
    wire(entry), prepared.required, prepared.evidence,
  );
  const chargedBefore = store.status().storedBytes;
  objectSyncFailures = 2;
  const retired = await store.retireCommittedPublicationMetadata(
    indexKeyFor(request), '2026-09-18T04:00:00.000Z',
  );
  assert.equal(retired.cleanup.status().pending, true);
  assert.equal(retired.cleanup.status().errors[0].code, 'EIO');
  assert.equal(store.status().storedBytes, chargedBefore);
  const pendingMarker = JSON.parse(await readFile(join(
    directory,
    'metadata-deletions',
    (await readdir(join(directory, 'metadata-deletions')))[0],
  ), 'utf8'));
  assert.equal(
    pendingMarker.version,
    'actql-local-publication-metadata-deletion/0.1',
  );
  assert.equal(await store.inspectCommittedIndex(
    indexKeyFor(request),
  ), undefined);
  await assert.rejects(
    store.close(), code('PublicationStoreCleanupPending'),
  );
  const retried = await retired.cleanup.retry();
  assert.equal(retried.pending, false);
  assert.equal(retried.errors.length, 1);
  assert.equal(store.status().storedBytes, 0);
  assert.equal(store.status().objectCount, 0);
  assert.deepEqual(await readdir(join(directory,'metadata-deletions')),[]);
  const fences=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'),{readOnly:true});
  try{assert.deepEqual({...fences.prepare('SELECT run_cid,retired FROM metadata_deletion_fences').get()},
    {run_cid:request.run_definition_cid,retired:1});}finally{fences.close();}
  assert.equal(await store.close(), true);
});

test('restart resumes metadata retirement after an interrupted unlink',
  async t => {
    const {store, configuration, directory} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    await store.close();

    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const child = await runStoreChild(`
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const directory = ${JSON.stringify(directory)};
      let armed = false;
      const durability = Object.freeze({async syncDirectory(path) {
        const handle = await open(path, 'r');
        try { await handle.sync(); } finally { await handle.close(); }
        if (armed && path === join(directory, 'objects')) process.exit(73);
      }});
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
        durability,
      );
      armed = true;
      await store.retireCommittedPublicationMetadata(
        ${JSON.stringify(indexKeyFor(request))},
        '2026-09-18T04:00:00.000Z',
      );
    `);
    assert.equal(child.exitCode, 73, child.stderr);
    assert.equal(child.signal, null);

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(await reopened.confirmCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(reopened.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ), code('PublicationContractMissing'));
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

test('metadata retirement preserves allocations shared by another Run',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const firstRequest = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const secondRequest = publicationRequest(
      resultDefinition(), digest('second Run'),
    );
    const firstAttempt = publicationAttempt(firstRequest, 'first-attempt');
    const secondAttempt = publicationAttempt(secondRequest, 'second-attempt');
    const first = await prepareCommit(
      store, firstRequest, firstAttempt, invocationValue,
    );
    const second = await prepareCommit(
      store, secondRequest, secondAttempt, invocationValue,
    );
    const firstEntry = indexEntry(
      firstRequest, firstAttempt, invocationValue,
      {durable_result_binding_cids: [first.binding.identity]},
    );
    const secondEntry = indexEntry(
      secondRequest, secondAttempt, invocationValue,
      {durable_result_binding_cids: [second.binding.identity]},
    );
    await commitFixtureIndex(store,
      wire(firstEntry), first.required, first.evidence,
    );
    await commitFixtureIndex(store,
      wire(secondEntry), second.required, second.evidence,
    );
    const retired = await store.retireCommittedPublicationMetadata(
      indexKeyFor(firstRequest), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(retired.cleanup.status().pending, false);
    assert.equal((await store.readPublicationContract(
      invocationValue.invocation_cid, 'run_invocation',
    )).identity, invocationValue.invocation_cid);
    const chunks = [];
    await store.consumeCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
      () => true,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(
      Buffer.concat(chunks).toString('utf8'),
      'fixture durable Result payload',
    );
  });

async function selectedRetentionFixture(setup, label) {
  const {store,directory}=setup;
  const base=seal('result_retention_policy',{
    version:'actql-result-retention-policy/0.1',retention_contract_cid:digest('retention-contract'),
    effective_data_policy_cid:digest('data-policy'),available_until:'2026-09-18T01:00:00.000Z',
    delete_by:'2026-09-18T03:00:00.000Z',extension_ceiling_at:'2026-09-18T02:30:00.000Z',
    metadata_retention_policy_cid:digest('metadata-retention'),metadata_delete_by:'2026-09-18T04:00:00.000Z',
    clock_contract_cid:digest('clock-contract'),
  });
  const extension=seal('result_retention_policy',{...base,available_until:'2026-09-18T02:00:00.000Z',
    effective_retention_policy_cid:undefined});
  await store.putPublicationContract('result_retention_policy',wire(base));
  const invocationValue=invocation(),request=publicationRequest(resultDefinition(),digest(label));
  const attempt=publicationAttempt(request,label),prepared=await prepareCommit(store,request,attempt,invocationValue,base.effective_retention_policy_cid);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);
  const resultCid=request.inventory[0].result_definition_cid,key=indexKeyFor(request);
  await store.putCommittedResultRetentionExtension(key,resultCid,undefined,
    contractControl.admit('result_retention_policy',wire(extension),limits),'2026-09-18T00:30:00.000Z');
  const root=join(directory,'retention-extensions');
  for(const parent of await readdir(root)) {
    const path=join(root,parent,resultCid.slice(7));
    try {
      if(JSON.parse(await readFile(join(path,'0.json'),'utf8')).public_index_entry_cid===entry.public_index_entry_cid) {
        return{key,resultCid,entry,extension,path};
      }
    } catch(error) {if(error.code!=='ENOENT')throw error;}
  }
  throw new Error('MissingSelectedRetentionFixture');
}

test('selected retention opening performs no committed extension history walk',async t=>{
  const setup=await fixture(t),first=await selectedRetentionFixture(setup,'first selected retention');
  await selectedRetentionFixture(setup,'unrelated selected retention');
  await setup.store.close();
  const root=join(setup.directory,'retention-extensions'),enumerations=[],acks=[];
  const original=fsPromises.readdir;
  t.mock.method(fsPromises,'readdir',function(path,...args){
    if(String(path)===root||String(path).startsWith(root+sep))enumerations.push(String(path));
    return Reflect.apply(original,this,[path,...args]);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl,{
    async syncDirectory(path){acks.push(path);const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}},
  });
  assert.deepEqual(enumerations,[],'ordinary open does not enumerate even valid unrelated extension histories');
  assert.deepEqual(acks.filter(path=>path.startsWith(root+sep)),[],
    'ordinary open does not acknowledge every historical Result directory');
  enumerations.length=acks.length=0;
  const selected=await reopened.readCommittedResultRetentionExtension(first.key,first.resultCid);
  assert.equal(selected.extension.identity,first.extension.effective_retention_policy_cid);
  assert.deepEqual(enumerations,[first.path]);
  assert.deepEqual(acks.filter(path=>path.startsWith(root+sep)),[first.path],
    'the selected original still receives its actual containing-directory ACK');
  await reopened.close();
});

test('selected retention keeps malformed unrelated history deferred and refuses selected corruption',async t=>{
  const setup=await fixture(t),healthy=await selectedRetentionFixture(setup,'healthy retained Result');
  const damaged=await selectedRetentionFixture(setup,'damaged retained Result');
  await setup.store.close();
  const foreign=join(damaged.path,'foreign.txt');await writeFile(foreign,'unrelated malformed history');
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.equal((await reopened.readCommittedResultRetentionExtension(healthy.key,healthy.resultCid))
    .extension.identity,healthy.extension.effective_retention_policy_cid);
  await assert.rejects(reopened.readCommittedResultRetentionExtension(damaged.key,damaged.resultCid),
    code('InvalidPublicationRetentionExtensionStore'));
  assert.equal(await readFile(foreign,'utf8'),'unrelated malformed history');
  await reopened.close();
});

for(const level of ['Run','Result']) {
test(`selected retention refuses a symlink at its ${level} directory`,async t=>{
  const setup=await fixture(t),selected=await selectedRetentionFixture(setup,`symlink retention ${level}`);
  await setup.store.close();
  const target=level==='Run'?resolve(selected.path,'..'):selected.path;
  const original=target+'.fixture-original';
  await fsPromises.rename(target,original);await fsPromises.symlink(original,target);
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  await assert.rejects(reopened.readCommittedResultRetentionExtension(selected.key,selected.resultCid),
    code('InvalidPublicationRetentionExtensionStore'));
  assert.equal((await fsPromises.lstat(target)).isSymbolicLink(),true);
  await reopened.close();
});
}

test('selected retention refuses a failed target ACK without changing or adopting the record',async t=>{
  const setup=await fixture(t),selected=await selectedRetentionFixture(setup,'selected retention ACK failure');
  await setup.store.close();
  const bytes=await readFile(join(selected.path,'0.json'));
  let failSelected=true,attempts=0;
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl,{
    async syncDirectory(path){
      if(path===selected.path){attempts++;if(failSelected)throw Object.assign(new Error('selected extension ACK failed'),{code:'EIO'});}
      const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
    },
  });
  await assert.rejects(reopened.readCommittedResultRetentionExtension(selected.key,selected.resultCid),code('EIO'));
  assert.deepEqual(await readFile(join(selected.path,'0.json')),bytes);
  failSelected=false;
  assert.equal((await reopened.readCommittedResultRetentionExtension(selected.key,selected.resultCid))
    .extension.identity,selected.extension.effective_retention_policy_cid);
  assert.equal(attempts,2,'the failed ACK is not a successful durability observation');
  await reopened.close();
});

test('Result retention extensions are append-only CAS records across restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const base = seal('result_retention_policy', {
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: digest('retention-contract'),
      effective_data_policy_cid: digest('data-policy'),
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T03:00:00.000Z',
      extension_ceiling_at: '2026-09-18T02:30:00.000Z',
      metadata_retention_policy_cid: digest('metadata-retention'),
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
      clock_contract_cid: digest('clock-contract'),
    });
    const first = seal('result_retention_policy', {
      ...base,
      available_until: '2026-09-18T02:00:00.000Z',
      effective_retention_policy_cid: undefined,
    });
    const second = seal('result_retention_policy', {
      ...base,
      available_until: '2026-09-18T02:15:00.000Z',
      effective_retention_policy_cid: undefined,
    });
    await store.putPublicationContract(
      'result_retention_policy', wire(base),
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store,
      request,
      attempt,
      invocationValue,
      base.effective_retention_policy_cid,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    const resultCid = request.inventory[0].result_definition_cid;
    assert.equal(await store.readCommittedResultRetentionExtension(
      indexKeyFor(request), resultCid,
    ), undefined);
    const installed = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      undefined,
      contractControl.admit('result_retention_policy', wire(first), limits),
      '2026-09-18T00:30:00.000Z',
    );
    assert.equal(installed.idempotent, false);
    assert.equal(installed.record.sequence, 0);
    const idempotent = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      first.effective_retention_policy_cid,
      contractControl.admit('result_retention_policy', wire(first), limits),
      '2026-09-18T00:30:00.000Z',
    );
    assert.equal(idempotent.idempotent, true);
    await assert.rejects(store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      undefined,
      contractControl.admit('result_retention_policy', wire(second), limits),
      '2026-09-18T00:45:00.000Z',
    ), code('PublicationRetentionExtensionConflict'));
    const advanced = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      first.effective_retention_policy_cid,
      contractControl.admit('result_retention_policy', wire(second), limits),
      '2026-09-18T00:45:00.000Z',
    );
    assert.equal(advanced.record.sequence, 1);
    assert.equal(advanced.record.prior_extension_policy_cid,
      first.effective_retention_policy_cid);
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    const recovered = await reopened.readCommittedResultRetentionExtension(
      indexKeyFor(request), resultCid,
    );
    assert.equal(recovered.record.sequence, 1);
    assert.equal(recovered.extension.identity,
      second.effective_retention_policy_cid);
  });

test('Result retirement retains capacity until object durability retry',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-retirement-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let objectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'objects') && objectSyncFailures > 0) {
          objectSyncFailures--;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    const before = store.status().storedBytes;
    objectSyncFailures = 1;
    const retired = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retired.cleanup.status().pending, true);
    assert.equal(store.status().storedBytes, before);
    const replacementPayload = Buffer.from(
      'fixture durable Result payload', 'utf8',
    );
    const replacement = store.createPreparedObjectWriter(
      replacementPayload.byteLength,
    );
    await replacement.append(replacementPayload);
    await assert.rejects(
      replacement.seal(digest(replacementPayload)),
      code('PublicationObjectReclamationPending'),
    );
    assert.equal(store.status().reservedBytes, 0);
    const recovered = await retired.cleanup.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.errors.length, 1);
    assert.equal(
      store.status().storedBytes,
      before - Buffer.byteLength('fixture durable Result payload', 'utf8'),
    );
  });

test('restart reconciles a retired Result after unlink response is lost',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-retirement-restart-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const store = await openLocalPublicationStore(
      configuration, contractControl,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    await store.close();
    const child = await runStoreChild(`
      import assert from 'node:assert/strict';
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
      import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
      const configuration = ${JSON.stringify(configuration)};
      const control = createPublicationContractControlFixture();
      let objectSyncFailures = 0;
      const store = await openLocalPublicationStore(configuration, control, {
        async syncDirectory(path) {
          if (path === join(configuration.directory, 'objects') && objectSyncFailures > 0) {
            objectSyncFailures--;
            throw Object.assign(new Error('lost object directory sync response'), {code: 'EIO'});
          }
          const handle = await open(path, 'r');
          try { await handle.sync(); } finally { await handle.close(); }
        },
      });
      const before = store.status().storedBytes;
      objectSyncFailures = 1;
      const retired = await store.retireCommittedResult(${JSON.stringify(indexKeyFor(request))},
        ${JSON.stringify(request.inventory[0].result_definition_cid)});
      assert.equal(retired.cleanup.status().pending, true);
      assert.equal(store.status().storedBytes, before, 'lost ACK keeps original capacity');
      await assert.rejects(openLocalPublicationStore(configuration, control),
        {code: 'PublicationStoreBusy'});
      // Actual process death ends this native lease without product cleanup.
      process.exit(77);
    `);
    assert.equal(child.exitCode, 77, child.stderr);
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    const recovered = await reopened.recoverRetiredResults();
    assert.equal(recovered.length, 1);
    assert.equal(recovered[0].cleanup.status().pending, false);
    await assert.rejects(reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result reappeared after restart'),
    ), code('PublicationObjectMissing'));
  });

test('Result retirement preserves a physical allocation held by another Run',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const firstRequest = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const secondRequest = publicationRequest(
      resultDefinition('other'), digest('second Run Definition'),
    );
    const commits = [];
    for (const [request, attemptId] of [
      [firstRequest, 'shared-attempt-a'],
      [secondRequest, 'shared-attempt-b'],
    ]) {
      const attempt = publicationAttempt(request, attemptId);
      const prepared = await prepareCommit(
        store, request, attempt, invocationValue,
      );
      const entry = indexEntry(request, attempt, invocationValue, {
        durable_result_binding_cids: [prepared.binding.identity],
      });
      await commitFixtureIndex(store,
        wire(entry), prepared.required, prepared.evidence,
      );
      commits.push({request, prepared});
    }
    assert.equal(
      commits[0].prepared.binding.wire === commits[1].prepared.binding.wire,
      false,
    );
    const physicalCid = JSON.parse(
      commits[0].prepared.binding.wire,
    ).material_generation_cid;
    assert.equal(
      JSON.parse(commits[1].prepared.binding.wire).material_generation_cid,
      physicalCid,
    );
    const firstRetired = await store.retireCommittedResult(
      indexKeyFor(firstRequest),
      firstRequest.inventory[0].result_definition_cid,
    );
    assert.equal(firstRetired.cleanup.status().pending, false);
    assert.equal((await store.verifyObject(physicalCid)).cid, physicalCid);
    const remaining = [];
    await store.consumeCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
      () => true,
      chunk => remaining.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(remaining).toString('utf8'),
      'fixture durable Result payload');
    const secondRetired = await store.retireCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
    );
    assert.equal(secondRetired.cleanup.status().pending, false);
    await assert.rejects(
      store.verifyObject(physicalCid), code('PublicationObjectMissing'),
    );
  });

test('visible index is not committed until directory durability is confirmed',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-durability-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let indexSyncFailures = 2;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
          indexSyncFailures--;
          const error = new Error('injected index directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    let unknown;
    await assert.rejects(
      commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
      error => {
        unknown = error;
        return error?.code === 'EIO' && error.cleanupPending === true &&
          error.cleanupHandle?.status().pending === true;
      },
    );
    assert.deepEqual(
      await store.inspectCommittedIndex(indexKeyFor(request)), entry,
    );
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(store.status().storedBytes > 0, true);
    assert.equal((await unknown.cleanupHandle.retry()).pending, false);
    assert.equal(unknown.cleanupHandle.status().outcome, 'committed');
    assert.deepEqual(
      await store.confirmCommittedIndex(indexKeyFor(request)), entry,
    );
    const idempotent = await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(idempotent.committed, false);
    assert.equal(idempotent.idempotent, true);
    assert.deepEqual(idempotent.entry, entry);
    assert.equal(prepared.prepared.status().pending, false);
  });

test('committed payload custody remains retryable after cleanup failure',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-custody-retry-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let custodySyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'prepared-custody') &&
            custodySyncFailures > 0) {
          custodySyncFailures--;
          const error = new Error('injected custody sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    // No intermediate semantic preparations remain. Fail the SAME payload's
    // adoption ACK and reconciliation, not a historical internal sync count.
    custodySyncFailures = 2;
    let unknown;
    await assert.rejects(commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    ), error => {
      unknown = error;
      return error?.cleanupPending === true &&
        error.cleanupHandle?.status().pending === true;
    });
    assert.deepEqual(
      await store.inspectCommittedIndex(indexKeyFor(request)), entry,
    );
    assert.equal(prepared.prepared.status().pending, false,
      'the transferred holder is settled; the original commit pin owns failed allocation cleanup');
    const recovered = await unknown.cleanupHandle.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.outcome, 'committed');
    assert.equal(prepared.prepared.status().pending, false);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  });

test('confirmed non-commit releases custody before prepared reclamation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-noncommit-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let indexSyncFailures = 2;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
          indexSyncFailures--;
          const error = new Error('injected index directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    let unknown;
    await assert.rejects(commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    ), error => {
      unknown = error;
      return error?.cleanupHandle?.status().pending === true;
    });
    const installed = await readdir(join(directory, 'indexes'));
    assert.equal(installed.length, 1);
    await unlink(join(directory, 'indexes', installed[0]));
    const reconciled = await unknown.cleanupHandle.retry();
    assert.equal(reconciled.pending, false);
    assert.equal(reconciled.outcome, 'uncommitted');
    const holdingCid = digest('uncommitted-effect-source-holding');
    const heldBytes = Buffer.from('held effect source', 'utf8');
    const heldWriter = store.createPreparedObjectWriter(heldBytes.length);
    await heldWriter.append(heldBytes);
    const held = await heldWriter.seal(digest(heldBytes));
    await store.commitPhysicalHolding({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'effect-source',
      holding_cid: holdingCid,
      manifest_cid: cids.manifest,
      objects: [{cid: held.cid, byte_count: held.bytes}],
    }, [held.prepared]);
    // Model an Effectful commit's exact durable inventory at the fault edge.
    const inventoryPath = await legacyInventoryFixture(directory,entry.public_index_entry_cid);
    const inventory = JSON.parse(await readFile(inventoryPath, 'utf8'));
    inventory.physical_holding_cids = [holdingCid];
    await writeFile(inventoryPath, JSON.stringify(inventory));
    const inventoryHandle = await open(inventoryPath, 'r');
    try { await inventoryHandle.sync(); }
    finally { await inventoryHandle.close(); }
    // Model the same Effectful stage original in its retained recovery row,
    // not an independently mutated file with a different pending original.
    const recovery = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'));
    try {
      recovery.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; BEGIN IMMEDIATE');
      assert.equal(recovery.prepare('UPDATE pending_publications SET inventory_wire=? WHERE public_index_cid=?')
        .run(JSON.stringify(inventory),entry.public_index_entry_cid).changes,1);
      recovery.exec('COMMIT');
    } finally { recovery.close(); }
    const candidateCleanup = await store.retireUncommittedPublication(
      entry.public_index_entry_cid,
    );
    assert.equal(candidateCleanup.deleted, false);
    assert.equal(candidateCleanup.cleanup.status().pending, true);
    assert.equal(
      candidateCleanup.cleanup.status().errors.at(-1)?.code,
      'PublicationUncommittedMetadataLive',
    );
    assert.equal((await readdir(
      join(directory, 'metadata-inventories'),
    )).length, 1);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal(store.status().closed, false);
    const cancelled = publicationRecord(
      attempt, 2, 'cancelled', prepared.committing,
    );
    await store.appendRecord(wire(cancelled), {uncommittedConfirmed: true});
    await assert.rejects(candidateCleanup.cleanup.retry(),
      code('PublicationPhysicalHoldingCleanupRequired'));
    assert.notEqual(await store.inspectPhysicalHolding(holdingCid), undefined);
    assert.equal((await readdir(
      join(directory, 'metadata-inventories'),
    )).length, 1);
    assert.equal((await store.retirePhysicalHolding(holdingCid)).deleted,
      true);
    assert.equal((await candidateCleanup.cleanup.retry()).pending, false);
    assert.deepEqual(await readdir(
      join(directory, 'metadata-inventories'),
    ), []);
    await assert.rejects(
      store.readPublicationContract(
        entry.public_index_entry_cid, 'public_index_entry',
      ),
      code('PublicationContractMissing'),
    );
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(await prepared.prepared.release(), true);
    assert.equal(prepared.prepared.status().pending, false);
    assert.equal(await store.close(), true);
  });

test('restart reclaims terminal uncommitted publication metadata', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-uncommitted-metadata-',
  ));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  let indexSyncFailures = 2;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
        indexSyncFailures--;
        const error = new Error('injected index directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const store = await openLocalPublicationStore(
    configuration, contractControl, durability,
  );
  const invocationValue = invocation();
  const request = publicationRequest(
    resultDefinition(), invocationValue.invocation_cid,
  );
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(
    store, request, attempt, invocationValue,
  );
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  let unknown;
  await assert.rejects(commitFixtureIndex(store,
    wire(entry), prepared.required, prepared.evidence,
  ), error => {
    unknown = error;
    return error?.cleanupHandle?.status().pending === true;
  });
  const [installed] = await readdir(join(directory, 'indexes'));
  await unlink(join(directory, 'indexes', installed));
  assert.equal((await unknown.cleanupHandle.retry()).outcome, 'uncommitted');
  const cancelled = publicationRecord(
    attempt, 2, 'cancelled', prepared.committing,
  );
  await store.appendRecord(wire(cancelled), {uncommittedConfirmed: true});
  assert.equal(await prepared.prepared.release(), true);
  const nativeInventory = () => {
    const db = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'), {readOnly: true});
    try {return db.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?')
      .get(entry.public_index_entry_cid);}
    finally {db.close();}
  };
  assert.notEqual(nativeInventory(), undefined, 'the original uncommitted native inventory remains pending');
  assert.equal(await store.close(), true);

  const reopened = await openLocalPublicationStore(
    configuration, contractControl,
  );
  t.after(async () => { await reopened.close(); });
  assert.deepEqual(await readdir(
    join(directory, 'metadata-inventories'),
  ), []);
  assert.equal(nativeInventory(), undefined, 'cold cleanup retires that same native inventory');
  await assert.rejects(
    reopened.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ),
    code('PublicationContractMissing'),
  );
});

test('commit verifies durable binding against the stored physical generation',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const mismatchedValue = JSON.parse(prepared.binding.wire);
    delete mismatchedValue.durable_result_binding_cid;
    mismatchedValue.byte_count++;
    const mismatched = seal('durable_result_binding', mismatchedValue);
    const mismatchedContract = contractControl.admit(
      'durable_result_binding', wire(mismatched), limits,
    );
    await store.putPublicationContract(
      'durable_result_binding', wire(mismatched),
    );
    const evidence = Object.freeze({
      ...prepared.evidence,
      durableBindings: Object.freeze([mismatchedContract]),
    });
    const required = prepared.required
      .filter(cid => cid !== prepared.binding.identity)
      .concat(mismatchedContract.identity);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [mismatchedContract.identity],
    });
    await assert.rejects(
      commitFixtureIndex(store, wire(entry), required, evidence),
      code('PublicationDurableBindingMismatch'),
    );
    assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)),
      undefined);
    assert.equal(await prepared.prepared.release(), true);
  });

test('same intent is idempotent while conflicting commit is rejected',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await commitFixtureIndex(store,
      wire(entry), prepared.required, prepared.evidence,
    );

    const retryAttempt = publicationAttempt(request, 'attempt-2');
    const retry = await prepareCommit(
      store, request, retryAttempt, invocationValue,
    );
    const retryEntry = indexEntry(request, retryAttempt, invocationValue, {
      durable_result_binding_cids: [retry.binding.identity],
      committed_at: '2026-09-18T00:01:00.000Z',
    });
    const idempotent = await commitFixtureIndex(store,
      wire(retryEntry), retry.required, retry.evidence,
    );
    assert.equal(idempotent.committed, false);
    assert.equal(idempotent.idempotent, true);
    assert.deepEqual(idempotent.entry, entry);
    assert.equal(retry.prepared.status().pending, false);

    const otherReceiptCid = digest('different final receipt');
    await store.putSemantic('different final receipt', otherReceiptCid);
    const changedReceipt = indexEntry(request, retryAttempt,
      invocationValue, {
        durable_result_binding_cids: [retry.binding.identity],
        run_receipt_cid: otherReceiptCid,
      });
    await assert.rejects(commitFixtureIndex(store,
      wire(changedReceipt), [...retry.required, otherReceiptCid],
      retry.evidence,
    ), code('PublicationCommitConflict'));
    assert.deepEqual(await store.confirmCommittedIndex(indexKeyFor(request)),
      entry);

    const conflictingRequest = publicationRequest(
      resultDefinition('other'), invocationValue.invocation_cid,
    );
    const conflictAttempt = publicationAttempt(
      conflictingRequest, 'attempt-3',
    );
    const conflict = await prepareCommit(
      store, conflictingRequest, conflictAttempt, invocationValue,
    );
    const conflictingEntry = indexEntry(
      conflictingRequest, conflictAttempt, invocationValue, {
        durable_result_binding_cids: [conflict.binding.identity],
      },
    );
    await assert.rejects(commitFixtureIndex(store,
      wire(conflictingEntry), conflict.required, conflict.evidence,
    ), code('PublicationCommitConflict'));
    assert.equal(await conflict.prepared.release(), true);
  });

test('concurrent public commits serialize one installation and one replay',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const results = await Promise.all([
      commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
      commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence),
    ]);
    assert.deepEqual(results.map(result => [
      result.committed, result.idempotent,
    ]), [[true, false], [false, true]]);
    assert.deepEqual(await store.confirmCommittedIndex(indexKeyFor(request)),
      entry);
    assert.equal(prepared.prepared.status().pending, false);
  });

test('lookup hides absence and verifies current authorization', async t => {
  const {store} = await fixture(t);
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => false),
    code('PublicationLookupDenied'));
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => true),
    code('PublicationLookupDenied'));
  let calls = 0;
  await assert.rejects(store.lookupCommittedIndex(indexKey, value => {
    calls++;
    return !Object.hasOwn(value, 'entry');
  }), code('PublicationLookupDenied'));
  assert.equal(calls, 1);
  await assert.rejects(store.consumeCommittedResult(
    indexKey,
    resultDefinition().result_definition_cid,
    () => false,
    () => assert.fail('an unauthorized payload was exposed'),
  ), code('PublicationLookupDenied'));
});

test('physical mutation is rejected after restart', async t => {
  const {store, directory} = await fixture(t);
  const stored = await store.putBytes(Buffer.from('original'));
  await writeFile(join(
    directory, 'objects', stored.cid.slice('sha256:'.length),
  ), 'mutated!');
  await assert.rejects(store.verifyObject(stored.cid),
    code('PublicationObjectCorrupt'));
});

test('publication capacity preflight observes limits without reserving',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 1024,
      maxObjectBytes: 128,
      maxObjects: 4,
    });
    const before = store.status();
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 4,
      maxObjectBytes: 128,
    }), true);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1025,
      objectCount: 4,
      maxObjectBytes: 128,
    }), false);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 5,
      maxObjectBytes: 128,
    }), false);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 4,
      maxObjectBytes: 129,
    }), false);
    assert.deepEqual(store.status(), before);
  });

test('native publication Index and inventory share their real commit without duplicate file metadata', async t => {
  const tracked = new Set();
  const syncs = [], open = fsPromises.open, exec = DatabaseSync.prototype.exec;
  let commits = 0, armed = false;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') commits++;
    return result;
  });
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(open, this, [path, ...args]);
    if (tracked.has(String(path))) {
      const sync = handle.sync;
      t.mock.method(handle, 'sync', function(...syncArgs) {
        if (armed) syncs.push(String(path));
        return Reflect.apply(sync, this, syncArgs);
      });
    }
    return handle;
  });
  syncBuiltinESMExports();
  t.after(() => {armed = false; t.mock.restoreAll(); syncBuiltinESMExports();});
  const {store, directory} = await fixture(t), invocationValue = invocation();
  const request = publicationRequest(resultDefinition(), digest('native Index publication Run'));
  const attempt = publicationAttempt(request, 'native Index publication');
  const prepared = await prepareCommit(store, request, attempt, invocationValue, cids.policy, false, true);
  const entry = indexEntry(request, attempt, invocationValue, {durable_result_binding_cids: [prepared.binding.identity]});
  for (const name of ['objects', 'contracts', 'indexes']) tracked.add(join(directory, name));
  armed = true;
  const committed = await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
  assert.equal(committed.committed, true);
  assert.equal(commits, 1, 'Index CAS, immutable body and inventory share the same actual durable transition');
  assert.deepEqual(syncs, [], 'native Index does not also install filesystem body/Index aliases');
  assert.deepEqual(await readdir(join(directory, 'indexes')), []);
  assert.equal((await store.lookupCommittedIndex(indexKeyFor(request), () => true)).public_index_entry_cid,
    entry.public_index_entry_cid);
  assert.equal((await store.readSemanticBytes(entry.public_index_entry_cid)).toString(), wire(entry));
  armed = false;
  await store.close();
});

for (const afterCommit of [false,true]) {
test(`native Index Store retains both storage and payload custody after ${afterCommit ? 'committed' : 'rolled-back'} reply loss`, async t => {
  const exec = DatabaseSync.prototype.exec, prepare = DatabaseSync.prototype.prepare;
  let armed = false, selected = false, lost = false;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql){
    const statement = Reflect.apply(prepare,this,[sql]), run = statement.run;
    if (sql === 'INSERT INTO native_publication_indexes VALUES(?,?,?,?,?,1)') t.mock.method(statement,'run',function(...args){
      const result = Reflect.apply(run,this,args); if (armed) selected = true; return result;
    });
    return statement;
  });
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if (armed && selected && !lost && sql === 'COMMIT') {
      lost = true; if (afterCommit) Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost original native Index reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,directory} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(),digest('native Index reply loss ' + afterCommit));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store,request,attempt,invoked,cids.policy,false,true);
  const entry = indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
  let failure; armed = true;
  await assert.rejects(commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence),error=>{
    failure = error; return error.outcome === 'unknown';
  });
  assert(lost);
  assert.equal(failure.cleanupHandle.status().pending,true);
  assert.equal(prepared.prepared.status().pending,true,'the original payload remains owned before storage confirmation');
  assert.equal(store.status().reservedObjects,1,'Index body reservation is not refunded on Unknown');
  const first = failure.cleanupHandle.retry(), same = failure.cleanupHandle.retry();
  assert.equal(first,same,'same original cleanup is single-flight');
  assert.equal((await first).pending,false);
  assert.equal(prepared.prepared.status().pending,false);
  assert.equal(store.status().reservedObjects,0);
  assert.equal((await store.lookupCommittedIndex(indexKeyFor(request),()=>true)).public_index_entry_cid,entry.public_index_entry_cid);
  const database = new DatabaseSync(join(directory,'delivery-attempts.sqlite3'),{readOnly:true});
  try {
    assert.equal(database.prepare('SELECT count(*) AS n FROM native_publication_indexes').get().n,1);
    assert.equal(database.prepare('SELECT count(*) AS n FROM native_publication_materials').get().n,1);
    assert.equal(database.prepare('SELECT ack_revision FROM native_publication_indexes').get().ack_revision,afterCommit ? 2 : 1);
  } finally {database.close();}
  armed = false; await store.close();
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});
}

test('original Host commit lookup confirms its same native Index writer before reconciliation', async t => {
  const exec = DatabaseSync.prototype.exec, prepare = DatabaseSync.prototype.prepare;
  let armed = false, selected = false, lost = false, confirmations = 0, receiver;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]), run = statement.run;
    if (sql === 'INSERT INTO native_publication_indexes VALUES(?,?,?,?,?,1)') {
      t.mock.method(statement, 'run', function(...args) {
        const result = Reflect.apply(run, this, args);
        if (armed) selected = true;
        return result;
      });
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && selected && sql === 'COMMIT') {
      if (!lost) {
        lost = true; receiver = this;
        throw Object.assign(new Error('lost selected native Index COMMIT reply'), {code: 'EIO'});
      }
      assert.equal(this, receiver, 'confirmation stays on the same original database');
      confirmations++;
    }
    return result;
  });
  const {store, directory} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(), digest('original Host native Index lookup'));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invoked, cids.policy, false, true);
  const entry = indexEntry(request, attempt, invoked, {durable_result_binding_cids: [prepared.binding.identity]});
  let original; armed = true;
  await assert.rejects(commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence), error => {
    original = error; return error.outcome === 'unknown' && error.cleanupPending === true;
  });
  t.after(async () => {
    armed = false;
    if (original.cleanupHandle.status().pending) await original.cleanupHandle.retry();
  });
  assert(lost); assert.equal(confirmations, 0);
  const committed = await lookupOriginalPublicationCommit(original, () =>
    store.lookupCommittedIndex(indexKeyFor(request), () => true));
  assert.equal(committed.public_index_entry_cid, entry.public_index_entry_cid);
  assert.equal(confirmations, 1, 'only the original storage confirmation is needed');
  assert.equal(original.cleanupHandle.status().pending, false);
  assert.equal(prepared.prepared.status().pending, false);
  assert.equal(store.status().reservedObjects, 0);
  armed = false;
  await store.close();
  await assert.rejects(stat(join(directory, 'owner')), code('ENOENT'));
});

test('native Index rechecks the original publication record inside its commit', async t => {
  const {store,directory} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(),digest('native Index changed publication record'));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store,request,attempt,invoked,cids.policy,false,true);
  const entry = indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
  const changed = publicationRecord(attempt,2,'publication_unknown',prepared.committing);
  const target = join(directory,'contracts',entry.public_index_entry_cid.slice(7)+'.json');
  const lstatOriginal = fsPromises.lstat;
  let changedOnce = false;
  t.mock.method(fsPromises,'lstat',async function(path,...args){
    if (!changedOnce && String(path) === target) {
      changedOnce = true;
      await store.appendRecord(wire(changed),{uncommittedConfirmed:false});
    }
    return Reflect.apply(lstatOriginal,this,[path,...args]);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  await assert.rejects(commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence),code('PublicationRecordConflict'));
  assert(changedOnce);
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)),undefined);
  assert.equal((await store.latestRecord(attempt.publication_attempt_cid)).publication_record_cid,changed.publication_record_cid);
  assert.equal(store.status().reservedObjects,0);
  assert.equal(await prepared.prepared.release(),true);
  await store.close();
});

test('concurrent native Index confirmation retains one original lost-reply writer', async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, lost = false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if (armed && !lost && sql === 'COMMIT') {
      lost = true; Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('original native Index confirmation reply lost'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const {store,directory,configuration} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(),digest('concurrent native Index confirmation'));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store,request,attempt,invoked,cids.policy,false,true);
  const entry = indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence); await store.close();
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  const lstatOriginal = fsPromises.lstat;
  let entered = 0, release;
  const both = new Promise(resolve => {release = resolve;});
  t.mock.method(fsPromises,'lstat',async function(path,...args){
    if (armed && String(path).startsWith(join(directory,'indexes')+sep)) {
      if (++entered === 2) release();
      await both;
    }
    return Reflect.apply(lstatOriginal,this,[path,...args]);
  });
  syncBuiltinESMExports();
  t.after(async()=>{armed=false;t.mock.restoreAll();syncBuiltinESMExports();await reopened.close();});
  armed = true;
  const results = await Promise.allSettled([reopened.lookupCommittedIndex(indexKeyFor(request),()=>true),
    reopened.lookupCommittedIndex(indexKeyFor(request),()=>true)]);
  assert(lost); assert.equal(entered,2);
  assert(results.every(result => result.status === 'rejected'));
  assert.equal(results[0].reason,results[1].reason,'the second acquisition cannot replace the existing storage duty');
  const cleanup = results[0].reason.cleanupHandle;
  assert.equal(cleanup.status().pending,true);
  assert.equal((await cleanup.retry()).pending,false);
  armed = false;
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(request),()=>true)).public_index_entry_cid,entry.public_index_entry_cid);
  await reopened.close();
  const db = new DatabaseSync(join(directory,'delivery-attempts.sqlite3'),{readOnly:true});
  try {assert.equal(db.prepare('SELECT ack_revision FROM native_publication_indexes').get().ack_revision,3);}
  finally {db.close();}
  await assert.rejects(stat(join(directory,'owner')),code('ENOENT'));
});

test('native Index confirmation retains its same cleanup through two committed lost replies', async t => {
  const exec = DatabaseSync.prototype.exec;
  let armed = false, remaining = 2;
  const acknowledgedRevisions = [];
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const answer = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') {
      const row = this.prepare('SELECT ack_revision FROM native_publication_indexes').get();
      acknowledgedRevisions.push(row.ack_revision);
      if (remaining-- > 0) throw Object.assign(new Error('same Index confirmation reply lost'), {code: 'EIO'});
    }
    return answer;
  });
  const {store, directory, configuration} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(), digest('repeated native Index confirmation'));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store, request, attempt, invoked, cids.policy, false, true);
  const entry = indexEntry(request, attempt, invoked, {durable_result_binding_cids: [prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence); await store.close();
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  t.after(async () => {armed = false; t.mock.restoreAll(); await reopened.close();});
  let original;
  armed = true;
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(request), () => true), error => {
    original = error; return error.outcome === 'unknown' && error.cleanupPending === true;
  });
  const cleanup = original.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  await assert.rejects(cleanup.retry(), error => error.outcome === 'unknown');
  assert.equal(cleanup.status().pending, true);
  assert.deepEqual(acknowledgedRevisions, [2, 3], 'Both failures followed actual commits of the same Index');
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(request), () => true));
  assert.deepEqual(acknowledgedRevisions, [2, 3], 'Another read cannot replace the uncertain original');
  assert.equal((await cleanup.retry()).pending, false, 'The SAME captured cleanup must acknowledge its next real write');
  assert.equal(original.cleanupPending, false);
  assert.deepEqual(acknowledgedRevisions, [2, 3, 4]);
  armed = false;
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(request), () => true)).public_index_entry_cid,
    entry.public_index_entry_cid);
  await reopened.close();
  await assert.rejects(stat(join(directory, 'owner')), code('ENOENT'));
});

test('native Index shared Result payload keeps the same allocation until final real unlink ACK', async t => {
  const {store,directory,configuration} = await fixture(t);
  const publish = async label => {
    const invoked = invocation(), request = publicationRequest(resultDefinition(),digest(label));
    const attempt = publicationAttempt(request), prepared = await prepareCommit(store,request,attempt,invoked,cids.policy,false,true);
    const entry = indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
    await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);
    return {request,entry,physical:JSON.parse(prepared.binding.wire).material_generation_cid};
  };
  const first = await publish('native first shared Result'), second = await publish('native second shared Result');
  assert.equal(first.physical,second.physical);
  const path = join(directory,'objects',first.physical.slice(7)), original = await stat(path);
  await store.close();
  let armed = false, lost = false;
  const reopened = await openLocalPublicationStore(configuration,contractControl,{async syncDirectory(directoryPath){
    if (armed && !lost && directoryPath === join(directory,'objects')) {
      let missing = false;
      try {await stat(path);} catch (error) {if(error.code !== 'ENOENT') throw error; missing = true;}
      if (missing) {lost = true; throw Object.assign(new Error('last native Result directory ACK failed'),{code:'EIO'});}
    }
    const handle = await open(directoryPath,'r'); try {await handle.sync();} finally {await handle.close();}
  }});
  t.after(async()=>{armed=false;await reopened.close();});
  const retired = await reopened.retireCommittedResult(indexKeyFor(first.request),first.request.inventory[0].result_definition_cid);
  assert.equal(retired.cleanup.status().pending,false);
  const retained = await stat(path);
  assert.equal(retained.dev,original.dev); assert.equal(retained.ino,original.ino);
  const bytes = [];
  await reopened.consumeCommittedResult(indexKeyFor(second.request),second.request.inventory[0].result_definition_cid,
    ()=>true,chunk=>bytes.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(bytes).toString(),'fixture durable Result payload');
  const before = reopened.status(); armed = true;
  const last = await reopened.retireCommittedResult(indexKeyFor(second.request),second.request.inventory[0].result_definition_cid);
  assert(lost); assert.equal(last.cleanup.status().pending,true);
  assert.equal(reopened.status().objectCount,before.objectCount,'unlink visibility is not quota release');
  await assert.rejects(reopened.close(),code('PublicationStoreCleanupPending'));
  assert.equal((await last.cleanup.retry()).pending,false);
  assert.equal(reopened.status().objectCount,before.objectCount-1);
  await assert.rejects(stat(path),code('ENOENT'));
  armed = false; await reopened.close();
});

test('native Index selected body corruption refuses without rebuilding unrelated publications', async t => {
  const {store,directory,configuration} = await fixture(t), invoked = invocation();
  const request = publicationRequest(resultDefinition(),digest('native selected corruption'));
  const attempt = publicationAttempt(request), prepared = await prepareCommit(store,request,attempt,invoked,cids.policy,false,true);
  const entry = indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence); await store.close();
  const db = new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {db.prepare('UPDATE publication_contracts SET wire=?,byte_count=? WHERE semantic_cid=?').run('{}',2,entry.public_index_entry_cid);}
  finally {db.close();}
  const reopened = await openLocalPublicationStore(configuration,contractControl);
  try {
    await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(request),()=>true),code('InvalidPublicationContract'));
    assert.deepEqual(await readdir(join(directory,'indexes')),[],'no file Index or authority is reconstructed');
  } finally {await reopened.close();}
});

test('native publication inventory is the durable original without duplicate file ACKs',async t=>{
  const {store,directory}=await fixture(t),invocationValue=invocation();
  const request=publicationRequest(resultDefinition(),digest('native inventory Run'));
  const attempt=publicationAttempt(request,'native inventory');
  const prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  const inventoryDirectory=join(directory,'metadata-inventories'),opens=[];
  const actualOpen=fsPromises.open;
  t.mock.method(fsPromises,'open',function(path,...args){
    if(String(path)===inventoryDirectory||String(path).startsWith(inventoryDirectory+sep))opens.push(String(path));
    return Reflect.apply(actualOpen,this,[path,...args]);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  assert.equal((await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence)).committed,true);
  assert.deepEqual(opens,[],'native inventory is not also an FS body/directory acknowledgement');
  assert.deepEqual(await readdir(inventoryDirectory),[]);
  assert.equal((await store.lookupCommittedIndex(indexKeyFor(request),()=>true)).public_index_entry_cid,entry.public_index_entry_cid);
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {
    const row=database.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?').get(entry.public_index_entry_cid);
    assert.equal(JSON.parse(row.inventory_wire).run_definition_cid,entry.run_definition_cid);
    assert.equal(database.prepare('SELECT count(*) AS n FROM pending_publications').get().n,1,
      'the derived completion is retained, not acknowledged before its next actual transaction');
  } finally { database.close(); }
  await store.close();
  const closedDatabase = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'), {readOnly: true});
  try { assert.equal(closedDatabase.prepare('SELECT count(*) AS n FROM pending_publications').get().n, 0); }
  finally { closedDatabase.close(); }
});

test('native publication inventory survives reopen and retires only its original ownership',async t=>{
  const setup=await fixture(t),{store,directory,configuration}=setup;
  const publish=async label=>{
    const invocationValue=invocation(),request=publicationRequest(resultDefinition(),digest(label));
    const attempt=publicationAttempt(request,label),prepared=await prepareCommit(store,request,attempt,invocationValue);
    const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
    await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);
    return {request,entry};
  };
  const first=await publish('first native owner'),second=await publish('second native owner');
  await store.close();
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(first.request),()=>true)).public_index_entry_cid,first.entry.public_index_entry_cid);
  const retirement=await reopened.retireCommittedPublicationMetadata(indexKeyFor(first.request),'2027-01-01T00:00:00.000Z');
  assert.equal(retirement.cleanup.status().pending,false);
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(first.request),()=>true),code('PublicationLookupDenied'));
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(second.request),()=>true)).public_index_entry_cid,second.entry.public_index_entry_cid);
  assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(),resultSchemaWire);
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {
    assert.equal(database.prepare('SELECT count(*) AS n FROM native_publication_inventories').get().n,1);
    assert.equal(database.prepare('SELECT entries FROM native_publication_inventory_usage').get().entries,1);
  } finally {database.close();}
  await reopened.close();
});

test('metadata deletion keeps the same cleanup after native retirement and lost marker directory ACK',async t=>{
  const {store,directory,configuration}=await fixture(t);
  const invocationValue=invocation(),request=publicationRequest(resultDefinition(),invocationValue.invocation_cid);
  const attempt=publicationAttempt(request),prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);await store.close();
  let lost=false,armed=false;
  const reopened=await openLocalPublicationStore(configuration,contractControl,{async syncDirectory(path){
    if(armed&&!lost&&path===join(directory,'metadata-deletions')&&(await readdir(path)).length===0){
      lost=true;throw Object.assign(new Error('lost final marker directory ACK'),{code:'EIO'});
    }
    const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
  }});
  armed=true;
  const retired=await reopened.retireCommittedPublicationMetadata(indexKeyFor(request),'2027-01-01T00:00:00.000Z');
  assert.equal(lost,true);assert.equal(retired.cleanup.status().pending,true);
  const again=await reopened.retireCommittedPublicationMetadata(indexKeyFor(request),'2027-01-01T00:00:01.000Z');
  assert.equal(again.cleanup,retired.cleanup);assert.equal(again.deleted,false);
  await assert.rejects(reopened.close(),code('PublicationStoreCleanupPending'));
  assert.equal((await again.cleanup.retry()).pending,false);
  assert.equal((await reopened.retireCommittedPublicationMetadata(indexKeyFor(request),'2027-01-01T00:00:02.000Z')).deleted,true);
  await reopened.close();
});

for(const phase of ['transfer','completion']) {
test(`metadata deletion ${phase} Unknown retains the actual Store cleanup original`,async t=>{
  let armed=false,lost=false,request;
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT') {
      const fence=this.prepare('SELECT retired FROM metadata_deletion_fences WHERE run_cid=?').get(request.run_definition_cid);
      if(fence?.retired===(phase==='transfer'?0:1)) {
        lost=true;Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('lost original Store metadata '+phase+' reply'),{code:'EIO'});
      }
    }
    return Reflect.apply(exec,this,[sql]);
  });
  // Install the fault before opening: the real Store captures its original
  // native exec and must not dispatch through a later prototype replacement.
  const {store,directory}=await fixture(t);
  const invocationValue=invocation();request=publicationRequest(resultDefinition(),invocationValue.invocation_cid);
  const attempt=publicationAttempt(request),prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);armed=true;
  const retired=await store.retireCommittedPublicationMetadata(indexKeyFor(request),'2027-01-01T00:00:00.000Z');
  assert.equal(lost,true);assert.equal(retired.cleanup.status().pending,true);
  const again=await store.retireCommittedPublicationMetadata(indexKeyFor(request),'2027-01-01T00:00:01.000Z');
  assert.equal(again.cleanup,retired.cleanup);
  await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
  assert.equal((await retired.cleanup.retry()).pending,false);armed=false;
  assert.deepEqual(await readdir(join(directory,'metadata-deletions')),[]);
  assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)),undefined);
  await store.close();
});
}

test('native shared holding selection reads only owners of that holding', async t => {
  const setup = await fixture(t), {store, directory, configuration} = setup;
  const publish = async label => {
    const invocationValue = invocation(), request = publicationRequest(resultDefinition(), digest(label));
    const attempt = publicationAttempt(request, label), prepared = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {durable_result_binding_cids: [prepared.binding.identity]});
    await commitFixtureIndex(store, wire(entry), prepared.required, prepared.evidence);
    return {request, entry};
  };
  const first = await publish('indexed first holding owner');
  const second = await publish('indexed second holding owner');
  const unrelated = await publish('unrelated holding inventory');
  const payload = await preparePhysical(store, Buffer.from('indexed shared physical bytes'));
  const holding = physicalHolding(digest('indexed shared physical holding'), digest('indexed shared manifest'),
    [{cid: payload.cid, byte_count: payload.bytes}], 'effect-source');
  await store.commitPhysicalHolding(holding, [payload.prepared]);
  // Existing explicit contract-control fixture: two native inventory owners
  // of one real holding. This does not fabricate a Source/Model issuer.
  const database = new DatabaseSync(join(directory, 'delivery-attempts.sqlite3'));
  try {
    database.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; BEGIN IMMEDIATE');
    for (const owner of [first, second]) {
      const row = database.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?')
        .get(owner.entry.public_index_entry_cid);
      const inventory = JSON.parse(row.inventory_wire);
      inventory.physical_holding_cids = [holding.holding_cid];
      database.prepare('UPDATE native_publication_inventories SET inventory_wire=? WHERE public_index_cid=?')
        .run(JSON.stringify(inventory), owner.entry.public_index_entry_cid);
    }
    database.exec('COMMIT');
  } finally {database.close();}
  await store.close();
  let armed = false, fullInventoryReads = 0;
  const holdingOwners = [], prepare = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]), all = statement.all;
    t.mock.method(statement, 'all', function(...args) {
      const rows = Reflect.apply(all, this, args);
      if (armed && sql === 'SELECT * FROM native_publication_inventories ORDER BY public_index_cid LIMIT ?') {
        fullInventoryReads += rows.length;
      }
      if (armed && args[0] === 'holding' && args[1] === holding.holding_cid) {
        holdingOwners.push(...rows.map(row => row.public_index_cid));
      }
      return rows;
    });
    return statement;
  });
  const reopened = await openLocalPublicationStore(configuration, contractControl);
  const path = join(directory, 'objects', payload.cid.slice(7)), original = await stat(path);
  armed = true;
  const retired = await reopened.retireCommittedPublicationMetadata(indexKeyFor(first.request), '2027-01-01T00:00:00.000Z');
  armed = false;
  assert.equal(retired.cleanup.status().pending, false);
  assert.deepEqual(await reopened.inspectPhysicalHolding(holding.holding_cid), holding);
  const retained = await stat(path);
  assert.equal(retained.dev, original.dev); assert.equal(retained.ino, original.ino);
  assert.equal(fullInventoryReads, 0, 'selected retirement does not read native inventory history');
  assert.deepEqual(holdingOwners, [second.entry.public_index_entry_cid]);
  assert(!holdingOwners.includes(unrelated.entry.public_index_entry_cid));
  await reopened.close();
});

test('native publication inventories retain one shared physical holding until its final original ACK',async t=>{
  const setup=await fixture(t),{store,directory,configuration}=setup;
  const publish=async label=>{
    const invocationValue=invocation(),request=publicationRequest(resultDefinition(),digest(label));
    const attempt=publicationAttempt(request,label),prepared=await prepareCommit(store,request,attempt,invocationValue);
    const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
    await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);return {request,entry};
  };
  const first=await publish('first shared native holding owner');
  const second=await publish('second shared native holding owner');
  const expectedBytes=Buffer.from('same original physical source holding');
  const payload=await preparePhysical(store,expectedBytes);
  const holding=physicalHolding(digest('shared native holding'),digest('shared native manifest'),
    [{cid:payload.cid,byte_count:payload.bytes}],'effect-source');
  await store.commitPhysicalHolding(holding,[payload.prepared]);
  // Explicit contract-control inventory fixture, not a fabricated Common
  // Source/Model issuer. Both native originals refer to the SAME real holding;
  // neither is converted to the legacy inventory-file representation.
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {
    database.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; BEGIN IMMEDIATE');
    for(const owner of [first,second]) {
      const row=database.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?')
        .get(owner.entry.public_index_entry_cid);
      const inventory=JSON.parse(row.inventory_wire);inventory.physical_holding_cids=[holding.holding_cid];
      assert.equal(database.prepare('UPDATE native_publication_inventories SET inventory_wire=? WHERE public_index_cid=?')
        .run(JSON.stringify(inventory),owner.entry.public_index_entry_cid).changes,1);
    }
    database.exec('COMMIT');
  } finally {database.close();}
  assert.deepEqual(await readdir(join(directory,'metadata-inventories')),[]);
  await store.close();
  const physicalPath=join(directory,'objects',payload.cid.slice(7));
  const originalIdentity=await stat(physicalPath);
  let armed=false,failAck=true,lostAcks=0;
  const reopened=await openLocalPublicationStore(configuration,contractControl,{
    async syncDirectory(path){
      if(armed&&failAck&&path===join(directory,'objects')) {
        let missing=false;
        try {await stat(physicalPath);}catch(error){if(error.code!=='ENOENT')throw error;missing=true;}
        if(missing){failAck=false;lostAcks++;throw Object.assign(new Error('final shared holding directory ACK failed'),{code:'EIO'});}
      }
      const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
    },
  });
  const retiredFirst=await reopened.retireCommittedPublicationMetadata(indexKeyFor(first.request),'2027-01-01T00:00:00.000Z');
  assert.equal(retiredFirst.cleanup.status().pending,false);
  assert.deepEqual(await reopened.inspectPhysicalHolding(holding.holding_cid),holding);
  const retainedIdentity=await stat(physicalPath);
  assert.equal(retainedIdentity.dev,originalIdentity.dev);assert.equal(retainedIdentity.ino,originalIdentity.ino);
  const chunks=[];await reopened.consumePhysicalHolding(holding.holding_cid,0,chunk=>chunks.push(Buffer.from(chunk)));
  assert.deepEqual(Buffer.concat(chunks),expectedBytes);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(second.request),()=>true)).public_index_entry_cid,
    second.entry.public_index_entry_cid);
  armed=true;
  const retiredLast=await reopened.retireCommittedPublicationMetadata(indexKeyFor(second.request),'2027-01-01T00:00:01.000Z');
  assert.equal(lostAcks,1);assert.equal(retiredLast.cleanup.status().pending,true);
  assert(reopened.status().storedBytes>=payload.bytes,'unacknowledged physical unlink does not refill its charge');
  await assert.rejects(reopened.close(),code('PublicationStoreCleanupPending'));
  assert.equal((await retiredLast.cleanup.retry()).pending,false);
  assert.equal(await reopened.inspectPhysicalHolding(holding.holding_cid),undefined);
  await assert.rejects(reopened.verifyObject(payload.cid),code('PublicationObjectMissing'));
  assert.deepEqual(await readdir(join(directory,'physical-holding-deletions')),[]);
  assert.deepEqual(await readdir(join(directory,'metadata-inventories')),[]);
  await reopened.close();
});

test('native publication inventory validates only the selected body and exact Index tuple',async t=>{
  const setup=await fixture(t),{store,directory,configuration}=setup;
  const publish=async label=>{
    const invocationValue=invocation(),request=publicationRequest(resultDefinition(),digest(label));
    const attempt=publicationAttempt(request,label),prepared=await prepareCommit(store,request,attempt,invocationValue);
    const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
    await commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence);return {request,entry};
  };
  const healthy=await publish('healthy native tuple'),selected=await publish('selected native tuple');
  await store.close();
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  let inventory;
  try {
    inventory=JSON.parse(database.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?')
      .get(selected.entry.public_index_entry_cid).inventory_wire);
    database.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON');
    database.prepare('UPDATE native_publication_inventories SET inventory_wire=? WHERE public_index_cid=?')
      .run(JSON.stringify({...inventory,run_definition_cid:digest('foreign native inventory Run')}),selected.entry.public_index_entry_cid);
  } finally {database.close();}
  const reopened=await openLocalPublicationStore(configuration,contractControl);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(healthy.request),()=>true)).public_index_entry_cid,healthy.entry.public_index_entry_cid);
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(selected.request),()=>true),code('InvalidPublicationMetadataInventoryStore'));
  await reopened.close();
});

async function committedHoldingFixture(setup, label) {
  const request = publicationRequest(resultDefinition(), digest(`published ${label}`));
  const invocationValue = invocation();
  const attempt = publicationAttempt(request, label);
  const prepared = await prepareCommit(setup.store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await commitFixtureIndex(setup.store, wire(entry), prepared.required, prepared.evidence);
  const payload = await preparePhysical(setup.store, `source ${label}`);
  const holding = physicalHolding(digest(`holding ${label}`), digest(`manifest ${label}`),
    [{cid: payload.cid, byte_count: payload.bytes}], 'effect-source');
  await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
  // Explicit adapter evidence fixture: bind this real holding to the committed
  // inventory without claiming an actual Common-issued Effect/capture chain.
  const inventoryPath = await legacyInventoryFixture(setup.directory,entry.public_index_entry_cid);
  const inventory = JSON.parse(await readFile(inventoryPath, 'utf8'));
  inventory.physical_holding_cids = [holding.holding_cid];
  await writeFile(inventoryPath, JSON.stringify(inventory));
  return {request, entry, holding, inventory, inventoryPath,
    holdingPath: join(setup.directory, 'physical-holdings',
      `${holding.holding_cid.slice(7)}.json`)};
}

test('publication recovery opens completed history without enumerating or reading its inventories and indexes',async t=>{
  const setup=await fixture(t);
  const selected=await committedHoldingFixture(setup,'pending indexed selected');
  await committedHoldingFixture(setup,'pending indexed unrelated');
  await setup.store.close();
  const originalOpen=fsPromises.open,originalReaddir=fsPromises.readdir;
  const reads=[],enumerations=[];
  const inventories=join(setup.directory,'metadata-inventories'),indexes=join(setup.directory,'indexes');
  t.mock.method(fsPromises,'open',function(path,...args){reads.push(String(path));return Reflect.apply(originalOpen,this,[path,...args]);});
  t.mock.method(fsPromises,'readdir',function(path,...args){enumerations.push(String(path));return Reflect.apply(originalReaddir,this,[path,...args]);});
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.deepEqual(enumerations.filter(path=>path===inventories||path===indexes),[]);
  assert.deepEqual(reads.filter(path=>path.startsWith(inventories+sep)||path.startsWith(indexes+sep)),[]);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(selected.request),()=>true))
    .public_index_entry_cid,selected.entry.public_index_entry_cid);
  assert.equal(reads.filter(path=>path===selected.inventoryPath).length,1);
  await reopened.close();
});

for(const damaged of ['inventory','Index']) {
test(`publication recovery defers an unrelated damaged committed ${damaged} to selected use`,async t=>{
  const setup=await fixture(t);
  const selected=await committedHoldingFixture(setup,'healthy recovery selection');
  const other=await committedHoldingFixture(setup,'damaged recovery selection');
  const hash=createHash('sha256').update('actql-local-public-index-key/0.1\0','utf8');
  for(const text of [other.request.namespace_id,other.request.authority_scope_cid,other.request.run_definition_cid]){
    const bytes=Buffer.from(text,'utf8'),length=Buffer.alloc(8);
    length.writeBigUInt64BE(BigInt(bytes.length));hash.update(length);hash.update(bytes);
  }
  const indexName=hash.digest('hex');
  const path=damaged==='inventory'?other.inventoryPath:join(setup.directory,'indexes',indexName+'.json');
  await setup.store.close();
  const bytes=Buffer.from('{}');await writeFile(path,bytes);
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(selected.request),()=>true))
    .public_index_entry_cid,selected.entry.public_index_entry_cid);
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(other.request),()=>true),
    code(damaged==='inventory'?'InvalidPublicationMetadataInventoryStore':'InvalidPublicationContract'));
  assert.deepEqual(await readFile(path),bytes);
  await reopened.close();
});
}

test('publication recovery completes only its retained inventory after a lost pre-file stage reply',async t=>{
  let armed=false,lost=false,staged=false;
  const prepare=DatabaseSync.prototype.prepare,exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql){
    const statement=Reflect.apply(prepare,this,[sql]);
    if(sql==='INSERT INTO pending_publications VALUES(?,?)'){
      const run=statement.run;
      t.mock.method(statement,'run',function(...args){const result=Reflect.apply(run,this,args);staged=true;return result;});
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    const result=Reflect.apply(exec,this,[sql]);
    if(armed&&staged&&!lost&&sql==='COMMIT'){
      lost=true;throw Object.assign(new Error('lost retained pre-file stage reply'),{code:'EIO'});
    }
    return result;
  });
  const setup=await fixture(t),invocationValue=invocation();
  const request=publicationRequest(resultDefinition(),digest('retained stage Run'));
  const attempt=publicationAttempt(request,'retained stage');
  const prepared=await prepareCommit(setup.store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  armed=true;
  let originalFailure;
  await assert.rejects(commitFixtureIndex(setup.store, wire(entry),prepared.required,prepared.evidence),error=>{
    originalFailure=error;return error.outcome==='unknown';
  });
  assert.equal(lost,true);
  assert.deepEqual(await readdir(join(setup.directory,'indexes')),[]);
  assert.deepEqual(await readdir(join(setup.directory,'metadata-inventories')),[]);
  assert.equal(originalFailure.cleanupHandle.status().pending, true);
  assert.equal((await originalFailure.cleanupHandle.retry()).pending, false,
    'settle the same staging original before acquiring physical-removal metadata');
  await prepared.prepared.release();
  await setup.store.close();
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  const originalDatabase=new DatabaseSync(join(setup.directory,'delivery-attempts.sqlite3'));
  try {
    const original=originalDatabase.prepare('SELECT inventory_wire FROM native_publication_inventories WHERE public_index_cid=?').get(entry.public_index_entry_cid);
    assert.equal(JSON.parse(original.inventory_wire).public_index_entry_cid,entry.public_index_entry_cid);
  } finally {originalDatabase.close();}
  assert.deepEqual(await readdir(join(setup.directory,'metadata-inventories')),[],
    'native recovery retains its original instead of creating a shadow file');
  assert.deepEqual(await readdir(join(setup.directory,'indexes')),[],'recovery never publishes or resubmits the Run');
  assert.equal((await reopened.latestRecord(attempt.publication_attempt_cid)).state,'committing');
  const cancelled=publicationRecord(attempt,2,'cancelled',prepared.committing);
  await reopened.appendRecord(wire(cancelled),{uncommittedConfirmed:true});
  const retired=await reopened.retireUncommittedPublication(entry.public_index_entry_cid);
  assert.equal(retired.deleted,true);
  assert.equal(originalFailure.outcome,'unknown','metadata completion never rewrites the original outcome');
  await reopened.close();
});

test('publication recovery retries only the native removal after physical uncommitted retirement',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-recovery-retirement-'));
  t.after(()=>removeFixtureDirectory(directory));
  const configuration={directory,storeAuthorityCid:cids.authority,capacityBytes:1024*1024,
    maxObjectBytes:65536,maxObjects:100,maxContractNodes:4096,maxContractDepth:64};
  let indexFailures=2,armed=false,removed=false,lost=false;
  const prepare=DatabaseSync.prototype.prepare,exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql){
    const statement=Reflect.apply(prepare,this,[sql]);
    if(sql==='DELETE FROM pending_publications WHERE public_index_cid=?'){
      const run=statement.run;
      t.mock.method(statement,'run',function(...args){const result=Reflect.apply(run,this,args);removed=true;return result;});
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    const result=Reflect.apply(exec,this,[sql]);
    if(armed&&removed&&!lost&&sql==='COMMIT'){
      lost=true;throw Object.assign(new Error('lost same pending retirement reply'),{code:'EIO'});
    }
    return result;
  });
  const store=await openLocalPublicationStore(configuration,contractControl,{
    async syncDirectory(path){
      if(path===join(directory,'indexes')&&indexFailures>0){indexFailures--;throw Object.assign(new Error('index ACK failure'),{code:'EIO'});}
      const fd=await open(path,'r');try{await fd.sync();}finally{await fd.close();}
    },
  });
  const invocationValue=invocation(),request=publicationRequest(resultDefinition(),digest('retired pending Run'));
  const attempt=publicationAttempt(request,'retired pending');
  const prepared=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[prepared.binding.identity]});
  let failure;
  await assert.rejects(commitFixtureIndex(store, wire(entry),prepared.required,prepared.evidence),error=>{failure=error;return error.cleanupHandle?.status().pending===true;});
  for(const name of await readdir(join(directory,'indexes')))await unlink(join(directory,'indexes',name));
  assert.equal((await failure.cleanupHandle.retry()).outcome,'uncommitted');
  await store.appendRecord(wire(publicationRecord(attempt,2,'cancelled',prepared.committing)),{uncommittedConfirmed:true});
  await prepared.prepared.release();armed=true;
  const retired=await store.retireUncommittedPublication(entry.public_index_entry_cid);
  assert.equal(lost,true);assert.equal(retired.cleanup.status().pending,true);
  assert.equal(retired.cleanup.status().errors.at(-1).outcome,'unknown');
  assert.deepEqual(await readdir(join(directory,'metadata-inventories')),[]);
  assert.equal((await retired.cleanup.retry()).pending,false);
  assert.equal(await store.close(),true);
});

function pendingPublicationFixture(directory, inventory) {
  const database=new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try {
    database.exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; BEGIN IMMEDIATE');
    database.prepare('INSERT INTO pending_publications VALUES(?,?)')
      .run(inventory.public_index_entry_cid,JSON.stringify(inventory));
    assert.equal(database.prepare('UPDATE publication_recovery SET entries=entries+1,ack_revision=ack_revision+1 WHERE id=1')
      .run().changes,1);
    database.exec('COMMIT');
  } finally { database.close(); }
}

test('publication recovery transfers its pending original to the durable deletion marker before physical work',async t=>{
  let armed=false,removed=false,lost=false;
  const prepare=DatabaseSync.prototype.prepare,exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql){
    const statement=Reflect.apply(prepare,this,[sql]);
    if(sql==='DELETE FROM pending_publications WHERE public_index_cid=?'){
      const run=statement.run;
      t.mock.method(statement,'run',function(...args){const result=Reflect.apply(run,this,args);removed=true;return result;});
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    const result=Reflect.apply(exec,this,[sql]);
    if(armed&&removed&&!lost&&sql==='COMMIT'){
      lost=true;throw Object.assign(new Error('lost pending deletion transfer reply'),{code:'EIO'});
    }
    return result;
  });
  const setup=await fixture(t),selected=await committedHoldingFixture(setup,'pending deletion transfer');
  // Close the real current completion before modelling an older file-backed
  // interrupted stage. Its edited legacy holding inventory is not a replacement
  // for the current lifetime's retained native completion original.
  await setup.store.close();
  setup.store = await openLocalPublicationStore(setup.configuration, contractControl);
  // Exact retained metadata from the same already-published stage, modelling
  // its still-pending native completion at the deletion transition.
  pendingPublicationFixture(setup.directory,selected.inventory);
  const before=setup.store.status();removed=false;armed=true;
  const retired=await setup.store.retireCommittedPublicationMetadata(indexKeyFor(selected.request),
    '2026-09-18T04:00:00.000Z');
  assert.equal(lost,true);assert.equal(retired.cleanup.status().pending,true);
  assert.equal(retired.cleanup.status().errors.at(-1).outcome,'unknown');
  assert.equal(setup.store.status().storedBytes,before.storedBytes,'no physical object is retired before the original transfer ACK');
  assert.deepEqual(await readFile(selected.inventoryPath,'utf8'),JSON.stringify(selected.inventory));
  assert.equal((await retired.cleanup.retry()).pending,false);
  assert.equal(setup.store.status().storedBytes,0);
  await setup.store.close();
});

test('publication recovery resumes a retiring original without recreating its removed inventory',async t=>{
  const setup=await fixture(t),selected=await committedHoldingFixture(setup,'interrupted pending deletion');
  await setup.store.close();
  const storeUrl=new URL('./publication-store.mjs',import.meta.url).href;
  const controlUrl=new URL('../host-common/publication-contract-control.fixture.mjs',import.meta.url).href;
  const child=await runStoreChild(`
    import{open}from'node:fs/promises';import{join}from'node:path';
    import{openLocalPublicationStore}from${JSON.stringify(storeUrl)};
    import{createPublicationContractControlFixture}from${JSON.stringify(controlUrl)};
    const directory=${JSON.stringify(setup.directory)};let armed=false;
    const store=await openLocalPublicationStore(${JSON.stringify(setup.configuration)},
      createPublicationContractControlFixture(),{async syncDirectory(path){
        const fd=await open(path,'r');try{await fd.sync();}finally{await fd.close();}
        if(armed&&path===join(directory,'metadata-inventories'))process.exit(73);
      }});
    armed=true;await store.retireCommittedPublicationMetadata(
      ${JSON.stringify(indexKeyFor(selected.request))},'2026-09-18T04:00:00.000Z');
  `);
  assert.equal(child.exitCode,73,child.stderr);assert.equal(child.signal,null);
  await assert.rejects(stat(selected.inventoryPath),code('ENOENT'));
  // Model the prior partial native/file transition using only this stopped
  // disposable fixture's same original inventory and durable deletion marker.
  pendingPublicationFixture(setup.directory,selected.inventory);
  const originalLink=fsPromises.link,restorations=[];
  t.mock.method(fsPromises,'link',function(from,to,...args){
    if(String(to)===selected.inventoryPath)restorations.push(String(to));
    return Reflect.apply(originalLink,this,[from,to,...args]);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.deepEqual(restorations,[]);
  assert.equal(await reopened.confirmCommittedIndex(indexKeyFor(selected.request)),undefined);
  assert.equal(reopened.status().storedBytes,0);assert.equal(reopened.status().objectCount,0);
  await reopened.close();
});

test('committed Result opening defers holding proof to the selected publication', async t => {
  const setup = await fixture(t);
  const selected = await committedHoldingFixture(setup, 'selected proof');
  const unrelated = await committedHoldingFixture(setup, 'unrelated proof');
  await setup.store.close();
  const originalOpen = fsPromises.open, reads = [];
  t.mock.method(fsPromises, 'open', function(path, ...args) {
    reads.push(String(path));
    return Reflect.apply(originalOpen, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
  assert.deepEqual(reads.filter(path => path.includes(`${sep}physical-holdings${sep}`)), []);
  // Complete native recovery coverage does not reread committed inventories.
  // Separate payload capacity accounting still walks its own physical objects.
  for (const target of [selected, unrelated]) {
    assert.equal(reads.filter(path => path === target.inventoryPath).length, 0);
  }
  reads.length = 0;
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(selected.request), () => true))
    .public_index_entry_cid, selected.entry.public_index_entry_cid);
  assert.deepEqual(reads.filter(path => path.includes(`${sep}physical-holdings${sep}`)),
    [selected.holdingPath]);
  assert.equal(reads.filter(path => path === selected.inventoryPath).length, 1);
  assert.equal(reads.includes(unrelated.inventoryPath), false);
  await reopened.close();
});

test('committed Result opening does not inspect an unrelated damaged holding', async t => {
  const setup = await fixture(t);
  const selected = await committedHoldingFixture(setup, 'healthy selected');
  const unrelated = await committedHoldingFixture(setup, 'damaged unrelated');
  await setup.store.close();
  const damaged = Buffer.from('{incomplete');
  await writeFile(unrelated.holdingPath, damaged);
  const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
  assert.equal((await reopened.lookupCommittedIndex(indexKeyFor(selected.request), () => true))
    .public_index_entry_cid, selected.entry.public_index_entry_cid);
  await assert.rejects(reopened.lookupCommittedIndex(indexKeyFor(unrelated.request), () => true),
    code('InvalidPublicationPhysicalHoldingStore'));
  assert.deepEqual(await readFile(unrelated.holdingPath), damaged);
  await reopened.close();
});

for (const missing of ['inventory', 'holding']) {
test(`selected committed Result refuses its missing ${missing} before returning the Index`, async t => {
  const setup = await fixture(t);
  const selected = await committedHoldingFixture(setup, `missing ${missing}`);
  await unlink(missing === 'inventory' ? selected.inventoryPath : selected.holdingPath);
  await assert.rejects(setup.store.lookupCommittedIndex(indexKeyFor(selected.request), () => true),
    code('InvalidPublicationMetadataInventoryStore'));
});
}

test('selected committed Result entrypoints reuse only their own current owner links', async t => {
  const setup = await fixture(t);
  const selected = await committedHoldingFixture(setup, 'current entrypoint');
  await setup.store.putPublicationContract('result_definition', wire(resultDefinition()));
  const key = indexKeyFor(selected.request);
  const operations = [
    () => setup.store.inspectCommittedIndex(key),
    () => setup.store.confirmCommittedIndex(key),
    () => setup.store.readCommittedResultDescriptionEvidence(
      key, selected.request.inventory[0].result_definition_cid),
  ];
  const originalOpen = fsPromises.open, reads = [];
  t.mock.method(fsPromises, 'open', function(path, ...args) {
    reads.push(String(path));
    return Reflect.apply(originalOpen, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  for (const operation of operations) {
    reads.length = 0;
    await operation();
    assert.equal(reads.filter(path => path === selected.inventoryPath).length, 1);
    assert.equal(reads.filter(path => path === selected.holdingPath).length, 1);
  }
  await unlink(selected.holdingPath);
  for (const operation of operations) {
    await assert.rejects(operation(), code('InvalidPublicationMetadataInventoryStore'));
  }
});

test('selected committed Result refuses foreign inventory identity and tuple without rewriting it', async t => {
  const setup = await fixture(t);
  const selected = await committedHoldingFixture(setup, 'inventory identity');
  const unrelated = await committedHoldingFixture(setup, 'foreign inventory identity');
  for (const value of [unrelated.inventory,
    {...selected.inventory, namespace_id: 'different-namespace'},
    {...selected.inventory, authority_scope_cid: digest('foreign scope')},
    {...selected.inventory, run_definition_cid: digest('foreign Run')},
    {...selected.inventory, publication_attempt_cid: digest('foreign publication attempt')}]) {
    const bytes = Buffer.from(JSON.stringify(value));
    await writeFile(selected.inventoryPath, bytes);
    await assert.rejects(setup.store.lookupCommittedIndex(indexKeyFor(selected.request), () => true),
      code('InvalidPublicationMetadataInventoryStore'));
    assert.deepEqual(await readFile(selected.inventoryPath), bytes);
  }
  await writeFile(selected.inventoryPath, JSON.stringify(selected.inventory));
});

function physicalHolding(holdingCid, manifestCid, objects,
  namespace = 'remote-transfer') {
  return Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace,
    holding_cid: holdingCid,
    manifest_cid: manifestCid,
    objects: Object.freeze(objects.map(object => Object.freeze({...object}))),
  });
}

test('ordinary Store opening does not enumerate or stat committed physical holding history', async t => {
  const setup=await fixture(t),holdings=[];
  for(let i=0;i<12;i++){
    const payload=await preparePhysical(setup.store,`history ${i}`);
    const holding=physicalHolding(digest(`history holding ${i}`),digest(`history manifest ${i}`),
      [{cid:payload.cid,byte_count:payload.bytes}]);
    await setup.store.commitPhysicalHolding(holding,[payload.prepared]);holdings.push(holding);
  }
  await setup.store.close();
  const directory=join(setup.directory,'physical-holdings');
  const originalReaddir=fsPromises.readdir,originalLstat=fsPromises.lstat,originalOpen=fsPromises.open;
  let enumerations=0;const stats=[],reads=[];
  t.mock.method(fsPromises,'readdir',function(path,...args){
    if(String(path)===directory)enumerations++;
    return Reflect.apply(originalReaddir,this,[path,...args]);
  });
  t.mock.method(fsPromises,'lstat',function(path,...args){
    if(String(path).startsWith(directory+sep))stats.push(String(path));
    return Reflect.apply(originalLstat,this,[path,...args]);
  });
  t.mock.method(fsPromises,'open',function(path,...args){
    if(String(path).startsWith(directory+sep))reads.push(String(path));
    return Reflect.apply(originalOpen,this,[path,...args]);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.deepEqual({enumerations,stats,reads},{enumerations:0,stats:[],reads:[]});
  const selected=holdings[7];
  assert.deepEqual(await reopened.inspectPhysicalHolding(selected.holding_cid),selected);
  const selectedPath=join(directory,selected.holding_cid.slice(7)+'.json');
  assert.deepEqual(reads,[selectedPath]);
  assert.equal(enumerations,0);
  assert(stats.length>0&&stats.every(path=>path===selectedPath),
    'the selected original retains its real path-generation checks, not an unrelated history walk');
  const chunks=[];await reopened.consumePhysicalHolding(selected.holding_cid,0,chunk=>chunks.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(chunks).toString(),'history 7');
  assert.equal(reopened.status().objectCount,12);
  await reopened.close();
});

for(const type of ['directory','symlink']) {
test(`ordinary Store opening defers an unrelated holding ${type} but refuses its selected FD`,async t=>{
  const setup=await fixture(t);
  const payload=await preparePhysical(setup.store,'selected intact generation');
  const holding=physicalHolding(digest('opening selected intact'),digest('opening selected manifest'),
    [{cid:payload.cid,byte_count:payload.bytes}]);
  await setup.store.commitPhysicalHolding(holding,[payload.prepared]);await setup.store.close();
  const invalidCid=digest(`unrelated ${type}`),target=join(setup.directory,'physical-holdings',invalidCid.slice(7)+'.json');
  if(type==='directory')await mkdir(target);
  else await fsPromises.symlink(join(setup.directory,'physical-holdings',holding.holding_cid.slice(7)+'.json'),target);
  const reopened=await openLocalPublicationStore(setup.configuration,contractControl);
  assert.deepEqual(await reopened.inspectPhysicalHolding(holding.holding_cid),holding);
  await assert.rejects(reopened.inspectPhysicalHolding(invalidCid),
    error=>type==='directory'?error.code==='InvalidPublicationStoreObject':error.code==='ELOOP');
  const state=await fsPromises.lstat(target);
  assert.equal(type==='directory'?state.isDirectory():state.isSymbolicLink(),true);
  assert.equal(reopened.status().objectCount,1);
  await reopened.close();
});
}

test('ordinary Store reopen reads no unrelated immutable physical holding bodies', async t => {
  const setup = await fixture(t);
  const holdings = [];
  for (const name of ['selected', 'unrelated']) {
    const payload = await preparePhysical(setup.store, `rows ${name}`);
    const holding = physicalHolding(digest(`open holding ${name}`),
      digest(`open artifact ${name}`),
      [{cid: payload.cid, byte_count: payload.bytes}], 'effect-source');
    await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
    holdings.push(holding);
  }
  await setup.store.close();
  const originalOpen = fsPromises.open;
  const reads = [];
  fsPromises.open = function(path, ...arguments_) {
    if (String(path).startsWith(join(setup.directory, 'physical-holdings') + sep)) {
      reads.push(String(path));
    }
    return Reflect.apply(originalOpen, this, [path, ...arguments_]);
  };
  syncBuiltinESMExports();
  try {
    const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
    assert.deepEqual(reads, [], 'ordinary startup does not admit unrelated immutable bodies');
    assert.deepEqual(await reopened.inspectPhysicalHolding(holdings[0].holding_cid), holdings[0]);
    assert.deepEqual(reads, [join(setup.directory, 'physical-holdings',
      `${holdings[0].holding_cid.slice(7)}.json`)]);
    await reopened.close();
  } finally {
    fsPromises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('ordinary Store reopen defers unrelated damaged holding refusal to its selected read', async t => {
  const setup = await fixture(t);
  const payload = await preparePhysical(setup.store, 'selected rows');
  const holding = physicalHolding(digest('selected intact holding'),
    digest('selected intact artifact'), [{cid: payload.cid, byte_count: payload.bytes}],
    'effect-source');
  await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
  await setup.store.close();
  const damagedCid = digest('unrelated damaged holding');
  const damagedPath = join(setup.directory, 'physical-holdings', `${damagedCid.slice(7)}.json`);
  const damagedBytes = Buffer.from('{incomplete');
  await writeFile(damagedPath, damagedBytes);
  const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
  const rows = [];
  await reopened.consumePhysicalHolding(holding.holding_cid, 0,
    chunk => rows.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(rows).toString('utf8'), 'selected rows');
  await assert.rejects(reopened.inspectPhysicalHolding(damagedCid),
    code('InvalidPublicationPhysicalHoldingStore'));
  assert.deepEqual(await readFile(damagedPath), damagedBytes,
    'target refusal preserves the original invalid record rather than repairing it');
  await reopened.close();
});

test('ordinary Store selected holding refuses a different valid record under its name', async t => {
  const setup = await fixture(t);
  const payload = await preparePhysical(setup.store, 'original named holding');
  const holding = physicalHolding(digest('original named holding'),
    digest('original named artifact'), [{cid: payload.cid, byte_count: payload.bytes}],
    'effect-source');
  await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
  await setup.store.close();
  const foreignCid = digest('different selected holding');
  const foreignPath = join(setup.directory, 'physical-holdings', `${foreignCid.slice(7)}.json`);
  const original = Buffer.from(JSON.stringify(holding));
  await writeFile(foreignPath, original);
  const reopened = await openLocalPublicationStore(setup.configuration, contractControl);
  await assert.rejects(reopened.inspectPhysicalHolding(foreignCid),
    code('InvalidPublicationPhysicalHoldingStore'));
  assert.deepEqual(await reopened.inspectPhysicalHolding(holding.holding_cid), holding);
  assert.deepEqual(await readFile(foreignPath), original);
  await reopened.close();
});

test('ordinary Store pending holding recovery still refuses a foreign deletion record', async t => {
  const setup = await fixture(t);
  await setup.store.close();
  const requestedCid = digest('pending deletion name');
  const original = Buffer.from(JSON.stringify(physicalHolding(
    digest('foreign pending deletion'), digest('foreign pending artifact'), [])));
  const path = join(setup.directory, 'physical-holding-deletions', `${requestedCid.slice(7)}.json`);
  await writeFile(path, original);
  await assert.rejects(openLocalPublicationStore(setup.configuration, contractControl),
    code('InvalidPublicationPhysicalHoldingStore'));
  assert.deepEqual(await readFile(path), original);
  await assert.rejects(stat(join(setup.directory, 'owner')), code('ENOENT'),
    'failed recovery closes its native database and releases the original owner');
});

for (const damage of ['missing', 'corrupt']) {
test(`one ${damage} Effect payload does not disable unrelated holdings`,
  async t => {
    const setup = await fixture(t);
    const holdings = [];
    for (const value of ['healthy input', 'damaged input']) {
      const payload = await preparePhysical(setup.store, value);
      const holding = physicalHolding(digest(`holding ${value}`),
        digest(`artifact ${value}`),
        [{cid: payload.cid, byte_count: payload.bytes}], 'effect-source');
      await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
      holdings.push(holding);
    }
    await setup.store.close();
    const damagedPath = join(setup.directory, 'objects',
      holdings[1].objects[0].cid.slice('sha256:'.length));
    if (damage === 'missing') await unlink(damagedPath);
    else await writeFile(damagedPath, 'Damaged input');
    const reopened = await openLocalPublicationStore(setup.configuration,
      contractControl);
    t.after(() => reopened.close());
    const chunks = [];
    await reopened.consumePhysicalHolding(holdings[0].holding_cid, 0,
      chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString(), 'healthy input');
    const expected = damage === 'missing'
      ? 'PublicationObjectMissing' : 'PublicationObjectCorrupt';
    await assert.rejects(reopened.inspectPhysicalHolding(
      holdings[1].holding_cid), code(expected));
    await assert.rejects(reopened.consumePhysicalHolding(
      holdings[1].holding_cid, 0, () => assert.fail('corrupt bytes exposed')),
    code(expected));
    // Unavailable input is not a reason to discard its recovery evidence.
    assert.deepEqual(JSON.parse(await readFile(join(setup.directory,
      'physical-holdings', `${holdings[1].holding_cid.slice(7)}.json`))),
    holdings[1]);
  });
}

test('Effect source and other physical holdings release independently',
  async t => {
    const setup = await fixture(t);
    const source = await preparePhysical(setup.store, 'source rows');
    const sourceHolding = physicalHolding(
      digest('effect source holding'), digest('effect source artifact'),
      [{cid: source.cid, byte_count: source.bytes}], 'effect-source');
    await setup.store.commitPhysicalHolding(sourceHolding,
      [source.prepared]);
    const otherHolding = physicalHolding(
      digest('other holding'), sourceHolding.manifest_cid,
      sourceHolding.objects);
    await setup.store.sharePhysicalHolding(sourceHolding.holding_cid,
      otherHolding);
    assert.equal(setup.store.status().storedBytes, source.bytes);
    await setup.store.close();
    const reopened = await openLocalPublicationStore(setup.configuration,
      contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      sourceHolding.holding_cid), sourceHolding);
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      otherHolding.holding_cid), otherHolding);
    assert.equal((await reopened.retirePhysicalHolding(
      sourceHolding.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, source.bytes);
    const chunks = [];
    await reopened.consumePhysicalHolding(otherHolding.holding_cid,
      0, chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'source rows');
    assert.equal((await reopened.retirePhysicalHolding(
      otherHolding.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, 0);
  });

test('capture holding borrows an exact allocation across manifest scopes',
  async t => {
    const setup = await fixture(t);
    const shared = await preparePhysical(setup.store, 'shared rows');
    const unique = await preparePhysical(setup.store, 'private output');
    const source = physicalHolding(
      digest('source custody'), digest('source manifest'),
      [{cid: shared.cid, byte_count: shared.bytes}], 'effect-source');
    await setup.store.commitPhysicalHolding(source, [shared.prepared]);
    const capture = physicalHolding(
      digest('capture custody'), digest('captured Run'), [
        {cid: shared.cid, byte_count: shared.bytes},
        {cid: unique.cid, byte_count: unique.bytes},
      ], 'effect-capture');
    await assert.rejects(setup.store.commitPhysicalHolding(
      capture, [shared.prepared, unique.prepared],
    ), code('InvalidPublicationPhysicalHoldingOwner'));
    await setup.store.commitPhysicalHolding(
      capture, [shared.prepared, unique.prepared], [source.holding_cid]);
    assert.equal(unique.prepared.status().pending, false);
    assert.equal((await setup.store.retirePhysicalHolding(
      source.holding_cid)).deleted, true);
    assert.equal(setup.store.status().storedBytes,
      shared.bytes + unique.bytes);
    const foreign = physicalHolding(
      digest('foreign capture custody'), digest('foreign captured Run'),
      [{cid: shared.cid, byte_count: shared.bytes}], 'effect-capture');
    await assert.rejects(setup.store.commitPhysicalHolding(
      foreign, [], [source.holding_cid],
    ), code('PublicationPhysicalHoldingUnavailable'));
    assert.equal(await setup.store.inspectPhysicalHolding(
      foreign.holding_cid), undefined);
    await setup.store.close();

    const reopened = await openLocalPublicationStore(
      setup.configuration, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      capture.holding_cid), capture);
    for (const [index, expected] of ['shared rows', 'private output']
      .entries()) {
      const chunks = [];
      await reopened.consumePhysicalHolding(capture.holding_cid, index,
        chunk => chunks.push(Buffer.from(chunk)));
      assert.equal(Buffer.concat(chunks).toString('utf8'), expected);
    }
    assert.equal((await reopened.retirePhysicalHolding(
      capture.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

async function captureCustodyFixture(t) {
  // This existing fixed Run is an explicit admission port, not a Common issuer.
  const run = Object.freeze({...captureCustodyRunFixture,
    identityField: 'run_definition_cid'});
  let runAdmissions = 0;
  const control = Object.freeze({...contractControl, admit(name, wire, limits) {
    if (name !== 'run_definition') return contractControl.admit(name, wire, limits);
    runAdmissions++;
    assert.equal(wire, run.wire);
    return run;
  }});
  const setup = await fixture(t, {}, control);
  const holding = physicalHolding(digest('capture durability source'),
    digest('capture durability artifact'), [], 'effect-source');
  const path = join(setup.directory, 'effect-capture-custody',
    `${run.identity.slice(7)}.json`);
  const originalOpen = fsPromises.open;
  const calls = {writes: 0, fileSyncs: 0, directorySyncs: 0};
  let rejectNextDirectorySync = false;
  t.mock.method(fsPromises, 'open', async function(selected, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [selected, ...args]);
    const staging = String(selected).startsWith(join(setup.directory, 'staging') + sep);
    if (staging) {
      const write = handle.write;
      handle.write = async function(...args) {
        calls.writes++;
        return Reflect.apply(write, this, args);
      };
    }
    if (staging || String(selected) === join(setup.directory, 'effect-capture-custody')) {
      const sync = handle.sync;
      handle.sync = async function(...args) {
        const result = await Reflect.apply(sync, this, args);
        if (staging) calls.fileSyncs++;
        else {
          calls.directorySyncs++;
          if (rejectNextDirectorySync) {
            rejectNextDirectorySync = false;
            throw Object.assign(new Error('CaptureCustodySyncReplyLost'), {code: 'EIO'});
          }
        }
        return result;
      };
    }
    return handle;
  });
  syncBuiltinESMExports();
  t.after(() => {t.mock.restoreAll(); syncBuiltinESMExports();});
  return {...setup, control, run, holding, path, calls,
    get runAdmissions() {return runAdmissions;},
    reset() {for (const key of Object.keys(calls)) calls[key] = 0; runAdmissions = 0;},
    rejectDirectorySync() {rejectNextDirectorySync = true;}};
}

test('unchanged acknowledged Effect capture custody performs no repeated physical write', async t => {
  const f = await captureCustodyFixture(t);
  await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  assert.equal(f.runAdmissions, 1);
  assert.deepEqual(f.calls, {writes: 1, fileSyncs: 1, directorySyncs: 1});
  const original = await stat(f.path);
  f.reset();
  await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  assert.equal(f.runAdmissions, 1);
  assert.deepEqual(f.calls, {writes: 0, fileSyncs: 0, directorySyncs: 0});
  const current = await stat(f.path);
  assert.equal(current.dev, original.dev);
  assert.equal(current.ino, original.ino);
  assert.deepEqual((await f.store.readEffectCaptureCustody(f.run)).holdings, [f.holding]);
});

test('Effect capture custody never reuses failed acknowledgement or a replacement file', async t => {
  const f = await captureCustodyFixture(t);
  f.rejectDirectorySync();
  await assert.rejects(f.store.retainEffectCaptureCustody(f.run, [f.holding]), {code: 'EIO'});
  f.reset();
  await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  assert.deepEqual(f.calls, {writes: 1, fileSyncs: 1, directorySyncs: 1});
  const bytes = await readFile(f.path);
  const predecessor = await open(f.path, 'r');
  try {
    await unlink(f.path);
    await writeFile(f.path, bytes);
    assert.notEqual((await stat(f.path)).ino, (await predecessor.stat()).ino);
    f.reset();
    await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
    assert.deepEqual(f.calls, {writes: 1, fileSyncs: 1, directorySyncs: 1});
  } finally {await predecessor.close();}
  await writeFile(f.path, '{');
  f.reset();
  await assert.rejects(f.store.retainEffectCaptureCustody(f.run, [f.holding]),
    {code: 'InvalidEffectCaptureCustody'});
  assert.deepEqual(f.calls, {writes: 0, fileSyncs: 0, directorySyncs: 0});
});

test('Effect capture custody changes and a fresh Store retain real durability', async t => {
  const f = await captureCustodyFixture(t);
  await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  const capture = physicalHolding(digest('capture durability output'),
    digest('capture durability Run'), [], 'effect-capture');
  f.reset();
  await f.store.retainEffectCaptureCustody(f.run, [f.holding, capture]);
  assert.deepEqual(f.calls, {writes: 1, fileSyncs: 1, directorySyncs: 1});
  await assert.rejects(f.store.retainEffectCaptureCustody(f.run,
    [{...f.holding, manifest_cid: digest('conflicting capture manifest')}]),
  {code: 'EffectCaptureCustodyConflict'});
  await f.store.close();
  const reopened = await openLocalPublicationStore(f.configuration, f.control);
  f.reset();
  await reopened.retainEffectCaptureCustody(f.run, [f.holding, capture]);
  assert.deepEqual(f.calls, {writes: 1, fileSyncs: 1, directorySyncs: 1});
  assert.deepEqual((await reopened.readEffectCaptureCustody(f.run)).holdings,
    [f.holding, capture]);
  f.reset();
  await reopened.retireEffectCaptureCustody(f.run);
  assert.equal(f.runAdmissions, 1);
  assert.deepEqual(f.calls, {writes: 0, fileSyncs: 0, directorySyncs: 1});
  await reopened.close();
});

test('queued Effect capture custody refuses after the same Store closes', async t => {
  const f = await captureCustodyFixture(t);
  const originalOpen = fsPromises.open;
  let entered, release;
  const enteredRead = new Promise(resolve => {entered = resolve;});
  const blockedRead = new Promise(resolve => {release = resolve;});
  const primary = Object.assign(new Error('OriginalCaptureReadStopped'), {code: 'EIO'});
  let intercepted = false;
  t.mock.method(fsPromises, 'open', async function(selected, ...args) {
    if (!intercepted && String(selected) === f.path) {
      intercepted = true;
      entered();
      await blockedRead;
      throw primary; // No original FD was acquired by this test-owned read.
    }
    return Reflect.apply(originalOpen, this, [selected, ...args]);
  });
  syncBuiltinESMExports();
  const first = f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  const firstResult = first.then(value => ({value}), error => ({error}));
  await enteredRead;
  const queued = f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  const queuedResult = queued.then(value => ({value}), error => ({error}));
  try {
    await f.store.close();
    assert.equal(f.store.status().closed, true);
  } finally {release();}
  assert.strictEqual((await firstResult).error, primary);
  assert.equal((await queuedResult).error?.code, 'PublicationStoreClosed');
  assert.equal(f.runAdmissions, 2, 'one admission per original public operation');
  assert.deepEqual(f.calls, {writes: 0, fileSyncs: 0, directorySyncs: 0});
  await assert.rejects(readFile(f.path), {code: 'ENOENT'});
});

test('Effect capture retirement refuses final unlink after the same Store closes', async t => {
  const f = await captureCustodyFixture(t);
  await f.store.retainEffectCaptureCustody(f.run, [f.holding]);
  const original = await readFile(f.path), state = await stat(f.path);
  const originalOpen = fsPromises.open;
  const holdingPath = join(f.directory, 'physical-holdings',
    `${f.holding.holding_cid.slice(7)}.json`);
  let holdingReads = 0, closedDuringRetirement = false;
  t.mock.method(fsPromises, 'open', async function(selected, ...args) {
    // The first read validates the custody inventory. The second belongs to
    // actual holding retirement; absence means this holding already retired,
    // not that the capture's later unlink may ignore Store lifetime.
    if (String(selected) === holdingPath && ++holdingReads === 2) {
      await f.store.close();
      closedDuringRetirement = true;
    }
    return Reflect.apply(originalOpen, this, [selected, ...args]);
  });
  syncBuiltinESMExports();
  f.reset();
  await assert.rejects(f.store.retireEffectCaptureCustody(f.run),
    {code: 'PublicationStoreClosed'});
  assert.equal(closedDuringRetirement, true);
  assert.equal(f.store.status().closed, true);
  assert.equal(f.runAdmissions, 1);
  assert.deepEqual(f.calls, {writes: 0, fileSyncs: 0, directorySyncs: 0});
  assert.deepEqual(await readFile(f.path), original);
  const retained = await stat(f.path);
  assert.equal(retained.dev, state.dev);
  assert.equal(retained.ino, state.ino);
});

async function preparePhysical(store, value) {
  const bytes = Buffer.from(value, 'utf8');
  const writer = store.createPreparedObjectWriter(bytes.byteLength);
  await writer.append(bytes);
  return await writer.seal(digest(bytes));
}

test('Content physical custody preserves exact generated bytes across a new process',
  async t => {
    const setup = await fixture(t);
    // Independent common-generation vector. This Store test validates physical
    // custody, not public SERIALIZE or ReferenceIssuer admission.
    const expected = '{"id":2}\n{"id":1}\n';
    const expectedCid =
      'sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60';
    const writer = setup.store.createPreparedObjectWriter(18);
    for (const piece of ['{"id":', '2}\n', '{"id":1}', '\n']) {
      await writer.append(piece);
    }
    const prepared = await writer.seal(expectedCid);
    assert.equal(prepared.bytes, 18);
    const holding = physicalHolding(digest('Content holding fixture'),
      digest('Content Ref candidate fixture'),
      [{cid: prepared.cid, byte_count: prepared.bytes}], 'content');
    await setup.store.commitPhysicalHolding(holding, [prepared.prepared]);
    assert.equal(prepared.prepared.status().pending, false);
    await setup.store.close();
    const child = await runStoreChild(`
      import {openLocalPublicationStore} from
        ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
      const store = await openLocalPublicationStore(
        ${JSON.stringify(setup.configuration)},
        createPublicationContractControlFixture());
      const holding = await store.inspectPhysicalHolding(${JSON.stringify(holding.holding_cid)});
      const chunks = [];
      await store.consumePhysicalHolding(holding.holding_cid, 0,
        chunk => chunks.push(Buffer.from(chunk)));
      console.log(JSON.stringify({holding, bytes: Buffer.concat(chunks).toString('utf8')}));
      await store.close();
    `);
    assert.equal(child.exitCode, 0, child.stderr);
    assert.equal(child.signal, null);
    assert.deepEqual(JSON.parse(child.stdout), {holding, bytes: expected});
    const reopened = await openLocalPublicationStore(setup.configuration,
      contractControl);
    t.after(() => reopened.close());
    await reopened.retirePhysicalHolding(holding.holding_cid);
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

test('Content holdings share bytes without merging their custody or extending retention',
  async t => {
    const setup = await fixture(t);
    const prepared = await preparePhysical(setup.store, '');
    assert.equal(prepared.cid,
      'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    const first = physicalHolding(digest('Content scope one'),
      digest('Content reference one'), [{cid: prepared.cid, byte_count: 0}],
      'content');
    await setup.store.commitPhysicalHolding(first, [prepared.prepared]);
    // Equal bytes alone do not authorize sharePhysicalHolding. The existing
    // Store requires the exact source holding and its manifest binding.
    const incompatible = physicalHolding(digest('Content scope two'),
      digest('Content reference two'), first.objects, 'content');
    await assert.rejects(setup.store.sharePhysicalHolding(first.holding_cid,
      incompatible), code('PublicationPhysicalHoldingConflict'));
    const second = physicalHolding(digest('Content second occurrence'),
      first.manifest_cid, first.objects, 'content');
    await setup.store.sharePhysicalHolding(first.holding_cid, second);
    await setup.store.retirePhysicalHolding(first.holding_cid);
    assert.equal(setup.store.status().objectCount, 1);
    const chunks = [];
    await setup.store.consumePhysicalHolding(second.holding_cid, 0,
      chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).byteLength, 0);
    await setup.store.retirePhysicalHolding(second.holding_cid);
    assert.equal(setup.store.status().objectCount, 0);
    assert.equal(setup.store.status().reservedBytes, 0);
  });

test('physical Transfer holding survives reopen and reclaims exact objects',
  async t => {
    const setup = await fixture(t);
    const values = ['alpha', '日本語'];
    const prepared = [];
    for (const value of values) {
      prepared.push(await preparePhysical(setup.store, value));
    }
    const holdingCid = digest('transfer holding a');
    const record = physicalHolding(
      holdingCid,
      digest('physical manifest a'),
      prepared.map(object => ({cid: object.cid, byte_count: object.bytes})),
    );
    const committed = await setup.store.commitPhysicalHolding(
      record,
      prepared.map(object => object.prepared),
    );
    assert.equal(committed.created, true);
    assert.equal(setup.store.status().storedBytes, 14);
    assert.equal(setup.store.status().objectCount, 2);
    assert.equal(prepared.every(object =>
      object.prepared.status().pending === false), true);

    await setup.store.close();
    const reopened = await openLocalPublicationStore(
      setup.configuration,
      contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(holdingCid), record);
    const received = [];
    for (let index = 0; index < values.length; index++) {
      const chunks = [];
      await reopened.consumePhysicalHolding(
        holdingCid,
        index,
        chunk => chunks.push(Buffer.from(chunk)),
      );
      received.push(Buffer.concat(chunks).toString('utf8'));
    }
    assert.deepEqual(received, values);
    const retired = await reopened.retirePhysicalHolding(holdingCid);
    assert.equal(retired.deleted, true);
    assert.equal(retired.cleanup.status().pending, false);
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

for (const namespace of ['remote-transfer', 'content']) {
test(`visible physical holdings retry directory durability before success (${namespace})`,
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-holding-commit-durability-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 512,
      maxObjects: 8,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let failHoldingSync = false;
    let holdingSyncs = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'physical-holdings')) {
          holdingSyncs++;
          if (failHoldingSync) {
            failHoldingSync = false;
            const error = new Error('injected holding sync failure');
            error.code = 'EIO';
            throw error;
          }
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const prepared = await preparePhysical(store, 'durable');
    const source = physicalHolding(
      digest('holding retry source'), digest('holding retry manifest'),
      [{cid: prepared.cid, byte_count: prepared.bytes}], namespace,
    );
    const initialSyncs = holdingSyncs;
    failHoldingSync = true;
    await assert.rejects(store.commitPhysicalHolding(
      source, [prepared.prepared],
    ), code('EIO'));
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(holdingSyncs, initialSyncs + 1);
    assert.equal((await store.commitPhysicalHolding(
      source, [prepared.prepared],
    )).created, false);
    assert.equal(holdingSyncs, initialSyncs + 2);
    assert.equal(prepared.prepared.status().pending, false);

    const shared = physicalHolding(
      digest('holding retry shared'), source.manifest_cid, source.objects,
      namespace,
    );
    failHoldingSync = true;
    await assert.rejects(store.sharePhysicalHolding(
      source.holding_cid, shared,
    ), code('EIO'));
    assert.equal(holdingSyncs, initialSyncs + 3);
    assert.equal((await store.sharePhysicalHolding(
      source.holding_cid, shared,
    )).created, false);
    assert.equal(holdingSyncs, initialSyncs + 4);
    assert.equal((await store.retirePhysicalHolding(
      source.holding_cid,
    )).deleted, true);
    assert.equal((await store.retirePhysicalHolding(
      shared.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });
}

test('independent Transfer holdings share bytes but release independently',
  async t => {
    const {store} = await fixture(t);
    const first = await preparePhysical(store, 'shared');
    const firstRecord = physicalHolding(
      digest('transfer holding first'),
      digest('physical manifest shared'),
      [{cid: first.cid, byte_count: first.bytes}],
    );
    await store.commitPhysicalHolding(firstRecord, [first.prepared]);

    const second = await preparePhysical(store, 'shared');
    const secondRecord = physicalHolding(
      digest('transfer holding second'),
      digest('physical manifest shared'),
      [{cid: second.cid, byte_count: second.bytes}],
    );
    await store.commitPhysicalHolding(secondRecord, [second.prepared]);
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().objectCount, 1);

    assert.equal((await store.retirePhysicalHolding(
      firstRecord.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 6);
    const chunks = [];
    await store.consumePhysicalHolding(
      secondRecord.holding_cid,
      0,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'shared');
    assert.equal((await store.retirePhysicalHolding(
      secondRecord.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
  });

test('sealed Transfer holding is reused without uploading source again',
  async t => {
    const {store} = await fixture(t);
    const prepared = await preparePhysical(store, 'sealed');
    const source = physicalHolding(
      digest('sealed source holding'),
      digest('sealed manifest'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(source, [prepared.prepared]);
    const destination = physicalHolding(
      digest('sealed destination holding'),
      source.manifest_cid,
      source.objects,
    );
    assert.deepEqual(await store.sharePhysicalHolding(
      source.holding_cid,
      destination,
    ), {record: destination, created: true});
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().objectCount, 1);

    assert.equal((await store.retirePhysicalHolding(
      source.holding_cid,
    )).deleted, true);
    const chunks = [];
    await store.consumePhysicalHolding(
      destination.holding_cid,
      0,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'sealed');
    assert.equal((await store.retirePhysicalHolding(
      destination.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });

test('sealed Transfer reuse rejects a different manifest or object order',
  async t => {
    const {store} = await fixture(t);
    const first = await preparePhysical(store, 'first');
    const second = await preparePhysical(store, 'second');
    const source = physicalHolding(
      digest('ordered source holding'),
      digest('ordered source manifest'),
      [
        {cid: first.cid, byte_count: first.bytes},
        {cid: second.cid, byte_count: second.bytes},
      ],
    );
    await store.commitPhysicalHolding(
      source,
      [first.prepared, second.prepared],
    );
    const differentManifest = physicalHolding(
      digest('different manifest holding'),
      digest('different manifest'),
      source.objects,
    );
    await assert.rejects(
      store.sharePhysicalHolding(source.holding_cid, differentManifest),
      {code: 'PublicationPhysicalHoldingConflict'},
    );
    const reordered = physicalHolding(
      digest('reordered holding'),
      source.manifest_cid,
      [...source.objects].reverse(),
    );
    await assert.rejects(
      store.sharePhysicalHolding(source.holding_cid, reordered),
      {code: 'PublicationPhysicalHoldingConflict'},
    );
    assert.equal(await store.inspectPhysicalHolding(
      differentManifest.holding_cid,
    ), undefined);
    assert.equal(await store.inspectPhysicalHolding(reordered.holding_cid),
      undefined);
  });

test('physical holding retirement waits for the exact active reader',
  async t => {
    const {store} = await fixture(t);
    const prepared = await preparePhysical(store, 'reader');
    const record = physicalHolding(
      digest('transfer holding reader'),
      digest('physical manifest reader'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(record, [prepared.prepared]);
    let continueRead;
    const blocked = new Promise(resolve => { continueRead = resolve; });
    let reading;
    const started = new Promise(resolve => { reading = resolve; });
    const consume = store.consumePhysicalHolding(
      record.holding_cid,
      0,
      async () => {
        reading();
        await blocked;
      },
    );
    await started;
    const retiring = await store.retirePhysicalHolding(record.holding_cid);
    assert.equal(retiring.deleted, false);
    assert.equal(retiring.cleanup.status().pending, true);
    assert.equal(await store.inspectPhysicalHolding(record.holding_cid),
      undefined);
    continueRead();
    await consume;
    assert.equal((await retiring.cleanup.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
  });

for (const interruption of ['failed ACK', 'replacement during ACK']) {
test(`missing prior-lifetime holding retains capacity on ${interruption}`, async t => {
  let failObjectSync = false;
  const {store, configuration, directory} = await fixture(t);
  const prepared = await preparePhysical(store, 'missing');
  const record = physicalHolding(digest('missing prior holding'), digest('missing prior manifest'),
    [{cid: prepared.cid, byte_count: prepared.bytes}]);
  await store.commitPhysicalHolding(record, [prepared.prepared]);
  await store.close();
  await unlink(join(directory, 'objects', prepared.cid.slice(7)));
  const reopened = await openLocalPublicationStore(configuration, contractControl, {
    async syncDirectory(path) {
      if (failObjectSync && path === join(directory, 'objects')) {
        failObjectSync = false;
        if (interruption === 'failed ACK') {
          throw Object.assign(new Error('original missing-object directory ACK unavailable'), {code: 'EIO'});
        }
        await writeFile(join(path,prepared.cid.slice(7)), 'foreign replacement');
      }
      const handle = await open(path, 'r');
      try {await handle.sync();} finally {await handle.close();}
    },
  });
  await assert.rejects(reopened.inspectPhysicalHolding(record.holding_cid), code('PublicationObjectMissing'));
  const unrelated = await reopened.putBytes(Buffer.from('current healthy object'));
  const before = reopened.status();
  failObjectSync = true;
  const retired = await reopened.retirePhysicalHolding(record.holding_cid);
  assert.equal(retired.deleted, false);
  assert.equal(retired.cleanup.status().pending, true);
  assert.equal(reopened.status().storedBytes, before.storedBytes,
    'an absent pathname alone cannot refund its indexed original');
  if (interruption === 'replacement during ACK') {
    assert.equal(retired.cleanup.status().errors.at(-1).code, 'PublicationObjectAccountingMismatch');
    assert.equal(await readFile(join(directory,'objects',prepared.cid.slice(7)), 'utf8'), 'foreign replacement');
    await unlink(join(directory,'objects',prepared.cid.slice(7)));
  }
  assert.equal((await retired.cleanup.retry()).pending, false);
  assert.equal(reopened.status().storedBytes, unrelated.bytes);
  assert.equal(reopened.status().objectCount, 1);
  await reopened.close();
  assert.deepEqual(await readFile(join(directory, 'objects', unrelated.cid.slice(7))), Buffer.from('current healthy object'));
});
}

test('missing current-lifetime holding retains its original charge until the original allocation returns', async t => {
  const {store, directory} = await fixture(t);
  const prepared = await preparePhysical(store, 'current');
  const record = physicalHolding(digest('missing current holding'), digest('missing current manifest'),
    [{cid: prepared.cid, byte_count: prepared.bytes}]);
  await store.commitPhysicalHolding(record, [prepared.prepared]);
  const path = join(directory, 'objects', prepared.cid.slice(7));
  const retained = join(directory, 'original-current-allocation');
  await link(path, retained);
  await unlink(path);
  const before = store.status();
  const retired = await store.retirePhysicalHolding(record.holding_cid);
  assert.equal(retired.deleted, false);
  assert.equal(retired.cleanup.status().pending, true);
  assert.equal(store.status().storedBytes, before.storedBytes);
  assert.equal(retired.cleanup.status().errors.at(-1).code, 'PublicationObjectAccountingMismatch');
  await link(retained, path);
  await unlink(retained);
  assert.equal((await retired.cleanup.retry()).pending, false);
  assert.equal(store.status().storedBytes, 0);
});

test('physical holding retains capacity until unlink durability retry',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-transfer-holding-durability-',
    ));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 512,
      maxObjects: 8,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let objectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'objects') && objectSyncFailures > 0) {
          objectSyncFailures--;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration,
      contractControl,
      durability,
    );
    t.after(async () => { await store.close(); });
    const prepared = await preparePhysical(store, 'durable');
    const record = physicalHolding(
      digest('transfer holding durability'),
      digest('physical manifest durability'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(record, [prepared.prepared]);
    objectSyncFailures = 1;
    const retired = await store.retirePhysicalHolding(record.holding_cid);
    assert.equal(retired.deleted, false);
    assert.equal(retired.cleanup.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await store.inspectPhysicalHolding(record.holding_cid),
      undefined);
    const recovered = await retired.cleanup.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.errors.length, 1);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
  });

for (const count of [2, 3]) {
  test(`prepared adoption serializes ${count} identical-material seals without orphan custody`, async t => {
    let physicalReady, blocked = false, physicalCount = 0, staging;
    const ready = new Promise(resolve => { physicalReady = resolve; });
    const {store, directory, configuration} = await fixture(t, {}, contractControl, {
      async syncDirectory(path) {
        const handle = await open(path, 'r');
        try { await handle.sync(); } finally { await handle.close(); }
        if (blocked && path === staging && ++physicalCount === count - 1) physicalReady();
      },
    });
    staging = join(directory, 'staging');
    const request = publicationRequest(resultDefinition(), digest(`custody-race-${count}`));
    const invocationValue = invocation();
    const attempt = publicationAttempt(request, `custody-race-${count}`);
    const first = await prepareCommit(store, request, attempt, invocationValue);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [first.binding.identity],
    });
    const custodyDirectory = join(directory, 'prepared-custody');
    const names = await readdir(custodyDirectory);
    assert.equal(names.length, 1);
    const originalUnlink = fsPromises.unlink;
    let enter, resume;
    const entered = new Promise(resolve => { enter = resolve; });
    const paused = new Promise(resolve => { resume = resolve; });
    let consumed = false;
    t.mock.method(fsPromises, 'unlink', async path => {
      if (!consumed && String(path) === join(custodyDirectory, names[0])) {
        consumed = true; blocked = true; enter(); await paused;
      }
      const result = await originalUnlink(path);
      return result;
    });
    syncBuiltinESMExports();
    t.after(() => {t.mock.restoreAll(); syncBuiltinESMExports();});
    const committing = commitFixtureIndex(store, wire(entry), first.required, first.evidence);
    await entered;
    const payload = Buffer.from('fixture durable Result payload');
    const seals = Array.from({length:count-1}, async () => {
      const writer = store.createPreparedObjectWriter(payload.length);
      await writer.append(payload);
      return writer.seal(digest(payload));
    });
    try {
      await ready;
      // Allow physical seal continuations to attempt metadata attachment while
      // adoption still owns its original snapshot. The fixed queue waits.
      await new Promise(resolve => setImmediate(resolve));
      await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
      assert.equal(store.status().closed,false,'queued seal custody prevents premature close');
    } finally { blocked = false; resume(); }
    await committing;
    const later = await Promise.all(seals);
    for (const value of later) {
      assert.equal(value.prepared.status().pending, true,
        'earlier adoption cannot silently retire a later prepared owner');
      await value.prepared.release();
    }
    assert.deepEqual(await readdir(custodyDirectory), []);
    const bytes = (await store.verifyObject(digest(payload))).bytes;
    assert.equal(bytes, payload.length, 'published material survives later cancellation');
    await store.close();
    const reopened = await openLocalPublicationStore(configuration, contractControl);
    assert.equal((await reopened.verifyObject(digest(payload))).bytes, payload.length);
    await reopened.close();
  });
}

test('failed prepared custody retirement retains the original retry and later same-CID owner', async t => {
  const {store, directory} = await fixture(t);
  const request = publicationRequest(resultDefinition(), digest('custody-retirement-failure'));
  const invocationValue = invocation();
  const attempt = publicationAttempt(request, 'custody-retirement-failure');
  const first = await prepareCommit(store, request, attempt, invocationValue);
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [first.binding.identity],
  });
  const custodyDirectory = join(directory, 'prepared-custody');
  const [name] = await readdir(custodyDirectory);
  const originalUnlink = fsPromises.unlink;
  let refuse = true;
  t.mock.method(fsPromises, 'unlink', async path => {
    if (refuse && String(path) === join(custodyDirectory, name)) {
      throw Object.assign(new Error('OriginalCustodyRetirementUnavailable'), {code:'EIO'});
    }
    return originalUnlink(path);
  });
  syncBuiltinESMExports();
  t.after(() => {t.mock.restoreAll(); syncBuiltinESMExports();});
  let failure;
  await assert.rejects(commitFixtureIndex(store, wire(entry), first.required, first.evidence), error => {
    failure=error; return error.cleanupPending===true;
  });
  assert.equal(first.prepared.status().pending,false,
    'durable transfer settled the holder; the original commit pin retains failed allocation cleanup');
  assert.equal(failure.cleanupHandle.status().pending,true);
  const payload=Buffer.from('fixture durable Result payload');
  const writer=store.createPreparedObjectWriter(payload.length);
  await writer.append(payload);
  const later=await writer.seal(digest(payload));
  assert.equal(later.prepared.status().pending,true);
  await assert.rejects(store.close(),code('PublicationStoreCleanupPending'));
  refuse=false;
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending,false);
  assert.equal(later.prepared.status().pending,true,
    'reconciliation transfers only the original selected holder');
  await later.prepared.release();
  assert.deepEqual(await readdir(custodyDirectory),[]);
  assert.equal((await store.verifyObject(digest(payload))).bytes,payload.length);
  await store.close();
});

test('prepared release winning before commit custody acquisition refuses missing material before install', async t => {
  let stageReady;
  const staged = new Promise(resolve => {stageReady=resolve;});
  const {store,directory}=await fixture(t);
  const request=publicationRequest(resultDefinition(),digest('release-begin-race'));
  const invocationValue=invocation();
  const attempt=publicationAttempt(request,'release-begin-race');
  const first=await prepareCommit(store,request,attempt,invocationValue);
  const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[first.binding.identity]});
  const payload=Buffer.from('fixture durable Result payload');
  const target=join(directory,'objects',digest(payload).slice(7));
  let sawRelease,resumeRelease,resumeInstall,block=true;
  const releaseEntered=new Promise(r=>sawRelease=r),releaseWait=new Promise(r=>resumeRelease=r);
  const installWait=new Promise(r=>resumeInstall=r);
  const originalStat=fsPromises.lstat,originalLink=fsPromises.link;
  t.mock.method(fsPromises,'lstat',async function(path,...args){
    const value=await originalStat(path,...args);
    if(block&&path===target){block=false;sawRelease();await releaseWait;}
    return value;
  });
  t.mock.method(fsPromises,'link',async function(from,to){
    if(String(to).startsWith(join(directory,'indexes')+sep))await installWait;
    const linked=await originalLink(from,to);
    if(String(to)===join(directory,'contracts',entry.public_index_entry_cid.slice(7)+'.json'))stageReady();
    return linked;
  });
  syncBuiltinESMExports();
  t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const releasing=first.prepared.release();
  await releaseEntered;
  const committing=commitFixtureIndex(store, wire(entry),first.required,first.evidence);
  committing.catch(()=>{});
  await staged;
  await new Promise(resolve=>setImmediate(resolve));
  resumeRelease();
  assert.equal(await releasing,true);
  resumeInstall();
  await assert.rejects(committing,code('PublicationObjectMissing'));
  assert.equal(await store.confirmCommittedIndex({namespaceId:entry.namespace_id,
    authorityScopeCid:entry.authority_scope_cid,runDefinitionCid:entry.run_definition_cid}),undefined);
});

test('commit custody acquired before prepared cancellation retains material through original install',async t=>{
 const {store,directory}=await fixture(t);
 const request=publicationRequest(resultDefinition(),digest('commit-before-cancel'));
 const invocationValue=invocation(),attempt=publicationAttempt(request,'commit-before-cancel');
 const first=await prepareCommit(store,request,attempt,invocationValue);
 const entry=indexEntry(request,attempt,invocationValue,{durable_result_binding_cids:[first.binding.identity]});
 let entered,resume;
 const installing=new Promise(r=>entered=r),wait=new Promise(r=>resume=r);
 const originalLink=fsPromises.link;
 t.mock.method(fsPromises,'link',async(from,to)=>{
  if(String(to).startsWith(join(directory,'indexes')+sep)){entered();await wait;}
  return originalLink(from,to);
 });
 syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
 const committing=commitFixtureIndex(store, wire(entry),first.required,first.evidence);
 await installing;
 assert.equal(await first.prepared.release(),false);
 assert.equal(first.prepared.status().pending,true);
 resume();assert.equal((await committing).committed,true);
 assert.equal(first.prepared.status().pending,false);
 assert.equal((await store.verifyObject(digest('fixture durable Result payload'))).bytes,30);
});

for (const privateAdoption of [false,true]) test(`adopted shared material is pinned before another Run index installs, privateAdoption=${privateAdoption}`, async t => {
  const {store,directory}=await fixture(t);
  const invoked=invocation();
  const prepare=async label=>{
    const request=publicationRequest(resultDefinition(),digest(label));
    const attempt=publicationAttempt(request,label);
    const prepared=await prepareCommit(store,request,attempt,invoked);
    const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[prepared.binding.identity]});
    return {request,prepared,entry};
  };
  const a=await prepare('shared-pin-a'), b=await prepare('shared-pin-b');
  await commitFixtureIndex(store, wire(a.entry),a.prepared.required,a.prepared.evidence);
  assert.equal(b.prepared.prepared.status().pending,true);
  await b.prepared.prepared.release();
  assert.equal(b.prepared.prepared.status().pending,false);
  let entered,resume;
  const installing=new Promise(r=>entered=r), wait=new Promise(r=>resume=r);
  const originalLink=fsPromises.link;
  t.mock.method(fsPromises,'link',async(from,to)=>{
    if(String(to).startsWith(join(directory,'indexes')+sep)){entered();await wait;}
    return originalLink(from,to);
  });
  syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
  const committing=commitFixtureIndex(store, wire(b.entry),b.prepared.required,b.prepared.evidence);
  await installing;
  let holdingRetirement;
  if (privateAdoption) {
    const payload=await preparePhysical(store,Buffer.from('fixture durable Result payload'));
    const holding=physicalHolding(digest('concurrent private adopter'),digest('concurrent private manifest'),
      [{cid:payload.cid,byte_count:payload.bytes}], 'effect-source');
    await store.commitPhysicalHolding(holding,[payload.prepared]);
    holdingRetirement=()=>store.retirePhysicalHolding(holding.holding_cid);
  }
  const retired=await store.retireCommittedResult(indexKeyFor(a.request),a.request.inventory[0].result_definition_cid);
  const privateRetired=await holdingRetirement?.();
  try {
    assert.equal(retired.cleanup.status().pending,true,'temporary commit pin retains last original');
    assert.equal((await store.verifyObject(digest('fixture durable Result payload'))).bytes,30);
  } finally {resume();await committing;await retired.cleanup.retry();await privateRetired?.cleanup.retry();}
  const chunks=[];
  await store.consumeCommittedResult(indexKeyFor(b.request),b.request.inventory[0].result_definition_cid,
    ()=>true,chunk=>chunks.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(chunks).toString(),'fixture durable Result payload');
});

test('independent prepared holder survives another same-CID publication retirement before its stage', async t => {
  const {store}=await fixture(t), invoked=invocation();
  const prepare=async label=>{
    const request=publicationRequest(resultDefinition(),digest(label)), attempt=publicationAttempt(request,label);
    const value=await prepareCommit(store,request,attempt,invoked);
    const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[value.binding.identity]});
    return {request,value,entry};
  };
  const a=await prepare('holder-stage-a'), b=await prepare('holder-stage-b');
  await commitFixtureIndex(store, wire(a.entry),a.value.required,a.value.evidence,undefined,[a.value.prepared]);
  assert.equal(a.value.prepared.status().pending,false);
  assert.equal(b.value.prepared.status().pending,true,'A cannot transfer B by content identity');
  const retired=await store.retireCommittedResult(indexKeyFor(a.request),a.request.inventory[0].result_definition_cid);
  assert.equal(retired.cleanup.status().pending,true);
  const committed=await commitFixtureIndex(store, wire(b.entry),b.value.required,b.value.evidence,undefined,[b.value.prepared]);
  assert.equal(committed.committed,true);assert.equal(b.value.prepared.status().pending,false);
  await retired.cleanup.retry();
  const rows=[];
  await store.consumeCommittedResult(indexKeyFor(b.request),b.request.inventory[0].result_definition_cid,
    ()=>true,part=>rows.push(Buffer.from(part)));
  assert.equal(Buffer.concat(rows).toString(),'fixture durable Result payload');
});

test('CID-only commit and stored confirmation cannot transfer independent prepared handles', async t => {
  const {store}=await fixture(t), invoked=invocation();
  const request=publicationRequest(resultDefinition(),digest('no-holder-authority'));
  const attempt=publicationAttempt(request), p=await prepareCommit(store,request,attempt,invoked);
  const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[p.binding.identity]});
  await store.commitIndex(wire(entry),p.required,p.evidence);
  assert.equal(p.prepared.status().pending,true);
  await store.validateCommittedEvidence(contractControl.admit('public_index_entry',wire(entry),limits),p.evidence);
  assert.equal(p.prepared.status().pending,true);
  await p.prepared.release();
  assert.equal(p.prepared.status().pending,false);
});

const holderPermutations = [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]];
for (const order of holderPermutations) for (const adopter of ['public','private'])
  for (const terminal of ['publish','cancel']) {
  test(`nominal holder interleaving ${order.join('')}/${adopter}/${terminal}`, async t => {
    const {store}=await fixture(t), invoked=invocation(), holders=[];
    for (let i=0;i<3;i++) {
      const request=publicationRequest(resultDefinition(),digest(`permutation-${order}-${adopter}-${terminal}-${i}`));
      const attempt=publicationAttempt(request), p=await prepareCommit(store,request,attempt,invoked);
      const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[p.binding.identity]});
      holders.push({request,p,entry});
    }
    const [a,b,c]=order.map(index=>holders[index]);let retirement;
    if (adopter==='public') {
      await store.commitIndex(wire(a.entry),a.p.required,a.p.evidence,undefined,[a.p.prepared,a.p.prepared]);
      retirement=await store.retireCommittedResult(indexKeyFor(a.request),a.request.inventory[0].result_definition_cid);
    } else {
      const material=JSON.parse(a.p.binding.wire);
      const holding=physicalHolding(digest('permutation-holding'),digest('permutation-manifest'),
        [{cid:material.material_generation_cid,byte_count:material.byte_count}],'effect-source');
      await store.commitPhysicalHolding(holding,[a.p.prepared]);
      retirement=await store.retirePhysicalHolding(holding.holding_cid);
    }
    assert.equal(a.p.prepared.status().pending,false);
    assert.equal(b.p.prepared.status().pending,true);assert.equal(c.p.prepared.status().pending,true);
    await c.p.prepared.release();assert.equal(b.p.prepared.status().pending,true);
    if (terminal==='publish') {
      await store.commitIndex(wire(b.entry),b.p.required,b.p.evidence,undefined,[b.p.prepared]);
      assert.equal((await store.verifyObject(digest('fixture durable Result payload'))).bytes,30);
    } else await b.p.prepared.release();
    assert.equal(b.p.prepared.status().pending,false);assert.equal(c.p.prepared.status().pending,false);
    await retirement.cleanup.retry();
  });
}

for (const creatorFirst of [true,false]) test(`shared original allocation recovery survives holder retirement, creatorFirst=${creatorFirst}`,async t=>{
 const directory=await mkdtemp(join(tmpdir(),'actql-holder-generation-crash-'));
 t.after(()=>removeFixtureDirectory(directory));
 const configuration={directory,storeAuthorityCid:cids.authority,capacityBytes:1024*1024,
   maxObjectBytes:64*1024,maxObjects:100,maxContractNodes:limits.maxNodes,maxContractDepth:limits.maxDepth};
 const storeUrl=new URL('./publication-store.mjs',import.meta.url).href;
 const controlUrl=new URL('../host-common/publication-contract-control.fixture.mjs',import.meta.url).href;
 const bytes='shared allocation recovery',material=digest(bytes);
 const holding=physicalHolding(digest('holder-generation-holding'),digest('holder-generation-manifest'),
   [{cid:material,byte_count:Buffer.byteLength(bytes)}],'effect-source');
 const child=await runStoreChild(`
  import assert from 'node:assert/strict';
  import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
  import {createPublicationContractControlFixture} from ${JSON.stringify(controlUrl)};
  const store=await openLocalPublicationStore(${JSON.stringify(configuration)},createPublicationContractControlFixture());
  const holders=[];
  for(let i=0;i<2;i++){const writer=store.createPreparedObjectWriter(${Buffer.byteLength(bytes)});
    await writer.append(Buffer.from(${JSON.stringify(bytes)}));holders.push((await writer.seal(${JSON.stringify(material)})).prepared);}
  const selected=${creatorFirst?0:1}, remaining=1-selected;
  await store.commitPhysicalHolding(${JSON.stringify(holding)},[holders[selected]]);
  assert.equal(holders[selected].status().pending,false);assert.equal(holders[remaining].status().pending,true);
  await store.retirePhysicalHolding(${JSON.stringify(holding.holding_cid)});
  assert.equal((await store.verifyObject(${JSON.stringify(material)})).bytes,${Buffer.byteLength(bytes)});
  process.exit(77);
 `);
 assert.equal(child.exitCode,77,child.stderr);
 const reopened=await openLocalPublicationStore(configuration,contractControl);
 await assert.rejects(reopened.verifyObject(material),code('PublicationObjectMissing'));
 assert.deepEqual(await readdir(join(directory,'prepared-custody')),[]);
 assert.equal(reopened.status().storedBytes,0);
 await reopened.close();
});

test('original allocation recovery survives zero holders with a pending public commit pin',async t=>{
 const {store,configuration,directory}=await fixture(t), invoked=invocation();
 const request=publicationRequest(resultDefinition(),digest('pin-without-holder-crash'));
 const attempt=publicationAttempt(request),p=await prepareCommit(store,request,attempt,invoked);
 const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[p.binding.identity]});
 await p.prepared.release();await store.close();
 const payload='fixture durable Result payload',material=digest(payload);
 const holding=physicalHolding(digest('pin-only-private-holding'),digest('pin-only-manifest'),
   [{cid:material,byte_count:30}],'effect-source');
 const child=await runStoreChild(`
  import assert from 'node:assert/strict';import fs from 'node:fs/promises';
  import {syncBuiltinESMExports} from 'node:module';import {join} from 'node:path';
  import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs',import.meta.url).href)};
  import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs',import.meta.url).href)};
  const control=createPublicationContractControlFixture();
  const store=await openLocalPublicationStore(${JSON.stringify(configuration)},control);
  const admit=value=>{if(Array.isArray(value))return value.map(admit);try{return control.admit(value.name,value.wire,${JSON.stringify(limits)});}catch(error){if(error.code!=='UnknownPublicationContract')throw error;return control.admitArtifactFixture(value.name,value.wire);}};
  const evidence=Object.fromEntries(Object.entries(${JSON.stringify(p.evidence)}).map(([key,value])=>[key,admit(value)]));
  const writer=store.createPreparedObjectWriter(30);await writer.append(Buffer.from(${JSON.stringify(payload)}));
  const owner=(await writer.seal(${JSON.stringify(material)})).prepared;
  let entered;const installing=new Promise(r=>entered=r);const originalLink=fs.link;
  fs.link=async(from,to)=>{if(String(to).startsWith(join(${JSON.stringify(directory)},'indexes')+'/')){
    entered();await new Promise(()=>{});}return originalLink(from,to);};syncBuiltinESMExports();
  store.commitIndex(${JSON.stringify(wire(entry))},${JSON.stringify(p.required)},evidence).catch(error=>{console.error(error);process.exit(79);});
  await installing;
  await store.commitPhysicalHolding(${JSON.stringify(holding)},[owner]);
  assert.equal(owner.status().pending,false);
  await store.retirePhysicalHolding(${JSON.stringify(holding.holding_cid)});
  assert.equal((await store.verifyObject(${JSON.stringify(material)})).bytes,30);
  process.exit(77);
 `);
 assert.equal(child.exitCode,77,child.stderr);
 const reopened=await openLocalPublicationStore(configuration,contractControl);
 await assert.rejects(reopened.verifyObject(material),code('PublicationObjectMissing'));
 assert.deepEqual(await readdir(join(directory,'prepared-custody')),[]);
 await reopened.close();
});

for (const mode of ['retired','unknown-marker']) test(`final pin checks original Index retirement, ${mode}`,async t=>{
 let storeRef,directoryRef,selected,armed=false,retirement;
 const fixtureValue=await fixture(t,{},contractControl,{async syncDirectory(path){
   const handle=await open(path,'r');try{await handle.sync();}finally{await handle.close();}
   if(armed&&path===join(directoryRef,'indexes')){
     armed=false;
     if(mode==='retired') retirement=await storeRef.retireCommittedResult(
       indexKeyFor(selected.request),selected.request.inventory[0].result_definition_cid);
     else refuse=true;
   }
 }});
 const {store,directory}=fixtureValue;storeRef=store;directoryRef=directory;
 const invoked=invocation(),request=publicationRequest(resultDefinition(),digest('pin-own-retention-'+mode));
 const attempt=publicationAttempt(request),p=await prepareCommit(store,request,attempt,invoked);
 const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[p.binding.identity]});
 selected={request};let refuse=false;
 const originalStat=fsPromises.lstat;
 t.mock.method(fsPromises,'lstat',async(path,...args)=>{
   if(refuse&&String(path).startsWith(join(directory,'deletions')+sep))throw Object.assign(new Error('OriginalDeletionMarkerUnknown'),{code:'EIO'});
   return originalStat(path,...args);
 });
 syncBuiltinESMExports();t.after(()=>{refuse=false;t.mock.restoreAll();syncBuiltinESMExports();});
 armed=true;
 if(mode==='retired'){
   await store.commitIndex(wire(entry),p.required,p.evidence,undefined,[p.prepared]);
   await retirement.cleanup.retry();
   await assert.rejects(store.verifyObject(digest('fixture durable Result payload')),code('PublicationObjectMissing'));
 } else {
   let failure;
   await assert.rejects(store.commitIndex(wire(entry),p.required,p.evidence,undefined,[p.prepared]),error=>{
     failure=error;return error.cleanupPending===true&&error.cleanupHandle.status().pending===true;
   });
   assert.equal((await readdir(join(directory,'prepared-custody'))).length,1);
   refuse=false;await failure.cleanupHandle.retry();
   assert.equal(failure.cleanupHandle.status().pending,false);
   assert.equal((await store.verifyObject(digest('fixture durable Result payload'))).bytes,30);
 }
});

test('Store typed validation retains semantic close custody while yielded and releases after cancellation',async t=>{
  let intercept=false, entered, resume;
  const atBarrier=new Promise(resolve=>{entered=resolve;});
  const barrier=new Promise(resolve=>{resume=resolve;});
  const events=[];
  const control={...contractControl,async effectFreeStoredCommitValid(...args){
    if(!intercept)return contractControl.effectFreeStoredCommitValid(...args);
    const requireCurrent=args.pop();
    try{requireCurrent();entered();await barrier;requireCurrent();throw new Error('InjectedValidationCancellation');}
    finally{events.push('checker-cancelled');}
  }};
  const {store}=await fixture(t,{},control),invoked=invocation();
  const request=publicationRequest(resultDefinition(),invoked.invocation_cid);
  const attempt=publicationAttempt(request),p=await prepareCommit(store,request,attempt,invoked);
  const entry=indexEntry(request,attempt,invoked,{durable_result_binding_cids:[p.binding.identity]});
  await commitFixtureIndex(store,wire(entry),p.required,p.evidence);
  await p.prepared.release();
  intercept=true;
  const validating=store.validateCommittedEvidence(contractControl.admit('public_index_entry',wire(entry),limits),p.evidence);
  const refused=assert.rejects(validating,error=>error.code==='InvalidPublicationCommitChain'&&error.cause?.message==='InjectedValidationCancellation');
  await atBarrier;
  try {
    await assert.rejects(store.close(),{code:'PublicationStoreCleanupPending'});
    assert.equal(store.status().closed,false);assert.deepEqual(events,[]);
  } finally {resume();await refused;}
  assert.deepEqual(events,['checker-cancelled']);
  assert.equal(await store.close(),true);assert.equal(store.status().closed,true);
});

test('independent physical holding readers survive interleaved equal-CID publication and retirement',
  {timeout: 10000}, async t => {
    const {store, directory} = await fixture(t);
    const publish = async (name, value) => {
      const prepared = await preparePhysical(store, value);
      const record = physicalHolding(digest(`interleaved holding ${name}`),
        digest(`interleaved manifest ${value}`),
        [{cid: prepared.cid, byte_count: prepared.bytes}]);
      await store.commitPhysicalHolding(record, [prepared.prepared]);
      return record;
    };
    const first = await publish('first', 'shared');
    const second = await publish('second', 'shared');
    const unrelated = await publish('unrelated', 'different');
    assert.equal(first.objects[0].cid, second.objects[0].cid);
    const consume = async (record, accept = () => {}) => {
      const chunks = [];
      await store.consumePhysicalHolding(record.holding_cid, 0, async chunk => {
        chunks.push(Buffer.from(chunk));
        await accept();
      });
      return Buffer.concat(chunks).toString('utf8');
    };
    let releaseFirst, releaseSecond, enterFirst, enterSecond;
    const firstGate = new Promise(resolve => {releaseFirst = resolve;});
    const secondGate = new Promise(resolve => {releaseSecond = resolve;});
    const firstEntered = new Promise(resolve => {enterFirst = resolve;});
    const secondEntered = new Promise(resolve => {enterSecond = resolve;});
    const firstRead = consume(first, async () => {enterFirst(); await firstGate;});
    const secondRead = consume(second, async () => {enterSecond(); await secondGate;});
    try {
      await Promise.all([firstEntered, secondEntered]);
      const firstRetirement = await store.retirePhysicalHolding(first.holding_cid);
      assert.equal(firstRetirement.deleted, false);
      const fourth = physicalHolding(digest('interleaved holding fourth'),
        second.manifest_cid, second.objects);
      assert.equal((await store.sharePhysicalHolding(second.holding_cid, fourth)).created, true);
      assert.equal((await store.sharePhysicalHolding(second.holding_cid, fourth)).created, false);
      assert.equal((await store.retirePhysicalHolding(unrelated.holding_cid)).deleted, true);
      assert.equal(store.status().storedBytes, 6);
      assert.equal(store.status().objectCount, 1);
      assert.equal(await consume(fourth), 'shared');
      releaseFirst();
      assert.equal(await firstRead, 'shared');
      assert.equal((await firstRetirement.cleanup.retry()).pending, false);
      const secondRetirement = await store.retirePhysicalHolding(second.holding_cid);
      assert.equal(secondRetirement.deleted, false);
      assert.equal(await consume(fourth), 'shared');
      assert.equal(store.status().storedBytes, 6);
      releaseSecond();
      assert.equal(await secondRead, 'shared');
      assert.equal((await secondRetirement.cleanup.retry()).pending, false);
      assert.equal(await consume(fourth), 'shared');
      assert.equal((await store.retirePhysicalHolding(fourth.holding_cid)).deleted, true);
      const status = store.status();
      for (const field of ['storedBytes', 'reservedBytes', 'objectCount', 'reservedObjects']) {
        assert.equal(status[field], 0, field);
      }
      assert.deepEqual(await readdir(join(directory, 'objects')), []);
    } finally {
      // Always unblock and settle actual readers, including a failed oracle.
      releaseFirst();
      releaseSecond();
      await Promise.allSettled([firstRead, secondRead]);
      await store.recoverPhysicalHoldingDeletions();
    }
  });
for (const oldVersion of [5, 7, 10, 14]) {
  test(`Store refuses private format ${oldVersion} without deleting retained originals`, async t => {
    const setup = await fixture(t);
    // Use the current fixture's exact prepared handles and attempt-owned commit;
    // only this disposable database's private format marker is made unsupported.
    const selected = await committedHoldingFixture(setup, 'unsupported private format');
    await setup.store.close();
    const path = join(setup.directory, 'delivery-attempts.sqlite3');
    const database = new DatabaseSync(path);
    try { database.prepare('UPDATE coverage SET version=?').run(oldVersion); }
    finally { database.close(); }
    const before = await readFile(path), inventory = await readFile(selected.inventoryPath);
    await assert.rejects(openLocalPublicationStore(setup.configuration, contractControl),
      code('DeliveryAttemptIndexUnavailable'));
    assert.deepEqual(await readFile(path), before);
    assert.deepEqual(await readFile(selected.inventoryPath), inventory);
    await assert.rejects(stat(join(setup.directory, 'owner')), code('ENOENT'));
  });
}

test('retiring allocation stays physically owned while two earlier writers seal replacements', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retirement-concurrent-'));
  t.after(() => removeFixtureDirectory(directory));
  const object = join(directory, 'objects', digest('payload').slice(7));
  let failAck = false, capture = false;
  const handles = [], originalOpen = fsPromises.open;
  t.mock.method(fsPromises, 'open', async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (capture && String(path) === object) handles.push(handle);
    return handle;
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: cids.authority,
    capacityBytes: 1024, maxObjectBytes: 1024, maxObjects: 10,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth}, contractControl, {
    async syncDirectory(path) {
      if (failAck && path === join(directory, 'objects')) {
        failAck = false; throw Object.assign(new Error('original unlink ACK'), {code: 'EIO'});
      }
      const handle = await open(path, 'r'); try { await handle.sync(); } finally { await handle.close(); }
    },
  });
  t.after(() => store.close());
  const first = store.createPreparedObjectWriter(7); await first.append('payload');
  const old = await first.seal(digest('payload'));
  const original = await stat(object);
  // These writes are admitted before retirement, not only after its fence.
  const a = store.createPreparedObjectWriter(7), b = store.createPreparedObjectWriter(7);
  await Promise.all([a.append('payload'), b.append('payload')]);
  capture = true; failAck = true;
  await assert.rejects(old.prepared.release(), {code: 'EIO'});
  capture = false;
  const keeper = handles.find(handle => handle.fd >= 0);
  assert(keeper, 'an actual original FD, not an in-memory generation flag, remains owned');
  assert.equal((await keeper.stat()).nlink, 0);
  const replacements = await Promise.all([a.seal(digest('payload')), b.seal(digest('payload'))]);
  assert.equal(replacements.filter(value => value.created).length, 1);
  const current = await stat(object);
  assert.notDeepEqual([current.dev, current.ino], [original.dev, original.ino]);
  assert.equal(store.status().storedBytes, 14);
  const reader = await open(object, 'r');
  try {
    await Promise.all([old.prepared.retry(), old.prepared.retry()]);
    assert.equal(await reader.readFile('utf8'), 'payload');
    assert.equal(store.status().storedBytes, 7);
    assert.equal(keeper.fd, -1);
  } finally { await reader.close(); }
  await replacements[0].prepared.release();
  assert.equal(store.status().storedBytes, 7);
  await replacements[1].prepared.release();
  assert.equal(store.status().storedBytes, 0);
});

for (const boundary of ['before-lifetime-dirty-marker', 'after-lifetime-dirty-marker-commit', 'after-unlink',
  'after-directory-ack', 'before-original-close', 'after-original-close', 'after-retirement-quota-delta', 'after-close-time-native-quota-commit']) {
  test(`physical allocation lifetime recovers after process death at ${boundary}`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-retirement-crash-'));
    t.after(() => removeFixtureDirectory(directory));
    const configuration = {directory, storeAuthorityCid: cids.authority, capacityBytes: 1024,
      maxObjectBytes: 1024, maxObjects: 10, maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
    const child = await runStoreChild(`
      import assert from 'node:assert/strict';
      import fs from 'node:fs/promises';
      import {syncBuiltinESMExports} from 'node:module';
      import {DatabaseSync} from 'node:sqlite';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
      import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
      const configuration = ${JSON.stringify(configuration)}, boundary = ${JSON.stringify(boundary)};
      const object = join(configuration.directory, 'objects', ${JSON.stringify(digest('payload').slice(7))});
      let armed = false, dirty = false, sealing = false, retirementArmed = false, quotaSealUpdated = false;
      const exec = DatabaseSync.prototype.exec;
      DatabaseSync.prototype.exec = function(sql) {
        if (armed && sql === 'PRAGMA user_version=1') {
          if (boundary === 'before-lifetime-dirty-marker') process.exit(71);
          dirty = true;
        }
        const result = Reflect.apply(exec, this, [sql]);
        if (armed && dirty && sql === 'COMMIT' && boundary === 'after-lifetime-dirty-marker-commit') process.exit(71);
        if (sealing && sql === 'PRAGMA user_version=0') quotaSealUpdated = true;
        if (sealing && quotaSealUpdated && sql === 'COMMIT' && boundary === 'after-close-time-native-quota-commit') {
          const usage = this.prepare('SELECT objects,bytes FROM physical_object_usage WHERE id=1').get();
          assert.equal(usage.objects, 0); assert.equal(usage.bytes, 0); process.exit(71);
        }
        return result;
      };
      const originalOpen = fs.open, originalUnlink = fs.unlink;
      fs.unlink = async function(path, ...args) {
        if (retirementArmed && String(path) === object) {
          assert.equal((await fs.lstat(object)).size, 7);
          const check = new DatabaseSync(join(configuration.directory, 'delivery-attempts.sqlite3'), {readOnly:true});
          try { assert.equal(check.prepare('PRAGMA user_version').get().user_version, 1); } finally { check.close(); }
        }
        const result = await Reflect.apply(originalUnlink, this, [path, ...args]);
        if (retirementArmed && String(path) === object && boundary === 'after-unlink') process.exit(71);
        return result;
      };
      fs.open = async function(path, ...args) {
        const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
        if (String(path) === object) {
          const close = handle.close.bind(handle);
          handle.close = async () => {
            const retained = retirementArmed && (await handle.stat()).nlink === 0;
            if (retained && boundary === 'before-original-close') process.exit(71);
            const result = await close();
            if (retained && boundary === 'after-original-close') process.exit(71);
            return result;
          };
        }
        return handle;
      };
      syncBuiltinESMExports();
      const store = await openLocalPublicationStore(configuration, createPublicationContractControlFixture(), {
        async syncDirectory(path) {
          const handle = await fs.open(path, 'r'); try { await handle.sync(); } finally { await handle.close(); }
          if (retirementArmed && path === join(configuration.directory, 'objects') && boundary === 'after-directory-ack' &&
              await fs.lstat(object).then(() => false, e => { if (e.code !== 'ENOENT') throw e; return true; })) process.exit(71);
        },
      });
      armed = true;
      const writer = store.createPreparedObjectWriter(7); await writer.append('payload');
      const stored = await writer.seal(${JSON.stringify(digest('payload'))});
      assert.equal((await fs.lstat(object)).size, 7);
      assert.equal(store.status().storedBytes, 7); retirementArmed = true;
      await stored.prepared.release();
      assert.equal(store.status().storedBytes, 0);
      if (boundary === 'after-retirement-quota-delta') process.exit(71);
      sealing = true; await store.close();
      throw new Error('selected crash boundary was not reached');
    `);
    assert.equal(child.exitCode, 71, child.stderr);
    let openingAck = 0;
    const reopened = await openLocalPublicationStore(configuration, contractControl, {
      async syncDirectory(path) {
        if (path === join(directory, 'objects')) openingAck++;
        const handle = await open(path, 'r'); try { await handle.sync(); } finally { await handle.close(); }
      },
    });
    assert.equal(reopened.status().storedBytes, 0);
    if (!['before-lifetime-dirty-marker', 'after-close-time-native-quota-commit'].includes(boundary)) {
      assert(openingAck > 0, 'dirty recovery actually acknowledges the object directory before admission');
    }
    const next = reopened.createObjectWriter(7); await next.append('payload');
    assert.equal((await next.seal(digest('payload'))).created, true);
    assert.equal(reopened.status().storedBytes, 7);
    await reopened.close();
    const again = await openLocalPublicationStore(configuration, contractControl);
    assert.equal(again.status().storedBytes, 7);
    assert.equal((await again.verifyObject(digest('payload'))).bytes, 7);
    await again.close();
  });
}

test('process recovery preserves replacement while retiring FD ownership dies', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retirement-replacement-crash-'));
  t.after(() => removeFixtureDirectory(directory));
  const configuration = {directory, storeAuthorityCid: cids.authority, capacityBytes: 1024,
    maxObjectBytes: 1024, maxObjects: 10, maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
  const child = await runStoreChild(`
    import assert from 'node:assert/strict'; import {open} from 'node:fs/promises'; import {join} from 'node:path';
    import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
    const configuration = ${JSON.stringify(configuration)}; let failAck = false;
    const store = await openLocalPublicationStore(configuration, createPublicationContractControlFixture(), {
      async syncDirectory(path) {
        if (failAck && path === join(configuration.directory, 'objects')) { failAck = false; throw Object.assign(new Error('lost ACK'), {code:'EIO'}); }
        const h = await open(path, 'r'); try { await h.sync(); } finally { await h.close(); }
      },
    });
    const a = store.createPreparedObjectWriter(7); await a.append('payload'); const old = await a.seal(${JSON.stringify(digest('payload'))});
    failAck = true; await assert.rejects(old.prepared.release(), {code:'EIO'});
    const b = store.createObjectWriter(7); await b.append('payload'); assert.equal((await b.seal(${JSON.stringify(digest('payload'))})).created, true);
    assert.equal(store.status().storedBytes, 14); process.exit(71);
  `);
  assert.equal(child.exitCode, 71, child.stderr);
  const store = await openLocalPublicationStore(configuration, contractControl);
  assert.equal(store.status().storedBytes, 7);
  assert.equal((await store.verifyObject(digest('payload'))).bytes, 7);
  await store.close();
});

test('unknown original close fences only its Store allocation until process recovery', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retirement-close-unknown-'));
  const otherDirectory = await mkdtemp(join(tmpdir(), 'actql-retirement-close-other-'));
  t.after(() => removeFixtureDirectory(directory));
  t.after(() => removeFixtureDirectory(otherDirectory));
  const configuration = {directory, storeAuthorityCid: cids.authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100, maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth};
  const child = await runStoreChild(`
    import assert from 'node:assert/strict'; import fs from 'node:fs/promises';
    import {syncBuiltinESMExports} from 'node:module'; import {join} from 'node:path'; import {tmpdir} from 'node:os';
    import {openLocalPublicationStore} from ${JSON.stringify(new URL('./publication-store.mjs', import.meta.url).href)};
    import {createPublicationContractControlFixture} from ${JSON.stringify(new URL('../host-common/publication-contract-control.fixture.mjs', import.meta.url).href)};
    const configuration = ${JSON.stringify(configuration)}, wire = ${JSON.stringify(resultSchemaWire)};
    const physicalCid = ${JSON.stringify(digest(resultSchemaWire))};
    const object = join(configuration.directory, 'objects', physicalCid.slice(7));
    const originalOpen = fs.open, replacements = []; let closeCalls = 0, reused, expectedFd;
    const extra = await fs.mkdtemp(join(tmpdir(), 'actql-retirement-reused-fd-'));
    const lost = Object.assign(new Error('original close reply unavailable'), {code: 'EIO'});
    fs.open = async function(path, ...args) {
      const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
      if (String(path) === object) {
        const close = handle.close.bind(handle);
        handle.close = async () => {
          if ((await handle.stat()).nlink !== 0) return close();
          closeCalls++; expectedFd = handle.fd; await close();
          for (let i = 0; i < 64 && reused === undefined; i++) {
            const next = await originalOpen(join(extra, String(i)), 'wx+'); replacements.push(next);
            if (next.fd === expectedFd) reused = next;
          }
          assert(reused, 'the original numeric descriptor must actually be reused');
          throw lost;
        };
      }
      return handle;
    };
    syncBuiltinESMExports();
    const control = createPublicationContractControlFixture();
    const store = await openLocalPublicationStore(configuration, control);
    const writer = store.createPreparedObjectWriter(Buffer.byteLength(wire)); await writer.append(wire);
    const stored = await writer.seal(physicalCid);
    await assert.rejects(stored.prepared.release(), error => error === lost);
    await assert.rejects(stored.prepared.retry(), error => error === lost);
    assert.equal(closeCalls, 1);
    assert.equal(store.status().storedBytes, Buffer.byteLength(wire));
    await reused.writeFile('replacement descriptor remains open');
    assert.equal(reused.fd, expectedFd);
    const blocked = store.createObjectWriter(Buffer.byteLength(wire)); await blocked.append(wire);
    await assert.rejects(blocked.seal(physicalCid), {code: 'PublicationObjectReclamationPending'});
    await blocked.cancel();
    await assert.rejects(store.putSemantic(wire, ${JSON.stringify(cids.schema)}), {code: 'PublicationObjectReclamationPending'});
    await store.putBytes(Buffer.from('other'));
    assert.equal(store.status().storedBytes, Buffer.byteLength(wire) + 5);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    const other = await openLocalPublicationStore({...configuration, directory: ${JSON.stringify(otherDirectory)}}, control);
    await other.putBytes(Buffer.from(wire)); await other.close();
    assert.equal(closeCalls, 1);
    for (const handle of replacements) await handle.close(); await fs.rm(extra, {recursive: true});
    process.exit(71);
  `);
  assert.equal(child.exitCode, 71, child.stderr);
  let openingAck = 0;
  const reopened = await openLocalPublicationStore(configuration, contractControl, {
    async syncDirectory(path) {
      if (path === join(directory, 'objects')) openingAck++;
      const handle = await open(path, 'r'); try { await handle.sync(); } finally { await handle.close(); }
    },
  });
  assert(openingAck > 0, 'process recovery performs a real directory ACK before lifting quarantine');
  assert.equal(reopened.status().storedBytes, 5);
  await reopened.putBytes(Buffer.from(resultSchemaWire));
  assert.equal(reopened.status().storedBytes, 5 + Buffer.byteLength(resultSchemaWire));
  await reopened.close();
});
