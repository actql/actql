import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientError, connectInProcess, explainRunObservationFailure, formatRunObservationFailure,
  explainEffectUncertainty} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'revision-fixture', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'revision-principal', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
// Independent state and control clocks keep control refusals reachable even
// when the rejected reply has a newer state revision. Wait replies are stable.
const state = (controlRevision, revision = 41) => ({version: 'actql-run-state/0.1',
  run_id: 'revision-run', revision, status: 'succeeded',
  updated_at: '2026-10-09T00:00:00.000Z', next_action: {kind: 'none'}, result_available: false,
  result_availability: {answer: {state: 'unavailable', reason: 'not_published',
    observed_at: '2026-10-09T00:00:00.000Z'}},
  control: {revision: controlRevision, cancellation_requested: false, physical_stop: 'unknown'}});

async function fixture(t, answer) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
    calls.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
    if (operation === 'close') return;
    assert.deepEqual(body.ref, ref);
    return answer(operation);
  }});
  t.after(() => client.close());
  return {run: await client.attach(ref), calls};
}

test('a successful observation never caches authority for the next operation', async t => {
  let denied = false;
  const {run, calls} = await fixture(t, () => {
    if (denied) throw new ClientError('ClientConnectionDenied', {status: 403});
    return state(17);
  });
  assert.equal((await run.status()).status, 'succeeded');
  denied = true;
  await assert.rejects(run.status(), error => error.code === 'ClientConnectionDenied' &&
    explainRunObservationFailure(error)?.problem === 'observation_unavailable');
  assert.deepEqual(calls, ['connect', 'attach', 'status', 'status']);
});

for (const [field, value] of [['cancellation_requested', true], ['physical_stop', 'confirmed']]) {
  test(`same revision cannot change the original ${field} fact`, async t => {
    let response = state(17);
    const {run, calls} = await fixture(t, () => response);
    await run.status();
    response = {...state(17, 42), control: {...state(17).control, [field]: value}};
    const failure = await run.status().then(() => undefined, error => error);
    assert.equal(explainRunObservationFailure(failure)?.problem, 'stale_observation',
      '[check-mutation:run-control-conflict]');
    assert.equal(failure.code, 'InvalidHostRunState');
    assert.deepEqual(calls, ['connect', 'attach', 'status', 'status']);
  });
}

for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: a delayed older reply is rejected after a newer concurrent observation`, async t => {
    let deliverOlder;
    const older = new Promise(resolve => {deliverOlder = resolve;});
    let reads = 0;
    const {run, calls} = await fixture(t, () => ++reads === 1 ? older : state(18, 43));
    const pending = run[operation]();
    const rejection = pending.then(() => undefined, error => error);
    const current = await run.status();
    deliverOlder(state(17, 44));
    const failure = await rejection;
    assert.equal(explainRunObservationFailure(failure)?.problem, 'stale_observation',
      '[check-mutation:run-control-completion-order]');
    assert.equal(failure.code, 'InvalidHostRunState');
    assert.equal(current.control.revision, 18);
    assert.deepEqual(calls, ['connect', 'attach', operation, 'status']);
  });
}

test('duplicate control revisions do not impose a revision on independent Effect facts or timestamps', async t => {
  let response = state(17);
  const {run} = await fixture(t, () => response);
  const first = await run.status();
  response = {...state(17, 42), updated_at: '2026-10-09T00:01:00.000Z',
    status: 'needs_reconciliation', next_action: {kind: 'reconcile', effects: ['save']}};
  const effect = await run.wait();
  assert.deepEqual(effect.control, first.control);
  assert.equal(explainEffectUncertainty(effect).observation, 'effect_outcome_unknown');
  response = {...state(18, 43), updated_at: '2026-10-08T00:00:00.000Z'};
  assert.equal((await run.status()).control.revision, 18);
});

test('rejected and omitted control observations do not reset the retained revision or authorize retries', async t => {
  let response = state(17);
  const {run, calls} = await fixture(t, () => response);
  await run.status();
  const withoutControl = state(17, 42);
  delete withoutControl.control;
  response = withoutControl;
  assert.equal(Object.hasOwn(await run.status(), 'control'), false);
  response = {...state(16, 44), updated_at: '2026-10-10T00:00:00.000Z'};
  let failure;
  await assert.rejects(run.status(), error => {failure = error; return error.code === 'InvalidHostRunState';});
  const before = [...calls];
  const expected = {kind: 'protocol_failure', problem: 'stale_observation', operation: 'status',
    summary: 'The Run reply has an older control revision or conflicts with previously observed control facts.',
    hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.',
    next: {operation: 'status', ref}};
  assert.deepEqual(explainRunObservationFailure(failure), expected);
  for (const format of ['text', 'html', 'json']) {
    const output = formatRunObservationFailure(failure, {format});
    assert.ok(output);
    if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected);
    assert.equal(formatRunObservationFailure({...failure}, {format}), undefined);
  }
  const {summary, hint, ...translated} = explainRunObservationFailure(failure, {locale: 'ja'});
  const {summary: englishSummary, hint: englishHint, ...facts} = expected;
  assert.deepEqual(translated, facts);
  assert.deepEqual(calls, before);
  response = state(16, 44);
  await assert.rejects(run.status(), error => explainRunObservationFailure(error)?.problem === 'stale_observation');
  response = state(18, 43);
  assert.equal((await run.status()).control.revision, 18);
});

test('mutating a previously returned observation cannot replace the private control revision', async t => {
  let response = state(17);
  const {run} = await fixture(t, () => response);
  const first = await run.status();
  first.control.revision = 0;
  first.control.cancellation_requested = true;
  response = state(16, 44);
  const failure = await run.status().then(() => undefined, error => error);
  assert.equal(explainRunObservationFailure(failure)?.problem, 'stale_observation',
    '[check-mutation:run-control-custody]');
  assert.equal(failure.code, 'InvalidHostRunState');
  response = state(17);
  assert.deepEqual((await run.status()).control, state(17).control);
});

for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: an older Run control revision cannot replace a newer observation`, async t => {
    let response = state(17);
    const {run, calls} = await fixture(t, () => response);
    const original = await run.status();
    response = state(16, 44);
    const failure = await run[operation]().then(() => undefined, error => error);
    const explanation = explainRunObservationFailure(failure);
    assert.equal(explanation?.problem, 'stale_observation',
      '[check-mutation:run-control-revision]');
    assert.equal(failure.code, 'InvalidHostRunState');
    assert.deepEqual(explanation.next, {operation: 'status', ref});
    assert.equal(original.control.revision, 17);
    assert.equal(explainRunObservationFailure({...failure}), undefined);
    assert.deepEqual(calls, ['connect', 'attach', 'status', operation]);
  });
}
