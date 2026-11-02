// Synthetic TLS/data configuration only. Every product Owner and runtime is
// resolved from the ordinary installed Local package; no checkout overlay.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile, mkdir, mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import * as common from '@actql/local-node/runtime';
import {fixtureCertificates} from '../../adapters/site-node/https-exchange-fixture.mjs';

const local = new URL('./', import.meta.resolve('@actql/local-node'));
const {loadInstalledSource} = await import(new URL('adapters/host-node/installed-source.mjs', local));
const {canonicalJson} = await import(new URL('adapters/host-node/local-account-config.mjs', local));
const {openHostInitializationPreparation, closeHostInitializationPreparation} =
  await import(new URL('adapters/local-node/request-preparation-adapter.mjs', local));
const {createInstalledHostServices, retireInstalledSourceInitialization} =
  await import(new URL('adapters/host-node/installed-host-services.mjs', local));
const runtimeUrl = new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', local);
const baseEnvironmentWire = await readFile(new URL('spec/local-check-environment.json', local), 'utf8');
export const expected = {id: '9007199254740993', amount: '9007199254740993.0100000000', tags: ['a', 'b']};
const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number'},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', options: [{value: 'a'}, {value: 'b'}]},
]};
const identityBody = '{"portalId":7,"accountType":"STANDARD"}';
const propertiesBody = JSON.stringify(properties);
const objectBody = JSON.stringify({results: [{id: expected.id, archived: false,
  properties: {amount: '9007199254740993.01', tags: 'a;b'}}]});

