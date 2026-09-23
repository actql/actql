import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import * as salesforceConformance from
  '../../_build/js/release/build/connectors/salesforce/site_test/site_test.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openEffectLedger} from '../host-node/effect-ledger.mjs';
import {captureClaimedEffectCollectionResponse} from
  '../host-node/effect-physical-dispatch.mjs';
import {captureSalesforceSingleEffectWrite} from
  '../host-node/salesforce-effect-write.mjs';
import {openSqliteCredentialJournal} from
  './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  './remote-credential-signature.mjs';
import {syncSalesforceCatalog} from './salesforce-catalog-sync.mjs';
import {createSalesforceCliSecretResolver} from './salesforce-cli-secret.mjs';
import {readSalesforceIssuedBroad, readSalesforceManagedQuery,
  readSalesforceQuery} from
  './salesforce-query-read.mjs';
import {writeSalesforceSingleRecord} from './salesforce-single-write.mjs';
import {writeSalesforceContinueCollection} from
  './salesforce-collection-write.mjs';

const control = runtimeCore(commonMoon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const listBody = JSON.stringify({sobjects: [
  {name: 'Account', queryable: true, createable: false,
    updateable: false},
  {name: 'Test_Record__c', queryable: true, createable: true,
    updateable: true},
]});
const accountBody = JSON.stringify({name: 'Account', queryable: true,
  createable: false, updateable: false,
  fields: [{name: 'Id', type: 'id', nillable: false}]});
const customBody = JSON.stringify({name: 'Test_Record__c', queryable: true,
  createable: true, updateable: true,
  fields: [{name: 'External_Key__c', type: 'string', externalId: true,
    unique: true, caseSensitive: true, nillable: false,
    defaultedOnCreate: false,
    createable: true, updateable: true}]});

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

async function fixture(t, {customStatus = 200, customResponse = customBody,
  orgId = '00D000000000001EAA',
  listStatus = 200, listResponse = listBody,
  accountRefreshResponse, querySecondStatus = 200,
  queryFirstResponse, writeStatus = 201,
  writeResponse = JSON.stringify({id: 'a00123456789012',
    success: true, errors: []}),
  collectionStatus = 200,
  collectionResponse = JSON.stringify([
    {id: 'a00123456789012', success: true, errors: []},
    {id: null, success: false, errors: [{statusCode: 'INVALID_FIELD',
      message: 'Rejected field', fields: ['External_Key__c']}]},
  ])} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-catalog-'));
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(root, 'req', '-x509', '-new', '-key', 'ca.key', '-out',
    'ca.crt', '-subj', '/CN=ActQL Catalog Test CA', '-days', '1');
  openssl(root, 'genrsa', '-out', 'resource.key', '2048');
  openssl(root, 'req', '-new', '-key', 'resource.key', '-out',
    'resource.csr', '-subj', '/CN=localhost');
  await writeFile(join(root, 'resource.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n');
  openssl(root, 'x509', '-req', '-in', 'resource.csr', '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', 'resource.crt',
    '-days', '1', '-extfile', 'resource.ext');
  const [ca, cert, key] = await Promise.all([
    readFile(join(root, 'ca.crt')),
    readFile(join(root, 'resource.crt')),
    readFile(join(root, 'resource.key')),
  ]);
  const seen = [];
  let accountDescribeCount = 0;
  const server = createServer({cert, key}, (request, response) => {
    const observed = {method: request.method, path: request.url,
      authorization: request.headers.authorization};
    seen.push(observed);
    if (request.headers.authorization !== 'Bearer test-only-secret') {
      response.writeHead(401).end();
    } else if (request.url === '/services/data/v62.0/sobjects/') {
      response.writeHead(listStatus, {'content-type': 'application/json'});
      response.end(listResponse);
    } else if (request.url ===
      '/services/data/v62.0/sobjects/Account/describe') {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(accountDescribeCount++ === 0
        ? accountBody : accountRefreshResponse ?? accountBody);
    } else if (request.url ===
      '/services/data/v62.0/sobjects/Test_Record__c/describe') {
      response.writeHead(customStatus, {'content-type': 'application/json'});
      response.end(customResponse);
    } else if (request.method === 'POST' && request.url ===
      '/services/data/v62.0/sobjects/Test_Record__c/') {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        response.writeHead(writeStatus, {'content-type': 'application/json'});
        response.end(writeResponse);
      });
    } else if (['POST', 'PATCH'].includes(request.method) && [
      '/services/data/v62.0/composite/sobjects',
      '/services/data/v62.0/composite/sobjects/' +
        'Test_Record__c/External_Key__c',
    ].includes(request.url)) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        response.writeHead(collectionStatus,
          {'content-type': 'application/json'});
        response.end(collectionResponse);
      });
    } else if (request.method === 'PATCH' && request.url.startsWith(
      '/services/data/v62.0/sobjects/Test_Record__c/External_Key__c/')) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        response.writeHead(404, {'content-type': 'application/json'});
        response.end('[{"errorCode":"NOT_FOUND"}]');
      });
    } else if (request.url ===
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account') {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(queryFirstResponse ?? JSON.stringify({totalSize: 2, done: false,
        nextRecordsUrl: '/services/data/v62.0/query/01gABC-2000',
        records: [{attributes: {type: 'Account'}, Id: '001A'}]}));
    } else if (request.url ===
      '/services/data/v62.0/query/01gABC-2000') {
      response.writeHead(querySecondStatus,
        {'content-type': 'application/json'});
      response.end(querySecondStatus === 200
        ? JSON.stringify({totalSize: 2, done: true,
          records: [{attributes: {type: 'Account'}, Id: '001B'}]})
        : JSON.stringify([{errorCode: 'REQUEST_LIMIT_EXCEEDED'}]));
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([[
      'credential-authority-a',
      new Map([['credential-key-a', authority.publicKey]]),
    ]]),
  });
  t.after(async () => {
    journal.close();
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  });
  const scope = operation => Object.freeze({
    issuerAuthority: 'credential-authority-a',
    principal: 'principal-a', tenant: 'tenant-a',
    environment: 'test', siteKey: 'site-a', siteGeneration: 4,
    runtimeBundleCid: cid('a'), connectorRegistration: 'salesforce',
    connectorRevision: 'salesforce/0.1', resourceOrigin: origin,
    operation, runInvocationCid: cid('b'), taskAttempt: 2,
    dispatchRequestCid: cid(operation === 'salesforce:query:read' ? 'd' : 'c'),
    expiresUnixMilliseconds: 2_000_000_000_000n,
    maxUses: 5,
  });
  const authorize = operation => {
    const value = scope(operation);
    const grant = control.prepare(value);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
      keyId: 'credential-key-a', privateKey: authority.privateKey,
    }), control);
    return {grant, scope: value};
  };
  const list = authorize('salesforce:catalog:list');
  const describe = authorize('salesforce:catalog:describe');
  const query = authorize('salesforce:query:read');
  const write = authorize('salesforce:record:create');
  const writeUpdate = authorize('salesforce:record:update');
  const writeUpsert = authorize('salesforce:record:upsert');
  return {
    seen, journal, list, describe, query, write, writeUpdate, writeUpsert, ca,
    orgId,
    credential: {
      orgId,
      control, journal,
      resolveSecret: async () => 'test-only-secret',
      ca, now: () => 1_999_999_999_999,
    },
  };
}

const listLimits = Object.freeze({maxBytes: 10000, maxNodes: 1000,
  maxDepth: 20, maxResources: 20, maxSelected: 20,
  maxNameUnits: 1000});
const describeLimits = Object.freeze({maxBytes: 10000, maxNodes: 1000,
  maxDepth: 20, maxFields: 20, maxNameUnits: 1000});

