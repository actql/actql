import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {createClientHttpHandler} from '../../../host-node/client-http.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {connect} from '../../../../packages/sdk/index.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION, installSalesforceAuthorization,
  loadInstalledSalesforceSite} from '../host/installed-salesforce-site.mjs';
import {installSalesforceResourceService} from
  '../host/salesforce-resource-service.mjs';
import {loadSalesforceGeneration, publishSalesforceGeneration} from
  '../host/salesforce-publication.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

// A public Client Host serving discovery for one installed local org. The
// account configuration allows reading Test_Record__c only.
async function discoveryHost(t) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-discovery-'));
  const sites = [];
  const servers = [];
  t.after(async () => {
    for (const server of servers) {
      await new Promise(resolve => server.close(resolve));
    }
    for (const site of sites) site.close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const profilePath = join(root, 'salesforce-site.json');
  const profile = {
    version: INSTALLED_SALESFORCE_SITE_VERSION, apiVersion: 'v62.0',
    cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-authority', credentialKeyId: 'host-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'journal'), orgId: org.orgId, siteGeneration: 1,
    siteKey: 'salesforce-site', tenant: 'tenant-a',
    caPath: join(root, 'org-ca.crt')};
  const accountConfiguration = readable => canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'discovery-account',
    entries: [{entry_id: 'records-read', outcome: 'allow', exclusions: [],
      principal: {all: true},
      connection: {any_of: [`salesforce:${org.orgId}`]},
      resource: {any_of: [...readable].sort()},
      operation: {any_of: ['read']}}]});
  // Each open plays one Host process with the profile and account
  // configuration as installed then.
  const generationPath = join(root, 'generation.json');
  const targets = ['Test_Record__c', 'Missing__c'];
  const open = async ({changes = {}, principalId = 'owner-principal',
    readable = ['Test_Record__c', 'Missing__c', 'Contact']} = {}) => {
    await writeFile(profilePath, JSON.stringify({...profile, ...changes}));
    const authorization = await installSalesforceAuthorization({
      accountConfiguration: accountConfiguration(readable), principalId,
      root});
    const site = await loadInstalledSalesforceSite(profilePath, {commonMoon,
      salesforceMoon, authorization, runtimeBundleCid: cid('b'),
      resolveSecret: async () => 'test-only-secret'});
    sites.push(site);
    const service = installSalesforceResourceService({salesforceMoon,
      sites: [site]});
    const server = createServer(createClientHttpHandler({
      authenticate: header => ({'Bearer owner-token': 'owner-principal',
        'Bearer other-token': 'other-principal'})[header],
      authorizeConnection: facts => facts.connection.mode === 'local' &&
        facts.connection.owner === 'local',
      negotiate: ({principalId}) => ({
        version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: principalId,
        capabilities: ['result-jsonl'],
        limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
          maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
          maxRows: 100, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
      }),
      resources: service.resources,
      inspectResource: service.inspectResource,
      peekResource: service.peekResource,
    }));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    servers.push(server);
    const client = token => connect({mode: 'local', owner: 'local',
      endpoint: `http://127.0.0.1:${server.address().port}/`, token});
    // The explicit publication step, and a Host start from it.
    const publish = async () => {
      const published = await publishSalesforceGeneration({site,
        path: generationPath, connectorId: 'crm-main', resources: targets});
      service.installPublished(site.connection, published.declared);
      return published;
    };
    const load = async () => {
      const loaded = await loadSalesforceGeneration({site,
        path: generationPath, connectorId: 'crm-main', resources: targets});
      service.installPublished(site.connection, loaded.declared);
      return loaded;
    };
    return {site, service, client, publish, load};
  };
  return {org, open, generationPath, connection: `salesforce:${org.orgId}`};
}

