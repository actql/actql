import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostObservationConnection, installHostObservation,
  observationTraceParent, snapshotObservationContext,
  projectEffectApplication, captureManagedRunObservation} from './observation.mjs';

const trace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
const ref = {namespaceId: 'local', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const turn = () => new Promise(resolve => setImmediate(resolve));

const selectedRows = (extra = {}) => ({ref, rowOwner: 'request-journal', selection: 'run-definition',
  rowKind: 'run', returnedRows: 1, unrelatedRows: 0, coverage: 'selected-returned', ...extra});

test('Run identity lookup contributes its actual row before the final selected-row record closes', async () => {
  const records = []; let lookups = 0, observer;
  observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), include: ['run'],
    measurements: {include: ['rows']}, events: {level: 'diagnostic'},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    runId(original) {
      assert.deepEqual(original, ref); lookups++;
      // Explicit original-port fixture: the Host's real resolver performs a
      // selected Journal lookup before deriving this immutable identifier.
      observer.diagnostic('selected_rows_observed', selectedRows());
      return 'original-run';
    }});
  await observer.run('read', trace, () => observer.diagnostic('selected_rows_observed', selectedRows()));
  await observer.close();
  const rows = records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(rows.length, 1); assert.equal(rows[0].attributes['actql.rows.returned'], 2);
  assert.equal(rows[0].attributes['actql.run.id'], 'original-run');
  assert.deepEqual(rows[0].parent, trace); assert.equal(lookups, 1);
  assert.deepEqual(observer.status().loss, {});
});

test('positive Run identity is reused only inside the same original operation and exact Run tuple', async () => {
  const records = [], calls = [], foreignScope = {...ref, authorityScopeCid: `sha256:${'c'.repeat(64)}`};
  const observer = installHostObservation(createHostObservationConnection({deliver: record => records.push(record)}), {
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    runId(original) {calls.push({...original}); return original.authorityScopeCid === ref.authorityScopeCid ? 'first-run' : 'other-run';},
  });
  await observer.run('submit', trace, () => {
    observer.emit('run', 'dispatch_reserved', {ref});
    observer.emit('run', 'physical_start_reserved', {ref: {...ref}});
    observer.emit('run', 'dispatch_reserved', {ref: foreignScope});
    observer.emit('run', 'owner_observed', {ref});
  });
  assert.deepEqual(calls, [ref, foreignScope]);
  await observer.run('read', trace, () => observer.emit('run', 'owner_observed', {ref}));
  assert.deepEqual(calls, [ref, foreignScope, ref], 'A new operation resolves its own original metadata');
  await observer.close();
  const other = records.find(record => record.attributes['actql.run.definition_cid'] === foreignScope.runDefinitionCid &&
    record.attributes['actql.run.id'] === 'other-run');
  assert(other); assert.equal(observer.status().dropped, 0);
});

test('missing Run identity is not retained as a positive original and disabled correlation performs no lookup', async () => {
  const records = [], failure = new Error('OriginalRunLookupFailed'); let available = false, calls = 0;
  const observer = installHostObservation(createHostObservationConnection({deliver: record => records.push(record)}), {
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    runId() {calls++; if (!available) return undefined; return 'now-original';},
  });
  await observer.run('submit', trace, () => {
    observer.emit('run', 'dispatch_reserved', {ref}); available = true;
    observer.emit('run', 'physical_start_reserved', {ref});
    observer.emit('run', 'owner_observed', {ref});
  });
  await observer.close(); assert.equal(calls, 2);
  assert.equal(records.find(record => record.event === 'dispatch_reserved').attributes['actql.run.id'], undefined);
  assert.equal(records.find(record => record.event === 'physical_start_reserved').attributes['actql.run.id'], 'now-original');
  const disabled = installHostObservation(createHostObservationConnection({deliver() {}, correlation: false}), {
    runId() {throw failure;}, journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
  });
  assert.equal(await disabled.run('read', trace, () => {disabled.emit('run', 'owner_observed', {ref}); return 7;}), 7);
  await disabled.close(); assert.equal(disabled.status().dropped, 0);
});

