// One retired publication owns the transition from a hidden index to
// durably reclaimed metadata. The Store remains the sole capacity ledger.
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';

type Marker<Result, Contract> = Readonly<{
  results: readonly Result[]; physical_holding_cids: readonly string[]; contract_objects: readonly Contract[];
}>;
type Operations<Result, Contract, Removal> = Readonly<{
  serialize(run: () => Promise<void>): PromiseLike<void>;
  syncObjects(objects: Map<string, Removal>): unknown;
  releaseUnconfirmed(objects: Map<string, Removal>): unknown;
  retireResult(result: Result): boolean | PromiseLike<boolean>;
  retireHolding(holdingCid: string): boolean | PromiseLike<boolean>;
  removeRunDirectories(): unknown;
  removeIndex(): unknown;
  reclaimContract(contract: Contract, unconfirmedObjects: Map<string, Removal>): unknown;
  removeResultDeletionDirectory(): unknown;
  removeInventory(): unknown;
  compactMarker(): unknown;
  settle(): undefined;
}>;

export function createMetadataDeletionOwner<Result, Contract, Removal>(
  marker: Marker<Result, Contract>, operations: Operations<Result, Contract, Removal>) {
  let pending = true;
  const errors: unknown[] = [];
  const unconfirmedObjects = new Map<string, Removal>();
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const confirmUnlinkedObjects = async () => {
    if (unconfirmedObjects.size === 0) return;
    await operations.syncObjects(unconfirmedObjects);
    await operations.releaseUnconfirmed(unconfirmedObjects);
    unconfirmedObjects.clear();
  };

  return Object.freeze({
    status,
    async retry() {
      if (!pending) return status();
      try {
        await operations.serialize(async () => {
          // A second retry may have queued while the first one was running.
          if (!pending) return;
          await confirmUnlinkedObjects();
          for (const result of marker.results) {
            if (!await operations.retireResult(result)) return;
          }
          for (const holdingCid of marker.physical_holding_cids) {
            if (!await operations.retireHolding(holdingCid)) return;
          }
          await operations.removeRunDirectories();
          await operations.removeIndex();
          for (const object of marker.contract_objects) {
            await operations.reclaimContract(object, unconfirmedObjects);
          }
          await confirmUnlinkedObjects();
          await operations.removeResultDeletionDirectory();
          await operations.removeInventory();
          await operations.compactMarker();
          pending = false;
          operations.settle();
        });
      } catch (error) {
        retainFirstAndLatestCleanupError(errors, error);
        throw error;
      }
      return status();
    },
  });
}
