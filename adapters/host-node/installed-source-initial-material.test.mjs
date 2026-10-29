import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createInstalledHostServices, retainInstalledHostServiceInstallation,
  installedSourceConfigurationReader, beginInstalledSourceInitialization,
  assertInstalledSourceConstruction, retainInstalledSourceConstruction,
  closeInstalledSourceConstruction, finishInstalledSourceInitialization,
  completeInstalledSourceInitialization, borrowInstalledSourceInitialization,
  retireInstalledSourceInitialization} from './installed-host-services.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {loadInstalledSource} from './installed-source.mjs';
import {readSourceProfileJson} from './source-profile-json.mjs';

const ok = value => ({$tag: 1, _0: value});
const baseWire = JSON.stringify({version: 'actql-check-environment/0.1',
  connector_catalogs: [], schema_snapshots: [], connector_capabilities: [],
  source_views: [], contract_registry: []});
const views = [{resource: 'users', resource_kind: 'fixture', schema_wire: '{}', schema_cid: 'original'}];

// These are explicit original Core/Resource ports. This tests the actual
// service/loader/native I/O composition, NOT a compiled Ledger, real Account,
// RowRun, normal constructor admission or physical Source stop qualification.
function fixture() {
  const initial = {}, input = {}, unit = {}, capacity = {}, events = [];
  let takes = 0, selected, originalEnvironment, live = 0, retiring = false, refuse = false, onReserve;
  const moon = {
    clientProgramTakeHostInitializationSourceCapacity(owner) {
      assert.equal(this, moon); assert.equal(owner, initial); assert.equal(takes++, 0);
      events.push('take'); return ok({_0: input, _1: unit});
    },
    clientProgramContinueInstalledSourceMaterial(value, original) {
      assert.equal(value, unit); assert.equal(original, input); events.push('continue'); return ok(capacity);
    },
    clientProgramInstalledSourceConstructionCapacity(...counts) {
      assert(counts.every(value => typeof value === 'bigint' && value >= 0n));
      events.push(['quote', ...counts]); return ok(Object.freeze(counts));
    },
    clientProgramReserveInstalledSourceConstruction(value, original, quote) {
      assert.equal(value, capacity); assert.equal(original, input);
      events.push(['reserve', quote]);
      if (refuse) throw new Error('same original parent refusal');
      onReserve?.();
      return ok(undefined);
    },
    clientProgramReconcileInstalledSourceConstruction(value, original, quote) {
      assert.equal(value, capacity); assert.equal(original, input);
      assert.deepEqual(quote.slice(3), [0n, 0n, 0n]); events.push('reconcile'); return ok(undefined);
    },
    clientProgramCompleteInstalledSourceMaterial(value, original, source, environment) {
      assert.equal(value, capacity); assert.equal(original, input); assert.equal(source, input);
      originalEnvironment = environment; events.push('complete'); return ok(undefined);
    },
    clientProgramBorrowInstalledSourceMaterial(value) {
      assert.equal(value, capacity); assert.equal(retiring, false); live++;
      return ok({environment: originalEnvironment, returned: false});
    },
    clientProgramBorrowedInstalledSourceEnvironment(holder, original) {
      assert.equal(original, input); assert.equal(holder.returned, false); return ok(holder.environment);
    },
    clientProgramReturnInstalledSourceMaterial(holder) {
      assert.equal(holder.returned, false); holder.returned = true; live--; return ok(retiring && live === 0);
    },
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity); assert.equal(original, input); retiring = true;
      events.push('retire'); return ok(live === 0);
    },
    clientProgramAbortUncontinuedSourceMaterial() {assert.fail('no uncontinued abort');},
    clientProgramRowSourceRestoreRelationDeclaration(connector, registration, revision, wire, expected) {
      assert.equal(this, moon); assert.equal(connector, 'fixture');
      assert.equal(registration, 'service_fixture'); assert.equal(revision, 'service_fixture/0.1');
      assert.deepEqual(JSON.parse(wire), {views}); assert.equal(expected, undefined);
      selected = {}; events.push('restore'); return ok(selected);
    },
    clientProgramRowSourceDeclarationJson(value) {
      assert.equal(value, selected); events.push('declared');
      return JSON.stringify({evidence_schemas: [], evidence_capabilities: [], view_bodies: [],
        contracts: [], catalog: '{}', manifest_entry: '{}'});
    },
  };
  const services = createInstalledHostServices({root: '/UNOPENED/initial-service', principalId: 'fixture',
    moon, initialPreparation: initial, assertCurrent() {}});
  return {services, moon, input, initial, events, takes: () => takes,
    refuse() {refuse = true;}, duringReserve(fn) {onReserve = fn;}};
}

