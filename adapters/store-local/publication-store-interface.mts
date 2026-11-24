import type {createPublicationEvidence} from './publication-evidence-inspection.mjs';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {PublicationContract} from './publication-contract-store.mjs';
import type {SemanticReader} from './publication-object-verifier.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {createOriginalStoreStorageBindings} from './publication-store-format.mjs';
import {privateEvidenceWireLimitForObject} from './publication-store-private-evidence.mjs';
import {exactKeys, fail, PublicationStoreError, quantity} from './publication-store-io.mjs';

type Sized = Readonly<{size: number}>;
type LifecycleState = {
  closed: boolean;
  closeRequested: boolean;
  closeFlight: Promise<boolean> | undefined;
};
type CapacityState = Readonly<{storedBytes: number; reservedBytes: number; objectCount: number; reservedObjects: number}>;
type Resources = Readonly<{
  physicalRemovalOriginals: Sized;
  physicalRemovalAcquisitions: Sized;
  preparedObjects: Sized;
  preparedSchemas: Sized;
  reclaimableCustodies: Sized;
  pendingResultDeletions: Sized;
  pendingMetadataDeletions: Sized;
  pendingUncommittedMetadataCleanups: Sized;
  pendingPhysicalHoldingDeletions: Sized;
  activeResultReaders: Sized;
  activePhysicalHoldingReaders: Sized;
  activeSemanticReaders: ReadonlySet<SemanticReader>;
  activePhysicalRecordWriters: ReadonlySet<ActivePhysicalRecordWriter>;
}>;
type SemanticRead<Contract extends PublicationContract> = ReturnType<typeof createPublicationSemanticReader<Contract>>;
type EvidenceInspection<Contract extends PublicationContract> =
  ReturnType<typeof createPublicationEvidence<Contract>>['inspectEffectfulStoredEvidence'];
type ClosePorts<Contract extends PublicationContract> =
  Pick<SemanticRead<Contract>, 'readContract' | 'readSemanticOriginal'> & Readonly<{
    active(): unknown;
    currentDeliveryIndex(): Readonly<{retainResultDeletionSeal(): unknown; close(): unknown}> | undefined;
    clearEffectCaptureCustodyObservation(): unknown;
    inspectEffectfulStoredEvidence: EvidenceInspection<Contract>;
  }>;

