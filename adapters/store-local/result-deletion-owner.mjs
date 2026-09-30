// One retired Result owns the unlink-to-durable-reclamation transition.
// The Store retains the shared capacity ledger and material-retention queue.
export function createResultDeletionOwner(operations) {
  let pending = true;
  let unlinked = false;
  let accounted = false;
  const errors = [];
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const settle = clearReclaiming => {
    pending = false;
    operations.settle(clearReclaiming);
  };

  return Object.freeze({
    status,
    async retry() {
      if (!pending) return status();
      try {
        await operations.serialize(async () => {
          await operations.ensureMarker();
          const retention = await operations.retention();
          if (retention === 'wait') return;
          if (retention === 'settled') {
            settle(false);
            return;
          }
          operations.markReclaiming();
          if (!unlinked) {
            const allocation = await operations.inspectAllocation();
            if (allocation === 'missing' || allocation === 'shared') {
              settle(true);
              return;
            }
            await operations.unlink();
            unlinked = true;
          }
          await operations.syncObjects();
          if (!accounted) {
            operations.releaseCapacity();
            accounted = true;
          }
          settle(true);
        });
      } catch (error) {
        errors.push(error);
        throw error;
      }
      return status();
    },
  });
}
