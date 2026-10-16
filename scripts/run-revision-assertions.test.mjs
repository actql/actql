import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {assertObservedTransition, createComputedBarrier, hasSettledResult, observeSettledResult,
  observedRevision, publishedFacts} from './fixtures/run-revision-assertions.mjs';

const state = () => ({version: 'actql-run-state/0.1', run_id: 'original-run', revision: 1,
  status: 'succeeded', updated_at: '2026-10-17T00:00:00Z',
  control: {revision: 2, cancellation_requested: false, physical_stop: 'unknown'},
  result_available: true, next_action: {kind: 'read_result', results: ['answer']},
  result_availability: {answer: {state: 'available', reason: 'confirmed_present',
    observed_at: '2026-10-17T00:00:00Z'}}});

test('only specified read clocks are ignored without mutating observations', () => {
  const before = state(), after = structuredClone(before);
  after.updated_at = '2026-10-17T00:00:01Z';
  after.result_availability.answer.observed_at = after.updated_at;
  assertObservedTransition(before, after, 'read clocks');
  assert.equal(before.result_availability.answer.observed_at, '2026-10-17T00:00:00Z');
  assert.equal(after.revision, 1);
  assert.deepEqual(publishedFacts(before), publishedFacts(after));
});

test('an unjustified revision increment fails even for a terminal Run', () => {
  const before = state(), after = {...before, revision: 2};
  assert.throws(() => assertObservedTransition(before, after, 'no-op'), /no-op read/u);
});

test('same succeeded status with actual control change requires advancement', () => {
  const before = state(), after = structuredClone(before);
  after.control = {...after.control, revision: 3, physical_stop: 'confirmed'};
  assert.throws(() => assertObservedTransition(before, after, 'control'), /must advance/u);
  after.revision = 2;
  assertObservedTransition(before, after, 'control');
});

test('availability cause, next action and complete control remain facts', () => {
  for (const change of [value => {value.result_availability.answer.reason = 'expired';},
    value => {value.next_action.results = [];},
    value => {value.control.revision++;},
    value => {value.control.cancellation_requested = true;}]) {
    const before = state(), after = structuredClone(before);
    change(after);
    assert.throws(() => assertObservedTransition(before, after, 'changed fact'), /must advance/u);
  }
});

test('foreign Run, missing revision, negative revision and rollback fail', () => {
  const before = state();
  assert.throws(() => assertObservedTransition(before, {...before, run_id: 'foreign'}, 'foreign'), /same original/u);
  for (const revision of [undefined, -1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => observedRevision({...before, revision}, 'invalid'));
  }
  const after = {...before, revision: 0, status: 'failed'};
  assert.throws(() => assertObservedTransition(before, after, 'rollback'), /must advance/u);
});

test('terminal status or repeated counter alone is not settled control', async () => {
  const initial = state(), unchanged = structuredClone(initial), settled = state();
  settled.control = {...settled.control, revision: 3, physical_stop: 'confirmed'};
  settled.revision = 2;
  assert.equal(hasSettledResult(initial, 'answer'), false);
  let reads = 0;
  const run = {async status() {return [unchanged, settled][reads++];}};
  assert.equal(await observeSettledResult(run, initial, 'answer', 'settle', AbortSignal.timeout(1000)), settled);
  assert.equal(reads, 2);
});

test('settled control without an available Result is not the wait baseline', () => {
  const observed = state();
  observed.control.physical_stop = 'confirmed';
  observed.result_availability.answer.state = 'unavailable';
  assert.equal(hasSettledResult(observed, 'answer'), false);
  observed.result_availability.answer.state = 'available';
  assert.equal(hasSettledResult(observed, 'answer'), true);
});

test('churning counters without new facts fail rather than eventually stabilize', async () => {
  const initial = state();
  await assert.rejects(observeSettledResult({async status() {return {...initial, revision: 2};}},
    initial, 'answer', 'churn', AbortSignal.timeout(1000)), /no-op read/u);
});

test('an aborted settle observation never substitutes a settled default', async () => {
  const abort = new AbortController();
  abort.abort(new Error('TestStop'));
  await assert.rejects(observeSettledResult({status() {assert.fail('No read after abort');}},
    state(), 'answer', 'cancel', abort.signal), /TestStop/u);
});

test('both external consumer preparations stage the actual assertion module', async () => {
  for (const path of ['test-package-release-install.mjs', 'test-packed-local-without-duckdb.mjs']) {
    const source = await readFile(new URL(path, import.meta.url), 'utf8');
    assert.match(source, /copyFile\(join\(repository, 'scripts\/fixtures\/run-revision-assertions\.mjs'\),/u);
  }
});

test('computed barrier retains the exact original ref and one pending lifetime', async () => {
  const barrier = createComputedBarrier(), ref = {namespaceId: 'original', runDefinitionCid: 'run'};
  let retired = false;
  const pending = barrier.observe(ref).then(() => {retired = true;});
  await barrier.waitForOriginal({...ref}, AbortSignal.timeout(1000));
  assert.equal(retired, false);
  barrier.release(); await pending;
  assert.equal(retired, true);
  await assert.rejects(barrier.observe(ref), /One original/u);
});

test('computed barrier refuses a foreign original and can still release custody', async () => {
  const barrier = createComputedBarrier();
  const pending = barrier.observe({runDefinitionCid: 'original'});
  await assert.rejects(barrier.waitForOriginal({runDefinitionCid: 'foreign'},
    AbortSignal.timeout(1000)), /same original/u);
  barrier.release(); await pending;
});

test('revision zero is a legal earlier observation, not an invented predecessor', () => {
  const before = {...state(), revision: 0}, after = state();
  after.control = {...after.control, revision: 3, physical_stop: 'confirmed'};
  assert.equal(observedRevision(before, 'zero'), 0);
  assertObservedTransition(before, after, 'real transition');
  assert.equal(after.revision > before.revision, true);
});
