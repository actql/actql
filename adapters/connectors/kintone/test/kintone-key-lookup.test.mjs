import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';
import {KintoneLookupFailure} from '../site/kintone-key-lookup.mjs';
import {lookupFixture, lookupForm, lookupRecord} from './kintone-key-lookup.fixture.mjs';

const present = record => ({body: {records: [record], totalCount: '1'}});

test('original unique Text lookup retains API ID and revision through real Account Site SQLite TLS', async t => {
  const f = await lookupFixture(t);
  const raw = await f.send();
  assert.equal(f.common.clientProgramKintoneLookupUsesRequest(raw.observation, f.request), true);
  const page = f.common.clientProgramKintoneLookupPage(raw.observation);
  const target = checked(f.common.clientProgramKintoneOriginalRecordTarget(page, 0, 128));
  const deletion = checked(f.common.clientProgramKintoneDeleteRequest([target],
    f.common.clientProgramKintoneMutationLimits(100, 10000, 10000, 4096, 2000, 20)));
  assert.deepEqual(JSON.parse(f.common.clientProgramKintoneDeleteBody(deletion)),
    {app: '12', ids: ['9007199254740993'], revisions: ['9']});
  assert.equal(f.state.forms, 2); assert.equal(f.state.targets, 1);
  assert.equal(f.state.charges, 3); assert.equal(f.state.consumed, 3);
  assert.deepEqual(f.state.fixtureFailures, []);
  const journal = f.journal.recover();
  assert.equal(journal.length, 3); assert.equal(journal.filter(row => row.outcome === 'succeeded').length, 3);
  assert.equal(f.tls.seen().length, 3);
  f.row.assertNoCapture(); // This response component has no Effect Ledger or Preview.
});

test('explicit complete zero count is an original empty page, never an ID or write grant', async t => {
  const f = await lookupFixture(t);
  f.state.records = () => ({body: {records: [], totalCount: '0'}});
  const raw = await f.send();
  const page = f.common.clientProgramKintoneLookupPage(raw.observation);
  assert.throws(() => checked(f.common.clientProgramKintoneOriginalRecordTarget(page, 0, 128)),
    {code: 'MoonBitHostFailure'});
  assert.equal(f.state.charges, 3); assert.equal(f.tls.seen().length, 3);
  f.row.assertNoCapture();
});

test('non-success, missing count, duplicate and foreign-key replies cannot become absent or select a target', async t => {
  const original = lookupRecord();
  const replies = [
    {status: 404, body: {records: [], totalCount: '0'}},
    {status: 202, body: {records: [], totalCount: '0'}},
    {body: {records: [], totalCount: null}}, {body: {records: []}},
    {body: {records: [original, lookupRecord('9007199254740994')], totalCount: '2'}},
    present({...original, ExternalKey: {type: 'SINGLE_LINE_TEXT', value: 'foreign-key'}}),
    {body: '{'},
  ];
  for (const reply of replies) {
    const f = await lookupFixture(t); f.state.records = () => reply;
    await assert.rejects(f.send(), error => {
      assert.ok(error instanceof KintoneLookupFailure);
      assert.equal(error.phase, 'lookup'); assert.equal(error.observations.length, 2);
      assert.equal(error.observations[1].body.toString(), typeof reply.body === 'string'
        ? reply.body : JSON.stringify(reply.body));
      return true;
    });
    assert.equal(f.state.forms, 1); assert.equal(f.state.targets, 1);
    assert.equal(f.state.charges, 2); assert.equal(f.state.consumed, 1);
    f.row.assertNoCapture();
  }
});

test('actual unique metadata and revision must still match at initial and final Form reads', async t => {
  for (const at of [1, 2]) for (const form of [
    {...lookupForm, revision: '8'},
    {...lookupForm, properties: {...lookupForm.properties,
      ExternalKey: {...lookupForm.properties.ExternalKey, unique: false}}},
  ]) {
    const f = await lookupFixture(t);
    f.state.form = () => ({body: f.state.forms === at ? form : lookupForm});
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'MoonBitHostFailure');
      assert.equal(error.phase, at === 1 ? 'initial-form' : 'final-form');
      assert.equal(error.observations.length, at === 1 ? 1 : 3); return true;
    });
    assert.equal(f.state.targets, at === 1 ? 0 : 1);
    assert.equal(f.state.consumed, at === 1 ? 0 : 2);
  }
});