test('failed Run identity lookup preserves execution and never becomes a successful retained fact', async () => {
  const records = [], failure = new Error('OriginalRunLookupFailed'), answer = {};
  let calls = 0, failing = true;
  const observer = installHostObservation(createHostObservationConnection({deliver: record => records.push(record)}), {
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    runId() {calls++; if (failing) throw failure; return 'original-after-observation';},
  });
  assert.strictEqual(await observer.run('read', trace, () => {
    observer.emit('run', 'dispatch_reserved', {ref}); failing = false;
    observer.emit('run', 'physical_start_reserved', {ref});
    observer.emit('run', 'owner_observed', {ref}); return answer;
  }), answer);
  await observer.close();
  assert.equal(calls, 2); assert.equal(observer.status().budgetUnavailable, 1);
  assert.equal(records.some(record => record.event === 'dispatch_reserved'), false);
  assert.equal(records.find(record => record.event === 'physical_start_reserved').attributes['actql.run.id'], 'original-after-observation');
});

test('foreign Run identity projections do not borrow the current installation context', async () => {
  const firstRecords = [], otherRecords = []; let firstCalls = 0, otherCalls = 0;
  const first = installHostObservation(createHostObservationConnection({deliver: r => firstRecords.push(r),
    include: ['run'], measurements: {include: ['rows']}, events: {level: 'diagnostic'}}), {
    runId() {firstCalls++; return 'first-original';},
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
  });
  const other = installHostObservation(createHostObservationConnection({deliver: r => otherRecords.push(r),
    include: ['run'], measurements: {include: ['rows']}, events: {level: 'diagnostic'}}), {
    runId() {otherCalls++; return 'other-original';},
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
  });
  await first.run('read', trace, () => {
    first.emit('run', 'owner_observed', {ref});
    other.diagnostic('selected_rows_observed', selectedRows());
    other.emit('run', 'owner_observed', {ref});
  });
  await first.close(); await other.close();
  assert.equal(firstCalls, 1); assert.equal(otherCalls, 1);
  assert.equal(firstRecords.some(record => record.event === 'selected_rows_observed'), false);
  assert.equal(otherRecords[0].parent, undefined);
  assert.equal(otherRecords[0].attributes['actql.run.id'], 'other-original');
  assert.equal(other.status().loss.rowsUnavailable, 1);
});

test('Run identity lookup is unnecessary for excluded or already limited observation records', async () => {
  for (const options of [{attributes: {exclude: ['actql.event']}}, {limits: {requestRecords: 1}}]) {
    let calls = 0;
    const observer = installHostObservation(createHostObservationConnection({deliver() {}, ...options}), {
      runId() {calls++; return 'must-not-be-needed';},
      journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    });
    assert.equal(await observer.run('read', trace, () => {observer.emit('run', 'owner_observed', {ref}); return 7;}), 7);
    await observer.close(); assert.equal(calls, 0);
  }
});

test('selected-row Run identity snapshots cannot be transferred to another installation projection', async () => {
  const firstRecords = [], otherRecords = [];
  const options = deliver => ({deliver, include: ['run'], measurements: {include: ['rows']}, events: {level: 'diagnostic'}});
  const journal = {observationStorage: () => ({consume: () => ({accepted: true})})};
  const first = installHostObservation(createHostObservationConnection(options(r => firstRecords.push(r))), {
    journal, runId: () => 'first-original',
  });
  await first.run('read', trace, () => first.diagnostic('selected_rows_observed', selectedRows()));
  await first.close();
  const snapshot = firstRecords.find(record => record.event === 'selected_rows_observed').attributes;
  const other = installHostObservation(createHostObservationConnection(options(r => otherRecords.push(r))), {
    journal, runId: () => 'other-original',
  });
  other.emit('run', 'selected_rows_observed', {ref}, {selectedRows: snapshot});
  await other.close();
  assert.equal(otherRecords.length, 0); assert.equal(other.status().loss.rowsUnavailable, 1);
});

