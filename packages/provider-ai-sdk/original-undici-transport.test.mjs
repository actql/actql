import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {channel} from 'node:diagnostics_channel';
import net from 'node:net';
import {setImmediate as turn} from 'node:timers/promises';
import {gzipSync} from 'node:zlib';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {createOriginalUndiciFetch} from './_internal/original-undici-transport.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';
import {interceptSdkRequest, pollSdkPreparation, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  pollSdkDecode, cleanupSdkPreparation, cancelSdkPreparation,
  progressSdkOriginalIoCleanup} from './_internal/intercepted-request.mjs';

const requestLimits = {maxBytes: 256, maxHeaderBytes: 1024, maxHeaders: 8};
const responseLimits = {maxBytes: 256, maxChunkBytes: 256, maxChunks: 8,
  maxHeaderBytes: 1024, observedHeaders: ['content-type', 'content-encoding']};
const originalBody = '{"model":"synthetic","messages":[{"role":"user","content":"é\\n雪"}]}';
async function until(read, accepted) {
  for (let index = 0; index < 500; index++) {
    const value = read();
    if (accepted(value)) return value;
    await turn();
  }
  assert.fail('Finite original transport observation not reached');
}
async function fixture(t, respond) {
  const calls = [];
  const sockets = new Set();
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    calls.push({method: request.method, path: request.url,
      body: Buffer.concat(chunks).toString('utf8'), headers: request.headers,
      socket: request.socket});
    respond(request, response, calls.length);
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
  const fetch = createOriginalUndiciFetch({endpoint, requestLimits, responseLimits});
  const preparations = [];
  t.after(async () => {
    try {
      for (const handle of preparations) {
        await until(() => cleanupSdkPreparation(handle), value => value === true);
      }
    } finally {
      // Fixture shutdown only; never product retirement evidence.
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  });
  function prepare({transport = true} = {}) {
    const handle = interceptSdkRequest({endpoint, maxRequestBytes: requestLimits.maxBytes,
      maxHeaderBytes: requestLimits.maxHeaderBytes, maxHeaders: requestLimits.maxHeaders,
      notify() {}, async runSdk(intercepted, signal) {
        // Deliberately no SDK decode. This finite fixture exercises the actual
        // SDK-owner interceptor/reader/Undici transport; builder is a double.
        await intercepted(endpoint, {method: 'POST', body: originalBody,
          headers: {'content-type': 'application/json'}, signal});
        assert.fail('Raw-only transport must not deliver an SDK response copy');
      }});
    assert.equal(pollSdkPreparation(handle).kind, 'ready');
    if (transport) prepareSdkTransport(handle, {fetch, responseLimits, responseMode: 'raw-only'});
    preparations.push(handle);
    return handle;
  }
  return {endpoint, fetch, prepare, calls, sockets};
}

test('original IO retirement keeps raw backing and SDK holding until independent cleanup', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.setHeader('content-type', 'application/json');
    response.end('{"answer":"é\\n雪","usage":null}');
  });
  const handle = f.prepare();
  assert.equal(progressSdkOriginalIoCleanup(handle), false, 'no original started Call');
  assert.equal(f.calls.length, 0);
  startSdkTransport(handle); // Common Entry is a fixture double, not admission.
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  const backing = raw.body.buffer;
  await until(() => progressSdkOriginalIoCleanup(handle), value => value === true);
  assert.strictEqual(sdkTransportRawObservation(handle), raw);
  assert.strictEqual(raw.body.buffer, backing);
  assert.equal(raw.transportComplete, true);
  assert.equal(pollSdkTransport(handle).kind, 'response', 'IO ACK does not retire SDK/raw view');
  assert.equal(f.calls.length, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(Buffer.from(raw.body).toString(), '{"answer":"é\\n雪","usage":null}');
});

test('original IO observation never stops an unfinished normal read', {timeout: 5000}, async t => {
  let output;
  const f = await fixture(t, (request, response) => { output = response; });
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => f.calls.length, value => value === 1);
  for (let index = 0; index < 4; index++) {
    assert.equal(progressSdkOriginalIoCleanup(handle), false);
    assert.equal(pollSdkTransport(handle).kind, 'pending');
    assert.equal(f.sockets.size, 1);
    await turn();
  }
  output.setHeader('content-type', 'application/json');
  output.end('{}');
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  await until(() => progressSdkOriginalIoCleanup(handle), value => value === true);
  assert.equal(f.calls.length, 1);
  assert.equal(sdkTransportRawObservation(handle).transportComplete, true);
});

