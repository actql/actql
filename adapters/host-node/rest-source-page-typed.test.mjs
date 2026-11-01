import assert from 'node:assert/strict';
import test from 'node:test';
import {restSourcePageReader} from './rest-source-page.mjs';

// Actual pure page adapter; compiled parsing/schema results are explicit
// component ports. These cases issue no Source, Account, charge or cleanup ACK.
function fixture(transform, options = {}) {
  const calls = [], first = Object.freeze({}), changed = Object.freeze({}), legacy = Object.freeze({});
  const bytes = Buffer.from('original response DATA'), wire = '[{"id":"9007199254740993"}]';
  const projected = (method, value) => function(...args) {
    assert.equal(this, moon);calls.push([method, ...args]);
    if (method === 'typed') options.onTyped?.(args);
    if (method === 'typed' && options.failure !== undefined) throw options.failure;
    return {$tag: 1, _0: value};
  };
  const moon = {
    clientProgramRowSourceProjectJsonPage: projected('wire', legacy),
    clientProgramRowSourceProjectTypedJsonPage: projected('typed', first),
    clientProgramRowSourceJsonPageRowsWire(value) {
      assert.equal(this, moon);assert.equal(value, legacy);calls.push(['rows-wire']);return wire;
    },
    clientProgramRowSourceJsonPageOriginal(value) {
      assert.equal(this, moon);assert.equal(value, legacy);calls.push(['original']);return first;
    },
    clientProgramRowSourceTypedJsonPageRowCount(value) {
      assert.equal(this, moon);assert([first, changed].includes(value));return value === first ? 1 : 2;
    },
    clientProgramRowSourceTypedJsonPageHasNextCursor(value) {
      assert.equal(this, moon);assert([first, changed].includes(value));
      return Object.hasOwn(options, 'hasNext') ? options.hasNext : value === first;
    },
    clientProgramRowSourceTypedJsonPageNextCursor(value) {
      assert.equal(this, moon);assert.equal(value, first);return {$tag: 1, _0: ''};
    },
  };
  const source = {resource: 'records', fields: [{name: 'id'}], read: {path: '/records'},
    pagination: {kind: 'cursor', parameter: 'cursor', items: ['items'], next: ['next']},
    limits: {maxPageBytes: options.maxPageBytes ?? 1024, maxNodes: 64, maxDepth: 8, maxPageRows: 2,
      maxRows: 4, maxPages: 3, maxCursorBytes: 32}};
  const prepare = restSourcePageReader({moon, source, decodePage: transform});
  const invoke = (fn, receiver, args) => Reflect.apply(fn, receiver, args);
  return {calls, moon, first, changed, bytes, wire, legacy, source, prepare,
    reader: prepare(undefined, invoke), response: {accepted: true, statusCode: 200, body: bytes},
    progress: {pageIndex: 0, rowCount: 0}};
}

test('REST typed page forwards the same opaque original without rows wire encoding', () => {
  const f = fixture(), result = f.reader.decodePage(f.response, f.progress);
  assert.equal(result.projectedPage, f.first);assert.equal(result.rowCount, 1);assert.equal(result.done, false);
  assert.deepEqual(Object.keys(result).sort(), ['done', 'projectedPage', 'rowCount']);
  assert.equal(f.calls.length, 1);assert.equal(f.calls[0][0], 'typed');assert.equal(f.calls[0][1], f.bytes);
  assert.deepEqual(f.reader.fetchPage({pageIndex: 1, rowCount: 1}).query, [['cursor', '']]);
  // Captured methods/receiver remain the same after the author installation changes.
  f.moon.clientProgramRowSourceProjectTypedJsonPage = () => assert.fail('No replacement method');
  assert.throws(() => f.reader.decodePage(f.response, {pageIndex: 1, rowCount: 1}), {code: 'RestSourceCursorCycle'});
});

test('REST unchanged author transform preserves its old DTO and reuses the parsed original', () => {
  let observed;
  const f = fixture((page, context) => {
    observed = page;assert(Object.isFrozen(page));assert(Object.isFrozen(context));
    assert.deepEqual(Object.keys(page).sort(), ['nextCursor', 'rowCount', 'rowsWire']);
    assert.equal(context.resource, 'records');assert.deepEqual(context.columns, ['id']);
    return {rowsWire: page.rowsWire, nextCursor: page.nextCursor};
  });
  const result = f.reader.decodePage(f.response, f.progress);
  assert.equal(observed.rowsWire, f.wire);assert.equal(result.projectedPage, f.first);
  assert.deepEqual(f.calls.map(call => call[0]), ['wire', 'original', 'rows-wire']);
});