export function createPublicationStoreInterface<Contract extends PublicationContract>(
  configuration: Readonly<{maxObjectBytes: number; maxObjects: number; capacityBytes: number; privateEvidenceKey?: Uint8Array}>,
  lifecycleState: LifecycleState,
  writeState: CapacityState,
  trustedClock: Readonly<{clockObservationsPending: number}>,
  storageBindings: Pick<ReturnType<typeof createOriginalStoreStorageBindings>,
    'modelStorageBindingReaders' | 'installationPublicationStorageBindingReaders' | 'clearInstallationPublicationStorageBinding'>,
  ownership: Readonly<{release(): unknown}>,
  {physicalRemovalOriginals, physicalRemovalAcquisitions, preparedObjects, preparedSchemas, reclaimableCustodies,
    pendingResultDeletions, pendingMetadataDeletions, pendingUncommittedMetadataCleanups, pendingPhysicalHoldingDeletions,
    activeResultReaders, activePhysicalHoldingReaders, activeSemanticReaders, activePhysicalRecordWriters}: Resources,
  {active, currentDeliveryIndex, clearEffectCaptureCustodyObservation, readContract, readSemanticOriginal,
    inspectEffectfulStoredEvidence}: ClosePorts<Contract>,
) {
  return {
    // Read-only projection of this SAME immutable Store configuration. A
    // caller must still fund export/tree/String/encoding workspace BEFORE
    // allocation and retain its original reservation through actual ACK.
    // No write, grant, reservation, persistence or cleanup is issued here.
    privateEvidenceWireLimit() {
      active();
      return privateEvidenceWireLimitForObject(configuration.maxObjectBytes);
    },
    async readPublicationContract(cid: string, name: unknown, readDemand?: Parameters<SemanticRead<Contract>['readSemanticOriginal']>[4]) {
      active();
      if (typeof name !== 'string' || name.length === 0) {
        fail('InvalidPublicationContractName');
      }
      return (await readContract(cid, name,
        (semanticCid, includeNative) => readSemanticOriginal(semanticCid, includeNative, false, undefined, readDemand))).contract!;
    },
    inspectEffectfulStoredEvidence(preparation: Parameters<EvidenceInspection<Contract>>[0],
      readOriginal?: Parameters<EvidenceInspection<Contract>>[1]) {
      return inspectEffectfulStoredEvidence(preparation, readOriginal);
    },
    publicationCapacitySupports(requirement: unknown) {
      active();
      if (!exactKeys(requirement, [
        'requiredBytes', 'objectCount', 'maxObjectBytes',
      ]) || !quantity(requirement.requiredBytes) ||
          !quantity(requirement.objectCount) ||
          !quantity(requirement.maxObjectBytes)) {
        fail('InvalidPublicationCapacityRequirement');
      }
      return requirement.maxObjectBytes <= configuration.maxObjectBytes &&
        writeState.storedBytes + writeState.reservedBytes + requirement.requiredBytes <=
          configuration.capacityBytes &&
        writeState.objectCount + writeState.reservedObjects + requirement.objectCount <=
          configuration.maxObjects;
    },
    status() {
      return Object.freeze({
        storedBytes: writeState.storedBytes,
        reservedBytes: writeState.reservedBytes,
        objectCount: writeState.objectCount,
        reservedObjects: writeState.reservedObjects,
        capacityBytes: configuration.capacityBytes,
        closed: lifecycleState.closed,
      });
    },
    close() {
      if (lifecycleState.closeFlight !== undefined) return lifecycleState.closeFlight;
      if (lifecycleState.closed) return Promise.resolve(true);
      // Snapshot only closed resource counts at the original refusal. These
      // diagnostics neither acknowledge cleanup nor observe/retry an owner.
      const cleanupPendingFailure = (cause?: unknown) => Object.assign(
        new PublicationStoreError('PublicationStoreCleanupPending', cause), {
          cleanupDiagnostic: Object.freeze({kind: 'publication-store-close',
            resources: Object.freeze({
              physicalRemovalOriginals: physicalRemovalOriginals.size,
              physicalRemovalAcquisitions: physicalRemovalAcquisitions.size,
              clockObservations: trustedClock.clockObservationsPending,
              reservedObjects: writeState.reservedObjects,
              preparedObjects: preparedObjects.size,
              preparedSchemas: preparedSchemas.size,
              reclaimableCustodies: reclaimableCustodies.size,
              resultDeletions: pendingResultDeletions.size,
              metadataDeletions: pendingMetadataDeletions.size,
              uncommittedMetadataCleanups: pendingUncommittedMetadataCleanups.size,
              physicalHoldingDeletions: pendingPhysicalHoldingDeletions.size,
              resultReaders: activeResultReaders.size,
              physicalHoldingReaders: activePhysicalHoldingReaders.size,
              modelStorageBindingReaders: storageBindings.modelStorageBindingReaders,
              installationPublicationStorageBindingReaders: storageBindings.installationPublicationStorageBindingReaders,
              semanticReaders: activeSemanticReaders.size,
              physicalRecordWriters: activePhysicalRecordWriters.size,
            }),
          }),
        });
      lifecycleState.closeFlight = Promise.resolve().then(async () => {
        // A failed native writer retains its capacity until its SAME mutation
        // receives a real confirmation. Drain that original before treating its
        // reservation as an independent live user. Healthy in-flight writers
        // and every other unfinished owner still keep the existing close fence.
        const retriedWriters = new Set<ActivePhysicalRecordWriter>();
        for (const writer of activePhysicalRecordWriters) {
          if (!writer.failed || writer.cleanup === undefined) continue;
          retriedWriters.add(writer);
          try { await writer.cleanup!.retry(); }
          catch (cause) { throw cleanupPendingFailure(cause); }
        }
        if (physicalRemovalOriginals.size !== 0 || physicalRemovalAcquisitions.size !== 0 ||
            trustedClock.clockObservationsPending !== 0 || writeState.reservedObjects !== 0 || preparedObjects.size !== 0 ||
            preparedSchemas.size !== 0 ||
            reclaimableCustodies.size !== 0 ||
            pendingResultDeletions.size !== 0 ||
            pendingMetadataDeletions.size !== 0 ||
            pendingUncommittedMetadataCleanups.size !== 0 ||
            pendingPhysicalHoldingDeletions.size !== 0 ||
            activeResultReaders.size !== 0 ||
            activePhysicalHoldingReaders.size !== 0 ||
            storageBindings.modelStorageBindingReaders !== 0 ||
            storageBindings.installationPublicationStorageBindingReaders !== 0) {
          throw cleanupPendingFailure();
        }
        // An unsettled read still owns its FD; close must not interrupt it.
        for (const reader of activeSemanticReaders) {
          if (reader.cleanup === undefined) {
            throw cleanupPendingFailure();
          }
        }
        for (const writer of activePhysicalRecordWriters) {
          if (writer.cleanup === undefined) {
            throw cleanupPendingFailure();
          }
        }
        // Refuse new Store work once retirement starts, but do not report closed
        // or erase the original key until the SAME ownership confirms release.
        // A redacted control-read error cannot drive private cleanup. The same
        // Store retains that original duty and drains close only, never read/send.
        lifecycleState.closeRequested = true;
        for (const reader of activeSemanticReaders) {
          try { await reader.cleanup!.retry(); }
          catch { throw cleanupPendingFailure(); }
        }
        if (activeSemanticReaders.size !== 0) throw cleanupPendingFailure();
        for (const writer of activePhysicalRecordWriters) {
          if (retriedWriters.has(writer)) continue;
          try { await writer.cleanup!.retry(); }
          catch { throw cleanupPendingFailure(); }
        }
        if (activePhysicalRecordWriters.size !== 0) throw cleanupPendingFailure();
        currentDeliveryIndex()!.retainResultDeletionSeal();
        if (currentDeliveryIndex()?.close() !== true) throw cleanupPendingFailure();
        return ownership.release();
      }).then(released => {
        if (released !== true) fail('PublicationStoreOwnershipLost');
        lifecycleState.closed = true;
        configuration.privateEvidenceKey?.fill(0);
        storageBindings.clearInstallationPublicationStorageBinding();
        clearEffectCaptureCustodyObservation();
        return true;
      }).finally(() => { lifecycleState.closeFlight = undefined; });
      return lifecycleState.closeFlight;
    },
  };
}
