// The same generated Common runtime executes both branch codecs and the cold
// restoration. This fixture exercises request DATA before the physical owner.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as common from '../../../../_build/js/debug/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createKintoneKeyUpsertRequestAdapter} from '../host/kintone-key-upsert-request.mjs';
import {form, cid, encode, bytes, identity as nativeId, revision, policy} from './kintone-update.fixture.mjs';

const key = 'Key 東京';
const app = '12';
const input = {Subject: 'next 東京', Tags: ['red', 'red']};
const keyedForm = {revision: form.revision, properties: {
  Subject: {...form.properties.Subject, required: true},
  Tags: {...form.properties.Tags, required: false},
  Computed: {...form.properties.Computed, required: false},
  CustomerKey: {type: 'SINGLE_LINE_TEXT', code: 'CustomerKey', expression: '', unique: true, required: true},
}};
const present = {records: [{
  $id: {type: '__ID__', value: nativeId}, $revision: {type: '__REVISION__', value: revision},
  CustomerKey: {type: 'SINGLE_LINE_TEXT', value: key},
  Subject: {type: 'SINGLE_LINE_TEXT', value: 'before'},
  Tags: {type: 'MULTI_SELECT', value: ['red']},
  Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'},
}], totalCount: '1'};
const absent = {records: [], totalCount: '0'};
const observation = value => ({statusCode: 200, body: bytes(value)});

function fixture() {
  const catalog = checked(common.clientProgramKintoneProjectForm(bytes(keyedForm), app,
    common.clientProgramKintoneFormLimits(16384, 8000, 32, 16, 512)));
  const limits = common.clientProgramKintoneDeclarationLimits(65536, 8000, 32, 4, 16);
  const declaration = checked(common.clientProgramKintoneDeclareRecords(catalog, undefined,
    ['Subject', 'Tags', 'Computed', 'CustomerKey'], 'kintone', 'kintone/0.1', 'inquiries',
    common.clientProgramKintoneValueLimits(8, 512, 8000, 32, 16384), limits));
  const mapping = checked(common.clientProgramKintonePrepareKeyUpsertMapping(declaration, 'inquiries',
    'CustomerKey', [{target: 'Subject', field: 'subject', null_behavior: 'reject'},
      {target: 'Tags', field: 'tags', null_behavior: 'reject'}], limits));
  const calls = Object.create(null);
  const moon = {...common};
  for (const name of ['clientProgramKintoneLookupResponse', 'clientProgramKintoneRestoreKeyUpsertExecution']) {
    moon[name] = (...args) => {
      calls[name] = (calls[name] ?? 0) + 1;
      return common[name](...args);
    };
  }
  const options = {moon, declaration, mapping, origin: 'https://tenant.example.test', appId: app,
    connectorId: 'kintone', resource: 'inquiries', siteBindingCid: cid('a'), generationCid: cid('b'),
    guestSpaceId: '23', limits: policy};
  return {adapter: createKintoneKeyUpsertRequestAdapter(options), calls, options};
}

