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
