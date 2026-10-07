import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import * as sdk from './index.mjs';
import {connectInProcess} from './host-port.mjs';
import {ClientError, explainRunObservationFailure, explainEffectUncertainty} from './index.mjs';
import {validRunState} from '../client-wire/index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'observation-namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'observation-principal', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const running = () => ({version: 'actql-run-state/0.1', run_id: 'original-run',
  status: 'running', updated_at: '2026-10-07T00:00:00.000Z',
  next_action: {kind: 'none'}, result_available: false, result_availability: {answer: {state: 'unavailable', reason: 'not_published', observed_at: '2026-10-07T00:00:00.000Z'}}});
const capture = async promise => {
  let rejected;
  try { await promise; } catch (error) { rejected = error; }
  assert.equal(rejected?.code, 'InvalidHostRunState', '[check-mutation:run-protocol-rejection]');
  return rejected;
};
async function fixture(t, reply) {
  const operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      operations.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref: {...ref}, durability: 'durable', revision: 1};
      if (operation === 'close') return;
      assert.deepEqual(body.ref, ref);
      return reply(operation);
    },
  });
  t.after(() => client.close());
  return {run: await client.attach(ref), operations};
}
for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: rejected Run observations distinguish unknown state from malformed known facts`, async t => {
    let reply;
    const {run, operations} = await fixture(t, () => reply);
    for (const [value, kind, problem] of [
      [{...running(), status: 'private-future-state'}, 'uninterpretable', 'unknown_state'],
      [{...running(), result_available: 'true'}, 'protocol_failure', 'malformed_response'],
      [{...running(), version: 'actql-private-future-state/0.1'}, 'protocol_failure', 'contract_mismatch'],
      [{...running(), version: undefined}, 'protocol_failure', 'malformed_response'],
      [{...running(), next_action: {kind: 'future_write', private_value: 'private'}}, 'protocol_failure', 'malformed_response'],
    ]) {
      reply = value;
      const error = await capture(run[operation]());
      const view = explainRunObservationFailure(error);
      assert.deepEqual({kind: view.kind, problem: view.problem, operation: view.operation}, {kind, problem, operation},
        '[check-mutation:run-protocol-kind]');
      assert.deepEqual(view.next, {operation: 'status', ref}, '[check-mutation:run-protocol-ref]');
      assert.ok(Object.isFrozen(view.next.ref));
      assert.equal(explainEffectUncertainty(error), undefined);
      assert.equal(explainRunObservationFailure({...error}), undefined);
      assert.equal(explainRunObservationFailure(structuredClone(error)), undefined);
      for (const key of ['state', 'revision', 'status', 'resultAvailable', 'effects', 'cause']) assert.equal(Object.hasOwn(view, key), false);
      assert.doesNotMatch(JSON.stringify({error, view}), /private-future-state|private_value/,
        '[check-mutation:run-protocol-disclosure]');
      const japanese = explainRunObservationFailure(error, {get locale() {
        error.kind = 'success'; error.problem = 'verified'; error.next = {operation: 'submit'}; return 'ja';
      }});
      assert.deepEqual({kind: japanese.kind, problem: japanese.problem, operation: japanese.operation, next: japanese.next},
        {kind, problem, operation, next: {operation: 'status', ref}}, '[check-mutation:run-protocol-presentation]');
      assert.equal(explainRunObservationFailure(error, {get locale() {throw new Error('private');}}).kind, kind);
    }
    assert.deepEqual(operations, ['connect', 'attach', ...Array(5).fill(operation)], '[check-mutation:run-protocol-passive]');
  });
}

test('Run protocol observations do not invoke rejected getters or retain arbitrary exceptions', async t => {
  let reads = 0;
  const value = {...running(), get status() { reads++; throw new Error('private getter failure'); }};
  const {run} = await fixture(t, () => value);
  const error = await capture(run.status());
  assert.equal(reads, 1);
  assert.equal(explainRunObservationFailure(error).problem, 'malformed_response');
  assert.equal(Object.hasOwn(error, 'cause'), false);
  assert.equal(explainRunObservationFailure(new ClientError('InvalidHostRunState')), undefined);
});

test('Run protocol explanations preserve earlier valid observations and transport refusals', async t => {
  let reply = running();
  const {run} = await fixture(t, () => { if (reply instanceof Error) throw reply; return reply; });
  const before = await run.status();
  reply.status = 'private-future-state';
  const error = await capture(run.status());
  assert.equal(before.status, 'running');
  assert.equal(explainRunObservationFailure(before), undefined);
  reply = new ClientError('ClientOperationUnavailable');
  await assert.rejects(run.reconcile(), current => current === reply && explainRunObservationFailure(current) === undefined);
  assert.equal(explainRunObservationFailure(error).problem, 'unknown_state');
});

const unresolved = () => ({...running(), status: 'needs_reconciliation',
  next_action: {kind: 'reconcile', effects: ['e\u0301\r\n', 'é']},
  control: {revision: 7, cancellation_requested: true, physical_stop: 'unknown'}});
const copyFaults = [
  ['execution and publication', copy => {
    copy.status = 'succeeded'; copy.next_action = {kind: 'read_result', results: ['answer']};
    copy.result_available = true;
    copy.result_availability.answer = {state: 'available', reason: 'confirmed_present',
      observed_at: '2026-10-07T00:00:00.000Z'};
  }],
  ['Run identity', copy => { copy.run_id = 'another-run'; }],
  ['observation time', copy => { copy.updated_at = '2026-10-07T01:00:00.000Z'; }],
  ['control revision', copy => { copy.control.revision = 8; }],
  ['physical stop', copy => { copy.control.physical_stop = 'confirmed'; }],
  ['Effect identity', copy => { copy.next_action.effects[0] = 'é\r\n'; }],
  ['Result availability', copy => {
    copy.result_availability.answer = {state: 'unknown', reason: 'verification_pending',
      observed_at: '2026-10-07T00:00:00.000Z'};
  }],
];
for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: equivalent Run copies preserve original strings and explanation custody`, async t => {
    const original = unresolved();
    const {run} = await fixture(t, () => original);
    const clone = globalThis.structuredClone;
    t.after(() => { globalThis.structuredClone = clone; });
    globalThis.structuredClone = value => {
      const copy = clone(value);
      return value?.version === 'actql-run-state/0.1'
        ? Object.fromEntries(Object.entries(copy).reverse()) : copy;
    };
    const answer = await run[operation]();
    original.next_action.effects[0] = 'later-host-value';
    original.control.physical_stop = 'confirmed';
    assert.deepEqual(answer, unresolved());
    const view = explainEffectUncertainty(answer);
    assert.deepEqual({effects: view.effects, physicalStop: view.physicalStop,
      controlRevision: view.controlRevision}, {
      effects: ['e\u0301\r\n', 'é'], physicalStop: 'unknown', controlRevision: 7,
    });
    answer.control.physical_stop = 'confirmed';
    assert.equal(explainEffectUncertainty(answer).physicalStop, 'unknown');
    assert.equal(explainEffectUncertainty({...answer}), undefined);
    assert.equal(explainEffectUncertainty(clone(answer)), undefined);
  });
  for (const [name, alter] of copyFaults) {
    test(`${operation}: copied Run observation cannot replace ${name}`, async t => {
      const original = unresolved();
      const {run, operations} = await fixture(t, () => original);
      const clone = globalThis.structuredClone;
      t.after(() => { globalThis.structuredClone = clone; });
      globalThis.structuredClone = value => {
        const copy = clone(value);
        if (value?.version === 'actql-run-state/0.1') {
          alter(copy);
          assert.equal(validRunState(copy), true, 'Fault must retain the known wire shape');
        }
        return copy;
      };
      let rejected;
      try { await run[operation](); } catch (error) { rejected = error; }
      assert.equal(rejected?.code, 'InvalidHostRunState', '[check-mutation:run-copy-preservation]');
      assert.deepEqual(explainRunObservationFailure(rejected)?.next, {operation: 'status', ref});
      assert.equal(explainEffectUncertainty(rejected), undefined);
      assert.equal(Object.hasOwn(rejected, 'cause'), false);
      assert.deepEqual(operations, ['connect', 'attach', operation]);
      assert.deepEqual(original, unresolved());
    });
  }
  test(`${operation}: later Effect projection cannot replace admitted Run facts`, async t => {
    const {run} = await fixture(t, () => unresolved());
    const clone = globalThis.structuredClone;
    let copies = 0;
    t.after(() => { globalThis.structuredClone = clone; });
    globalThis.structuredClone = value => {
      const copy = clone(value);
      if (value?.version === 'actql-run-state/0.1' && ++copies > 1) {
        copy.control.physical_stop = 'confirmed';
        copy.control.revision = 8;
        copy.next_action.effects[0] = 'é\r\n';
      }
      return copy;
    };
    let answer, failure;
    try { answer = await run[operation](); } catch (error) { failure = error; }
    if (failure) {
      assert.equal(failure.code, 'InvalidHostRunState');
      assert.equal(explainRunObservationFailure(failure).problem, 'malformed_response');
      return;
    }
    const view = explainEffectUncertainty(answer);
    assert.deepEqual({control: answer.control, effects: answer.next_action.effects,
      physicalStop: view.physicalStop, controlRevision: view.controlRevision,
      retainedEffects: view.effects}, {
      control: {revision: 7, cancellation_requested: true, physical_stop: 'unknown'},
      effects: ['e\u0301\r\n', 'é'], physicalStop: 'unknown', controlRevision: 7,
      retainedEffects: ['e\u0301\r\n', 'é'],
    }, '[check-mutation:run-effect-projection-copy]');
  });
}

