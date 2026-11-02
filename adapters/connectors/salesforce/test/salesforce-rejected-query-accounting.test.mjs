// Actual exported JS sequencers with explicit compiler, authorization, current,
// transport and accounting ports. No nominal Core, RowRun, Account or HTTPS
// acceptance is inferred from these callback-boundary cases.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readSalesforceQuery, readSalesforceManagedQuery} from
  '../site/salesforce-query-read.mjs';
import {credentialInvocationBindingKeys} from
  '../../../host-common/credential-scope-fields.generated.mjs';
import {createInstalledCredentialSourceReader} from
  '../../../host-node/installed-credential-source-reader.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {prepareSalesforceSourceReadSequence, readSalesforceSourceChild} from
  '../site/salesforce-query-read.mjs';

const operation = 'salesforce:query:read';
const path = '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account';
// Explicit pinned-compiler Result port, not an opaque-value issuer or ABI test.
const ok = value => ({$tag: 1, _0: value});
const forbidden = () => assert.fail('Rejected response reached provider admission or delivery');

function fixture(mode, accounting) {
  const plan = Object.freeze({port: 'projection'});
  const read = Object.freeze({port: 'original-read'});
  const values = Object.freeze({port: 'managed-values'});
  const observation = Object.freeze({port: 'current-catalog'});
  const grant = Object.freeze({port: 'original-grant'});
  const scope = Object.freeze({
    ...Object.fromEntries(credentialInvocationBindingKeys.map(key => [key, 'same'])),
    operation, siteGeneration: 1,
  });
  const response = {accepted: false, statusCode: 503,
    body: Buffer.from('original rejected response')};
  const events = [];
  let requests = 0;
  const moon = {
    salesforceReadProjectionScopeMatches(actualPlan, ...fields) {
      assert.equal(actualPlan, plan);
      assert.deepEqual(fields, ['namespaceId', 'principal', 'environment',
        'siteKey', 'siteGeneration', 'connectorRegistration',
        'connectorRevision', 'resourceOrigin', 'runInvocationCid',
        'dispatchRequestCid'].map(key => scope[key]));
      return true;
    },
    salesforceRecheckReadProjection(actualPlan, actualObservation) {
      assert.equal(actualPlan, plan); assert.equal(actualObservation, observation);
      events.push('current'); return ok(undefined);
    },
  };
  const prefix = mode === 'raw' ? 'salesforceQueryRead' : 'salesforceManagedQuery';
  const begin = (...args) => {
    assert.equal(args[0], plan); assert.equal(args[1], 'v62.0');
    assert.equal(args[8], 2n);
    if (mode === 'managed') assert.equal(args[9], values);
    events.push('begin'); return ok(read);
  };
  moon[mode === 'raw' ? 'salesforceBeginQueryRead' : 'salesforcePrepareManagedQuery'] = begin;
  moon[prefix + 'NextPath'] = actual => {
    assert.equal(actual, read); events.push('next'); return ok(path);
  };
  for (const suffix of ['AcceptPage', 'Complete', 'RowCount', 'Finish', 'AcknowledgePage']) {
    moon[prefix + suffix] = forbidden;
  }
  moon[prefix + (mode === 'raw' ? 'Interrupt' : 'Cancel')] = actual => {
    assert.equal(actual, read); events.push('interrupt');
  };
  const options = {
    moon, plan, values, apiVersion: 'v62.0',
    initialAuthorization: {grant, scope, useId: 'same-query-use'},
    authorizationForPage: forbidden,
    credential: {port: 'credential'},
    refreshCatalog: async () => ({status: 'complete', observation}),
    limits: {maxBytes: 1024, maxNodes: 100, maxDepth: 8, maxRows: 2,
      maxLocatorUnits: 1024, maxPages: 2, maxTotalRows: 2},
    async callResource(input) {
      assert.equal(++requests, 1); assert.equal(input.grant, grant);
      assert.equal(input.returnRejectedResponse, true);
      assert.equal(input.maxResponseBytes, 1024);
      assert.deepEqual([...input.operations], [[operation, {method: 'GET', path}]]);
      events.push('response'); return response;
    },
    async chargePage(body) {
      assert.equal(body, response.body); events.push('charge');
      if (accounting) await accounting({response, events});
      events.push('charged'); return Object.freeze({port: 'original-charge'});
    },
    consumePage: forbidden,
  };
  return {events, response,
    run: () => (mode === 'raw' ? readSalesforceQuery : readSalesforceManagedQuery)(options)};
}

for (const mode of ['raw', 'managed']) {
  test(`Salesforce ${mode} query charges the original rejected body before refusal`, async () => {
    const f = fixture(mode);
    await assert.rejects(f.run(), error => error.code === 'SalesforceQueryResourceRejected');
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'charged', 'interrupt']);
  });
}

