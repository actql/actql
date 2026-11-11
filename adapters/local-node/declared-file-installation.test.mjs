import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {loadDeclaredProjectCatalog, inspectDeclaredProjectCatalog} from './declared-project-catalog.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {declaredProjectCatalogJsonParseConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';
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

async function fixture(t, extendMoon) {
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
  extendMoon?.({moon, state, events, nativeOriginals});
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

// Exercise real inventory/service ownership with explicit Common semantic ports.
// These fixtures verify staging and original custody, not Core admission laws.
async function catalogFixture(t, {refuseNative = 0, missingNative = 0, malformedEntry = false, refuseEntry = false} = {}) {
  let latestQuote;
  const exports = new Map(), restoreCalls = [];
  const f = await fixture(t, ({moon, state, events, nativeOriginals}) => {
    state.nativeQuotes = 0;state.nativeRestores = 0;state.nativeExports = 0;
    state.entryQuotes = 0;state.entryWire = undefined;
    let entryQuantity;
    moon.clientProgramInstalledSourceConstructionCapacity = (...values) => {
      if (entryQuantity !== undefined && values.every((value, index) => value === entryQuantity[index])) {
        state.entryQuotes++;state.phase = 'entry';
        if (refuseEntry) state.refuse = state.phase;
      }
      return ok({values});
    };
    Object.assign(moon, {
      clientProjectCatalogAdmissionConstructionCapacity: () => Object.freeze({fixture: 'catalog-admission-quantity'}),
      clientProjectCatalogAdmit(original) {
        assert.equal(events.at(-1), 'reserve:' + state.phase);
        return ok(JSON.parse(original));
      },
      clientProjectCatalogCount: original => Object.keys(original.connections).length,
      clientProjectCatalogName: (original, index) => Object.keys(original.connections)[index],
      clientProjectCatalogEntryOriginalJson(original, index) {
        const wire = malformedEntry ? '{' : JSON.stringify(original.connections[Object.keys(original.connections)[index]]);
        const {retained, workspace} = declaredProjectCatalogJsonParseConstructionGeometry(wire);
        entryQuantity = [retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire];
        state.entryWire = wire;return wire;
      },
      clientProgramRelationRestoreConstructionCapacity(connector, registration, revision, wire,
        resources, kinds, schemas, requests, facts, acquisitions, identities) {
        const index = ++state.nativeQuotes;state.phase = 'native-' + index;
        latestQuote = Object.freeze({fixture: 'actual-invocation-native-quantity', index,
          connector, registration, revision, wire, resources, kinds, schemas, requests, facts, acquisitions, identities});
        if (index === refuseNative) state.refuse = state.phase;
        return index === missingNative ? undefined : latestQuote;
      },
      clientProgramRowSourceRestoreRelationDeclaration(connector, registration, revision, wire) {
        assert.equal(events.at(-1), 'reserve:' + state.phase);
        assert.deepEqual([connector, registration, revision, wire],
          [latestQuote.connector, latestQuote.registration, latestQuote.revision, latestQuote.wire]);
        const declaration = Object.freeze({fixture: 'native-declaration', index: latestQuote.index});
        const views = JSON.parse(wire).views;
        assert.deepEqual([latestQuote.resources, latestQuote.kinds, latestQuote.schemas, latestQuote.requests,
          latestQuote.facts, latestQuote.acquisitions, latestQuote.identities],
          ['resource', 'resource_kind', 'schema_wire', 'request_schema_wire', 'facts_wire',
            'acquisition_wire', 'resource_identity_wire'].map(name => views.map(view => view[name])));
        const declared = {views: views.map(view => ({resource: view.resource,
          source_ref: `connector://${connector}/${view.resource}#records`, carrier_schema_cid: cid})),
          evidence_schemas: [], evidence_capabilities: [], view_bodies: [], contracts: [],
          catalog: JSON.stringify({connector_id: connector}), manifest_entry: JSON.stringify({
            connector_id: connector, connector: registration, connector_version: revision})};
        nativeOriginals.set(declaration, JSON.stringify(declared));
        restoreCalls.push(latestQuote);state.nativeRestores++;return ok(declaration);
      },
      clientProgramRowSourceDeclarationJson(declaration) {
        assert(nativeOriginals.has(declaration));
        assert.equal(exports.get(declaration) ?? 0, 0, 'each native restore has exactly one owned export');
        exports.set(declaration, 1);state.nativeExports++;return nativeOriginals.get(declaration);
      },
      clientProgramRelationUpdateMapping: unused,
      clientProgramRowSourcePrepareUpdateMapping(declaration, wire, resource, sources) {
        assert(nativeOriginals.has(declaration));assert.equal(events.at(-1), 'reserve:' + state.phase);
        assert.deepEqual(JSON.parse(wire), {writes: [{resource: 'records', primary_identity: 'id',
          update: {fields: ['label'], permission: 'write', approval: 'required'}}]});
        assert.deepEqual(JSON.parse(sources), [{target: 'label', field: 'label', null_behavior: 'reject'}]);
        const declared = JSON.parse(nativeOriginals.get(declaration));
        const connector = JSON.parse(declared.catalog).connector_id;
        state.mappings++;
        return JSON.stringify({mapping_ref: `mapping:${connector}/update.v1`, mapping_cid: cid,
          body: JSON.stringify({mapping_contract_cid: cid, target_ref: `connector://${connector}/${resource}`,
            primary_identity: 'id', writable_fields: ['label'], minimum_approval: 'required',
            permission_rules: [{effect_kind: 'update', permissions: ['write']}]}),
          write_fields: ['label'], omittable: []});
      },
    });
  });
  const string = {type: 'string', nullable: false};
  const catalog = {connections: {
    // Deliberately reverse configured connection order and share the provider.
    crm_secondary: {views: [{resource: 'files', resource_kind: 'record', schema: {id: string, name: string}},
      {resource: 'contents', resource_kind: 'record', schema: {id: string}}],
      query_aliases: [{name: 'files.listing', resource: 'files'}],
      data: [{resource: 'files', items_path: ['files'], key_path: ['keys'], primary_identity: 'id',
        schema: {id: string, name: string, version: string, media_type: string, content_utf8: string}}],
      file_bindings: [{listing_resource: 'files', content_resource: 'contents', data_resource: 'files',
        identity_field: 'id', name_field: 'name', version_field: 'version', media_type_field: 'media_type',
        content_utf8_field: 'content_utf8'}]},
    crm_primary: {views: [{resource: 'records', resource_kind: 'record', schema: {id: string, label: string}}],
      query_aliases: [{name: 'crm.records', resource: 'records'}],
      data: [{resource: 'records', items_path: ['records'], key_path: ['keys'], primary_identity: 'id'}],
      writes: [{resource: 'records', primary_identity: 'id', writable_fields: ['label'],
        permission: 'write', observe_permission: 'read', approval: 'required', aliases: ['CRM.Record']}]},
  }};
  const originalWire = JSON.stringify(catalog);
  await writeFile(join(f.root, 'catalog.json'), originalWire);
  return {...f, exports, restoreCalls, originalWire, load: () => loadDeclaredProjectCatalog(f.moon, {
    directory: f.root, catalogFile: 'catalog.json', dataFile: 'absent-data.json',
    connections: f.connectionOriginal.connections, connectionOriginal: f.connectionOriginal,
    installationInventory: f.inventory, assertCurrent() {},
  })};
}

test('component catalog stages actual connection members before constructors and exports each declaration once', async t => {
  const f = await catalogFixture(t), result = await f.load();
  const [files, records] = result.sources;
  assert.equal(files.catalogue.connection, 'crm_secondary');assert.equal(records.catalogue.connection, 'crm_primary');
  assert.equal(files.sourceMember, await f.begin(1));assert.equal(records.sourceMember, await f.begin(0));
  assert.equal(files.sourceMember.providerNamespace, records.sourceMember.providerNamespace);
  assert.equal(files.sourcePrepared.declaration, files.declaration);
  assert.equal(files.sourcePrepared.wire, files.wire);
  assert.equal(records.sourcePrepared.declaration, records.effectPrepared.declaration);
  assert.equal(records.effectMember, await f.begin(0, 'effect'));
  assert.equal(records.writes[0].mappingWire, records.effectPrepared.mappings[0].body);
  assert.notEqual(files.physical[0].declaration, files.declaration);
  assert.equal(records.physical[0].declaration, records.declaration);
  assert.equal(f.state.nativeRestores, 4);assert.equal(f.state.nativeExports, 4);
  assert.deepEqual(f.restoreCalls.map(value => [value.connector, value.registration]), [
    ['crm_secondary', 'declared_file'], ['crm_secondary', 'declared_file_data'],
    ['crm_secondary', 'declared_file'], ['crm_primary', 'declared_file']]);
  const expectedScope = 'sha256:' + createHash('sha256').update(canonicalJson({
    connection: 'crm_secondary', connector: 'salesforce', dataPath: join(f.root, 'absent-data.json'),
    catalog: f.originalWire}, {dataKeys: true})).digest('hex');
  assert.equal(files.scopeCid, expectedScope);
  assert.equal(f.state.mappings, 1);assert.equal(f.state.takes, 1);
  const adapter = await records.sourceMember.load(f.sourceOptions());
  assert.equal(adapter.admitsSource('connector://crm_primary/records#records'), true);
  await adapter.close();await f.inventory.fail(new Error('finished catalog constructor component'));
  assert.equal(f.retire(), true);
});

for (const index of [1, 2, 3, 4]) {
  test(`component catalog native reservation refusal ${index} precedes its constructor and retains the earlier prefix`, async t => {
    const f = await catalogFixture(t, {refuseNative: index});
    await assert.rejects(f.load(), error => error === f.refusal);
    assert.equal(f.state.nativeQuotes, index);assert.equal(f.state.nativeRestores, index - 1);
    assert.equal(f.state.nativeExports, index - 1);assert.equal(f.retire(), false);
    await f.inventory.fail(f.refusal);assert.equal(f.retire(), true);assert.equal(f.state.takes, 1);
    assert.equal(f.state.sourceCloses + f.state.effectCloses, 0);
  });
}

test('component catalog missing native quote refuses without restore or export fallback', async t => {
  const f = await catalogFixture(t, {missingNative: 1});
  await assert.rejects(f.load(), {code: 'InstalledSourceDeclarationCapacityUnavailable'});
  assert.equal(f.state.nativeRestores, 0);assert.equal(f.state.nativeExports, 0);
  await f.inventory.fail(new Error('missing exact native quantity'));assert.equal(f.retire(), true);
});

test('component catalog malformed entry is refused inside its original funded projection', async t => {
  const f = await catalogFixture(t, {malformedEntry: true});
  await assert.rejects(f.load(), SyntaxError);
  assert.equal(f.state.nativeQuotes, 0);assert.equal(f.state.nativeRestores, 0);
  assert.equal(f.retire(), false);
  await f.inventory.fail(new Error('malformed original entry'));assert.equal(f.retire(), true);
});

test('component native input cannot substitute for the final prepared Source tuple', async t => {
  const f = await fixture(t), source = await f.begin();
  const input = Object.freeze({fixture: 'earlier-js-stage'});
  assert.equal(source.prepareNativeInput(Object.freeze({capacity: () => Object.freeze({fixture: 'input-quote'}),
    project: () => input})), input);
  await assert.rejects(source.load(f.sourceOptions()), {code: 'DeclaredFileInstallationAlreadyConstructed'});
  const prepared = source.prepareNativeDeclaration(f.projection());
  const adapter = await source.load(f.sourceOptions());
  assert.equal(adapter.admitsSource('connector://crm_primary/records#records'), true);
  assert.notEqual(input, prepared);
  await adapter.close();await f.inventory.fail(new Error('component complete'));assert.equal(f.retire(), true);
});


test('component catalog Entry quantity refusal precedes its first JavaScript parse', async t => {
  const f = await catalogFixture(t, {refuseEntry: true});
  const parse = JSON.parse;
  let entryParses = 0;
  JSON.parse = function(value, ...args) {
    if (value === f.state.entryWire) entryParses++;
    return Reflect.apply(parse, this, [value, ...args]);
  };
  try {await assert.rejects(f.load(), error => error === f.refusal);}
  finally {JSON.parse = parse;}
  assert.equal(f.state.entryQuotes, 1);assert.equal(entryParses, 0);
  assert.equal(f.state.nativeQuotes, 0);assert.equal(f.state.nativeRestores, 0);
  await f.inventory.fail(f.refusal);assert.equal(f.retire(), true);
});


for (const thrown of [undefined, null]) test(`component ${String(thrown)} native-input failure stays failed and retains original cleanup ownership`, async t => {
  const f = await fixture(t), source = await f.begin(), earlier = await f.begin(1);
  earlier.prepareNativeDeclaration(f.projection('crm_secondary'));
  const adapter = await earlier.load(f.sourceOptions('crm_secondary'));
  let attempts = 0, caught = false;
  const projection = Object.freeze({capacity: () => Object.freeze({fixture: 'input-quote'}),
    project() {attempts++;throw thrown;}});
  try {source.prepareNativeInput(projection);}
  catch (cause) {caught = true;assert.equal(cause, thrown);}
  assert.equal(caught, true);assert.equal(attempts, 1);
  const different = Object.freeze({capacity: () => Object.freeze({fixture: 'different-input-quote'}),
    project() {attempts++;return {};}});
  assert.throws(() => source.prepareNativeInput(different), {code: 'DeclaredFileInstallationClosed'});
  assert.throws(() => source.prepareNativeDeclaration(f.projection()), {code: 'DeclaredFileInstallationClosed'});
  await assert.rejects(source.load(f.sourceOptions()), {code: 'DeclaredFileInstallationClosed'});
  assert.equal(attempts, 1);assert.equal(f.state.projections, 1);
  const failure = await source.cleanup(thrown);
  assert.equal(failure.code, 'InstalledHostInitializationFailed');
  assert.equal(Object.hasOwn(failure, 'primaryFailure'), true);assert.equal(failure.primaryFailure, thrown);
  assert.equal(Object.hasOwn(failure, 'cause'), true);assert.equal(failure.cause, thrown);
  f.state.sourcePending = true;
  await assert.rejects(adapter.close(), error => error === f.pendingClose);
  await f.inventory.fail(thrown);assert.equal(f.retire(), false);
  f.state.sourcePending = false;await adapter.close();
  assert.equal(f.retire(), true);assert.equal(f.state.retires, 1);
});

test('installed catalog requires its exact live inventory before metadata constructors', async t => {
  const f = await catalogFixture(t);
  const base = {directory: f.root, catalogFile: 'catalog.json', dataFile: 'absent-data.json',
    connections: f.connectionOriginal.connections, connectionOriginal: f.connectionOriginal,
    assertCurrent() {}, openFile() {assert.fail('No diagnostic read fallback');}};
  const before = f.events.length;
  for (const inventory of [undefined, {}, {...f.inventory}]) {
    await assert.rejects(loadDeclaredProjectCatalog(f.moon, {...base, installationInventory: inventory}),
      {code: 'ForeignDeclaredFileInstallation'});
  }
  await assert.rejects(loadDeclaredProjectCatalog({...f.moon}, {...base, installationInventory: f.inventory}),
    {code: 'ForeignDeclaredFileInstallation'});
  await assert.rejects(loadDeclaredProjectCatalog(f.moon, {...base, installationInventory: f.inventory,
    connectionOriginal: {...f.connectionOriginal, project: {}}}), {code: 'ForeignDeclaredFileInstallation'});
  assert.equal(f.events.length, before);
  assert.equal(f.state.nativeRestores, 0);
  await f.inventory.fail(new Error('closed original'));
  await assert.rejects(loadDeclaredProjectCatalog(f.moon, {...base, installationInventory: f.inventory}),
    {code: 'DeclaredFileInstallationClosed'});
});


test('catalog entrypoints reject changing inventory accessors without invoking them', async t => {
  const f = await catalogFixture(t);let gets = 0;
  for (const load of [loadDeclaredProjectCatalog, inspectDeclaredProjectCatalog]) {
    const options = {directory: f.root, catalogFile: 'catalog.json', dataFile: 'absent-data.json',
      connections: f.connectionOriginal.connections, connectionOriginal: f.connectionOriginal,
      assertCurrent() {}, get installationInventory() {gets++;return gets % 2 ? f.inventory : undefined;}};
    const before = f.events.length;
    await assert.rejects(load(f.moon, options), {code: 'ForeignDeclaredFileInstallation'});
    assert.equal(f.events.length, before);
  }
  assert.equal(gets, 0);assert.equal(f.state.nativeRestores, 0);
  await f.inventory.fail(new Error('accessor refusal complete'));
});
