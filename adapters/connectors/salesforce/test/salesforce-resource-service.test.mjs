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
  const accountConfiguration = canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'discovery-account',
    entries: [{entry_id: 'records-read', outcome: 'allow', exclusions: [],
      principal: {all: true},
      connection: {any_of: [`salesforce:${org.orgId}`]},
      resource: {any_of: ['Test_Record__c']},
      operation: {any_of: ['read']}}]});
  // Each open plays one Host process with the profile as installed then.
  const open = async ({changes = {}, principalId = 'owner-principal'} = {}) => {
    await writeFile(profilePath, JSON.stringify({...profile, ...changes}));
    const authorization = await installSalesforceAuthorization({
      accountConfiguration, principalId, root});
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
    return {site, service, client};
  };
  return {org, open, connection: `salesforce:${org.orgId}`};
}

test('public Client discovers, inspects and previews an installed org',
  async t => {
    const host = await discoveryHost(t);
    const {service, client: connectAs} = await host.open();
    const client = await connectAs('owner-token');
    t.after(() => client.close());
    const listing = await client.resources(host.connection);
    assert.deepEqual(listing.resources, [
      {name: 'Test_Record__c', outcome: 'described'}]);
    assert.equal(listing.snapshotComplete, true);
    assert.equal(listing.resultTruncated, false);
    assert.deepEqual((await client.resources(host.connection,
      {query: 'account'})).resources, []);
    const inspected = await client.inspectResource(host.connection,
      'Test_Record__c');
    assert.equal(inspected.status, 'ready');
    assert.deepEqual(inspected.summary.fields.map(field => field.name).sort(),
      ['External_Key__c', 'Id', 'Name']);
    const preview = await client.peekResource(host.connection,
      'Test_Record__c', {fields: ['Id', 'Name'], maxRows: 2});
    assert.deepEqual(preview.rows, [
      {Id: 'a00000000000001', Name: 'record-1'},
      {Id: 'a00000000000002', Name: 'record-2'},
    ]);
    assert.equal(preview.limited, true);
    // Listing and inspection read no rows; only the preview queried once.
    assert.equal(host.org.seen.filter(item =>
      item.path.startsWith('/services/data/v62.0/query')).length, 1);
    // Another principal, an unknown connection and an unconfigured
    // Resource are refused before any provider query.
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
    assert.equal(host.org.seen.filter(item =>
      item.path.startsWith('/services/data/v62.0/query')).length, 1);
    assert.equal(typeof service.refresh, 'function');
  });

test('a restarted Host restores discovery from the retained snapshot',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    const snapshot = await first.service.refresh(host.connection);
    assert.ok(snapshot.retained);
    first.site.close();
    const second = await host.open();
    const requests = host.org.seen.length;
    assert.equal(second.service.restore(host.connection, snapshot),
      snapshot.observationCid);
    const client = await second.client('owner-token');
    t.after(() => client.close());
    const listing = await client.resources(host.connection);
    assert.equal(listing.observationCid, snapshot.observationCid);
    assert.deepEqual(listing.resources.map(item => item.name),
      ['Test_Record__c']);
    assert.equal((await client.inspectResource(host.connection,
      'Test_Record__c')).status, 'ready');
    // Restoring and answering from the snapshot used no provider request.
    assert.equal(host.org.seen.length, requests);
    // A foreign restore is refused and the current view stays.
    assert.throws(() => second.service.restore(host.connection, {
      ...snapshot, observationCid: cid('9')}),
    {code: 'ForeignRetainedSalesforceCatalog'});
    assert.equal((await client.resources(host.connection)).observationCid,
      snapshot.observationCid);
  });

test('a snapshot of another Site installation never becomes current discovery',
  async t => {
    const host = await discoveryHost(t);
    const first = await host.open();
    const snapshot = await first.service.refresh(host.connection);
    first.site.close();
    for (const [name, options, field] of [
      ['tenant', {changes: {tenant: 'tenant-other'}}, 'tenant'],
      ['environment', {changes: {environment: 'staging'}}, 'environment'],
      ['Site key', {changes: {siteKey: 'other-site'}}, 'site_key'],
      ['Site generation', {changes: {siteGeneration: 99}}, 'site_generation'],
      ['connection revision', {changes: {
        connectionRevision: 'connection-revision-b'}}, 'connection_revision'],
      ['origin', {changes: {instanceOrigin: 'https://127.0.0.1:1'}},
        'resource_origin'],
      ['principal', {principalId: 'other-principal'}, 'principal'],
    ]) {
      const reopened = await host.open(options);
      const requests = host.org.seen.length;
      assert.throws(() => reopened.service.restore(host.connection, snapshot),
        error => error.code === 'ResourceCatalogBindingMismatch' &&
          error.fields.includes(field), name);
      assert.equal(host.org.seen.length, requests, name);
      reopened.site.close();
    }
    // A different org is another connection: nothing to restore into.
    const otherOrg = await host.open({changes: {orgId: '00D000000000009EAA'}});
    assert.throws(() => otherOrg.service.restore(host.connection, snapshot),
      {code: 'ResourceConnectionNotFound'});
    otherOrg.site.close();
    // A snapshot another generation observed is refused by the current
    // installation, which keeps answering from its own observation.
    const changed = await host.open({changes: {siteGeneration: 99}});
    const foreign = await changed.service.refresh(host.connection);
    changed.site.close();
    const same = await host.open();
    assert.equal(same.service.restore(host.connection, snapshot),
      snapshot.observationCid);
    const client = await same.client('owner-token');
    t.after(() => client.close());
    const requests = host.org.seen.length;
    assert.throws(() => same.service.restore(host.connection, foreign),
      error => error.code === 'ResourceCatalogBindingMismatch' &&
        error.fields.includes('site_generation'));
    assert.equal((await client.resources(host.connection)).observationCid,
      snapshot.observationCid);
    // A snapshot whose bytes do not reproduce the named observation is
    // refused before any binding check, and the current view still stays.
    assert.throws(() => same.service.restore(host.connection, {
      ...snapshot, observationCid: cid('9')}),
    {code: 'ForeignRetainedSalesforceCatalog'});
    assert.equal((await client.resources(host.connection)).observationCid,
      snapshot.observationCid);
    assert.equal(host.org.seen.length, requests);
  });
