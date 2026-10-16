import assert from 'node:assert/strict';
import test from 'node:test';
import {getSubmissionInput} from './index.mjs';
import {connectInProcess} from './host-port.mjs';
import {originalSubmission, readySubmissionAttempt, submissionEpoch} from './submission-fixture.mjs';

const ref = {namespaceId: 'stop-before-namespace',
  authorityScopeCid: submissionEpoch.authorityScopeCid,
  runDefinitionCid: `sha256:${'d'.repeat(64)}`};
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'stop-before-principal', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

// This counter establishes only SDK request preservation. The echoed admission
// is not an authorization, Checkpoint, physical dispatch or durable Host proof.
test('stopBefore commit reaches the original submission intent without changing its Run', async t => {
  const requests = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      if (operation === 'close') return undefined;
      assert.equal(operation, 'submit-intent');
      requests.push(body);
      return readySubmissionAttempt(body, {ref, durability: 'durable', revision: 7});
    },
  });
  t.after(() => client.close());
  const run = await client.startSource('SELECT 1 AS n', {format: 'aql-text',
    submissionRef: originalSubmission('stop-before-original'), stopBefore: 'commit'});
  assert.equal(requests.length, 1);
  assert.equal(requests[0].stopBefore, 'commit');
  assert.equal(getSubmissionInput(run).stopBefore, 'commit');
  assert.equal(run.ref.runDefinitionCid, ref.runDefinitionCid);
});
