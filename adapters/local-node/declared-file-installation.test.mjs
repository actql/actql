import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {admitInstalledProjectConfiguration, installedProjectOriginalsForRuntime}
  from '../host-node/installed-project-configuration.mjs';
import {createInstalledHostServices, retireInstalledSourceInitialization,
  assertInstalledSourceConstruction} from '../host-node/installed-host-services.mjs';

// Component boundary: real nominal table, Project registry, initializer,
// configuration FD/runtime hash, Environment and Row source/effect factories.
// Common semantic/Resource ports and physical Site operations are explicit
// fixtures. Passing these tests is not Common or operational acceptance.
const ok = value => ({$tag: 1, _0: value});
const cid = 'sha256:' + 'a'.repeat(64);
const unused = () => assert.fail('No Source read, Account grant or Effect send in constructor component');
const baseEnvironmentWire = JSON.stringify({version: 'actql-check-environment/0.1',
  connector_catalogs: [], schema_snapshots: [], connector_capabilities: [], mapping_contracts: []});
const writes = Object.freeze([Object.freeze({resource: 'records', sources: Object.freeze([
  Object.freeze({target: 'label', field: 'label', null_behavior: 'reject'})])})]);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-declared-file-component-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const runtimePath = join(root, 'runtime.mjs');
  await writeFile(runtimePath, 'export const identityOnly = true;\n');
  const initial = {}, input = {}, unit = {}, capacity = {}, nativeOriginals = new Map();
  const events = [], liveIo = new Set(), connections = Object.freeze([
    Object.freeze({name: 'crm_primary', connector: 'salesforce'}),
    Object.freeze({name: 'crm_secondary', connector: 'salesforce'}),
  ]);
  const refusal = new Error('same original reservation refusal');
  const pendingClose = new Error('same physical Site cleanup pending');
  const state = {phase: 'initial', refuse: undefined, currentFailure: undefined,
    projects: 0, projections: 0, mappings: 0, acquisitions: 0, retires: 0, takes: 0,
    sourceCloses: 0, effectCloses: 0, sourcePending: false, effectPending: false};
  const moon = Object.fromEntries(['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial'].map(name => ['clientProgram' + name, () => ok()]));
  Object.assign(moon, {
    clientProjectConfigurationAdmit: () => ok({configuration: 'original'}),
    clientProjectConfigurationModelTasksFile: () => undefined,
    clientProjectConnectionsCount: value => {assert.equal(value, connections);return value.length;},
    clientProjectConnectionsName: (value, index) => {assert.equal(value, connections);return value[index].name;},
    clientProjectConnectionsConnector: (value, index) => {assert.equal(value, connections);return value[index].connector;},
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-component-kind',
    clientProgramTakeHostInitializationSourceCapacity(value) {
      assert.equal(value, initial);state.takes++;events.push('take');return ok({_0: input, _1: unit});
    },
    clientProgramContinueInstalledSourceMaterial(value, original) {
      assert.equal(value, unit);assert.equal(original, input);events.push('continue');return ok(capacity);
    },
    clientProgramInstalledSourceConstructionCapacity: (...values) => ok({values}),
    clientProgramComposeInstalledSourceConstructionCapacity: (original, selected) => ok({original, selected: [...selected]}),
    clientProgramReserveInstalledSourceConstruction(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);events.push('reserve:' + state.phase);
      if (state.refuse === state.phase) throw refusal;
      return ok();
    },
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);assert.equal(liveIo.size, 0);
      state.retires++;events.push('retire');return ok(true);
    },
    clientProgramBeginInstalledSourceIo(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);
      const operation = {};liveIo.add(operation);events.push('io');return ok(operation);
    },
    clientProgramChargeInstalledSourceIo(operation) {assert(liveIo.has(operation));return ok();},
    clientProgramMarkInstalledSourceIoTransferUncertain: unused,
    clientProgramFinishInstalledSourceIoAfterCleanup(operation) {assert(liveIo.delete(operation));return ok();},
    clientProgramRowSourceRestoreRelationDeclaration: unused,
    clientProgramRowSourceDeclarationJson(declaration) {
      assert(nativeOriginals.has(declaration));return nativeOriginals.get(declaration);
    },
    clientProgramRowSourcePrepareMapping(declaration, wire, resource, sources) {
      assert(nativeOriginals.has(declaration));assert.equal(wire, '{"original":"writes"}');
      assert.equal(resource, 'records');assert.deepEqual(JSON.parse(sources), writes[0].sources);
      assert.equal(events.at(-1), 'reserve:' + state.phase);state.mappings++;events.push('mapping');
      return JSON.stringify({mapping_ref: 'mapping:crm_primary/create.v1', mapping_cid: cid,
        body: JSON.stringify({mapping_contract_cid: cid, target_ref: 'connector://crm_primary/records',
          minimum_approval: 'required', permission_rules: [{effect_kind: 'create', permissions: ['write']}]}),
        write_fields: ['label'], omittable: []});
    },
    clientProgramRowSourceAcquisitionContractsConstructionCapacity: () => ok(Object.freeze({fixture: 'original-acquisition-quote'})),
    clientProgramRowSourceAdmitAcquisitionContracts(query, evidence) {
      assert.equal(query, 'actql-query-acquisition.json');assert.equal(evidence, 'actql-query-process-evidence.json');
      assert.equal(events.at(-1), 'reserve:' + state.phase);state.acquisitions++;events.push('acquisition');
      return ok(Object.freeze({fixture: 'original-acquisition-contracts'}));
    },
    clientProgramRowSourcePrepareAcquisitionWithContracts: unused,
    clientProgramInstalledSourceReadCheckCurrent: unused,
    clientProgramInstalledSourceReadBindProgram: unused,
    clientProgramInstalledSourceReadBindEffectProgram: unused,
    clientProgramInstalledSourceReadAttachAcquisition: unused,
  });
  const project = admitInstalledProjectConfiguration(moon, '{"fixture":"configuration"}');
  const projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  const connectionOriginal = Object.freeze({project: projectOriginal, connections});
  const current = () => {if (state.currentFailure !== undefined) throw state.currentFailure;};
  const services = createInstalledHostServices({root, principalId: 'fixture', moon,
    initialPreparation: initial, assertCurrent: current});
  const inventory = createDeclaredFileInstallationInventory({moon, project, services,
    runtimeUrl: pathToFileURL(runtimePath), baseEnvironmentWire, assertCurrent: current});
  const authorization = {authorize: unused, accountConfiguration: {}, context: {contextCid: cid}};
  function sourceOptions(connection = 'crm_primary') {
    return {authorization, site: {connection, issueReadGrant: unused, async close() {
      state.sourceCloses++;if (state.sourcePending) throw pendingClose;
    }}, readOperation: 'read', physicalTarget: unused, readPages: unused,
    prepareSourceRead: unused, readAsset: path => path.split('/').at(-1), bindingCid: cid,
    limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}};
  }
  function effectOptions() {
    return {authorization, site: {issueEffectGrant: unused, issueReadGrant: unused, async close() {
      state.effectCloses++;if (state.effectPending === 'false') return false;
      if (state.effectPending) throw pendingClose;
    }}, bindingCid: cid, ledgerRoot: join(root, 'ledger'),
    driver: {kinds: ['create'], prepareRequest: unused, requestFacts: unused,
      writeOperation: unused, send: unused, project: unused, footprint: unused}};
  }
  function projection(connection = 'crm_primary', projectOverride) {
    const declaration = {}, physical = Object.freeze([{declaration}]);
    const declared = {views: [{source_ref: `connector://${connection}/records#records`, resource: 'records'}],
      evidence_schemas: [], evidence_capabilities: [], view_bodies: [], contracts: [],
      catalog: JSON.stringify({connector_id: connection}),
      manifest_entry: JSON.stringify({connector_id: connection, connector: 'declared_file', connector_version: 'declared_file/0.1'})};
    nativeOriginals.set(declaration, JSON.stringify(declared));
    // Explicit fixture quantity, never a production numeric fallback.
    const quantity = Object.freeze({fixture: 'complete-logical-and-physical-native-quote'});
    return Object.freeze({capacity: () => quantity, project() {
      assert.equal(events.at(-1), 'reserve:' + state.phase);state.projections++;events.push('project');
      if (projectOverride !== undefined) return projectOverride();
      return Object.freeze({declaration, physical});
    }});
  }
  return {root, moon, services, inventory, connectionOriginal, project, state, events, refusal,
    pendingClose, projection, sourceOptions, effectOptions,
    begin: (index = 0, role = 'source') => inventory.begin(connectionOriginal, index, role),
    retire: () => retireInstalledSourceInitialization(services)};
}

