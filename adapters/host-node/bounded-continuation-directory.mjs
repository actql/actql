import {opendir} from 'node:fs/promises';

const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const count = n => Number.isSafeInteger(n) && n >= 0;

// Physical acquisition only. The installed original Scope must fund the
// directory handle/buffer, all names, UTF8 decode, result backing, sorting and
// pending-close controls simultaneously BEFORE calling this primitive. These
// limits are not that funding, a ledger-entry count, custody or a send grant.
export async function listContinuationLedgerNamesBounded(path, supplied, signal) {
  const maxDirectoryEntries = supplied?.maxDirectoryEntries;
  const maxWireBytes = supplied?.maxWireBytes;
  if (typeof path !== 'string' || path.length === 0 || supplied === null ||
      typeof supplied !== 'object' || Array.isArray(supplied) ||
      Object.keys(supplied).sort().join(',') !== 'maxDirectoryEntries,maxWireBytes' ||
      !count(maxDirectoryEntries) || !count(maxWireBytes) ||
      (signal !== undefined && !(signal instanceof AbortSignal))) {
    fail('InvalidContinuationDirectoryBounds');
  }
  // One entry per internal fill, rather than readdir's unbounded array. The
  // single excess entry needed to detect N+1 also belongs in the funded overlap.
  signal?.throwIfAborted();
  let directory;
  try { directory = await opendir(path, {encoding: 'buffer', bufferSize: 1}); }
  catch (cause) {
    if (cause?.code === 'ENOENT') fail('ContinuationDirectoryUnavailable', cause);
    throw cause;
  }
  let primary, failed = false;
  try {
    const names = [];
    let entries = 0, wireBytes = 0;
    for (;;) {
      signal?.throwIfAborted();
      const entry = await directory.read();
      signal?.throwIfAborted();
      if (entry === null) break;
      if (entries === maxDirectoryEntries) fail('ContinuationDirectoryEntriesLimit');
      entries++;
      if (!(entry.name instanceof Uint8Array) ||
          entry.name.byteLength > maxWireBytes - wireBytes) {
        fail('ContinuationDirectoryWireLimit');
      }
      wireBytes += entry.name.byteLength;
      let name;
      try { name = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(entry.name); }
      catch (cause) { fail('InvalidContinuationDirectoryName', cause); }
      // Every entry counts before filtering. Unrelated/tmp/invalid attempt
      // names cannot make an unlimited directory look like an empty selection.
      if (/^[A-Za-z0-9._:-]{1,128}\.json$/u.test(name)) names.push(name.slice(0, -5));
    }
    names.sort(); // Finite declared entry ceiling, not another observation.
    return names;
  } catch (cause) { primary = cause; failed = true; throw cause; }
  finally {
    try {
      if (await directory.close() === false) fail('ContinuationDirectoryCleanupPending');
    }
    catch (closeFailure) {
      // Keep this same physical Dir and its original reservation/custody. A
      // retry is close-only; it never reopens or repeats directory acquisition.
      let original = directory, flight;
      const status = () => Object.freeze({pending: original !== undefined});
      const cleanup = Object.freeze({status, retry() {
        if (flight !== undefined) return flight;
        if (original === undefined) return Promise.resolve(status());
        flight = Promise.resolve().then(() => original.close()).then(result => {
          if (result === false) fail('ContinuationDirectoryCleanupPending');
          original = undefined;
          return status();
        }).finally(() => { flight = undefined; });
        return flight;
      }});
      const reason = failed ? primary : closeFailure;
      const failure = reason !== null && typeof reason === 'object' &&
        Object.isExtensible(reason) && reason.cleanupHandle === undefined
        ? reason : new Error('ContinuationDirectoryCleanupPending', {cause: reason});
      failure.cleanupHandle = cleanup;
      failure.cleanupPending = true;
      failure.cleanupError = closeFailure;
      throw failure;
    }
    // A cancellation during close must not publish a successful names result.
    if (!failed) signal?.throwIfAborted();
  }
}
