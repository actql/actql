import assert from 'node:assert/strict';
import test from 'node:test';
import {gmailAuthenticationFixture} from './gmail-authentication.fixture.mjs';

test('Gmail SQL and AQL capture consume the original authenticated parent use without exposing a token', async t => {
  for (const format of ['sql', 'aql']) {
    const f = await gmailAuthenticationFixture(t, {format});
    const auth = await f.authenticate();
    assert.deepEqual(Object.keys(auth), ['useCid']);
    assert.equal(f.state.authRequests, 1);
    assert.equal(f.state.apiRequests, 0);
    assert.equal(f.state.materialResolutions, 1);
    const originalParent = f.parentClaim();
    const reader = f.reader();
    const result = await reader.read();
    assert.equal(result.pages, 1); assert.equal(result.rowCount, 2);
    assert.equal(result.observations.length, 1);
    assert.equal(f.state.bodyCharges, 1);
    assert.deepEqual(f.state.rows, [
      {id: 'INBOX', name: 'Inbox', type: 'system'},
      {id: 'Label_1', name: '顧客 / é 📩', type: 'user'},
    ]);
    f.row.finish(); assert.equal(f.row.captureCount(), 2);
    const records = f.journal.recover();
    assert.equal(records.length, 2);
    assert.equal(records.find(x => x.useId === 'original-labels').useCid, originalParent.record.useCid);
    assert.equal(records.find(x => x.useId === 'original-auth').useCid, auth.useCid);
    assert.deepEqual(records.map(x => x.outcome), ['succeeded', 'succeeded']);
    assert.equal(f.state.apiRequests, 1); assert.equal(f.state.legacyResolutions, 0);
    assert.equal(reader.observe().cleanupConfirmed, false);
    await assert.rejects(reader.read(), {code: 'GmailLabelListReaderAlreadyStarted'});
    assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 1);
  }
});

test('Gmail missing original authentication refuses before API claim or legacy token resolution', async t => {
  const f = await gmailAuthenticationFixture(t), reader = f.reader();
  await assert.rejects(reader.read(), error => error.code === 'GmailLabelListReadFailed' &&
    error.cause.code === 'RemoteCredentialAuthenticationUnavailable');
  assert.equal(f.journal.recover().length, 0);
  assert.equal(f.state.authRequests, 0); assert.equal(f.state.apiRequests, 0);
  assert.equal(f.state.materialResolutions, 0); assert.equal(f.state.legacyResolutions, 0);
  f.row.assertNoCapture(); assert.equal(reader.observe().cleanupConfirmed, false);
});

test('Gmail authentication success grants no API right after current Account revocation', async t => {
  const f = await gmailAuthenticationFixture(t);
  await f.authenticate(); await f.writeAccount('deny');
  const reader = f.reader();
  await assert.rejects(reader.read(), error => error.cause.code === 'GmailReadDenied');
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 0);
  const records = f.journal.recover();
  assert.equal(records.find(x => x.useId === 'original-auth').outcome, 'succeeded');
  assert.equal(records.find(x => x.useId === 'original-labels').outcome, 'claimed');
  assert.equal(f.state.legacyResolutions, 0); f.row.assertNoCapture();
});

test('Gmail lost auth response retains its original Unknown and never refreshes or sends labels', async t => {
  const f = await gmailAuthenticationFixture(t);
  f.state.onToken = request => {request.socket.destroy(); return true;};
  await assert.rejects(f.authenticate());
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  const reopened = f.opens();
  assert.equal(reopened.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  reopened.close();
  await assert.rejects(f.authenticate(), {code: 'RemoteCredentialAuthenticationAlreadyClaimed'});
  await assert.rejects(f.reader().read(), error => error.cause.code === 'RemoteCredentialAuthenticationUnavailable');
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 0);
  assert.equal(f.state.materialResolutions, 1); assert.equal(f.state.legacyResolutions, 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-labels').outcome, 'claimed');
  f.row.assertNoCapture();
});

test('Gmail authenticated request cannot replace its original parent use id', async t => {
  const f = await gmailAuthenticationFixture(t);
  await f.authenticate();
  const reader = f.reader({authorizationFor: () => ({grant: f.grant, scope: f.scope, useId: 'replacement-parent'})});
  await assert.rejects(reader.read(), error => error.cause.code === 'ForeignRemoteCredentialAuthenticationParent');
  const records = f.journal.recover();
  assert.equal(records.length, 2);
  assert.equal(records.find(x => x.useId === 'original-labels').outcome, 'claimed');
  assert.equal(records.some(x => x.useId === 'replacement-parent'), false);
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 0);
  f.row.assertNoCapture();
});

test('Gmail expired private token cannot refresh or become a legacy secret', async t => {
  const f = await gmailAuthenticationFixture(t);
  await f.authenticate(); f.state.now += 61_000;
  await assert.rejects(f.reader().read(), error => error.cause.code === 'RemoteCredentialAuthenticationMaterialExpired');
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 0);
  assert.equal(f.state.materialResolutions, 1); assert.equal(f.state.legacyResolutions, 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-labels').outcome, 'claimed');
  f.row.assertNoCapture();
});

test('Gmail actual material retirement after auth refuses at the original physical current fence', async t => {
  const f = await gmailAuthenticationFixture(t);
  await f.authenticate(); f.state.materialCurrent = false;
  await assert.rejects(f.reader().read(), error => error.cause.code === 'OriginalMaterialRetired');
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 0);
  assert.equal(f.state.materialResolutions, 1); assert.equal(f.state.legacyResolutions, 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-labels').outcome, 'claimed');
  f.row.assertNoCapture();
});

test('Gmail lost authenticated label reply keeps the original API Unknown without a second auth or data send', async t => {
  const f = await gmailAuthenticationFixture(t);
  await f.authenticate();
  f.state.onApi = request => {request.socket.destroy(); return true;};
  const reader = f.reader();
  await assert.rejects(reader.read());
  const records = f.journal.recover();
  assert.equal(records.length, 2);
  assert.equal(records.find(x => x.useId === 'original-auth').outcome, 'succeeded');
  assert.equal(records.find(x => x.useId === 'original-labels').outcome, 'unknown');
  const reopened = f.opens();
  assert.equal(reopened.recover().find(x => x.useId === 'original-labels').outcome, 'unknown');
  reopened.close();
  await assert.rejects(reader.read(), {code: 'GmailLabelListReaderAlreadyStarted'});
  // The original physical Owner rejects an Unknown parent before it can
  // attempt another claim; no replay is promoted into a fresh API permit.
  await assert.rejects(f.reader().read(), error => error.cause.code === 'InvalidRemoteCredentialAuthenticationParent');
  assert.equal(f.state.authRequests, 1); assert.equal(f.state.apiRequests, 1);
  assert.equal(f.state.materialResolutions, 1); assert.equal(f.state.legacyResolutions, 0);
  f.row.assertNoCapture(); assert.equal(reader.observe().cleanupConfirmed, false);
});
