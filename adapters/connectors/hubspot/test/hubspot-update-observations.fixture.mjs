// Actual Native decoders with explicit authorization/current/physical-child
// ports. No actual Account, Credential, Ledger, TLS, update or Run is claimed.
import assert from 'node:assert/strict';
import test from 'node:test';
import {hubspotUpdateRequestFixture} from './hubspot-update-request.fixture.mjs';
import {createHubSpotUpdateObservationAdapter, HubSpotUpdateObservationFailure} from '../host/hubspot-update-observations.mjs';

const recordId = '9007199254740993';
const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', calculated: false,
    modificationMetadata: {readOnlyValue: false}, options: [{value: 'a'}, {value: 'b'}]},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
const record = () => ({id: recordId, archived: false, updatedAt: '2026-11-07T00:00:00.000Z',
  properties: {amount: '9007199254740993.01', tags: 'a;b'}});
function fixture(moon) {
  const f = hubspotUpdateRequestFixture(moon);
  const limits = {maxResponseBytes: 30000, maxRequestBytes: 10000, maxNodes: 3000, maxDepth: 24,
    maxProperties: 100, maxNameUnits: 256, maxRows: 10, maxColumns: 10, maxCursorUnits: 256,
    maxValueNodes: 3000, maxValueTextBytes: 8192, maxOutputBytes: 10000, maxOutputNodes: 3000,
    maxOutputDepth: 24, maxRequestNodes: 3000, maxRequestDepth: 24};
  const adapter = createHubSpotUpdateObservationAdapter({moon, portalId: '7', installedFor: () => f.installed,
    requests: f.adapter, limits});
  const value = {amount: '1.0000000000', tags: ['a']};
  const prepared = f.adapter.prepare({member: f.member, value, selector: recordId});
  const state = {calls: [], events: [], authorize: [], verifies: [], responseHook: undefined, verifyHook: undefined};
  const options = {member: f.member, entries: [{request: prepared.request}],
    async verify(slot) {state.verifies.push(slot); await state.verifyHook?.(slot);},
    async authorizationFor(slot, row) {
      const grant = Object.freeze({componentSlot: slot, row, occurrence: state.authorize.length});
      const original = Object.freeze({grant, useId: 'original-' + state.authorize.length});
      state.authorize.push({slot, row, original}); return original;
    },
    async readChild(authorization, input, row, slot, project) {
      assert.strictEqual(authorization, state.authorize.at(-1).original);
      assert.strictEqual(input.grant, authorization.grant); assert.equal(input.useId, authorization.useId);
      assert.equal(input.returnRejectedResponse, true); assert.equal(input.operations.size, 1);
      const [[operation, http]] = [...input.operations];
      state.calls.push({slot, row, operation, http, input}); state.events.push(slot + ':begin');
      await input.currentBeforeSend();
      const body = slot === 'account' ? {portalId: 7} : slot === 'target'
        ? {status: 'COMPLETE', results: [record()]} : properties;
      const response = {accepted: true, statusCode: 200, body: Buffer.from(JSON.stringify(body))};
      await state.responseHook?.(slot, response);
      const output = project(response);
      assert.equal(typeof output?.then, 'undefined'); state.events.push(slot + ':projected');
      return output;
    }};
  const describe = () => adapter.describe(options);
  return {...f, adapter, limits, prepared, state, options, describe,
    async observe(current) {return adapter.observeTargets({...options, current});}};
}

