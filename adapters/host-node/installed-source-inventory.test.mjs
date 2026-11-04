import assert from 'node:assert/strict';
import {copyFile, mkdir, mkdtemp, readdir, readFile, rm, symlink, writeFile} from
  'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {installedInventoryComponent, copyInstalledInventoryLoader} from './fixtures/installed-inventory-component.fixture.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {composeInstalledCheckEnvironment, verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {installedSourcePaths} from './installed-source.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const moon = await import(runtimeUrl.href);
const baseWire = (await readFile(new URL('../../spec/' +
  'local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
function environment(ids, change = () => {}) {
  const body = JSON.parse(baseWire);
  for (const id of ids) withFixtureConnector(body, `connector://${id}/records`);
  delete body.evidence_bundle_cid;
  change(body);
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
}
const binding = (connectorId, site = connectorId) =>
  ({connectorId, bindingCid: contentCid({site})});
const alias = (name, sourceRef) => ({name, sourceRef,
  sourceViewContractCid: 'sha256:' + '1'.repeat(64),
  schemaContractCid: 'sha256:' + '2'.repeat(64)});
function profile(name, changes = {}) {
  return {version: 'actql-installed-inventory-fixture/0.1', name,
    refs: [`connector://${name}/records#v`], environmentWire: environment([name]),
    connectorBindings: [binding(name)], ...changes};
}

// Authored member modules supply inert or deliberately malformed inventory
// DATA. The actual fold owns composition and cleanup; this component does not
// establish bound module initialization or physical provider admission.
async function installation(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-source-inventory-'));
  let component;
  t.after(async () => {await component?.close(); await rm(root, {recursive: true, force: true});});
  const host = join(root, 'adapters', 'host-node');
  const connectors = join(root, 'adapters', 'connectors-builtin');
  await mkdir(host, {recursive: true});
  await mkdir(connectors, {recursive: true});
  const original = fileURLToPath(new URL('./', import.meta.url));
  for (const entry of await readdir(original, {withFileTypes: true})) {
    if (entry.name === 'installed-source.mjs') {
      await copyInstalledInventoryLoader(new URL('./installed-source.mjs', import.meta.url), join(host, entry.name));
    } else if (entry.isFile() && entry.name.endsWith('.mjs')) {
      await symlink(join(original, entry.name), join(host, entry.name));
    }
  }
  await symlink(fileURLToPath(new URL('../connectors', import.meta.url)),
    join(root, 'adapters', 'connectors'));
  await writeFile(join(connectors, 'installations.generated.mjs'), `
    import * as fixture from './fixture.mjs';
    export const installedConnectors = Object.freeze([Object.freeze({name: 'inventory_fixture',
      registration: 'inventory_fixture', revision: 'inventory_fixture/0.1',
      source: Object.freeze({profileVersion: 'actql-installed-inventory-fixture/0.1',
        load: async () => fixture})})]);
  `);
  await writeFile(join(connectors, 'fixture.mjs'), `
    export const events = [], blocked = new Set(), loaded = new Map();
    export const check = profile => profile;
    export const identityParts = profile => [profile];
    export async function load(profile) {
      const touch = action => {
        events.push([profile.name, action]);
        throw new Error('UnexpectedInventoryOperation:' + action);
      };
      const authorization = {authorize: () => touch('read')};
      const accesses = profile.refs.map(sourceRef => ({sourceRef,
        connection: profile.name, resource: profile.name, authorization}));
      const adapter = {
        connectorRegistration: profile.registrationMismatch ? 'other' : 'inventory_fixture',
        connectorRevision: 'inventory_fixture/0.1', realizationKey: 'fixture',
        environmentWire: profile.environmentWire,
        connectorBindings: profile.connectorBindings,
        sourceAccess: accesses[0], sourceReadAccesses: accesses,
        admitsSource: ref => profile.refs.includes(ref),
        ledgerCapacity: () => touch('capacity'),
        prepare: () => touch('prepare'), open: () => touch('open'),
        close() {
          events.push([profile.name, 'close']);
          if (blocked.has(profile.name)) throw new Error('ClosePending:' + profile.name);
        },
      };
      loaded.set(profile.name, adapter);
      events.push([profile.name, 'load']);
      return adapter;
    }
  `);
  const loader = await import(pathToFileURL(join(host, 'installed-source.mjs')).href);
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
  const options = {root, principalId: 'inventory', moon, runtimeUrl, baseEnvironmentWire: baseWire,
    resolveSecret() { fixture.events.push(['secret']); throw new Error('UnexpectedSecret'); }};
  component = installedInventoryComponent(loader, fixture.loaded);
  return {...fixture, ...loader, paths, options,
    loadInstalledSources: (paths, options) => component.load('source', paths, options)};
}
const primary = message => error => {
  assert.equal(error.primaryFailure?.message ?? error.message, message);
  assert.equal(error.cleanupPending, false);
  return true;
};

test('plural inventory admits 2 through 128 unique paths and preserves other entry paths', () => {
  const paths = Array.from({length: 129}, (_, index) => `/source-${index}.json`);
  for (const size of [2, 3, 128]) {
    assert.deepEqual(installedSourcePaths({sourceProfilePaths: paths.slice(0, size)}),
      paths.slice(0, size));
  }
  for (const sourceProfilePaths of [[], [paths[0]], paths, [paths[0], paths[0]],
    [paths[0], 'relative']]) {
    assert.throws(() => installedSourcePaths({sourceProfilePaths}),
      {message: 'InvalidInstalledSourceProfiles'});
  }
  assert.deepEqual(installedSourcePaths({sourceProfilePath: paths[0]}), [paths[0]]);
  assert.deepEqual(installedSourcePaths({}, paths[0]), [paths[0]]);
  assert.throws(() => installedSourcePaths({sourceProfilePaths: paths.slice(0, 3)}, paths[0]),
    {message: 'InvalidInstalledSourceProfiles'});
});

test('all members compose with exact bindings, aliases and inert unselected owners', async t => {
  const fixture = await installation(t);
  const declarations = [profile('first'), profile('second'), profile('third')];
  declarations[0].queryAliases = [alias('caf\u00e9', declarations[0].refs[0])];
  declarations[2].queryAliases = [alias('cafe\u0301', declarations[2].refs[0])];
  const loaded = await fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
  assert.deepEqual(loaded.sources.map(source => source.sourceAccess.connection),
    ['first', 'second', 'third']);
  assert.deepEqual(loaded.connectorBindings, declarations.flatMap(value => value.connectorBindings));
  assert.deepEqual(loaded.queryAliases, declarations.flatMap(value => value.queryAliases ?? []));
  assert.equal(fixture.installedSourceFor(loaded, declarations[2].refs[0]), loaded.sources[2]);
  assert.deepEqual(JSON.parse(loaded.environmentWire).connector_catalogs.map(value =>
    value.connector_id).sort(), ['first', 'second', 'third']);
  assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load']]);
  await loaded.close();
  await loaded.close();
  assert.deepEqual(fixture.events.slice(3), [['first', 'close'], ['second', 'close'], ['third', 'close']]);
});

test('matching nonadjacent shared physical bindings coalesce once in first-seen order', async t => {
  const fixture = await installation(t);
  const declarations = [profile('first', {environmentWire: environment(['first', 'shared']),
    connectorBindings: [binding('first'), binding('shared')]}), profile('second'),
  profile('third', {environmentWire: environment(['shared', 'third']),
    connectorBindings: [binding('shared'), binding('third')]})];
  const loaded = await fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
  assert.deepEqual(loaded.connectorBindings,
    ['first', 'shared', 'second', 'third'].map(id => binding(id)));
  assert.doesNotThrow(() => verifyInstalledConnectorBindings(loaded, {
    environmentWire: environment(['shared']), connectorBindings: [binding('shared')]}));
  await loaded.close();
});

test('disjoint catalogs may omit optional physical bindings', async t => {
  const fixture = await installation(t);
  const declarations = ['first', 'second', 'third'].map(name =>
    profile(name, {connectorBindings: undefined}));
  const loaded = await fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
  assert.deepEqual(loaded.connectorBindings, []);
  await loaded.close();
});

for (const fault of ['policy', 'encoding', 'catalog', 'physical', 'missing-binding',
  'duplicate-binding', 'malformed-binding', 'source-ref', 'alias']) {
  test(`third inventory member cannot hide a ${fault} conflict`, async t => {
    const fixture = await installation(t);
    const declarations = [profile('first'), profile('second'), profile('third')];
    const third = declarations[2];
    let code = 'InstalledCheckEnvironmentConflict';
    if (fault === 'policy') third.environmentWire = environment(['third'], body => {
      body.host_policy_profile.capacity.max_effect_items += 1;
    });
    if (fault === 'encoding') third.environmentWire += '\n';
    if (fault === 'catalog') {
      third.environmentWire = environment(['first'], body => {
        const catalog = body.connector_catalogs[0];
        catalog.connector_version = 'changed';
        delete catalog.catalog_cid;
        catalog.catalog_cid = contentCid(catalog);
        body.connector_manifest.connectors[0].connector_version = 'changed';
      });
      third.connectorBindings = [binding('first')];
    }
    if (fault === 'physical' || fault === 'missing-binding') {
      third.environmentWire = environment(['first']);
      third.connectorBindings = fault === 'physical' ? [binding('first', 'elsewhere')] : undefined;
    }
    if (fault === 'duplicate-binding') third.connectorBindings.push(binding('third'));
    if (fault === 'malformed-binding') third.connectorBindings = [binding('undeclared')];
    if (fault === 'source-ref') {
      third.refs = declarations[0].refs;
      third.environmentWire = declarations[0].environmentWire;
      third.connectorBindings = declarations[0].connectorBindings;
      code = 'InstalledSourceBindingAmbiguous';
    }
    if (fault === 'alias') {
      declarations[0].queryAliases = [alias('records', declarations[0].refs[0])];
      third.queryAliases = [alias('records', third.refs[0])];
      code = 'InvalidPublicSourcePublication';
    }
    await assert.rejects(fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options),
      primary(code));
    assert.deepEqual(fixture.events, [['first', 'load'], ['second', 'load'], ['third', 'load'],
      ['first', 'close'], ['second', 'close'], ['third', 'close']]);
  });
}

test('inventory retains the 64 per-member and 128 aggregate read-authority caps', async t => {
  const fixture = await installation(t);
  const refs = (name, count) => Array.from({length: count}, (_, index) =>
    `connector://${name}/records-${index}#v`);
  for (const counts of [[64, 63, 1], [64, 64, 1], [65, 1, 1]]) {
    const declarations = counts.map((count, index) => profile(`member-${index}`,
      {refs: refs(`member-${index}`, count)}));
    const loading = fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
    if (counts[0] === 64 && counts[1] === 63) {
      const loaded = await loading;
      assert.equal(loaded.sources.flatMap(fixture.installedSourceReadBindings).length, 128);
      await loaded.close();
    } else await assert.rejects(loading, primary('InvalidInstalledSourceReadAccesses'));
  }
  const declarations = Array.from({length: 128}, (_, index) => profile(`member-${index}`));
  const loaded = await fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
  assert.equal(loaded.sources.length, 128);
  assert.equal(JSON.parse(loaded.environmentWire).connector_catalogs.length, 128);
  await loaded.close();
});

test('inventory retains aggregate alias publication count and byte caps', async t => {
  const fixture = await installation(t);
  for (const [count, width, accepted] of [[1024, 0, true], [1025, 0, false], [1024, 900, false]]) {
    const declarations = [profile('first'), profile('second'), profile('third')];
    for (let index = 0; index < count; index++) {
      const owner = declarations[index % declarations.length];
      (owner.queryAliases ??= []).push(alias(`alias-${index}` + 'x'.repeat(width), owner.refs[0]));
    }
    const loading = fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
    if (accepted) {
      const loaded = await loading;
      assert.equal(loaded.queryAliases.length, count);
      await loaded.close();
    } else await assert.rejects(loading, primary('InvalidPublicSourcePublication'));
  }
});

test('partial member loading retains original pending cleanup owners through retries', async t => {
  const fixture = await installation(t);
  fixture.blocked.add('first'); fixture.blocked.add('third');
  const paths = await fixture.paths([profile('first'), profile('second'),
    profile('third', {registrationMismatch: true}), profile('fourth')]);
  let failure;
  await assert.rejects(fixture.loadInstalledSources(paths, fixture.options), error => {
    failure = error;
    assert.equal(error.primaryFailure.code, 'InstalledConnectorRegistrationMismatch');
    assert.equal(error.cleanupPending, true);
    return true;
  });
  assert.deepEqual(failure.cleanupHandle.status().owners, ['initialization', 'source-profile']);
  assert.equal(fixture.loaded.has('fourth'), false);
  assert.equal(fixture.events.some(([name, action]) => name !== 'third' && action === 'close'), false);
  fixture.blocked.delete('third');
  await failure.cleanupHandle.retry();
  assert.deepEqual(failure.cleanupHandle.status().owners, ['source-profile']);
  const thirdCloses = fixture.events.filter(([name, action]) => name === 'third' && action === 'close').length;
  fixture.blocked.delete('first');
  await failure.cleanupHandle.retry();
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(failure.primaryFailure.code, 'InstalledConnectorRegistrationMismatch');
  assert.equal(fixture.events.filter(([name, action]) => name === 'third' && action === 'close').length, thirdCloses);
  assert.equal(fixture.events.filter(([name, action]) => name === 'second' && action === 'close').length, 1);
  assert.equal(fixture.events.filter(([name, action]) => name === 'first' && action === 'close').length, 2);
});

test('two-member composition preserves the original environment bytes and binding order', async t => {
  const fixture = await installation(t);
  const declarations = [profile('second'), profile('first')];
  const expected = composeInstalledCheckEnvironment(moon, baseWire,
    ...declarations.map(value => value.environmentWire));
  const loaded = await fixture.loadInstalledSources(await fixture.paths(declarations), fixture.options);
  assert.equal(loaded.environmentWire, expected);
  assert.deepEqual(loaded.connectorBindings, declarations.flatMap(value => value.connectorBindings));
  await loaded.close();
  assert.equal(await fixture.loadInstalledSources([], fixture.options), undefined);
  const singular = await fixture.loadInstalledSources(await fixture.paths([profile('singular')]), fixture.options);
  assert.equal(singular.sources, undefined);
  await singular.close();
});
