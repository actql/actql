import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, explainCancellation, formatCancellation} from './index.mjs';
import {connectInProcess} from './host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
const original = {ref, cancelRef, kind: 'accepted', revision: 20};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'local-scope', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
async function fixture(t, perform) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      calls.push({operation, body});
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 19};
      return perform(operation, body);
    },
  });
  t.after(() => client.close());
  return {client, run: await client.attach(ref), calls};
}

test('lost cancel response retains the exact original identity and only looks it up', async t => {
  const f = await fixture(t, (operation, body) => {
    if (operation === 'cancel') throw new Error('RESPONSE_LOST');
    assert.equal(operation, 'lookup-cancellation');
    assert.equal(body.cancelId, 'original-cancel');
    assert.equal(body.expectedRevision, 19);
    return {kind: 'found', cancellation: original};
  });
  let failure;
  await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19}), error => {
    failure = error;
    assert.equal(error.code, 'CancellationUnknown');
    assert.deepEqual(error.cancelRef, cancelRef);
    assert(Object.isFrozen(error.cancelRef));
    return true;
  });
  const result = await f.run.lookupCancellation(failure.cancelRef);
  assert.deepEqual(result, {kind: 'found', cancellation: original});
  assert(Object.isFrozen(result.cancellation.cancelRef));
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'attach', 'cancel', 'lookup-cancellation']);
});

test('a transported conflict code is not an owner-issued operation outcome', async t => {
  const f = await fixture(t, () => { throw new ClientError('ClientCancellationIntentConflict', {status: 409}); });
  await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19}), error => {
    assert.equal(error.code, 'CancellationUnknown');
    assert.deepEqual(error.cancelRef, cancelRef);
    return true;
  });
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 1);
});

for (const code of ['ClientAuthenticationDenied', 'ClientConnectionDenied',
  'ClientCancellationDenied', 'ClientCancellationRevisionConflict',
  'InvalidClientRequest', 'InvalidClientCancellationOperation', 'ClientOperationUnavailable']) {
  test(`transported ${code} does not certify an uncommitted cancellation attempt`, async t => {
    const f = await fixture(t, () => { throw new ClientError(code, {status: 403}); });
    await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19}), error => {
      assert.equal(error.code, 'CancellationUnknown');
      assert.deepEqual(error.cancelRef, cancelRef);
      assert.equal(explainCancellation(error)?.observation, 'outcome_unknown');
      return true;
    });
    assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 1);
    assert.equal(f.calls.filter(call => call.operation === 'lookup-cancellation').length, 0);
  });
}

test('typed Refused binds the invocation without granting retry authority', async t => {
  const f = await fixture(t, (operation, body) => {
    assert.equal(operation, 'cancel');
    assert.deepEqual(body.attemptRef, {operation: 'cancel', attemptId: 'denied-attempt'});
    return {kind: 'refused', attemptRef: {operation: 'cancel', attemptId: 'denied-attempt'},
      guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'};
  });
  assert.deepEqual(await f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19,
    attemptId: 'denied-attempt'}), {kind: 'refused',
    attemptRef: {operation: 'cancel', attemptId: 'denied-attempt'},
    guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'});
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'attach', 'cancel']);
});

test('typed revision Conflict preserves the original cancellation reference', async t => {
  const f = await fixture(t, () => ({kind: 'conflict', reason: 'control_revision',
    attemptRef: {operation: 'cancel', attemptId: 'stale-attempt'}, cancelRef}));
  const answer = await f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19,
    attemptId: 'stale-attempt'});
  assert.deepEqual(answer, {kind: 'conflict', reason: 'control_revision',
    attemptRef: {operation: 'cancel', attemptId: 'stale-attempt'}, cancelRef});
  assert(Object.isFrozen(answer.attemptRef));
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 1);
});

