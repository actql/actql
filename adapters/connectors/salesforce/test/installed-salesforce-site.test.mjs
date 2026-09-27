import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {accountEntry} from '../../../host-node/authorization-fixture.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {DEFAULT_SALESFORCE_CATALOG_LIMITS, INSTALLED_SALESFORCE_SITE_VERSION,
  installSalesforceAuthorization, loadInstalledSalesforceSite} from
  '../host/installed-salesforce-site.mjs';
import {openSalesforceEffectSiteFixture} from
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
  extraObjects, idSortable, storedOrder} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    extraObjects, idSortable, storedOrder});
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
    // Two syncs (plan and recheck) each list once and describe only the
    // previewed Resource, then one query; no other object is described.
    assert.deepEqual(setup.org.seen.slice(before).map(item =>
      decodeURIComponent(item.path)), [
      '/services/data/v62.0/sobjects/',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/sobjects/',
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
    // One list and one describe of the selected Resource, no query.
    assert.deepEqual(setup.org.seen.slice(before).map(item =>
      decodeURIComponent(item.path)), [
      '/services/data/v62.0/sobjects/',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
    ]);
    assert.equal(site.ownsDeclaration(declared.declaration), true);
    assert.equal(site.ownsDeclaration({...declared.declaration}), false);
    assert.deepEqual(declared.views.map(view => [view.resource,
      view.source_ref, view.fields]), [['Test_Record__c',
      'connector://crm-main/Test_Record__c#records',
      ['Id', 'Name', 'External_Key__c']]]);
    const [mapping] = declared.mappings;
    assert.equal(mapping.target_ref, 'connector://crm-main/Test_Record__c');
    assert.deepEqual(mapping.create_fields, ['External_Key__c', 'Name']);
    assert.deepEqual(mapping.upsert_keys, ['External_Key__c']);
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
    // Account was listed but not selected: it is outside the declaration,
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