test('generic fetch default retirement is not an original physical IO observation', {timeout: 5000}, async () => {
  const endpoint = 'https://fixture.invalid/chat/completions';
  const handle = interceptSdkRequest({endpoint, maxRequestBytes: 256,
    maxHeaderBytes: 1024, maxHeaders: 8, notify() {},
    async runSdk(fetch, signal) {
      await fetch(endpoint, {method: 'POST', body: originalBody, signal});
      assert.fail('Raw-only SDK response copy is unavailable');
    }});
  prepareSdkTransport(handle, {fetch: () => new Response('{}',
    {headers: {'content-type': 'application/json'}}), responseLimits, responseMode: 'raw-only'});
  assert.equal(progressSdkOriginalIoCleanup(handle), undefined);
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  assert.equal(progressSdkOriginalIoCleanup(handle), undefined);
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(progressSdkOriginalIoCleanup(handle), undefined);
});

test('original IO observation rejects copied or foreign SDK preparations', () => {
  for (const value of [{}, Object.freeze({}), undefined, null]) {
    assert.throws(() => progressSdkOriginalIoCleanup(value), {code: 'ForeignSdkPreparation'});
  }
});

test('original Model port drives IO close while the same raw Store save stays pending', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.setHeader('content-type', 'application/json');
    response.end('{"answer":"original"}');
  });
  const handle = f.prepare({transport: false});
  const request = Object.freeze({original: Symbol('request double')});
  const entry = Object.freeze({original: Symbol('Entry double')});
  let heldRaw;
  let completeSave;
  let rawReleased = false;
  let saves = 0;
  const moon = {
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(actual, bytes, tokens, cost, duration,
      profile, installation, start) {
      assert.strictEqual(actual, request);
      return {start};
    },
    clientProgramModelPhysicalCallForRequest(actual, original, poll, cancel, cleanup) {
      assert.strictEqual(actual, entry);
      assert.strictEqual(original, request);
      return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: response => ({kind: 'saved', response}),
  };
  const port = createSdkModelPreflight({moon, request, preparation: handle,
    profile: {}, installation: {}, quantities: {tokens: 16n, costUnits: 0n, durationMs: 500n},
    fetch: f.fetch, responseLimits, checked: value => value, notify() {},
    observeAt: () => '2026-10-14T00:00:00.000Z',
    persistRaw(call, raw) {
      saves++;
      heldRaw = raw;
      return new Promise(resolve => { completeSave = resolve; });
    }, cleanupRaw: () => rawReleased});
  const {_1: plan} = await until(() => port.preflight.advance(), value => value._0);
  const call = plan.start(entry);
  await until(() => { call.poll(); return heldRaw; }, value => value !== undefined);
  const backing = heldRaw.body.buffer;
  // Real original Client/socket cleanup is driven by this existing port;
  // Common Entry/receipt and Store persistence remain explicit doubles.
  await until(() => { call.poll(); return progressSdkOriginalIoCleanup(handle); }, value => value === true);
  assert.deepEqual(call.poll(), {kind: 'pending'});
  assert.equal(call.cleanup(), false);
  assert.strictEqual(heldRaw.body.buffer, backing);
  assert.equal(Buffer.from(heldRaw.body).toString(), '{"answer":"original"}');
  assert.equal(saves, 1);
  assert.equal(f.calls.length, 1);
  assert.equal(plan.start(entry), undefined);
  completeSave({response: {original: heldRaw, nominal: Symbol('saved double')}});
  await until(() => call.poll(), value => value.kind === 'saved');
  assert.equal(call.cleanup(), false, 'actual raw alias cleanup remains independent');
  rawReleased = true;
  await until(() => call.cleanup(), value => value === true);
  assert.equal(saves, 1);
  assert.equal(f.calls.length, 1);
  assert.strictEqual(heldRaw.body.buffer, backing, 'escaped immutable raw view not mutated');
});

test('per-call Client is prepared without IO and raw response/Unicode stay original', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.setHeader('content-type', 'application/json');
    response.end('{"answer":"é\\n雪","usage":null}');
  });
  const handle = f.prepare();
  await turn();
  assert.equal(f.calls.length, 0);
  assert.equal(f.sockets.size, 0);
  assert.throws(() => f.fetch(f.endpoint, {}), {code: 'UndiciOriginalRequestNotPrepared'});
  startSdkTransport(handle); // Existing Core gate is a test double here.
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.equal(raw.transportComplete, true);
  assert.equal(raw.status, 200);
  assert.equal(Buffer.from(raw.body).toString(), '{"answer":"é\\n雪","usage":null}');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].body, originalBody);
  assert.equal(f.calls[0].path, '/chat/completions');
  await until(() => pollSdkDecode(handle), value => value.kind === 'retired');
  assert.equal(cleanupSdkPreparation(handle), false, 'Client retirement has its own ACK');
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(f.sockets.size, 0);
  assert.equal(Buffer.from(raw.body).toString(), '{"answer":"é\\n雪","usage":null}');
});