export function registerHubSpotUpdateObservationTests(moon) {
  test('HubSpot update reads exact account schema target schema through distinct original child slots', async () => {
    const f = fixture(moon), current = await f.describe(), rows = await f.observe(current);
    assert.deepEqual(f.state.calls.map(({slot}) => slot), ['account', 'schema', 'account', 'schema-before', 'target', 'schema-after']);
    assert.deepEqual(f.state.calls.map(({operation, http}) => [operation, http.method, http.path]), [
      ['hubspot:account:details', 'GET', '/account-info/v3/details'],
      ['hubspot:properties:read', 'GET', '/crm/v3/properties/companies'],
      ['hubspot:account:details', 'GET', '/account-info/v3/details'],
      ['hubspot:properties:read', 'GET', '/crm/v3/properties/companies'],
      ['hubspot:objects:batch-read', 'POST', '/crm/v3/objects/companies/batch/read'],
      ['hubspot:properties:read', 'GET', '/crm/v3/properties/companies'],
    ]);
    assert.deepEqual(JSON.parse(f.state.calls[4].http.body), {
      inputs: [{id: recordId}], properties: ['amount', 'tags']});
    assert.deepEqual(rows[0].before, {amount: '9007199254740993.0100000000', tags: ['a', 'b']});
    assert.equal(rows[0].identity, recordId); assert.match(rows[0].versionCid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(f.state.authorize.length, 6); assert.equal(new Set(f.state.authorize.map(a => a.original)).size, 6);
    assert.deepEqual(f.state.events, f.state.calls.flatMap(({slot}) => [slot + ':begin', slot + ':projected']));
  });

  test('HubSpot update cannot promote rejected account foreign portal or changed schema into a current description', async () => {
    for (const changed of ['http', 'portal', 'schema']) {
      const f = fixture(moon);
      f.state.responseHook = (slot, response) => {
        if (changed === 'http' && slot === 'account') response.accepted = false;
        if (changed === 'portal' && slot === 'account') response.body = Buffer.from('{"portalId":8}');
        if (changed === 'schema' && slot === 'schema') {
          const body = structuredClone(properties); body.results[0].type = 'string'; body.results[0].fieldType = 'text';
          response.body = Buffer.from(JSON.stringify(body));
        }
      };
      await assert.rejects(f.describe(), error => error instanceof HubSpotUpdateObservationFailure &&
        error.observations.length === (changed === 'schema' ? 2 : 1));
      assert.equal(f.state.calls.length, changed === 'schema' ? 2 : 1);
    }
  });

  test('HubSpot target missing foreign archived duplicate and partial responses never prove an absent or writable row', async () => {
    for (const changed of ['missing', 'foreign', 'archived', 'duplicate', 'partial']) {
      const f = fixture(moon), current = await f.describe();
      f.state.responseHook = (slot, response) => {
        if (slot !== 'target') return;
        const body = {status: 'COMPLETE', results: [record()]};
        if (changed === 'missing') body.results = [];
        if (changed === 'foreign') body.results[0].id = 'other';
        if (changed === 'archived') body.results[0].archived = true;
        if (changed === 'duplicate') body.results.push(record());
        if (changed === 'partial') body.status = 'PENDING';
        response.body = Buffer.from(JSON.stringify(body));
      };
      await assert.rejects(f.observe(current), error => error instanceof HubSpotUpdateObservationFailure && error.observations.length === 3);
      assert.equal(f.state.calls.at(-1).slot, 'target');
    }
  });

  test('HubSpot update schema-after change or current cancellation prevents an observed guard from escaping', async () => {
    for (const changed of ['schema', 'current', 'cancel']) {
      const f = fixture(moon), current = await f.describe(), cause = new Error('Original current cancelled');
      const controller = new AbortController(); f.options.signal = controller.signal;
      f.state.responseHook = (slot, response) => {
        if (changed === 'schema' && slot === 'schema-after') {
          const body = structuredClone(properties); body.results[0].modificationMetadata.readOnlyValue = true;
          response.body = Buffer.from(JSON.stringify(body));
        }
        if (changed === 'cancel' && slot === 'target') controller.abort(cause);
      };
      if (changed === 'current') f.state.verifyHook = slot => {if (slot === 'schema-after') throw cause;};
      await assert.rejects(f.observe(current), error => error instanceof HubSpotUpdateObservationFailure &&
        (changed === 'schema' || error.cause === cause));
      assert.equal(f.state.calls.at(-1).slot, changed === 'schema' ? 'schema-after' : 'target');
    }
  });

  test('HubSpot update current belongs to the original holder and guard includes exact typed state and update timestamp', async () => {
    const f = fixture(moon), current = await f.describe(), before = f.state.calls.length;
    const foreign = fixture(moon), foreignCurrent = await foreign.describe();
    for (const copied of [{...current}, foreignCurrent]) {
      await assert.rejects(f.observe(copied), {code: 'ForeignHubSpotUpdateCurrent'});
      assert.equal(f.state.calls.length, before);
    }
    const [first] = await f.observe(current);
    f.state.responseHook = (slot, response) => {
      if (slot === 'target') {
        const body = {status: 'COMPLETE', results: [record()]};
        body.results[0].updatedAt = '2026-11-07T00:00:01.000Z'; response.body = Buffer.from(JSON.stringify(body));
      }
    };
    const [later] = await f.observe(current);
    assert.deepEqual(first.before, later.before); assert.notEqual(first.versionCid, later.versionCid);
    f.limits.maxResponseBytes = 999999;
    f.state.responseHook = (slot, response) => {if (slot === 'account') response.body = Buffer.from(' '.repeat(30001));};
    await assert.rejects(f.describe(), error => error instanceof HubSpotUpdateObservationFailure);
    assert.equal(f.state.calls.at(-1).input.maxResponseBytes, 30000);
  });
}
