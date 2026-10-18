import assert from 'node:assert/strict';
import test from 'node:test';
import {snapshotInitialControlHostInput as snapshot} from './initial-control-host-input.mjs';

// Explicit reader limits test DATA/work bounds, not an operational envelope,
// backing-byte proof, selected startup issuer or normal Host positive.
const limits = Object.freeze({maxProperties: 100, maxNodes: 100, maxDepth: 10,
  maxStringCodeUnits: 100, maxTotalStringCodeUnits: 1000,
  maxArrayItems: 100, maxOpaqueAliases: 20, maxWork: 10000});
const unavailable = {code: 'NodeInitialControlInputUnavailable'};

test('finite snapshot preserves all own data, shape and immutable shared DATA', () => {
  const shared = {value: 'original'}, array = new Array(3);
  array[2] = shared;
  const installation = Object.create(null);
  Object.defineProperty(installation, '__proto__', {value: shared, enumerable: true});
  const raw = {mode: 'local', installation, unknown: shared, array};
  Object.defineProperty(raw, 'hidden', {value: shared, enumerable: false});
  const result = snapshot(raw, limits), packet = result.packet;
  assert.notEqual(packet, raw);
  assert.equal(Object.getPrototypeOf(packet.installation), null);
  assert.equal(Object.hasOwn(packet.installation, '__proto__'), true);
  assert.equal(packet.unknown, packet.hidden);
  assert.equal(packet.array[2], packet.unknown);
  assert.equal(packet.installation.__proto__, packet.unknown);
  assert.notEqual(packet.unknown, shared);
  assert.equal(Object.getOwnPropertyDescriptor(packet, 'hidden').enumerable, false);
  assert.equal(packet.array.length, 3);
  assert.equal(Object.hasOwn(packet.array, 0), false);
  shared.value = 'replacement'; raw.mode = 'remote';
  assert.equal(packet.unknown.value, 'original'); assert.equal(packet.mode, 'local');
  for (const value of [result, result.usage, result.originalReferences, packet,
    packet.installation, packet.unknown, packet.array]) assert.equal(Object.isFrozen(value), true);
});

test('original Host Owner handles and callbacks retain exact identity without traversal', () => {
  let calls = 0;
  const callback = () => { calls++; }, nominal = Object.freeze({});
  const original = Object.defineProperty({}, 'neverRead', {get() { calls++; throw new Error('OwnerGetter'); }});
  const raw = {installation: {authorization: original, connectorTable: nominal,
    modelInstallation: original, resolveSourceSecret: callback}, callback};
  const result = snapshot(raw, limits);
  assert.equal(result.packet.installation.authorization, original);
  assert.equal(result.packet.installation.connectorTable, nominal);
  assert.equal(result.packet.installation.modelInstallation, original);
  assert.equal(result.packet.installation.resolveSourceSecret, callback);
  assert.equal(result.packet.callback, callback);
  assert.deepEqual(result.originalReferences.map(value => value.path), [
    ['installation', 'authorization'], ['installation', 'connectorTable'],
    ['installation', 'modelInstallation'], ['installation', 'resolveSourceSecret'], ['callback']]);
  assert.equal(result.originalReferences[0].original, original);
  assert.equal(result.usage.opaqueAliases, 5); assert.equal(calls, 0);
  for (const value of result.originalReferences) assert.equal(Object.isFrozen(value.path), true);
});

test('unsupported Proxy and accessor inputs refuse without executing traps or getters', () => {
  let observations = 0;
  const proxy = new Proxy({}, {get() { observations++; }, ownKeys() { observations++; },
    getPrototypeOf() { observations++; }, getOwnPropertyDescriptor() { observations++; }});
  const getter = Object.defineProperty({}, 'value', {get() { observations++; }});
  for (const raw of [proxy, getter, {nested: proxy}, {installation: {authorization: proxy}},
    {nested: getter}]) assert.throws(() => snapshot(raw, limits), unavailable);
  assert.equal(observations, 0);
});