test('REST changed author wire is a new bounded Core parse while original cursor remains exact', () => {
  const transformed = '[{"id":"-9223372036854775808"},{"id":null}]';
  const f = fixture(() => ({rowsWire: transformed}));
  // Supply the distinct new parse result before installation captures it.
  const moon = {...f.moon, clientProgramRowSourceProjectTypedJsonPage(bytes, items, cursor) {
    assert.equal(this, moon);assert.deepEqual(bytes, Buffer.from(transformed));
    assert.deepEqual(items, []);assert.equal(cursor, false);f.calls.push(['changed-typed']);
    return {$tag: 1, _0: f.changed};
  }};
  // Other captured methods also retain their actual supplied receiver.
  for (const name of Object.keys(moon)) if (name !== 'clientProgramRowSourceProjectTypedJsonPage') {
    const method = f.moon[name];moon[name] = (...args) => Reflect.apply(method, f.moon, args);
  }
  const reader = restSourcePageReader({moon, source: f.source, decodePage: () => ({rowsWire: transformed})})(
    undefined, (fn, receiver, args) => Reflect.apply(fn, receiver, args));
  const result = reader.decodePage(f.response, f.progress);
  assert.equal(result.projectedPage, f.changed);assert.equal(result.rowCount, 2);assert.equal(result.done, false);
  assert.deepEqual(reader.fetchPage({pageIndex: 1, rowCount: 2}).query, [['cursor', '']]);
  assert.deepEqual(f.calls.map(call => call[0]), ['wire', 'original', 'rows-wire', 'changed-typed']);
});

test('REST typed page never substitutes EOF for malformed cursor projection or parser refusal', () => {
  for (const badCursor of [undefined, 0, '', {}]) {
    const f = fixture(undefined, {hasNext: badCursor});
    assert.throws(() => f.reader.decodePage(f.response, f.progress), {code: 'RestSourceCursorRuntimeBindingMismatch'});
  }
  const refusal = new Error('original bounded parser refusal'), f = fixture(undefined, {failure: refusal});
  assert.throws(() => f.reader.decodePage(f.response, f.progress), error => error === refusal);
});

test('REST author transform cannot change cursor add fields or exceed the existing page bound', () => {
  for (const [transform, code] of [
    [page => ({rowsWire: page.rowsWire, nextCursor: 'substitute'}), 'RestSourceCursorProjectionMismatch'],
    [page => ({rowsWire: page.rowsWire, rowCount: 0}), 'InvalidRestSourceTransform'],
    [() => ({rowsWire: ' '.repeat(1025)}), 'RestSourceTransformPageLimit'],
  ]) {
    const f = fixture(transform);
    assert.throws(() => f.reader.decodePage(f.response, f.progress), {code});
    assert.equal(f.calls.filter(call => call[0] === 'typed').length, 0);
  }
});


test('REST transform captures own DATA before an alternating getter can bypass the byte bound', t => {
  let reads = 0;
  const typedBytes = [], downstream = new Error('original bounded Core refusal');
  const value = {get rowsWire() {return ++reads <= 4 ? '[]' : ' '.repeat(256 * 1024);}};
  const f = fixture(() => value, {maxPageBytes: 64, onTyped(args) {
    typedBytes.push(args[0].byteLength);
    assert.equal(args[4], 64);
    if (args[0].byteLength > 64) throw downstream;
  }});
  let failure;
  try { f.reader.decodePage(f.response, f.progress); } catch (error) { failure = error; }
  t.diagnostic(JSON.stringify({getterReads: reads, typedBufferBytes: typedBytes,
    failureCode: failure?.code ?? null, originalDownstreamRefusal: failure === downstream}));
  assert.equal(failure?.code, 'InvalidRestSourceTransform');
  assert.equal(reads, 0, 'An own accessor is rejected without entering author DATA');
  assert.deepEqual(typedBytes, [], 'No changed Buffer reaches Core after rejected transform DATA');
});
