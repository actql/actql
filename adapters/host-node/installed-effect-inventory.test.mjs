import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, mkdtemp, readdir, readFile, rm, symlink, writeFile}
  from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {installedInventoryComponent, copyInstalledInventoryLoader} from './fixtures/installed-inventory-component.fixture.mjs';
import './installed-effect-inventory.integration.test.mjs';
import './installed-effect-profile-cleanup.test.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {installedEffectPaths} from './installed-effect.mjs';
import {readSourceProfileJson, installedRuntimeBundleCid} from './source-profile-json.mjs';
import {verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const moon = await import(runtimeUrl.href);
const baseWire = (await readFile(new URL('../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trimEnd();
const cid = digit => 'sha256:' + digit.repeat(64);
const binding = (connectorId, site = connectorId) =>
  ({connectorId, bindingCid: contentCid({site})});
const sealEnvironment = body => {
  delete body.evidence_bundle_cid;
  for (const key of ['mapping_contracts', 'connector_catalogs']) {
    body[key].sort((a, b) => contentCid(a).localeCompare(contentCid(b)));
  }
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
};
function profile(name, changes = {}) {
  const kind = changes.mode === 'row' ? 'create' : 'store';
  const body = JSON.parse(baseWire);
  const targetRef = `connector://${name}/records`;
  const schema = {type: 'object', nullable: false, additional_properties: false,
    fields: {Id: {type: 'string', nullable: false}, Name: {type: 'string', nullable: true}}};
  const mappingBody = {schema: 'actql.mapping_contract/0.1', version: 'fixture',
    connector_manifest_cid: withFixtureConnector(body, targetRef),
    mapping_ref: `mapping:${name}.records.v1`, target_ref: targetRef,
    target_schema: schema, target_schema_identity: contentCid(schema),
    resource_identity_cid: cid('b'), primary_identity: 'Id',
    minimum_approval: 'required', conversions: [], required_fields: [],
    writable_fields: ['Name'], required_permissions: [],
    row_mapping: {Name: {field: 'name', null_behavior: 'reject'}},
    permission_rules: [{effect_kind: kind, selector_class: 'none',
      write_fields: ['Name'], permissions: [`scope:${kind}`]}]};
  const mapping = {...mappingBody, mapping_contract_cid: contentCid(mappingBody)};
  body.mapping_contracts = [mapping];
  return {version: 'actql-installed-effect-inventory-fixture/0.1', name,
    environmentWire: sealEnvironment(body), connectorBindings: [binding(name)],
    targets: [{effectId: 'save', resource: 'records', targetRef,
      mappingRef: mapping.mapping_ref, mappingCid: mapping.mapping_contract_cid,
      action: 'create', catalogCid: cid('3'), namespace: ['inventory'], tableName: name,
      expectedTable: null, permissions: [`scope:${kind}`], footprint: {}}],
    ...changes};
}
const descriptor = (value, index = 0) => ({kind: value.mode === 'row' ? 'create' : 'store',
  target: value.targets[index].targetRef, mappingRef: value.targets[index].mappingRef,
  mappingCid: value.targets[index].mappingCid, effectId: value.targets[index].effectId});

// Authored Table/row members supply inventory DATA, including deliberately
// malformed publications. The actual inventory fold and funded Environment
// remain real; these member ports do not qualify bound module initialization.
async function installation(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-inventory-'));
  let component;
  t.after(async () => {await component?.close(); await rm(root, {recursive: true, force: true});});
  const host = join(root, 'adapters', 'host-node');
  const connectors = join(root, 'adapters', 'connectors-builtin');
  await mkdir(host, {recursive: true});
  await mkdir(connectors, {recursive: true});
  const original = fileURLToPath(new URL('./', import.meta.url));
  for (const entry of await readdir(original, {withFileTypes: true})) {
    if (entry.name === 'installed-effect.mjs') {
      await copyInstalledInventoryLoader(new URL('./installed-effect.mjs', import.meta.url), join(host, entry.name));
    } else if (entry.isFile() && entry.name.endsWith('.mjs')) {
      await symlink(join(original, entry.name), join(host, entry.name));
    }
  }
  await symlink(fileURLToPath(new URL('../connectors', import.meta.url)),
    join(root, 'adapters', 'connectors'));
  await writeFile(join(connectors, 'installations.generated.mjs'), `
    import * as fixture from './fixture.mjs';
    export const installedConnectors = Object.freeze([Object.freeze({name: 'effect_inventory_fixture',
      registration: 'effect_inventory_fixture', revision: 'effect_inventory_fixture/0.1',
      effect: Object.freeze({profileVersion: 'actql-installed-effect-inventory-fixture/0.1',
        load: async () => fixture})})]);
  `);
  await writeFile(join(connectors, 'fixture.mjs'), `
    import {createInstalledTableEffect} from ${JSON.stringify(new URL('./installed-table-effect.mjs', import.meta.url).href)};
    import {createInstalledRowEffect} from ${JSON.stringify(new URL('./installed-row-effect.mjs', import.meta.url).href)};
    export const events = [], blocked = new Set(), loaded = new Map();
    export const check = profile => profile;
    export const identityParts = async (profile, read) => profile.identityPath === undefined
      ? [profile] : [profile, await read(profile.identityPath)];
    export async function load(profile, options) {
      events.push([profile.name, 'load']);
      if (profile.loadFailure) {
        let pending = true;
        throw Object.assign(new Error('FixtureModuleLoadFailed'), {
          code: 'FixtureModuleLoadFailed', cleanupPending: true,
          cleanupHandle: {status: () => ({pending}), async retry() {
            if (!pending) return;
            events.push([profile.name, 'failed-load-cleanup']);
            await Promise.resolve();
            if (blocked.has(profile.name)) throw new Error('CleanupPending:' + profile.name);
            pending = false;
          }},
        });
      }
      const touch = action => {
        events.push([profile.name, action]);
        throw new Error('UnexpectedInventoryOperation:' + action);
      };
      const authorization = {authorize: () => touch('authorize')};
      const common = {moon: options.moon, environmentWire: profile.environmentWire,
        connectorId: profile.name, connectorRegistration: 'effect_inventory_fixture',
        connectorRevision: 'effect_inventory_fixture/0.1', connection: profile.name,
        runtimeBundleCid: options.runtimeBundleCid, bindingCid: 'sha256:' + '9'.repeat(64),
        authorization, ledgerRoot: options.ledgerRoot};
      let effect;
      if (profile.mode === 'row') {
        const mappings = JSON.parse(profile.environmentWire).mapping_contracts;
        effect = await createInstalledRowEffect({...common,
          mappings: mappings.map(mapping => ({resource: 'records',
            mappingRef: mapping.mapping_ref, mappingCid: mapping.mapping_contract_cid,
            body: JSON.stringify(mapping)})),
          site: {issueEffectGrant: () => touch('effect-grant'),
            issueReadGrant: () => touch('read-grant'), close() {}},
          driver: {kinds: ['create'], prepareRequest: () => touch('request'),
            requestFacts: () => touch('facts'), writeOperation: () => touch('operation'),
            send: () => touch('send'), project: () => touch('project'),
            footprint: () => touch('footprint')}});
      } else {
        effect = await createInstalledTableEffect({...common, catalogCid: 'sha256:' + '3'.repeat(64),
          targets: profile.targets, bridge: {
            ...Object.fromEntries(['prepareWrite', 'execute', 'inspect', 'cleanup',
              'status', 'reconcileOperation', 'projectCommitResponse',
              'issueStorageMapping', 'admitStorageMapping']
              .map(action => [action, () => touch(action)])),
            supportsOperation: ({action, kind}) => action === 'create' && kind === 'relation',
          }});
      }
      const adapter = {...effect,
        connectorRegistration: profile.registrationMismatch ? 'other' : 'effect_inventory_fixture',
        connectorBindings: profile.connectorBindings,
        targetReadAuthorization: Object.freeze({fixture: profile.name}),
        targetReadInventory: Object.freeze([]),
        async close() {
          events.push([profile.name, 'close']);
          await Promise.resolve();
          if (blocked.has(profile.name)) throw new Error('ClosePending:' + profile.name);
          await effect.close();
        },
      };
      if (profile.effectSelectors !== undefined) adapter.effectSelectors =
        Object.freeze(profile.effectSelectors.map(value => Object.freeze(value)));
      if (profile.metadataAbsent) delete adapter.effectSelectors;
      loaded.set(profile.name, adapter);
      return adapter;
    }
  `);
  const loader = await import(pathToFileURL(join(host, 'installed-effect.mjs')).href);
  const fixture = await import(pathToFileURL(join(connectors, 'fixture.mjs')).href);
  let generation = 0;
  const paths = async profiles => {
    const result = [];
    for (const value of profiles) {
      const path = join(root, `profile-${generation++}.json`);
      await writeFile(path, JSON.stringify(value));
      result.push(path);
    }
    return result;
  };
  const options = {root, principalId: 'inventory', moon, runtimeUrl,
    baseEnvironmentWire: baseWire,
    resolveSecret() { fixture.events.push(['secret']); throw new Error('UnexpectedSecret'); }};
  const {installedConnectors} = await import(pathToFileURL(join(connectors, 'installations.generated.mjs')).href);
  component = installedInventoryComponent(loader, fixture.loaded, async (path, captured, retain) => {
    // This authored member port exposes DATA and independent cleanup before
    // metadata validation. It does not claim bound module initialization.
    const profile = fixture.check(await readSourceProfileJson(path));
    const entry = installedConnectors[0];
    const adapter = await fixture.load(profile, {...captured, installation: entry,
      runtimeBundleCid: await installedRuntimeBundleCid(runtimeUrl),
      ledgerRoot: join(root, 'state', 'effects', 'ledger')});
    retain(adapter);
    verifyInstalledConnectorRegistration(entry, adapter);
    return adapter;
  });
  return {...fixture, ...loader, root, paths, options,
    loadInstalledEffects: (paths, options) => component.load('effect', paths, options)};
}
const primary = code => error => {
  assert.equal(error.primaryFailure?.code ?? error.code, code);
  assert.equal(error.cleanupPending, false);
  return true;
};

test('Effect paths preserve absent/singular routes and use only the Environment member upper bound', () => {
  const paths = Array.from({length: 257}, (_, index) => `/effect-${index}.json`);
  for (const size of [2, 3, 16, 17, 128, 129, 256]) {
    const selected = installedEffectPaths({effectProfilePaths: paths.slice(0, size)});
    assert.deepEqual(selected, paths.slice(0, size));
    assert.ok(Object.isFrozen(selected));
  }
  for (const effectProfilePaths of [[], [paths[0]], paths, [paths[0], paths[0]],
    [paths[0], 'relative'], [paths[0], null]]) {
    assert.throws(() => installedEffectPaths({effectProfilePaths}),
      {code: 'InvalidInstalledEffectProfiles'});
  }
  assert.deepEqual(installedEffectPaths({}), []);
  assert.deepEqual(installedEffectPaths({effectProfilePath: 'legacy-relative'}), ['legacy-relative']);
  assert.deepEqual(installedEffectPaths({}, paths[0]), [paths[0]]);
  assert.throws(() => installedEffectPaths({effectProfilePaths: paths.slice(0, 2)}, paths[0]),
    {code: 'InvalidInstalledEffectProfiles'});
  assert.throws(() => installedEffectPaths({effectProfilePath: paths[0],
    effectProfilePaths: paths.slice(1, 3)}), {code: 'InvalidInstalledEffectProfiles'});
  const longPath = '/' + 'x'.repeat(65537);
  assert.deepEqual(installedEffectPaths({effectProfilePaths: [paths[0], longPath]}),
    [paths[0], longPath], 'Environment wire bytes are not a filepath byte limit');
});

for (const reverse of [false, true]) {
  test(`real Table and row selectors choose exact owners with ${reverse ? 'reversed' : 'original'} profile order`, async t => {
    const fixture = await installation(t);
    const table = profile('table'), row = profile('row', {mode: 'row'});
    table.targets.push({...table.targets[0], effectId: 'other', tableName: 'other'});
    const declarations = reverse ? [row, table] : [table, row];
    const inventory = await fixture.loadInstalledEffects(await fixture.paths(declarations), fixture.options);
    assert.ok(Object.isFrozen(inventory.effects));
    assert.equal(inventory.environmentWire, composeInstalledCheckEnvironment(moon, baseWire,
      ...declarations.map(value => value.environmentWire)));
    for (const [index, value] of declarations.entries()) {
      const selected = fixture.installedEffectFor(inventory, [descriptor(value)]);
      assert.equal(selected, inventory.effects[index]);
      assert.equal(selected.effectSelectors, fixture.loaded.get(value.name).effectSelectors);
      assert.equal(selected.targetReadAuthorization, fixture.loaded.get(value.name).targetReadAuthorization);
      assert.equal(selected.targetReadInventory, fixture.loaded.get(value.name).targetReadInventory);
    }
    const tableOwner = fixture.installedEffectFor(inventory, table.targets.map((_, index) => descriptor(table, index)));
    assert.equal(tableOwner, inventory.effects[reverse ? 1 : 0]);
    assert.equal(fixture.installedEffectFor(inventory, [{...descriptor(row), effectId: 'arbitrary'}]),
      inventory.effects[reverse ? 0 : 1], 'row ownership is independent of Effect ID');
    assert.throws(() => fixture.installedEffectFor(inventory,
      [{...descriptor(table), effectId: 'arbitrary'}]), {code: 'InstalledEffectProgramMismatch'});
    assert.throws(() => fixture.installedEffectFor(inventory,
      [descriptor(table), descriptor(row)]), {code: 'InstalledEffectSetOwnerMismatch'});
    for (const descriptors of [[], [{...descriptor(row), kind: 'update'}],
      [{...descriptor(row), mappingCid: cid('d')}], [{...descriptor(row), target: 'elsewhere'}]]) {
      assert.throws(() => fixture.installedEffectFor(inventory, descriptors),
        {code: 'InstalledEffectProgramMismatch'});
    }
    assert.throws(() => fixture.installedEffectFor({effects: [tableOwner, tableOwner]},
      [descriptor(table)]), {code: 'InstalledEffectProgramMismatch'});
    assert.throws(() => fixture.installedEffectFor(undefined, [descriptor(table)]),
      {code: 'InstalledEffectProgramMismatch'});
    assert.deepEqual(fixture.events, declarations.map(value => [value.name, 'load']));
    const firstClose = inventory.close();
    assert.equal(inventory.close(), firstClose);
    await firstClose;
    await inventory.close();
    assert.deepEqual(fixture.events.slice(2), declarations.map(value => [value.name, 'close']));
  });
}

test('a nonadjacent third installation cannot own an earlier Mapping under another Effect ID', async t => {
  const fixture = await installation(t);
  const first = profile('first'), second = profile('second');
  const third = {...first, name: 'third', targets: first.targets.map(target =>
    ({...target, effectId: 'different'}))};
  await assert.rejects(fixture.loadInstalledEffects(await fixture.paths(
    [first, second, third, profile('unreached')]), fixture.options), primary('InstalledEffectMappingAmbiguous'));
  assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load'],
    ['first', 'close'], ['second', 'close'], ['third', 'close']]);
});

for (const fault of ['different-binding', 'missing-binding', 'duplicate-binding', 'undeclared-binding']) {
  test(`a third Effect installation rejects ${fault} before loading the next member`, async t => {
    const fixture = await installation(t);
    const first = profile('first'), second = profile('second'), third = profile('third');
    const body = JSON.parse(third.environmentWire);
    withFixtureConnector(body, 'connector://first/records');
    third.environmentWire = sealEnvironment(body);
    third.connectorBindings = [binding('third'), binding('first')];
    if (fault === 'different-binding') third.connectorBindings[1] = binding('first', 'elsewhere');
    if (fault === 'missing-binding') third.connectorBindings.pop();
    if (fault === 'duplicate-binding') third.connectorBindings.push(binding('third'));
    if (fault === 'undeclared-binding') third.connectorBindings.push(binding('unknown'));
    await assert.rejects(fixture.loadInstalledEffects(await fixture.paths(
      [first, second, third, profile('unreached')]), fixture.options), primary('InstalledCheckEnvironmentConflict'));
    assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load'],
      ['first', 'close'], ['second', 'close'], ['third', 'close']]);
  });
}

