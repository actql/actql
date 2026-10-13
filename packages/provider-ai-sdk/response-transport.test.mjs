import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {interceptSdkRequest, pollSdkPreparation, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportResponse, pollSdkDecode,
  takeSdkDecodedResult, cancelSdkPreparation, cleanupSdkPreparation,
  sdkTransportRawObservation}
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

test('actual SDK transport exposes cancelled raw prefix while original read and cancel retain cleanup custody', async t => {
  const handle = realPreparation();
  let finishRead;
  let finishCancel;
  let reads = 0;
  let cancellations = 0;
  let releases = 0;
  let sends = 0;
  t.after(async () => {
    finishRead?.({done: true});
    finishCancel?.();
    await release(handle);
  });
  await until(() => pollSdkPreparation(handle), 'ready');
  prepareSdkTransport(handle, {responseLimits: bounds, fetch() {
    sends++;
    return {status: 200, headers: new Headers({'content-type': 'application/json'}),
      body: {getReader() { return {
        read() {
          reads++;
          if (reads === 1) return Promise.resolve({done: false,
            value: new Uint8Array([123])});
          return new Promise(resolve => { finishRead = resolve; });
        },
        cancel() { cancellations++; return new Promise(resolve => { finishCancel = resolve; }); },
        releaseLock() { releases++; },
      }; }}};
  }});
  startSdkTransport(handle);
  for (let i = 0; i < 40 && finishRead === undefined; i++) await turn();
  assert.equal(reads, 2);
  cancelSdkPreparation(handle);
  assert.equal((await until(() => pollSdkTransport(handle), 'response')).issue,
    'InferResponseReadCancelled');
  const raw = sdkTransportRawObservation(handle);
  assert.deepEqual(raw.body, new Uint8Array([123]));
  assert.equal(raw.observedBytes, 1);
  assert.equal(raw.transportComplete, false);
  assert.equal((await until(() => pollSdkDecode(handle), 'rejected')).kind, 'rejected');
  assert.equal(cleanupSdkPreparation(handle), false);
  finishCancel();
  for (let i = 0; i < 4; i++) await turn();
  assert.equal(cleanupSdkPreparation(handle), false);
  assert.equal(releases, 0);
  finishRead({done: false, value: new Uint8Array([125])});
  await release(handle);
  assert.equal(releases, 1);
  assert.equal(cancellations, 1);
  assert.equal(reads, 2);
  assert.equal(sends, 1);
  assert.deepEqual(raw.body, new Uint8Array([123]));
  assert.equal(raw.transportComplete, false);
  assert.throws(() => startSdkTransport(handle), {code: 'ForeignSdkPreparation'});
  // Physical SDK/reader and synthetic HTTP response, not a Common Entry,
  // remote stop, saved nominal response, normal numeric profile or public Run.
});

test('real SDK defaults do not replace the separately retained original partial usage', async t => {
  const wire='{"choices":[{"index":0,"message":{"content":"{}"},"finish_reason":"stop"}],"usage":{"completion_tokens":0}}';
  const originalBytes=new TextEncoder().encode(wire);
  const handle=realPreparation();
  t.after(()=>release(handle));
  let calls=0;
  await until(()=>pollSdkPreparation(handle),'ready');
  prepareSdkTransport(handle,{responseLimits:{...bounds,maxBytes:originalBytes.length,
    maxChunkBytes:originalBytes.length},fetch(){calls++;return rawResponse(originalBytes);}});
  startSdkTransport(handle);
  await until(()=>pollSdkTransport(handle),'response');
  await until(()=>pollSdkDecode(handle),'ready');
  const original=sdkTransportRawObservation(handle);
  const decoded=takeSdkDecodedResult(handle);
  // These SDK zeros are generated defaults, not provider observations. The
  // Common raw codec must independently retain absent prompt/total as unknown.
  assert.equal(decoded.usage.inputTokens.total,0);
  assert.equal(decoded.usage.outputTokens.reasoning,0);
  assert.deepEqual(decoded.response.body.usage,{completion_tokens:0});
  assert.equal(Object.hasOwn(decoded.response.body.usage,'prompt_tokens'),false);
  assert.equal(Object.hasOwn(decoded.response.body.usage,'total_tokens'),false);
  assert.deepEqual(original.body,originalBytes);
  assert.equal(Object.hasOwn(JSON.parse(new TextDecoder().decode(original.body)).usage,
    'prompt_tokens'),false);
  assert.equal(calls,1);
});

