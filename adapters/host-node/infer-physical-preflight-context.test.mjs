import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import {createInferIoNotification} from './infer-io-notification.mjs';
import {prepareOpenAIChatRequest} from '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';
import {pollSdkPreparation, sdkPreparedRequest, cancelSdkPreparation,
  cleanupSdkPreparation} from '../../packages/provider-ai-sdk/_internal/intercepted-request.mjs';
const {openNodeInferOperation} = await import(process.env.ACTQL_PREFLIGHT_CONTEXT_MODULE ??
  './infer-operation.mjs');

// Actual Node driver and pinned SDK preparation, with explicit Core ports.
// These ports cannot prove Common admission, funding, Store ACK or public I/O.
function fixture({preflight, notification = createInferIoNotification(), signal,
  bindingIssue, omitNotification = false, poll = () => false, cleanup = () => true} = {}) {
  const active = {}, request = {}, output = Object.freeze([{answer: 7}]);
  let bound, invoked = false, requested = false, stopped = false;
  let advances = 0, starts = 0, cleanups = 0, progress = 0;
  const moon = {
    clientProgramStartScopedInferExecution() { starts++; return {$tag: 1, _0: active}; },
    clientProgramBindInferQuantityCapacity: () => ({$tag: 1, _0: undefined}),
    clientProgramBindInferPhysicalPreflight(owner, value) {
      assert.equal(owner, active); bound = value;
      return bindingIssue === undefined ? {$tag: 1, _0: undefined} : {$tag: 0, _0: bindingIssue};
    },
    clientProgramAdvanceInferExecution(owner) {
      assert.equal(owner, active); advances++;
      if (!requested && !invoked) { invoked = true; bound(request); }
      const ready = poll();
      if (requested && ready) stopped = true;
      return {$tag: 1, _0: stopped ? 'stopped' : ready ? 'complete' : 'await_io'};
    },
    clientProgramInferExecutionPollKind: value => value,
    clientProgramInferExecutionOutput: () => output,
    clientProgramCancelInferExecution() { requested = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution() { cleanups++; return {$tag: 1, _0: cleanup()}; },
  };
  const open = () => openNodeInferOperation({moon, preparedProgram: {}, step: 0,
    graph: {}, registry: '', values: '', fragment: '', ordered: '', provider: {}, signal,
    physicalPreflight: preflight, ioNotification: omitNotification ? undefined : notification,
    quantityCapacity: {limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}},
    observeProgress() { progress++; }});
  return {open, notification, request, output, bound: () => bound,
    counts: () => ({advances, starts, cleanups, progress})};
}

test('preflight receives the same original notification only when Core calls it', async () => {
  let calls = 0;
  const f = fixture({preflight(request, context) {
    calls++; assert.equal(request, f.request); assert.equal(context, f.notification);
    assert.equal(Object.isFrozen(context), true);
    assert.deepEqual(Object.keys(context), ['notify']);
    return 'original-plan';
  }, poll: () => true});
  const operation = f.open();
  assert.equal(calls, 0, 'binding is not physical preparation or send');
  assert.equal(operation.ioNotification, f.notification);
  assert.equal(f.bound()(f.request), 'original-plan', 'original callback result is not changed');
  assert.equal(await operation.run(), f.output);
  assert.equal(calls, 2, 'the explicit second Core call uses the same original context');
  await operation.close();
  assert.equal(f.notification.notify(), false);
});

test('pinned SDK request preparation wakes the same drive without a physical fetch', async () => {
  const sdkPackage = JSON.parse(readFileSync(new URL(
    '../../packages/provider-ai-sdk/node_modules/@ai-sdk/openai/package.json', import.meta.url)));
  assert.equal(sdkPackage.version, '4.0.91');
  let preparation, ready = false, preflights = 0;
  const f = fixture({preflight(request, context) {
    assert.equal(request, f.request); assert.equal(preparation, undefined); preflights++;
    assert.equal(context, f.notification);
    preparation = prepareOpenAIChatRequest({modelId: 'gpt-4.1-nano',
      baseURL: 'https://fixture.invalid/v1', apiKey: 'fixture-only',
      maxRequestBytes: 1000, maxHeaderBytes: 4096, maxHeaders: 16,
      notify: context.notify,
      options: {prompt: [{role: 'user', content: [{type: 'text', text: 'e\u0301\r\noriginal'}]}],
        maxOutputTokens: 32, responseFormat: {type: 'json'}}});
  }, poll() {
    ready ||= pollSdkPreparation(preparation).kind === 'ready';
    return ready;
  }});
  const operation = f.open();
  try {
    const running = operation.run();
    assert.equal(operation.run(), running);
    assert.equal(await running, f.output);
    const original = sdkPreparedRequest(preparation);
    assert.equal(original.url, 'https://fixture.invalid/v1/chat/completions');
    assert.equal(JSON.parse(original.body).messages[0].content, 'e\u0301\r\noriginal');
    assert.equal(preflights, 1);
    assert.equal(f.counts().progress, 0, 'no progress callback substitutes for the I/O wake');
  } finally {
    if (preparation !== undefined) {
      cancelSdkPreparation(preparation);
      let retired = false;
      for (let index = 0; index < 16 && !retired; index++) {
        await turn(); retired = cleanupSdkPreparation(preparation);
      }
      assert.equal(retired, true, 'the original SDK Promise actually settles before retirement');
    }
    ready = true;
    await operation.close();
  }
  assert.equal(f.notification.notify(), false);
});

