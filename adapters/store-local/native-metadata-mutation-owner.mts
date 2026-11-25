import {PublicationStoreError} from './publication-store-io.mjs';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {InventoryOriginal} from './publication-metadata-inventory.mjs';

type Cleanup = NonNullable<ActivePhysicalRecordWriter['cleanup']>;
type CleanupStatus = ReturnType<Cleanup['status']>;
type ActiveNativeRecordWriter = ActivePhysicalRecordWriter & {
  nativeIndexKey?: string;
  failure?: unknown;
};
type MutationCause = Readonly<{outcome?: unknown}> | null | undefined;
type MutationFailure = PublicationStoreError & {
  outcome: 'unknown';
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: Cleanup;
};
type MetadataMutationIndex = Readonly<{
  stageNativePublicationInventory(original: InventoryOriginal): unknown;
  stagePublicationInventory(original: InventoryOriginal): unknown;
}>;
type IndexArguments = [Readonly<{metadata_key: string}>, ...unknown[]];
type Reservation = Readonly<{release(): unknown}>;

export function createNativeMetadataMutationOwner(
  currentDeliveryIndex: () => MetadataMutationIndex | undefined,
  activePhysicalRecordWriters: Set<ActiveNativeRecordWriter>,
) {
  const stageMetadataInventory = (original: InventoryOriginal, native: boolean) => {
    const index = currentDeliveryIndex()!;
    const stage = native ? index.stageNativePublicationInventory : index.stagePublicationInventory;
    const writer: ActivePhysicalRecordWriter = {failed: false, cleanup: undefined};
    activePhysicalRecordWriters.add(writer);
    try { Reflect.apply(stage, index, [original]); }
    catch (primary) {
      if ((primary as MutationCause)?.outcome !== 'unknown') {
        activePhysicalRecordWriters.delete(writer);
        throw primary;
      }
      // stage() precedes the Index commit's payload-custody owner. Keep its
      // SAME native mutation here, not only inside an inaccessible DB latch.
      // Finalization confirms storage only; it never publishes or reruns a Run.
      writer.failed = true;
      let pending = true;
      let flight: Promise<CleanupStatus> | undefined;
      const failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown', primary) as MutationFailure;
      const status = () => Object.freeze({pending});
      writer.cleanup = Object.freeze({status, retry() {
        if (flight !== undefined) return flight;
        flight = Promise.resolve().then(() => {
          if (pending) {
            Reflect.apply(stage, index, [original]);
            pending = false;
            activePhysicalRecordWriters.delete(writer);
          }
          return status();
        }).finally(() => {
          failure.cleanupPending = pending;
          flight = undefined;
        });
        return flight;
      }});
      failure.outcome = 'unknown';
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = writer.cleanup;
      throw failure;
    }
    activePhysicalRecordWriters.delete(writer);
  };

  const writeNativeIndexOriginal = <Args extends IndexArguments, Result>(
    method: (...args: Args) => Result, args: Args,
    acknowledge: (result: Result) => unknown, reservation?: Reservation,
  ): Result => {
    const metadataKey = args[0].metadata_key;
    for (const retained of activePhysicalRecordWriters) {
      if (retained.nativeIndexKey === metadataKey && retained.failed) {
        reservation?.release();
        throw retained.failure;
      }
    }
    const index = currentDeliveryIndex()!;
    const writer: ActiveNativeRecordWriter = {failed:false,cleanup:undefined,nativeIndexKey:metadataKey};
    let pending = true;
    let flight: Promise<CleanupStatus> | undefined;
    let failure: MutationFailure | undefined;
    const status = () => Object.freeze({pending});
    const finish = () => {
      const result = Reflect.apply(method,index,args);
      acknowledge(result);
      reservation?.release();
      pending = false;
      activePhysicalRecordWriters.delete(writer);
      return result;
    };
    writer.cleanup = Object.freeze({status,retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(() => {
        if (pending) finish();
        return status();
      }).finally(() => {if (failure !== undefined) failure.cleanupPending = pending; flight = undefined;});
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try {return finish();}
    catch (primary) {
      if ((primary as MutationCause)?.outcome !== 'unknown') {
        reservation?.release(); pending = false; activePhysicalRecordWriters.delete(writer); throw primary;
      }
      writer.failed = true;
      failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown',primary) as MutationFailure;
      failure.outcome = 'unknown'; failure.primaryFailure = primary;
      failure.cleanupPending = true; failure.cleanupHandle = writer.cleanup;
      writer.failure = failure;
      throw failure;
    }
  };

  return {stageMetadataInventory, writeNativeIndexOriginal};
}
