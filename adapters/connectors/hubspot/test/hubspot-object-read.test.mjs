import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {readHubSpotObjects, HubSpotObjectReadFailure, HUBSPOT_PROPERTIES_READ_OPERATION,
  HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

const propertiesBody = JSON.stringify({results: [
  {name: 'amount', type: 'number', fieldType: 'number'},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', options: [{value: 'a'}, {value: 'b'}]},
]});
const limits = Object.freeze({maxResponseBytes: 4096, maxNodes: 1000,
  maxDepth: 20, maxProperties: 10, maxNameUnits: 100, maxPages: 2,
  maxRows: 2, maxRequests: 5, perPage: 1, maxColumns: 3, maxCursorUnits: 64,
  maxValueNodes: 100, maxValueTextBytes: 4096, maxRowsWireBytes: 4096,
  maxRowsWireNodes: 100, maxRowsWireDepth: 10});
const record = (id, amount, tags) => ({id, archived: false, properties: {amount, tags}});
const pages = [
  JSON.stringify({results: [record('9007199254740993', '9007199254740993.01', 'a;b')],
    paging: {next: {after: 'opaque /%+é', link: 'https://foreign.invalid/never-follow'}}}),
  JSON.stringify({results: [record('9007199254740994', '0', '')]}),
];
const rowSchema = {amount: {type: 'decimal', precision: 38, scale: 10, nullable: true},
  id: {type: 'string', nullable: false},
  tags: {type: 'array', nullable: true, items: {type: 'string', nullable: false}}};

async function fixture(t) {
  const f = await accountFixture(t, {rowSchema, resources: ['account', 'companies']});
  const state = {properties: propertiesBody, pages: pages.slice(), propertiesReads: 0,
    pagesRead: 0, rows: [], observations: 0, responseHook: undefined};
  f.state.onRequest = async (request, response) => {
    if (await state.responseHook?.(request, response)) return true;
    if (request.url === '/account-info/v3/details') return false;
    let body;
    if (request.url === '/crm/v3/properties/companies') {
      state.propertiesReads++; body = state.properties;
    } else if (request.url.startsWith('/crm/v3/objects/companies?')) {
      body = state.pages[state.pagesRead++];
      assert.equal(typeof body, 'string');
    } else assert.fail(`Unexpected original request ${request.url}`);
    response.writeHead(200, {'content-type': 'application/json'}); response.end(body); return true;
  };
  const originalCatalog = checked(moon.hubspotProjectProperties(Buffer.from(propertiesBody),
    'companies', limits.maxResponseBytes, limits.maxNodes, limits.maxDepth,
    limits.maxProperties, limits.maxNameUnits));
  const grants = new Map();
  for (const operation of [HUBSPOT_PROPERTIES_READ_OPERATION, HUBSPOT_OBJECT_LIST_OPERATION]) {
    const scope = Object.freeze({...f.scope, operation, maxUses: 2});
    const grant = f.control.prepare(scope); f.journal.acceptGrant(f.sign(grant), f.control);
    grants.set(operation, {scope, grant});
  }
  const options = {moon, originalCatalog, objectType: 'companies', properties: ['amount', 'tags'],
    originalPortalId: '7', initialAuthorization: f.options.authorization,
    credential: f.options.credential, limits,
    authorizationFor: ({operation, index}) => ({...grants.get(operation), useId: `request-${index}`}),
    current: operation => f.current(operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION ? 'account' : 'companies'),
    chargeResponse: f.options.chargeResponse,
    consumeObservation: charge => {state.observations++; return f.options.consumeObservation(charge);},
    consumePage: (rows, {charge}) => { f.row.page(rows, charge); state.rows.push(...rows); }};
  return {...f, pageState: state, readOptions: options,
    read: overrides => readHubSpotObjects({...options, ...overrides})};
}

test('actual bound identity schema and pages use one accounted RowRun with exact Decimal and cursor DATA', async t => {
  const f = await fixture(t);
  const result = await f.read();
  assert.equal(result.pages, 2); assert.equal(result.rowCount, 2);
  assert.equal(result.observations.length, 5); assert.equal(f.state.charges, 5);
  assert.equal(f.pageState.observations, 3); assert.equal(f.pageState.propertiesReads, 2);
  assert.deepEqual(f.pageState.rows, [
    {id: '9007199254740993', amount: '9007199254740993.0100000000', tags: ['a', 'b']},
    {id: '9007199254740994', amount: '0.0000000000', tags: []},
  ]);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.observations.reduce((n, r) => n + BigInt(r.body.length), 0n));
  assert.equal(f.state.requests.length, 5);
  assert.ok(f.state.requests.every(r => r.authorization === 'Bearer provider-secret'));
  const query = new URL(`https://fixture${f.state.requests[3].path}`);
  assert.equal(query.pathname, '/crm/v3/objects/companies');
  assert.equal(query.searchParams.get('after'), 'opaque /%+é');
  assert.equal(query.searchParams.get('properties'), 'amount,tags');
  // Only the actual original Host finishes/captures, after final schema/current.
  // Premature capture is a stateful refusal, not a read-only observation; the
  // independent failure cases exercise that refusal without aborting this run.
  f.row.finish(); assert.equal(f.row.captureCount(), 2);
});

