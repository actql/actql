import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostObservationConnection, installHostObservation,
  observationTraceParent, snapshotObservationContext} from './observation.mjs';

const trace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
const ref = {namespaceId: 'local', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const turn = () => new Promise(resolve => setImmediate(resolve));

test('metadata projection discards every unapproved value and baggage', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}));
  const sentinel = 'SECRET_SENTINEL';
  await observer.run('check', {...trace, baggage: {password: sentinel}}, async () => {
    observer.emit('check', 'check_completed', {outcome: 'failed',
      query: sentinel, error: sentinel, name: sentinel, resource: sentinel});
  });
  await observer.close();
  assert.equal(records.length, 3);
  assert.equal(JSON.stringify(records).includes(sentinel), false);
  assert.deepEqual(records[0].parent, trace);
  assert.equal(records[1].attributes['actql.outcome'], 'failed');
  assert.equal(records.some(x => x.attributes['actql.run.id'] !== undefined), false);
});

test('strict context parsing is correlation only and retains no baggage', () => {
  assert.deepEqual(observationTraceParent({traceparent:
    `00-${trace.traceId}-${trace.spanId}-01`, baggage: 'secret'}), trace);
  for (const value of [undefined, 'invalid', `00-${'0'.repeat(32)}-${trace.spanId}-01`,
    `ff-${trace.traceId}-${trace.spanId}-01`]) {
    assert.equal(observationTraceParent({traceparent: value}), undefined);
  }
  assert.deepEqual(snapshotObservationContext({...trace, traceFlags: 255,
    tracestate: 'secret'}), trace);
});

test('unavailable Run budget stops new observations without changing execution', async () => {
  let called = 0;
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}), {journal: {
    observationStorage() { throw new Error('failed disk'); },
  }});
  await observer.run('submit', trace, async () => {
    observer.accepted({inserted: true, ref}, 'request');
    observer.emit('run', 'owner_observed', {ref, outcome: 'running'});
    called++;
    return 'executed';
  });
  await observer.close();
  assert.equal(called, 1);
  assert.equal(records.length, 1);
  assert.equal(observer.status().budgetUnavailable, 2);
});

test('failed optional storage initialization retains retryable close custody', async () => {
  let closes = 0;
  const observer = installHostObservation(createHostObservationConnection({deliver() {}}), {
    journal: {observationStorage() { throw new Error('initialization failed'); },
      closeObservationStorage() { if (++closes === 1) throw new Error('close failed'); }},
  });
  assert.equal(await observer.run('check', trace, () => 42), 42);
  await observer.close();
  assert.equal(observer.status().budgetUnavailable, 1);
  await observer.close();
  assert.equal(closes, 2);
});

test('queue overflow and delivery failure cannot replace an operation result', async () => {
  let release;
  const blocked = new Promise(resolve => { release = resolve; });
  const observer = installHostObservation(createHostObservationConnection({
    limits: {queueRecords: 1, shutdownMs: 20},
    deliver: async () => { await blocked; throw new Error('export failed'); },
  }));
  observer.emit('compute', 'task_started');
  await turn();
  assert.equal(observer.status().active, 1);
  observer.emit('compute', 'task_completed');
  observer.emit('cleanup', 'cleanup_completed');
  assert.equal(observer.status().queueOverflow, 1);
  const cause = new Error('original execution cause');
  await assert.rejects(observer.run('submit', trace, () => { throw cause; }),
    error => error === cause);
  await observer.close();
  assert.equal(observer.status().active, 1);
  release();
  await turn();
  assert.equal(observer.status().deliveryFailed, 1);
  assert.equal(observer.status().active, 0);
});

test('disabled signals neither open telemetry storage nor call delivery', async () => {
  let calls = 0;
  const observer = installHostObservation(createHostObservationConnection({
    include: [], deliver: () => { calls++; },
    currentContext: () => { throw new Error('must not be called'); },
  }), {journal: {observationStorage() { throw new Error('must not be read'); }}});
  assert.equal(await observer.run('check', trace, () => 42), 42);
  await observer.close();
  assert.equal(calls, 0);
  assert.equal(observer.status().dropped, 0);
});

test('context getters are copied once and cannot inject a later value', () => {
  let reads = 0;
  assert.deepEqual(snapshotObservationContext({...trace,
    get traceId() { return ++reads === 1 ? trace.traceId : 'SECRET_SENTINEL'; },
  }), trace);
  assert.equal(reads, 1);
  assert.equal(snapshotObservationContext({get traceId() { throw new Error('secret'); }}), undefined);
});

test('timed-out delivery keeps its connection owned until physical settlement', async () => {
  let release;
  const connection = createHostObservationConnection({limits: {shutdownMs: 10},
    deliver: () => new Promise(resolve => { release = resolve; })});
  const observer = installHostObservation(connection);
  observer.emit('compute', 'task_started');
  await turn();
  await observer.close();
  assert.throws(() => installHostObservation(connection), /HostObservationConnectionInUse/u);
  release();
  await turn();
  await installHostObservation(connection).close();
});

test('recovery links saved context, never reopens its caller span', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}), {journal: {observationStorage: () => ({
    consume: () => ({accepted: true, context: trace}),
  })}});
  observer.emit('recovery', 'resume_claimed', {ref});
  await observer.close();
  assert.equal(records[0].parent, undefined);
  assert.deepEqual(records[0].link, trace);
});

test('unknown configuration and increased budgets are rejected at installation', () => {
  for (const options of [{transport: 'grpc'}, {limits: {runRecords: 99999}},
    {include: ['unknown']}, {include: ['run', 'run']}, {limits: null}]) {
    assert.throws(() => createHostObservationConnection({deliver() {}, ...options}), TypeError);
  }
});

test('disabling correlation removes saved links, caller context and Run identity', async () => {
  const records = [];
  let initialized;
  const observer = installHostObservation(createHostObservationConnection({
    correlation: false, deliver: record => records.push(record)}), {
    runId: () => 'owner-run', journal: {observationStorage: () => ({
      initialize: value => { initialized = value; },
      consume: () => ({accepted: true, context: trace}),
    })}});
  await observer.run('submit', trace, () => {
    observer.accepted({inserted: true, ref}, 'request');
    observer.emit('run', 'owner_observed', {ref});
  });
  await observer.close();
  assert.equal(initialized.context, undefined);
  for (const record of records) {
    assert.equal(record.parent, undefined);
    assert.equal(record.link, undefined);
    assert.equal(record.attributes['actql.run.id'], undefined);
    assert.equal(record.attributes['actql.run.definition_cid'], undefined);
  }
});

test('unknown event content never enters the queue', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: record => records.push(record)}));
  observer.emit('run', 'SECRET_SENTINEL');
  await observer.close();
  assert.equal(records.length, 0);
  assert.equal(observer.status().limited, 1);
});
