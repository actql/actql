import {setImmediate as yieldEventLoop} from 'node:timers/promises';
// Completion keeps the original Local operations until their installed
// cleanup refresh confirms release. Reuse the common recovery progression;
// it never starts or advances another Compute attempt.
import {settleFailedManagedOperations} from '../host-common/managed-failure.mjs';
import {managedMemoryReleaseFailureMatches} from '../store-local/managed-memory-representations.mjs';

const completedRetirements = new WeakMap();
const completedRetirementFlights = new WeakMap();
function retirementProgress(operations) {
  if (typeof operations.cleanup_progress !== 'function') return undefined;
  const value = operations.cleanup_progress();
  return typeof value === 'bigint' && value >= 0n && value <= (1n << 63n) - 1n
    ? value : undefined;
}

function retainProgressingCleanup(failure, operations) {
  if (typeof operations.cleanup_progress !== 'function') return failure;
  const original = failure.cleanupHandle;
  const originalRetry = original.retry;
  const originalStatus = original.status;
  const observe = operations.cleanup_progress.bind(operations);
  let flight;
  const retry = () => {
    if (flight !== undefined) return flight;
    flight = Promise.resolve().then(async () => {
      let previous = observe();
      for (;;) {
        const state = await Reflect.apply(originalRetry, original, []);
        if (state.pending !== true || state.errors?.length > 0) return state;
        const current = observe();
        // Only original bounded scratch retirement justifies another slice.
        // A provider/reader stall or failed observation stays caller-retryable.
        if (typeof previous !== 'bigint' || typeof current !== 'bigint' ||
            current <= previous) return state;
        previous = current;
        await new Promise(resolve => setTimeout(resolve, 0));
      }
    }).finally(() => { flight = undefined; });
    return flight;
  };
  failure.cleanupHandle = Object.freeze({
    status: () => Reflect.apply(originalStatus, original, []), retry,
  });
  return failure;
}

export function closeCompletedLocalManagedOutput(operations, checked, progress) {
  let before;
  try { before = retirementProgress(operations); } catch { /* No automatic continuation. */ }
  let synthetic = true;
  let reason = new Error('LocalManagedOutputCleanupPending');
  try {
    operations.close();
    if (typeof operations.cleanup_refresh !== 'function') {
      throw new Error('MissingLocalManagedCleanupRefresh');
    }
    if (operations.cleanup_refresh() === true) return;
  } catch (error) { reason = error; synthetic = false; }
  const failure = settleFailedManagedOperations(operations, checked, reason, progress);
  if (failure !== reason) {
    const owned = retainProgressingCleanup(failure, operations);
    if (synthetic && typeof before === 'bigint') {
      try {
        const after = retirementProgress(operations);
        if (typeof after === 'bigint' && after > before &&
            owned.cleanupHandle.status().errors.length === 0) {
          completedRetirements.set(owned, {operations, after});
        }
      } catch { /* Original failure remains caller-retryable. */ }
    }
    throw owned;
  }
}

// Await only an original completed-output retirement that already made finite
// scratch progress. The memory registry's release callback stays synchronous;
// its own recovery handle alone acknowledges the physical representation cut.
export async function closeCompletedLocalManagedOutputAsync(operations, checked, progress, memory) {
  try {
    await (memory === undefined
      ? closeCompletedLocalManagedOutput(operations, checked, progress) : memory.close());
    return;
  } catch (failure) {
    if (memory !== undefined && !managedMemoryReleaseFailureMatches(memory, failure)) throw failure;
    const inner = completedRetirements.has(failure) ? failure : failure?.primaryFailure;
    const original = completedRetirements.get(inner);
    const handle = failure?.cleanupHandle;
    if (original?.operations !== operations || typeof handle?.retry !== 'function' ||
        typeof handle?.status !== 'function') throw failure;
    let flight = completedRetirementFlights.get(inner);
    if (flight === undefined) {
      flight = (async () => {
        try {
          const now = retirementProgress(operations);
          if (typeof now !== 'bigint' || now < original.after) return false;
          // One original bounded retry; its existing progress-limited driver
          // stops at a physical stall or error and cannot advance Compute.
          const result = await handle.retry();
          const final = handle.status();
          const local = inner.cleanupHandle.status();
          return local?.pending === false && local.errors?.length === 0 && result?.pending === false && result.errors?.length === 0 &&
            final?.pending === false && final.errors?.length === 0;
        } catch { return false; }
      })().finally(() => { completedRetirementFlights.delete(inner); });
      completedRetirementFlights.set(inner, flight);
    }
    if (!await flight) throw failure;
  }
}

