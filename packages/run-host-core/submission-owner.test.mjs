import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {prepareSubmissionEpoch, submissionEpochFacts, submissionEpochValidity,
  submissionRequestId, prepareSubmittedIntent, submittedIntentFacts,
  submittedIntentTransition} from './index.mjs';

const scope = {authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  epochNonce: 'b'.repeat(64), notBefore: 1000, expiresAt: 2000};
const digest = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const limits = {maxWireBytes: 8192, maxNodes: 256, maxDepth: 16};

test('portable submission preserves independent epoch and original request identities', () => {
  const epoch = prepareSubmissionEpoch(scope);
  const wire = JSON.stringify({authority_scope_cid: scope.authorityScopeCid,
    epoch_nonce: scope.epochNonce, expires_at: 2000, not_before: 1000,
    version: 'actql-submission-epoch/0.1'});
  assert.deepEqual(submissionEpochFacts(epoch), {wire, cid: digest(wire)});
  const request = JSON.stringify({caller_nonce: 'original-nonce', epoch_cid: digest(wire),
    version: 'actql-submission-identity/0.1'});
  assert.equal(submissionRequestId(epoch, 'original-nonce'), digest(request));
  assert.equal(submissionRequestId(prepareSubmissionEpoch({...scope}), 'original-nonce'), digest(request));
  assert.notEqual(submissionRequestId(prepareSubmissionEpoch({...scope,
    epochNonce: 'c'.repeat(64)}), 'original-nonce'), digest(request));
  assert.notEqual(submissionRequestId(epoch, 'other-nonce'), digest(request));
});

test('portable epoch distinguishes admission interval from later original-identity lookup', () => {
  const epoch = prepareSubmissionEpoch(scope);
  const original = submissionRequestId(epoch, 'original-nonce');
  assert.equal(submissionEpochValidity(epoch, 999), 'not_yet_valid');
  assert.equal(submissionEpochValidity(epoch, 1000), 'admissible');
  assert.equal(submissionEpochValidity(epoch, 1999), 'admissible');
  assert.equal(submissionEpochValidity(epoch, 2000), 'expired');
  assert.equal(submissionRequestId(epoch, 'original-nonce'), original);
  // Epoch identity alone is not proof of current permission or validation custody.
});

test('portable submitted intent preserves values and independent original content CID', () => {
  const intent = {input: {nested: {text: 'e\u0301\r\nline\rnext\n'}},
    kind: 'program', parameters: null};
  const wire = JSON.stringify(intent);
  const facts = submittedIntentFacts(prepareSubmittedIntent(wire, limits));
  assert.deepEqual(facts, {wire,
    cid: digest(JSON.stringify({intent, version: 'actql-submitted-intent/0.1'}))});
  assert.deepEqual(JSON.parse(facts.wire), intent);
  const composed = {...intent, input: {nested: {text: '\u00e9\r\nline\rnext\n'}}};
  assert.notEqual(submittedIntentFacts(prepareSubmittedIntent(JSON.stringify(composed), limits)).cid, facts.cid);
  const reordered = JSON.stringify({parameters: null, kind: 'program', input: intent.input});
  assert.deepEqual(submittedIntentFacts(prepareSubmittedIntent(reordered, limits)), facts);
});

test('portable submitted-intent phase decisions keep original terminal outcomes immutable', () => {
  for (const phase of ['preparing', 'held', 'ready', 'preparation_failed']) {
    assert.equal(submittedIntentTransition('preparing', phase), true);
  }
  assert.equal(submittedIntentTransition('preparing', 'not_accepted'), false);
  assert.equal(submittedIntentTransition('held', 'not_accepted'), false);
  for (const terminal of ['ready', 'not_accepted', 'preparation_failed']) {
    assert.equal(submittedIntentTransition(terminal, terminal), true);
    assert.equal(submittedIntentTransition(terminal, 'preparing'), false);
    for (const other of ['ready', 'not_accepted', 'preparation_failed']) {
      if (other !== terminal) assert.equal(submittedIntentTransition(terminal, other), false);
    }
  }
  assert.equal(submittedIntentTransition('invented', 'ready'), false);
});

test('portable submission rejects foreign handles and bounded invalid identity/content', () => {
  const epoch = prepareSubmissionEpoch(scope);
  assert.throws(() => submissionEpochFacts({}), /ForeignRunHostHandle/u);
  assert.throws(() => submittedIntentFacts(epoch), /ForeignRunHostHandle/u);
  assert.throws(() => prepareSubmissionEpoch({...scope, expiresAt: scope.notBefore}), /SubmissionEpochRejected/u);
  assert.throws(() => prepareSubmissionEpoch({...scope, notBefore: -0}), /SubmissionEpochRejected/u);
  assert.throws(() => prepareSubmissionEpoch({...scope, epochNonce: 'invalid'}), /SubmissionEpochRejected/u);
  assert.throws(() => submissionEpochValidity(epoch, NaN), /InvalidSubmissionClock/u);
  assert.throws(() => submissionEpochValidity(epoch, -1), /SubmissionClockRejected/u);
  assert.throws(() => submissionRequestId(epoch, ''), /SubmissionNonceRejected/u);
  assert.throws(() => prepareSubmittedIntent('{}', limits), /SubmittedIntentRejected/u);
  assert.throws(() => prepareSubmittedIntent('{', limits), /SubmittedIntentRejected/u);
  assert.throws(() => prepareSubmittedIntent('{"input":{},"kind":"program","parameters":null}',
    {...limits, maxWireBytes: 1}), /SubmittedIntentRejected/u);
  assert.throws(() => prepareSubmittedIntent('{}', {...limits, maxNodes: 2147483648}), /InvalidSubmittedIntent/u);
});
