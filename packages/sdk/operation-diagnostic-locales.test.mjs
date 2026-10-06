import test from 'node:test';
import assert from 'node:assert/strict';
import * as sdk from './index.mjs';

const ref = {namespaceId: 'namespace-a', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope-a', capabilities: ['result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const unknown = {version: 'actql-run-state/0.1', run_id: 'run-a', status: 'needs_reconciliation',
  updated_at: '2026-10-06T00:00:00.000Z', next_action: {kind: 'reconcile', effects: ['save', 'notify']},
  result_available: false, result_availability: {answer: {state: 'unavailable',
    observed_at: '2026-10-06T00:00:00.000Z', reason: 'not_published'}},
  control: {revision: 7, cancellation_requested: true, physical_stop: 'unknown'}};
async function fixture(t) {
  const calls = [];
  let cancellation = 'accepted';
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'submit') throw new Error('private-provider-cause');
      if (operation === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
      if (operation === 'status') return unknown;
      if (operation === 'cancel') {
        if (cancellation === 'outcome_unknown') throw new Error('private-cancel-cause');
        return {kind: cancellation, ref: body.ref, revision: 7};
      }
      if (operation === 'read') return {kind: 'rows', frames: (async function* () {
        yield {value: {value: 1}, byteLength: 12};
        throw new Error('private-delivery-cause');
      })()};
      throw new Error('unexpected fixture operation: ' + operation);
    },
  });
  t.after(() => client.close());
  return {client, calls, cancel: kind => {cancellation = kind;}};
}

test('submission locale preserves the original unknown acceptance and lookup', async t => {
  const f = await fixture(t);
  let failure;
  try {await f.client.start({params: {}, stages: []}, {requestId: 'saved-request'});}
  catch (error) {failure = error;}
  assert.equal(failure.code, 'SubmissionUnknown');
  const expected = {observation: 'acceptance_unknown',
    summary: '送信の受理を確認できません。処理は既に始まっている可能性があります。',
    next: {operation: 'lookupRequest', requestId: 'saved-request',
      lookupContext: {endpoint: 'actql:embedded', scopeRef: 'scope-a'}}};
  const english = sdk.explainSubmission(failure);
  assert.deepEqual(sdk.explainSubmission(failure, {locale: 'ja-JP'}), expected,
    '[check-mutation:operation-submit-locale]');
  assert.equal(sdk.explainSubmission(failure, {locale: 'unknown'}), english);
  assert.equal(sdk.explainSubmission(failure, {get locale() {throw new Error('private-locale');}}), english);
  assert.deepEqual(sdk.explainSubmission(failure, {get locale() {
    failure.code = 'Succeeded'; failure.requestId = 'foreign'; return 'ja';
  }}), expected, '[check-mutation:operation-submit-custody]');
  assert.equal(sdk.explainSubmission({...failure}, {locale: 'ja'}), undefined);
  assert.deepEqual(f.calls, ['connect', 'submit'], '[check-mutation:operation-locale-passive]');
});

test('cancellation locale retains the recorded request and unconfirmed stop', async t => {
  const f = await fixture(t), execution = await f.client.attach(ref);
  for (const [kind, summary] of [
    ['accepted', 'HostはRunの取消し要求を記録しました。物理停止・Effect・解放はRunの現在状態で確認してください。'],
    ['already_requested', 'Hostは既存のRun取消し要求を報告しました。物理停止・Effect・解放はRunの現在状態で確認してください。'],
    ['already_terminal', 'Hostは取消しについてRunが既に終端状態にあると報告しました。Effect・解放の詳細はRunの現在状態で確認してください。'],
    ['outcome_unknown', 'Run取消しの結果を確認できません。要求は記録されている可能性があります。'],
  ]) {
    f.cancel(kind);
    let result;
    try {result = await execution.cancel();} catch (error) {result = error;}
    const before = [...f.calls];
    const expected = {observation: kind, ...(kind === 'outcome_unknown' ? {} : {revision: 7}),
      summary, next: {operation: 'status', ref}};
    const localized = sdk.explainCancellation(result, {locale: 'ja'});
    assert.deepEqual(localized, expected, '[check-mutation:operation-cancel-locale]');
    assert.equal(Object.isFrozen(localized), true);
    assert.equal(Object.isFrozen(localized.next.ref), true);
    assert.equal(sdk.explainCancellation({...result}, {locale: 'ja'}), undefined);
    assert.deepEqual(f.calls, before, '[check-mutation:operation-locale-passive]');
  }
});

test('read locale preserves caller-yielded rows and the original attempt', async t => {
  const f = await fixture(t), execution = await f.client.attach(ref);
  const reader = execution.result('answer').rows();
  let failure;
  try {await Array.fromAsync(reader);} catch (error) {failure = error;}
  const before = [...f.calls];
  assert.deepEqual(sdk.explainReadFailure(failure, {locale: 'ja'}), {
    observation: 'read_incomplete', attemptId: reader.attemptId, rowsYielded: 1,
    summary: 'この読み取りは1行を返した後で停止しました。',
    hint: 'この読み取り参照を保持してください。先頭から新しく読み取るか判断する前に、元の参照で状態を確認してください。',
    next: {operation: 'deliveryAttempt', ref, resultName: 'answer', attemptId: reader.attemptId,
      lookupContext: {endpoint: 'actql:embedded', scopeRef: 'scope-a'}},
  }, '[check-mutation:operation-read-locale]');
  assert.equal(sdk.explainReadFailure({...failure}, {locale: 'ja'}), undefined);
  assert.deepEqual(f.calls, before, '[check-mutation:operation-locale-passive]');
});

test('Effect locale retains separate uncertainty, control revision and physical stop', async t => {
  const f = await fixture(t), execution = await f.client.attach(ref), state = await execution.status();
  const before = [...f.calls];
  const expected = {observation: 'effect_outcome_unknown',
    summary: '外部Effectの結果は未確定です。計算の停止はEffectの結果や資源解放を示しません。',
    effects: ['save', 'notify'], physicalStop: 'unknown', controlRevision: 7,
    next: {operation: 'status', ref}};
  assert.deepEqual(sdk.explainEffectUncertainty(state, {get locale() {
    state.status = 'succeeded'; state.next_action.effects.length = 0;
    state.control.physical_stop = 'confirmed'; return 'ja';
  }}), expected, '[check-mutation:operation-effect-custody]');
  assert.equal(sdk.explainEffectUncertainty({...state}, {locale: 'ja'}), undefined);
  assert.deepEqual(f.calls, before, '[check-mutation:operation-locale-passive]');
});

test('operation locale identity is separate from check schemas and malformed options fall back', () => {
  for (const [options, locale] of [[undefined, 'en'], [{locale: 'ja'}, 'ja'], [{locale: 'ja-JP'}, 'ja'],
    [{locale: 'unknown'}, 'en'], [{get locale() {throw new Error('private-locale');}}, 'en']]) {
    const info = sdk.getOperationPresentationInfo(options);
    assert.deepEqual(info, {locale, translationRevision: `2026-10-06.operations.${locale}.1`},
      '[check-mutation:operation-locale-identity]');
    assert.equal(Object.isFrozen(info), true);
  }
  for (const explain of [sdk.explainSubmission, sdk.explainCancellation,
    sdk.explainReadFailure, sdk.explainEffectUncertainty]) {
    let reads = 0;
    assert.equal(explain({}, {get locale() {reads++; return 'ja';}}), undefined);
    assert.equal(reads, 0);
  }
});
