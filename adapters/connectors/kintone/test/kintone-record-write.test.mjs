import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {projectKintoneWriteObservation, KintoneWriteFailure} from '../site/kintone-record-write.mjs';
import {writeFixture} from './kintone-record-write.fixture.mjs';
import {originalForm, record} from './installed-kintone.fixture.mjs';

for (const kind of ['create', 'update']) {
  const reads = kind === 'create' ? 1 : 2;
  test(`${kind} uses exact original checked values through real Account Site SQLite TLS once`, async t => {
    const f = await writeFixture(t, {kind});
    const raw = await f.send();
    assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, reads + 1);
    assert.equal(f.state.charges, reads + 1); assert.equal(f.state.consumed, reads + 1);
    assert.deepEqual(f.state.fixtureFailures, []);
    assert.equal(f.journal.recover().filter(row => row.outcome === 'succeeded').length, reads + 1);
    const projected = projectKintoneWriteObservation({moon: f.common, kind, request: f.request,
      observation: raw.observation, limits: f.options.limits});
    assert.equal(projected.kind, `typed-${kind}-response`);
    assert.equal((kind === 'create' ? f.common.clientProgramKintoneCreateResponseRequest
      : f.common.clientProgramKintoneUpdateResponseRequest)(projected.response), f.request);
    assert.equal(projected.observation, raw.observation);
    const identities = (kind === 'create' ? f.common.clientProgramKintoneCreateResponseRecords
      : f.common.clientProgramKintoneUpdateResponseRecords)(projected.response);
    assert.deepEqual(identities.map(pair => [runtimeField(pair, 0), runtimeField(pair, 1)]), kind === 'create'
      ? [['9007199254740994', '1'], ['9007199254740995', '1']]
      : [['9007199254740992', '10'], ['9007199254740993', '10']]);
    f.row.assertNoCapture();
  });

  test(`${kind} does not treat read Allow as write permission`, async t => {
    const f = await writeFixture(t, {kind, effect: 'deny'});
    await assert.rejects(f.send(), error => {
      assert.ok(error instanceof KintoneWriteFailure);
      assert.equal(error.code, 'ExecutionAuthorizationDenied');
      assert.equal(error.phase, kind); assert.equal(error.observations.length, reads); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, reads);
  });

  test(`${kind} refuses resolver rotation without a wrong-account write or replacement lookup`, async t => {
    const f = await writeFixture(t, {kind});
    await assert.rejects(f.send({consumeObservation: charge => {
      f.options.consumeObservation(charge);
      if (f.state.consumed === reads) f.state.secret = 'replacement-account-token';
    }}), error => {
      assert.equal(error.code, 'RemoteCredentialBindingChanged');
      assert.equal(error.observations.length, reads); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, reads);
    const resolutions = f.state.resolutions;
    await assert.rejects(f.send(), {code: 'RemoteCredentialBindingChanged'});
    assert.equal(f.state.resolutions, resolutions); assert.equal(f.state.writes, 0);
  });

  test(`${kind} retains original charged bytes when Account is revoked during the write response`, async t => {
    const f = await writeFixture(t, {kind});
    f.state.reply = async () => {await f.writeAccount('deny'); return {body: {original: 'received'}};};
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
      assert.equal(error.observations.length, reads + 1);
      assert.equal(error.observations[reads].body.toString(), '{"original":"received"}'); return true;
    });
    assert.equal(f.state.writes, 1); assert.equal(f.state.charges, reads + 1);
    f.row.assertNoCapture();
  });

  test(`${kind} lost reply preserves original Unknown without automatic resend`, async t => {
    const f = await writeFixture(t, {kind, faults: [{method: kind === 'create' ? 'POST' : 'PUT',
      bodyIncludes: '"value":"next 東京"', kind: 'apply-then-lose-reply'}]});
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'ECONNRESET'); assert.equal(error.observations.length, reads); return true;
    });
    assert.equal(f.state.writes, 1);
    assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
    await assert.rejects(f.send());
    assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, reads + 1);
  });
}

test('changed original Form refuses both writes with charged bytes still owned', async t => {
  for (const kind of ['create', 'update']) {
    const f = await writeFixture(t, {kind});
    f.state.form = () => ({...originalForm, revision: '8'});
    await assert.rejects(f.send(), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 1); return true;
    });
    assert.equal(f.state.writes, 0); assert.equal(f.state.charges, 1); assert.equal(f.state.consumed, 0);
  }
});

test('UPDATE target revision drift never falls through to CREATE', async t => {
  const f = await writeFixture(t);
  f.state.records = () => ({records: [record('9007199254740992'),
    {...record('9007199254740993'), $revision: {type: '__REVISION__', value: '10'}}], totalCount: null});
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.phase, 'target'); return true;
  });
  assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 2);
  assert.equal(f.state.charges, 2); assert.equal(f.state.consumed, 1);
});

