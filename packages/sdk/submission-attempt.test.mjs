import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, getSubmissionAttempt, getSubmissionInput, getSubmissionOutcome} from './index.mjs';
import {connectInProcess} from './host-port.mjs';
import {submissionEpoch, originalSubmission, readySubmission} from './submission-fixture.mjs';
import {validSubmissionAttemptShape} from '../client-wire/client-host.generated.js';

const ref = {namespaceId: 'namespace-a', authorityScopeCid: submissionEpoch.authorityScopeCid,
  runDefinitionCid: `sha256:${'d'.repeat(64)}`};
const attemptRef = {operation: 'submit', attemptId: 'this-invocation'};
const submissionRef = originalSubmission('original-operation');
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'test-principal', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
const original = body => readySubmission(body, {ref, durability: 'durable', revision: 7});
const recorded = body => ({kind: 'recorded', attemptRef: body.attemptRef, outcome: original(body)});

async function fixture(t, answer) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
    calls.push({operation, body});
    return operation === 'connect' ? profile : answer(operation, body);
  }});
  t.after(() => client.close());
  return {client, calls, submit: () => client.startSource('SELECT 1 AS n',
    {format: 'aql-text', submissionRef, attemptId: attemptRef.attemptId})};
}

test('Submission recorded receipt binds this invocation without replacing the original durable outcome', async t => {
  const f = await fixture(t, (operation, body) => {
    assert.equal(operation, 'submit-intent');
    assert.deepEqual(body.attemptRef, attemptRef);
    return recorded(body);
  });
  const execution = await f.submit();
  assert.deepEqual(getSubmissionAttempt(execution)?.attemptRef, attemptRef);
  assert.equal(getSubmissionAttempt(execution)?.kind, 'recorded');
  assert.equal(getSubmissionOutcome(execution)?.kind, 'ready');
  assert.deepEqual(getSubmissionInput(execution)?.attemptRef, attemptRef);
  assert.equal(f.calls.filter(call => call.operation === 'submit-intent').length, 1);
  assert.equal(getSubmissionAttempt(JSON.parse(JSON.stringify(getSubmissionAttempt(execution)))), undefined);
});

for (const kind of ['refused', 'conflict']) {
  test(`typed Submission ${kind} is distinct from unknown transport and durable NotAccepted`, async t => {
    let wire;
    const f = await fixture(t, (_operation, body) => {
      wire = kind === 'refused' ? {kind, attemptRef: body.attemptRef,
        reason: 'authorization', guarantee: 'attempt_uncommitted_unconsumed'}
        : {kind, attemptRef: body.attemptRef, reason: 'intent',
          submissionRef: body.submissionRef, intentCid: body.intentCid};
      return wire;
    });
    await assert.rejects(f.submit(), error => {
      assert.equal(error.code, kind === 'refused' ? 'SubmissionRefused' : 'SubmissionConflict');
      assert.deepEqual(getSubmissionAttempt(error), wire);
      assert.equal(getSubmissionOutcome(error), undefined);
      assert.deepEqual(error.attemptRef, attemptRef);
      assert.deepEqual(error.submissionRef, submissionRef);
      assert(Object.isFrozen(getSubmissionAttempt(error)));
      return true;
    });
    assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'submit-intent']);
  });
}

for (const code of ['ClientSubmittedIntentConflict', 'ClientSubmittedIntentCapacity',
  'ClientSubmissionEpochExpired', 'ClientRequestLookupDenied', 'ClientAuthenticationDenied']) {
  test(`a transported ${code} supplies no typed Submission refusal certificate`, async t => {
    const f = await fixture(t, () => {throw new ClientError(code, {status: 409});});
    await assert.rejects(f.submit(), error => {
      assert.equal(error.code, 'SubmissionUnknown');
      assert.equal(getSubmissionAttempt(error), undefined);
      assert.equal(getSubmissionOutcome(error), undefined);
      assert.deepEqual(error.attemptRef, attemptRef);
      return true;
    });
    assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'submit-intent']);
  });
}

for (const alteration of ['attempt', 'operation', 'reference', 'intent', 'guarantee', 'raw-receipt']) {
  test(`foreign or malformed Submission fact (${alteration}) stays unknown`, async t => {
    const f = await fixture(t, (_operation, body) => {
      if (alteration === 'raw-receipt') return original(body);
      const wire = alteration === 'guarantee' ? {kind: 'refused', attemptRef: {...body.attemptRef},
        reason: 'authorization', guarantee: 'original_never_executed'} : recorded(body);
      if (alteration === 'attempt') wire.attemptRef = {...body.attemptRef, attemptId: 'another-invocation'};
      if (alteration === 'operation') wire.attemptRef = {...body.attemptRef, operation: 'cancel'};
      if (alteration === 'reference') wire.outcome.submissionRef = originalSubmission('other-operation');
      if (alteration === 'intent') wire.outcome.intentCid = `sha256:${'e'.repeat(64)}`;
      return wire;
    });
    await assert.rejects(f.submit(), error => {
      assert.equal(error.code, 'SubmissionUnknown');
      assert.equal(getSubmissionAttempt(error), undefined);
      assert.equal(getSubmissionOutcome(error), undefined);
      return true;
    });
  });
}

test('AlreadySatisfied cannot claim satisfaction of an in-progress preparation', async t => {
  const f = await fixture(t, (_operation, body) => {
    const wire = {kind: 'already_satisfied', attemptRef: body.attemptRef,
      outcome: {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid}};
    assert.equal(validSubmissionAttemptShape(wire), false, 'the generated common contract rejects the contradiction');
    return wire;
  });
  await assert.rejects(f.submit(), {code: 'SubmissionUnknown'});
});

test('durable NotAccepted remains the consumed original identity, separately from the invocation fact', async t => {
  const f = await fixture(t, (_operation, body) => ({kind: 'recorded', attemptRef: body.attemptRef,
    outcome: {kind: 'not_accepted', submissionRef: body.submissionRef, intentCid: body.intentCid,
      problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}}}));
  await assert.rejects(f.submit(), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    assert.equal(getSubmissionOutcome(error)?.kind, 'not_accepted');
    assert.equal(getSubmissionAttempt(error)?.kind, 'recorded');
    return true;
  });
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'submit-intent']);
});
