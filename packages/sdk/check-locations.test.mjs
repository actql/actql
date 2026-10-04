import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {checkReasonSchemaCid} from '@actql/client-wire';
import {connect, getCheckInput, resolveCheckTextRange} from './index.mjs';

const revision = 'rev:' + '4'.repeat(64);
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'scope-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096, maxRows: 10,
    maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};

async function checkedInput(t, text, byteLength) {
  mock.method(globalThis, 'fetch', async url => url.pathname.endsWith('/connect')
    ? Response.json(profile) : Response.json({version: 'actql-check-outcome/0.1',
      reason_schema_cid: checkReasonSchemaCid, outcome: 'completed', report: {
        context_ref: 'ctx:fixture', scope: {kind: 'bound_input'}, verdict: 'invalid',
        inputs: [{document_id: 'source', kind: 'text', revision, byte_length: byteLength}],
        reasons: [{code: 'query_syntax_invalid', location: {kind: 'text',
          document_id: 'source', revision, start_byte: 0, end_byte: 0,
          precision: 'exact'}}], requirements: [], coverage: {limits: [], unresolved: []}}}));
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/', token: 'token'});
  const outcome = await client.check(text, {format: 'sql'});
  return {outcome, location: outcome.report.reasons[0].location};
}

test('UTF-16 check coordinates preserve BOM, scalars, combining marks and original newlines', async t => {
  // Literal byte offsets and coordinates are independent of the converter.
  const {outcome, location} = await checkedInput(t, '\ufeffAé😀e\u0301\r\nB\rC\n', 19);
  const cases = [[0, 0, 0], [3, 0, 1], [4, 0, 2], [6, 0, 3], [10, 0, 5],
    [11, 0, 6], [13, 0, 7], [15, 1, 0], [16, 1, 1], [17, 2, 0],
    [18, 2, 1], [19, 3, 0]];
  for (const [byte, line, character] of cases) {
    const resolved = resolveCheckTextRange(outcome, {...location, start_byte: byte, end_byte: byte});
    assert.deepEqual(resolved?.range, {start: {line, character}, end: {line, character}},
      '[check-mutation:editor-coordinates]');
    assert.equal(resolved.text, '');
    assert.equal(resolved.positionEncoding, 'utf-16');
    assert.equal(resolved.input, getCheckInput(outcome, 'source'));
    assert.equal(Object.isFrozen(resolved.range.start), true);
    assert.equal(Object.isFrozen(resolved.range), true);
  }
  const across = resolveCheckTextRange(outcome, {...location, start_byte: 4, end_byte: 18});
  assert.deepEqual(across.range, {start: {line: 0, character: 2}, end: {line: 2, character: 1}},
    '[check-mutation:editor-coordinates]');
  assert.equal(across.text, 'é😀e\u0301\r\nB\rC');
});

test('UTF-16 check coordinates omit CRLF interiors and non-scalar byte boundaries', async t => {
  const {outcome, location} = await checkedInput(t, '\ufeffAé😀e\u0301\r\nB\rC\n', 19);
  for (const [start, end] of [[14, 14], [13, 14], [14, 15], [0, 14],
    [1, 3], [7, 10], [-1, 0], [19, 20], [10, 6]]) {
    assert.equal(resolveCheckTextRange(outcome, {...location, start_byte: start, end_byte: end}),
      undefined, '[check-mutation:editor-boundary]');
  }
});

test('UTF-16 check coordinates retain approximate precision without granting edits', async t => {
  const {outcome, location} = await checkedInput(t, 'é😀', 6);
  const resolved = resolveCheckTextRange(outcome,
    {...location, start_byte: 0, end_byte: 6, precision: 'approximate'});
  assert.equal(resolved.precision, 'approximate');
  assert.deepEqual(resolved.range, {start: {line: 0, character: 0}, end: {line: 0, character: 3}});
  assert.equal(resolved.input.text, 'é😀');
});

test('UTF-16 check coordinates refuse copied reports, stale revisions and edited buffers', async t => {
  const {outcome, location} = await checkedInput(t, 'é😀', 6);
  const input = getCheckInput(outcome, 'source');
  for (const current of [{...input, text: 'xxxxxx'},
    {...input, revision: 'rev:' + '5'.repeat(64)}, {...input, documentId: 'reopened-source'}]) {
    assert.equal(resolveCheckTextRange(outcome, location, current), undefined,
      '[check-mutation:editor-revision]');
  }
  assert.equal(resolveCheckTextRange(JSON.parse(JSON.stringify(outcome)), location), undefined,
    '[check-mutation:editor-revision]');
  assert.equal(resolveCheckTextRange(outcome, {...location, revision: undefined}), undefined);
  assert.equal(resolveCheckTextRange(outcome, {...location, kind: 'structured', pointer: ''}), undefined);
});

test('malformed original Unicode is refused before editable check coordinates exist', async t => {
  await assert.rejects(checkedInput(t, '\ud800A', 4), {code: 'InvalidCheckRequest'});
});
