// Synthetic provider DATA only. Revision comparison and exactly one UPDATE
// are protocol assertions; actual grants, claims and cleanup stay installed.
import assert from 'node:assert/strict';
import {form} from '../../../adapters/connectors/kintone/test/kintone-update-form.fixture.mjs';

export function kintoneApprovalProvider({recordId, controlId, previousName, nextName}) {
  for (const value of [recordId, controlId]) assert.match(value, /^[1-9][0-9]*$/u);
  for (const value of [previousName, nextName]) {
    assert.equal(typeof value, 'string'); assert(value.length > 0);
  }
  assert.notEqual(recordId, controlId);
  assert.notEqual(previousName, nextName);
  const revision = '9007199254740994', nextRevision = '9007199254740995';
  const target = {id: recordId, name: previousName, revision};
  const control = {id: controlId, name: 'Untouched control', revision};
  const fields = ['$id', '$revision', 'Computed', 'Subject', 'Tags'];
  const record = value => ({$id: {type: '__ID__', value: value.id},
    $revision: {type: '__REVISION__', value: value.revision},
    Subject: {type: 'SINGLE_LINE_TEXT', value: value.name},
    Tags: {type: 'MULTI_SELECT', value: ['red']},
    Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'}});
  let writes = 0;
  const requests = [], failures = [];
  const route = (method, pathname, action) => ({method, pathname, handle(exchange) {
    try {
      assert.equal(exchange.method, method); assert.equal(exchange.pathname, pathname);
      assert.equal(exchange.authorized, true, 'The original credential header must be present');
      requests.push({method, pathname});
      return {body: action(exchange)};
    } catch (error) {
      failures.push({name: error.name, code: error.code, message: error.message});
      throw error;
    }
  }});
  const routes = [
    route('POST', '/k/v1/app/form/fields.json', exchange => {
      assert.equal(exchange.headers['x-http-method-override'], 'GET');
      assert.deepEqual(JSON.parse(exchange.body), {app: '12'});
      return structuredClone(form);
    }),
    route('POST', '/k/v1/records.json', exchange => {
      assert.equal(exchange.headers['x-http-method-override'], 'GET');
      const body = JSON.parse(exchange.body);
      assert.deepEqual(Object.keys(body).sort(), ['app', 'fields', 'query']);
      assert.equal(body.app, '12'); assert.deepEqual(body.fields, fields);
      if (body.query === `$id in (${recordId}) order by $id asc limit 1`)
        return {records: [record(target)], totalCount: null};
      if (body.query === 'order by $id asc limit 2')
        return {records: [record(target), record(control)], totalCount: null};
      assert.equal(body.query, `$id > ${controlId} order by $id asc limit 2`);
      return {records: [], totalCount: null};
    }),
    route('PUT', '/k/v1/records.json', exchange => {
      assert.equal(exchange.headers['x-http-method-override'], undefined);
      assert.deepEqual(JSON.parse(exchange.body), {app: '12', records: [{id: recordId, revision,
        record: {Subject: {value: nextName}}}], upsert: false});
      assert.equal(writes, 0, 'Only one original physical UPDATE is expected');
      writes++; target.name = nextName; target.revision = nextRevision;
      return {records: [{id: recordId, revision: nextRevision}]};
    }),
  ];
  return {routes, form: structuredClone(form), snapshot: () => ({writes,
    target: structuredClone(target), control: structuredClone(control),
    requests: structuredClone(requests), failures: structuredClone(failures)})};
}