test('four original SDK calls have separate Clients rather than one serial queue', {timeout: 5000}, async t => {
  const responses = [];
  const f = await fixture(t, (request, response) => {
    responses.push(response);
    if (responses.length === 4) for (const pending of responses) pending.end('{}');
  });
  const handles = Array.from({length: 4}, () => f.prepare());
  assert.equal(f.calls.length, 0);
  for (const handle of handles) startSdkTransport(handle);
  await until(() => f.calls.length, value => value === 4);
  assert.equal(new Set(f.calls.map(call => call.socket)).size, 4);
  for (const handle of handles) await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  t.diagnostic('Physical per-call fixture only; not Core four-Slot/funded concurrency acceptance');
});

test('redirect is an original response without follow-up request', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.writeHead(307, {location: '/redirect-target'});
    response.end('{}');
  });
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  assert.equal(sdkTransportRawObservation(handle).status, 307);
  assert.equal(f.calls.length, 1);
});

test('compressed bytes are retained without automatic content decoding', {timeout: 5000}, async t => {
  const compressed = gzipSync('{"answer":7}');
  const f = await fixture(t, (request, response) => {
    response.writeHead(200, {'content-encoding': 'gzip'});
    response.end(compressed);
  });
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  assert.deepEqual(Buffer.from(sdkTransportRawObservation(handle).body), compressed);
  assert.equal(f.calls.length, 1);
});

test('cancel before transport start closes the prepared Client and sends zero', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => response.end('{}'));
  const handle = f.prepare();
  cancelSdkPreparation(handle);
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
  assert.equal(cleanupSdkPreparation(handle), false);
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(f.calls.length, 0);
  assert.equal(f.sockets.size, 0);
});

test('pending body abort retains incomplete raw and awaits original physical cleanup', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.writeHead(200, {'content-type': 'application/json'});
    response.write('{');
  });
  const handle = f.prepare();
  let incomingChunks = 0;
  const received = channel('undici:request:bodyChunkReceived');
  const count = ({request}) => { if (String(request.origin) === new URL(f.endpoint).origin) incomingChunks++; };
  received.subscribe(count);
  t.after(() => received.unsubscribe(count));
  startSdkTransport(handle);
  await until(() => incomingChunks, value => value === 1);
  await turn();
  // Original request is entered; cancellation never returns it to unsent.
  cancelSdkPreparation(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  assert.equal(sdkTransportRawObservation(handle).transportComplete, false);
  assert.equal(sdkTransportRawObservation(handle).status, 200);
  assert.equal(cleanupSdkPreparation(handle), false);
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(f.calls.length, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'ForeignSdkPreparation'});
});

test('response loss after original request is Unknown and not retried', {timeout: 5000}, async t => {
  const f = await fixture(t, request => request.socket.destroy());
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'unknown');
  assert.equal(sdkTransportRawObservation(handle), undefined);
  assert.equal(f.calls.length, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'SdkTransportStartRefused'});
});

test('actual all-header parser ceiling rejects overflow, distinct from observed-header subset', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.setHeader('x-unobserved', 'x'.repeat(2048));
    response.end('{}');
  });
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'unknown');
  assert.equal(f.calls.length, 1);
});

test('physical body byte ceiling refuses excess without a second request', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => response.end('x'.repeat(257)));
  const handle = f.prepare();
  startSdkTransport(handle);
  const terminal = await until(() => pollSdkTransport(handle), value => value.kind === 'unknown' || value.kind === 'response');
  if (terminal.kind === 'response') assert.equal(sdkTransportRawObservation(handle).transportComplete, false);
  assert.equal(f.calls.length, 1);
});

test('physical body byte exact-fit succeeds at the original declaration', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => response.end('x'.repeat(256)));
  const handle = f.prepare();
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.equal(raw.transportComplete, true);
  assert.equal(raw.body.byteLength, 256);
  assert.equal(Buffer.from(raw.body).toString(), 'x'.repeat(256));
  assert.equal(f.calls.length, 1);
});

test('actual header field/value sum below ceiling succeeds while exact ceiling refuses', {timeout: 5000}, async t => {
  // No automatic Date. Names+values: x-fill(6)+fill + content-length(14)+2(1)
  // + connection(10)+close(5) = fill+36. Separators/status are another domain.
  for (const fill of [987, 988]) {
    const f = await fixture(t, (request, response) => {
      response.sendDate = false;
      response.setHeader('x-fill', 'x'.repeat(fill));
      response.setHeader('connection', 'close');
      response.end('{}');
    });
    const handle = f.prepare();
    startSdkTransport(handle);
    const terminal = await until(() => pollSdkTransport(handle),
      value => value.kind === 'response' || value.kind === 'unknown');
    assert.equal(terminal.kind, fill === 987 ? 'response' : 'unknown');
    if (terminal.kind === 'response') assert.equal(sdkTransportRawObservation(handle).transportComplete, true);
    assert.equal(f.calls.length, 1);
  }
});

