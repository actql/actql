import assert from 'node:assert/strict';
import test from 'node:test';
import {captureInstalledSourceServices} from './installed-host-services.mjs';

const names = ['sourceReaderImplementationProfile', 'sourceReaderImplementation', 'openRowSite', 'createSourceReader'];

test('Source service snapshot captures four original methods and receiver before metadata await', async () => {
  const receiver = {}, calls = [], results = names.map(() => ({}));
  for (const [index, name] of names.entries()) receiver[name] = function(...args) {
    assert.equal(this, receiver); calls.push([name, ...args]); return results[index];
  };
  const unavailable = () => {assert.fail('healthy service');};
  const service = captureInstalledSourceServices(receiver, unavailable);
  assert.equal(Object.isFrozen(service), true); assert.deepEqual(calls, []);
  await Promise.resolve();
  for (const name of names) receiver[name] = () => assert.fail('replacement service method');
  for (const [index, name] of names.entries()) {
    const argument = {};
    assert.equal(service(name, argument), results[index]);
    assert.equal(calls[index][0], name); assert.equal(calls[index][1], argument);
  }
  assert.equal(calls.length, 4);
});

test('Source service snapshot rejects missing inherited accessor and proxy methods without callbacks', () => {
  let traps = 0, factoryCalls = 0;
  const original = Object.assign(new Error('connector unavailable'), {code: 'OriginalConnectorUnavailable'});
  const unavailable = () => {factoryCalls++; return original;};
  const healthy = Object.fromEntries(names.map(name => [name, () => assert.fail('no service operation')]));
  const accessor = {...healthy};
  Object.defineProperty(accessor, names[0], {get() {traps++; return healthy[names[0]];}});
  const revoked = Proxy.revocable(healthy, {}); revoked.revoke();
  for (const input of [undefined, null, {}, Object.create(healthy), accessor,
    {...healthy, openRowSite: 1}, new Proxy(healthy, {ownKeys() {traps++; return [];},
      getOwnPropertyDescriptor() {traps++;}}), revoked.proxy]) {
    assert.throws(() => captureInstalledSourceServices(input, unavailable), error => error === original);
  }
  const service = captureInstalledSourceServices(healthy, unavailable);
  for (const name of ['constructor', '__proto__', 'unknown', Symbol('method'), {toString() {traps++; return names[0];}}]) {
    assert.throws(() => service(name), error => error === original);
  }
  assert.equal(traps, 0); assert.equal(factoryCalls, 13);
  const thrown = {};
  assert.throws(() => captureInstalledSourceServices({}, () => {throw thrown;}), error => error === thrown);
});

test('Source service invoker preserves exact Promise failure and cleanup carrier without wrapping', async () => {
  const original = Object.freeze({code: 'OriginalPending', cleanupPending: true, cleanupHandle: {}});
  let reject;
  const pending = new Promise((_resolve, fail) => {reject = fail;});
  const receiver = Object.fromEntries(names.map(name => [name, function() {
    assert.equal(this, receiver); return pending;
  }]));
  receiver.createSourceReader = function() {assert.equal(this, receiver); throw original;};
  const service = captureInstalledSourceServices(receiver, () => assert.fail('healthy service'));
  const returned = service('openRowSite', {});
  assert.equal(returned, pending);
  const observed = assert.rejects(returned, error => error === original);
  reject(original); await observed;
  assert.throws(() => service('createSourceReader', {}), error => error === original);
});