for (const [name, row] of [['create', absent], ['update', present]]) {
  test('keyed UPSERT retains the exact ' + name + ' branch across finalized request and cold restore', () => {
    const f = fixture(), adapter = f.adapter;
    const value = structuredClone(input), proposal = adapter.prepare({value, selector: key});
    value.Tags.push('changed');
    assert.deepEqual(adapter.requestFacts(proposal.request), {value: input, target: key});
    assert.throws(() => adapter.finalize({request: proposal.request, requestTag: cid('c')}),
      {code: 'KintoneKeyUpsertFinalizationUnavailable'});
    assert.deepEqual(JSON.parse(adapter.targetReadBody(proposal.request)), {
      app, fields: ['$id', '$revision', 'Subject', 'Tags', 'Computed', 'CustomerKey'],
      query: 'CustomerKey = "Key 東京" limit 2', totalCount: true,
    });
    adapter.recheckForm(proposal.request, observation(keyedForm));
    const target = adapter.projectTarget(proposal.request, observation(row));
    if (name === 'create') assert.deepEqual(target, {identity: key, state: 'absent'});
    else {
      assert.equal(target.identity, key);
      assert.equal(target.state, 'present');
      assert.match(target.versionCid, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(target.before, {$id: nativeId, Computed: 'server',
        CustomerKey: key, Subject: 'before', Tags: ['red']});
    }
    const final = adapter.finalize({request: proposal.request, requestTag: cid('c')});
    assert.notEqual(final.requestCid, proposal.requestCid);
    assert.equal(adapter.capabilityRequestCid(final.request), proposal.requestCid);
    adapter.assertFinalized(final.request, cid('c'));
    assert.throws(() => adapter.finalize({request: proposal.request, requestTag: cid('c')}),
      {code: 'KintoneKeyUpsertFinalizationUnavailable'});
    assert.throws(() => adapter.writeRequest({...final.request}), {code: 'ForeignKintoneKeyUpsertRequest'});
    const native = adapter.writeRequest(final.request);
    assert.equal(native.operation, 'kintone:records:' + name);
    assert.equal(native.method, name === 'create' ? 'POST' : 'PUT');
    assert.equal(native.path, '/k/guest/23/v1/records.json');
    const record = {Subject: {value: 'next 東京'}, Tags: {value: ['red', 'red']}};
    assert.deepEqual(JSON.parse(native.body), name === 'create'
      ? {app, records: [{...record, CustomerKey: {value: key}}]}
      : {app, records: [{id: nativeId, revision, record}], upsert: false});
    const wire = adapter.savedWire(final.request), cold = createKintoneKeyUpsertRequestAdapter(f.options);
    const restored = cold.restore({wire, requestTag: cid('c')});
    assert.deepEqual(cold.writeRequest(restored.request), native);
    assert.equal(restored.requestCid, final.requestCid);
    assert.equal(cold.savedWire(restored.request), wire);
    assert.equal(f.calls.clientProgramKintoneLookupResponse, 1);
    assert.equal(f.calls.clientProgramKintoneRestoreKeyUpsertExecution, 1);
    assert.throws(() => cold.projectTarget(restored.request, observation(name === 'create' ? present : absent)),
      {code: 'KintoneKeyUpsertTargetChanged'});
    const recordId = name === 'create' ? '9007199254740996' : nativeId;
    const resultRevision = '0009007199254740997';
    const reply = observation(name === 'create' ? {ids: [recordId], revisions: [resultRevision]}
      : {records: [{id: recordId, revision: resultRevision}]});
    const projected = cold.projectResponse(restored.request, reply);
    assert.equal(projected.kind, 'typed-success-response');
    assert.deepEqual(projected.outcome, {state: 'applied', action: name === 'create' ? 'created' : 'updated',
      result: {record_id: recordId, revision: resultRevision, ...(name === 'create' ? {created: true} : {})}});
    const wrongBranch = observation(name === 'create' ? {records: []} : {ids: [recordId], revisions: [resultRevision]});
    const rejected = cold.projectResponse(restored.request, wrongBranch);
    assert.equal(rejected.kind, 'unclassified-response');
    assert.strictEqual(rejected.observation, wrongBranch);
  });
}

test('keyed UPSERT refuses unstable Form, incomplete absence and a rehashed opposite saved branch', () => {
  const {adapter, options} = fixture(), proposal = adapter.prepare({value: input, selector: key});
  const changed = structuredClone(keyedForm);
  changed.properties.CustomerKey.unique = false;
  assert.throws(() => adapter.recheckForm(proposal.request, observation(changed)), {code: 'MoonBitHostFailure'});
  assert.throws(() => adapter.projectTarget(proposal.request, observation({records: [], totalCount: null})),
    {code: 'MoonBitHostFailure'});
  adapter.projectTarget(proposal.request, observation(absent));
  const final = adapter.finalize({request: proposal.request, requestTag: cid('c')});
  const original = JSON.parse(adapter.savedWire(final.request));
  const cold = createKintoneKeyUpsertRequestAdapter(options);
  assert.throws(() => cold.restore({wire: encode({...original, body: '{}'}), requestTag: cid('c')}),
    {code: 'ForeignKintoneKeyUpsertRecovery'});
  assert.throws(() => cold.restore({wire: encode(original), requestTag: cid('d')}),
    {code: 'ForeignKintoneKeyUpsertRecovery'});
  const forged = {...original, branch: 'update'};
  const hash = createHash('sha256').update(encode({binding: forged.binding, logicalCid: forged.logicalCid,
    requestTag: forged.requestTag, targetBodyCid: forged.targetBodyCid, branch: forged.branch, body: forged.body})).digest('hex');
  assert.throws(() => cold.restore({wire: encode({...forged, requestCid: 'sha256:' + hash}), requestTag: cid('c')}),
    {code: 'MoonBitHostFailure'});
});
