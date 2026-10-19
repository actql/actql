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
  // Protocol fixture only; exact Common identities have independent vectors.
  receiver.intentCid ??= () => cid('d');
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
  const acquire = () => registry.connect('/original/source', 'same', async () => host,
    {mode: 'local', owner: 'local'});
  const client = await acquire();
  return {client, acquire, port, get storeCloses() {return storeCloses;}, get sends() {return sends;}};
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

test('installed Host lease forwards query acquisition before raw options without a replacement Source snapshot', async () => {
  let reads = 0, snapshots = 0, queries = 0;
  const refusal = new Error('OriginalQueryUnavailable');
  const raw = Object.defineProperty({}, 'signal', {get() {reads++; return undefined;}});
  const receiver = {beforeSourceSnapshot() {snapshots++; assert.fail('NoSecondSnapshot');},
    beforeSourceQuery(format, text, parameters, options) {
      assert.equal(this, receiver);assert.equal(format, 'sql');assert.equal(text, 'SELECT 1');
      assert.equal(parameters, undefined);assert.equal(options, raw);queries++;throw refusal;
    }, bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {}};
  const f = await fixture(receiver, () => assert.fail('NoSubmission'));
  await assert.rejects(f.client.sql('SELECT 1', undefined, raw), error => error === refusal);
  assert.equal(queries, 1);assert.equal(snapshots, 0);assert.equal(reads, 0);assert.equal(f.sends, 0);
  await f.client.close();assert.equal(f.storeCloses, 1);
});

test('installed Host lease retains the original Result read pair at the eager query boundary', async () => {
  const queryRefusal = new Error('OriginalQueryUnavailable');let reads = 0, currents = 0;
  const receiver = {beforeSourceSnapshot() {assert.fail('NoSnapshot');},
    beforeSourceQuery() {throw queryRefusal;},bindSourceSnapshot() {},bindSourceRequest() {},finishSourceProducer() {},
    beforeResultRead(schema, options) {
      assert.equal(this, receiver);assert.equal(schema, undefined);assert.equal(options, undefined);reads++;
    },assertResultReadCurrent() {assert.equal(this, receiver);currents++;}};
  const f = await fixture(receiver, () => assert.fail('NoSubmission'));
  receiver.beforeResultRead = () => assert.fail('ReplacementRead');
  receiver.assertResultReadCurrent = () => assert.fail('ReplacementCurrent');
  const query = f.client.sql('SELECT 1');const all = query.all();
  assert.equal(reads, 1);
  await assert.rejects(all, error => error === queryRefusal);
  assert.equal(currents, 0);assert.equal(f.sends, 0);
  await f.client.close();assert.equal(f.storeCloses, 1);
});

test('query alias cleanup retains the Host after sibling lease release until its same retry', async () => {
  const receipt = {}, finishes = [];let released = false, queries = 0;
  const f = await fixture({beforeSourceSnapshot() {assert.fail('NoSecondSnapshot');},
    beforeSourceQuery() {queries++;return receipt;},bindSourceSnapshot() {},bindSourceRequest() {},
    finishSourceProducer(original, terminal) {
      assert.equal(original, receipt);assert.equal(terminal, 'failed');finishes.push(original);
      if (!released) throw new Error('OriginalQueryAliasesPending');
    }}, () => assert.fail('NoSubmission'));
  const sibling = await f.acquire();
  await assert.rejects(f.client.sql('SELECT 1', undefined, {unknown: true}), {code: 'InvalidQueryOptions'});
  await assert.rejects(f.client.close(), {code: 'ClientCleanupPending'});
  // This SDK has not released the failed-cleanup lease to the registry. The
  // sibling may release its own lease, but cannot acknowledge the held Host.
  await sibling.close();
  assert.equal(f.storeCloses, 0);assert.equal(queries, 1);assert.equal(f.sends, 0);
  released = true;
  await f.client.close();await sibling.close();
  assert.equal(f.storeCloses, 1);assert.equal(queries, 1);
  assert.deepEqual(finishes, [receipt, receipt, receipt]);
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

test('a sibling last lease cannot release another lease original pending Source producer', async () => {
  let finishes = 0, allowRetirement = false, closing;
  const receipt = {};
  const f = await fixture({beforeSourceSnapshot() {return receipt;},
    bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer(original) {
      assert.equal(original, receipt); finishes++;
      if (!allowRetirement) throw new Error('OriginalProducerStillRetained');
    }}, request => {
      closing = f.client.close(); closing.catch(() => {});
      return readySubmissionAttempt(request, admission);
    });
  const sibling = await f.acquire();
  await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('sibling-source-custody')}));
  await assert.rejects(closing, {code: 'ClientCleanupPending'});
  // The first lease still holds its original cleanup even if its retry failed.
  // Releasing a different lease cannot acknowledge those aliases.
  await assert.rejects(sibling.close(), {code: 'ClientCleanupPending'});
  assert.equal(f.storeCloses, 0); assert.equal(f.sends, 1); assert.equal(finishes, 1);
  allowRetirement = true;
  await f.client.close();
  await sibling.close();
  assert.equal(f.storeCloses, 1); assert.equal(f.sends, 1); assert.equal(finishes, 2);
});
