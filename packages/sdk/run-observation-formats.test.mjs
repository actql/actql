import assert from 'node:assert/strict';
import test from 'node:test';
import * as sdk from './index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'format-original-run', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable',
  scopeRef: 'format-principal', capabilities: [], limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const hint = 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.';
const cases = [
  ['unavailable', 'observation_unavailable', 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.', undefined],
  ['uninterpretable', 'unknown_state', 'The Run reply contains a state this SDK cannot interpret.', {version: 'actql-run-state/0.1', status: 'private-future-state'}],
  ['protocol_failure', 'contract_mismatch', 'The Run reply does not match this SDK’s registered state contract.', {version: 'private-state/0.1', status: 'running'}],
  ['protocol_failure', 'malformed_response', 'The Run reply violates the registered state contract.', {version: 'actql-run-state/0.1', status: 'running'}],
];
async function failure(t, operation, reply) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {perform(name, body) {
    calls.push(name);
    if (name === 'connect') return profile;
    if (name === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
    if (name === 'close') return;
    if (reply === undefined) throw new Error('private-provider-message');
    return reply;
  }});
  t.after(() => client.close());
  const run = await client.attach(ref);
  let error;
  try {await run[operation]();} catch (value) {error = value;}
  assert.ok(error instanceof sdk.ClientError);
  return {error, calls};
}
for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: Run failure formats preserve original classification and lookup without I/O`, async t => {
    for (const [kind, problem, summary, reply] of cases) {
      const {error, calls} = await failure(t, operation, reply);
      const expected = {kind, problem, operation, summary, hint, next: {operation: 'status', ref}};
      const sent = [...calls];
      const json = JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json'}));
      assert.deepEqual(json, {domain: 'observation', explanation: expected,
        presentation: {locale: 'en', translationRevision: '2026-10-09.operations.en.12'}},
        '[check-mutation:run-format-facts]');
      for (const format of ['text', 'html']) {
        const output = sdk.formatRunObservationFailure(error, {format});
        assert.equal(output.includes(`observation/${kind}:`), true, '[check-mutation:run-format-kind]');
        assert.ok(output.includes(problem));
        assert.ok(output.includes(ref.runDefinitionCid));
      }
      const translated = JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json', get locale() {
        error.kind = 'success'; error.problem = 'verified'; error.next = {operation: 'submit'};
        return 'ja';
      }}));
      const {summary: translatedSummary, hint: translatedHint, ...facts} = translated.explanation;
      const {summary: englishSummary, hint: englishHint, ...original} = expected;
      assert.deepEqual(facts, original, '[check-mutation:run-format-authority]');
      assert.equal(translated.presentation.locale, 'ja');
      assert.notEqual(translatedSummary, englishSummary);
      assert.notEqual(translatedHint, englishHint);
      assert.doesNotMatch(JSON.stringify(json), /private-provider-message|private-future-state|private-state/,
        '[check-mutation:run-format-disclosure]');
      for (const copied of [{...error}, JSON.parse(JSON.stringify(error)), new sdk.ClientError(error.code)]) {
        assert.equal(sdk.formatRunObservationFailure(copied), undefined, '[check-mutation:run-format-custody]');
      }
      assert.equal(sdk.formatRunObservationFailure(error, {get locale() {throw new Error('private-locale');}}),
        sdk.formatRunObservationFailure(error));
      assert.deepEqual(calls, sent, '[check-mutation:run-format-passive]');
    }
  });
}
test('Run failure formatting bounds and unknown inputs do not create presentation custody', async t => {
  const {error} = await failure(t, 'status');
  for (const options of [{format: 'future'}, {maxBytes: 0}, {maxBytes: Infinity}, {maxBytes: 1048577},
    {get format() {throw new Error('private-option');}}]) assert.equal(sdk.formatRunObservationFailure(error, options), undefined);
  let reads = 0;
  assert.equal(sdk.formatRunObservationFailure({}, {get locale() {reads++; return 'ja';}}), undefined);
  assert.equal(reads, 0);
  for (const format of ['text', 'html', 'json']) {
    const value = sdk.formatRunObservationFailure(error, {format, maxBytes: 1024});
    assert.ok(value === undefined || Buffer.byteLength(value) <= 1024);
    if (value !== undefined && format === 'json') assert.deepEqual(JSON.parse(value).explanation.next, {operation: 'status', ref});
  }
});
