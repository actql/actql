// Completion keeps the original Local operations until their installed
// cleanup refresh confirms release. Reuse the common recovery progression;
// it never starts or advances another Compute attempt.
import {settleFailedManagedOperations} from '../host-common/managed-failure.mjs';

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
        if (state.pending !== true) return state;
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
  let reason = new Error('LocalManagedOutputCleanupPending');
  try {
    operations.close();
    if (typeof operations.cleanup_refresh !== 'function') {
      throw new Error('MissingLocalManagedCleanupRefresh');
    }
    if (operations.cleanup_refresh() === true) return;
  } catch (error) { reason = error; }
  const failure = settleFailedManagedOperations(operations, checked, reason, progress);
  if (failure !== reason) throw retainProgressingCleanup(failure, operations);
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

async function continueFailureCleanup(failure, operations) {
  const handle = failure?.cleanupHandle;
  if (typeof operations.cleanup_local_continuation !== 'function' ||
      typeof handle?.retry !== 'function' || typeof handle?.status !== 'function') return failure;
  try {
    let previous = operations.cleanup_local_continuation();
    while (typeof previous === 'bigint' && previous >= 0n &&
        handle.status()?.pending === true) {
      await new Promise(resolve => setTimeout(resolve, 0));
      // A reader/cancellation may change eligibility while yielded.
      const ready = operations.cleanup_local_continuation();
      if (typeof ready !== 'bigint' || ready < previous) break;
      const state = await handle.retry();
      if (state?.pending !== true || state.errors?.length > 0) break;
      const current = operations.cleanup_local_continuation();
      if (typeof current !== 'bigint' || current <= previous) break;
      previous = current;
    }
  } catch { /* Original failure and recovery owner remain authoritative. */ }
  return failure;
}