// Actual shared Reader plus the existing Salesforce query sequencer. The Site
// issuer, typed codecs, same-parent capacity and physical Resource are explicit
// ports; this is not normal Common/HTTPS or numerical backing acceptance.
function managedSourceFixture({rejected = false, consumeFailure = false} = {}) {
  const events = [], cells = Object.freeze([Object.freeze([Object.freeze({typed: true})])]);
  const columns = Object.freeze(['Id']), acquisition = Object.freeze({}), declaration = Object.freeze({});
  const plan = Object.freeze({}), query = Object.freeze({}), observation = Object.freeze({});
  const root = Object.freeze({grant: Object.freeze({}), scope: Object.freeze({
    ...Object.fromEntries(credentialInvocationBindingKeys.map(key => [key, 'same'])), operation,
    runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch', siteGeneration: 1})});
  const originalCredential = Object.freeze({}), boundCredential = Object.freeze({});
  const originals = new Set([root]), chargeByBody = new Map();
  let pages = 0, closes = 0, charges = 0, consumed = 0;
  const preparedRead = Object.freeze({acquisition, resource: 'Account', nonce: 'original',
    runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch'});
  const site = Object.freeze({credential: originalCredential, apiVersion: 'v62.0',
    async describeForAcquisition(request) {
      assert.equal(this, site);assert.equal(request.resource, 'Account');
      assert.equal(request.runInvocationCid, 'original-run');
      assert.equal(request.dispatchRequestCid, 'original-dispatch');
      const metadata = Object.freeze({grant: Object.freeze({}),
        scope: Object.freeze({...root.scope, operation: 'salesforce:catalog:describe'})});
      originals.add(metadata);
      await invokeScopedCredentialOperation({authorization: {...metadata, useId: request.occurrence},
        credential: originalCredential, operation: 'salesforce:catalog:describe', method: 'GET',
        path: '/services/data/v62.0/sobjects/Account/describe', maxResponseBytes: 1024,
        callResource: input => request.readChild(metadata, input)});
      return {evidence: {observationJson: '{}'}, observationCid: 'original-observation'};
    }});
  const moon = Object.freeze({
    clientProgramRecheckSalesforceRowProjection(d, a, o, max) {
      assert.equal(d, declaration);assert.equal(a, acquisition);assert.equal(o, observation);
      assert.equal(max, 4096);events.push('plan');return ok(plan);
    }, clientProgramSalesforceQueryPageValues(page) {
      assert.equal(page, query);events.push('values');return {_0: columns, _1: cells};
    }});
  const queryMoon = Object.freeze({
    salesforceReadProjectionScopeMatches(p) {assert.equal(p, plan);return true;},
    salesforceRecheckReadProjection(p, o) {assert.equal(p, plan);assert.equal(o, observation);return ok(undefined);},
    salesforceBeginQueryRead(p) {assert.equal(p, plan);events.push('begin');return ok(query);},
    salesforceQueryReadNextPath(q) {assert.equal(q, query);return ok(pages === 0 ? path : undefined);},
    salesforceQueryReadAcceptPage(q, actualPath, body) {
      assert.equal(q, query);assert.equal(actualPath, path);assert(chargeByBody.has(body));
      events.push('decode');return ok(query);
    }, salesforceQueryReadAcknowledgePage(page) {assert.equal(page, query);pages++;return ok(undefined);},
    salesforceQueryReadComplete(q) {assert.equal(q, query);return pages === 1;},
    salesforceQueryReadRowCount(q) {assert.equal(q, query);return 1;},
    salesforceQueryPageResponseSha256() {return 'original-digest';},
    salesforceQueryPageRowCount() {return 1;},
    salesforceQueryReadInterrupt(q) {assert.equal(q, query);events.push('interrupt');},
  });
  const originalBinding = Object.freeze({credential: boundCredential, close() {closes++;return 'closed';}});
  const originalSite = Object.freeze({site, referenceCurrent() {return true;},
    authorizationPurpose(original) {assert.equal(original, root);return {kind: 'read'};},
    bindRunAcquisition(original) {assert.equal(original, root);events.push('bind');return originalBinding;},
    readChildCredential(binding, original) {
      assert.equal(binding, originalBinding);assert(originals.has(original));return boundCredential;
    }, async callResource(input) {
      assert.equal(this, site);assert([...originals].some(original => original.grant === input.grant));
      await input.currentBeforeSend();
      const selected = [...input.operations.keys()][0], isQuery = selected === operation;
      events.push(isQuery ? 'query-response' : 'describe-response');
      const response = Object.freeze({accepted: !isQuery || !rejected, statusCode: isQuery && rejected ? 503 : 200,
        body: Buffer.from(isQuery ? 'query bytes' : 'metadata bytes'), useCid: 'original-use'});
      input.responseCustody.retain(response);return response;
    }});
  const limits = Object.freeze({maxBytes: 1024, maxNodes: 100, maxDepth: 8, maxRows: 2,
    maxLocatorUnits: 1024, maxPages: 1, maxTotalRows: 2});
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite, assertCurrent() {},
    maxResponses: 3, maxResponseBytes: 1024,
    prepareReadSequence(input) {
      assert.equal(input.preparedRead, preparedRead);assert.equal(input.originalAuthorization, root);
      assert.deepEqual(events, []);
      return prepareSalesforceSourceReadSequence({moon, queryMoon, site, declaration,
        preparedRead: input.preparedRead, originalAuthorization: input.originalAuthorization,
        recover(_evidence, run) {assert.equal(run, 'original-run');events.push('recover');return observation;}, limits});
    }});
  const reader = factory.prepare(Object.freeze({originalAuthorization: root, preparedRead, columns,
    verifyRead() {}, authorizationFor() {return {...root, useId: 'original-query-0'};},
    authorizeReadChild(_operation, _index, _occurrence, supplied) {return supplied;},
    chargePage(body) {const charge = Object.freeze({});charges++;chargeByBody.set(body, charge);events.push('charge');return charge;},
    consumeObservation(charge) {assert([...chargeByBody.values()].includes(charge));events.push('observation');},
    consumeValues(names, rows, {charge}) {
      assert.equal(names, columns);assert.equal(rows, cells);assert([...chargeByBody.values()].includes(charge));
      consumed++;events.push('consume');if (consumeFailure) throw undefined;return rows.length;
    }}));
  return {reader, factory, events, counts: () => ({charges, consumed, closes, pages})};
}

test('Salesforce managed source joins two original describes and typed query on the same Reader', async () => {
  const f = managedSourceFixture();assert.deepEqual(f.events, []);
  assert.deepEqual(await f.reader.read(), {pages: 3, rowCount: 1});
  assert.deepEqual(f.events, ['bind', 'describe-response', 'charge', 'recover', 'observation', 'plan',
    'describe-response', 'charge', 'recover', 'observation', 'begin', 'query-response', 'charge', 'decode', 'values', 'consume']);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 1, closes: 1, pages: 1});
});

test('Salesforce managed source charges a rejected query once and keeps its original refusal', async () => {
  const f = managedSourceFixture({rejected: true});
  await assert.rejects(f.reader.read(), {code: 'SalesforceQueryResourceRejected'});
  assert(!f.events.includes('decode'));assert.equal(f.events.at(-1), 'interrupt');
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 0, closes: 1, pages: 0});
});

