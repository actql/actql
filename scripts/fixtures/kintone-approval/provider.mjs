// Synthetic provider DATA for the original CREATE or revision-checked UPDATE.
import assert from 'node:assert/strict';
import {createRecordUpdateProviderState} from '../record-approval/provider-state.mjs';
import {form} from '../../../adapters/connectors/kintone/test/kintone-update-form.fixture.mjs';

export function kintoneApprovalProvider(selection) {
  const {recordId, controlId, key} = selection;
  const keyed = key !== undefined, creating = keyed && selection.previousName === null;
  const controlKey = 'Untouched fixture key';
  if (keyed) assert(typeof key === 'string' && key.length > 0 && key !== controlKey);
  for (const value of [recordId, controlId]) assert.match(value, /^[1-9][0-9]*$/u);
  const revision = '9007199254740994', nextRevision = '9007199254740995';
  const state = createRecordUpdateProviderState(selection, {revision}, {allowCreate: keyed});
  const {route} = state;
  const fields = ['$id', '$revision', 'Computed', ...(keyed ? ['CustomerKey'] : []), 'Subject', 'Tags'];
  const projectedForm = structuredClone(form);
  if (keyed) {
    projectedForm.properties.Subject.required = true;
    projectedForm.properties.Tags.required = false;
    projectedForm.properties.Computed.required = false;
    projectedForm.properties.CustomerKey = {code: 'CustomerKey', type: 'SINGLE_LINE_TEXT', expression: '',
      unique: true, required: true};
  }
  const record = value => ({$id: {type: '__ID__', value: value.id},
    $revision: {type: '__REVISION__', value: value.revision},
    Subject: {type: 'SINGLE_LINE_TEXT', value: value.name},
    Tags: {type: 'MULTI_SELECT', value: ['red']},
    Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'},
    ...(keyed ? {CustomerKey: {type: 'SINGLE_LINE_TEXT', value: value.id === controlId ? controlKey : key}} : {})});
  const writeRoute = route('PUT', '/k/v1/records.json', exchange => {
    assert.equal(exchange.headers['x-http-method-override'], undefined);
    assert(state.target !== null);
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
      return structuredClone(projectedForm);
    }),
    route('POST', '/k/v1/records.json', exchange => {
      const body = JSON.parse(exchange.body);
      if (keyed && exchange.headers['x-http-method-override'] === undefined) {
        const name = body?.records?.[0]?.Subject?.value;
        assert.equal(typeof name, 'string');
        assert.deepEqual(body, {app: '12', records: [{CustomerKey: {value: key}, Subject: {value: name}}]});
        state.createTarget(name, {revision: nextRevision});
        return {ids: [recordId], revisions: [nextRevision]};
      }
      assert.equal(exchange.headers['x-http-method-override'], 'GET');
      if (keyed && Object.hasOwn(body, 'totalCount')) {
        assert.deepEqual(body, {app: '12', fields, query: `CustomerKey = ${JSON.stringify(key)} limit 2`, totalCount: true});
        const target = state.target;
        return {records: target === null ? [] : [record(target)], totalCount: target === null ? '0' : '1'};
      }
      assert.deepEqual(Object.keys(body).sort(), ['app', 'fields', 'query']);
      assert.equal(body.app, '12'); assert.deepEqual(body.fields, fields);
      if (body.query === `$id in (${recordId}) order by $id asc limit 1`)
        return {records: [record(state.target)], totalCount: null};
      if (body.query === 'order by $id asc limit 2')
        return {records: [state.target, state.control].filter(value => value !== null).map(record), totalCount: null};
      assert.equal(body.query, `$id > ${controlId} order by $id asc limit 2`);
      return {records: [], totalCount: null};
    }),
    writeRoute,
  ];
  return {routes, writeRequest: Object.freeze({method: creating ? 'POST' : writeRoute.method, pathname: writeRoute.pathname,
    ...(keyed ? {methodOverride: null} : {}), ...(creating ? {bodyIncludes: '"records":['} : {})}),
    form: projectedForm, snapshot: state.snapshot, reset: state.reset};
}
