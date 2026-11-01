import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {getSubmissionInput} from './index.mjs';
import {sourcePreparationPort} from './internal/private-source-preparation.mjs';
import {submissionEpoch, readySubmissionAttempt} from './submission-fixture.mjs';

// Actual SDK objects with explicit original-resource/Host controls. These
// callbacks issue no installed capacity, Account grant or durable Run proof.
const cid = digit => 'sha256:' + digit.repeat(64);
const ref = {namespaceId: 'original-query', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'original-query', capabilities: ['aql-document'], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const state = {version: 'actql-run-state/0.1', run_id: 'original-query', revision: 1,
  status: 'succeeded', updated_at: '2026-10-20T00:00:00.000Z',
  next_action: {kind: 'read_result', results: ['answer']}, result_available: true,
  result_availability: {answer: {state: 'available', observed_at: '2026-10-20T00:00:00.000Z',
    reason: 'confirmed_present'}}};
const source = () => ({
  captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
  assertSourceSnapshotCurrent() {},
  publishSourceSnapshot() {},
  beforeSourceSnapshot() {assert.fail('NoSecondAdmission');},
  bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {}, intentCid() {return cid('c');},
  beforeResultRead() {}, assertResultReadCurrent() {}});
async function fixture(t, receiver, overrides = {}) {
  const calls = [];
  const port = {async perform(operation, packet) {
    calls.push(operation);
    if (operation === 'connect') return profile;
    if (overrides[operation]) return overrides[operation](packet);
    if (operation === 'submit-intent') return readySubmissionAttempt(packet,
      {ref, durability: 'volatile', revision: 1});
    if (operation === 'wait') return state;
    if (operation === 'read') return {kind: 'rows', frames: (async function* () {
      yield {value: {n: 1}, byteLength: 8};
    })()};
    assert.fail(operation);
  }};
  if (receiver !== undefined) port[sourcePreparationPort] = receiver;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  return {client, calls, port};
}

for (const [method, format] of [['sql', 'sql'], ['aql', 'aql-text']]) {
  test(`${method} original refusal precedes every raw query option getter and enumeration`, async t => {
    let reads = 0, before = 0;
    const original = new Error('OriginalQueryUnavailable'), parameters = {};
    const options = new Proxy({}, {get() {reads++; assert.fail('UnownedGet');},
      ownKeys() {reads++; assert.fail('UnownedKeys');}});
    const receiver = {...source(), beforeSourceQuery(actualFormat, text, params, raw) {
      before++; assert.equal(this, receiver); assert.equal(actualFormat, format);
      assert.equal(text, 'original'); assert.equal(params, parameters); assert.equal(raw, options);
      throw original;
    }};
    const f = await fixture(t, receiver);
    const query = f.client[method]('original', parameters, options);
    assert.ok(query instanceof Promise); assert.equal(typeof query.all, 'function');
    await assert.rejects(query, error => error === original);
    assert.equal(before, 1); assert.equal(reads, 0); assert.deepEqual(f.calls, ['connect']);
  });

  test(`${method} uses one original receipt for capture, request, identity and terminal before wait`, async t => {
    const receipt = {}, parameters = {n: {original: 1}}, options = {}, events = [];
    let body, observed;
    const receiver = {...source(), beforeSourceQuery(actualFormat, text, params, raw) {
      events.push('before'); assert.equal(this, receiver); assert.equal(actualFormat, format);
      assert.equal(text, 'original'); assert.equal(params, parameters); assert.equal(raw, options);
      return receipt;
    }, bindSourceSnapshot(value, captured) {
      events.push('snapshot'); assert.equal(value, receipt); body = captured;
      assert.equal(captured.input.text, 'original'); assert.equal(captured.input.format, format);
      assert.equal(captured.readOnly, true); assert.equal(Object.isFrozen(captured), true);
      assert.equal(captured.parameters.n.original, 1);
    }, intentCid(value, captured) {
      events.push('identity'); assert.equal(value, receipt); assert.equal(captured, body); return cid('c');
    }, bindSourceRequest(value, captured, packet) {
      events.push('request'); assert.equal(value, receipt); assert.equal(captured, body);
      assert.equal(packet.input.text, 'original'); assert.equal(packet.parameters.n.original, 1);
      observed = packet;
    }, finishSourceProducer(value, terminal) {
      events.push('finish'); assert.equal(value, receipt); assert.equal(terminal, 'returned');
    }};
    const f = await fixture(t, receiver, {wait() {events.push('wait'); return state;}});
    const query = f.client[method]('original', parameters, options);
    parameters.n.original = 99; options.result = 'foreign';
    f.port[sourcePreparationPort] = {};
    receiver.beforeSourceQuery = () => assert.fail('Replacement');
    assert.deepEqual(await query.all(), [{n: 1}]);
    assert.deepEqual(events, ['before', 'snapshot', 'identity', 'request', 'finish', 'wait']);
    assert.equal(getSubmissionInput(query).requestId, query.requestId);
    assert.equal(getSubmissionInput(query).input.text, observed.input.text);
    assert.equal(f.calls.filter(name => name === 'submit-intent').length, 1);
    assert.equal(f.calls.filter(name => name === 'read').length, 1);
  });
}

test('query omission and null parameters reach the original before SDK defaults', async t => {
  const seen = [], original = new Error('OriginalUnavailable');
  const f = await fixture(t, {...source(), beforeSourceQuery(...args) {seen.push(args); throw original;}});
  await assert.rejects(f.client.sql('original'), error => error === original);
  await assert.rejects(f.client.aql('original', null), error => error === original);
  assert.deepEqual(seen.map(args => args.slice(0, 4)), [['sql', 'original', undefined, undefined], ['aql-text', 'original', null, undefined]]);
  assert.equal(seen[0][4], seen[1][4]);
  assert.equal(Object.isFrozen(seen[0][4]), true);
  assert.equal(seen[0][4].mode, 'local');
  assert.deepEqual(f.calls, ['connect']);
});

test('a selected missing or accessor query method refuses without invoking raw inputs', async t => {
  let gets = 0;
  for (const accessor of [false, true]) {
    const receiver = source();
    if (accessor) Object.defineProperty(receiver, 'beforeSourceQuery', {get() {gets++; assert.fail('MethodGetter');}});
    const f = await fixture(t, receiver);
    const raw = Object.defineProperty({}, 'signal', {get() {gets++; assert.fail('RawGetter');}});
    await assert.rejects(f.client.sql('SELECT 1', undefined, raw), {code: 'NodeSourceManagedAdmissionUnavailable'});
    assert.deepEqual(f.calls, ['connect']);
  }
  assert.equal(gets, 0);
});

test('asynchronous query acquisition cannot defer raw capture or produce a replacement receipt', async t => {
  let gets = 0;
  const f = await fixture(t, {...source(), beforeSourceQuery() {return Promise.reject(new Error('OwnedPartial'));}});
  const options = Object.defineProperty({}, 'signal', {get() {gets++; assert.fail('RawGetter');}});
  await assert.rejects(f.client.sql('SELECT 1', undefined, options), {code: 'NodeSourceManagedAdmissionUnavailable'});
  await Promise.resolve(); assert.equal(gets, 0); assert.deepEqual(f.calls, ['connect']);
});

test('capture rejection finishes only its original producer and retains failed cleanup for close', async t => {
  const receipt = {}, finishes = [], originalCleanup = new Error('OriginalAliasPending');
  let ready = false, before = 0;
  const f = await fixture(t, {...source(), beforeSourceQuery() {before++; return receipt;},
    finishSourceProducer(value, terminal) {
      finishes.push([value, terminal]); if (!ready) throw originalCleanup;
    }});
  await assert.rejects(f.client.sql('SELECT 1', undefined, {unknown: true}), {code: 'InvalidQueryOptions'});
  assert.deepEqual(finishes, [[receipt, 'failed']]);
  ready = true; await f.client.close();
  assert.deepEqual(finishes, [[receipt, 'failed'], [receipt, 'failed']]);
  assert.equal(before, 1); assert.deepEqual(f.calls, ['connect']);
});

test('submission uncertainty retains the same query receipt and never resends', async t => {
  const receipt = {}, finishes = [];
  const f = await fixture(t, {...source(), beforeSourceQuery() {return receipt;},
    finishSourceProducer(value, terminal) {finishes.push([value, terminal]);}},
  {'submit-intent'() {throw new Error('OriginalLostReply');}});
  const query = f.client.sql('SELECT 1 AS n');
  await assert.rejects(query.all(), {code: 'SubmissionUnknown'});
  assert.deepEqual(finishes, [[receipt, 'failed']]);
  assert.equal(f.calls.filter(name => name === 'submit-intent').length, 1);
  assert.equal(f.calls.includes('wait'), false); assert.equal(f.calls.includes('read'), false);
});

test('unselected query options keep their existing getter and read behavior', async t => {
  let gets = 0;
  const f = await fixture(t, undefined);
  assert.deepEqual(await f.client.sql('SELECT 1 AS n', undefined,
    {get signal() {gets++; return undefined;}}).all(), [{n: 1}]);
  assert.equal(gets, 1);
  assert.equal(f.calls.filter(name => name === 'submit-intent').length, 1);
});
