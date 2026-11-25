import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {open} from 'node:fs/promises';
import type {PhysicalReadHandle, ReadCleanupStatus, ReadFailureCarrier} from './publication-object-verifier.mjs';
import {fail, quantity} from './publication-store-io.mjs';

export function createPublicationObjectConsumer(
  configuration: Readonly<{maxObjectBytes: number}>,
  objectPath: (cid: unknown) => string,
  cidHex: (cid: unknown) => string,
  active: () => unknown,
  physicalContentReadWindowBytes: number,
) {
  const consumeObject = async <Cid,>(
    cid: Cid, accept: (piece: Buffer) => unknown, closed?: () => unknown,
  ) => {
    let handle: PhysicalReadHandle;
    try {
      active();
      if (typeof accept !== 'function') fail('InvalidPublicationObjectConsumer');
      const path = objectPath(cid);
      handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    } catch (error) {
      closed?.(); // No original FD was acquired.
      throw error;
    }
    const hash = createHash('sha256');
    let bytes = 0;
    let readFailure: unknown;
    let readFailed = false;
    try {
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationStoreObject');
      }
      // One dedicated backing per bounded piece, filled on this SAME FD.
      // A ReadStream can allocate a second backing for a short read and read
      // ahead while accept is pending. Here short reads fill the original
      // piece, and no following piece is acquired until its callback returns.
      // Do not reuse a delivered backing: the consumer can retain its alias.
      while (bytes < before.size) {
        const buffer = Buffer.allocUnsafeSlow(Math.min(physicalContentReadWindowBytes, before.size - bytes));
        let filled = 0;
        while (filled < buffer.byteLength) {
          const requested = buffer.byteLength - filled;
          const {bytesRead} = await handle.read(buffer, filled, requested, bytes + filled);
          if (!quantity(bytesRead) || bytesRead > requested) fail('PublicationObjectCorrupt');
          if (bytesRead === 0) break;
          filled += bytesRead;
        }
        if (filled === 0) break;
        // Preserve delivery of an original prefix on truncation, followed by
        // the existing size/hash/version refusal. subarray adds only a view;
        // it neither copies a short piece nor proves retirement of its backing.
        const chunk = filled === buffer.byteLength ? buffer : buffer.subarray(0, filled);
        hash.update(chunk);
        await accept(chunk);
        bytes += filled;
        if (filled < buffer.byteLength) break;
      }
      const after = await handle.stat();
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || bytes !== after.size ||
          hash.digest('hex') !== cidHex(cid)) {
        fail('PublicationObjectCorrupt');
      }
      return Object.freeze({cid, bytes});
    } catch (error) {
      readFailure = error;
      readFailed = true;
      throw error;
    } finally {
      try {
        if (await handle.close() === false) fail('PublicationStoreCleanupPending');
        closed?.();
      } catch (closeFailure) {
        // A view of this SAME original read/FD, not a replacement reader,
        // cleanup owner or proof of successful consumption. Keep its existing
        // active-reader count until close succeeds; never reopen by path.
        let original: PhysicalReadHandle | undefined = handle;
        let retire = closed;
        let flight: Promise<ReadCleanupStatus> | undefined;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({
          status,
          retry() {
            if (flight !== undefined) return flight;
            if (original === undefined) return Promise.resolve(status());
            flight = Promise.resolve().then(async () => {
              if (await original!.close() === false) fail('PublicationStoreCleanupPending');
              original = undefined;
              const acknowledge = retire;
              retire = undefined;
              acknowledge?.();
              return status();
            }).finally(() => { flight = undefined; });
            return flight;
          },
        });
        const primary = readFailed ? readFailure : closeFailure;
        // Preserve ordinary mutable failures, but never let existing readonly
        // fields or hostile accessors discard the same original FD duty.
        let failure: object;
        try {
          failure = primary !== null && typeof primary === 'object' &&
            Object.isExtensible(primary) && (primary as ReadFailureCarrier).cleanupHandle === undefined &&
            ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
              const field = Object.getOwnPropertyDescriptor(primary, name);
              return field === undefined || field.writable === true;
            })
            ? primary : new Error('PublicationObjectReaderCleanupPending', {cause: primary});
          // Ordinary inherited setters may silently discard assignments. Own
          // data fields preserve the same FD duty and mutable primary identity.
          Object.defineProperties(failure, {
            cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
              {writable: true, enumerable: true, configurable: true}), value: cleanup},
            cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
              {writable: true, enumerable: true, configurable: true}), value: true},
            cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
              {writable: true, enumerable: true, configurable: true}), value: closeFailure},
          });
        } catch {
          failure = new Error('PublicationObjectReaderCleanupPending', {cause: primary});
          Object.defineProperties(failure, {
            cleanupHandle: {value: cleanup, writable: true, enumerable: true, configurable: true},
            cleanupPending: {value: true, writable: true, enumerable: true, configurable: true},
            cleanupError: {value: closeFailure, writable: true, enumerable: true, configurable: true},
          });
        }
        throw failure;
      }
    }
  };

  return consumeObject;
}
