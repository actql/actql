// One exclusively held original allocation spans unlink, directory ACK, native
// close and Store quota settlement. The Store supplies all authority and I/O.
import type {Stats} from 'node:fs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type PhysicalOriginal = Readonly<{device: string; inode: string; byte_count: number}>;
type AllocationState = Readonly<Pick<Stats, 'dev' | 'ino' | 'isFile' | 'nlink' | 'size'>>;
type Handle = Readonly<{
  close(): boolean | void | PromiseLike<boolean | void>;
  stat(): AllocationState | PromiseLike<AllocationState>;
}>;
type Retirement<Original> = Readonly<{
  original: Original;
  settled: boolean;
  admit(): undefined;
  abandon(): Promise<void>;
  unlinkOriginal(): Promise<void>;
  retireAfterDirectoryAck(): Promise<void>;
}>;
type Operations<Original> = Readonly<{
  fence(owner: Retirement<Original>): SynchronousRuntimeData;
  forget(owner: Retirement<Original>): SynchronousRuntimeData;
  pathState(): AllocationState | undefined | PromiseLike<AllocationState | undefined>;
  unlink(): unknown;
  releaseQuota(original: Original): unknown;
}>;

export function createPhysicalRetirementOwner<Original extends PhysicalOriginal>(
  original: Original, handle: Handle, operations: Operations<Original>) {
  let admitted = false, unlinked = false, settled = false;
  let unlinkFlight: Promise<void> | undefined, closePromise: Promise<void> | undefined, retireFlight: Promise<void> | undefined;
  const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
  const closeOriginal = () => {
    operations.fence(owner);
    // Node invalidates FileHandle.fd before its asynchronous close settles.
    // Retain this exact promise forever: a later close() can resolve vacuously
    // after the original rejected, and a numeric FD may already be reused.
    closePromise ??= Promise.resolve().then(() => handle.close()).then(result => {
      if (result === false) fail('PublicationStoreCleanupPending');
    });
    return closePromise;
  };
  const owner: Retirement<Original> = Object.freeze({
    original,
    get settled() { return settled; },
    admit(): undefined {
      if (settled || closePromise !== undefined) fail('PublicationStoreCleanupPending');
      admitted = true;
    },
    async abandon() {
      if (admitted) fail('PublicationStoreCleanupPending');
      await closeOriginal();
      settled = true;
      operations.forget(owner);
    },
    unlinkOriginal() {
      if (unlinked || settled) return Promise.resolve();
      if (unlinkFlight !== undefined) return unlinkFlight;
      unlinkFlight = Promise.resolve().then(async () => {
        if (!admitted || closePromise !== undefined) fail('PublicationStoreCleanupPending');
        const current = await operations.pathState();
        if (current !== undefined && String(current.dev) === original.device &&
            String(current.ino) === original.inode) {
          if (!current.isFile() || current.size !== original.byte_count) {
            fail('PublicationObjectAccountingMismatch');
          }
          await operations.unlink();
        }
        // The pathname can already name a replacement. Only this still-held
        // original proves that its final link retired; never unlink by CID again.
        const held = await handle.stat();
        if (!held.isFile() || held.size !== original.byte_count ||
            String(held.dev) !== original.device || String(held.ino) !== original.inode ||
            held.nlink !== 0) fail('PublicationObjectAccountingMismatch');
        unlinked = true;
      }).finally(() => { unlinkFlight = undefined; });
      return unlinkFlight;
    },
    retireAfterDirectoryAck() {
      if (settled) return Promise.resolve();
      if (retireFlight !== undefined) return retireFlight;
      retireFlight = Promise.resolve().then(async () => {
        if (!admitted || !unlinked) fail('PublicationStoreCleanupPending');
        await closeOriginal();
        // The fence remains through native uncertainty. Retry repeats only the
        // same Store quota original, never a fresh lookup of the current CID.
        await operations.releaseQuota(original);
        settled = true;
        operations.forget(owner);
      }).finally(() => { retireFlight = undefined; });
      return retireFlight;
    },
  });
  return owner;
}