for (const [kind, reason, summary, localized] of [
  ['refused', 'authorization',
    'The Host refused this cancellation invocation under current authorization. This invocation committed no cancellation and consumed no operation identity.',
    'Hostは現在の認可により今回の取消し呼出しを拒否しました。今回の呼出しは取消しをcommitせず、操作identityも消費していません。'],
  ['refused', 'admission_capacity',
    'The Host refused this cancellation invocation because admission capacity was unavailable. This invocation committed no cancellation and consumed no operation identity.',
    'Hostは受付容量が不足しているため今回の取消し呼出しを拒否しました。今回の呼出しは取消しをcommitせず、操作identityも消費していません。'],
  ['conflict', 'intent',
    'The Host reports a conflicting intent for this original cancellation identity.',
    'Hostは元の取消しidentityに対する意図の競合を報告しています。'],
  ['conflict', 'control_revision',
    'The Host reports a conflict with the submitted control revision for this cancellation invocation.',
    'Hostは今回の取消し呼出しで提出したcontrol revisionとの競合を報告しています。'],
]) {
  test(`typed cancellation ${kind}/${reason} explains only its original invocation`, async t => {
    const attemptRef = {operation: 'cancel', attemptId: 'explained-invocation'};
    const reply = {kind, reason, attemptRef,
      ...(kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {cancelRef})};
    const f = await fixture(t, () => reply);
    const answer = await f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19,
      attemptId: 'explained-invocation'});
    const expected = {observation: kind, reason,
      attemptRef: {operation: 'cancel', attemptId: 'explained-invocation'}, cancelRef,
      ...(kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {}),
      summary,
      hint: 'Keep the original cancellation reference and use a currently authorized lookup. This invocation outcome does not establish another invocation\'s outcome, grant permission to resend, or confirm physical stop, external Effects or resource release.',
      next: {operation: 'lookupCancellation', cancelRef}};
    assert.deepEqual(explainCancellation(answer), expected, '[check-mutation:cancel-attempt-explanation]');
    const explanation = explainCancellation(answer);
    assert(Object.isFrozen(explanation));
    assert(Object.isFrozen(explanation.attemptRef));
    assert(Object.isFrozen(explanation.cancelRef));
    assert(Object.isFrozen(explanation.next.cancelRef));
    assert.equal(Object.hasOwn(explanation, 'revision'), false);
    for (const copied of [{...answer}, structuredClone(answer), JSON.parse(JSON.stringify(answer))]) {
      assert.equal(explainCancellation(copied), undefined, '[check-mutation:cancel-attempt-custody]');
      assert.equal(formatCancellation(copied), undefined);
    }
    reply.kind = 'accepted';
    reply.reason = 'private-reason';
    attemptRef.attemptId = 'other-invocation';
    assert.deepEqual(explainCancellation(answer), expected);
    assert.deepEqual(explainCancellation(answer, {locale: 'ja'}), {...expected,
      summary: localized,
      hint: '元の取消し参照を保持し、現在の認可で照会してください。今回の呼出し結果は別の呼出しの結果を確定せず、再送信を許可せず、物理停止・外部Effect・資源解放を確認しません。'});
    for (const format of ['text', 'html', 'json']) {
      const rendered = formatCancellation(answer, {format});
      assert.ok(rendered);
      assert.doesNotMatch(rendered, /private-reason|other-invocation/);
      if (format === 'json') assert.deepEqual(JSON.parse(rendered).explanation, expected);
    }
    assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'attach', 'cancel'],
      '[check-mutation:cancel-attempt-passive]');
  });
}

for (const change of ['attempt', 'operation', 'guarantee', 'target']) {
  test(`a borrowed or contradictory typed refusal (${change}) remains unknown`, async t => {
    const reply = {kind: 'refused', reason: 'authorization',
      attemptRef: {operation: 'cancel', attemptId: 'original-attempt'},
      guarantee: 'attempt_uncommitted_unconsumed', cancelRef};
    if (change === 'attempt') reply.attemptRef.attemptId = 'other-attempt';
    if (change === 'operation') reply.attemptRef.operation = 'submit';
    if (change === 'guarantee') reply.guarantee = 'nothing_executed';
    if (change === 'target') reply.cancelRef = {...cancelRef, runDefinitionCid: cid('f')};
    const f = await fixture(t, () => reply);
    await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19,
      attemptId: 'original-attempt'}), error => {
      assert.equal(error.code, 'CancellationUnknown');
      assert.deepEqual(error.attemptRef, {operation: 'cancel', attemptId: 'original-attempt'});
      assert.deepEqual(error.cancelRef, cancelRef);
      return true;
    });
  });
}

