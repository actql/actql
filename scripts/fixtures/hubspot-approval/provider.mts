// Independent synthetic provider DATA and protocol assertions. The actual
// installed Host retains all Account, Credential, Preview, approval and claims.
// These routes neither grant a write nor classify a lost response as absent.
import assert from 'node:assert/strict';
import {createRecordUpdateProviderState} from '../record-approval/provider-state.mjs';
import type {RecordApprovalSeed} from '../record-approval/cases.mjs';

const cid = /^sha256:[0-9a-f]{64}$/u;
const sameKeys = (value: object, names: readonly string[]) => assert.deepEqual(Object.keys(value).sort(), [...names].sort());

export function hubspotApprovalProvider(selection: RecordApprovalSeed, collection?: Readonly<{
  additionalTargets: readonly Readonly<{id: string; name: string}>[];
  writeOrder: readonly string[];
}>) {
  const state = createRecordUpdateProviderState(selection, {marker: '', updatedAt: '2026-11-07T00:00:00.000Z'}, {
    operation: 'update', additionalTargets: collection?.additionalTargets,
    writes: collection?.writeOrder.map(key => ({operation: 'update', key})),
  });
  const {route} = state;
  const properties = {results: ['actql_request_id', 'name'].map(name => ({name,
    type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}}))};
  const record = (value: NonNullable<typeof state.target>) => ({id: value.id, archived: false, updatedAt: value.updatedAt,
    properties: {name: value.name, actql_request_id: value.marker}});
  const writeRoute = route('POST', '/crm/v3/objects/companies/batch/update', exchange => {
    const body = JSON.parse(exchange.body);
    sameKeys(body, ['inputs']);
    assert.equal(body.inputs.length, 1);
    const item = body.inputs[0];
    sameKeys(item, ['id', 'objectWriteTraceId', 'properties']);
    assert.match(item.objectWriteTraceId, cid);
    sameKeys(item.properties, ['name', 'actql_request_id']);
    assert.match(item.properties.actql_request_id, cid);
    const target = state.updateTarget(item.properties.name, {marker: item.properties.actql_request_id,
      updatedAt: '2026-11-07T00:00:01.000Z'}, item.id);
    return {status: 'COMPLETE', results: [record(target)]};
  });
  const routes = [
    route('GET', '/account-info/v3/details', () => ({portalId: 7, accountType: 'STANDARD'})),
    route('GET', '/crm/v3/properties/companies', () => structuredClone(properties)),
    route('GET', '/crm/v3/objects/companies', () => ({results: [...state.targets().map(record), record(state.control)]})),
    route('POST', '/crm/v3/objects/companies/batch/read', exchange => {
      const body = JSON.parse(exchange.body);
      sameKeys(body, ['inputs', 'properties']);
      assert.equal(body.inputs.length, 1);
      sameKeys(body.inputs[0], ['id']);
      assert.deepEqual(body.properties, ['name']);
      const target = state.readTarget(body.inputs[0].id);
      assert(target);
      return {status: 'COMPLETE', results: [record(target)]};
    }),
    writeRoute,
  ];
  return {routes, writeRequest: Object.freeze({method: writeRoute.method, pathname: writeRoute.pathname}), properties, account: {portalId: 7, accountType: 'STANDARD'},
    snapshot: state.snapshot, reset: state.reset};
}
