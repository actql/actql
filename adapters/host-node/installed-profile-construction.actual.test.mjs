import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {installedEffectIdentity} from './installed-effect.mjs';
import {snapshotProcessValue} from './process-frames.mjs';
import {createInstalledConnectorTable, installedConnectorForTable} from './installed-connectors.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';


// Real Source parent/reader, runtime namespace and complete Local installer.
// The fixture supplies declaration and native-profile DATA only: no Run,
// Account grant, Content read or physical Local writer operation is issued here.
test('Local file installer prepays its recovery profile on the original Source reader', async t => {
  const {installPreparedProjectLocalFileEffects} = await import('../connectors/local/host/installed-project-file-effects.mjs');
  const {canonicalJson, contentCid} = await import('./local-account-config.mjs');
  const {readFile} = await import('node:fs/promises');
  const f = await boundConstructionActualFixture(t);
  const connectorId = 'local-files', connection = 'local-files';
  const manifest = {connector: 'local', connector_id: connectorId, connector_version: 'local/0.1'};
  const catalog = {schema: 'actql.connector_catalog/0.1', connector_id: connectorId,
    connector_version: 'local/0.1', source_views: [], commands: [], contracts: []};
  const catalogCid = contentCid(catalog);
  const declaredWire = canonicalJson({connector_id: connectorId, connector_registration: 'local',
    connector_version: 'local/0.1', catalog: canonicalJson({...catalog, catalog_cid: catalogCid}),
    catalog_cid: catalogCid, contracts: [], command_bodies: [], evidence_schemas: [],
    evidence_capabilities: [], view_bodies: [],
    manifest_entry: canonicalJson(manifest), manifest_entry_cid: contentCid(manifest)});
  const entry = Object.freeze({connectorId, connection, wire: declaredWire, rootPath: f.root,
    scopeCid: contentCid({root: f.root}), limits: Object.freeze({maxFileBytes: 4096})});
  const bundle = Object.freeze({sources: Object.freeze([entry])});
  const context = Object.freeze({contextCid: contentCid({fixture: 'Local installation context'})});
  let grants = 0, physical = 0;
  const authorization = Object.freeze({context,
    configurationCid: contentCid({fixture: 'ungranted Local installation'}),
    authorize() {grants++; assert.fail('Installation cannot authorize a Run');}});
  const nativeFilesystem = Object.freeze({
    localFileWriteConstructionProfile() {return Object.freeze({nativeOriginalBytes: 8192,
      maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130, writeQuantumBytes: 65536});},
    ...Object.fromEntries(['openFileRoot', 'openFileDirectory', 'openRootFileWriter',
      'fileRootCurrent', 'fileRootWrite', 'fileRootPublish', 'fileRootClose'].map(name =>
      [name, () => {physical++; assert.fail('Installation cannot perform a file operation');}]))});
  const resources = Object.freeze(Object.fromEntries(['bindRunOriginal', 'assertCurrent', 'limits'].map(name =>
    [name, () => assert.fail('Installation cannot use a Run resource')])));
  const baseEnvironmentWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  const effect = await installPreparedProjectLocalFileEffects({moon: f.moon,
    preparation: {originalsForRuntime(runtime) {assert.strictEqual(runtime, f.moon); return bundle;}},
    sourceManaged: {assertCurrent() {}}, baseEnvironmentWire,
    authorizationFor: async selected => {assert.equal(selected, connection); return authorization;},
    principalId: 'operator', runtimeBundleCid: contentCid({fixture: 'Local installation runtime'}),
    ledgerRoot: join(f.root, 'local-effect-ledger'), nativeFilesystem, effectResources: resources,
    sourceBindings: [{connectorId, bindingCid: contentCid({scope: entry.scopeCid,
      declaration: entry.wire, account_context: context.contextCid})}], installationServices: f.services});
  try {
    assert.equal(effect.effects.length, 1);
    assert.equal(effect.queryStoreTargets[0].name, `${connection}.files`);
    assert.equal(grants, 0); assert.equal(physical, 0); assert.equal(f.secretReads(), 0);
  } finally {await effect.close();}
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('same original profile facts fund parse snapshot and inspection as distinct native constructors', async t => {
  const f = await boundConstructionActualFixture(t);
  const reader = installedSourceConfigurationReader(f.services);
  const expected = {version: 'fixture', payload: 'A'.repeat(100000), nested: {a: [1, 2, 'é😀']}};
  const wire = JSON.stringify(expected), path = join(f.root, 'profile-material.json');
  await writeFile(path, wire);
  const text = await reader.readText(path, {maxBytes: Buffer.byteLength(wire)});
  let parses = 0;
  const construction = reader.prepareProfile(text, () => {
    parses++;
    return Object.freeze(JSON.parse(text));
  });
  assert.equal(parses, 1); assert.deepEqual(construction.value, expected);
  const snapshot = construction.construct(() => {
    return snapshotProcessValue(construction.value, {maxBytes: 200000, maxNodes: 1000, maxDepth: 32});
  });
  assert.deepEqual(snapshot, expected); assert.notEqual(snapshot, construction.value);
  const facts = construction.inspect(() => {
    const fields = Object.getOwnPropertyDescriptors(snapshot);
    return Object.freeze({fields: BigInt(Object.keys(fields).length)});
  });
  assert.equal(facts.fields, 3n);
  assert.throws(() => reader.prepareProfile(text + ' ', () => assert.fail('Foreign text')),
    {code: 'ForeignInstalledConfigurationText'});
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

async function table(t, extra = '') {
  const f = await boundConstructionActualFixture(t);
  const selection = await f.tableEffectProfile();
  if (extra) {
    selection.value.targets[0].footprint.extra = extra;
    await writeFile(selection.path, JSON.stringify(selection.value));
  }
  const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'effect', selection.value);
  let checked, descriptorReads = 0;
  const connectorTable = createInstalledConnectorTable([{...entry, effect: {...entry.effect,
    async load() {
      const module = await entry.effect.load();
      return {...module, check(value) {checked = module.check(value); return checked;},
        async load(profile, options) {
          if (extra) {
            // A distinct actual retained input on this SAME parent. Do not
            // replace its Ledger or raise a profile/budget to force a result.
            const path = join(f.root, 'retained-overlap.txt'), text = 'X'.repeat(8 * 1024 * 1024);
            await writeFile(path, text);
            const retained = await installedSourceConfigurationReader(f.services).readText(path, {maxBytes: text.length});
            assert.equal(retained.length, text.length);
          }
          return module.load(profile, options);
        }};
    }}}]);
  const descriptors = Object.getOwnPropertyDescriptors;
  t.mock.method(Object, 'getOwnPropertyDescriptors', value => {
    if (value === checked) {
      descriptorReads++;
    }
    return descriptors(value);
  });
  return {f, selection, connectorTable, checkedProfile: () => checked, descriptorReads: () => descriptorReads};
}

test('actual Table Effect reserves its own inspection after completed profile snapshot', async t => {
  const c = await table(t);
  const effect = await c.f.load(c.selection, {connectorTable: c.connectorTable});
  assert(effect.environmentWire.length > 0); assert(c.descriptorReads() >= 1);
  assert.equal(c.f.secretReads(), 0);
  await c.f.close(); assert.equal(c.f.pending(), false); assert.equal(c.f.retire(), true);
});

test('actual Table inspection refuses an overlapping retained input before descriptor allocation', async t => {
  const c = await table(t, 'A'.repeat(2050000));
  await assert.rejects(c.f.load(c.selection, {connectorTable: c.connectorTable}));
  assert(c.checkedProfile(), 'the actual profile check completed before inspection was refused');
  assert.equal(c.descriptorReads(), 0);
  assert.equal(c.f.secretReads(), 0);
  await c.f.close(); assert.equal(c.f.pending(), false); assert.equal(c.f.retire(), true);
});


test('actual Table Source uses the same original profile constructor before its own inspection', async t => {
  const f = await boundConstructionActualFixture(t);
  const source = await f.load(await f.tableSourceProfile());
  assert.equal(source.connectorRegistration, 'local');
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('same profile reader preserves native parse failure before pending original close', async t => {
  const f = await boundConstructionActualFixture(t);
  const reader = installedSourceConfigurationReader(f.services), path = join(f.root, 'malformed-profile.json');
  await writeFile(path, '{"incomplete":');
  const originalOpen = fs.open;
  let allowed = false, closes = 0, opens = 0, failure;
  fs.open = async (candidate, ...args) => {
    const handle = await originalOpen(candidate, ...args);
    if (candidate !== path) return handle;
    opens++;
    return {read: (...values) => handle.read(...values), async close() {
      closes++;
      if (!allowed) return false;
      await handle.close();
    }};
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(reader.readProfile(path), error => {
      failure = error;
      return error.cleanupHandle?.status().pending === true && error.cleanupHandle.primaryFailure instanceof SyntaxError;
    });
    assert.equal(opens, 1); assert.equal(closes, 1);
    const primary = failure.cleanupHandle.primaryFailure;
    assert.equal(f.retire(), false, 'no completion or refund while the SAME original FD is pending');
    allowed = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.strictEqual(failure.cleanupHandle.primaryFailure, primary);
    assert.equal(opens, 1); assert.equal(closes, 2);
    await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
  } finally {
    allowed = true;
    if (failure !== undefined) await failure.cleanupHandle.retry();
    fs.open = originalOpen; syncBuiltinESMExports();
  }
});


test('funded Effect profile split preserves exact invalid update-target cause outside the read wrapper', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.tableEffectProfile();
  selected.value.queryUpdateTargets = null;
  await writeFile(selected.path, JSON.stringify(selected.value));
  await assert.rejects(f.load(selected), {code: 'InvalidInstalledUpdateTargets'});
  assert.equal(f.sources.length, 0); assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('funded Effect profile constructor preserves exact current refusal after the original read returns', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.tableEffectProfile(), original = installedSourceConfigurationReader(f.services);
  let primary, fault;
  const configurationReader = Object.freeze({
    readJson: (...args) => original.readJson(...args),
    readText: (...args) => original.readText(...args),
    async readProfile(...args) {
      const construction = await original.readProfile(...args);
      return Object.freeze({...construction, construct(project) {
        fault = f.failCurrentBeforeNextConstruction();
        try {return construction.construct(project);}
        catch (cause) {primary = cause; throw cause;}
      }});
    },
  });
  await assert.rejects(installedEffectIdentity(selected.path, {configurationReader}), cause => {
    assert.strictEqual(cause, primary, 'the read wrapper cannot relabel the later constructor failure');
    assert.equal(cause.code, 'MoonBitHostFailure');
    assert.notEqual(cause.cause, undefined);
    return true;
  });
  assert.equal(fault.calls, 1);
  assert.equal(f.sources.length, 0); assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});
