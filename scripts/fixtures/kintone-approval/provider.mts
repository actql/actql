// Synthetic provider DATA only. Revision comparison and exactly one UPDATE
// are protocol assertions; actual grants, claims and cleanup stay installed.
import assert from 'node:assert/strict';
import {createRecordUpdateProviderState} from '../record-approval/provider-state.mjs';
import type {RecordApprovalSeed} from '../record-approval/cases.mjs';
import {form} from '../../../adapters/connectors/kintone/test/kintone-update-form.fixture.mjs';

export function kintoneApprovalProvider(selection: RecordApprovalSeed) {
  const {recordId, controlId} = selection;
  for (const value of [recordId, controlId]) assert.match(value, /^[1-9][0-9]*$/u);
  const revision = '9007199254740994', nextRevision = '9007199254740995';
  const state = createRecordUpdateProviderState(selection, {revision});
  const {route} = state;
  const fields = ['$id', '$revision', 'Computed', 'Subject', 'Tags'];
  const record = (value: typeof state.target) => ({$id: {type: '__ID__', value: value.id},
    $revision: {type: '__REVISION__', value: value.revision},
    Subject: {type: 'SINGLE_LINE_TEXT', value: value.name},
    Tags: {type: 'MULTI_SELECT', value: ['red']},
    Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'}});
  const writeRoute = route('PUT', '/k/v1/records.json', exchange => {
    assert.equal(exchange.headers['x-http-method-override'], undefined);
    const body = JSON.parse(exchange.body);
    const name = body?.records?.[0]?.record?.Subject?.value;
    assert.equal(typeof name, 'string');
    assert.deepEqual(body, {app: '12', records: [{id: recordId, revision: state.target.revision,
      record: {Subject: {value: name}}}], upsert: false});
    state.updateTarget(name, {revision: nextRevision});
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
        return {records: [record(state.target)], totalCount: null};
      if (body.query === 'order by $id asc limit 2')
        return {records: [record(state.target), record(state.control)], totalCount: null};
      assert.equal(body.query, `$id > ${controlId} order by $id asc limit 2`);
      return {records: [], totalCount: null};
    }),
    writeRoute,
  ];
  return {routes, writeRequest: Object.freeze({method: writeRoute.method, pathname: writeRoute.pathname}),
    form: structuredClone(form), snapshot: state.snapshot, reset: state.reset};
}