test('normal loader reserves original profile identity and declaration before provider construction', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-source-material-'));
  const path = join(root, 'profile.json'), metadata = join(root, 'site.json'), runtime = join(root, 'runtime.mjs');
  await writeFile(path, JSON.stringify({version: 'actql-installed-service-fixture/0.1', connectorId: 'fixture'}));
  await writeFile(metadata, '{"same":"λ\r\noriginal"}'.replace('\r\n', '\\r\\n'));
  await writeFile(runtime, '// Explicit loader component runtime identity.\n');
  const f = fixture();
  let originalContext, originalPrepared, originalAdapter, identityReads = 0;
  const module = {
    check(profile) {
      assert.deepEqual(f.events.slice(0, 2), ['take', 'continue']);
      assert(f.events.includes('reconcile')); return profile;
    },
    async identityParts(profile, provider, read, installation, context) {
      const site = await read(metadata); identityReads++;
      assert.equal(context.configurationReader, installedSourceConfigurationReader(f.services));
      return [profile, provider, site];
    },
    load(profile, options) {
      assert.equal(options.installationServices, f.services);
      assert.equal(options.readerCapacity, undefined);
      originalContext = options.sourceInitialization;
      originalPrepared = originalContext.prepareDeclaration(views);
      assertInstalledSourceConstruction(originalContext, originalPrepared.declaration,
        originalPrepared.declared, originalPrepared.environment);
      assert.throws(() => assertInstalledSourceConstruction(originalContext,
        originalPrepared.declaration, {...originalPrepared.declared}, originalPrepared.environment),
      {code: 'ForeignInstalledSourceConstruction'});
      originalAdapter = Object.freeze({connectorRegistration: 'service_fixture', connectorRevision: 'service_fixture/0.1',
        environmentWire: originalPrepared.environment.wire, close() {
          closeInstalledSourceConstruction(originalContext, originalAdapter);
        }});
      retainInstalledSourceConstruction(originalContext, originalAdapter, originalPrepared.declaration,
        originalPrepared.declared, originalPrepared.environment);
      return originalAdapter;
    },
  };
  const connectorTable = createInstalledConnectorTable([{name: 'service_fixture', registration: 'service_fixture',
    revision: 'service_fixture/0.1', source: {profileVersion: 'actql-installed-service-fixture/0.1', load: async () => module}}]);
  const source = await loadInstalledSource(path, {root, principalId: 'fixture', moon: f.moon,
    runtimeUrl: pathToFileURL(runtime), baseEnvironmentWire: baseWire, connectorTable, installationServices: f.services});
  assert.equal(f.takes(), 1); assert.equal(identityReads, 2);
  assert(f.events.findIndex(value => Array.isArray(value) && value[0] === 'reserve') < f.events.indexOf('restore'));
  assert.throws(() => originalContext.prepareDeclaration.call({...originalContext}, views),
    {code: 'ForeignInstalledSourceInitialization'});
  const environment = {};
  completeInstalledSourceInitialization(f.services, f.input, environment, source.environmentWire);
  assert.throws(() => borrowInstalledSourceInitialization(f.services, {...f.input}, environment),
    {code: 'ForeignInstalledSourceMaterial'});
  const held = borrowInstalledSourceInitialization(f.services, f.input, environment);
  assert.equal(held.environment(), environment);
  assert.equal(retireInstalledSourceInitialization(f.services), false, 'original Source has not closed');
  await source.close();
  assert.equal(retireInstalledSourceInitialization(f.services), false, 'same Request borrow remains');
  assert.equal(held.release(), true);
  assert.throws(() => held.environment(), {code: 'ForeignInstalledSourceMaterial'});
  assert.equal(retireInstalledSourceInitialization(f.services), true);
  await assert.rejects(installedSourceConfigurationReader(f.services).readJson(path),
    {code: 'InstalledSourceInitializationClosed'});
});

