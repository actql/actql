import assert from 'node:assert/strict';
import test from 'node:test';
import {captureLocalFileWriteConstructionProfile as capture} from './root-file-writer-profile.mjs';
import {localProjectFilesystem} from '../../../host-node/local-files-native.mjs';
const value = Object.freeze({nativeOriginalBytes: 6000, maxRootBytes: 4096,
  maxNameBytes: 1024, maxDepth: 130, writeQuantumBytes: 65536});
const failure = {code: 'LocalFileWriteConstructionUnavailable'};

test('Local writer captures one native receiver call as immutable DATA', () => {
  let calls = 0;
  const native = Object.freeze({localFileWriteConstructionProfile() {
    assert.strictEqual(this, native); calls++; return value;
  }});
  const actual = capture(native);
  assert.equal(calls, 1); assert.deepEqual(actual, value);
  assert(Object.isFrozen(actual)); assert.notStrictEqual(actual, value);
});

test('Local writer refuses missing, accessor, asynchronous and malformed construction DATA', () => {
  let called = 0;
  for (const native of [null, {}, new Proxy({}, {}),
    {get localFileWriteConstructionProfile() {called++; return () => value;}},
    {async localFileWriteConstructionProfile() {called++; return value;}}]) {
    assert.throws(() => capture(native), failure);
  }
  assert.equal(called, 0);
  for (const result of [undefined, {...value}, Object.freeze({...value, extra: 1}),
    Object.freeze({...value, nativeOriginalBytes: 0}), Object.freeze({...value, maxDepth: -1}),
    Object.freeze({...value, writeQuantumBytes: 1.5}), new Proxy(value, {})]) {
    assert.throws(() => capture({localFileWriteConstructionProfile: () => result}), failure);
  }
});

test('normal selected Local native image supplies its actual descriptor and writer bounds', () => {
  const native = localProjectFilesystem(), actual = capture(native);
  assert.equal(actual.maxRootBytes, 4096); assert.equal(actual.maxNameBytes, 1024);
  assert.equal(actual.maxDepth, 130); assert.equal(actual.writeQuantumBytes, 65536);
  // Real descriptor storage also contains the two original name arrays. Its
  // platform-dependent stat/FD fields must not be guessed in JavaScript.
  assert(actual.nativeOriginalBytes > actual.maxRootBytes + 1 + actual.maxNameBytes + 1);
  assert.deepEqual(capture(native), actual);
});