const delivery = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const checked = JSON.parse(readFileSync(new URL('../client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
const held = () => ({kind: 'held', requestId: 'saved', prepareAttemptId: 'original-attempt',
  state: 'resuming', durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
const lookup = () => ({kind: 'found', requestId: 'saved', ref: {...ref},
  durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
const cancellation = () => ({kind: 'accepted', ref: {...ref}, revision: 7});
async function responseFixture(t, reply) {
  const operations = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation) {
      operations.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref: {...ref}, durability: 'durable', revision: 1};
      if (operation === 'close') return;
      return reply;
    },
  });
  t.after(() => client.close());
  return {client, run: await client.attach(ref), operations};
}
function changing(object, key, first, later, counts) {
  Object.defineProperty(object, key, {enumerable: true, configurable: true,
    get() { counts[key] = (counts[key] ?? 0) + 1; return counts[key] === 1 ? first : later; }});
}
const paths = [
  ...['status', 'wait', 'reconcile'].map(operation => ({name: operation,
    reply: running, call: f => f.run[operation](), code: 'InvalidHostRunState', key: 'run_id',
    first: 'original-run', later: 'replacement-run',
    assert: answer => assert.equal(answer.run_id, 'original-run', '[check-mutation:response-capture-run]')})),
  {name: 'lookupRequest', reply: lookup, call: f => f.client.lookupRequest('saved'),
    code: 'InvalidHostRequestLookup', key: 'ref', first: ref, later: {...ref, runDefinitionCid: cid('c')},
    assert: answer => assert.deepEqual({ref: answer.ref, next: sdk.explainRequestLookup(answer).next},
      {ref, next: {operation: 'status', ref}}, '[check-mutation:response-capture-lookup]')},
  {name: 'held submit', reply: held, call: async f => {
    try { await f.client.start({params: {}, stages: []}, {requestId: 'saved'}); }
    catch (error) { if (error instanceof sdk.RequestHeld) return error; throw error; }
    assert.fail('Expected the held branch');
  }, code: 'SubmissionUnknown', key: 'prepareAttemptId', first: 'original-attempt', later: 'replacement-attempt',
  assert: answer => assert.deepEqual({held: answer.held.prepareAttemptId,
    explanation: sdk.explainSubmission(answer).prepareAttemptId},
  {held: 'original-attempt', explanation: 'original-attempt'}, '[check-mutation:response-capture-held]')},
  {name: 'cancel', reply: cancellation, call: f => f.run.cancel(), code: 'InvalidHostCancellation',
    key: 'kind', first: 'accepted', later: 'already_terminal',
    assert: answer => assert.deepEqual({kind: answer.kind, revision: answer.revision,
      observation: sdk.explainCancellation(answer).observation},
    {kind: 'accepted', revision: 7, observation: 'accepted'}, '[check-mutation:response-capture-cancel]')},
  {name: 'deliveryAttempt', reply: () => structuredClone(delivery),
    call: f => f.run.result('answer').deliveryAttempt('read-a'), code: 'InvalidHostAttemptLookup',
    key: 'record', first: (() => { const record = {...delivery.record, state: 'streaming'};
      delete record.delivered_sha256; delete record.result_delivery_receipt_cid; return record; })(),
    later: delivery.record,
    assert: answer => assert.deepEqual({state: answer.record.state, receipt: answer.hostReleaseReceipt,
      observation: sdk.explainDeliveryAttempt(answer).observation},
    {state: 'streaming', receipt: null, observation: 'delivery_streaming'}, '[check-mutation:response-capture-delivery]')},
  {name: 'check', reply: () => structuredClone(checked), call: f => f.client.check('SELECT 1 AS n', {format: 'sql'}),
    code: 'InvalidHostCheckOutcome', key: 'report', first: checked.report,
    later: {...checked.report, context_ref: 'ctx:replacement', inputs: [{...checked.report.inputs[0], revision: 'rev:' + '2'.repeat(64)}]},
    assert: answer => assert.deepEqual({context: answer.report.context_ref,
      revision: sdk.getCheckInput(answer, 'source').revision},
    {context: 'ctx:independent-schema-pin', revision: 'rev:' + '1'.repeat(64)}, '[check-mutation:response-capture-check]')},
  {name: 'cancelRequest', reply: () => ({...cancellation(), requestId: 'saved'}),
    call: f => f.client.cancelRequest('saved'), code: 'CancellationUnknown',
    key: 'kind', first: 'accepted', later: 'already_terminal',
    assert: answer => assert.deepEqual({kind: answer.kind,
      observation: sdk.explainRequestCancellation(answer).observation},
    {kind: 'accepted', observation: 'accepted'}, '[check-mutation:response-capture-request-cancel]')},
];
for (const path of paths) {
  test(`${path.name}: response fields are captured once before admission`, async t => {
    const reply = path.reply(), counts = {};
    changing(reply, path.key, path.first, path.later, counts);
    if (path.name === 'cancel') changing(reply, 'revision', 7, 99, counts);
    if (path.name === 'deliveryAttempt') changing(reply, 'hostReleaseReceipt', null, delivery.hostReleaseReceipt, counts);
    const f = await responseFixture(t, reply);
    const answer = await path.call(f);
    path.assert(answer);
    assert.deepEqual(counts, Object.fromEntries(Object.keys(counts).map(key => [key, 1])), '[check-mutation:response-capture-once]');
    const second = await path.call(f);
    path.assert(answer);
    assert.notEqual(second, answer);
    assert.equal(Object.isFrozen(reply), false);
    assert.equal(f.operations.length, 4);
    assert.equal(sdk.explainRequestLookup(structuredClone(answer)), undefined);
    assert.equal(sdk.explainDeliveryAttempt(structuredClone(answer)), undefined);
    assert.equal(sdk.explainCancellation(structuredClone(answer)), undefined);
    assert.equal(sdk.getCheckInput(structuredClone(answer), 'source'), undefined);
    assert.equal(sdk.explainRequestCancellation(structuredClone(answer)), undefined);
  });
  test(`${path.name}: throwing response getters produce only safe operation failure`, async t => {
    const reply = path.reply(); let reads = 0;
    Object.defineProperty(reply, path.key, {enumerable: true, get() {
      reads++; throw new Error('private-response-getter');
    }});
    const f = await responseFixture(t, reply);
    let error; try { await path.call(f); } catch (cause) { error = cause; }
    assert.equal(error?.code, path.code, '[check-mutation:response-capture-failure]');
    assert.equal(reads, 1);
    assert.doesNotMatch(JSON.stringify(error), /private-response-getter/);
    if (path.name === 'lookupRequest') assert.equal(sdk.explainRequestLookup(error).next.requestId, 'saved');
    if (path.name === 'cancel') assert.equal(sdk.explainCancellation(error).observation, 'outcome_unknown');
    if (path.name === 'held submit') assert.equal(sdk.getSubmissionInput(error).requestId, 'saved');
    assert.equal(sdk.explainDeliveryAttempt(error), undefined);
    assert.equal(f.operations.length, 3);
  });
}

for (const path of paths.filter(value => ['lookupRequest', 'held submit', 'cancel', 'deliveryAttempt', 'check'].includes(value.name))) {
  test(`${path.name}: a well-shaped clone cannot replace captured facts`, async t => {
    const reply = path.reply(), f = await responseFixture(t, reply);
    if (path.name === 'deliveryAttempt') { reply.record = {...path.first}; reply.hostReleaseReceipt = null; }
    const nativeClone = globalThis.structuredClone;
    t.after(() => { globalThis.structuredClone = nativeClone; });
    globalThis.structuredClone = value => {
      const copy = nativeClone(value);
      if (value?.[path.key] === undefined) return copy;
      copy[path.key] = nativeClone(path.later);
      if (path.name === 'cancel') copy.revision = 99;
      if (path.name === 'deliveryAttempt') copy.hostReleaseReceipt = nativeClone(delivery.hostReleaseReceipt);
      return copy;
    };
    let error; try { await path.call(f); } catch (cause) { error = cause; }
    assert.equal(error?.code, path.code, '[check-mutation:response-capture-copy]');
    assert.equal(f.operations.length, 3);
  });
}
