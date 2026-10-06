import assert from 'node:assert/strict';
import test from 'node:test';
import * as sdk from './index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'format-scope', capabilities: [], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
async function observations(t, {requestId = 'original-request', effects = ['save', 'notify']} = {}) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
      if (operation === 'submit') throw new Error('private-provider-message');
      if (operation === 'cancel') return {kind: 'accepted', ref: body.ref, revision: 7};
      if (operation === 'status') return {version: 'actql-run-state/0.1', run_id: 'run-a',
        status: 'needs_reconciliation', updated_at: '2026-10-07T00:00:00.000Z',
        next_action: {kind: 'reconcile', effects}, result_available: false,
        result_availability: {answer: {state: 'unavailable', reason: 'not_published',
          observed_at: '2026-10-07T00:00:00.000Z'}},
        control: {revision: 8, cancellation_requested: true, physical_stop: 'unknown'}};
      if (operation === 'read') return {kind: 'rows', frames: (async function* () {
        yield {value: {value: 1}, byteLength: 12};
        throw new Error('private-delivery-message');
      })()};
      if (operation !== 'close') assert.fail('Unexpected operation');
    },
  });
  t.after(() => client.close());
  let submission, read;
  try { await client.start({params: {}, stages: []}, {requestId}); } catch (error) {submission = error;}
  const run = await client.attach(ref);
  const cancellation = await run.cancel(), effect = await run.status();
  try { await Array.fromAsync(run.result('answer').rows()); } catch (error) {read = error;}
  return {calls, cases: [
    ['submission', submission, sdk.explainSubmission, sdk.formatSubmission, 'acceptance_unknown'],
    ['cancellation', cancellation, sdk.explainCancellation, sdk.formatCancellation, 'accepted'],
    ['read', read, sdk.explainReadFailure, sdk.formatReadFailure, 'read_incomplete'],
    ['effect', effect, sdk.explainEffectUncertainty, sdk.formatEffectUncertainty, 'effect_outcome_unknown'],
  ]};
}

test('operation formats retain typed facts, original lookup references and unknown outcomes without I/O', async t => {
  const f = await observations(t), calls = [...f.calls];
  for (const [domain, value, explain, format, observation] of f.cases) {
    const expected = explain(value);
    assert.equal(expected.observation, observation);
    for (const locale of ['en', 'ja']) {
      const json = JSON.parse(format(value, {format: 'json', locale}));
      assert.deepEqual(json, {domain, explanation: explain(value, {locale}),
        presentation: sdk.getOperationPresentationInfo({locale})}, '[check-mutation:operation-format-facts]');
      assert.equal(Object.hasOwn(json, 'permission'), false);
      assert.equal(Object.hasOwn(json, 'verdict'), false);
      assert.match(format(value, {locale}), new RegExp('^' + domain + '/' + observation));
      assert.match(format(value, {format: 'html', locale}), /^<section><h2>/);
      assert.doesNotMatch(JSON.stringify(json), /private-provider-message|private-delivery-message/,
        '[check-mutation:operation-format-disclosure]');
    }
    const before = JSON.parse(format(value, {format: 'json'}));
    const hostile = JSON.parse(format(value, {format: 'json', get locale() {
      value.message = 'success'; value.code = 'Succeeded'; value.next = {operation: 'submit'};
      value.rowsYielded = 0; value.effects = []; return 'ja';
    }}));
    const {summary, hint, ...facts} = before.explanation;
    const {summary: translated, hint: translatedHint, ...translatedFacts} = hostile.explanation;
    assert.deepEqual(translatedFacts, facts, '[check-mutation:operation-format-authority]');
    assert.equal(format({...value}, {format: 'json'}), undefined, '[check-mutation:operation-format-custody]');
    assert.equal(format(new sdk.ClientError(value.code)), undefined);
    assert.equal(format(value, {get locale() {throw new Error('private-locale');}}), format(value));
    void summary; void hint; void translated; void translatedHint;
  }
  assert.deepEqual(f.calls, calls, '[check-mutation:operation-format-passive]');
});

test('operation format escaping retains control and markup bytes as data', async t => {
  const requestId = '<img src=x onerror="run()">\u202e\u2066\u061c\u0085\u001b[2J\n';
  const {cases} = await observations(t, {requestId});
  const [, failure] = cases[0];
  for (const format of ['text', 'html', 'json']) {
    const output = sdk.formatSubmission(failure, {format});
    assert.ok(output);
    assert.doesNotMatch(output, /[\u202e\u2066\u061c\u0085\u001b]/u, '[check-mutation:operation-format-escaping]');
    assert.doesNotMatch(output, /<img|onerror="run/u);
    if (format === 'json') assert.equal(JSON.parse(output).explanation.next.requestId, requestId);
  }
});

test('operation format budgets refuse to drop unresolved effects or original lookup facts', async t => {
  const effects = Array.from({length: 50}, (_, i) => `effect-${i}-${'x'.repeat(200)}`);
  const {cases} = await observations(t, {effects});
  const [, state] = cases[3];
  for (const format of ['text', 'html', 'json']) {
    assert.equal(sdk.formatEffectUncertainty(state, {format, maxBytes: 1024}), undefined,
      '[check-mutation:operation-format-budget]');
    const output = sdk.formatEffectUncertainty(state, {format, maxBytes: 65536});
    assert.ok(Buffer.byteLength(output) <= 65536);
    if (format === 'json') assert.deepEqual(JSON.parse(output).explanation.effects, effects);
  }
  for (const options of [{format: 'future'}, {maxBytes: 0}, {maxBytes: Infinity}, {maxBytes: 1048577},
    {get format() {throw new Error('private option');}}]) assert.equal(sdk.formatEffectUncertainty(state, options), undefined);
  for (const format of [sdk.formatSubmission, sdk.formatCancellation, sdk.formatReadFailure, sdk.formatEffectUncertainty]) {
    let reads = 0;
    assert.equal(format({}, {get locale() {reads++; return 'ja';}}), undefined);
    assert.equal(reads, 0);
  }
});
