import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {interceptSdkRequest, pollSdkPreparation, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportResponse, pollSdkDecode,
  takeSdkDecodedResult, cancelSdkPreparation, cleanupSdkPreparation}
  from './_internal/intercepted-request.mjs';
import {deliverSdkResponse} from './_internal/intercepted-request.mjs';

const responseWire = '{"id":"physical-chat-1","object":"chat.completion",' +
  '"created":0,"model":"actual-reported-model","choices":[{"index":0,' +
  '"message":{"role":"assistant","content":"{\\"assessment\\":\\"é\\\\r\\\\n\\"}",' +
  '"refusal":null},"finish_reason":"stop"}],' +
  '"usage":{"prompt_tokens":3,"completion_tokens":4,"total_tokens":7}}';
const bytes = new TextEncoder().encode(responseWire);
const bounds = {maxBytes: bytes.byteLength, maxChunkBytes: bytes.byteLength,
  maxChunks: 4, maxHeaderBytes: 128,
  observedHeaders: ['content-type', 'x-request-id']};
const schema = {type: 'object', properties: {assessment: {type: 'string'}},
  required: ['assessment'], additionalProperties: false};
const expectedBody = {model: 'gpt-4.1-nano', max_tokens: 16,
  response_format: {type: 'json_schema', json_schema: {schema, strict: true,
    name: 'assessment'}}, store: false,
  messages: [{role: 'user', content: 'Original e\u0301\r\n'}]};

function realPreparation(notify = () => {}) {
  return prepareOpenAIChatRequest({modelId: 'gpt-4.1-nano',
    baseURL: 'https://fixture.invalid/v1', apiKey: 'private-key-sentinel',
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16, notify,
    options: {prompt: [{role: 'user', content: [{type: 'text',
      text: 'Original e\u0301\r\n'}]}], maxOutputTokens: 16,
      responseFormat: {type: 'json', schema, name: 'assessment'},
      providerOptions: {openai: {store: false, strictJsonSchema: true}}}});
}
async function until(read, kind) {
  for (let i = 0; i < 40; i++) {
    const current = read();
    if (current.kind === kind) return current;
    await turn();
  }
  assert.fail(`Missing finite physical ${kind} observation`);
}
async function release(handle) {
  for (let i = 0; i < 40; i++) {
    if (cleanupSdkPreparation(handle)) return;
    await turn();
  }
  assert.fail('Same original SDK/reader cleanup did not finish');
}
function rawResponse(wire = bytes, status = 200) {
  return new Response(wire, {status, headers: {'content-type': 'application/json',
    'x-request-id': 'actual-header-id', 'private-extra': 'response-secret'}});
}

