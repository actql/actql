import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as loader from './installed-effect.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {createInstalledHostServices, retainInstalledHostServiceInstallation,
  retireInstalledSourceInitialization, beginInstalledSourceInitialization, finishInstalledSourceInitialization,
  assertInstalledSourceConstruction, retainInstalledSourceConstruction, closeInstalledSourceConstruction, reserveInstalledSourceEnvironment, prepareInstalledSourceAcquisitionContracts, installedSourceConfigurationReader, readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {loadInstalledGitHubEffect, INSTALLED_GITHUB_EFFECT_VERSION} from '../connectors/github/host/installed-github-effect.mjs';

// Exercise the actual bounded reader with real files. Only the physical close
// call is faulted on the actual imported reader; no parser or Owner is replaced.
async function readerFixture(t, contents, falseClose = false) {
  const root = await fs.mkdtemp(join(tmpdir(), 'actql-effect-profile-close-'));
  const path = join(root, 'profile.json');
  await fs.writeFile(path, contents);
  const open = fs.open;
  let original;
  const io = {state: {remaining: 2, calls: 0, released: 0, reads: 0, opens: 0},
    closeFailure: new Error('InjectedProfileCloseFailure')};
  fs.open = async (name, ...args) => {
    const file = await open(name, ...args);
    if (name !== path) return file;
    io.state.opens++;
    original = file;
    return {read(...values) { io.state.reads++; return file.read(...values); }, async close() {
      io.state.calls++;
      if (io.state.remaining-- > 0) {
        if (falseClose) return false;
        throw io.closeFailure;
      }
      await file.close(); io.state.released++;
    }};
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = open;
    syncBuiltinESMExports();
    await original?.close();
    await fs.rm(root, {recursive: true, force: true});
  });
  return {loader, io, path, fd: () => original?.fd};
}

// Real profile/runtime-byte readers, table selection and Host service registry;
// no runtime module import, Common, Account/Site creation or grant is supplied.
async function serviceFixture(t, {onCheck = value => value, onLoad} = {}) {
  const root = await fs.mkdtemp(join(tmpdir(), 'actql-effect-service-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const profilePath = join(root, 'profile.json'), runtimePath = join(root, 'runtime-identity.mjs');
  const version = 'actql-installed-effect-service-fixture/0.1';
  const runtimeBytes = 'export const fixtureIdentityOnly = true;\n';
  await fs.writeFile(profilePath, JSON.stringify({version})); await fs.writeFile(runtimePath, runtimeBytes);
  let calls = 0;
  const stop = Object.assign(new Error('OriginalInstallerStopBeforeSite'), {code: 'OriginalInstallerStopBeforeSite'});
  const connectorTable = createInstalledConnectorTable([{name: 'effect_service_fixture',
    registration: 'effect_service_fixture', revision: 'effect_service_fixture/0.1', effect: {
      profileVersion: version, load: async () => ({check: onCheck,
        identityParts() {assert.fail('load must not replay publication');},
        load(profile, options) {calls++; if (onLoad) onLoad(profile, options); throw stop;},
      }),
    }}]);
  const services = createInstalledHostServices({root, principalId: 'fixture', moon: {}, assertCurrent() {}});
  const options = {root, principalId: 'fixture', moon: {}, runtimeUrl: pathToFileURL(runtimePath),
    baseEnvironmentWire: '{}', connectorTable, installationServices: services};
  return {root, profilePath, runtimePath, runtimeCid: 'sha256:' + createHash('sha256').update(runtimeBytes).digest('hex'),
    services, options, stop, calls: () => calls};
}

test('Effect load forwards the same registered Host service before the original installer', async t => {
  let f;
  f = await serviceFixture(t, {onLoad(profile, options) {
    assert.equal(options.installationServices, f.services);
    assert.equal(options.runtimeBundleCid, f.runtimeCid);
    assert.ok(Object.isFrozen(options.installation));
    assert.throws(() => retainInstalledHostServiceInstallation(f.services, options.installation,
      `sha256:${'f'.repeat(64)}`), {code: 'InstalledHostServiceRuntimeChanged'});
  }});
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, f.options), error => error === f.stop);
  assert.equal(f.calls(), 1);
});

test('Effect load pins one original runtime and refuses replacement before installer reentry', async t => {
  const f = await serviceFixture(t);
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, f.options), error => error === f.stop);
  const changed = join(f.root, 'other-runtime-identity.mjs');
  await fs.writeFile(changed, 'export const fixtureIdentityOnly = false;\n');
  await assert.rejects(loader.loadInstalledEffect(f.profilePath,
    {...f.options, runtimeUrl: pathToFileURL(changed)}), {code: 'InstalledHostServiceRuntimeChanged'});
  assert.equal(f.calls(), 1);
});

test('Effect load refuses a copied Host service before installer or Site acquisition', async t => {
  const f = await serviceFixture(t);
  await assert.rejects(loader.loadInstalledEffect(f.profilePath,
    {...f.options, installationServices: Object.freeze({...f.services})}), {code: 'ForeignInstalledHostServices'});
  assert.equal(f.calls(), 0);
});

test('Effect load preserves original profile refusal before runtime identity or installer selection', async t => {
  const failure = new Error('OriginalProfileRefusal');
  const f = await serviceFixture(t, {onCheck() {throw failure;}});
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, {...f.options,
    runtimeUrl: pathToFileURL(join(f.root, 'missing-runtime'))}), error => error === failure);
  assert.equal(f.calls(), 0);
});

test('Effect load keeps the absent-service installer envelope unchanged', async t => {
  const f = await serviceFixture(t, {onLoad(_profile, options) {
    assert.equal(Object.hasOwn(options, 'installationServices'), false);
    assert.equal(Object.hasOwn(options, 'configurationReader'), false);
  }});
  const {installationServices: _unused, ...options} = f.options;
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, options), error => error === f.stop);
  assert.equal(f.calls(), 1);
});

