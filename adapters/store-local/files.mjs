// Trusted local Store implementation. This module handles physical bytes only;
// it cannot issue ActQL completion, schema admission or logical identity proof.
import { mkdtemp, open, lstat, unlink, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';

export class RetainedFileError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const fail = code => { throw new RetainedFileError(code); };
const quantity = n => Number.isSafeInteger(n) && n >= 0;
const bodyOwners = new WeakMap(), storeOwners = new WeakMap();

// Exact installed Store ownership, not content equality or completion authority.
export function localStoreOwnsBody(store, body) {
  const owner = storeOwners.get(store)?.owner;
  return owner !== undefined && bodyOwners.get(body) === owner;
}

export function localRetainedStoreAvailable(store) {
  return storeOwners.get(store)?.available() === true;
}

export function validateLocalStoreConfiguration({ parentDirectory, capacityBytes, maxFrameBytes,
  maxEntries = 1024, maxReadersPerBody = 1, maxReadBufferBytes }) {
  // Pure validation precedes file creation/reservation.
  if (typeof parentDirectory !== 'string' || !parentDirectory.length ||
      !quantity(capacityBytes) || !quantity(maxEntries) || maxEntries === 0 ||
      !quantity(maxFrameBytes) || maxFrameBytes === 0 ||
      maxFrameBytes > 16 * 1024 * 1024 || !quantity(maxReadersPerBody) ||
      maxReadersPerBody === 0) fail('InvalidStoreLimits');
  // Preserve the existing one-reader-per-body default, with an explicit global
  // byte reservation for simultaneous verifier buffers when sharing is enabled.
  const readCapacity = maxReadBufferBytes === undefined ? maxFrameBytes * maxEntries : maxReadBufferBytes;
  if (!quantity(readCapacity)) fail('InvalidStoreLimits');
  return Object.freeze({parentDirectory, capacityBytes, maxFrameBytes, maxEntries,
    maxReadersPerBody, maxReadBufferBytes: readCapacity});
}

export async function createLocalRetainedStore(options) {
  const {parentDirectory, capacityBytes, maxFrameBytes, maxEntries, maxReadersPerBody,
    maxReadBufferBytes} = validateLocalStoreConfiguration(options);
  const directory = await mkdtemp(join(parentDirectory, 'actql-retained-'));
  const entries = new Set();
  const owner = Object.freeze({});
  let remaining = capacityBytes;
  let admittedWriteBytes = 0;
  let uncertainWriteBytes = 0;
  let delegatedWriteBytes = 0;
  let next = 0;
  let closed = false;
  let removed = false;
  let cleanupInFlight;
  let activeReaders = 0, reservedReadBufferBytes = 0;

  const releaseEntry = async entry => {
    if (entry.released) return true;
    if (!entry.revoked || entry.busy || entry.readers) return false;
    if (entry.fd) {
      if (!entry.identity) entry.identity = await entry.fd.stat();
      await entry.fd.close();
      entry.fd = undefined;
    }
    if (entry.created) {
      // Never remove a replacement at our former pathname. Reading uses the
      // opened descriptor, not this pathname; cleanup has its own identity check.
      let current;
      try { current = await lstat(entry.path); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (current) {
        if (!entry.identity || current.ino !== entry.identity.ino ||
            current.dev !== entry.identity.dev || !current.isFile()) fail('RetainedPathReplaced');
        await unlink(entry.path);
      }
      entry.created = false;
    }
    entry.released = true;
    remaining += entry.reservation;
    entry.reservation = 0;
    entries.delete(entry);
    return true;
  };
  const cleanupEntry = entry => {
    if (entry.cleanupInFlight) return entry.cleanupInFlight;
    entry.cleanupInFlight = releaseEntry(entry).finally(() => { entry.cleanupInFlight = undefined; });
    return entry.cleanupInFlight;
  };

  const status = () => Object.freeze({
    capacityBytes,
    reservedBytes: capacityBytes - remaining,
    admittedWriteBytes,
    uncertainWriteBytes,
    delegatedWriteBytes,
    activeReaders,
    reservedReadBufferBytes,
    holdings: [...entries].filter(e => e.sealed && !e.revoked).length,
    cleanupPending: [...entries].some(e => e.revoked && !e.released) || (closed && !removed),
  });

  const reserve = maxBytes => {
    if (closed) fail('StoreClosed');
    if (entries.size >= maxEntries || next >= Number.MAX_SAFE_INTEGER) fail('StoreEntryLimit');
    if (!quantity(maxBytes) || maxBytes > remaining) fail('StoreCapacity');
    remaining -= maxBytes;
    const entry = {
      path: join(directory, `body-${next++}`), reservation: maxBytes,
      fd: undefined, identity: undefined, created: false, opening: false,
      busy: false, readers: 0, revoked: false, released: false, sealed: false,
      bytes: 0, hash: createHash('sha256'), cid: undefined,
      delegation: undefined,
    };
    entries.add(entry);
    const revoke = () => { entry.revoked = true; };
    const active = () => {
      if (closed || entry.revoked || entry.released) fail('RetainedUnavailable');
    };
    const acquireRead = () => {
      active();
      if (entry.readers >= maxReadersPerBody) fail('StoreReaderBusy');
      const bytes = Math.min(maxFrameBytes, Math.max(1, entry.bytes));
      if (bytes > maxReadBufferBytes - reservedReadBufferBytes) fail('StoreReadCapacity');
      entry.readers++; activeReaders++; reservedReadBufferBytes += bytes;
      let released = false;
      return () => {
        if (released) return false;
        released = true;
        entry.readers--; activeReaders--; reservedReadBufferBytes -= bytes;
        return true;
      };
    };
    const cleanupHandle = Object.freeze({
      status: () => Object.freeze({ pending: entry.revoked && !entry.released }),
      retry: () => cleanupEntry(entry),
    });
    const attachCleanup = error => {
      revoke();
      const failure = error instanceof Error ? error : new RetainedFileError('StoreFailure');
      failure.cleanupHandle = cleanupHandle;
      return failure;
    };

    const start = async () => {
      active();
      if (entry.opening || entry.fd || entry.created || entry.sealed) fail('StoreAlreadyStarted');
      entry.opening = true;
      entry.busy = true;
      try {
        entry.fd = await open(entry.path, 'wx+', 0o600);
        entry.created = true;
        entry.identity = await entry.fd.stat();
        active();
      } catch (error) { throw attachCleanup(error); }
      finally { entry.busy = false; }
    };

    const append = async (frame, binary = false) => {
      active();
      if (!entry.fd || entry.sealed || entry.busy) fail('InvalidStoreWriteState');
      if (binary ? !(frame instanceof Uint8Array) : typeof frame !== 'string') fail('InvalidStoreFrame');
      const bytes = binary ? frame.byteLength : Buffer.byteLength(frame, 'utf8');
      if (bytes > maxFrameBytes || bytes > entry.reservation - entry.bytes ||
          !Number.isSafeInteger(admittedWriteBytes + uncertainWriteBytes + delegatedWriteBytes + bytes)) fail('StoreCapacity');
      entry.busy = true;
      // Charge accepted traffic before writing; failure never refunds it. The
      // reservation remains conservative if the write outcome becomes unknown.
      admittedWriteBytes += bytes;
      // Copy bounded bytes before the first await: native producers may reuse
      // their output buffer as soon as the write has been submitted.
      const buffer = binary ? Buffer.from(frame) : Buffer.from(frame, 'utf8');
      try {
        let offset = 0;
        while (offset < buffer.length) {
          active();
          const { bytesWritten } = await entry.fd.write(buffer, offset, buffer.length - offset, entry.bytes + offset);
          if (!bytesWritten) fail('IncompleteStoreWrite');
          offset += bytesWritten;
        }
        entry.hash.update(buffer);
        entry.bytes += bytes;
      } catch (error) { throw attachCleanup(error); }
      finally { entry.busy = false; }
    };

    const seal = async (identity, delegated = false, physical = false) => {
      active();
      if (!entry.fd || entry.sealed || entry.busy) fail('InvalidStoreSealState');
      entry.busy = true;
      try {
        const bytes = physical ? entry.bytes : identity?.bytes;
        const actual = delegated ? undefined : `sha256:${entry.hash.digest('hex')}`;
        const cid = physical ? actual : identity?.cid;
        if (!quantity(bytes) || bytes !== entry.bytes ||
            typeof cid !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(cid)) fail('StoreIdentityMismatch');
        if (!delegated) {
          if (cid !== actual) fail('StoreIdentityMismatch');
        }
        const state = await entry.fd.stat();
        if (!state.isFile() || state.size !== bytes ||
            state.dev !== entry.identity.dev || state.ino !== entry.identity.ino) fail('StoreIdentityMismatch');
        active();
        entry.cid = cid;
        entry.sealed = true;
        remaining += entry.reservation - entry.bytes;
        entry.reservation = entry.bytes;
      } catch (error) { throw attachCleanup(error); }
      finally { entry.busy = false; }
      const body = Object.freeze({
        // Immutable identity of physical bytes only, not an ActQL result claim.
        bytes: entry.bytes, cid: entry.cid,
        available: () => !closed && !entry.revoked && !entry.released,
        close: revoke,
        cleanupHandle,
        delegateRead(session) {
          active();
          if (typeof session !== 'string' || !session.length || session.length > 256) fail('InvalidStoreSession');
          const descriptor = Object.freeze({
            version: 'actql-local-file-read/0.1', session, token: randomUUID(),
            path: entry.path, device: entry.identity.dev, inode: entry.identity.ino,
            bytes: entry.bytes, cid: entry.cid, maxFrameBytes,
          });
          const release = acquireRead();
          let settled = false;
          const settle = () => {
            if (settled) return false;
            settled = true;
            release();
            return true;
          };
          const verifyReport = report => {
            if (settled || !report || report.version !== descriptor.version ||
                report.session !== descriptor.session || report.token !== descriptor.token ||
                report.bytes !== descriptor.bytes || report.cid !== descriptor.cid) fail('ForeignStoreReadReport');
          };
          return Object.freeze({
            descriptor,
            // A verified read can keep the physical holding borrowed while
            // logical admission/consumer work finishes. Verification is not
            // release and does not make a closed body available again.
            verify(report) {
              verifyReport(report);
              active();
              return Object.freeze({bytes: entry.bytes, cid: entry.cid});
            },
            finish(report) {
              verifyReport(report);
              settle();
              active();
              return Object.freeze({ bytes: entry.bytes, cid: entry.cid });
            },
            // Trusted actual process exit or confirmed reader stop only. A
            // cancellation request cannot settle a still-running borrow.
            confirmStopped: settle,
          });
        },
        async consume(accept, signal) {
          active();
          if (typeof accept !== 'function') fail('InvalidStoreReader');
          signal?.throwIfAborted();
          const release = acquireRead();
          try {
            const hash = createHash('sha256');
            const buffer = Buffer.alloc(Math.min(maxFrameBytes, Math.max(1, entry.bytes)));
            let position = 0;
            while (position < entry.bytes) {
              active();
              signal?.throwIfAborted();
              let bytesRead;
              try {
                ({ bytesRead } = await entry.fd.read(buffer, 0, Math.min(buffer.length, entry.bytes - position), position));
              } catch (error) { throw attachCleanup(error); }
              if (!bytesRead) throw attachCleanup(new RetainedFileError('RetainedBodyTruncated'));
              active();
              signal?.throwIfAborted();
              hash.update(buffer.subarray(0, bytesRead));
              // Borrowed bytes valid until this awaited callback resolves.
              await accept(buffer.subarray(0, bytesRead));
              active();
              signal?.throwIfAborted();
              position += bytesRead;
            }
            let state;
            try { state = await entry.fd.stat(); }
            catch (error) { throw attachCleanup(error); }
            if (state.size !== entry.bytes || `sha256:${hash.digest('hex')}` !== entry.cid) {
              throw attachCleanup(new RetainedFileError('RetainedBodyChanged'));
            }
            active();
            signal?.throwIfAborted();
            return Object.freeze({ bytes: position, cid: entry.cid });
          } finally { release(); }
        },
      });
      bodyOwners.set(body, owner);
      return body;
    };

    // Trusted local-process wiring only. The Host owns the inode/reservation;
    // a selected execution process writes directly, without relaying body bytes
    // through the control channel. Neither descriptor nor report is completion
    // evidence. Reports must arrive over that process's exact owned IPC session.
    const delegate = session => {
      active();
      if (typeof session !== 'string' || !session.length || session.length > 256) fail('InvalidStoreSession');
      if (!entry.fd || entry.busy || entry.sealed || entry.bytes || entry.delegation) fail('InvalidStoreWriteState');
      if (!Number.isSafeInteger(admittedWriteBytes + uncertainWriteBytes + delegatedWriteBytes + entry.reservation)) fail('StoreCapacity');
      const descriptor = Object.freeze({
        version: 'actql-local-file/0.1', session, token: randomUUID(),
        path: entry.path, device: entry.identity.dev, inode: entry.identity.ino,
        maxBytes: entry.reservation, maxFrameBytes,
      });
      entry.delegation = descriptor;
      delegatedWriteBytes += descriptor.maxBytes;
      entry.busy = true;
      return descriptor;
    };
    const finishDelegated = async report => {
      const lease = entry.delegation;
      if (!lease || !entry.busy || entry.sealed || !report ||
          report.session !== lease.session || report.token !== lease.token ||
          report.version !== lease.version ||
          !quantity(report.bytes) || report.bytes > lease.maxBytes ||
          typeof report.cid !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(report.cid)) fail('ForeignStoreReport');
      // The installed writer returns only after closing its writable descriptor.
      // Preserve consumed traffic even if subsequent holding admission fails.
      if (!Number.isSafeInteger(admittedWriteBytes + report.bytes)) fail('StoreCapacity');
      admittedWriteBytes += report.bytes;
      delegatedWriteBytes -= lease.maxBytes;
      entry.bytes = report.bytes;
      entry.busy = false;
      entry.delegation = undefined;
      return seal({ bytes: report.bytes, cid: report.cid }, true);
    };
    const confirmDelegatedStopped = () => {
      // Host-only actual process exit/confirmed writer stop, never cancellation.
      if (!entry.delegation) return false;
      // No terminal byte receipt survived. Charge the granted upper bound in a
      // separate conservative counter; never report unknown traffic as zero.
      uncertainWriteBytes += entry.delegation.maxBytes;
      delegatedWriteBytes -= entry.delegation.maxBytes;
      entry.delegation = undefined;
      entry.busy = false;
      revoke();
      return true;
    };
    return Object.freeze({ start, append: text => append(text), appendBytes: bytes => append(bytes, true),
      seal: identity => seal(identity),
      // Physical-byte proof only. Logical content/conversion and completion
      // still require their own exact, installed verifier.
      sealPhysical: () => seal(undefined, false, true),
      delegate, finishDelegated, confirmDelegatedStopped,
      cancel: revoke, cleanupHandle });
  };

  const store = Object.freeze({
    reserve, status,
    close() { closed = true; for (const entry of entries) entry.revoked = true; },
    cleanup() {
      if (cleanupInFlight) return cleanupInFlight;
      cleanupInFlight = (async () => {
        const errors = [];
        for (const entry of entries) {
          try { await cleanupEntry(entry); }
          catch (error) { errors.push(error); }
        }
        if (closed && !entries.size && !removed) {
          try { await rmdir(directory); removed = true; }
          catch (error) { errors.push(error); }
        }
        if (errors.length) throw new AggregateError(errors, 'Retained store cleanup failed');
        return !status().cleanupPending;
      })().finally(() => { cleanupInFlight = undefined; });
      return cleanupInFlight;
    },
  });
  storeOwners.set(store, {owner, available: () => !closed});
  return store;
}
