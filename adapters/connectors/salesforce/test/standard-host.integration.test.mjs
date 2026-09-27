// The standard installed Host reading a Salesforce source: an explicit
// publication, a Host start that restores it without provider I/O,
// discovery, Program Check, acquisition and computation through the public
// Client, and the Named Result read. The org is a local HTTPS mock.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {connect} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from
  '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../host/installed-salesforce-site.mjs';
import {INSTALLED_SALESFORCE_SOURCE_VERSION,
  publishInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'salesforce-standard-host');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'host.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'host.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));

const owner = userInfo().username;
const cid = digit => `sha256:${digit.repeat(64)}`;
const runtimeBundleCid = `sha256:${createHash('sha256').update(
  await readFile(new URL(
    '../../../../_build/js/release/build/connectors_builtin_node/' +
    'connectors_builtin_node.js', import.meta.url))).digest('hex')}`;
const secret = async () => 'test-only-secret';
const accountConfiguration = (orgId, readable) => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-source-account',
  entries: [{entry_id: 'records-read', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection: {any_of: [`salesforce:${orgId}`]},
    resource: {any_of: [...readable].sort()}, operation: {any_of: ['read']}}],
});
// The Program reads the declared records view (the compiler's scan, filter,
// select acquisition chain; the filter runs locally) and computes from it.
const program = JSON.stringify({version: 'actql/0.1', id: 'salesforce-read',
  stages: [
    {id: 'acquire',
      inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
      steps: [{filter: "Name <> 'record-2'", as: 'filtered'},
        {select: ['Id', 'Name', 'External_Key__c'], as: 'captured'}],
      results: {r: {from: 'captured',
        fields: ['Id', 'Name', 'External_Key__c']}}},
    {id: 'compute',
      inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
      steps: [{select: ['External_Key__c', 'Name'], as: 'out'}],
      results: {r: {from: 'out', fields: ['External_Key__c', 'Name']}}},
  ],
  results: {records: {from: {stage: 'compute', result: 'r'}}}});

async function installation(t, {readable = ['Test_Record__c']} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const root = await mkdtemp(join(scratch, 'host-'));
  // Hosts close before their directory is removed.
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const siteDocument = {
    version: INSTALLED_SALESFORCE_SITE_VERSION, apiVersion: 'v62.0',
    cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'credential-journal'), orgId: org.orgId,
    siteGeneration: 1, siteKey: 'salesforce-site', tenant: 'tenant-a',
    caPath: join(root, 'org-ca.crt')};
  const sitePath = join(root, 'salesforce-site.json');
  await writeFile(sitePath, JSON.stringify(siteDocument));
  const profile = {version: INSTALLED_SALESFORCE_SOURCE_VERSION,
    siteProfilePath: sitePath,
    publicationPath: join(root, 'salesforce-publication.json'),
    connectorId: 'crm-main', resources: ['Test_Record__c'],
    accountConfigurationWire: accountConfiguration(org.orgId, readable)};
  const profilePath = join(root, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify(profile));
  const hostRoot = join(root, 'state');
  const publish = () => publishInstalledSalesforceSource(profile, {
    root: hostRoot, principalId: owner, moon: commonMoon, salesforceMoon,
    runtimeBundleCid, resolveSecret: secret});
  const open = async ({authenticate = () => owner} = {}) => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate, sourceProfilePath: profilePath,
      resolveSourceSecret: secret});
    const server = createServer({key: tlsKey, cert: tlsCertificate},
      host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    let closed = false;
    const close = async () => {
      if (closed) return;
      closed = true;
      server.closeAllConnections?.();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    };
    closers.push(close);
    const client = await connect({mode: 'remote',
      endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'owner-token', durability: 'durable'});
    closers.push(() => client.close());
    return {client, close};
  };
  const queries = () => org.seen.filter(item =>
    item.path.startsWith('/services/data/v62.0/query'));
  return {org, root, profile, profilePath, sitePath, siteDocument, publish,
    open, queries, connection: `salesforce:${org.orgId}`};
}

