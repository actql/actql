import {createHash, randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import type {Stats} from 'node:fs';
import {link, lstat, open, unlink} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {createPublicationCustodyRecords} from './publication-custody-records.mjs';
import type {createPublicationMetadataInventory, InventoryOriginal} from './publication-metadata-inventory.mjs';
import type {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import type {createPublicationObjectWrites} from './publication-object-writes.mjs';
import {fail, PublicationStoreError, quantity, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type SemanticBody = Readonly<{wire: string; semanticCid: string}>;
type FileOriginal = Readonly<{bytes: Buffer; physicalCid: string}>;
type PhysicalOriginal = Readonly<{cid: string; device: string; inode: string; byte_count: number}>;
type NativePreparation = PhysicalOriginal & Readonly<{semantic_cid: string}>;
type ReserveObjectCapacity = ReturnType<typeof createPublicationObjectWrites>['reserveObjectCapacity'];
type StagingHandle = Pick<FileHandle, 'write' | 'sync'> & {
  stat(): Promise<Stats>;
  close(): Promise<false | void>;
};
type WriterCleanup = NonNullable<ActivePhysicalRecordWriter['cleanup']>;
type SemanticWriteFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: WriterCleanup;
};
type StagedBody = SemanticBody & {
  bytes: Buffer;
  cid: string;
  handle: StagingHandle | undefined;
  close: StagingHandle['close'] | undefined;
  temporary: string | undefined;
  reservation: ReturnType<ReserveObjectCapacity> | undefined;
  state: Stats | undefined;
  preparation?: NativePreparation;
  accounted: boolean;
  objectLinkAttempted: boolean;
  objectCreated: boolean;
  created: boolean;
};
type NativeSemanticIndex = Readonly<{
  pendingPublication(cid: unknown): InventoryOriginal | undefined;
  beginPhysicalObjectLifetime(): unknown;
  stagePhysicalObjects(originals: readonly NativePreparation[], options: Readonly<{durable: boolean}>): unknown;
  finishPhysicalPreparations(originals: readonly NativePreparation[]): unknown;
}>;
type SemanticWriteDirectories = Readonly<{
  stagingDirectory: string;
  objectsDirectory: string;
  contractsDirectory: string;
}>;
type SemanticWritePorts =
  Pick<ReturnType<typeof createPublicationMetadataInventory>, 'publicationRecoveryValue'> &
  Pick<ReturnType<typeof createPublicationCustodyRecords>, 'reclaimNativePreparation'> & Readonly<{
    active(): unknown;
    cidHex(value: unknown): string;
    currentDeliveryIndex(): NativeSemanticIndex | undefined;
    objectPath(cid: string): string;
    contractPath(cid: string): string;
    physicalOriginal(cid: string, bytes: number, state: Stats): PhysicalOriginal;
    accountPhysicalInstall(original: PhysicalOriginal): boolean;
    settlePhysicalInstalls(originals: readonly PhysicalOriginal[]): unknown;
    confirmPhysicalCapacity(originals: readonly PhysicalOriginal[], retainPreparations: boolean): unknown;
    syncDirectory(path: string): unknown;
    reserveObjectCapacity: ReserveObjectCapacity;
    verifyObject: ReturnType<typeof createPublicationObjectVerifier>;
    exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
  }>;

export function createPublicationSemanticWrites(
  configuration: Readonly<{maxObjectBytes: number}>,
  {stagingDirectory, objectsDirectory, contractsDirectory}: SemanticWriteDirectories,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
  reclaimingMaterialCids: ReadonlySet<unknown>,
  physicalRetirementFences: ReadonlyMap<unknown, unknown>,
  {active, cidHex, currentDeliveryIndex, objectPath, contractPath, physicalOriginal, accountPhysicalInstall,
    settlePhysicalInstalls, confirmPhysicalCapacity, syncDirectory, reserveObjectCapacity, verifyObject, exactUtf8WireMatches,
    publicationRecoveryValue, reclaimNativePreparation}: SemanticWritePorts,
) {
  // Semantic contract identities exclude their self-CID field and therefore
  // are deliberately not the physical digest of the stored complete body.
  // The binding is an exclusive hard link to one immutable physical object.
  const putSemanticBatch = async (
    supplied: readonly SemanticBody[], retainedOriginals?: Pick<Map<string, FileOriginal>, 'set'>,
    recoveryInventory?: InventoryOriginal,
  ) => {
    active();
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    // This private caller supplies one semantic body, an admitted delivery
    // group or a bounded publication metadata group. Original generation
    // records precede final-name acquisition in the existing native metadata
    // transaction. No per-item custody file or directory barrier is needed.
    const items = supplied.map(({wire, semanticCid}): StagedBody => {
      if (typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidPublicationSemanticWire');
      }
      cidHex(semanticCid);
      const bytes = Buffer.from(wire, 'utf8');
      return {wire, semanticCid, bytes,
        cid: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
        handle: undefined, close: undefined, temporary: undefined,
        reservation: undefined, state: undefined, objectLinkAttempted: false,
        accounted: false, objectCreated: false, created: true};
    });
    if (recoveryInventory !== undefined) {
      const retained = currentDeliveryIndex()!.pendingPublication(recoveryInventory.public_index_cid);
      if (retained?.inventory_wire !== recoveryInventory.inventory_wire) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = publicationRecoveryValue(retained);
      for (const item of items) {
        const member = inventory.contract_objects.find(value => value.semantic_cid === item.semanticCid);
        if (member?.physical_cid !== item.cid || member.byte_count !== item.bytes.byteLength) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
      }
    }
    const writer: ActivePhysicalRecordWriter = {cleanup: undefined, failed: false};
    const dirty = new Set<string>();
    activePhysicalRecordWriters.add(writer);
    const account = (item: StagedBody) => {
      if (item.accounted) return;
      item.accounted = accountPhysicalInstall(physicalOriginal(item.cid,item.bytes.byteLength,item.state!));
    };
    let physicalPreparations: NativePreparation[] | undefined, aliasesPublished = false;
    const syncNames = async () => {
      for (const directory of [objectsDirectory, contractsDirectory]) {
        if (!dirty.has(directory)) continue;
        await syncDirectory(directory);
        if (directory === objectsDirectory) {
          confirmPhysicalCapacity(items.filter(item=>item.objectCreated)
            .map(item=>physicalOriginal(item.cid,item.bytes.byteLength,item.state!)), true);
        }
        if (directory === contractsDirectory && aliasesPublished) {
          if (physicalPreparations !== undefined) {
            currentDeliveryIndex()!.finishPhysicalPreparations(physicalPreparations);
            physicalPreparations=undefined;
          }
        }
        dirty.delete(directory);
      }
    };
    let flight: ReturnType<WriterCleanup['retry']> | undefined, failure: SemanticWriteFailure | undefined;
    const status = () => Object.freeze({pending: dirty.size !== 0 || physicalPreparations!==undefined || items.some(item =>
      item.handle !== undefined || item.temporary !== undefined || item.reservation?.held)});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        let firstFailure, failed = false;
        // Each original FD can retire independently. A failed second close
        // must not retain an already closed unpublished first staging file.
        for (const item of items) {
          try {
            if (item.handle !== undefined) {
              if (item.close === undefined) item.close = item.handle.close;
              if (await Reflect.apply(item.close, item.handle, []) === false) {
                fail('PublicationStoreCleanupPending');
              }
              item.handle = item.close = undefined;
            }
            if (item.objectLinkAttempted && !item.objectCreated) {
              let original;
              try { original = await lstat(objectPath(item.cid)); }
              catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
              // Observe a lost link reply without reissuing the link/write.
              if (original?.isFile() && original.dev === item.state!.dev &&
                  original.ino === item.state!.ino) {
                account(item);item.objectCreated=true;
              } else {
                settlePhysicalInstalls([physicalOriginal(item.cid,item.bytes.byteLength,item.state!)]);
                item.accounted=false;
              }
            }
            if (item.temporary !== undefined) {
              try { await unlink(item.temporary); }
              catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
              item.temporary = undefined;
            }
            item.reservation?.release();
          } catch (error) {
            if (!failed) firstFailure = error;
            failed = true;
          }
        }
        // Complete only those original final-name ACKs already attempted.
        // Completed immutable objects remain charged in the Store inventory;
        // a failed semantic publication is not permission to refill capacity.
        try { await syncNames(); } catch (error) {
          if (!failed) firstFailure = error;
          failed = true;
        }
        if (dirty.size===0 && physicalPreparations!==undefined) {
          try {
            const closed = items.every(item => item.handle === undefined && item.temporary === undefined);
            if (closed && !items.some(item => item.objectLinkAttempted)) {
              // A failed stage never attempted installation. Confirm absence
              // before same-original metadata settlement, including Unknown.
              await syncDirectory(objectsDirectory);
              currentDeliveryIndex()!.finishPhysicalPreparations(physicalPreparations);
              physicalPreparations=undefined;
            } else {
              let settled = true;
              for (const item of items) {
                if (item.preparation === undefined) continue;
                if (item.handle !== undefined || item.temporary !== undefined) {settled = false; continue;}
                if (await reclaimNativePreparation(item.preparation) !== true) settled = false;
              }
              if (settled) physicalPreparations=undefined;
            }
          } catch(error){if(!failed)firstFailure=error;failed=true;}
        }
        if (!status().pending) activePhysicalRecordWriters.delete(writer);
        if (failed) throw firstFailure;
        return status();
      }).finally(() => {
        flight = undefined;
        if (failure !== undefined) failure.cleanupPending = status().pending;
      });
      return flight;
    }});
    try {
      for (const item of items) {
        try {
          const existing = await verifyObject(item.cid);
          if (existing.bytes !== item.bytes.byteLength) fail('PublicationObjectIdentityMismatch');
          continue;
        } catch (error) { if ((error as CodedCause)?.code !== 'PublicationObjectMissing') throw error; }
        item.reservation = reserveObjectCapacity(item.bytes.byteLength);
        item.temporary = resolve(stagingDirectory, `object-${randomUUID()}`);
        item.handle = await open(item.temporary,
          constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
        item.close = item.handle.close;
        let offset = 0;
        while (offset < item.bytes.byteLength) {
          const {bytesWritten} = await item.handle.write(item.bytes, offset,
            item.bytes.byteLength - offset, offset);
          if (!quantity(bytesWritten) || bytesWritten === 0 ||
              bytesWritten > item.bytes.byteLength - offset) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
        await item.handle.sync();
        item.state = await item.handle.stat();
        if (!item.state.isFile() || item.state.size !== item.bytes.byteLength) {
          fail('IncompletePublicationWrite');
        }
        if (await Reflect.apply(item.close, item.handle, []) === false) {
          fail('PublicationStoreCleanupPending');
        }
        item.handle = item.close = undefined;
      }
      const originals=(recoveryInventory === undefined ? items : [])
        .filter(item=>item.temporary!==undefined).map(item =>
        item.preparation = Object.freeze({...physicalOriginal(item.cid,item.bytes.byteLength,item.state!),
          semantic_cid:item.semanticCid}));
      if(originals.length!==0) {
        currentDeliveryIndex()!.beginPhysicalObjectLifetime();
        physicalPreparations=originals;
        currentDeliveryIndex()!.stagePhysicalObjects(originals, {durable: true});
      }
      for (const item of items) {
        if (item.temporary === undefined) continue;
        if (reclaimingMaterialCids.has(item.cid) || physicalRetirementFences.has(item.cid)) fail('PublicationObjectReclamationPending');
        item.objectLinkAttempted = true;
        dirty.add(objectsDirectory);
        account(item);
        try { await link(item.temporary, objectPath(item.cid)); item.objectCreated=true; }
        catch (error) {
          if ((error as CodedCause)?.code !== 'EEXIST') throw error;
          if ((await verifyObject(item.cid)).bytes !== item.bytes.byteLength) {
            fail('PublicationObjectIdentityMismatch');
          }
          settlePhysicalInstalls([physicalOriginal(item.cid,item.bytes.byteLength,item.state!)]);
          item.accounted=false;
        }
      }
      await syncNames();
      for (const item of items) {
        dirty.add(contractsDirectory);
        try { await link(objectPath(item.cid), contractPath(item.semanticCid)); }
        catch (error) {
          if ((error as CodedCause)?.code !== 'EEXIST') throw error;
          item.created = false;
          const existing = await readBounded(contractPath(item.semanticCid), configuration.maxObjectBytes);
          if (!exactUtf8WireMatches(existing, item.wire)) fail('PublicationSemanticIdentityConflict');
        }
      }
      aliasesPublished = true;
      await syncNames();
      // Staging names never establish durable state. They are unlinked only
      // after original close; a name resurrected by a crash is removed by the
      // existing exclusive opening recovery, not interpreted as a commit.
      await cleanup.retry();
      // Only these two newly linked names belong to this successful writer.
      // Its bounded bytes/digest and real file/close/directory ACKs already
      // establish the same-commit inventory fact. Existing aliases still use
      // their actual reader; no observation escapes this operation's map.
      if (retainedOriginals !== undefined) {
        for (const item of items) {
          if (item.objectCreated && item.created) retainedOriginals.set(
            item.semanticCid, Object.freeze({bytes: item.bytes, physicalCid: item.cid}),
          );
        }
      }
      return Object.freeze(items.map(item => Object.freeze({semanticCid: item.semanticCid,
        physical: Object.freeze({cid: item.cid, bytes: item.bytes.byteLength,
          created: item.objectCreated}), created: item.created})));
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      failure = new PublicationStoreError(
        ((primary as CodedCause)?.code ?? 'PublicationSemanticWriteFailed') as string, primary,
      ) as SemanticWriteFailure;
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };

  const putSemantic = async (wire: string, semanticCid: string) =>
    (await putSemanticBatch([{wire, semanticCid}]))[0];

  return {putSemanticBatch, putSemantic};
}