test('matching third-member physical bindings coalesce independently of Mapping ownership', async t => {
  const fixture = await installation(t);
  const values = [profile('first'), profile('second'), profile('third')];
  const third = values[2], body = JSON.parse(third.environmentWire);
  withFixtureConnector(body, 'connector://first/records');
  third.environmentWire = sealEnvironment(body);
  third.connectorBindings.push(binding('first'));
  const inventory = await fixture.loadInstalledEffects(await fixture.paths(values), fixture.options);
  assert.deepEqual(inventory.connectorBindings, ['first', 'second', 'third'].map(name => binding(name)));
  assert.equal(fixture.installedEffectFor(inventory, [descriptor(third)]), inventory.effects[2]);
  await inventory.close();
});

test('more than sixteen independent Effects install without changing the per-Set limit', async t => {
  const fixture = await installation(t);
  const values = Array.from({length: 17}, (_, index) => profile(`member-${index}`));
  const inventory = await fixture.loadInstalledEffects(await fixture.paths(values), fixture.options);
  assert.equal(inventory.effects.length, 17);
  assert.equal(fixture.installedEffectFor(inventory, [descriptor(values[16])]), inventory.effects[16]);
  assert.deepEqual(fixture.events, values.map(value => [value.name, 'load']));
  await inventory.close();
});