// Real shared Effect loader, initial-material service and physical file readers.
// Resource/Core admission is explicit here; these counters do not supply a
// real Ledger, Site, grant, Host close or ordinary installed acceptance.
async function initialEffectFixture(t, {refuseReservation = false, suspended = false, undefinedFailure = false} = {}) {
  const root = await fs.mkdtemp(join(tmpdir(), 'actql-effect-initial-material-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const version = 'actql-installed-effect-initial-material-fixture/0.1', profilePath = join(root, 'profile.json');
  const runtimePath = join(root, 'identity.mjs'), metadataPath = join(root, 'site.json');
  const profileWire = JSON.stringify({version, connectorId: 'initial-effect-fixture'}), runtimeWire = 'export const original = true;\n';
  const metadataWire = '{"original":"site metadata"}';
  await fs.writeFile(profilePath, profileWire);await fs.writeFile(runtimePath, runtimeWire);await fs.writeFile(metadataPath, metadataWire);
  const initial = {}, input = {}, unit = {}, capacity = {}, events = [], live = new Set();
  const ok = value => ({$tag: 1, _0: value});
  let transferred = 0n, loaded = 0, entered, release;
  const enteredLoad = new Promise(done => {entered = done;}), hold = new Promise(done => {release = done;});
  const refusal = new Error('original initial reservation refusal'), installerFailure = new Error('original installer failure');
  const moon = {
    clientProgramRowSourceRestoreRelationDeclaration() {assert.fail('No native declaration in this prefix unit');},
    clientProgramRowSourceDeclarationJson() {assert.fail('No declaration output in this prefix unit');},
    clientProgramTakeHostInitializationSourceCapacity(value) {
      assert.equal(value, initial);events.push('take');return ok({_0: input, _1: unit});
    },
    clientProgramContinueInstalledSourceMaterial(value, original) {
      assert.equal(value, unit);assert.equal(original, input);events.push('continue');return ok(capacity);
    },
    clientProgramInstalledSourceConstructionCapacity(...values) {return ok(Object.freeze({values}));},
    clientProgramReserveInstalledSourceConstruction(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);events.push('reserve');
      if (refuseReservation) throw refusal;return ok();
    },
    clientProgramReconcileInstalledSourceConstruction: () => ok(),
    clientProgramCompleteInstalledSourceMaterial() {assert.fail('No completed installation in this prefix unit');},
    clientProgramBorrowInstalledSourceMaterial() {assert.fail('No Request borrow in this prefix unit');},
    clientProgramBorrowedInstalledSourceEnvironment() {assert.fail('No Request environment in this prefix unit');},
    clientProgramReturnInstalledSourceMaterial() {assert.fail('No Request return in this prefix unit');},
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);assert.equal(live.size, 0);events.push('retire');return ok(true);
    },
    clientProgramAbortUncontinuedSourceMaterial() {assert.fail('The same material continued');},
    clientProgramBeginInstalledSourceIo(value, original, bytes) {
      assert.equal(value, capacity);assert.equal(original, input);assert(events.includes('reserve'));
      const operation = {bytes};live.add(operation);events.push('begin');return ok(operation);
    },
    clientProgramChargeInstalledSourceIo(operation, bytes) {
      assert(live.has(operation));transferred += bytes;return ok();
    },
    clientProgramMarkInstalledSourceIoTransferUncertain() {assert.fail('No uncertain file read');},
    clientProgramFinishInstalledSourceIoAfterCleanup(operation) {assert(live.delete(operation));events.push('file-close');return ok();},
  };
  const services = createInstalledHostServices({root, principalId: 'fixture', moon,
    initialPreparation: initial, assertCurrent() {}});
  const connectorTable = createInstalledConnectorTable([{name: 'effect_initial_fixture',
    registration: 'effect_initial_fixture', revision: 'effect_initial_fixture/0.1', effect: {
      profileVersion: version, load: async () => ({check: value => value,
        identityParts() {assert.fail('Loading is not publication');},
        async load(profile, options) {
          loaded++;entered();
          if (suspended) await hold;
          else {
            assert(events.includes('take'), 'original initial owner before profile/runtime work');
            assert.equal(typeof options.configurationReader?.readJson, 'function');
            assert.deepEqual(await options.configurationReader.readJson(metadataPath), {original: 'site metadata'});
          }
          throw undefinedFailure ? undefined : installerFailure;
        },
      }),
    }}]);
  const options = {root, principalId: 'fixture', moon, runtimeUrl: pathToFileURL(runtimePath),
    baseEnvironmentWire: '{}', connectorTable, installationServices: services};
  return {profilePath, options, services, events, live, refusal, installerFailure, enteredLoad, release,
    counts: () => ({loaded, transferred}), expectedBytes: BigInt(Buffer.byteLength(profileWire + runtimeWire + metadataWire))};
}

test('Effect initial material owns profile runtime and installer metadata reads before native Site construction', async t => {
  const f = await initialEffectFixture(t);
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, f.options), error => error === f.installerFailure);
  assert.deepEqual(f.events.slice(0, 3), ['take', 'continue', 'reserve']);
  // Each small original file has one FD lease, one body read and one EOF
  // read. Read completions do not substitute for the original FD close.
  assert.equal(f.events.filter(value => value === 'begin').length, 3 * 3);
  assert.equal(f.events.filter(value => value === 'file-close').length, 3 * 3);
  assert.deepEqual(f.counts(), {loaded: 1, transferred: f.expectedBytes});assert.equal(f.live.size, 0);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect initial material reservation refusal precedes profile I/O and preserves the original failure', async t => {
  const f = await initialEffectFixture(t, {refuseReservation: true});
  await assert.rejects(loader.loadInstalledEffect(join(f.options.root, 'never-created-profile.json'), f.options), error => {
    assert.equal(error.code, 'InvalidInstalledEffectProfile');assert.equal(error.cause, f.refusal);return true;
  });
  assert.deepEqual(f.events, ['take', 'continue', 'reserve']);assert.equal(f.counts().loaded, 0);assert.equal(f.live.size, 0);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect initial material remains live through installer await and thrown undefined without a second load', async t => {
  const f = await initialEffectFixture(t, {suspended: true, undefinedFailure: true});
  const observed = loader.loadInstalledEffect(f.profilePath, f.options).then(value => ({ok: true, value}), error => ({ok: false, error}));
  await f.enteredLoad;
  try {
    assert.equal(retireInstalledSourceInitialization(f.services), false, 'same original load remains pending after its FD reads finish');
    assert.equal(f.events.includes('retire'), false);
  } finally {f.release();}
  assert.deepEqual(await observed, {ok: false, error: undefined});assert.equal(f.counts().loaded, 1);assert.equal(f.live.size, 0);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect false close remains in same initialization custody without a reread', async t => {
  const f = await readerFixture(t, '{}', true);
  let failure;
  await assert.rejects(f.loader.loadInstalledEffect(f.path, {}), error => {
    failure = error;
    assert.equal(error.code, 'InvalidInstalledEffectProfile');
    assert.equal(error.cleanupHandle.status().pending, true);
    return true;
  });
  assert(f.fd() >= 0);
  const reads = f.io.state.reads;
  const outer = await retainInstalledHostInitializationFailure(failure, {});
  assert.equal(outer.cleanupPending, false);
  assert.equal(f.fd(), -1);
  assert.equal(f.io.state.opens, 1);
  assert.equal(f.io.state.reads, reads);
  assert.equal(f.io.state.released, 1);
});

