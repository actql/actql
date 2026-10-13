import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOriginalHttpChatRequest} from './_internal/original-chat-request.mjs';

const limits = {maxBytes: 4096, maxNodes: 256, maxDepth: 16, maxFrames: 32, maxWork: 4096};
function fixture() {
  const request = {}, provider = {}, body = '{"model":"fixture","n":1,"stream":false}';
  let calls = 0;
  const moon = {clientProgramProjectHTTPChatRequest(p, r, model, ...bounds) {
    calls++; assert.equal(p, provider); assert.equal(r, request);
    assert.equal(model, 'fixture');
    assert.deepEqual(bounds, [4096, 256, 16, 32, 4096]);
    return {$tag: 1, _0: {_0: body, _1: 'task', _2: 'prompt', _3: 'schema', _4: 'selector'}};
  }};
  return {args: {moon, request, admittedProvider: provider, modelId: 'fixture',
    taskCid: 'task', promptCid: 'prompt', outputSchemaCid: 'schema',
    modelSelector: 'selector', limits}, body, calls: () => calls};
}

// Common is an explicit boundary double here; this does not execute the
// compiler/runtime codec, authorize a request or establish a public provider.
test('independent HTTP preparation consumes original Common arguments and body unchanged', () => {
  const f = fixture();
  const view = prepareOriginalHttpChatRequest(f.args);
  assert.deepEqual(view, {body: f.body}); assert(Object.isFrozen(view));
  assert.equal(f.calls(), 1);
});
test('independent HTTP preparation rejects every changed semantic binding', () => {
  for (const name of ['taskCid', 'promptCid', 'outputSchemaCid', 'modelSelector']) {
    const f = fixture();
    assert.throws(() => prepareOriginalHttpChatRequest({...f.args, [name]: 'foreign'}),
      /HTTPChatOriginalBindingMismatch/);
  }
});
test('independent HTTP preparation refuses accessor or invalid limits before Common', () => {
  const f = fixture();
  let getterCalls = 0;
  const changed = {...limits};
  Object.defineProperty(changed, 'maxBytes', {enumerable: true, get() {getterCalls++;return 4096;}});
  assert.throws(() => prepareOriginalHttpChatRequest({...f.args, limits: changed}),
    /InvalidHTTPChatProjectionLimits/);
  assert.equal(getterCalls, 0); assert.equal(f.calls(), 0);
  assert.throws(() => prepareOriginalHttpChatRequest({...f.args, limits: {...limits, maxWork: -1}}),
    /InvalidHTTPChatProjectionLimits/);
  assert.equal(f.calls(), 0);
});
test('independent HTTP preparation preserves Common refusal without another codec', () => {
  const f = fixture();
  f.args.moon.clientProgramProjectHTTPChatRequest = () => ({$tag: 0, _0: {}});
  assert.throws(() => prepareOriginalHttpChatRequest(f.args), /HTTPChatOriginalProjectionRefused/);
});