for (const fault of ['absent', 'empty', 'ref', 'cid', 'target', 'kind', 'extra',
  'duplicate', 'foreign-permission', 'false-mapping-cid']) {
  test(`plural inventory rejects ${fault} selector metadata against its own admitted Environment`, async t => {
    const fixture = await installation(t);
    const value = profile('invalid');
    value.effectSelectors = [descriptor(value)];
    if (fault === 'absent') value.metadataAbsent = true;
    if (fault === 'empty') value.effectSelectors = [];
    if (fault === 'ref') value.effectSelectors[0].mappingRef = 'mapping:missing.v1';
    if (fault === 'cid') value.effectSelectors[0].mappingCid = cid('f');
    if (fault === 'target') value.effectSelectors[0].target = 'connector://other/records';
    if (fault === 'kind') value.effectSelectors[0].kind = 'unsupported';
    if (fault === 'extra') value.effectSelectors[0].provider = 'first';
    if (fault === 'duplicate') value.effectSelectors.push(value.effectSelectors[0]);
    if (fault === 'foreign-permission') value.effectSelectors[0].kind = 'create';
    if (fault === 'false-mapping-cid') {
      const body = JSON.parse(value.environmentWire);
      body.mapping_contracts[0].mapping_contract_cid = cid('f');
      value.environmentWire = sealEnvironment(body);
      value.effectSelectors[0].mappingCid = cid('f');
      value.targets[0].mappingCid = cid('f');
    }
    await assert.rejects(fixture.loadInstalledEffects(await fixture.paths(
      [profile('first'), value, profile('unreached')]), fixture.options), primary('InvalidInstalledEffectSelectors'));
    assert.deepEqual(fixture.events, [['first', 'load'], ['invalid', 'load'],
      ['first', 'close'], ['invalid', 'close']]);
  });
}

