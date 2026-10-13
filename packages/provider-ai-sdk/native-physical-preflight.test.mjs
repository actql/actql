import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {createProjectedTypeSafeDecisionPreflight} from './_internal/typesafe-decision.mjs';

const wire = '{"answers":{"q0000000000":{"type":"noul","noul":0.25}},"opaque":"é\\r\\n"}';
const expected = {model: 'jev-latest', state: 'é\r\n',
  questions: {q0000000000: {type: 'noul', instructions: ''}}};
async function until(read, accept) {
  for (let i = 0; i < 100; i++) { const value = read(); if (accept(value)) return value; await turn(); }
  assert.fail('Finite native SDK preflight did not settle');
}

// Actual pinned SDK preparation/transport with synthetic fetch. Common's
// view/profile/Plan/Entry/save are explicit doubles, not installed execution,
// native raw validation, complete funding or nominal response evidence.
function fixture(change = {}) {
  const projected = {}, provider = {}, request = {}, probability = {}, profile = {}, installation = {}, entry = {};
  let retired = false, plans = 0, starts = 0, saves = 0, wakes = 0, cleanupAllowed = false, raw;
  const response = Object.freeze({originalSavedView: true});
  const moon = {
    clientProgramNativeDecisionRequestMatches: (view, p, r) => !retired && view === projected && p === provider && r === request,
    clientProgramNativeDecisionRequestBinding: () => ({_0: 'task', _1: 'prompt', _2: 'schema', _3: 'native'}),
    clientProgramNativeDecisionRequestWires: () => ({_0: '"é\\r\\n"',
      _1: '{"q0000000000":{"type":"boolean","instructions":""}}'}),
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncNativeDecisionRequestPlan(r, view, p, bytes, tokens, cost, duration, selected, installed, prob, start) {
      assert.equal(r, request); assert.equal(view, projected); assert.equal(p, provider);
      assert.equal(prob, probability); assert.equal(selected, profile); assert.equal(installed, installation);
      assert.equal(bytes, BigInt(Buffer.byteLength(JSON.stringify(expected))));
      assert.deepEqual([tokens, cost, duration], [128n, 0n, 1000n]);
      plans++; return {$tag: 1, _0: {start}};
    },
    clientProgramModelPhysicalCallForRequest(actual, r, poll, cancel, cleanup) {
      assert.equal(actual, entry); assert.equal(r, request); return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: () => assert.fail('Native raw must not use generation decoder'),
    clientProgramModelPhysicalSavedNativeDecision(view, original, admitted, prob) {
      assert.equal(view, response); assert.equal(original, projected);
      assert.equal(admitted, provider); assert.equal(prob, probability);
      return {$tag: 1, _0: {kind: 'saved', view}};
    },
  };
  const config = {moon, projected, admittedProvider: provider, request, probability,
    taskCid: 'task', promptCid: 'prompt', outputSchemaCid: 'schema', modelSelector: 'native',
    modelId: 'jev-latest', baseURL: 'https://fixture.invalid/v1', apiKey: 'fixture-only',
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16, profile, installation,
    quantities: {tokens: 128n, costUnits: 0n, durationMs: 1000n},
    responseLimits: {maxBytes: 512, maxChunkBytes: 512, maxChunks: 4, maxHeaderBytes: 64, observedHeaders: ['content-type']},
    notify() { wakes++; }, observeAt: () => '2026-10-13T00:00:00.000Z',
    checked(value) { if (value?.$tag === 1) return value._0; throw Error('OriginalNativePlanRefused'); },
    fetch(url, init) {
      starts++; assert.equal(url, 'https://fixture.invalid/v1/systemone');
      assert.deepEqual(JSON.parse(init.body), expected);
      for (const key of ['temperature', 'top_p', 'max_tokens', 'seed', 'tools']) {
        assert.equal(Object.hasOwn(JSON.parse(init.body), key), false);
      }
      return new Response(wire, {headers: {'content-type': 'application/json'}});
    },
    persistRaw(call, original) { saves++; raw = original; return Promise.resolve({response}); },
    cleanupRaw: () => cleanupAllowed,
    ...change,
  };
  return {config, projected, provider, request, entry, response, moon,
    counters: () => ({plans, starts, saves, wakes}), raw: () => raw,
    retire: () => { retired = true; },
    release: async port => { cleanupAllowed = true; await until(() => port.preflight.cleanup(), Boolean); }};
}

test('native SDK preflight uses dedicated original plan without generation defaults or invented observations', async t => {
  const f = fixture(); const port = createProjectedTypeSafeDecisionPreflight(f.config);
  t.after(() => f.release(port));
  assert.equal(f.counters().wakes, 0, 'lazy construction starts no SDK invocation');
  const plan = (await until(() => port.preflight.advance(), value => value._0 === true))._1;
  assert.notEqual(plan, undefined); assert.equal(f.counters().starts, 0);
  const call = plan.start(f.entry);
  assert.equal(plan.start(f.entry), undefined);
  const observed = await until(() => call.poll(), value => value.kind === 'saved');
  assert.equal(observed.view, f.response);
  assert.deepEqual(Buffer.from(f.raw().body), Buffer.from(wire));
  assert.equal(f.raw().transportComplete, true);
  assert.equal(Object.hasOwn(f.raw(), 'input_tokens'), false);
  assert.equal(Object.hasOwn(f.raw(), 'provider_request_id'), false);
  assert.equal(call.cleanup(), false, 'same raw custody has not acknowledged cleanup');
  await f.release(port);
  assert.equal(f.moon.clientProgramNativeDecisionRequestMatches(f.projected, f.provider, f.request), true,
    'SDK preparation cannot retire the caller-owned projection view');
  assert.deepEqual({...f.counters(), wakes: 0}, {plans: 1, starts: 1, saves: 1, wakes: 0});
});

test('native SDK preflight rejects missing runtime and foreign originals before SDK allocation', () => {
  for (const mutate of [f => { delete f.moon.clientProgramModelAsyncNativeDecisionRequestPlan; },
    f => { delete f.moon.clientProgramModelPhysicalSavedNativeDecision; },
    f => { f.config.projected = {}; }, f => { f.config.admittedProvider = {}; },
    f => { f.config.request = {}; }, f => { f.config.probability = undefined; }, f => { f.retire(); }]) {
    const f = fixture(); mutate(f);
    assert.throws(() => createProjectedTypeSafeDecisionPreflight(f.config), /Unavailable/);
    assert.deepEqual(f.counters(), {plans: 0, starts: 0, saves: 0, wakes: 0});
  }
});

test('native late saved-binding refusal keeps original Unknown raw custody without another transport', async t => {
  const f = fixture(); let checks = 0;
  f.moon.clientProgramModelPhysicalSavedNativeDecision = () => {
    checks++; return {$tag: 0, _0: 'ForeignOriginalNativeResponse'};
  };
  const port = createProjectedTypeSafeDecisionPreflight(f.config);
  t.after(() => f.release(port));
  const plan = (await until(() => port.preflight.advance(), value => value._0))._1;
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  assert.equal(call.poll().kind, 'unknown');
  assert.equal(checks, 1);
  assert.equal(plan.start(f.entry), undefined);
  assert.deepEqual(Buffer.from(f.raw().body), Buffer.from(wire));
  assert.equal(call.cleanup(), false);
  assert.deepEqual({...f.counters(), wakes: 0}, {plans: 1, starts: 1, saves: 1, wakes: 0});
});

test('native SDK preflight checks original membership again before lazy preparation', async t => {
  const f = fixture(); const port = createProjectedTypeSafeDecisionPreflight(f.config);
  t.after(() => f.release(port)); f.retire();
  assert.deepEqual(port.preflight.advance(), {_0: true, _1: undefined});
  assert.deepEqual(f.counters(), {plans: 0, starts: 0, saves: 0, wakes: 0});
});

test('native Common plan refusal retains SDK cleanup and sends zero without generation fallback', async t => {
  const f = fixture(); f.moon.clientProgramModelAsyncNativeDecisionRequestPlan = () => ({$tag: 0, _0: 'ProfileMismatch'});
  const port = createProjectedTypeSafeDecisionPreflight(f.config);
  t.after(() => f.release(port));
  assert.deepEqual(await until(() => port.preflight.advance(), value => value._0), {_0: true, _1: undefined});
  assert.equal(f.counters().starts, 0); assert.equal(f.counters().saves, 0);
});

test('native cancellation after preparation retains original entered Unknown and cannot resend', async t => {
  const controller = new AbortController(); const f = fixture({signal: controller.signal});
  const port = createProjectedTypeSafeDecisionPreflight(f.config);
  t.after(() => f.release(port));
  const plan = (await until(() => port.preflight.advance(), value => value._0))._1;
  controller.abort(); const call = plan.start(f.entry);
  assert.equal(call.poll().kind, 'unknown');
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.counters().starts, 0); assert.equal(f.counters().saves, 0);
});