function request(setup, overrides = {}) {
  return {
    moon: salesforceMoon,
    apiVersion: 'v62.0',
    connectionRevision: 'connection-revision-a',
    orgId: setup.orgId,
    syncOccurrence: 'catalog-sync-a',
    maxObservationBytes: 10000,
    listAuthorization: {...setup.list, useId: 'list-use'},
    authorizationForDescribe: async name => ({
      ...setup.describe, useId: `describe-${name}`,
    }),
    credential: setup.credential,
    listLimits,
    describeLimits,
    ...overrides,
  };
}

test('Site HTTPS catalog sync completes with scoped credential uses',
  async t => {
    const setup = await fixture(t);
    const result = await syncSalesforceCatalog(request(setup));
    assert.equal(result.status, 'complete');
    assert.equal(result.observationCid,
      salesforceMoon.salesforceCatalogObservationCid(result.observation));
    assert.equal(result.observationCid, `sha256:${createHash('sha256')
      .update(result.observationJson).digest('hex')}`);
    assert.equal(JSON.parse(result.observationJson).binding.connection_revision,
      'connection-revision-a');
    assert.deepEqual(JSON.parse(result.observationJson).listed_resources.map(
      entry => entry.outcome), ['described', 'described']);
    assert.equal(result.describeUseCids.length, 2);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Account'), 1);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), 1);
    assert.deepEqual(setup.seen.map(({method, path}) => [method, path]), [
      ['GET', '/services/data/v62.0/sobjects/'],
      ['GET', '/services/data/v62.0/sobjects/Account/describe'],
      ['GET', '/services/data/v62.0/sobjects/Test_Record__c/describe'],
    ]);
    assert.ok(setup.seen.every(entry =>
      entry.authorization === 'Bearer test-only-secret'));
    assert.equal(setup.journal.inspect(result.listUseCid).outcome,
      'succeeded');
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareReadProjection(
      result.observation,
      binding.tenant, binding.principal, binding.environment,
      'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Account',
      ['Id'], 22));
    assert.equal(salesforceMoon.salesforceReadProjectionSoql(projection),
      'SELECT Id FROM Account');
    assert.equal(salesforceMoon.salesforceReadProjectionObservationCid(
      projection), result.observationCid);
    assert.throws(() => checked(salesforceMoon.salesforcePrepareReadProjection(
      result.observation,
      binding.tenant, binding.principal, binding.environment,
      'connection-revision-b', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Account',
      ['Id'], 22)), {code: 'MoonBitHostFailure'});
  });

test('Catalog org binding is fixed before any scoped metadata request',
  async t => {
    const setup = await fixture(t);
    await assert.rejects(syncSalesforceCatalog(request(setup, {
      orgId: '00D000000000002EAA',
    })), {code: 'InvalidSalesforceCatalogSync'});
    const resolver = async () => 'test-only-secret';
    resolver.connectionOrgId = '00D000000000002EAA';
    await assert.rejects(syncSalesforceCatalog(request(setup, {
      credential: {...setup.credential, resolveSecret: resolver},
    })), {code: 'InvalidSalesforceCatalogSync'});
    assert.equal(setup.seen.length, 0);
    assert.equal(setup.journal.recover().length, 0);
  });

test('Salesforce write bridge binds a checked Catalog to one REST request',
  async t => {
    const setup = await fixture(t);
    const result = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      result.observation,
      binding.tenant, binding.principal, binding.environment,
      'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
      0, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"key-1"}'),
      1024, 32, 5));
    const outbound = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
      body, 'v62.0', 0, '', 0, 256, 128, 1024));
    assert.equal(checked(
      salesforceMoon.salesforceRecheckSingleWriteRequest(
        outbound, result.observation)), true);
    assert.equal(salesforceMoon.salesforceSingleWriteRequestScopeMatches(
      outbound, binding.tenant, binding.principal, binding.environment,
      binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid), true);
    assert.equal(salesforceMoon.salesforceSingleWriteRequestScopeMatches(
      outbound, binding.tenant, binding.principal, binding.environment,
      binding.siteKey, binding.siteGeneration + 1,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid), false);
    assert.equal(salesforceMoon.salesforceSingleWriteRequestMethod(outbound),
      'POST');
    assert.equal(salesforceMoon.salesforceSingleWriteRequestPath(outbound),
      '/services/data/v62.0/sobjects/Test_Record__c/');
    assert.equal(salesforceMoon.salesforceSingleWriteRequestBody(outbound),
      '{"External_Key__c":"key-1"}');
    const requestCid = checked(salesforceMoon.salesforceSingleWriteRequestCid(
      outbound, binding.resourceOrigin, 2048));
    assert.match(requestCid, /^sha256:[0-9a-f]{64}$/);
    assert.notEqual(requestCid, checked(
      salesforceMoon.salesforceSingleWriteRequestCid(
        outbound, 'https://other.invalid', 2048)));
    const response = checked(salesforceMoon.salesforceProjectSingleWriteSuccess(
      outbound, 201, Buffer.from(JSON.stringify({
        id: 'a00123456789012', success: true, errors: [],
      })), 1024, 32, 5));
    const projectionResult = checked(
      salesforceMoon.salesforceSingleWriteSuccessProjection(response));
    assert.deepEqual([projectionResult[0], projectionResult[1]],
      ['a00123456789012', 'created']);
    assert.match(projectionResult[2], /^[0-9a-f]{64}$/);
    assert.throws(() => checked(
      salesforceMoon.salesforceProjectSingleWriteSuccess(
        outbound, 200, Buffer.from(JSON.stringify({
          id: 'a00123456789012', success: true, errors: [],
        })), 1024, 32, 5)), {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(salesforceMoon.salesforcePrepareWriteProjection(
      result.observation,
      binding.tenant, binding.principal, binding.environment,
      'foreign-connection', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
      0, '', ['External_Key__c'], 2)), {code: 'MoonBitHostFailure'});
  });

test('Site sends one scoped Salesforce write and keeps response as observation',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      catalog.observation,
      binding.tenant, binding.principal, binding.environment,
      'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
      0, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"key-1"}'),
      1024, 32, 5));
    const outbound = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
      body, 'v62.0', 0, '', 0, 256, 128, 1024));
    const options = {
      moon: salesforceMoon,
      request: outbound,
      currentObservation: catalog.observation,
      authorization: {...setup.write, useId: 'write-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 32, maxDepth: 5},
    };
    assert.equal(salesforceMoon.salesforceSingleWriteRequestGrantOperation(
      outbound), 'salesforce:record:create');
    await assert.rejects(writeSalesforceSingleRecord({
      ...options,
      authorization: {...setup.write, useId: 'foreign-write-use',
        scope: {...setup.write.scope, siteGeneration: 5}},
    }), {code: 'ForeignSalesforceSingleWrite'});
    assert.equal(setup.seen.filter(item => item.method === 'POST').length, 0);
    const result = await writeSalesforceSingleRecord(options);
    assert.equal(result.kind, 'typed-success-response');
    assert.deepEqual([result.result[0], result.result[1]],
      ['a00123456789012', 'created']);
    assert.equal(result.observation.statusCode, 201);
    assert.equal(setup.journal.inspect(result.observation.useCid).outcome,
      'succeeded');
    assert.deepEqual(setup.seen.filter(item => item.method === 'POST').map(
      item => [item.path, item.body]), [[
      '/services/data/v62.0/sobjects/Test_Record__c/',
      '{"External_Key__c":"key-1"}',
    ]]);
  });

