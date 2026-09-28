// The standard installed Host reading a Salesforce source: an explicit
// publication, a Host start that restores it without provider I/O,
// discovery, Program Check, acquisition and computation through the public
// Client, and the Named Result read. The org is a local HTTPS mock.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
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
import {connect, RequestHeld} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from
  '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../host/installed-salesforce-site.mjs';
import {INSTALLED_SALESFORCE_SOURCE_VERSION,
  publishInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';
import {effectProgram} from './installed-salesforce-effect.fixture.mjs';

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
// Checkpoint review for Hosts installed with Run-acceptance protection.
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal']]);
const checkpointAuthorization = extra => ({
  accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'host-account', entries: [{entry_id: 'host-run',
      outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['write']},
      exclusions: []}]}),
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}],
  reviewReaders: [],
  hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
  leaseMs: 10_000, ...extra});
const accountConfiguration = (orgId, readable, outcome = 'allow') =>
  canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-source-account',
  entries: [{entry_id: 'records-read', outcome, exclusions: [],
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

async function installation(t, {readable = ['Test_Record__c'],
  sourceResources = ['Test_Record__c'], extraObjects = [],
  queryFailureStatus, storedRecords, temporalFields = false} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    queryFailureStatus, storedRecords, extraObjects, temporalFields,
    optionalText: storedRecords !== undefined});
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
    connectorId: 'crm-main', resources: sourceResources,
    accountConfigurationWire: accountConfiguration(org.orgId, readable)};
  const profilePath = join(root, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify(profile));
  const hostRoot = join(root, 'state');
  const publish = () => publishInstalledSalesforceSource(profile, {
    root: hostRoot, principalId: owner, moon: commonMoon, salesforceMoon,
    runtimeBundleCid, resolveSecret: secret});
  const open = async ({authenticate = header =>
    tokens.get(header?.replace(/^Bearer /u, '')), authorization} = {}) => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate, sourceProfilePath: profilePath, authorization,
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
    const as = async token => {
      const connected = await connect({mode: 'remote',
        endpoint: `https://127.0.0.1:${server.address().port}/`,
        token, durability: 'durable'});
      closers.push(() => connected.close());
      return connected;
    };
    return {client: await as('owner-token'), as, close};
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

