// One retired Result owns the unlink-to-durable-reclamation transition.
// The Store retains the shared capacity ledger and material-retention queue.
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';

type Retention = 'wait' | 'settled' | 'free';
type Allocation = 'missing' | 'shared' | 'missing-unconfirmed' | 'exclusive';
type Operations = Readonly<{
  serialize(run: () => Promise<void>): PromiseLike<void>;
  ensureMarker(): unknown;
  retention(): Retention | PromiseLike<Retention>;
  markReclaiming(): undefined;
  inspectAllocation(): Allocation | PromiseLike<Allocation>;
  unlink(): unknown;
  syncObjects(): unknown;
  releaseCapacity(): unknown;
  settle(clearReclaiming: boolean): undefined;
}>;

export function createResultDeletionOwner(operations: Operations) {
  let pending = true;
  let unlinked = false;
  let accounted = false;
  const errors: unknown[] = [];
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const settle = (clearReclaiming: boolean) => {
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
            if (allocation !== 'missing-unconfirmed') await operations.unlink();
            unlinked = true;
          }
          await operations.syncObjects();
          if (!accounted) {
            await operations.releaseCapacity();
            accounted = true;
          }
          settle(true);
        });
      } catch (error) {
        retainFirstAndLatestCleanupError(errors, error);
        throw error;
      }
      return status();
    },
  });
}