test('same private original token spans all three reads; rotation never selects another account', async t => {
  for (const after of [1, 2]) {
    const f = await lookupFixture(t);
    await assert.rejects(f.send({consumeObservation: charge => {
      f.options.consumeObservation(charge);
      if (f.state.consumed === after) f.state.secret = 'replacement-account-token';
    }}), {code: 'RemoteCredentialBindingChanged'});
    assert.equal(f.tls.seen().length, after); assert.equal(f.state.resolutions, after + 1);
    assert.equal(f.state.charges, after);
  }
});

test('current revocation during secret resolution prevents the next physical send', async t => {
  const f = await lookupFixture(t);
  f.state.resolve = async () => {if (f.state.resolutions === 2) await f.writeAccount('deny');};
  await assert.rejects(f.send(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.tls.seen().length, 1); assert.equal(f.state.targets, 0);
  assert.equal(f.journal.recover().length, 2);
});

test('current loss after awaited lookup response retains its charged bytes without disclosure', async t => {
  const f = await lookupFixture(t);
  f.state.records = async () => {await f.writeAccount('deny'); return present(lookupRecord());};
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.state.charges, 2); assert.equal(f.state.consumed, 1);
  assert.equal(f.state.forms, 1); f.row.assertNoCapture();
});

test('target-read current is checked again after the final awaited Form fence', async t => {
  const f = await lookupFixture(t);
  const current = f.options.current;
  await assert.rejects(f.send({current: async operation => {
    if (operation === KINTONE_TARGET_READ_OPERATION && f.state.forms === 2) await f.writeAccount('deny');
    await current(operation);
  }}), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.tls.seen().length, 3); assert.equal(f.state.charges, 3);
  assert.equal(f.state.consumed, 3); f.row.assertNoCapture();
});

test('lost lookup reply preserves nominal Unknown and cannot resend the same acquisition uses', async t => {
  const f = await lookupFixture(t, {faults: [{method: 'POST', pathname: '/k/v1/records.json',
    kind: 'apply-then-lose-reply'}]});
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'ECONNRESET'); assert.equal(error.observations.length, 1); return true;
  });
  assert.equal(f.state.targets, 1); assert.equal(f.tls.seen().length, 2);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  await assert.rejects(f.send(), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(f.state.targets, 1); assert.equal(f.tls.seen().length, 2); f.row.assertNoCapture();
});

test('required entry, App, all generated scope fields and original operation refuse before I/O', async t => {
  const f = await lookupFixture(t);
  await assert.rejects(f.send({originalAppId: '13'}), {code: 'ForeignKintoneLookupInstallation'});
  await assert.rejects(f.send({moon: {...f.common, clientProgramKintoneLookupResponse: undefined}}),
    {code: 'InvalidKintoneLookup'});
  await assert.rejects(f.send({current: undefined}), {code: 'InvalidKintoneLookup'});
  for (const key of [...credentialInvocationBindingKeys, 'operation']) {
    await assert.rejects(f.send({authorizationFor: async spec => {
      const original = await f.authorizationFor(spec), value = original.scope[key];
      return {...original, scope: {...original.scope, [key]: typeof value === 'number' ? value + 1 : value + '/foreign'}};
    }}), {code: 'ForeignKintoneLookupAuthorization'}, key);
  }
  assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
});

test('physical response and async frame retain original binding and reservation until confirmed retirement', async t => {
  const f = await lookupFixture(t);
  let pending, refused;
  f.state.records = () => {
    pending = closeHttpsCredentialBinding(f.binding);
    try {f.closeRoot();} catch (cause) {refused = cause;}
    return present(lookupRecord());
  };
  await assert.rejects(f.send(), {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(pending, 'pending'); assert.equal(refused?.code, 'MoonBitHostFailure');
  assert.ok(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]).some(value => value > 0n));
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  f.closeRoot(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  assert.equal(f.state.targets, 1);
});

test('root retirement during final Form current cannot dispatch the final physical request', async t => {
  const f = await lookupFixture(t);
  let refused;
  f.state.current = operation => {
    if (operation === KINTONE_FORM_READ_OPERATION && f.state.targets === 1) {
      try {f.closeRoot();} catch (cause) {refused = cause;}
    }
  };
  await assert.rejects(f.send(), {code: 'OriginalAcquisitionRetiring'});
  assert.equal(refused?.code, 'MoonBitHostFailure');
  assert.equal(f.state.forms, 1); assert.equal(f.state.targets, 1);
  f.closeRoot(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});
