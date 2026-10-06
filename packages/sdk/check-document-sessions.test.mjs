import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '@actql/client-wire';
import {connect, createCheckDocumentSession, getCheckInput, resolveCheckTextRangeEncoding} from './index.mjs';

const revision = 'rev:' + '4'.repeat(64);
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'scope-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const reply = bytes => ({version: 'actql-check-outcome/0.1',
  reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
  outcome: 'completed', report: {context_ref: 'ctx:fixture', scope: {kind: 'bound_input'},
    verdict: 'invalid', inputs: [{document_id: 'source', kind: 'text', revision, byte_length: bytes}],
    reasons: [{code: 'query_syntax_invalid', location: {kind: 'text', document_id: 'source', revision,
      start_byte: bytes, end_byte: bytes, precision: 'exact'}}], requirements: [],
    coverage: {limits: [], unresolved: []}}});
const location = observation => observation.outcome.report.reasons[0].location;
async function clientFixture(t, pending = []) {
  mock.method(globalThis, 'fetch', async (url, request) => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile);
    const text = JSON.parse(request.body).input.text;
    if (pending) return await new Promise((resolve, reject) => pending.push({text,
      release: () => resolve(Response.json(reply(new TextEncoder().encode(text).length))), reject}));
    return Response.json(reply(new TextEncoder().encode(text).length));
  });
  t.after(() => mock.restoreAll());
  return connect({mode: 'remote', endpoint: 'https://host.example/', token: 'token'});
}
const tick = async () => {await new Promise(resolve => setImmediate(resolve));};

test('negotiated coordinates use original scalar boundaries in all supported encodings', async t => {
  const client = await clientFixture(t, null);
  const outcome = await client.check('\ufeffAé😀e\u0301\r\nB\rC\n', {format: 'sql'});
  const original = outcome.report.reasons[0].location;
  // Independent literal byte, line, UTF-8, UTF-16 and UTF-32 coordinates.
  const cases = [[0,0,0,0,0], [3,0,3,1,1], [4,0,4,2,2], [6,0,6,3,3],
    [10,0,10,5,4], [11,0,11,6,5], [13,0,13,7,6], [15,1,0,0,0],
    [16,1,1,1,1], [17,2,0,0,0], [18,2,1,1,1], [19,3,0,0,0]];
  for (const [encoding, column] of [['utf-8',2], ['utf-16',3], ['utf-32',4]]) {
    for (const row of cases) {
      const resolved = resolveCheckTextRangeEncoding(outcome,
        {...original, start_byte: row[0], end_byte: row[0]}, encoding);
      assert.deepEqual(resolved?.range,
        {start: {line: row[1], character: row[column]}, end: {line: row[1], character: row[column]}},
        '[check-mutation:negotiated-coordinates]');
      assert.equal(resolved.positionEncoding, encoding);
      assert.equal(resolved.input, getCheckInput(outcome, 'source'));
    }
    for (const byte of [1,2,5,7,8,9,12,14]) {
      assert.equal(resolveCheckTextRangeEncoding(outcome,
        {...original, start_byte: byte, end_byte: byte}, encoding), undefined,
      '[check-mutation:negotiated-boundaries]');
    }
  }
  assert.equal(resolveCheckTextRangeEncoding(outcome, original, 'unknown'), undefined);
});

test('document sessions reject reused versions without replacing exact buffer bytes', async t => {
  const client = await clientFixture(t, null);
  const session = createCheckDocumentSession(client, {text: 'é😀', version: -2});
  const first = await session.check({format: 'sql'});
  for (const [text, version] of [['edited', -2], ['edited', -3], ['\ud800', -1],
    ['edited', 1.5], ['edited', 2147483648], ['edited', -2147483649]]) {
    let refusal;
    try { session.update(text, version); } catch (error) { refusal = error.code; }
    assert.equal(refusal, 'InvalidCheckDocument', '[check-mutation:document-version]');
  }
  assert.deepEqual(session.resolveTextRange(first, location(first)).range,
    {start: {line: 0, character: 3}, end: {line: 0, character: 3}});
  session.update('e\u0301😀', -1);
  assert.equal(session.resolveTextRange(first, location(first)), undefined,
    '[check-mutation:document-current]');
  const second = await session.check({format: 'sql'});
  assert.equal(second.version, -1);
  assert.equal(getCheckInput(second.outcome, 'source').text, 'e\u0301😀');
  assert.deepEqual(session.resolveTextRange(second, location(second)).range,
    {start: {line: 0, character: 4}, end: {line: 0, character: 4}});
});

