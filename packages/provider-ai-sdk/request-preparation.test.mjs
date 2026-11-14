import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {interceptSdkRequest, pollSdkPreparation, sdkPreparedRequest,
  deliverSdkResponse, pollSdkDecode, takeSdkDecodedResult,
  cancelSdkPreparation, cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

const schema = {type: 'object', properties: {assessment: {type: 'string'}},
  required: ['assessment'], additionalProperties: false};
const text = 'Original e\u0301\r\n =literal';
const expectedBody = {model: 'gpt-4.1-nano', max_tokens: 16,
  response_format: {type: 'json_schema', json_schema: {schema, strict: true,
    name: 'assessment'}}, store: false,
  messages: [{role: 'user', content: text}]};
const responseWire = JSON.stringify({id: 'fixture-chat-1', object: 'chat.completion',
  created: 0, model: 'fixture-reported-model', choices: [{index: 0,
    message: {role: 'assistant', content: '{"assessment":"ok"}', refusal: null},
    finish_reason: 'stop'}], usage: {prompt_tokens: 3, completion_tokens: 4,
      total_tokens: 7}});
function preparation(overrides = {}) {
  return prepareOpenAIChatRequest({modelId: 'gpt-4.1-nano',
    baseURL: 'https://fixture.invalid/v1', apiKey: 'fixture-secret-never-log',
    options: {prompt: [{role: 'user', content: [{type: 'text', text}]}],
      maxOutputTokens: 16, responseFormat: {type: 'json', schema,
        name: 'assessment'}, providerOptions: {openai: {store: false,
          strictJsonSchema: true}}},
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16,
    notify() {}, ...overrides});
}
async function eventually(read, desired) {
  for (let i = 0; i < 30; i++) {
    const value = read();
    if (value.kind === desired) return value;
    await turn();
  }
  assert.fail(`Expected ${desired}, observed ${JSON.stringify(read())}`);
}
async function release(handle) {
  for (let i = 0; i < 30; i++) {
    if (cleanupSdkPreparation(handle)) return;
    await turn();
  }
  assert.fail('SDK physical preparation did not retire');
}

test('real pinned SDK captures one exact original request with no ambient network', async t => {
  const ambient = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = () => { requests++; throw new Error('Unexpected network'); };
  t.after(() => { globalThis.fetch = ambient; });
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  const request = sdkPreparedRequest(handle);
  assert.deepEqual(JSON.parse(request.body), expectedBody);
  assert.equal(request.url, 'https://fixture.invalid/v1/chat/completions');
  assert.equal(request.method, 'POST');
  assert.equal(request.requestBytes, Buffer.byteLength(request.body));
  assert.equal(request.body.includes('e\u0301'), true);
  assert.equal(JSON.stringify(request).includes('fixture-secret-never-log'), false);
  assert.deepEqual(pollSdkDecode(handle), {kind: 'pending'});
  assert.equal(requests, 0);
});

test('the same suspended real SDK invocation decodes one supplied response without restart', async t => {
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  deliverSdkResponse(handle, new Response(responseWire, {headers: {
    'content-type': 'application/json'}}));
  assert.throws(() => deliverSdkResponse(handle, new Response(responseWire)),
    {code: 'SdkResponseDeliveryRefused'});
  await eventually(() => pollSdkDecode(handle), 'ready');
  const value = takeSdkDecodedResult(handle);
  assert.deepEqual(value.content, [{type: 'text', text: '{"assessment":"ok"}'}]);
  assert.equal(value.response.modelId, 'fixture-reported-model');
  assert.deepEqual(value.response.body, JSON.parse(responseWire));
  assert.throws(() => takeSdkDecodedResult(handle),
    {code: 'SdkDecodedResultUnavailable'});
});

test('abort before preparation starts invokes no SDK and releases the same handle', () => {
  let starts = 0;
  const controller = new AbortController();
  controller.abort();
  const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
    maxRequestBytes: 10, maxHeaderBytes: 10, maxHeaders: 2,
    signal: controller.signal, notify() {}, runSdk() { starts++; }});
  assert.equal(starts, 0);
  assert.deepEqual(pollSdkPreparation(handle), {kind: 'rejected',
    issue: 'SdkPreparationCancelled'});
  assert.equal(cleanupSdkPreparation(handle), true);
  assert.equal(cleanupSdkPreparation(handle), true);
});

test('real SDK cancellation after interception retains cleanup until its Promise settles', async () => {
  const handle = preparation();
  await eventually(() => pollSdkPreparation(handle), 'ready');
  cancelSdkPreparation(handle);
  assert.equal(cleanupSdkPreparation(handle), false);
  assert.throws(() => deliverSdkResponse(handle, new Response(responseWire)),
    {code: 'SdkResponseDeliveryRefused'});
  await release(handle);
  assert.equal(cleanupSdkPreparation(handle), true);
  assert.throws(() => pollSdkPreparation(handle), {code: 'ForeignSdkPreparation'});
});