test('component generic inventory installs real Row source and Effect from the same prepared declaration', async t => {
  const f = await fixture(t);
  const first = f.begin(), repeated = f.begin();assert.equal(first, repeated);
  const source = await first, effect = await f.begin(0, 'effect');
  assert.equal(source.connection, 'crm_primary');assert.equal(source.connectorId, 'crm_primary');
  assert.equal(source.providerNamespace, 'salesforce');assert.equal(source.registration, 'declared_file');
  assert.equal(source.runtimeBundleCid, effect.runtimeBundleCid);
  f.state.phase = 'native';const prepared = source.prepareNativeDeclaration(f.projection());
  assert.equal(prepared.physical[0].declaration, prepared.declaration);
  f.state.phase = 'borrow';const borrowed = effect.prepareBorrowedDeclaration(source);
  assert.equal(borrowed.declaration, prepared.declaration);assert.equal(borrowed.declared, prepared.declared);
  f.state.phase = 'mapping';const mapped = effect.prepareMappings('{"original":"writes"}', writes);
  assert.equal(mapped.declaration, prepared.declaration);
  f.state.phase = 'source-factory';const adapter = await source.load(f.sourceOptions());
  assert.equal(adapter.admitsSource('connector://crm_primary/records#records'), true);
  assert.equal(adapter.sourceAccess.connection, 'crm_primary');assert.equal(typeof adapter.open, 'function');
  f.state.phase = 'effect-factory';const installedEffect = await effect.load(f.effectOptions());
  assert.equal(typeof installedEffect.prepareCaptured, 'function');
  assert.equal(typeof installedEffect.prepareManagedPlan, 'function');
  assert.equal(f.state.projections, 1);assert.equal(f.state.mappings, 1);assert.equal(f.state.acquisitions, 1);
  assert.equal(f.state.takes, 1);assert.equal(f.retire(), false);
  await assert.rejects(source.load(f.sourceOptions()), {code: 'DeclaredFileInstallationClosed'});
  await assert.rejects(effect.load(f.effectOptions()), {code: 'DeclaredFileInstallationClosed'});
  f.state.sourcePending = true;await assert.rejects(adapter.close(), error => error === f.pendingClose);
  assert.equal(f.retire(), false);f.state.sourcePending = false;await adapter.close();
  f.state.effectPending = 'false';await assert.rejects(installedEffect.close(), {code: 'InstalledEffectSiteCleanupPending'});
  assert.equal(f.retire(), false);f.state.effectPending = false;await installedEffect.close();
  await f.inventory.fail(new Error('normal final retirement'));
  assert.equal(f.retire(), true);assert.equal(f.state.retires, 1);
});

