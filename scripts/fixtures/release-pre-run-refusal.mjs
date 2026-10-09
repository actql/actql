// Current installed Host deliberately refuses epoch-bound pre-Run deferral.
// This checks that limit and original lookup; it is not approval acceptance.
import assert from 'node:assert/strict';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {connect} from '@actql/node';

const step = process.argv[2], authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
authorization.resumeAfterAnswer = false;
authorization.faultInjection = name => appendFileSync('embedded-events.log', `${name}\n`);
const client = await connect({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: join(process.cwd(), 'state'), authorization}});
const problem = {classification: 'operation_failed', code: 'ACTQL_E_DELEGATION_UNAVAILABLE'};
try {
  if (step === 'submit') {
    const submissionRef = client.newSubmission({nonce: 'release-delegation-refusal'});
    writeFileSync('submission.json', JSON.stringify(submissionRef), {mode: 0o600, flag: 'wx'});
    await assert.rejects(client.startSource(readFileSync('values.json', 'utf8'), {format: 'json', submissionRef}), error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      assert.equal(error.outcome.kind, 'preparation_failed'); assert.deepEqual(error.outcome.problem, problem);
      assert.deepEqual(error.outcome.submissionRef, submissionRef); assert.equal(error.outcome.ref, undefined); return true;
    });
  } else assert.equal(step, 'lookup');
  const submissionRef = JSON.parse(readFileSync('submission.json', 'utf8'));
  const lookup = await client.lookupSubmission(submissionRef);
  assert.equal(lookup.kind, 'preparation_failed'); assert.deepEqual(lookup.problem, problem);
  assert.deepEqual(lookup.submissionRef, submissionRef); assert.equal(lookup.ref, undefined);
  console.log(step === 'submit' ? 'delegation-refused' : 'original-refusal-preserved');
} finally {await client.close();}
