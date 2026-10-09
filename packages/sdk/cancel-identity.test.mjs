import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, explainCancellation} from './index.mjs';
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

test('cancellation lookup detachment cannot change a valid original outcome', async t => {
  const f = await fixture(t, () => ({kind: 'found', cancellation: original}));
  const clone = globalThis.structuredClone;
  t.after(() => { globalThis.structuredClone = clone; });
  globalThis.structuredClone = value => {
    const copy = clone(value);
    if (value.kind === 'found' && value.cancellation !== undefined) {
      copy.cancellation.kind = 'already_terminal';
    }
    return copy;
  };
  await assert.rejects(f.run.lookupCancellation(cancelRef), error => {
    assert.equal(error.code, 'InvalidHostCancellationLookup');
    assert.deepEqual(error.cancelRef, cancelRef);
    return true;
  });
  assert.equal(f.calls.filter(call => call.operation === 'cancel').length, 0);
});
