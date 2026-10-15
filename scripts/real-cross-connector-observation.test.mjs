// Inert counter/allowance controls only. No actual HTTP or database is used.
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import test from 'node:test';
import {gcsMetadataRequestObserver} from './fixtures/real-cross-connector-observation.mjs';
const manifest = {bucket: 'actql-content-test', prefix: 'actql-content-test/',
  limits: {maxRequests: 10, maxResponseBytes: 1048576, maxDurationMs: 60000}};
const options = () => ({protocol: 'https:', hostname: 'storage.googleapis.com', method: 'GET',
  path: '/storage/v1/b/actql-content-test/o?prefix=actql-content-test%2F&maxResults=9&projection=noAcl'});

test('metadata observation preserves original request/response identity without reading secret headers', () => {
  const request = {}, response = new EventEmitter(), argument = options();
  Object.defineProperty(argument, 'headers', {get() { throw new Error('HeadersMustNotBeRead'); }});
  const observer = gcsMetadataRequestObserver({manifest, request(actual, callback) {
    assert.equal(actual, argument); callback(response); return request;
  }});
  let received;
  assert.equal(observer.request(argument, actual => {received = actual;}), request);
  assert.equal(received, response); response.emit('data', Buffer.alloc(23));
  assert.deepEqual(observer.observation(), {requests: 1, responses: 1, responseBytes: 23});
  observer.assertBounds();
});
for (const fault of ['content', 'bucket', 'prefix', 'method', 'extra-query', 'forbidden']) {
  test(`metadata counter refuses ${fault} before the real request`, () => {
    const value = options(); let calls = 0;
    if (fault === 'content') value.path = '/download/storage/v1/b/actql-content-test/o/a.csv?alt=media';
    if (fault === 'bucket') value.path = value.path.replace('actql-content-test/o', 'foreign/o');
    if (fault === 'prefix') value.path = value.path.replace('prefix=actql-content-test%2F', 'prefix=foreign');
    if (fault === 'method') value.method = 'POST';
    if (fault === 'extra-query') value.path += '&alt=media';
    const observer = gcsMetadataRequestObserver({manifest, forbidden: fault === 'forbidden',
      request() { calls++; }});
    assert.throws(() => observer.request(value, () => {})); assert.equal(calls, 0);
  });
}
test('the eleventh real metadata request is not sent', () => {
  let calls = 0;
  const observer = gcsMetadataRequestObserver({manifest, request() { calls++; }});
  for (let index = 0; index < 10; index++) observer.request(options(), () => {});
  assert.throws(() => observer.request(options(), () => {})); assert.equal(calls, 10);
});
test('actual response bytes and full campaign deadline remain independent observations', () => {
  const response = new EventEmitter(); let now = 0;
  const observer = gcsMetadataRequestObserver({manifest, now: () => now,
    request(_options, callback) { callback(response); }});
  observer.request(options(), () => {}); response.emit('data', Buffer.alloc(1048577));
  assert.throws(() => observer.assertBounds()); now = 60000;
  assert.throws(() => observer.request(options(), () => {}));
});

test('one global metadata deadline cancels only the original physical request and retains custody until close', () => {
  const controller = new AbortController(), physical = new EventEmitter();
  let destroyed = 0;
  physical.destroy = error => {assert.equal(error.code, 'GcsTestWindowExpired'); destroyed++;};
  const observer = gcsMetadataRequestObserver({manifest, signal: controller.signal, request: () => physical});
  assert.equal(observer.request(options(), () => {}), physical);
  assert.throws(() => observer.assertClosed()); controller.abort();
  assert.equal(destroyed, 1); assert.throws(() => observer.assertClosed());
  physical.emit('close'); observer.assertClosed();
  assert.throws(() => observer.request(options(), () => {}));
});
