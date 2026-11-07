import {submissionAttempt} from './submission-fixture.mjs';
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

test('explicit restart saves its original history link before first send and never retries a lost reply', async () => {
  let sends = 0;
  const freshEpoch = {...epoch, epochNonce: 'd'.repeat(64), notBefore: epoch.expiresAt,
    expiresAt: epoch.expiresAt + 1000};
  const original = {epoch, nonce: 'unresolvable-original'};
  const unresolvedHistory = {submissionRef: original, acknowledgement: 'possible_prior_execution_and_effects'};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return {...profile, submissionEpoch: freshEpoch};
      assert.equal(operation, 'restart-intent');
      sends++;
      assert.deepEqual(body.unresolvedHistory.submissionRef, original);
      throw new Error('FixtureRestartReplyLost');
    },
  });
  const submissionRef = client.newSubmission({nonce: 'explicit-new-work'});
  const pending = client.start({}, {submissionRef, unresolvedHistory});
  assert.deepEqual(getSubmissionInput(pending).unresolvedHistory, unresolvedHistory);
  unresolvedHistory.acknowledgement = 'caller mutation after submission';
  await assert.rejects(pending, error => {
    assert.equal(getSubmissionInput(error).unresolvedHistory.acknowledgement, 'possible_prior_execution_and_effects');
    assert.deepEqual(error.submissionRef, submissionRef);
    return error.code === 'SubmissionUnknown';
  });
  assert.equal(sends, 1);
  await client.close();
});

test('explicit restart rejects missing or changed acknowledgement in the Host reply', async () => {
  for (const change of ['missing', 'original', 'acknowledgement']) {
    let sends = 0;
    const original = {epoch, nonce: 'unresolvable-original'};
    const unresolvedHistory = {submissionRef: original, acknowledgement: 'possible_prior_execution_and_effects'};
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body) {
        if (operation === 'connect') return {...profile, submissionEpoch: {...epoch,
          epochNonce: 'd'.repeat(64), notBefore: epoch.expiresAt, expiresAt: epoch.expiresAt + 1000}};
        assert.equal(operation, 'restart-intent'); sends++;
        // The intent CID remains the registered independent vector: history
        // acknowledgement is separately bound, not inserted in its preimage.
        assert.equal(body.intentCid, 'sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44');
        const response = {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid};
        if (change !== 'missing') response.unresolvedHistory = change === 'original'
          ? {...unresolvedHistory, submissionRef: {...original, nonce: 'different-original'}}
          : {...unresolvedHistory, acknowledgement: 'retry'};
        return submissionAttempt(body, response);
      },
    });
    await assert.rejects(client.start({}, {submissionRef: client.newSubmission(), unresolvedHistory}),
      {code: 'SubmissionUnknown'});
    assert.equal(sends, 1);
    await client.close();
  }
});

test('risk acknowledgement requires caller-retained fresh identity and rejects invalid scope before send', async () => {
  let sends = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return {...profile, submissionEpoch: {...epoch,
        epochNonce: 'd'.repeat(64), notBefore: epoch.expiresAt, expiresAt: epoch.expiresAt + 1000}};
      sends++; throw new Error('MustNotSend');
    },
  });
  const original = {epoch, nonce: 'old'};
  const unresolvedHistory = {submissionRef: original, acknowledgement: 'possible_prior_execution_and_effects'};
  await assert.rejects(client.start({}, {unresolvedHistory}), {code: 'SubmissionReferenceRequired'});
  await assert.rejects(client.start({}, {submissionRef: client.newSubmission(), unresolvedHistory: {
    ...unresolvedHistory, submissionRef: {...original, epoch: {...epoch, authorityScopeCid: cid('0')}}},
  }), {code: 'InvalidSubmissionRestart'});
  assert.equal(sends, 0);
  await client.close();
});

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
  const pending = client.startSource(source, {format: 'aql-text', submissionRef, parameters});
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
      return submissionAttempt(body, {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid});
    },
  });
  const submissionRef = client.newSubmission({nonce: 'independent-vector'});
  await assert.rejects(client.start({}, {submissionRef}), {code: 'SubmissionPreparing'});
  client.close();
});

