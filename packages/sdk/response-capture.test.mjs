import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import * as sdk from './index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const running = () => ({version: 'actql-run-state/0.1', run_id: 'original-run',
  status: 'needs_reconciliation', updated_at: '2026-10-07T00:00:00.000Z',
  next_action: {kind: 'reconcile', effects: ['e\u0301\r\n', 'é']},
  control: {revision: 7, cancellation_requested: true, physical_stop: 'unknown'},
  result_available: false, result_availability: {answer: {state: 'unavailable',
    reason: 'not_published', observed_at: '2026-10-07T00:00:00.000Z'}}});
const found = () => ({kind: 'found', requestId: 'saved', ref: {...ref},
  durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
const held = () => ({kind: 'held', requestId: 'saved', prepareAttemptId: 'original-attempt',
  state: 'resuming', durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
const delivered = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const streaming = () => {
  const reply = structuredClone(delivered);
  reply.record.state = 'streaming';
  delete reply.record.delivered_sha256;
  delete reply.record.result_delivery_receipt_cid;
  reply.hostReleaseReceipt = null;
  return reply;
};
const cases = [
  ...['status', 'wait', 'reconcile'].map(operation => ({operation, reply: running,
    field: 'run_id', replacement: 'replacement-run', error: 'InvalidHostRunState',
    invoke: run => run[operation](), explain: sdk.explainEffectUncertainty,
    failure: sdk.explainRunObservationFailure})),
  {operation: 'lookup-request', reply: found, field: 'ref',
    replacement: {...ref, runDefinitionCid: cid('d')}, error: 'InvalidHostRequestLookup',
    invoke: (_run, client) => client.lookupRequest('saved'), explain: sdk.explainRequestLookup,
    failure: sdk.explainRequestLookup},
  {operation: 'submit', reply: held, field: 'prepareAttemptId', replacement: 'replacement-attempt',
    error: 'SubmissionUnknown', invoke: (_run, client) => client.start({params: {}, stages: []}, {requestId: 'saved'})
      .catch(error => { if (error.code === 'RequestHeld') return error; throw error; }),
    explain: sdk.explainSubmission, failure: sdk.explainSubmission},
  {operation: 'cancel', reply: () => ({kind: 'accepted', ref: {...ref}, revision: 7}),
    field: 'kind', replacement: 'already_terminal', error: 'InvalidHostCancellation',
    invoke: run => run.cancel(), explain: sdk.explainCancellation, failure: sdk.explainCancellation},
  {operation: 'delivery-attempt', reply: streaming, field: 'record', replacement: delivered.record,
    error: 'InvalidHostAttemptLookup', invoke: run => run.result('answer').deliveryAttempt('read-a'),
    explain: sdk.explainDeliveryAttempt},
];
async function fixture(t, reply) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
      return reply;
    },
  });
  t.after(() => client.close());
  return {client, run: await client.attach(ref), calls};
}
for (const item of cases) {
  test(`${item.operation}: capture observes response getters once before admission`, async t => {
    const reply = item.reply(), first = reply[item.field];
    let reads = 0, secondReads = 0;
    Object.defineProperty(reply, item.field, {enumerable: true, configurable: true,
      get() { return ++reads === 1 ? first : item.replacement; }});
    if (item.operation === 'cancel') Object.defineProperty(reply, 'revision', {
      enumerable: true, get() { return ++secondReads === 1 ? 7 : 99; }});
    if (item.operation === 'delivery-attempt') Object.defineProperty(reply, 'hostReleaseReceipt', {
      enumerable: true, get() { return ++secondReads === 1 ? null : delivered.hostReleaseReceipt; }});
    const f = await fixture(t, reply), answer = await item.invoke(f.run, f.client);
    assert.equal(reads, 1, '[check-mutation:response-capture-once]');
    if (['cancel', 'delivery-attempt'].includes(item.operation)) assert.equal(secondReads, 1);
    assert.deepEqual(item.operation === 'submit' ? answer.held : answer, item.reply());
    const view = item.explain(answer);
    assert.ok(view);
    assert.equal(item.explain({...answer}), undefined);
    assert.equal(item.explain(structuredClone(answer)), undefined);
    if (item.operation === 'submit') {
      assert.equal(view.prepareAttemptId, 'original-attempt');
      assert.equal(sdk.getSubmissionInput(answer).requestId, 'saved');
    } else if (item.operation === 'lookup-request') assert.deepEqual(view.next, {operation: 'status', ref});
    else if (item.operation === 'cancel') assert.equal(view.observation, 'accepted');
    else if (item.operation === 'delivery-attempt') {
      assert.equal(view.observation, 'delivery_streaming');
      assert.equal(view.hostReleaseReceiptCid, undefined);
      assert.ok(Object.isFrozen(answer.record));
    } else {
      assert.deepEqual(view.effects, ['e\u0301\r\n', 'é']);
      assert.equal(Object.isFrozen(answer), false);
      answer.control.revision = 99;
      assert.equal(item.explain(answer).controlRevision, 7);
    }
    assert.deepEqual(f.calls, ['connect', 'attach', item.operation]);
    assert.equal(reads, 1);
  });
  test(`${item.operation}: throwing response getters retain only original uncertainty`, async t => {
    const reply = item.reply(); let reads = 0;
    Object.defineProperty(reply, item.field, {enumerable: true,
      get() { reads++; throw new Error('private getter value'); }});
    const f = await fixture(t, reply);
    await assert.rejects(item.invoke(f.run, f.client), error => {
      assert.equal(error.code, item.error);
      const view = item.failure?.(error);
      assert.doesNotMatch(JSON.stringify(view ?? null), /private getter value/);
      if (view?.next?.ref) assert.deepEqual(view.next.ref, ref);
      if (view?.next?.requestId) assert.equal(view.next.requestId, 'saved');
      return true;
    });
    assert.equal(reads, 1);
    assert.deepEqual(f.calls, ['connect', 'attach', item.operation]);
  });
}

