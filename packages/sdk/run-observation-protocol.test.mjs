import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {ClientError, explainRunObservationFailure, explainEffectUncertainty} from './index.mjs';

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