test('Salesforce request CID binds the exact HTTPS upsert request-target',
  async t => {
    const metadata = JSON.stringify({name: 'Test_Record__c',
      queryable: true, createable: true, updateable: true, fields: [
        {name: 'External_Key__c', type: 'string', externalId: true,
          unique: true, caseSensitive: true, nillable: false,
          defaultedOnCreate: false,
          createable: true, updateable: true},
        {name: 'Name', type: 'string', nillable: false,
          defaultedOnCreate: false, createable: true, updateable: true},
      ]});
    const prefix = '/services/data/v62.0/sobjects/' +
      'Test_Record__c/External_Key__c/';
    for (const [name, target, suffix] of [
      ['dot', '.', '.'],
      ['dot-dot', '..', '..'],
      ['ordinary dot', 'a.b', 'a.b'],
      ['encoded-dot text', '%2E', '%252E'],
      ['slash', 'a/b', 'a%2Fb'],
      ['percent', '100%', '100%25'],
      ['unicode', 'é', '%C3%A9'],
      ['query and hash text', 'a?b#c', 'a%3Fb%23c'],
    ]) {
      await t.test(name, async child => {
        const setup = await fixture(child, {customResponse: metadata});
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation,
            binding.tenant, binding.principal, binding.environment,
            'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
            binding.connectorRegistration, binding.connectorRevision,
            binding.resourceOrigin, binding.runInvocationCid,
            binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
            2, 'External_Key__c', ['Name'], 2));
        const body = checked(salesforceMoon.salesforcePrepareWriteBody(
          projection, Buffer.from('{"Name":"new value"}'), 1024, 32, 5));
        const outbound = checked(
          salesforceMoon.salesforcePrepareSingleWriteRequest(
            body, 'v62.0', 2, target, 0, 256, 128, 1024));
        const requestTarget = checked(
          salesforceMoon.salesforceSingleWriteRequestTargetIdentity(
            outbound, 4096));
        const admittedTarget = checked(
          salesforceMoon.salesforcePrepareWriteTargetIdentity(
            projection, 2, target, 0, 128, 4096));
        assert.equal(salesforceMoon.salesforceWriteTargetObjectCid(
          requestTarget), salesforceMoon.salesforceWriteTargetObjectCid(
          admittedTarget));
        const expectedPath = prefix + suffix;
        const expectedBody = '{"Name":"new value"}';
        assert.equal(salesforceMoon.salesforceSingleWriteRequestPath(outbound),
          expectedPath);
        const requestCid = checked(
          salesforceMoon.salesforceSingleWriteRequestCid(
            outbound, binding.resourceOrigin, 4096));
        const independentPreimage = JSON.stringify({body: expectedBody,
          method: 'PATCH', path: expectedPath,
          resource_origin: binding.resourceOrigin,
          version: 'actql-salesforce-rest-request/0.1'});
        assert.equal(requestCid, `sha256:${createHash('sha256')
          .update(independentPreimage).digest('hex')}`);
        const effect = runtimeCore(commonMoon).effectApplicationControl;
        const authorityScopeCid = cid('8');
        const scope = effect.logicalRequestScope(authorityScopeCid,
          `exact-target-${name}`, 128);
        const key = effect.dispatchKey(scope, cid('7'), '"row-1"', 32, 8, 3);
        const locator = effect.logicalItemLocator(scope, 'program-1',
          'node-1', 'UpsertOne', JSON.stringify({target}), 64, 128, 8, 3);
        const basis = effect.ledgerBasis(scope, locator, key,
          cid('6'), cid('5'), cid('4'), requestCid, cid('3'),
          'unavailable', cid('2'), cid('1'));
        const claim = {scope, locator, key, basis,
          intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
        const ledgerRoot = await mkdtemp(join(tmpdir(),
          'actql-salesforce-exact-target-'));
        child.after(() => rm(ledgerRoot, {recursive: true, force: true}));
        const ledger = openEffectLedger({moon: commonMoon, root: ledgerRoot,
          authorityScopeCid, callerRequestId: `exact-target-${name}`,
          maxEntryBytes: 4096});
        child.after(() => ledger.close());
        const result = await captureSalesforceSingleEffectWrite({
          ledger, claim, moon: salesforceMoon, request: outbound,
          currentObservation: catalog.observation,
          authorization: {...setup.writeUpsert, useId: 'exact-target-use'},
          credential: setup.credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 32, maxDepth: 5},
        });
        assert.equal(result.claimed, true);
        assert.equal(result.physical.kind, 'provider-response');
        assert.ok(ledger.current(effect.logicalItemLocatorCid(locator)));
        assert.deepEqual(setup.seen.filter(item => item.method === 'PATCH')
          .map(item => ({method: item.method, path: item.path,
            body: item.body})), [
          {method: 'PATCH', path: expectedPath, body: expectedBody},
        ]);
      });
    }
  });

test('Host claim owns one local HTTPS write', async t => {
  const setup = await fixture(t);
  const catalog = await syncSalesforceCatalog(request(setup));
  const binding = setup.list.scope;
  const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
    catalog.observation,
    binding.tenant, binding.principal, binding.environment,
    'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
    binding.connectorRegistration, binding.connectorRevision,
    binding.resourceOrigin, binding.runInvocationCid,
    binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
    0, '', ['External_Key__c'], 2));
  const body = checked(salesforceMoon.salesforcePrepareWriteBody(
    projection, Buffer.from('{"External_Key__c":"key-1"}'),
    1024, 32, 5));
  const outbound = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
    body, 'v62.0', 0, '', 0, 256, 128, 1024));
  const requestCid = checked(salesforceMoon.salesforceSingleWriteRequestCid(
    outbound, binding.resourceOrigin, 4096));
  const effect = runtimeCore(commonMoon).effectApplicationControl;
  const authorityScopeCid = cid('8');
  const scope = effect.logicalRequestScope(authorityScopeCid,
    'salesforce-business-request', 128);
  const key = effect.dispatchKey(scope, cid('7'), '"row-1"', 32, 8, 3);
  const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
    'CreateOne', '{"row":"key-1"}', 64, 128, 8, 3);
  const basis = effect.ledgerBasis(scope, locator, key,
    cid('6'), cid('5'), cid('4'), requestCid, cid('3'),
    'unavailable', cid('2'), cid('1'));
  const claim = {scope, locator, key, basis,
    intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
  const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-effect-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const open = () => openEffectLedger({moon: commonMoon, root,
    authorityScopeCid, callerRequestId: 'salesforce-business-request',
    maxEntryBytes: 4096});
  const options = {claim, moon: salesforceMoon, request: outbound,
    currentObservation: catalog.observation,
    authorization: {...setup.write, useId: 'effect-write-use'},
    credential: setup.credential,
    limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
      maxNodes: 32, maxDepth: 5}};
  const first = open();
  t.after(() => first.close());
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    claim: {...claim, canonicalRequestCid: cid('9')},
  }), {code: 'InvalidEffectPhysicalDispatch'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    authorization: {...options.authorization,
      scope: {...options.authorization.scope, siteGeneration: 5}},
  }), {code: 'ForeignSalesforceEffectWrite'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    authorization: {...options.authorization, grant: undefined},
  }), {code: 'ForeignSalesforceEffectWrite'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    credential: {...options.credential, orgId: '00D000000000002EAA'},
  }), {code: 'ForeignSalesforceEffectWrite'});
  const foreignResolver = async () => 'test-only-secret';
  foreignResolver.connectionOrgId = '00D000000000002EAA';
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    credential: {...options.credential, resolveSecret: foreignResolver},
  }), {code: 'ForeignSalesforceEffectWrite'});
  assert.equal(first.current(effect.logicalItemLocatorCid(locator)), undefined);
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 0);
  const sent = await captureSalesforceSingleEffectWrite({
    ...options, ledger: first});
  assert.equal(sent.claimed, true);
  assert.equal(sent.physical.kind, 'typed-success-response');
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
  assert.deepEqual(sent.response.responseBytes,
    Buffer.from(JSON.stringify({id: 'a00123456789012',
      success: true, errors: []})));
  first.close();
  const restarted = open();
  t.after(() => restarted.close());
  const retry = await captureSalesforceSingleEffectWrite({
    ...options, ledger: restarted});
  assert.equal(retry.claimed, false);
  assert.equal(retry.ownership.action, 3);
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
});

