import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {sendRawHubSpotRecordBatch, projectHubSpotRecordWriteObservation,
  HUBSPOT_BATCH_WRITE_OPERATIONS, HubSpotRecordWriteFailure} from '../site/hubspot-record-write.mjs';
import {recordWriteFixture as fixture, recordWriteResultBody as resultBody,
  recordWriteProperties as properties} from './hubspot-record-write.fixture.mjs';


test('real Credential Account SQLite TLS sends exact create update upsert once and projects only complete acknowledgement', async t => {
  for (const kind of ['create', 'update', 'upsert']) {
    const f = await fixture(t, kind), raw = await f.send();
    assert.deepEqual(f.writeState.writes, [moon.hubspotRecordBatchBody(f.request)]);
    assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 3);
    assert.equal(f.state.consumed, 3);
    assert.ok(f.state.requests.every(r => r.authorization === 'Bearer provider-secret'));
    const projected = f.project(raw.observation);
    assert.equal(projected.kind, 'typed-success-response');
    assert.deepEqual(moon.hubspotRecordWriteResponseRows(projected.response),
      [['9007199254740993', kind === 'create' ? 'created' : 'updated']]);
    assert.equal(f.journal.recover().filter(r => r.outcome === 'succeeded').length, 3);
    // Transport nominal success is DATA only; this fixture has no Effect
    // Preview, approval or Effect Ledger and cannot publish an applied row.
    f.row.assertNoCapture();
  }
});

test('read Allow does not authorize the write operation and no POST is sent', async t => {
  const f = await fixture(t, 'update', ['read']);
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'ExecutionAuthorizationDenied'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.writeState.writes.length, 0); assert.equal(f.state.requests.length, 2);
});

test('rotation after original identity or schema cannot send with a replacement account token', async t => {
  for (const after of [1, 2]) {
    const f = await fixture(t);
    await assert.rejects(f.send({consumeObservation: charge => {
      f.options.consumeObservation(charge);
      if (f.state.consumed === after) f.state.secret = 'different-account';
    }}), error => {
      assert.ok(error instanceof HubSpotRecordWriteFailure);
      assert.equal(error.code, 'RemoteCredentialBindingChanged');
      assert.equal(error.observations.length, after); return true;
    });
    assert.equal(f.state.requests.length, after); assert.equal(f.writeState.writes.length, 0);
    assert.ok(f.state.requests.every(r => r.authorization === 'Bearer provider-secret'));
  }
});

test('current Account revocation after awaited write retains original bytes without reporting application', async t => {
  const f = await fixture(t);
  f.writeState.responseHook = async request => {
    if (request.url.endsWith('/batch/update')) await f.writeAccount('deny'); return false;
  };
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 3);
    assert.equal(error.observations[2].body.toString(), f.writeState.body); return true;
  });
  assert.equal(f.writeState.writes.length, 1); assert.equal(f.state.charges, 3);
});

test('current schema drift refuses the write while retaining identity and schema observations', async t => {
  const f = await fixture(t);
  f.writeState.properties = properties.replace('"number"', '"string"');
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.writeState.writes.length, 0); assert.equal(f.state.requests.length, 2);
});

test('foreign generated invocation scope and missing current refuse before any write', async t => {
  const f = await fixture(t);
  await assert.rejects(f.send({current: undefined}), {code: 'InvalidHubSpotRecordWrite'});
  await assert.rejects(f.send({authorizationFor: async spec => {
    const original = await f.options.authorizationFor(spec);
    return {...original, scope: {...original.scope, dispatchRequestCid: `sha256:${'e'.repeat(64)}`}};
  }}), {code: 'ForeignHubSpotWriteAuthorization'});
  assert.equal(f.writeState.writes.length, 0); assert.equal(f.state.requests.length, 1);
});

test('lost POST response retains original nominal Unknown without any resend', async t => {
  const f = await fixture(t);
  f.writeState.responseHook = async (request, response) => {
    if (!request.url.endsWith('/batch/update')) return false;
    for await (const _ of request) { /* Drain the original request once. */ }
    f.writeState.writes.push('received-once'); response.destroy(); return true;
  };
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'ECONNRESET');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.writeState.writes.length, 1); assert.equal(f.state.requests.length, 3);
  assert.equal(f.journal.recover().filter(r => r.outcome === 'unknown').length, 1);
});

test('partial pending malformed and non-success bytes stay original unclassified response', async t => {
  for (const [status, body] of [[207, resultBody()], [200, '{"status":"PENDING","results":[]}'],
    [200, '{'], [400, '{"category":"VALIDATION_ERROR"}'], [503, '{}']]) {
    const f = await fixture(t); f.writeState.status = status; f.writeState.body = body;
    const raw = await f.send(), projected = f.project(raw.observation);
    assert.equal(projected.kind, 'unclassified-response');
    assert.equal(projected.observation, raw.observation); assert.equal(raw.observation.body.toString(), body);
    assert.equal(f.writeState.writes.length, 1); assert.equal(f.state.requests.length, 3);
  }
});

test('original binding cleanup stays pending during send and preserves Unknown until physical retirement', async t => {
  const f = await fixture(t);
  let pending;
  f.writeState.responseHook = request => {
    if (request.url.endsWith('/batch/update')) pending = closeHttpsCredentialBinding(f.binding);
    return false;
  };
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'RemoteCredentialBindingRetiring');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(pending, 'pending');
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(f.journal.recover().filter(r => r.outcome === 'unknown').length, 1);
  assert.equal(f.state.requests.length, 3);
  f.row.assertNoCapture();
});
