import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import * as salesforceConformance from
  '../../../../_build/js/release/build/connectors/salesforce/site_test/site_test.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from
  '../../../host-common/publication-contract-control.fixture.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {checkAuthorizedEffectMemberReceiptRowPartition,
  readAuthorizedEffectTerminalOutcome} from
  '../../../host-node/effect-response-recovery.mjs';
import {captureClaimedSalesforceSingleResponse,
  captureSalesforceSingleEffectWrite,
  captureSalesforceCollectionEffectWrite,
  recoverStoredSalesforceSingleResponse,
  recoverStoredSalesforceCollectionResponse} from
  '../host/salesforce-effect-write.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {signRemoteCredentialGrant} from
  '../../../site-node/remote-credential-signature.mjs';
import {syncSalesforceCatalog} from '../site/salesforce-catalog-sync.mjs';
import {resolveSalesforceResource} from
  '../host/salesforce-resource-resolver.mjs';
import {installSalesforceResourceDiscovery} from
  '../host/salesforce-resource-discovery.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site/salesforce-catalog-recovery.mjs';
import {accountEntry, fixtureAuthorization} from
  '../../../host-node/authorization-fixture.mjs';
import {createSalesforceCliSecretResolver} from '../site/salesforce-cli-secret.mjs';
import {readSalesforceManagedQuery,
  readSalesforceQuery} from
  '../site/salesforce-query-read.mjs';
import {writeSalesforceSingleRecord} from '../site/salesforce-single-write.mjs';
import {observeSalesforceSingleTarget, observeSalesforceTargetSet} from
  '../site/salesforce-target-observation.mjs';
import {writeSalesforceContinueCollection} from
  '../site/salesforce-collection-write.mjs';

const control = runtimeCore(commonMoon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

function independentPreviewRowCid(operation, target, guard, intended,
  before, after) {
  const body = {
    version: 'actql-effect-preview-row/0.1',
    program_definition_cid: cid('a'), invocation_cid: cid('a'),
    effect_identity_cid: cid('a'), resolved_contract_cid: cid('a'),
    operation, target_row_identity: target, preview_strength: 'full_diff',
    target_guard: guard, intended_changes: intended, before, after,
  };
  return `sha256:${createHash('sha256').update(canonicalJson(body))
    .digest('hex')}`;
}

function admittedCreateRowFixture(effect, scope, effectId, after,
  providerBoundaryCid) {
  const authoring =
    'sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a';
  const contentCid = `sha256:${createHash('sha256').update(canonicalJson({
    value: after, version: 'actql-effect-content-row/0.1',
  })).digest('hex')}`;
  const correlation = {content_cid: contentCid, occurrence: 0};
  const guard = {state: 'not_applicable'};
  const intended = {state: 'present', value: after.value};
  const before = {state: 'absent'};
  const rowCid = independentPreviewRowCid('create', correlation, guard,
    intended, before, after);
  const member = {
    effect_id: effectId, effect_kind: 'create',
    target: 'Test_Record__c', mapping: 'mapping:fixture',
    resolved_mapping_contract_cid: cid('a'),
    effect_identity_cid: cid('a'), preview_strength: 'full_diff',
    source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
    authority_scope_cid: cid('8'),
    write_footprint: {
      kind: 'collection', resource_identity_scheme_cid: cid('a'),
      provider_namespace: 'salesforce',
      provider_boundary_cid: providerBoundaryCid,
      resource_kind: 'Test_Record__c', provider_object_identity_cids: [],
    },
    count: 1, max_items: 1, required_permissions: ['write'],
    approval: 'none', on_item_failure: 'halt',
    changes: [{target_row_identity: correlation, target_guard: guard,
      intended_changes: intended, before, after, row_preview_cid: rowCid,
      row_idempotency_key: cid('4')}],
    row_order: [rowCid], effect_member_preview_cid: cid('a'),
    executed: false,
  };
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
    invocation_cid: cid('a'), run_identity_cid: cid('a'),
    compiled_plan_cid: cid('a'), check_environment_cid: cid('a'),
    authoring_context: {
      version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('a'), annotations: [],
      authoring_context_cid: authoring,
    },
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [], effects: [member], executed: false,
    effect_preview_cid: cid('a'),
  };
  assert.deepEqual(effect.derivePreviewRowIdentities(
    canonicalJson(preview), 8192, 256, 12), [[rowCid]]);
  member.effect_member_preview_cid = effect.derivePreviewIdentities(
    canonicalJson(preview), 8192, 256, 12)[1];
  preview.effect_preview_cid = effect.derivePreviewIdentities(
    canonicalJson(preview), 8192, 256, 12)[0];
  const key = effect.dispatchKey(scope, preview.effect_preview_cid,
    canonicalJson(correlation), 128, 8, 3);
  member.changes[0].row_idempotency_key = effect.dispatchKeyCid(key);
  const wire = canonicalJson(preview);
  return Object.freeze({
    key, correlation, rowCid, memberCid: member.effect_member_preview_cid,
    admit: () => effect.admitPreviewIdentity(wire, cid('a'), authoring,
      scope, [[key]], 8192, 256, 12),
  });
}
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
  ]), targetStatus = 200,
  targetResponse = JSON.stringify({Id: 'a00123456789012',
    External_Key__c: 'key-1'})} = {}) {
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
    } else if (request.method === 'GET' && request.url ===
      '/services/data/v62.0/sobjects/Test_Record__c/a00123456789012') {
      response.writeHead(targetStatus, {'content-type': 'application/json'});
      response.end(targetResponse);
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
    principal: 'principal-a', namespaceId: 'namespace-a',
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
  const observe = authorize('salesforce:record:observe');
  return {
    seen, journal, list, describe, query, write, writeUpdate, writeUpsert,
    observe, ca,
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

test('Catalog owns the original binding across the HTTPS response',
  async t => {
    const setup = await fixture(t);
    const original = setup.list.scope;
    const mutableScope = {...original};
    const result = await syncSalesforceCatalog(request(setup, {
      listAuthorization: {...setup.list, useId: 'mutable-list',
        scope: mutableScope},
      callResource: async call => {
        const response = await callHttpsCredentialResource(call);
        if (call.scope.operation === 'salesforce:catalog:list') {
          mutableScope.namespaceId = 'namespace-b';
          mutableScope.principal = 'principal-b';
          mutableScope.siteGeneration = 5;
          mutableScope.resourceOrigin = 'https://foreign.example.invalid';
          mutableScope.runInvocationCid = cid('9');
        }
        return response;
      },
    }));
    assert.equal(result.status, 'complete');
    assert.equal(setup.seen.length, 3);
    assert.equal(setup.journal.recover().length, 3);
    assert.equal(checked(salesforceMoon.salesforceCatalogObservedResourceState(
      result.observation, original.namespaceId, original.principal,
      original.environment, 'connection-revision-a', setup.orgId,
      original.siteKey, original.siteGeneration,
      original.connectorRegistration, original.connectorRevision,
      original.resourceOrigin, original.runInvocationCid,
      original.dispatchRequestCid, 'catalog-sync-a', 'Account')), 1);
  });

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
    const scope = setup.list.scope;
    const observedState = (name, generation = scope.siteGeneration) =>
      checked(salesforceMoon.salesforceCatalogObservedResourceState(
        result.observation, scope.namespaceId, scope.principal, scope.environment,
        'connection-revision-a', setup.orgId, scope.siteKey, generation,
        scope.connectorRegistration, scope.connectorRevision,
        scope.resourceOrigin, scope.runInvocationCid,
        scope.dispatchRequestCid, 'catalog-sync-a', name));
    assert.equal(observedState('Account'), 1);
    assert.equal(observedState('Test_Record__c'), 1);
    assert.equal(observedState('Unlisted__c'), -1);
    assert.throws(() => observedState('Account', scope.siteGeneration + 1));
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
      binding.namespaceId, binding.principal, binding.environment,
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
      binding.namespace_id, binding.principal, binding.environment,
      'connection-revision-b', '00D000000000001EAA', binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Account',
      ['Id'], 22)), {code: 'MoonBitHostFailure'});
  });