test('Site does not promote rejected or malformed writes to Effect success',
  async t => {
    for (const scenario of [
      {writeStatus: 429, writeResponse: JSON.stringify([
        {errorCode: 'REQUEST_LIMIT_EXCEEDED'},
      ]), expected: 'provider-response'},
      {writeStatus: 201, writeResponse: '{"success":true}',
        expected: 'unclassified-response'},
    ]) {
      await t.test(scenario.expected, async child => {
        const setup = await fixture(child, scenario);
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation,
            binding.tenant, binding.principal, binding.environment,
            'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
            binding.connectorRegistration, binding.connectorRevision,
            binding.resourceOrigin, binding.runInvocationCid,
            binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
            0, '', ['External_Key__c'], 2));
        const body = checked(salesforceMoon.salesforcePrepareWriteBody(
          projection, Buffer.from('{"External_Key__c":"key-1"}'),
          1024, 32, 5));
        const outbound = checked(
          salesforceMoon.salesforcePrepareSingleWriteRequest(
            body, 'v62.0', 0, '', 0, 256, 128, 1024));
        const result = await writeSalesforceSingleRecord({
          moon: salesforceMoon,
          request: outbound,
          currentObservation: catalog.observation,
          authorization: {...setup.write, useId: 'write-use'},
          credential: setup.credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 32, maxDepth: 5},
        });
        assert.equal(result.kind, scenario.expected);
        assert.equal(result.observation.statusCode, scenario.writeStatus);
        assert.equal(setup.seen.filter(item => item.method === 'POST').length,
          1);
      });
    }
  });

test('Site Collections preserve exact row order and partial outcomes',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(
      salesforceMoon.salesforcePrepareWriteProjection(
        catalog.observation,
        binding.tenant, binding.principal, binding.environment,
        'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
        binding.connectorRegistration, binding.connectorRevision,
        binding.resourceOrigin, binding.runInvocationCid,
        binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
        0, '', ['External_Key__c'], 2));
    const first = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"key-1"}'),
      1024, 32, 5));
    const second = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"key-2"}'),
      1024, 32, 5));
    const outbound = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        [cid('1'), cid('2')], [first, second], [0, 0], ['', ''],
        [0, 0], 'v62.0', 256, 128, 1024, 64, 6, 200));
    assert.equal(salesforceMoon.salesforceCollectionWriteRequestGrantOperation(
      outbound), 'salesforce:record:create');
    assert.equal(salesforceMoon.salesforceCollectionWriteRequestRowCid(
      outbound, 1), cid('2'));
    const restBody = '{"allOrNone":false,"records":[' +
      '{"External_Key__c":"key-1","attributes":{"type":' +
      '"Test_Record__c"}},{"External_Key__c":"key-2",' +
      '"attributes":{"type":"Test_Record__c"}}]}';
    const requestPreimage = JSON.stringify({
      body: restBody,
      method: 'POST',
      path: '/services/data/v62.0/composite/sobjects',
      resource_origin: binding.resourceOrigin,
      row_preview_cids: [cid('1'), cid('2')],
      version: 'actql-salesforce-collection-request/0.1',
    });
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteRequestCid(
      outbound, binding.resourceOrigin, 4096)),
    `sha256:${createHash('sha256').update(requestPreimage).digest('hex')}`);
    const swapped = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        [cid('2'), cid('1')], [first, second], [0, 0], ['', ''],
        [0, 0], 'v62.0', 256, 128, 1024, 64, 6, 200));
    assert.notEqual(checked(salesforceMoon.salesforceCollectionWriteRequestCid(
      swapped, binding.resourceOrigin, 4096)),
    checked(salesforceMoon.salesforceCollectionWriteRequestCid(
      outbound, binding.resourceOrigin, 4096)));
    const options = {
      moon: salesforceMoon,
      request: outbound,
      currentObservation: catalog.observation,
      authorization: {...setup.write, useId: 'collection-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 64, maxDepth: 6, maxRows: 200},
    };
    const priorUses = setup.journal.recover().length;
    await assert.rejects(writeSalesforceContinueCollection({
      ...options, limits: {...options.limits, maxRows: 1},
    }), {code: 'SalesforceCollectionRowLimitExceeded'});
    assert.equal(setup.journal.recover().length, priorUses);
    await assert.rejects(writeSalesforceContinueCollection({
      ...options,
      authorization: {...setup.write, useId: 'foreign-collection-use',
        scope: {...setup.write.scope, siteGeneration: 5}},
    }), {code: 'ForeignSalesforceCollectionWrite'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 0);
    const result = await writeSalesforceContinueCollection(options);
    assert.equal(result.kind, 'typed-row-response');
    assert.equal(result.rowCount, 2);
    assert.equal(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      result.result, 0), true);
    assert.equal(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      result.result, 1), false);
    assert.equal(setup.journal.inspect(result.observation.useCid).outcome,
      'succeeded');
    assert.deepEqual(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).map(item => [item.method, item.body]), [[
      'POST', restBody,
    ]]);
  });

test('Host custody binds one HTTPS Collections response to every row',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(
      salesforceMoon.salesforcePrepareWriteProjection(
        catalog.observation,
        binding.tenant, binding.principal, binding.environment,
        'connection-revision-a', '00D000000000001EAA',
        binding.siteKey, binding.siteGeneration,
        binding.connectorRegistration, binding.connectorRevision,
        binding.resourceOrigin, binding.runInvocationCid,
        binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
        0, '', ['External_Key__c'], 2));
    const bodies = ['key-1', 'key-2'].map(key => checked(
      salesforceMoon.salesforcePrepareWriteBody(projection,
        Buffer.from(JSON.stringify({External_Key__c: key})),
        1024, 32, 5)));
    const rowCids = [cid('1'), cid('2')];
    const outbound = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        rowCids, bodies, [0, 0], ['', ''], [0, 0], 'v62.0',
        256, 128, 1024, 64, 6, 200));
    const requestCid = checked(
      salesforceMoon.salesforceCollectionWriteRequestCid(
        outbound, binding.resourceOrigin, 4096));
    const effect = runtimeCore(commonMoon).effectApplicationControl;
    const authorityScopeCid = cid('8');
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'collection-business-request', 128);
    const claims = rowCids.map((rowCid, index) => {
      assert.equal(salesforceMoon.salesforceCollectionWriteRequestRowCid(
        outbound, index), rowCid);
      const key = effect.dispatchKey(scope, cid('7'),
        JSON.stringify(rowCid), 128, 8, 3);
      const locator = effect.logicalItemLocator(scope, 'program-1',
        'node-1', 'CreateTwo', JSON.stringify({row_preview_cid: rowCid}),
        64, 128, 8, 3);
      const basis = effect.ledgerBasis(scope, locator, key,
        cid('6'), cid('5'), cid('4'), requestCid, cid('3'),
        'unavailable', cid('2'), cid('1'));
      return {scope, locator, key, basis,
        intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
    });
    const root = await mkdtemp(join(tmpdir(),
      'actql-salesforce-collection-effect-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const open = () => openEffectLedger({moon: commonMoon, root,
      authorityScopeCid, callerRequestId: 'collection-business-request',
      maxEntryBytes: 4096});
    const execute = () => writeSalesforceContinueCollection({
      moon: salesforceMoon, request: outbound,
      currentObservation: catalog.observation,
      authorization: {...setup.write, useId: 'collection-effect-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 64, maxDepth: 6, maxRows: 200},
    });
    const first = open();
    t.after(() => first.close());
    const sent = await captureClaimedEffectCollectionResponse({
      ledger: first, claims, requestCid, execute,
    });
    assert.equal(sent.claimed, true);
    assert.equal(sent.physical.kind, 'typed-row-response');
    assert.equal(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      sent.physical.result, 0), true);
    assert.equal(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      sent.physical.result, 1), false);
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 1);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: restarted, claims, requestCid, execute,
    });
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.ownership.actions, [3, 3]);
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 1);
    for (const dispatching of sent.ownership.dispatching) {
      assert.deepEqual(restarted.response(
        effect.ledgerEntryCid(dispatching)).responseBytes,
      sent.physical.observation.body);
    }
  });

