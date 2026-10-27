import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {HubSpotAccountObservationFailure} from '../site/hubspot-account-read.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

test('actual identity request uses its original credential and RowRun charge without a data page', async t => {
  const f = await accountFixture(t);
  const result = await f.observe();
  assert.deepEqual(f.state.requests, [{method: 'GET', path: '/account-info/v3/details',
    authorization: 'Bearer provider-secret'}]);
  assert.deepEqual(result.identity, {portalId: '7', responseSha256:
    createHash('sha256').update(f.state.body).digest('hex')});
  assert.equal(result.response.body.toString(), f.state.body);
  assert.equal(f.journal.inspect(result.response.useCid).outcome, 'succeeded');
  assert.equal(f.state.charges, 1); assert.equal(f.state.consumed, 1);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(Buffer.byteLength(f.state.body)));
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  f.row.assertNoCapture();
  assert.equal(f.state.resolutions, 1); assert.equal(f.state.currentCalls, 4);
  assert.equal(Object.keys(f.binding).length, 0);
  assert.equal(JSON.stringify(result).includes('provider-secret'), false);
});

test('foreign or rounded account responses keep actual raw custody and charges without consuming the observation', async t => {
  for (const [body, issue] of [
    ['{"portalId":8}', 'ForeignAccount'],
    ['{"portalId":7.0000000000000000001}', 'InvalidResponse'],
    ['{"status":"error"}', 'InvalidResponse'],
  ]) {
    const f = await accountFixture(t); f.state.body = body;
    await assert.rejects(f.observe(), error => {
      assert.ok(error instanceof HubSpotAccountObservationFailure);
      assert.equal(error.code, 'HubSpotAccountIdentityRefused');
      assert.equal(error.cause.refusal.issue, issue);
      assert.equal(error.observation.body.toString(), body);
      assert.equal(Object.keys(error).includes('observation'), false);
      return true;
    });
    assert.equal(f.state.requests.length, 1); assert.equal(f.state.consumed, 0);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(Buffer.byteLength(body)));
    f.row.assertNoCapture();
  }
});

test('permission is explicit and identity requires its own operation and original private binding before send', async t => {
  const f = await accountFixture(t);
  for (const overrides of [
    {credential: {...f.options.credential, binding: undefined}},
    {consumeObservation: undefined}, {chargeResponse: undefined},
    {moon: {}},
  ]) await assert.rejects(f.observe(overrides), {code: 'InvalidHubSpotAccountObservation'});
  await assert.rejects(f.observe({credential: {...f.options.credential, binding: {}}}),
    {code: 'ForeignRemoteCredentialBinding'});
  const otherScope = {...f.scope, operation: 'hubspot:objects:list'};
  const other = f.control.prepare(otherScope);
  f.journal.acceptGrant(f.sign(other), f.control);
  await assert.rejects(f.observe({authorization: {grant: other,
    scope: otherScope, useId: 'wrong-operation'}}), {code: 'ForeignHubSpotAccountOperation'});
  await assert.rejects(f.observe({authorization: {grant: other,
    scope: f.scope, useId: 'not-an-identity-grant'}}));
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.equal(f.journal.recover().length, 0); assert.equal(f.state.charges, 0);
});