test('original parent refusal precedes configuration open and missing runtime precedes one-shot take', async () => {
  const f = fixture(); f.refuse();
  const reader = installedSourceConfigurationReader(f.services);
  await assert.rejects(reader.readJson('/UNOPENED/never-opened.json'), /same original parent refusal/);
  assert.equal(f.takes(), 1);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
  const absent = fixture(); delete absent.moon.clientProgramCompleteInstalledSourceMaterial;
  assert.throws(() => installedSourceConfigurationReader(absent.services),
    {code: 'InstalledSourceInitializationRuntimeUnavailable'});
  assert.equal(absent.takes(), 0);
});

test('native decode reserves before concat and retains the same failed file cleanup without retrying read', async () => {
  const f = fixture(), installation = Object.freeze({registration: 'service_fixture', revision: 'service_fixture/0.1'});
  retainInstalledHostServiceInstallation(f.services, installation, 'sha256:' + 'a'.repeat(64));
  const context = beginInstalledSourceInitialization(f.services, installation, 'fixture', baseWire);
  let reads = 0, closes = 0, allowClose = false, failure;
  const originalFailure = new Error('same original native capacity refusal');
  try {
    await readSourceProfileJson('/UNOPENED/native-component', {maxBytes: 8,
      openFile: async () => ({async read(buffer) {
        if (reads++ === 0) {buffer.set(Buffer.from('{"x":1}')); return {bytesRead: 7};}
        return {bytesRead: 0};
      }, async close() {closes++; if (!allowClose) throw new Error('same FD pending');}}),
      beforeDecode(bytes) {assert.equal(bytes, 7); throw originalFailure;}});
    assert.fail('decode should refuse');
  } catch (cause) {failure = cause;}
  assert.equal(failure.cause, originalFailure); assert.equal(reads, 2); assert.equal(closes, 1);
  finishInstalledSourceInitialization(context, undefined, failure, true);
  assert.equal(retireInstalledSourceInitialization(f.services), false);
  allowClose = true; await failure.cleanupHandle.retry();
  assert.equal(reads, 2); assert.equal(closes, 2);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Source declaration retains original view strings across current and freezes only its original projection', () => {
  const f = fixture(), installation = Object.freeze({registration: 'service_fixture', revision: 'service_fixture/0.1'});
  retainInstalledHostServiceInstallation(f.services, installation, 'sha256:' + 'a'.repeat(64));
  const context = beginInstalledSourceInitialization(f.services, installation, 'fixture', baseWire);
  const authored = structuredClone(views);
  f.duringReserve(() => {authored[0].schema_wire = 'foreign replacement';});
  const prepared = context.prepareDeclaration(authored);
  assert.equal(authored[0].schema_wire, 'foreign replacement');
  assert.equal(Object.isFrozen(prepared.declared), true);
  assert.equal(Object.isFrozen(prepared.declared.view_bodies), true);
  assert.throws(() => {prepared.declared.view_bodies.push('foreign');}, TypeError);
  assertInstalledSourceConstruction(context, prepared.declaration, prepared.declared, prepared.environment);
  const originalFailure = new Error('same constructor failure after preparation');
  finishInstalledSourceInitialization(context, undefined, originalFailure, true);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
  assert.throws(() => context.prepareDeclaration(authored), {code: 'ForeignInstalledSourceInitialization'});
});

test('normal configuration reader refuses an explicit null bound before reservation or open', async () => {
  const f = fixture(), reader = installedSourceConfigurationReader(f.services);
  await assert.rejects(reader.readJson('/UNOPENED/null-is-not-the-default.json', {maxBytes: null}),
    {code: 'InvalidInstalledSourceProfileByteLimit'});
  assert.equal(f.events.filter(value => Array.isArray(value) && value[0] === 'reserve').length, 0);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});
