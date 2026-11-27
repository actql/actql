import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {deriveInstalledRowTextUpdate} from './installed-row-effect-text-update.mjs';
import {prepareInstalledDeclaredUpdatePlanRecipe} from './installed-effect-plan.mjs';

const cid = raw => `sha256:${createHash('sha256').update(raw).digest('hex')}`;
const domain = 'external-event-update', boundaryCid = `sha256:${'f'.repeat(64)}`;
const id = 'a'.repeat(32), note = '\u0001'.repeat(64);
const originalBody = JSON.stringify({note});
const requestCid = cid(JSON.stringify({body: originalBody, boundaryCid, id, note, version: domain}));
const member = Object.freeze({kind: 'update', resource: 'events', effectId: 'a'.repeat(128), memberIndex: 0,
  mapping: Object.freeze({primaryIdentity: 'id', mappingCid: `sha256:${'c'.repeat(64)}`})});
const wire = JSON.stringify([boundaryCid, [member.effectId, member.memberIndex, member.mapping.mappingCid], id, note]);
const original = Object.freeze({memberIndex: 0, kind: domain, wire, observationCid: cid(wire)});
const transport = Object.freeze({maxRequestBytes: 512, maxResponseBytes: 512, maxTargetBytes: 80});
const write = Object.freeze({kind: 'update', operation: 'change', transport,
  targetRead: Object.freeze({operation: 'observe', transport}),
  standardText: Object.freeze({resource: 'events', identityField: 'id', field: 'note', domain,
    boundaryCid, maxIdentityUnits: 32, maxTextUnits: 64, maxRecoveryBytes: 1024})});

function setup(selectedWrite = write) {
  let requestCalls = 0, recoveryCalls = 0;
  const runtime = Object.freeze({
    clientProgramInstalledUpdateTextRequestBounds: moon.clientProgramInstalledUpdateTextRequestBounds,
    clientProgramConstructInstalledUpdateTextRequest(...args) {
      requestCalls++;
      return moon.clientProgramConstructInstalledUpdateTextRequest(...args);
    },
    clientProgramConstructInstalledUpdateTextRecovery(...args) {
      recoveryCalls++;
      return moon.clientProgramConstructInstalledUpdateTextRecovery(...args);
    },
  });
  return {...deriveInstalledRowTextUpdate(runtime, selectedWrite), counts: () => [requestCalls, recoveryCalls]};
}

test('standard textual UPDATE restores an explicitly nullable mapped column and rejects a missing cell', () => {
  const tickets = Object.freeze({...write, standardText: Object.freeze({...write.standardText,
    resource: 'tickets', identityField: 'ticket_key', field: 'memo', domain: 'ticket-update'})});
  const {owned, admitsNull, counts} = setup(tickets);
  const policy = {primary_identity: 'ticket_key',
    target_schema: {fields: {memo: {type: 'string', nullable: true}}},
    row_mapping: {memo: {null_behavior: 'write_null'}}};
  assert(admitsNull('tickets', policy));
  assert(!admitsNull('events', policy));
  assert(!admitsNull('tickets', {...policy, primary_identity: 'id'}));
  assert(!admitsNull('tickets', {...policy, target_schema: {fields: {memo: {type: 'string', nullable: false}}}}));
  assert(!admitsNull('tickets', {...policy, row_mapping: {memo: {null_behavior: 'omit'}}}));
  const selected = Object.freeze({...member, resource: 'tickets',
    mapping: Object.freeze({...member.mapping, primaryIdentity: 'ticket_key',
      standardTextAcceptsNull: admitsNull('tickets', policy)})});
  const selector = 'ac-7';
  const prepare = (value, original = selected) => owned.prepareRequest({member: original, selector, value});
  assert.throws(() => prepare({}), {code: 'ForeignInstalledRowEffectRequest'});
  assert.throws(() => prepare({memo: undefined}), {code: 'ForeignInstalledRowEffectRequest'});
  assert.throws(() => prepare({memo: null}, {...selected, mapping: {...selected.mapping, standardTextAcceptsNull: false}}),
    {code: 'ForeignInstalledRowEffectRequest'});
  assert.deepEqual(counts(), [0, 0]);
  const prepared = prepare({memo: null});
  const body = JSON.stringify({memo: null});
  assert.equal(prepared.request.body, body);
  assert.equal(prepared.requestCid, cid(JSON.stringify({
    body, boundaryCid, memo: null, ticket_key: selector, version: 'ticket-update'})));
  const facts = owned.requestFacts(prepared.request);
  const saved = owned.recoveryEntry({member: selected, entries: [{...prepared, ...facts}]});
  assert.equal(saved.wire, JSON.stringify([boundaryCid, [selected.effectId, selected.memberIndex,
    selected.mapping.mappingCid], selector, null]));
  assert.equal(saved.observationCid, cid(saved.wire));
  assert.notEqual(prepare({memo: 'null'}).requestCid, prepared.requestCid);
  const cold = setup(tickets);
  const restore = (value) => cold.owned.recoverRequests({members: [selected],
    body: {effects: [{effect_id: selected.effectId, changes: [{target_row_identity: selector, after: {value}}]}]},
    durable: {connectorRecovery: [{memberIndex: selected.memberIndex, ...saved}]}});
  assert.throws(() => restore({memo: 'null'}), {code: 'InstalledEffectContinuationMismatch'});
  assert.throws(() => restore({}), {code: 'ForeignInstalledRowEffectRequest'});
  assert.deepEqual(cold.counts(), [0, 1]);
  const {requests: [[restored]]} = restore({memo: null});
  assert.equal(cold.owned.requestCid(restored), prepared.requestCid);
  assert.deepEqual(restored, prepared.request);
});

