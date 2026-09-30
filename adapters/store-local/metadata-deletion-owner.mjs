// One retired publication owns the transition from a hidden index to
// durably reclaimed metadata. The Store remains the sole capacity ledger.
export function createMetadataDeletionOwner(marker, operations) {
  let pending = true;
  const errors = [];
  const unconfirmedObjects = new Map();
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const confirmUnlinkedObjects = async () => {
    if (unconfirmedObjects.size === 0) return;
    await operations.syncObjects();
    operations.releaseUnconfirmed(unconfirmedObjects);
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
        errors.push(error);
        throw error;
      }
      return status();
    },
  });
}