test('Effect identity callback forwards its Connector ceiling to shared acquisition', async t => {
  const root = await fs.mkdtemp(join(tmpdir(), 'actql-effect-identity-limit-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const profilePath = join(root, 'profile.json'), metadataPath = join(root, 'publication.json');
  const version = 'actql-installed-effect-ceiling-fixture/0.1';
  const profile = {version, metadataPath};
  await fs.writeFile(profilePath, JSON.stringify(profile));
  const connectorTable = createInstalledConnectorTable([{name: 'ceiling_fixture', effect: {
    profileVersion: version, load: async () => ({check: value => value,
      identityParts: async (value, read) => [value, await read(value.metadataPath, {maxBytes: 1048576})],
      load() { assert.fail('identity cannot acquire an Effect adapter'); },
    }),
  }}]);
  await fs.writeFile(metadataPath, '{}');
  const original = await loader.installedEffectIdentity(profilePath, {connectorTable});
  await fs.appendFile(metadataPath, ' '.repeat(1048576 - 2));
  assert.equal(await loader.installedEffectIdentity(profilePath, {connectorTable}), original);
  await fs.appendFile(metadataPath, ' ');
  await assert.rejects(loader.installedEffectIdentity(profilePath, {connectorTable}),
    {code: 'InvalidInstalledEffectProfile'});
});

for (const malformed of [false, true]) {
  test(`Effect profile close failure retains retry custody after ${malformed ? 'parse refusal' : 'successful read'}`, async t => {
    const {loader, io, path} = await readerFixture(t, malformed ? '{' : '{}');
    let failure;
    await assert.rejects(loader.loadInstalledEffect(path, {}), error => {
      failure = error;
      assert.equal(error.code, 'InvalidInstalledEffectProfile');
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle.status().pending, true);
      if (malformed) assert.equal(error.primaryFailure.name, 'SyntaxError');
      else assert.equal(error.primaryFailure, io.closeFailure);
      return true;
    });
    assert.equal(io.state.released, 0);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(io.state.released, 1);
    const calls = io.state.calls;
    await failure.cleanupHandle.retry();
    assert.equal(io.state.calls, calls, 'successful release is never repeated');
  });
}

// Actual loader, initial owner, Mapping/Environment constructor and RowEffect
// adapter together. Native semantic/Resource and Site ports are explicit:
// this is not a Common, Account, physical Site or normal public execution.
async function constructionFixture(t, {refuseMapping = false, beforeAdapter} = {}) {
  const root = await fs.mkdtemp(join(tmpdir(), 'actql-effect-initial-construction-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const version = 'actql-installed-effect-construction-fixture/0.1';
  const profilePath = join(root, 'profile.json'), runtimePath = join(root, 'runtime.mjs');
  await fs.writeFile(profilePath, JSON.stringify({version, connectorId: 'construction'}));
  await fs.writeFile(runtimePath, 'export const identityOnly = true;\n');
  const initial = {}, input = {}, unit = {}, capacity = {}, declaration = {}, events = [];
  const ok = value => ({$tag: 1, _0: value}), cid = 'sha256:' + 'a'.repeat(64);
  const declared = {evidence_schemas: [], evidence_capabilities: [], view_bodies: [],
    contracts: [], catalog: '{}', manifest_entry: '{}'};
  const environmentWire = JSON.stringify({version: 'actql-check-environment/0.1',
    connector_catalogs: [], schema_snapshots: [], connector_capabilities: [], mapping_contracts: []});
  const refusal = new Error('original Mapping backing refusal'), pendingClose = new Error('original Site cleanup pending');
  let mappingPhase = false, retained, prepared, installedOptions, closePending = true, nativeRetire = 0;
  const moon = Object.fromEntries(['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial', 'ChargeInstalledSourceIo', 'MarkInstalledSourceIoTransferUncertain',
    'FinishInstalledSourceIoAfterCleanup'].map(name => ['clientProgram' + name, () => ok()]));
  Object.assign(moon, {
    strategyRemoteManagedOutputEvidenceKind: () => 'explicit-unused-kind',
    clientProgramTakeHostInitializationSourceCapacity(value) {assert.equal(value, initial);return ok({_0: input, _1: unit});},
    clientProgramContinueInstalledSourceMaterial(value, original) {assert.equal(value, unit);assert.equal(original, input);return ok(capacity);},
    clientProgramInstalledSourceConstructionCapacity: (...values) => ok({values}),
    clientProgramReserveInstalledSourceConstruction(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);events.push('reserve');
      if (mappingPhase && refuseMapping) throw refusal;return ok();
    },
    clientProgramBeginInstalledSourceIo: () => ok({}),
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);nativeRetire++;return ok(true);
    },
    clientProgramRowSourceRestoreRelationDeclaration() {assert.equal(events.at(-1), 'reserve');events.push('declaration');return ok(declaration);},
    clientProgramRowSourceDeclarationJson(value) {assert.equal(value, declaration);return JSON.stringify(declared);},
    clientProgramRowSourcePrepareMapping(value, writes, resource, sources) {
      assert.equal(value, declaration);assert.equal(writes, '{"original":"writes"}');
      assert.equal(resource, 'records');assert.deepEqual(JSON.parse(sources), [{target: 'label', field: 'label', null_behavior: 'reject'}]);
      assert.equal(events.at(-1), 'reserve');events.push('mapping');
      return JSON.stringify({mapping_ref: 'mapping:construction/create.v1', mapping_cid: cid,
        body: JSON.stringify({mapping_contract_cid: cid, target_ref: 'connector://construction/records',
          minimum_approval: 'required', permission_rules: [{effect_kind: 'create', permissions: ['write']}]}),
        write_fields: ['label'], omittable: []});
    },
  });
  const services = createInstalledHostServices({root, principalId: 'fixture', moon,
    initialPreparation: initial, assertCurrent() {}});
  const writes = Object.freeze([Object.freeze({resource: 'records', sources: Object.freeze([
    Object.freeze({target: 'label', field: 'label', null_behavior: 'reject'})])})]);
  const unused = () => assert.fail('No provider/Account operation in this constructor component');
  const site = {issueEffectGrant: unused, issueReadGrant: unused,
    async close() {if (closePending === 'false') return false;if (closePending) throw pendingClose;}};
  const driver = {kinds: ['create'], prepareRequest: unused, requestFacts: unused,
    writeOperation: unused, send: unused, project: unused, footprint: unused};
  const connectorTable = createInstalledConnectorTable([{name: 'effect_construction_fixture',
    registration: 'effect_construction_fixture', revision: 'effect_construction_fixture/0.1', effect: {
      profileVersion: version, load: async () => ({check: value => value, identityParts: unused,
        async load(_profile, options) {
          retained = options.sourceInitialization;
          assert.equal(typeof retained?.prepareDeclaration, 'function', 'same original initial constructor before native work');
          prepared = retained.prepareDeclaration([], undefined);
          mappingPhase = true;
          prepared = retained.prepareMappings('{"original":"writes"}', writes);
          assert.equal(prepared.declaration, declaration);
          assert.equal(JSON.parse(prepared.environment.wire).mapping_contracts.length, 1);
          installedOptions = {moon, mappings: prepared.mappings, environmentWire: prepared.environment.wire,
            declaration, declared: prepared.declared, environment: prepared.environment, sourceInitialization: retained,
            connectorId: 'construction', connectorRegistration: options.installation.registration,
            connectorRevision: options.installation.revision, installation: options.installation,
            connection: 'explicit-construction', site, authorization: {authorize: unused},
            runtimeBundleCid: options.runtimeBundleCid, bindingCid: cid, ledgerRoot: join(root, 'ledger'), driver};
          await beforeAdapter?.(installedOptions);
          return createInstalledRowEffect(installedOptions);
        },
      }),
    }}]);
  return {run: () => loader.loadInstalledEffect(profilePath, {root, principalId: 'fixture', moon,
    runtimeUrl: pathToFileURL(runtimePath), baseEnvironmentWire: environmentWire, connectorTable, installationServices: services}),
    services, events, refusal, pendingClose, options: () => installedOptions,
    context: () => retained, writes,
    allowClose() {closePending = false;}, falseClose() {closePending = 'false';}, retired: () => nativeRetire};
}

test('Effect construction retains original Mapping Environment and adapter until the same Site cleanup', async t => {
  const f = await constructionFixture(t), adapter = await f.run();
  assert.equal(typeof adapter.prepareManagedPlan, 'function');
  assert.deepEqual(f.events.slice(-4), ['reserve', 'declaration', 'reserve', 'mapping']);
  assert.equal(retireInstalledSourceInitialization(f.services), false);
  await assert.rejects(adapter.close(), error => error === f.pendingClose);
  assert.equal(retireInstalledSourceInitialization(f.services), false);assert.equal(f.retired(), 0);
  f.allowClose();await adapter.close();
  assert.equal(retireInstalledSourceInitialization(f.services), true);assert.equal(f.retired(), 1);
});

