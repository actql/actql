import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import './installed-salesforce-site-cleanup.test.mjs';
import {DatabaseSync} from 'node:sqlite';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {accountEntry} from '../../../host-node/authorization-fixture.mjs';
import {createLocalAuthorizationGate} from
  '../../../host-node/local-account-config.mjs';
import {retainSalesforceSiteCleanup} from
  '../host/installed-salesforce-site.mjs';
import {INSTALLED_SALESFORCE_SOURCE_VERSION,
  publishInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {createInstalledHostShutdown} from
  '../../../host-node/installed-host-cleanup.mjs';
import {DEFAULT_SALESFORCE_CATALOG_LIMITS, INSTALLED_SALESFORCE_SITE_VERSION,
  installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite} from
  '../host/installed-salesforce-site.mjs';
import {closeFailingJournal, openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';
import {declarationEnvironment, declaredReadProgram} from
  './salesforce-declaration-environment.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const configuration = entries => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-account', entries});

// A Host profile against the local HTTPS org. Only the provider secret is
// supplied by the test; the account gate comes from the Host installation and
// the credential authority and org binding from the installed profile.
async function installed(t, {entries, profile = {}, secret,
  extraObjects, idSortable, storedOrder, storedRecords} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    extraObjects, idSortable, storedOrder, storedRecords});
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
    siteGeneration: 1, siteKey: 'salesforce-site', namespaceId: 'namespace-a',
    caPath: join(root, 'org-ca.crt'), ...profile,
  };
  const path = join(root, 'salesforce-site.json');
  await writeFile(path, JSON.stringify(document));
  const scopes = [];
  const defaultEntries = entries ?? [
    accountEntry('records-read', 'allow', {
      connection: `salesforce:${org.orgId}`, resource: 'Test_Record__c',
      operation: 'read'}),
  ];
  // `entries` replaces the account configuration for this load only, as a
  // Host restarted with changed permissions would.
  const load = async ({entries: loadEntries, path: loadPath = path,
    ...options} = {}) => {
    const authorization = await installSalesforceAuthorization({
      accountConfiguration: configuration(loadEntries ?? defaultEntries),
      principalId: 'principal-a', root});
    const site = await loadInstalledSalesforceSite(loadPath, {
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
      scope.namespaceId, scope.environment, scope.siteKey, scope.resourceOrigin]
      .join(' ')))], [`principal-a namespace-a test salesforce-site ${
      setup.org.origin}`]);
  });

test('coinstalled roles bind to exact non-secret Site and principal facts',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const expected = installedSalesforceSiteBinding(site, 'crm-main');
    assert.deepEqual(installedSalesforceSiteBinding(site, 'crm-main'),
      expected);
    for (const difference of [{principal: 'foreign-principal'},
      {siteGeneration: 2}, {cliAlias: 'other-org-alias'},
      {credentialKeyId: 'other-authority-key'}]) {
      assert.notEqual(installedSalesforceSiteBinding({...site, ...difference},
        'crm-main').bindingCid, expected.bindingCid);
    }
  });

