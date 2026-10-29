import assert from 'node:assert/strict';
import test from 'node:test';
import {restSourcePageReader} from './rest-source-page.mjs';

// Explicit original-parser result ports. These tests cover only the pure
// adapter; C's actual parser tests and the matched Node ABI remain separate.
function fixture({pages = [], decodePage, limits = {}, pagination} = {}) {
  const calls = [], source = {resource: 'records', fields: [{name: 'id'}],
    read: {method: 'GET', path: '/v1/records'},
    pagination: pagination ?? {kind: 'cursor', items: ['data'], next: ['next'], parameter: 'after'},
    limits: {maxPageRows: 2, maxPageBytes: 1024, maxPages: 3, maxRows: 4,
      maxNodes: 64, maxDepth: 8, maxCursorBytes: 32, ...limits}};
  const moon = {
    clientProgramRowSourceProjectJsonPage(...args) {
      calls.push(args); const page = pages.shift(); assert(page, 'Unexpected parser call');
      if (page.bodyText !== undefined) assert.equal(args[0].toString('utf8'), page.bodyText);
      else assert.equal(args[0], page.body);
      return {$tag: 1, _0: page};
    },
    clientProgramRowSourceJsonPageRowsWire: page => page.wire,
    clientProgramRowSourceJsonPageRowCount: page => page.count,
    clientProgramRowSourceJsonPageHasNextCursor: page => page.hasNextOverride ?? (page.next !== undefined),
    clientProgramRowSourceJsonPageNextCursor: page => ({$tag: 1, _0: page.next}),
  };
  const prepare = restSourcePageReader({moon, source, decodePage});
  return {reader: prepare(), calls, moon, source};
}
const response = body => ({accepted: true, statusCode: 200, body});
const context = (pageIndex, rowCount) => ({pageIndex, rowCount, receivedBodyBytes: 0n});

test('standard REST hooks keep exact row wire and fixed request without author lifecycle ports', () => {
  const body = Buffer.from('original charged response'), wire = '[ {"id":9007199254740993.0100000000,"s":"e\\u0301"} ]';
  const f = fixture({pages: [{body, wire, count: 1, next: 'page-2'}]});
  assert.deepEqual(f.reader.fetchPage(context(0, 0)), {method: 'GET', path: '/v1/records',
    query: [], headers: [['accept', 'application/json']], responseHeaders: []});
  assert.deepEqual(f.reader.decodePage(response(body), context(0, 0)), {rowsWire: wire, rowCount: 1, done: false});
  assert.deepEqual(f.reader.fetchPage(context(1, 1)).query, [['after', 'page-2']]);
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0][0], body);
  assert.deepEqual(f.calls[0].slice(1), [['data'], true, ['next'], 1024, 64, 8, 2, 32]);
  assert.deepEqual(Object.keys(f.reader).sort(), ['decodePage', 'fetchPage']);
});

test('Some empty cursor remains a real next request and unknown runtime layouts never become EOF', () => {
  const first = Buffer.from('first'), second = Buffer.from('second');
  const f = fixture({pages: [{body: first, wire: '[]', count: 0, next: ''},
    {body: second, wire: '[]', count: 0}]});
  assert.equal(f.reader.decodePage(response(first), context(0, 0)).done, false);
  assert.deepEqual(f.reader.fetchPage(context(1, 0)).query, [['after', '']]);
  assert.equal(f.reader.decodePage(response(second), context(1, 0)).done, true);
  const g = fixture({pages: [{body: first, wire: '[]', count: 0, hasNextOverride: ''}]});
  assert.throws(() => g.reader.decodePage(response(first), context(0, 0)),
    {code: 'RestSourceCursorRuntimeBindingMismatch'});
});

test('provider errors refuse before parsing and never synthesize empty rows', () => {
  const f = fixture();
  assert.throws(() => f.reader.decodePage({accepted: true, statusCode: 503, body: Buffer.from('error')}, context(0, 0)),
    {code: 'RestSourceProviderRejected'});
  assert.equal(f.calls.length, 0);
});

