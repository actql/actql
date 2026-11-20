import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, explainCancellation, formatCancellation} from './index.mjs';
import {connectInProcess} from './host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'original-namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'original-scope', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
async function fixture(t, lookup) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      calls.push({operation, body});
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 19};
      assert.equal(operation, 'lookup-cancellation');
      return lookup(body);
    },
  });
  t.after(() => client.close());
  return {run: await client.attach(ref), calls};
}
const unknown = () => ({kind: 'unknown', cancelRef: {...cancelRef}});
const nextLookup = {operation: 'lookupCancellation', cancelRef};
const unknownExplanation = {
  observation: 'outcome_unknown',
  summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
  next: nextLookup,
};

for (const [kind, revision, summary] of [
  ['accepted', 20, 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.'],
  ['already_requested', 21, 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.'],
  ['already_terminal', 19, 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.'],
]) {
  test(`cancellation lookup explains original ${kind} without stop or release claims`, async t => {
    const f = await fixture(t, () => ({kind: 'found', cancellation: {ref, cancelRef, kind, revision}}));
    const answer = await f.run.lookupCancellation(cancelRef);
    const expected = {observation: kind, revision, summary, next: {operation: 'status', ref}};
    assert.deepEqual(explainCancellation(answer), expected, '[check-mutation:cancel-lookup-found]');
    for (const format of ['text', 'html', 'json']) {
      const rendered = formatCancellation(answer, {format});
      assert.ok(rendered);
      if (format === 'json') assert.deepEqual(JSON.parse(rendered).explanation, expected);
    }
    assert.equal(explainCancellation({...answer}), undefined);
    assert.equal(explainCancellation(JSON.parse(JSON.stringify(answer))), undefined);
    assert.equal(Object.isFrozen(explainCancellation(answer)), true);
    assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation']);
  });
}

test('cancellation lookup uncertainty retains the original operation instead of current Run state', async t => {
  const f = await fixture(t, unknown);
  const answer = await f.run.lookupCancellation(cancelRef);
  assert.deepEqual(explainCancellation(answer), unknownExplanation, '[check-mutation:cancel-lookup-unknown]');
  assert.deepEqual(explainCancellation(answer, {locale: 'ja'}), {...unknownExplanation,
    summary: 'Run取消しの結果を確認できません。要求は記録されている可能性があります。'});
  assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation']);
});

for (const [label, reply, expectedCode] of [
  ['lost reply', () => {throw new Error('private provider cause');}, 'ClientTransportUnknown'],
  ['denied lookup', () => {throw new ClientError('ClientCancellationDenied', {status: 403});}, 'ClientCancellationDenied'],
  ['unknown variant', () => ({kind: 'future_success', cancelRef}), 'InvalidHostCancellationLookup'],
  ['foreign identity', () => ({kind: 'unknown', cancelRef: {...cancelRef, cancelId: 'foreign-cancel'}}), 'InvalidHostCancellationLookup'],
]) {
  test(`cancellation lookup ${label} offers only the original read-only target`, async t => {
    const f = await fixture(t, reply);
    let failure;
    await assert.rejects(f.run.lookupCancellation(cancelRef), error => {failure = error; return true;});
    assert.equal(failure.code, expectedCode);
    assert.deepEqual(explainCancellation(failure), unknownExplanation, '[check-mutation:cancel-lookup-failure]');
    failure.code = 'UnexpectedSuccess';
    assert.deepEqual(explainCancellation(failure), unknownExplanation);
    for (const format of ['text', 'html', 'json']) {
      const rendered = formatCancellation(failure, {format});
      assert.ok(rendered);
      assert.doesNotMatch(rendered, /private provider cause|UnexpectedSuccess|foreign-cancel/);
    }
    assert.equal(explainCancellation({...failure}), undefined);
    assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation']);
  });
}

test('reused cancellation lookups preserve each original outcome and input identity', async t => {
  const reused = unknown();
  const f = await fixture(t, () => reused);
  const input = {...cancelRef};
  const first = await f.run.lookupCancellation(input);
  input.cancelId = 'edited-cancel';
  delete reused.cancelRef;
  reused.kind = 'found';
  reused.cancellation = {ref, cancelRef, kind: 'accepted', revision: 20};
  const second = await f.run.lookupCancellation(cancelRef);
  assert.deepEqual(first, unknown());
  assert.deepEqual(explainCancellation(first), unknownExplanation);
  assert.equal(explainCancellation(second).observation, 'accepted');
  assert.equal(explainCancellation(second).revision, 20);
  assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation', 'lookup-cancellation']);
});

for (const [field, later] of [
  ['namespaceId', 'foreign-namespace'], ['authorityScopeCid', cid('c')],
  ['runDefinitionCid', cid('d')], ['cancelId', 'foreign-cancel'], ['expectedRevision', 23],
]) {
  test(`cancellation lookup captures the first ${field} before admission`, async t => {
    let reads = 0;
    const input = {...cancelRef};
    Object.defineProperty(input, field, {enumerable: true,
      get: () => ++reads === 1 ? cancelRef[field] : later});
    const f = await fixture(t, body => ({kind: 'unknown', cancelRef: {...body.ref,
      cancelId: body.cancelId, expectedRevision: body.expectedRevision}}));
    let answer, failure;
    try {answer = await f.run.lookupCancellation(input);} catch (error) {failure = error;}
    assert.equal(failure?.code, undefined);
    assert.deepEqual(f.calls.at(-1).body, {
      connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []},
      ref, cancelId: 'original-cancel', expectedRevision: 19},
      '[check-mutation:cancel-lookup-input-once]');
    assert.equal(reads, 1);
    assert.deepEqual(explainCancellation(answer), unknownExplanation);
  });
}

test('cancellation lookup captures caller identity once without a verification clone', async t => {
  const f = await fixture(t, body => ({kind: 'unknown', cancelRef: {...body.ref,
    cancelId: body.cancelId, expectedRevision: body.expectedRevision}}));
  const nativeClone = globalThis.structuredClone;
  const clone = t.mock.method(globalThis, 'structuredClone', value => {
    if (Object.hasOwn(value, 'connection')) return nativeClone(value);
    assert.fail('Unexpected response verification clone');
  });
  const answer = await f.run.lookupCancellation({...cancelRef});
  assert.deepEqual(explainCancellation(answer), unknownExplanation);
  assert.equal(clone.mock.calls.filter(({arguments: [value]}) => !Object.hasOwn(value, 'connection')).length, 0);
  assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation']);
});

for (const fault of ['replacement', 'mutation']) {
  test(`cancellation lookup preserves caller identity without clone ${fault}`, async t => {
    const f = await fixture(t, body => ({kind: 'unknown', cancelRef: {...body.ref,
      cancelId: body.cancelId, expectedRevision: body.expectedRevision}}));
    const nativeClone = globalThis.structuredClone;
    let conversions = 0;
    t.mock.method(globalThis, 'structuredClone', value => {
      if (Object.hasOwn(value, 'connection')) return nativeClone(value);
      conversions++;
      if (fault === 'mutation') value.cancelId = 'foreign-cancel';
      return {...nativeClone(value), cancelId: 'foreign-cancel'};
    });
    let answer, failure;
    try { answer = await f.run.lookupCancellation({...cancelRef}); }
    catch (error) { failure = error; }
    assert.equal(failure, undefined, '[check-mutation:cancel-lookup-no-conversion]');
    assert.equal(conversions, 0, '[check-mutation:cancel-lookup-no-conversion]');
    assert.deepEqual(explainCancellation(answer), unknownExplanation);
    assert.deepEqual(f.calls.at(-1).body, {
      connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []},
      ref, cancelId: 'original-cancel', expectedRevision: 19});
    assert.deepEqual(f.calls.map(c => c.operation), ['connect', 'attach', 'lookup-cancellation']);
  });
}