// Finalization failure can leave more than one local retirement quantum. Keep
// the dispatch alive while the original driver proves runnable finite work;
// never poll an external owner or substitute a new Compute attempt.
const failureCleanupFlights = new WeakMap();
export function continueLocalManagedFailureCleanup(failure, operations) {
  if (failure === null || typeof failure !== 'object') return Promise.resolve(failure);
  const existing = failureCleanupFlights.get(failure);
  if (existing !== undefined) return existing;
  const flight = continueFailureCleanup(failure, operations).finally(() => {
    failureCleanupFlights.delete(failure);
  });
  failureCleanupFlights.set(failure, flight);
  return flight;
}

// MoonBit's JS ABI may expose an Int64 as its unsigned 64-bit bit pattern.
// Normalize the original witness, but never wrap an out-of-domain value into
// authority to run cleanup. In particular, unsigned -1 still means blocked.
function cleanupContinuation(operations) {
  const value = operations.cleanup_local_continuation();
  if (typeof value !== 'bigint' || value < -(1n << 63n) ||
      value > (1n << 64n) - 1n) return undefined;
  return BigInt.asIntN(64, value);
}

async function continueFailureCleanup(failure, operations) {
  const handle = failure?.cleanupHandle;
  if (typeof operations.cleanup_local_continuation !== 'function' ||
      typeof handle?.retry !== 'function' || typeof handle?.status !== 'function') return failure;
  try {
    let previous = cleanupContinuation(operations);
    while (typeof previous === 'bigint' && previous >= 0n &&
        handle.status()?.pending === true) {
      await new Promise(resolve => setTimeout(resolve, 0));
      // A reader/cancellation may change eligibility while yielded.
      const ready = cleanupContinuation(operations);
      if (typeof ready !== 'bigint' || ready < previous) break;
      const state = await handle.retry();
      if (state?.pending !== true || state.errors?.length > 0) break;
      const current = cleanupContinuation(operations);
      if (typeof current !== 'bigint' || current <= previous) break;
      previous = current;
    }
  } catch { /* Original failure and recovery owner remain authoritative. */ }
  return failure;
}


// A completed material stays live. This advances only the original provider's
// existing scratch cleanup, never output close, stop, retention release or work.
// Retry only a typed local continuation that made finite retirement progress;
// a provider/reader/physical stall preserves its original reservation.
export async function refreshCompletedLocalManagedScratch(operations, available) {
  if (typeof operations.cleanup_refresh !== 'function' ||
      typeof operations.cleanup_local_continuation !== 'function' ||
      typeof available !== 'function') {
    throw new TypeError('MissingLocalCompletedScratchRefresh');
  }
  if (!available()) throw new Error('ReleasedLocalManagedOutput');
  operations.cleanup_refresh();
  let previous = cleanupContinuation(operations);
  while (typeof previous === 'bigint' && previous >= 0n) {
    await yieldEventLoop();
    if (!available()) throw new Error('ReleasedLocalManagedOutput');
    const ready = cleanupContinuation(operations);
    if (typeof ready !== 'bigint' || ready < previous) return;
    operations.cleanup_refresh();
    const current = cleanupContinuation(operations);
    if (typeof current !== 'bigint' || current < 0n || current <= previous) return;
    previous = current;
  }
}