test('Resource resolution uses only the supplied authorized Catalog snapshot',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = JSON.parse(catalog.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('account-read', 'allow', {resource: 'Account',
        operation: 'read'}),
      accountEntry('record-read', 'deny', {resource: 'Test_Record__c',
        operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const resolve = (resource, overrides = {}) => resolveSalesforceResource({
      moon: salesforceMoon, catalog, binding, authorization,
      connection: `salesforce:${setup.orgId}`, resource, operation: 'read',
      fieldNames: ['Id'], ...overrides,
    });
    const requests = setup.seen.length;
    const uses = setup.journal.recover().length;
    const account = await resolve('Account');
    assert.equal(account.status, 'ready');
    assert.equal(account.observationCid, catalog.observationCid);
    assert.equal(salesforceMoon.salesforceReadProjectionSoql(
      account.projection), 'SELECT Id FROM Account');
    const mutableBinding = {...binding};
    const mutatingAuthorization = {
      principal: authorization.principal,
      async authorize(...args) {
        const decision = await authorization.authorize(...args);
        mutableBinding.namespace_id = 'foreign-namespace';
        mutableBinding.site_generation++;
        return decision;
      },
    };
    assert.equal((await resolve('Account', {binding: mutableBinding,
      authorization: mutatingAuthorization})).status, 'ready');
    await assert.rejects(resolve('Test_Record__c'),
      {code: 'ExecutionAuthorizationDenied'});
    await assert.rejects(resolve('Account', {
      connection: 'salesforce:foreign-org',
    }), {code: 'InvalidSalesforceResourceResolution'});
    await assert.rejects(resolve('Account', {binding: {...binding,
      site_generation: binding.site_generation + 1}}),
    {code: 'MoonBitHostFailure'});
    const writeAuthorization = await fixtureAuthorization([
      accountEntry('record-metadata', 'allow',
        {resource: 'Test_Record__c', operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const candidate = await resolve('Test_Record__c', {
      operation: 'create', fieldNames: ['External_Key__c'],
      authorization: writeAuthorization,
    });
    assert.equal(candidate.status, 'ready');
    assert.equal(checked(salesforceMoon.salesforceRecheckWriteProjection(
      candidate.projection, catalog.observation)), true);
    assert.deepEqual(await resolve('Test_Record__c', {
      fieldNames: ['Undisclosed_Field__c'],
      authorization: writeAuthorization,
    }), {status: 'catalog_required', reason: 'field_unconfirmed',
      field: 'Undisclosed_Field__c', observationCid: catalog.observationCid});
    assert.equal(setup.seen.length, requests);
    assert.equal(setup.journal.recover().length, uses);
  });

test('installed Resource discovery filters current disclosure without provider I/O',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = JSON.parse(catalog.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('account-read', 'allow', {resource: 'Account',
        operation: 'read'}),
      accountEntry('record-read', 'deny', {resource: 'Test_Record__c',
        operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const suppliedCatalog = {...catalog};
    const discovery = installSalesforceResourceDiscovery({moon: salesforceMoon,
      catalog: suppliedCatalog, binding, authorization,
      connection: `salesforce:${setup.orgId}`});
    const requests = setup.seen.length;
    const uses = setup.journal.recover().length;
    assert.deepEqual(await discovery.list(), {
      observationCid: catalog.observationCid,
      resources: [{name: 'Account', outcome: 'described'}],
      snapshotTruncated: false, snapshotComplete: true,
      resultTruncated: false,
    });
    assert.deepEqual((await discovery.search('test')).resources, []);
    suppliedCatalog.observationCid = cid('f');
    suppliedCatalog.observationJson = '{}';
    const inspected = await discovery.inspect({resource: 'Account'});
    assert.equal(inspected.status, 'ready');
    assert.equal(inspected.observationCid, catalog.observationCid);
    assert.deepEqual(inspected.summary.fields.map(field => field.name),
      ['Id']);
    assert.equal(inspected.summary.fields[0].nullable, false);
    await assert.rejects(discovery.inspect({resource: 'Test_Record__c'}),
      {code: 'ExecutionAuthorizationDenied'});
    assert.equal((await discovery.resolve({resource: 'Account',
      operation: 'read', fieldNames: ['Id']})).status, 'ready');
    await assert.rejects(discovery.resolve({resource: 'Test_Record__c',
      operation: 'read', fieldNames: ['Id']}),
    {code: 'ExecutionAuthorizationDenied'});
    assert.equal(setup.seen.length, requests);
    assert.equal(setup.journal.recover().length, uses);
    await assert.rejects(async () => installSalesforceResourceDiscovery({
      moon: salesforceMoon, catalog, binding: {...binding,
        site_generation: binding.site_generation + 1}, authorization,
      connection: `salesforce:${setup.orgId}`}),
    {code: 'InvalidSalesforceResourceDiscovery'});
  });

test('Resource discovery preserves snapshot and display truncation separately',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = JSON.parse(catalog.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('all-read', 'allow', {operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const discovery = installSalesforceResourceDiscovery({moon: salesforceMoon,
      catalog, binding, authorization,
      connection: `salesforce:${setup.orgId}`});
    assert.deepEqual(await discovery.list({maxResults: 1}), {
      observationCid: catalog.observationCid,
      resources: [{name: 'Account', outcome: 'described'}],
      snapshotTruncated: false, snapshotComplete: true,
      resultTruncated: true,
    });
    const partial = await syncSalesforceCatalog(request(setup, {
      listLimits: {...listLimits, maxSelected: 1},
      listAuthorization: {...setup.list, useId: 'partial-list'},
      describeAuthorization: () => ({...setup.describe,
        useId: 'partial-describe'}),
    }));
    const partialDiscovery = installSalesforceResourceDiscovery({
      moon: salesforceMoon, catalog: partial,
      binding: JSON.parse(partial.observationJson).binding, authorization,
      connection: `salesforce:${setup.orgId}`,
    });
    const listed = await partialDiscovery.list();
    assert.equal(listed.snapshotTruncated, true);
    assert.equal(listed.snapshotComplete, false);
    assert.equal(listed.resultTruncated, false);
    assert.deepEqual(await partialDiscovery.inspect({
      resource: 'Test_Record__c',
    }), {status: 'catalog_required',
      observationCid: partial.observationCid, reason: 'listing_truncated'});
  });

test('recovered Resource discovery keeps partial metadata and current authority',
  async t => {
    const setup = await fixture(t, {customStatus: 403});
    const observed = await syncSalesforceCatalog(request(setup, {
      retainResponses: true, maxRetainedBytes: 20000,
    }));
    const recovered = recoverRetainedSalesforceCatalog({
      moon: salesforceMoon, retained: observed.retainedResponses,
      expectedObservationCid: observed.observationCid,
      maxRetainedBytes: 20000,
    });
    const binding = JSON.parse(observed.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('account-read', 'allow', {resource: 'Account',
        operation: 'read'}),
      accountEntry('record-read', 'deny', {resource: 'Test_Record__c',
        operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const discovery = installSalesforceResourceDiscovery({moon: salesforceMoon,
      catalog: recovered,
      binding, authorization, connection: `salesforce:${setup.orgId}`});
    const requests = setup.seen.length;
    const uses = setup.journal.recover().length;
    const listed = await discovery.list();
    assert.deepEqual(listed.resources,
      [{name: 'Account', outcome: 'described'}]);
    assert.equal(listed.snapshotTruncated, false);
    assert.equal(listed.snapshotComplete, false);
    assert.deepEqual(await discovery.inspect({resource: 'Account'}), {
      status: 'ready', observationCid: observed.observationCid,
      summary: {name: 'Account', queryable: true, createable: false,
        updateable: false, fields: [{name: 'Id', native_type: 'id',
          nullable: false, nullability_confirmed: true,
          defaulted_on_create: false, default_on_create_confirmed: false,
          createable: false, updateable: false, filterable: false,
          sortable: false, external_id: false, unique: false,
          case_sensitive: null, reference_to: []}]},
    });
    await assert.rejects(discovery.inspect({resource: 'Test_Record__c'}),
      {code: 'ExecutionAuthorizationDenied'});
    assert.equal(setup.seen.length, requests);
    assert.equal(setup.journal.recover().length, uses);
  });

test('Resource resolution keeps partial metadata as a typed requirement',
  async t => {
    const setup = await fixture(t, {customStatus: 403});
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = JSON.parse(catalog.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('record-read', 'allow', {resource: 'Test_Record__c',
        operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    const response = await resolveSalesforceResource({moon: salesforceMoon,
      catalog, binding, authorization,
      connection: `salesforce:${setup.orgId}`,
      resource: 'Test_Record__c', operation: 'create',
      fieldNames: ['External_Key__c']});
    assert.deepEqual(response, {
      status: 'catalog_required', reason: 'describe_unavailable',
      observationCid: catalog.observationCid,
    });
    assert.equal(setup.seen.length, 3);
  });

test('Resource resolution does not infer absence from a truncated listing',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup, {
      listLimits: {...listLimits, maxSelected: 1},
    }));
    const binding = JSON.parse(catalog.observationJson).binding;
    const authorization = await fixtureAuthorization([
      accountEntry('record-read', 'allow', {resource: 'Test_Record__c',
        operation: 'read'}),
    ], {context: {principal: binding.principal, contextCid: cid('d')}});
    assert.deepEqual(await resolveSalesforceResource({moon: salesforceMoon,
      catalog, binding, authorization,
      connection: `salesforce:${setup.orgId}`,
      resource: 'Test_Record__c', operation: 'read',
      fieldNames: ['Id']}), {
      status: 'catalog_required', reason: 'listing_truncated',
      observationCid: catalog.observationCid,
    });
    assert.deepEqual(setup.seen.map(({path}) => path), [
      '/services/data/v62.0/sobjects/',
      '/services/data/v62.0/sobjects/Account/describe',
    ]);
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
      binding.namespaceId, binding.principal, binding.environment,
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
      outbound, binding.namespaceId, binding.principal, binding.environment,
      binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid), true);
    assert.equal(salesforceMoon.salesforceSingleWriteRequestScopeMatches(
      outbound, binding.namespaceId, binding.principal, binding.environment,
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
      binding.namespaceId, binding.principal, binding.environment,
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
      binding.namespaceId, binding.principal, binding.environment,
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

test('Site reads the exact prospective target with separate read authority',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      catalog.observation,
      binding.namespaceId, binding.principal, binding.environment,
      'connection-revision-a', setup.orgId, binding.siteKey,
      binding.siteGeneration, binding.connectorRegistration,
      binding.connectorRevision, binding.resourceOrigin,
      binding.runInvocationCid, binding.dispatchRequestCid,
      'catalog-sync-a', 'Test_Record__c', 1, '',
      ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"changed"}'),
      1024, 32, 5));
    const update = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
      body, 'v62.0', 1, 'a00123456789012', 0, 256, 128, 1024));
    const options = {
      moon: salesforceMoon, request: update,
      currentCatalog: catalog.observation,
      authorization: {...setup.observe, useId: 'target-read'},
      credential: setup.credential,
      limits: {maxResponseBytes: 1024, maxNodes: 32,
        maxDepth: 5, maxIdentityBytes: 1024},
    };
    await assert.rejects(observeSalesforceSingleTarget({
      ...options, authorization: {...setup.observe,
        useId: 'foreign-target-read',
        scope: {...setup.observe.scope, siteGeneration: 5}},
    }), {code: 'ForeignSalesforceTargetObservation'});
    await assert.rejects(observeSalesforceSingleTarget({
      ...options, authorization: {...setup.writeUpdate,
        useId: 'write-grant-for-read'},
    }), {code: 'ForeignSalesforceTargetObservation'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/a00123456789012')).length, 0);
    const observed = await observeSalesforceSingleTarget(options);
    assert.equal(observed.statusCode, 200);
    assert.deepEqual(JSON.parse(observed.body), {
      Id: 'a00123456789012', External_Key__c: 'key-1',
    });
    assert.match(observed.versionCid, /^sha256:[0-9a-f]{64}$/);
    assert.equal(observed.beforeWire,
      '{"External_Key__c":"key-1"}');
    assert.equal(observed.versionCid,
      salesforceMoon.salesforceTargetObservationVersionCid(observed.record));
    const target = checked(
      salesforceMoon.salesforceSingleWriteRequestTargetIdentity(
        update, 1024));
    assert.equal(observed.versionCid, `sha256:${createHash('sha256')
      .update(canonicalJson({
        object_cid: salesforceMoon.salesforceWriteTargetObjectCid(target),
        response_sha256: createHash('sha256').update(observed.body)
          .digest('hex'),
        version: 'actql-salesforce-target-observation/0.1',
      })).digest('hex')}`);
    assert.equal(setup.journal.inspect(observed.useCid).outcome, 'succeeded');
    assert.deepEqual(setup.seen.filter(item => item.path?.endsWith(
      '/a00123456789012')).map(item => [item.method, item.path]), [[
      'GET', '/services/data/v62.0/sobjects/Test_Record__c/a00123456789012',
    ]]);
    assert.equal(setup.seen.filter(item => item.method === 'PATCH').length, 0);
    const targetReads = setup.seen.length;
    await assert.rejects(observeSalesforceTargetSet({
      moon: salesforceMoon, members: [{requests: [update, update],
        currentCatalog: catalog.observation,
        authorizationForRow: () => ({...setup.observe,
          useId: 'target-set-over-limit'}),
        credential: setup.credential, limits: options.limits}],
      maxMembers: 1, maxRows: 1, maxTotalResponseBytes: 1024,
    }), {code: 'InvalidSalesforceTargetSet'});
    assert.equal(setup.seen.length, targetReads);
    const abort = new AbortController();
    await assert.rejects(observeSalesforceTargetSet({
      moon: salesforceMoon, members: [{requests: [update, update],
        currentCatalog: catalog.observation,
        authorizationForRow: rowIndex => {
          if (rowIndex === 1) abort.abort();
          return {...setup.observe, useId: `target-set-${rowIndex}`};
        },
        credential: setup.credential, limits: options.limits}],
      maxMembers: 1, maxRows: 2, maxTotalResponseBytes: 1024,
      signal: abort.signal,
    }), {name: 'AbortError'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/a00123456789012')).length, 2);
    let admittedReads = 0;
    await assert.rejects(observeSalesforceTargetSet({
      moon: salesforceMoon, members: [{requests: [update, update],
        currentCatalog: catalog.observation,
        authorizationForRow: () => ({...setup.observe,
          useId: `target-set-byte-${admittedReads++}`}),
        credential: setup.credential, limits: options.limits}],
      maxMembers: 1, maxRows: 2,
      maxTotalResponseBytes: observed.body.byteLength,
    }), {code: 'SalesforceTargetSetByteLimit'});
    assert.equal(admittedReads, 1);
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/a00123456789012')).length, 3);
  });

test('target read cannot turn absence or a foreign record into a guard',
  async t => {
    for (const scenario of [
      {targetStatus: 404, targetResponse: '[{"errorCode":"NOT_FOUND"}]',
        expected: 'unresolved'},
      {targetStatus: 200, targetResponse: JSON.stringify({
        Id: 'a00123456789013', External_Key__c: 'key-1',
      }), expected: 'foreign'},
      {targetStatus: 200, targetResponse: JSON.stringify({
        Id: 'a00123456789012',
      }), expected: 'incomplete'},
      {targetStatus: 200, targetResponse: JSON.stringify({
        Id: 'a00123456789012', External_Key__c: 7,
      }), expected: 'wrong-field-type'},
    ]) {
      await t.test(scenario.expected, async child => {
        const setup = await fixture(child, scenario);
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation, binding.namespaceId, binding.principal,
            binding.environment, 'connection-revision-a', setup.orgId,
            binding.siteKey, binding.siteGeneration,
            binding.connectorRegistration, binding.connectorRevision,
            binding.resourceOrigin, binding.runInvocationCid,
            binding.dispatchRequestCid, 'catalog-sync-a',
            'Test_Record__c', 1, '', ['External_Key__c'], 2));
        const body = checked(salesforceMoon.salesforcePrepareWriteBody(
          projection, Buffer.from('{"External_Key__c":"changed"}'),
          1024, 32, 5));
        const update = checked(
          salesforceMoon.salesforcePrepareSingleWriteRequest(
            body, 'v62.0', 1, 'a00123456789012', 0, 256, 128, 1024));
        const options = {
          moon: salesforceMoon, request: update,
          currentCatalog: catalog.observation,
          authorization: {...setup.observe,
            useId: `target-${scenario.expected}`},
          credential: setup.credential,
          limits: {maxResponseBytes: 1024, maxNodes: 32,
            maxDepth: 5, maxIdentityBytes: 1024},
        };
        if (scenario.expected === 'unresolved') {
          const observed = await observeSalesforceSingleTarget(options);
          assert.equal(observed.statusCode, 404);
          assert.equal(observed.record, undefined);
          assert.equal(observed.versionCid, undefined);
          assert.equal(observed.beforeWire, undefined);
          await assert.rejects(observeSalesforceTargetSet({
            moon: salesforceMoon, members: [{requests: [update],
              currentCatalog: catalog.observation,
              authorizationForRow: () => ({...setup.observe,
                useId: 'target-set-unresolved'}),
              credential: setup.credential, limits: options.limits}],
            maxMembers: 1, maxRows: 1, maxTotalResponseBytes: 1024,
          }), {code: 'UnresolvedSalesforceTarget'});
        } else {
          await assert.rejects(observeSalesforceSingleTarget(options),
            {code: 'MoonBitHostFailure'});
        }
        assert.equal(setup.seen.filter(item => item.method === 'GET' &&
          item.path?.endsWith('/a00123456789012')).length,
        scenario.expected === 'unresolved' ? 2 : 1);
        assert.equal(setup.seen.filter(item => item.method === 'PATCH').length,
          0);
      });
    }
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
            binding.namespaceId, binding.principal, binding.environment,
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
        const result = await captureClaimedSalesforceSingleResponse({
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
    binding.namespaceId, binding.principal, binding.environment,
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
  const boundaryCid = checked(
    salesforceMoon.salesforceSingleWriteRequestBoundaryCid(outbound, 4096));
  const preview = admittedCreateRowFixture(effect, scope,
    'CreateOne', {state: 'present', value: {External_Key__c: 'key-1'}},
    boundaryCid);
  const rowPreviewCid = preview.rowCid;
  const key = preview.key;
  const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
    'CreateOne', canonicalJson(preview.correlation), 64, 128, 8, 3);
  const basis = effect.ledgerBasis(scope, locator, key,
    cid('6'), preview.memberCid, cid('4'), requestCid, cid('3'),
    'unavailable', cid('2'), cid('1'));
  const claim = {scope, locator, key, basis,
    intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
  const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-effect-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const open = () => openEffectLedger({moon: commonMoon, root,
    authorityScopeCid, callerRequestId: 'salesforce-business-request',
    maxEntryBytes: 4096});
  const options = {claim, commonMoon, admittedPreview: preview.admit(),
    memberIndex: 0, rowIndex: 0, rowPreviewCid,
    moon: salesforceMoon, request: outbound,
    currentObservation: catalog.observation,
    authorization: {...setup.write, useId: 'effect-write-use'},
    credential: setup.credential,
    limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
      maxNodes: 32, maxDepth: 5}};
  const first = open();
  t.after(() => first.close());
  const unapprovedBody = checked(salesforceMoon.salesforcePrepareWriteBody(
    projection, Buffer.from('{"External_Key__c":"unapproved"}'),
    1024, 32, 5));
  const unapprovedRequest = checked(
    salesforceMoon.salesforcePrepareSingleWriteRequest(
      unapprovedBody, 'v62.0', 0, '', 0, 256, 128, 1024));
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first, request: unapprovedRequest,
  }), {code: 'ForeignSalesforceEffectFootprint'});
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 0);
  const foreignPreview = admittedCreateRowFixture(effect, scope,
    'CreateOne',
    {state: 'present', value: {External_Key__c: 'key-1'}}, cid('f'));
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first, admittedPreview: foreignPreview.admit(),
  }), {code: 'ForeignSalesforceEffectFootprint'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first,
    claim: {...claim, canonicalRequestCid: cid('9')},
  }), {code: 'InvalidEffectPhysicalDispatch'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first, rowPreviewCid: cid('9'),
  }), {code: 'MoonBitHostFailure'});
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: first, rowIndex: 1,
  }), {code: 'ForeignSalesforceEffectFootprint'});
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
  const mutableLimits = {...options.limits};
  const sent = await captureSalesforceSingleEffectWrite({
    ...options, ledger: first, limits: mutableLimits,
    callResource: async call => {
      const response = await callHttpsCredentialResource(call);
      mutableLimits.maxDepth = 0;
      return response;
    },
  });
  assert.equal(mutableLimits.maxDepth, 0);
  assert.equal(sent.claimed, true);
  assert.equal(sent.physical.kind, 'typed-success-response');
  assert.equal(first.readClaimedOutcome(options.claim).outcomeCid,
    sent.outcomeReceipt.identity);
  assert.equal(sent.terminal.created, true);
  assert.equal(JSON.parse(first.current(
    effect.logicalItemLocatorCid(claim.locator)).entryJson).state, 'applied');
  assert.equal(JSON.parse(sent.outcomeReceipt.wire).row_preview_cid,
    rowPreviewCid);
  const sentOutcome = checked(salesforceMoon.salesforceProjectSingleEffectOutcome(
    options.admittedPreview, 0, 0, outbound, sent.physical.response,
    4096, 2048, 128, 8));
  assert.equal(salesforceMoon.salesforceWriteEffectOutcomeRowCid(sentOutcome),
    rowPreviewCid);
  assert.deepEqual(JSON.parse(
    salesforceMoon.salesforceWriteEffectOutcomeWire(sentOutcome)), {
    result: {created: true, record_id: 'a00123456789012'},
    state: 'applied',
  });
  assert.equal(salesforceMoon.salesforceWriteEffectOutcomeResponseSha256(
    sentOutcome), sent.physical.result[2]);
  assert.throws(() => checked(salesforceMoon.salesforceProjectSingleEffectOutcome(
    foreignPreview.admit(), 0, 0, outbound, sent.physical.response,
    4096, 2048, 128, 8)));
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
  assert.deepEqual(sent.response.responseBytes,
    Buffer.from(JSON.stringify({id: 'a00123456789012',
      success: true, errors: []})));
  first.close();
  const restarted = open();
  t.after(() => restarted.close());
  const usesBeforeRetry = setup.journal.recover().length;
  const withoutEvidence = await captureSalesforceSingleEffectWrite({
    ...options, ledger: restarted, admittedPreview: preview.admit()});
  assert.equal(withoutEvidence.ownership.action, 5);
  assert.equal(withoutEvidence.recovered, undefined);
  assert.equal(withoutEvidence.outcomeReceipt, undefined);
  assert.equal(withoutEvidence.ownership.response, undefined);
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...options, ledger: restarted, admittedPreview: preview.admit(),
    authorizeEvidenceRead: async () => false,
  }), {code: 'EffectEvidenceAccessDenied'});
  const retry = await captureSalesforceSingleEffectWrite({
    ...options, ledger: restarted, admittedPreview: preview.admit(),
    authorizeEvidenceRead: async () => true});
  assert.equal(retry.claimed, false);
  assert.equal(retry.ownership.action, 5);
  assert.equal(retry.recovered.kind, 'typed-success-response');
  assert.equal(retry.outcomeReceipt.identity, sent.outcomeReceipt.identity);
  assert.equal(retry.terminal.created, false);
  const recoveredOutcome = checked(
    salesforceMoon.salesforceProjectSingleEffectOutcome(
      options.admittedPreview, 0, 0, outbound, retry.recovered.response,
      4096, 2048, 128, 8));
  assert.equal(salesforceMoon.salesforceWriteEffectOutcomeWire(
    recoveredOutcome), salesforceMoon.salesforceWriteEffectOutcomeWire(
    sentOutcome));
  assert.deepEqual(retry.recovered.result, sent.physical.result);
  assert.deepEqual(retry.recovered.observation.body,
    sent.physical.observation.body);
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
  assert.equal(setup.journal.recover().length, usesBeforeRetry);
  let evidenceReads = 0;
  const recovery = {
    ledger: restarted, claim: {...claim}, commonMoon, moon: salesforceMoon,
    request: outbound, resourceOrigin: binding.resourceOrigin,
    limits: options.limits,
  };
  const withoutWriteGrant = await recoverStoredSalesforceSingleResponse({
    ...recovery,
    authorizeEvidenceRead: async observed => {
      evidenceReads += 1;
      assert.equal(observed.logicalRequestScopeCid, restarted.scopeCid);
      assert.equal(observed.logicalItemLocatorCid,
        effect.logicalItemLocatorCid(locator));
      assert.equal(observed.canonicalRequestCid, requestCid);
      assert.equal(observed.orgId, '00D000000000001EAA');
      recovery.claim.canonicalRequestCid = cid('9');
      return true;
    },
  });
  assert.equal(withoutWriteGrant.recovered.kind,
    'typed-success-response');
  assert.deepEqual(withoutWriteGrant.recovered.result,
    sent.physical.result);
  assert.equal(evidenceReads, 1);
  await assert.rejects(recoverStoredSalesforceSingleResponse({
    ...recovery, claim, authorizeEvidenceRead: async () => false,
  }), {code: 'EffectEvidenceAccessDenied'});
  await assert.rejects(recoverStoredSalesforceSingleResponse({
    ...recovery, claim, request: unapprovedRequest,
    authorizeEvidenceRead: async () => true,
  }), {code: 'ForeignSalesforceEffectResponse'});
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
  assert.equal(setup.journal.recover().length, usesBeforeRetry);

  const faultRoot = await mkdtemp(join(tmpdir(),
    'actql-salesforce-terminal-retry-'));
  t.after(() => rm(faultRoot, {recursive: true, force: true}));
  const openFault = () => openEffectLedger({moon: commonMoon, root: faultRoot,
    authorityScopeCid, callerRequestId: 'salesforce-business-request',
    maxEntryBytes: 4096});
  const faultLedger = openFault();
  t.after(() => faultLedger.close());
  let failTerminal = true;
  const interrupted = Object.freeze({...faultLedger,
    commitAdmittedRowOutcome(args) {
      if (failTerminal) {
        failTerminal = false;
        throw new Error('InjectedTerminalCommitFailure');
      }
      return faultLedger.commitAdmittedRowOutcome(args);
    },
  });
  const faultOptions = {...options,
    authorization: {...options.authorization, useId: 'effect-write-fault-use'}};
  await assert.rejects(captureSalesforceSingleEffectWrite({
    ...faultOptions, ledger: interrupted,
  }), {message: 'InjectedTerminalCommitFailure'});
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 2);
  assert.ok(faultLedger.readClaimedOutcome(claim));
  assert.equal(JSON.parse(faultLedger.current(
    effect.logicalItemLocatorCid(claim.locator)).entryJson).state,
  'dispatching');
  faultLedger.close();
  const resumed = openFault();
  t.after(() => resumed.close());
  const reconciled = await captureSalesforceSingleEffectWrite({
    ...faultOptions, ledger: resumed,
    authorizeEvidenceRead: async () => true,
  });
  assert.equal(reconciled.claimed, false);
  assert.equal(reconciled.ownership.action, 3);
  assert.equal(reconciled.terminal.created, true);
  const repeated = await captureSalesforceSingleEffectWrite({
    ...faultOptions, ledger: resumed,
    authorizeEvidenceRead: async () => true,
  });
  assert.equal(repeated.ownership.action, 5);
  assert.equal(repeated.terminal.created, false);
  assert.equal(setup.seen.filter(item => item.method === 'POST').length, 2);
});

