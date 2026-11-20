import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './index.mjs';
import {validClientBody, validRunWaitContract} from '@actql/client-wire';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId:'wait-original', authorityScopeCid:cid('a'), runDefinitionCid:cid('b')};
const profile = {version:'actql-client-host/0.1', mode:'local', owner:'local', durability:'durable',
  scopeRef:'wait-principal', capabilities:[], limits:{maxReadWireBytes:4096, maxRowWireBytes:1024,
    maxRowRetainedValueBytes:1024, maxRetainedValueBytes:4096, maxRows:10, maxBatchRows:3,
    maxBatchRetainedValueBytes:1024}};
const state = (revision, status = 'succeeded') => ({version:'actql-run-state/0.1',
  run_id:'original-wait-run', revision, status, updated_at:'2026-10-16T00:00:00.000Z',
  next_action:{kind:'none'}, result_available:false, result_availability:{},
  control:{revision:99, cancellation_requested:false, physical_stop:'unknown'}});

async function fixture(t, answer) {
  const calls = [];
  const client = await connectInProcess({mode:'local', owner:'local'}, {perform(operation, body) {
    calls.push({operation, body});
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref, durability:'durable', revision:1};
    if (operation === 'close') return;
    return answer(operation, body);
  }});
  t.after(() => client.close());
  return {run:await client.attach(ref), calls};
}

test('wait wire requires an explicit nullable safe state revision, not control revision', async t => {
  const {run, calls} = await fixture(t, () => state(7));
  assert.equal((await run.wait({since:6})).revision, 7);
  assert.equal((await run.wait()).revision, 7);
  assert.deepEqual(calls.filter(call => call.operation === 'wait').map(call => call.body.since), [6,null]);
  const body = calls.find(call => call.operation === 'wait').body;
  assert.equal(validClientBody('wait', body), true);
  const {since, ...missing} = body;
  assert.equal(validClientBody('wait', missing), false);
  for (const bad of [-1, 1.5, 9007199254740992, '6', true, NaN, Infinity]) {
    assert.equal(validClientBody('wait', {...body, since:bad}), false);
    await assert.rejects(run.wait({since:bad}), {code:'InvalidWaitRevision'});
  }
  assert.equal(calls.filter(call => call.operation === 'wait').length, 2);
});

test('wait rejects equal older or unstable replies and missing state revision', async t => {
  let response = state(7);
  const {run} = await fixture(t, () => response);
  for (const reply of [state(6), state(5), state(7,'running'), (() => {
    const result = state(7); delete result.revision; return result;
  })()]) {
    response = reply;
    await assert.rejects(run.wait({since:6}), {code:'InvalidHostRunState'});
  }
  response = state(7);
  assert.equal((await run.wait({since:6})).revision, 7);
});

test('attached observations reject a different Run and delayed older state despite newer control', async t => {
  let response = state(7);
  const {run} = await fixture(t, () => response);
  await run.status();
  response = {...state(8), run_id:'foreign-run'};
  await assert.rejects(run.status(), {code:'InvalidHostRunState'});
  response = {...state(6), control:{...state(6).control, revision:100}};
  await assert.rejects(run.status(), {code:'InvalidHostRunState'});
  response = state(8);
  assert.equal((await run.wait({since:7})).revision, 8);
});

test('wait timeout and cancellation do not dispatch a Run control operation', async t => {
  const {run, calls} = await fixture(t, () => state(7));
  const timeout = new AbortController();
  timeout.abort(new DOMException('deadline', 'TimeoutError'));
  await assert.rejects(run.wait({since:7, signal:timeout.signal}), {code:'WaitTimeout'});
  const abort = new AbortController(); abort.abort();
  await assert.rejects(run.wait({since:7, signal:abort.signal}), {code:'WaitAborted'});
  assert.deepEqual(calls.map(call => call.operation), ['connect','attach']);
});

test('generated wait correlation preserves checkpoint and Unknown waiting observations', () => {
  const checkpoint = {...state(8, 'waiting_checkpoint'), checkpoint:{checkpoint_id:'checkpoint',
    checkpoint_cid:cid('c'), kind:'run_scope'},
  next_action:{kind:'resolve_checkpoint', checkpoint_id:'checkpoint'}};
  const unknown = {...state(8, 'needs_reconciliation'),
    next_action:{kind:'reconcile_run', reason:'execution_unknown'}};
  for (const original of [checkpoint, unknown, state(8,'failed'), state(8,'cancelled')]) {
    assert.equal(validRunWaitContract(original, 7), true);
    assert.equal(validRunWaitContract(original, 8), false);
    assert.equal(validRunWaitContract(original, null), true);
  }
});