test('selected-row Run identity remains absent for unbound references without losing actual row counts', async () => {
  const records = []; let lookups = 0;
  const observer = installHostObservation(createHostObservationConnection({deliver: r => records.push(r),
    include: ['run'], measurements: {include: ['rows']}, events: {level: 'diagnostic'}}), {
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})},
    runId() {lookups++; throw new Error('NoOriginalRun');},
  });
  for (const unbound of [undefined, null]) await observer.run('read', trace, () => {
    observer.diagnostic('selected_rows_observed', selectedRows({ref: unbound}));
  });
  await observer.close();
  const rows = records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(rows.length, 2); assert.equal(lookups, 0); assert.deepEqual(observer.status().loss, {});
  for (const row of rows) {
    assert.equal(row.attributes['actql.rows.returned'], 1);
    assert.equal(Object.hasOwn(row.attributes, 'actql.run.definition_cid'), false);
    assert.equal(Object.hasOwn(row.attributes, 'actql.run.id'), false);
  }
});

test('retained original work settles without delaying ingress or creating a second observation context', async () => {
  const records = [], observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), include: ['run'], measurements: {include: ['rows']}, events: {level: 'diagnostic'},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  let release, child;
  const gate = new Promise(resolve => {release = resolve;}), result = {};
  assert.strictEqual(await observer.run('submit', trace, () => {
    observer.diagnostic('selected_rows_observed', selectedRows());
    child = gate.then(async () => {await turn(); observer.diagnostic('selected_rows_observed', selectedRows());});
    assert.equal(observer.retainOperation(child), undefined);
    observer.retainOperation(child);
    return result;
  }), result);
  assert.equal(observer.status().activeSegments, 1);
  assert.equal(records.filter(r => r.event === 'selected_rows_observed').length, 0);
  release(); await child; await turn();
  assert.equal(observer.status().activeSegments, 0);
  await observer.close();
  const selected = records.filter(r => r.event === 'selected_rows_observed');
  assert.equal(selected.length, 1); assert.equal(selected[0].attributes['actql.rows.returned'], 2);
  assert.deepEqual(selected[0].parent, trace); assert.deepEqual(observer.status().loss, {});
  assert.equal(records.filter(r => r.event === 'segment_started').length, 1);
});

test('retained rejection preserves the original failure and thenables cannot become operation originals', async () => {
  const observer = installHostObservation(createHostObservationConnection({deliver() {}, events: {level: 'diagnostic'}}));
  const marker = new Error('OriginalWork'); let reject, child, thenReads = 0;
  await observer.run('submit', trace, () => {
    child = new Promise((_, fail) => {reject = fail;}); observer.retainOperation(child);
    observer.retainOperation({get then() {thenReads++; throw new Error('UnownedThen');}});
  });
  assert.equal(thenReads, 0); assert.equal(observer.status().activeSegments, 1);
  reject(marker); await assert.rejects(child, error => error === marker); await turn();
  assert.equal(observer.status().activeSegments, 0); assert.equal(observer.status().loss.rowsUnavailable, 1);
  await observer.close();
});