test('Site Collections do not turn malformed or rejected HTTP into success',
  async t => {
    for (const scenario of [
      {collectionStatus: 429, collectionResponse: '[]',
        expected: 'provider-response'},
      {collectionStatus: 200, collectionResponse: '[]',
        expected: 'unclassified-response'},
      {collectionStatus: 201, collectionResponse: JSON.stringify([
        {id: 'a00123456789012', success: true, errors: []},
      ]), expected: 'unclassified-response'},
    ]) {
      await t.test(scenario.expected, async child => {
        const setup = await fixture(child, scenario);
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation,
            binding.tenant, binding.principal, binding.environment,
            'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
            binding.connectorRegistration, binding.connectorRevision,
            binding.resourceOrigin, binding.runInvocationCid,
            binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
            0, '', ['External_Key__c'], 2));
        const body = checked(salesforceMoon.salesforcePrepareWriteBody(
          projection, Buffer.from('{"External_Key__c":"key-1"}'),
          1024, 32, 5));
        const outbound = checked(
          salesforceMoon.salesforcePrepareContinueWriteCollection(
            [cid('1')], [body], [0], [''], [0], 'v62.0',
            256, 128, 1024, 64, 6, 200));
        const result = await writeSalesforceContinueCollection({
          moon: salesforceMoon, request: outbound,
          currentObservation: catalog.observation,
          authorization: {...setup.write, useId: 'collection-use'},
          credential: setup.credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 64, maxDepth: 6, maxRows: 200},
        });
        assert.equal(result.kind, scenario.expected);
        assert.equal(setup.seen.filter(item => item.path?.endsWith(
          '/composite/sobjects')).length, 1);
      });
    }
  });

test('Site Collections use exact update and external-ID upsert authority',
  async t => {
    const metadata = JSON.stringify({name: 'Test_Record__c', queryable: true,
      createable: true, updateable: true, fields: [
        {name: 'External_Key__c', type: 'string', externalId: true,
          unique: true, caseSensitive: true, nillable: false,
          defaultedOnCreate: false,
          createable: true, updateable: true},
        {name: 'Name', type: 'string', nillable: false,
          defaultedOnCreate: false, createable: true, updateable: true},
      ]});
    for (const scenario of [
      {name: 'update', operation: 1, external: '', targetCode: 1,
        target: 'a00123456789012', method: 'PATCH',
        path: '/services/data/v62.0/composite/sobjects',
        targetField: 'Id', authorization: 'writeUpdate',
        response: [{id: 'a00123456789012', success: true, errors: []}]},
      {name: 'upsert', operation: 2, external: 'External_Key__c',
        targetCode: 2, target: 'key-1', method: 'PATCH',
        path: '/services/data/v62.0/composite/sobjects/' +
          'Test_Record__c/External_Key__c',
        targetField: 'External_Key__c', authorization: 'writeUpsert',
        response: [{id: 'a00123456789012', created: false,
          success: true, errors: []}]},
    ]) {
      await t.test(scenario.name, async child => {
        const setup = await fixture(child, {customResponse: metadata,
          collectionResponse: JSON.stringify(scenario.response)});
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation,
            binding.tenant, binding.principal, binding.environment,
            'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
            binding.connectorRegistration, binding.connectorRevision,
            binding.resourceOrigin, binding.runInvocationCid,
            binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
            scenario.operation, scenario.external, ['Name'], 2));
        const body = checked(salesforceMoon.salesforcePrepareWriteBody(
          projection, Buffer.from('{"Name":"new value"}'),
          1024, 32, 5));
        const outbound = checked(
          salesforceMoon.salesforcePrepareContinueWriteCollection(
            [cid('1')], [body], [scenario.targetCode], [scenario.target],
            [0], 'v62.0', 256, 128, 1024, 64, 6, 200));
        const requestTarget = checked(
          salesforceMoon.salesforceCollectionWriteRequestTargetIdentity(
            outbound, 0, 4096));
        const admittedTarget = checked(
          salesforceMoon.salesforcePrepareWriteTargetIdentity(
            projection, scenario.targetCode, scenario.target, 0, 128,
            4096));
        assert.equal(salesforceMoon.salesforceWriteTargetObjectCid(
          requestTarget), salesforceMoon.salesforceWriteTargetObjectCid(
          admittedTarget));
        assert.throws(() => checked(
          salesforceMoon.salesforceCollectionWriteRequestTargetIdentity(
            outbound, 1, 4096)));
        const result = await writeSalesforceContinueCollection({
          moon: salesforceMoon, request: outbound,
          currentObservation: catalog.observation,
          authorization: {...setup[scenario.authorization],
            useId: `collection-${scenario.name}`},
          credential: setup.credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 64, maxDepth: 6, maxRows: 200},
        });
        assert.equal(result.kind, 'typed-row-response');
        assert.equal(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
          result.result, 0), true);
        const writes = setup.seen.filter(item => item.method === 'PATCH');
        assert.deepEqual(writes.map(item => [item.method, item.path]), [[
          scenario.method, scenario.path,
        ]]);
        assert.equal(JSON.parse(writes[0].body).allOrNone, false);
        assert.equal(JSON.parse(writes[0].body).records[0]
          [scenario.targetField], scenario.target);
        assert.equal(setup.journal.inspect(result.observation.useCid).outcome,
          'succeeded');
      });
    }
  });

test('Salesforce target aliases fail before a collection claim or HTTP write',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(
      salesforceMoon.salesforcePrepareWriteProjection(
        catalog.observation,
        binding.tenant, binding.principal, binding.environment,
        'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
        binding.connectorRegistration, binding.connectorRevision,
        binding.resourceOrigin, binding.runInvocationCid,
        binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
        1, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"changed"}'),
      1024, 32, 5));
    const usesBefore = setup.journal.recover().length;
    assert.throws(() => checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        [cid('1'), cid('2')], [body, body], [1, 1],
        ['001000000000001', '001000000000001AAA'], [0, 0],
        'v62.0', 256, 128, 1024, 64, 6, 200)));
    assert.equal(setup.journal.recover().length, usesBefore);
    assert.equal(setup.seen.filter(item => item.method === 'PATCH').length, 0);
  });