test('component configured provider does not replace either connection namespace', async t => {
  const f = await fixture(t), first = await f.begin(), second = await f.begin(1);
  assert.equal(first.providerNamespace, second.providerNamespace);
  assert.notEqual(first.connectorId, second.connectorId);
  first.prepareNativeDeclaration(f.projection('crm_primary'));
  second.prepareNativeDeclaration(f.projection('crm_secondary'));
  const a = await first.load(f.sourceOptions('crm_primary'));
  const b = await second.load(f.sourceOptions('crm_secondary'));
  assert.equal(a.admitsSource('connector://crm_secondary/records#records'), false);
  assert.equal(b.admitsSource('connector://crm_primary/records#records'), false);
  await a.close();await b.close();assert.equal(f.retire(), true);
});

test('component borrowed declaration refuses copied and foreign original contexts before another native constructor', async t => {
  const f = await fixture(t), foreign = await fixture(t);
  const source = await f.begin(), effect = await f.begin(0, 'effect');
  const other = await foreign.begin();source.prepareNativeDeclaration(f.projection());
  other.prepareNativeDeclaration(foreign.projection());
  const bad = [Object.freeze({...source.sourceInitialization}), other.sourceInitialization,
    (await f.begin(1)).sourceInitialization, effect.sourceInitialization];
  for (const context of bad) assert.throws(() => effect.sourceInitialization.prepareBorrowedDeclaration(context),
    {code: 'ForeignInstalledSourceInitialization'});
  assert.throws(() => effect.prepareBorrowedDeclaration(Object.freeze({...source})),
    {code: 'ForeignInstalledSourceConstruction'});
  const borrowed = effect.prepareBorrowedDeclaration(source);
  assert.doesNotThrow(() => assertInstalledSourceConstruction(effect.sourceInitialization,
    borrowed.declaration, borrowed.declared, borrowed.environment));
  assert.throws(() => effect.prepareBorrowedDeclaration(source), {code: 'ForeignInstalledSourceInitialization'});
  assert.equal(f.state.projections, 1);assert.equal(foreign.state.projections, 1);
  await f.inventory.fail(new Error('component stopped before physical installation'));
  await foreign.inventory.fail(new Error('component stopped before physical installation'));
  assert.equal(f.retire(), true);assert.equal(foreign.retire(), true);
});

