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
