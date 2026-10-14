// Source-qualified queue witnesses, not a Host allocator grant or heap bound.
// Observe the actual pinned Undici BodyReadable without changing its push/read
// results. The original transport, parser and native input remain unmodified.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch} from
  './_internal/original-undici-transport.mjs';
import {readBoundedInferResponse} from './_internal/bounded-response.mjs';

const require = createRequire(import.meta.url);
const {Readable: BodyReadable} = require('undici/lib/api/readable.js');

async function exercise(t, {maxBytes, overflow, chunked}) {
  assert.equal(process.versions.node, '22.22.0');
  assert.equal(require('undici/package.json').version, '7.30.0');
  const maxChunkBytes = 1024;
  const first = Buffer.alloc(400, 65), second = Buffer.alloc(900, 66);
  const pushed = [], concats = [], bodyErrors = [];
  let observedBody, bodyReadDepth = 0, requests = 0, call;
  let resolveFirst, resolveSecond, resolveBodyError;
  const firstPushed = new Promise(resolve => { resolveFirst = resolve; });
  const secondPushed = new Promise(resolve => { resolveSecond = resolve; });
  const bodyFailed = new Promise(resolve => { resolveBodyError = resolve; });
  const push = BodyReadable.prototype.push, allocate = Buffer.allocUnsafe;
  BodyReadable.prototype.push = function(chunk) {
    if (observedBody === undefined) {
      observedBody = this;
      this.on('error', error => { bodyErrors.push(error.code); resolveBodyError(); });
      const read = this.read;
      this.read = function(...args) {
        bodyReadDepth++;
        try { return Reflect.apply(read, this, args); }
        finally { bodyReadDepth--; }
      };
    }
    assert.equal(this, observedBody, 'one original body, no other request');
    const result = Reflect.apply(push, this, [chunk]);
    if (chunk !== null) {
      pushed.push(chunk.byteLength);
      if (pushed.length === 1) resolveFirst();
      if (pushed.length === 2) resolveSecond();
    }
    return result;
  };
  Buffer.allocUnsafe = function(length) {
    const bytes = Reflect.apply(allocate, Buffer, [length]);
    if (bodyReadDepth > 0 && new Error().stack.includes('fromList')) {
      concats.push({length, backingBytes: bytes.buffer.byteLength});
    }
    return bytes;
  };
  const sockets = new Set();
  const server = createServer(async (request, response) => {
    requests++;
    assert.equal(request.method, 'POST');
    assert.equal(request.url, '/chat/completions');
    for await (const _bytes of request) { /* Consume this original request. */ }
    response.writeHead(200, {'content-type': 'application/octet-stream',
      connection: 'close', ...(chunked ? {} : {'content-length': 1300})});
    response.flushHeaders();
    response.write(first);
    // The second fragment cannot be coalesced with the first before its actual
    // parser/body push. No HWM or arbitrary timer is used as the queue oracle.
    await firstPushed;
    if (!response.destroyed) response.end(second);
  });
  server.on('connection', socket => {
    sockets.add(socket); socket.once('close', () => sockets.delete(socket));
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
    });
    const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
    const limits = {maxBytes, maxChunkBytes, maxChunks: 32,
      maxHeaderBytes: 16384, observedHeaders: ['content-type']};
    const fetch = createOriginalUndiciFetch({endpoint,
      requestLimits: {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16},
      responseLimits: limits, physicalAcquisitionLimits: {
        maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
    call = prepareOriginalUndiciFetch(fetch, endpoint, {method: 'POST', body: '{}',
      headers: [], redirect: 'error', signal: new AbortController().signal}, limits);
    const response = await call.invoke();
    if (overflow) await bodyFailed;
    else await secondPushed;
    assert.equal(response.status, 200);
    assert.deepEqual(pushed, overflow ? [400] : [400, 900]);
    const queuedBeforeRead = observedBody.readableLength;
    if (!overflow) {
      assert.equal(queuedBeforeRead, 1300);
      assert.ok(queuedBeforeRead > maxChunkBytes, 'HWM is not a hard queue bound');
      assert.ok(queuedBeforeRead <= maxBytes, 'upstream parser limit is separate');
    }
    const captured = await readBoundedInferResponse(response, limits);
    assert.equal(captured.transportComplete, false);
    assert.equal(captured.issue, overflow ? 'InferResponseReadFailed' : 'InferResponseChunkLimit');
    assert.equal(captured.body.byteLength, 0);
    if (overflow) {
      assert.deepEqual(bodyErrors, ['UND_ERR_RES_EXCEEDED_MAX_SIZE']);
      assert.deepEqual(concats, [], 'oversize fragment never entered the body queue');
    } else {
      assert.equal(captured.observedBytes, 1300);
      assert.equal(concats.length, 1, 'the rejected observation has a real concat');
      assert.equal(concats[0].length, 1300);
      assert.ok(concats[0].backingBytes >= 1300);
    }
    assert.equal(await captured.readerRetirement, true);
    assert.equal(await call.cleanup(), true);
    assert.equal(await call.cleanup(), true);
    assert.equal(requests, 1);
    assert.throws(() => call.invoke(), {code: 'UndiciOriginalTransportRetired'});
    t.diagnostic(JSON.stringify({scenario: overflow ? 'upstream-body-overflow' : 'rejected-body-concat',
      chunked, maxBytes, maxChunkBytes, pushed, queuedBeforeRead, concats, bodyErrors,
      requests, normalNumericProfile: null, publicE2E: 0}));
  } finally {
    try {
      if (call !== undefined) assert.equal(await call.cleanup(), true);
    } finally {
      BodyReadable.prototype.push = push; Buffer.allocUnsafe = allocate;
      for (const socket of sockets) socket.destroy();
      await new Promise(resolve => server.close(resolve));
    }
  }
}

test('rejected original body concat exceeds HWM but not the upstream response extent', async t => {
  await exercise(t, {maxBytes: 8192, overflow: false, chunked: false});
});

test('Content-Length overflow is refused before the original BodyReadable push', async t => {
  await exercise(t, {maxBytes: 1024, overflow: true, chunked: false});
});

test('chunked overflow is refused before the original BodyReadable push', async t => {
  await exercise(t, {maxBytes: 1024, overflow: true, chunked: true});
});
