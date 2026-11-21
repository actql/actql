import {constants} from 'node:fs';
import type {BigIntStats} from 'node:fs';
import {lstat, open} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';

type MetadataClose = () => unknown;
type MetadataStatus = Readonly<{pending: boolean}>;

const originalApply = Reflect.apply;

export class PublicationStoreError extends Error {
  declare code: string;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

export const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw new PublicationStoreError(code, cause);
};
export const quantity = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;

export const exactKeys = <Key extends string>(value: unknown, keys: readonly Key[]):
  value is Record<Key, unknown> => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export async function readBounded(path: Parameters<typeof open>[0], maximum: unknown,
  closed?: () => void, signal?: AbortSignal, ownerOnly = false, readDemand?: (size: number) => undefined) {
  if (!quantity(maximum)) {
    fail('InvalidPublicationStoreObject');
  }
  if (signal !== undefined && !(signal instanceof AbortSignal)) {
    fail('InvalidPublicationMetadataSignal');
  }
  // Pin the original allocation before allocating its bounded output. A
  // nonblocking open also refuses a raced-in FIFO without waiting for a writer.
  let handle: FileHandle;
  try {
    signal?.throwIfAborted();
    handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW |
      constants.O_NONBLOCK);
  } catch (error) {
    closed?.(); // No original FD was acquired.
    throw error;
  }
  let readFailure: unknown;
  let readFailed = false;
  let originalClose: MetadataClose | undefined;
  const captureClose = () => {
    if (originalClose !== undefined) return;
    const method = handle.close;
    if (typeof method !== 'function') fail('PublicationMetadataReaderCleanupPending');
    originalClose = method;
  };
  try {
    captureClose();
    signal?.throwIfAborted();
    const before = await handle.stat({bigint: true});
    signal?.throwIfAborted();
    if (!before.isFile() || before.size < 0n ||
        before.size > BigInt(maximum)) {
      fail('InvalidPublicationStoreObject');
    }
    // The installation key's existing owner-only rule must hold on THIS FD,
    // not only on a pathname observed before its asynchronous acquisition.
    if (ownerOnly && (before.mode & 0o077n) !== 0n) {
      fail('PrivateEvidenceKeyExposed');
    }
    const sameFile = (state: BigIntStats) => state.isFile() &&
      state.dev === before.dev && state.ino === before.ino &&
      state.size === before.size && state.mtimeNs === before.mtimeNs &&
      state.ctimeNs === before.ctimeNs;
    if (!sameFile(await lstat(path, {bigint: true}))) {
      fail('InvalidPublicationStoreObject');
    }
    signal?.throwIfAborted();
    const size = Number(before.size);
    // The SAME original FD supplies actual demand before output/text/JSON.
    // A refused installed reservation cannot allocate and then fall back.
    if (readDemand !== undefined && (typeof readDemand !== 'function' ||
        readDemand(size) !== undefined)) fail('InvalidPublicationMetadataDemand');
    // Avoid pooled backing and growth/concatenation. The one-byte probe is a
    // separate bounded allocation; neither buffer is a byte-capacity grant.
    const bytes = Buffer.allocUnsafeSlow(size);
    let offset = 0;
    while (offset < size) {
      signal?.throwIfAborted();
      const {bytesRead} = await handle.read(bytes, offset, size - offset, offset);
      signal?.throwIfAborted();
      if (!Number.isSafeInteger(bytesRead) || bytesRead <= 0 ||
          bytesRead > size - offset) {
        fail('InvalidPublicationStoreObject');
      }
      offset += bytesRead;
    }
    signal?.throwIfAborted();
    const probe = Buffer.allocUnsafeSlow(1);
    const {bytesRead} = await handle.read(probe, 0, 1, size);
    signal?.throwIfAborted();
    if (bytesRead !== 0) fail('InvalidPublicationStoreObject');
    const after = await handle.stat({bigint: true});
    signal?.throwIfAborted();
    if (ownerOnly && (after.mode & 0o077n) !== 0n) {
      fail('PrivateEvidenceKeyExposed');
    }
    if (!sameFile(after)) fail('InvalidPublicationStoreObject');
    const pathAfter = await lstat(path, {bigint: true});
    signal?.throwIfAborted();
    if (!sameFile(pathAfter)) fail('InvalidPublicationStoreObject');
    return bytes;
  } catch (error) {
    readFailed = true;
    readFailure = error;
    throw error;
  } finally {
    try {
      captureClose();
      if (await originalApply(originalClose!, handle, []) === false) fail('PublicationMetadataReaderCleanupPending');
    } catch (closeFailure) {
      // Retain exactly this failed FD, not a pathname reopen or another read.
      // As for the existing object reader, the original caller's reservation
      // and custody stay live until confirmed close. This control/frame and
      // any escaped error are part of the original funded read inventory.
      let original: FileHandle | undefined = handle;
      let closeOriginal = originalClose;
      let retire = closed;
      let flight: Promise<MetadataStatus> | undefined;
      const status = () => Object.freeze({pending: original !== undefined});
      const cleanup: Readonly<{status(): MetadataStatus; retry(): Promise<MetadataStatus>}> = Object.freeze({
        status,
        retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(() => {
            // Retry the successfully captured original only. If its getter
            // never yielded a method, custody stays with this same handle.
            if (closeOriginal === undefined) {
              const method = original!.close;
              if (typeof method !== 'function') fail('PublicationMetadataReaderCleanupPending');
              closeOriginal = method;
            }
            return originalApply(closeOriginal, original, []);
          }).then(result => {
            if (result === false) fail('PublicationMetadataReaderCleanupPending');
            original = closeOriginal = undefined;
            const acknowledge = retire;
            retire = undefined;
            acknowledge?.();
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        },
      });
      const primary = readFailed ? readFailure : closeFailure;
      let failure;
      try {
        failure = primary !== null && typeof primary === 'object' &&
          Object.isExtensible(primary) && (primary as {cleanupHandle?: unknown}).cleanupHandle === undefined &&
          ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
            const field = Object.getOwnPropertyDescriptor(primary, name);
            return field === undefined || field.writable === true;
          })
          ? primary : new Error('PublicationMetadataReaderCleanupPending', {cause: primary});
        // Define own data fields: inherited setters can silently discard an
        // assignment even on an ordinary extensible Error subclass. Preserve
        // existing writable own-field attributes and ordinary error identity.
        Object.defineProperties(failure, {
          cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
            {writable: true, enumerable: true, configurable: true}), value: cleanup},
          cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
            {writable: true, enumerable: true, configurable: true}), value: true},
          cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
            {writable: true, enumerable: true, configurable: true}), value: closeFailure},
        });
      } catch {
        // Readonly fields/accessors must not mask the original read failure
        // or discard the same FD. The fresh wrapper owns diagnostics only.
        failure = new Error('PublicationMetadataReaderCleanupPending', {cause: primary});
        Object.defineProperties(failure, {
          cleanupHandle: {value: cleanup, writable: true, enumerable: true, configurable: true},
          cleanupPending: {value: true, writable: true, enumerable: true, configurable: true},
          cleanupError: {value: closeFailure, writable: true, enumerable: true, configurable: true},
        });
      }
      throw failure;
    }
    closed?.();
  }
}

