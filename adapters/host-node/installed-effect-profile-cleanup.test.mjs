import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as loader from './installed-effect.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {createInstalledHostServices, retainInstalledHostServiceInstallation} from './installed-host-services.mjs';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

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

test('Effect load preserves original profile refusal before runtime or service selection', async t => {
  const failure = new Error('OriginalProfileRefusal');
  const f = await serviceFixture(t, {onCheck() {throw failure;}});
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, {...f.options,
    runtimeUrl: pathToFileURL(join(f.root, 'missing-runtime')), installationServices: {}}), error => error === failure);
  assert.equal(f.calls(), 0);
});

test('Effect load keeps the absent-service installer envelope unchanged', async t => {
  const f = await serviceFixture(t, {onLoad(_profile, options) {
    assert.equal(Object.hasOwn(options, 'installationServices'), false);
  }});
  const {installationServices: _unused, ...options} = f.options;
  await assert.rejects(loader.loadInstalledEffect(f.profilePath, options), error => error === f.stop);
  assert.equal(f.calls(), 1);
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
