import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareAdmittedOpenAIChatRequest} from './_internal/original-openai-chat.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';
import {pollSdkPreparation, pollSdkDecode, sdkPreparedRequest,
  prepareSdkTransport, startSdkTransport, takeSdkDecodedResult,
  cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

// Fixed independent schema and value-wire. Common admission, call and saved
// receipt are boundary doubles; the pinned SDK/physical port are real. These
// identity observations are not bytes, GC, grant or public Run evidence.
const schema = {type: 'object', additionalProperties: false,
  properties: {answer: {type: 'array', items: {anyOf: [
    {type: 'string'}, {type: 'null'},
  ]}}}, required: ['answer']};
const schemaWire = JSON.stringify(schema);
const inputWire = '["9007199254740993","é\\r\\n",null]';
const instructions = 'Original é\r\n';
const responseWire = '{"model":"reported","choices":[{"index":0,' +
  '"message":{"content":"{\\"answer\\":[\\"é\\",null]}"},' +
  '"finish_reason":"stop"}],"usage":{"completion_tokens":0}}';
const responseBytes = Buffer.from(responseWire);
const limits = {maxBytes: 4096, maxChunkBytes: 4096, maxChunks: 2,
  maxHeaderBytes: 128, observedHeaders: ['content-type']};
const original = Object.freeze({});
const provider = Object.freeze({});
const projected = {_0: instructions, _1: inputWire, _2: schemaWire,
  _3: 'task', _4: 'prompt', _5: 'schema', _6: 'fixture-chat'};
const generation = {_0: 'fixture-chat', _1: 0.25, _2: 0.875,
  _3: 16n, _4: undefined};
const projection = {maxBytes: 10000, maxNodes: 1000, maxDepth: 40,
  maxFrames: 100, maxWork: 10000};
const baseMoon = {
  clientProgramProjectOpenAIChatRequest(p, r) {
    assert.equal(p, provider); assert.equal(r, original);
    return {$tag: 1, _0: projected};
  },
  clientProgramModelRequestGeneration(r) {
    assert.equal(r, original); return generation;
  },
};
function prepare() {
  return prepareAdmittedOpenAIChatRequest({moon: baseMoon,
    admittedProvider: provider, request: original, taskCid: 'task',
    promptCid: 'prompt', outputSchemaCid: 'schema', modelSelector: 'fixture-chat',
    projectionLimits: projection, modelId: 'gpt-4.1-nano',
    baseURL: 'https://fixture.invalid/v1', apiKey: 'private-fixture-only',
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16, notify() {},
  });
}
async function until(read, accept) {
  for (let i = 0; i < 40; i++) {
    const value = read();
    if (accept(value)) return value;
    await turn();
  }
  assert.fail('Finite SDK phase observation unavailable');
}
const release = handle => until(() => cleanupSdkPreparation(handle), x => x);

test('actual SDK schema normalization and verification retain distinct trees with shared leaf arrays', async t => {
  const parse = JSON.parse;
  const schemas = [];
  const envelopes = [];
  let handle;
  try {
    // Instrument only preparation. Escaping these trees extends their test
    // lifetime intentionally; it does not measure normal reachability or GC.
    JSON.parse = function(text, ...rest) {
      const value = parse(text, ...rest);
      if (text === schemaWire) schemas.push(value);
      if (value?.model === 'gpt-4.1-nano' && value.response_format) envelopes.push(value);
      return value;
    };
    handle = prepare();
    t.after(() => release(handle));
    await until(() => pollSdkPreparation(handle), x => x.kind === 'ready');
  } finally { JSON.parse = parse; }
  assert.equal(schemas.length, 2);
  assert.equal(envelopes.length, 1);
  assert.notEqual(schemas[0], schemas[1]);
  assert.notEqual(envelopes[0].response_format.json_schema.schema, schemas[1]);
  const request = sdkPreparedRequest(handle);
  assert.equal(JSON.parse(request.body).messages[1].content, inputWire);
  let sends = 0;
  prepareSdkTransport(handle, {responseLimits: limits, fetch() {
    sends++; return new Response(responseBytes,
      {headers: {'content-type': 'application/json'}});
  }});
  assert.equal(sends, 0);
  startSdkTransport(handle);
  await until(() => pollSdkDecode(handle), x => x.kind === 'ready');
  const decoded = takeSdkDecodedResult(handle);
  const normalized = decoded.request.body.response_format.json_schema.schema;
  assert.deepEqual(normalized, schema);
  assert.notEqual(normalized, schemas[0]);
  assert.notEqual(normalized.properties, schemas[0].properties);
  assert.notEqual(normalized.properties.answer, schemas[0].properties.answer);
  assert.notEqual(normalized.properties.answer.items, schemas[0].properties.answer.items);
  assert.notEqual(normalized.properties.answer.items.anyOf,
    schemas[0].properties.answer.items.anyOf);
  assert.equal(normalized.required, schemas[0].required);
  assert.notEqual(normalized, schemas[1]);
  assert.notEqual(normalized, envelopes[0].response_format.json_schema.schema);
  await release(handle);
  assert.equal(decoded.request.body.response_format.json_schema.schema, normalized);
  assert.equal(normalized.required, schemas[0].required);
  assert.equal(sends, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'ForeignSdkPreparation'});
});

