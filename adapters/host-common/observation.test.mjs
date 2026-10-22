import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostObservationConnection, installHostObservation,
  observationTraceParent, snapshotObservationContext,
  projectEffectApplication, captureManagedRunObservation} from './observation.mjs';

const trace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
const ref = {namespaceId: 'local', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const turn = () => new Promise(resolve => setImmediate(resolve));

test('managed usage retains one original reader and operation correlation across row consumption', async () => {
  const records = [], charges = [];
  const connection = createHostObservationConnection({deliver: value => records.push(value)});
  const observer = installHostObservation(connection, {journal: {observationStorage: () => ({
    consume(value) {charges.push(value); return {accepted: true};},
  })}});
  const values = [7n, 2n, 3n, 64n, 128n, 256n, 1n, 2n, 3n, 4n, 0n, 0n, 8n, 0n, 0n, 16n];
  let reads = 0, complete;
  await observer.run('read', trace, () => {
    complete = captureManagedRunObservation(observer, ref, () => {reads++; return values;});
    assert.equal(reads, 0, 'No speculative sample before the actual row response finishes');
  });
  complete(); complete(); values.fill(999n);
  await observer.close();
  const usage = records.filter(record => record.event === 'resources_observed');
  assert.equal(reads, 1); assert.equal(usage.length, 1);
  assert.deepEqual(usage[0].parent, trace);
  assert.equal(usage[0].attributes['actql.run.definition_cid'], ref.runDefinitionCid);
  assert.equal(usage[0].attributes['actql.resource.scope'], 'managed-run-ledger');
  assert.equal(usage[0].attributes['actql.resource.limit.retained_bytes'], '128');
  assert.equal(usage[0].attributes['actql.resource.usage.held_bytes'], '8');
  assert.equal(usage[0].attributes['actql.resource.usage.peak_retention'], '16');
  assert(Object.isFrozen(usage[0].attributes));
  assert.equal(charges.length, 1, 'The resource record spends the real existing observation allowance');
  assert(connection.configuration().measurements.available.includes('resources'));
});

test('managed usage refuses foreign readers and missing or retired observations without zero fill', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value)}));
  let foreign = 0;
  assert.equal(captureManagedRunObservation({captureManagedRun() {foreign++;}}, ref, () => []), undefined);
  assert.equal(foreign, 0);
  for (const value of [undefined, Array(16).fill(0), Array(15).fill(0n), Array(16).fill(-1n)]) {
    captureManagedRunObservation(observer, ref, () => value)();
  }
  captureManagedRunObservation(observer, ref, () => {throw new Error('Retired');})();
  assert.equal(observer.status().loss.resourceUnavailable, 5);
  assert.equal(records.length, 0);
  const excluded = installHostObservation(createHostObservationConnection({deliver() {},
    measurements: {exclude: ['resources']}}));
  assert.equal(captureManagedRunObservation(excluded, ref, () => {throw new Error('MustNotRead');}), undefined);
  await excluded.close();
  const afterClose = captureManagedRunObservation(observer, ref, () => {throw new Error('MustNotReadAfterClose');});
  await observer.close(); afterClose();
  assert.equal(records.length, 0);
});

test('internal Effect projection uses the active scope and defers delivery', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}));
  projectEffectApplication({diagnostic() { throw new Error('must not call a foreign hook'); }},
    undefined, {status: 'published'});
  await observer.run('submit', trace, () => {
    projectEffectApplication(observer, undefined,
      {status: 'needs_reconciliation', receipt: 'SECRET_SENTINEL'});
    assert.equal(records.length, 0, 'no processor runs inside completion');
  });
  await observer.close();
  const effects = records.filter(record => record.operation === 'effect');
  assert.equal(effects.length, 1);
  assert.equal(effects[0].attributes['actql.outcome'], 'needs_reconciliation');
  assert.equal(effects[0].durationMs, undefined);
  assert.deepEqual(effects[0].parent, trace);
  assert.equal(JSON.stringify(records).includes('SECRET_SENTINEL'), false);
});

