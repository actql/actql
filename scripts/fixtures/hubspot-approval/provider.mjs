// Independent synthetic provider DATA and protocol assertions. The actual
// installed Host retains all Account, Credential, Preview, approval and claims.
// These routes neither grant a write nor classify a lost response as absent.
import assert from 'node:assert/strict';

const cid = /^sha256:[0-9a-f]{64}$/u;
const sameKeys = (value, names) => assert.deepEqual(Object.keys(value).sort(), [...names].sort());

export function hubspotApprovalProvider({recordId, controlId, previousName, nextName}) {
  for (const value of [recordId, controlId, previousName, nextName]) {
    assert.equal(typeof value, 'string');
    assert(value.length > 0);
  }
  assert.notEqual(recordId, controlId);
  assert.notEqual(previousName, nextName);
  const target = {id: recordId, name: previousName, marker: '', updatedAt: '2026-11-07T00:00:00.000Z'};
  const control = {id: controlId, name: 'Untouched control', marker: '', updatedAt: target.updatedAt};
  const properties = {results: ['actql_request_id', 'name'].map(name => ({name,
    type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}}))};
  const record = value => ({id: value.id, archived: false, updatedAt: value.updatedAt,
    properties: {name: value.name, actql_request_id: value.marker}});
  let writes = 0;
  const requests = [], failures = [];
  const route = (method, pathname, action) => ({method, pathname, handle(exchange) {
    try {
      assert.equal(exchange.method, method);
      assert.equal(exchange.pathname, pathname);
      assert.equal(exchange.authorized, true, 'The original credential header must be present');
      requests.push({method, pathname});
      return {body: action(exchange)};
    } catch (error) {
      failures.push({name: error.name, code: error.code, message: error.message});
      throw error;
    }
  }});
  const routes = [
    route('GET', '/account-info/v3/details', () => ({portalId: 7, accountType: 'STANDARD'})),
    route('GET', '/crm/v3/properties/companies', () => structuredClone(properties)),
    route('GET', '/crm/v3/objects/companies', () => ({results: [record(target), record(control)]})),
    route('POST', '/crm/v3/objects/companies/batch/read', exchange => {
      const body = JSON.parse(exchange.body);
      sameKeys(body, ['inputs', 'properties']);
      assert.deepEqual(body.inputs, [{id: recordId}]);
      assert.deepEqual(body.properties, ['name']);
      return {status: 'COMPLETE', results: [record(target)]};
    }),
    route('POST', '/crm/v3/objects/companies/batch/update', exchange => {
      const body = JSON.parse(exchange.body);
      sameKeys(body, ['inputs']);
      assert.equal(body.inputs.length, 1);
      const item = body.inputs[0];
      sameKeys(item, ['id', 'objectWriteTraceId', 'properties']);
      assert.equal(item.id, recordId);
      assert.match(item.objectWriteTraceId, cid);
      sameKeys(item.properties, ['name', 'actql_request_id']);
      assert.equal(item.properties.name, nextName);
      assert.match(item.properties.actql_request_id, cid);
      assert.equal(writes, 0, 'Only one original physical UPDATE is expected');
      writes++;
      target.name = item.properties.name;
      target.marker = item.properties.actql_request_id;
      target.updatedAt = '2026-11-07T00:00:01.000Z';
      return {status: 'COMPLETE', results: [record(target)]};
    }),
  ];
  return {routes, properties, account: {portalId: 7, accountType: 'STANDARD'},
    snapshot: () => ({writes, target: structuredClone(target), control: structuredClone(control),
      requests: structuredClone(requests), failures: structuredClone(failures)})};
}