test('public HTTP Client resumes an installed Salesforce Effect after restart',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    const effectPath = join(setup.root, 'effect-profile.json');
    const hostAccountWire = canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'salesforce-effect-host', entries: [
        {entry_id: 'effect-commit', outcome: 'delegate', exclusions: [],
          principal: {all: true},
          connection: {any_of: [`salesforce:${setup.org.orgId}`]},
          resource: {any_of: ['Test_Record__c']},
          operation: {any_of: ['effect']}},
        {entry_id: 'host-run', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {all: true},
          resource: {all: true}, operation: {any_of: ['write']}},
        {entry_id: 'target-read', outcome: 'allow', exclusions: [],
          principal: {all: true},
          connection: {any_of: [`salesforce:${setup.org.orgId}`]},
          resource: {any_of: ['Test_Record__c']},
          operation: {any_of: ['read']}},
      ]});
    await writeFile(effectPath, JSON.stringify({
      version: 'actql-installed-salesforce-effect/0.1',
      siteProfilePath: setup.sitePath,
      publicationPath: join(setup.root, 'effect-publication.json'),
      connectorId: 'crm-main',
      accountConfigurationWire: hostAccountWire,
      writes: [{resource: 'Test_Record__c', kind: 'update',
        fields: ['Name']}],
    }));
    const published = await publishInstalledEffect({effectProfilePath:
      effectPath, directory: join(setup.root, 'state'),
    resolveEffectSecret: secret});
    const beforeStart = setup.org.seen.length;
    const diagnostics = [];
    const authorization = checkpointAuthorization({
      resumeAfterAnswer: false,
      observe: (name, detail) => diagnostics.push({name, detail}),
      accountConfiguration: hostAccountWire,
      reviewReaders: ['reviewer-principal'],
    });
    const openEffect = async () => {
      const host = await openInstalledRemoteHttpHost({
        directory: join(setup.root, 'state'),
        authenticate: header => tokens.get(
          header?.replace(/^Bearer /u, '')),
        sourceProfilePath: setup.profilePath,
        resolveSourceSecret: secret,
        effectProfilePath: effectPath, resolveEffectSecret: secret,
        authorization,
      });
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
      t.after(close);
      const endpoint = `https://127.0.0.1:${server.address().port}/`;
      const as = token => connect({mode: 'remote', endpoint, token,
        durability: 'durable'});
      return {as, close};
    };
    const first = await openEffect();
    assert.equal(setup.org.seen.length, beforeStart,
      'generation restoration performs no provider request');
    const ownerClient = await first.as('owner-token');
    const read = await ownerClient.aql(program, {format: 'json',
      requestId: 'coinstalled-salesforce-read'});
    assert.equal((await read.wait()).status, 'succeeded');
    assert.deepEqual((await read.result('records').all()).map(row =>
      [row.External_Key__c, row.Name]).sort(),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
    const mapping = published.mappings[0];
    const unsupported = JSON.parse(program);
    unsupported.id = 'unsupported-acquire-and-effect';
    unsupported.stages[1].effects = {save: {update: {
      target: 'connector://crm-main/Test_Record__c',
      mapping: mapping.mappingRef, from: {result: 'r'},
      id: 'External_Key__c', set: {Name: {field: 'Name'}},
    }}};
    const beforeUnsupported = setup.org.seen.length;
    await assert.rejects(ownerClient.aql(JSON.stringify(unsupported), {
      format: 'json', requestId: 'unsupported-acquire-and-effect'}),
    {code: 'ClientProgramUnsupported'});
    assert.deepEqual(await ownerClient.lookupRequest(
      'unsupported-acquire-and-effect'), {kind: 'not_found'});
    assert.equal(setup.org.seen.length, beforeUnsupported);
    const effectDocument = effectProgram({save: {update: {
      target: `connector://crm-main/Test_Record__c`,
      mapping: mapping.mappingRef, from: {result: 'rows'}, id: 'id',
      set: {Name: {field: 'id'}}}}},
    [{id: 'a00000000000001'}, {id: 'a00000000000002'}]);
    const execution = await ownerClient.aql(JSON.stringify(effectDocument), {
      format: 'json', requestId: 'installed-effect-http'});
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint');
    assert.equal(setup.org.seen.filter(item => item.method === 'PATCH').length,
      0);
    await first.close();
    const second = await openEffect();
    const reviewer = await second.as('reviewer-token');
    const [checkpoint] = (await reviewer.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    const answer = await reviewer.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer: {...signer,
        authorityScopeCid: execution.ref.authorityScopeCid}});
    assert.deepEqual(answer.results.map(item => item.status), ['committed']);
    await second.close();
    const third = await openEffect();
    const resumed = await (await third.as('owner-token')).attach(execution.ref);
    let lastState;
    const state = await waitFor(async () => {
      const current = await resumed.status();
      lastState = current;
      const failure = diagnostics.find(item =>
        item.name === 'effect_resume_failed');
      if (failure !== undefined) {
        throw new Error(`EffectResumeFailed:${JSON.stringify(failure)}`);
      }
      return current.status === 'succeeded' ? current : undefined;
    }).catch(error => {
      error.message = JSON.stringify({state: lastState,
        writes: setup.org.seen.filter(item => item.method === 'PATCH'),
        observed: setup.org.seen.map(item => [item.method, item.path]),
        diagnostics});
      throw error;
    });
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await resumed.result('answer').all(),
      [{id: 'a00000000000001'}, {id: 'a00000000000002'}]);
    assert.equal(setup.org.seen.filter(item => item.method === 'PATCH').length,
      2);
    await third.close();
  });