test('public Client discovers, inspects and previews a published org',
  async t => {
    const host = await discoveryHost(t);
    const {client: connectAs, publish} = await host.open();
    const client = await connectAs('owner-token');
    t.after(() => client.close());
    // Nothing is published yet: discovery does not sync the org itself.
    const before = host.org.seen.length;
    await assert.rejects(client.resources(host.connection),
      {code: 'ResourceCatalogUnavailable'});
    assert.equal(host.org.seen.length, before);
    const published = await publish();
    // The publication described exactly its targets: no listing.
    assert.deepEqual(host.org.seen.slice(before).map(item => item.path), [
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/sobjects/Missing__c/describe']);
    const listing = await client.resources(host.connection);
    assert.equal(listing.observationCid, published.declared.observationCid);
    assert.deepEqual(listing.resources, [
      {name: 'Test_Record__c', outcome: 'described'},
      {name: 'Missing__c', outcome: 'not_found'}]);
    assert.equal(listing.snapshotComplete, false);
    assert.equal(listing.resultTruncated, false);
    const inspected = await client.inspectResource(host.connection,
      'Test_Record__c');
    assert.equal(inspected.status, 'ready');
    assert.deepEqual(inspected.summary.fields.map(field => field.name).sort(),
      ['External_Key__c', 'Id', 'Name']);
    // A published name the org did not find (listed as `not_found`) and a
    // readable Resource the publication did not target (not listed,
    // unobserved) are different answers; neither is declared absent.
    assert.equal((await client.inspectResource(host.connection,
      'Missing__c')).reason, 'describe_unavailable');
    assert.equal((await client.inspectResource(host.connection,
      'Contact')).reason, 'listing_truncated');
    const describes = host.org.seen.length;
    const preview = await client.peekResource(host.connection,
      'Test_Record__c', {fields: ['Id', 'Name'], maxRows: 2});
    assert.deepEqual(preview.rows, [
      {Id: 'a00000000000001', Name: 'record-1'},
      {Id: 'a00000000000002', Name: 'record-2'},
    ]);
    assert.equal(preview.limited, true);
    // Listing and inspection read nothing; the preview described its
    // Resource twice (plan and recheck) and queried once.
    assert.deepEqual(host.org.seen.slice(describes).map(item =>
      item.path.split('?')[0]), [
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/query']);
    // Another principal, an unknown connection and an unconfigured
    // Resource are refused before any provider request.
    const requests = host.org.seen.length;
    const other = await connectAs('other-token');
    t.after(() => other.close());
    await assert.rejects(other.resources(host.connection),
      {code: 'ResourceDiscoveryDenied'});
    await assert.rejects(client.resources('salesforce:00D000000000009EAA'),
      {code: 'ResourceConnectionNotFound'});
    await assert.rejects(client.peekResource(host.connection, 'Account',
      {fields: ['Id']}), {code: 'ResourcePeekDenied'});
    await assert.rejects(client.inspectResource(host.connection, 'Account'),
      {code: 'ResourceDiscoveryDenied'});
    assert.equal(host.org.seen.length, requests);
  });

test('a restarted Host restores discovery from the published generation',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    const published = await first.publish();
    first.site.close();
    const second = await host.open();
    const requests = host.org.seen.length;
    const loaded = await second.load();
    assert.equal(loaded.generationCid, published.generationCid);
    assert.deepEqual(loaded.resourceStates, [
      {name: 'Test_Record__c', state: 'described'},
      {name: 'Missing__c', state: 'not_found'}]);
    const client = await second.client('owner-token');
    t.after(() => client.close());
    const listing = await client.resources(host.connection);
    assert.equal(listing.observationCid, published.declared.observationCid);
    assert.equal((await client.inspectResource(host.connection,
      'Test_Record__c')).status, 'ready');
    // Restoring and answering from the generation used no provider request.
    assert.equal(host.org.seen.length, requests);
    // A declaration of another Site is never installed.
    assert.throws(() => second.service.installPublished(host.connection,
      published.declared), {code: 'ForeignSalesforceDeclaration'});
    assert.equal((await client.resources(host.connection)).observationCid,
      published.declared.observationCid);
  });

test('a generation of another Site installation never becomes current discovery',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    await first.publish();
    first.site.close();
    for (const [name, options] of [
      ['tenant', {changes: {tenant: 'tenant-other'}}],
      ['environment', {changes: {environment: 'staging'}}],
      ['Site key', {changes: {siteKey: 'other-site'}}],
      ['Site generation', {changes: {siteGeneration: 99}}],
      ['connection revision', {changes: {
        connectionRevision: 'connection-revision-b'}}],
      ['origin', {changes: {instanceOrigin: 'https://127.0.0.1:1'}}],
      ['principal', {principalId: 'other-principal'}],
      ['org', {changes: {orgId: '00D000000000009EAA'}}],
    ]) {
      const reopened = await host.open(options);
      const requests = host.org.seen.length;
      await assert.rejects(reopened.load(),
        {code: 'ForeignSalesforceDeclaration'}, name);
      assert.equal(host.org.seen.length, requests, name);
      reopened.site.close();
    }
  });

test('discovery refuses another principal before any Catalog request',
  async t => {
    const host = await discoveryHost(t);
    const {client: connectAs, publish} = await host.open();
    await publish();
    const before = host.org.seen.length;
    const other = await connectAs('other-token');
    t.after(() => other.close());
    await assert.rejects(other.resources(host.connection),
      {code: 'ResourceDiscoveryDenied'});
    await assert.rejects(other.inspectResource(host.connection,
      'Test_Record__c'), {code: 'ResourceDiscoveryDenied'});
    const owner = await connectAs('owner-token');
    t.after(() => owner.close());
    await assert.rejects(owner.resources('salesforce:00D000000000009EAA'),
      {code: 'ResourceConnectionNotFound'});
    // No describe or query reached the org.
    assert.equal(host.org.seen.length, before);
  });

test('a restored generation is disclosed only under current read authority',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    await first.publish();
    first.site.close();
    // The same installation, now configured to read nothing on this org.
    const revoked = await host.open({readable: ['Other_Object__c']});
    const requests = host.org.seen.length;
    await revoked.load();
    const client = await revoked.client('owner-token');
    t.after(() => client.close());
    // The generation is bound to this Site, but binding is not permission:
    // the Resources it described are no longer disclosed or described.
    assert.deepEqual((await client.resources(host.connection)).resources, []);
    await assert.rejects(client.inspectResource(host.connection,
      'Test_Record__c'), {code: 'ResourceDiscoveryDenied'});
    await assert.rejects(client.peekResource(host.connection,
      'Test_Record__c', {fields: ['Id']}), {code: 'ResourcePeekDenied'});
    await assert.rejects(publishSalesforceGeneration({site: revoked.site,
      path: host.generationPath, connectorId: 'crm-main',
      resources: ['Test_Record__c']}),
    {code: 'SalesforceCatalogDescribeNotAuthorized'});
    assert.equal(host.org.seen.length, requests);
  });

test('a published generation is replaced whole and checked against its targets',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    await first.publish();
    const {readFile: read, writeFile: write} = await import(
      'node:fs/promises');
    const body = await read(host.generationPath, 'utf8');
    // Another target set or connector id is another publication.
    await assert.rejects(loadSalesforceGeneration({site: first.site,
      path: host.generationPath, connectorId: 'crm-main',
      resources: ['Test_Record__c']}),
    {code: 'SalesforcePublicationTargetMismatch'});
    await assert.rejects(loadSalesforceGeneration({site: first.site,
      path: host.generationPath, connectorId: 'crm-other',
      resources: ['Test_Record__c', 'Missing__c']}),
    {code: 'SalesforcePublicationTargetMismatch'});
    // Reformatted or edited text is not the published generation.
    await write(host.generationPath, JSON.stringify(JSON.parse(body),
      null, 2));
    await assert.rejects(first.load(), {code: 'InvalidSalesforcePublication'});
    const edited = JSON.parse(body);
    edited.catalog_cid = cid('7');
    await write(host.generationPath, JSON.stringify(edited));
    await assert.rejects(first.load(), {code: 'ForeignSalesforceDeclaration'});
    await write(host.generationPath, body);
    await first.load();
    const {rm: remove} = await import('node:fs/promises');
    await remove(host.generationPath);
    await assert.rejects(first.load(), {code: 'SalesforcePublicationMissing'});
  });