export async function syncDirectoryPath(path: Parameters<typeof open>[0]) {
  const directory = await open(path, constants.O_RDONLY);
  let syncFailure: unknown, syncFailed = false;
  try { await directory.sync(); }
  catch (cause) { syncFailed = true; syncFailure = cause; }
  try {
    if ((await directory.close() as unknown) === false) fail('PublicationDirectorySyncCleanupPending');
  } catch (closeFailure) {
    // Keep this already-acquired FD, not a pathname reopen or repeated sync.
    // Its initialization/publication caller still owns all surrounding duty.
    let original: FileHandle | undefined = directory, flight: Promise<MetadataStatus> | undefined;
    const status = () => Object.freeze({pending: original !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      if (original === undefined) return Promise.resolve(status());
      flight = Promise.resolve().then(() => original!.close() as Promise<unknown>).then(result => {
        if (result === false) fail('PublicationDirectorySyncCleanupPending');
        original = undefined;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    const primary = syncFailed ? syncFailure : closeFailure;
    let failure;
    try {
      failure = primary !== null && typeof primary === 'object' &&
        Object.isExtensible(primary) && (primary as {cleanupHandle?: unknown}).cleanupHandle === undefined &&
        ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
          const field = Object.getOwnPropertyDescriptor(primary, name);
          return field === undefined || field.writable === true;
        }) ? primary : new Error('PublicationDirectorySyncCleanupPending', {cause: primary});
      Object.defineProperties(failure, {
        cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
          {writable: true, enumerable: true, configurable: true}), value: cleanup},
        cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
          {writable: true, enumerable: true, configurable: true}), value: true},
        cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
          {writable: true, enumerable: true, configurable: true}), value: closeFailure},
      });
      if (failure !== primary) Object.defineProperty(failure, 'primaryFailure', {value: primary});
    } catch {
      // Presentation must never mask raw thrown values or original FD duty.
      failure = Object.assign(new Error('PublicationDirectorySyncCleanupPending', {cause: primary}),
        {code: 'PublicationDirectorySyncCleanupPending', primaryFailure: primary,
          cleanupHandle: cleanup, cleanupPending: true, cleanupError: closeFailure});
    }
    throw failure;
  }
  if (syncFailed) throw syncFailure;
}