function physical({rejectSave = false} = {}) {
  const state = {sends: 0, saves: 0, cleanups: 0, cleanupAllowed: false};
  const entry = Object.freeze({});
  const failure = Object.freeze(new Error('OriginalSaveResponseLost'));
  let finishSave;
  let raw;
  let saved;
  const handle = prepare();
  const moon = {
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan: (...args) => ({start: args.at(-1)}),
    clientProgramModelPhysicalCallForRequest(e, r, poll, cancel, cleanup) {
      assert.equal(e, entry); assert.equal(r, original);
      return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: value => ({kind: 'chat', value}),
  };
  const port = createSdkModelPreflight({moon, request: original, preparation: handle,
    profile: {}, installation: {}, quantities: {tokens: 16n, costUnits: 0n,
      durationMs: 500n}, responseLimits: limits, checked: value => value,
    observeAt: () => '2026-10-13T00:00:00.000Z', notify() {}, fetch() {
      state.sends++; return new Response(responseBytes,
        {headers: {'content-type': 'application/json'}});
    }, persistRaw(call, value) {
      state.saves++;
      if (raw === undefined) raw = value;
      assert.equal(value, raw);
      if (rejectSave && state.saves === 1) return Promise.reject(failure);
      return new Promise(resolve => { finishSave = () => {
        saved = Object.freeze({response: Object.freeze({raw, call})});
        resolve(saved);
      }; });
    }, cleanupRaw() { state.cleanups++; return state.cleanupAllowed; },
  });
  return {port, entry, state, failure, raw: () => raw, saved: () => saved,
    finish() { const settle = finishSave; finishSave = undefined; settle?.(); },
    ready: () => finishSave !== undefined};
}
async function start(f) {
  const plan = (await until(() => f.port.preflight.advance(), x => x._0))._1;
  return {plan, call: plan.start(f.entry)};
}

test('saved immutable view shares the original backing through pending save and cleanup', async t => {
  const f = physical();
  t.after(async () => {
    f.finish(); f.state.cleanupAllowed = true;
    await until(() => f.port.preflight.cleanup(), x => x);
  });
  const {plan, call} = await start(f);
  await until(() => call.poll(), () => f.ready());
  const raw = f.raw();
  assert.notEqual(raw.body.buffer, responseBytes.buffer);
  assert.equal(raw.body.buffer.byteLength, limits.maxBytes);
  assert.deepEqual(raw.body, new Uint8Array(responseBytes));
  for (let i = 0; i < 4; i++) assert.equal(call.poll().kind, 'pending');
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(f.state.saves, 1);
  f.finish();
  const view = (await until(() => call.poll(), x => x.kind === 'chat')).value;
  assert.equal(view, f.saved().response);
  assert.equal(view.raw, raw);
  assert.equal(view.raw.body, raw.body);
  assert.equal(view.raw.body.buffer, raw.body.buffer);
  assert.equal(f.port.preflight.cleanup(), false);
  assert.equal(call.poll().value, view);
  f.state.cleanupAllowed = true;
  await until(() => f.port.preflight.cleanup(), x => x);
  assert.equal(view.raw.body, raw.body);
  assert.deepEqual(view.raw.body, new Uint8Array(responseBytes));
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.sends, 1);
  assert.equal(f.state.saves, 1);
});

test('failed save reconfirmation reuses one Promise and raw backing while original Unknown stays fixed', async t => {
  const f = physical({rejectSave: true});
  t.after(async () => {
    f.finish(); f.state.cleanupAllowed = true;
    await until(() => f.port.preflight.cleanup(), x => x);
  });
  const {plan, call} = await start(f);
  await until(() => call.poll(), x => x.kind === 'unknown');
  const raw = f.raw();
  assert.equal(f.port.rawFailure(), f.failure);
  assert.equal(f.port.preflight.cleanup(), false);
  const pending = f.port.reconcileRaw(call);
  assert.equal(f.port.reconcileRaw(call), pending);
  await until(() => f.ready(), x => x);
  assert.equal(f.raw(), raw);
  assert.equal(call.poll().kind, 'unknown');
  assert.equal(f.port.preflight.cleanup(), false);
  f.finish();
  const saved = await pending;
  assert.equal(saved, f.saved());
  assert.equal(saved.response.raw, raw);
  assert.equal(saved.response.raw.body.buffer, raw.body.buffer);
  assert.equal(await f.port.reconcileRaw(call), saved);
  assert.equal(call.poll().kind, 'unknown');
  assert.equal(f.port.rawFailure(), f.failure);
  f.state.cleanupAllowed = true;
  await until(() => f.port.preflight.cleanup(), x => x);
  assert.equal(saved.response.raw, raw);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.state.sends, 1);
  assert.equal(f.state.saves, 2);
});
