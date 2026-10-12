import {readBoundedLocalMetadata} from '../store-local/publication-store.mjs';

const version = 'actql-local-continuation-retention/0.1';
const attempt = /^[A-Za-z0-9._:-]{1,128}$/u;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const count = value => Number.isSafeInteger(value) && value >= 0;
const keys = (value, required, optional = []) => object(value) &&
  required.every(name => Object.hasOwn(value, name)) &&
  Object.keys(value).every(name => required.includes(name) || optional.includes(name));
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };

// Shape/wire acquisition ONLY. The existing Evidence Owner selects the exact
// path/attempt and supplies immutable installed bounds before this call. It
// still funds bytes + decoded tree/entries + frames + FD/cleanup overlap in its
// original Ledger. These two limits are not coefficients, custody, a stable
// current cut, restoration or Model-send authority. There is no numeric default.
// The existing physical reader closes the same original FD before returning;
// failed close retains that FD in the original error.cleanupHandle. Do not
// settle the caller's whole decode reservation merely because the FD closed.
export async function readContinuationLedgerBounded(path, prepareAttemptId, supplied, signal) {
  const maxWireBytes = supplied?.maxWireBytes;
  const maxLedgerEntries = supplied?.maxLedgerEntries;
  if (typeof path !== 'string' || path.length === 0 ||
      typeof prepareAttemptId !== 'string' || !attempt.test(prepareAttemptId) ||
      !keys(supplied, ['maxWireBytes', 'maxLedgerEntries']) ||
      !count(maxWireBytes) || maxWireBytes === 0 ||
      !count(maxLedgerEntries)) {
    fail('InvalidContinuationMetadataBounds');
  }
  // Capture before the first await, so caller mutation cannot widen a read.
  let bytes;
  try { bytes = await readBoundedLocalMetadata(path, maxWireBytes, undefined, signal); }
  catch (error) {
    // This consumes known original metadata, never creates a new ledger.
    // Missing/raced-away bytes are unavailable, not evidence of a fresh Run
    // or successful cleanup. Preserve pending original FD custody unchanged.
    if (!signal?.aborted && error?.code === 'ENOENT' && error.cleanupHandle === undefined) {
      fail('ContinuationMetadataUnavailable', error);
    }
    throw error;
  }
  // Close confirmation is not cancellation confirmation or resource release.
  // In particular, cancellation during close must not start decode/parse.
  signal?.throwIfAborted();
  let value;
  try {
    value = JSON.parse(new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes));
  } catch (cause) { fail('InvalidContinuationLedger', cause); }
  if (!keys(value, ['version', 'prepare_attempt_id', 'request_cid', 'key_id', 'holdings'], ['abandoned']) ||
      value.version !== version || value.prepare_attempt_id !== prepareAttemptId ||
      !cid(value.request_cid) || !cid(value.key_id) ||
      !Array.isArray(value.holdings) ||
      (value.abandoned !== undefined && typeof value.abandoned !== 'boolean')) {
    fail('InvalidContinuationLedger');
  }
  // Count ALL retained metadata entries, including retired revisions; role
  // count and live Core/physical holdings cannot replace this distinct bound.
  if (value.holdings.length > maxLedgerEntries) fail('ContinuationLedgerEntriesLimit');
  for (const entry of value.holdings) {
    if (!keys(entry, ['name', 'semantic_cid', 'holding_cid', 'key_id', 'state'], ['cleanup_error']) ||
        typeof entry.name !== 'string' || entry.name.length === 0 ||
        entry.name.length > 128 || !entry.name.isWellFormed() ||
        !cid(entry.semantic_cid) || !cid(entry.holding_cid) ||
        !cid(entry.key_id) || !['held', 'retiring', 'retired'].includes(entry.state) ||
        (entry.cleanup_error !== undefined &&
          (typeof entry.cleanup_error !== 'string' || !entry.cleanup_error.isWellFormed()))) {
      fail('InvalidContinuationLedger');
    }
  }
  // The existing Owner still validates its closed role set, same key, exact
  // holding derivation, current need and actual Store handle. A parsed row or
  // copied CID must not replace any of those nominal/physical obligations.
  return value;
}