test('conflicting coinstalled Catalogs fail before provider I/O', async t => {
  const setup = await installation(t, {
    readable: ['Other_Record__c', 'Test_Record__c'],
    sourceResources: ['Other_Record__c', 'Test_Record__c'],
    extraObjects: ['Other_Record__c'],
  });
  await setup.publish();
  const effectPath = join(setup.root, 'conflicting-effect.json');
  const account = canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'conflicting-effect', entries: [
      {entry_id: 'effect', outcome: 'allow', exclusions: [],
        principal: {all: true},
        connection: {any_of: [setup.connection]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['effect']}},
      {entry_id: 'metadata', outcome: 'allow', exclusions: [],
        principal: {all: true},
        connection: {any_of: [setup.connection]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['read']}},
    ]});
  await writeFile(effectPath, JSON.stringify({
    version: 'actql-installed-salesforce-effect/0.1',
    siteProfilePath: setup.sitePath,
    publicationPath: join(setup.root, 'conflicting-publication.json'),
    connectorId: 'crm-main', accountConfigurationWire: account,
    writes: [{resource: 'Test_Record__c', kind: 'update',
      fields: ['Name']}],
  }));
  await publishInstalledEffect({effectProfilePath: effectPath,
    directory: join(setup.root, 'state'), resolveEffectSecret: secret});
  const before = setup.org.seen.length;
  for (let attempt = 0; attempt < 2; attempt++) {
    await assert.rejects(openInstalledRemoteHttpHost({
      directory: join(setup.root, 'state'),
      authenticate: () => owner, sourceProfilePath: setup.profilePath,
      effectProfilePath: effectPath, resolveSourceSecret: secret,
      resolveEffectSecret: secret,
      authorization: checkpointAuthorization({
        accountConfiguration: account}),
    }), error => error.code === 'InstalledHostInitializationFailed' &&
      error.cause?.code === 'InstalledCheckEnvironmentConflict' &&
      error.cleanupPending === false);
    assert.equal(setup.org.seen.length, before);
  }
});

test('equal coinstalled Catalogs cannot mask another Site binding',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    const foreignSitePath = join(setup.root, 'foreign-alias-site.json');
    await writeFile(foreignSitePath, JSON.stringify({...setup.siteDocument,
      cliAlias: 'another-explicit-alias'}));
    const effectPath = join(setup.root, 'foreign-alias-effect.json');
    const account = canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'site-binding-test', entries: [
        {entry_id: 'effect', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {any_of: [setup.connection]},
          resource: {any_of: ['Test_Record__c']},
          operation: {any_of: ['effect']}},
        {entry_id: 'metadata', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {any_of: [setup.connection]},
          resource: {any_of: ['Test_Record__c']},
          operation: {any_of: ['read']}},
      ]});
    await writeFile(effectPath, JSON.stringify({
      version: 'actql-installed-salesforce-effect/0.1',
      siteProfilePath: foreignSitePath,
      publicationPath: join(setup.root, 'foreign-alias-publication.json'),
      connectorId: 'crm-main', accountConfigurationWire: account,
      writes: [{resource: 'Test_Record__c', kind: 'update',
        fields: ['Name']}],
    }));
    await publishInstalledEffect({effectProfilePath: effectPath,
      directory: join(setup.root, 'state'), resolveEffectSecret: secret});
    const before = setup.org.seen.length;
    await assert.rejects(openInstalledRemoteHttpHost({
      directory: join(setup.root, 'state'),
      authenticate: () => owner, sourceProfilePath: setup.profilePath,
      effectProfilePath: effectPath, resolveSourceSecret: secret,
      resolveEffectSecret: secret,
      authorization: checkpointAuthorization({
        accountConfiguration: account}),
    }), error => error.code === 'InstalledHostInitializationFailed' &&
      error.cause?.code === 'InstalledCheckEnvironmentConflict' &&
      error.cause?.cause === 'ConnectorBinding' &&
      error.cleanupPending === false);
    assert.equal(setup.org.seen.length, before);
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
      requestId: 'undeclared-1'}), {code: 'ClientProgramRejected'});
    // An acquisition the local planner cannot generate is refused as
    // unsupported, before any Run.
    const unsupported = program.replace("Name <> 'record-2'",
      "External_Key__c IN ('key-1', 'key-3')");
    await assert.rejects(client.aql(unsupported, {format: 'json',
      requestId: 'unsupported-1'}), {code: 'ClientProgramUnsupported'});
    assert.deepEqual(await client.lookupRequest('unsupported-1'),
      {kind: 'not_found'});
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

