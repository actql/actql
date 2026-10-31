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
  retireInstalledSourceInitialization} from './installed-host-services.mjs';
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
    moon: {}, providerMoon: {}, baseEnvironmentWire: '{}', runtimeBundleCid: 'sha256:' + 'b'.repeat(64),
    ledgerRoot: '/UNOPENED/ledger', installation, installationServices: services,
    sourceInitialization: initialization, configurationReader: reader}), cause => cause === stop);
  assert.deepEqual(events, ['site-json', 'publication-json', 'source-views.json', 'declaration', 'writes.json', 'mappings', 'Site']);
});
