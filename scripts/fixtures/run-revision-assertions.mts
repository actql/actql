// Acceptance assertions only. The installed Common/Journal remains the issuer
// and validator; this projection neither assigns revisions nor admits wire.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {userInfo} from 'node:os';
import {isDeepStrictEqual} from 'node:util';
import {setImmediate} from 'node:timers/promises';
import type {RunReference} from '@actql/sdk';

type RunObservation = {
  run_id: string;
  revision?: number;
  updated_at?: string;
  status?: string;
  control?: {physical_stop?: string};
  result_available?: boolean;
  result_availability?: Readonly<Record<string, {state?: string; observed_at?: string}>>;
};

export function observedRevision(state: RunObservation, label: string) {
  assert.equal(Number.isSafeInteger(state.revision), true, `${label}: state revision`);
  assert.ok(state.revision! >= 0, `${label}: nonnegative state revision`);
  return state.revision!;
}

// Keep every published fact, including the complete control and availability
// cause projections. Only the state counter and specified read clocks differ
// without a new logical fact (run-observation.state-revision).
export function publishedFacts<State extends RunObservation>(state: State) {
  const facts: Partial<State> = structuredClone(state);
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
function retainObservationPair(error: Error, before: RunObservation, after: RunObservation, label: string) {
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
  // A terminal newline keeps Node's uncaught-error property brace off this
  // complete JSON line; the ordinary runner captures stderr without a parser.
  const diagnostic = `RUN_STATE_OBSERVATIONS ${evidence}\n`;
  // Keep the original code, operator, actual/expected values and stack frames.
  // Node assertions may already have materialized their stack before this catch.
  const stack = error.stack;
  error.message += `\n${diagnostic}`;
  if (typeof stack === 'string') error.stack = `${stack}\n${diagnostic}`;
}

export function assertObservedTransition(before: RunObservation, after: RunObservation, label: string) {
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

export function hasSettledResult(state: RunObservation, resultName: string) {
  return state.status === 'succeeded' && state.control?.physical_stop === 'confirmed' &&
    state.result_available === true && state.result_availability?.[resultName]?.state === 'available';
}

export async function observeSettledResult<State extends RunObservation>(
  run: {status(): Promise<State>}, initial: State, resultName: string, label: string, signal: AbortSignal,
) {
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
export function createComputedBarrier<Reference extends object = object>() {
  const reached = Promise.withResolvers<Reference>(), released = Promise.withResolvers<void>();
  let entered = false;
  return Object.freeze({
    async observe(ref: Reference) {
      assert.equal(entered, false, 'One original computed observation');
      entered = true;
      reached.resolve(structuredClone(ref));
      await released.promise;
    },
    async waitForOriginal(ref: Reference, signal: AbortSignal) {
      signal.throwIfAborted();
      let onAbort!: () => void;
      const aborted = new Promise<never>((_, reject) => {
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

export function shortQueryAuthorization(outcome: 'allow' | 'delegate' = 'allow') {
  const keys = generateKeyPairSync('ed25519');
  let computes = 0, nextComputed: ReturnType<typeof createComputedBarrier<RunReference>> | undefined;
  return {count: () => computes, holdNextComputed() {
    assert.equal(nextComputed, undefined, 'One fixture-owned pending barrier');
    nextComputed = createComputedBarrier<RunReference>();
    return nextComputed;
  }, value: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: `short-${outcome}`, entries: [{entry_id: 'write', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      // Current Host observation and each named Result use distinct read
      // tuples. Neither grants a write or answers a delegated preparation.
      {entry_id: 'owner-read', outcome: 'allow',
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'result/main', 'result/named', 'run']},
        operation: {any_of: ['read']}, exclusions: []}]
        .sort((left, right) => left.entry_id.localeCompare(right.entry_id))}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name: string) {if (name === 'computed') computes++;},
    async faultInjection(name: string, detail: {ref: RunReference}) {
      if (name === 'computed' && nextComputed !== undefined) {
        const original = nextComputed;
        nextComputed = undefined;
        await original.observe(detail.ref);
      }
    },
  }};
}
