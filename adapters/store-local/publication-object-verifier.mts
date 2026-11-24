import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import type {Stats} from 'node:fs';
import {lstat, open} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {fail, quantity} from './publication-store-io.mjs';

export type PhysicalReadHandle = Pick<FileHandle, 'read' | 'stat'> & {close(): Promise<void | false>};
export type ReadCleanupStatus = Readonly<{pending: boolean}>;
type ReaderCleanup = Readonly<{
  status(): ReadCleanupStatus;
  retry(): Promise<ReadCleanupStatus>;
}>;
export type SemanticReader = {
  cleanup: ReaderCleanup | undefined;
  failure?: unknown;
};
export type ReadFailureCarrier = {
  cleanupHandle?: ReaderCleanup;
  cleanupPending?: boolean;
  cleanupError?: unknown;
};
type CodedCause = Readonly<{code?: unknown}> | null | undefined;

export function createPublicationObjectVerifier(
  configuration: Readonly<{maxObjectBytes: number}>,
  objectPath: (cid: unknown) => string,
  cidHex: (cid: unknown) => string,
  active: () => unknown,
  activeSemanticReaders: Set<SemanticReader>,
  physicalContentReadWindowBytes: number,
) {
  return async <Cid,>(cid: Cid, readDemand?: (window: number) => unknown) => {
    const path = objectPath(cid);
    active();
    // Borrow the same Store's existing private reader-duty collection. The
    // verifier owns its FD independently of an enclosing semantic/Result read.
    const reader: SemanticReader = {cleanup: undefined, failure: undefined};
    activeSemanticReaders.add(reader);
    let handle: PhysicalReadHandle | undefined;
    let readFailure: unknown;
    let readFailed = false;
    try {
      let state: Stats;
      try { state = await lstat(path); }
      catch (error) {
        if ((error as CodedCause)?.code === 'ENOENT') fail('PublicationObjectMissing');
        throw error;
      }
      if (!state.isFile() || !quantity(state.size) ||
          state.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationStoreObject');
      }
      handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW |
        constants.O_NONBLOCK);
      const hash = createHash('sha256');
      let bytes = 0;
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes ||
          before.dev !== state.dev || before.ino !== state.ino ||
          before.size !== state.size || before.mtimeMs !== state.mtimeMs) {
        fail('InvalidPublicationStoreObject');
      }
      // This same-FD verifier keeps one explicit overflow-probe byte so growth
      // is still refused before hashing it. Fund W+1 acquisition separately;
      // neither the accepted W nor a later clamp pays for that sentinel.
      // Nothing escapes this verifier's synchronous hash update. Reuse this
      // dedicated backing for short reads instead of a stream's shrink copy
      // or queued next backing; only the same original read is in flight.
      const window = before.size < physicalContentReadWindowBytes ? before.size + 1 : physicalContentReadWindowBytes;
      if (readDemand !== undefined && (typeof readDemand !== 'function' ||
          readDemand(window) !== undefined)) fail('InvalidPublicationMetadataDemand');
      const buffer = Buffer.allocUnsafeSlow(window);
      for (;;) {
        const remaining = before.size - bytes;
        const requested = remaining < buffer.byteLength ? remaining + 1 : buffer.byteLength;
        const {bytesRead} = await handle.read(buffer, 0, requested, bytes);
        if (!quantity(bytesRead) || bytesRead > requested) fail('PublicationObjectCorrupt');
        if (bytesRead === 0) break;
        // Refuse the original overflow probe before hashing any of that
        // read's bytes. The single backing includes its separately funded
        // sentinel even for an initially empty object.
        if (bytesRead > remaining ||
            bytesRead > configuration.maxObjectBytes - bytes) {
          fail('PublicationObjectCorrupt');
        }
        const chunk = bytesRead === buffer.byteLength ? buffer : buffer.subarray(0, bytesRead);
        hash.update(chunk);
        bytes += bytesRead;
      }
      const after = await handle.stat();
      if (!before.isFile() || !after.isFile() || before.dev !== after.dev ||
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
      if (handle === undefined) {
        activeSemanticReaders.delete(reader); // No original FD was acquired.
      } else {
        try {
          if (await handle.close() === false) fail('PublicationStoreCleanupPending');
          activeSemanticReaders.delete(reader);
        } catch (closeFailure) {
          // Keep the original FD/primary inside this Store before decorating
          // an outward failure. Retry only close; never verify or open again.
          let original: PhysicalReadHandle | undefined = handle;
          let flight: Promise<ReadCleanupStatus> | undefined;
          const status = () => Object.freeze({pending: original !== undefined});
          const cleanup = Object.freeze({status, retry() {
            if (flight !== undefined) return flight;
            if (original === undefined) return Promise.resolve(status());
            flight = Promise.resolve().then(async () => {
              if (await original!.close() === false) fail('PublicationStoreCleanupPending');
              original = undefined;
              activeSemanticReaders.delete(reader);
              reader.cleanup = reader.failure = undefined;
              return status();
            }).finally(() => { flight = undefined; });
            return flight;
          }});
          const primary = readFailed ? readFailure : closeFailure;
          reader.cleanup = cleanup;
          reader.failure = primary;
          let failure: ReadFailureCarrier;
          try {
            failure = (primary !== null && typeof primary === 'object' &&
              Object.isExtensible(primary) && (primary as ReadFailureCarrier).cleanupHandle === undefined &&
              ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
                const field = Object.getOwnPropertyDescriptor(primary, name);
                return field === undefined || field.writable === true;
              })
              ? primary : new Error('PublicationStoreCleanupPending', {cause: primary})) as ReadFailureCarrier;
            failure.cleanupHandle = cleanup;
            failure.cleanupPending = true;
            failure.cleanupError = closeFailure;
          } catch {
            failure = new Error('PublicationStoreCleanupPending', {cause: primary}) as Error & ReadFailureCarrier;
            failure.cleanupHandle = cleanup;
            failure.cleanupPending = true;
            failure.cleanupError = closeFailure;
          }
          reader.failure = failure;
          throw failure;
        }
      }
    }
  };
}