test('foreign catalog or absent private scope callbacks refuses before provider I/O', async t => {
  const f = await fixture(t);
  for (const override of [{current: undefined}, {consumePage: undefined},
    {credential: {...f.options.credential, binding: undefined}}, {properties: ['id']},
    {properties: ['amount,other']}, {properties: ['amount', 'amount']}]) {
    await assert.rejects(f.read(override), {code: 'InvalidHubSpotObjectRead'});
  }
  await assert.rejects(f.read({objectType: 'deals'}), {code: 'ForeignHubSpotObjectCatalog'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.journal.recover().length, 0);
});

test('actual identity token rotation cannot send metadata or pages with a replacement credential', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({consumeObservation: charge => {
    f.readOptions.consumeObservation(charge); f.state.secret = 'different-account-secret';
  }}), error => {
    assert.ok(error instanceof HubSpotObjectReadFailure);
    assert.equal(error.code, 'RemoteCredentialBindingChanged');
    assert.equal(error.observations.length, 1);
    assert.equal(Object.keys(error).includes('observations'), false); return true;
  });
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.resolutions, 2);
  assert.equal(f.state.charges, 1); assert.equal(f.pageState.rows.length, 0);
  assert.deepEqual(f.journal.recover().map(r => r.outcome).sort(), ['failed', 'succeeded']);
  f.row.assertNoCapture();
});

test('changed original metadata is charged and retained before any object page is sent', async t => {
  const f = await fixture(t);
  f.pageState.properties = propertiesBody.replace('"number"', '"string"');
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 2);
    assert.equal(error.observations[1].body.toString(), f.pageState.properties); return true;
  });
  assert.equal(f.state.requests.length, 2); assert.equal(f.state.charges, 2);
  assert.equal(f.pageState.pagesRead, 0); assert.equal(f.pageState.observations, 1);
  f.row.assertNoCapture();
});

test('final property drift refuses Source completion while retaining already admitted rows and responses', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({consumePage: (rows, charge) => {
    f.readOptions.consumePage(rows, charge);
    f.pageState.properties = propertiesBody.replace('"number"', '"string"');
  }}), error => {
    assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.observations.length, 5);
    return true;
  });
  assert.equal(f.pageState.rows.length, 2); assert.equal(f.state.charges, 5);
  assert.equal(f.pageState.observations, 2); f.row.assertNoCapture();
});

test('foreign invocation scope is rejected before another nominal use or metadata request', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({authorizationFor: context => {
    const value = f.readOptions.authorizationFor(context);
    return {...value, scope: {...value.scope, dispatchRequestCid: `sha256:${'f'.repeat(64)}`}};
  }}), {code: 'ForeignHubSpotReadAuthorization'});
  assert.equal(f.state.requests.length, 1); assert.equal(f.journal.recover().length, 1);
  f.row.assertNoCapture();
});

test('page cursor cycles and page ceilings stop without following response URLs or resending', async t => {
  for (const kind of ['cycle', 'ceiling']) {
    const f = await fixture(t);
    f.pageState.pages[1] = JSON.stringify({results: [], paging: {next: {after: 'opaque /%+é'}}});
    await assert.rejects(f.read({limits: {...limits, maxPages: kind === 'cycle' ? 3 : 1}}),
      {code: kind === 'cycle' ? 'HubSpotReadCursorCycle' : 'HubSpotReadPageLimit'});
    assert.equal(f.state.requests.length, kind === 'cycle' ? 4 : 3);
    assert.equal(f.pageState.propertiesReads, 1); f.row.assertNoCapture();
  }
});

