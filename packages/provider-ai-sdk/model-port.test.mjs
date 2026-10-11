import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';

const originalWire = '{"id":"actual-1","model":"reported-model",' +
  '"choices":[{"index":0,"message":{"role":"assistant",' +
  '"content":"{\\"answer\\":\\"é\\r\\n\\"}"},"finish_reason":"stop"}],' +
  '"usage":{"prompt_tokens":0,"completion_tokens":4}}';
const originalBytes = Buffer.from(originalWire);
const limits = {maxBytes: 4096, maxChunkBytes: 4096, maxChunks: 8,
  maxHeaderBytes: 128, observedHeaders: ['content-type']};

function fixture({persistRaw, response, rejectPlan = false, rejectCall = false,
  transportThrow = false, cleanupRaw = () => true} = {}) {
  const request = Object.freeze({original: Symbol('request owner double')});
  const prepared = Object.freeze({original: Symbol('prepared owner double')});
  const entry = Object.freeze({original: Symbol('consumed Entry double')});
  const state = {calls: 0, saves: 0, plans: 0, wakes: 0, rawCleanups: 0};
  const handle = prepareOpenAIChatRequest({modelId: 'gpt-4.1-nano',
    baseURL: 'https://fixture.invalid/v1', apiKey: 'credential-sentinel',
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16,
    notify() { state.wakes++; }, options: {
      prompt: [{role: 'user', content: [{type: 'text', text: 'Original é\r\n'}]}],
      maxOutputTokens: 16, responseFormat: {type: 'json'},
    }});
  // Real pinned SDK/request/fixed transport and raw backing, Core owners and
  // persistence/receipt doubles. Not public admission or same-Ledger funding.
  const moon = {
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(actual, bytes, tokens, cost,
      duration, profile, installation, start) {
      assert.equal(actual, request);
      assert.ok(bytes > 0n);
      assert.equal(tokens, 16n);
      assert.equal(cost, 0n);
      assert.equal(duration, 500n);
      state.plans++;
      if (rejectPlan) throw new Error('ProfileRefused');
      return {start};
    },
    clientProgramModelPhysicalCall(actual, original, poll, cancel, cleanup) {
      assert.equal(actual, entry);
      assert.equal(original, prepared);
      if (rejectCall) return undefined;
      return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: value => ({kind: 'chat', value}),
  };
  const port = createSdkModelPreflight({moon, request, preparation: handle,
    profile: {}, installation: {}, quantities: {tokens: 16n, costUnits: 0n,
      durationMs: 500n}, responseLimits: limits, checked: value => value,
    observeAt: () => '2026-10-12T00:00:00.000Z',
    cleanupRaw(call) { state.rawCleanups++; return cleanupRaw(call); },
    notify() { state.wakes++; }, fetch(url, init) {
      state.calls++;
      assert.equal(url, 'https://fixture.invalid/v1/chat/completions');
      assert.equal(init.method, 'POST');
      assert.equal(init.redirect, 'error');
      assert.equal(JSON.parse(init.body).messages[0].content, 'Original é\r\n');
      if (transportThrow) throw new Error('lost-response-secret');
      return response?.() ?? new Response(originalBytes,
        {headers: {'content-type': 'application/json'}});
    }, async persistRaw(call, raw) {
      state.saves++;
      assert.ok(call);
      return persistRaw ? persistRaw(call, raw)
        : {response: {originalRaw: raw, nominal: Symbol('receipt double')}};
    }});
  port.bindPrepared(prepared);
  return {port, entry, state};
}

async function until(read, predicate) {
  for (let i = 0; i < 50; i++) {
    const value = read();
    if (predicate(value)) return value;
    await turn();
  }
  assert.fail('Finite private physical caller did not reach its observation');
}
const planOf = f => until(() => f.port.preflight.advance(), value => value[0]);
const release = f => until(() => f.port.preflight.cleanup(), value => value);

test('real SDK preflight retains one plan and starts only its original consumed call', async () => {
  const f = fixture();
  const [, plan] = await planOf(f);
  assert.equal(f.port.preflight.advance()[1], plan);
  assert.equal(f.state.plans, 1);
  assert.equal(f.state.calls, 0);
  const call = plan.start(f.entry);
  assert.equal(f.state.calls, 1);
  assert.equal(plan.start(f.entry), undefined);
  const observed = await until(() => call.poll(), value => value.kind === 'chat');
  assert.deepEqual(observed.value.originalRaw.body, new Uint8Array(originalBytes));
  assert.equal(observed.value.originalRaw.transportComplete, true);
  assert.equal(observed.value.originalRaw.observedAt, '2026-10-12T00:00:00.000Z');
  assert.equal(f.state.saves, 1);
  assert.equal(call.poll().value, observed.value);
  await release(f);
  assert.equal(f.state.rawCleanups, 1);
  assert.equal(f.state.calls, 1);
});

test('rejected plan or foreign call cannot enter physical fetch', async () => {
  for (const options of [{rejectPlan: true}, {rejectCall: true}]) {
    const f = fixture(options);
    const [, plan] = await planOf(f);
    assert.equal(plan?.start(f.entry), undefined);
    assert.equal(f.state.calls, 0);
    assert.equal(f.state.plans, 1);
    await release(f);
  }
});

test('save await keeps cleanup pending and a saved original response is transferred once', async () => {
  let finish;
  const saved = new Promise(resolve => { finish = resolve; });
  const f = fixture({persistRaw: () => saved});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), () => f.state.saves === 1);
  assert.equal(f.port.preflight.cleanup(), false);
  const response = {nominal: Symbol('saved original response double')};
  finish({response});
  assert.equal((await until(() => call.poll(), value => value.kind === 'chat')).value,
    response);
  assert.equal(f.state.saves, 1);
  await release(f);
});

