import test from 'node:test';
import assert from 'node:assert/strict';
import {submissionCheckWireCorpus, submissionProgramCheckWireCorpus} from '../../scripts/fixtures/submission-check-wire-corpus.mjs';
import {originalSubmission} from '../sdk/submission-fixture.mjs';
import {validSubmissionOutcome} from './index.mjs';

const submissionRef = originalSubmission('independent');
const intentCid = 'sha256:' + 'd'.repeat(64);
for (const entry of [...submissionCheckWireCorpus, ...submissionProgramCheckWireCorpus]) {
  test(`JS ${entry.name}`, () => {
    const value = {...entry.value, submissionRef, intentCid};
    assert.equal(validSubmissionOutcome(value, {}, submissionRef, intentCid), entry.expected,
      '[check-mutation:submission-semantic-js]');
  });
}

// These were the independently fixed base pins before the current schema
// adoption. Updating the positive fixtures must not admit either old contract.
for (const [field, previousCid] of [
  ['reason_schema_cid', 'sha256:0d677186f7f4c10c906372124a89eb0a5169fc9a4ecaf97535715ba1815778ac'],
  ['outcome_schema_cid', 'sha256:2cb5ef23a94213780dc377fa9260b9fcfde1e9f7341063bd37cd7a7676aab10f'],
]) test(`JS submission check rejects the previous base ${field}`, () => {
  const entry = submissionCheckWireCorpus.find(value => value.name === 'submission check: exact syntax EOF');
  assert.ok(entry?.expected);
  const value = {...structuredClone(entry.value), submissionRef, intentCid};
  assert.equal(validSubmissionOutcome(value, {}, submissionRef, intentCid), true);
  value.checkObservation[field] = previousCid;
  assert.equal(validSubmissionOutcome(value, {}, submissionRef, intentCid), false);
});