test('Host retries a real Site journal close without restarting its owners',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const providerRequests = setup.org.seen.length;
    const originalClose = DatabaseSync.prototype.close;
    const injectedFailure = new Error('InjectedSiteJournalCloseFailure');
    let physicalCloses = 0;
    DatabaseSync.prototype.close = function () {
      if (++physicalCloses === 1) throw injectedFailure;
      return originalClose.call(this);
    };
    t.after(() => { DatabaseSync.prototype.close = originalClose; });
    const calls = [];
    const shutdown = createInstalledHostShutdown({
      stop: () => calls.push('stop'),
      drain: () => calls.push('drain'),
      retire: () => calls.push('retire'),
      checkpoint: () => calls.push('checkpoint'),
      journal: () => calls.push('journal'),
      source: () => { calls.push('source'); site.close(); },
      effect: () => calls.push('effect'),
      store: () => calls.push('store'),
    });
    let pending;
    await assert.rejects(shutdown.close(), error => {
      pending = error;
      assert.equal(error.code, 'InstalledHostCleanupPending');
      assert.equal(error.cleanupErrors[0].error, injectedFailure);
      assert.deepEqual(error.cleanupHandle.status().pending, ['source']);
      return true;
    });
    assert.deepEqual(calls, ['stop', 'drain', 'retire', 'checkpoint',
      'journal', 'source', 'effect', 'store']);
    await assert.rejects(site.refreshCatalog({occurrence: 'after-close'}),
      {code: 'SalesforceSiteClosed'});
    assert.equal(setup.org.seen.length, providerRequests);
    await pending.cleanupHandle.retry();
    assert.deepEqual(shutdown.status().pending, []);
    assert.deepEqual(calls, ['stop', 'drain', 'retire', 'checkpoint',
      'journal', 'source', 'effect', 'store', 'source']);
    assert.equal(physicalCloses, 2);
    await setup.load();
    assert.equal(setup.org.seen.length, providerRequests);
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
      dispatchRequestCid: cid('4'), subjectCid: cid('5')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    const denied = await site.authorization.authorize('effect_commit', {
      connection: site.connection, resource: 'Test_Record__c',
      operation: 'effect'}, {subjectCid: cid('6')});
    assert.equal(denied.action, 'deny');
    assert.throws(() => site.issueGrant({
      operation: 'salesforce:record:update', decision: denied,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4'), subjectCid: cid('6')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    const unconfigured = await site.authorization.authorize('acquisition',
      {...read, resource: 'Account'}, {subjectCid: cid('7')});
    assert.notEqual(unconfigured.action, 'dispatch');
  });

test('a record write is granted only for the commit decision of its Set',
  async t => {
    const setup = await installed(t, {entries: [
      accountEntry('records-write', 'allow', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'effect'}),
    ]});
    const site = await setup.load();
    const tuple = {connection: site.connection, resource: 'Test_Record__c',
      operation: 'effect'};
    const decision = await site.authorization.authorize('effect_commit',
      tuple, {subjectCid: cid('6')});
    assert.equal(decision.action, 'dispatch');
    const grant = subjectCid => site.issueGrant({
      operation: 'salesforce:record:update', decision,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4'), subjectCid});
    assert.equal(grant(cid('6')).scope.operation, 'salesforce:record:update');
    // Another sealed Set's approval, or none named, grants no write.
    assert.throws(() => grant(cid('7')),
      {code: 'SalesforceCredentialGrantNotAuthorized'});
    assert.throws(() => grant(undefined),
      {code: 'InvalidSalesforceCredentialGrantRequest'});
  });

test('a Host commit dispatch is admitted only for this principal and configuration',
  async t => {
    const entries = [accountEntry('records-write', 'allow', {
      connection: 'salesforce:00D000000000001EAA',
      resource: 'Test_Record__c', operation: 'effect'})];
    const setup = await installed(t, {entries});
    const site = await setup.load();
    const tuple = {connection: site.connection, resource: 'Test_Record__c',
      operation: 'effect'};
    // Another gate of the Host (as its Checkpoint commit gate is), deciding
    // under an account configuration and principal.
    const hostGate = async ({principal = 'principal-a',
      configurationEntries = entries} = {}) => {
      const gate = await createLocalAuthorizationGate({
        accountConfiguration: configuration(configurationEntries), principal,
        context: {principal, contextCid: cid('0')}});
      t.after(() => gate.close());
      return gate;
    };
    const decide = async (gate, subjectCid = cid('6'), scope = tuple) =>
      gate.authorize('effect_commit', scope, {subjectCid});
    const grant = (decision, resource = 'Test_Record__c') => site.issueGrant({
      operation: 'salesforce:record:update', decision, resource,
      runInvocationCid: cid('3'), dispatchRequestCid: cid('4'),
      subjectCid: cid('6')});
    const host = await hostGate();
    const allowed = await decide(host);
    assert.equal(allowed.action, 'dispatch');
    assert.equal(grant(allowed).scope.operation, 'salesforce:record:update');
    const otherPrincipal = await decide(await hostGate({
      principal: 'principal-b'}));
    // The same allow under a configuration that also allows reads (entries
    // in canonical order).
    const otherConfiguration = await decide(await hostGate({
      configurationEntries: [accountEntry('records-read', 'allow', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'read'}), ...entries]}));
    for (const decision of [
      // Constructed or copied, another principal, another configuration,
      // another Set, another Resource.
      Object.freeze({...allowed}), otherPrincipal, otherConfiguration,
      await decide(host, cid('7')),
      await decide(host, cid('6'), {...tuple, resource: 'Account'}),
    ]) {
      assert.throws(() => grant(decision),
        {code: 'SalesforceCredentialGrantNotAuthorized'});
    }
    assert.equal(otherPrincipal.action, 'dispatch');
    assert.equal(otherConfiguration.action, 'dispatch');
    // A commit decision never grants a read.
    assert.throws(() => site.issueGrant({
      operation: 'salesforce:record:observe', decision: allowed,
      resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
  });

test('an Effect capability attestation signs no grant and uses no credential',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const uses = setup.org.journal.recover().length;
    const seen = setup.org.seen.length;
    const authority = site.attestEffectCapability({
      operation: 'salesforce:record:update', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')});
    assert.equal(authority.scope.runtimeBundleCid, cid('b'));
    assert.equal(authority.scope.siteGeneration, 1);
    assert.equal(authority.scope.operation, 'salesforce:record:update');
    assert.equal('grant' in authority, false);
    for (const operation of ['salesforce:record:observe',
      'salesforce:query:read', 'salesforce:catalog:describe']) {
      assert.throws(() => site.attestEffectCapability({operation,
        runInvocationCid: cid('3'), dispatchRequestCid: cid('4')}),
      {code: 'InvalidSalesforceCredentialGrantRequest'});
    }
    assert.equal(setup.org.journal.recover().length, uses);
    assert.equal(setup.org.seen.length, seen);
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
    // Id is not described as sortable here, so no order is imposed.
    assert.equal(preview.order, 'provider');
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

test('installed Salesforce peek states a typed value violation', async t => {
  // A text field answered with a number.
  const setup = await installed(t, {storedRecords: [
    {Id: 'a00000000000001', Name: 12345}]});
  const site = await setup.load();
  const decision = await site.authorization.authorize('acquisition',
    {connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'}, {subjectCid: cid('8')});
  const failure = await site.peek({decision, resource: 'Test_Record__c',
    fields: ['Id', 'Name'], maxRows: 2}).then(() => undefined, error => error);
  assert.equal(failure?.code, 'SalesforceValueViolation', String(failure?.code));
  assert.deepEqual(failure.violation, {expected_type: 'string',
    field: 'Name', kind: 'type', resource: 'Test_Record__c'});
  assert.equal(JSON.stringify(failure.violation).includes('12345'), false);
});

test('installed Salesforce peek describes only its Resource in a larger org',
  async t => {
    const extraObjects = ['Account', 'Contact', 'Lead', 'Opportunity',
      'Case'];
    const setup = await installed(t, {extraObjects});
    const site = await setup.load();
    const decision = await site.authorization.authorize('acquisition', {
      connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'}, {subjectCid: cid('9')});
    const before = setup.org.seen.length;
    const preview = await site.peek({decision, resource: 'Test_Record__c',
      fields: ['Id'], maxRows: 2});
    assert.equal(preview.rows.length, 2);
    // The plan and the recheck each describe only the previewed Resource,
    // then one query; the sObject listing is never read.
    assert.deepEqual(setup.org.seen.slice(before).map(item =>
      decodeURIComponent(item.path)), [
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/query?q=SELECT Id FROM Test_Record__c LIMIT 2',
    ]);
    // A whole-Catalog sync still describes every selected object.
    const fullStart = setup.org.seen.length;
    const full = await site.refreshCatalog({occurrence: 'full-sync'});
    assert.equal(full.status, 'complete');
    assert.equal(setup.org.seen.slice(fullStart).filter(item =>
      item.path.endsWith('/describe')).length, extraObjects.length + 1);
  });

test('installed Salesforce peek orders by Id only where Id is sortable',
  async t => {
    const setup = await installed(t, {idSortable: true,
      storedOrder: [3, 1, 2]});
    const site = await setup.load();
    const decision = await site.authorization.authorize('acquisition', {
      connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'}, {subjectCid: cid('a')});
    const preview = await site.peek({decision, resource: 'Test_Record__c',
      fields: ['Id'], maxRows: 2});
    assert.equal(preview.order, 'id');
    assert.deepEqual(preview.rows, [{Id: 'a00000000000001'},
      {Id: 'a00000000000002'}]);
    assert.equal(preview.limited, true);
    assert.deepEqual(setup.org.seen.filter(item =>
      item.path.startsWith('/services/data/v62.0/query'))
      .map(item => decodeURIComponent(item.path)), [
      '/services/data/v62.0/query?q=SELECT Id FROM Test_Record__c ORDER BY Id LIMIT 2',
    ]);
  });

test('a targeted Catalog sync is never a complete Catalog', async t => {
  const setup = await installed(t, {extraObjects: ['Account']});
  const site = await setup.load();
  const full = await site.refreshCatalog({occurrence: 'full'});
  assert.equal(salesforceMoon.salesforceCatalogObservationIsComplete(
    full.observation), true);
  const targeted = await site.refreshCatalog({occurrence: 'targeted',
    resources: ['Test_Record__c']});
  assert.equal(JSON.parse(targeted.observationJson).truncated, true);
  assert.equal(salesforceMoon.salesforceCatalogObservationIsComplete(
    targeted.observation), false);
  await assert.rejects(site.refreshCatalog({occurrence: 'retained',
    resources: ['Test_Record__c'], retainResponses: true,
    maxRetainedBytes: 30000}), {code: 'InvalidSalesforceCatalogSync'});
});

test('default Catalog limits admit a full listing of provider-shaped entries',
  () => {
    // A listing entry as Salesforce returns it: flags plus URLs.
    const entry = index => {
      const name = `Generated_Object_${String(index).padStart(4, '0')}__c`;
      const base = `/services/data/v62.0/sobjects/${name}`;
      return {activateable: false, associateEntityType: null,
        associateParentEntity: null, createable: true, custom: true,
        customSetting: false, deepCloneable: false, deletable: true,
        deprecatedAndHidden: false, feedEnabled: false, hasSubtypes: false,
        isInterface: false, isSubtype: false, keyPrefix: 'a0X',
        label: `Generated Object ${index}`,
        labelPlural: `Generated Objects ${index}`, layoutable: true,
        mergeable: false, mruEnabled: true, name, queryable: true,
        replicateable: true, retrieveable: true, searchable: true,
        triggerable: true, undeletable: true, updateable: true,
        urls: {compactLayouts: `${base}/describe/compactLayouts`,
          rowTemplate: `${base}/{ID}`, approvalLayouts:
            `${base}/describe/approvalLayouts`, defaultValues:
            `${base}/defaultValues?recordTypeId&fields`, listviews:
            `${base}/listviews`, describe: `${base}/describe`,
          quickActions: `${base}/quickActions`, layouts:
            `${base}/describe/layouts`, sobject: base}};
    };
    const {list} = DEFAULT_SALESFORCE_CATALOG_LIMITS;
    const body = Buffer.from(JSON.stringify({encoding: 'UTF-8',
      maxBatchSize: 200, sobjects: Array.from({length: list.maxResources},
        (_, index) => entry(index))}));
    assert.ok(body.byteLength > 2_000_000);
    const listing = checked(salesforceMoon.salesforceProjectListing(body,
      list.maxBytes, list.maxNodes, list.maxDepth, list.maxResources,
      list.maxSelected, list.maxNameUnits));
    assert.equal(salesforceMoon.salesforceCatalogResourceNames(listing).length,
      list.maxSelected);
  });

test('installed Salesforce Site declares only its selected, typed Resources',
  async t => {
    const setup = await installed(t, {extraObjects: ['Account']});
    const site = await setup.load();
    const before = setup.org.seen.length;
    const declared = await site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']});
    // One describe of the selected Resource: no listing, no query.
    assert.deepEqual(setup.org.seen.slice(before).map(item =>
      decodeURIComponent(item.path)), [
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
    ]);
    assert.equal(site.ownsDeclaration(declared.declaration), true);
    assert.equal(site.ownsDeclaration({...declared.declaration}), false);
    assert.deepEqual(declared.views.map(view => [view.resource,
      view.source_ref, view.fields]), [['Test_Record__c',
      'connector://crm-main/Test_Record__c#records',
      ['Id', 'Name', 'External_Key__c']]]);
    const [writable] = declared.writables;
    assert.equal(writable.target_ref, 'connector://crm-main/Test_Record__c');
    assert.deepEqual(writable.create_fields, ['External_Key__c', 'Name']);
    assert.deepEqual(writable.upsert_keys, ['External_Key__c']);
    assert.deepEqual(writable.required_fields, ['External_Key__c', 'Name']);
    // The Catalog is the generator's canonical text; its CID is recomputed
    // here independently from the canonical bytes.
    const catalog = JSON.parse(declared.catalog);
    const {catalog_cid: catalogCid, ...unsealed} = catalog;
    assert.equal(catalogCid, declared.catalog_cid);
    assert.equal(canonicalJson(catalog), declared.catalog);
    assert.equal(`sha256:${createHash('sha256')
      .update(canonicalJson(unsealed)).digest('hex')}`, catalogCid);
    for (const view of catalog.source_views) {
      const {contract_cid: viewCid, ...body} = view;
      assert.equal(`sha256:${createHash('sha256')
        .update(canonicalJson(body)).digest('hex')}`, viewCid);
    }
    // Account exists but was not selected: it is outside the declaration,
    // not declared absent.
    assert.equal(declared.catalog.includes('Account'), false);
    // The same selection again is the same declaration.
    const again = await site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']});
    assert.equal(again.catalog_cid, declared.catalog_cid);
    await assert.rejects(site.declareCatalog({connectorId: 'crm main',
      resources: ['Test_Record__c']}), {code: 'MoonBitHostFailure'});
    await assert.rejects(site.declareCatalog({connectorId: 'crm-main',
      resources: []}), {code: 'InvalidSalesforceDeclaration'});
  });

test('a Program is checked against the Site\'s generated declaration',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const declared = await site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']});
    const {text, evidenceCid} = declarationEnvironment(declared);
    const environment = commonMoon.clientProgramCheckEnvironment(text,
      evidenceCid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const prepare = (resource, fields) =>
      commonMoon.clientProgramPrepareEffectFreeWithParameters(
        declaredReadProgram('crm-main', resource, fields), 'json',
        environment, undefined);
    const outcome = prepare('Test_Record__c', ['Id', 'Name']);
    assert.ok(commonMoon.clientProgramPreparationReady(outcome),
      String(commonMoon.clientProgramPreparationIssueCode(outcome)));
    // A field outside the declaration, and a Resource outside it, fail Check.
    for (const [resource, fields] of [['Test_Record__c', ['Id', 'Missing__c']],
      ['Account', ['Id']]]) {
      assert.equal(commonMoon.clientProgramPreparationReady(
        prepare(resource, fields)), undefined);
    }
  });

test('Catalog describe needs its own current read decision per Resource',
  async t => {
    const setup = await installed(t, {extraObjects: ['Account']});
    const site = await setup.load();
    const before = setup.org.seen.length;
    // Account has no read entry: the declaration is refused before any
    // provider call, including the permitted Resource's describe.
    await assert.rejects(site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c', 'Account']}),
    {code: 'SalesforceCatalogDescribeNotAuthorized', resource: 'Account'});
    assert.equal(setup.org.seen.length, before);
    // A Host restarted without the read entry cannot describe or preview.
    const revoked = await setup.load({entries: [
      accountEntry('records-read', 'deny', {
        connection: `salesforce:${setup.org.orgId}`,
        resource: 'Test_Record__c', operation: 'read'})]});
    await assert.rejects(revoked.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']}),
    {code: 'SalesforceCatalogDescribeNotAuthorized'});
    assert.equal(setup.org.seen.length, before);
  });

test('a metadata read decision never authorizes a record or query grant',
  async t => {
    const setup = await installed(t);
    const site = await setup.load({now: () => 1_000});
    await site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']});
    // The Site decided the describe under its own metadata subject. The
    // same subject asked by a caller is the gate's cached decision, which
    // authorizes a describe only.
    const read = {connection: site.connection, resource: 'Test_Record__c',
      operation: 'read'};
    const metadata = await site.authorization.authorize('acquisition', read, {
      subjectCid: `sha256:${createHash('sha256').update(JSON.stringify({
        version: 'actql-salesforce-catalog-describe/0.1',
        contextCid: site.context.contextCid, siteKey: 'salesforce-site',
        siteGeneration: 1, connectionRevision: 'connection-revision-a',
        resource: 'Test_Record__c', occurrence: 'declare-1000-0'}))
        .digest('hex')}`});
    assert.equal(metadata.action, 'dispatch');
    for (const operation of ['salesforce:query:read',
      'salesforce:record:observe']) {
      assert.throws(() => site.issueGrant({operation, decision: metadata,
        resource: 'Test_Record__c', runInvocationCid: cid('3'),
        dispatchRequestCid: cid('4')}),
      {code: 'SalesforceCredentialGrantNotAuthorized'});
    }
    // A data read decision under the caller's own subject still grants.
    const data = await site.authorization.authorize('acquisition', read,
      {subjectCid: cid('c')});
    assert.equal(site.issueGrant({operation: 'salesforce:query:read',
      decision: data, resource: 'Test_Record__c', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}).scope.operation,
    'salesforce:query:read');
  });

test('a published declaration restores without provider I/O and only for its Site',
  async t => {
    const setup = await installed(t);
    const site = await setup.load();
    const declared = await site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']});
    const published = JSON.parse(JSON.stringify({evidence: declared.evidence,
      observationCid: declared.observationCid,
      catalogCid: declared.catalog_cid}));
    // A restarted Host restores the same declaration from the retained
    // describe evidence: no credential, no provider call.
    const restarted = await setup.load({resolveSecret: async () => {
      throw new Error('secret must not be resolved');
    }});
    const before = setup.org.seen.length;
    const restored = restarted.restoreDeclaration({connectorId: 'crm-main',
      resources: ['Test_Record__c'], ...published});
    assert.equal(setup.org.seen.length, before);
    assert.equal(restored.catalog, declared.catalog);
    assert.equal(restarted.ownsDeclaration(restored.declaration), true);
    assert.equal(site.ownsDeclaration(restored.declaration), false);
    // Another connector id regenerates another Catalog: refused.
    assert.throws(() => restarted.restoreDeclaration({connectorId: 'crm-b',
      resources: ['Test_Record__c'], ...published}),
    {code: 'ForeignSalesforceDeclaration'});
    // Altered evidence cannot reproduce the published observation.
    const altered = structuredClone(published);
    altered.evidence.describeResponseSha256[0] = 'f'.repeat(64);
    assert.throws(() => restarted.restoreDeclaration({connectorId: 'crm-main',
      resources: ['Test_Record__c'], ...altered}));
    // A new Site generation or connection revision is another installation:
    // the old evidence is not carried over.
    for (const [key, value] of [['siteGeneration', 2],
      ['connectionRevision', 'connection-revision-b']]) {
      const path = join(setup.root, `site-${key}.json`);
      await writeFile(path, JSON.stringify({...setup.document,
        [key]: value}));
      const moved = await setup.load({path});
      assert.throws(() => moved.restoreDeclaration({connectorId: 'crm-main',
        resources: ['Test_Record__c'], ...published}),
      {code: 'ForeignSalesforceDeclaration'});
    }
  });

test('a Checkpoint read approval is admitted only for this installation',
  async t => {
    const {recordCheckpointApproval} = await import(
      '../../../host-common/checkpoint-approval.mjs');
    const setup = await installed(t);
    const site = await setup.load();
    const tuple = Object.freeze({connection: site.connection,
      resource: 'Test_Record__c', operation: 'read'});
    const binding = {version: 'actql-installed-salesforce-target/0.1',
      org_id: site.orgId, instance_origin: site.instanceOrigin,
      site_key: site.siteKey, site_generation: site.siteGeneration,
      connection_revision: site.connectionRevision, catalog_cid: cid('c'),
      resource: 'Test_Record__c', fields: ['Id', 'Name']};
    const approval = (facts = {}) => recordCheckpointApproval(Object.freeze({
      boundary: 'acquisition', action: 'dispatch', basis: 'resumed_approval',
      tuple, checkpointCid: cid('d')}), {checkpointCid: cid('d'),
      readTuple: tuple, physicalBinding: binding, principalId: 'principal-a',
      ...facts});
    const admitted = site.admitCheckpointReadApproval(approval());
    assert.equal(admitted.resource, 'Test_Record__c');
    // It grants exactly the query read of its Resource.
    const grant = operation => site.issueGrant({operation,
      decision: admitted, resource: 'Test_Record__c',
      runInvocationCid: cid('3'), dispatchRequestCid: cid('4'),
      subjectCid: cid('5')});
    assert.equal(grant('salesforce:query:read').scope.operation,
      'salesforce:query:read');
    for (const operation of ['salesforce:record:observe',
      'salesforce:record:update']) {
      assert.throws(() => grant(operation),
        {code: 'SalesforceCredentialGrantNotAuthorized'});
    }
    assert.throws(() => site.issueGrant({operation: 'salesforce:query:read',
      decision: admitted, resource: 'Account', runInvocationCid: cid('3'),
      dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
    // A hand-made decision, a copy, or another installation's approval is
    // never admitted.
    const forged = Object.freeze({boundary: 'acquisition', action: 'dispatch',
      basis: 'resumed_approval', tuple, checkpointCid: cid('d')});
    for (const decision of [forged, {...approval()},
      approval({principalId: 'principal-b'}),
      approval({physicalBinding: {...binding, site_generation: 2}}),
      approval({physicalBinding: {...binding,
        connection_revision: 'connection-revision-b'}}),
      approval({physicalBinding: {...binding, org_id: '00D000000000009EAA'}}),
      approval({physicalBinding: {...binding, resource: 'Account'}})]) {
      assert.throws(() => site.admitCheckpointReadApproval(decision),
        {code: 'SalesforceReadApprovalNotAdmitted'});
    }
    // A Site's own grant check never accepts a raw Checkpoint decision.
    assert.throws(() => site.issueGrant({operation: 'salesforce:query:read',
      decision: approval(), resource: 'Test_Record__c',
      runInvocationCid: cid('3'), dispatchRequestCid: cid('4')}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
  });

test('a closing Site refuses new operations until its journal is released',
  async t => {
    const setup = await installed(t, {entries: [
      accountEntry('records-write', 'allow', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'effect'})]});
    const journal = closeFailingJournal(1);
    const site = await setup.load({openCredentialJournal: journal.open});
    const decision = await site.authorization.authorize('effect_commit', {
      connection: site.connection, resource: 'Test_Record__c',
      operation: 'effect'}, {subjectCid: cid('6')});
    const seen = setup.org.seen.length;
    // The first release fails: the Site is closing but not released.
    assert.throws(() => site.close(), {code: 'InjectedJournalCloseFailure'});
    assert.equal(site.cleanupPending(), true);
    // No new operation starts, and nothing reaches the org.
    for (const operation of [
      () => site.issueGrant({operation: 'salesforce:record:update', decision,
        resource: 'Test_Record__c', runInvocationCid: cid('3'),
        dispatchRequestCid: cid('4'), subjectCid: cid('6')}),
      () => site.attestEffectCapability({operation: 'salesforce:record:update',
        runInvocationCid: cid('3'), dispatchRequestCid: cid('4')}),
    ]) {
      assert.throws(operation, {code: 'SalesforceSiteClosed'});
    }
    await assert.rejects(site.refreshCatalog(), {code: 'SalesforceSiteClosed'});
    await assert.rejects(site.declareCatalog({connectorId: 'crm-main',
      resources: ['Test_Record__c']}), {code: 'SalesforceSiteClosed'});
    assert.equal(setup.org.seen.length, seen);
    // The retry calls the journal's close again and releases the Site.
    site.close();
    assert.equal(journal.calls.close, 2);
    assert.equal(site.cleanupPending(), false);
    // A released Site does not close its journal again.
    site.close();
    assert.equal(journal.calls.close, 2);
  });

test('a real credential journal close retry releases the closing Site',
  async t => {
    const setup = await installed(t, {entries: [
      accountEntry('records-write', 'allow', {
        connection: 'salesforce:00D000000000001EAA',
        resource: 'Test_Record__c', operation: 'effect'})]});
    const site = await setup.load();
    const close = DatabaseSync.prototype.close;
    const failure = new Error('InjectedSqliteCloseFailure');
    let attempts = 0;
    DatabaseSync.prototype.close = function() {
      if (++attempts === 1) throw failure;
      return close.call(this);
    };
    try {
      assert.throws(() => site.close(), error => error === failure);
      assert.equal(site.cleanupPending(), true);
      assert.throws(() => site.attestEffectCapability({
        operation: 'salesforce:record:update', runInvocationCid: cid('3'),
        dispatchRequestCid: cid('4')}), {code: 'SalesforceSiteClosed'});
      site.close();
      assert.equal(site.cleanupPending(), false);
      site.close();
      assert.equal(attempts, 2);
    } finally {
      DatabaseSync.prototype.close = close;
    }
    const reopened = await setup.load();
    reopened.close();
  });

test('a failed Site owner keeps its primary failure and hands over the release',
  async t => {
    const setup = await installed(t);
    const journal = closeFailingJournal(2);
    const site = await setup.load({openCredentialJournal: journal.open});
    const primary = Object.assign(new Error('OwnerFailed'),
      {code: 'OwnerFailed'});
    const failure = retainSalesforceSiteCleanup(site, primary);
    // The owner's own failure stays the error; the release is pending.
    assert.equal(failure, primary);
    assert.equal(failure.cleanupPending, true);
    assert.deepEqual(failure.cleanupErrors.map(error => error.code),
      ['InjectedJournalCloseFailure']);
    assert.equal(journal.calls.close, 1);
    // A retry that fails again stays pending and keeps both failures.
    let status = await failure.cleanupHandle.retry();
    assert.equal(status.pending, true);
    assert.equal(status.errors.length, 2);
    assert.equal(journal.calls.close, 2);
    status = await failure.cleanupHandle.retry();
    assert.equal(status.pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal(journal.calls.close, 3);
    // A frozen failure is not modified: it is kept as the primary failure.
    const other = await setup.load({
      openCredentialJournal: closeFailingJournal(1).open});
    const frozen = Object.freeze(Object.assign(new Error('Frozen'),
      {code: 'FrozenFailure'}));
    const wrapped = retainSalesforceSiteCleanup(other, frozen);
    assert.equal(wrapped.primaryFailure, frozen);
    assert.equal(wrapped.code, 'FrozenFailure');
    assert.equal(wrapped.cleanupPending, true);
    assert.equal((await wrapped.cleanupHandle.retry()).pending, false);
  });

for (const closeFailures of [0, 1]) {
  test(`installed publication retains a frozen abort owner with ${closeFailures} journal close failures`,
    async t => {
      const setup = await installed(t);
      let pending = true;
      let retries = 0;
      const primary = Object.freeze(Object.assign(new Error('FrozenAbort'), {
        cleanupPending: true,
        cleanupHandle: Object.freeze({
          status: () => ({pending, errors: []}),
          async retry() { retries++; pending = false; },
        }),
      }));
      const close = DatabaseSync.prototype.close;
      let closes = 0;
      let secrets = 0;
      let failure;
      const seen = setup.org.seen.length;
      DatabaseSync.prototype.close = function() {
        if (++closes <= closeFailures) throw new Error('InjectedSqliteCloseFailure');
        return close.call(this);
      };
      try {
        await assert.rejects(publishInstalledSalesforceSource({
          version: INSTALLED_SALESFORCE_SOURCE_VERSION,
          accountConfigurationWire: configuration([
            accountEntry('records-read', 'allow', {
              connection: `salesforce:${setup.org.orgId}`,
              resource: 'Test_Record__c', operation: 'read'})]),
          connectorId: 'crm-main', resources: ['Test_Record__c'],
          publicationPath: join(setup.root, 'publication.json'),
          siteProfilePath: setup.path,
        }, {root: setup.root, principalId: 'principal-a', moon: commonMoon,
          providerMoon: salesforceMoon, runtimeBundleCid: cid('b'),
          resolveSecret: async () => { secrets++; throw new Error('UnexpectedSecretRead'); },
          signal: AbortSignal.abort(primary)}), error => {
          failure = error;
          assert.equal(error.primaryFailure, primary);
          assert.equal(error.cleanupPending, true);
          return true;
        });
        assert.equal(closes, 1);
        assert.equal(secrets, 0);
        assert.equal(setup.org.seen.length, seen);
        assert.equal((await failure.cleanupHandle.retry()).pending, false);
        assert.equal(pending, false);
        assert.equal(retries, 1);
        assert.equal(closes, closeFailures + 1);
      } finally {
        DatabaseSync.prototype.close = close;
        // Release the real journal even when a regression assertion fails.
        await failure?.cleanupHandle?.retry().catch(() => {});
      }
    });
}
