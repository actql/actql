import assert from 'node:assert/strict';
import {Duplex} from 'node:stream';
import {createRequire} from 'node:module';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';

// Same actual Undici parser; deterministic native-callback fixture only.
// Real TCP/pinned SDK paths are separate existing transport tests. This does
// not execute TLS or issue original Ledger/Entry/Store funding or authority.
const require = createRequire(import.meta.url);
const undici = require('undici');
const originalBuilder = undici.buildConnector;
let nextSocket, selected;
undici.buildConnector = options => {
  selected = options;
  return (_request, callback) => {
    const socket = nextSocket;
    queueMicrotask(() => callback(null, socket));
    return socket;
  };
};
let physical;
try { physical = await import('./_internal/original-undici-transport.mjs'); }
finally { undici.buildConnector = originalBuilder; }
const endpoint = 'http://fixture.invalid/chat/completions';
const wire = 'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\nA';
const responseLimits = {maxBytes: 256, maxChunkBytes: 256, maxChunks: 8,
  maxHeaderBytes: 1024, observedHeaders: []};

async function fixture(t, changes = {}) {
  let written = false, closes = 0;
  nextSocket = new Duplex({read() {}, write(_bytes, _encoding, callback) {
    written = true; callback();
  }});
  const socket = nextSocket;
  socket.on('error', () => {});
  socket.once('close', () => { closes++; });
  const fetch = physical.createOriginalUndiciFetch({endpoint,
    requestLimits: {maxBytes: 64, maxHeaderBytes: 128, maxHeaders: 4}, responseLimits,
    physicalAcquisitionLimits: {maxPlaintextBytes: 65536,
      maxBorrowedBackingBytes: 131072, maxReads: 64, ...changes}});
  const call = physical.prepareOriginalUndiciFetch(fetch, endpoint,
    {method: 'POST', body: '{}', redirect: 'error', headers: [],
      signal: new AbortController().signal}, responseLimits);
  const input = selected.onread;
  const emit = input.callback;
  const buffer = input.buffer;
  t.after(async () => { assert.equal(await call.cleanup(), true); });
  const pending = call.invoke();
  pending.catch(() => {});
  for (let index = 0; !written && index < 10; index++) await turn();
  assert.equal(written, true);
  return {call, socket, pending, input, buffer,
    emit: (length, supplied = buffer, receiver = socket) => Reflect.apply(emit, receiver, [length, supplied]),
    closes: () => closes};
}

test('native input is a single exact dedicated backing fixed before invoke', async t => {
  const f = await fixture(t);
  assert.equal(f.buffer.byteLength, 256);
  assert.equal(f.buffer.buffer.byteLength, 256);
  f.buffer.write(wire);
  assert.equal(f.emit(Buffer.byteLength(wire)), true);
  // The original native listener may refill immediately before parser/body
  // consumers run. Their queued bytes must not alias this reusable buffer.
  f.buffer.fill(90);
  const response = await f.pending;
  const reader = response.body.getReader();
  const chunk = await reader.read();
  assert.equal(Buffer.from(chunk.value).toString(), 'A');
  assert.notStrictEqual(chunk.value.buffer, f.buffer.buffer);
  assert.equal((await reader.read()).done, true);
  reader.releaseLock();
  assert.equal(await f.call.cleanup(), true);
  assert.equal(f.closes(), 1);
  assert.equal(f.input.buffer, undefined, 'drop our own alias only after actual closure');
});

test('plaintext excess refuses before any output copy or socket queue', async t => {
  const f = await fixture(t, {maxPlaintextBytes: 1});
  const allocate = Buffer.allocUnsafeSlow;
  let allocations = 0;
  Buffer.allocUnsafeSlow = length => { allocations++; return allocate(length); };
  try { assert.equal(f.emit(2), false); }
  finally { Buffer.allocUnsafeSlow = allocate; }
  assert.equal(allocations, 0);
  assert.equal(f.socket.readableLength, 0);
  await assert.rejects(f.pending, {code: 'UndiciOriginalAcquisitionPlaintextExceeded'});
  assert.equal(await f.call.cleanup(), true);
});

test('input plus dedicated output copy must fit the original backing declaration', async t => {
  const f = await fixture(t, {maxBorrowedBackingBytes: 256});
  assert.equal(f.buffer.byteLength, 256);
  assert.equal(f.emit(1), false);
  assert.equal(f.socket.readableLength, 0);
  await assert.rejects(f.pending, {code: 'UndiciOriginalAcquisitionBackingExceeded'});
  assert.equal(await f.call.cleanup(), true);
});

test('copied input view cannot feed the original callback', async t => {
  const f = await fixture(t);
  assert.equal(f.emit(1, Buffer.alloc(256)), false);
  assert.equal(f.socket.readableLength, 0);
  await assert.rejects(f.pending, {code: 'UndiciOriginalAcquisitionShapeRefused'});
  assert.equal(await f.call.cleanup(), true);
});

test('foreign socket cannot feed the original native callback', async t => {
  const f = await fixture(t);
  assert.equal(f.emit(1, f.buffer, {}), false);
  assert.equal(f.socket.readableLength, 0);
  await assert.rejects(f.pending, {code: 'UndiciOriginalAcquisitionShapeRefused'});
  assert.equal(await f.call.cleanup(), true);
});

test('exact input plus output-copy extent preserves the full original response', async t => {
  const length = Buffer.byteLength(wire);
  const f = await fixture(t, {maxBorrowedBackingBytes: 256 + length});
  f.buffer.write(wire);
  assert.equal(f.emit(length), true);
  const reader = (await f.pending).body.getReader();
  assert.equal(Buffer.from((await reader.read()).value).toString(), 'A');
  assert.equal((await reader.read()).done, true);
  reader.releaseLock();
  assert.equal(await f.call.cleanup(), true);
});

test('unknown physical close keeps the same input and cleanup Promise', async t => {
  const f = await fixture(t);
  const destroy = f.socket._destroy;
  let finish;
  f.socket._destroy = (error, callback) => { finish = () => Reflect.apply(destroy, f.socket, [error, callback]); };
  const cleanup = f.call.cleanup();
  assert.strictEqual(f.call.cleanup(), cleanup);
  await turn();
  assert.equal(f.closes(), 0);
  assert.strictEqual(f.input.buffer, f.buffer);
  finish();
  assert.equal(await cleanup, true);
  assert.equal(f.closes(), 1);
});

test('cancel close pending retains input until the same actual destroy completes', async t => {
  const f = await fixture(t);
  const originalDestroy = f.socket._destroy;
  let finish;
  f.socket._destroy = function (error, callback) {
    finish = () => Reflect.apply(originalDestroy, f.socket, [error, callback]);
  };
  const cleanup = f.call.cleanup();
  let settled = false;
  cleanup.then(() => { settled = true; });
  await turn();
  assert.equal(settled, false);
  assert.strictEqual(f.input.buffer, f.buffer);
  assert.equal(f.closes(), 0);
  assert.equal(f.emit(1), false, 'cancelled original input cannot queue another copy');
  finish();
  assert.equal(await cleanup, true);
  assert.equal(f.closes(), 1);
  assert.equal(f.input.buffer, undefined);
  assert.throws(() => f.call.invoke(), {code: 'UndiciOriginalTransportRetired'});
});
