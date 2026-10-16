// Acceptance assertions only. The installed Common/Journal remains the issuer
// and validator; this projection neither assigns revisions nor admits wire.
import assert from 'node:assert/strict';
import {isDeepStrictEqual} from 'node:util';
import {setImmediate} from 'node:timers/promises';

export function observedRevision(state, label) {
  assert.equal(Number.isSafeInteger(state.revision), true, `${label}: state revision`);
  assert.ok(state.revision >= 0, `${label}: nonnegative state revision`);
  return state.revision;
}

// Keep every published fact, including the complete control and availability
// cause projections. Only the state counter and specified read clocks differ
// without a new logical fact (run-observation.state-revision).
export function publishedFacts(state) {
  const facts = structuredClone(state);
  delete facts.revision;
  delete facts.updated_at;
  if (facts.result_availability !== undefined) {
    for (const observation of Object.values(facts.result_availability)) {
      delete observation.observed_at;
    }
  }
  return facts;
}

// These arguments are the fixture's already-authorized public Run responses,
// never transport errors, journal parameters or backend objects. Keep a full
// pair on failure without changing the assertion or the product's disclosure.
function retainObservationPair(error, before, after, label) {
  let evidence;
  try {
    const pair = JSON.stringify({label, before, after,
      beforeFacts: publishedFacts(before), afterFacts: publishedFacts(after)});
    const bytes = Buffer.byteLength(pair);
    evidence = bytes <= 64 * 1024 ? pair : JSON.stringify({available: false,
      reason: 'observation_pair_byte_limit', bytes});
  } catch {
    evidence = JSON.stringify({available: false, reason: 'observation_pair_serialization_failed'});
  }
  const diagnostic = `RUN_STATE_OBSERVATIONS ${evidence}`;
  // Keep the original code, operator, actual/expected values and stack frames.
  // Node assertions may already have materialized their stack before this catch.
  const stack = error.stack;
  error.message += `\n${diagnostic}`;
  if (typeof stack === 'string') error.stack = `${stack}\n${diagnostic}`;
}

export function assertObservedTransition(before, after, label) {
  try {
    assert.equal(after.run_id, before.run_id, `${label}: same original Run`);
    const previous = observedRevision(before, label), next = observedRevision(after, label);
    if (isDeepStrictEqual(publishedFacts(before), publishedFacts(after))) {
      assert.equal(next, previous, `${label}: a no-op read must not advance revision`);
    } else {
      assert.ok(next > previous, `${label}: changed published facts must advance revision`);
    }
  } catch (error) {
    if (error instanceof assert.AssertionError) retainObservationPair(error, before, after, label);
    throw error;
  }
}

export function hasSettledResult(state, resultName) {
  return state.status === 'succeeded' && state.control?.physical_stop === 'confirmed' &&
    state.result_available === true && state.result_availability?.[resultName]?.state === 'available';
}

export async function observeSettledResult(run, initial, resultName, label, signal) {
  let state = initial;
  // Do not accept a stable counter or terminal status as evidence of settled
  // control. Read only this original Run until its actual published facts say so.
  while (!hasSettledResult(state, resultName)) {
    signal.throwIfAborted();
    await setImmediate();
    const next = await run.status();
    assertObservedTransition(state, next, label);
    state = next;
  }
  return state;
}

// The existing awaited computed hook can expose a real earlier publication
// before its original cleanup/stop transition. No counter or state is invented.
export function createComputedBarrier() {
  const reached = Promise.withResolvers(), released = Promise.withResolvers();
  let entered = false;
  return Object.freeze({
    async observe(ref) {
      assert.equal(entered, false, 'One original computed observation');
      entered = true;
      reached.resolve(structuredClone(ref));
      await released.promise;
    },
    async waitForOriginal(ref, signal) {
      signal.throwIfAborted();
      let onAbort;
      const aborted = new Promise((_, reject) => {
        onAbort = () => reject(signal.reason);
        signal.addEventListener('abort', onAbort, {once: true});
      });
      try {
        assert.deepEqual(await Promise.race([reached.promise, aborted]), ref,
          'Computed hook belongs to the same original Run');
      } finally {signal.removeEventListener('abort', onAbort);}
    },
    release() {released.resolve();},
  });
}
