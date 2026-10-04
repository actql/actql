import assert from 'node:assert/strict';
import test from 'node:test';
import {installedConnectorFor, installedConnectorTable,
  loadInstalledConnectorModule, providerBundleUrl,
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