test('a captured continuation uses the original context once and respects existing lifetime bounds', async () => {
  const records = [], observer = installHostObservation(createHostObservationConnection({
    deliver: value => records.push(value), include: ['run'], measurements: {include: ['rows']},
    events: {level: 'diagnostic'}, limits: {activeSegments: 1},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  let capture;
  await observer.run('read', trace, () => {capture = observer.captureCurrentOperation();});
  let unobservedWork = 0;
  await observer.run('read', trace, () => {unobservedWork++;});
  assert.equal(unobservedWork, 1); assert.equal(observer.status().limited, 1);
  await capture.run(async () => {await turn(); observer.diagnostic('selected_rows_observed', selectedRows());});
  capture.release(); capture.release();
  assert.equal(observer.status().activeSegments, 0);
  await observer.close();
  assert.equal(records.filter(r => r.event === 'selected_rows_observed').length, 1);
  assert.equal(observer.captureCurrentOperation(), undefined);
});

test('observation close detaches its bounded metadata without settling original unfinished work', async () => {
  const observer = installHostObservation(createHostObservationConnection({deliver() {}, events: {level: 'diagnostic'}}));
  const other = installHostObservation(createHostObservationConnection({deliver() {}, events: {level: 'diagnostic'}}));
  let finish, settled = false, child;
  await observer.run('submit', trace, () => {
    child = new Promise(resolve => {finish = resolve;});
    assert.equal(other.captureCurrentOperation(), undefined);
    other.retainOperation(child); observer.retainOperation(child);
    child.then(() => {settled = true;});
  });
  await observer.close(); assert.equal(settled, false);
  assert.equal(observer.status().activeSegments, 0); assert.equal(observer.status().loss.rowsUnavailable, 1);
  assert.equal(other.status().activeSegments, 0);
  finish(); await child; await turn(); assert.equal(settled, true); assert.equal(observer.status().activeSegments, 0);
  await other.close();
});

test('no-row observation close preserves the pending ingress count until its original settlement', async () => {
  const connection = createHostObservationConnection({deliver() {}, include: ['run'], measurements: {include: ['duration']}});
  const observer = installHostObservation(connection), answer = {};
  let release;
  const gate = new Promise(resolve => {release = resolve;});
  const original = observer.run('read', trace, () => gate.then(() => answer));
  try {
    assert.equal(observer.status().activeSegments, 1);
    await observer.close();
    release(); assert.strictEqual(await original, answer);
    assert.equal(observer.status().activeSegments, 0);
    const reopened = installHostObservation(connection);
    await reopened.close(); assert.equal(reopened.status().activeSegments, 0);
  } finally {release(); await original;}
});

test('selected row diagnostics copy only actual reader scalars and the original operation context', async () => {
  const records = [], charges = [];
  const connection = createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}, measurements: {include: ['rows']}, include: ['run']});
  const observer = installHostObservation(connection, {journal: {observationStorage: () => ({
    consume(value) {charges.push(value); return {accepted: true};},
  })}});
  const facts = selectedRows({payload: 'SECRET_ROW', statement: 'SECRET_QUERY'});
  await observer.run('read', trace, () => {
    observer.diagnostic('selected_rows_observed', facts);
    observer.diagnostic('selected_rows_observed', selectedRows());
    assert.equal(charges.length, 0, 'Reader hooks do not consume a durable observation budget per native get');
    facts.returnedRows = 999;
  });
  await observer.close();
  const selected = records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(selected.length, 1); assert.deepEqual(selected[0].parent, trace);
  assert.equal(selected[0].attributes['actql.run.definition_cid'], ref.runDefinitionCid);
  assert.equal(selected[0].attributes['actql.rows.returned'], 2);
  assert.equal(selected[0].attributes['actql.rows.unrelated'], 0);
  assert.equal(selected[0].attributes['actql.rows.coverage'], 'selected-returned');
  assert.equal(JSON.stringify(records).includes('SECRET_'), false);
  assert(Object.isFrozen(selected[0].attributes));
  assert.equal(charges.filter(charge => charge.ref === ref).length, 2,
    'One aggregate record and the ending segment use the existing Run budget, not each native get');
  assert(connection.configuration().measurements.available.includes('rows'));
});

test('selected row diagnostics stay disabled before reading facts unless explicitly selected', async () => {
  for (const options of [{}, {events: {level: 'diagnostic'}, include: ['compute']},
    {events: {level: 'diagnostic'}, measurements: {exclude: ['rows']}}]) {
    let reads = 0;
    const observer = installHostObservation(createHostObservationConnection({deliver() {}, ...options}));
    observer.diagnostic('selected_rows_observed', {get rowOwner() {reads++; throw new Error('MustNotRead');}});
    await observer.close();
    assert.equal(reads, 0); assert.deepEqual(observer.status().loss, {});
  }
});

test('selected row diagnostics preserve missing and invalid coverage instead of inventing zero counts', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}, measurements: {include: ['rows']}}));
  await observer.run('read', trace, () => {
    for (const facts of [undefined, selectedRows({coverage: undefined}), selectedRows({rowOwner: 'unknown-owner'}),
      selectedRows({selection: 'all-history'}), selectedRows({rowKind: 'effect'}), selectedRows({returnedRows: -1}),
      selectedRows({unrelatedRows: 2}), selectedRows({returnedRows: 1.5}),
      {get rowOwner() {throw new Error('Unavailable');}}]) observer.diagnostic('selected_rows_observed', facts);
  });
  assert.equal(observer.status().loss.rowsUnavailable, 9);
  await observer.close(); assert.equal(records.filter(record => record.event === 'selected_rows_observed').length, 0);
});