test('Salesforce target identities feed the common Effect Set preflight',
  async t => {
    const setup = await fixture(t);
    const secondConnection = await fixture(t);
    const foreignOrg = await fixture(t, {orgId: '00D000000000002EAA'});
    const catalogs = new Map();
    const target = async (connection, operation, value) => {
      if (!catalogs.has(connection)) {
        catalogs.set(connection, await syncSalesforceCatalog(
          request(connection)));
      }
      const catalog = catalogs.get(connection);
      const binding = connection.list.scope;
      const projection = checked(
        salesforceMoon.salesforcePrepareWriteProjection(
          catalog.observation,
          binding.tenant, binding.principal, binding.environment,
          'connection-revision-a', connection.orgId,
          binding.siteKey, binding.siteGeneration,
          binding.connectorRegistration, binding.connectorRevision,
          binding.resourceOrigin, binding.runInvocationCid,
          binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
          operation === 'record' ? 1 : 2,
          operation === 'record' ? '' : 'External_Key__c',
          ['External_Key__c'], 2));
      return checked(salesforceMoon.salesforcePrepareWriteTargetIdentity(
        projection, operation === 'record' ? 1 : 2, value, 0, 128, 4096));
    };
    const first = await target(setup, 'record', '001000000000001');
    const alias = await target(secondConnection, 'record',
      '001000000000001AAA');
    const other = await target(secondConnection, 'record',
      '001000000000002');
    const differentOrg = await target(foreignOrg, 'record',
      '001000000000001AAA');
    const boundary = salesforceMoon.salesforceWriteTargetBoundaryCid(first);
    const scheme = salesforceMoon.salesforceWriteTargetSchemeCid(first);
    const preflight = second => runtimeCore(commonMoon)
      .effectApplicationControl.checkSetFootprintConflicts(
        ['first', 'second'], [0, 0], ['salesforce', 'salesforce'],
        [boundary, salesforceMoon.salesforceWriteTargetBoundaryCid(second)],
        [scheme, salesforceMoon.salesforceWriteTargetSchemeCid(second)],
        ['Test_Record__c', 'Test_Record__c'],
        [[salesforceMoon.salesforceWriteTargetObjectCid(first)],
          [salesforceMoon.salesforceWriteTargetObjectCid(second)]],
        2, 2, 20);
    assert.throws(() => preflight(alias));
    assert.equal(preflight(other), true);
    assert.equal(preflight(differentOrg), true);
    assert.notEqual(setup.list.scope.resourceOrigin,
      secondConnection.list.scope.resourceOrigin);
    for (const connection of [setup, secondConnection, foreignOrg]) {
      assert.equal(connection.seen.filter(item => item.method === 'PATCH')
        .length, 0);
    }
  });

test('Effect Set preflight uses observed external-ID matching rules',
  async t => {
    const upsertMetadata = JSON.parse(customBody);
    upsertMetadata.fields.push({name: 'Value__c', type: 'string',
      nillable: true, defaultedOnCreate: false,
      createable: true, updateable: true});
    const prepare = async (caseSensitive, firstValue, secondValue) => {
      const setup = await fixture(t, {customResponse: JSON.stringify(
        upsertMetadata).replace(
        '"caseSensitive":true',
        `"caseSensitive":${caseSensitive}`)});
      const catalog = await syncSalesforceCatalog(request(setup));
      const binding = setup.list.scope;
      const projection = checked(
        salesforceMoon.salesforcePrepareWriteProjection(
          catalog.observation,
          binding.tenant, binding.principal, binding.environment,
          'connection-revision-a', setup.orgId,
          binding.siteKey, binding.siteGeneration,
          binding.connectorRegistration, binding.connectorRevision,
          binding.resourceOrigin, binding.runInvocationCid,
          binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
          2, 'External_Key__c', ['Value__c'], 2));
      const target = value => checked(
        salesforceMoon.salesforcePrepareWriteTargetIdentity(
          projection, 2, value, 0, 128, 4096));
      const first = target(firstValue);
      const second = target(secondValue);
      const boundary = salesforceMoon.salesforceWriteTargetBoundaryCid(first);
      const scheme = salesforceMoon.salesforceWriteTargetSchemeCid(first);
      const preflight = () => runtimeCore(commonMoon)
        .effectApplicationControl.checkSetFootprintConflicts(
          ['first', 'second'], [0, 0], ['salesforce', 'salesforce'],
          [boundary, salesforceMoon.salesforceWriteTargetBoundaryCid(second)],
          [scheme, salesforceMoon.salesforceWriteTargetSchemeCid(second)],
          ['Test_Record__c', 'Test_Record__c'],
          [[salesforceMoon.salesforceWriteTargetObjectCid(first)],
            [salesforceMoon.salesforceWriteTargetObjectCid(second)]],
          2, 2, 20);
      return {setup, preflight};
    };
    const insensitive = await prepare(false, 'ABC123', 'abc123');
    assert.throws(() => insensitive.preflight());
    const sensitive = await prepare(true, 'ABC123', 'abc123');
    assert.equal(sensitive.preflight(), true);
    for (const {setup} of [insensitive, sensitive]) {
      assert.equal(setup.seen.filter(item => item.method === 'PATCH')
        .length, 0);
    }
  });

test('CLI alias supplies only Site secret for the authorized HTTPS path',
  async t => {
    const setup = await fixture(t);
    const origin = setup.list.scope.resourceOrigin;
    let displays = 0;
    let tokenCalls = 0;
    const resolveSecret = createSalesforceCliSecretResolver({
      connection: {alias: 'actql-test', orgId: '00D000000000001EAA',
        username: 'test@example.invalid', instanceOrigin: origin},
      principal: 'principal-a', tenant: 'tenant-a', environment: 'test',
      siteKey: 'site-a', siteGeneration: 4,
      invoke: async (_executable, args) => {
        if (args[1] === 'auth') {
          assert.deepEqual(args, ['org', 'auth', 'show-access-token',
            '--target-org', 'test@example.invalid', '--json']);
          tokenCalls++;
          return {stdout: JSON.stringify({status: 0,
            result: {accessToken: 'test-only-secret'}})};
        }
        assert.deepEqual(args, ['org', 'display', '--target-org',
          'actql-test', '--json']);
        displays++;
        return {stdout: JSON.stringify({status: 0, result: {
          alias: 'actql-test', id: '00D000000000001EAA',
          username: 'test@example.invalid', instanceUrl: origin,
          accessToken: '(redacted)',
        }})};
      },
    });
    assert.equal(resolveSecret.connectionOrgId, '00D000000000001EAA');
    const result = await syncSalesforceCatalog(request(setup, {
      credential: {...setup.credential, resolveSecret},
    }));
    assert.equal(result.status, 'complete');
    assert.equal(displays, 2);
    assert.equal(tokenCalls, 1);
    assert.equal(setup.seen.length, 3);
    assert.ok(setup.seen.every(entry =>
      entry.authorization === 'Bearer test-only-secret'));
    assert.doesNotMatch(await readFile(setup.journal.path, 'utf8'),
      /test-only-secret/u);
  });

test('retargeted CLI alias cannot send an authorized catalog request',
  async t => {
    const setup = await fixture(t);
    const resolveSecret = createSalesforceCliSecretResolver({
      connection: {alias: 'actql-test', orgId: '00D000000000001EAA',
        username: 'test@example.invalid',
        instanceOrigin: setup.list.scope.resourceOrigin},
      principal: 'principal-a', tenant: 'tenant-a', environment: 'test',
      siteKey: 'site-a', siteGeneration: 4,
      invoke: async () => ({stdout: JSON.stringify({status: 0, result: {
        alias: 'actql-test', id: '00D000000000002EAA',
        username: 'test@example.invalid',
        instanceUrl: setup.list.scope.resourceOrigin,
        accessToken: 'test-only-secret',
      }})}),
    });
    await assert.rejects(syncSalesforceCatalog(request(setup, {
      credential: {...setup.credential, resolveSecret},
    })), {code: 'SalesforceCliConnectionMismatch'});
    assert.equal(setup.seen.length, 0);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome),
      ['failed']);
  });

