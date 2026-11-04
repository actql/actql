import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {createInstalledHostServices, retireInstalledSourceInitialization,
  retainInstalledHostServiceInstallation, installedSourceConfigurationReader,
  beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization, finishInstalledSourceInitialization,
  bindInstalledSourceConstruction, retainBoundInstalledSourceFailure,
  assertInstalledSourceConstruction, retainInstalledSourceConstruction,
  closeInstalledSourceConstruction, readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';
import {loadInstalledSource} from './installed-source.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {checkInstalledDuckDBSourceProfile} from './installed-duckdb-source.mjs';

// Actual loader, Source owner and configuration FD. Semantic Resource and
// Environment admission remain explicit ports; this stops before Account,
// native-library loading, a DuckDB connection or a Request can be constructed.
test('builtin Source enters its original checked Environment before native construction', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-builtin-source-owner-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const f = await publishedFixture(() => {}, () => {}, root);
  const {moon, services, events, baseWire, sourceWire} = f;
  const profile = {version: 'actql-installed-duckdb-source/0.1',
    database: '/UNOPENED/builtin-source.duckdb', schema: 'main', table: 'records',
    sourceRef: 'connector://crm/main/r#v', checkEnvironmentWire: sourceWire,
    accountConfigurationWire: '{"version":"UNEXECUTED"}',
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']}};
  const path = join(root, 'profile.json'), runtimePath = join(root, 'runtime.mjs');
  await writeFile(path, JSON.stringify(profile));
  await writeFile(runtimePath, 'export const originalSoftwareIdentity = true;\n');
  const stop = new Error('same original Source Environment construction stop');
  const original = moon.clientProgramCheckEnvironmentFromWire;
  moon.clientProgramCheckEnvironmentFromWire = (raw, ...flags) => {
    const admitted = original(raw, ...flags);
    events.push(raw.wire === baseWire ? 'base' : 'source');
    if (raw.wire === sourceWire) throw stop;
    assert.equal(raw.wire, baseWire);
    return admitted;
  };
  await assert.rejects(loadInstalledSource(path, {root, principalId: 'fixture', moon,
    runtimeUrl: pathToFileURL(runtimePath), baseEnvironmentWire: baseWire, installationServices: services}),
  error => error === stop || error.primaryFailure === stop);
  assert.deepEqual(events.filter(event => event === 'base' || event === 'source'), ['base', 'source']);
  assert.equal(retireInstalledSourceInitialization(services), true);
  assert.equal(events.at(-1), 'retire');
});

async function publishedFixture(change = () => {}, reserve = () => {}, root = '/UNOPENED/builtin-owner') {
  const base = JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const source = JSON.parse(await readFile(new URL('./fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  source.host_policy_profile = base.host_policy_profile;
  change(source);
  delete source.evidence_bundle_cid;
  source.evidence_bundle_cid = contentCid(source);
  const baseWire = canonicalJson(base), sourceWire = canonicalJson(source);
  const initial = {}, input = {}, unit = {}, capacity = {}, installation = Object.freeze({}), events = [], live = new Set();
  const rawEnvironments = new WeakSet();
  const ok = value => ({$tag: 1, _0: value});
  const moon = Object.fromEntries(['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial', 'ChargeInstalledSourceIo', 'MarkInstalledSourceIoTransferUncertain']
    .map(name => ['clientProgram' + name, () => ok()]));
  Object.assign(moon, {
    strategyRemoteManagedOutputEvidenceKind: () => 'explicit-unused-kind',
    clientProgramRowSourceRestoreRelationDeclaration() {assert.fail('No Row declaration');},
    clientProgramRowSourceDeclarationJson() {assert.fail('No Row projection');},
    clientProgramTakeHostInitializationSourceCapacity(value) {assert.equal(value, initial); return ok({_0: input, _1: unit});},
    clientProgramContinueInstalledSourceMaterial(value, original) {assert.equal(value, unit); assert.equal(original, input); return ok(capacity);},
    clientProgramInstalledSourceConstructionCapacity: (...values) => ok({values}),
    clientProgramInstalledSourceRetainedConstructionCapacity(original) {
      assert.strictEqual(this, moon);
      assert.equal(typeof original, 'object');
      return ok(Object.freeze({retainedOriginal: original}));
    },
    clientProgramComposeInstalledSourceConstructionCapacity(base, providers) {
      assert.strictEqual(this, moon); assert(providers.length > 0);
      events.push('compose'); return ok({base, providers: providers.slice()});
    },
    clientProgramReserveInstalledSourceConstruction(value, original) {
      assert.equal(value, capacity); assert.equal(original, input); events.push('reserve'); reserve(events); return ok();
    },
    clientProgramBeginInstalledSourceIo() {const operation = {}; live.add(operation); return ok(operation);},
    clientProgramFinishInstalledSourceIoAfterCleanup(operation) {assert(live.delete(operation)); events.push('io-finish'); return ok();},
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity); assert.equal(original, input); assert.equal(live.size, 0); events.push('retire'); return ok(true);
    },
    clientProgramCheckEnvironmentWireConstructionCapacity(...census) {
      assert.equal(census.length, 14); assert(census.every(value => Number.isSafeInteger(value) && value >= 0));
      return Object.freeze({census});
    },
    clientProgramReadCheckEnvironmentWire(wire, evidenceCid) {
      assert(events.includes('reserve')); assert([baseWire, sourceWire].includes(wire));
      const {evidence_bundle_cid: original, ...body} = JSON.parse(wire);
      assert.equal(evidenceCid, original); assert.equal(evidenceCid, contentCid(body));
      const raw = Object.freeze({wire, evidenceCid}); rawEnvironments.add(raw); return raw;
    },
    clientProgramCheckEnvironmentFromWireConstructionCapacity(raw) {
      assert(rawEnvironments.has(raw)); return Object.freeze({raw});
    },
    clientProgramCheckEnvironmentFromWire(raw, ...flags) {
      assert(rawEnvironments.has(raw)); assert.deepEqual(flags, [false, false, true, false, false, false, false]);
      events.push('check'); return Object.freeze({raw});
    },
    clientProgramCheckEnvironment() {assert.fail('the original native Environment is not rechecked through a legacy path');},
  });
  const services = createInstalledHostServices({root, principalId: 'fixture',
    moon, initialPreparation: initial, assertCurrent() {}});
  retainInstalledHostServiceInstallation(services, installation, 'sha256:' + 'a'.repeat(64));
  installedSourceConfigurationReader(services);
  return {services, installation, moon, events, live, baseWire, sourceWire};
}

async function nativeConstructor(ports) {
  const moduleURL = new URL('./installed-duckdb-source.mjs', import.meta.url);
  const text = await readFile(moduleURL, 'utf8');
  const at = text.indexOf('export async function createInstalledDuckDBSource(');
  assert(at >= 0);
  // Keep the original module URL for its actual contract paths. The selected
  // native-library and semantic/Account ports are explicit, not imported code.
  const body = text.slice(at).replaceAll('import.meta.url', 'moduleURL');
  return Function(...Object.keys(ports), 'moduleURL',
    body.replace('export async function', 'async function') + '\nreturn createInstalledDuckDBSource;')
  (...Object.values(ports), moduleURL);
}

test('builtin native constructor keeps original Environment contracts and pending gate retirement', async () => {
  const f = await publishedFixture();
  // The existing Context entrance returns its SAME admitted Environment.
  // This component supplies the independent fixture connector; the actual
  // automatic selector is covered through the public loader/selector cases.
  const context = beginInstalledSourceInitialization(f.services, f.installation, 'crm/main', f.baseWire);
  const environment = context.preparePublishedEnvironment(f.sourceWire);
  let canClose = false, closes = 0, nativeLoads = 0;
  const authorization = Object.freeze({close() {assert.equal(this, authorization); closes++; return canClose;}});
  const ports = {assertInstalledSourceConstruction, retainInstalledSourceConstruction,
    closeInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
    loadDuckDBNativeRuntime() {nativeLoads++;}, checked: value => value,
    contentCid, duckDBPhysicalTarget, computePhysicalCapacity() {assert.fail('No Request capacity call');},
    capturedDuckDBRequirement() {assert.fail('No capture');}, capturedDuckDBPendingCapacity() {assert.fail('No capture');},
    capturedDuckDBPhysicalCapacity() {assert.fail('No capture');}, capturedDuckDBConfiguration() {assert.fail('No capture');},
    prepareCapturedDuckDBSource() {assert.fail('No source prepare');}, openCapturedDuckDBSource() {assert.fail('No physical acquisition');}, readFile};
  const construct = await nativeConstructor(ports);
  const profile = {environmentWire: f.sourceWire, database: '/UNOPENED/original.duckdb', schema: 'main', table: 'records',
    sourceRef: 'connector://crm/main/r#v', sourceAccess: {authorization}, readAuthorization: {}, acquisitionPlanning: {}};
  await assert.rejects(construct(profile, f.moon, {root: '/UNOPENED/builtin-owner', principalId: 'fixture',
    sourceInitialization: {...context}, environment}), {code: 'ForeignInstalledSourceConstruction'});
  assert.equal(nativeLoads, 0, 'copied original refuses before native loader');
  const adapter = await construct(profile, f.moon, {root: '/UNOPENED/builtin-owner', principalId: 'fixture',
    sourceInitialization: context, environment});
  finishInstalledSourceInitialization(context, adapter);
  assert.equal(nativeLoads, 1);
  assert(f.events.includes('compose'), 'the original common native Environment capacity stays in its construction quote');
  assert.equal(f.events.filter(event => event === 'check').length, 2, 'same Environment is not reissued');
  // Each small protocol file has its original FD lease, stat, body read and EOF read.
  assert.equal(f.events.filter(event => event === 'io-finish').length, 12);
  assert.equal(f.live.size, 0, 'all original protocol I/O operations have finished');
  assert.equal(retireInstalledSourceInitialization(f.services), false, 'adapter still owns the original gate');
  assert.throws(() => adapter.close(), /InstalledSourceAuthorizationCleanupPending/);
  assert.equal(retireInstalledSourceInitialization(f.services), false);
  assert.equal(closes, 1);
  assert.equal(adapter.admitsSource(profile.sourceRef), false);
  assert.throws(() => adapter.managedCaptureCapacity({}), /InstalledSourceReaderNotCurrent/);
  assert.throws(() => adapter.managedEffectPlanSelection(), /InstalledSourceReaderNotCurrent/);
  canClose = true; adapter.close(); adapter.close();
  assert.equal(closes, 2);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

async function boundBuiltinMethod(ports) {
  const text = await readFile(new URL('./installed-host-services.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('    async createDuckDBSource() {');
  const end = text.indexOf('    async createTableSource(options) {', start);
  assert(start > 0 && end > start);
  return Function(...Object.keys(ports), 'return ({' + text.slice(start, end) + '}).createDuckDBSource;')(...Object.values(ports));
}

for (const kind of ['profile-wrapper', 'post-gate-current']) {
  test('builtin bound constructor retains original gate through ' + kind + ' failure', async () => {
    const original = new Error('same original ' + kind), gate = {}, profile = {}, moon = {}, environment = {};
    const checkedProfile = {}, material = {inputs: []}, owned = {attempted: false, constructing: false};
    const scope = {role: 'source', publishedEnvironment: true, connectorId: 'crm/main', prepared: {environment}};
    const events = [];
    const method = await boundBuiltinMethod({scope, material, owned, checkedProfile, context: {},
      original: {root: '/UNOPENED', principalId: 'fixture', moon},
      current() {events.push('current'); if (kind === 'post-gate-current' && owned.authorization === gate) throw original;},
      fail(code) {throw Object.assign(new Error(code), {code});},
      reserveInstalledDuckDBConstruction(o, m, p, e) {
        assert.equal(o.moon, moon); assert.equal(m, material); assert.equal(p, checkedProfile);
        assert.equal(e, environment); events.push('reserve');
      },
      async installDuckDBSourceProfile(p, options) {
        assert.equal(p, checkedProfile); assert.equal(options.runtime, moon);
        assert(events.includes('reserve')); options.retainAuthorization(gate);
        assert.equal(owned.authorization, gate);
        if (kind === 'profile-wrapper') throw original;
        return profile;
      },
      createInstalledDuckDBSource() {assert.fail('No native constructor after original failure');},
    });
    await assert.rejects(method(), error => error === original);
    assert.equal(owned.authorization, gate); assert(material.inputs.includes(gate));
    assert.equal(owned.constructing, false); assert.equal(owned.attempted, true);
    if (kind === 'post-gate-current') await assert.rejects(method(), error => error === original);
    else await assert.rejects(method(), {code: 'InstalledSourceConstructionUnavailable'});
  });
}

for (const [kind, change, code] of [
  ['original snapshot member', () => {}, undefined],
  ['foreign source reference', source => {source.schema_snapshots[0].source_ref += '/foreign';}, 'InstalledSourceProgramMismatch'],
  ['foreign Catalog contract', source => {source.schema_snapshots[0].source_view_contract_cid = 'sha256:' + 'f'.repeat(64);}, 'InstalledSourceProgramMismatch'],
  ['ambiguous snapshot member', source => {source.schema_snapshots.push({...source.schema_snapshots[0]});}, 'InstalledSourceBindingAmbiguous'],
]) {
  test('builtin published Source selects only ' + kind + ' before its bound constructor', async () => {
    // Semantic admission is explicit here. The selector must still preserve
    // the exact correspondence and keep every partial on its original owner.
    const f = await publishedFixture(change);
    const begin = () => beginInstalledPublishedSourceInitialization(f.services, f.installation,
      'connector://crm/main/r#v', f.sourceWire, f.baseWire);
    if (code === undefined) {
      const context = begin();
      assert.equal(retireInstalledSourceInitialization(f.services), false);
      assert.throws(() => context.preparePublishedEnvironment(f.sourceWire),
        {code: 'ForeignInstalledSourceInitialization'});
      finishInstalledSourceInitialization(context, undefined, new Error('original selected constructor stop'), true);
    } else assert.throws(begin, {code});
    assert.equal(f.events.filter(event => event === 'check').length, 2);
    assert.equal(retireInstalledSourceInitialization(f.services), true);
  });
}

for (const kind of ['backing-refusal', 'original-Account']) {
  test('builtin bound Source reserves original construction before ' + kind, async () => {
    const stop = new Error('same original ' + kind);
    let constructing = false, constructorReservations = 0;
    const f = await publishedFixture(undefined, () => {
      if (!constructing) return;
      constructorReservations++;
      if (kind === 'backing-refusal') throw stop;
    });
    let admits = 0;
    for (const name of ['Admit', 'Missing', 'AccountJson', 'Evaluate', 'EvaluationJson',
      'EvaluationAction', 'Prepare', 'RequestJson', 'Answer', 'DecisionJson']) {
      f.moon['executionAuthorization' + name] = () => {assert.fail('No later Account callback');};
    }
    f.moon.executionAuthorizationAdmit = wire => {
      assert.equal(wire, '{"originalAccount":true}'); admits++;
      assert.equal(constructorReservations, 1, 'the original DuckDB constructor is backed before Account admission');
      throw stop;
    };
    const context = beginInstalledPublishedSourceInitialization(f.services, f.installation,
      'connector://crm/main/r#v', f.sourceWire, f.baseWire);
    const profile = checkInstalledDuckDBSourceProfile({version: 'actql-installed-duckdb-source/0.1',
      database: '/UNOPENED/builtin-owner/original.duckdb', schema: 'main', table: 'records',
      sourceRef: 'connector://crm/main/r#v', checkEnvironmentWire: f.sourceWire,
      accountConfigurationWire: '{"originalAccount":true}',
      acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']}});
    const bound = bindInstalledSourceConstruction(f.services, context, profile);
    // Environment parse/model constructors already own their separate
    // reservations. Select this actual constructor phase, not their ordinal.
    constructing = true;
    await assert.rejects(bound.createDuckDBSource(), cause => cause === stop);
    assert.equal(constructorReservations, 1);
    constructing = false;
    assert.equal(admits, kind === 'backing-refusal' ? 0 : 1);
    await assert.rejects(bound.createDuckDBSource(), {code: 'InstalledSourceConstructionUnavailable'});
    const failure = await retainBoundInstalledSourceFailure(context, stop);
    finishInstalledSourceInitialization(context, undefined, failure, true);
    assert.equal(retireInstalledSourceInitialization(f.services), true);
  });
}

test('native capture-only entry forwards the same original Ledger and acquisition promise', async () => {
  const capture = {}, completion = Promise.resolve(capture), calls = [];
  const authorization = Object.freeze({close() {assert.strictEqual(this, authorization); return true;}});
  const profile = {environmentWire: '{"connector_catalogs":[]}', database: '/UNOPENED/original.duckdb',
    schema: 'main', table: 'records', sourceRef: 'source:original', sourceAccess: {authorization},
    transportLimits: {}, acquisitionPlanning: {}};
  const moon = {};
  const construct = await nativeConstructor({loadDuckDBNativeRuntime() {}, readFile,
    contentCid, duckDBPhysicalTarget,
    openCapturedDuckDBSource(options) {calls.push(options); return completion;}});
  const adapter = await construct(profile, moon, {root: '/UNOPENED/original', principalId: 'fixture'});
  const ledger = {}, preparedProgram = {}, preparedSource = {}, signal = new AbortController().signal;
  const options = {preparedProgram, preparedSource, sourceAccess: profile.sourceAccess, ledger, signal};
  assert.strictEqual(adapter.openCapture(options), completion);
  assert.equal(calls.length, 1);
  assert.strictEqual(calls[0].ledger, ledger);
  assert.strictEqual(calls[0].preparedProgram, preparedProgram);
  assert.strictEqual(calls[0].preparedSource, preparedSource);
  assert.strictEqual(calls[0].sourceAccess, profile.sourceAccess);
  assert.strictEqual(calls[0].signal, signal);
  assert.strictEqual(await completion, capture);
  assert.throws(() => adapter.openCapture({...options, ledger: undefined}), /InstalledSourceCaptureLedgerUnavailable/);
  adapter.close();
  assert.throws(() => adapter.openCapture(options), /InstalledSourceReaderNotCurrent/);
  assert.equal(calls.length, 1, 'neither missing Ledger nor retired Source can reopen the original');
});