test('retained Catalog responses restore only the exact typed observation',
  async t => {
    const setup = await fixture(t);
    const live = await syncSalesforceCatalog(request(setup, {
      retainResponses: true, maxRetainedBytes: 30000,
    }));
    const beforeRequests = setup.seen.length;
    const beforeUses = setup.journal.recover().length;
    const retained = JSON.parse(JSON.stringify(live.retainedResponses));
    const restored = recoverRetainedSalesforceCatalog({
      moon: salesforceMoon, retained,
      expectedObservationCid: live.observationCid,
      maxRetainedBytes: 30000,
    });
    assert.equal(restored.observationCid, live.observationCid);
    assert.equal(salesforceMoon.salesforceCatalogObservationJson(
      restored.observation), live.observationJson);
    assert.equal(setup.seen.length, beforeRequests);
    assert.equal(setup.journal.recover().length, beforeUses);
    const wrongResponse = structuredClone(retained);
    wrongResponse.describeBodyBase64[1] = Buffer.from(
      '{"name":"Other","fields":[]}', 'utf8').toString('base64');
    assert.throws(() => recoverRetainedSalesforceCatalog({
      moon: salesforceMoon, retained: wrongResponse,
      expectedObservationCid: live.observationCid,
      maxRetainedBytes: 30000,
    }), {code: 'MoonBitHostFailure'});
    const wrongBinding = structuredClone(retained);
    wrongBinding.observationJson = wrongBinding.observationJson.replace(
      '"namespace_id":"namespace-a"', '"namespace_id":"namespace-b"');
    assert.throws(() => recoverRetainedSalesforceCatalog({
      moon: salesforceMoon, retained: wrongBinding,
      expectedObservationCid: live.observationCid,
      maxRetainedBytes: 30000,
    }), {code: 'ForeignRetainedSalesforceCatalog'});
    assert.throws(() => recoverRetainedSalesforceCatalog({
      moon: salesforceMoon, retained,
      expectedObservationCid: live.observationCid,
      maxRetainedBytes: 1,
    }), {code: 'InvalidRetainedSalesforceCatalog'});
    assert.equal(setup.seen.length, beforeRequests);
  });

