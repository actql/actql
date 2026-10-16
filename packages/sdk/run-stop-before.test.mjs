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

test('stopBefore selection changes the original intent while omission preserves its old CID', async t => {
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
  const original = originalSubmission('same-original-intent');
  const old = await client.start({}, {submissionRef: original});
  const selected = await client.start({}, {submissionRef: original, stopBefore: 'commit'});
  assert.equal(requests[0].intentCid,
    'sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44');
  // Independently hashed literal preimages shared with the Common counter.
  assert.equal(requests[1].intentCid,
    'sha256:4f9c3ae04162c1dba9cdc083c925ac8898e23d8f1b9da298ced13d3d62886d07');
  assert.deepEqual(requests[0].submissionRef, requests[1].submissionRef);
  assert.equal(Object.hasOwn(getSubmissionInput(old), 'stopBefore'), false);
  assert.equal(getSubmissionInput(selected).stopBefore, 'commit');
  assert.ok(Object.isFrozen(getSubmissionInput(selected)));
});

test('stopBefore observes the selected primitive once and rejects unknown choices before transport', async t => {
  let sends = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      if (operation === 'close') return undefined;
      assert.equal(operation, 'submit-intent');
      sends++;
      assert.equal(body.stopBefore, 'commit');
      return readySubmissionAttempt(body, {ref, durability: 'durable', revision: 7});
    },
  });
  t.after(() => client.close());
  for (const stopBefore of [null, false, 1, '', 'prepare', {}, ['commit']]) {
    await assert.rejects(client.start({}, {submissionRef: originalSubmission('invalid-stop'), stopBefore}),
      {code: 'InvalidClientPayload'});
  }
  assert.equal(sends, 0);
  let reads = 0;
  await client.start({}, {submissionRef: originalSubmission('read-once-stop'),
    get stopBefore() {reads++; return reads === 1 ? 'commit' : 'changed';}});
  assert.equal(reads, 1);
  assert.equal(sends, 1);
});