for (const phase of ['native', 'borrow', 'mapping']) {
  test(`component ${phase} reservation refusal precedes its constructor and earlier contexts retire once`, async t => {
    const f = await fixture(t), source = await f.begin(), earlier = await f.begin(1);
    earlier.prepareNativeDeclaration(f.projection('crm_secondary'));
    const effect = await f.begin(0, 'effect');
    if (phase !== 'native') source.prepareNativeDeclaration(f.projection());
    if (phase === 'mapping') effect.prepareBorrowedDeclaration(source);
    f.state.phase = phase;f.state.refuse = phase;
    const before = {projections: f.state.projections, mappings: f.state.mappings};
    const attempt = phase === 'native' ? () => source.prepareNativeDeclaration(f.projection())
      : phase === 'borrow' ? () => effect.prepareBorrowedDeclaration(source)
      : () => effect.prepareMappings('{"original":"writes"}', writes);
    assert.throws(attempt, error => error === f.refusal);
    assert.throws(attempt, {code: 'DeclaredFileInstallationClosed'});
    assert.deepEqual({projections: f.state.projections, mappings: f.state.mappings}, before);
    assert.equal(f.retire(), false);
    await f.inventory.fail(f.refusal);await f.inventory.fail(f.refusal);
    assert.equal(f.retire(), true);assert.equal(f.state.retires, 1);
    assert.equal(f.state.sourceCloses + f.state.effectCloses, 0, 'no fabricated physical adapter');
  });
}

test('component pure failure remains original and prevents a second projection', async t => {
  const f = await fixture(t), source = await f.begin();
  const failure = new Error('original native projection failure');
  assert.throws(() => source.prepareNativeDeclaration(f.projection('crm_primary', () => {throw failure;})), error => error === failure);
  assert.throws(() => source.prepareNativeDeclaration(f.projection()), {code: 'DeclaredFileInstallationClosed'});
  await f.inventory.fail(failure);assert.equal(f.retire(), true);assert.equal(f.state.projections, 1);
});