test('lost HTTPS reply remains uncertain across Effect ledger restart',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      catalog.observation,
      binding.namespaceId, binding.principal, binding.environment,
      'connection-revision-a', '00D000000000001EAA', binding.siteKey,
      binding.siteGeneration, binding.connectorRegistration,
      binding.connectorRevision, binding.resourceOrigin,
      binding.runInvocationCid, binding.dispatchRequestCid,
      'catalog-sync-a', 'Test_Record__c', 0, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"lost-reply"}'),
      1024, 32, 5));
    const outbound = checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
      body, 'v62.0', 0, '', 0, 256, 128, 1024));
    const requestCid = checked(salesforceMoon.salesforceSingleWriteRequestCid(
      outbound, binding.resourceOrigin, 4096));
    const effect = runtimeCore(commonMoon).effectApplicationControl;
    const authorityScopeCid = cid('8');
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'lost-reply-business-request', 128);
    const boundaryCid = checked(
      salesforceMoon.salesforceSingleWriteRequestBoundaryCid(outbound, 4096));
    const preview = admittedCreateRowFixture(effect, scope,
      'CreateLostReply', {state: 'present', value: {
        External_Key__c: 'lost-reply',
      }}, boundaryCid);
    const rowPreviewCid = preview.rowCid;
    const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
      'CreateLostReply', canonicalJson(preview.correlation), 64, 128, 8, 3);
    const basis = effect.ledgerBasis(scope, locator, preview.key,
      cid('6'), preview.memberCid, cid('4'), requestCid, cid('3'),
      'unavailable', cid('2'), cid('1'));
    const claim = {scope, locator, key: preview.key, basis,
      intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
    const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-lost-reply-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const open = () => openEffectLedger({moon: commonMoon, root,
      authorityScopeCid, callerRequestId: 'lost-reply-business-request',
      maxEntryBytes: 4096});
    const options = {claim, commonMoon, admittedPreview: preview.admit(),
      memberIndex: 0, rowIndex: 0, rowPreviewCid, moon: salesforceMoon,
      request: outbound, currentObservation: catalog.observation,
      authorization: {...setup.write, useId: 'lost-reply-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 32, maxDepth: 5}};
    const first = open();
    t.after(() => first.close());
    await assert.rejects(captureSalesforceSingleEffectWrite({
      ...options, ledger: first,
      callResource: async request => {
        await callHttpsCredentialResource(request);
        throw new Error('reply lost after provider request');
      },
    }), /reply lost after provider request/);
    assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const usesBeforeRetry = setup.journal.recover().length;
    const retry = await captureSalesforceSingleEffectWrite({
      ...options, ledger: restarted, admittedPreview: preview.admit(),
    });
    assert.equal(retry.claimed, false);
    assert.equal(retry.ownership.action, 3);
    assert.equal(retry.ownership.response, undefined);
    assert.equal(retry.recovered, undefined);
    assert.equal(setup.seen.filter(item => item.method === 'POST').length, 1);
    assert.equal(setup.journal.recover().length, usesBeforeRetry);
    const evidence = await recoverStoredSalesforceSingleResponse({
      ledger: restarted, claim, commonMoon, moon: salesforceMoon,
      request: outbound, resourceOrigin: binding.resourceOrigin,
      limits: options.limits,
      authorizeEvidenceRead: async () => true,
    });
    assert.equal(evidence.recovered, undefined);
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
            binding.namespaceId, binding.principal, binding.environment,
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
        binding.namespaceId, binding.principal, binding.environment,
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
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      result.result, 0)), true);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      result.result, 1)), false);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowCid(
      result.result, 0)), cid('1'));
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowCid(
      result.result, 1)), cid('2'));
    assert.throws(() => checked(
      salesforceMoon.salesforceCollectionWriteResponseRowCid(
        result.result, 2)));
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
        binding.namespaceId, binding.principal, binding.environment,
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
    // Independent fixed hashes of the 0.1 content-row preimages for key-1
    // and key-2; neither the request builder nor the author is the oracle.
    const contentCids = [
      'sha256:7ce09707fd3536365f014709747d65543e87e2275954be399195ea40f84af20d',
      'sha256:cd284cc2dafaee96a14341975ded56ad6072cf0aff34891428b711df06afbd31',
    ];
    const rowCids = contentCids.map((contentCid, index) => {
      const after = {state: 'present', value: {
        External_Key__c: `key-${index + 1}`}};
      return independentPreviewRowCid('create',
        {content_cid: contentCid, occurrence: 0},
        {state: 'not_applicable'},
        {state: 'present', value: after.value},
        {state: 'absent'}, after);
    });
    const outbound = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        rowCids, bodies, [0, 0], ['', ''], [0, 0], 'v62.0',
        256, 128, 1024, 64, 6, 200));
    const requestCid = checked(
      salesforceMoon.salesforceCollectionWriteRequestCid(
        outbound, binding.resourceOrigin, 4096));
    const boundaryCid = checked(
      salesforceMoon.salesforceCollectionWriteRequestBoundaryCid(
        outbound, 4096));
    const effect = runtimeCore(commonMoon).effectApplicationControl;
    const authorityScopeCid = cid('8');
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'collection-business-request', 128);
    const authoring =
      'sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a';
    const member = {
      effect_id: 'CreateTwo', effect_kind: 'create',
      target: 'Test_Record__c', mapping: 'mapping:fixture',
      resolved_mapping_contract_cid: cid('a'),
      effect_identity_cid: cid('a'), preview_strength: 'full_diff',
      source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
      authority_scope_cid: authorityScopeCid,
      write_footprint: {
        kind: 'collection', resource_identity_scheme_cid: cid('a'),
        provider_namespace: 'salesforce',
        provider_boundary_cid: boundaryCid,
        resource_kind: 'Test_Record__c',
        provider_object_identity_cids: [],
      },
      count: 2, max_items: 2, required_permissions: ['write'],
      approval: 'none', on_item_failure: 'continue',
      changes: rowCids.map((rowCid, index) => ({
        target_row_identity: {content_cid: contentCids[index], occurrence: 0},
        target_guard: {state: 'not_applicable'},
        intended_changes: {state: 'present', value: {
          External_Key__c: `key-${index + 1}`}},
        before: {state: 'absent'},
        after: {state: 'present', value: {
          External_Key__c: `key-${index + 1}`}},
        row_preview_cid: rowCid,
        row_idempotency_key: cid(index === 0 ? '4' : '5'),
      })),
      row_order: rowCids, effect_member_preview_cid: cid('a'),
      executed: false,
    };
    const preview = {
      version: 'actql-effect-preview/0.1', sensitivity: 'private',
      retention_class: 'authority-evidence', encryption_required: true,
      program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
      invocation_cid: cid('a'), run_identity_cid: cid('a'),
      compiled_plan_cid: cid('a'), check_environment_cid: cid('a'),
      authoring_context: {
        version: 'actql-authoring-context/0.1',
        program_definition_cid: cid('a'), annotations: [],
        authoring_context_cid: authoring,
      },
      barrier_provenance_cids: [], model_derived: false,
      model_task_contract_cids: [], model_invocation_evidence_cids: [],
      model_response_artifact_cids: [], effects: [member], executed: false,
      effect_preview_cid: cid('a'),
    };
    assert.deepEqual(effect.derivePreviewRowIdentities(
      canonicalJson(preview), 8192, 256, 12), [rowCids]);
    member.effect_member_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(preview), 8192, 256, 12)[1];
    preview.effect_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(preview), 8192, 256, 12)[0];
    const keys = contentCids.map(contentCid => effect.dispatchKey(
      scope, preview.effect_preview_cid,
      canonicalJson({content_cid: contentCid, occurrence: 0}),
      128, 8, 3));
    member.changes.forEach((change, index) => {
      change.row_idempotency_key = effect.dispatchKeyCid(keys[index]);
    });
    const previewWire = canonicalJson(preview);
    const admitPreview = () => effect.admitPreviewIdentity(
      previewWire, cid('a'), authoring, scope, [keys], 8192, 256, 12);
    const admittedPreview = admitPreview();
    const reorderedPreview = structuredClone(preview);
    reorderedPreview.effects[0].row_order = [...rowCids].reverse();
    reorderedPreview.effects[0].effect_member_preview_cid =
      effect.derivePreviewIdentities(
        canonicalJson(reorderedPreview), 8192, 256, 12)[1];
    reorderedPreview.effect_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(reorderedPreview), 8192, 256, 12)[0];
    const reorderedKeys = contentCids.map(contentCid => effect.dispatchKey(
      scope, reorderedPreview.effect_preview_cid,
      canonicalJson({content_cid: contentCid, occurrence: 0}), 128, 8, 3));
    reorderedPreview.effects[0].changes.forEach((change, index) => {
      change.row_idempotency_key = effect.dispatchKeyCid(
        reorderedKeys[index]);
    });
    const reorderedAdmitted = effect.admitPreviewIdentity(
      canonicalJson(reorderedPreview), cid('a'), authoring, scope,
      [reorderedKeys], 8192, 256, 12);
    const reorderedRequest = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        [...rowCids].reverse(), [...bodies].reverse(), [0, 0], ['', ''],
        [0, 0], 'v62.0', 256, 128, 1024, 64, 6, 200));
    assert.equal(checked(
      salesforceMoon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
        reorderedAdmitted, 0, 0, reorderedRequest, 4096, 100_000)), true);
    assert.equal(checked(
      salesforceMoon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
        reorderedAdmitted, 0, 0, outbound, 4096, 100_000)), false);
    assert.equal(effect.checkPreviewFootprintConflicts(
      previewWire, ['CreateTwo'], [1], [cid('a')],
      8192, 256, 12, 1, 0, 100), true);
    const claims = rowCids.map((rowCid, index) => {
      assert.equal(salesforceMoon.salesforceCollectionWriteRequestRowCid(
        outbound, index), rowCid);
      const key = keys[index];
      const locator = effect.logicalItemLocator(scope, 'program-1',
        'node-1', 'CreateTwo', canonicalJson({
          content_cid: contentCids[index], occurrence: 0}),
        64, 128, 8, 3);
      const basis = effect.ledgerBasis(scope, locator, key,
        cid('6'), member.effect_member_preview_cid, cid('4'),
        requestCid, cid('3'),
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
    const options = {commonMoon, moon: salesforceMoon, request: outbound,
      currentObservation: catalog.observation,
      authorization: {...setup.write, useId: 'collection-effect-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 64, maxDepth: 6, maxRows: 200},
      claims, admittedPreview, memberIndex: 0, firstRow: 0};
    const first = open();
    t.after(() => first.close());
    const unapprovedBody = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"unapproved"}'),
      1024, 32, 5));
    const unapprovedRequest = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        rowCids, [unapprovedBody, bodies[1]], [0, 0], ['', ''], [0, 0],
        'v62.0', 256, 128, 1024, 64, 6, 200));
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, request: unapprovedRequest,
    }), {code: 'ForeignSalesforceEffectFootprint'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 0);
    const foreignPreview = structuredClone(preview);
    foreignPreview.effects[0].write_footprint.provider_boundary_cid = cid('f');
    foreignPreview.effects[0].effect_member_preview_cid =
      effect.derivePreviewIdentities(
        canonicalJson(foreignPreview), 8192, 256, 12)[1];
    foreignPreview.effect_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(foreignPreview), 8192, 256, 12)[0];
    const foreignKeys = contentCids.map(contentCid => effect.dispatchKey(
      scope, foreignPreview.effect_preview_cid,
      canonicalJson({content_cid: contentCid, occurrence: 0}),
      128, 8, 3));
    foreignPreview.effects[0].changes.forEach((change, index) => {
      change.row_idempotency_key = effect.dispatchKeyCid(foreignKeys[index]);
    });
    const foreignAdmitted = effect.admitPreviewIdentity(
      canonicalJson(foreignPreview), cid('a'), authoring, scope,
      [foreignKeys], 8192, 256, 12);
    const usesBeforeForeign = setup.journal.recover().length;
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, admittedPreview: foreignAdmitted,
    }), {code: 'ForeignSalesforceEffectFootprint'});
    assert.equal(setup.journal.recover().length, usesBeforeForeign);
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, claims: [...claims].reverse(),
    }), {code: 'MoonBitHostFailure'});
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, memberIndex: 1,
    }), {code: 'ForeignSalesforceEffectFootprint'});
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, firstRow: 1,
    }), {code: 'ForeignSalesforceEffectFootprint'});
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: first,
      claims: [{...claims[0], locator: claims[1].locator}, claims[1]],
    }), {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 0);
    const mutableLimits = {...options.limits};
    const sent = await captureSalesforceCollectionEffectWrite({
      ...options, ledger: first, limits: mutableLimits,
      callResource: async call => {
        const response = await callHttpsCredentialResource(call);
        mutableLimits.maxDepth = 0;
        return response;
      },
    });
    assert.equal(mutableLimits.maxDepth, 0);
    assert.equal(sent.claimed, true);
    assert.equal(sent.physical.kind, 'typed-row-response');
    assert.equal(sent.outcomeReceipts.length, 2);
    assert.deepEqual(sent.terminalTransitions.map(value => value.created),
      [true, true]);
    assert.deepEqual(first.readClaimedBatchOutcomes(claims)
      .map(value => value.outcomeCid), sent.outcomeReceipts.map(
      value => value.identity));
    assert.notEqual(sent.outcomeReceipts[0].identity,
      sent.outcomeReceipts[1].identity);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      sent.physical.result, 0)), true);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      sent.physical.result, 1)), false);
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 1);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const usesBeforeRetry = setup.journal.recover().length;
    for (const index of [0, 1]) {
      const terminal = await readAuthorizedEffectTerminalOutcome({
        ledger: restarted, claims, batch: true, batchRowIndex: index,
        commonMoon, expectedRequestCid: requestCid,
        preview: admittedPreview, memberIndex: 0, previewRowIndex: index,
        authorizeEvidenceRead: async () => true,
      });
      assert.equal(terminal.receipt.identity,
        sent.outcomeReceipts[index].identity);
    }
    // This checks the ordered row partition against durable physical facts;
    // aggregate member outcome admission remains a separate obligation.
    const memberReceipt = runtimeCore(commonMoon).publicationControl.seal(
      'effect_apply_receipt', JSON.stringify({
        version: 'actql-effect-apply-receipt/0.1',
        run_identity_cid: preview.run_identity_cid,
        effect_preview_cid: preview.effect_preview_cid,
        effect_member_preview_cid: member.effect_member_preview_cid,
        rows: rowCids.map((row_preview_cid, row_index) => ({
          row_index, row_preview_cid,
          state: row_index === 0 ? 'applied' : 'failed',
          dispatch_entry_cid: effect.ledgerEntryCid(
            sent.ownership.dispatching[row_index]),
          attempt_sequence: 1,
          outcome_receipt_cid: sent.outcomeReceipts[row_index].identity,
        })),
        status: 'partial_failure',
      }), {maxWireBytes: 4096, maxNodes: 512, maxDepth: 16});
    const rowOwners = [0, 1].map(batchRowIndex =>
      ({claims, batchRowIndex}));
    const evidenceBindings = [];
    assert.equal(await checkAuthorizedEffectMemberReceiptRowPartition({
      ledger: restarted, rowOwners, preview: admittedPreview,
      memberIndex: 0, memberReceiptWire: memberReceipt.wire,
      commonMoon, authorizeEvidenceRead: async binding => {
        evidenceBindings.push(binding);
        return true;
      },
    }), true);
    assert.equal(evidenceBindings.length, 1);
    assert.deepEqual(evidenceBindings[0].logicalItemLocatorCids.length, 2);
    await assert.rejects(checkAuthorizedEffectMemberReceiptRowPartition({
      ledger: restarted, rowOwners, preview: admittedPreview,
      memberIndex: 0, memberReceiptWire: memberReceipt.wire,
      commonMoon, authorizeEvidenceRead: async () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    await assert.rejects(checkAuthorizedEffectMemberReceiptRowPartition({
      ledger: restarted, rowOwners: [...rowOwners].reverse(),
      preview: admittedPreview, memberIndex: 0,
      memberReceiptWire: memberReceipt.wire, commonMoon,
      authorizeEvidenceRead: async () => true,
    }), {code: 'MoonBitHostFailure'});
    const withoutEvidence = await captureSalesforceCollectionEffectWrite({
      ...options, ledger: restarted, admittedPreview: admitPreview()});
    assert.deepEqual(withoutEvidence.ownership.actions, [5, 7]);
    assert.equal(withoutEvidence.recovered, undefined);
    assert.equal(withoutEvidence.outcomeReceipts, undefined);
    assert.equal(withoutEvidence.ownership.response, undefined);
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...options, ledger: restarted, admittedPreview: admitPreview(),
      authorizeEvidenceRead: async () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    const retry = await captureSalesforceCollectionEffectWrite({
      ...options, ledger: restarted, admittedPreview: admitPreview(),
      authorizeEvidenceRead: async () => true,
    });
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.ownership.actions, [5, 7]);
    assert.equal(retry.recovered.kind, 'typed-row-response');
    assert.equal(retry.recovered.rowCount, 2);
    assert.deepEqual(retry.outcomeReceipts.map(value => value.identity),
      sent.outcomeReceipts.map(value => value.identity));
    assert.deepEqual(retry.terminalTransitions.map(value => value.created),
      [false, false]);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      retry.recovered.result, 0)), true);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
      retry.recovered.result, 1)), false);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowCid(
      retry.recovered.result, 0)), rowCids[0]);
    assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowCid(
      retry.recovered.result, 1)), rowCids[1]);
    for (const index of [0, 1]) {
      const original = checked(
        salesforceMoon.salesforceProjectCollectionEffectOutcome(
          options.admittedPreview, 0, 0, sent.physical.result,
          index, 2048, 128, 8));
      const recovered = checked(
        salesforceMoon.salesforceProjectCollectionEffectOutcome(
          options.admittedPreview, 0, 0, retry.recovered.result,
          index, 2048, 128, 8));
      assert.equal(
        salesforceMoon.salesforceWriteEffectOutcomeRowCid(recovered),
        rowCids[index]);
      assert.deepEqual(JSON.parse(
        salesforceMoon.salesforceWriteEffectOutcomeWire(original)),
      index === 0
        ? {result: {created: true, record_id: 'a00123456789012'},
          state: 'applied'}
        // The provider's message stays in the private response.
        : {error: {code: 'SalesforceRowFailed',
          details: {errors: [{error_code: 'INVALID_FIELD',
            fields: ['External_Key__c']}]},
          message: 'Salesforce did not save the row'}, state: 'failed'});
      assert.equal(
        salesforceMoon.salesforceWriteEffectOutcomeWire(recovered),
        salesforceMoon.salesforceWriteEffectOutcomeWire(original));
      assert.equal(
        salesforceMoon.salesforceWriteEffectOutcomeResponseSha256(recovered),
        createHash('sha256').update(sent.physical.observation.body)
          .digest('hex'));
    }
    assert.throws(() => checked(
      salesforceMoon.salesforceProjectCollectionEffectOutcome(
        options.admittedPreview, 0, 1, sent.physical.result,
        0, 2048, 128, 8)), {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(
      salesforceMoon.salesforceProjectCollectionEffectOutcome(
        options.admittedPreview, 1, 0, sent.physical.result,
        0, 2048, 128, 8)), {code: 'MoonBitHostFailure'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 1);
    assert.equal(setup.journal.recover().length, usesBeforeRetry);
    for (const dispatching of sent.ownership.dispatching) {
      assert.deepEqual(restarted.response(
        effect.ledgerEntryCid(dispatching)).responseBytes,
      sent.physical.observation.body);
    }
    const recovery = {
      ledger: restarted, claims: [...claims], commonMoon,
      moon: salesforceMoon,
      request: outbound, resourceOrigin: binding.resourceOrigin,
      limits: options.limits,
    };
    const withoutWriteGrant =
      await recoverStoredSalesforceCollectionResponse({
        ...recovery,
        authorizeEvidenceRead: async observed => {
          assert.deepEqual(observed.logicalItemLocatorCids,
            claims.map(claim =>
              effect.logicalItemLocatorCid(claim.locator)));
          assert.equal(observed.canonicalRequestCid, requestCid);
          recovery.claims.reverse();
          return true;
        },
      });
    assert.equal(withoutWriteGrant.recovered.kind, 'typed-row-response');
    assert.equal(withoutWriteGrant.recovered.rowCount, 2);
    await assert.rejects(recoverStoredSalesforceCollectionResponse({
      ...recovery, claims, authorizeEvidenceRead: async () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    await assert.rejects(recoverStoredSalesforceCollectionResponse({
      ...recovery, claims: [...claims].reverse(),
      authorizeEvidenceRead: async () => true,
    }), {code: 'EffectCollectionResponseBindingMismatch'});
    await assert.rejects(recoverStoredSalesforceCollectionResponse({
      ...recovery, claims, request: unapprovedRequest,
      authorizeEvidenceRead: async () => true,
    }), {code: 'ForeignSalesforceEffectResponse'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 1);
    assert.equal(setup.journal.recover().length, usesBeforeRetry);

    const faultRoot = await mkdtemp(join(tmpdir(),
      'actql-salesforce-collection-terminal-retry-'));
    t.after(() => rm(faultRoot, {recursive: true, force: true}));
    const openFault = () => openEffectLedger({moon: commonMoon,
      root: faultRoot, authorityScopeCid,
      callerRequestId: 'collection-business-request', maxEntryBytes: 4096});
    const faultLedger = openFault();
    t.after(() => faultLedger.close());
    let terminalCalls = 0;
    const interrupted = Object.freeze({...faultLedger,
      commitAdmittedRowOutcome(args) {
        terminalCalls++;
        if (terminalCalls === 2) {
          throw new Error('InjectedSecondRowTerminalFailure');
        }
        return faultLedger.commitAdmittedRowOutcome(args);
      },
    });
    const faultOptions = {...options,
      authorization: {...options.authorization,
        useId: 'collection-effect-fault-use'}};
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ...faultOptions, ledger: interrupted,
    }), {message: 'InjectedSecondRowTerminalFailure'});
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 2);
    assert.deepEqual(claims.map(claim => JSON.parse(faultLedger.current(
      effect.logicalItemLocatorCid(claim.locator)).entryJson).state),
    ['applied', 'dispatching']);
    assert.deepEqual(faultLedger.readClaimedBatchOutcomes(claims).map(
      value => value !== undefined), [true, true]);
    faultLedger.close();
    const resumed = openFault();
    t.after(() => resumed.close());
    const reconciled = await captureSalesforceCollectionEffectWrite({
      ...faultOptions, ledger: resumed,
      authorizeEvidenceRead: async () => true,
    });
    assert.equal(reconciled.claimed, false);
    assert.deepEqual(reconciled.ownership.actions, [5, 3]);
    assert.deepEqual(reconciled.terminalTransitions.map(value => value.created),
      [false, true]);
    const repeated = await captureSalesforceCollectionEffectWrite({
      ...faultOptions, ledger: resumed,
      authorizeEvidenceRead: async () => true,
    });
    assert.deepEqual(repeated.ownership.actions, [5, 7]);
    assert.deepEqual(repeated.terminalTransitions.map(value => value.created),
      [false, false]);
    assert.equal(setup.seen.filter(item => item.path?.endsWith(
      '/composite/sobjects')).length, 2);
  });

