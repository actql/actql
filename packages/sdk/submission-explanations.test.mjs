import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import * as sdk from './index.mjs';
import {submissionEpoch, originalSubmission} from './submission-fixture.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'original-run', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable',
  scopeRef: 'submission-explanations', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const original = originalSubmission('original-submission');
const next = {operation: 'lookupSubmission', submissionRef: original,
  lookupContext: {endpoint: 'actql:embedded', scopeRef: profile.scopeRef}};
const problem = {code: 'FixtureKnownRefusal', classification: 'invalid_input'};
const hint = 'Keep the original submission reference and use an authorized lookup. This observation grants no permission to resubmit, execute or release resources.';
const summaries = {
  not_accepted: 'The Host durably rejected this submission before acceptance. Its identity is consumed; no Run reference was returned.',
  preparation_failed: 'The Host accepted this submission, then preparation failed. No Run reference was returned; this is not a rejection before acceptance.',
  preparing: 'The Host accepted this submission and preparation is still pending. No Run reference was returned.',
  history_unresolvable: 'The Host cannot establish the original submission outcome. Work may already have started.',
};
const expected = kind => kind === 'ready'
  ? {observation: 'run_reference_received',
    summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
    next: {operation: 'status', ref}}
  : {observation: kind === 'unresolvable' ? 'history_unresolvable' : kind,
    summary: summaries[kind === 'unresolvable' ? 'history_unresolvable' : kind], hint, next,
    ...(['not_accepted', 'preparation_failed'].includes(kind) ? {problem} : {})};

async function fixture(t, reply) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local', durability: 'durable'}, {
    perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      return reply(operation, body);
    },
  });
  t.after(() => client.close());
  return {client, calls};
}
const outcome = (kind, body) => ({kind, submissionRef: body.submissionRef,
  ...(kind === 'unresolvable' ? {problem: {code: 'submission_history_unresolvable'}} : {
    intentCid: body.intentCid ?? cid('c'),
    ...(kind === 'ready' ? {admission: {ref, revision: 1, durability: 'durable'}} : {}),
    ...(['not_accepted', 'preparation_failed'].includes(kind) ? {problem: {...problem}} : {}),
  })});

for (const kind of ['not_accepted', 'preparation_failed', 'preparing', 'ready']) {
  test(`submission explanation retains admitted ${kind} without changing its acceptance phase`, async t => {
    const f = await fixture(t, (operation, body) => outcome(kind, body));
    let result;
    try {result = await f.client.start({}, {submissionRef: original});}
    catch (error) {result = error;}
    assert.equal(sdk.getSubmissionOutcome(result).kind, kind);
    assert.deepEqual(sdk.explainSubmission(result), expected(kind), '[check-mutation:submission-phase]');
    const calls = [...f.calls];
    for (const format of ['text', 'html', 'json']) assert.equal(typeof sdk.formatSubmission(result, {format}), 'string');
    assert.deepEqual(JSON.parse(sdk.formatSubmission(result, {format: 'json'})).explanation,
      expected(kind), '[check-mutation:submission-format]');
    assert.deepEqual(f.calls, calls);
    assert.equal(sdk.explainSubmission({...result}), undefined);
    assert.equal(sdk.formatSubmission({...result}), undefined);
    assert.ok(Object.isFrozen(sdk.explainSubmission(result)));
  });
}

for (const kind of ['not_accepted', 'preparation_failed', 'preparing', 'ready', 'unresolvable']) {
  test(`submission lookup explanation retains admitted ${kind} and the original epoch`, async t => {
    const f = await fixture(t, (operation, body) => {
      assert.equal(operation, 'lookup-submission'); return outcome(kind, body);
    });
    const answer = await f.client.lookupSubmission(original);
    assert.deepEqual(sdk.explainSubmission(answer), expected(kind), '[check-mutation:submission-lookup]');
    assert.deepEqual(JSON.parse(sdk.formatSubmission(answer, {format: 'json'})).explanation, expected(kind));
    assert.equal(sdk.getSubmissionInput(answer), undefined);
    assert.equal(sdk.explainSubmission(structuredClone(answer)), undefined);
    assert.deepEqual(f.calls, ['connect', 'lookup-submission']);
  });
}