test('rejected and uncorrelated write bodies remain original observations rather than committed Effects', async t => {
  for (const kind of ['create', 'update']) for (const reply of [
    {status: 409, body: {code: 'GAIA_CO02'}},
    {body: kind === 'create' ? {ids: ['7'], revisions: ['1']} : {records: []}},
  ]) {
    const f = await writeFixture(t, {kind}); f.state.reply = () => reply;
    const raw = await f.send();
    assert.equal(raw.observation.statusCode, reply.status ?? 200);
    const projected = projectKintoneWriteObservation({moon: f.common, kind, request: f.request,
      observation: raw.observation, limits: f.options.limits});
    assert.equal(projected.kind, 'unclassified-response'); assert.equal(projected.observation, raw.observation);
    assert.equal(raw.observation.body.toString(), JSON.stringify(reply.body));
    assert.equal(f.state.writes, 1); f.row.assertNoCapture();
  }
});

test('missing or foreign physical inputs refuse before a write or replacement acquisition', async t => {
  const f = await writeFixture(t);
  await assert.rejects(f.send({credential: {...f.options.credential, binding: undefined}}), {code: 'InvalidKintoneWrite'});
  await assert.rejects(f.send({originalAppId: '13'}), {code: 'ForeignKintoneWriteInstallation'});
  await assert.rejects(f.send({kind: 'upsert'}), {code: 'InvalidKintoneWriteKind'});
  await assert.rejects(f.send({moon: {}}), {code: 'KintoneWriteRuntimeUnavailable'});
  assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
});

test('guest-space routes preserve the same original App IDs and exact write method', async t => {
  for (const kind of ['create', 'update']) {
    const f = await writeFixture(t, {kind, guestSpaceId: '23'});
    await f.send();
    assert.equal(f.state.writes, 1); assert.deepEqual(f.state.fixtureFailures, []);
    assert.ok(f.tls.seen().every(exchange => exchange.pathname.startsWith('/k/guest/23/v1/')));
  }
});

test('an in-flight physical write holds the same binding and response custody until socket retirement', async t => {
  const f = await writeFixture(t);
  let arrived, release;
  const started = new Promise(resolve => {arrived = resolve;});
  const barrier = new Promise(resolve => {release = resolve;});
  f.state.reply = async () => {arrived(); await barrier; return {body: {records: [
    {id: '9007199254740992', revision: '10'}, {id: '9007199254740993', revision: '10'},
  ]}};};
  const pending = f.send();
  let settled = false;
  const result = pending.then(value => {settled = true; return value;}, error => {settled = true; throw error;});
  try {
    await started;
    assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
    assert.equal(settled, false); assert.equal(f.state.writes, 1);
    assert.throws(() => f.closeRoot(), {code: 'MoonBitHostFailure'});
    assert.ok(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]).some(value => value > 0n));
  } finally {release();}
  await assert.rejects(result, {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  f.closeRoot(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.state.writes, 1);
});


test('every generated binding member remains required before original write observation I/O', async t => {
  const f = await writeFixture(t);
  for (const key of credentialInvocationBindingKeys) {
    await assert.rejects(f.send({authorizationFor: async spec => {
      const original = await f.authorizationFor(spec);
      const value = original.scope[key];
      return {...original, scope: {...original.scope, [key]: typeof value === 'number' ? value + 1 : value + '/foreign'}};
    }}), {code: 'ForeignKintoneWriteAuthorization'}, key);
  }
  assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
});

for (const change of ['calculation', 'mapping']) {
  test(`same-revision ${change} drift retains charged Form and refuses CREATE and UPDATE`, async t => {
    for (const kind of ['create', 'update']) {
      const f = await writeFixture(t, {kind});
      f.state.form = () => ({...originalForm, properties: {...originalForm.properties,
        Subject: {...originalForm.properties.Subject, expression: change === 'calculation' ? '"server value"' : '',
          ...(change === 'mapping' ? {lookup: {fieldMappings: [{field: 'Tags', relatedField: 'source'}]}} : {})}}});
      await assert.rejects(f.send(), error => {
        assert.equal(error.code, 'MoonBitHostFailure');
        assert.equal(error.phase, 'form');
        assert.equal(error.observations.length, 1);
        return true;
      });
      assert.equal(f.state.forms, 1); assert.equal(f.state.targets, 0);
      assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 1);
      assert.equal(f.state.charges, 1); assert.equal(f.state.consumed, 0);
      assert.deepEqual(f.state.fixtureFailures, []);
    }
  });
}
