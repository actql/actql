import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import type {RegisteredRequestOptions} from './_internal/model-port.mjs';
import type {LanguageModelV4, LanguageModelV4CallOptions} from '@ai-sdk/provider';
import type {JSONSchema7} from 'json-schema';
import {isDeepStrictEqual} from 'node:util';
import {createOpenAI} from '@ai-sdk/openai';
import {createAnthropic} from '@ai-sdk/anthropic';
import {createGoogle} from '@ai-sdk/google';
import * as chat from './_internal/openai-chat.mjs';
import * as anthropic from './_internal/anthropic-messages.mjs';
import * as google from './_internal/google-generate-content.mjs';
import * as responses from './_internal/openai-responses.mjs';
import {interceptSdkRequest, prepareRegisteredSdkLanguageModel, pollSdkPreparation, sdkPreparedRequest,
  prepareSdkTransport, startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  confirmSavedSdkTransportResponse, pollSdkDecode, takeSavedSdkDecodedResult,
  cancelSdkPreparation, cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

type RegisteredOptions = LanguageModelV4CallOptions & RegisteredRequestOptions;
type DecodedSdk = Awaited<ReturnType<LanguageModelV4['doGenerate']>>;
const schema: JSONSchema7 = {type: 'object', properties: {assessment: {type: 'string'}},
  required: ['assessment'], additionalProperties: false};
const text = 'Original e\u0301\r\n =literal';
const expectedBody = {model: 'gpt-4.1-nano', max_tokens: 16, temperature: 0, top_p: 1,
  response_format: {type: 'json_schema', json_schema: {schema, strict: true,
    name: 'assessment'}}, store: false,
  messages: [{role: 'system', content: 'Return the assessment.'}, {role: 'user', content: text}]};
const responseWire = JSON.stringify({id: 'fixture-chat-1', object: 'chat.completion',
  created: 0, model: 'fixture-reported-model', choices: [{index: 0,
    message: {role: 'assistant', content: '{"assessment":"ok"}', refusal: null},
    finish_reason: 'stop'}], usage: {prompt_tokens: 3, completion_tokens: 4,
      total_tokens: 7}});
function preparation({maxRequestBytes = 4096} = {}) {
  const selector = 'fixture-assessment', admission = Object.freeze({});
  const modelId = 'gpt-4.1-nano';
  const route = {modelId, apiMode: 'chat_completions', endpoint: chat.credentialBinding.endpoint};
  const providerOptions = {openai: {store: false, strictJsonSchema: true}};
  const options: RegisteredOptions = {
    prompt: [{role: 'system', content: 'Return the assessment.'},
      {role: 'user', content: [{type: 'text', text}]}],
    maxOutputTokens: 16, temperature: 0, topP: 1,
    responseFormat: {type: 'json', schema, name: 'assessment'}, providerOptions,
  };
  return prepareRegisteredSdkLanguageModel({
    moon: {clientProgramAdmittedStructuredSdkRouteMatches: (...actual: unknown[]) =>
      isDeepStrictEqual(actual, [admission, selector, modelId, route.apiMode, route.endpoint])},
    admission, selector, ...route, sdkProvider: chat.sdkProvider, options,
    createLanguageModel: fetch => chat.createLanguageModel(createOpenAI, modelId, fetch, route),
    verifyRequest: body => chat.verifyRequest(body, options, route, providerOptions),
    maxRequestBytes, maxHeaderBytes: 4096, maxHeaders: 16, notify() {},
  });
}
async function eventually<T extends {kind: string}, K extends T['kind']>(read: () => T, desired: K): Promise<Extract<T, {kind: K}>> {
  for (let i = 0; i < 30; i++) {
    const value = read();
    if (value.kind === desired) return value as Extract<T, {kind: K}>;
    await turn();
  }
  assert.fail(`Expected ${desired}, observed ${JSON.stringify(read())}`);
}
async function release(handle: unknown) {
  for (let i = 0; i < 30; i++) {
    if (cleanupSdkPreparation(handle)) return;
    await turn();
  }
  assert.fail('SDK physical preparation did not retire');
}

// A physical response double supplies one bounded response. The fixture
// confirms its exact bytes without claiming a Core or durable Store grant.
async function confirmResponse(handle: unknown, wire: string, status = 200) {
  const bytes = new TextEncoder().encode(wire);
  let sends = 0;
  prepareSdkTransport(handle, {responseMode: 'saved-sdk',
    responseLimits: {maxBytes: 8192, maxChunkBytes: 8192, maxChunks: 2, maxHeaderBytes: 1024},
    async fetch() {
      assert.equal(++sends, 1);
      return new Response(bytes, {status, headers: {'content-type': 'application/json'}});
    }});
  startSdkTransport(handle);
  await eventually(() => pollSdkTransport(handle), 'response');
  const raw = sdkTransportRawObservation(handle);
  assert(raw?.transportComplete);
  assert.equal(raw.status, status);
  assert.deepEqual(raw.body, bytes);
  assert.deepEqual(pollSdkDecode(handle), {kind: 'pending'});
  assert.equal(sends, 1);
  const receipt = Object.freeze({});
  confirmSavedSdkTransportResponse(handle, raw, {receipt, bytes});
  return {raw, receipt, bytes};
}

test('registered Anthropic preserves the selected Messages body and refuses non-neutral topP', async () => {
  const modelId = 'claude-sonnet-4-6', selector = 'fixture-alias', apiMode = 'messages';
  const endpoint = 'https://api.anthropic.com/v1/messages';
  const route = {modelId, selector, apiMode, endpoint}, admission = {};
  const moon = {clientProgramAdmittedStructuredSdkRouteMatches: (...actual: unknown[]) =>
    isDeepStrictEqual(actual, [admission, selector, modelId, apiMode, endpoint])};
  const prompt: RegisteredOptions['prompt'] = [{role: 'system', content: 'Return a typed assessment.'},
    {role: 'user', content: [{type: 'text', text}]}];
  const providerOptions = {anthropic: {structuredOutputMode: 'outputFormat'}};
  const expected = {model: modelId, max_tokens: 16, temperature: 0,
    system: [{type: 'text', text: 'Return a typed assessment.'}], messages: [prompt[1]],
    output_config: {format: {type: 'json_schema', schema}}};
  for (const topP of [1, 0.5]) {
    const options: RegisteredOptions = {prompt, responseFormat: {type: 'json', schema, name: 'assessment'},
      providerOptions, temperature: 0, topP, maxOutputTokens: 16};
    const handle = prepareRegisteredSdkLanguageModel({moon, admission, ...route,
      sdkProvider: anthropic.sdkProvider,
      createLanguageModel: fetch => anthropic.createLanguageModel(createAnthropic, modelId, fetch, route),
      options, verifyRequest: body => anthropic.verifyRequest(body, options, route, providerOptions),
      maxRequestBytes: 8192, maxHeaderBytes: 8192, maxHeaders: 16, notify() {}});
    try {
      if (topP !== 1) {
        assert.equal((await eventually(() => pollSdkPreparation(handle), 'rejected')).issue, 'SdkOriginalRequestMismatch');
        assert.equal(sdkPreparedRequest(handle), undefined);
        continue;
      }
      await eventually(() => pollSdkPreparation(handle), 'ready');
      assert.deepEqual(JSON.parse(sdkPreparedRequest(handle)!.body), expected);
      const reply = {id: 'anthropic-fixture', type: 'message', role: 'assistant', model: modelId,
        stop_reason: 'end_turn', content: [{type: 'text', text: '{"assessment":"ok"}'}],
        usage: {input_tokens: 0, output_tokens: 4}};
      const {receipt, bytes} = await confirmResponse(handle, JSON.stringify(reply));
      await eventually(() => pollSdkDecode(handle), 'ready');
      const decoded = takeSavedSdkDecodedResult(handle, receipt, bytes) as DecodedSdk;
      assert.equal((decoded.content[0] as {text: string}).text, '{"assessment":"ok"}');
      assert.deepEqual(anthropic.readReportedUsage(reply), {inputTokens: 0n, outputTokens: 4n});
      assert.equal(anthropic.readReportedUsage({}), undefined);
    } finally {await release(handle);}
  }
});

test('registered Google preserves the selected GenerateContent body and reported usage', async () => {
  const modelId = 'gemini-2.5-flash', selector = 'fixture-gemini', apiMode = 'generate_content';
  const endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  const route = {modelId, selector, apiMode, endpoint}, admission = {};
  const moon = {clientProgramAdmittedStructuredSdkRouteMatches: (...actual: unknown[]) =>
    isDeepStrictEqual(actual, [admission, selector, modelId, apiMode, endpoint])};
  const prompt: RegisteredOptions['prompt'] = [{role: 'system', content: 'Return a typed assessment.'},
    {role: 'user', content: [{type: 'text', text}]}];
  const providerOptions = {google: {structuredOutputs: true}};
  const options: RegisteredOptions = {prompt, responseFormat: {type: 'json', schema, name: 'assessment'},
    providerOptions, temperature: 0, topP: 1, maxOutputTokens: 16};
  const handle = prepareRegisteredSdkLanguageModel({moon, admission, ...route,
    sdkProvider: google.sdkProvider, createLanguageModel: fetch => google.createLanguageModel(createGoogle, modelId, fetch, route),
    options, verifyRequest: body => google.verifyRequest(body, options, route, providerOptions),
    maxRequestBytes: 8192, maxHeaderBytes: 8192, maxHeaders: 16, notify() {}});
  try {
    await eventually(() => pollSdkPreparation(handle), 'ready');
    const request = sdkPreparedRequest(handle)!;
    assert.equal(request.url, endpoint);
    assert.deepEqual(JSON.parse(request.body), {
      generationConfig: {maxOutputTokens: 16, temperature: 0, topP: 1,
        responseMimeType: 'application/json', responseJsonSchema: schema},
      contents: [{role: 'user', parts: [{text}]}],
      systemInstruction: {parts: [{text: 'Return a typed assessment.'}]},
    });
    assert.equal(google.verifyRequest(request.body, {...options, seed: 1}, route, providerOptions), false);
    assert.equal(google.verifyRequest(request.body, options, route, {google: {structuredOutputs: false}}), false);
    const reply = {modelVersion: modelId, candidates: [{index: 0, finishReason: 'STOP',
      content: {role: 'model', parts: [{text: '{"assessment":"ok"}'}]}}],
    usageMetadata: {promptTokenCount: 0, candidatesTokenCount: 4, thoughtsTokenCount: 2}};
    const {receipt, bytes} = await confirmResponse(handle, JSON.stringify(reply));
    await eventually(() => pollSdkDecode(handle), 'ready');
    const decoded = takeSavedSdkDecodedResult(handle, receipt, bytes) as DecodedSdk;
    assert.equal((decoded.content[0] as {text: string}).text, '{"assessment":"ok"}');
    assert.deepEqual(google.readReportedUsage(reply), {inputTokens: 0n, outputTokens: 6n});
    assert.deepEqual(google.readReportedUsage({usageMetadata: {thoughtsTokenCount: 2}}),
      {inputTokens: undefined, outputTokens: undefined});
  } finally {await release(handle);}
});

test('real pinned SDK captures one exact original request with no ambient network', async t => {
  const ambient = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = () => { requests++; throw new Error('Unexpected network'); };
  t.after(() => { globalThis.fetch = ambient; });
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  const request = sdkPreparedRequest(handle)!;
  assert.deepEqual(JSON.parse(request.body), expectedBody);
  assert.equal(request.url, 'https://api.openai.com/v1/chat/completions');
  assert.equal(request.method, 'POST');
  assert.equal(request.requestBytes, Buffer.byteLength(request.body));
  assert.equal(request.body.includes('e\u0301'), true);
  assert.equal(JSON.stringify(request).includes(chat.credentialBinding.placeholder), false);
  assert.deepEqual(pollSdkDecode(handle), {kind: 'pending'});
  assert.equal(requests, 0);
});

test('the same suspended real SDK invocation decodes one confirmed response without restart', async t => {
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  const {raw, receipt, bytes} = await confirmResponse(handle, responseWire);
  assert.throws(() => confirmSavedSdkTransportResponse(handle, raw, {receipt, bytes}),
    {code: 'SdkSavedResponseBindingRefused'});
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await eventually(() => pollSdkDecode(handle), 'ready');
  const value = takeSavedSdkDecodedResult(handle, receipt, bytes) as DecodedSdk;
  assert.deepEqual(value.content, [{type: 'text', text: '{"assessment":"ok"}'}]);
  assert.equal(value.response!.modelId, 'fixture-reported-model');
  assert.deepEqual(value.response!.body, JSON.parse(responseWire));
  assert.throws(() => takeSavedSdkDecodedResult(handle, receipt, bytes),
    {code: 'SdkDecodedResultUnavailable'});
});

const responsesBase = 'https://api.openai.com/v1';
const responsesEndpoint = responsesBase + '/responses';
const responsesModel = 'gpt-4.1-mini';
const responsesAdmission = Object.freeze({});
const responsesRoute = {modelId: responsesModel, apiMode: 'responses', endpoint: responsesEndpoint};
const responsesProviderOptions = {openai: {store: false, strictJsonSchema: true}};
const responsesOptions: RegisteredOptions = {prompt: [{role: 'system', content: 'Return the assessment.'},
  {role: 'user', content: [{type: 'text', text}]}], maxOutputTokens: 16, temperature: 0,
  providerOptions: responsesProviderOptions, responseFormat: {type: 'json', schema, name: 'assessment'}};
const responsesRequest = {model: responsesModel, max_output_tokens: 16, temperature: 0, store: false,
  input: [{role: 'system', content: 'Return the assessment.'},
    {role: 'user', content: [{type: 'input_text', text}]}],
  text: {format: {type: 'json_schema', name: 'assessment', schema, strict: true}}};

function registeredResponses(overrides: Partial<Parameters<typeof prepareRegisteredSdkLanguageModel>[0]> = {}) {
  return prepareRegisteredSdkLanguageModel({admission: responsesAdmission,
    selector: 'fixture-alias', modelId: responsesModel, apiMode: 'responses',
    endpoint: responsesEndpoint, sdkProvider: 'openai.responses',
    moon: {clientProgramAdmittedStructuredSdkRouteMatches(...route) {
      return isDeepStrictEqual(route, [responsesAdmission, 'fixture-alias',
        responsesModel, 'responses', responsesEndpoint]);
    }},
    createLanguageModel: (fetch: typeof globalThis.fetch) =>
      responses.createLanguageModel(createOpenAI, responsesModel, fetch, responsesRoute),
    options: responsesOptions,
    verifyRequest: (wire: string) => responses.verifyRequest(wire, responsesOptions, responsesRoute, responsesProviderOptions),
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16, notify() {},
    ...overrides});
}

test('a selected registered V4 factory serializes and decodes Responses through the guarded port', async t => {
  const handle = registeredResponses();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  assert.equal(sdkPreparedRequest(handle)!.url, responsesEndpoint);
  assert.deepEqual(JSON.parse(sdkPreparedRequest(handle)!.body), responsesRequest);
  const raw = {id: 'fixture-response', model: responsesModel, status: 'completed', output: [{
    id: 'fixture-message', type: 'message', role: 'assistant', content: [{
      type: 'output_text', text: '{"assessment":"ok"}', annotations: [],
    }],
  }], usage: {input_tokens: 3, output_tokens: 4, total_tokens: 7}};
  const {receipt, bytes} = await confirmResponse(handle, JSON.stringify(raw));
  await eventually(() => pollSdkDecode(handle), 'ready');
  assert.deepEqual((takeSavedSdkDecodedResult(handle, receipt, bytes) as DecodedSdk).content, [
    {type: 'text', text: '{"assessment":"ok"}',
      providerMetadata: {openai: {itemId: 'fixture-message'}}},
  ]);
  assert.deepEqual(responses.readReportedUsage(raw), {inputTokens: 3n, outputTokens: 4n});
  assert.equal(responses.readReportedResponse(raw)?.outcome, 'stop');
  assert.equal(responses.readReportedResponse({...raw, status: 'in_progress'})?.outcome, 'other');
  assert.equal(responses.readReportedResponse({...raw, output: [raw.output[0], raw.output[0]]})?.outcome, 'other');
  assert.deepEqual(responses.readReportedUsage({usage: {input_tokens: 0}}), {inputTokens: 0n, outputTokens: undefined});
  assert.equal(responses.readReportedUsage({}), undefined);
  for (const [reason, outcome] of [['max_output_tokens', 'length'], ['content_filter', 'content-filter']]) {
    assert.deepEqual(responses.readReportedResponse({...raw, status: 'incomplete', incomplete_details: {reason}}),
      {model: responsesModel, requestId: raw.id, finishReason: reason, outcome});
  }
  assert.equal(responses.readReportedResponse({...raw, output: [{type: 'message', role: 'assistant',
    content: [{type: 'refusal', refusal: 'Fixture refusal'}]}]})?.outcome, 'refusal');
  assert.equal(responses.readReportedResponse({...raw, output: [{type: 'message', role: 'assistant',
    content: [{type: 'refusal', refusal: false}]}]})?.outcome, 'other');
});

test('the selected Responses adapter requires no provider storage or continuation', () => {
  assert.equal(responses.verifyRequest(JSON.stringify(responsesRequest), responsesOptions, responsesRoute, {}), false);
  assert.equal(responses.verifyRequest(JSON.stringify(responsesRequest), {...responsesOptions, seed: 1},
    responsesRoute, responsesProviderOptions), false);
  for (const extra of [{store: true}, {store: undefined}, {previous_response_id: 'foreign'},
    {tools: [{type: 'web_search'}]}]) {
    assert.equal(responses.verifyRequest(JSON.stringify({...responsesRequest, ...extra}), responsesOptions,
      responsesRoute, responsesProviderOptions), false);
  }
});

test('a foreign registered route or missing request verifier refuses before the factory', () => {
  const createLanguageModel = () => assert.fail('No SDK factory for a foreign route');
  for (const changed of [{modelId: 'other-model'}, {apiMode: 'chat_completions'},
    {endpoint: 'https://fixture.invalid/other'}, {verifyRequest: undefined}]) {
    assert.throws(() => registeredResponses({...changed, createLanguageModel}),
      {code: 'RegisteredSdkRouteUnavailable'});
  }
});

test('a different V4 SDK model, SDK transport mode or rendered body cannot prepare a send', async () => {
  for (const [changed, issue] of [
    [{createLanguageModel: (fetch: typeof globalThis.fetch) => createOpenAI({baseURL: responsesBase,
      apiKey: 'fixture-only', fetch}).responses('other-model')}, 'SdkPreparationRejected'],
    [{createLanguageModel: (fetch: typeof globalThis.fetch) => createOpenAI({baseURL: responsesBase,
      apiKey: 'fixture-only', fetch}).chat(responsesModel)}, 'SdkPreparationRejected'],
    [{verifyRequest: (wire: string) => isDeepStrictEqual(JSON.parse(wire),
      {...responsesRequest, max_output_tokens: 8})}, 'SdkOriginalRequestMismatch'],
  ] as const) {
    const handle = registeredResponses(changed);
    try {
      assert.equal((await eventually(() => pollSdkPreparation(handle), 'rejected')).issue, issue);
      assert.equal(sdkPreparedRequest(handle), undefined);
    } finally {
      await release(handle);
    }
  }
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
  const saved = {receipt: Object.freeze({}), bytes: new TextEncoder().encode(responseWire)};
  assert.throws(() => confirmSavedSdkTransportResponse(handle, undefined, saved),
    {code: 'SdkSavedResponseBindingRefused'});
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
    assert.throws(() => confirmSavedSdkTransportResponse(foreign, undefined,
      {receipt: Object.freeze({}), bytes: new Uint8Array()}), {code: 'ForeignSdkPreparation'});
  }
});