for (const fault of ['encoding', 'policy', 'identity', 'over-budget']) {
  test(`plural inventory independently rejects a ${fault} Environment`, async t => {
    const fixture = await installation(t);
    const value = profile('invalid'), body = JSON.parse(value.environmentWire);
    if (fault === 'encoding') value.environmentWire += '\n';
    if (fault === 'policy') {
      body.host_policy_profile.capacity.max_effect_items += 1;
      value.environmentWire = sealEnvironment(body);
    }
    if (fault === 'identity') {
      body.evidence_bundle_cid = cid('f');
      value.environmentWire = canonicalJson(body);
    }
    if (fault === 'over-budget') {
      body.mapping_contracts[0].padding = 'x'.repeat(65536);
      value.environmentWire = sealEnvironment(body);
    }
    await assert.rejects(fixture.loadInstalledEffects(await fixture.paths(
      [profile('first'), value, profile('unreached')]), fixture.options), primary('InstalledCheckEnvironmentConflict'));
    assert.deepEqual(fixture.events, [['first', 'load'], ['invalid', 'load'],
      ['first', 'close'], ['invalid', 'close']]);
  });
}

test('composition retains the standard Environment byte budget across individually admitted members', async t => {
  const fixture = await installation(t);
  const values = ['first', 'second', 'third'].map(name => {
    const value = profile(name), body = JSON.parse(value.environmentWire);
    const {mapping_contract_cid: ignored, ...mapping} = body.mapping_contracts[0];
    void ignored;
    mapping.version = 'fixture-' + 'x'.repeat(23000);
    const mappingCid = contentCid(mapping);
    body.mapping_contracts = [{...mapping, mapping_contract_cid: mappingCid}];
    value.targets[0].mappingCid = mappingCid;
    value.environmentWire = sealEnvironment(body);
    assert.ok(Buffer.byteLength(value.environmentWire) < 65536);
    assert.notEqual(moon.clientProgramCheckEnvironment(value.environmentWire,
      JSON.parse(value.environmentWire).evidence_bundle_cid,
      false, false, true, false, false, false, false), undefined);
    return value;
  });
  await assert.rejects(fixture.loadInstalledEffects(await fixture.paths(
    [...values, profile('unreached')]), fixture.options), primary('InstalledCheckEnvironmentConflict'));
  assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load'],
    ['first', 'close'], ['second', 'close'], ['third', 'close']]);
});

