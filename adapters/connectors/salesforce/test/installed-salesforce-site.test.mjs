import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {accountEntry} from '../../../host-node/authorization-fixture.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION, installSalesforceAuthorization,
  loadInstalledSalesforceSite} from
  '../host/installed-salesforce-site.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const configuration = entries => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-account', entries});

// A Host profile against the local HTTPS org. Only the provider secret is
// supplied by the test; the account gate comes from the Host installation and
// the credential authority and org binding from the installed profile.
async function installed(t, {entries, profile = {}, secret} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-salesforce-'));
  // Close every loaded Site before its journal directory is removed.
  const sites = [];
  t.after(async () => {
    for (const site of sites) site.close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const document = {
    version: INSTALLED_SALESFORCE_SITE_VERSION,
    apiVersion: 'v62.0', cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'credential-journal'), orgId: org.orgId,
    siteGeneration: 1, siteKey: 'salesforce-site', tenant: 'tenant-a',
    caPath: join(root, 'org-ca.crt'), ...profile,
  };
  const path = join(root, 'salesforce-site.json');
  await writeFile(path, JSON.stringify(document));
  const scopes = [];
  const accountConfiguration = configuration(entries ?? [
    accountEntry('records-read', 'allow', {
      connection: `salesforce:${org.orgId}`, resource: 'Test_Record__c',
      operation: 'read'}),
  ]);
  const load = async (options = {}) => {
    const authorization = await installSalesforceAuthorization({
      accountConfiguration, principalId: 'principal-a', root});
    const site = await loadInstalledSalesforceSite(path, {
      commonMoon, salesforceMoon, authorization,
      runtimeBundleCid: cid('b'),
      resolveSecret: secret ?? (async scope => {
        scopes.push(scope);
        return 'test-only-secret';
      }), ...options});
    sites.push(site);
    return site;
  };
  return {org, root, path, document, scopes, load};
}

test('installed Salesforce Site syncs its Catalog under Host-issued grants',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const before = setup.org.seen.length;
    const catalog = await site.refreshCatalog({occurrence: 'sync-a'});
    assert.equal(catalog.status, 'complete');
    assert.deepEqual(setup.org.seen.slice(before).map(item => item.path), [
      '/services/data/v62.0/sobjects/',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
    ]);
    const binding = JSON.parse(catalog.observationJson).binding;
    assert.equal(binding.principal, 'principal-a');
    assert.equal(binding.org_id, setup.org.orgId);
    assert.equal(binding.site_key, 'salesforce-site');
    // The secret source sees only the installed scope.
    assert.deepEqual([...new Set(setup.scopes.map(scope => [scope.principal,
      scope.tenant, scope.environment, scope.siteKey, scope.resourceOrigin]
      .join(' ')))], [`principal-a tenant-a test salesforce-site ${
      setup.org.origin}`]);
  });