test('actual original Host Account denial prevents identity resolution or I/O', async t => {
  const f = await accountFixture(t, {accountOutcome: 'deny'});
  await assert.rejects(f.observe(), {code: 'ExecutionAuthorizationDenied'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.equal(f.journal.recover().length, 0); assert.equal(f.state.charges, 0);
});

test('Host Account replacement before the request preserves its original refusal before identity I/O', async t => {
  const f = await accountFixture(t); await f.writeAccount('deny');
  await assert.rejects(f.observe(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.equal(f.journal.recover().length, 0); assert.equal(f.state.charges, 0);
});

test('Credential revocation while resolving the original secret prevents an identity send', async t => {
  const f = await accountFixture(t);
  f.state.resolve = () => f.journal.revoke(f.control.identity(f.grant));
  await assert.rejects(f.observe());
  assert.equal(f.state.resolutions, 1); assert.equal(f.state.requests.length, 0);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
  assert.equal(f.state.charges, 0); assert.equal(f.state.consumed, 0);
});

test('Account replacement during the original resolver await refuses before physical send', async t => {
  const f = await accountFixture(t);
  f.state.resolve = async () => { await f.writeAccount('deny'); };
  await assert.rejects(f.observe(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.state.resolutions, 1);
  assert.equal(f.state.requests.length, 0);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
  assert.equal(f.state.charges, 0); assert.equal(f.state.consumed, 0);
});

test('Host Account replacement across the actual response keeps bytes but refuses disclosure and capture', async t => {
  const f = await accountFixture(t);
  f.state.onRequest = async () => { await f.writeAccount('deny'); return false; };
  await assert.rejects(f.observe(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.cause.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observation.body.toString(), f.state.body);
    return true;
  });
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.charges, 1);
  assert.equal(f.state.consumed, 0); f.row.assertNoCapture();
  assert.equal(f.journal.recover()[0].outcome, 'succeeded',
    'the observed HTTP success is distinct from current disclosure permission');
});

test('HTTP refusal bodies are charged and retained without granting an account observation', async t => {
  const f = await accountFixture(t); f.state.status = 403; f.state.body = '{"message":"denied"}';
  await assert.rejects(f.observe(), error => {
    assert.equal(error.code, 'HubSpotAccountObservationRejected');
    assert.equal(error.observation.statusCode, 403);
    assert.equal(error.observation.body.toString(), f.state.body); return true;
  });
  assert.equal(f.state.charges, 1); assert.equal(f.state.consumed, 0);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
  assert.equal(f.state.requests.length, 1);
});

test('current Account is checked again after the awaited original charge consumption', async t => {
  const f = await accountFixture(t);
  await assert.rejects(f.observe({consumeObservation: async charge => {
    f.options.consumeObservation(charge);
    await f.writeAccount('deny');
  }}), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observation.body.toString(), f.state.body);
    return true;
  });
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.consumed, 1);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(Buffer.byteLength(f.state.body)));
  f.row.assertNoCapture();
});

test('cancellation after a received observation preserves its original AbortError and bounded custody', async t => {
  const f = await accountFixture(t);
  const controller = new AbortController();
  await assert.rejects(f.observe({signal: controller.signal,
    consumeObservation: charge => {
      f.options.consumeObservation(charge); controller.abort();
    }}), error => {
    assert.equal(error.name, 'AbortError'); assert.equal(error.code, controller.signal.reason.code);
    assert.equal(error.cause, controller.signal.reason);
    assert.equal(error.observation.body.toString(), f.state.body);
    return true;
  });
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.consumed, 1);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  f.row.assertNoCapture();
});

test('cleanup during a suspended resolver retains the same original custody until actual completion', async t => {
  const f = await accountFixture(t);
  let resume, started;
  const entered = new Promise(resolve => { started = resolve; });
  f.state.resolve = () => new Promise(resolve => { resume = resolve; started(); });
  const result = f.observe();
  await entered;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  assert.equal(f.state.requests.length, 0);
  resume();
  await assert.rejects(result, {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
});

test('lost identity reply stays unknown under the original use and duplicate use cannot resend', async t => {
  // This case qualifies Credential/transport Unknown, not unreported RowRun
  // transfer funding. No complete response byte observation is fabricated.
  const f = await accountFixture(t, {accounted: false});
  f.state.onRequest = request => { request.socket.destroy(); return true; };
  await assert.rejects(f.observe(), {code: 'ECONNRESET'});
  const original = f.journal.recover()[0];
  assert.equal(original.outcome, 'unknown');
  await assert.rejects(f.observe(), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(f.journal.recover()[0].useCid, original.useCid);
  assert.equal(f.journal.recover()[0].outcome, 'unknown');
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.resolutions, 1);
  assert.equal(f.state.charges, 0); assert.equal(f.state.consumed, 0);
});