test('selected row diagnostics keep unknown classification and pre-Run binding absent in a mixed aggregate', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}, measurements: {include: ['rows']}}),
    {journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  await observer.run('read', trace, () => {
    observer.accepted({ref, inserted: false});
    observer.diagnostic('selected_rows_observed', selectedRows());
    observer.diagnostic('selected_rows_observed', selectedRows({ref: undefined, selection: 'request',
      returnedRows: 0, unrelatedRows: undefined}));
  });
  await observer.close();
  const selected = records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(selected.length, 1);
  assert.equal(selected[0].attributes['actql.rows.returned'], 1);
  assert.equal(selected[0].attributes['actql.rows.selection'], 'mixed-selected');
  assert.equal(Object.hasOwn(selected[0].attributes, 'actql.rows.unrelated'), false);
  assert.equal(Object.hasOwn(selected[0].attributes, 'actql.run.definition_cid'), false,
    'A later admitted Run in the context cannot substitute the missing earlier binding');
});

test('selected row diagnostics refuse contextless or late facts instead of creating another operation frame', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}, measurements: {include: ['rows']}}));
  observer.diagnostic('selected_rows_observed', selectedRows());
  let release, late;
  const pending = new Promise(resolve => {release = resolve;});
  await observer.run('read', trace, () => {
    late = pending.then(() => observer.diagnostic('selected_rows_observed', selectedRows()));
  });
  release(); await late; await observer.close();
  assert.equal(observer.status().loss.rowsUnavailable, 2);
  assert.equal(records.filter(record => record.event === 'selected_rows_observed').length, 0);
});

test('selected row diagnostics cannot be forged through generic event attributes', async () => {
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}}));
  observer.emit('run', 'selected_rows_observed', {ref}, {selectedRows: {'actql.rows.returned': 0}});
  assert.equal(observer.status().loss.rowsUnavailable, 1);
  await observer.close(); assert.equal(records.length, 0);
});

test('selected row diagnostics cannot replace the original result when optional custody refuses', async () => {
  const records = [], result = {};
  const observer = installHostObservation(createHostObservationConnection({deliver: value => records.push(value),
    events: {level: 'diagnostic'}}), {journal: {observationStorage: () => ({consume() {throw new Error('Unavailable');}})}});
  const actual = await observer.run('read', trace, () => {
    observer.diagnostic('selected_rows_observed', selectedRows()); return result;
  });
  assert.strictEqual(actual, result); assert(observer.status().budgetUnavailable > 0);
  await observer.close();
  assert.equal(records.filter(record => record.event === 'selected_rows_observed').length, 0);
});

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

test('application callback state changes at actual delivery entry and thrown settlement only', async () => {
  let observer, active;
  observer = installHostObservation(createHostObservationConnection({deliver() {
    active = observer.applicationCallbackState();
    assert.equal(active.active, true);
    throw new Error('original callback rejection');
  }}));
  try {
    const idle = observer.applicationCallbackState();
    assert(Object.isFrozen(idle));
    observer.emit('compute', 'task_started');
    assert.equal(observer.applicationCallbackState(), idle, 'enqueueing is not application reentry');
    await turn();
    const settled = observer.applicationCallbackState();
    assert.equal(settled.active, false);
    assert(Object.isFrozen(active));
    assert.notEqual(settled, active);
    assert.notEqual(settled, idle);
    assert.equal(observer.status().deliveryFailed, 1);
    await Promise.resolve();
    assert.equal(observer.applicationCallbackState(), settled, 'internal reads and awaits keep this identity');
  } finally {await observer.close();}
});

test('observation shutdown cannot mark an unsettled application callback idle', async () => {
  let release;
  const callback = new Promise(resolve => {release = resolve;});
  const observer = installHostObservation(createHostObservationConnection({
    limits: {shutdownMs: 10}, deliver: () => callback,
  }));
  try {
    observer.emit('compute', 'task_started');
    await turn();
    const active = observer.applicationCallbackState();
    assert.equal(active.active, true);
    await observer.close();
    assert.equal(observer.applicationCallbackState(), active, 'timeout is not callback settlement');
    release();
    await turn();
    assert.equal(observer.applicationCallbackState().active, false);
    assert.notEqual(observer.applicationCallbackState(), active);
  } finally {release(); await observer.close();}
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
  assert.deepEqual(connection.configuration().measurements.available, ['duration', 'resources', 'rows']);
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
