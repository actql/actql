import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOriginalOpenAIChatRequest} from './_internal/original-openai-chat.mjs';
import {pollSdkPreparation, sdkPreparedRequest, cleanupSdkPreparation}
  from './_internal/intercepted-request.mjs';

// Selected first-service request preparation only. The Common generation
// accessor is a double; this neither admits a Profile nor authorizes a Run.
// A fake credential stays in the interceptor. No transport is installed.
const request = Object.freeze({});
const schema = {type: 'object', properties: {
  reason: {anyOf: [{type: 'string'}, {type: 'null'}]},
  risk: {type: 'string'},
}, required: ['reason', 'risk'], additionalProperties: false};
const expected = model => ({model, temperature: 0, top_p: 1,
  max_tokens: 32, seed: -7,
  messages: [{role: 'system', content: 'Original e\u0301\r\n'},
    {role: 'user', content: '{"text":"hello"}'}],
  response_format: {type: 'json_schema', json_schema: {
    schema, strict: true, name: 'actql_output',
  }}});

function prepare(modelId, reads) {
  return prepareOriginalOpenAIChatRequest({moon: {
    clientProgramModelRequestGeneration(actual) {
      assert.strictEqual(actual, request);
      reads.count++;
      return {_0: 'selected-chat', _1: 0, _2: 1, _3: 32n, _4: -7n};
    },
  }, request, modelSelector: 'selected-chat', modelId,
  baseURL: 'https://api.openai.com/v1', apiKey: 'fixture-only-never-sent',
  maxRequestBytes: 1000, maxHeaderBytes: 4096, maxHeaders: 16,
  prompt: [{role: 'system', content: 'Original e\u0301\r\n'},
    {role: 'user', content: [{type: 'text', text: '{"text":"hello"}'}]}],
  responseFormat: {type: 'json', name: 'actql_output', schema},
  notify() {}, verifyRequest: body =>
    // Independent expected envelope, not a value regenerated from SDK output.
    assert.deepStrictEqual(JSON.parse(body), expected(modelId)) === undefined,
  });
}

async function until(read, accept) {
  for (let index = 0; index < 100; index++) {
    const value = read();
    if (accept(value)) return value;
    await turn();
  }
  assert.fail('Bounded selected SDK preparation did not settle');
}

test('selected service snapshot preserves the original structured generation before any transport',
  {timeout: 5000}, async () => {
    const reads = {count: 0};
    const handle = prepare('gpt-4.1-mini-2025-04-14', reads);
    try {
      await until(() => pollSdkPreparation(handle), value => value.kind !== 'pending');
      assert.deepEqual(pollSdkPreparation(handle), {kind: 'ready'});
      const wire = sdkPreparedRequest(handle);
      assert.equal(wire.url, 'https://api.openai.com/v1/chat/completions');
      assert.equal(wire.method, 'POST');
      assert.deepEqual(JSON.parse(wire.body), expected('gpt-4.1-mini-2025-04-14'));
      assert.equal(wire.requestBytes, Buffer.byteLength(wire.body));
      assert.ok(wire.requestBytes <= 1000);
      assert.ok(wire.headerBytes <= 4096);
      assert.equal(reads.count, 1);
    } finally {
      await until(() => cleanupSdkPreparation(handle), value => value === true);
    }
  });

test('model-dependent SDK generation rewrite is refused without fallback or a new request',
  {timeout: 5000}, async () => {
    const reads = {count: 0};
    const handle = prepare('gpt-6-luna', reads);
    try {
      const value = await until(() => pollSdkPreparation(handle), observed =>
        observed.kind !== 'pending');
      assert.deepEqual(value, {kind: 'rejected', issue: 'SdkOriginalRequestMismatch'});
      assert.equal(sdkPreparedRequest(handle), undefined);
      assert.equal(reads.count, 1);
    } finally {
      await until(() => cleanupSdkPreparation(handle), value => value === true);
    }
  });