export const localDurability = Object.freeze({syncDirectory: syncDirectoryPath});

export async function writeExclusive(path: Parameters<typeof open>[0], bytes: Uint8Array) {
  const handle = await open(path, constants.O_CREAT | constants.O_EXCL |
    constants.O_WRONLY, 0o600);
  try {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const {bytesWritten} = await handle.write(
        bytes, offset, bytes.byteLength - offset, offset,
      );
      if (bytesWritten === 0) fail('IncompletePublicationWrite');
      offset += bytesWritten;
    }
    await handle.sync();
  } finally {
    await handle.close();
  }
}

type OpeningFailureCause = {
  code?: unknown;
  primaryFailure?: unknown;
  cleanupHandle?: Readonly<{status(): Readonly<{pending?: unknown}>; retry(): unknown}>;
};
type OpeningCleanupFailure = Error & {
  code?: unknown;
  primaryFailure?: unknown;
  cleanupPending?: true;
  cleanupError?: unknown;
  cleanupHandle?: Readonly<{status(): MetadataStatus; retry(): Promise<MetadataStatus>}>;
};

// An opener can fail after acquiring the existing Store owner but before it
// returns a Store. Keep that SAME ownership and any failed physical reader;
// retry only cleanup, never reopen initialization or invent completed custody.
export async function retainStoreOpeningFailure(cause: unknown,
  ownership: {release(): unknown} | undefined, key: Uint8Array | undefined) {
  let original = ownership;
  const reader = (cause as OpeningFailureCause | null | undefined)?.cleanupHandle;
  let flight: Promise<MetadataStatus> | undefined, cleanupError: unknown;
  const status = () => Object.freeze({pending: original !== undefined ||
    reader?.status().pending === true});
  const retry = () => {
    if (flight !== undefined) return flight;
    if (!status().pending) { key?.fill(0); return Promise.resolve(status()); }
    flight = Promise.resolve().then(async () => {
      if (reader?.status().pending) {
        await reader.retry();
        if (reader.status().pending) fail('PublicationStoreCleanupPending');
      }
      if (original !== undefined) {
        const released = await original.release();
        // Absence/false is not proof of this opener's successful cleanup.
        if (released !== true) fail('PublicationStoreOwnershipLost');
        original = undefined;
      }
      key?.fill(0);
      return status();
    }).finally(() => { flight = undefined; });
    return flight;
  };
  try { await retry(); }
  catch (error) { cleanupError = error; }
  if (!status().pending) return cause;
  const failure: OpeningCleanupFailure = new Error('PublicationStoreOpeningCleanupPending', {cause});
  failure.code = (cause as OpeningFailureCause | null | undefined)?.code ?? 'PublicationStoreOpeningCleanupPending';
  failure.primaryFailure = cause !== null && typeof cause === 'object' &&
    Object.hasOwn(cause, 'primaryFailure') ? (cause as OpeningFailureCause).primaryFailure : cause;
  failure.cleanupPending = true;
  failure.cleanupError = cleanupError;
  failure.cleanupHandle = Object.freeze({status, retry});
  return failure;
}
