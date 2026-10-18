import assert from 'node:assert/strict';
import test from 'node:test';
import {readSourceManagedOriginalInput as read} from './source-managed-original-input.mjs';

// Explicit reader bounds only. No Source supplier or physical grant is made.
const limits = {maxProperties: 32, maxNodes: 40, maxDepth: 6,
  maxStringCodeUnits: 128, maxTotalStringCodeUnits: 2048,
  maxArrayItems: 8, maxOpaqueAliases: 4, maxWork: 4096};
const unavailable = {code: 'NodeSourceManagedInputUnavailable'};

test('Source intake preserves exact text, all own option DATA and its immutable snapshot', () => {
  const options = {format: 'sql', parameters: null, extra: {original: 'not dropped'}};
  Object.defineProperty(options, 'hidden', {value: 7, enumerable: false});
  const result = read('aql', 'SELECT 1 AS n\r\n', options, limits);
  assert.equal(result.packet.kind, 'aql');
  assert.equal(result.packet.input, 'SELECT 1 AS n\r\n');
  assert.equal(result.packet.options.format, 'sql');
  assert.equal(result.packet.options.parameters, null);
  assert.equal(result.packet.options.extra.original, 'not dropped');
  assert.equal(result.packet.options.hidden, 7);
  assert.equal(Object.getOwnPropertyDescriptor(result.packet.options, 'hidden').enumerable, false);
  options.format = 'json'; options.extra.original = 'changed';
  assert.equal(result.packet.options.format, 'sql');
  assert.equal(result.packet.options.extra.original, 'not dropped');
  assert.equal(Object.isFrozen(result.packet.options), true);
  assert.equal(result.originalReferences.length, 0);
});

test('Source reader does not redefine invalid format or synthesize absent parameters', () => {
  const result = read('aql', 'original', {format: 'not-a-format'}, limits);
  assert.equal(result.packet.options.format, 'not-a-format');
  assert.equal(Object.hasOwn(result.packet.options, 'parameters'), false);
});

test('Source intake refuses Proxy and getter inputs without observing them', () => {
  let traps = 0;
  const proxy = new Proxy({}, {get() {traps++;}, ownKeys() {traps++;},
    getPrototypeOf() {traps++;}, getOwnPropertyDescriptor() {traps++;}});
  const getter = Object.defineProperty({}, 'format', {get() {traps++;}});
  for (const options of [proxy, getter, {parameters: proxy}]) {
    assert.throws(() => read('aql', 'original', options, limits), unavailable);
  }
  assert.equal(traps, 0);
});

test('Source intake keeps original callback aliases separate from bounded DATA', () => {
  let calls = 0;
  const callback = () => {calls++;};
  const result = read('aql', 'original', {format: 'sql', callback}, limits);
  assert.equal(result.packet.options.callback, callback);
  assert.equal(result.originalReferences.length, 1);
  assert.equal(result.originalReferences[0].original, callback);
  assert.deepEqual(result.originalReferences[0].path, ['options', 'callback']);
  assert.equal(calls, 0);
  assert.throws(() => read('aql', 'original', {callback}, {...limits, maxOpaqueAliases: 0}), unavailable);
});

test('Source reader retains finite original bounds and refuses unsupported overlap', () => {
  assert.throws(() => read('aql', 'x'.repeat(129), {format: 'sql'}, limits), unavailable);
  assert.throws(() => read('aql', 'original', {format: 'sql'}, {...limits, maxProperties: 1}), unavailable);
  assert.throws(() => read('aql', 'original', {}, {...limits, maxWork: 1}), unavailable);
  assert.throws(() => read('aql', 'original', {}, undefined), unavailable);
});
