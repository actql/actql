import assert from 'node:assert/strict';
import test from 'node:test';
import {captureSourceResponseCustody} from './source-response-custody.mjs';

const failure = () => Object.assign(new TypeError('OriginalVendorCustodyFailure'),
  {code: 'OriginalVendorCustodyFailure'});
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};

test('standard response custody retains the exact receiver and original response with synchronous Unit', () => {
  assert.equal(captureSourceResponseCustody(undefined), undefined);
  const response = {}, calls = [];
  const holder = Object.freeze({retain(value) {calls.push([this, value]);}});
  const retain = captureSourceResponseCustody(holder, () => assert.fail('valid original holder'));
  assert.equal(retain(response), undefined, 'the valid synchronous path does not return a Promise');
  assert.deepEqual(calls, [[holder, response]]);
  assert.strictEqual(calls[0][0], holder);
  assert.strictEqual(calls[0][1], response);
});

test('response custody refuses mutable extra accessor and proxy holders without invoking them', () => {
  let callbacks = 0, traps = 0;
  const method = () => {callbacks++;};
  const accessor = Object.freeze({get retain() {callbacks++; return method;}});
  const inherited = Object.freeze(Object.create({get retain() {callbacks++; return method;}}));
  const proxy = new Proxy(Object.freeze({retain: method}), {
    get() {traps++; assert.fail('proxy get');},
    ownKeys() {traps++; assert.fail('proxy ownKeys');},
    getOwnPropertyDescriptor() {traps++; assert.fail('proxy descriptor');},
    isExtensible() {traps++; assert.fail('proxy extensibility');},
  });
  for (const holder of [null, false, 0, 'holder', method, {}, {retain: method}, accessor, inherited,
    Object.freeze({retain: 1}), Object.freeze({retain: method, extra: undefined}),
    Object.freeze({retain: method, [Symbol('extra')]: true}), proxy]) {
    const original = failure();
    assert.throws(() => captureSourceResponseCustody(holder, () => original), cause => cause === original);
  }
  assert.equal(callbacks, 0);
  assert.equal(traps, 0);
});

test('a synchronous original retain throw stays primary without return validation', () => {
  const original = new Error('original retain failure');
  const retain = captureSourceResponseCustody(Object.freeze({retain() {throw original;}}),
    () => assert.fail('a thrown callback has no returned borrow to validate'));
  assert.throws(() => retain({}), cause => cause === original);
});

test('non-Unit response custody stays joined until its exact returned borrow settles then refuses', async () => {
  for (const rejected of [false, true]) {
    const borrow = deferred(), original = failure(), response = {};
    let invalidCalls = 0, settled = false;
    const holder = Object.freeze({retain(value) {
      assert.strictEqual(this, holder); assert.strictEqual(value, response);
      return borrow.promise;
    }});
    const retain = captureSourceResponseCustody(holder, () => {invalidCalls++; return original;});
    const pending = retain(response);
    const rejectedReturn = assert.rejects(pending, cause => cause === original).then(() => {settled = true;});
    await Promise.resolve();
    assert.equal(settled, false);
    assert.equal(invalidCalls, 0, 'a pending borrow cannot be discarded by a protocol refusal');
    if (rejected) borrow.reject(new Error('invalid callback return rejection'));
    else borrow.resolve(undefined);
    await rejectedReturn;
    assert.equal(invalidCalls, 1);
  }
});

test('every non-Unit result refuses including resolved Unit promises and scalar values', async () => {
  for (const returned of [true, false, 0, null, {}, Promise.resolve(undefined)]) {
    const original = failure();
    const retain = captureSourceResponseCustody(Object.freeze({retain() {return returned;}}), () => original);
    await assert.rejects(retain({}), cause => cause === original);
  }
  let joined = 0;
  const original = failure();
  const retain = captureSourceResponseCustody(Object.freeze({retain() {
    return {then(resolve) {joined++; resolve(undefined);}};
  }}), () => original);
  await assert.rejects(retain({}), cause => cause === original);
  assert.equal(joined, 1, 'the exact invalid thenable still completes its borrowed work');
});

test('a rejected custody borrow preserves its original Unknown outcome and pending cleanup carrier', async () => {
  const borrow = deferred(), cleanupHandle = {status: () => ({pending: true})};
  const original = Object.assign(new Error('original retained response failure'), {
    code: 'OriginalResponseCustodyFailure', outcome: 'unknown', cleanupPending: true, cleanupHandle,
  });
  let invalidCalls = 0;
  const retain = captureSourceResponseCustody(Object.freeze({retain() {return borrow.promise;}}),
    () => {invalidCalls++; return failure();});
  const pending = retain({});
  const checked = assert.rejects(pending, cause => {
    assert.strictEqual(cause, original);
    assert.strictEqual(cause.cleanupHandle, cleanupHandle);
    assert.equal(cause.outcome, 'unknown');
    assert.equal(cause.cleanupPending, true);
    return true;
  });
  borrow.reject(original);
  await checked;
  assert.equal(invalidCalls, 0, 'an original rejected borrow is already a failure, never a replacement error');
});