test('standard textual UPDATE retains exact mapped facts and reproduces its historic recovery', () => {
  const {owned, bounds, counts} = setup();
  assert.deepEqual(bounds, {body: 395, request: 908, preimage: 1030, recovery: 1024});
  const value = {note};
  const prepared = owned.prepareRequest({member, selector: id, value});
  assert.equal(prepared.request.body, originalBody);
  assert.equal(prepared.requestCid, requestCid);
  const facts = owned.requestFacts(prepared.request);
  assert.strictEqual(facts.value, value);
  assert.equal(facts.target, id);
  assert.throws(() => owned.requestCid({...prepared.request}), {code: 'ForeignInstalledRowEffectRequest'});
  assert.deepEqual(owned.recoveryEntry({member, entries: [{...prepared, ...facts}]}),
    {kind: original.kind, wire: original.wire, observationCid: original.observationCid});
  const cold = setup();
  const body = {effects: [{effect_id: member.effectId, changes: [{target_row_identity: id, after: {value}}]}]};
  const restore = (selected, current = member) => cold.owned.recoverRequests({members: [current], body,
    durable: {connectorRecovery: [selected]}});
  assert.throws(() => restore({...original, wire: wire + ' ', observationCid: cid(wire + ' ')}),
    {code: 'InstalledEffectContinuationMismatch'});
  assert.throws(() => restore(original, {...member, mapping: {...member.mapping, mappingCid: cid('foreign')}}),
    {code: 'InstalledEffectContinuationMismatch'});
  assert.deepEqual(cold.counts(), [0, 2]);
  const {requests: [[restored]]} = restore(original);
  assert.deepEqual(restored, prepared.request);
  assert.equal(cold.owned.requestCid(restored), requestCid);
  assert.deepEqual(counts(), [1, 1]);
  assert.deepEqual(cold.counts(), [1, 3]);
});

test('standard textual UPDATE quotes on the existing member and row recipe without provider arithmetic', () => {
  const {owned, bounds, counts} = setup();
  assert.throws(() => owned.prepareRequest({member, selector: id, value: {}}),
    {code: 'ForeignInstalledRowEffectRequest'});
  assert.throws(() => owned.prepareRequest({member, selector: id, value: {note: null}}),
    {code: 'ForeignInstalledRowEffectRequest'});
  assert.throws(() => owned.prepareRequest({member, selector: `${id}a`, value: {note}}),
    {code: 'ForeignInstalledRowEffectRequest'});
  assert.deepEqual(counts(), [0, 0]);
  const recipe = prepareInstalledDeclaredUpdatePlanRecipe({moon, write: owned, standardTextBounds: bounds,
    limits: {preview: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32},
      body: {maxBytes: 16384, maxNodes: 4096, maxDepth: 32}},
    resourceTextUnits: 'events'.length, connectorRegistration: 'external_effect',
    credentialSite: {construction: {scope: {}, issuer: {}, limits: {maxSecretBytes: 32}}}});
  assert.deepEqual(recipe.credentialOperations.map(({phase}) => phase),
    ['capture-target', 'apply-target', 'resume-target', 'write']);
  assert.notEqual(recipe.captureConstruction.operationIndex, recipe.recoveryConstruction.operationIndex);
  assert.deepEqual(counts(), [0, 0]);
});
