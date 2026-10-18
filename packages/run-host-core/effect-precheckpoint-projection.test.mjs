import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitEnvironment, prepareEffect, compileEffect, prepareEffectRequest,
  issueAllowedEffectRun, issueEffectRunDefinition, inspectEffectTaskProgress,
  projectEffectSiteRun, issueEffectSourceDispatch} from './index.mjs';
import {createJournal, admitDispatchJson, prepareIntent, admissionDurableJson} from '@actql/coordinator-core';

const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
const document = read('completion-free-update-source.program.json');
const environmentWire = read('completion-free-update-source.environment.json');
const fixed = c => 'sha256:' + c.repeat(64);
const authority = fixed('c'), observedAt = '2026-10-09T00:01:00.000Z';
function original(program = document) {
  const environment = admitEnvironment(environmentWire, JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
  const prepared = prepareEffect(program, 'json', environment);
  const compilation = compileEffect(prepared, {normalizationProfile: 'completion-free'});
  const allowed = issueAllowedEffectRun(prepared, compilation, {
    executionContextCid: fixed('a'), hostPolicyCid: fixed('b'), expiresAt: '2026-10-10T00:00:00.000Z'});
  const definition = issueEffectRunDefinition(allowed, 'scope', 'original-effect',
    '2026-10-09T00:00:00.000Z', '2026-10-10T00:00:00.000Z');
  const request = prepareEffectRequest(prepared, compilation, authority, 'original-effect-projection');
  const claims = inspectEffectTaskProgress(allowed, definition, authority, []).tasks.map(task => ({
    taskKey: task.taskKey, dispatchCid: null, dispatchReserved: false, physicalStartClaimed: false}));
  const project = (wires = [], cancelled = false, saved = claims) =>
    projectEffectSiteRun(allowed, definition, authority, wires, observedAt, cancelled, saved);
  return {allowed, definition, request, claims, project};
}

test('original pre-checkpoint candidate is unpublished and cancellation request does not issue a whole Run fence', () => {
  const f = original();
  for (const cancelled of [false, true]) {
    const projected = f.project([], cancelled), state = JSON.parse(projected.stateWire);
    assert.equal(state.status, 'preparing'); assert.equal(state.run_id, 'original-effect');
    assert.equal(state.revision, undefined); assert.equal(state.result_available, false);
    assert.equal(projected.publicationReady, false);
    assert.equal(Object.hasOwn(projected, 'cleanupComplete'), false);
    assert.equal(projected.taskCleanupComplete, false);
  }
});

test('missing original physical-start observation remains reconciliation without a retry or completion', () => {
  const f = original();
  const claims = f.claims.map((claim, index) => index ? claim : {...claim,
    dispatchCid: fixed('d'), dispatchReserved: true, physicalStartClaimed: true});
  const projected = f.project([], true, claims), state = JSON.parse(projected.stateWire);
  assert.equal(state.status, 'needs_reconciliation');
  assert.equal(state.next_action.kind, 'reconcile_run');
  assert.equal(projected.nextTask, undefined); assert.equal(projected.publicationReady, false);
});

test('complete saved claims refuse foreign duplicate missing or inconsistent originals', () => {
  const f = original();
  for (const claims of [[], [f.claims[0], f.claims[0]],
    f.claims.map((row, i) => i ? row : {...row, taskKey: 'foreign'}),
    f.claims.map((row, i) => i ? row : {...row, physicalStartClaimed: true}),
    f.claims.map((row, i) => i ? row : {...row, dispatchCid: ''})]) {
    assert.throws(() => f.project([], false, claims));
  }
  assert.throws(() => projectEffectSiteRun({...f.allowed}, f.definition,
    authority, [], observedAt, false, f.claims), /ForeignRunHostHandle/u);
  const foreign = original(document.replace('"local-update-source"', '"foreign-update-source"'));
  assert.throws(() => projectEffectSiteRun(f.allowed, foreign.definition,
    authority, [], observedAt, false, f.claims));
});

test('native Array facts are captured once without caller-owned iteration or validation methods', () => {
  const f = original();
  const wires = []; wires.some = () => {throw new Error('CallerSome');};
  wires[Symbol.iterator] = () => {throw new Error('CallerIterator');};
  const claims = f.claims.slice(); let reads = 0;
  Object.defineProperty(claims, 0, {get() {reads++; return reads === 1 ? f.claims[0] : {...f.claims[0], taskKey: 'foreign'};}});
  claims.slice = () => [{taskKey: 'foreign'}]; claims.some = () => false;
  assert.equal(JSON.parse(f.project(wires, false, claims).stateWire).status, 'preparing');
  assert.equal(reads, 1);
  const malformed = [1]; malformed.some = () => false;
  assert.throws(() => f.project(malformed));
  for (const value of ['[]', new Set(), {length: 0}]) assert.throws(() => f.project(value));
});

test('actual original Coordinator intent is bound to its same saved dispatch claim before projection', () => {
  const f = original();
  const issued = issueEffectSourceDispatch(f.allowed, f.definition, f.request, {
    taskAttempt: 1, dispatchId: 'original-effect-source', siteKey: 'site', siteGeneration: 1,
    runtimeBundleCid: fixed('d'), connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', obligationsCid: fixed('2'), budgetCid: fixed('3'),
    evidenceIssuerCapabilityCid: fixed('4'), grantCid: fixed('5')});
  const journal = createJournal(authority), request = admitDispatchJson(issued.wire, issued.cid);
  const durable = admissionDurableJson(prepareIntent(journal, request));
  const claims = f.claims.map((row, i) => i ? row : {...row, dispatchCid: issued.cid, dispatchReserved: true});
  const projection = f.project([durable], false, claims);
  assert.equal(projection.tasks[0].dispatchCid, issued.cid);
  assert.equal(projection.publicationReady, false);
  assert.throws(() => f.project([durable], false, f.claims));
  assert.throws(() => f.project([durable], false, claims.map((row, i) => i ? row : {...row, dispatchCid: fixed('e')})));
});