test('public Client reads a published Salesforce source to a Named Result',
  async t => {
    const setup = await installation(t);
    const start = setup.org.seen.length;
    // A Host start without a publication refuses before any provider I/O.
    await assert.rejects(setup.open(), {code: 'SalesforcePublicationMissing'});
    assert.equal(setup.org.seen.length, start);
    await setup.publish();
    const published = setup.org.seen.length;
    const {client} = await setup.open();
    // The Host start restored the publication without provider I/O.
    assert.equal(setup.org.seen.length, published);
    const listing = await client.resources(setup.connection);
    assert.deepEqual(listing.resources, [
      {name: 'Test_Record__c', outcome: 'described'}]);
    assert.equal(listing.snapshotComplete, false);
    assert.equal((await client.inspectResource(setup.connection,
      'Test_Record__c')).status, 'ready');
    // Check used only the published Catalog.
    assert.equal(setup.org.seen.length, published);
    const execution = await client.aql(program, {format: 'json',
      requestId: 'salesforce-read-1'});
    const state = await execution.wait();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const rows = await execution.result('records').all();
    // Independently expected from the org's stored records.
    assert.deepEqual(rows.map(row => [row.External_Key__c, row.Name]).sort(),
      [['key-1', 'record-1'], ['key-3', 'record-3']]);
    // Acquisition described the Resource (plan and recheck) and ran one
    // query; nothing was listed.
    const paths = setup.org.seen.slice(published).map(item =>
      decodeURIComponent(item.path).split('?')[0]);
    assert.deepEqual(paths, [
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/sobjects/Test_Record__c/describe',
      '/services/data/v62.0/query',
    ]);
    assert.equal(paths.includes('/services/data/v62.0/sobjects/'), false);
  });

test('a Program outside the published declaration fails Check without I/O',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    const {client} = await setup.open();
    const before = setup.org.seen.length;
    const undeclared = program.replace('"External_Key__c", "Name"]',
      '"External_Key__c", "Missing__c"]')
      .replaceAll('External_Key__c', 'Missing__c');
    await assert.rejects(client.aql(undeclared, {format: 'json',
      requestId: 'undeclared-1'}));
    assert.equal(setup.org.seen.length, before);
  });

test('a lost read permission acquires nothing and discloses nothing',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    // The same installation restarted with no read on this org.
    await writeFile(setup.profilePath, JSON.stringify({...setup.profile,
      accountConfigurationWire: accountConfiguration(setup.org.orgId,
        ['Other_Object__c'])}));
    const {client} = await setup.open();
    const before = setup.org.seen.length;
    assert.deepEqual((await client.resources(setup.connection)).resources,
      []);
    await assert.rejects(client.inspectResource(setup.connection,
      'Test_Record__c'), {code: 'ResourceDiscoveryDenied'});
    // The read is refused at submit: no Run, no provider request.
    await assert.rejects(client.aql(program, {format: 'json',
      requestId: 'revoked-1'}), error =>
      /^ACTQL_E_ACCOUNT_/u.test(error.code));
    assert.deepEqual(await client.lookupRequest('revoked-1'),
      {kind: 'not_found'});
    assert.equal(setup.org.seen.length, before);
    assert.equal(setup.queries().length, 0);
  });

test('a publication of another connection or Site generation is refused',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    for (const change of [{siteGeneration: 2},
      {connectionRevision: 'connection-revision-b'},
      {orgId: '00D000000000009EAA'}]) {
      await writeFile(setup.sitePath, JSON.stringify({...setup.siteDocument,
        ...change}));
      await assert.rejects(setup.open(),
        {code: 'ForeignSalesforceDeclaration'}, JSON.stringify(change));
    }
    // An altered publication is refused as well.
    await writeFile(setup.sitePath, JSON.stringify(setup.siteDocument));
    const body = JSON.parse(await readFile(setup.profile.publicationPath,
      'utf8'));
    body.evidence.describeResponseSha256[0] = 'f'.repeat(64);
    await writeFile(setup.profile.publicationPath, JSON.stringify(body));
    await assert.rejects(setup.open());
    assert.equal(setup.queries().length, 0);
  });
