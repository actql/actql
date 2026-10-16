import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {channel} from 'node:diagnostics_channel';
import {setImmediate as turn} from 'node:timers/promises';

// Observe actual original object identities, not their byte prices. The
// delegating Client observes WeakRefs only; real close still uses Node's
// original _destroy/error/callback. No Common/Store/Provider ACK is issued.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
const observations = [];
const sockets = [];
let delayClose = false;
const connected = channel('undici:client:connected');
const observeSocket = ({socket}) => {
  const record = {socket, closes: 0, finish: undefined};
  socket.once('close', () => { record.closes++; });
  if (delayClose) {
    const destroy = socket._destroy;
    socket._destroy = function(error, callback) {
      const owner = this;
      record.finish = () => {
        record.finish = undefined;
        Reflect.apply(destroy, owner, [error, callback]);
      };
    };
  }
  sockets.push(record);
};
connected.subscribe(observeSocket);
undici.Client = new Proxy(OriginalClient, {construct(target, args) {
  const client = Reflect.construct(target, args, target);
  const request = client.request;
  client.request = function(options) {
    return Reflect.apply(request, this, [options]).then(response => {
      const observed = {headers: new WeakRef(response.headers),
        trailers: new WeakRef(response.trailers), body: new WeakRef(response.body),
        bodyCloses: 0};
      response.body.once('close', () => { observed.bodyCloses++; });
      observations.push(observed);
      return response;
    });
  };
  return client;
}});
let physical, sdk, intercepted, bounded;
try {
  physical = await import('./_internal/original-undici-transport.mjs');
  sdk = await import('./_internal/openai-chat.mjs');
  intercepted = await import('./_internal/intercepted-request.mjs');
  bounded = await import('./_internal/bounded-response.mjs');
} finally { undici.Client = OriginalClient; }

const limits = {maxBytes: 8192, maxChunkBytes: 8192, maxChunks: 32,
  maxHeaderBytes: 16384, observedHeaders: ['content-type']};
const requestLimits = {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16};
const acquisition = {maxPlaintextBytes: 65536,
  maxBorrowedBackingBytes: 131072, maxReads: 64};
