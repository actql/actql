import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess, getSubmissionInput, getSubmissionOutcome} from './index.mjs';
import {sourcePreparationPort} from './internal/private-source-preparation.mjs';
import {submissionEpoch, originalSubmission, readySubmissionAttempt} from './submission-fixture.mjs';

// Explicit Source receiver/Host doubles; these tests do not issue operational
// capacity. The real installed owner must authenticate every original receipt.
const cid = value => 'sha256:' + value.repeat(64);
const admission = {ref: {namespaceId: 'source-receiver', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')}, durability: 'volatile', revision: 0};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'source-receiver', capabilities: ['aql-document'],
  submissionEpoch, limits: {maxReadWireBytes: 256, maxRowWireBytes: 128,
    maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 1024}};

async function fixture(receiver, perform) {
  const port = {[sourcePreparationPort]: receiver, async perform(operation, packet) {
    if (operation === 'connect') return profile;
    return perform(operation, packet);
  }};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  return {client, port};
}

test('Source refusal precedes every original option access and sends nothing', async t => {
  let reads = 0, sends = 0;
  const original = Object.assign(new Error('Unavailable'), {code: 'NodeSourceManagedAdmissionUnavailable'});
  const options = new Proxy({}, {get() {reads++; throw new Error('ReadBeforeAdmission');},
    ownKeys() {reads++; throw new Error('EnumeratedBeforeAdmission');}});
  const {client} = await fixture({beforeSourceSnapshot(kind, input, supplied) {
    assert.equal(kind, 'aql'); assert.equal(input, 'original'); assert.equal(supplied, options);
    throw original;
  }, bindSourceSnapshot() {assert.fail('NoSnapshot');},
  bindSourceRequest() {assert.fail('NoPacket');}, finishSourceProducer() {assert.fail('NoReceipt');}},
  () => {sends++;});
  t.after(() => client.close());
  await assert.rejects(client.startSource('original', options), error => error === original);
  assert.equal(reads, 0); assert.equal(sends, 0);
});

test('one original receipt binds the synchronous frozen snapshot and exact transport packet', async t => {
  const receipt = {}, parameters = {n: 1}, order = [];
  const options = {format: 'sql', parameters, submissionRef: originalSubmission('source-original')};
  let body, packet;
  const receiver = {
    beforeSourceSnapshot(kind, text, originalOptions) {
      order.push('before'); assert.equal(kind, 'aql'); assert.equal(text, 'SELECT @n AS n');
      assert.equal(originalOptions, options); return receipt;
    },
    bindSourceSnapshot(original, value) {
      order.push('snapshot'); assert.equal(original, receipt); body = value;
      assert.equal(Object.isFrozen(body), true); assert.equal(Object.isFrozen(body.parameters), true);
      assert.equal(body.parameters.n, 1);
    },
    bindSourceRequest(original, snapshot, value) {
      order.push('packet'); assert.equal(original, receipt); assert.equal(snapshot, body);
      assert.equal(value.parameters.n, 1); packet = value;
    },
    finishSourceProducer(original, terminal) {
      order.push('finish'); assert.equal(original, receipt); assert.equal(terminal, 'returned');
    },
  };
  const {client, port} = await fixture(receiver, (operation, value) => {
    order.push('perform'); assert.equal(operation, 'submit-intent'); assert.equal(value, packet);
    return readySubmissionAttempt(value, admission);
  });
  t.after(() => client.close());
  const pending = client.startSource('SELECT @n AS n', options);
  assert.deepEqual(order, ['before', 'snapshot']);
  parameters.n = 2;
  port[sourcePreparationPort] = {};
  const execution = await pending;
  assert.deepEqual(order, ['before', 'snapshot', 'packet', 'perform', 'finish']);
  assert.equal(getSubmissionInput(pending).parameters.n, 1);
  assert.equal(getSubmissionOutcome(execution).kind, 'ready');
  assert.deepEqual(execution.ref, admission.ref);
  assert.equal(Object.getOwnPropertySymbols(packet).length, 0);
  assert.equal(Object.hasOwn(packet, 'sourceProducer'), false);
});

test('failed producer cleanup retains original Unknown and retries only alias retirement on close', async () => {
  let sends = 0, finishes = 0;
  const receipt = {}, cleanup = new Error('OriginalAliasPending');
  const {client} = await fixture({beforeSourceSnapshot() {return receipt;},
    bindSourceSnapshot() {}, bindSourceRequest() {},
    finishSourceProducer(original, terminal) {
      assert.equal(original, receipt); assert.equal(terminal, 'failed');
      if (++finishes === 1) throw cleanup;
    }}, () => {sends++; throw new Error('OriginalReplyLost');});
  let original;
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-unknown')}), error => {
    original = error; return error.code === 'SubmissionUnknown';
  });
  assert.equal(original.requestId, 'source-unknown');
  assert.equal(sends, 1); assert.equal(finishes, 1);
  await client.close();
  assert.equal(sends, 1); assert.equal(finishes, 2);
});

test('successful producer cleanup failure retains the original returned Run without resubmission', async () => {
  let sends = 0, finishes = 0;
  const {client} = await fixture({beforeSourceSnapshot() {return {};},
    bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {
      if (++finishes === 1) throw new Error('OriginalAliasPending');
    }}, (_operation, packet) => {sends++; return readySubmissionAttempt(packet, admission);});
  let failure;
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-cleanup')}), error => {
    failure = error; return error.code === 'ClientCleanupPending';
  });
  assert.deepEqual(failure.execution.ref, admission.ref);
  assert.equal(Object.getOwnPropertyDescriptor(failure, 'execution').enumerable, false);
  assert.equal(getSubmissionOutcome(failure).kind, 'ready');
  await client.close();
  assert.equal(sends, 1); assert.equal(finishes, 2);
});

test('packet binding refusal remains NotSent and never reaches the Host', async t => {
  let sends = 0, finishes = 0;
  const {client} = await fixture({beforeSourceSnapshot() {return {};}, bindSourceSnapshot() {},
    bindSourceRequest() {throw new Error('ForeignOriginalPacket');},
    finishSourceProducer(_original, terminal) {assert.equal(terminal, 'failed'); finishes++;}},
  () => {sends++;});
  t.after(() => client.close());
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-no-send')}), {code: 'SubmissionNotSent'});
  assert.equal(sends, 0); assert.equal(finishes, 1);
});