test('rate-limited describe remains partial with its physical use failed',
  async t => {
    const setup = await fixture(t, {customStatus: 403,
      customResponse: '[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]'});
    const result = await syncSalesforceCatalog(request(setup));
    assert.equal(result.status, 'partial');
    assert.deepEqual(JSON.parse(result.observationJson).listed_resources.map(
      entry => entry.outcome), ['described', 'rate_limited']);
    assert.equal(JSON.parse(result.observationJson).listed_resources[1]
      .response_sha256, createHash('sha256')
      .update('[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]')
      .digest('hex'));
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Account'), 1);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), 3);
    assert.equal(setup.journal.inspect(result.describeUseCids[1]).outcome,
      'failed');
    assert.equal(setup.seen.length, 3);
  });

test('foreign Site generation is rejected before a describe request',
  async t => {
    const setup = await fixture(t);
    const result = await syncSalesforceCatalog(request(setup, {
      authorizationForDescribe: async name => ({
        ...setup.describe,
        scope: {...setup.describe.scope, siteGeneration: 5},
        useId: `foreign-${name}`,
      }),
    }));
    assert.equal(result.status, 'interrupted');
    assert.deepEqual(JSON.parse(result.observationJson).listed_resources.map(
      entry => entry.use_cid === null), [true, true]);
    assert.equal(result.interruptionCode, 'ForeignSalesforceCatalogBinding');
    assert.equal(setup.seen.length, 1);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Account'), 7);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), 7);
  });

test('invalid describe does not become a completed resource',
  async t => {
    const setup = await fixture(t, {customResponse: '{"name":"Wrong"}'});
    const result = await syncSalesforceCatalog(request(setup));
    assert.equal(result.status, 'partial');
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), 6);
    assert.equal(setup.seen.length, 3);
  });

test('cancellation preserves the first resource and stops later HTTPS I/O',
  async t => {
    const setup = await fixture(t);
    const controller = new AbortController();
    const result = await syncSalesforceCatalog(request(setup, {
      signal: controller.signal,
      authorizationForDescribe: async name => {
        if (name === 'Test_Record__c') controller.abort();
        return {...setup.describe, useId: `describe-${name}`};
      },
    }));
    assert.equal(result.status, 'interrupted');
    assert.equal(result.interruptionCode, 'SalesforceCatalogCancelled');
    assert.equal(setup.seen.length, 2);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Account'), 1);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), 7);
  });

test('truncated discovery never requests or implies an unseen describe',
  async t => {
    const setup = await fixture(t);
    const result = await syncSalesforceCatalog(request(setup, {
      listLimits: {...listLimits, maxSelected: 1},
    }));
    assert.equal(result.status, 'partial');
    assert.equal(setup.seen.length, 2);
    assert.equal(salesforceMoon.salesforceCatalogResourceState(
      result.sync, 'Test_Record__c'), -1);
  });

test('list rejection keeps the provider reason without starting describes',
  async t => {
    const setup = await fixture(t, {listStatus: 403,
      listResponse: '[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]'});
    await assert.rejects(
      syncSalesforceCatalog(request(setup)),
      {code: 'SalesforceCatalogListRejected', reason: 1},
    );
    assert.equal(setup.seen.length, 1);
  });

async function queryProjection(setup) {
  const catalog = await syncSalesforceCatalog(request(setup));
  const binding = setup.list.scope;
  return checked(salesforceMoon.salesforcePrepareReadProjection(
    catalog.observation,
    binding.tenant, binding.principal, binding.environment,
    'connection-revision-a', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
    binding.connectorRegistration, binding.connectorRevision,
    binding.resourceOrigin, binding.runInvocationCid,
    binding.dispatchRequestCid, 'catalog-sync-a', 'Account', ['Id'], 100));
}

const queryLimits = Object.freeze({maxBytes: 4096, maxNodes: 100,
  maxDepth: 10, maxRows: 2, maxLocatorUnits: 128,
  maxPages: 3, maxTotalRows: 4});

function queryRequest(setup, plan, overrides = {}) {
  return {
    moon: salesforceMoon,
    plan,
    apiVersion: 'v62.0',
    initialAuthorization: {...setup.query, useId: 'query-initial'},
    authorizationForPage: async () => ({
      ...setup.query, useId: 'query-continuation',
    }),
    credential: setup.credential,
    refreshCatalog: request(setup, {
      syncOccurrence: 'catalog-refresh',
      listAuthorization: {...setup.list, useId: 'refresh-list'},
      authorizationForDescribe: async name => ({
        ...setup.describe, useId: `refresh-describe-${name}`,
      }),
    }),
    limits: queryLimits,
    consumePage: async () => {},
    ...overrides,
  };
}

test('Site HTTPS query follows the exact locator with bounded page delivery',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    assert.notEqual(setup.query.scope.dispatchRequestCid,
      setup.list.scope.dispatchRequestCid);
    const delivered = [];
    const result = await readSalesforceQuery(queryRequest(setup, plan, {
      consumePage: async (page, context) => {
        delivered.push({index: context.pageIndex,
          rows: salesforceMoon.salesforceQueryPageRowCount(page)});
      },
    }));
    assert.deepEqual(delivered, [{index: 0, rows: 1},
      {index: 1, rows: 1}]);
    assert.equal(result.rowCount, 2n);
    assert.notEqual(result.currentCatalog.observationCid,
      salesforceMoon.salesforceReadProjectionObservationCid(plan));
    assert.equal(result.pages.length, 2);
    assert.deepEqual(setup.seen.slice(-2).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
    assert.equal(setup.journal.inspect(result.pages[0].useCid).outcome,
      'succeeded');
    assert.equal(setup.journal.inspect(result.pages[1].useCid).outcome,
      'succeeded');
    assert.ok(result.pages.every(entry => entry.responseSha256.length === 64));
  });

test('page ceiling rejects a locator before HTTP or credential use',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    let delivered = 0;
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      limits: {...queryLimits, maxPages: 1},
      consumePage: async () => { delivered += 1; },
    })), {code: 'MoonBitHostFailure'});
    assert.equal(delivered, 1);
    assert.deepEqual(setup.seen.filter(entry =>
      entry.path?.includes('/query')).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
    ]);
    assert.deepEqual(setup.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).map(entry => entry.useId),
    ['query-initial']);
  });

test('terminal first page and exact two-page ceiling both complete',
  async t => {
    const single = await fixture(t, {queryFirstResponse: JSON.stringify({
      totalSize: 1, done: true, records: [{Id: '001A'}],
    })});
    const singlePlan = await queryProjection(single);
    const one = await readSalesforceQuery(queryRequest(single, singlePlan, {
      limits: {...queryLimits, maxPages: 1},
    }));
    assert.equal(one.rowCount, 1n);
    assert.equal(single.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
    assert.equal(single.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).length, 1);

    const double = await fixture(t);
    const doublePlan = await queryProjection(double);
    const two = await readSalesforceQuery(queryRequest(double, doublePlan, {
      limits: {...queryLimits, maxPages: 2},
    }));
    assert.equal(two.rowCount, 2n);
    assert.equal(double.seen.filter(entry => entry.path?.includes('/query'))
      .length, 2);
    assert.equal(double.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).length, 2);
  });

test('query rejects changed selected schema before any query credential use',
  async t => {
    const setup = await fixture(t, {accountRefreshResponse: JSON.stringify({
      name: 'Account', queryable: true,
      fields: [{name: 'Id', type: 'int', nillable: false}],
    })});
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan)),
      {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/describe'))
      .length, 4);
  });

test('query rejects lost resource permission before any query credential use',
  async t => {
    const setup = await fixture(t, {accountRefreshResponse: JSON.stringify({
      name: 'Account', queryable: false,
      fields: [{name: 'Id', type: 'id', nillable: false}],
    })});
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan)),
      {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
  });

test('query requires a current Catalog refresh before any Site I/O',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const before = setup.seen.length;
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      refreshCatalog: undefined,
    })), {code: 'InvalidSalesforceQueryRead'});
    assert.equal(setup.seen.length, before);
  });