test('metadata projection discards every unapproved value and baggage', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}));
  const sentinel = 'SECRET_SENTINEL';
  await observer.run('check', {...trace, baggage: {password: sentinel}}, async () => {
    observer.emit('check', 'check_completed', {outcome: 'failed',
      query: sentinel, error: sentinel, name: sentinel, resource: sentinel},
    {resources: {arbitrary: sentinel}});
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

test('repeated Owner facts are neither delivered nor reported as observation loss', async () => {
  const records = [], charges = [];
  let key;
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record)}), {journal: {observationStorage: () => ({
      consume(value) {
        charges.push(value);
        if (key === value.ownerFactKey) return {accepted: false, repeated: true};
        key = value.ownerFactKey;
        return {accepted: true};
      },
    })}});
  const facts = {ref, outcome: 'succeeded', revision: 7, cleanupPending: true};
  observer.emit('run', 'owner_observed', facts, {ownerFactKey: 'succeeded;7;1;?'});
  observer.emit('run', 'owner_observed', facts, {ownerFactKey: 'succeeded;7;1;?'});
  observer.emit('run', 'owner_observed', {...facts, cleanupPending: false,
    physicalStop: 'confirmed'}, {ownerFactKey: 'succeeded;7;0;1'});
  await observer.close();
  assert.equal(records.length, 2);
  assert.equal(records[0].attributes['actql.cleanup.pending'], true);
  assert.equal(records[1].attributes['actql.physical_stop'], 'confirmed');
  assert.equal(observer.status().repeated, 1);
  assert.equal(observer.status().dropped, 0);
  assert.deepEqual(charges.map(value => value.ownerFactKey),
    ['succeeded;7;1;?', 'succeeded;7;1;?', 'succeeded;7;0;1']);
  assert.equal(JSON.stringify(records).includes('succeeded;7;'), false,
    'the internal comparison key is not an exported attribute');
});

test('failed optional storage initialization retains retryable close custody', async () => {
  let closes = 0;
  const connection = createHostObservationConnection({deliver() {}});
  const observer = installHostObservation(connection, {
    journal: {observationStorage() { throw new Error('initialization failed'); },
      closeObservationStorage() { if (++closes === 1) throw new Error('close failed'); }},
  });
  assert.equal(await observer.run('check', trace, () => 42), 42);
  await assert.rejects(observer.close(), {message: 'HostObservationCleanupPending'});
  assert.equal(observer.status().budgetUnavailable, 1);
  assert.equal(observer.status().cleanupPending, true);
  assert.throws(() => installHostObservation(connection), /HostObservationConnectionInUse/u);
  await observer.close();
  await observer.close();
  assert.equal(closes, 2);
  assert.equal(observer.status().cleanupPending, false);
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

test('measurement and correlation selections preserve facts while narrowing disclosure', async () => {
  const records = [];
  const connection = createHostObservationConnection({deliver: record => records.push(record),
    measurements: {include: ['duration'], exclude: ['duration']},
    correlation: {include: ['task']}, attributes: {exclude: ['actql.task.ordinal']}});
  const observer = installHostObservation(connection, {journal: {observationStorage: () => ({
    consume: () => ({accepted: true, context: trace}),
  })}, runId: () => 'original-run'});
  await observer.run('check', trace, () => observer.emit('compute', 'task_completed',
    {ref, task: 0, slot: 0, attempt: 1, attemptCid: `sha256:${'c'.repeat(64)}`}, {durationMs: 100}));
  await observer.close();
  assert.deepEqual(connection.configuration().measurements.selected, []);
  assert.deepEqual(connection.configuration().measurements.available, ['duration', 'resources']);
  for (const record of records) {
    if (record.event === 'task_completed') assert.equal(record.durationMs, 100);
    assert.equal(record.parent, undefined);
    assert.equal(record.link, undefined);
    for (const key of ['actql.task.ordinal', 'actql.run.id', 'actql.model.attempt_cid',
      'actql.model.slot.ordinal', 'actql.attempt.ordinal']) assert.equal(record.attributes[key], undefined);
  }
});

test('excluding required metadata suppresses a record instead of emitting a misleading schema', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    attributes: {exclude: ['actql.operation']}, deliver: record => records.push(record)}));
  assert.equal(await observer.run('check', trace, () => 42), 42);
  await observer.close();
  assert.equal(records.length, 0);
  assert.equal(observer.status().loss.requiredAttributeExcluded, 2);
});