test('document replies cannot replace a newer request even when completion is reordered', async t => {
  const pending = [], client = await clientFixture(t, pending);
  const session = createCheckDocumentSession(client, {text: '\ufeff/*😀*/\r\nSELECT (', version: 1});
  const first = session.check({format: 'sql'}), second = session.check({format: 'sql'});
  await tick();
  assert.equal(pending.length, 2);
  pending[1].release(); const newer = await second;
  pending[0].release(); const older = await first;
  assert.equal(session.resolveTextRange(older, location(older)), undefined,
    '[check-mutation:document-response-order]');
  assert.deepEqual(session.resolveTextRange(newer, location(newer)).range,
    {start: {line: 1, character: 8}, end: {line: 1, character: 8}});
  const failing = session.check({format: 'sql'});
  await tick();
  assert.equal(session.resolveTextRange(newer, location(newer)), undefined,
    '[check-mutation:document-pending]');
  pending[2].reject(new Error('transport unavailable'));
  await assert.rejects(failing);
  assert.equal(session.resolveTextRange(newer, location(newer)), undefined);
});

test('pending replies remain historical after editing, closing or reopening a document', async t => {
  const pending = [], client = await clientFixture(t, pending);
  const session = createCheckDocumentSession(client, {text: 'SELECT (', version: 1});
  const checking = session.check({format: 'sql'});
  session.update('SELECT 1 AS n', 2);
  await tick(); pending[0].release(); const old = await checking;
  assert.equal(getCheckInput(old.outcome, 'source').text, 'SELECT (');
  assert.equal(session.resolveTextRange(old, location(old)), undefined,
    '[check-mutation:document-current]');
  const closing = session.check({format: 'sql'});
  session.close(); session.close();
  await tick(); pending[1].release(); const closed = await closing;
  assert.equal(session.resolveTextRange(closed, location(closed)), undefined,
    '[check-mutation:document-closed]');
  assert.throws(() => session.update('SELECT (', 3), {code: 'CheckDocumentClosed'});
  await assert.rejects(session.check({format: 'sql'}), {code: 'CheckDocumentClosed'});
  const reopened = createCheckDocumentSession(client, {text: 'SELECT (', version: 1});
  assert.equal(reopened.resolveTextRange(old, location(old)), undefined,
    '[check-mutation:document-session]');
  const next = reopened.check({format: 'sql'});
  await tick(); pending[2].release(); const current = await next;
  assert.ok(reopened.resolveTextRange(current, location(current)));
  assert.equal(reopened.resolveTextRange({...current}, location(current)), undefined,
    '[check-mutation:document-copy]');
  assert.equal(reopened.resolveTextRange(JSON.parse(JSON.stringify(current)), location(current)), undefined);
  assert.equal(Object.isFrozen(current), true);
});

test('document sessions refuse invalid options and outcomes without owned source input', async t => {
  const client = await clientFixture(t, null);
  for (const options of [{text: '\ud800', version: 1}, {text: 'x', version: NaN},
    {text: 'x', version: 1, positionEncoding: 'unknown'}]) {
    assert.throws(() => createCheckDocumentSession(client, options), {code: 'InvalidCheckDocument'});
  }
  const copiedClient = {check: async () => reply(1)};
  const session = createCheckDocumentSession(copiedClient, {text: 'x', version: 1});
  const observation = await session.check({format: 'sql'});
  assert.equal(session.resolveTextRange(observation, location(observation)), undefined);
});
