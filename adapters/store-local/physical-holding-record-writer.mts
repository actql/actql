import {randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import {link, lstat, open, readdir, unlink} from 'node:fs/promises';
import type {Stats} from 'node:fs';
import type {FileHandle} from 'node:fs/promises';
import {resolve} from 'node:path';
import {cidPattern, fail, PublicationStoreError, readBounded} from './publication-store-io.mjs';
import type {createPhysicalHoldingRecordReader, PhysicalHoldingRecord, ReadPhysicalHolding, SelectedPhysicalHoldingRecord}
  from './physical-holding-record-reader.mjs';
import type {createPreparedHolderRegistry} from './prepared-holder-owner.mjs';

type CleanupStatus = Readonly<{pending: boolean}>;
type RecordWriterCleanup = Readonly<{
  status(): CleanupStatus;
  retry(): Promise<CleanupStatus>;
}>;
export type ActivePhysicalRecordWriter = {
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

type HoldingDeletionStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type HoldingDeletionCleanup = Readonly<{
  status(): HoldingDeletionStatus;
  retry(): Promise<HoldingDeletionStatus>;
}>;
type ConfirmationChild = Readonly<{retry?: unknown; status?: unknown}>;
type ConfirmationCause = Readonly<{cleanupHandle?: ConfirmationChild; outcome?: unknown}> | null | undefined;
type ConfirmationFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  outcome?: 'unknown';
  cleanupHandle: RecordWriterCleanup;
};
type PreparedStatusHandle = Readonly<{status(): Readonly<{pending: boolean}>}>;
type PreparedOriginal = NonNullable<ReturnType<ReturnType<typeof createPreparedHolderRegistry>["original"]>>;
type PreparedOwners<Original extends PreparedOriginal> = Pick<ReturnType<typeof createPreparedHolderRegistry<Original>>,
  'select' | 'original' | 'retainTransfer' | 'pendingTransfer' | 'finishTransfer'>;
type PreparedGroup = Readonly<{holders: ReadonlySet<unknown>; commitOwners: ReadonlySet<unknown>}>;
type HoldingRemoval = Readonly<{unlinkOriginal(): Promise<unknown>}>;
type HoldingLifecyclePorts<Original extends PreparedOriginal, Removal extends HoldingRemoval> = Readonly<{
  active(): unknown;
  cidHex(value: unknown): string;
  admitPhysicalHolding: ReturnType<typeof createPhysicalHoldingRecordReader>['admitPhysicalHolding'];
  readPhysicalHoldingAt: ReturnType<typeof createPhysicalHoldingRecordReader>['readPhysicalHoldingAt'];
  readPhysicalHolding(holdingCid: unknown): ReturnType<ReadPhysicalHolding>;
  readPhysicalHoldingDeletion(holdingCid: unknown): ReturnType<ReadPhysicalHolding>;
  verifyPhysicalHoldingObjects(record: PhysicalHoldingRecord): Promise<unknown>;
  preparedObjectOwners: PreparedOwners<Original>;
  preparedObjects: ReadonlyMap<unknown, PreparedGroup>;
  confirmPreparedMaterials(cids: readonly unknown[]): Promise<unknown>;
  adoptPreparedObjects(selected: readonly Readonly<Original>[]): Promise<unknown>;
  writePhysicalHoldingRecord: ReturnType<typeof createPhysicalHoldingRecordWriter>;
  physicalHoldingPath(holdingCid: unknown): string;
  physicalHoldingDeletionPath(holdingCid: unknown): string;
  objectPath(cid: unknown): string;
  syncDirectory(path: string): unknown;
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>;
  activePhysicalHoldingReaders: ReadonlyMap<string, number>;
  retainPhysicalHoldingReader(holdingCid: string): () => void;
  pendingPhysicalHoldingDeletions: Map<string, HoldingDeletionCleanup>;
  materialRetentionCurrent(): Promise<unknown>;
  retainMaterialOperation(operation: Promise<unknown>): void;
  materialHasLiveReference(cid: unknown): Promise<boolean>;
  rememberPhysicalRemoval(cid: unknown, bytes: number, state?: Stats): Promise<Removal | undefined>;
  confirmPhysicalRemovals(removals: ReadonlyMap<unknown, Removal>): Promise<unknown>;
}>;

export function createPhysicalHoldingLifecycle<Original extends PreparedOriginal, Removal extends HoldingRemoval>(
  configuration: Readonly<{maxObjectBytes: number}>,
  physicalHoldingsDirectory: string, physicalHoldingDeletionsDirectory: string,
  {active, cidHex, admitPhysicalHolding, readPhysicalHoldingAt, readPhysicalHolding, readPhysicalHoldingDeletion,
    verifyPhysicalHoldingObjects, preparedObjectOwners, preparedObjects, confirmPreparedMaterials, adoptPreparedObjects,
    writePhysicalHoldingRecord, physicalHoldingPath, physicalHoldingDeletionPath, objectPath, syncDirectory,
    activePhysicalRecordWriters, activePhysicalHoldingReaders, retainPhysicalHoldingReader, pendingPhysicalHoldingDeletions,
    materialRetentionCurrent, retainMaterialOperation, materialHasLiveReference, rememberPhysicalRemoval,
    confirmPhysicalRemovals}: HoldingLifecyclePorts<Original, Removal>,
) {
  const commitPhysicalHoldingInternal = async (
    value: unknown, prepared: readonly PreparedStatusHandle[], borrowedHoldingCids: readonly string[],
  ) => {
    active();
    if (!Array.isArray(borrowedHoldingCids) ||
        new Set(borrowedHoldingCids).size !== borrowedHoldingCids.length ||
        borrowedHoldingCids.some(cid => !cidPattern.test(cid))) {
      fail('InvalidPublicationPhysicalHoldingOwner');
    }
    const admitted = admitPhysicalHolding(value);
    const record = admitted.record;
    if (await readPhysicalHoldingDeletion(record.holding_cid) !== undefined) {
      fail('PublicationPhysicalHoldingRetiring');
    }
    const selected = preparedObjectOwners.select(prepared,
      new Map(record.objects.map(object => [object.cid, object.byte_count])));
    const retainSelected = () => {
      preparedObjectOwners.retainTransfer(record.holding_cid as string, selected);
    };
    const current = await readPhysicalHolding(record.holding_cid);
    if (current !== undefined) {
      if (!Buffer.from(JSON.stringify(current), 'utf8').equals(
        admitted.bytes,
      )) {
        fail('PublicationPhysicalHoldingConflict');
      }
      await verifyPhysicalHoldingObjects(current);
      retainSelected();
      await confirmPhysicalHoldingDirectory(current);
      return Object.freeze({record: current, created: false});
    }
    if (!Array.isArray(prepared)) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const expected = new Map();
    for (const object of record.objects) {
      if (!expected.has(object.cid)) {
        expected.set(object.cid, object.byte_count);
      }
    }
    const supplied = new Map();
    for (const handle of prepared) {
      const owner = preparedObjectOwners.original(handle);
      if (owner === undefined || supplied.has(owner.cid)) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
      if (handle.status().pending === true) {
        supplied.set(owner.cid, owner.bytes);
      } else if (borrowedHoldingCids.length === 0) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
    }
    const borrowed = new Map();
    for (const holdingCid of borrowedHoldingCids) {
      if (await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
        fail('PublicationPhysicalHoldingRetiring');
      }
      const source = await readPhysicalHolding(holdingCid);
      if (source === undefined) {
        fail('PublicationPhysicalHoldingUnavailable');
      }
      await verifyPhysicalHoldingObjects(source);
      for (const object of source.objects) {
        if (expected.get(object.cid) === object.byte_count) {
          borrowed.set(object.cid, object.byte_count);
        }
      }
    }
    if (borrowedHoldingCids.length !== 0) {
      await confirmPhysicalHoldingDirectory(record, false);
    }
    for (const [cid, bytes] of expected) {
      if (supplied.get(cid) !== bytes && borrowed.get(cid) !== bytes) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
    }
    if ([...supplied].some(([cid, bytes]) => expected.get(cid) !== bytes)) {
      fail('InvalidPublicationPhysicalHoldingOwner');
    }
    await verifyPhysicalHoldingObjects(record);
    retainSelected();
    try {
      await writePhysicalHoldingRecord(
        physicalHoldingPath(record.holding_cid),
        admitted.bytes,
      );
    } catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      const installed = await readBounded(
        physicalHoldingPath(record.holding_cid),
        configuration.maxObjectBytes,
      );
      if (!installed.equals(admitted.bytes)) {
        fail('PublicationPhysicalHoldingConflict');
      }
    }
    await confirmPhysicalHoldingDirectory(record);
    return Object.freeze({record, created: true});
  };

  const commitPhysicalHolding = (value: unknown, prepared: readonly PreparedStatusHandle[],
    borrowedHoldingCids: readonly string[] = []) => {
    const operation = materialRetentionCurrent().then(() =>
      commitPhysicalHoldingInternal(value, prepared, borrowedHoldingCids));
    retainMaterialOperation(operation.catch(() => {}));
    return operation;
  };

  const sharePhysicalHolding = async (sourceHoldingCid: string, value: unknown) => {
    active();
    cidHex(sourceHoldingCid);
    const admitted = admitPhysicalHolding(value);
    const record = admitted.record;
    if (sourceHoldingCid === record.holding_cid) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const operation = materialRetentionCurrent().then(async () => {
      if (await readPhysicalHoldingDeletion(sourceHoldingCid) !== undefined ||
          await readPhysicalHoldingDeletion(record.holding_cid) !== undefined) {
        fail('PublicationPhysicalHoldingRetiring');
      }
      const source = await readPhysicalHolding(sourceHoldingCid);
      if (source === undefined) {
        fail('PublicationPhysicalHoldingUnavailable');
      }
      const expectedObjects = Buffer.from(JSON.stringify(source.objects));
      const requestedObjects = Buffer.from(JSON.stringify(record.objects));
      if (source.manifest_cid !== record.manifest_cid ||
          !expectedObjects.equals(requestedObjects)) {
        fail('PublicationPhysicalHoldingConflict');
      }
      const current = await readPhysicalHolding(record.holding_cid);
      if (current !== undefined) {
        if (!Buffer.from(JSON.stringify(current), 'utf8').equals(
          admitted.bytes,
        )) {
          fail('PublicationPhysicalHoldingConflict');
        }
        await verifyPhysicalHoldingObjects(current);
        await confirmPhysicalHoldingDirectory(current, false);
        return Object.freeze({record: current, created: false});
      }
      await verifyPhysicalHoldingObjects(source);
      try {
        await writePhysicalHoldingRecord(
          physicalHoldingPath(record.holding_cid),
          admitted.bytes,
        );
      } catch (error) {
        if ((error as CodedCause)?.code !== 'EEXIST') throw error;
        const installed = await readBounded(
          physicalHoldingPath(record.holding_cid),
          configuration.maxObjectBytes,
        );
        if (!installed.equals(admitted.bytes)) {
          fail('PublicationPhysicalHoldingConflict');
        }
      }
      await confirmPhysicalHoldingDirectory(record, false);
      return Object.freeze({record, created: true});
    });
    retainMaterialOperation(operation.catch(() => {}));
    return await operation;
  };

  const confirmPhysicalHoldingDirectory = async (record: PhysicalHoldingRecord, adopt = true) => {
    try {
      await syncDirectory(physicalHoldingsDirectory);
      if (adopt) {
        await confirmPreparedMaterials(record.objects.map(object => object.cid));
        const selected = preparedObjectOwners.pendingTransfer(record.holding_cid as string);
        if (selected !== undefined) {
          await adoptPreparedObjects(selected);
          preparedObjectOwners.finishTransfer(record.holding_cid as string);
        }
      }
    } catch (primary) {
      const child = (primary as ConfirmationCause)?.cleanupHandle;
      if (child === undefined) throw primary;
      // The existing publication scope ends on rejection, but this SAME
      // acquired directory FD still prevents Store and holding retirement.
      // Reuse the Store's failed-writer custody; cleanup confirms no evidence.
      const release = retainPhysicalHoldingReader(record.holding_cid as string);
      let original: ConfirmationChild | undefined = child, retry = child.retry, observe = child.status;
      let pending = true, flight: Promise<CleanupStatus> | undefined;
      const writer: ActivePhysicalRecordWriter = {failed: true, cleanup: undefined};
      const failure = new PublicationStoreError('PublicationPrivateConfirmationCleanupPending', primary) as ConfirmationFailure;
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      if ((primary as NonNullable<ConfirmationCause>).outcome === 'unknown') failure.outcome = 'unknown';
      const status = () => Object.freeze({pending});
      writer.cleanup = Object.freeze({status, retry() {
        if (flight !== undefined) return flight;
        if (!pending) return Promise.resolve(status());
        flight = Promise.resolve().then(async () => {
          if (typeof retry !== 'function' || typeof observe !== 'function') {
            fail('PublicationPrivateConfirmationCleanupPending');
          }
          await Reflect.apply(retry, original, []);
          const observed = await Reflect.apply(observe, original, []);
          const descriptor = observed !== null && typeof observed === 'object'
            ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
          if (descriptor?.value !== false) fail('PublicationPrivateConfirmationCleanupPending');
          pending = false;
          release();
          activePhysicalRecordWriters.delete(writer);
          original = retry = observe = undefined;
          return status();
        }).finally(() => {failure.cleanupPending = pending; flight = undefined;});
        return flight;
      }});
      failure.cleanupHandle = writer.cleanup;
      activePhysicalRecordWriters.add(writer);
      throw failure;
    }
  };

  const ensurePhysicalHoldingDeletion = async (record: SelectedPhysicalHoldingRecord) => {
    const bytes = Buffer.from(JSON.stringify(record), 'utf8');
    const path = physicalHoldingDeletionPath(record.holding_cid);
    try { await writePhysicalHoldingRecord(path, bytes); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        path,
        configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) {
        fail('PublicationPhysicalHoldingConflict');
      }
    }
    await syncDirectory(physicalHoldingDeletionsDirectory);
  };

  const createPhysicalHoldingDeletionCleanup = (record: SelectedPhysicalHoldingRecord) => {
    const existing = pendingPhysicalHoldingDeletions.get(record.holding_cid);
    if (existing !== undefined) return existing;
    let pending = true;
    const errors: unknown[] = [];
    const unconfirmedObjects = new Map<unknown, Removal>();
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const cleanup = Object.freeze({
      status,
      async retry() {
        if (!pending) return status();
        const operation = materialRetentionCurrent().then(async () => {
          await ensurePhysicalHoldingDeletion(record);
          if ((activePhysicalHoldingReaders.get(record.holding_cid) ?? 0) !==
              0) return;
          const current = await readPhysicalHolding(record.holding_cid);
          if (current !== undefined) {
            const currentBytes = Buffer.from(JSON.stringify(current), 'utf8');
            const expectedBytes = Buffer.from(JSON.stringify(record), 'utf8');
            if (!currentBytes.equals(expectedBytes)) {
              fail('PublicationPhysicalHoldingConflict');
            }
            await unlink(physicalHoldingPath(record.holding_cid));
            await syncDirectory(physicalHoldingsDirectory);
          }
          const unique = new Map();
          for (const object of record.objects) {
            if (!unique.has(object.cid)) {
              unique.set(object.cid, object.byte_count);
            }
          }
          for (const [cid, bytes] of unique) {
            if (unconfirmedObjects.has(cid)) continue;
            const prepared = preparedObjects.get(cid);
            if (prepared !== undefined &&
                (prepared.holders.size !== 0 ||
                  prepared.commitOwners.size !== 0)) continue;
            if (await materialHasLiveReference(cid)) continue;
            let state;
            try { state = await lstat(objectPath(cid)); }
            catch (error) {
              if ((error as CodedCause)?.code !== 'ENOENT') throw error;
            }
            if (state === undefined) {
              const removal = await rememberPhysicalRemoval(cid,bytes);
              if (removal !== undefined) unconfirmedObjects.set(cid, removal);
              continue;
            }
            if (!state.isFile() || state.size !== bytes) {
              fail('InvalidPublicationStoreObject');
            }
            if (state.nlink > 1) continue;
            const removal = (await rememberPhysicalRemoval(cid,bytes,state))!;
            unconfirmedObjects.set(cid, removal);
            await removal.unlinkOriginal();
          }
          if (unconfirmedObjects.size !== 0) {
            await confirmPhysicalRemovals(unconfirmedObjects);
            unconfirmedObjects.clear();
          }
          await unlink(physicalHoldingDeletionPath(record.holding_cid));
          await syncDirectory(physicalHoldingDeletionsDirectory);
          pending = false;
          pendingPhysicalHoldingDeletions.delete(record.holding_cid);
        });
        retainMaterialOperation(operation.catch(() => {}));
        try { await operation; }
        catch (error) {
          errors.push(error);
          throw error;
        }
        return status();
      },
    });
    pendingPhysicalHoldingDeletions.set(record.holding_cid, cleanup);
    return cleanup;
  };

  const retirePhysicalHolding = async (holdingCid: string) => {
    active();
    cidHex(holdingCid);
    const record = await readPhysicalHolding(holdingCid) ??
      await readPhysicalHoldingDeletion(holdingCid);
    if (record === undefined) {
      const cleanup = Object.freeze({
        status: () => Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        }),
        retry: () => Promise.resolve(Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        })),
      });
      return Object.freeze({record, cleanup, deleted: true});
    }
    const cleanup = createPhysicalHoldingDeletionCleanup(record);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      record,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const recoverPhysicalHoldingDeletions = async () => {
    active();
    const recovered = [];
    for (const name of await readdir(physicalHoldingDeletionsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      const record = await readPhysicalHoldingAt(
        resolve(physicalHoldingDeletionsDirectory, name),
        `sha256:${name.slice(0, -5)}`,
      );
      const cleanup = createPhysicalHoldingDeletionCleanup(record!);
      try { await cleanup.retry(); }
      catch {}
      recovered.push(cleanup);
    }
    return Object.freeze(recovered);
  };

  return {commitPhysicalHolding, sharePhysicalHolding, confirmPhysicalHoldingDirectory,
    retirePhysicalHolding, recoverPhysicalHoldingDeletions};
}