test('Collections cannot swap two Preview targets before the send claim',
  async t => {
    const setup = await fixture(t);
    const catalog = await syncSalesforceCatalog(request(setup));
    const binding = setup.list.scope;
    const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
      catalog.observation,
      binding.namespaceId, binding.principal, binding.environment,
      'connection-revision-a', setup.orgId,
      binding.siteKey, binding.siteGeneration,
      binding.connectorRegistration, binding.connectorRevision,
      binding.resourceOrigin, binding.runInvocationCid,
      binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
      1, '', ['External_Key__c'], 2));
    const body = checked(salesforceMoon.salesforcePrepareWriteBody(
      projection, Buffer.from('{"External_Key__c":"changed"}'),
      1024, 32, 5));
    const targets = ['001000000000001', '001000000000002'];
    const rowCids = targets.map(target => independentPreviewRowCid(
      'update', target,
      {state: 'version', version_cid: cid('a')},
      {state: 'present', value: {External_Key__c: 'changed'}},
      {state: 'present', value: {External_Key__c: 'old'}},
      {state: 'present', value: {External_Key__c: 'changed'}}));
    const outbound = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        rowCids, [body, body], [1, 1], [...targets].reverse(), [0, 0],
        'v62.0', 256, 128, 1024, 64, 6, 200));
    const requestCid = checked(
      salesforceMoon.salesforceCollectionWriteRequestCid(
        outbound, binding.resourceOrigin, 4096));
    const physicalTargets = rowCids.map((_, index) => checked(
      salesforceMoon.salesforceCollectionWriteRequestTargetIdentity(
        outbound, index, 4096)));
    const effect = runtimeCore(commonMoon).effectApplicationControl;
    const authorityScopeCid = cid('8');
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'swapped-target-business-request', 128);
    const authoring =
      'sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a';
    const member = {
      effect_id: 'UpdateTwo', effect_kind: 'update',
      target: 'Test_Record__c', mapping: 'mapping:fixture',
      resolved_mapping_contract_cid: cid('a'),
      effect_identity_cid: cid('a'), preview_strength: 'full_diff',
      source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
      authority_scope_cid: authorityScopeCid,
      write_footprint: {
        kind: 'exact_targets',
        resource_identity_scheme_cid:
          salesforceMoon.salesforceWriteTargetSchemeCid(physicalTargets[0]),
        provider_namespace: 'salesforce',
        provider_boundary_cid:
          salesforceMoon.salesforceWriteTargetBoundaryCid(physicalTargets[0]),
        resource_kind: 'Test_Record__c',
        provider_object_identity_cids: physicalTargets.map(target =>
          salesforceMoon.salesforceWriteTargetObjectCid(target)),
      },
      count: 2, max_items: 2, required_permissions: ['write'],
      approval: 'none', on_item_failure: 'continue',
      changes: rowCids.map((rowCid, index) => ({
        target_row_identity: targets[index],
        target_guard: {state: 'version', version_cid: cid('a')},
        intended_changes: {state: 'present', value: {
          External_Key__c: 'changed'}},
        before: {state: 'present', value: {External_Key__c: 'old'}},
        after: {state: 'present', value: {External_Key__c: 'changed'}},
        row_preview_cid: rowCid,
        row_idempotency_key: cid(index === 0 ? '4' : '5'),
      })),
      row_order: rowCids, effect_member_preview_cid: cid('a'),
      executed: false,
    };
    const preview = {
      version: 'actql-effect-preview/0.1', sensitivity: 'private',
      retention_class: 'authority-evidence', encryption_required: true,
      program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
      invocation_cid: cid('a'), run_identity_cid: cid('a'),
      compiled_plan_cid: cid('a'), check_environment_cid: cid('a'),
      authoring_context: {
        version: 'actql-authoring-context/0.1',
        program_definition_cid: cid('a'), annotations: [],
        authoring_context_cid: authoring,
      },
      barrier_provenance_cids: [], model_derived: false,
      model_task_contract_cids: [], model_invocation_evidence_cids: [],
      model_response_artifact_cids: [], effects: [member], executed: false,
      effect_preview_cid: cid('a'),
    };
    assert.deepEqual(effect.derivePreviewRowIdentities(
      canonicalJson(preview), 8192, 256, 12), [rowCids]);
    member.effect_member_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(preview), 8192, 256, 12)[1];
    preview.effect_preview_cid = effect.derivePreviewIdentities(
      canonicalJson(preview), 8192, 256, 12)[0];
    const keys = targets.map(target => effect.dispatchKey(
      scope, preview.effect_preview_cid, canonicalJson(target), 128, 8, 3));
    member.changes.forEach((change, index) => {
      change.row_idempotency_key = effect.dispatchKeyCid(keys[index]);
    });
    const admittedPreview = effect.admitPreviewIdentity(
      canonicalJson(preview), cid('a'), authoring, scope, [keys],
      8192, 256, 12);
    const ordered = checked(
      salesforceMoon.salesforcePrepareContinueWriteCollection(
        rowCids, [body, body], [1, 1], targets, [0, 0],
        'v62.0', 256, 128, 1024, 64, 6, 200));
    const sentRecord = JSON.parse(
      salesforceMoon.salesforceCollectionWriteRequestBody(ordered)).records[0];
    assert.equal(sentRecord.External_Key__c, 'changed');
    assert.equal(checked(
      salesforceMoon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
        admittedPreview, 0, 0, ordered, 4096, 100_000)), true);
    assert.equal(checked(
      salesforceMoon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
        admittedPreview, 0, 0, outbound, 4096, 100_000)), false);
    const singleFirst = checked(
      salesforceMoon.salesforcePrepareSingleWriteRequest(
        body, 'v62.0', 1, targets[0], 0, 256, 128, 1024));
    assert.equal(salesforceMoon.salesforceSingleWriteRequestBody(singleFirst),
      '{"External_Key__c":"changed"}');
    const singleSecond = checked(
      salesforceMoon.salesforcePrepareSingleWriteRequest(
        body, 'v62.0', 1, targets[1], 0, 256, 128, 1024));
    assert.equal(checked(
      salesforceMoon.salesforceSingleWriteRequestMatchesPreviewFootprint(
        admittedPreview, 0, 0, singleFirst, 4096)), true);
    assert.equal(checked(
      salesforceMoon.salesforceSingleWriteRequestMatchesPreviewFootprint(
        admittedPreview, 0, 0, singleSecond, 4096)), false);
    const claims = rowCids.map((rowCid, index) => {
      const locator = effect.logicalItemLocator(scope, 'program-1',
        'node-1', 'UpdateTwo', canonicalJson(targets[index]),
        64, 128, 8, 3);
      const basis = effect.ledgerBasis(scope, locator, keys[index],
        cid('6'), member.effect_member_preview_cid, cid('4'),
        requestCid, cid('3'), 'unavailable', cid('2'), cid('1'));
      return {scope, locator, key: keys[index], basis,
        intentFingerprintCid: cid('4'), canonicalRequestCid: requestCid};
    });
    const root = await mkdtemp(join(tmpdir(), 'actql-salesforce-swapped-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const ledger = openEffectLedger({moon: commonMoon, root,
      authorityScopeCid, callerRequestId: 'swapped-target-business-request',
      maxEntryBytes: 4096});
    t.after(() => ledger.close());
    const usesBefore = setup.journal.recover().length;
    await assert.rejects(captureSalesforceCollectionEffectWrite({
      ledger, claims, admittedPreview, memberIndex: 0, firstRow: 0,
      commonMoon, moon: salesforceMoon, request: outbound,
      currentObservation: catalog.observation,
      authorization: {...setup.writeUpdate, useId: 'swapped-target-use'},
      credential: setup.credential,
      limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
        maxNodes: 64, maxDepth: 6, maxRows: 200},
    }), {code: 'ForeignSalesforceEffectFootprint'});
    assert.equal(setup.journal.recover().length, usesBefore);
    assert.equal(setup.seen.filter(item => item.method === 'PATCH').length, 0);
    for (const claim of claims) {
      assert.equal(ledger.current(effect.logicalItemLocatorCid(claim.locator)),
        undefined);
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
      // A documented request-level rejection: no row was saved.
      {collectionStatus: 400, collectionResponse: JSON.stringify([
        {message: 'bad', errorCode: 'JSON_PARSER_ERROR'}]),
      expected: 'typed-row-response', failedRows: 1},
      // A provider failure keeps every row unknown.
      {collectionStatus: 500, collectionResponse: JSON.stringify([
        {message: 'bad', errorCode: 'UNKNOWN_EXCEPTION'}]),
      expected: 'provider-response'},
    ]) {
      await t.test(`${scenario.collectionStatus} ${scenario.expected}`,
        async child => {
        const setup = await fixture(child, scenario);
        const catalog = await syncSalesforceCatalog(request(setup));
        const binding = setup.list.scope;
        const projection = checked(
          salesforceMoon.salesforcePrepareWriteProjection(
            catalog.observation,
            binding.namespaceId, binding.principal, binding.environment,
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
        if (scenario.failedRows !== undefined) {
          assert.equal(result.rowCount, scenario.failedRows);
          assert.equal(checked(
            salesforceMoon.salesforceCollectionWriteResponseRowApplied(
              result.result, 0)), false);
        }
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
            binding.namespaceId, binding.principal, binding.environment,
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
        assert.equal(checked(salesforceMoon.salesforceCollectionWriteResponseRowApplied(
          result.result, 0)), true);
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
        binding.namespaceId, binding.principal, binding.environment,
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
          binding.namespaceId, binding.principal, binding.environment,
          'connection-revision-a', connection.orgId,
          binding.siteKey, binding.siteGeneration,
          binding.connectorRegistration, binding.connectorRevision,
          binding.resourceOrigin, binding.runInvocationCid,
          binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
          operation === 'record' ? 1 : 2,
          operation === 'record' ? '' : 'External_Key__c',
          ['External_Key__c'], 2));
      const body = checked(salesforceMoon.salesforcePrepareWriteBody(
        projection, Buffer.from('{"External_Key__c":"changed"}'),
        1024, 32, 5));
      const outbound = checked(
        salesforceMoon.salesforcePrepareSingleWriteRequest(
          body, 'v62.0', operation === 'record' ? 1 : 2,
          value, 0, 256, 128, 1024));
      return checked(salesforceMoon.salesforceSingleWriteRequestTargetIdentity(
        outbound, 4096));
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
          binding.namespaceId, binding.principal, binding.environment,
          'connection-revision-a', setup.orgId,
          binding.siteKey, binding.siteGeneration,
          binding.connectorRegistration, binding.connectorRevision,
          binding.resourceOrigin, binding.runInvocationCid,
          binding.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c',
          2, 'External_Key__c', ['Value__c'], 2));
      const body = checked(salesforceMoon.salesforcePrepareWriteBody(
        projection, Buffer.from('{"Value__c":"changed"}'),
        1024, 32, 5));
      const target = value => {
        const outbound = checked(
          salesforceMoon.salesforcePrepareSingleWriteRequest(
            body, 'v62.0', 2, value, 0, 256, 128, 1024));
        return checked(
          salesforceMoon.salesforceSingleWriteRequestTargetIdentity(
            outbound, 4096));
      };
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
      principal: 'principal-a', namespaceId: 'namespace-a', environment: 'test',
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
      principal: 'principal-a', namespaceId: 'namespace-a', environment: 'test',
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
    const scope = setup.list.scope;
    assert.equal(checked(salesforceMoon.salesforceCatalogObservedResourceState(
      result.observation, scope.namespaceId, scope.principal, scope.environment,
      'connection-revision-a', setup.orgId, scope.siteKey,
      scope.siteGeneration, scope.connectorRegistration,
      scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
      scope.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c')), 3);
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
    const scope = setup.list.scope;
    assert.equal(checked(salesforceMoon.salesforceCatalogObservedResourceState(
      result.observation, scope.namespaceId, scope.principal, scope.environment,
      'connection-revision-a', setup.orgId, scope.siteKey,
      scope.siteGeneration, scope.connectorRegistration,
      scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
      scope.dispatchRequestCid, 'catalog-sync-a', 'Test_Record__c')), -2);
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
    binding.namespaceId, binding.principal, binding.environment,
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

test('Query continuation compares against its owned initial binding',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const mutableScope = {...setup.query.scope};
    const result = await readSalesforceQuery(queryRequest(setup, plan, {
      initialAuthorization: {...setup.query, useId: 'mutable-query-initial',
        scope: mutableScope},
      callResource: async call => {
        const response = await callHttpsCredentialResource(call);
        if (call.scope.operation === 'salesforce:query:read' &&
            call.useId === 'mutable-query-initial') {
          mutableScope.namespaceId = 'namespace-b';
          mutableScope.siteGeneration = 5;
          mutableScope.runInvocationCid = cid('9');
        }
        return response;
      },
    }));
    assert.equal(result.rowCount, 2n);
    assert.equal(result.pages.length, 2);
    assert.equal(setup.journal.inspect(result.pages[1].useCid).outcome,
      'succeeded');
    assert.deepEqual(setup.seen.slice(-2).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
  });

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

test('neutral query page charges are owned before decoding and handed off exactly',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const events = [], bodies = [], paths = [], charges = [];
    let decoded = 0;
    const moon = {...salesforceMoon,
      salesforceQueryReadAcceptPage(read, path, body) {
        const index = decoded++;
        assert.equal(body, bodies[index]);
        assert.equal(path, paths[index]);
        assert.equal(charges.length, index + 1);
        assert.equal(events.at(-1), `charged:${index}`);
        events.push(`decode:${index}`);
        return salesforceMoon.salesforceQueryReadAcceptPage(read, path, body);
      },
    };
    const options = queryRequest(setup, plan, {
      moon,
      callResource: async call => {
        const response = await callHttpsCredentialResource(call);
        if (call.scope.operation === 'salesforce:query:read') {
          events.push(`received:${bodies.length}`);
          bodies.push(response.body);
          paths.push(call.operations.get(call.scope.operation).path);
        }
        return response;
      },
      chargePage: async body => {
        const index = charges.length;
        assert.equal(body, bodies[index]);
        assert.ok(body.byteLength > 0);
        assert.equal(decoded, index);
        events.push(`charging:${index}`);
        // The driver must await admission before decoding this body.
        await Promise.resolve();
        const charge = Object.freeze({index});
        charges.push(charge);
        events.push(`charged:${index}`);
        return charge;
      },
      consumePage: async (page, context) => {
        assert.ok(Object.isFrozen(context));
        assert.equal(context.charge, charges[context.pageIndex]);
        assert.equal(context.path, paths[context.pageIndex]);
        assert.equal(salesforceMoon.salesforceQueryPageRowCount(page), 1);
        events.push(`consume:${context.pageIndex}`);
      },
    });
    const refresh = options.refreshCatalog;
    options.refreshCatalog = {...refresh,
      async authorizationForDescribe(name) {
        const authorization = await refresh.authorizationForDescribe(name);
        // Mutating caller options during an await cannot replace the owner.
        options.chargePage = () => assert.fail('ReplacedPageChargeCallback');
        return authorization;
      },
    };
    const result = await readSalesforceQuery(options);
    assert.equal(result.rowCount, 2n);
    assert.equal(decoded, 2);
    assert.equal(charges.length, 2);
    assert.notEqual(charges[0], charges[1]);
    assert.deepEqual(events, [
      'received:0', 'charging:0', 'charged:0', 'decode:0', 'consume:0',
      'received:1', 'charging:1', 'charged:1', 'decode:1', 'consume:1',
    ]);
    assert.deepEqual(result.pages.map(page => page.responseSha256),
      bodies.map(body => createHash('sha256').update(body).digest('hex')));
    assert.deepEqual(paths, [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
  });

test('refused neutral page charge interrupts before provider decoding or delivery',
  async t => {
    const setup = await fixture(t, {queryFirstResponse: '{invalid-json'});
    const plan = await queryProjection(setup);
    const refusal = Object.assign(new Error('PageChargeRefused'),
      {code: 'PageChargeRefused'});
    let charged = 0, decoded = 0, delivered = 0, interrupted = 0;
    const moon = {...salesforceMoon,
      salesforceQueryReadAcceptPage(...args) {
        decoded++;
        return salesforceMoon.salesforceQueryReadAcceptPage(...args);
      },
      salesforceQueryReadInterrupt(...args) {
        interrupted++;
        return salesforceMoon.salesforceQueryReadInterrupt(...args);
      },
    };
    await assert.rejects(readSalesforceQuery(queryRequest(setup, plan, {
      moon,
      chargePage: async body => {
        charged++;
        assert.equal(Buffer.from(body).toString('utf8'), '{invalid-json');
        throw refusal;
      },
      consumePage: async () => { delivered++; },
    })), error => error === refusal);
    assert.equal(charged, 1);
    assert.equal(decoded, 0);
    assert.equal(delivered, 0);
    assert.equal(interrupted, 1);
    assert.deepEqual(setup.seen.filter(entry =>
      entry.path?.includes('/query')).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
    ]);
    assert.deepEqual(setup.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).map(entry => entry.useId),
    ['query-initial']);
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

test('managed output rejects a locator before excess HTTP and credential use',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceManagedQuery(queryRequest(setup, plan, {
      moon: salesforceMoon,
      values: salesforceConformance.salesforceSiteTestOutputValues(),
      limits: {...queryLimits, maxPages: 1},
    })), {code: 'MoonBitHostFailure'});
    assert.deepEqual(setup.seen.filter(entry =>
      entry.path?.includes('/query')).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
    ]);
    assert.deepEqual(setup.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).map(entry => entry.useId),
    ['query-initial']);
  });

test('managed output rejects a foreign continuation before credential use',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceManagedQuery(queryRequest(setup, plan, {
      moon: salesforceMoon,
      values: salesforceConformance.salesforceSiteTestOutputValues(),
      authorizationForPage: async () => ({...setup.query,
        useId: 'foreign-managed-continuation',
        scope: {...setup.query.scope, siteGeneration: 5}}),
    })), {code: 'InvalidSalesforceQueryAuthorization'});
    assert.deepEqual(setup.seen.filter(entry =>
      entry.path?.includes('/query')).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
    ]);
    assert.deepEqual(setup.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).map(entry => entry.useId),
    ['query-initial']);
  });