// A Run whose acquisition ended without a capture: the Run fails, nothing is
// retried, and the Host still closes (its dispatch owner holds nothing).
// The installed source adapter the standard Host loads, and the prepared
// `source` Program's acquisition inputs, for asserting how an acquisition
// ended.
async function installedAdapter(setup, source) {
  const {loadInstalledSource} = await import(
    '../../../host-node/installed-source.mjs');
  const spec = name => readFile(join(repository, name), 'utf8');
  const base = (await spec('spec/local-check-environment.json')).trimEnd();
  const adapter = await loadInstalledSource(setup.profilePath, {
    root: join(setup.root, 'adapter-state'), principalId: owner,
    moon: commonMoon, runtimeUrl: new URL(
      '../../../../_build/js/release/build/connectors_builtin_node/' +
      'connectors_builtin_node.js', import.meta.url),
    baseEnvironmentWire: base, resolveSecret: secret});
  const environment = commonMoon.clientProgramCheckEnvironment(
    adapter.environmentWire, JSON.parse(adapter.environmentWire)
      .evidence_bundle_cid, false, false, true, false, false, false, false);
  const preparedProgram = commonMoon.clientProgramPreparationReady(
    commonMoon.clientProgramPrepareEffectFreeWithParameters(source, 'json',
      environment, undefined));
  const aoa = JSON.parse(await spec('spec/contracts/actql-aoa.json'));
  const common = {preparedProgram,
    registry: await spec('spec/dependencies/aoa-pipeline-registry.json'),
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(
      aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  return {adapter, common};
}

async function assertEndedRun(setup, client, requestId) {
  const execution = await client.aql(program, {format: 'json', requestId});
  assert.equal((await execution.wait()).status, 'failed');
  const requests = setup.org.seen.length;
  assert.equal((await client.lookupRequest(requestId)).kind, 'found');
  assert.equal((await execution.wait()).status, 'failed');
  assert.equal(setup.org.seen.length, requests);
}

test('a delegated read with no Checkpoint ends at dispatch and the Host closes',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    // The account delegates the read and this Host installs no Checkpoint:
    // nothing can answer it, so the dispatch's current read decision refuses
    // it before any provider request. The Run fails once, nothing is
    // retried, and the Host's dispatch owner holds nothing at close.
    await writeFile(setup.profilePath, JSON.stringify({...setup.profile,
      accountConfigurationWire: accountConfiguration(setup.org.orgId,
        ['Test_Record__c'], 'delegate')}));
    const {client, close} = await setup.open();
    const before = setup.org.seen.length;
    await assertEndedRun(setup, client, 'delegated-1');
    assert.equal(setup.org.seen.length, before);
    await close();
  });

test('a read denied when the acquisition opens is stated as not started',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    const {adapter, common} = await installedAdapter(setup, program);
    try {
      // The read is allowed when prepared and revoked before the dispatch.
      let decisions = 0;
      const access = {...adapter.sourceAccess, authorization: {
        authorize: async (...args) => ++decisions === 1
          ? adapter.sourceAccess.authorization.authorize(...args)
          : Object.freeze({action: 'deny', reason: 'no_match'})}};
      const preparedSource = await adapter.prepare({...common,
        sourceAccess: access});
      const before = setup.org.seen.length;
      await assert.rejects(adapter.open({...common, sourceAccess: access,
        preparedSource}), error => error.outcome === 'not_started' &&
        error.code === 'ExecutionAuthorizationDenied');
      assert.equal(setup.org.seen.length, before);
    } finally {
      adapter.close();
    }
  });

