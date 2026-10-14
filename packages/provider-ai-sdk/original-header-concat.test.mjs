// Actual parser allocation-order witness, not a complete capacity declaration.
import assert from 'node:assert/strict';
import test from 'node:test';
import net from 'node:net';
import {createRequire} from 'node:module';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch} from
  './_internal/original-undici-transport.mjs';

const require = createRequire(import.meta.url);

test('original fragmented header concat precedes overflow refusal and same socket cleanup', async t => {
  assert.equal(process.versions.node, '22.22.0');
  assert.equal(require('undici/package.json').version, '7.30.0');
  const firstValue = 'A'.repeat(100), nextValue = 'B'.repeat(2048);
  const maxHeaderBytes = 256;
  let resolveFirstRead;
  const firstRead = new Promise(resolve => { resolveFirstRead = resolve; });
  let port, requests = 0, connections = 0, clientCloses = 0, clientSocket, call;
  const sockets = new Set(), concats = [];
  const read = net.Socket.prototype.read, concat = Buffer.concat;
  net.Socket.prototype.read = function(...args) {
    const bytes = Reflect.apply(read, this, args);
    if (this.remotePort === port) {
      if (clientSocket === undefined) {
        clientSocket = this;
        this.once('close', () => { clientCloses++; });
      }
      assert.equal(this, clientSocket);
      if (bytes?.includes(Buffer.from(firstValue))) resolveFirstRead();
    }
    return bytes;
  };
  Buffer.concat = function(chunks, ...args) {
    const bytes = Reflect.apply(concat, Buffer, [chunks, ...args]);
    if (new Error().stack.includes('Parser.onHeaderValue')) {
      concats.push({inputs: chunks.map(chunk => chunk.length), length: bytes.length,
        backingBytes: bytes.buffer.byteLength});
    }
    return bytes;
  };
  const server = net.createServer(socket => {
    connections++;
    sockets.add(socket);
    socket.on('error', () => {});
    socket.once('close', () => sockets.delete(socket));
    let request = '';
    socket.on('data', async bytes => {
      request += bytes.toString('latin1');
      if (!request.includes('\r\n\r\n')) return;
      assert.equal(requests++, 0, 'the original request is never resent');
      socket.removeAllListeners('data');
      socket.write(`HTTP/1.1 200 OK\r\nx-probe: ${firstValue}`);
      // Only send the continuation after the first original socket read. Its
      // synchronous parser call finishes before this Promise continuation.
      await firstRead;
      if (!socket.destroyed) socket.end(`${nextValue}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`);
    });
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
    });
    port = server.address().port;
    const endpoint = `http://127.0.0.1:${port}/chat/completions`;
    const limits = {maxBytes: 8192, maxChunkBytes: 8192, maxChunks: 32,
      maxHeaderBytes, observedHeaders: []};
    const fetch = createOriginalUndiciFetch({endpoint,
      requestLimits: {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16},
      responseLimits: limits, physicalAcquisitionLimits: {
        maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
    call = prepareOriginalUndiciFetch(fetch, endpoint, {method: 'POST', body: '{}',
      headers: [], redirect: 'error', signal: new AbortController().signal}, limits);
    await assert.rejects(call.invoke(), {code: 'UND_ERR_HEADERS_OVERFLOW'});
    assert.equal(concats.length, 1);
    assert.deepEqual(concats[0].inputs, [100, 2048]);
    assert.equal(concats[0].length, 2148);
    assert.ok(concats[0].length > maxHeaderBytes, 'header cap was not a preallocation bound');
    assert.ok(concats[0].backingBytes >= concats[0].length);
    // The actual original client socket was observed through the same read
    // method before parsing. Track physical closure, not its destroyed flag.
    assert.equal(await call.cleanup(), true);
    assert.equal(await call.cleanup(), true);
    assert.equal(requests, 1);
    assert.equal(connections, 1);
    assert.equal(clientCloses, 1);
    assert.throws(() => call.invoke(), {code: 'UndiciOriginalTransportRetired'});
    t.diagnostic(JSON.stringify({maxHeaderBytes, concats, requests, connections, clientCloses,
      normalNumericProfile: null, publicE2E: 0}));
  } finally {
    try {
      if (call !== undefined) assert.equal(await call.cleanup(), true);
    } finally {
      net.Socket.prototype.read = read; Buffer.concat = concat;
      for (const socket of sockets) socket.destroy();
      await new Promise(resolve => server.close(resolve));
    }
  }
});