test('a completion inside preflight is not lost before the original await', async () => {
  let ready = false;
  const f = fixture({preflight(_request, context) {
    queueMicrotask(() => { ready = true; context.notify(); });
  }, poll: () => ready});
  const operation = f.open();
  assert.equal(await operation.run(), f.output);
  assert.equal(f.counts().advances, 2);
  await operation.close();
});

test('one registered preflight cannot wake another original operation', async () => {
  const contexts = new Map(), complete = new Set();
  const preflight = (request, context) => contexts.set(request, context);
  const a = fixture({preflight, poll: () => complete.has(a.request)});
  const b = fixture({preflight, poll: () => complete.has(b.request)});
  const ao = a.open(), bo = b.open();
  const ar = ao.run(), br = bo.run();
  await turn();
  assert.notEqual(contexts.get(a.request), contexts.get(b.request));
  assert.equal(contexts.get(a.request), a.notification);
  assert.equal(contexts.get(b.request), b.notification);
  complete.add(a.request); contexts.get(a.request).notify();
  assert.equal(await ar, a.output);
  await turn();
  assert.equal(b.counts().advances, 1, 'no cross-operation wake or shared pending queue');
  complete.add(b.request); contexts.get(b.request).notify();
  assert.equal(await br, b.output);
  await ao.close(); await bo.close();
});

test('preflight wake cannot confirm physical stop or cleanup after cancellation', async () => {
  const controller = new AbortController();
  let context, ready = false, reclaim = false;
  const f = fixture({signal: controller.signal, preflight(_request, value) { context = value; },
    poll: () => ready, cleanup: () => reclaim});
  const operation = f.open(), running = operation.run();
  const reason = new Error('OriginalCancelled');
  const failure = assert.rejects(running, error => error === reason);
  await turn();
  controller.abort(reason);
  await turn(); await turn();
  assert.equal(operation.cleanup(), false);
  assert.equal(f.counts().cleanups, 0);
  assert.equal(context.notify(), true);
  await turn();
  assert.equal(operation.cleanup(), false, 'a wake is not an ACK or physical completion');
  ready = true; context.notify(); await failure;
  assert.equal(operation.cleanup(), false);
  assert.equal(context.notify(), true, 'cleanup pending retains the original wake endpoint');
  reclaim = true;
  assert.equal(operation.cleanup(), true);
  assert.equal(operation.cleanup(), true);
  assert.equal(context.notify(), false);
  assert.equal(f.counts().starts, 1);
  assert.equal(f.counts().cleanups, 2);
});

test('synchronous preflight retains the exact unary binding without an I/O profile', async () => {
  let calls = 0;
  const preflight = function(request) {
    assert.equal(arguments.length, 1); assert.equal(request, f.request); calls++;
  };
  const f = fixture({preflight, omitNotification: true, poll: () => true});
  const operation = f.open();
  assert.equal(f.bound(), preflight);
  assert.equal(await operation.run(), f.output);
  assert.equal(calls, 1);
  assert.equal(operation.ioNotification, undefined);
  await operation.close();
});

test('binding refusal never invokes preflight and retains the original cleanup owner', () => {
  const issue = {kind: 'PhysicalBindingRefused'};
  const f = fixture({bindingIssue: issue, preflight() { assert.fail('no preparation on binding refusal'); }});
  let failure;
  try { f.open(); } catch (error) { failure = error; }
  assert.equal(failure.cause, issue);
  assert.notEqual(failure.cleanupOwner, undefined);
  assert.equal(f.notification.notify(), true, 'failed constructor retains its still-owned notification');
  assert.equal(f.counts().starts, 1);
  assert.equal(failure.cleanupOwner.cleanupPending(), true);
});
