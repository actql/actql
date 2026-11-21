import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {runtimeField, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {captureRestSourceRead, restSourcePageRequest, restSourceReadConstructionUnits,
  restSourceRequestConstructionUnits} from './rest-source-request.mjs';
import {requestTarget} from '../host-common/http-exchange.mjs';
import {prepareNotionUserListPages} from '../connectors/notion/site/user-list-read.mjs';
import {captureRestReadOriginals, restReadOriginalControlUnits,
  restReadTransportConstructionUnits} from './rest-read-original.mjs';

test('declarative request inventory pins retained DATA and full original query escape overlap', () => {
  const read={method:'GET',path:'/v1/users',pageSize:{parameter:'page_size',limit:100},
    versionHeader:{name:'notion-version',value:'2026-03-11'}};
  // Independent output/descriptor inventories. Neither vector supplies a
  // limit/grant, and no returned capacity is inspected as an untyped record.
  assert.deepEqual(restSourceReadConstructionUnits(read,'start_cursor'),[11n,114n,0n,172n,160n,0n]);
  assert.deepEqual(restSourceRequestConstructionUnits(read,'start_cursor'),[38n,8232n,0n,72n,49212n,0n]);
  const fixed={...read,query:[['filter','é'.repeat(16)],['label','x y']]};
  const units=restSourceReadConstructionUnits(fixed,'start_cursor');
  assert(units[0]>11n);assert(units[1]>114n);assert(units[3]>172n);
  const request=restSourcePageRequest(captureRestSourceRead(fixed,'start_cursor'),'start_cursor',1,'');
  assert.equal(requestTarget(request.path,request.query),
    '/v1/users?filter='+('%C3%A9'.repeat(16))+'&label=x%20y&page_size=1&start_cursor=');
});

test('declarative read request preserves literal query order version and remaining page size', () => {
  const definition = {method: 'GET', path: '/v1/records', query: [['kind', 'person+bot'], ['label', 'e\u0301']],
    pageSize: {parameter: 'page_size', limit: 100}, versionHeader: {name: 'api-version', value: '2026-03-11'}};
  const read = captureRestSourceRead(definition, 'after');
  definition.query[0][1] = 'foreign';definition.versionHeader.value = 'changed';
  const request = restSourcePageRequest(read, 'after', 3, '');
  assert.equal(requestTarget(request.path, request.query),
    '/v1/records?kind=person%2Bbot&label=e%CC%81&page_size=3&after=');
  assert.deepEqual(request.headers, [['accept', 'application/json'], ['api-version', '2026-03-11']]);
  assert.deepEqual(restSourcePageRequest(captureRestSourceRead({method: 'GET', path: '/legacy'}, 'after'),
    'after', 1, undefined), {method: 'GET', path: '/legacy', query: [],
    headers: [['accept', 'application/json']], responseHeaders: []});
  assert.throws(() => restSourcePageRequest(read, 'after', 0, undefined), {code: 'InvalidRestSourceRead'});
});

test('declarative read request refuses ambiguous and accessor input without invoking it', () => {
  const base = {method: 'GET', path: '/rows'};
  for (const value of [
    {...base, query: [['after', 'borrowed-cursor']]},
    {...base, query: [['kind', 'a'], ['kind', 'b']]},
    {...base, query: [['size', '1']], pageSize: {parameter: 'size', limit: 2}},
    {...base, pageSize: {parameter: 'after', limit: 2}},
    {...base, pageSize: {parameter: 'size', limit: 0}},
    {...base, versionHeader: {name: 'authorization', value: 'forbidden'}},
    {...base, versionHeader: {name: 'api-version', value: 'bad\r\nvalue'}},
  ]) assert.throws(() => captureRestSourceRead(value, 'after'), {code: 'InvalidRestSourceRead'});
  let touched = 0;
  const query = [['kind', 'value']];
  Object.defineProperty(query, 'map', {get() {touched++;throw new Error('Do not invoke');}});
  assert.throws(() => captureRestSourceRead({...base, query}, 'after'), {code: 'InvalidRestSourceRead'});
  const pair = ['kind', 'value'];Object.defineProperty(pair, '1', {get() {touched++;return 'foreign';}});
  assert.throws(() => captureRestSourceRead({...base, query: [pair]}, 'after'), {code: 'InvalidRestSourceRead'});
  const value = {...base};Object.defineProperty(value, 'versionHeader', {get() {touched++;return {};}});
  assert.throws(() => captureRestSourceRead(value, 'after'), {code: 'InvalidRestSourceRead'});
  assert.equal(touched, 0);
});

test('declarative Notion request keeps original version and caps requested rows before any projection', () => {
  // These are primitive request-selection ports, not fake parsed-page handles.
  // Actual Catalog decoding/HTTP remains a separately required boundary.
  const unused = () => {assert.fail('No page projection in a request-only control');};
  const moon = {notionUserListColumnNames: () => ['id', 'name', 'type', 'email'],
    notionProjectUserList: unused, notionUserListIds: unused, notionUserListRowsWire: unused,
    notionUserListMetadataJson: unused};
  const limits = Object.fromEntries(['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth',
    'maxRows', 'maxPages', 'maxCursorBytes', 'maxIdentityBytes', 'maxTargetBytes', 'maxValueNodes',
    'maxValueTextBytes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'].map(name => [name, 100]));
  const progress = Object.freeze({});
  const exhausted = Object.freeze({});
  const common = {
    clientProgramRowSourcePrepareCursorProgress(...args) {
      assert.deepEqual(args,[100,1,10,100]);return {$tag:1,_0:progress};
    },
    clientProgramRowSourceCursorRemainingRows(original,index,count) {
      assert.equal(original,progress);
      if (index===0&&count===0) return {$tag:1,_0:1};
      assert.deepEqual([index,count],[1,1]);return {$tag:0,_0:exhausted};
    },
    clientProgramRowSourceCursorHasNext(original) {assert.equal(original,progress);return false;},
    clientProgramRowSourceCursorNext: unused,
    clientProgramRowSourceAdvanceProviderPageCursor: unused,
    clientProgramRowSourceCursorIssueCode(original) {assert.equal(original,exhausted);return 'RestSourceRowLimit';},
  };
  const pages = prepareNotionUserListPages({moon, common, names: ['id'], limits: {...limits, maxTotalRows: 1, pageSize: 10}},
    (method, receiver, args) => Reflect.apply(method, receiver, args));
  const request = pages.fetchPage({pageIndex: 0, rowCount: 0});
  assert.equal(requestTarget(request.path, request.query), '/v1/users?page_size=1');
  assert.deepEqual(request.headers, [['accept', 'application/json'], ['notion-version', '2026-03-11']]);
  assert.throws(() => pages.fetchPage({pageIndex: 1, rowCount: 1}), {code: 'NotionUserListRowLimit'});
});

// Actual pure page adapter; compiled parsing/schema results are explicit
// component ports. The shared-reader case below retains its actual JS lifecycle
// with explicit Site/Account/charge ports; no case issues a normal public Run.
function fixture(transform, options = {}) {
  const calls = [], first = Object.freeze({}), changed = Object.freeze({}), legacy = Object.freeze({});
  const cursorCalls = [], progress = Object.freeze({}), cycle = Object.freeze({});
  let advanced = 0;
  const bytes = Buffer.from('original response DATA'), wire = '[{"id":"9007199254740993"}]';
  const projected = (method, value) => function(...args) {
    assert.equal(this, moon);calls.push([method, ...args]);
    if (method === 'typed') options.onTyped?.(args);
    if (method === 'typed' && options.failure !== undefined) throw options.failure;
    return {$tag: 1, _0: value};
  };
  const moon = {
    clientProgramRowSourcePrepareCursorProgress(...limits) {
      assert.equal(this,moon);assert.deepEqual(limits,[3,4,2,32]);
      cursorCalls.push(['prepare']);return {$tag:1,_0:progress};
    },
    clientProgramRowSourceCursorRemainingRows(value,index,count) {
      assert.equal(this,moon);assert.equal(value,progress);
      cursorCalls.push(['remaining',index,count]);return {$tag:1,_0:2};
    },
    clientProgramRowSourceCursorRequestRows(value,index,count,present,limit) {
      assert.equal(this,moon);assert.equal(value,progress);
      cursorCalls.push(['requestRows',index,count,present,limit]);
      return {$tag:1,_0:options.requestRows??2};
    },
    clientProgramRowSourceAdvanceCursorProgress(value,index,count,envelope,rows) {
      assert.equal(this,moon);assert.equal(value,progress);assert.equal(envelope,first);
      assert([first,changed].includes(rows));cursorCalls.push(['advance',index,count,envelope,rows]);
      // Canned typed port outcomes, not another pagination implementation.
      // Actual bounds/cycle/EOF semantics are executed by the Core cases.
      advanced++;
      return advanced===1 ? {$tag:1,_0:options.hasNext===false} : {$tag:0,_0:cycle};
    },
    clientProgramRowSourceCursorHasNext(value) {
      assert.equal(this,moon);assert.equal(value,progress);return advanced!==0;
    },
    clientProgramRowSourceCursorNext(value) {
      assert.equal(this,moon);assert.equal(value,progress);return {$tag:1,_0:''};
    },
    clientProgramRowSourceCursorIssueCode(value) {
      assert.equal(this,moon);assert.equal(value,cycle);return 'RestSourceCursorCycle';
    },
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
  const source = {resource: 'records', fields: [{name: 'id'}], read: options.read ?? {path: '/records'},
    pagination: {kind: 'cursor', parameter: 'cursor', items: ['items'], next: ['next']},
    limits: {maxPageBytes: options.maxPageBytes ?? 1024, maxNodes: 64, maxDepth: 8, maxPageRows: 2,
      maxRows: 4, maxPages: 3, maxCursorBytes: 32}};
  const prepare = restSourcePageReader({moon, source, decodePage: transform});
  const invoke = (fn, receiver, args) => Reflect.apply(fn, receiver, args);
  return {calls, cursorCalls, cycle, moon, first, changed, bytes, wire, legacy, source, prepare,
    reader: prepare(undefined, invoke), response: {accepted: true, statusCode: 200, body: bytes},
    progress: {pageIndex: 0, rowCount: 0}};
}

test('portable request caller forwards original cursor and hint while response keeps its original ceiling', () => {
  const f=fixture(undefined,{read:{path:'/records',pageSize:{parameter:'size',limit:1}},requestRows:1});
  assert.deepEqual(f.reader.fetchPage({pageIndex:0,rowCount:0}).query,[['size','1']]);
  assert.deepEqual(f.cursorCalls.at(-1),['requestRows',0,0,true,1]);
  f.reader.decodePage(f.response,f.progress);
  assert(f.cursorCalls.some(value=>value[0]==='remaining'&&value[1]===0&&value[2]===0));
  // Explicit Core port above, never a second JS progress/min implementation.
  // Missing current ABI fails before preparing any progress; no old fallback.
  const old={...f.moon};delete old.clientProgramRowSourceCursorRequestRows;
  assert.throws(()=>restSourcePageReader({moon:old,source:f.source}),{code:'RestSourcePageProjectionUnavailable'});
  assert.throws(()=>restSourcePageRequest(captureRestSourceRead({method:'GET',path:'/records',
    pageSize:{parameter:'size',limit:1}}),'cursor',2,undefined),{code:'InvalidRestSourceRead'});
});

test('REST typed page forwards the same opaque original without rows wire encoding', () => {
  const f = fixture(), result = f.reader.decodePage(f.response, f.progress);
  assert.equal(result.projectedPage, f.first);assert.equal(result.rowCount, 1);assert.equal(result.done, false);
  assert.deepEqual(Object.keys(result).sort(), ['done', 'projectedPage', 'rowCount']);
  assert.equal(f.calls.length, 1);assert.equal(f.calls[0][0], 'typed');assert.equal(f.calls[0][1], f.bytes);
  assert.deepEqual(f.cursorCalls.at(-1),['advance',0,0,f.first,f.first]);
  assert.deepEqual(f.reader.fetchPage({pageIndex: 1, rowCount: 1}).query, [['cursor', '']]);
  // Captured methods/receiver remain the same after the author installation changes.
  f.moon.clientProgramRowSourceProjectTypedJsonPage = () => assert.fail('No replacement method');
  assert.throws(() => f.reader.decodePage(f.response, {pageIndex: 1, rowCount: 1}),
    error => error.code==='RestSourceCursorCycle' && error.cause===f.cycle);
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
  assert.deepEqual(f.cursorCalls.at(-2),['advance',0,0,f.first,f.changed]);
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

test('REST transform accepts null-prototype own DATA without replacing its original page', () => {
  const f = fixture(page => Object.assign(Object.create(null),
    {rowsWire: page.rowsWire, nextCursor: page.nextCursor}));
  assert.equal(f.reader.decodePage(f.response, f.progress).projectedPage, f.first);
  assert.deepEqual(f.calls.map(call => call[0]), ['wire', 'original', 'rows-wire']);
});

test('REST transform rejects inherited accessor and extra fields as closed DATA', () => {
  const bad = [null, [], new String('[]'), Object.create({rowsWire: '[]'}),
    Object.assign(Object.create({extra: true}), {rowsWire: '[]'}),
    {rowsWire: '[]', extra: true}, {rowsWire: '[]', [Symbol('extra')]: true},
    Object.defineProperty({rowsWire: '[]'}, 'extra', {value: true}),
    {rowsWire: '[]', nextCursor: {}}, {nextCursor: ''}];
  for (const value of bad) {
    const f = fixture(() => value);
    assert.throws(() => f.reader.decodePage(f.response, f.progress), {code: 'InvalidRestSourceTransform'});
    assert.equal(f.calls.filter(call => call[0] === 'typed').length, 0);
  }
});

test('REST transform never enters throwing or retiring rowsWire and cursor getters', () => {
  for (const field of ['rowsWire', 'nextCursor']) for (const action of ['throw', 'retire']) {
    let reads = 0, retired = false;
    const value = {rowsWire: '[]'};
    Object.defineProperty(value, field, {get() {
      reads++;
      if (action === 'throw') throw new Error('original author getter failure');
      retired = true;
      return field === 'rowsWire' ? '[]' : '';
    }});
    const f = fixture(() => value);
    assert.throws(() => f.reader.decodePage(f.response, f.progress), {code: 'InvalidRestSourceTransform'});
    assert.equal(reads, 0);assert.equal(retired, false);
    assert.equal(f.calls.filter(call => call[0] === 'typed').length, 0);
  }
});

test('REST transform rejects live and revoked Proxies before its own shape inspection', () => {
  let traps = 0;
  const value = new Proxy({rowsWire: '[]'}, {
    get() {traps++;throw new Error('author get trap');},
    ownKeys() {traps++;throw new Error('author keys trap');},
    getOwnPropertyDescriptor() {traps++;throw new Error('author descriptor trap');},
    getPrototypeOf() {traps++;throw new Error('author prototype trap');},
  });
  const revoked = Proxy.revocable({rowsWire: '[]'}, {});revoked.revoke();
  for (const result of [value, revoked.proxy]) {
    const f = fixture(() => result);
    assert.throws(() => f.reader.decodePage(f.response, f.progress), {code: 'InvalidRestSourceTransform'});
  }
  assert.equal(traps, 0);
  // This direct facade component supplies the projection invoker explicitly.
  // It does not claim that the shared owner's earlier then-observation is absent.
});

test('REST transform checks the captured primitive UTF8 extent before encoding', () => {
  const f = fixture(() => ({rowsWire: JSON.stringify([{id: 'é'.repeat(30)}])}),
    {maxPageBytes: 64});
  assert.throws(() => f.reader.decodePage(f.response, f.progress), {code: 'RestSourceTransformPageLimit'});
  assert.equal(f.calls.filter(call => call[0] === 'typed').length, 0);
});


test('REST transform refusal keeps the shared original response charge and first cleanup without another send', async () => {
  let getters = 0;
  const bad = {get rowsWire() {getters++;throw new Error('unentered author getter');}};
  const f = fixture(() => bad, {hasNext: false});
  const charge = Object.freeze({}), site = Object.freeze({});
  const authorization = Object.freeze({grant: {}, useId: 'original', scope: Object.freeze({operation: 'read'})});
  let sends = 0, charges = 0, consumes = 0, closes = 0;
  const acquisition = Object.freeze({credential: Object.freeze({}), close() {
    assert.equal(this, acquisition);closes++;return 'closed';
  }});
  const originalSite = Object.freeze({site, referenceCurrent() {return true;},
    authorizationPurpose(value) {assert.equal(value, authorization);return {kind: 'read'};},
    bindRunAcquisition(value, callbacks) {assert.equal(value, authorization);callbacks.assertCurrent();return acquisition;},
    async callResource(input) {
      assert.equal(this, site);sends++;await input.currentBeforeSend();
      input.responseCustody.retain(f.response);return f.response;
    }});
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite,
    assertCurrent() {}, operation: 'read', maxResponses: 2, maxResponseBytes: 128,
    maxSecretBytes: 128, preparePageReader: f.prepare});
  const reader = factory.prepare(Object.freeze({originalAuthorization: authorization,
    columns: ['id'], verifyRead() {}, authorizationFor() {return authorization;},
    chargePage(bytes) {assert.equal(bytes, f.response.body);charges++;return charge;},
    consumePage() {assert.fail('No untyped row fallback');},
    consumePageWire() {assert.fail('No wire fallback');},
    consumeProjectedPage() {consumes++;assert.fail('No schema consume after transform rejection');},
  }));
  await assert.rejects(reader.read(), {code: 'InvalidRestSourceTransform'});
  assert.equal(getters, 0);assert.equal(sends, 1);assert.equal(charges, 1);assert.equal(consumes, 0);
  assert.equal(reader.observe().cleanupConfirmed, false);
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed, true);
  assert.equal(factory.retire(), true);assert.equal(closes, 1);assert.equal(sends, 1);
  // Real shared Reader JS; Site/Account/charge/Core are explicit component
  // ports. One callResource entrance is not an actual HTTP or funding claim.
});

test('REST changed author wire preserves the original Core schema refusal', () => {
  const cause = new Error('original changed-page schema refusal');
  const f = fixture(() => ({rowsWire: '[]'}), {failure: cause});
  assert.throws(() => f.reader.decodePage(f.response, f.progress), error => error === cause);
  assert.deepEqual(f.calls.map(call => call[0]), ['wire', 'original', 'rows-wire', 'typed']);
});

// Reuse the existing explicit Common-module test input. Absent input leaves
// only these two compiled-boundary cases unexecuted; canned ports above do not
// qualify a runtime. Every nominal value below comes from this ONE namespace.
const selectedCommon = process.env.ACTQL_METADATA_COMMON_RUNTIME;
const actualCommon = selectedCommon === undefined ? undefined : import(pathToFileURL(selectedCommon));

test('REST actual checked GET capacity preserves original reference Options',
  {skip: selectedCommon === undefined}, async () => {
    const moon = await actualCommon;
    const originals = captureRestReadOriginals(moon);
    const wire = JSON.stringify({method: 'GET', path: '/v1/users',
      pageSize: {parameter: 'page_size', limit: 2},
      versionHeader: {name: 'notion-version', value: '2026-03-11'}});
    const profile = {maxDeclarationBytes: 4096, maxDeclarationNodes: 1000,
      maxDepth: 16, maxTargetBytes: 1024};
    const quote = originals.quote(wire, 'start_cursor', profile);
    // Pure quantity composition only: this test creates no Source reservation,
    // physical reader, Account, HTTP request or Run.
    const construction = originals.composeConstruction(restReadOriginalControlUnits(1), 1, () => quote);
    const read = originals.project(wire, 'start_cursor', profile);
    const originalOption = read.capacityOption();
    const page = runtimeUnboxedReferenceOption(originalOption);
    assert(page !== undefined && page !== null);
    assert.strictEqual(read.capacityOption(), originalOption);
    const units = restReadTransportConstructionUnits(read);
    const request = originals.requestCapacity(units, [read]);
    // The opaque values go back to their actual typed namespace; never inspect
    // their record fields or reconstruct an Option from quantity scalars.
    for (const capacity of [construction, page, request]) {
      const bytes = moon.clientProgramSerializationCapacityBytes(capacity);
      assert(runtimeField(bytes, 0) > 0n);
      assert(runtimeField(bytes, 1) >= runtimeField(bytes, 0));
    }
    assert.deepEqual(read.page(3, 2, undefined), {method: 'GET', path: '/v1/users',
      query: [['page_size', '2']],
      headers: [['accept', 'application/json'], ['notion-version', '2026-03-11']], responseHeaders: []});
    assert.throws(() => originals.requestCapacity(units, []),
      {code: 'RestReadOriginalCapacityUnavailable'});
    assert.strictEqual(read.capacityOption(), originalOption);
  });

// A genuinely new caller boundary for the next matching normal Common. It is
// deliberately outside the old two-case selector; its CI owner can add it to
// that SAME existing preparation build, never a second Common producer.
test('REST actual portable request hint keeps original parse and cursor ownership',
  {skip: selectedCommon === undefined}, async () => {
    const moon=await actualCommon;
    const source={resource:'records',fields:[{name:'id'}],read:{method:'GET',path:'/records',
      pageSize:{parameter:'size',limit:1}},
      pagination:{kind:'cursor',parameter:'after',items:['items'],next:['next']},
      limits:{maxPageBytes:1024,maxNodes:64,maxDepth:8,maxPageRows:2,maxRows:3,maxPages:3,maxCursorBytes:32}};
    const reader=restSourcePageReader({moon,source})();
    assert.deepEqual(reader.fetchPage({pageIndex:0,rowCount:0}).query,[['size','1']]);
    const first=reader.decodePage({accepted:true,statusCode:200,
      body:Buffer.from('{"items":[{"id":"one"},{"id":"two"}],"next":""}')},{pageIndex:0,rowCount:0});
    assert.equal(first.rowCount,2);assert.equal(first.done,false);
    assert.deepEqual(reader.fetchPage({pageIndex:1,rowCount:2}).query,[['size','1'],['after','']]);
    assert.throws(()=>reader.fetchPage({pageIndex:1,rowCount:1}),{code:'RestSourceCursorProgressMismatch'});
    const last=reader.decodePage({accepted:true,statusCode:200,
      body:Buffer.from('{"items":[{"id":"last"}]}')},{pageIndex:1,rowCount:2});
    assert.equal(last.done,true);
    assert.throws(()=>reader.fetchPage({pageIndex:2,rowCount:3}),{code:'RestSourceCursorCompleted'});
  });

test('REST actual Common cursor boundary keeps empty Unicode EOF and original progress',
  {skip: selectedCommon === undefined}, async () => {
    const moon = await actualCommon;
    const source = {resource: 'records', fields: [{name: 'id'}], read: {path: '/records'},
      pagination: {kind: 'cursor', parameter: 'cursor', items: ['items'], next: ['next']},
      limits: {maxPageBytes: 1024, maxNodes: 64, maxDepth: 8, maxPageRows: 2,
        maxRows: 4, maxPages: 3, maxCursorBytes: 32}};
    const prepare = restSourcePageReader({moon, source});
    const reader = prepare();
    const response = body => ({accepted: true, statusCode: 200,
      body: Buffer.from(JSON.stringify(body), 'utf8')});
    assert.deepEqual(reader.fetchPage({pageIndex: 0, rowCount: 0}).query, []);
    const first = reader.decodePage(response({items: [{id: '🌱'}], next: ''}),
      {pageIndex: 0, rowCount: 0});
    assert.equal(first.rowCount, 1);assert.equal(first.done, false);
    assert.deepEqual(reader.fetchPage({pageIndex: 1, rowCount: 1}).query, [['cursor', '']]);
    assert.throws(() => reader.fetchPage({pageIndex: 1, rowCount: 0}),
      {code: 'RestSourceCursorProgressMismatch'});
    const empty = reader.decodePage(response({items: [], next: '次🌱'}),
      {pageIndex: 1, rowCount: 1});
    assert.equal(empty.rowCount, 0);assert.equal(empty.done, false);
    assert.deepEqual(reader.fetchPage({pageIndex: 2, rowCount: 1}).query, [['cursor', '次🌱']]);
    const last = reader.decodePage(response({items: [{id: 'last'}]}),
      {pageIndex: 2, rowCount: 1});
    assert.equal(last.rowCount, 1);assert.equal(last.done, true);
    assert.throws(() => reader.fetchPage({pageIndex: 3, rowCount: 2}),
      {code: 'RestSourceCursorCompleted'});

    const cycle = prepare();
    cycle.decodePage(response({items: [{id: 'first'}], next: ''}),
      {pageIndex: 0, rowCount: 0});
    assert.throws(() => cycle.decodePage(response({items: [{id: 'second'}], next: ''}),
      {pageIndex: 1, rowCount: 1}), error => error.code === 'RestSourceCursorCycle' &&
      moon.clientProgramRowSourceCursorIssueCode(error.cause) === error.code);
    assert.deepEqual(cycle.fetchPage({pageIndex: 1, rowCount: 1}).query, [['cursor', '']]);
  });

test('REST actual Common cursor capacity uses the original domain representation',
  {skip: selectedCommon === undefined}, async () => {
    const moon = await actualCommon;
    const limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4];
    const original = runtimeUnboxedReferenceOption(
      moon.clientProgramInstalledJsonSourceReaderCapacity(limits, 2, 3));
    const cursor = runtimeUnboxedReferenceOption(
      moon.clientProgramInstalledJsonCursorSourceReaderCapacity(limits, 2, 3));
    assert(original !== undefined && original !== null);
    assert(cursor !== undefined && cursor !== null);
    // Independent shared-tariff/domain vector from the exact/one-short Core
    // fixture. The original capacity is opaque; use its existing typed Common
    // projection, then the canonical tuple binding. This issues no capacity.
    const originalBytes = moon.clientProgramSerializationCapacityBytes(original);
    const cursorBytes = moon.clientProgramSerializationCapacityBytes(cursor);
    assert.equal(runtimeField(originalBytes, 0), 3632n);
    assert.equal(runtimeField(cursorBytes, 0), 4366n);
    assert.equal(runtimeField(cursorBytes, 1) - runtimeField(originalBytes, 1), 774n);
  });