test('raw persistence failure preserves the original cleanup responsibility without resend', async () => {
  const failure = Object.assign(new Error('Store ACK unknown'), {rawCustodyRetained: true});
  const f = fixture({persistRaw: () => { throw failure; }, cleanupRaw: () => false});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.calls, 1);
  assert.equal(f.state.saves, 1);
  // The original Core/Store parent retains this pending owner; no claim of
  // cleanup completion or public Run release is made by this private fixture.
});

test('same original raw cleanup completion retires the SDK without adopting an unknown response', async () => {
  const failure = Object.assign(new Error('original raw save failed'),
    {cleanupHandle: Object.freeze({original: Symbol('holding double')})});
  let rawReleased = false;
  let seenCall;
  const f = fixture({persistRaw: call => { seenCall = call; throw failure; },
    cleanupRaw(call) {
      assert.equal(call, seenCall);
      return rawReleased;
    }});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(f.port.rawFailure(), failure);
  rawReleased = true;
  await release(f);
  assert.equal(f.port.preflight.cleanup(), true);
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.calls, 1);
  assert.equal(f.state.saves, 1);
});

test('saved raw cleanup remains pending until the original successful save port retires', async () => {
  let savedCall;
  let released = false;
  let cleanupCalls = 0;
  const f = fixture({persistRaw: call => {
    savedCall = call;
    return {response: {nominal: Symbol('saved original response double')}};
  }, cleanupRaw(call) {
    assert.equal(call, savedCall);
    cleanupCalls++;
    if (cleanupCalls === 1) throw new Error('OriginalRawCleanupUnavailable');
    return released;
  }});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'chat');
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(cleanupCalls, 2);
  released = true;
  await release(f);
  assert.equal(cleanupCalls, 3);
  assert.equal(f.port.preflight.cleanup(), true);
  assert.equal(cleanupCalls, 3);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.saves, 1);
  assert.equal(f.state.calls, 1);
});

test('lost response has no invented raw body, no saved response and no second request', async () => {
  const f = fixture({transportThrow: true});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  assert.equal(f.state.saves, 0);
  await assert.rejects(f.port.reconcileRaw(call),
    {message: 'OriginalRawReconciliationUnavailable'});
  assert.equal(plan.start(f.entry), undefined);
  await release(f);
  assert.equal(f.state.rawCleanups, 0);
  assert.equal(f.state.calls, 1);
});

test('explicit raw reconciliation reuses the original call without rewriting Unknown or retrying transport', async () => {
  const failure = new Error('Original ACK response lost');
  let originalCall;
  let originalRaw;
  let finish;
  const saved = {response: {nominal: Symbol('reconfirmed original raw double')}};
  const f = fixture({persistRaw(call, raw) {
    if (originalCall === undefined) {
      originalCall = call;
      originalRaw = raw;
      throw failure;
    }
    assert.equal(call, originalCall);
    assert.equal(raw, originalRaw);
    return new Promise(resolve => { finish = resolve; });
  }});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  await assert.rejects(f.port.reconcileRaw({}),
    {message: 'OriginalRawReconciliationUnavailable'});
  const first = f.port.reconcileRaw(call);
  assert.equal(f.port.reconcileRaw(call), first);
  await until(() => finish, value => typeof value === 'function');
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(call.poll().kind, 'unknown');
  finish(saved);
  assert.equal(await first, saved);
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(call.poll().kind, 'unknown');
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.calls, 1);
  assert.equal(f.state.saves, 2);
  await release(f);
  await assert.rejects(f.port.reconcileRaw(call),
    {message: 'OriginalRawReconciliationUnavailable'});
});

test('failed explicit raw reconciliation retains Unknown and cleanup responsibility without automatic retry', async () => {
  const first = new Error('Original save unknown');
  const next = new Error('Same original receipt unavailable');
  const f = fixture({persistRaw() { throw f.state.saves === 1 ? first : next; },
    cleanupRaw: () => false});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'unknown');
  await assert.rejects(f.port.reconcileRaw(call), error => error === next);
  for (let i = 0; i < 5; i++) assert.equal(call.poll().kind, 'unknown');
  assert.equal(f.port.rawFailure(), first);
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(f.state.saves, 2);
  assert.equal(f.state.calls, 1);
});

test('incomplete transport preserves exact observed prefix for raw persistence, not success', async () => {
  const prefix = Uint8Array.of(0x7b, 0xc3);
  let reads = 0;
  const f = fixture({response: () => ({status: 503, headers: new Headers(), body: {
    getReader() { return {async read() {
      if (reads++ === 0) return {done: false, value: prefix};
      throw new Error('physical lost body');
    }, async cancel() {}, releaseLock() {}}; },
  }})});
  const [, plan] = await planOf(f);
  const call = plan.start(f.entry);
  const observed = await until(() => call.poll(), value => value.kind === 'chat');
  assert.deepEqual(observed.value.originalRaw.body, prefix);
  assert.equal(observed.value.originalRaw.status, 503);
  assert.equal(observed.value.originalRaw.transportComplete, false);
  assert.equal(f.state.saves, 1);
  await release(f);
  assert.equal(f.state.calls, 1);
});
