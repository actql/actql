import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const names = ['published', 'consumed_a', 'consumed_b'];
// Stay inside the installed 10,000-byte record ceiling. Both unused values
// belong to the record; their combined wire walk crosses a Host quantum.
const payload = 'p'.repeat(8193);
const unused = Array.from({length: 129}, () => 1);
const baseRow = {event_id: 1, occurred_at: 12, payload, zz_unused: unused};
const cases = {
  watermark: {step: {watermark_events: {watermark_ms: 10, policy: 'mark'}},
    row: {...baseRow, watermark_ms: 10, late: false, watermark_decision: 'keep'}},
  window: {step: {window_events: {kind: 'fixed', size: 10}},
    row: {...baseRow, window_start_ms: 10, window_end_ms: 20}},
  dedupe: {step: {dedupe_events: {by: ['event_id'],
    order_by: [{field: 'occurred_at', dir: 'asc', nulls: 'last'}]}}, row: baseRow},
  session: {step: {session: {by: ['event_id'], gap: 10}},
    row: {...baseRow, session_start_ms: 12, session_end_ms: 22,
      session_id: 'session:12:v:1:1:v:1:1'}},
};

function program(id, kind) {
  const schema = {event_id: {type: 'number', nullable: false},
    occurred_at: {type: 'number', nullable: false},
    payload: {type: 'string', nullable: false},
    zz_unused: {type: 'array', nullable: false, max_items: 129,
      items: {type: 'number', nullable: false}}};
  const fields = Object.keys(cases[kind].row);
  return {version: 'actql/0.1', id, stages: [
    {id: 'values', inputs: {}, steps: [{values: {schema, rows: [baseRow]}, as: 'out'}],
      results: {r: {from: 'out', fields: Object.keys(schema)}}},
    {id: 'bridge', inputs: {rows: {result: {stage: 'values', result: 'r'}}}, steps: [
      {to_events: {id: 'event_id', time: 'occurred_at'}, as: 'source'},
      {from: 'source', ...cases[kind].step, as: 'computed'},
      {from: 'computed', events: true, as: 'out'},
    ], results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(id => ({id,
      inputs: {rows: {result: {stage: 'bridge', result: 'r'}}},
      steps: [{select: fields, as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'bridge', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

async function runEventsRecordBoundary(t, kind) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-events-record-'));
  const barrier = Promise.withResolvers();
  const released = Promise.withResolvers();
  let client;
  t.after(async () => {
    released.resolve();
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  let cancelling = false;
  let prefixComplete = false;
  let dispatches = 0;
  let advances = 0;
  let completions = 0;
  let representations;
  const trace = [];
  const diagnostics = [];
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'events-record',
      entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}],
    }),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    async faultInjection(step, detail) {
      if (step === 'dispatch_reserved') dispatches++;
      if (step !== 'local_compute_advanced') return;
      advances++;
      if (!cancelling) trace.push({...detail});
      if (!cancelling || detail.task !== 1) return;
      trace.push({...detail});
      if (!prefixComplete) {
        assert.equal(detail.work, '5');
        assert.equal(detail.progress, '1');
        prefixComplete = true;
        return;
      }
      // The four-field bridge has completed. Text emission takes 130 polls,
      // and the Array takes 260. Poll 256 is inside record value emission,
      // before commit; no fixed sleep determines the cancellation boundary.
      assert.equal(detail.work, '256');
      assert.equal(detail.progress, '0');
      barrier.resolve();
      await released.promise;
    },
    observe(step, detail) {
      if (step === 'dispatch_failed') diagnostics.push(detail);
      if (step !== 'computed') return;
      completions++;
      representations = detail.outputRepresentations;
      if (cancelling) throw new Error('unfinished Events record was published');
    },
  };
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, retainedRelationOutput: true, authorization}});
  const fixtureId = `public-events-record-${kind}`;
  const source = JSON.stringify(program(fixtureId, kind));
  const options = {format: 'json', requestId: fixtureId};
  const execution = await client.aql(source, options).catch(cause => {
    assert.fail(inspect(cause, {depth: 8}));
  });
  const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
  assert.equal(state.status, 'succeeded', inspect({state, diagnostics, trace}, {depth: 6}));
  trace.length = 0;
  assert.deepEqual(Object.keys(state.result_availability).sort(), [...names].sort());
  for (const name of names) {
    assert.deepEqual(await execution.result(name).all(), [cases[kind].row]);
  }
  assert.equal(completions, 1);
  assert.ok(representations?.some(item => item.representation === 'retained-file'));
  const completedAdvances = advances;
  const repeated = await client.aql(source, options);
  assert.deepEqual(repeated.ref, execution.ref);
  assert.deepEqual(await repeated.result('published').all(), [cases[kind].row]);
  assert.equal(advances, completedAdvances);
  assert.equal(dispatches, 1);
  assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

  cancelling = true;
  const cancel = await client.aql(JSON.stringify(program(fixtureId + '-cancel', kind)),
    {format: 'json', requestId: fixtureId + '-cancel'});
  await Promise.race([barrier.promise,
    cancel.wait({signal: AbortSignal.timeout(10_000)}).then(state => {
      throw new Error(`Events emission missed barrier: ${inspect({state, trace}, {depth: 6})}`);
    })]);
  const atBarrier = advances;
  const retained = await readdir(join(directory, 'carrier-snapshots'));
  try {
    await cancel.cancel();
    const pending = await cancel.status();
    assert.equal(pending.control.cancellation_requested, true);
    assert.notEqual(pending.control.physical_stop, 'confirmed');
    assert.notEqual(pending.status, 'cancelled');
    assert.equal(completions, 1);
    assert.equal(advances, atBarrier);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), retained);
  } finally { released.resolve(); }
  const stopped = await cancel.wait({signal: AbortSignal.timeout(10_000)});
  assert.equal(stopped.status, 'cancelled', inspect(stopped, {depth: 6}));
  assert.equal(stopped.control.physical_stop, 'confirmed');
  for (const name of names) {
    assert.equal(stopped.result_availability[name].state, 'unavailable');
    await assert.rejects(cancel.result(name).all());
  }
  assert.equal(completions, 1);
  assert.equal(advances, atBarrier);
  assert.equal(dispatches, 2);
  assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
}

test('public retained watermark publishes and cancels inside record emission',
  {timeout: 45_000}, t => runEventsRecordBoundary(t, 'watermark'));
test('public retained window publishes and cancels inside record emission',
  {timeout: 45_000}, t => runEventsRecordBoundary(t, 'window'));
test('public retained dedupe publishes and cancels inside record emission',
  {timeout: 45_000}, t => runEventsRecordBoundary(t, 'dedupe'));
test('public retained session publishes and cancels inside record emission',
  {timeout: 45_000}, t => runEventsRecordBoundary(t, 'session'));
