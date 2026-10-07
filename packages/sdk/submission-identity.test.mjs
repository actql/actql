import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess, getSubmissionInput} from './index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const epoch = {version: 'actql-submission-epoch/0.1', authorityScopeCid: cid('a'),
  epochNonce: 'b'.repeat(64), authenticator: 'c'.repeat(64),
  notBefore: 1_800_000_000_000, expiresAt: 1_800_000_001_000};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable',
  scopeRef: 'submission-test', capabilities: ['aql-document'], submissionEpoch: epoch,
  limits: {maxReadWireBytes: 1024, maxRowWireBytes: 256, maxRowRetainedValueBytes: 512,
    maxRetainedValueBytes: 2048, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

test('SDK saves exact submission ref and original source before a lost response', async () => {
  let body;
  const client = await connectInProcess({mode: 'local', owner: 'local', durability: 'durable'}, {
    async perform(operation, value) {
      if (operation === 'connect') return profile;
      assert.equal(operation, 'submit-intent'); body = value;
      throw new Error('fixture acceptance reply lost');
    },
  });
  const submissionRef = client.newSubmission({nonce: 'original-nonce'});
  const parameters = {nested: ['e\u0301', 'é', '\r', '\n', '\r\n']};
  const source = "SELECT 'e\u0301\r\n' AS value";
  const pending = client.aql(source, {format: 'aql-text', submissionRef, parameters});
  parameters.nested[0] = 'changed after call';
  let error;
  await assert.rejects(pending, value => {error = value; return value.code === 'SubmissionUnknown';});
  assert.deepEqual(error.submissionRef, submissionRef);
  const retained = getSubmissionInput(error);
  assert.deepEqual(retained.submissionRef, submissionRef);
  assert.equal(retained.input.text, source);
  assert.deepEqual(retained.parameters, {nested: ['e\u0301', 'é', '\r', '\n', '\r\n']});
  assert.deepEqual(body.submissionRef, submissionRef);
  assert.equal(body.input.text, source);
  assert.deepEqual(body.parameters, retained.parameters);
  assert.equal(getSubmissionInput({...error}), undefined);
  client.close();
});

test('SDK submitted-intent CID has an independent value-preserving preimage', async () => {
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      assert.equal(operation, 'submit-intent');
      assert.equal(body.intentCid, 'sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44');
      return {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid};
    },
  });
  const submissionRef = client.newSubmission({nonce: 'independent-vector'});
  await assert.rejects(client.start({}, {submissionRef}), {code: 'SubmissionPreparing'});
  client.close();
});

test('SDK reconnect lookup preserves the original epoch and nonce without submission', async () => {
  const original = {epoch, nonce: 'retained-original'};
  let calls = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return {...profile, submissionEpoch: {...epoch, epochNonce: 'd'.repeat(64)}};
      assert.equal(operation, 'lookup-submission'); calls++;
      assert.deepEqual(body.submissionRef, original);
      return {kind: 'unresolvable', submissionRef: original, problem: {code: 'submission_history_unresolvable'}};
    },
  });
  const found = await client.lookupSubmission(original);
  assert.equal(found.kind, 'unresolvable');
  assert.deepEqual(found.submissionRef, original);
  assert.equal(calls, 1);
  assert.notDeepEqual(client.newSubmission({nonce: original.nonce}), original);
  client.close();
});

test('SDK rejects a response bound to another submission or intent', async () => {
  for (const change of ['nonce', 'intent']) {
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body) {
        if (operation === 'connect') return profile;
        return {kind: 'preparing', submissionRef: change === 'nonce'
          ? {...body.submissionRef, nonce: 'another-nonce'} : body.submissionRef,
          intentCid: change === 'intent' ? cid('0') : body.intentCid};
      },
    });
    const submissionRef = client.newSubmission({nonce: 'exact-original'});
    await assert.rejects(client.start({}, {submissionRef}), error => {
      assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
      return error.code === 'SubmissionUnknown';
    });
    client.close();
  }
});