test('a provider failure after the read started ends its Run once',
  async t => {
    const setup = await installation(t, {queryFailureStatus: 503});
    await setup.publish();
    const {client, close} = await setup.open();
    await assertEndedRun(setup, client, 'failed-after-start');
    // One query was sent and none repeated.
    assert.equal(setup.queries().length, 1);
    await close();
  });

// Synthetic records: long text in several columns across many rows.
const records = (count, textBytes) => Array.from({length: count},
  (_, index) => {
    const tag = String(index).padStart(3, '0');
    return {Id: `a00000000000${tag}`,
      Name: `n${tag}`.padEnd(textBytes, 'n'),
      External_Key__c: `k${tag}`.padEnd(textBytes, 'k'),
      Optional_Text__c: index % 2 === 0 ? null
        : `t${tag}`.padEnd(textBytes, 't')};
  });

test('long text in several columns and many rows reaches the Named Result',
  async t => {
    // 60 rows of about 3 x 1,500 characters: each row fits one Local import
    // batch; the whole input spans several.
    const stored = records(60, 1500);
    const setup = await installation(t, {storedRecords: stored});
    await setup.publish();
    const {client, close} = await setup.open();
    const execution = await client.aql(program, {format: 'json',
      requestId: 'long-rows'});
    assert.equal((await execution.wait()).status, 'succeeded');
    const rows = await execution.result('records').all();
    assert.deepEqual(rows.map(row => [row.External_Key__c, row.Name]).sort(),
      stored.map(row => [row.External_Key__c, row.Name]).sort());
    await close();
  });

test('an acquisition over its capture bound publishes nothing and ends once',
  async t => {
    // 100 rows of 3 x 10,000 characters exceed what one acquisition may
    // capture (about 1 MB of text).
    const setup = await installation(t, {storedRecords: records(100, 10000)});
    await setup.publish();
    const {client, close} = await setup.open();
    const execution = await client.aql(program, {format: 'json',
      requestId: 'over-capture'});
    assert.equal((await execution.wait()).status, 'failed');
    await assert.rejects(execution.result('records').all());
    assert.equal(setup.queries().length, 1);
    // The Host holds nothing for the Run: it closes.
    await close();
  });

// A held read: submitting it returns the held request.
async function heldRead(client, requestId) {
  try { await client.aql(program, {format: 'json', requestId}); }
  catch (error) {
    assert.equal(error instanceof RequestHeld, true, String(error?.code));
    return error.held;
  }
  assert.fail('expected a held request');
}

async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Timeout');
}

// Publish under a read the account allows, then install the Host with the
// read delegated to its Checkpoint.
async function delegatedInstallation(t, options) {
  const setup = await installation(t, options);
  await setup.publish();
  await writeFile(setup.profilePath, JSON.stringify({...setup.profile,
    accountConfigurationWire: accountConfiguration(setup.org.orgId,
      ['Test_Record__c'], 'delegate')}));
  return setup;
}

test('a held read is approved across a Host restart and reaches the Named Result',
  async t => {
    const setup = await delegatedInstallation(t);
    const first = await setup.open({authorization:
      checkpointAuthorization({resumeAfterAnswer: false})});
    const before = setup.org.seen.length;
    const hold = await heldRead(first.client, 'held-read');
    assert.equal(hold.checkpoint.kind, 'read_access');
    const reviewer = await first.as('reviewer-token');
    const {items: [summary]} = await reviewer.checkpoints();
    await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    // Nothing was read while the request was held and answered.
    assert.equal(setup.org.seen.length, before);
    await first.close();
    const second = await setup.open({authorization:
      checkpointAuthorization({})});
    const found = await waitFor(async () => {
      const lookup = await second.client.lookupRequest('held-read');
      return lookup.kind === 'found' ? lookup : undefined;
    });
    const execution = await second.client.attach(found.ref);
    const state = await waitFor(async () => {
      const current = await execution.wait();
      return ['succeeded', 'failed', 'cancelled'].includes(current.status)
        ? current : undefined;
    });
    assert.equal(state.status, 'succeeded');
    const rows = await execution.result('records').all();
    assert.deepEqual(rows.map(row => [row.External_Key__c, row.Name]).sort(),
      [['key-1', 'record-1'], ['key-3', 'record-3']]);
    // The approved read described its Resource and queried once.
    assert.equal(setup.queries().length, 1);
  });

