import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {Duplex} from 'node:stream';
import {setImmediate as turn} from 'node:timers/promises';

// Actual pinned Undici parser, controlled original Duplex, no TCP/TLS/SDK.
// This witnesses checks after Node acquisition, not a funded first allocator.
const require = createRequire(import.meta.url);
const undici = require('undici');
const buildConnector = undici.buildConnector;
let selectedSocket, connections = 0;
undici.buildConnector = () => (_options, callback) => {
  const socket = selectedSocket;
  connections++;
  queueMicrotask(() => callback(null, socket));
  return socket;
};
let physical;
try { physical = await import('./_internal/original-undici-transport.mjs'); }
finally { undici.buildConnector = buildConnector; }
const endpoint = 'http://fixture.invalid/chat/completions';
const responseLimits = {maxBytes: 8192, maxChunkBytes: 8192, maxChunks: 32,
  maxHeaderBytes: 16384, observedHeaders: []};
const limits = {maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64};
const select = physicalAcquisitionLimits => physical.createOriginalUndiciFetch({endpoint,
  requestLimits: {maxBytes: 64, maxHeaderBytes: 128, maxHeaders: 4},
  responseLimits, physicalAcquisitionLimits});
const exactBuffer = text => {
  const bytes = Buffer.allocUnsafeSlow(Buffer.byteLength(text));
  bytes.write(text);
  return bytes;
};
const wire = 'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\nA';

async function exercise(t, declaration, packets) {
  let responded = false, closes = 0;
  const socket = new Duplex({read() {}, write(_bytes, _encoding, callback) {
    callback();
    if (responded) return;
    responded = true;
    void (async () => {
      for (const packet of packets) {
        await turn();
        if (socket.destroyed) return;
        socket.push(packet);
      }
    })();
  }});
  socket.on('error', () => {});
  socket.once('close', () => { closes++; });
  selectedSocket = socket;
  const before = connections;
  const fetch = select(declaration);
  const call = physical.prepareOriginalUndiciFetch(fetch, endpoint,
    {method: 'POST', body: '{}', headers: [], redirect: 'error',
      signal: new AbortController().signal}, responseLimits);
  t.after(async () => { assert.equal(await call.cleanup(), true); });
  let result;
  try {
    const response = await call.invoke();
    const reader = response.body.getReader();
    const parts = [];
    for (let index = 0; index < 8; index++) {
      const next = await reader.read();
      if (next.done) {
        reader.releaseLock();
        result = {body: Buffer.concat(parts).toString()};
        break;
      }
      parts.push(next.value);
    }
    assert.ok(result);
  } catch (error) { result = {error: error.code}; }
  assert.equal(await call.cleanup(), true);
  assert.equal(await call.cleanup(), true);
  assert.equal(closes, 1);
  assert.equal(connections, before + 1);
  assert.throws(() => call.invoke(), {code: 'UndiciOriginalTransportRetired'});
  return result;
}

test('acquisition DATA is required closed positive and does not invoke accessors', () => {
  for (const value of [undefined, null, {}, {...limits, extra: 1},
    {'maxBorrowedBackingBytes,maxPlaintextBytes,maxReads': 1},
    {...limits, maxReads: 0}, {...limits, maxReads: 1.5},
    {...limits, maxPlaintextBytes: 2147483648}]) {
    assert.throws(() => select(value), {code: 'UndiciOriginalAcquisitionLimitsUnavailable'});
  }
  let gets = 0;
  const accessor = {...limits};
  Object.defineProperty(accessor, 'maxReads', {enumerable: true, get() { gets++; return 1; }});
  assert.throws(() => select(accessor), {code: 'UndiciOriginalAcquisitionLimitsUnavailable'});
  assert.equal(gets, 0);
});

test('private acquisition snapshot reads DATA descriptors once and ignores later input mutation', () => {
  const source = {...limits};
  const reads = [];
  const proxy = new Proxy(source, {
    get() { assert.fail('No late Proxy property read'); },
    getOwnPropertyDescriptor(target, key) {
      reads.push(key); return Object.getOwnPropertyDescriptor(target, key);
    },
  });
  const snapshot = physical.fixedOriginalAcquisitionLimits(proxy);
  source.maxReads = 1;
  assert.deepEqual(snapshot, limits);
  assert.equal(Object.isFrozen(snapshot), true);
  assert.strictEqual(physical.fixedOriginalAcquisitionLimits(snapshot), snapshot);
  assert.deepEqual(reads, ['maxBorrowedBackingBytes', 'maxPlaintextBytes', 'maxReads']);
});

test('exact plaintext and backing limits admit the same original read and retire once', async t => {
  const packet = exactBuffer(wire);
  assert.deepEqual(await exercise(t, {maxPlaintextBytes: packet.length,
    maxBorrowedBackingBytes: packet.length, maxReads: 1}, [packet]), {body: 'A'});
});

test('plaintext limit minus one refuses framing before parser and preserves physical cleanup', async t => {
  const packet = exactBuffer(wire);
  assert.deepEqual(await exercise(t, {...limits, maxPlaintextBytes: packet.length - 1}, [packet]),
    {error: 'UndiciOriginalAcquisitionPlaintextExceeded'});
});

test('small emitted view cannot conceal a larger original backing', async t => {
  const original = Buffer.allocUnsafeSlow(8192);
  original.write(wire);
  assert.deepEqual(await exercise(t, {...limits, maxBorrowedBackingBytes: 8191},
    [original.subarray(0, Buffer.byteLength(wire))]),
  {error: 'UndiciOriginalAcquisitionBackingExceeded'});
});

test('framing-only large chunk exceeds acquisition while body remains one byte', async t => {
  const packet = exactBuffer('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n' +
    `1;${'x'.repeat(16384)}\r\nA\r\n0\r\n\r\n`);
  assert.deepEqual(await exercise(t, {...limits, maxPlaintextBytes: 8192}, [packet]),
    {error: 'UndiciOriginalAcquisitionPlaintextExceeded'});
});

test('same backing across two reads is counted once but each read consumes its own bound', async t => {
  const packet = exactBuffer(wire);
  const parts = [packet.subarray(0, packet.length - 1), packet.subarray(packet.length - 1)];
  assert.deepEqual(await exercise(t, {maxPlaintextBytes: packet.length,
    maxBorrowedBackingBytes: packet.length, maxReads: 2}, parts), {body: 'A'});
});

test('second original read refuses when read count is exhausted without another connection', async t => {
  const packet = exactBuffer(wire);
  assert.deepEqual(await exercise(t, {...limits, maxReads: 1},
    [packet.subarray(0, packet.length - 1), packet.subarray(packet.length - 1)]),
  {error: 'UndiciOriginalAcquisitionReadsExceeded'});
});

test('distinct backing allocation accumulates even after its earlier read completed', async t => {
  const header = exactBuffer(wire.slice(0, -1));
  const body = Buffer.allocUnsafeSlow(header.length);
  body.write('A');
  assert.deepEqual(await exercise(t, {...limits, maxBorrowedBackingBytes: header.length},
    [header, body.subarray(0, 1)]), {error: 'UndiciOriginalAcquisitionBackingExceeded'});
});
