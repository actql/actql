// Run from an installation containing only sdk and client-wire. The actual
// HTTPS Host runs separately in the standard Node consumer.
import assert from 'node:assert/strict';
import {connect, getSubmissionInput} from '@actql/sdk';
const client = await connect({mode: 'remote', endpoint: process.env.ACTQL_RELEASE_TEST_ENDPOINT,
  token: 'short-token'});
try {
  const query = client.sql('SELECT 17 AS id', undefined,
    {submissionRef: client.newSubmission({nonce: 'release-sdk-only'})});
  const requestId = query.requestId;
  const result = await query;
  assert.equal(getSubmissionInput(result).requestId, requestId);
  assert.deepEqual(await result.all(), [{id: 17}]);
  const recovery = client.recoverRequest(result), observed = await recovery.lookup();
  assert.equal(observed.kind, 'ready');
  assert.deepEqual((await recovery.attach(observed)).ref, result.execution.ref);
  assert.deepEqual(await result.all(), [{id: 17}]);
  console.log('SDK-only registry consumer: real HTTPS, independent Result and original request lookup passed');
} finally {await client.close();}
