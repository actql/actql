import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '@actql/client-wire';
import {connect, createCheckDocumentSession, formatCheckOutcome} from './index.mjs';

const revision = 'rev:' + '4'.repeat(64);
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'scope-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const reply = text => ({version: 'actql-check-outcome/0.1',
  reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
  outcome: 'completed', report: {context_ref: 'ctx:session-presentation', scope: {kind: 'bound_input'},
    verdict: 'invalid', inputs: [{document_id: 'source', kind: 'text', revision,
      byte_length: new TextEncoder().encode(text).length}],
    reasons: [{code: 'query_syntax_invalid', location: {kind: 'text', document_id: 'source', revision,
      start_byte: new TextEncoder().encode(text).length, end_byte: new TextEncoder().encode(text).length,
      precision: 'exact'}}], requirements: [], coverage: {limits: [], unresolved: []}}});
async function fixture(t, pending) {
  let calls = 0;
  mock.method(globalThis, 'fetch', async (url, request) => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile);
    calls++;
    const text = JSON.parse(request.body).input.text;
    if (pending) return await new Promise(resolve => pending.push(() => resolve(Response.json(reply(text)))));
    return Response.json(reply(text));
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/', token: 'token'});
  return {client, calls: () => calls};
}

test('check display coordinates honor the selected position encoding', async t => {
  const {client} = await fixture(t);
  const outcome = await client.check('é😀', {format: 'sql'});
  for (const [positionEncoding, character] of [['utf-8', 6], ['utf-16', 3], ['utf-32', 2]]) {
    const display = JSON.parse(formatCheckOutcome(outcome, {format: 'json', positionEncoding}));
    assert.deepEqual(display.entries[0].location,
      {kind: 'text', documentId: 'source', revision, startByte: 6, endByte: 6, precision: 'exact',
        positionEncoding, range: {start: {line: 0, character}, end: {line: 0, character}}},
      '[check-mutation:format-position-encoding]');
  }
  assert.equal(formatCheckOutcome(outcome, {positionEncoding: 'unknown'}), undefined,
    '[check-mutation:format-position-encoding-refusal]');
});

test('session displays retain safe explanations but only current owned positions', async t => {
  const {client, calls} = await fixture(t);
  const session = createCheckDocumentSession(client, {text: 'é😀', version: 1, positionEncoding: 'utf-8'});
  const observation = await session.check({format: 'sql'});
  const display = value => JSON.parse(session.format(value, {format: 'json'}));
  const first = display(observation);
  assert.equal(first.entries[0].location.positionEncoding, 'utf-8');
  assert.equal(first.entries[0].location.range.start.character, 6);
  for (const currentInputs of [[], null, {}]) {
    const restricted = JSON.parse(session.format(observation, {format: 'json', currentInputs}));
    assert.equal(Object.hasOwn(restricted.entries[0], 'location'), false,
      '[check-mutation:session-format-input-set]');
  }
  const noPosition = value => {
    const shown = display(value);
    assert.equal(shown.entries[0].code, 'query_syntax_invalid');
    assert.equal(shown.observation.report.verdict, 'invalid');
    assert.equal(Object.hasOwn(shown.entries[0], 'location'), false,
      '[check-mutation:session-format-current]');
  };
  noPosition({...observation});
  noPosition(JSON.parse(JSON.stringify(observation)));
  session.update('é😀', 2);
  noPosition(observation);
  const current = await session.check({format: 'sql'});
  assert.equal(display(current).entries[0].location.range.start.character, 6);
  const other = createCheckDocumentSession(client, {text: 'é😀', version: 2});
  assert.equal(Object.hasOwn(JSON.parse(other.format(current, {format: 'json'})).entries[0], 'location'), false);
  session.close();
  noPosition(current);
  assert.equal(calls(), 2);
});

test('session display drops positions if option callbacks edit the current buffer', async t => {
  const {client, calls} = await fixture(t);
  const session = createCheckDocumentSession(client, {text: 'é😀', version: 1});
  const observation = await session.check({format: 'sql'});
  const shown = JSON.parse(session.format(observation, {format: 'json', get locale() {
    session.update('edited', 2); return 'ja';
  }}));
  assert.equal(Object.hasOwn(shown.entries[0], 'location'), false,
    '[check-mutation:session-format-options]');
  assert.equal(shown.observation.report.contextRef, 'ctx:session-presentation');
  assert.equal(shown.observation.report.verdict, 'invalid');
  assert.equal(calls(), 1);
});

test('session display rechecks its revision after current-input accessors run', async t => {
  const {client, calls} = await fixture(t);
  const session = createCheckDocumentSession(client, {text: 'é😀', version: 1});
  const observation = await session.check({format: 'sql'});
  let edited = false;
  const current = {documentId: 'source', revision, kind: 'text', get text() {
    if (!edited) { edited = true; session.update('edited', 2); }
    return 'é😀';
  }};
  const shown = JSON.parse(session.format(observation, {format: 'json', currentInputs: [current]}));
  assert.equal(Object.hasOwn(shown.entries[0], 'location'), false,
    '[check-mutation:session-format-recheck]');
  assert.equal(shown.observation.report.verdict, 'invalid');
  assert.equal(calls(), 1);
});

test('session display refuses old and pending requests even when their text is equal', async t => {
  const pending = [], {client} = await fixture(t, pending);
  const session = createCheckDocumentSession(client, {text: 'é😀', version: 1});
  const first = session.check({format: 'sql'}), second = session.check({format: 'sql'});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(pending.length, 2);
  pending[1](); const current = await second;
  pending[0](); const old = await first;
  const shown = value => JSON.parse(session.format(value, {format: 'json'}));
  assert.equal(Object.hasOwn(shown(old).entries[0], 'location'), false,
    '[check-mutation:session-format-order]');
  assert.equal(shown(current).entries[0].location.range.start.character, 3);
  const third = session.check({format: 'sql'});
  assert.equal(Object.hasOwn(shown(current).entries[0], 'location'), false,
    '[check-mutation:session-format-pending]');
  await new Promise(resolve => setImmediate(resolve)); pending[2](); await third;
});
