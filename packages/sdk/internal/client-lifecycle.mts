// One connection's physical close and reader cleanup responsibilities.
// Sealing is immediate; failed cleanup remains retryable on this same connection.
import {ClientError} from './errors.mjs';

export function createClientLifecycle(port) {
  let closed = false;
  let closeFlight;
  let released = false;
  const activeReaders = new Set();
  const readerCleanups = new Set();
  const readCleanupFailures = [];
  function close() {
    // Revoke new use before returning, including while physical cleanup waits.
    closed = true;
    let sealFailed = false;
    try { port?.seal?.(); } catch { sealFailed = true; }
    for (const reader of activeReaders) reader.abort();
    if (closeFlight !== undefined) return closeFlight;
    closeFlight = Promise.resolve().then(async () => {
      const readers = [...activeReaders];
      // Abort before return(): a pending next or backpressured Local producer
      // must settle without another application call into the iterator.
      for (const reader of readers) reader.abort();
      await Promise.allSettled(readers.map(reader => reader.finish()));
      for (const reader of readers) {
        // Only the original reader marks a failed disposal without a retry
        // witness. Registered Local close duties are confirmed separately.
        if (reader.cleanupFailure !== undefined && !readCleanupFailures.includes(reader.cleanupFailure)) {
          readCleanupFailures.push(reader.cleanupFailure);
        }
      }
      const failures = [];
      for (const cleanup of [...readerCleanups]) {
        try { await cleanup(); readerCleanups.delete(cleanup); }
        catch (error) { failures.push(error); }
      }
      if (sealFailed || failures.length) {
        throw new ClientError('ClientCleanupPending', {cleanupPending: true});
      }
      if (!released) {
        try { await port?.close?.(); }
        catch { throw new ClientError('ClientCleanupPending', {cleanupPending: true}); }
        released = true;
      }
      // Report the original read's uncertainty after releasing actual local
      // duties. A finished iterator supplies no fabricated cleanup retry owner.
      if (readCleanupFailures.length === 1) throw readCleanupFailures.pop();
      if (readCleanupFailures.length > 1) {
        throw new ClientError('ResultReadCleanupUnknown', {cleanupError:
          new AggregateError(readCleanupFailures.splice(0), 'Multiple reader cleanup failures')});
      }
    }).finally(() => { closeFlight = undefined; });
    return closeFlight;
  }
  return {close, isClosed: () => closed, activeReaders, readerCleanups};
}
