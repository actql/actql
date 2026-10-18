import assert from 'node:assert/strict';
import test from 'node:test';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {submissionEpoch, originalSubmission, readySubmissionAttempt} from
  '../../packages/sdk/submission-fixture.mjs';

// Actual registry and SDK, explicit Source/physical Host doubles. This does
// not issue installation capacity, authenticate a Source or perform file I/O.
const cid = digit => `sha256:${digit.repeat(64)}`;
const admission = {ref: {namespaceId: 'original-source', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')}, durability: 'volatile', revision: 0};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'original-source', capabilities: ['aql-document'],
  submissionEpoch, limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
    maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};

async function fixture(receiver, perform) {
  let storeCloses = 0, sends = 0;
  const port = {[sourcePreparationPort]: receiver, async perform(operation, request) {
    if (operation === 'connect') return profile;
    sends++;
    assert.equal(operation, 'submit-intent');
    return perform(request);
  }};
  const host = {port, dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {storeCloses++;}}};
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const client = await registry.connect('/original/source', 'same', async () => host,
    {mode: 'local', owner: 'local'});
  return {client, port, get storeCloses() {return storeCloses;}, get sends() {return sends;}};
}

test('installed Host lease delivers the original synchronous Source refusal before option reads', async () => {
  let reads = 0, before = 0;
  const refusal = Object.assign(new Error('OriginalSourceUnavailable'),
    {code: 'SourceManagedPreparationUnavailable'});
  const receiver = {beforeSourceSnapshot(kind, input, options) {
    assert.equal(this, receiver); assert.equal(kind, 'aql'); assert.equal(input, 'original');
    assert.equal(options, raw); before++; throw refusal;
  }, bindSourceSnapshot() {assert.fail('NoSnapshot');},
  bindSourceRequest() {assert.fail('NoRequest');}, finishSourceProducer() {assert.fail('NoReceipt');}};
  const raw = new Proxy({}, {get() {reads++; throw new Error('ReadBeforeOriginal');},
    ownKeys() {reads++; throw new Error('EnumeratedBeforeOriginal');}});
  const f = await fixture(receiver, () => assert.fail('NoSend'));
  await assert.rejects(f.client.startSource('original', raw), error => error === refusal);
  assert.equal(before, 1); assert.equal(reads, 0); assert.equal(f.sends, 0);
  await f.client.close(); assert.equal(f.storeCloses, 1);
});

test('installed Host lease retains one original receiver and complete Source snapshot/request/finish pair', async () => {
  const receipt = {}, order = [];
  let body, packet;
  const receiver = {beforeSourceSnapshot(kind, input, options) {
    assert.equal(this, receiver); assert.equal(kind, 'aql'); assert.equal(input, 'SELECT 1 AS n');
    assert.equal(options, raw); order.push('before'); return receipt;
  }, bindSourceSnapshot(original, value) {
    assert.equal(this, receiver); assert.equal(original, receipt); body = value;
    assert.equal(Object.isFrozen(body), true); order.push('snapshot');
  }, bindSourceRequest(original, value, request) {
    assert.equal(this, receiver); assert.equal(original, receipt); assert.equal(value, body);
    packet = request; order.push('request');
  }, finishSourceProducer(original, terminal) {
    assert.equal(this, receiver); assert.equal(original, receipt); assert.equal(terminal, 'returned');
    order.push('finish');
  }};
  const raw = {format: 'sql', submissionRef: originalSubmission('same-host-source')};
  const f = await fixture(receiver, request => {
    assert.equal(request, packet); order.push('perform');
    assert.equal(Object.getOwnPropertySymbols(request).length, 0);
    return readySubmissionAttempt(request, admission);
  });
  // Replacing either public property after connection cannot redirect captured
  // original receiver/methods or create another Source preparation.
  f.port[sourcePreparationPort] = {};
  receiver.beforeSourceSnapshot = () => assert.fail('ReplacementBefore');
  receiver.finishSourceProducer = () => assert.fail('ReplacementFinish');
  const pending = f.client.startSource('SELECT 1 AS n', raw);
  assert.deepEqual(order, ['before', 'snapshot']);
  const execution = await pending;
  assert.deepEqual(execution.ref, admission.ref);
  assert.deepEqual(order, ['before', 'snapshot', 'request', 'perform', 'finish']);
  await f.client.close(); assert.equal(f.sends, 1); assert.equal(f.storeCloses, 1);
});

test('close racing the first producer retirement retains the same retry and never releases Host custody early', async () => {
  const receipt = {};
  let finishes = 0, close;
  const receiver = {beforeSourceSnapshot() {return receipt;},
    bindSourceSnapshot() {}, bindSourceRequest() {},
    finishSourceProducer(original) {
      assert.equal(this, receiver); assert.equal(original, receipt);
      if (++finishes === 1) throw new Error('OriginalProducerStillRetained');
    }};
  const f = await fixture(receiver, request => {
    close = f.client.close();
    // Observe the rejection immediately without changing its original result.
    close.catch(() => {});
    return readySubmissionAttempt(request, admission);
  });
  const pending = f.client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('same-host-retirement')});
  await assert.rejects(pending);
  await assert.rejects(close, {code: 'ClientCleanupPending'});
  assert.equal(finishes, 1); assert.equal(f.sends, 1); assert.equal(f.storeCloses, 0);
  await f.client.close();
  assert.equal(finishes, 2); assert.equal(f.sends, 1); assert.equal(f.storeCloses, 1);
});
