import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:net';
import {once} from 'node:events';
import {createRequire} from 'node:module';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch}
  from './_internal/original-undici-transport.mjs';

const require = createRequire(import.meta.url);
const BodyReadable = require('undici/lib/api/readable.js');
const limits = {maxBytes: 32, maxChunkBytes: 32, maxChunks: 16,
  maxHeaderBytes: 1024, observedHeaders: []};
const headers = 'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n';

async function fixture(t, reply) {
  const sockets = new Set();
  let requests = 0;
  const server = createServer(socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    socket.once('data', () => { requests++; socket.write(reply); });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
  const fetch = createOriginalUndiciFetch({endpoint,
    requestLimits: {maxBytes: 64, maxHeaderBytes: 128, maxHeaders: 4},
    responseLimits: limits,
    physicalAcquisitionLimits: {maxPlaintextBytes: 4096,
      maxBorrowedBackingBytes: 16384, maxReads: 128}});
  const call = prepareOriginalUndiciFetch(fetch, endpoint,
    {method: 'POST', body: '{}', headers: [], redirect: 'error',
      signal: new AbortController().signal}, limits);
  const push = BodyReadable.prototype.push;
  const observed = [];
  // Test-process observation only: delegate every invocation to its original
  // receiver/method; do not alter parser/queue/cleanup ordering or body bytes.
  BodyReadable.prototype.push = function (chunk, ...args) {
    if (Buffer.isBuffer(chunk)) observed.push({body: this, bytes: chunk.byteLength});
    return Reflect.apply(push, this, [chunk, ...args]);
  };
  t.after(async () => {
    try { assert.equal(await call.cleanup(), true); }
    finally {
      BodyReadable.prototype.push = push;
      for (const socket of sockets) socket.destroy(); // Fixture, not product ACK.
      await new Promise(resolve => server.close(resolve));
    }
  });
  return {call, observed, requests: () => requests};
}

test('original parser exact body ceiling reaches the queue before any consumer read', {timeout: 5000}, async t => {
  const f = await fixture(t, headers + `20\r\n${'A'.repeat(32)}\r\n0\r\n\r\n`);
  const response = await f.call.invoke();
  const reader = response.body.getReader();
  const parts = [];
  for (;;) {
    const next = await reader.read();
    if (next.done) break;
    parts.push(next.value);
  }
  reader.releaseLock();
  assert.equal(Buffer.concat(parts).toString(), 'A'.repeat(32));
  assert.equal(f.observed.reduce((sum, value) => sum + value.bytes, 0), 32);
  assert.equal(new Set(f.observed.map(value => value.body)).size, 1);
  assert.equal(f.requests(), 1);
  assert.equal(await f.call.cleanup(), true);
  assert.throws(() => f.call.invoke(), {code: 'UndiciOriginalTransportRetired'});
});

test('original parser rejects an oversized first chunk before body queue insertion', {timeout: 5000}, async t => {
  const f = await fixture(t, headers + `21\r\n${'B'.repeat(33)}\r\n0\r\n\r\n`);
  let error;
  try {
    const reader = (await f.call.invoke()).body.getReader();
    for (;;) { if ((await reader.read()).done) break; }
  } catch (failure) { error = failure; }
  assert.equal(error?.code, 'UND_ERR_RES_EXCEEDED_MAX_SIZE');
  const accepted = f.observed.reduce((sum, value) => sum + value.bytes, 0);
  // Native input/parser callbacks can subdivide a wire chunk. The prefix can
  // be queued, but the next positive onBody callback is refused before push.
  assert.ok(accepted <= 32);
  assert.equal(f.requests(), 1);
  assert.equal(await f.call.cleanup(), true);
  assert.throws(() => f.call.invoke(), {code: 'UndiciOriginalTransportRetired'});
  t.diagnostic(JSON.stringify({acceptedQueuedBytes: accepted, originalBodyCeiling: 32,
    qualification: 'Actual selected Undici/TCP path; no Core/Store funding or Provider.'}));
});

test('accepted exact body plus excess tail never queues cumulative bytes above its ceiling', {timeout: 5000}, async t => {
  const f = await fixture(t, headers + `20\r\n${'C'.repeat(32)}\r\n1\r\nD\r\n0\r\n\r\n`);
  let error;
  try {
    const reader = (await f.call.invoke()).body.getReader();
    for (;;) { if ((await reader.read()).done) break; }
  } catch (failure) { error = failure; }
  assert.equal(error?.code, 'UND_ERR_RES_EXCEEDED_MAX_SIZE');
  assert.equal(f.observed.reduce((sum, value) => sum + value.bytes, 0), 32);
  assert.equal(new Set(f.observed.map(value => value.body)).size, 1);
  assert.equal(f.requests(), 1);
  assert.equal(await f.call.cleanup(), true);
  assert.throws(() => f.call.invoke(), {code: 'UndiciOriginalTransportRetired'});
});
