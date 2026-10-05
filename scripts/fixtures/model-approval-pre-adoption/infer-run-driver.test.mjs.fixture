import assert from 'node:assert/strict';
import test from 'node:test';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {driveNodeInferOperation} from './infer-run-driver.mjs';

// The real gate issues opaque decisions; common execution and account parsing
// below remain explicit doubles. No physical/journal/packed acceptance claim.
const cid = `sha256:${'a'.repeat(64)}`;
const tuple = {principal: 'owner', connection: 'models/fixture',
  resource: 'task', operation: 'infer'};
function gate() {
  const runtime = {
    executionAuthorizationAdmit: () => ({state: 'admitted',
      account_id: 'account', configuration_cid: cid}),
    executionAuthorizationMissing: () => ({state: 'missing'}),
    executionAuthorizationAccountJson: JSON.stringify,
    executionAuthorizationEvaluate: () => ({outcome: 'allow'}),
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction: () => ({action: 'dispatch',
      basis: 'account_allow'}),
    executionAuthorizationPrepare() { assert.fail('ordinary allow'); },
    executionAuthorizationRequestJson: JSON.stringify,
    executionAuthorizationAnswer() { assert.fail('ordinary allow'); },
    executionAuthorizationDecisionJson: JSON.stringify,
  };
  return createAuthorizationGate({runtime, configuration: '{}',
    context: {principal: 'owner', contextCid: cid}});
}
function operation() {
  const inputReceipt = {};
  const prepared = Object.freeze({inputReceipt, inputWire: 'exact-input',
    binding: {providerId: tuple.connection, taskCid: tuple.resource},
    count: 1, slotWire: () => 'exact-slot'});
  const counts = {run: 0, resumed: 0};
  let waiting = true;
  const owner = {
    async run() {
      counts.run++;
      return waiting ? {kind: 'waiting', callSet: prepared} : 'output';
    },
    preparedCallSet: () => waiting ? prepared : undefined,
    resume() { counts.resumed++; waiting = false; },
  };
  return {owner, prepared, counts};
}

test('installed driver exits a retained Model wait once with the original owner and input receipt', async () => {
  const {owner, prepared, counts} = operation();
  let decisions = 0;
  const result = await driveNodeInferOperation(owner, {dispatch: {
    async authorize(context) {
      decisions++;
      assert.equal(context.operation, owner);
      assert.equal(context.prepared, prepared);
      assert.equal(context.prepared.inputReceipt, prepared.inputReceipt);
      return {action: 'waiting', boundary: 'activation', tuple,
        checkpoint: {checkpointCid: cid}};
    },
    resume() { assert.fail('no approval'); },
  }});
  assert.deepEqual(result, {status: 'waiting_checkpoint', checkpointCid: cid});
  assert.deepEqual(counts, {run: 1, resumed: 0});
  assert.equal(decisions, 1);
});

test('installed driver continues only the same prepared operation under a gate-issued dispatch', async () => {
  const f = operation();
  const authority = gate();
  try {
    const result = await driveNodeInferOperation(f.owner, {dispatch: {
      authorize: () => authority.authorize('activation', tuple, {subjectCid: cid}),
      resume(context) {
        assert.equal(context.operation, f.owner);
        assert.equal(context.prepared, f.prepared);
        f.owner.resume();
      },
    }});
    assert.equal(result, 'output');
    assert.deepEqual(f.counts, {run: 2, resumed: 1});
  } finally { authority.close(); }
});

test('copied dispatch, a Source permit and a no-op resume cannot complete Model preparation', async () => {
  const authority = gate();
  try {
    const decision = await authority.authorize('activation', tuple, {subjectCid: cid});
    const source = await authority.authorize('activation', {...tuple, operation: 'read'},
      {subjectCid: cid});
    for (const value of [{...decision}, source]) {
      const f = operation();
      await assert.rejects(driveNodeInferOperation(f.owner, {dispatch: {
        authorize: async () => value,
        resume() { assert.fail('foreign dispatch'); },
      }}), {message: 'InstalledInferForeignDispatchDecision'});
      assert.equal(f.counts.resumed, 0);
    }
    const f = operation();
    await assert.rejects(driveNodeInferOperation(f.owner, {dispatch: {
      authorize: async () => decision, resume() {},
    }}), {message: 'InstalledInferModelResumeIncomplete'});
    assert.deepEqual(f.counts, {run: 1, resumed: 0});
  } finally { authority.close(); }
});

test('cancellation after authorization stops continuation before resume', async () => {
  const f = operation();
  const abort = new AbortController();
  const failure = new Error('cancelled');
  await assert.rejects(driveNodeInferOperation(f.owner, {signal: abort.signal,
    dispatch: {authorize() {
      abort.abort(failure);
      return {action: 'waiting', boundary: 'activation', tuple,
        checkpoint: {checkpointCid: cid}};
    }, resume() { assert.fail('cancelled'); }},
  }), error => error === failure);
  assert.equal(f.counts.resumed, 0);
});

test('an unconnected Model wait refuses before completed-output publication', async () => {
  const f = operation();
  await assert.rejects(driveNodeInferOperation(f.owner),
    {message: 'InstalledInferModelApprovalNotConnected'});
  assert.deepEqual(f.counts, {run: 1, resumed: 0});
});
