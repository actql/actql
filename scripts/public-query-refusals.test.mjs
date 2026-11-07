import assert from 'node:assert/strict';
import test from 'node:test';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';

async function exerciseRefusal(code, {expectedCode, admit = false,
  submissionCode = 'SubmissionNotAccepted', requestPrefix = 'refusal-control'} = {}) {
  let acceptedRuns = 0, closed = false, outcome;
  const connect = async () => ({
    newSubmission: ({nonce}) => ({nonce}),
    async startSource(text, {submissionRef}) {
      assert.equal(text, 'SELECT UNKNOWN_FUNCTION(1) AS value');
      if (admit) acceptedRuns++;
      outcome = {kind: 'not_accepted', submissionRef, problem: {code}};
      throw Object.assign(new Error(code), {code: submissionCode, outcome});
    },
    async lookupSubmission(ref) {
      assert.deepEqual(ref, outcome.submissionRef);
      return outcome;
    },
    async close() { closed = true; },
  });
  try {
    await exercisePublicQueryInput(connect, {}, {
      requestPrefix,
      observe: () => ({acceptedRuns, sourceIo: 0}),
      successes: [],
      refusals: [{name: 'unsupported', format: 'sql',
        text: 'SELECT UNKNOWN_FUNCTION(1) AS value',
        ...(expectedCode === undefined ? {} : {expectedCode})}],
    });
  } finally {
    assert.equal(closed, true);
  }
}

test('an explicit implementation-limit expectation keeps the refusal checks', async () => {
  await exerciseRefusal('ClientProgramImplementationLimit', {
    expectedCode: 'ClientProgramImplementationLimit',
  });
});

test('implementation limits require an explicit fixture expectation', async () => {
  await assert.rejects(exerciseRefusal('ClientProgramImplementationLimit'),
    {code: 'ERR_ASSERTION'});
});

test('ordinary invalid input still uses the default refusal contract', async () => {
  await exerciseRefusal('ClientProgramInvalidInput');
});

test('an explicit expected code rejects a different valid input refusal', async () => {
  await assert.rejects(exerciseRefusal('ClientProgramInvalidInput', {
    expectedCode: 'ClientProgramImplementationLimit',
  }), {code: 'ERR_ASSERTION'});
});

test('an exact expected code cannot conceal Run admission', async () => {
  await assert.rejects(exerciseRefusal('ClientProgramImplementationLimit', {
    expectedCode: 'ClientProgramImplementationLimit', admit: true,
  }), {code: 'ERR_ASSERTION'});
});


test('outer refusal mismatch identifies the authored occurrence and backend', async () => {
  await assert.rejects(exerciseRefusal('ClientProgramInvalidInput', {
    submissionCode: 'SubmissionUnknown', requestPrefix: 'packed-local',
    expectedCode: 'ClientProgramInvalidInput',
  }), error => {
    assert.equal(error.code, 'ERR_ASSERTION');
    assert.equal(error.actual, 'SubmissionUnknown');
    assert.equal(error.expected, 'SubmissionNotAccepted');
    assert.match(error.message, /packed-local\/unsupported/u);
    assert.ok(!error.message.includes('SELECT UNKNOWN_FUNCTION'));
    return true;
  });
});

test('typed refusal mismatch identifies the authored occurrence and backend', async () => {
  await assert.rejects(exerciseRefusal('ClientProgramInvalidInput', {
    requestPrefix: 'packed-http', expectedCode: 'ClientProgramImplementationLimit',
  }), error => {
    assert.equal(error.code, 'ERR_ASSERTION');
    assert.equal(error.actual, 'ClientProgramInvalidInput');
    assert.equal(error.expected, 'ClientProgramImplementationLimit');
    assert.match(error.message, /packed-http\/unsupported/u);
    assert.ok(!error.message.includes('SELECT UNKNOWN_FUNCTION'));
    return true;
  });
});