test('an expired, cancelled or retargeted approval reads nothing',
  async t => {
    // Expired: the approval lapses before the Host resumes the read.
    const expired = await delegatedInstallation(t);
    const e1 = await expired.open({authorization: checkpointAuthorization({
      checkpointTtlMs: 8000, resumeAfterAnswer: false})});
    await heldRead(e1.client, 'expired-read');
    const eReviewer = await e1.as('reviewer-token');
    const {items: [eSummary]} = await eReviewer.checkpoints();
    await eReviewer.resolveCheckpoints([{checkpoint: eSummary,
      decision: 'approved'}], {signer});
    await e1.close();
    await new Promise(resolve => setTimeout(resolve,
      Math.max(0, Date.parse(eSummary.expiresAt) + 300 - Date.now())));
    const eBefore = expired.org.seen.length;
    const e2 = await expired.open({authorization: checkpointAuthorization({
      checkpointTtlMs: 8000})});
    await waitFor(async () => (await e2.client.lookupRequest('expired-read'))
      .state === 'ended');
    assert.equal(expired.org.seen.length, eBefore);

    // Cancelled: the request is cancelled after approval, before resuming.
    const cancelled = await delegatedInstallation(t);
    const c1 = await cancelled.open({authorization:
      checkpointAuthorization({resumeAfterAnswer: false})});
    await heldRead(c1.client, 'cancelled-read');
    const cReviewer = await c1.as('reviewer-token');
    const {items: [cSummary]} = await cReviewer.checkpoints();
    await cReviewer.resolveCheckpoints([{checkpoint: cSummary,
      decision: 'approved'}], {signer});
    await c1.client.cancelRequest('cancelled-read');
    await c1.close();
    const cBefore = cancelled.org.seen.length;
    const c2 = await cancelled.open({authorization:
      checkpointAuthorization({})});
    await waitFor(async () => (await c2.client.lookupRequest(
      'cancelled-read')).state === 'ended');
    assert.equal(cancelled.org.seen.length, cBefore);

    // Retargeted: the declaration is republished after approval with another
    // field set, so the same Program would read another declared target.
    const retargeted = await delegatedInstallation(t);
    const r1 = await retargeted.open({authorization:
      checkpointAuthorization({resumeAfterAnswer: false})});
    await heldRead(r1.client, 'retargeted-read');
    const rReviewer = await r1.as('reviewer-token');
    const {items: [rSummary]} = await rReviewer.checkpoints();
    await rReviewer.resolveCheckpoints([{checkpoint: rSummary,
      decision: 'approved'}], {signer});
    await r1.close();
    retargeted.org.setOptionalText(true);
    await writeFile(retargeted.profilePath, JSON.stringify(
      retargeted.profile));
    await retargeted.publish();
    await writeFile(retargeted.profilePath, JSON.stringify({
      ...retargeted.profile, accountConfigurationWire: accountConfiguration(
        retargeted.org.orgId, ['Test_Record__c'], 'delegate')}));
    const rBefore = retargeted.queries().length;
    const r2 = await retargeted.open({authorization:
      checkpointAuthorization({})});
    await waitFor(async () => (await r2.client.lookupRequest(
      'retargeted-read')).state === 'ended');
    assert.equal(retargeted.queries().length, rBefore);
  });

