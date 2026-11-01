import test from 'node:test';
import assert from 'node:assert/strict';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';

// The Program and actual result are tiny. The configured upper bound makes
// its generic metadata quote exceed existing resource policy; no large rows
// are allocated and no product guard is increased for this regression.
test('metadata quote failure is a durable original pre-admission refusal', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-metadata-refusal-', label: 'metadata quote refusal original'});
  let db;
  try {
    db = await open({stateDir: scratch.path, installation: {valuesMaxRows: 10000000}});
    const submissionRef = db.newSubmission({nonce: 'metadata-quote-refusal'});
    let failure;
    await assert.rejects(db.startSource('SELECT x FROM UNNEST([1, 2]) AS x', {
      format: 'sql', readOnly: true, submissionRef, signal: AbortSignal.timeout(20000),
    }), error => {
      failure = error;
      return error.code === 'SubmissionNotAccepted';
    });
    const outcome = getSubmissionOutcome(failure);
    assert.equal(outcome.kind, 'not_accepted');
    assert.equal(outcome.problem.code, 'ClientProgramRejected');
    assert.equal(outcome.problem.classification, 'operation_failed');
    assert.deepEqual(outcome.submissionRef, submissionRef);
    assert.equal(Object.hasOwn(outcome, 'admission'), false);
    const first = await db.lookupSubmission(submissionRef);
    const second = await db.lookupSubmission(submissionRef);
    assert.deepEqual(first, second);
    assert.deepEqual(first.submissionRef, submissionRef);
    assert.equal(first.kind, 'not_accepted');
    assert.equal(first.problem.code, 'ClientProgramRejected');
    assert.deepEqual(await db.sql('SELECT 7 AS x').all(), [{x: 7}]);
    await db.close();
    db = await open({stateDir: scratch.path});
    const reopened = await db.lookupSubmission(submissionRef);
    assert.equal(reopened.kind, 'not_accepted');
    assert.deepEqual(reopened.submissionRef, submissionRef);
    assert.deepEqual(reopened.problem, first.problem);
    assert.deepEqual(await db.sql('SELECT 8 AS x').all(), [{x: 8}]);
  } finally {
    await db?.close();
  }
  scratch.passed();
});

test('metadata quote normal and empty result controls retain their semantics', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-metadata-controls-', label: 'metadata quote normal controls'});
  let db;
  try {
    db = await open({stateDir: scratch.path});
    assert.deepEqual(await db.sql('SELECT x FROM UNNEST([1, 2]) AS x').all(), [{x: 1}, {x: 2}]);
    assert.deepEqual(await db.sql('SELECT x FROM UNNEST([1, 2]) AS x WHERE FALSE').all(), []);
    assert.deepEqual(await db.sql('SELECT 7 AS x').all(), [{x: 7}]);
  } finally {
    await db?.close();
  }
  scratch.passed();
});
