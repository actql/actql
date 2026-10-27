import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_RECORD_DELETE_OPERATION, KintoneDeleteFailure,
  projectKintoneDeleteObservation} from '../site/kintone-record-delete.mjs';
import {deleteFixture} from './kintone-record-delete.fixture.mjs';
import {originalForm, record} from './installed-kintone.fixture.mjs';

test('original App API IDs and paired revisions traverse real Account Site SQLite TLS once', async t => {
  const f = await deleteFixture(t);
  const raw = await f.send();
  assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, 3);
  assert.equal(f.state.charges, 3); assert.equal(f.state.consumed, 3);
  assert.deepEqual(f.state.fixtureFailures, []);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'succeeded').length, 3);
  const projected = projectKintoneDeleteObservation({moon: f.common, request: f.request,
    observation: raw.observation, limits: f.options.limits});
  assert.equal(projected.kind, 'typed-delete-response');
  assert.equal(f.common.clientProgramKintoneDeleteResponseRequest(projected.response), f.request);
  assert.equal(projected.observation, raw.observation);
  // There is no Effect Ledger or Preview in this raw component assembly.
  f.row.assertNoCapture();
});

test('read Allow cannot dispatch a DELETE under effect Deny', async t => {
  const f = await deleteFixture(t, {effect: 'deny'});
  await assert.rejects(f.send(), error => {
    assert.ok(error instanceof KintoneDeleteFailure);
    assert.equal(error.code, 'ExecutionAuthorizationDenied');
    assert.equal(error.phase, 'delete'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 2);
});

test('same original token is retained across Form target read and DELETE; rotation never substitutes', async t => {
  for (const after of [1, 2]) {
    const f = await deleteFixture(t);
    await assert.rejects(f.send({consumeObservation: charge => {
      f.options.consumeObservation(charge);
      if (f.state.consumed === after) f.state.secret = 'replacement-account-token';
    }}), error => {
      assert.equal(error.code, 'RemoteCredentialBindingChanged');
      assert.equal(error.observations.length, after); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, after);
    assert.equal(f.state.resolutions, after + 1);
  }
});

test('Form revision or field-definition drift retains charged bytes and refuses the write', async t => {
  for (const form of [{...originalForm, revision: '8'}, {...originalForm, properties: {
    ...originalForm.properties, Subject: {code: 'Subject', type: 'MULTI_LINE_TEXT'}}}]) {
    const f = await deleteFixture(t); f.state.form = () => form;
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 1); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 1);
    assert.equal(f.state.charges, 1); assert.equal(f.state.consumed, 0);
    f.row.assertNoCapture();
  }
});

test('missing extra duplicate and changed-revision observations cannot select a different deletion', async t => {
  const first = record('9007199254740992'), second = record('9007199254740993');
  for (const records of [[first], [first, second, record('9007199254740994')],
    [first, first], [first, {...second, $revision: {type: '__REVISION__', value: '10'}}]]) {
    const f = await deleteFixture(t); f.state.records = () => ({records, totalCount: null});
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 2); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 2);
    assert.equal(f.state.charges, 2); assert.equal(f.state.consumed, 1);
  }
});

test('actual current Account is rechecked after the awaited write response before disclosure', async t => {
  const f = await deleteFixture(t);
  f.state.reply = async () => {await f.writeAccount('deny'); return {body: {}};};
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 3);
    assert.equal(error.observations[2].body.toString(), '{}'); return true;
  });
  assert.equal(f.state.writes, 1); assert.equal(f.state.charges, 3);
  f.row.assertNoCapture();
});

test('current loss during the resolver await refuses before physical DELETE', async t => {
  const f = await deleteFixture(t);
  f.state.resolve = async () => {if (f.state.resolutions === 3) await f.writeAccount('deny');};
  await assert.rejects(f.send(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 2);
  assert.equal(f.journal.recover().length, 3);
});

test('lost DELETE reply remains original nominal Unknown and is never automatically resent', async t => {
  const f = await deleteFixture(t, {faults: [{method: 'POST', bodyIncludes: '"revisions"', kind: 'apply-then-lose-reply'}]});
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'ECONNRESET'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, 3);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  // Even an explicit second call with those same nominal uses is refused.
  await assert.rejects(f.send(), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, 3);
  f.row.assertNoCapture();
});

test('non-success and malformed write replies stay exact unclassified original bytes', async t => {
  for (const [status, body] of [[409, '{"code":"GAIA_CO02"}'], [200, '{'], [202, '{}']]) {
    const f = await deleteFixture(t); f.state.reply = () => ({status, body});
    const raw = await f.send();
    const projected = projectKintoneDeleteObservation({moon: f.common, request: f.request,
      observation: raw.observation, limits: f.options.limits});
    assert.equal(projected.kind, 'unclassified-response');
    assert.equal(projected.observation, raw.observation);
    assert.equal(raw.observation.body.toString(), body);
    assert.equal(f.state.writes, 1); assert.equal(f.state.charges, 3);
    f.row.assertNoCapture();
  }
});

test('generated full invocation scope, actual App, required API and current are checked before I/O', async t => {
  const f = await deleteFixture(t);
  await assert.rejects(f.send({originalAppId: '13'}), {code: 'ForeignKintoneDeleteInstallation'});
  await assert.rejects(f.send({current: undefined}), {code: 'InvalidKintoneDelete'});
  await assert.rejects(f.send({moon: {...f.common, clientProgramKintoneDeleteRecheckForm: undefined}}),
    {code: 'InvalidKintoneDelete'});
  for (const key of credentialInvocationBindingKeys) {
    await assert.rejects(f.send({authorizationFor: async spec => {
      const original = await f.authorizationFor(spec);
      const value = original.scope[key];
      return {...original, scope: {...original.scope, [key]: typeof value === 'number' ? value + 1 : value + '/foreign'}};
    }}), {code: 'ForeignKintoneDeleteAuthorization'}, key);
  }
  assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
});

test('original binding and reservation stay held until physical request and async frame retire', async t => {
  const f = await deleteFixture(t);
  let pending, rootRefused;
  f.state.reply = () => {
    pending = closeHttpsCredentialBinding(f.binding);
    try {f.closeRoot();} catch (cause) {rootRefused = cause;}
    return {body: {}};
  };
  await assert.rejects(f.send(), {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(pending, 'pending'); assert.equal(rootRefused?.code, 'MoonBitHostFailure');
  assert.ok(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]).some(value => value > 0n));
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  f.closeRoot(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  assert.equal(f.state.writes, 1);
});

test('retiring the original root during awaited current cannot start another physical request', async t => {
  const f = await deleteFixture(t);
  let rootRefused;
  f.state.current = operation => {
    if (operation === KINTONE_RECORD_DELETE_OPERATION) {
      try {f.closeRoot();} catch (cause) {rootRefused = cause;}
    }
  };
  await assert.rejects(f.send(), {code: 'OriginalAcquisitionRetiring'});
  assert.equal(rootRefused?.code, 'MoonBitHostFailure');
  assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 2);
  f.closeRoot(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});
