// Real pinned Undici and Node streams, controlled Duplex only. This is an
// acquisition/alias witness, not an installed Model, TLS or capacity grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {Duplex} from 'node:stream';
import {setImmediate as turn} from 'node:timers/promises';
import {createRequire} from 'node:module';
import {Client} from 'undici';

const require = createRequire(import.meta.url);

test('chunk framing can retain larger original backing than accepted response bytes', async t => {
  assert.equal(process.version, 'v22.22.0');
  assert.equal(require('undici/package.json').version, '7.30.0');
  // Three independently bounded plaintext chunks, each <= the pinned TLS
  // ClearOut chunk extent16384. This is NOT a real TLS pump or its queue bound.
  const packets = ['A', 'B', 'C'].map(value => {
    const packet = Buffer.alloc(16384);
    assert.equal(packet.write(`1;${'x'.repeat(16377)}\r\n${value}\r\n`), 16384);
    return packet;
  });
  let responded = false, connections = 0, closes = 0;
  const socket = new Duplex({readableHighWaterMark: 65536,
    read() {},
    write(_bytes, _encoding, callback) {
      callback();
      if (responded) return;
      responded = true;
      // Like a native producer's synchronous emission, complete this finite
      // batch before Promise consumers can read the response body.
      queueMicrotask(() => {
        socket.push(Buffer.from('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'));
        for (const packet of packets) socket.push(packet);
        socket.push(Buffer.from('0\r\n\r\n'));
      });
    },
  });
  socket.on('error', () => {});
  socket.once('close', () => { closes++; });
  const client = new Client('http://fixture.invalid', {allowH2: false,
    pipelining: 0, maxHeaderSize: 16384, maxResponseSize: 8192,
    connect(_options, callback) { connections++; callback(null, socket); },
  });
  t.after(async () => {
    await client.destroy();
    if (!socket.closed) { socket.destroy(); await turn(); }
    assert.equal(closes, 1);
  });
  const response = await client.request({method: 'GET', path: '/',
    highWaterMark: 8192, idempotent: false});
  await turn();
  assert.equal(connections, 1);
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.readableLength, 3);
  const queued = response.body._readableState.buffer.filter(value => value !== null);
  assert.equal(queued.length, 3);
  assert.deepEqual(queued.map(value => value.toString()), ['A', 'B', 'C']);
  const backings = new Set(queued.map(value => value.buffer));
  assert.ok([...backings].some(backing => backing.byteLength > 8192));
  t.diagnostic(JSON.stringify({acceptedBodyBytes: 3, bodyChunkViews: 3,
    distinctBorrowedBackings: backings.size,
    backingExtents: [...backings].map(backing => backing.byteLength),
    sourcePlaintextChunks: 3, sourcePlaintextExtent: 16384,
    requestCount: 1, TCP: 0, TLS: 0, Provider: 0,
    qualification: 'Controlled emission, not a normal socket queue upper bound.'}));
  assert.deepEqual(response.body.read(), Buffer.from('ABC'));
  await client.destroy();
  await turn();
  assert.equal(closes, 1);
  // Queued views intentionally retained by this diagnostic may still borrow
  // their original backing after Client ACK. It is not raw/Store retirement.
  assert.deepEqual(queued.map(value => value.toString()), ['A', 'B', 'C']);
});
