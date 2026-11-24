import {createHash} from 'node:crypto';
import type {Stats} from 'node:fs';
import {link, lstat, open, unlink} from 'node:fs/promises';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {createObjectWriterOwner} from './object-writer-owner.mjs';
import type {createPublicationCustodyRecords} from './publication-custody-records.mjs';
import type {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import {fail, PublicationStoreError, quantity} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type WriteCleanupStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type ObjectWriteFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupErrors: readonly unknown[];
  cleanupHandle: Readonly<{status(): WriteCleanupStatus; retry(): Promise<WriteCleanupStatus>}>;
};
type PhysicalOriginal = Readonly<{cid: string; byte_count: number; device: string; inode: string}>;
type StoreWriteState = {
  readonly storedBytes: number;
  readonly objectCount: number;
  reservedBytes: number;
  reservedObjects: number;
  materialRetentionBusy: Promise<unknown>;
};
type CustodyPorts = Pick<ReturnType<typeof createPublicationCustodyRecords>, 'registerCustody' | 'reclaimCustody' | 'removeCustodyRecord'>;
type WritePorts = CustodyPorts & Readonly<{
  active(): unknown;
  syncDirectory(path: string): unknown;
  objectPath(cid: string): string;
  currentDeliveryIndex(): Readonly<{pendingPhysicalObject(original: PhysicalOriginal): unknown}> | undefined;
  physicalOriginal(cid: string, bytes: number, state: Stats): PhysicalOriginal;
  confirmPhysicalCapacity(originals: PhysicalOriginal[]): unknown;
  settlePhysicalInstalls(originals: PhysicalOriginal[]): unknown;
  accountPhysicalInstall(original: PhysicalOriginal): boolean;
  verifyObject: ReturnType<typeof createPublicationObjectVerifier>;
}>;

export function createPublicationObjectWrites(
  configuration: Readonly<{maxObjectBytes: number; maxObjects: number; capacityBytes: number}>,
  stagingDirectory: string,
  objectsDirectory: string,
  storeState: StoreWriteState,
  reclaimingMaterialCids: ReadonlySet<unknown>,
  physicalRetirementFences: ReadonlyMap<unknown, unknown>,
  ports: WritePorts,
) {
  const {active, syncDirectory, objectPath, currentDeliveryIndex, physicalOriginal,
    confirmPhysicalCapacity, settlePhysicalInstalls, accountPhysicalInstall, verifyObject} = ports;

  const reserveObjectCapacity = (maxBytes: unknown) => {
    active();
    if (!quantity(maxBytes) || maxBytes > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    if (storeState.objectCount + storeState.reservedObjects >= configuration.maxObjects) {
      fail('PublicationStoreObjectLimit');
    }
    if (storeState.storedBytes + storeState.reservedBytes + maxBytes >
        configuration.capacityBytes) {
      fail('PublicationStoreCapacity');
    }
    storeState.reservedBytes += maxBytes;
    storeState.reservedObjects++;
    let held = true;
    return Object.freeze({
      get held() { return held; },
      release() {
        if (!held) return false;
        storeState.reservedBytes -= maxBytes;
        storeState.reservedObjects--;
        held = false;
        return true;
      },
    });
  };

  const createObjectWriter = (maxBytes: number, trackCustody = false) =>
    createObjectWriterOwner(
      maxBytes,
      trackCustody,
      reserveObjectCapacity(maxBytes),
      {
        stagingDirectory,
        objectsDirectory,
        open,
        link,
        unlink,
        syncDirectory,
        fail,
        objectPath,
        isReclaiming: cid => reclaimingMaterialCids.has(cid) || physicalRetirementFences.has(cid),
        registerCustody: ports.registerCustody,
        protectInstallation: true,
        async confirmInstalled(cid, bytes, state, custody, installed) {
          if (installed) confirmPhysicalCapacity([physicalOriginal(cid, bytes, state)]);
          else if (!trackCustody) {
            const selected = await lstat(objectPath(cid));
            const original = physicalOriginal(cid, bytes, selected);
            if (currentDeliveryIndex()!.pendingPhysicalObject(original) !== undefined) {
              const adoption = storeState.materialRetentionBusy.then(async () => {
                // A cleanup may have won while this writer was waiting. Only
                // the still-present original can become its accepted object.
                await verifyObject(cid);
                const current = await lstat(objectPath(cid));
                if (current.dev !== selected.dev || current.ino !== selected.ino || current.size !== bytes) {
                  fail('PublicationObjectAccountingMismatch');
                }
                confirmPhysicalCapacity([original]);
              });
              storeState.materialRetentionBusy = adoption.catch(() => {});
              await adoption;
            }
          }
        },
        discardInstallation(cid, bytes, state, custody) {
          settlePhysicalInstalls([physicalOriginal(cid, bytes, state)]);
          if (custody !== undefined) custody.accounted = false;
        },
        finishUntrackedCustody: ports.removeCustodyRecord,
        reclaimCustody: ports.reclaimCustody,
        verifyObject,
        accountInstalled(bytes, custody, cid, state) {
          const accounted = accountPhysicalInstall(physicalOriginal(cid, bytes, state));
          if (custody !== undefined) custody.accounted = accounted;
        },
      },
    );

  const putBytesInternal = async (value: unknown, expectedCid: string | undefined, trackCustody: boolean) => {
    const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value as ArrayLike<number>);
    const cid = `sha256:${createHash('sha256').update(buffer).digest('hex')}`;
    if (expectedCid !== undefined && expectedCid !== cid) {
      fail('PublicationObjectIdentityMismatch');
    }
    try {
      const existing = await verifyObject(cid);
      if (existing.bytes !== buffer.byteLength) {
        fail('PublicationObjectIdentityMismatch');
      }
      return Object.freeze({...existing, created: false});
    } catch (error) {
      if ((error as CodedCause)?.code !== 'PublicationObjectMissing') throw error;
    }
    const writer = createObjectWriter(buffer.byteLength, trackCustody);
    try {
      await writer.append(buffer);
      return await writer.seal(cid);
    } catch (primaryFailure) {
      const cleanupErrors: unknown[] = [];
      try {
        const status = writer.status();
        if (status.reservationHeld || status.custodyPending) {
          await writer.cancel();
        }
      } catch (error) { retainFirstAndLatestCleanupError(cleanupErrors, error); }
      if (!writer.status().reservationHeld &&
          !writer.status().custodyPending) throw primaryFailure;
      const code = typeof (primaryFailure as CodedCause)?.code === 'string'
        ? (primaryFailure as {code: string}).code : 'PublicationObjectWriteFailed';
      const failure = new PublicationStoreError(code, primaryFailure) as ObjectWriteFailure;
      failure.primaryFailure = primaryFailure;
      const status = () => Object.freeze({
        pending: writer.status().reservationHeld ||
          writer.status().custodyPending,
        errors: Object.freeze([...cleanupErrors]),
      });
      const cleanupHandle = Object.freeze({
        status,
        async retry() {
          if (writer.status().reservationHeld ||
              writer.status().custodyPending) {
            try { await writer.cancel(); }
            catch (error) { retainFirstAndLatestCleanupError(cleanupErrors, error); }
          }
          failure.cleanupPending = status().pending;
          failure.cleanupErrors = status().errors;
          return status();
        },
      });
      failure.cleanupPending = true;
      failure.cleanupErrors = status().errors;
      failure.cleanupHandle = cleanupHandle;
      throw failure;
    }
  };

  const putBytes = (value: unknown, expectedCid?: string) =>
    putBytesInternal(value, expectedCid, false);

  return {reserveObjectCapacity, createObjectWriter, putBytes};
}