export async function fixture(t, entrance) {
  const parent = join(process.cwd(), 'hubspot-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, `public-${entrance.toLowerCase()}-`));
  const tls = await fixtureCertificates(root);
  const state = {requests: [], resolutions: 0};
  const provider = createServer({key: tls.key, cert: tls.cert}, (request, response) => {
    state.requests.push({method: request.method, path: request.url});
    let body;
    if (request.method === 'GET' && request.headers.authorization === 'Bearer provider-secret') {
      if (request.url === '/account-info/v3/details') body = identityBody;
      else if (request.url === '/crm/v3/properties/companies') body = propertiesBody;
      else if (request.url.startsWith('/crm/v3/objects/companies?')) body = objectBody;
    }
    if (body === undefined) {
      response.writeHead(400, {'content-type': 'application/json'}); response.end('{}'); return;
    }
    response.writeHead(200, {'content-type': 'application/json'}); response.end(body);
  });
  let client, host, server, priorCa, declared;
  const pendingInitialization = [];
  // Bootstrap uses the same installed package/runtime's real initial owner.
  // Retain its state before opening; never pass a checkout-owned private brand.
  const bootstrapState = {};
  let bootstrapServices, bootstrapPending = false, bootstrapClosed = false;
  const closeBootstrap = () => {
    if (bootstrapClosed) return;
    if (bootstrapServices !== undefined) {
      assert.equal(retireInstalledSourceInitialization(bootstrapServices), true,
        'Bootstrap Source children must retire before their original parent');
    }
    bootstrapPending = false;
    if (bootstrapState.runtime !== undefined) closeHostInitializationPreparation(bootstrapState);
    bootstrapClosed = true;
  };
  const acquire = async action => {
    try {return await action();}
    catch (error) {
      if (error.cleanupHandle?.status?.().pending) pendingInitialization.push(error.cleanupHandle);
      throw error;
    }
  };
  t.after(async () => {
    const failures = [];
    for (const close of [
      () => client?.close(),
      async () => {if (server?.listening) {server.closeAllConnections(); await new Promise((resolve, reject) => server.close(e => e ? reject(e) : resolve()));}},
      () => host?.close(),
      ...pendingInitialization.map(handle => async () => {
        await handle.retry();
        assert.equal(handle.status().pending, false, 'Original initialization cleanup remains owned');
      }),
      () => declared?.close(),
      closeBootstrap,
      async () => {if (provider.listening) {provider.closeAllConnections(); await new Promise((resolve, reject) => provider.close(e => e ? reject(e) : resolve()));}},
    ]) try {await close();} catch (error) {failures.push(error);}
    if (priorCa !== undefined) setDefaultCACertificates(priorCa);
    t.diagnostic(`Retained ordinary HubSpot original root: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'HubSpotFixtureCleanupUnconfirmed');
  });
  await new Promise((resolve, reject) => {provider.once('error', reject); provider.listen(0, '127.0.0.1', resolve);});
  const authority = generateKeyPairSync('ed25519');
  const credentialPrivateKeyPath = join(root, 'credential-authority.key');
  await writeFile(credentialPrivateKeyPath, authority.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: `https://127.0.0.1:${provider.address().port}`,
    credentialAuthorityId: 'installed-hubspot', credentialKeyId: 'key', credentialPrivateKeyPath,
    environment: 'test', journalRoot: join(root, 'installed-credential-journal'), namespaceId: 'installed-hubspot',
    siteGeneration: 1, siteKey: 'installed-hubspot', tokenEnvironment: 'ACTQL_HUBSPOT_TEST_TOKEN', caPath: tls.caPath};
  const siteProfilePath = join(root, 'installed-site.json');
  await writeFile(siteProfilePath, JSON.stringify(site));
  const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'hubspot', portalId: '7',
    apiOrigin: site.apiOrigin, accountBody: Buffer.from(identityBody).toString('base64'),
    objects: [{resource: 'companies', objectType: 'companies', propertiesBody: Buffer.from(propertiesBody).toString('base64')}]};
  const metadataPath = join(root, 'installed-metadata.json');
  await writeFile(metadataPath, JSON.stringify(metadata));
  const accountConfigurationWire = canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'installed',
    entries: [['records', 'companies'], ['identity', 'account'], ['schema', 'properties']]
      .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([entry_id, resource]) => ({
        entry_id, outcome: 'allow', principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
        resource: {any_of: [resource]}, operation: {any_of: ['read']}, exclusions: []}))});
  const profile = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'hubspot', portalId: '7',
    resources: [{resource: 'companies', objectType: 'companies'}], metadataPath, siteProfilePath,
    metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire,
    // Original component's explicit test units; no normal numerical profile adoption.
    limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20, maxProperties: 10,
      maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
      maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
      maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
      maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128}};
  const sourceProfilePath = join(root, 'installed-source.json');
  await writeFile(sourceProfilePath, JSON.stringify(profile));
  const resolveSourceSecret = async () => {state.resolutions++; return 'provider-secret';};
  const assertBootstrapCurrent = () => assert.equal(bootstrapClosed, false);
  const initialPreparation = openHostInitializationPreparation(bootstrapState, common,
    Object.freeze({root, purpose: 'packed Source schema bootstrap'}),
    assertBootstrapCurrent, () => bootstrapPending);
  bootstrapServices = createInstalledHostServices({root, principalId: 'operator', moon: common,
    initialPreparation, assertCurrent: assertBootstrapCurrent});
  bootstrapPending = true;
  declared = await acquire(() => loadInstalledSource(sourceProfilePath, {root, principalId: 'operator', moon: common,
    runtimeUrl, baseEnvironmentWire, resolveSecret: resolveSourceSecret,
    installationServices: bootstrapServices}));
  const environment = JSON.parse(declared.environmentWire);
  const view = environment.schema_snapshots.find(value => value.source_ref === declared.sourceReadAccesses[0].sourceRef);
  assert.ok(view);
  await declared.close(); declared = undefined;
  closeBootstrap();
  await writeFile(sourceProfilePath, JSON.stringify({...profile, queryAliases: [{
    name: 'hubspot.companies', sourceRef: view.source_ref,
    sourceViewContractCid: view.source_view_contract_cid, schemaContractCid: view.carrier_schema_contract_cid}]}));
  const keys = generateKeyPairSync('ed25519'), observations = [], principal = userInfo().username;
  const authorization = {accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'hubspot-public-test',
    entries: [{entry_id: 'run-read-write', outcome: 'allow', exclusions: [], principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {any_of: ['read', 'write']}}]}),
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  observe(name, detail) {observations.push([name, detail]);}};
  const installation = {directory: join(root, 'public-host'), sourceProfilePath, resolveSourceSecret,
    authorization, retainedRelationOutput: true};
  if (entrance === 'Local') client = await acquire(() => connect({mode: 'local', owner: 'local', durability: 'durable', installation}));
  else {
    priorCa = getCACertificates('default'); setDefaultCACertificates([...priorCa, tls.ca.toString('utf8')]);
    host = await acquire(() => openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer hubspot-public-test' ? principal : undefined}));
    server = createServer({key: tls.key, cert: tls.cert}, host.handler);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'hubspot-public-test', durability: 'durable'});
  }
  return {root, state, client, observations, installation,
    async closeHost() {
      await client.close();
      if (server?.listening) {server.closeAllConnections(); await new Promise((resolve, reject) => server.close(e => e ? reject(e) : resolve()));}
      await host?.close();
    }};
}
