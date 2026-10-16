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

export function assertObservedTransition(before, after, label) {
  assert.equal(after.run_id, before.run_id, `${label}: same original Run`);
  const previous = observedRevision(before, label), next = observedRevision(after, label);
  if (isDeepStrictEqual(publishedFacts(before), publishedFacts(after))) {
    assert.equal(next, previous, `${label}: a no-op read must not advance revision`);
  } else {
    assert.ok(next > previous, `${label}: changed published facts must advance revision`);
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
