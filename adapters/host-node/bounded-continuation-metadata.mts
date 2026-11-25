import {readBoundedLocalMetadata} from '../store-local/publication-store.mjs';

type MetadataLimitInput = Readonly<{maxWireBytes?: unknown; maxLedgerEntries?: unknown}>;
type ShapeControl = Readonly<{
  privateContinuationRetentionShape(bytes: Uint8Array, attemptId: string, maxWireBytes: number, maxEntries: number): string;
}>;
type Holding = {
  name: string;
  semantic_cid: string;
  holding_cid: string;
  key_id: string;
  state: 'held' | 'retiring' | 'retired';
  cleanup_error?: string;
  artifact_cid?: string;
};
type ContinuationLedger = {
  version: typeof version;
  prepare_attempt_id: string;
  request_cid: string;
  key_id: string;
  holdings: Holding[];
  abandoned?: boolean;
};

const version = 'actql-local-continuation-retention/0.1';
const attempt = /^[A-Za-z0-9._:-]{1,128}$/u;
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const count = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const keys = (value: unknown, required: readonly string[], optional: readonly string[] = []):
  value is Record<string, unknown> => object(value) &&
  required.every(name => Object.hasOwn(value, name)) &&
  Object.keys(value).every(name => required.includes(name) || optional.includes(name));
const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };

// Shape/wire acquisition ONLY. The existing Evidence Owner selects the exact
// path/attempt and supplies immutable installed bounds before this call. It
// still funds bytes + decoded tree/entries + frames + FD/cleanup overlap in its
// original Ledger. These two limits are not coefficients, custody, a stable
// current cut, restoration or Model-send authority. There is no numeric default.
// The existing physical reader closes the same original FD before returning;
// failed close retains that FD in the original error.cleanupHandle. Do not
// settle the caller's whole decode reservation merely because the FD closed.
export async function readContinuationLedgerBounded(path: string, prepareAttemptId: string,
  supplied: MetadataLimitInput | undefined, signal?: AbortSignal, control?: ShapeControl): Promise<ContinuationLedger> {
  const maxWireBytes = supplied?.maxWireBytes;
  const maxLedgerEntries = supplied?.maxLedgerEntries;
  if (typeof path !== 'string' || path.length === 0 ||
      typeof prepareAttemptId !== 'string' || !attempt.test(prepareAttemptId) ||
      !keys(supplied, ['maxWireBytes', 'maxLedgerEntries']) ||
      !count(maxWireBytes) || maxWireBytes === 0 ||
      !count(maxLedgerEntries)) {
    fail('InvalidContinuationMetadataBounds');
  }
  // A fixed data parser in the installed Core, not a caller-supplied grant or
  // an unbounded JSON fallback. Its complete temporary lifetime belongs to the
  // same READ envelope as the original bytes and the returned metadata.
  if (typeof control?.privateContinuationRetentionShape !== 'function') {
    fail('ContinuationMetadataUnavailable');
  }
  const shape = control.privateContinuationRetentionShape;
  // Capture before the first await, so caller mutation cannot widen a read.
  let bytes;
  try { bytes = await readBoundedLocalMetadata(path, maxWireBytes, undefined, signal); }
  catch (error) {
    // This consumes known original metadata, never creates a new ledger.
    // Missing/raced-away bytes are unavailable, not evidence of a fresh Run
    // or successful cleanup. Preserve pending original FD custody unchanged.
    if (!signal?.aborted && (error as {code?: unknown} | null | undefined)?.code === 'ENOENT' &&
        (error as {cleanupHandle?: unknown}).cleanupHandle === undefined) {
      fail('ContinuationMetadataUnavailable', error);
    }
    throw error;
  }
  // Close confirmation is not cancellation confirmation or resource release.
  // In particular, cancellation during close must not start decode/parse.
  signal?.throwIfAborted();
  // Use the actual bounded FD length, not a potentially larger safe-integer
  // Host ceiling, at the Int Core ABI. No valid entry can outnumber its input
  // bytes. This preserves large ceilings for small actual records without
  // narrowing, wrapping or treating an unknown count as zero.
  if (bytes.byteLength >= 2147483647) fail('InvalidContinuationLedger');
  const issue = shape(bytes, prepareAttemptId, bytes.byteLength,
    Math.min(maxLedgerEntries, bytes.byteLength));
  if (issue !== '') {
    fail(issue === 'ContinuationLedgerEntriesLimit' ? issue : 'InvalidContinuationLedger');
  }
  let value: unknown;
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
    if (!keys(entry, ['name', 'semantic_cid', 'holding_cid', 'key_id', 'state'], ['cleanup_error', 'artifact_cid']) ||
        typeof entry.name !== 'string' || entry.name.length === 0 ||
        entry.name.length > 128 || !entry.name.isWellFormed() ||
        !cid(entry.semantic_cid) || !cid(entry.holding_cid) ||
        !cid(entry.key_id) || !['held', 'retiring', 'retired'].includes(entry.state as string) ||
        (entry.artifact_cid !== undefined &&
          (entry.name !== 'review_projection' || !cid(entry.artifact_cid))) ||
        (entry.cleanup_error !== undefined &&
          (typeof entry.cleanup_error !== 'string' || !entry.cleanup_error.isWellFormed()))) {
      fail('InvalidContinuationLedger');
    }
  }
  // The existing Owner still validates its closed role set, same key, exact
  // holding derivation, current need and actual Store handle. A parsed row or
  // copied CID must not replace any of those nominal/physical obligations.
  return value as ContinuationLedger;
}