test('limit descriptors are checked before any raw input observation', () => {
  let reads = 0;
  const raw = Object.defineProperty({}, 'value', {get() { reads++; }});
  for (const value of [undefined, null, {}, {...limits, maxWork: 0}, {...limits, maxNodes: 0},
    {...limits, maxProperties: -1}, {...limits, maxDepth: 0.5},
    {...limits, maxArrayItems: Number.MAX_SAFE_INTEGER + 1},
    new Proxy(limits, {getOwnPropertyDescriptor() { reads++; }})]) {
    assert.throws(() => snapshot(raw, value), unavailable);
  }
  const getter = Object.defineProperty({...limits}, 'maxWork', {get() { reads++; }});
  assert.throws(() => snapshot(raw, getter), unavailable);
  assert.equal(reads, 0);
});

test('exact counted bounds pass and each smaller total refuses without truncation', () => {
  const raw = {mode: 'local', installation: {directory: 'original'}, consentRefs: ['one', 'two'],
    callback() {}};
  const first = snapshot(raw, limits);
  const exact = {maxProperties: first.usage.properties, maxNodes: first.usage.nodes,
    maxDepth: first.usage.depth, maxStringCodeUnits: 12,
    maxTotalStringCodeUnits: first.usage.stringCodeUnits, maxArrayItems: 2,
    maxOpaqueAliases: first.usage.opaqueAliases, maxWork: first.usage.work};
  assert.deepEqual(snapshot(raw, exact).packet, first.packet);
  for (const name of Object.keys(exact)) {
    assert.throws(() => snapshot(raw, {...exact, [name]: exact[name] - 1}), unavailable, name);
  }
});

test('empty input can use zero structural allowances without implying zero backing bytes', () => {
  const result = snapshot({}, {maxProperties: 0, maxNodes: 1, maxDepth: 0,
    maxStringCodeUnits: 0, maxTotalStringCodeUnits: 0, maxArrayItems: 0,
    maxOpaqueAliases: 0, maxWork: 1});
  assert.deepEqual(result.packet, {});
  assert.deepEqual(result.usage, {properties: 0, nodes: 1, depth: 0,
    stringCodeUnits: 0, arrayItems: 0, opaqueAliases: 0, work: 1});
});

test('primitive String code units are counted unchanged, including keys and lone surrogates', () => {
  const text = '\ud800\udc00\ud800';
  const result = snapshot({x: text}, {...limits, maxStringCodeUnits: 3, maxTotalStringCodeUnits: 4});
  assert.equal(result.packet.x, text); assert.equal(result.usage.stringCodeUnits, 4);
  assert.throws(() => snapshot({x: text}, {...limits, maxStringCodeUnits: 2}), unavailable);
  assert.throws(() => snapshot({x: text}, {...limits, maxTotalStringCodeUnits: 3}), unavailable);
});

test('sparse array length is bounded before allocating its copy', () => {
  const raw = {array: new Array(0xffffffff)};
  assert.throws(() => snapshot(raw, limits), unavailable);
  const small = snapshot({array: new Array(3)}, {...limits, maxArrayItems: 3});
  assert.equal(small.packet.array.length, 3);
  assert.equal(small.usage.arrayItems, 3);
  assert.throws(() => snapshot({array: new Array(3)}, {...limits, maxArrayItems: 2}), unavailable);
});

test('unsupported cycles, symbols and root shapes do not masquerade as valid DATA', () => {
  const cycle = {}; cycle.self = cycle;
  for (const raw of [null, [], () => {}, 1, new Date(), cycle, {[Symbol('key')]: 1}]) {
    assert.throws(() => snapshot(raw, limits), unavailable);
  }
  class Policy {constructor() {this.value = 1;}}
  const policy = new Policy(), packet = snapshot({policy}, limits).packet;
  // Keeping the original class lets the existing semantic Owner reject it;
  // this reader must not turn it into an admissible plain policy.
  assert.equal(packet.policy, policy); assert.equal(Object.getPrototypeOf(packet.policy), Policy.prototype);
});

test('deep finite intake uses explicit bounded frames rather than recursive VM calls', () => {
  const raw = {}; let current = raw;
  for (let index = 0; index < 1500; index++) current = current.child = {};
  const result = snapshot(raw, {...limits, maxProperties: 1500, maxNodes: 1501,
    maxDepth: 1500, maxTotalStringCodeUnits: 7500, maxWork: 1200000});
  assert.equal(result.usage.depth, 1500);
  assert.throws(() => snapshot(raw, {...limits, maxProperties: 1500, maxNodes: 1501,
    maxDepth: 1499, maxTotalStringCodeUnits: 7500, maxWork: 1200000}), unavailable);
});
