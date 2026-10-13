import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {pollSdkPreparation, prepareSdkTransport, startSdkTransport,
  pollSdkTransport, sdkTransportRawObservation, pollSdkDecode,
  takeSdkDecodedResult, cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

async function until(read, accepts) {
  for (let i = 0; i < 50; i++) {
    const value = read();
    if (accepts(value)) return value;
    await turn();
  }
  assert.fail('Original private SDK observation did not finish');
}

test('Chat raw-only keeps original bytes without an unused SDK response copy or decoder', async t => {
  // Actual pinned SDK, synthetic fixed HTTP only. No original Common/Store
  // receipt, numerical profile, public Run or Provider execution is claimed.
  const wire = '{"choices":[{"index":0,"message":{"role":"assistant",' +
    '"content":"{\\"answer\\":\\"é\\r\\n\\"}"},"finish_reason":"stop"}],' +
    '"usage":{"prompt_tokens":0,"completion_tokens":4}}';
  const bytes = new TextEncoder().encode(wire);
  const response = new Response(bytes, {headers: {'content-type': 'application/json'}});
  const handle = prepareOpenAIChatRequest({modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
    maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,notify(){},
    options:{prompt:[{role:'user',content:[{type:'text',text:'Original é\r\n'}]}],
      maxOutputTokens:16,responseFormat:{type:'json'}}});
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  const originalParse = JSON.parse;
  const OriginalResponse = globalThis.Response;
  let parses = 0, copies = 0, sends = 0;
  t.after(async () => {
    JSON.parse = originalParse;
    globalThis.Response = OriginalResponse;
    await until(() => cleanupSdkPreparation(handle), value => value === true);
  });
  // Preparation is already ready. These probes observe the unused physical
  // response work only, not the required SDK request normalization/schema work.
  JSON.parse = (...args) => { parses++; return originalParse(...args); };
  globalThis.Response = class extends OriginalResponse {
    constructor(...args) { copies++; super(...args); }
  };
  prepareSdkTransport(handle, {responseMode:'raw-only',
    responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
      maxHeaderBytes:128,observedHeaders:['content-type']},
    observeAt:()=>'2026-10-14T00:00:00.000Z',fetch(){sends++;return response;}});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.deepEqual(raw.body, bytes);
  assert.equal(raw.transportComplete, true);
  assert.equal(raw.status, 200);
  assert.equal(raw.observedAt, '2026-10-14T00:00:00.000Z');
  const consumer = await until(() => pollSdkDecode(handle), value => value.kind !== 'pending');
  assert.equal(copies, 0, 'Raw Chat must not allocate an unused SDK Response copy');
  assert.equal(parses, 0, 'Common owns Chat response decoding; SDK request normalization remains');
  assert.deepEqual(consumer, {kind:'retired'});
  assert.throws(() => takeSdkDecodedResult(handle), {code:'SdkDecodedResultUnavailable'});
  assert.equal(sends, 1);
  assert.throws(() => startSdkTransport(handle), {code:'SdkTransportStartRefused'});
});