const wire = '{"choices":[{"index":0,"message":{"content":"{}"},"finish_reason":"stop"}],"usage":null}';
async function until(read, accept) {
  for (let i = 0; i < 1000; i++) {
    const value = read();
    if (accept(value)) return value;
    await turn();
  }
  assert.fail('Original finite observation did not settle');
}
async function collected(reference) {
  assert.equal(typeof global.gc, 'function', 'Run this diagnostic with --expose-gc');
  for (let i = 0; i < 24; i++) {
    await turn(); global.gc(); await turn();
    if (reference.deref() === undefined) return true;
  }
  return false;
}
async function fixture(t) {
  const firstObservation = observations.length, firstSocket = sockets.length;
  let requests = 0;
  const server = createServer((request, response) => {
    request.resume(); requests++;
    response.setHeader('content-type', 'application/json');
    response.setHeader('x-head', ['head-a', 'head-b']);
    response.setHeader('trailer', 'x-tail');
    response.write(wire);
    response.addTrailers({'x-tail': 'original-trailer'});
    response.end();
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
  const fetch = physical.createOriginalUndiciFetch({endpoint, requestLimits,
    responseLimits: limits, physicalAcquisitionLimits: acquisition});
  delayClose = true;
  t.after(async () => {
    delayClose = false;
    for (const socket of sockets.slice(firstSocket)) socket.finish?.();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  return {fetch, endpoint, requests: () => requests,
    observation() {assert.equal(observations.length, firstObservation + 1); return observations[firstObservation];},
    socket() {assert.equal(sockets.length, firstSocket + 1); return sockets[firstSocket];}};
}

test('raw-only SDK does not retain unused response maps after actual body close while Socket is pending',
  {timeout: 15000}, async t => {
    const f = await fixture(t);
    const handle = sdk.prepareOpenAIChatRequest({modelId: 'synthetic-model',
      baseURL: f.endpoint.slice(0, -'/chat/completions'.length), apiKey: 'synthetic-only',
      maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16, notify() {},
      options: {prompt: [{role: 'user', content: [{type: 'text', text: 'original'}]}],
        maxOutputTokens: 16, responseFormat: {type: 'json'}}});
    t.after(async () => {
      f.socket().finish?.();
      await until(() => intercepted.cleanupSdkPreparation(handle), value => value === true);
    });
    await until(() => intercepted.pollSdkPreparation(handle), value => value.kind === 'ready');
    intercepted.prepareSdkTransport(handle, {fetch: f.fetch, responseLimits: limits,
      responseMode: 'raw-only'});
    intercepted.startSdkTransport(handle);
    await until(() => intercepted.pollSdkTransport(handle), value => value.kind === 'response');
    const raw = intercepted.sdkTransportRawObservation(handle);
    assert.equal(raw.transportComplete, true);
    assert.equal(await raw.readerRetirement, true);
    await until(() => intercepted.pollSdkDecode(handle), value => value.kind === 'retired');
    const socket = f.socket(), observed = f.observation();
    assert.equal(intercepted.progressSdkOriginalIoCleanup(handle), false);
    await until(() => socket.finish, value => typeof value === 'function');
    await until(() => observed.bodyCloses, value => value === 1);
    assert.equal(socket.closes, 0);
    assert.equal(intercepted.progressSdkOriginalIoCleanup(handle), false);
    const unreachable = {head: await collected(observed.headers),
      body: await collected(observed.body), trailers: await collected(observed.trailers)};
    assert.deepEqual(unreachable, {head: true, body: true, trailers: true},
      'original body close may retire the unused alias, never the pending Socket duty');
    assert.deepEqual(raw.headers, [['content-type', 'application/json']]);
    assert.equal(Buffer.from(raw.body).toString('utf8'), wire);
    assert.equal(socket.closes, 0);
    assert.equal(intercepted.progressSdkOriginalIoCleanup(handle), false);
    assert.equal(f.requests(), 1);
    socket.finish();
    await until(() => intercepted.progressSdkOriginalIoCleanup(handle), value => value === true);
    assert.equal(socket.closes, 1);
    assert.equal(Buffer.from(raw.body).toString('utf8'), wire);
    assert.throws(() => intercepted.startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  });

async function borrowBody(call) {
  const view = await call.invoke();
  const raw = await bounded.readBoundedInferResponse(view, limits);
  assert.equal(raw.transportComplete, true);
  assert.equal(await raw.readerRetirement, true);
  return {raw, body: view.body};
}
test('an escaped original body keeps its own completed trailer handler after physical cleanup',
  {timeout: 15000}, async t => {
    const f = await fixture(t);
    const call = physical.prepareOriginalUndiciFetch(f.fetch, f.endpoint,
      {method: 'POST', body: '{}', headers: [], redirect: 'error',
        signal: new AbortController().signal}, limits);
    t.after(async () => {f.socket().finish?.(); assert.equal(await call.cleanup(), true);});
    const saved = await borrowBody(call);
    const socket = f.socket(), observed = f.observation();
    const cleanup = call.cleanup();
    await until(() => socket.finish, value => typeof value === 'function');
    assert.equal(socket.closes, 0);
    socket.finish(); assert.equal(await cleanup, true);
    assert.equal(await collected(observed.headers), true);
    assert.equal(await collected(observed.body), false, 'escaped stream still owns the original body');
    assert.equal(await collected(observed.trailers), false, 'borrowed body keeps its original abort/handler chain');
    await saved.body.cancel();
    assert.equal(Buffer.from(saved.raw.body).toString('utf8'), wire);
    assert.equal(f.requests(), 1);
  });