test('count refusal precedes profile I/O and empty/singular loads preserve legacy behavior', async t => {
  const fixture = await installation(t);
  await assert.rejects(fixture.loadInstalledEffects(Array.from({length: 257}, (_, index) =>
    join(fixture.root, `missing-${index}`)), fixture.options), {code: 'InvalidInstalledEffectProfiles'});
  assert.deepEqual(fixture.events, []);
  assert.equal(await fixture.loadInstalledEffects([], fixture.options), undefined);
  const [path] = await fixture.paths([profile('legacy', {metadataAbsent: true})]);
  const singular = await fixture.loadInstalledEffects([path], fixture.options);
  assert.equal(singular.effects, undefined);
  assert.equal(singular.effectSelectors, undefined);
  assert.equal(fixture.installedEffectFor(singular, []), singular);
  await singular.close();
});

for (const loadFailure of [false, true]) {
  test(`partial ${loadFailure ? 'module load' : 'validation'} failure attempts every independent cleanup and coalesces retries`, async t => {
    const fixture = await installation(t);
    fixture.blocked.add('first');
    fixture.blocked.add('third');
    let failure;
    await assert.rejects(fixture.loadInstalledEffects(await fixture.paths([
      profile('first'), profile('second'), profile('third', loadFailure
        ? {loadFailure: true} : {registrationMismatch: true}), profile('unreached')]),
    fixture.options), error => {
      failure = error;
      assert.equal(error.primaryFailure.code, loadFailure
        ? 'FixtureModuleLoadFailed' : 'InstalledConnectorRegistrationMismatch');
      assert.equal(error.cleanupPending, true);
      return true;
    });
    const thirdAction = loadFailure ? 'failed-load-cleanup' : 'close';
    assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load'],
      ['first', 'close'], ['second', 'close'], ['third', thirdAction]]);
    fixture.blocked.delete('third');
    await Promise.all([failure.cleanupHandle.retry(), failure.cleanupHandle.retry()]);
    assert.equal(failure.cleanupHandle.status().pending, true);
    fixture.blocked.delete('first');
    await Promise.all([failure.cleanupHandle.retry(), failure.cleanupHandle.retry()]);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(fixture.events.filter(([name, action]) => name === 'first' && action === 'close').length, 3);
    assert.equal(fixture.events.filter(([name, action]) => name === 'second' && action === 'close').length, 1);
    assert.equal(fixture.events.filter(([name, action]) => name === 'third' && action === thirdAction).length, 2);
  });
}