for (const change of [{cancelId: 'foreign-cancel'}, {expectedRevision: 20}, {runDefinitionCid: cid('f')}]) {
  test(`foreign cancellation reply ${Object.keys(change)[0]} is unknown under the original identity`, async t => {
    const f = await fixture(t, () => ({...original, cancelRef: {...cancelRef, ...change}}));
    await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19}), error => {
      assert.equal(error.code, 'CancellationUnknown');
      assert.deepEqual(error.cancelRef, cancelRef);
      return true;
    });
  });
}

test('exact cancellation lookup rejects a changed operation without dispatching', async t => {
  const f = await fixture(t, () => ({kind: 'found', cancellation: {...original,
    cancelRef: {...cancelRef, expectedRevision: 20}}}));
  await assert.rejects(f.run.lookupCancellation(cancelRef), {code: 'InvalidHostCancellationLookup'});
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 0);
  await assert.rejects(f.run.lookupCancellation({...cancelRef, runDefinitionCid: cid('f')}),
    {code: 'InvalidCancellationReference'});
  assert.equal(f.calls.filter(call => call.operation === 'lookup-cancellation').length, 1);
});

test('a closed Client refuses an explicit cancellation before any dispatch or uncertainty advice', async t => {
  const f = await fixture(t, () => assert.fail('Closed Client must never dispatch'));
  f.client.close();
  await assert.rejects(f.run.cancel({cancelId: 'original-cancel', expectedRevision: 19}),
    error => {
      assert.equal(error.code, 'ClientClosed');
      assert.equal(explainCancellation(error), undefined);
      return true;
    });
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 0);
});

test('invalid cancellation identity is refused before observing a revision or dispatching', async t => {
  const f = await fixture(t, () => assert.fail('Invalid operation must never be observed or dispatched'));
  for (const options of [{cancelId: ''}, {cancelId: 'bad\ridentity'},
    {cancelId: 'original-cancel', expectedRevision: null},
    {cancelId: 'original-cancel', expectedRevision: 2147483648}]) {
    await assert.rejects(f.run.cancel(options), {code: 'InvalidCancellationReference'});
  }
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'attach']);
});

test('original cancellation lookup captures nested identity and outcome exactly once', async t => {
  let identityReads = 0, kindReads = 0;
  const cancellation = {...original};
  Object.defineProperty(cancellation, 'cancelRef', {enumerable: true,
    get() { return ++identityReads === 1 ? cancelRef : {...cancelRef, cancelId: 'replacement'}; }});
  Object.defineProperty(cancellation, 'kind', {enumerable: true,
    get() { return ++kindReads === 1 ? 'accepted' : 'already_terminal'; }});
  const f = await fixture(t, () => ({kind: 'found', cancellation}));
  const observed = await f.run.lookupCancellation(cancelRef);
  assert.deepEqual(observed, {kind: 'found', cancellation: original});
  assert.equal(identityReads, 1);
  assert.equal(kindReads, 1);
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'attach', 'lookup-cancellation']);
});

test('cancellation lookup uses its captured original with no verification clone', async t => {
  const f = await fixture(t, () => ({kind: 'found', cancellation: original}));
  const nativeClone = globalThis.structuredClone;
  const clone = t.mock.method(globalThis, 'structuredClone', value => {
    if (Object.hasOwn(value, 'connection')) return nativeClone(value);
    assert.fail('Unexpected response verification clone');
  });
  const answer = await f.run.lookupCancellation(cancelRef);
  assert.deepEqual(answer, {kind: 'found', cancellation: original});
  assert.equal(clone.mock.calls.filter(({arguments: [value]}) => !Object.hasOwn(value, 'connection')).length, 0);
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 0);
});
