import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {readHubSpotRecordTargets, HubSpotTargetReadFailure,
  HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number'},
  {name: 'external_key', type: 'string', fieldType: 'text', hasUniqueValue: true},
  {name: 'hs_lastmodifieddate', type: 'datetime', fieldType: 'date'},
]};
const propertiesBody = JSON.stringify(properties);
const bounds = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const limits = Object.freeze({maxResponseBytes: 4096, maxRequestBytes: 4096,
  maxNodes: 1000, maxDepth: 20, maxProperties: 10, maxNameUnits: 100,
  maxRows: 2, maxColumns: 3, maxCursorUnits: 100, maxValueNodes: 100,
  maxValueTextBytes: 4096, maxOutputBytes: 4096, maxOutputNodes: 100,
  maxOutputDepth: 10, maxRequests: 4});
const record = (id, key, amount) => ({id, archived: false,
  updatedAt: '2026-10-17T00:00:00.000Z', properties: {external_key: key,
    amount, hs_lastmodifieddate: '2026-10-17T00:00:00.000Z'}});
const records = [record('2', 'second', '0'), record('9007199254740993', 'first', '9007199254740993.01')];

async function fixture(t) {
  const f = await accountFixture(t, {resources: ['account', 'companies']});
  const state = {properties: propertiesBody, body: JSON.stringify({status: 'COMPLETE', results: records}),
    status: 200, bodies: [], schemaReads: 0, targetReads: 0, responseHook: undefined};
  f.state.onRequest = async (request, response) => {
    if (await state.responseHook?.(request, response)) return true;
    if (request.url === '/account-info/v3/details') return false;
    let body;
    if (request.url === '/crm/v3/properties/companies') {
      assert.equal(request.method, 'GET'); state.schemaReads++; body = state.properties;
    } else if (request.url === '/crm/v3/objects/companies/batch/read') {
      assert.equal(request.method, 'POST'); state.targetReads++;
      assert.equal(request.headers['content-type'], 'application/json');
      const chunks = []; for await (const chunk of request) chunks.push(chunk);
      state.bodies.push(Buffer.concat(chunks).toString()); body = state.body;
    } else assert.fail(`Unexpected original target read ${request.url}`);
    response.writeHead(request.url.endsWith('/batch/read') ? state.status : 200,
      {'content-type': 'application/json'}); response.end(body); return true;
  };
  const catalog = checked(moon.hubspotProjectProperties(Buffer.from(propertiesBody),
    'companies', 4096, 1000, 20, 10, 100));
  const targets = ['first', 'second'].map(value => checked(moon.hubspotPrepareRecordTarget(
    catalog, 'external_key', Buffer.from(JSON.stringify(value)), ...bounds)));
  const request = checked(moon.hubspotPrepareRecordRead(catalog, targets,
    ['amount', 'hs_lastmodifieddate'], 100, 100, 3, 4096, 100, 10));
  const grants = new Map();
  for (const operation of [HUBSPOT_PROPERTIES_READ_OPERATION, HUBSPOT_OBJECT_BATCH_READ_OPERATION]) {
    const scope = Object.freeze({...f.scope, operation,
      maxUses: operation === HUBSPOT_PROPERTIES_READ_OPERATION ? 2 : 1});
    const grant = f.control.prepare(scope); f.journal.acceptGrant(f.sign(grant), f.control);
    grants.set(operation, {scope, grant});
  }
  const options = {moon, originalPortalId: '7', originalCatalog: catalog, request,
    initialAuthorization: f.options.authorization, credential: f.options.credential,
    limits, authorizationFor: ({operation, index}) => ({...grants.get(operation), useId: `target-${index}`}),
    current: operation => f.current(operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION ? 'account' : 'companies'),
    chargeResponse: f.options.chargeResponse, consumeObservation: f.options.consumeObservation};
  return {...f, targetState: state, targetOptions: options,
    read: overrides => readHubSpotRecordTargets({...options, ...overrides})};
}