test('UTF-8 request exact-fit succeeds and one short rejects before any response', async () => {
  const bytes = Buffer.byteLength(JSON.stringify(expectedBody));
  const exact = preparation({maxRequestBytes: bytes});
  await eventually(() => pollSdkPreparation(exact), 'ready');
  assert.equal(sdkPreparedRequest(exact)!.requestBytes, bytes);
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
  assert.equal(pollSdkDecode(handle).kind, 'rejected');
  assert.throws(() => takeSavedSdkDecodedResult(handle, Object.freeze({}), new Uint8Array()),
    {code: 'SdkSavedResponseBindingRefused'});
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
    [3, 1, 'ready'], [2, 1, 'rejected']] as const) {
    const handle = interceptSdkRequest({endpoint: 'https://fixture.invalid/v1',
      maxRequestBytes: 2, maxHeaderBytes, maxHeaders, notify() {},
      runSdk: fetch => fetch('https://fixture.invalid/v1', {method: 'POST',
        body: '{}', headers: {'a': 'bc'}})});
    await eventually(() => pollSdkPreparation(handle), expected);
    if (expected === 'rejected') assert.equal((pollSdkPreparation(handle) as Extract<ReturnType<typeof pollSdkPreparation>, {kind: 'rejected'}>).issue,
      'SdkRequestHeadersRefused');
    await release(handle);
  }
});