test('installed Salesforce grants follow only this Site\'s own dispatch',
  async t => {
    const setup = await installed(t, {entries: [
      accountEntry('records-read', 'allow', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'read'}),
      accountEntry('records-write', 'deny', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'effect'}),
    ]});
    const site = await setup.load();
    const grant = decision => site.issueGrant({
      operation: 'salesforce:record:observe', decision,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')});
    const read = {connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'};
    const allowed = await site.authorization.authorize('acquisition', read,
      {subjectCid: cid('5')});
    assert.equal(allowed.action, 'dispatch');
    const issued = grant(allowed);
    assert.equal(issued.scope.operation, 'salesforce:record:observe');
    assert.equal(issued.scope.issuerAuthority, 'host-credential-authority');
    assert.equal(issued.scope.maxUses, 1);
    // A copied or forged decision is not this gate's dispatch.
    for (const decision of [undefined, {...allowed},
      Object.freeze({action: 'dispatch', boundary: 'acquisition',
        contextCid: site.context.contextCid, tuple: read})]) {
      assert.throws(() => grant(decision),
        {code: 'SalesforceCredentialGrantNotAuthorized'});
    }
    // The decision covers one exact Resource and operation class.
    assert.throws(() => site.issueGrant({
      operation: 'salesforce:record:observe', decision: allowed,
      resource: 'Account', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    assert.throws(() => site.issueGrant({
      operation: 'salesforce:record:update', decision: allowed,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    const denied = await site.authorization.authorize('effect_commit', {
      connection: site.connection, resource: 'Test_Record__c',
      operation: 'effect'}, {subjectCid: cid('6')});
    assert.equal(denied.action, 'deny');
    assert.throws(() => site.issueGrant({
      operation: 'salesforce:record:update', decision: denied,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    const unconfigured = await site.authorization.authorize('acquisition',
      {...read, resource: 'Account'}, {subjectCid: cid('7')});
    assert.notEqual(unconfigured.action, 'dispatch');
  });

test('installed Salesforce profile refuses incomplete or foreign settings',
  async t => {
    const setup = await installed(t);
    await assert.rejects(loadInstalledSalesforceSite('relative.json', {}),
      {code: 'InvalidInstalledSalesforceSiteProfilePath'});
    for (const change of [
      {instanceOrigin: 'http://127.0.0.1:1'},
      {orgId: 'not-an-org'},
      {journalRoot: 'relative-journal'},
      {extra: true},
      {version: 'actql-installed-salesforce-site/9'},
    ]) {
      await writeFile(setup.path, JSON.stringify({...setup.document,
        ...change}));
      await assert.rejects(setup.load(),
        {code: 'InvalidInstalledSalesforceSiteProfile'}, JSON.stringify(change));
    }
    const {credentialKeyId: _omitted, ...missing} = setup.document;
    await writeFile(setup.path, JSON.stringify(missing));
    await assert.rejects(setup.load(),
      {code: 'InvalidInstalledSalesforceSiteProfile'});
    // A rejected account configuration fails installation; it never
    // degrades to allow.
    await assert.rejects(installSalesforceAuthorization({
      accountConfiguration: '{"account_id":"a","entries":[]}',
      principalId: 'principal-a', root: setup.root}), error =>
      error.runtimeCode === 'ACTQL_E_ACCOUNT_CONFIG_INVALID' ||
      error.code === 'ACTQL_E_ACCOUNT_CONFIG_INVALID');
    // A Site accepts only an installed authorization, never a bare gate.
    await writeFile(setup.path, JSON.stringify(setup.document));
    await assert.rejects(loadInstalledSalesforceSite(setup.path, {commonMoon,
      salesforceMoon, runtimeBundleCid: cid('b'),
      authorization: {context: {principal: 'principal-a'},
        authorize: async () => ({action: 'dispatch'})}}),
    {code: 'InvalidInstalledSalesforceSiteOptions'});
    // Without a supplied secret source the profile's sf CLI connection is
    // the only resolver, bound to the installed org.
    const site = await setup.load({resolveSecret: undefined});
    assert.equal(site.credential.resolveSecret.connectionOrgId,
      setup.org.orgId);
  });

test('installed Salesforce peek reads a bounded prefix under its own grant',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const read = {connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'};
    const decision = await site.authorization.authorize('acquisition', read,
      {subjectCid: cid('8')});
    const queries = () => setup.org.seen.filter(item =>
      item.path.startsWith('/services/data/v62.0/query'));
    const preview = await site.peek({decision, resource: 'Test_Record__c',
      fields: ['Id', 'Name'], maxRows: 2});
    assert.deepEqual(preview.rows, [
      {Id: 'a00000000000001', Name: 'record-1'},
      {Id: 'a00000000000002', Name: 'record-2'},
    ]);
    assert.equal(preview.limited, true);
    assert.match(preview.observationCid, /^sha256:[0-9a-f]{64}$/u);
    assert.deepEqual(queries().map(item => decodeURIComponent(item.path)), [
      '/services/data/v62.0/query?q=SELECT Id,Name FROM Test_Record__c LIMIT 2',
    ]);
    const all = await site.peek({decision, resource: 'Test_Record__c',
      fields: ['Id'], maxRows: 5});
    assert.equal(all.rows.length, 3);
    assert.equal(all.limited, false);
    // Only the installed gate's read dispatch for this Resource reads rows.
    const sent = queries().length;
    for (const forged of [undefined, {...decision}]) {
      await assert.rejects(site.peek({decision: forged,
        resource: 'Test_Record__c', fields: ['Id'], maxRows: 1}),
      {code: 'SalesforcePeekNotAuthorized'});
    }
    await assert.rejects(site.peek({decision, resource: 'Account',
      fields: ['Id'], maxRows: 1}), {code: 'SalesforcePeekNotAuthorized'});
    await assert.rejects(site.peek({decision, resource: 'Test_Record__c',
      fields: ['Missing__c'], maxRows: 1}));
    await assert.rejects(site.peek({decision, resource: 'Test_Record__c',
      fields: ['Id'], maxRows: 201}), {code: 'InvalidSalesforcePeek'});
    assert.equal(queries().length, sent);
  });