test('real Credential Account SQLite and TLS target read correlates reordered records under the same original binding', async t => {
  const f = await fixture(t), result = await f.read();
  assert.deepEqual(JSON.parse(moon.hubspotRecordReadWire(result.observation)), [
    {id: '9007199254740993', updatedAt: '2026-10-17T00:00:00.000Z',
      properties: {amount: '9007199254740993.0100000000', hs_lastmodifieddate: '2026-10-17T00:00:00.000Z', external_key: 'first'}},
    {id: '2', updatedAt: '2026-10-17T00:00:00.000Z',
      properties: {amount: '0.0000000000', hs_lastmodifieddate: '2026-10-17T00:00:00.000Z', external_key: 'second'}},
  ]);
  assert.equal(result.observations.length, 4); assert.equal(f.state.charges, 4);
  assert.equal(f.state.consumed, 4); assert.equal(f.targetState.schemaReads, 2);
  assert.equal(f.targetState.targetReads, 1);
  assert.deepEqual(f.targetState.bodies, ['{"inputs":[{"id":"first"},{"id":"second"}],"idProperty":"external_key","properties":["amount","hs_lastmodifieddate","external_key"]}']);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.observations.reduce((sum, r) => sum + BigInt(r.body.length), 0n));
  assert.equal(f.journal.recover().filter(r => r.outcome === 'succeeded').length, 4);
  f.row.assertNoCapture();
});

test('missing callbacks foreign catalog and local request ceiling refuse before a nominal use or Provider send', async t => {
  const f = await fixture(t);
  for (const override of [{current: undefined}, {consumeObservation: undefined},
    {credential: {...f.options.credential, binding: undefined}},
    {limits: {...limits, maxRows: 0}}]) {
    await assert.rejects(f.read(override), {code: 'InvalidHubSpotTargetRead'});
  }
  await assert.rejects(f.read({limits: {...limits, maxRequestBytes: 1}}), {code: 'HubSpotTargetRequestLimit'});
  const catalog = checked(moon.hubspotProjectProperties(Buffer.from(propertiesBody), 'deals', 4096, 1000, 20, 10, 100));
  await assert.rejects(f.read({originalCatalog: catalog}), {code: 'ForeignHubSpotTargetCatalog'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.journal.recover().length, 0);
});

test('rotation across identity schema and target responses cannot substitute another account credential', async t => {
  for (const [phase, expectedRequests] of [['identity', 1], ['schema', 2], ['target', 3]]) {
    const f = await fixture(t);
    await assert.rejects(f.read({consumeObservation: charge => {
      f.options.consumeObservation(charge);
      if (phase === 'identity' || (phase === 'schema' && f.targetState.schemaReads) ||
          (phase === 'target' && f.targetState.targetReads)) f.state.secret = 'other-account-secret';
    }}), error => {
      assert.ok(error instanceof HubSpotTargetReadFailure);
      assert.equal(error.code, 'RemoteCredentialBindingChanged');
      assert.equal(error.observations.length, expectedRequests); return true;
    });
    assert.equal(f.state.requests.length, expectedRequests);
    assert.equal(f.state.resolutions, expectedRequests + 1);
    assert.ok(f.state.requests.every(request => request.authorization === 'Bearer provider-secret'));
    assert.equal(f.targetState.targetReads, phase === 'target' ? 1 : 0); f.row.assertNoCapture();
  }
});

test('type or unique-key metadata drift refuses before batch read while retaining original charged responses', async t => {
  for (const drift of ['type', 'unique']) {
    const f = await fixture(t);
    f.targetState.properties = drift === 'type' ? propertiesBody.replace('"number"', '"string"')
      : propertiesBody.replace('"hasUniqueValue":true', '"hasUniqueValue":false');
    await assert.rejects(f.read(), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 2); return true;
    });
    assert.equal(f.state.charges, 2); assert.equal(f.targetState.targetReads, 0);
    assert.equal(f.state.requests.length, 2); f.row.assertNoCapture();
  }
});

test('awaited target response Account revocation keeps bytes but cannot disclose an observation', async t => {
  const f = await fixture(t);
  f.targetState.responseHook = async request => {
    if (request.url.endsWith('/batch/read')) await f.writeAccount('deny'); return false;
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged'); assert.equal(error.observations.length, 3);
    assert.equal(error.observations[2].body.toString(), f.targetState.body); return true;
  });
  assert.equal(f.state.charges, 3); assert.equal(f.targetState.schemaReads, 1);
  assert.equal(f.state.requests.length, 3); f.row.assertNoCapture();
});