for (const item of cases.filter(value => ['lookup-request', 'submit', 'cancel', 'delivery-attempt'].includes(value.operation))) {
  test(`${item.operation}: detachment cannot substitute another valid observation`, async t => {
    const reply = item.reply(), f = await fixture(t, reply), clone = globalThis.structuredClone;
    t.after(() => { globalThis.structuredClone = clone; });
    globalThis.structuredClone = value => {
      const copy = clone(value);
      if (value.kind === reply.kind && !Object.hasOwn(value, 'connection')) {
        copy[item.field] = clone(item.replacement);
        if (item.operation === 'delivery-attempt') copy.hostReleaseReceipt = clone(delivered.hostReleaseReceipt);
      }
      return copy;
    };
    await assert.rejects(item.invoke(f.run, f.client), error => error.code === item.error);
    assert.deepEqual(f.calls, ['connect', 'attach', item.operation]);
  });
}
test('held submit captures its branch before the first kind read', async t => {
  const reply = held(); let reads = 0;
  Object.defineProperty(reply, 'kind', {enumerable: true,
    get() { return ++reads === 1 ? 'held' : 'found'; }});
  const f = await fixture(t, reply);
  const answer = await cases.find(value => value.operation === 'submit').invoke(f.run, f.client);
  assert.equal(answer.code, 'RequestHeld');
  assert.equal(reads, 1);
});
test('Run rejection classification uses the same first captured status', async t => {
  const reply = running(); let reads = 0;
  Object.defineProperty(reply, 'status', {enumerable: true,
    get() { return ++reads === 1 ? 'future-state' : 'running'; }});
  const f = await fixture(t, reply);
  await assert.rejects(f.run.status(), error => {
    assert.equal(sdk.explainRunObservationFailure(error).problem, 'unknown_state');
    return error.code === 'InvalidHostRunState';
  });
  assert.equal(reads, 1);
});
test('Run capture reads shared nested objects once and preserves prototype-named own keys', async t => {
  let reads = 0;
  const availability = {get state() { reads++; return 'unavailable'; },
    reason: 'not_published', observed_at: '2026-10-07T00:00:00.000Z'};
  const reply = running();
  reply.result_availability = Object.create(null);
  for (const key of ['answer', '__proto__']) Object.defineProperty(reply.result_availability, key,
    {value: availability, enumerable: true});
  const f = await fixture(t, reply), answer = await f.run.status();
  assert.equal(reads, 1);
  assert.equal(Object.hasOwn(answer.result_availability, '__proto__'), true);
  assert.deepEqual(answer.result_availability.__proto__, answer.result_availability.answer);
  assert.equal(Object.getPrototypeOf(answer.result_availability), Object.prototype);
});
for (const [label, value] of [['undefined', undefined], ['nonfinite', Infinity],
  ['negative zero', -0], ['boxed string', new String('original-run')],
  ['function', () => 'original-run'], ['symbol', Symbol('original-run')], ['bigint', 1n]]) {
  test(`Run capture does not normalize malformed ${label} into a string`, async t => {
    const reply = running(); reply.run_id = value;
    const f = await fixture(t, reply);
    await assert.rejects(f.run.status(), error => error.code === 'InvalidHostRunState');
  });
}
test('Run capture rejects cyclic data without retaining a raw cause', async t => {
  const reply = running(); reply.next_action = reply;
  const f = await fixture(t, reply);
  await assert.rejects(f.run.status(), error => error.code === 'InvalidHostRunState' &&
    !Object.hasOwn(error, 'cause'));
});
test('response capture does not call toJSON to repair malformed data', async t => {
  let calls = 0;
  const reply = running(); reply.run_id = {toJSON() { calls++; return 'original-run'; }};
  const f = await fixture(t, reply);
  await assert.rejects(f.run.status(), error => error.code === 'InvalidHostRunState');
  assert.equal(calls, 0);
});

for (const method of ['every', 'map']) {
  test(`Run capture refuses an own array ${method} without invoking it`, async t => {
    let calls = 0;
    const reply = running();
    reply.next_action.effects[method] = () => { calls++; return method === 'every' ? true : []; };
    const f = await fixture(t, reply);
    await assert.rejects(f.run.status(), error => error.code === 'InvalidHostRunState');
    assert.equal(calls, 0);
  });
}