test('fixed real SDK transport starts once and delivers bounded original bytes to the same invocation', async t => {
  const ambient = globalThis.fetch;
  let ambientCalls = 0;
  globalThis.fetch = () => { ambientCalls++; throw new Error('Ambient network'); };
  t.after(() => { globalThis.fetch = ambient; });
  let calls = 0;
  let wakes = 0;
  const handle = realPreparation(() => { wakes++; });
  t.after(() => release(handle));
  await until(() => pollSdkPreparation(handle), 'ready');
  const mutableLimits = {...bounds, observedHeaders: [...bounds.observedHeaders]};
  prepareSdkTransport(handle, {responseLimits: mutableLimits, fetch(url, init) {
    calls++;
    assert.equal(url, 'https://fixture.invalid/v1/chat/completions');
    assert.equal(init.method, 'POST');
    assert.equal(init.redirect, 'error');
    assert.ok(init.signal instanceof AbortSignal);
    assert.deepEqual(JSON.parse(init.body), expectedBody);
    assert.equal(new Headers(init.headers).get('authorization'), 'Bearer private-key-sentinel');
    assert.ok(Object.isFrozen(init) && Object.isFrozen(init.headers));
    return rawResponse();
  }});
  mutableLimits.maxBytes = 1;
  mutableLimits.observedHeaders.push('private-extra');
  assert.deepEqual(pollSdkTransport(handle), {kind: 'not-started'});
  assert.equal(calls, 0);
  startSdkTransport(handle);
  assert.equal(calls, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await until(() => pollSdkTransport(handle), 'response');
  const original = sdkTransportResponse(handle);
  assert.deepEqual(original.body, bytes);
  assert.equal(original.body.buffer.byteLength, bounds.maxBytes);
  assert.deepEqual(original.headers, [['content-type', 'application/json'],
    ['x-request-id', 'actual-header-id']]);
  assert.equal(original.transportComplete, true);
  await until(() => pollSdkDecode(handle), 'ready');
  const decoded = takeSdkDecodedResult(handle);
  assert.deepEqual(decoded.content, [{type: 'text', text: '{"assessment":"é\\r\\n"}'}]);
  assert.equal(decoded.response.modelId, 'actual-reported-model');
  assert.equal(calls, 1);
  assert.equal(ambientCalls, 0);
  assert.ok(wakes > 0);
  assert.equal(JSON.stringify(pollSdkTransport(handle)).includes('private-key-sentinel'), false);
  assert.equal(Object.hasOwn(pollSdkTransport(handle), 'complete'), false);
});

test('physical preparation and cancellation never authorize a start or build a second request', async () => {
  let calls = 0;
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  assert.throws(() => prepareSdkTransport(handle, {fetch() {},
    responseLimits: {...bounds, maxBytes: 0}}), {code: 'InvalidInferResponseReader'});
  prepareSdkTransport(handle, {fetch() { calls++; }, responseLimits: bounds});
  assert.throws(() => prepareSdkTransport(handle, {fetch() {}, responseLimits: bounds}),
    {code: 'SdkTransportPreparationRefused'});
  cancelSdkPreparation(handle);
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  assert.deepEqual(pollSdkTransport(handle), {kind: 'not-started'});
  assert.equal(calls, 0);
  await release(handle);
  assert.throws(() => pollSdkTransport(handle), {code: 'ForeignSdkPreparation'});
});

test('a final invoke throw or lost response stays unknown and cannot restart', async () => {
  for (const asynchronous of [false, true]) {
    let calls = 0;
    const handle = realPreparation();
    await until(() => pollSdkPreparation(handle), 'ready');
    prepareSdkTransport(handle, {responseLimits: bounds, fetch() {
      calls++;
      const secret = new Error('credential/provider-exception-sentinel');
      if (asynchronous) return Promise.reject(secret);
      throw secret;
    }});
    startSdkTransport(handle);
    const observed = await until(() => pollSdkTransport(handle), 'unknown');
    assert.deepEqual(observed, {kind: 'unknown', issue: 'SdkTransportUnknown'});
    assert.equal(sdkTransportResponse(handle), undefined);
    assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
    await until(() => pollSdkDecode(handle), 'rejected');
    await release(handle);
    assert.equal(calls, 1);
  }
});

test('raw byte overflow refuses before SDK parsing and retains original prefix until reader retry', async () => {
  let attempts = 0;
  let reads = 0;
  let sdkParses = 0;
  let calls = 0;
  let wakes = 0;
  const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
    maxRequestBytes: 16, maxHeaderBytes: 16, maxHeaders: 2, notify() { wakes++; },
    async runSdk(fetch) {
      const response = await fetch('https://fixture.invalid/v1', {method: 'POST', body: '{}'});
      sdkParses++;
      return response.json();
    }});
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: {maxBytes: 4, maxChunkBytes: 4,
    maxChunks: 4, maxHeaderBytes: 16}, fetch() {
    calls++;
    return {status: 200, headers: new Headers(), body: {getReader() {
      return {async read() { reads++; return {done: false,
        value: new TextEncoder().encode(reads === 1 ? 'abcd' : 'e')}; },
        cancel() { if (++attempts === 1) throw new Error('secret'); },
        releaseLock() {}};
    }}};
  }});
  startSdkTransport(handle);
  const observed = await until(() => pollSdkTransport(handle), 'response');
  assert.equal(observed.issue, 'InferResponseByteLimit');
  const original = sdkTransportResponse(handle);
  assert.equal(new TextDecoder().decode(original.body), 'abcd');
  assert.equal(original.transportComplete, false);
  assert.equal(await original.readerRetirement, false);
  await until(() => pollSdkDecode(handle), 'rejected');
  assert.equal(cleanupSdkPreparation(handle), false);
  const priorWakes = wakes;
  await release(handle);
  assert.ok(wakes > priorWakes);
  assert.equal(calls, 1);
  assert.equal(reads, 2);
  assert.equal(attempts, 2);
  assert.equal(sdkParses, 0);
});