for (const fault of ['unknown branch', 'wrong nonce', 'malformed problem', 'changed clone']) {
  test(`submission lookup refuses ${fault} without acquiring outcome facts`, async t => {
    const f = await fixture(t, (operation, body) => {
      const answer = outcome('preparation_failed', body);
      if (fault === 'unknown branch') answer.kind = 'succeeded';
      if (fault === 'wrong nonce') answer.submissionRef = {...body.submissionRef, nonce: 'foreign'};
      if (fault === 'malformed problem') answer.problem.classification = 'success';
      return answer;
    });
    const clone = globalThis.structuredClone;
    if (fault === 'changed clone') t.mock.method(globalThis, 'structuredClone', value => {
      const copy = clone(value);
      if (copy.kind === 'preparation_failed') copy.kind = 'not_accepted';
      return copy;
    });
    let failure;
    try {await f.client.lookupSubmission(original);} catch (error) {failure = error;}
    assert.equal(failure.code, 'InvalidHostSubmissionLookup');
    assert.deepEqual(sdk.explainSubmission(failure)?.next, next, '[check-mutation:submission-rejected-reference]');
    assert.equal(sdk.explainSubmission(failure).observation, 'lookup_uninterpretable');
    assert.equal(sdk.getSubmissionOutcome(failure), undefined);
    assert.deepEqual(f.calls, ['connect', 'lookup-submission']);
  });
}

test('submission lookup detaches shared hostile failures without inferring acceptance', async t => {
  const borrowed = new sdk.ClientError('SubmissionNotAccepted', {status: 503});
  Object.defineProperty(borrowed, 'code', {get() {throw new Error('private-code-accessor');}});
  const f = await fixture(t, () => {throw borrowed;});
  const failures = [];
  for (const nonce of ['original-submission', 'second-original']) {
    try {await f.client.lookupSubmission(originalSubmission(nonce));} catch (error) {failures.push(error);}
  }
  assert.notEqual(failures[0], failures[1]);
  for (const [i, nonce] of ['original-submission', 'second-original'].entries()) {
    const explanation = sdk.explainSubmission(failures[i]);
    assert.equal(explanation?.observation, 'lookup_unavailable', '[check-mutation:submission-lookup-failure]');
    assert.equal(explanation.next.submissionRef.nonce, nonce);
    assert.equal(sdk.getSubmissionOutcome(failures[i]), undefined);
    assert.doesNotMatch(inspect(failures[i], {showHidden: true, depth: 8}), /private-code-accessor/);
  }
  assert.equal(sdk.explainSubmission(borrowed), undefined);
});

test('known unsent submission explains dispatch only and has no Owner outcome', async t => {
  const f = await fixture(t, () => assert.fail('Closed Client must not send'));
  f.client.close();
  let failure;
  try {await f.client.start({}, {submissionRef: original});} catch (error) {failure = error;}
  assert.equal(failure.code, 'SubmissionNotSent');
  assert.equal(sdk.explainSubmission(failure)?.observation, 'not_sent', '[check-mutation:submission-unsent]');
  assert.deepEqual(sdk.explainSubmission(failure).next, next);
  assert.equal(sdk.getSubmissionOutcome(failure), undefined);
  assert.deepEqual(f.calls, ['connect']);
});

test('submission lookup owns immutable reused replies and formatting cannot acquire custody', async t => {
  let shared;
  const f = await fixture(t, (operation, body) => {
    if (!shared) shared = outcome('preparation_failed', body);
    shared.submissionRef = body.submissionRef;
    return shared;
  });
  const first = await f.client.lookupSubmission(original);
  const second = await f.client.lookupSubmission(originalSubmission('second-original'));
  shared.kind = 'not_accepted'; shared.problem.code = 'private-later-change';
  assert.deepEqual(sdk.explainSubmission(first), expected('preparation_failed'), '[check-mutation:submission-lookup-custody]');
  assert.equal(sdk.explainSubmission(second).next.submissionRef.nonce, 'second-original');
  assert.equal(sdk.formatSubmission({kind: 'not_accepted'}), undefined);
  assert.equal(sdk.explainSubmission(new sdk.ClientError('SubmissionNotAccepted')), undefined);
  const english = sdk.explainSubmission(first);
  const japanese = sdk.explainSubmission(first, {locale: 'ja'});
  const {summary: enSummary, hint: enHint, ...enFacts} = english;
  const {summary: jaSummary, hint: jaHint, ...jaFacts} = japanese;
  assert.deepEqual(jaFacts, enFacts);
  assert.notEqual(jaSummary, enSummary);
  assert.deepEqual(sdk.explainSubmission(first, {locale: 'unknown'}), english);
  const large = await f.client.lookupSubmission(originalSubmission('b'.repeat(256)));
  assert.equal(typeof sdk.formatSubmission(large), 'string');
  assert.equal(sdk.formatSubmission(large, {maxBytes: 1024}), undefined);
});
