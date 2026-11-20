import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {captureSourcePreparation, sourcePreparationPort} from './internal/private-source-preparation.mjs';
import {captureQueryResultRead, collectCapturedResult, createResultFactory} from './internal/result-read.mjs';
import {submissionEpoch, readySubmissionAttempt} from './submission-fixture.mjs';

// Actual SDK entry points with explicit Host/resource ports, not operational
// capacity or a physical Result Store. Only the installed owner can issue it.
const cid = digit => 'sha256:' + digit.repeat(64);
const ref = {namespaceId: 'original-result', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const time = '2026-10-07T00:00:00.000Z';
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'result-scope', capabilities: ['aql-document'], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const source = () => ({
  captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
  assertSourceSnapshotCurrent() {},
  publishSourceSnapshot() {},
  beforeSourceSnapshot() {return {};}, bindSourceSnapshot() {},
  beforeSourceQuery() {return {};}, bindSourceRequest() {}, finishSourceProducer() {}, intentCid() {return cid('c');}});
async function fixture(t, beforeResultRead, wait, assertResultReadCurrent = () => {}) {
  const receiver = source(), calls = [];
  if (beforeResultRead !== undefined) receiver.beforeResultRead = beforeResultRead;
  receiver.assertResultReadCurrent = assertResultReadCurrent;
  const port = {[sourcePreparationPort]: receiver, async perform(operation, packet) {
    calls.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref, durability: 'volatile', revision: 1};
    if (operation === 'submit-intent') return readySubmissionAttempt(packet,
      {ref, durability: 'volatile', revision: 1});
    if (operation === 'wait') {
      await wait?.();
      return {version: 'actql-run-state/0.1', run_id: 'original-result', revision: 1,
        status: 'succeeded', updated_at: time, next_action: {kind: 'read_result', results: ['answer']},
        result_available: true, result_availability: {answer: {state: 'available',
          observed_at: time, reason: 'confirmed_present'}}};
    }
    assert.equal(operation, 'read');
    return {kind: 'rows', frames: (async function* () {
      yield {value: {n: 1}, byteLength: 8};
    })()};
  }};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  return {client, receiver, calls, result: (await client.attach(ref)).result('answer')};
}

test('Result callback retains its original receiver and does not acquire a replacement', () => {
  const receiver = source(), raw = {}, options = {}, calls = [];
  receiver.beforeResultRead = function (...args) {calls.push([this, ...args]);};
  receiver.assertResultReadCurrent = () => {};
  const captured = captureSourcePreparation({[sourcePreparationPort]: receiver});
  receiver.beforeResultRead = () => assert.fail('Replacement');
  captured.beforeResultRead(raw, options);
  assert.deepEqual(calls, [[receiver, raw, options]]);
});

test('missing, accessor and nonvoid Result callbacks refuse only at the read boundary', async () => {
  let reads = 0;
  for (const make of [receiver => {}, receiver => Object.defineProperty(receiver, 'beforeResultRead',
    {get() {reads++; assert.fail('Getter');}}), receiver => {receiver.beforeResultRead = () => false;},
  receiver => {receiver.beforeResultRead = () => Promise.reject(new Error('Pending'));}]) {
    const receiver = {...source(), assertResultReadCurrent() {}}; make(receiver);
    const captured = captureSourcePreparation({[sourcePreparationPort]: receiver});
    assert.equal(captured.intentCid({}, {}), cid('c'));
    assert.throws(() => captured.beforeResultRead(undefined, undefined),
      {code: 'NodeSourceManagedAdmissionUnavailable'});
  }
  await Promise.resolve();
  assert.equal(reads, 0);
});

for (const method of ['rows', 'batches', 'all', 'one', 'scalar']) {
  test(`Result ${method} refuses before inspecting original caller options or starting read`, async t => {
    let accesses = 0;
    const original = new Error('OriginalResultUnavailable');
    const raw = new Proxy({}, {get() {accesses++; throw new Error('Read');},
      has() {accesses++; throw new Error('Has');}, ownKeys() {accesses++; throw new Error('Keys');}});
    const f = await fixture(t, function (first, second) {
      assert.equal(this, f.receiver); assert.equal(first, raw); assert.equal(second, undefined);
      throw original;
    });
    const uuid = mock.method(globalThis.crypto, 'randomUUID', () => assert.fail('UUIDBeforeAdmission'));
    t.after(() => uuid.mock.restore());
    if (['rows', 'batches'].includes(method)) assert.throws(() => f.result[method](raw), error => error === original);
    else await assert.rejects(f.result[method](raw), error => error === original);
    assert.equal(accesses, 0); assert.equal(f.calls.includes('read'), false);
  });
}

