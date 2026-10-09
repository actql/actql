import test from 'node:test';
import assert from 'node:assert/strict';
import {validSubmissionOutcome, validStoredSubmissionOutcome, validSubmissionLookup} from './index.mjs';
import {submissionCheckWireCorpus} from '../../scripts/fixtures/submission-check-wire-corpus.mjs';

// Independent negative-response fixture; neither Host nor SDK produces it.
const submissionRef = {epoch: {version: 'actql-submission-epoch/0.1',
  authorityScopeCid: 'sha256:' + 'a'.repeat(64), epochNonce: 'b'.repeat(64),
  notBefore: 1, expiresAt: 2, authenticator: 'c'.repeat(64)}, nonce: 'original'};
const intentCid = 'sha256:' + 'd'.repeat(64);
const observation = {version: 'actql-check-outcome/0.1',
  reason_schema_cid: 'sha256:332a61df6738e4e21d916345f31f2ae28aec30cd779cd614dba2a24044f061e6',
  outcome_schema_cid: 'sha256:b1062306669a530f532faa3b7fc5d24e34bd72aeae712c177cee7557216ea464',
  outcome: 'completed', report: {context_ref: 'ctx:independent', scope: {kind: 'bound_input'},
    verdict: 'invalid', inputs: [{document_id: 'source', kind: 'text',
      revision: 'rev:' + '4'.repeat(64), byte_length: 6}],
    reasons: [{code: 'query_syntax_invalid', location: {kind: 'text', document_id: 'source',
      revision: 'rev:' + '4'.repeat(64), start_byte: 6, end_byte: 6, precision: 'exact'}}],
    requirements: [], coverage: {limits: [], unresolved: []}}};

for (const kind of ['not_accepted', 'preparation_failed']) {
  test(`submission checking is transient, not stored or reference-only ${kind}`, () => {
    const base = {kind, submissionRef, intentCid,
      problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}};
    const response = {...base, checkObservation: observation};
    assert.equal(validSubmissionOutcome(response, {}, submissionRef, intentCid), true);
    assert.equal(validStoredSubmissionOutcome(base, submissionRef, intentCid), true);
    assert.equal(validStoredSubmissionOutcome(response, submissionRef, intentCid), false,
      '[check-mutation:submission-check-persistence]');
    assert.equal(validSubmissionLookup(base, {}, submissionRef), true);
    assert.equal(validSubmissionLookup(response, {}, submissionRef), false);
    const malformed = structuredClone(response);
    malformed.checkObservation.report.reasons[0].location.revision = 'rev:' + '5'.repeat(64);
    assert.equal(validSubmissionOutcome(malformed, {}, submissionRef, intentCid), false,
      '[check-mutation:submission-check-semantic]');
  });
}

test('query alias absence wire enforces independent closed facts and current pins', () => {
  const cases = submissionCheckWireCorpus.filter(entry => /query alias absence|previous .* schema/u.test(entry.name));
  assert.equal(cases.length, 9);
  for (const entry of cases) {
    const response = {...entry.value, submissionRef, intentCid};
    assert.equal(validSubmissionOutcome(response, {}, submissionRef, intentCid), entry.expected,
      entry.name + ' [check-mutation:namespace-wire]');
    assert.equal(validStoredSubmissionOutcome(response, submissionRef, intentCid), false);
  }
});
