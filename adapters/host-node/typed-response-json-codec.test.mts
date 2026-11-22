import test from 'node:test';
import assert from 'node:assert/strict';
import {encodeTypedResponseJson} from './typed-response-json-codec.mjs';

test('identity response encoder preserves Unicode, wire references, sparse arrays and JSON values', () => {
  for (const value of [[{content: {identity: 'sha256:' + 'a'.repeat(64)}, path: '\u0000😀é\ud800', n: -1.2e-50}],
    [], [null, true, false, 0, -0, 1e100], Array(12), [{empty: {}, quote: '"\\'}]]) {
    const encoded = encodeTypedResponseJson(value, 1048576);
    assert.deepEqual(JSON.parse(encoded as unknown as string), JSON.parse(JSON.stringify(value)));
  }
});

test('identity response encoder refuses getters and proxies without invoking them', () => {
  let called = 0;
  const accessor = Object.defineProperty({}, 'value', {enumerable: true, get() {called++;}});
  for (const value of [[accessor], [new Proxy({}, {ownKeys() {called++;return [];}})], [{x: undefined}], [Infinity]]) {
    assert.throws(() => encodeTypedResponseJson(value, 1048576));
  }
  assert.equal(called, 0);
  assert.throws(() => encodeTypedResponseJson([{value: 'a'.repeat(40)}], 8), {code: 'InstalledRowPageLimit'});
});

test('identity response encoder ignores Object and Array prototype toJSON hooks', () => {
  let called = 0;
  const object = Object.getOwnPropertyDescriptor(Object.prototype, 'toJSON');
  const array = Object.getOwnPropertyDescriptor(Array.prototype, 'toJSON');
  try {
    Object.defineProperty(Object.prototype, 'toJSON', {configurable: true, get() {called++; return () => 'changed';}});
    Object.defineProperty(Array.prototype, 'toJSON', {configurable: true, get() {called++; return () => 'changed';}});
    assert.deepEqual(JSON.parse(encodeTypedResponseJson([{value: 'original'}], 1024) as unknown as string), [{value: 'original'}]);
    assert.equal(called, 0);
  } finally {
    if (object) Object.defineProperty(Object.prototype, 'toJSON', object);
    else delete (Object.prototype as {toJSON?: unknown}).toJSON;
    if (array) Object.defineProperty(Array.prototype, 'toJSON', array);
    else delete (Array.prototype as {toJSON?: unknown}).toJSON;
  }
});