test('real SDK response rejection is sanitized and never causes another model request', async t => {
  const handle = preparation();
  t.after(() => release(handle));
  await eventually(() => pollSdkPreparation(handle), 'ready');
  const original = sdkPreparedRequest(handle)!;
  const {receipt, bytes} = await confirmResponse(handle, JSON.stringify({error: {
    message: 'secret sentinel must not be a diagnostic', type: 'rate_limit',
    code: 'rate_limit'}}), 429);
  const rejected = await eventually(() => pollSdkDecode(handle), 'rejected');
  assert.deepEqual(rejected, {kind: 'rejected', issue: 'SdkPreparationRejected'});
  assert.deepEqual(sdkPreparedRequest(handle), undefined);
  assert.equal(original.body, JSON.stringify(expectedBody));
  assert.throws(() => takeSavedSdkDecodedResult(handle, receipt, bytes),
    {code: 'SdkDecodedResultUnavailable'});
});

test('the exact installed lock closure uses v4 and only the Host registration entry', () => {
  const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url)) as unknown as string) as {exports: unknown; private: unknown};
  const lock = JSON.parse(readFileSync(new URL('./package-lock.json', import.meta.url)) as unknown as string) as {packages: Record<string, {version?: string; integrity?: string; resolved?: string}>};
  assert.deepEqual(pkg.exports, {'.': {types: './index.d.ts', default: './index.mjs'}});
  assert.equal(pkg.private, true);
  assert.equal(lock.packages['node_modules/@ai-sdk/openai'].version, '4.0.91');
  assert.equal(lock.packages['node_modules/@ai-sdk/provider'].version, '4.0.26');
  assert.equal(lock.packages['node_modules/@ai-sdk/provider-utils'].version, '5.0.58');
  for (const [name, value] of Object.entries(lock.packages)) {
    if (name === '') continue;
    assert.match(value.integrity!, /^sha512-/u);
    assert.match(value.resolved!, /^https:\/\/registry\.npmjs\.org\//u);
  }
});