test('final schema drift refuses completion after target bytes without repeating target read', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({consumeObservation: charge => {
    f.options.consumeObservation(charge);
    if (f.targetState.targetReads) f.targetState.properties = propertiesBody.replace('"number"', '"string"');
  }}), error => {
    assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 4); return true;
  });
  assert.equal(f.state.charges, 4); assert.equal(f.targetState.targetReads, 1);
  assert.equal(f.state.requests.length, 4); f.row.assertNoCapture();
});

test('lost target reply keeps original nominal use Unknown and never resends', async t => {
  const f = await fixture(t);
  f.targetState.responseHook = request => {
    if (!request.url.endsWith('/batch/read')) return false;
    request.socket.destroy(); return true;
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'ECONNRESET'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.journal.recover().filter(r => r.outcome === 'unknown').length, 1);
  assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 2);
  f.row.assertNoCapture();
});

test('partial missing rejected or duplicate targets remain refusal rather than an upsert-create decision', async t => {
  for (const kind of ['partial', 'missing', 'duplicate', 'http']) {
    const f = await fixture(t);
    if (kind === 'partial') f.targetState.body = JSON.stringify({status: 'PROCESSING', results: records});
    if (kind === 'missing') f.targetState.body = '{"status":"COMPLETE","results":[]}';
    if (kind === 'duplicate') f.targetState.body = JSON.stringify({status: 'COMPLETE', results:
      [record('1', 'first', '0'), record('2', 'first', '0')]});
    if (kind === 'http') f.targetState.status = 207;
    await assert.rejects(f.read(), error => {
      assert.equal(error.code, kind === 'http' ? 'HubSpotTargetReadRejected' : 'MoonBitHostFailure');
      assert.equal(error.observations.length, 3); return true;
    });
    assert.equal(f.state.charges, 3); assert.equal(f.targetState.schemaReads, 1);
    assert.equal(f.state.requests.length, 3); f.row.assertNoCapture();
  }
});

test('foreign original invocation scope refuses before a replacement nominal use or schema send', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({authorizationFor: context => {
    const value = f.targetOptions.authorizationFor(context);
    return {...value, scope: {...value.scope, runInvocationCid: `sha256:${'f'.repeat(64)}`}};
  }}), {code: 'ForeignHubSpotTargetAuthorization'});
  assert.equal(f.state.requests.length, 1); assert.equal(f.journal.recover().length, 1);
  f.row.assertNoCapture();
});

test('target admission Account loss or request exhaustion cannot skip final schema and current fences', async t => {
  for (const kind of ['revoked', 'ceiling']) {
    const f = await fixture(t);
    await assert.rejects(f.read({limits: {...limits, maxRequests: kind === 'ceiling' ? 3 : 4},
      consumeObservation: async charge => {
        f.options.consumeObservation(charge);
        if (kind === 'revoked' && f.targetState.targetReads) await f.writeAccount('deny');
      }}), {code: kind === 'ceiling' ? 'HubSpotTargetRequestLimit' : 'AuthorizationCurrentAccountChanged'});
    assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 3);
    assert.equal(f.targetState.schemaReads, 1); f.row.assertNoCapture();
  }
});

test('active target socket binding cleanup stays pending until original physical retirement', async t => {
  const f = await fixture(t);
  let entered, resume;
  const started = new Promise(resolve => {entered = resolve;});
  const blocked = new Promise(resolve => {resume = resolve;});
  f.targetState.responseHook = async request => {
    if (!request.url.endsWith('/batch/read')) return false;
    entered(); await blocked; return false;
  };
  const pending = f.read(); await started;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  resume();
  await assert.rejects(pending, error => {
    assert.equal(error.code, 'RemoteCredentialBindingRetiring'); assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(f.journal.recover().filter(r => r.outcome === 'unknown').length, 1);
  assert.equal(f.state.requests.length, 3); f.row.assertNoCapture();
});
