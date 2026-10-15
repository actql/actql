import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {channel} from 'node:diagnostics_channel';
import {setImmediate as turn} from 'node:timers/promises';
import {readBoundedInferResponse} from './_internal/bounded-response.mjs';

// Delegating observations of the actual pinned Client and original Socket.
// WeakRef checks alias reachability, not heap bytes, GC completion or an ACK.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
const headerRefs = [];
const sockets = [];
let delayClose = false;
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
const connected = channel('undici:client:connected');
connected.subscribe(observeSocket);
undici.Client = new Proxy(OriginalClient, {construct(target, args) {
  const client = Reflect.construct(target, args, target);
  const request = client.request;
  client.request = function(options) {
    return Reflect.apply(request, this, [options]).then(response => {
      headerRefs.push(new WeakRef(response.headers));
      return response;
    });
  };
  return client;
}});
let physical;
try { physical = await import('./_internal/original-undici-transport.mjs'); }
finally { undici.Client = OriginalClient; }

const limits = {maxBytes: 256, maxChunkBytes: 256, maxChunks: 8,
  maxHeaderBytes: 1024, observedHeaders: ['content-type']};
const acquisition = {maxPlaintextBytes: 65536,
  maxBorrowedBackingBytes: 131072, maxReads: 64};
async function collected(ref) {
  assert.equal(typeof global.gc, 'function', 'Select this test with --expose-gc');
  for (let index = 0; index < 24; index++) {
    await turn();
    global.gc();
    await turn();
    if (ref.deref() === undefined) return true;
  }
  return false;
}
async function consume(call, escapeHeaders) {
  const view = await call.invoke();
  const raw = await readBoundedInferResponse(view, limits);
  assert.equal(raw.transportComplete, true);
  assert.equal(await raw.readerRetirement, true);
  return {raw, headers: escapeHeaders ? view.headers : undefined};
}
async function fixture(t, {delayed = false} = {}) {
  let requests = 0;
  const beforeHeaders = headerRefs.length, beforeSockets = sockets.length;
  const server = createServer((request, response) => {
    request.resume(); requests++;
    response.setHeader('content-type', 'application/json');
    response.setHeader('x-original', ['first', 'second']);
    response.end('{"original":true}');
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
  const fetch = physical.createOriginalUndiciFetch({endpoint,
    requestLimits: {maxBytes: 256, maxHeaderBytes: 1024, maxHeaders: 8},
    responseLimits: limits, physicalAcquisitionLimits: acquisition});
  const call = physical.prepareOriginalUndiciFetch(fetch, endpoint,
    {method: 'POST', body: '{}', headers: [], redirect: 'error',
      signal: new AbortController().signal}, limits);
  delayClose = delayed;
  t.after(async () => {
    delayClose = false;
    for (const record of sockets.slice(beforeSockets)) record.finish?.();
    try { assert.equal(await call.cleanup(), true); }
    finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  });
  return {call, requests: () => requests,
    header() {assert.equal(headerRefs.length, beforeHeaders + 1); return headerRefs[beforeHeaders];},
    socket() {assert.equal(sockets.length, beforeSockets + 1); return sockets[beforeSockets];}};
}

test('fulfilled original request does not retain unused headers while actual Socket close is pending',
  {timeout: 10000}, async t => {
    const f = await fixture(t, {delayed: true});
    const saved = await consume(f.call, false);
    assert.equal(Buffer.from(saved.raw.body).toString(), '{"original":true}');
    const socket = f.socket();
    const cleanup = f.call.cleanup();
    let retired = false; cleanup.then(() => { retired = true; });
    await turn();
    assert.equal(typeof socket.finish, 'function');
    assert.equal(socket.closes, 0);
    assert.equal(retired, false, 'request completion is not actual Socket close');
    assert.equal(await collected(f.header()), true,
      'the Call needs original request settlement, not its fulfilled response/header value');
    assert.equal(retired, false);
    assert.equal(socket.closes, 0);
    assert.equal(f.requests(), 1);
    socket.finish();
    assert.equal(await cleanup, true);
    assert.equal(socket.closes, 1);
    assert.equal(await f.call.cleanup(), true);
    assert.throws(() => f.call.invoke(), {code: 'UndiciOriginalTransportRetired'});
  });

test('an escaped original header view remains unchanged after request and physical retirement',
  {timeout: 10000}, async t => {
    const f = await fixture(t);
    const saved = await consume(f.call, true);
    assert.equal(saved.headers.get('x-original'), 'first, second');
    assert.equal(await f.call.cleanup(), true);
    assert.equal(await collected(f.header()), false, 'the escaped view still borrows its original map');
    assert.equal(saved.headers.get('CONTENT-TYPE'), 'application/json');
    assert.equal(saved.headers.get('x-original'), 'first, second');
    assert.equal(Buffer.from(saved.raw.body).toString(), '{"original":true}');
    assert.equal(f.requests(), 1);
  });