test('cursor cycles and pending page or row ceilings refuse before delivering another page', () => {
  const body = Buffer.from('response');
  const f = fixture({pages: [{body, wire: '[]', count: 0, next: 'repeat'},
    {body, wire: '[]', count: 0, next: 'repeat'}]});
  f.reader.decodePage(response(body), context(0, 0));
  assert.throws(() => f.reader.decodePage(response(body), context(1, 0)), {code: 'RestSourceCursorCycle'});
  const lastPage = fixture({limits: {maxPages: 1}, pages: [{body, wire: '[]', count: 0, next: 'more'}]});
  assert.throws(() => lastPage.reader.decodePage(response(body), context(0, 0)), {code: 'RestSourcePageLimit'});
  const lastRow = fixture({limits: {maxRows: 1}, pages: [{body, wire: '[{}]', count: 1, next: 'more'}]});
  assert.throws(() => lastRow.reader.decodePage(response(body), context(0, 0)), {code: 'RestSourceRowLimit'});
});

test('optional transform sees only preserving DATA and unchanged wire does not add a parse', () => {
  const body = Buffer.from('response'), wire = '[{"id":"original"}]'; let callbacks = 0;
  const f = fixture({pages: [{body, wire, count: 1}], decodePage(page, context) {
    callbacks++; assert(Object.isFrozen(page)); assert.deepEqual(Object.keys(context).sort(), ['columns', 'resource']);
    assert.deepEqual(context, {resource: 'records', columns: ['id']});
    return {rowsWire: page.rowsWire, nextCursor: page.nextCursor};
  }});
  assert.deepEqual(f.reader.decodePage(response(body), context(0, 0)), {rowsWire: wire, rowCount: 1, done: true});
  assert.equal(callbacks, 1); assert.equal(f.calls.length, 1);
});


test('an optional row transform cannot silently drop or replace the declared next cursor', () => {
  const body = Buffer.from('response'), wire = '[{"id":"original"}]';
  const identityRows = fixture({pages: [{body, wire, count: 1, next: 'next'}],
    decodePage: page => ({rowsWire: page.rowsWire})});
  assert.equal(identityRows.reader.decodePage(response(body), context(0, 0)).done, false);
  assert.deepEqual(identityRows.reader.fetchPage(context(1, 1)).query, [['after', 'next']]);
  const tampered = fixture({pages: [{body, wire, count: 1, next: 'next'}],
    decodePage: page => ({rowsWire: page.rowsWire, nextCursor: 'other'})});
  assert.throws(() => tampered.reader.decodePage(response(body), context(0, 0)),
    {code: 'RestSourceCursorProjectionMismatch'});
});


test('a non-paged root array disables only the original Core cursor selector', () => {
  const body = Buffer.from('[]');
  const f = fixture({pagination: {kind: 'none', items: []}, pages: [{body, wire: '[]', count: 0}]});
  assert.deepEqual(f.reader.fetchPage(context(0, 0)).query, []);
  assert.deepEqual(f.reader.decodePage(response(body), context(0, 0)), {rowsWire: '[]', rowCount: 0, done: true});
  assert.deepEqual(f.calls[0].slice(1, 4), [[], false, []]);
});

test('a changed transform wire is revalidated by the same Core and cannot author a row count', () => {
  const body = Buffer.from('response'), changed = '[{"id":"one"},{"id":"two"}]';
  const f = fixture({pages: [{body, wire: '[{"id":"old"}]', count: 1, next: 'next'},
    {bodyText: changed, wire: changed, count: 2}], decodePage: () => ({rowsWire: changed})});
  assert.deepEqual(f.reader.decodePage(response(body), context(0, 0)),
    {rowsWire: changed, rowCount: 2, done: false});
  assert.equal(f.calls.length, 2); assert.deepEqual(f.calls[1].slice(1, 4), [[], false, []]);
  assert.deepEqual(f.reader.fetchPage(context(1, 2)).query, [['after', 'next']]);
  const bad = fixture({pages: [{body, wire: '[]', count: 0}],
    decodePage: () => ({rowsWire: changed, rowCount: 999})});
  assert.throws(() => bad.reader.decodePage(response(body), context(0, 0)), {code: 'InvalidRestSourceTransform'});
  assert.equal(bad.calls.length, 1);
});

test('an asynchronous transform is refused without an unhandled rejection', async () => {
  const body = Buffer.from('response'), original = new Error('original async author error');
  const f = fixture({pages: [{body, wire: '[]', count: 0}], decodePage: () => Promise.reject(original)});
  assert.throws(() => f.reader.decodePage(response(body), context(0, 0)), {code: 'InvalidRestSourceTransform'});
  await new Promise(resolve => setImmediate(resolve));
});