test('pending response cancellation preserves unknown responsibility and waits for actual transport settlement', async () => {
  let calls = 0;
  let rejectPhysical;
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: bounds, fetch(_, init) {
    calls++;
    return new Promise((_, reject) => {
      rejectPhysical = reject;
      init.signal.addEventListener('abort', () => {}, {once: true});
    });
  }});
  startSdkTransport(handle);
  cancelSdkPreparation(handle);
  assert.equal(cleanupSdkPreparation(handle), false);
  assert.deepEqual(pollSdkTransport(handle), {kind: 'pending'});
  assert.equal(calls, 1);
  rejectPhysical(new Error('response loss after cancellation'));
  await until(() => pollSdkTransport(handle), 'unknown');
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await release(handle);
  assert.equal(calls, 1);
});

test('actual HTTP refusal is retained without inferring a retry or SDK success', async () => {
  let calls = 0;
  const errorBody = '{"error":{"message":"unavailable","type":"server_error","code":null}}';
  const errorBytes = new TextEncoder().encode(errorBody);
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: bounds, fetch() {
    calls++;
    return rawResponse(errorBytes, 503);
  }});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), 'response');
  assert.equal(sdkTransportResponse(handle).status, 503);
  assert.deepEqual(sdkTransportResponse(handle).body, errorBytes);
  await until(() => pollSdkDecode(handle), 'rejected');
  assert.throws(() => takeSdkDecodedResult(handle), {code: 'SdkDecodedResultUnavailable'});
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await release(handle);
  assert.equal(calls, 1);
});

test('foreign SDK handles cannot start, observe or retire a fixed transport', async () => {
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: bounds, fetch() { return rawResponse(); }});
  for (const foreign of [{}, {...handle}, Object.freeze({})]) {
    assert.throws(() => startSdkTransport(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => pollSdkTransport(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => sdkTransportResponse(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => cleanupSdkPreparation(foreign), {code: 'ForeignSdkPreparation'});
  }
  await release(handle);
});

test('a prepared transport cannot take a manual legacy response or an already supplied SDK response', async () => {
  let calls = 0;
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: bounds, fetch() { calls++; return rawResponse(); }});
  assert.throws(() => deliverSdkResponse(handle, rawResponse()), {code: 'SdkResponseDeliveryRefused'});
  assert.equal(calls, 0);
  startSdkTransport(handle);
  assert.throws(() => deliverSdkResponse(handle, rawResponse()), {code: 'SdkResponseDeliveryRefused'});
  await until(() => pollSdkDecode(handle), 'ready');
  await release(handle);
  assert.equal(calls, 1);
  const supplied = realPreparation();
  await until(() => pollSdkPreparation(supplied), 'ready');
  deliverSdkResponse(supplied, rawResponse());
  assert.throws(() => prepareSdkTransport(supplied, {responseLimits: bounds, fetch() { calls++; }}),
    {code: 'SdkTransportPreparationRefused'});
  await release(supplied);
  assert.equal(calls, 1);
});

test('header refusal retains the unread original until its own cleanup retry succeeds', async () => {
  let reads = 0;
  let retirements = 0;
  let calls = 0;
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: {...bounds, maxHeaderBytes: 1}, fetch() {
    calls++;
    return {status: 200, headers: new Headers({'content-type': 'application/json'}),
      body: {getReader() { reads++; throw new Error('Must not read oversized headers'); },
        cancel() { if (++retirements === 1) throw new Error('cleanup secret'); }}};
  }});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), 'unknown');
  await until(() => pollSdkDecode(handle), 'rejected');
  assert.equal(cleanupSdkPreparation(handle), false);
  await turn();
  assert.equal(retirements, 1);
  assert.deepEqual(pollSdkTransport(handle), {kind: 'unknown', issue: 'SdkTransportUnknown'});
  assert.equal(cleanupSdkPreparation(handle), false);
  await turn();
  assert.equal(retirements, 2);
  assert.equal(cleanupSdkPreparation(handle), true);
  assert.equal(cleanupSdkPreparation(handle), true);
  assert.equal(reads, 0);
  assert.equal(calls, 1);
});
