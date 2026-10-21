import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {validRunState} from '@actql/client-wire';
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
    assert.equal(state.revision, undefined); assert.equal(validRunState(state), false);
    assert.equal(state.result_available, false);
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
  const oversized = new Array(f.claims.length + 1); let oversizedReads = 0;
  Object.defineProperty(oversized, 0, {get() {oversizedReads++; throw new Error('MustNotRead');}});
  assert.throws(() => f.project([], false, oversized), {name: 'TypeError'});
  assert.equal(oversizedReads, 0);
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

for (const field of ['savedClaims', 'durableWires']) {
  test(`Array-backed Proxy ${field} length is captured once before bounded element reads`, () => {
    const f = original(), originalValues = field === 'savedClaims' ? f.claims : [];
    let lengthReads = 0, elementReads = 0;
    const values = new Proxy(originalValues, {get(target, key, receiver) {
      if (key === 'length') return ++lengthReads === 1 ? target.length : target.length + 100;
      if (typeof key === 'string' && /^(?:0|[1-9][0-9]*)$/u.test(key)) {
        const index = Number(key);
        assert(index < target.length, 'ReadBeyondCapturedLength'); elementReads++;
      }
      return Reflect.get(target, key, receiver);
    }});
    const projected = field === 'savedClaims' ? f.project([], false, values) : f.project(values);
    assert.equal(JSON.parse(projected.stateWire).status, 'preparing');
    assert.equal(lengthReads, 1); assert.equal(elementReads, originalValues.length);
    for (const length of [-1, 0.5, NaN, Infinity, '0', undefined]) {
      let indexReads = 0;
      const invalid = new Proxy([], {get(target, key, receiver) {
        if (key === 'length') return length;
        if (typeof key === 'string' && /^(?:0|[1-9][0-9]*)$/u.test(key)) indexReads++;
        return Reflect.get(target, key, receiver);
      }});
      assert.throws(() => field === 'savedClaims' ? f.project([], false, invalid) : f.project(invalid),
        {name: 'TypeError'});
      assert.equal(indexReads, 0);
    }
  });
}


// Wrap only the real compiled export in a child process; all admitted originals
// and reductions remain the actual runtime's objects and implementation.
test('Effect projection reduces durable progress at most once without an empty progress probe', () => {
  const name = 'Effect projection reduces durable progress at most once without an empty progress probe';
  const key = Symbol.for('actql.test.effect-progress-work');
  const probe = globalThis[key];
  if (probe === undefined) {
    const module = new URL('./dist/client_values_host_abi.js', import.meta.url).href;
    const preload = `import {mock} from 'node:test';
      import * as actual from ${JSON.stringify(module)};
      let calls = 0;
      globalThis[Symbol.for('actql.test.effect-progress-work')] = {reset() {calls = 0;}, count() {return calls;}};
      mock.module(${JSON.stringify(module)}, {namedExports: {...actual,
        clientValuesHostInspectEffectTaskProgress(...args) {calls++; return actual.clientValuesHostInspectEffectTaskProgress(...args);}}});`;
    const env = {...process.env};
    delete env.NODE_TEST_CONTEXT;
    const child = spawnSync(process.execPath, ['--experimental-test-module-mocks',
      '--import', 'data:text/javascript,' + encodeURIComponent(preload), '--test',
      '--test-name-pattern=^' + name + '$', fileURLToPath(import.meta.url)], {encoding: 'utf8', env});
    console.log(child.stdout.trim());
    if (child.stderr) console.error(child.stderr.trim());
    assert.equal(child.status, 0);
    assert.match(child.stdout, /effect-progress-reductions [0-9]+/u);
    return;
  }
  const f = original();
  probe.reset();
  const projected = f.project();
  assert.equal(JSON.parse(projected.stateWire).status, 'preparing');
  console.log('effect-progress-reductions ' + probe.count());
  assert(probe.count() <= 1, 'EffectProgressReductionBudgetExceeded');
});
