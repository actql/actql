// Actual exported JS sequencers with explicit compiler, authorization, current,
// transport and accounting ports. No nominal Core, RowRun, Account or HTTPS
// acceptance is inferred from these callback-boundary cases.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readSalesforceQuery, readSalesforceManagedQuery} from
  '../site/salesforce-query-read.mjs';
import {credentialInvocationBindingKeys} from
  '../../../host-common/credential-scope-fields.generated.mjs';

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