// A Program reading the declared `date` and `datetime` fields through the
// same scan, filter and select acquisition chain; the filter keeps every
// stored record.
const temporalProgram = JSON.stringify({version: 'actql/0.1',
  id: 'salesforce-temporal', stages: [
    {id: 'acquire',
      inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
      steps: [{filter: "Id <> 'none'", as: 'filtered'},
        {select: ['Id', 'Due_Date__c', 'Due_At__c'], as: 'captured'}],
      results: {r: {from: 'captured',
        fields: ['Id', 'Due_Date__c', 'Due_At__c']}}},
    {id: 'compute',
      inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
      steps: [{select: ['Id', 'Due_Date__c', 'Due_At__c'], as: 'out'}],
      results: {r: {from: 'out', fields: ['Id', 'Due_Date__c', 'Due_At__c']}}},
  ],
  results: {records: {from: {stage: 'compute', result: 'r'}}}});

test('Salesforce dates and UTC datetimes reach the Named Result as the same values',
  async t => {
    const setup = await installation(t, {temporalFields: true});
    await setup.publish();
    const {client, close} = await setup.open();
    const execution = await client.aql(temporalProgram, {format: 'json',
      requestId: 'temporal-read'});
    const state = await execution.wait();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const rows = await execution.result('records').all();
    // Independently expected from the org's stored replies: the date as it
    // is, the `+0000` datetime as the same UTC instant ending in Z, and
    // nulls kept.
    assert.deepEqual(rows.map(row => [row.Id, row.Due_Date__c, row.Due_At__c])
      .sort(), [
      ['a00000000000001', '2024-05-22', '2012-07-12T17:49:01.123Z'],
      ['a00000000000002', null, null],
      ['a00000000000003', '1700-01-01', '4000-12-31T00:00:00.000Z'],
    ]);
    await close();
  });

test('a datetime outside its declared type fails the acquisition, typed',
  async t => {
    // A reply in another offset is not converted to UTC: the whole
    // acquisition fails and nothing is published.
    const stored = [
      {Id: 'a00000000000001', Name: 'record-1', External_Key__c: 'key-1',
        Due_Date__c: '2024-05-22', Due_At__c: '2012-07-12T17:49:01.123+0000'},
      {Id: 'a00000000000002', Name: 'record-2', External_Key__c: 'key-2',
        Due_Date__c: '2024-05-23', Due_At__c: '2012-07-13T02:49:01.123+0900'}];
    const setup = await installation(t, {temporalFields: true,
      storedRecords: stored});
    await setup.publish();
    const {client, close} = await setup.open();
    const execution = await client.aql(temporalProgram, {format: 'json',
      requestId: 'temporal-violation'});
    assert.equal((await execution.wait()).status, 'failed');
    await assert.rejects(execution.result('records').all());
    assert.equal(setup.queries().length, 1);
    await close();
    // The adapter states the failure: a typed value violation naming the
    // Resource, field, declared type and kind, never the value, after the
    // read stopped.
    const {adapter, common} = await installedAdapter(setup, temporalProgram);
    try {
      const before = setup.queries().length;
      const failure = await adapter.open(common).then(() => undefined,
        error => error);
      assert.equal(failure?.code, 'SalesforceValueViolation',
        String(failure?.code));
      assert.equal(failure.outcome, 'stopped');
      assert.deepEqual(failure.cause.violation, {expected_type: 'timestamp',
        field: 'Due_At__c', kind: 'format', resource: 'Test_Record__c'});
      assert.equal(JSON.stringify(failure.cause.violation).includes('2012'),
        false);
      assert.equal(setup.queries().length, before + 1);
    } finally {
      adapter.close();
    }
  });

test('a capture budget overrun is not a value violation', async t => {
  const setup = await installation(t, {storedRecords: records(100, 10000)});
  await setup.publish();
  const {adapter, common} = await installedAdapter(setup, program);
  try {
    const failure = await adapter.open(common).then(() => undefined,
      error => error);
    assert.ok(failure);
    assert.notEqual(failure.code, 'SalesforceValueViolation');
    assert.equal(failure.cause?.violation, undefined);
  } finally {
    adapter.close();
  }
});