test('query rejects a changed connection revision before query I/O',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const options = queryRequest(setup, plan);
    await assert.rejects(readSalesforceQuery({
      ...options,
      refreshCatalog: {...options.refreshCatalog,
        connectionRevision: 'connection-revision-b'},
    }), {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
  });

test('unrelated incomplete resource does not invalidate a complete read view',
  async t => {
    const setup = await fixture(t, {customStatus: 403});
    const plan = await queryProjection(setup);
    const result = await readSalesforceQuery(queryRequest(setup, plan));
    assert.equal(result.rowCount, 2n);
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 2);
  });

test('failed locator cannot be replaced by a fresh query in one observation',
  async t => {
    const setup = await fixture(t, {querySecondStatus: 503});
    const plan = await queryProjection(setup);
    const delivered = [];
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      consumePage: async page => delivered.push(
        salesforceMoon.salesforceQueryPageRowCount(page)),
    })), {code: 'SalesforceQueryResourceRejected'});
    assert.deepEqual(delivered, [1]);
    assert.deepEqual(setup.seen.slice(-2).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
  });

test('foreign continuation authority is rejected before the next request',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      authorizationForPage: async () => ({...setup.query,
        useId: 'foreign-query-continuation',
        scope: {...setup.query.scope, siteGeneration: 5}}),
    })), {code: 'InvalidSalesforceQueryAuthorization'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('foreign initial query authority is rejected before any query request',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      initialAuthorization: {...setup.query,
        useId: 'foreign-query-initial',
        scope: {...setup.query.scope, siteGeneration: 5}},
    })), {code: 'ForeignSalesforceQueryProjection'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
  });

test('invalid locator fails closed before a second credential use',
  async t => {
    const setup = await fixture(t, {queryFirstResponse: JSON.stringify({
      totalSize: 2, done: false,
      nextRecordsUrl: 'https://foreign.invalid/query/01gABC',
      records: [{Id: '001A'}],
    })});
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan)),
      {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('Site rejects a provider value that violates the selected field type',
  async t => {
    const setup = await fixture(t, {queryFirstResponse: JSON.stringify({
      totalSize: 1, done: true,
      records: [{Id: 42}],
    })});
    const plan = await queryProjection(setup);
    let delivered = 0;
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      consumePage: async () => { delivered += 1; },
    })), {code: 'MoonBitHostFailure'});
    assert.equal(delivered, 0);
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('page consumer failure stops the locator chain instead of retrying',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      consumePage: async () => {
        throw Object.assign(new Error('PageConsumerFailed'),
          {code: 'PageConsumerFailed'});
      },
    })), {code: 'PageConsumerFailed'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('terminal page consumer failure cannot report a completed read',
  async t => {
    const setup = await fixture(t, {queryFirstResponse: JSON.stringify({
      totalSize: 1, done: true, records: [{Id: '001A'}],
    })});
    const plan = await queryProjection(setup);
    let delivered = 0;
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      consumePage: async () => {
        delivered += 1;
        throw Object.assign(new Error('TerminalConsumerFailed'),
          {code: 'TerminalConsumerFailed'});
      },
    })), {code: 'TerminalConsumerFailed'});
    assert.equal(delivered, 1);
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('managed physical driver fills the real MoonBit output owner',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const result = await readSalesforceManagedQuery(queryRequest(setup, plan, {
      moon: salesforceMoon,
      values: salesforceConformance.salesforceSiteTestOutputValues(),
    }));
    assert.equal(salesforceConformance.salesforceSiteTestReceiptRows(
      result.receipt), 2);
    assert.equal(result.rowCount, 2n);
    assert.equal(result.pages.length, 2);
    assert.ok(result.pages.every(page =>
      setup.journal.inspect(page.useCid).outcome === 'succeeded'));
    assert.deepEqual(setup.seen.slice(-2).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
  });

test('managed physical driver rejects a wrong typed value before receipt',
  async t => {
    const setup = await fixture(t, {queryFirstResponse: JSON.stringify({
      totalSize: 1, done: true, records: [{Id: 42}],
    })});
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceManagedQuery(queryRequest(setup, plan, {
      moon: salesforceMoon,
      values: salesforceConformance.salesforceSiteTestOutputValues(),
    })), {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 1);
  });

test('issued broad Site driver leaves completion to the Host verifier',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const attempt = Object.freeze({selected: true});
    const hostRun = Object.freeze({owned: true});
    let read;
    let state = 'pending';
    let aborts = 0;
    const moon = {
      ...salesforceMoon,
      salesforceBroadHostAttempt: selected => {
        assert.equal(selected, hostRun);
        return attempt;
      },
      salesforceBroadHostAbort: selected => {
        assert.equal(selected, hostRun);
        aborts += 1;
        state = 'aborted';
      },
      salesforceIssuedBroadPlan: selected => {
        assert.equal(selected, attempt);
        return plan;
      },
      salesforceIssuedBroadBegin(selected, ...args) {
        assert.equal(selected, attempt);
        if (state !== 'pending') {
          return {$tag: 0, _0: new Error('InvalidState')};
        }
        read = checked(salesforceMoon.salesforceBeginQueryRead(
          plan, ...args.slice(0, 8)));
        state = 'reading';
        return {$tag: 1, _0: true};
      },
      salesforceIssuedBroadNextPath: () =>
        salesforceMoon.salesforceQueryReadNextPath(read),
      salesforceIssuedBroadAcceptPage(_selected, path, body) {
        const page = checked(salesforceMoon.salesforceQueryReadAcceptPage(
          read, path, body));
        checked(salesforceMoon.salesforceQueryReadAcknowledgePage(read, page));
        return {$tag: 1, _0: page};
      },
      salesforceIssuedBroadComplete: () =>
        salesforceMoon.salesforceQueryReadComplete(read),
      salesforceIssuedBroadRowCount: () =>
        salesforceMoon.salesforceQueryReadRowCount(read),
      salesforceIssuedBroadFinish: () => {
        assert.equal(state, 'reading');
        state = 'awaiting-cleanup';
        return {$tag: 1, _0: true};
      },
    };
    let enteredDescribe;
    const describeStarted = new Promise(resolve => { enteredDescribe = resolve; });
    let releaseDescribe;
    const describeGate = new Promise(resolve => { releaseDescribe = resolve; });
    const options = queryRequest(setup, plan, {
      moon, hostRun, maxCaptureRows: 3,
      captureLimits: {maxNodes: 100, maxTextBytes: 1000,
        maxDepth: 10, maxWork: 1000},
    });
    const refresh = options.refreshCatalog;
    options.refreshCatalog = {
      ...refresh,
      async authorizationForDescribe(name) {
        enteredDescribe();
        await describeGate;
        return refresh.authorizationForDescribe(name);
      },
    };
    const first = readSalesforceIssuedBroad(options);
    try {
      await describeStarted;
      const physicalRequests = setup.seen.length;
      await assert.rejects(readSalesforceIssuedBroad(options),
        {code: 'MoonBitHostFailure'});
      assert.equal(setup.seen.length, physicalRequests);
      assert.equal(state, 'reading');
      assert.equal(aborts, 0);
    } finally {
      releaseDescribe();
    }
    const result = await first;
    assert.equal(state, 'awaiting-cleanup');
    assert.equal(result.hostRun, hostRun);
    assert.equal(result.rowCount, 2n);
    assert.equal(result.pages.length, 2);
    assert.equal(Object.hasOwn(result, 'receipt'), false);
    assert.equal(Object.hasOwn(result, 'observation'), false);
  });

test('invalid physical caller is rejected before a query owner or HTTP use',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      callResource: null,
    })), {code: 'InvalidSalesforceQueryRead'});
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
  });