test('selected omitted Result inputs stay omitted across all internal defaults', async t => {
  const f = await fixture(t, (first, second) => {
    assert.equal(first, undefined); assert.equal(second, undefined);
  });
  assert.deepEqual(await f.result.all(), [{n: 1}]);
  assert.deepEqual(await Array.fromAsync(f.result.rows()), [{n: 1}]);
  assert.deepEqual(await Array.fromAsync(f.result.batches()), [[{n: 1}]]);
  assert.deepEqual(await f.result.one(), {n: 1});
  assert.equal(await f.result.scalar(), 1);
  assert.equal(f.calls.filter(x => x === 'read').length, 5);
});

for (const method of ['all', 'one', 'scalar']) {
  test(`query ${method} checks the same omitted originals before capture and after wait`, async t => {
    let release, checks = 0, currentChecks = 0;
    const pending = new Promise(resolve => {release = resolve;});
    const f = await fixture(t, (first, second) => {
      checks++; assert.equal(first, undefined); assert.equal(second, undefined);
    }, () => pending, () => {currentChecks++;});
    const query = f.client.sql('SELECT 1 AS n');
    const collected = query[method]();
    assert.equal(checks, 1);
    assert.equal(f.calls.includes('read'), false);
    release();
    assert.deepEqual(await collected, method === 'all' ? [{n: 1}] : method === 'one' ? {n: 1} : 1);
    assert.equal(checks, 1); assert.equal(currentChecks, 2);
    assert.equal(f.calls.filter(x => x === 'submit-intent').length, 1);
    assert.equal(f.calls.filter(x => x === 'read').length, 1);
  });
}

test('query read refuses changed current original after await without sending a read', async t => {
  let release, current = true;
  const original = new Error('OriginalResultRetired');
  const pending = new Promise(resolve => {release = resolve;});
  const f = await fixture(t, () => {}, () => pending, () => {if (!current) throw original;});
  const collected = f.client.sql('SELECT 1 AS n').all();
  current = false; release();
  await assert.rejects(collected, error => error === original);
  assert.equal(f.calls.includes('read'), false);
});

test('eager query read refusal observes its query and sends no Result read', async t => {
  const original = new Error('OriginalResultUnavailable');
  const f = await fixture(t, () => {throw original;});
  const raw = new Proxy({}, {get() {assert.fail('OriginalRead');}, has() {assert.fail('OriginalHas');}});
  const query = f.client.sql('SELECT 1 AS n');
  await assert.rejects(query.all(raw), error => error === original);
  await query;
  assert.equal(f.calls.includes('read'), false);
});

test('a lazy reader rechecks original currentness before its first transport read', async t => {
  let current = true;
  const original = new Error('OriginalResultRetired');
  const f = await fixture(t, () => {}, undefined, () => {if (!current) throw original;});
  const reader = f.result.rows();
  current = false;
  await assert.rejects(Array.fromAsync(reader), error => error === original);
  assert.equal(f.calls.includes('read'), false);
});

test('copied captures and another installation cannot consume a selected Result continuation', async t => {
  const before = () => {}, current = () => {};
  const f = await fixture(t, before, undefined, current);
  const foreign = captureQueryResultRead(before, current, 'all', undefined, undefined);
  // The SDK captured installation methods are distinct from borrowed raw
  // receiver callbacks, even when both would return undefined.
  assert.throws(() => collectCapturedResult(f.result, foreign), {code: 'InvalidResult'});
  assert.throws(() => collectCapturedResult(f.result, {...foreign}), {code: 'InvalidResult'});
  assert.equal(f.calls.includes('read'), false);
});

test('an original captured query continuation starts exactly one read', async () => {
  let reads = 0;
  const before = () => {}, current = () => {};
  const result = createResultFactory({ref, limits: profile.limits, lookupContext: {},
    typedRows: true, beforeResultRead: before, assertResultReadCurrent: current},
  {runRequest() {reads++; return {kind: 'rows', frames: (async function* () {
    yield {value: {n: 1}, byteLength: 8};
  })()};}, responseValue() {}},
  {activeReaders: new Set(), readerCleanups: new Set()}, () => undefined)('answer');
  const token = captureQueryResultRead(before, current, 'all', undefined, undefined);
  const collected = collectCapturedResult(result, token);
  assert.throws(() => collectCapturedResult(result, token), {code: 'InvalidResult'});
  assert.deepEqual(await collected, [{n: 1}]);
  assert.equal(reads, 1);
});
