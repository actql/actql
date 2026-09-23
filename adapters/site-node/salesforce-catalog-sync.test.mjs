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
import {openSqliteCredentialJournal} from
  './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  './remote-credential-signature.mjs';
import {syncSalesforceCatalog} from './salesforce-catalog-sync.mjs';
import {createSalesforceCliSecretResolver} from './salesforce-cli-secret.mjs';
import {readSalesforceIssuedBroad, readSalesforceManagedQuery,
  readSalesforceQuery} from
  './salesforce-query-read.mjs';

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
    unique: true, nillable: false, defaultedOnCreate: false,
    createable: true, updateable: true}]});

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

async function fixture(t, {customStatus = 200, customResponse = customBody,
  listStatus = 200, listResponse = listBody,
  accountRefreshResponse, querySecondStatus = 200,
  queryFirstResponse} = {}) {
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
    seen.push({method: request.method, path: request.url,
      authorization: request.headers.authorization});
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
  return {
    seen, journal, list, describe, query, ca,
    credential: {
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
      'connection-revision-a', binding.siteKey, binding.siteGeneration,
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
      'connection-revision-b', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Account',
      ['Id'], 22)), {code: 'MoonBitHostFailure'});
  });

test('Salesforce write bridge binds a checked Catalog to one REST request',
  async t => {
    const setup = await fixture(t);
    const result = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      result.observation,
      binding.tenant, binding.principal, binding.environment,
      'connection-revision-a', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
      0, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"key-1"}'),
      1024, 32, 5));
    const outbound = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
      body, 'v62.0', 0, '', 0, 256, 128, 1024));
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

test('CLI alias supplies only Site secret for the authorized HTTPS path',
  async t => {
    const setup = await fixture(t);
    const origin = setup.list.scope.resourceOrigin;
    let displays = 0;
    let tokenCalls = 0;
    const resolveSecret = createSalesforceCliSecretResolver({
      connection: {alias: 'actql-test', orgId: '00D-TEST',
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
          alias: 'actql-test', id: '00D-TEST',
          username: 'test@example.invalid', instanceUrl: origin,
          accessToken: '(redacted)',
        }})};
      },
    });
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
      connection: {alias: 'actql-test', orgId: '00D-TEST',
        username: 'test@example.invalid',
        instanceOrigin: setup.list.scope.resourceOrigin},
      principal: 'principal-a', tenant: 'tenant-a', environment: 'test',
      siteKey: 'site-a', siteGeneration: 4,
      invoke: async () => ({stdout: JSON.stringify({status: 0, result: {
        alias: 'actql-test', id: '00D-OTHER',
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
    'connection-revision-a', binding.siteKey, binding.siteGeneration,
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