test('copied and foreign preparation handles cannot observe, feed or retire a real SDK call', async t => {
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  for (const foreign of [{}, {...handle}, Object.freeze({})]) {
    assert.throws(() => pollSdkPreparation(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => sdkPreparedRequest(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => cleanupSdkPreparation(foreign), {code: 'ForeignSdkPreparation'});
    assert.throws(() => deliverSdkResponse(foreign, new Response(responseWire)),
      {code: 'ForeignSdkPreparation'});
  }
});

test('UTF-8 request exact-fit succeeds and one short rejects before any response', async () => {
  const bytes = Buffer.byteLength(JSON.stringify(expectedBody));
  const exact = preparation({maxRequestBytes: bytes});
  await eventually(() => pollSdkPreparation(exact), 'ready');
  assert.equal(sdkPreparedRequest(exact).requestBytes, bytes);
  await release(exact);
  const short = preparation({maxRequestBytes: bytes - 1});
  const rejected = await eventually(() => pollSdkPreparation(short), 'rejected');
  assert.equal(rejected.issue, 'SdkRequestBindingRefused');
  await release(short);
});

test('additional or foreign-endpoint SDK fetch is a permanent preparation violation', async () => {
  for (const endpoint of ['https://fixture.invalid/v1', 'https://other.invalid/v1']) {
    let starts = 0;
    const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
      maxRequestBytes: 10, maxHeaderBytes: 10, maxHeaders: 2, notify() {},
      async runSdk(fetch) {
        starts++;
        if (endpoint.includes('other')) {
          await fetch(endpoint, {method: 'POST', body: '{}'});
        } else {
          const first = fetch(endpoint, {method: 'POST', body: '{}'});
          first.catch(() => {});
          await fetch(endpoint, {method: 'POST', body: '{}'});
        }
      }});
    const rejected = await eventually(() => pollSdkPreparation(handle), 'rejected');
    assert.equal(rejected.issue, endpoint.includes('other')
      ? 'SdkRequestBindingRefused' : 'SdkAdditionalRequestRefused');
    assert.equal(starts, 1);
    await release(handle);
  }
});

test('an SDK that returns before its guarded response cannot issue a ready decoded value', async () => {
  const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
    maxRequestBytes: 10, maxHeaderBytes: 10, maxHeaders: 2, notify() {},
    runSdk: () => ({invented: true})});
  await eventually(() => pollSdkPreparation(handle), 'rejected');
  assert.throws(() => takeSdkDecodedResult(handle),
    {code: 'SdkDecodedResultUnavailable'});
  await release(handle);
});

test('a builder throw after intercept retires its suspended request without another start', async () => {
  let starts = 0;
  const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
    maxRequestBytes: 10, maxHeaderBytes: 10, maxHeaders: 2, notify() {},
    runSdk(fetch) {
      starts++;
      void fetch('https://fixture.invalid/v1', {method: 'POST', body: '{}'});
      throw new Error('secret exception is not a diagnostic');
    }});
  assert.deepEqual(pollSdkPreparation(handle), {kind: 'rejected',
    issue: 'SdkPreparationRejected'});
  assert.equal(starts, 1);
  await release(handle);
});

test('exact header bytes/count succeed; one short rejects independently of body bound', async () => {
  for (const [maxHeaderBytes, maxHeaders, expected] of [
    [3, 1, 'ready'], [2, 1, 'rejected']]) {
    const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
      maxRequestBytes: 2, maxHeaderBytes, maxHeaders, notify() {},
      runSdk: fetch => fetch('https://fixture.invalid/v1', {method: 'POST',
        body: '{}', headers: {'a': 'bc'}})});
    await eventually(() => pollSdkPreparation(handle), expected);
    if (expected === 'rejected') assert.equal(pollSdkPreparation(handle).issue,
      'SdkRequestHeadersRefused');
    await release(handle);
  }
});

test('real SDK response rejection is sanitized and never causes another model request', async t => {
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  const original = sdkPreparedRequest(handle);
  deliverSdkResponse(handle, new Response(JSON.stringify({error: {
    message: 'secret sentinel must not be a diagnostic', type: 'rate_limit',
    code: 'rate_limit'}}), {status: 429}));
  const rejected = await eventually(() => pollSdkDecode(handle), 'rejected');
  assert.deepEqual(rejected, {kind: 'rejected', issue: 'SdkPreparationRejected'});
  assert.deepEqual(sdkPreparedRequest(handle), undefined);
  assert.equal(original.body, JSON.stringify(expectedBody));
  assert.throws(() => takeSdkDecodedResult(handle),
    {code: 'SdkDecodedResultUnavailable'});
});

test('the exact installed lock closure uses v4 and only the Host registration entry', () => {
  const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url)));
  const lock = JSON.parse(readFileSync(new URL('./package-lock.json', import.meta.url)));
  assert.deepEqual(pkg.exports, {'.': {types: './index.d.ts', default: './index.mjs'}});
  assert.equal(pkg.private, true);
  assert.equal(lock.packages['node_modules/@ai-sdk/openai'].version, '4.0.91');
  assert.equal(lock.packages['node_modules/@ai-sdk/provider'].version, '4.0.26');
  assert.equal(lock.packages['node_modules/@ai-sdk/provider-utils'].version, '5.0.58');
  for (const [name, value] of Object.entries(lock.packages)) {
    if (name === '') continue;
    assert.match(value.integrity, /^sha512-/u);
    assert.match(value.resolved, /^https:\/\/registry\.npmjs\.org\//u);
  }
});