test('real SDK returned raw and validated trees overlap the original request and survive handle retirement', async t => {
  const wire='{"model":"reported","extra":{"text":"é\\r\\n"},"choices":[{"index":0,"message":{"content":"{}","extra":"opaque"},"finish_reason":"stop"}],"usage":{"completion_tokens":0,"opaque":17}}';
  const originalBytes=new TextEncoder().encode(wire);
  const handle=realPreparation();
  t.after(()=>release(handle));
  let calls=0;
  await until(()=>pollSdkPreparation(handle),'ready');
  prepareSdkTransport(handle,{responseLimits:{...bounds,maxBytes:originalBytes.length,
    maxChunkBytes:originalBytes.length},fetch(){calls++;return rawResponse(originalBytes);}});
  startSdkTransport(handle);
  await until(()=>pollSdkTransport(handle),'response');
  await until(()=>pollSdkDecode(handle),'ready');
  const original=sdkTransportRawObservation(handle);
  const decoded=takeSdkDecodedResult(handle);
  // The raw parse and schema-validated projection are distinct objects. SDK
  // normalization/stripping is not the Common metadata or capture contract.
  assert.notEqual(decoded.usage.raw,decoded.response.body.usage);
  assert.deepEqual(decoded.usage.raw,{completion_tokens:0});
  assert.deepEqual(decoded.response.body.usage,{completion_tokens:0,opaque:17});
  assert.deepEqual(decoded.response.body.extra,{text:'é\r\n'});
  assert.equal(decoded.response.body.choices[0].message.extra,'opaque');
  const sdkBody=decoded.request.body;
  // Internal SDK args keep undefined fields that JSON.stringify omits from
  // the physical wire. Those owned reference slots are not costless absence.
  assert.deepEqual(Object.keys(sdkBody).sort(),[
    'model','logit_bias','logprobs','top_logprobs','user','parallel_tool_calls',
    'max_tokens','temperature','top_p','frequency_penalty','presence_penalty',
    'response_format','stop','seed','verbosity','max_completion_tokens','store',
    'metadata','prediction','reasoning_effort','service_tier','prompt_cache_key',
    'prompt_cache_options','prompt_cache_retention','safety_identifier','messages',
    'tools','tool_choice',
  ].sort());
  assert.equal(sdkBody.model,'gpt-4.1-nano');
  assert.equal(sdkBody.max_tokens,16);
  assert.equal(sdkBody.store,false);
  assert.deepEqual(sdkBody.messages,expectedBody.messages);
  assert.deepEqual(sdkBody.response_format.json_schema.schema,schema);
  assert.equal(Object.hasOwn(sdkBody.response_format.json_schema,'description'),true);
  assert.equal(sdkBody.response_format.json_schema.description,undefined);
  assert.equal(sdkBody.logit_bias,undefined);
  assert.deepEqual(JSON.parse(JSON.stringify(sdkBody)),expectedBody);
  await release(handle);
  // Retirement of the SDK handle does not retire transferred caller aliases.
  // Their lifetime still belongs in the original receiving Owner's inventory.
  assert.equal(decoded.request.body,sdkBody);
  assert.deepEqual(JSON.parse(JSON.stringify(sdkBody)),expectedBody);
  assert.deepEqual(original.body,originalBytes);
  assert.deepEqual(decoded.response.body.extra,{text:'é\r\n'});
  assert.equal(calls,1);
  assert.throws(()=>startSdkTransport(handle),{code:'ForeignSdkPreparation'});
});

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

test('Host response time is observed before delayed body read and retained without provider timestamp substitution', async () => {
  const handle = realPreparation();
  await until(() => pollSdkPreparation(handle), 'ready');
  let now = '2026-10-12T00:00:00.000Z';
  let observations = 0;
  let deliver;
  const received = new Promise(resolve => { deliver = resolve; });
  prepareSdkTransport(handle, {responseLimits: bounds,
    observeAt() { observations++; return now; },
    fetch: () => received});
  startSdkTransport(handle);
  assert.equal(observations, 0);
  const body = new ReadableStream({async start(controller) {
    await turn();
    now = '2026-10-12T00:00:01.000Z';
    controller.enqueue(bytes);
    controller.close();
  }});
  deliver(new Response(body, {headers: {'content-type': 'application/json'}}));
  await until(() => pollSdkTransport(handle), 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.equal(observations, 1);
  assert.equal(raw.observedAt, '2026-10-12T00:00:00.000Z');
  assert.equal(sdkTransportRawObservation(handle), raw);
  assert.equal(Object.hasOwn(raw, 'providerTimestamp'), false);
  await release(handle);
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
