// Test assembly of the installed Salesforce Effect over the local HTTPS org:
// an installed Site profile, the Host's Effect profile and its published
// generation, and the common Effect Run owners that call the factory. The
// Run-start and publication-plan facts stand in for the standard Host's
// installed Effect path; the factory under test receives only them.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {effectHost as createRowEffectHost} from '../../../host-node/fixtures/installed-row-effect.fixture.mjs';
import {INSTALLED_SALESFORCE_EFFECT_VERSION, checkInstalledSalesforceEffectProfile, loadInstalledSalesforceEffect,
  publishInstalledSalesforceEffect, salesforceEffectUnit} from
  '../host/installed-salesforce-effect.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../host/installed-salesforce-site.mjs';
import {checkInstalledSalesforceSourceProfile, loadInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';
import {createInstalledLoaderParent} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {retainInstalledHostServiceInstallation, beginInstalledSourceInitialization,
  bindInstalledSourceConstruction, finishInstalledSourceInitialization,
  retainBoundInstalledSourceFailure, withInstalledSourceLoading} from '../../../host-node/installed-host-services.mjs';


export {moon, salesforceMoon};
const cid = digit => `sha256:${digit.repeat(64)}`;
const repository = new URL('../../../../', import.meta.url);

// Entries are in the configuration's canonical order (by entry id).
export const accountConfiguration = entries => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-effect-account', entries: [...entries].sort(
    (a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0)});

export const recordEntry = (orgId, operation, outcome = 'allow',
  resource = 'Test_Record__c') => ({
  entry_id: `records-${resource.toLowerCase().replaceAll('_', '-')}-${
    operation}`,
  outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [`salesforce:${orgId}`]},
  resource: {any_of: [resource]}, operation: {any_of: [operation]}});

// The local org, the installed Site profile, and a published Effect profile
// for `writes`. `load` installs the Effect as a Host start would; `publish`
// republishes the generation explicitly.
// `principalId` and `accountConfigurationWire` default to a standalone
// installation; a standard Host's installation uses the Host's own.
export async function installedEffect(t, {writes, writeOperation = 'update',
  entries, siteProfile = {}, org: orgOptions = {},
  principalId = 'principal-a', accountConfigurationWire, connectorId = 'salesforce'} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon: moon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    writeOperation, connectorId, ...orgOptions});
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-effect-'));
  const loaderParents = [];
  // Hosts over this installation end before its directories are removed.
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    for (const parent of loaderParents.reverse()) await parent.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      t.diagnostic(`Retained installed Salesforce Effect fixture: ${root}`);
    } else {
      await rm(root, {recursive: true, force: true});
    }
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const siteDocument = {
    version: INSTALLED_SALESFORCE_SITE_VERSION,
    apiVersion: 'v62.0', cliAlias: 'actql-test',
    cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'credential-journal'), orgId: org.orgId,
    siteGeneration: 1, siteKey: 'salesforce-site', namespaceId: 'namespace-a',
    caPath: join(root, 'org-ca.crt'), ...siteProfile,
  };
  const sitePath = join(root, 'salesforce-site.json');
  const writeSite = document => writeFile(sitePath, JSON.stringify(document));
  await writeSite(siteDocument);
  const baseEnvironmentWire = (await readFile(new URL(
    'spec/local-check-environment.json', repository), 'utf8')).trimEnd();
  const profile = {
    version: INSTALLED_SALESFORCE_EFFECT_VERSION,
    siteProfilePath: sitePath,
    accountConfigurationWire: accountConfigurationWire ??
      accountConfiguration(entries ?? [recordEntry(org.orgId, 'read'),
        recordEntry(org.orgId, 'effect')]),
    connectorId,
    publicationPath: join(root, 'effect-publication.json'),
    writes,
  };
  const options = {root, principalId, moon, salesforceMoon,
    runtimeBundleCid: cid('b'),
    resolveSecret: async () => 'test-only-secret', baseEnvironmentWire};
  const ledgerRoot = join(root, 'effect-ledger');
  await mkdir(ledgerRoot, {recursive: true});
  const publish = (overrides = {}, publishOptions = {}) =>
    publishInstalledSalesforceEffect({...profile, ...overrides},
      {...options, ...publishOptions});
  const loadProvider = async (profile, selected, role, check, loader) => {
    // Keep the actual provider loader and its explicit fault/runtime ports.
    // Its original Source constructor now belongs to this real installation
    // parent, as it does in the common installed loader. No scope is mocked.
    const parent = createInstalledLoaderParent(selected);
    loaderParents.push(parent);
    parent.open();
    return parent.load((profile, originalOptions) => withInstalledSourceLoading(parent.services, async () => {
      const originalProfile = check(profile);
      const entry = installedConnectors.find(entry => entry[role]?.profileVersion === originalProfile.version);
      assert(entry);
      const services = parent.services;
      retainInstalledHostServiceInstallation(services,entry,originalOptions.runtimeBundleCid);
      const initialization = beginInstalledSourceInitialization(services,entry,
        originalProfile.connectorId,originalOptions.baseEnvironmentWire,role);
      let adapter;
      try {
        adapter = await loader(originalProfile,{...originalOptions,
          construction:bindInstalledSourceConstruction(services,initialization,originalProfile)});
        finishInstalledSourceInitialization(initialization,adapter);
        return adapter;
      } catch (cause) {
        const failure = await retainBoundInstalledSourceFailure(initialization,cause,adapter);
        finishInstalledSourceInitialization(initialization,adapter,failure,true);
        throw failure;
      }
    }),profile,selected);
  };
  const load = (overrides = {}, loadOptions = {}) => loadProvider(
    {...profile, ...overrides}, {...options, ledgerRoot, ...loadOptions},
    'effect', checkInstalledSalesforceEffectProfile, loadInstalledSalesforceEffect);
  const loadSource = (sourceProfile, loadOptions = {}) => loadProvider(
    sourceProfile, {...options, providerMoon: salesforceMoon, ...loadOptions},
    'source', checkInstalledSalesforceSourceProfile, loadInstalledSalesforceSource);
  const published = await publish();
  return {org, root, profile, siteDocument, writeSite, published, publish,
    load, loadSource, baseEnvironmentWire, options, ledgerRoot,
    onClose: close => closers.push(close)};
}

// A Values Program whose one Unit writes `rows` through each named Effect.
export function effectProgram(effects, rows, schema = {id: {type: 'string',
  nullable: false}}, fields = Object.keys(schema)) {
  return {version: 'actql/0.1', id: 'client-values', stages: [{
    id: 'source', inputs: {},
    steps: [{values: {schema, rows}, as: 'selected'}],
    results: {rows: {from: 'selected', fields}},
    effects}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}};
}

// Compatibility name retains the original Salesforce unit projection; the
// neutral test helper contains the same capture/recovery/cleanup assembly.
export async function effectHost(t, installation, state, options = {}) {
  return createRowEffectHost(t, installation, state, {...options, unitOf: salesforceEffectUnit});
}