test('component source factory refuses detached prepared originals and retains prior metadata cleanup', async t => {
  const f = await fixture(t), source = await f.begin();
  const prepared = source.prepareNativeDeclaration(f.projection());
  await assert.rejects(source.load({...f.sourceOptions(), environment: Object.freeze({...prepared.environment})}),
    error => error.code === 'InstalledHostInitializationFailed' && error.primaryFailure.code === 'ForeignInstalledSourceConstruction');
  assert.equal(f.state.acquisitions, 0);assert.equal(f.state.sourceCloses, 0);
  await f.inventory.fail(new Error('failed source factory'));assert.equal(f.retire(), true);
});

test('component startup reservation failure does not create a native declaration or replacement initial parent', async t => {
  const f = await fixture(t);f.state.refuse = 'initial';
  const flight = f.begin();assert.equal(f.begin(), flight);
  await assert.rejects(flight, error => error === f.refusal);
  await assert.rejects(f.begin(), error => error === f.refusal);
  assert.equal(f.state.projections, 0);assert.equal(f.state.acquisitions, 0);assert.equal(f.state.mappings, 0);
  await f.inventory.fail(f.refusal);assert.equal(f.retire(), true);assert.equal(f.state.takes, 1);
});

test('component preparation current failure closes all original contexts without rereading or reconstructing', async t => {
  const f = await fixture(t), source = await f.begin(), effect = await f.begin(0, 'effect');
  source.prepareNativeDeclaration(f.projection());effect.prepareBorrowedDeclaration(source);
  const before = f.events.filter(event => event === 'io').length;
  const failure = new Error('original currentness failure');f.state.currentFailure = failure;
  assert.throws(() => effect.prepareMappings('{"original":"writes"}', writes), error => error === failure);
  await f.inventory.fail(failure);assert.equal(f.retire(), true);
  assert.equal(f.state.projections, 1);assert.equal(f.state.mappings, 0);
  assert.equal(f.events.filter(event => event === 'io').length, before);
});

test('component retirement joins an actual Effect constructor before retiring its original material', async t => {
  const f = await fixture(t), source = await f.begin(), effect = await f.begin(0, 'effect');
  source.prepareNativeDeclaration(f.projection());effect.prepareBorrowedDeclaration(source);
  effect.prepareMappings('{"original":"writes"}', writes);
  const options = f.effectOptions(), failure = new Error('reentrant installation cancellation');
  let closing, entered;
  const factoryEntered = new Promise(resolve => {entered = resolve;});
  // This accessor is consumed by the real Row Effect's driver check, after
  // its original context check and before its asynchronous ledger mkdir.
  // No replacement factory or fabricated adapter supplies the completion.
  Object.defineProperty(options.driver, 'kinds', {get() {
    if (closing === undefined) {
      closing = f.inventory.fail(failure);entered();
    }
    return ['create'];
  }});
  const loading = effect.load(options);
  const rejected = assert.rejects(loading, error => error.code === 'InstalledHostInitializationFailed' &&
    error.primaryFailure.code === 'DeclaredFileInstallationClosed');
  await factoryEntered;
  assert.equal(f.retire(), false, 'pending constructor still owns the same initial material');
  assert.equal(f.state.effectCloses, 0);
  await closing;await rejected;
  assert.equal(f.state.effectCloses, 1, 'the real completed adapter owns physical Site cleanup');
  assert.equal(f.state.sourceCloses, 0, 'no source adapter was fabricated for metadata cleanup');
  assert.equal(f.retire(), true);assert.equal(f.state.retires, 1);
  assert.equal(f.state.projections, 1);assert.equal(f.state.mappings, 1);
});
