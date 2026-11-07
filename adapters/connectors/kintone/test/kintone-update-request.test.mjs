// Real same-source debug Common DATA ports. No provider I/O, Account decision,
// physical funding, ordinary Host or normal package acceptance is claimed.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as common from '../../../../_build/js/debug/build/connectors_builtin_node/connectors_builtin_node.js';
import {createKintoneUpdateRequestAdapter} from '../host/kintone-update-request.mjs';

import {cid, encode, bytes, identity, revision, form, value, observation, fixture} from './kintone-update.fixture.mjs';
function finalized(f, target = observation()) {
  const prepared = f.adapter.prepare({value, selector: identity});
  f.adapter.projectTarget(prepared.request, target);
  return f.adapter.finalize({request: prepared.request, requestTag: cid('c')});
}

test('UPDATE adapter preserves the original complete target before final CID and native PUT body', () => {
  const f = fixture(), a = f.adapter, prepared = a.prepare({value, selector: identity});
  assert.throws(() => a.finalize({request: prepared.request, requestTag: cid('c')}),
    {code: 'KintoneUpdateFinalizationUnavailable'});
  assert.throws(() => a.nativeRequest(prepared.request), {code: 'KintoneUpdateRequestNotFinalized'});
  assert.deepEqual(JSON.parse(a.targetReadBody(prepared.request)), {app: '12',
    fields: ['$id', '$revision', 'Computed', 'Subject', 'Tags'],
    query: '$id in (9007199254740993) order by $id asc limit 1'});
  const target = a.projectTarget(prepared.request, observation());
  assert.equal(target.identity, identity); assert.equal(target.before.Subject, 'before');
  assert.equal(target.before.Computed, 'server'); assert.match(target.versionCid, /^sha256:[0-9a-f]{64}$/u);
  const final = a.finalize({request: prepared.request, requestTag: cid('c')});
  assert.notEqual(final.requestCid, prepared.requestCid);
  assert.equal(a.capabilityRequestCid(final.request), prepared.requestCid);
  a.assertFinalized(final.request, cid('c'));
  assert.deepEqual(a.requestFacts(final.request), {value, target: identity});
  assert.deepEqual(JSON.parse(common.clientProgramKintoneUpdateBody(a.nativeRequest(final.request))), {
    app: '12', records: [{id: identity, revision, record: {
      Subject: {value: 'next 東京'}, Tags: {value: ['red', 'red']}}}], upsert: false});
  assert.throws(() => a.finalize({request: prepared.request, requestTag: cid('d')}),
    {code: 'KintoneUpdateFinalizationUnavailable'});
  assert.throws(() => a.nativeRequest({...final.request}), {code: 'ForeignKintoneUpdateRequest'});
});

test('UPDATE adapter restores the full saved body with independent before and PUT output bounds', () => {
  const f = fixture(), final = finalized(f, observation({subject: 'x'.repeat(6000)}));
  const wire = f.adapter.savedWire(final.request), a = createKintoneUpdateRequestAdapter(f.options);
  const freshCalls = f.calls.clientProgramKintonePrepareUpdateProposal;
  const restored = a.restore({wire, requestTag: cid('c')});
  assert.equal(f.calls.clientProgramKintonePrepareUpdateProposal, freshCalls,
    'cold enters the full Restore port, without calling the external fresh proposal port');
  assert.equal(f.calls.clientProgramKintoneRestoreUpdateExecution, 1);
  assert.equal(restored.requestCid, final.requestCid); a.assertFinalized(restored.request, cid('c'));
  assert.equal(a.savedWire(restored.request), wire);
  assert.deepEqual(a.requestFacts(restored.request), {value, target: identity});
  assert.equal(a.projectTarget(restored.request, observation({subject: 'x'.repeat(6000)})).before.Subject.length, 6000);
  assert.deepEqual(f.adapter.projectTarget(final.request, observation({subject: 'x'.repeat(6000)})).before,
    a.projectTarget(restored.request, observation({subject: 'x'.repeat(6000)})).before);
  assert.throws(() => a.assertFinalized(restored.request, cid('d')), {code: 'KintoneUpdateRequestTagMismatch'});
});

test('UPDATE adapter keeps complete Form and fresh target drift refusals without rebinding the request', () => {
  const f = fixture(), a = f.adapter, final = finalized(f);
  a.recheckForm({statusCode: 200, body: bytes(form)});
  const changedForm = structuredClone(form); changedForm.properties.Computed.expression = 'changed';
  assert.throws(() => a.recheckForm({statusCode: 200, body: bytes(changedForm)}), {code: 'MoonBitHostFailure'});
  assert.throws(() => a.projectTarget(final.request, observation({subject: 'changed'})), {code: 'KintoneUpdateTargetChanged'});
  assert.throws(() => a.projectTarget(final.request, observation({rev: '9007199254740995'})), {code: 'KintoneUpdateTargetChanged'});
  assert.throws(() => a.projectTarget(final.request, observation({id: '9007199254740992'})), {code: 'MoonBitHostFailure'});
  assert.throws(() => a.projectTarget(final.request, {statusCode: 404, body: bytes({})}), {code: 'InvalidKintoneTargetObservation'});
  const partial = JSON.parse(observation().body); delete partial.records[0].Computed;
  assert.throws(() => a.projectTarget(final.request, {statusCode: 200, body: bytes(partial)}), {code: 'MoonBitHostFailure'});
  assert.equal(JSON.parse(common.clientProgramKintoneUpdateBody(a.nativeRequest(final.request))).records[0].revision, revision);
});

test('UPDATE adapter rejects changed saved request fields and preserves captured native entry points', () => {
  const f = fixture(), final = finalized(f), wire = f.adapter.savedWire(final.request), original = JSON.parse(wire);
  const cold = createKintoneUpdateRequestAdapter(f.options);
  for (const changed of [
    {...original, body: original.body.replace('next 東京', 'different')},
    {...original, requestTag: cid('d')},
    {...original, valueWire: encode({...value, Subject: 'different'})},
    {...original, targetBodyBase64: Buffer.from(observation({subject: 'different'}).body).toString('base64')},
    {...original, binding: {...original.binding, appId: '13'}},
  ]) assert.throws(() => cold.restore({wire: encode(changed), requestTag: cid('c')}),
    {code: 'ForeignKintoneUpdateRecovery'});
  for (const name of Object.keys(f.moon)) if (typeof f.moon[name] === 'function') f.moon[name] = () => assert.fail('replaced native export');
  const restored = cold.restore({wire, requestTag: cid('c')});
  assert.equal(restored.requestCid, final.requestCid); cold.assertFinalized(restored.request, cid('c'));
});
