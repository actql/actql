// SDK connection to the existing named protocol with explicit Host replies.
// These ports do not establish a durable Journal, Run execution or permission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {getSubmissionAttempt, getSubmissionInput, getSubmissionOutcome} from './index.mjs';
import {submissionEpoch, originalSubmission} from './submission-fixture.mjs';

const ref = {namespaceId: 'named-workspace', authorityScopeCid: submissionEpoch.authorityScopeCid,
  runDefinitionCid: 'sha256:' + 'd'.repeat(64)};
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'named-actor', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
const observed = (body, original = body.submissionRef) => ({kind: 'observed',
  requestName: body.requestName, intentCid: body.intentCid, attemptRef: body.attemptRef,
  outcome: {kind: 'ready', submissionRef: original, intentCid: body.intentCid,
    admission: {ref, durability: 'durable', revision: 7}}});
async function fixture(t, answer, confirmed = profile) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return confirmed;
      calls.push({operation, body}); return answer(operation, body);
    },
  });
  t.after(() => client.close());
  return {client, calls};
}

test('requestId-only source uses the existing named operation and distinct first-binding candidate', async t => {
  let received;
  const f = await fixture(t, (operation, body) => {
    assert.equal(operation, 'submit-named-intent'); received = body;
    assert.equal(body.requestName, 'original-public-name');
    assert.notEqual(body.submissionRef.nonce, body.requestName);
    assert.deepEqual(body.input, {text: 'SELECT 1 AS id', format: 'sql'});
    assert.equal(Object.hasOwn(body, 'requestId'), false);
    return observed(body);
  });
  const run = await f.client.startSource('SELECT 1 AS id',
    {format: 'sql', requestId: 'original-public-name', attemptId: 'first-call'});
  assert.deepEqual(run.ref, ref);
  assert.equal(getSubmissionInput(run).requestId, 'original-public-name');
  assert.equal(getSubmissionInput(run).requestName, 'original-public-name');
  assert.deepEqual(getSubmissionInput(run).submissionRef, received.submissionRef);
  assert.equal(getSubmissionAttempt(run).kind, 'observed');
  assert.deepEqual(getSubmissionOutcome(run).submissionRef, received.submissionRef);
  assert.equal(f.calls.length, 1);
});

test('a named reply keeps the old original epoch rather than asserting the new candidate', async t => {
  const original = originalSubmission('saved-original-nonce');
  const current = {...profile, submissionEpoch: {...submissionEpoch, epochNonce: 'e'.repeat(64)}};
  const f = await fixture(t, (_operation, body) => observed(body, original), current);
  const run = await f.client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'saved-name'});
  assert.deepEqual(getSubmissionOutcome(run).submissionRef, original);
  assert.notDeepEqual(getSubmissionInput(run).submissionRef, original);
  assert.equal(getSubmissionInput(run).requestName, 'saved-name');
  assert.equal(f.calls.length, 1);
});

test('named conflicting intent is RequestConflict without an invented original receipt', async t => {
  let reply;
  const f = await fixture(t, (_operation, body) => (reply = {kind: 'conflict', reason: 'intent',
    requestName: body.requestName, intentCid: body.intentCid, attemptRef: body.attemptRef}));
  await assert.rejects(f.client.startSource('SELECT 2 AS id', {format: 'sql', requestId: 'saved-name'}), error => {
    assert.equal(error.code, 'RequestConflict');
    assert.deepEqual(getSubmissionAttempt(error), reply);
    assert.equal(getSubmissionOutcome(error), undefined);
    return true;
  });
  assert.equal(f.calls.length, 1);
});

test('named response name intent attempt and scope must match before returning an execution', async t => {
  for (const change of [
    value => ({...value, requestName: 'foreign-name'}),
    value => ({...value, intentCid: 'sha256:' + 'f'.repeat(64)}),
    value => ({...value, attemptRef: {...value.attemptRef, attemptId: 'other'}}),
    value => ({...value, outcome: {...value.outcome, submissionRef: {
      ...value.outcome.submissionRef, epoch: {...submissionEpoch, authorityScopeCid: 'sha256:' + 'f'.repeat(64)}}}}),
  ]) {
    const f = await fixture(t, (_operation, body) => change(observed(body)));
    await assert.rejects(f.client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'same-name'}),
      {code: 'SubmissionUnknown'});
    assert.equal(f.calls.length, 1);
  }
});

test('named transport loss stays Unknown once, while an aborted unsent call stays NotSent', async t => {
  const f = await fixture(t, () => {throw new Error('original reply lost');});
  await assert.rejects(f.client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'lost-name'}), error => {
    assert.equal(error.code, 'SubmissionUnknown'); assert.equal(error.requestName, 'lost-name'); return true;
  });
  assert.equal(f.calls.length, 1);
  const g = await fixture(t, () => assert.fail('aborted call must not enter Host'));
  await assert.rejects(g.client.startSource('SELECT 1 AS id',
    {format: 'sql', requestId: 'not-sent', signal: AbortSignal.abort()}), {code: 'SubmissionNotSent'});
  assert.equal(g.calls.length, 0);
});

test('invalid names and reference-less restart never enter a named or legacy Host operation', async t => {
  const f = await fixture(t, () => assert.fail('invalid input must not enter Host'));
  for (const requestId of ['', 'e\u0301', 'a'.repeat(257), '\ud800']) {
    await assert.rejects(f.client.startSource('SELECT 1 AS id', {format: 'sql', requestId}),
      {code: 'InvalidRequestId'});
  }
  await assert.rejects(f.client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'old',
    unresolvedHistory: {}}), {code: 'SubmissionReferenceRequired'});
  assert.equal(f.calls.length, 0);
});