test('Effect construction refuses Mapping backing before the native Mapping or Site constructor', async t => {
  const f = await constructionFixture(t, {refuseMapping: true});
  await assert.rejects(f.run(), error => error === f.refusal);
  assert.equal(f.events.includes('mapping'), false);assert.equal(f.options(), undefined);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect construction refuses copied context or changed original Environment without another constructor', async t => {
  const f = await constructionFixture(t, {async beforeAdapter(original) {
    for (const changed of [{sourceInitialization: Object.freeze({...original.sourceInitialization})},
      {environment: Object.freeze({...original.environment})}, {mappings: Object.freeze([...original.mappings])}]) {
      await assert.rejects(createInstalledRowEffect({...original, ...changed}), {code: 'ForeignInstalledSourceConstruction'});
    }
  }}), adapter = await f.run();
  assert.equal(f.events.filter(value => value === 'mapping').length, 1);
  f.allowClose();await adapter.close();assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect construction false Site close retains the same original initial body', async t => {
  const f = await constructionFixture(t), adapter = await f.run();f.falseClose();
  await assert.rejects(adapter.close(), {code: 'InstalledEffectSiteCleanupPending'});
  assert.equal(retireInstalledSourceInitialization(f.services), false);assert.equal(f.retired(), 0);
  f.allowClose();await adapter.close();assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('Effect construction failed Mapping reservation is sticky on the same original context', async t => {
  const f = await constructionFixture(t, {refuseMapping: true});
  await assert.rejects(f.run(), error => error === f.refusal);
  assert.throws(() => f.context().prepareMappings('{"original":"writes"}', f.writes),
    {code: 'ForeignInstalledSourceInitialization'});
  assert.equal(f.events.includes('mapping'), false);
  assert.equal(retireInstalledSourceInitialization(f.services), true);
});

test('GitHub Effect installer forwards original declaration Mapping and Site context before provider construction', async () => {
  const events = [], declaration = {}, declared = {}, environment = {wire: 'original-environment'}, mappings = [];
  const stop = new Error('original Site entrance'), installation = {};
  const profile = {version: INSTALLED_GITHUB_EFFECT_VERSION, connectorId: 'authored-github',
    siteProfilePath: '/UNOPENED/github-site.json', publicationPath: '/UNOPENED/github-publication.json',
    accountConfigurationWire: '{}', writes: [{resource: 'issue_comments',
      sources: [{target: 'body', field: 'body', null_behavior: 'reject'}]}]};
  const site = {version: 'actql-installed-github-site/0.1', apiOrigin: 'https://explicit.invalid', owner: 'owner', repo: 'repo',
    credentialAuthorityId: 'authored-authority', credentialKeyId: 'authored-key',
    credentialPrivateKeyPath: '/UNOPENED/key', environment: 'authored', journalRoot: '/UNOPENED/journal',
    namespaceId: 'authored-namespace', siteGeneration: 0, siteKey: 'authored-site', tokenEnvironment: 'ACTQL_AUTHORED_TOKEN'};
  const publication = {version: 'actql-github-publication/0.1', connectorId: profile.connectorId,
    apiOrigin: site.apiOrigin, owner: site.owner, repo: site.repo, catalogCid: 'sha256:' + 'a'.repeat(64),
    repository: {id: 1, node_id: 'authored-repository'}};
  const initialization = Object.freeze({prepareDeclaration(wire, expected) {
    assert.equal(this, initialization);assert.equal(expected, publication.catalogCid);
    assert.equal(wire, originals.get('source-views.json'));events.push('declaration');return {declaration, declared};
  }, prepareMappings(wire, writes) {
    assert.equal(this, initialization);assert.equal(wire, originals.get('writes.json'));
    assert.deepEqual(writes, profile.writes);assert(Object.isFrozen(writes));events.push('mappings');
    return {declaration, declared, environment, mappings};
  }});
  const originals = new Map();
  const reader = {async readJson(path) {
    assert.equal(this, reader);events.push(path === profile.siteProfilePath ? 'site-json' : 'publication-json');
    assert([profile.siteProfilePath, profile.publicationPath].includes(path));
    return path === profile.siteProfilePath ? site : publication;
  }, readText() {assert.fail('Published originals have no invented profile ceiling');},
  async readOriginalText(path) {
    assert.equal(this, reader);const name = new URL(path).pathname.split('/').at(-1);
    assert(['source-views.json', 'writes.json'].includes(name));const wire = await fs.readFile(path, 'utf8');
    originals.set(name, wire);events.push(name);return wire;
  }};
  const services = Object.freeze({openRowSite(options) {
    assert.equal(this, services);assert.equal(options.sourceInitialization, initialization);
    assert.equal(options.installation, installation);events.push('Site');throw stop;
  }});
  // Actual entire installer and shared Site helper; only initial constructor
  // and Site service ports are explicit. No native Common, grant or I/O Site.
  await assert.rejects(loadInstalledGitHubEffect(profile, {root: '/UNOPENED/root', principalId: 'authored',
    moon: {}, providerMoon: {installedStandardCreateHttpLimits() {
      events.push('native-http-limits');return [300000, 100000, 10000, 32];
    }}, baseEnvironmentWire: '{}', runtimeBundleCid: 'sha256:' + 'b'.repeat(64),
    ledgerRoot: '/UNOPENED/ledger', installation, installationServices: services,
    sourceInitialization: initialization, configurationReader: reader}), cause => cause === stop);
  assert.deepEqual(events, ['native-http-limits', 'site-json', 'publication-json', 'source-views.json', 'declaration', 'writes.json', 'mappings', 'Site']);
});


// Actual existing Source material/context and Environment assembler. Only
// native Core capacities/projection and current/retirement ports are explicit;
// this exercises ownership/order, not numeric backing or a physical ACK.
function commandConstructionFixture({refuseReserve = false, failProjection, duringReserve, role = 'effect', reserveAt = 2, additionalNative = [], contractQuantity, contractFailure, repeatedNative = false, retainedNative, failRetainedProjection, missingRetainedProjection = false} = {}) {
  const ok = value => ({$tag: 1, _0: value});
  const initial = {}, input = {}, unit = {}, capacity = {}, declaration = {}, native = {};
  const installed = Object.freeze({registration: 'sheets', revision: 'sheets/0.1', effect: {}});
  const cid = 'sha256:' + 'a'.repeat(64), commands = Object.freeze([Object.freeze({body: '{}'})]);
  const base = {catalog_cid: cid, catalog: '{}', contracts: [], view_bodies: [],
    evidence_schemas: [], evidence_capabilities: [], manifest_entry: '{}'};
  const declared = {...base, command_bodies: ['{}']};
  const events = [], quotes = [], reservedQuotes = [], completions = [], refusal = new Error('original command reservation refused'), contractOriginal={original:'contracts'};
  let reserveCalls = 0, retired = 0, context, pending;
  const originalIo=new Set();
  const moon = Object.fromEntries(['ReconcileInstalledSourceConstruction','CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial','BorrowedInstalledSourceEnvironment','ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial','BeginInstalledSourceIo','ChargeInstalledSourceIo',
    'MarkInstalledSourceIoTransferUncertain','FinishInstalledSourceIoAfterCleanup'].map(name => ['clientProgram' + name, () => ok()]));
  Object.assign(moon, {
    clientProgramBeginInstalledSourceIo(value,original,bytes) {assert.equal(value,capacity);assert.equal(original,input);assert.equal(typeof bytes,'bigint');const operation=Object.freeze({original:'fixture-io'});originalIo.add(operation);events.push('io-begin');return ok(operation);},
    clientProgramChargeInstalledSourceIo(operation,bytes) {assert(originalIo.has(operation));assert.equal(typeof bytes,'bigint');events.push('io-charge');return ok();},
    clientProgramFinishInstalledSourceIoAfterCleanup(operation) {assert(originalIo.delete(operation));events.push('io-finish');return ok();},
    clientProgramRowSourceAcquisitionContractsConstructionCapacity(...args) {events.push('contract-quantity');assert.deepEqual(args,[5,8]);return contractQuantity;},
    clientProgramRowSourceAdmitAcquisitionContracts(query,evidence) {assert.equal(query,'query');assert.equal(evidence,'evidence');events.push('admit-contract');if(contractFailure==='undefined')throw undefined;if(contractFailure==='async')return new Promise(resolve=>{pending=resolve;});return ok(contractOriginal);},
    clientProgramTakeHostInitializationSourceCapacity(value) {assert.equal(value, initial);return ok({_0: input, _1: unit});},
    clientProgramContinueInstalledSourceMaterial(value, original) {assert.equal(value, unit);assert.equal(original, input);return ok(capacity);},
    clientProgramInstalledSourceConstructionCapacity(...values) {return ok(Object.freeze({values}));},
    clientProgramInstalledSourceRetainedConstructionCapacity(value) {assert.equal(value,native);if(failRetainedProjection==='undefined')throw undefined;const retained=retainedNative??value;completions.push({original:value,retained});return ok(retained);},
    clientProgramComposeInstalledSourceConstructionCapacity(original, selected) {
      assert(selected[0]===native||retainedNative!==undefined&&selected[0]===retainedNative);if(repeatedNative)assert(selected.every(value=>value===native||value===retainedNative));else assert.deepEqual(selected.slice(1), selected.length === 1 ? [] : additionalNative);quotes.push({original, selected: [...selected]});return ok(Object.freeze({original, selected: Object.freeze([...selected])}));
    },
    clientProgramReserveInstalledSourceConstruction(value, original, quote) {
      assert.equal(value, capacity);assert.equal(original, input);reservedQuotes.push(quote);reserveCalls++;events.push('reserve');
      if (reserveCalls === reserveAt) {duringReserve?.(context);if (refuseReserve) throw refusal;}return ok();
    },
    clientProgramRetireInstalledSourceMaterial(value, original) {assert.equal(value, capacity);assert.equal(original, input);retired++;return ok(true);},
    clientProgramRowSourceRestoreRelationDeclaration(...args) {assert.equal(events.at(-1), 'reserve');events.push('restore');assert.equal(args[4], undefined);return ok(declaration);},
    clientProgramRowSourceDeclarationJson(value) {assert.equal(value, declaration);return JSON.stringify(base);},
  });
  if (missingRetainedProjection) delete moon.clientProgramInstalledSourceRetainedConstructionCapacity;
  const services = createInstalledHostServices({root: '/unopened-original-command-construction', principalId: 'fixture', moon,
    initialPreparation: initial, assertCurrent() {}});
  retainInstalledHostServiceInstallation(services, installed, cid);
  const environment = JSON.stringify({version:'actql-check-environment/0.1',connector_catalogs:[],schema_snapshots:[],
    connector_capabilities:[],mapping_contracts:[],command_contracts:[]});
  context = beginInstalledSourceInitialization(services, installed, 'sheets', environment, role);
  const projection = Object.freeze({capacity(wire) {
    assert.deepEqual(JSON.parse(wire), base);events.push('native-quantity');return native;
  }, project(wire) {
    assert.deepEqual(JSON.parse(wire), base);assert.equal(events.at(-1), 'reserve');events.push('project');
    if (failProjection === 'undefined') throw undefined;
    if (failProjection === 'async') return new Promise(resolve => {pending = resolve;});
    return Object.freeze({declared, commands, definition: Object.freeze({installed:commands[0]}), wire:JSON.stringify(declared)});
  }});
  return {context,services,projection,commands,declared,declaration,quotes,reservedQuotes,completions,events,refusal,contractOriginal,installed,moon,native,environment,
    prepare:expected=>context.prepareDeclaredCommands('{"views":[]}',projection,expected),
    finish:()=>finishInstalledSourceInitialization(context, undefined, new Error('original unit terminal'), true),
    retire:()=>retireInstalledSourceInitialization(services), retired:()=>retired,originalIo,
    // Native Promise settlement is independent of constructor refusal.
    getPending:()=>pending};
}

test('Command Source initialization retains same final Environment and original commands after one parent reserve', () => {
  const f = commandConstructionFixture(), prepared = f.prepare();
  assert.equal(prepared.declaration, f.declaration);assert.equal(prepared.declared, f.declared);
  assert.equal(prepared.commands, f.commands);assert.deepEqual(JSON.parse(prepared.environment.wire).command_contracts, [{}]);
  assert.deepEqual(f.events, ['reserve','restore','native-quantity','reserve','project','reserve']);
  assert(f.quotes.length >= 2);assert(f.quotes.every(value => value.selected[0] === f.quotes[0].selected[0]));
  assert.doesNotThrow(()=>assertInstalledSourceConstruction(f.context,f.declaration,f.declared,prepared.environment,undefined,[],f.commands));
  assert.throws(()=>assertInstalledSourceConstruction(f.context,f.declaration,f.declared,prepared.environment,undefined,[],[...f.commands]),{code:'ForeignInstalledSourceConstruction'});
  assert.throws(()=>assertInstalledSourceConstruction(f.context,f.declaration,f.declared,prepared.environment,undefined,[{}],f.commands),{code:'ForeignInstalledSourceConstruction'});
  assert.throws(()=>f.context.prepareMappings('{}',Object.freeze([])),{code:'ForeignInstalledSourceInitialization'});
  assert.throws(()=>f.prepare(),{code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);assert.equal(f.retired(),1);
});

test('Command native backing refusal never enters original projection or reissues declaration', () => {
  const f = commandConstructionFixture({refuseReserve:true});
  assert.throws(()=>f.prepare(),error=>error===f.refusal);
  assert.deepEqual(f.events,['reserve','restore','native-quantity','reserve']);
  assert.throws(()=>f.prepare(),{code:'ForeignInstalledSourceInitialization'});
  assert.equal(f.retire(),false);f.finish();assert.equal(f.retire(),true);
});

test('Command projection keeps thrown undefined sticky and rejects reentrant original construction', () => {
  const f = commandConstructionFixture({failProjection:'undefined',duringReserve(context) {
    assert.throws(()=>context.prepareDeclaration([]),{code:'ForeignInstalledSourceInitialization'});
  }});
  let thrown=false;try {f.prepare();}catch(cause){thrown=true;assert.equal(cause,undefined);}assert.equal(thrown,true);
  assert.throws(()=>f.prepare(),{code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);
});

test('invalid async Command projection stays with same Source until original settlement without becoming success', async () => {
  const f = commandConstructionFixture({failProjection:'async'});
  assert.throws(()=>f.prepare(),{code:'InstalledSourceConstructorNotSynchronous'});
  f.finish();assert.equal(f.retire(),false);assert.equal(f.retired(),0);
  // The fixture keeps the original resolver separately; no replacement
  // callback is used as a physical or semantic acknowledgement.
  const resolve = f.getPending();
  assert.equal(typeof resolve, 'function');resolve({original:'late-invalid-result'});
  await Promise.resolve();await Promise.resolve();
  assert.equal(f.retire(),true);assert.equal(f.retired(),1);
  assert.throws(()=>f.prepare(),{code:'ForeignInstalledSourceInitialization'});
});

test('Source read target is constructed only after SAME parent funds its retained original native peak',()=>{
  const quantity={},target={original:'reference'},f=commandConstructionFixture({role:'source',additionalNative:[quantity]});
  const prepared=f.prepare();let capacityCalls=0,projectCalls=0;
  const result=f.context.prepareReadTarget(Object.freeze({capacity(){capacityCalls++;return quantity;},project(){
    assert.equal(f.events.at(-1),'reserve');projectCalls++;return target;
  }}));
  assert.equal(result,target);assert.equal(Object.isFrozen(target),true);assert.equal(capacityCalls,1);assert.equal(projectCalls,1);
  assert.equal(f.quotes.at(-1).selected[1],quantity);
  assert.doesNotThrow(()=>assertInstalledSourceConstruction(f.context,f.declaration,f.declared,prepared.environment,undefined,undefined,f.commands));
  assert.throws(()=>f.context.prepareReadTarget(Object.freeze({capacity(){assert.fail('No reissue');},project(){assert.fail('No reconstruction');}})),
    {code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);
});

test('Source read target backing refusal retains original obligation without entering or retrying the native constructor',()=>{
  const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity],refuseReserve:true,reserveAt:4});
  f.prepare();let calls=0;
  const projection=Object.freeze({capacity(){return quantity;},project(){calls++;return {};}});
  assert.throws(()=>f.context.prepareReadTarget(projection),error=>error===f.refusal);
  assert.equal(calls,0);assert.equal(f.quotes.at(-1).selected[1],quantity);
  assert.throws(()=>f.context.prepareReadTarget(projection),{code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);
});

test('Source read target preserves thrown undefined and rejects original reentrant preparation',()=>{
  const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity]});f.prepare();
  const projection=Object.freeze({capacity(){return quantity;},project(){
    assert.throws(()=>f.context.prepareReadTarget(projection),{code:'ForeignInstalledSourceInitialization'});throw undefined;
  }});
  let caught=false;try{f.context.prepareReadTarget(projection);}catch(cause){caught=true;assert.equal(cause,undefined);}
  assert.equal(caught,true);assert.throws(()=>f.context.prepareReadTarget(projection),{code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);
});

test('invalid async Source target remains refused and retained until SAME original settles',async()=>{
  const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity]});f.prepare();let resolve;
  const pending=new Promise(done=>{resolve=done;});
  assert.throws(()=>f.context.prepareReadTarget(Object.freeze({capacity(){return quantity;},project(){return pending;}})),
    {code:'InstalledSourceConstructorNotSynchronous'});
  f.finish();assert.equal(f.retire(),false);assert.equal(f.retired(),0);
  resolve({original:'late invalid reference'});await Promise.resolve();await Promise.resolve();
  assert.equal(f.retire(),true);assert.equal(f.retired(),1);
});

