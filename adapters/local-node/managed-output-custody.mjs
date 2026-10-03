// Completion keeps the original Local operations until their installed
// cleanup refresh confirms release. Reuse the common recovery progression;
// it never starts or advances another Compute attempt.
import {settleFailedManagedOperations} from '../host-common/managed-failure.mjs';

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
  if (failure !== reason) throw failure;
}