test('managed output cannot append a fresh query after locator failure',
  async t => {
    const setup = await fixture(t, {querySecondStatus: 503});
    const plan = await queryProjection(setup);
    await assert.rejects(readSalesforceManagedQuery(queryRequest(setup, plan, {
      moon: salesforceMoon,
      values: salesforceConformance.salesforceSiteTestOutputValues(),
    })), {code: 'SalesforceQueryResourceRejected'});
    assert.deepEqual(setup.seen.filter(entry =>
      entry.path?.includes('/query')).map(entry => entry.path), [
      '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account',
      '/services/data/v62.0/query/01gABC-2000',
    ]);
    assert.deepEqual(setup.journal.recover().filter(entry =>
      entry.useId.startsWith('query-')).map(entry => entry.useId),
    ['query-initial', 'query-continuation']);
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

test('invalid physical caller is rejected before a query owner or HTTP use',
  async t => {
    const setup = await fixture(t);
    const plan = await queryProjection(setup);
    const requests = setup.seen.length;
    for (const callbacks of [{callResource: null}, {chargePage: null}]) {
      await assert.rejects(readSalesforceQuery(queryRequest(setup, plan,
        callbacks)), {code: 'InvalidSalesforceQueryRead'});
      assert.equal(setup.seen.length, requests);
    }
    assert.equal(setup.seen.filter(entry => entry.path?.includes('/query'))
      .length, 0);
  });
