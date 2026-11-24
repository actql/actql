// Actual debug runtime DATA ports. The ordinary Site, approval and credential
// dispatch are exercised separately from this request codec.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/debug/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createKintoneDeleteRequestAdapter} from '../host/kintone-delete-request.mjs';
import {bytes, cid, encode, form, identity, observation, policy, revision} from './kintone-update.fixture.mjs';

function fixture() {
  const declarationLimits = moon.clientProgramKintoneDeclarationLimits(65536, 8000, 32, 4, 16);
  const catalog = checked(moon.clientProgramKintoneProjectForm(bytes(form), '12',
    moon.clientProgramKintoneFormLimits(16384, 8000, 32, 16, 512)));
  const declaration = checked(moon.clientProgramKintoneDeclareRecords(catalog, undefined,
    ['Subject', 'Tags', 'Computed'], 'kintone', 'kintone/0.1', 'inquiries',
    moon.clientProgramKintoneValueLimits(8, 512, 8000, 32, 16384), declarationLimits));
  const mapping = checked(moon.clientProgramKintonePrepareDeleteMapping(declaration, 'inquiries', 'required', declarationLimits));
  const {maxInputBytes: _updateOnly, ...limits} = policy;
  const options = {moon, declaration, mapping, origin: 'https://tenant.example.test', appId: '12',
    connectorId: 'kintone', resource: 'inquiries', siteBindingCid: cid('a'), generationCid: cid('b'), limits};
  return {options, adapter: createKintoneDeleteRequestAdapter(options)};
}

test('DELETE request binds the original target observation before finalizing one conditional body', () => {
  const {adapter} = fixture(), tag = cid('c');
  const {request, requestCid} = adapter.prepare({selector: identity});
  assert.deepEqual(adapter.requestFacts(request), {target: identity});
  assert.deepEqual(JSON.parse(adapter.targetReadBody(request)), {app: '12',
    fields: ['$id', '$revision', 'Computed', 'Subject', 'Tags'],
    query: '$id in (9007199254740993) order by $id asc limit 1'});
  assert.throws(() => adapter.finalize({request, requestTag: tag}), {code: 'KintoneDeleteFinalizationUnavailable'});
  assert.throws(() => adapter.prepare({selector: identity, value: {Subject: 'substituted'}}), {code: 'InvalidKintoneDeleteSelector'});
  adapter.recheckForm({statusCode: 200, body: bytes(form)});
  const target = adapter.projectTarget(request, observation());
  assert.deepEqual(target.before, {$id: identity, Computed: 'server', Subject: 'before', Tags: ['red']});
  assert.throws(() => adapter.projectTarget(request, observation({rev: '9007199254740995'})), {code: 'KintoneDeleteTargetChanged'});
  assert.throws(() => adapter.projectTarget(request, observation({id: '9007199254740992'})), {code: 'MoonBitHostFailure'});
  const final = adapter.finalize({request, requestTag: tag});
  assert.notEqual(final.requestCid, requestCid);
  assert.equal(adapter.capabilityRequestCid(final.request), requestCid);
  adapter.assertFinalized(final.request, tag);
  assert.deepEqual(JSON.parse(adapter.requestBody(final.request)), {app: '12', ids: [identity], revisions: [revision]});
  assert.equal(moon.clientProgramKintoneDeleteBody(adapter.nativeRequest(final.request)), adapter.requestBody(final.request));
  assert.throws(() => adapter.finalize({request, requestTag: cid('d')}), {code: 'KintoneDeleteFinalizationUnavailable'});
  assert.throws(() => adapter.nativeRequest({...final.request}), {code: 'ForeignKintoneDeleteRequest'});
});

test('DELETE recovery reprojects only the original bounded target bytes and conditional request', () => {
  const {adapter, options} = fixture(), tag = cid('c');
  const {request} = adapter.prepare({selector: identity});
  const response = observation();
  adapter.projectTarget(request, response);
  response.body.fill(0);
  const final = adapter.finalize({request, requestTag: tag});
  const wire = adapter.savedWire(final.request), cold = createKintoneDeleteRequestAdapter(options);
  const restored = cold.restore({wire, requestTag: tag});
  assert.equal(restored.requestCid, final.requestCid);
  assert.equal(cold.savedWire(restored.request), wire);
  cold.assertFinalized(restored.request, tag);
  const original = JSON.parse(wire);
  for (const changed of [
    {...original, body: original.body.replace(revision, '9007199254740995')},
    {...original, requestTag: cid('d')},
    {...original, targetBodyBase64: observation({subject: 'foreign'}).body.toString('base64')},
    {...original, binding: {...original.binding, appId: {value: '12'}}},
  ]) assert.throws(() => cold.restore({wire: encode(changed), requestTag: tag}), {code: 'ForeignKintoneDeleteRecovery'});
  assert.throws(() => createKintoneDeleteRequestAdapter({...options, declaration: {...options.declaration}}),
    {code: 'ForeignKintoneDeleteMapping'});
  const changedForm = structuredClone(form);
  changedForm.revision = '8';
  assert.throws(() => cold.recheckForm({statusCode: 200, body: bytes(changedForm)}), {code: 'MoonBitHostFailure'});
});
