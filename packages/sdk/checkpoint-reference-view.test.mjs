import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './index.mjs';
import {validRunState} from '@actql/client-wire';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'checkpoint-view', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'original-view', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const state = () => ({version: 'actql-run-state/0.1', run_id: 'original-run', revision: 1,
  status: 'waiting_checkpoint', updated_at: '2026-10-18T00:00:00.000Z',
  next_action: {kind: 'resolve_checkpoint', checkpoint_id: 'original-checkpoint'},
  result_available: false, result_availability: {},
  checkpoint: {checkpoint_id: 'original-checkpoint', checkpoint_cid: cid('c'), kind: 'effect_set'}});

async function fixture(t, response) {
  const requests = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
    requests.push({operation, body});
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
    return response();
  }});
  t.after(() => client.close());
  return {execution: await client.attach(ref), requests};
}

for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation} projects only the original captured Checkpoint ID without changing wire bytes`, async t => {
    const original = state(), wire = JSON.stringify(original);
    assert.equal(validRunState(original), true);
    const {execution, requests} = await fixture(t, () => original);
    const observed = await execution[operation]();
    assert.equal(observed.checkpoint.id, 'original-checkpoint');
    assert.equal(Object.isFrozen(observed.checkpoint), true);
    assert.equal(Object.hasOwn(original.checkpoint, 'id'), false);
    assert.deepEqual(Object.keys(observed.checkpoint), Object.keys(original.checkpoint));
    assert.equal(JSON.stringify(observed), wire);
    assert.equal(validRunState(observed), true);
    assert.throws(() => {observed.checkpoint.id = 'foreign';}, TypeError);
    assert.throws(() => {observed.checkpoint.checkpoint_id = 'foreign';}, TypeError);
    original.checkpoint.checkpoint_id = 'later-host-mutation';
    assert.equal(observed.checkpoint.id, observed.checkpoint.checkpoint_id);
    assert.equal(observed.checkpoint.id, 'original-checkpoint');
    assert.equal(JSON.stringify(requests).includes('"id"'), false);
  });
}

test('a legitimate terminal outcome has no invented Checkpoint or throwing accessor', async t => {
  const original = state(); delete original.checkpoint;
  original.status = 'succeeded'; original.next_action = {kind: 'none'};
  assert.equal(validRunState(original), true);
  const {execution} = await fixture(t, () => original);
  const observed = await execution.wait();
  assert.equal(observed.checkpoint, undefined); assert.equal(Object.hasOwn(observed, 'checkpoint'), false);
  assert.deepEqual(observed, original);
});

test('invalid wire fields and malformed references are refused before SDK presentation', async t => {
  for (const checkpoint of [{...state().checkpoint, id: 'invented-wire-field'},
    {...state().checkpoint, checkpoint_id: null}, {...state().checkpoint, checkpoint_cid: 'not-a-cid'}]) {
    const {execution} = await fixture(t, () => ({...state(), checkpoint}));
    await assert.rejects(execution.wait(), {code: 'InvalidHostRunState'});
  }
});
