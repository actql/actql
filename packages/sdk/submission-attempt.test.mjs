import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, getSubmissionAttempt, getSubmissionInput, getSubmissionOutcome,
  getSubmissionCheckObservation, explainSubmission, formatSubmission} from './index.mjs';
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
const hint = 'Keep the original submission reference and use a currently authorized lookup. This invocation outcome does not establish another invocation\'s acceptance, grant permission to resubmit, or authorize changed input or a new restart decision.';

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

for (const [kind, reason, summary, localized] of [
  ['refused', 'authorization',
    'The Host refused this submission invocation under current authorization. This invocation committed no submission and consumed no operation identity.',
    'Hostは現在の認可により今回の提出呼出しを拒否しました。今回の呼出しは提出をcommitせず、操作identityも消費していません。'],
  ['refused', 'admission_capacity',
    'The Host refused this submission invocation because admission capacity was unavailable. This invocation committed no submission and consumed no operation identity.',
    'Hostは受付容量が不足しているため今回の提出呼出しを拒否しました。今回の呼出しは提出をcommitせず、操作identityも消費していません。'],
  ['refused', 'epoch_expired',
    'The Host refused this submission invocation because its submitted epoch has expired. This does not establish the original submission outcome.',
    'Hostは提出したepochが期限切れのため今回の提出呼出しを拒否しました。元の提出結果は確定しません。'],
  ['refused', 'epoch_not_yet_valid',
    'The Host refused this submission invocation because its submitted epoch is not yet valid. This does not establish the original submission outcome.',
    'Hostは提出したepochがまだ有効でないため今回の提出呼出しを拒否しました。元の提出結果は確定しません。'],
  ['conflict', 'intent',
    'The Host reports a conflicting intent for this original submission identity.',
    'Hostは元の提出identityに対する意図の競合を報告しています。'],
  ['conflict', 'restart_decision',
    'The Host reports a conflicting restart decision for this original submission identity.',
    'Hostは元の提出identityに対する再開始の判断の競合を報告しています。'],
]) {
  test(`typed Submission ${kind}/${reason} explains only its original invocation`, async t => {
    let reply;
    const f = await fixture(t, (_operation, body) => reply = {kind, attemptRef: body.attemptRef, reason,
      ...(reason === 'authorization' ? {} : {submissionRef: body.submissionRef, intentCid: body.intentCid}),
      ...(kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {})});
    let failure;
    await assert.rejects(f.submit(), error => {failure = error; return true;});
    const expected = {observation: kind, reason, attemptRef, submissionRef,
      ...(kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {}),
      summary, hint, next: {operation: 'lookupSubmission', submissionRef,
        lookupContext: {endpoint: 'actql:embedded', scopeRef: 'test-principal'}}};
    assert.deepEqual(explainSubmission(failure), expected, '[check-mutation:submit-attempt-explanation]');
    assert.equal(getSubmissionOutcome(failure), undefined);
    assert.equal(getSubmissionCheckObservation(failure), undefined);
    const diagnosis = explainSubmission(failure);
    assert(Object.isFrozen(diagnosis));
    assert(Object.isFrozen(diagnosis.attemptRef));
    assert(Object.isFrozen(diagnosis.submissionRef.epoch));
    assert(Object.isFrozen(diagnosis.next.lookupContext));
    for (const copied of [{...failure}, structuredClone(getSubmissionAttempt(failure)),
      JSON.parse(JSON.stringify(failure))]) {
      assert.equal(explainSubmission(copied), undefined, '[check-mutation:submit-attempt-custody]');
      assert.equal(formatSubmission(copied), undefined);
      assert.equal(getSubmissionInput(copied), undefined);
    }
    failure.code = 'SubmissionAccepted';
    failure.outcome = {kind: 'ready', privateValue: 'private-old-intent'};
    reply.reason = 'private-provider-cause';
    assert.deepEqual(explainSubmission(failure), expected);
    assert.deepEqual(explainSubmission(failure, {locale: 'ja'}), {...expected,
      summary: localized,
      hint: '元の提出参照を保持し、現在の認可で照会してください。今回の呼出し結果は別の呼出しの受理を確定せず、再提出・変更した入力・新しい再開始の判断を許可しません。'});
    for (const format of ['text', 'html', 'json']) {
      const rendered = formatSubmission(failure, {format});
      assert.ok(rendered);
      assert.doesNotMatch(rendered, /private-old-intent|private-provider-cause|SubmissionAccepted/);
      if (format === 'json') assert.deepEqual(JSON.parse(rendered).explanation, expected);
    }
    assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'submit-intent'],
      '[check-mutation:submit-attempt-passive]');
  });
}

test('typed Submission refusal retains its original snapshot while the caller edits bindings', async t => {
  const f = await fixture(t, (_operation, body) => ({kind: 'refused', reason: 'authorization',
    attemptRef: body.attemptRef, guarantee: 'attempt_uncommitted_unconsumed'}));
  const parameters = {'e\u0301/~🧭': {value: null}};
  const pending = f.client.startSource('SELECT 1 AS n\r\n', {format: 'sql', submissionRef,
    parameters, attemptId: 'before-edit'});
  const snapshot = getSubmissionInput(pending);
  parameters['e\u0301/~🧭'].value = 'edited';
  let error;
  await assert.rejects(pending, cause => {error = cause; return true;});
  assert.equal(getSubmissionInput(error), snapshot);
  assert.deepEqual(snapshot.parameters, {'e\u0301/~🧭': {value: null}});
  assert.equal(snapshot.input.text, 'SELECT 1 AS n\r\n');
  assert.deepEqual(explainSubmission(error).attemptRef, {operation: 'submit', attemptId: 'before-edit'});
  assert.deepEqual(explainSubmission(error).next.submissionRef, submissionRef);
  assert.equal(getSubmissionInput({...error}), undefined);
  assert.deepEqual(f.calls.map(call => call.operation), ['connect', 'submit-intent']);
});

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
