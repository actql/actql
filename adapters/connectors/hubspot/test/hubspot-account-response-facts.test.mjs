// Actual account-read JS with explicit projection, authorization, current,
// transport and accounting ports. No Common issuer, Account/RowRun, physical
// HTTPS or ordinary Host qualification is inferred from these interleavings.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {credentialInvocationBindingKeys} from
  '../../../host-common/credential-scope-fields.generated.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION,
  HubSpotAccountObservationFailure} from '../site/hubspot-account-read.mjs';

function fixture({accepted, statusCode, accounting}) {
  const body = Buffer.from('{"portalId":7}');
  const response = {accepted, statusCode, body};
  const grant = Object.freeze({componentPort: 'original-grant'});
  const scope = Object.freeze({
    ...Object.fromEntries(credentialInvocationBindingKeys.map(name => [name, 'same'])),
    operation: HUBSPOT_ACCOUNT_DETAILS_OPERATION, siteGeneration: 1,
    resourceOrigin: 'https://api.hubapi.com',
  });
  const events = [];
  let projections = 0, consumptions = 0, requests = 0;
  const options = {
    moon: {hubspotRecheckAccountIdentityJson(actual, portalId, ...limits) {
      assert.strictEqual(actual, body); assert.equal(portalId, '7');
      assert.deepEqual(limits, [1024, 100, 8]); projections++;
      return JSON.stringify({account: {portalId: '7',
        responseSha256: createHash('sha256').update(body).digest('hex')}});
    }},
    originalPortalId: '7', authorization: {grant, scope, useId: 'same-account-use'},
    credential: {binding: Object.freeze({componentPort: 'original-binding'})},
    limits: {maxResponseBytes: 1024, maxNodes: 100, maxDepth: 8},
    async current() {events.push('current');},
    async callResource(input) {
      assert.strictEqual(input.grant, grant);
      assert.equal(input.returnRejectedResponse, true);
      assert.deepEqual([...input.operations], [[HUBSPOT_ACCOUNT_DETAILS_OPERATION,
        {method: 'GET', path: '/account-info/v3/details', headers: [['accept', 'application/json']]}]]);
      await input.currentBeforeSend(); requests++; events.push('response');
      return response;
    },
    async chargeResponse(actual) {
      assert.strictEqual(actual, body); events.push('charge');
      await accounting?.(response);
      events.push('charged'); return Object.freeze({componentPort: 'same-charge'});
    },
    async consumeObservation() {consumptions++; events.push('consume');},
  };
  return {response, body, events, options, run: () => observeHubSpotAccount(options),
    get projections() {return projections;}, get consumptions() {return consumptions;},
    get requests() {return requests;}};
}

for (const field of ['accepted', 'statusCode']) {
  test(`HubSpot account preserves original ${field} while response accounting is pending`, async () => {
    let entered, release;
    const started = new Promise(resolve => {entered = resolve;});
    const held = new Promise(resolve => {release = resolve;});
    const f = fixture({accepted: field === 'statusCode', statusCode: field === 'accepted' ? 200 : 503,
      async accounting(response) {
        response[field] = field === 'accepted' ? true : 200;
        entered(); await held;
      }});
    let settled = false;
    const refused = assert.rejects(f.run(), error => {
      assert.ok(error instanceof HubSpotAccountObservationFailure);
      assert.equal(error.code, 'HubSpotAccountObservationRejected');
      assert.strictEqual(error.observation, f.response);
      assert.strictEqual(error.observation.body, f.body);
      return true;
    }).finally(() => {settled = true;});
    try {
      await started;
      assert.equal(settled, false);
      assert.equal(f.projections, 0); assert.equal(f.consumptions, 0);
      assert.deepEqual(f.events, ['current', 'current', 'response', 'charge']);
    } finally {release();}
    await refused;
    assert.equal(f.requests, 1); assert.equal(f.projections, 0); assert.equal(f.consumptions, 0);
    assert.deepEqual(f.events, ['current', 'current', 'response', 'charge', 'charged', 'current']);
  });
}

test('HubSpot account keeps original accounting failure ahead of HTTP classification', async () => {
  const cause = new Error('Original accounting failure');
  const f = fixture({accepted: false, statusCode: 503, accounting() {throw cause;}});
  await assert.rejects(f.run(), error => {
    assert.ok(error instanceof HubSpotAccountObservationFailure);
    assert.strictEqual(error.cause, cause);
    assert.strictEqual(error.observation, f.response);
    return true;
  });
  assert.equal(f.requests, 1); assert.equal(f.projections, 0); assert.equal(f.consumptions, 0);
  assert.deepEqual(f.events, ['current', 'current', 'response', 'charge']);
});

test('HubSpot account keeps current refusal separate from the received successful HTTP outcome', async () => {
  const cause = Object.assign(new Error('Original current refusal'), {code: 'ComponentCurrentRefusal'});
  const f = fixture({accepted: true, statusCode: 200});
  let checks = 0;
  f.options.current = async () => {
    f.events.push('current');
    if (++checks === 3) throw cause;
  };
  await assert.rejects(f.run(), error => {
    assert.strictEqual(error.cause, cause);
    assert.equal(error.code, cause.code);
    assert.strictEqual(error.observation, f.response);
    return true;
  });
  assert.equal(f.requests, 1); assert.equal(f.projections, 0); assert.equal(f.consumptions, 0);
  assert.deepEqual(f.events, ['current', 'current', 'response', 'charge', 'charged', 'current']);
});

test('HubSpot account retains cancellation and original response custody after accounting', async () => {
  const controller = new AbortController(), cause = new Error('Original cancellation');
  const f = fixture({accepted: true, statusCode: 200, accounting() {controller.abort(cause);}});
  f.options.signal = controller.signal;
  await assert.rejects(f.run(), error => {
    assert.strictEqual(error.cause, cause);
    assert.strictEqual(error.observation, f.response);
    assert.strictEqual(error.observation.body, f.body);
    return true;
  });
  assert.equal(f.requests, 1); assert.equal(f.projections, 0); assert.equal(f.consumptions, 0);
  assert.deepEqual(f.events, ['current', 'current', 'response', 'charge', 'charged', 'current']);
});
