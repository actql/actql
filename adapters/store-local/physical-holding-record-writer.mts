import {randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import {link, open, unlink} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fail, PublicationStoreError} from './publication-store-io.mjs';

type CleanupStatus = Readonly<{pending: boolean}>;
type RecordWriterCleanup = Readonly<{
  status(): CleanupStatus;
  retry(): Promise<CleanupStatus>;
}>;
type ActivePhysicalRecordWriter = {
  cleanup: RecordWriterCleanup | undefined;
  failed: boolean;
};
type DirectorySync = (path: string) => unknown;
type RetainedRecordWriter = {
  writers: Set<ActivePhysicalRecordWriter>;
  writer: ActivePhysicalRecordWriter;
  temporary: string;
  directory: string;
  syncDirectory: DirectorySync;
  finalNameAcknowledged: boolean;
};
type PhysicalRecordHandle = Pick<FileHandle, 'write' | 'sync'> & {
  close(): Promise<boolean | void>;
};
type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RetainedWriteFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: RecordWriterCleanup;
};

export function createPhysicalHoldingRecordWriter(
  stagingDirectory: string, syncDirectory: DirectorySync,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
) {
  return async (path: string, bytes: Buffer, exclusive = true, finalDirectory?: string) => {
    // Existing holding publication retains its exclusive preparation fence.
    // Independent prepared-object custodies historically write concurrently;
    // they share this same Store's FD duties without a new serialization owner.
    if (exclusive && activePhysicalRecordWriters.size !== 0) fail('PublicationStoreCleanupPending');
    // A failed duty can outlive its payload reservation. Refuse another
    // metadata FD before acquisition until that original duty actually retires;
    // healthy in-flight writes are not a serialization fence.
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    const temporary = resolve(stagingDirectory, `object-${randomUUID()}`);
    let handle: PhysicalRecordHandle | undefined;
    let flight: Promise<CleanupStatus> | undefined;
    const writer: ActivePhysicalRecordWriter = {cleanup: undefined, failed: false};
    activePhysicalRecordWriters.add(writer);
    let original: RetainedRecordWriter | undefined = {writers: activePhysicalRecordWriters, writer, temporary,
      directory: stagingDirectory, syncDirectory, finalNameAcknowledged: false};
    const status = () => Object.freeze({pending: original !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      if (!status().pending) return Promise.resolve(status());
      flight = Promise.resolve().then(async () => {
        if (handle !== undefined) {
          if (await handle.close() === false) fail('PublicationStoreCleanupPending');
          handle = undefined;
        }
        try { await unlink(original!.temporary); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        // A real final-name ACK retains these same synced bytes. Its removed
        // temporary alias is not another durable allocation; exclusive open
        // recovery already removes a crash-resurrected staging alias. Failed
        // publication and unselected holding writers keep their original ACK.
        if (!original!.finalNameAcknowledged) {
          await original!.syncDirectory(original!.directory);
        }
        original!.writers.delete(original!.writer);
        original = undefined;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    try {
      handle = await open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const {bytesWritten} = await handle.write(bytes, offset, bytes.byteLength - offset, offset);
        if (!Number.isSafeInteger(bytesWritten) || bytesWritten <= 0 ||
            bytesWritten > bytes.byteLength - offset) fail('IncompletePublicationWrite');
        offset += bytesWritten;
      }
      await handle.sync();
      if (await handle.close() === false) fail('PublicationStoreCleanupPending');
      handle = undefined;
      // Final names are exclusive links to complete, synced, closed bytes.
      // The containing holding directory still needs its original separate
      // durability ACK before prepared ownership can be adopted.
      await link(temporary, path);
      if (finalDirectory !== undefined) {
        await syncDirectory(finalDirectory);
        original.finalNameAcknowledged = true;
      }
      writer.cleanup = cleanup;
      await cleanup.retry();
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary) as RetainedWriteFailure;
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };
}
