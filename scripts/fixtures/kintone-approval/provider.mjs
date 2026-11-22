// Synthetic provider DATA only. Revision comparison and exactly one UPDATE
// are protocol assertions; actual grants, claims and cleanup stay installed.
import assert from 'node:assert/strict';
import {recordUpdateFixtureSeed} from '../record-approval/cases.mjs';
import {form} from '../../../adapters/connectors/kintone/test/kintone-update-form.fixture.mjs';

export function kintoneApprovalProvider({recordId, controlId, previousName}) {
  for (const value of [recordId, controlId]) assert.match(value, /^[1-9][0-9]*$/u);
  const revision = '9007199254740994', nextRevision = '9007199254740995';
  const seed = recordUpdateFixtureSeed({recordId, controlId, previousName});
  const target = {...seed.target, revision};
  const control = {...seed.control, revision};
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
  const writeRoute = route('PUT', '/k/v1/records.json', exchange => {
    assert.equal(exchange.headers['x-http-method-override'], undefined);
    const body = JSON.parse(exchange.body);
    const name = body?.records?.[0]?.record?.Subject?.value;
    assert.equal(typeof name, 'string');
    assert.deepEqual(body, {app: '12', records: [{id: recordId, revision: target.revision,
      record: {Subject: {value: name}}}], upsert: false});
    assert.equal(writes, 0, 'Only one original physical UPDATE is expected');
    writes++; target.name = name; target.revision = nextRevision;
    return {records: [{id: recordId, revision: nextRevision}]};
  });
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
    writeRoute,
  ];
  return {routes, writeRequest: Object.freeze({method: writeRoute.method, pathname: writeRoute.pathname}), form: structuredClone(form), snapshot: () => ({writes,
    target: structuredClone(target), control: structuredClone(control),
    requests: structuredClone(requests), failures: structuredClone(failures)})};
}