test('Salesforce managed source preserves thrown undefined without replaying a typed page', async () => {
  const f = managedSourceFixture({consumeFailure: true});let caught = false;
  try {await f.reader.read();} catch (cause) {caught = true;assert.equal(cause, undefined);}
  assert.equal(caught, true);assert.equal(f.events.at(-1), 'interrupt');
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 1, closes: 1, pages: 0});
});

test('Salesforce managed child refuses a copied-scope field substitution before the Reader', () => {
  const original = Object.freeze({grant: {}, scope: Object.freeze({operation, expiresUnixMilliseconds: 1n})});
  assert.throws(() => readSalesforceSourceChild({readChild: forbidden}, original,
    {grant: original.grant, scope: {...original.scope, expiresUnixMilliseconds: 2n},
      operations: new Map([[operation, {method: 'GET', path}]]), useId: 'original'}),
  {code: 'ForeignSalesforceSourceReadChild'});
});

for (const mode of ['raw', 'managed']) {
  test(`Salesforce ${mode} query preserves accounting failure and interrupts the original read`, async () => {
    const originalError = new Error('Original accounting refusal');
    const f = fixture(mode, () => { throw originalError; });
    await assert.rejects(f.run(), error => error === originalError);
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'interrupt']);
  });

  test(`Salesforce ${mode} query awaits pending accounting without upgrading the original rejection`, async () => {
    let entered, release;
    const started = new Promise(resolve => { entered = resolve; });
    const pending = new Promise(resolve => { release = resolve; });
    const f = fixture(mode, async ({response}) => {
      response.accepted = true;
      entered();
      await pending;
    });
    let settled = false;
    const rejected = assert.rejects(f.run(), error => error.code === 'SalesforceQueryResourceRejected')
      .finally(() => { settled = true; });
    try {
      await started;
      assert.equal(settled, false);
      assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge']);
    } finally {
      release();
    }
    await rejected;
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'charged', 'interrupt']);
  });
}