test('SDK read-only original has an independent fingerprint and cannot be disabled', async () => {
  let sends = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      assert.equal(operation, 'submit-intent'); sends++;
      assert.equal(body.readOnly, true);
      assert.equal(body.intentCid, 'sha256:2b7e2e13949315aa9877b748f60fd0b922f8271d663808af2fabd61c12745719');
      return submissionAttempt(body, {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid});
    },
  });
  try {
    const pending = client.start({}, {readOnly: true});
    assert.equal(getSubmissionInput(pending).readOnly, true);
    await assert.rejects(pending, {code: 'SubmissionPreparing'});
    for (const readOnly of [false, null, undefined, 'true', 1, {}]) {
      await assert.rejects(client.start({}, {readOnly}), {code: 'InvalidClientPayload'});
    }
    assert.equal(sends, 1);
  } finally {await client.close();}
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
        return submissionAttempt(body, {kind: 'preparing', submissionRef: change === 'nonce'
          ? {...body.submissionRef, nonce: 'another-nonce'} : body.submissionRef,
          intentCid: change === 'intent' ? cid('0') : body.intentCid});
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

test('ordinary SDK submission exposes its original identity and input before first send', async () => {
  let release;
  const answer = new Promise(resolve => {release = resolve;});
  let received;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      received = {operation, body};
      await answer;
      return submissionAttempt(body, {kind: 'preparing', submissionRef: body.submissionRef, intentCid: body.intentCid});
    },
  });
  const parameters = {value: 'e\u0301\r\n'};
  const pending = client.startSource('SELECT @value AS n', {format: 'sql', parameters});
  const input = getSubmissionInput(pending);
  try {
    assert.ok(input, 'the pending operation must expose its pre-send original');
    assert.deepEqual(input.submissionRef.epoch, epoch);
    assert.equal(typeof input.submissionRef.nonce, 'string');
    assert.equal(input.input.text, 'SELECT @value AS n');
    assert.deepEqual(input.parameters, {value: 'e\u0301\r\n'});
    parameters.value = 'changed after call';
  } finally {release();}
  await assert.rejects(pending, error => {
    assert.deepEqual(getSubmissionInput(error), input);
    return error.code === 'SubmissionPreparing';
  });
  assert.equal(received.operation, 'submit-intent');
  assert.deepEqual(received.body.submissionRef, input.submissionRef);
  assert.deepEqual(received.body.parameters, input.parameters);
  client.close();
});

test('public name never falls back to a legacy epoch operation when the named supplier is absent', async () => {
  let submissions = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      submissions++;
      assert.equal(operation, 'submit-named-intent');
      assert.equal(body.requestName, 'unknown-old-operation');
      throw new Error('named supplier unavailable');
    },
  });
  await assert.rejects(client.start({}, {requestId: 'unknown-old-operation'}),
    {code: 'SubmissionUnknown'});
  assert.equal(submissions, 1);
  client.close();
});

test('a Host without a submission epoch cannot trigger a legacy submission fallback', async () => {
  let submissions = 0;
  const {submissionEpoch, ...readOnlyProfile} = profile;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return readOnlyProfile;
      submissions++;
      throw new Error('fixture must not receive a legacy fallback');
    },
  });
  await assert.rejects(client.start({}), {code: 'SubmissionEpochUnavailable'});
  assert.equal(submissions, 0);
  client.close();
});

test('closed Client is known unsent and retains its original submission instead of claiming nonacceptance', async () => {
  let submissions = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return profile;
      submissions++;
      throw new Error('fixture must not be called after close');
    },
  });
  const submissionRef = client.newSubmission({nonce: 'closed-original'});
  client.close();
  const pending = client.start({}, {submissionRef});
  await assert.rejects(pending, error => {
    assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
    assert.equal(error.outcome, undefined);
    return error.code === 'SubmissionNotSent';
  });
  assert.equal(submissions, 0);
});

test('SDK submitted outcome needs no verification clone after admission', async t => {
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      if (operation === 'connect') return profile;
      return submissionAttempt(body, {kind: 'not_accepted', submissionRef: body.submissionRef,
        intentCid: body.intentCid, problem: {code: 'ClientProgramRejected', classification: 'operation_failed'}});
    },
  });
  t.after(() => client.close());
  const submissionRef = client.newSubmission({nonce: 'original-durable-outcome'});
  const nativeClone = globalThis.structuredClone;
  const clone = t.mock.method(globalThis, 'structuredClone', value => {
    if (Object.hasOwn(value, 'connection')) return nativeClone(value);
    assert.fail('Unexpected response verification clone');
  });
  let failure;
  try {await client.start({}, {submissionRef});} catch (error) {failure = error;}
  assert.equal(failure?.code, 'SubmissionNotAccepted', '[check-mutation:request-held-admission]');
  assert.deepEqual(getSubmissionInput(failure).submissionRef, submissionRef);
  assert.equal(clone.mock.calls.filter(({arguments: [value]}) => !Object.hasOwn(value, 'connection')).length, 0);
});