for(const refuseReserve of [false,true])test(`Effect driver construction retains SAME Source backing and original retirement: refusal ${refuseReserve}`,()=>{
  const quantity={},f=commandConstructionFixture({role:'effect',additionalNative:[quantity],refuseReserve,reserveAt:4});
  f.prepare();let projected=0;
  const original={driver:Object.freeze({original:'driver'}),target:Object.freeze({original:'target'})};
  const projection=Object.freeze({capacity(){return quantity;},project(){
    projected++;assert.equal(f.events.at(-1),'reserve');
    assert.throws(()=>f.context.prepareEffectDriverConstruction(projection),{code:'ForeignInstalledSourceInitialization'});
    return original;
  }});
  assert.throws(()=>f.context.prepareReadTarget(projection),{code:'ForeignInstalledSourceInitialization'});
  assert.throws(()=>f.context.prepareEffectDriverConstruction.call({},projection),{code:'ForeignInstalledSourceInitialization'});
  if(refuseReserve)assert.throws(()=>f.context.prepareEffectDriverConstruction(projection),cause=>cause===f.refusal);
  else assert.equal(f.context.prepareEffectDriverConstruction(projection),original);
  assert.equal(projected,refuseReserve?0:1);assert.equal(f.quotes.at(-1).selected[1],quantity);
  assert.throws(()=>f.context.prepareEffectDriverConstruction(projection),{code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);assert.equal(f.retired(),1);
});

for(const refuseReserve of [false,true])test(`Source protocols use one native constructor quantity before admission and keep failure sticky: ${refuseReserve}`,()=>{
 const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity],contractQuantity:quantity,refuseReserve,reserveAt:4});f.prepare();
 const prepare=()=>prepareInstalledSourceAcquisitionContracts(f.context,'query','evidence');
 if(refuseReserve)assert.throws(prepare,cause=>cause===f.refusal);else assert.equal(prepare(),f.contractOriginal);
 assert.equal(f.events.filter(x=>x==='contract-quantity').length,1);assert.equal(f.events.filter(x=>x==='admit-contract').length,refuseReserve?0:1);
 assert.equal(f.quotes.at(-1).selected[1],quantity);assert.throws(prepare,{code:'InstalledSourceAcquisitionContractsAlreadyPrepared'});
 f.finish();assert.equal(f.retire(),true);assert.equal(f.retired(),1);
});
test('Source protocol admission retains thrown undefined after original native backing without reconstruction',()=>{
 const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity],contractQuantity:quantity,contractFailure:'undefined'});f.prepare();let caught=false;
 try{prepareInstalledSourceAcquisitionContracts(f.context,'query','evidence');}catch(cause){caught=true;assert.equal(cause,undefined);}assert.equal(caught,true);
 assert.throws(()=>prepareInstalledSourceAcquisitionContracts(f.context,'query','evidence'),{code:'InstalledSourceAcquisitionContractsAlreadyPrepared'});
 f.finish();assert.equal(f.retire(),true);
});
test('Source protocol text uses the SAME original file reader before native contract construction',async t=>{
 const f=commandConstructionFixture({role:'source'}),reader=installedSourceConfigurationReader(f.services);f.prepare();
 const root=await fs.mkdtemp(join(tmpdir(),'actql-source-protocol-input-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const path=join(root,'protocol.json');await fs.writeFile(path,'query');
 const original=reader.readOriginalText;assert.equal(Object.isFrozen(reader),true);
 assert.equal(await readInstalledSourceAcquisitionContract(f.context,path),'query');assert.equal(reader.readOriginalText,original);
 assert.equal(f.events.includes('admit-contract'),false);f.finish();assert.equal(f.retire(),true);
 await assert.rejects(readInstalledSourceAcquisitionContract(f.context,path),{code:'ForeignInstalledSourceInitialization'});
});

test('invalid async Source protocol admission stays with SAME Source until settlement without becoming a holder',async()=>{
 const quantity={},f=commandConstructionFixture({role:'source',additionalNative:[quantity],contractQuantity:quantity,contractFailure:'async'});f.prepare();
 assert.throws(()=>prepareInstalledSourceAcquisitionContracts(f.context,'query','evidence'),{code:'InstalledSourceConstructorNotSynchronous'});
 f.finish();assert.equal(f.retire(),false);assert.equal(f.retired(),0);
 f.getPending()({$tag:1,_0:f.contractOriginal});await Promise.resolve();await Promise.resolve();
 assert.equal(f.retire(),true);assert.equal(f.retired(),1);
 assert.throws(()=>prepareInstalledSourceAcquisitionContracts(f.context,'query','evidence'),{code:'ForeignInstalledSourceInitialization'});
});


test('SAME parent Command Effect retains the original live Source Environment without constructing or charging it twice',()=>{
  const f=commandConstructionFixture({role:'source',repeatedNative:true}),first=f.prepare(),source={original:'source'};
  retainInstalledSourceConstruction(f.context,source,f.declaration,f.declared,first.environment);
  finishInstalledSourceInitialization(f.context,source);
  const effect=beginInstalledSourceInitialization(f.services,f.installed,'sheets',f.environment,'effect');
  const prepared=effect.prepareDeclaredCommands('{"views":[]}',f.projection);
  assert.equal(prepared.environment,first.environment,'Reuse only this original same-parent immutable Environment');
  assert.equal(prepared.declaration,f.declaration);assert.equal(prepared.commands,f.commands);
  assert.equal(f.quotes.at(-1).selected.length,2,'Both original native peaks remain charged; no refund or deduplication');
  assert.deepEqual(f.quotes.at(-1).original.values.slice(3),[0n,0n,0n],
    'SAME current boundary without another Environment workspace');
  finishInstalledSourceInitialization(effect,undefined,new Error('fixture construction terminal'),true);
  assert.equal(f.retire(),false,'The original Source is still held');
  closeInstalledSourceConstruction(f.context,source);assert.equal(f.retire(),true);
});


test('identical Source and Effect Environment inputs cross the original semantic admission once and select the SAME constructor quote',async()=>{
  const {composeInstalledCheckEnvironment}=await import('./installed-check-environment.mjs');
  const {canonicalJson,contentCid}=await import('./local-account-config.mjs');
  const {withFixtureConnector}=await import('../host-common/connector-manifest.fixture.mjs');
  const base=(await fs.readFile(new URL('../../spec/local-check-environment.json',import.meta.url),'utf8')).trimEnd();
  const body=JSON.parse(base);delete body.evidence_bundle_cid;
  withFixtureConnector(body,'connector://source-effect/records');
  const source=canonicalJson({...body,evidence_bundle_cid:contentCid(body)}),calls=[];
  // Actual composer/encoding/base checks, explicit pure Core admission port.
  // This measures original boundary calls, not Core internals or runtime time.
  const admission={clientProgramCheckEnvironment(wire){calls.push(wire);return {};}};
  assert.equal(composeInstalledCheckEnvironment(admission,base,source,source),source);
  assert.deepEqual(calls,[base,source],'No duplicate semantic admission or recomposition for identical complete input');
  const f=commandConstructionFixture(),prepared=f.prepare();
  reserveInstalledSourceEnvironment(f.services,base,source,undefined);
  const single=f.quotes.at(-1).original.values;
  reserveInstalledSourceEnvironment(f.services,base,source,source);
  assert.deepEqual(f.quotes.at(-1).original.values,single,'Quote and actual composer select the SAME complete inputs');
  assert.equal(f.quotes.at(-1).selected.length,1,'Existing native debt is unchanged');
  f.finish();assert.equal(f.retire(),true);
});


for(const difference of ['entry','base','declared-wire','closed-source','failed-source']){
  test(`Command Environment handoff refuses to alias a different or unavailable original: ${difference}`,()=>{
    const f=commandConstructionFixture({role:'source',repeatedNative:true}),first=f.prepare(),source={original:'source'};
    retainInstalledSourceConstruction(f.context,source,f.declaration,f.declared,first.environment);
    finishInstalledSourceInitialization(f.context,source,undefined,difference==='failed-source');
    if(difference==='closed-source')closeInstalledSourceConstruction(f.context,source);
    const entry=difference==='entry'?Object.freeze({...f.installed}):f.installed;
    if(entry!==f.installed)retainInstalledHostServiceInstallation(f.services,entry,'sha256:'+'a'.repeat(64));
    const base=difference==='base'?' '+f.environment:f.environment;
    const effect=beginInstalledSourceInitialization(f.services,entry,'sheets',base,'effect');
    const projection=difference!=='declared-wire'?f.projection:Object.freeze({
      capacity:f.projection.capacity,
      project(wire){const original=f.projection.project(wire);
        // The declared CID stays equal: complete changed input must still
        // construct its own Environment, not upgrade from a CID match.
        const declared={...original.declared,command_bodies:['{"literal":"different"}']};
        return {...original,declared,wire:JSON.stringify(declared)};}});
    const prepared=effect.prepareDeclaredCommands('{"views":[]}',projection);
    assert.notEqual(prepared.environment,first.environment);
    assert(f.reservedQuotes.at(-1).original.values.slice(3).every(value=>value>0n),
      'Distinct input must fund its own existing Environment construction');
    assert.equal(f.quotes.at(-1).selected.length,2);
    finishInstalledSourceInitialization(effect,undefined,new Error('fixture terminal'),true);
    closeInstalledSourceConstruction(f.context,source);assert.equal(f.retire(),true);
  });
}

test('selected original Source Environment cannot be reused or reconstructed after current reenters its close',()=>{
  let f,source;
  f=commandConstructionFixture({role:'source',repeatedNative:true,reserveAt:6,
    duringReserve(){closeInstalledSourceConstruction(f.context,source);}});
  const first=f.prepare();source={original:'source'};
  retainInstalledSourceConstruction(f.context,source,f.declaration,f.declared,first.environment);
  finishInstalledSourceInitialization(f.context,source);
  const effect=beginInstalledSourceInitialization(f.services,f.installed,'sheets',f.environment,'effect');
  assert.throws(()=>effect.prepareDeclaredCommands('{"views":[]}',f.projection),
    {code:'ForeignInstalledSourceInitialization'});
  assert.deepEqual(f.quotes.at(-1).original.values.slice(3),[0n,0n,0n],
    'No unselected reconstruction after loss of the original');
  assert.throws(()=>effect.prepareDeclaredCommands('{"views":[]}',f.projection),
    {code:'ForeignInstalledSourceInitialization'});
  assert.equal(f.retire(),false);
  finishInstalledSourceInitialization(effect,undefined,new Error('fixture terminal'),true);
  assert.equal(f.retire(),true);
});

test('original Environment handoff is private to its own initial parent and cannot outlive retirement',()=>{
  const f=commandConstructionFixture({role:'source',repeatedNative:true}),first=f.prepare(),source={original:'source'};
  retainInstalledSourceConstruction(f.context,source,f.declaration,f.declared,first.environment);
  finishInstalledSourceInitialization(f.context,source);
  const foreign=commandConstructionFixture(),other=foreign.prepare();
  assert.notEqual(other.environment,first.environment);
  foreign.finish();assert.equal(foreign.retire(),true);
  closeInstalledSourceConstruction(f.context,source);assert.equal(f.retire(),true);
  assert.throws(()=>beginInstalledSourceInitialization(f.services,f.installed,'sheets',f.environment,'effect'),
    {code:'InstalledSourceInitializationClosed'});
});


for(const difference of ['policy','body-with-old-cid','conflicting-catalog','physical-binding']){
  test(`same-wire Environment composition preserves independent admission and binding refusal: ${difference}`,async()=>{
    const {composeInstalledCheckEnvironment,verifyInstalledConnectorBindings}=await import('./installed-check-environment.mjs');
    const {canonicalJson,contentCid}=await import('./local-account-config.mjs');
    const {withFixtureConnector}=await import('../host-common/connector-manifest.fixture.mjs');
    const base=(await fs.readFile(new URL('../../spec/local-check-environment.json',import.meta.url),'utf8')).trimEnd();
    const original=JSON.parse(base);delete original.evidence_bundle_cid;
    withFixtureConnector(original,'connector://source-effect/records');
    const seal=body=>canonicalJson({...body,evidence_bundle_cid:contentCid(body)}),source=seal(original);
    const admission={clientProgramCheckEnvironment(){return {};}};
    if(difference==='physical-binding'){
      assert.equal(composeInstalledCheckEnvironment(admission,base,source,source),source);
      const adapter=site=>({environmentWire:source,connectorBindings:[{
        connectorId:'source-effect',bindingCid:contentCid({site})}]});
      assert.throws(()=>verifyInstalledConnectorBindings(adapter('original-a'),adapter('original-b')),
        {code:'InstalledCheckEnvironmentConflict'});
    }else{
      const body=structuredClone(original);let effect,first=source;
      if(difference==='policy'){
        body.host_policy_profile.capacity.max_effect_items++;
        first=effect=seal(body);
      }else if(difference==='body-with-old-cid'){
        body.connector_catalogs[0].connector_version='changed';
        first=effect=canonicalJson({...body,evidence_bundle_cid:JSON.parse(source).evidence_bundle_cid});
      }else{
        const catalog=body.connector_catalogs[0];catalog.connector_version='changed';
        const {catalog_cid:ignored,...catalogBody}=catalog;void ignored;catalog.catalog_cid=contentCid(catalogBody);
        body.connector_manifest.connectors[0].connector_version='changed';effect=seal(body);
      }
      assert.throws(()=>composeInstalledCheckEnvironment(admission,base,first,effect),
        {code:'InstalledCheckEnvironmentConflict'});
    }
  });
}

test('Environment quote shares only its paired role input and preserves all additional original occurrences',()=>{
  const f=commandConstructionFixture();f.prepare();
  reserveInstalledSourceEnvironment(f.services,'base','source','source','source');
  const paired=f.quotes.at(-1).original.values;
  reserveInstalledSourceEnvironment(f.services,'base','source',undefined,'source');
  assert.deepEqual(paired,f.quotes.at(-1).original.values);
  reserveInstalledSourceEnvironment(f.services,'base','source',undefined);
  assert(paired[3]>f.quotes.at(-1).original.values[3],'Additional occurrence stays funded');
  f.finish();assert.equal(f.retire(),true);
});


test('closed Command completion keeps its actual retained output quantity before the next original constructor',()=>{
  const output=Object.freeze({original:'retained-output'}),f=commandConstructionFixture({retainedNative:output});
  const prepared=f.prepare();assert.equal(prepared.declaration,f.declaration);
  assert.equal(f.completions.length,1);assert.equal(f.completions[0].original,f.native);
  assert.equal(f.completions[0].retained,output);
  assert.equal(f.reservedQuotes[0].selected,undefined);
  assert.equal(f.reservedQuotes[1].selected[0],f.native,'Full original peak before projection');
  assert.equal(f.reservedQuotes[2].selected[0],output,'Returned original output stays before Environment construction');
  assert.equal(f.quotes.at(-1).selected[0],output,'Same output stays until original Source retirement');
  f.finish();assert.equal(f.retire(),true);
});

for(const failure of ['reserve','projection','retained-projection']){
  test(`closed Command output cannot retire an incomplete original constructor: ${failure}`,()=>{
    const f=commandConstructionFixture({retainedNative:{original:'output'},
      refuseReserve:failure==='reserve',failProjection:failure==='projection'?'undefined':undefined,
      failRetainedProjection:failure==='retained-projection'?'undefined':undefined});
    let thrown=false,cause;
    try{f.prepare();}catch(error){thrown=true;cause=error;}
    assert.equal(thrown,true);assert.equal(cause,failure==='reserve'?f.refusal:undefined);
    assert.equal(f.completions.length,0);
    assert.equal(f.quotes.at(-1).selected[0],f.native,'Full original native debt remains');
    assert.throws(()=>f.prepare(),{code:'ForeignInstalledSourceInitialization'});
    assert.equal(f.retire(),false);f.finish();assert.equal(f.retire(),true);
  });
}

test('invalid asynchronous Command keeps its original peak and pending child without selecting retained output',async()=>{
  const f=commandConstructionFixture({failProjection:'async',retainedNative:{original:'output'}});
  assert.throws(()=>f.prepare(),{code:'InstalledSourceConstructorNotSynchronous'});
  assert.equal(f.completions.length,0);assert.equal(f.quotes.at(-1).selected[0],f.native);
  f.finish();assert.equal(f.retire(),false);
  f.getPending()({original:'late-invalid-output'});await Promise.resolve();await Promise.resolve();
  assert.equal(f.completions.length,0);assert.equal(f.retire(),true);
});

test('closed Command missing retained DATA port refuses before original constructor entry',()=>{
  const f=commandConstructionFixture({missingRetainedProjection:true});
  assert.throws(()=>f.prepare(),{code:'InstalledSourceInitializationRuntimeUnavailable'});
  assert.deepEqual(f.events,[]);assert.equal(f.completions.length,0);
  f.finish();assert.equal(f.retire(),true);
});

test('native Source input and original declaration stay on the same pre-reserved initializer',()=>{
  const f=commandConstructionFixture({role:'source',repeatedNative:true});
  const events=[];
  const input=f.context.prepareInputConstruction(Object.freeze({
    capacity(){events.push('input-quantity');return f.native;},
    project(){assert.equal(f.events.at(-1),'reserve');events.push('input');return Buffer.from('original');},
  }));
  const material=Object.freeze({input,description:Object.freeze({original:'description'})});
  const prepared=f.context.prepareNativeDeclaration(Object.freeze({
    capacity(){events.push('declaration-quantity');return f.native;},
    project(){assert.equal(f.events.at(-1),'reserve');events.push('declaration');
      return Object.freeze({declaration:f.declaration,material});},
  }));
  assert.strictEqual(prepared.declaration,f.declaration);
  assert.strictEqual(prepared.material,material);
  assert.equal(prepared.environment.wire,JSON.stringify(JSON.parse(prepared.environment.wire)));
  assert.doesNotThrow(()=>assertInstalledSourceConstruction(f.context,prepared.declaration,
    prepared.declared,prepared.environment));
  assert.deepEqual(events,['input-quantity','input','declaration-quantity','declaration']);
  assert.deepEqual(f.quotes.at(-1).selected,[f.native,f.native]);
  assert.throws(()=>f.context.prepareNativeDeclaration(Object.freeze({capacity(){return f.native;},project(){assert.fail('no second original');}})),
    {code:'ForeignInstalledSourceInitialization'});
  f.finish();assert.equal(f.retire(),true);
});

test('native Source input reservation refuses before allocation and cannot retry its failed original',()=>{
  const f=commandConstructionFixture({role:'source',refuseReserve:true,reserveAt:1});
  let entered=0;
  const projection=Object.freeze({capacity(){return f.native;},project(){entered++;return Buffer.alloc(8);}});
  assert.throws(()=>f.context.prepareInputConstruction(projection),cause=>cause===f.refusal);
  assert.equal(entered,0);
  assert.throws(()=>f.context.prepareInputConstruction(projection),{code:'ForeignInstalledSourceInitialization'});
  assert.equal(entered,0);assert.equal(f.retire(),false);
  f.finish();assert.equal(f.retire(),true);
});

test('native Source construction preserves thrown undefined and refuses foreign or reentrant entry',()=>{
  for(const method of ['prepareInputConstruction','prepareNativeDeclaration']){
    const f=commandConstructionFixture({role:'source'});let entered=0;
    const projection=Object.freeze({capacity(){return f.native;},project(){entered++;
      assert.throws(()=>f.context[method](projection),{code:'ForeignInstalledSourceInitialization'});
      throw undefined;}});
    assert.throws(()=>Reflect.apply(f.context[method],Object.freeze({}),[projection]),
      {code:'ForeignInstalledSourceInitialization'});
    let threw=false;
    try{f.context[method](projection);}catch(cause){threw=true;assert.equal(cause,undefined);}
    assert.equal(threw,true);assert.equal(entered,1);
    assert.throws(()=>f.context[method](projection),{code:'ForeignInstalledSourceInitialization'});
    f.finish();assert.equal(f.retire(),true);
  }
});

test('invalid async native Source construction remains held until original settlement without retry',async()=>{
  for(const method of ['prepareInputConstruction','prepareNativeDeclaration']){
    const f=commandConstructionFixture({role:'source'});let settle;
    const projection=Object.freeze({capacity(){return f.native;},project(){return new Promise(resolve=>{settle=resolve;});}});
    assert.throws(()=>f.context[method](projection),{code:'InstalledSourceConstructorNotSynchronous'});
    f.finish();assert.equal(f.retire(),false);
    assert.throws(()=>f.context[method](projection),{code:'ForeignInstalledSourceInitialization'});
    settle(Object.freeze({unexpected:'never admitted'}));await Promise.resolve();await Promise.resolve();
    assert.equal(f.retire(),true);
  }
});