test('aggregate close keeps only failed siblings and shares concurrent retries', async t => {
  const fixture = await installation(t);
  const inventory = await fixture.loadInstalledEffects(await fixture.paths(
    [profile('first'), profile('second'), profile('third')]), fixture.options);
  fixture.blocked.add('first'); fixture.blocked.add('third');
  const flight = inventory.close();
  assert.equal(inventory.close(), flight);
  let failure;
  await assert.rejects(flight, error => {
    failure = error;
    return error.code === 'InstalledEffectCleanupPending';
  });
  fixture.blocked.delete('first');
  const retry = failure.cleanupHandle.retry();
  assert.equal(inventory.close(), retry);
  await assert.rejects(retry, {code: 'InstalledEffectCleanupPending'});
  fixture.blocked.delete('third');
  await inventory.close();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(fixture.events.filter(([name, action]) => name === 'first' && action === 'close').length, 2);
  assert.equal(fixture.events.filter(([name, action]) => name === 'second' && action === 'close').length, 1);
  assert.equal(fixture.events.filter(([name, action]) => name === 'third' && action === 'close').length, 3);
});

test('singular Effect identity keeps its original length-prefixed canonical preimage', async t => {
  const fixture = await installation(t);
  const value = profile('identity');
  const [path] = await fixture.paths([value]);
  const canonical = canonicalJson(value);
  const expected = 'sha256:' + createHash('sha256')
    .update(String(Buffer.byteLength(canonical))).update('\0').update(canonical).digest('hex');
  assert.equal(await fixture.installedEffectIdentity(path), expected);
  assert.deepEqual(fixture.events, []);
});

test('Effect profile and identity-part files are bounded before loading an installation', async t => {
  const fixture = await installation(t);
  const oversized = join(fixture.root, 'oversized.json');
  await writeFile(oversized, JSON.stringify({...profile('oversized'),
    padding: 'x'.repeat(8 * 1024 * 1024)}));
  await assert.rejects(fixture.loadInstalledEffect(oversized, fixture.options),
    {code: 'InvalidInstalledEffectProfile'});
  const [path] = await fixture.paths([profile('identity', {identityPath: oversized})]);
  await assert.rejects(fixture.installedEffectIdentity(path), {code: 'InvalidInstalledEffectProfile'});
  assert.deepEqual(fixture.events, []);
});
