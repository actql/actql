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
  reason_schema_cid: 'sha256:0d677186f7f4c10c906372124a89eb0a5169fc9a4ecaf97535715ba1815778ac',
  outcome_schema_cid: 'sha256:2cb5ef23a94213780dc377fa9260b9fcfde1e9f7341063bd37cd7a7676aab10f',
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