test('current Account revocation during a page response keeps original bytes but forbids row admission', async t => {
  const f = await fixture(t);
  f.pageState.responseHook = async request => {
    if (request.url.startsWith('/crm/v3/objects/')) await f.writeAccount('deny');
    return false;
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 3); return true;
  });
  assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 3);
  assert.equal(f.pageState.rows.length, 0); f.row.assertNoCapture();
});

test('lost page reply stays the same original Unknown with no replay and retained prior observations', async t => {
  const f = await fixture(t);
  f.pageState.responseHook = request => {
    if (!request.url.startsWith('/crm/v3/objects/')) return false;
    request.socket.destroy(); return true;
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'ECONNRESET'); assert.equal(error.observations.length, 2); return true;
  });
  const records = f.journal.recover();
  assert.equal(records.filter(r => r.outcome === 'unknown').length, 1);
  assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 2);
  f.row.assertNoCapture();
  // No fabricated charge for the unobserved response; original transport use
  // responsibility remains Unknown, not evidence of wholephase funding.
});

test('same binding cleanup while awaiting the current page prevents send without another lookup', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({current: async operation => {
    await f.readOptions.current(operation);
    if (operation === HUBSPOT_OBJECT_LIST_OPERATION) {
      assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
    }
  }}), {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(f.state.requests.length, 2); assert.equal(f.state.resolutions, 2);
  assert.equal(f.pageState.rows.length, 0); f.row.assertNoCapture();
});

test('received schema HTTP refusal is charged once and retained without a data read', async t => {
  const f = await fixture(t);
  f.pageState.responseHook = (request, response) => {
    if (request.url !== '/crm/v3/properties/companies') return false;
    response.writeHead(403, {'content-type': 'application/json'});
    response.end('{"message":"denied"}'); return true;
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'HubSpotReadRejected');
    assert.equal(error.observations.length, 2);
    assert.equal(error.observations[1].statusCode, 403);
    assert.equal(error.observations[1].body.toString(), '{"message":"denied"}'); return true;
  });
  assert.equal(f.state.requests.length, 2); assert.equal(f.state.charges, 2);
  assert.equal(f.pageState.pagesRead, 0); f.row.assertNoCapture();
});

test('request ceiling counts identity schema and data independently and never sends an unreserved final observation', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({limits: {...limits, maxRequests: 4}}), error => {
    assert.equal(error.code, 'HubSpotReadRequestLimit');
    assert.equal(error.observations.length, 4); return true;
  });
  assert.equal(f.state.requests.length, 4); assert.equal(f.state.charges, 4);
  assert.equal(f.pageState.rows.length, 2); assert.equal(f.pageState.propertiesReads, 1);
  f.row.assertNoCapture();
});

test('a repeated original record id across different pages is refused without deduplication or a replacement read', async t => {
  const f = await fixture(t);
  f.pageState.pages[1] = JSON.stringify({results: [record('9007199254740993', '0', '')]});
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'HubSpotReadDuplicateRecord');
    assert.equal(error.observations.length, 4); return true;
  });
  assert.equal(f.pageState.rows.length, 1); assert.equal(f.state.requests.length, 4);
  assert.equal(f.state.charges, 4); f.row.assertNoCapture();
});

test('post-admission Account loss refuses before another page or final schema request', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read({consumePage: async (rows, charge) => {
    f.readOptions.consumePage(rows, charge); await f.writeAccount('deny');
  }}), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 3); return true;
  });
  assert.equal(f.pageState.rows.length, 1); assert.equal(f.state.requests.length, 3);
  assert.equal(f.state.charges, 3); f.row.assertNoCapture();
});

test('active original page socket close remains pending until physical retirement and never authorizes capture', async t => {
  const f = await fixture(t);
  let entered, resume;
  const started = new Promise(resolve => {entered = resolve;});
  const blocked = new Promise(resolve => {resume = resolve;});
  f.pageState.responseHook = async request => {
    if (!request.url.startsWith('/crm/v3/objects/')) return false;
    entered(); await blocked; return false;
  };
  const pending = f.read();
  await started;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  resume();
  await assert.rejects(pending, error => {
    assert.equal(error.code, 'RemoteCredentialBindingRetiring');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(f.state.requests.length, 3); assert.equal(f.pageState.rows.length, 0);
  assert.equal(f.journal.recover().filter(r => r.outcome === 'unknown').length, 1);
  f.row.assertNoCapture();
});
