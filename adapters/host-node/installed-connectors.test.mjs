import assert from 'node:assert/strict';
import test from 'node:test';
import {assertInstalledConnectorTable, createInstalledConnectorTable,
  installedConnectorFor, installedConnectorForTable, installedConnectorTable,
  loadInstalledConnectorModule, loadInstalledEffectModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';

const entry = (overrides = {}) => ({
  name: 'example', registration: 'example', revision: 'example/0.1',
  providerBundle: 'connectors/example/host_node', responseHeaders: ['link'],
  source: {profileVersion: 'actql-installed-example-source/0.1',
    load: async () => ({check: p => p, identityParts: p => [p],
      load: async () => ({connectorRegistration: 'example',
        connectorRevision: 'example/0.1'})})},
  ...overrides,
});

test('the installed connector table is keyed by profile version and refuses ambiguity', () => {
  const table = installedConnectorTable([entry(), entry({name: 'other',
    registration: undefined, revision: undefined, providerBundle: undefined,
    source: {profileVersion: 'actql-installed-other-source/0.1',
      load: async () => ({})}})]);
  assert.equal(table.size, 2);
  assert.equal(installedConnectorFor(table,
    {version: 'actql-installed-example-source/0.1'}).name, 'example');
  for (const profile of [undefined, null, {}, {version: 'actql-installed-none/0.1'},
    {version: 7}]) {
    assert.throws(() => installedConnectorFor(table, profile),
      {code: 'InvalidInstalledSourceProfile'});
  }
  assert.throws(() => installedConnectorTable([entry(), entry({name: 'twin',
    registration: 'twin', revision: 'twin/0.1',
    providerBundle: 'connectors/twin/host_node'})]),
  {code: 'InstalledConnectorVersionAmbiguous'});
  for (const invalid of [entry({name: 'Example'}),
    entry({registration: 'other'}), entry({revision: 'example-0.1'}),
    entry({providerBundle: 'adapters/example'}),
    entry({responseHeaders: 'link'}),
    entry({source: {profileVersion: 'installed-example/0.1', load: () => {}}}),
    entry({source: {profileVersion: 'actql-installed-example-source/0.1'}}),
    'example']) {
    assert.throws(() => installedConnectorTable([invalid]),
      {code: 'InvalidInstalledConnectorEntry'});
  }
});

test('a selected module must export the installation entries', async () => {
  const module = await loadInstalledConnectorModule(entry());
  assert.equal(typeof module.check, 'function');
  for (const broken of [{}, {check: 1, identityParts: () => {}, load: () => {}},
    {check: () => {}, identityParts: () => {}, load: () => {}, publish: 1}]) {
    await assert.rejects(loadInstalledConnectorModule(entry({source: {
      profileVersion: 'actql-installed-example-source/0.1',
      load: async () => broken}})), {code: 'InvalidInstalledConnectorModule'});
  }
});

test('declared registration is verified against the loaded implementation', () => {
  const declared = entry();
  const adapter = {connectorRegistration: 'example', connectorRevision: 'example/0.1'};
  assert.equal(verifyInstalledConnectorRegistration(declared, adapter), adapter);
  for (const foreign of [{connectorRegistration: 'other',
    connectorRevision: 'example/0.1'}, {connectorRegistration: 'example',
    connectorRevision: 'example/0.2'}, {}, undefined]) {
    assert.throws(() => verifyInstalledConnectorRegistration(declared, foreign),
      {code: 'InstalledConnectorRegistrationMismatch'});
  }
  // A built-in binding without a declaration is not verified here.
  const builtin = entry({registration: undefined, revision: undefined});
  assert.deepEqual(verifyInstalledConnectorRegistration(builtin, {}), {});
});

test('provider bundle URLs are derived next to the standard runtime', () => {
  assert.equal(providerBundleUrl(entry(), 'file:///repo/adapters/host-node/x.mjs').href,
    'file:///repo/_build/js/release/build/connectors/example/host_node/host_node.js');
  assert.equal(providerBundleUrl(entry({providerBundle: undefined})), undefined);
});

test('the generated table declares Salesforce and nothing provider-named is in the Host', async () => {
  const table = installedConnectorTable(installedConnectors);
  const salesforce = installedConnectorFor(table,
    {version: 'actql-installed-salesforce-source/0.1'});
  assert.equal(salesforce.registration, 'salesforce');
  assert.equal(salesforce.revision, 'salesforce/0.1');
  assert.deepEqual([...salesforce.responseHeaders], []);
  const module = await loadInstalledConnectorModule(salesforce);
  assert.equal(typeof module.publish, 'function');
  const {readFile} = await import('node:fs/promises');
  const host = await readFile(new URL('./installed-source.mjs', import.meta.url),
    'utf8');
  assert.doesNotMatch(host.replace(/\/\/[^\n]*/g, ''), /salesforce/i);
});

test('the Effect table selects declared Effect installations by their own version', async () => {
  const {installedEffectTable, loadInstalledEffectModule} = await import(
    './installed-connectors.mjs');
  const effect = {profileVersion: 'actql-installed-example-effect/0.1',
    load: async () => ({check: p => p, identityParts: p => [p],
      load: async () => ({})})};
  const table = installedEffectTable([entry({effect}), entry({name: 'plain',
    registration: undefined, revision: undefined, providerBundle: undefined,
    source: {profileVersion: 'actql-installed-plain-source/0.1',
      load: async () => ({})}})]);
  assert.deepEqual([...table.keys()], ['actql-installed-example-effect/0.1']);
  assert.equal(installedConnectorFor(table,
    {version: 'actql-installed-example-effect/0.1'},
    'InvalidInstalledEffectProfile').name, 'example');
  // A source version never selects an Effect installation.
  assert.throws(() => installedConnectorFor(table,
    {version: 'actql-installed-example-source/0.1'},
    'InvalidInstalledEffectProfile'), {code: 'InvalidInstalledEffectProfile'});
  assert.equal(typeof (await loadInstalledEffectModule(table.get(
    'actql-installed-example-effect/0.1'))).load, 'function');
  assert.throws(() => installedEffectTable([entry({effect: {...effect,
    profileVersion: 'actql-installed-example-source/0.1'}})]),
  {code: 'InvalidInstalledConnectorEntry'});
  assert.throws(() => installedEffectTable([entry({effect}), entry({
    name: 'twin', registration: 'twin', revision: 'twin/0.1',
    providerBundle: 'connectors/twin/host_node',
    source: {profileVersion: 'actql-installed-twin-source/0.1',
      load: async () => ({})}, effect})]),
  {code: 'InstalledConnectorVersionAmbiguous'});
  const {readFile} = await import('node:fs/promises');
  const host = await readFile(new URL('./installed-effect.mjs', import.meta.url),
    'utf8');
  assert.doesNotMatch(host.replace(/\/\/[^\n]*/g, ''), /salesforce/i);
});

const identityProfile = () => ({
  continuation: 'actql-installed-example-effect-continuation/0.1',
  continuationBinding: 'publication_generation_cid',
  dispatch: 'actql-installed-example-effect-dispatch/0.1',
  recovery: 'actql-installed-example-effect-recovery/0.1',
  source: 'actql-installed-example-effect-source/0.1',
  targetCheck: 'actql-installed-example-effect-check/0.1',
  unit: 'actql-installed-example-effect-unit/0.1',
});
const effectEntry = (overrides = {}) => entry({source: undefined,
  effect: {profileVersion: 'actql-installed-example-effect/0.1',
    identityProfile: identityProfile(), load() { assert.fail('Unused loader'); }},
  ...overrides});

test('owned tables admit independent roles and empty tables without default entries', () => {
  const source = entry({source: {
    profileVersion: 'actql-installed-shared-schema/0.1',
    load() { assert.fail('Unused loader'); }}});
  const effect = effectEntry({effect: {
    profileVersion: source.source.profileVersion,
    load() { assert.fail('Unused loader'); }}});
  const table = createInstalledConnectorTable([source, effect]);
  const profile = {version: source.source.profileVersion};
  assert.equal(installedConnectorForTable(table, 'source', profile).source.load,
    source.source.load);
  assert.equal(installedConnectorForTable(table, 'effect', profile).effect.load,
    effect.effect.load);
  for (const [entries, role, version] of [
    [[], 'source', 'actql-installed-github-source/0.1'],
    [[], 'effect', 'actql-installed-github-effect/0.1'],
    [[source], 'effect', profile.version],
    [[effect], 'source', profile.version],
  ]) {
    assert.throws(() => installedConnectorForTable(
      createInstalledConnectorTable(entries), role, {version}),
    {code: role === 'source' ? 'InvalidInstalledSourceProfile' :
      'InvalidInstalledEffectProfile'});
  }
  assert.throws(() => installedConnectorForTable(table, 'source', {}, 'Missing'),
    {code: 'Missing'});
});

test('owned tables refuse duplicate versions per role before any loader call', () => {
  const unused = () => { assert.fail('No loader may run during admission'); };
  for (const role of ['source', 'effect']) {
    const first = {name: 'one', [role]: {
      profileVersion: 'actql-installed-shared-schema/0.1', load: unused}};
    const second = {name: 'two', [role]: {...first[role]}};
    assert.throws(() => createInstalledConnectorTable([first, second]),
      {code: 'InstalledConnectorVersionAmbiguous'});
  }
  for (const entries of [null, {}, new Map(), [undefined], [{}]]) {
    assert.throws(() => createInstalledConnectorTable(entries),
      {code: 'InvalidInstalledConnectorEntry'});
  }
});

test('two owned tables select their exact implementations of the same schemas', async () => {
  const module = name => ({name, check: value => value,
    identityParts: value => [value], load: async () => ({})});
  const firstSource = module('first-source'), secondSource = module('second-source');
  const firstEffect = module('first-effect'), secondEffect = module('second-effect');
  const make = (source, effect) => createInstalledConnectorTable([entry({
    source: {profileVersion: 'actql-installed-example-source/0.1',
      load: () => source},
    effect: {profileVersion: 'actql-installed-example-effect/0.1',
      load: () => effect},
  })]);
  const first = make(firstSource, firstEffect);
  const second = make(secondSource, secondEffect);
  for (const [table, source, effect] of [[first, firstSource, firstEffect],
    [second, secondSource, secondEffect]]) {
    assert.equal(await loadInstalledConnectorModule(installedConnectorForTable(
      table, 'source', {version: 'actql-installed-example-source/0.1'})), source);
    assert.equal(await loadInstalledEffectModule(installedConnectorForTable(
      table, 'effect', {version: 'actql-installed-example-effect/0.1'})), effect);
  }
});

test('table admission snapshots every declared field and lazy reference synchronously', () => {
  const raw = entry({effect: effectEntry().effect});
  const sourceLoad = raw.source.load, effectLoad = raw.effect.load;
  const originalIdentity = {...raw.effect.identityProfile};
  const inputs = [raw];
  const table = createInstalledConnectorTable(inputs);
  const selected = installedConnectorForTable(table, 'source',
    {version: raw.source.profileVersion});
  raw.name = 'changed';
  raw.registration = 'changed';
  raw.revision = 'changed/0.2';
  raw.providerBundle = 'connectors/changed/host_node';
  raw.responseHeaders.push('retry-after');
  raw.source.profileVersion = 'actql-installed-changed-source/0.1';
  raw.source.load = () => { assert.fail('Replaced source loader'); };
  raw.effect.profileVersion = 'actql-installed-changed-effect/0.1';
  raw.effect.load = () => { assert.fail('Replaced Effect loader'); };
  for (const key of Object.keys(raw.effect.identityProfile)) {
    raw.effect.identityProfile[key] = 'changed';
  }
  inputs.splice(0, 1);
  assert.deepEqual(selected, {name: 'example', registration: 'example',
    revision: 'example/0.1', providerBundle: 'connectors/example/host_node',
    responseHeaders: ['link'],
    source: {profileVersion: 'actql-installed-example-source/0.1', load: sourceLoad},
    effect: {profileVersion: 'actql-installed-example-effect/0.1',
      load: effectLoad, identityProfile: originalIdentity}});
  assert.equal(installedConnectorForTable(table, 'effect',
    {version: 'actql-installed-example-effect/0.1'}), selected);
  for (const value of [table, selected, selected.responseHeaders, selected.source,
    selected.effect, selected.effect.identityProfile]) assert.ok(Object.isFrozen(value));
  assert.notEqual(selected, raw);
  assert.notEqual(selected.source, raw.source);
  assert.notEqual(selected.effect, raw.effect);
  assert.notEqual(selected.effect.identityProfile, raw.effect.identityProfile);
  assert.throws(() => { selected.source.load = raw.source.load; }, TypeError);
  assert.throws(() => { selected.effect.identityProfile.unit = 'changed'; }, TypeError);
});

test('only the owner-issued table handle is accepted and no mutable Map is exposed', () => {
  const table = createInstalledConnectorTable([entry()]);
  assert.equal(assertInstalledConnectorTable(table), table);
  assert.deepEqual(Reflect.ownKeys(table), []);
  assert.equal(table instanceof Map, false);
  for (const forged of [undefined, null, {}, Object.freeze({}), {...table},
    structuredClone(table), Object.create(table), new Proxy(table, {}), new Map()]) {
    assert.throws(() => assertInstalledConnectorTable(forged),
      {code: 'InvalidInstalledConnectorTable'});
    assert.throws(() => installedConnectorForTable(forged, 'source', {}),
      {code: 'InvalidInstalledConnectorTable'});
  }
  assert.throws(() => installedConnectorForTable(table, 'other', {}),
    {code: 'InvalidInstalledConnectorRole'});
});

test('owned declarations preserve the closed identity profile and response-header rules', () => {
  const invalidProfiles = [null, {}, [], {...identityProfile(), extra: 'value'},
    {...identityProfile(), continuationBinding: 'arbitrary_field'},
    {...identityProfile(), dispatch: 'actql-installed-example-effect-dispatch/0.2'},
    {...identityProfile(), unit: () => 'actql-installed-example-effect-unit/0.1'}];
  const {unit: _unit, ...missingUnit} = identityProfile();
  invalidProfiles.push(missingUnit);
  for (const profile of invalidProfiles) {
    const raw = effectEntry();
    raw.effect.identityProfile = profile;
    assert.throws(() => createInstalledConnectorTable([raw]),
      {code: 'InvalidInstalledConnectorEntry'});
  }
  for (const responseHeaders of ['link', ['Link'], ['link', 'link'],
    ['authorization'], ['set-cookie'], Array.from({length: 17}, (_, i) => `x-${i}`)]) {
    assert.throws(() => createInstalledConnectorTable([entry({responseHeaders})]),
      {code: 'InvalidInstalledConnectorEntry'});
  }
  for (const providerBundle of ['../example', '/connectors/example/host_node',
    'connectors/example/../host_node', 'https://example.test/runtime.js']) {
    assert.throws(() => createInstalledConnectorTable([entry({providerBundle})]),
      {code: 'InvalidInstalledConnectorEntry'});
  }
});