test('actual pinned OpenAI SDK resumes only into original loopback raw-only transport', {timeout: 5000}, async t => {
  const f = await fixture(t, (request, response) => {
    response.end('{"choices":[{"index":0,"message":{"content":"{}"},"finish_reason":"stop"}],"usage":null}');
  });
  const localRequest = {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16};
  const localResponse = {...responseLimits, maxBytes: 4096, maxChunkBytes: 512};
  const fetch = createOriginalUndiciFetch({endpoint: f.endpoint,
    requestLimits: localRequest, responseLimits: localResponse});
  const handle = prepareOpenAIChatRequest({modelId: 'synthetic-model',
    baseURL: f.endpoint.slice(0, -'/chat/completions'.length), apiKey: 'synthetic-only',
    maxRequestBytes: localRequest.maxBytes, maxHeaderBytes: localRequest.maxHeaderBytes,
    maxHeaders: localRequest.maxHeaders, notify() {}, options: {
      prompt: [{role: 'user', content: [{type: 'text', text: 'Original é\r\n'}]}],
      maxOutputTokens: 16, responseFormat: {type: 'json'},
    }});
  t.after(async () => { await until(() => cleanupSdkPreparation(handle), value => value === true); });
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  prepareSdkTransport(handle, {fetch, responseLimits: localResponse, responseMode: 'raw-only'});
  assert.equal(f.calls.length, 0);
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.equal(raw.transportComplete, true);
  assert.equal(Buffer.from(raw.body).toString(),
    '{"choices":[{"index":0,"message":{"content":"{}"},"finish_reason":"stop"}],"usage":null}');
  await until(() => pollSdkDecode(handle), value => value.kind === 'retired');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].headers.authorization, 'Bearer synthetic-only');
  const request = JSON.parse(f.calls[0].body);
  assert.equal(request.model, 'synthetic-model');
  assert.deepEqual(request.messages, [{role: 'user', content: 'Original é\r\n'}]);
  t.diagnostic('Actual pinned SDK/loopback; no Common Entry/Store/funding/public acceptance');
});

test('connecting Client destroy cannot retire the original socket before its real close', {timeout: 5000}, async t => {
  // Controlled acquisition only: real selected Undici and real Node Socket,
  // no TCP connection. Hold _destroy's callback to witness the late close.
  const originalConnect = net.connect;
  const socket = new net.Socket();
  const originalDestroy = socket._destroy;
  let finishClose, socketCloses = 0, connects = 0;
  // Socket disables generic stream emitClose. Only its original _destroy
  // closes/emits the actual Socket event; calling callback alone is not that
  // operation. Delay, then invoke that same original with exact arguments.
  socket._destroy = (error, callback) => {
    finishClose = () => {
      finishClose = undefined;
      Reflect.apply(originalDestroy, socket, [error, callback]);
    };
  };
  socket.on('error', () => {});
  socket.once('close', () => { socketCloses++; });
  net.connect = () => { connects++; return socket; };
  let handle;
  t.after(async () => {
    net.connect = originalConnect;
    finishClose?.();
    if (handle !== undefined) await until(() => cleanupSdkPreparation(handle), value => value === true);
  });
  const endpoint = 'http://127.0.0.1:1/chat/completions';
  const fetch = createOriginalUndiciFetch({endpoint, requestLimits, responseLimits});
  handle = interceptSdkRequest({endpoint, maxRequestBytes: 256,
    maxHeaderBytes: 1024, maxHeaders: 8, notify() {}, async runSdk(intercepted, signal) {
      await intercepted(endpoint, {method: 'POST', body: '{}', signal});
    }});
  prepareSdkTransport(handle, {fetch, responseLimits, responseMode: 'raw-only'});
  startSdkTransport(handle);
  assert.equal(connects, 1);
  assert.equal(cleanupSdkPreparation(handle), false);
  await until(() => pollSdkTransport(handle), value => value.kind === 'unknown');
  assert.equal(socket.destroyed, true, 'Destroy request is not a close acknowledgement');
  assert.equal(socketCloses, 0);
  for (let index = 0; index < 4; index++) {
    assert.equal(cleanupSdkPreparation(handle), false);
    await turn();
  }
  assert.equal(typeof finishClose, 'function');
  finishClose();
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.equal(socketCloses, 1);
  assert.equal(connects, 1);
  assert.throws(() => startSdkTransport(handle), {code: 'ForeignSdkPreparation'});
  t.diagnostic('Controlled pending connector/socket; TCP/TLS0, grant0/public0');
});
