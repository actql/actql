import type {Stats} from 'node:fs';
import {lstat} from 'node:fs/promises';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import type {createPreparedCustodyQueue} from './prepared-custody-queue.mjs';
import type {createPreparedHolderRegistry} from './prepared-holder-owner.mjs';
import type {createPublicationCustodyRecords} from './publication-custody-records.mjs';
import type {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import type {createPublicationObjectWrites} from './publication-object-writes.mjs';
import {fail} from './publication-store-io.mjs';

type Custody = Awaited<ReturnType<ReturnType<typeof createPublicationCustodyRecords>['registerCustody']>>;
type RemovalOwner = Readonly<{unlinkOriginal(): Promise<unknown>}>;
type PreparedHolder = {
  active: boolean;
  releasing: Promise<boolean> | undefined;
  custody: Custody | undefined;
};
type CommitOutcome = 'committed' | 'uncommitted';
type CommitPin<Removal> = {
  pending: boolean;
  outcome: CommitOutcome | undefined;
  groups: Set<PreparedGroup<Removal>>;
  errors: unknown[];
};
type PreparedGroup<Removal> = {
  holders: Set<PreparedHolder>;
  commitOwners: Set<CommitPin<Removal>>;
  removable: boolean;
  committed: boolean;
  pendingUnlink: {removal: Removal; owner: PreparedHolder; bytes: number; accounted: boolean} | undefined;
  custodies: Set<Custody>;
  allocationCustody?: Custody;
  busy: Promise<unknown>;
};
type PreparedOriginal<Removal> = Readonly<{cid: string; bytes: number; group: PreparedGroup<Removal>; holder: PreparedHolder}>;
type IndexConfirmation = Readonly<{public_index_entry_cid: string}>;
type PreparedPorts<Removal> =
  Pick<ReturnType<typeof createPublicationCustodyRecords>, 'removeCustodyRecord' | 'reclaimCustody'> & Readonly<{
    createObjectWriter: ReturnType<typeof createPublicationObjectWrites>['createObjectWriter'];
    objectPath(cid: string): string;
    confirmPhysicalRemovals(removals: ReadonlyMap<string, Removal>): Promise<unknown>;
    rememberPhysicalRemoval(cid: string, bytes: number, state: Stats): Promise<Removal>;
    materialHasLiveReference(cid: string): Promise<boolean>;
    confirmCommittedIndex(key: WireRunRef): Promise<IndexConfirmation | undefined>;
    verifyObject: ReturnType<typeof createPublicationObjectVerifier>;
  }>;

export function createPreparedObjectOwnership<Removal extends RemovalOwner>(
  preparedObjects: Map<string, PreparedGroup<Removal>>,
  preparedObjectOwners: Pick<ReturnType<typeof createPreparedHolderRegistry<PreparedOriginal<Removal>>>, 'register' | 'forgetHolder'>,
  withPreparedCustody: ReturnType<typeof createPreparedCustodyQueue>,
  writeState: {materialRetentionBusy: Promise<unknown>},
  {createObjectWriter, objectPath, confirmPhysicalRemovals, rememberPhysicalRemoval, verifyObject,
    removeCustodyRecord, reclaimCustody, materialHasLiveReference, confirmCommittedIndex}: PreparedPorts<Removal>,
) {
  // The recovery record for the installed allocation is shared by every
  // live holder of that generation. A losing seal's temporary inode record
  // cannot replace it. Retiring its first holder transfers this SAME recovery
  // duty to the remaining group, without new bytes or durable authority.
  const retirePreparedHolderCustody = async (group: PreparedGroup<Removal>, holder: PreparedHolder) => {
    const finalHolder = group.holders.size === 1 && group.commitOwners.size === 0;
    const selected = finalHolder ? [...group.custodies]
      : holder.custody === undefined || holder.custody === group.allocationCustody
        ? [] : [holder.custody];
    for (const custody of selected) {
      await removeCustodyRecord(custody);
      group.custodies.delete(custody);
      if (group.allocationCustody === custody) group.allocationCustody = undefined;
    }
    holder.custody = undefined;
  };

  const createPreparedObjectWriter = (maxBytes: number) => {
    const writer = createObjectWriter(maxBytes, true);
    return Object.freeze({
      append: (frame: unknown) => writer.append(frame),
      cancel: () => writer.cancel(),
      status: () => writer.status(),
      async seal(expectedCid?: string) {
        const physical = await writer.seal(expectedCid);
        // Join the current generation only after any prior adoption/release
        // finished. Never append to a snapshot that is already being retired.
        const {group, holder} = await withPreparedCustody(physical.cid, () => {
          let group = preparedObjects.get(physical.cid);
          if (group === undefined) {
            group = {
              holders: new Set(),
              commitOwners: new Set(),
              removable: physical.created,
              committed: false,
              pendingUnlink: undefined,
              custodies: new Set(),
              busy: Promise.resolve(),
            };
            preparedObjects.set(physical.cid, group);
          } else if (physical.created) {
            group.removable = true;
          }
          if (physical.custody !== undefined) {
            group.custodies.add(physical.custody);
            if (physical.created) group.allocationCustody = physical.custody;
          }
          const holder: PreparedHolder = {active: true, releasing: undefined, custody: physical.custody};
          group.holders.add(holder);
          return {group, holder};
        });
        const errors: unknown[] = [];
        const state = () => Object.freeze({
          pending: holder.active,
          errors: Object.freeze([...errors]),
        });
        const clearCustodies = () => retirePreparedHolderCustody(group, holder);
        const finishPendingUnlink = async () => {
          const pending = group.pendingUnlink;
          if (pending === undefined) return;
          if (!pending.accounted) {
            await confirmPhysicalRemovals(new Map([[physical.cid,pending.removal]]));
            pending.accounted = true;
          }
          await clearCustodies();
          pending.owner.active = false;
          preparedObjectOwners.forgetHolder(pending.owner);
          group.holders.delete(pending.owner);
          group.pendingUnlink = undefined;
        };
        const release = () => {
          if (!holder.active) return Promise.resolve(false);
          if (holder.releasing !== undefined) return holder.releasing;
          // A physical holding and its prepared release use the same existing
          // material queue. An awaited directory ACK must not race reclamation.
          const previous = group.busy;
          const operation = writeState.materialRetentionBusy.then(() => previous).then(() =>
            withPreparedCustody(physical.cid, async () => {
            if (!holder.active) return false;
            await finishPendingUnlink();
            if (!holder.active) {
              if (group.holders.size === 0 &&
                  group.commitOwners.size === 0) {
                preparedObjects.delete(physical.cid);
              }
              return true;
            }
            if (group.commitOwners.size > 0) return false;
            const adoptedStillRetained = group.committed &&
              await materialHasLiveReference(physical.cid);
            if (adoptedStillRetained || group.holders.size > 1 ||
                !group.removable) {
              const finalHolder = group.holders.size === 1 &&
                group.commitOwners.size === 0;
              await clearCustodies();
              group.holders.delete(holder);
              holder.active = false;
              preparedObjectOwners.forgetHolder(holder);
              if (finalHolder) {
                preparedObjects.delete(physical.cid);
              }
              return true;
            }
            const path = objectPath(physical.cid);
            const before = await lstat(path);
            if (!before.isFile() || before.size !== physical.bytes) {
              fail('InvalidPublicationStoreObject');
            }
            // Semantic contracts and public index entries are hard links to
            // their physical object. Never reclaim an allocation with another
            // filesystem owner, even if the prepared holder is the creator.
            if (before.nlink !== 1) {
              await clearCustodies();
              group.holders.delete(holder);
              holder.active = false;
              preparedObjectOwners.forgetHolder(holder);
              preparedObjects.delete(physical.cid);
              return true;
            }
            // Physical holdings refer to bytes by CID, not inode hard links.
            // A visible holding after a lost commit ACK is still responsibility,
            // not permission to unlink. Keep this exact pending handle until
            // the same commit is confirmed or its holding is lawfully retired.
            if (await materialHasLiveReference(physical.cid)) return false;
            const removal = await rememberPhysicalRemoval(physical.cid, before.size, before);
            group.pendingUnlink = {
              removal,
              owner: holder,
              bytes: before.size,
              accounted: false,
            };
            await removal.unlinkOriginal();
            group.removable = false;
            await finishPendingUnlink();
            if (group.holders.size === 0 &&
                group.commitOwners.size === 0) {
              preparedObjects.delete(physical.cid);
            }
            return true;
          }));
          group.busy = operation.catch(() => {});
          writeState.materialRetentionBusy = group.busy;
          holder.releasing = operation.catch(error => {
            // Private diagnostics retain the original first and latest
            // failed release, not an unbounded retry log. Keep both roles
            // even when the same Error is reused; status snapshots own their
            // copied arrays. This never settles the original physical duty.
            retainFirstAndLatestCleanupError(errors, error);
            throw error;
          }).finally(() => { holder.releasing = undefined; });
          return holder.releasing;
        };
        const prepared = Object.freeze({
          cid: physical.cid,
          status: state,
          release,
          async retry() {
            if (holder.active) await release();
            return state();
          },
        });
        preparedObjectOwners.register(prepared, {
          cid: physical.cid,
          bytes: physical.bytes, group, holder,
        });
        return Object.freeze({
          cid: physical.cid,
          bytes: physical.bytes,
          created: physical.created,
          prepared,
        });
      },
    });
  };

  // A durable witness can make an original holder releasable, but it cannot
  // choose that holder's terminal transition. The handle still owns release.
  const confirmPreparedMaterials = async (cids: Iterable<string>) => {
    for (const cid of new Set(cids)) await withPreparedCustody(cid, () => {
      const group = preparedObjects.get(cid);
      if (group !== undefined) group.committed = true;
    });
  };

  // A durable adoption witness transfers only the selected original holders.
  // Neither a CID match nor a read/confirmation grants another holder's duty.
  const adoptPreparedObjects = async (selected: readonly PreparedOriginal<Removal>[]) => {
    for (const original of selected) {
      const {cid, group, holder} = original;
      await withPreparedCustody(cid, async () => {
        if (!holder.active) return;
        if (preparedObjects.get(cid) !== group || !group.holders.has(holder)) {
          fail('InvalidPublicationPreparedOwner');
        }
        await retirePreparedHolderCustody(group, holder);
        group.committed = true;
        holder.active = false;
        preparedObjectOwners.forgetHolder(holder);
        group.holders.delete(holder);
        if (group.holders.size === 0 && group.commitOwners.size === 0) preparedObjects.delete(cid);
      });
    }
  };

  const beginPreparedCommit = async (
    cids: Iterable<string>, key: WireRunRef, indexCid: string, selected: readonly PreparedOriginal<Removal>[] = [],
    ownRetention?: (cid: string) => Promise<boolean>,
  ) => {
    const owner: CommitPin<Removal> = {
      pending: false,
      outcome: undefined,
      groups: new Set(),
      errors: [],
    };
    const acquired: Array<[string, PreparedGroup<Removal>]> = [];
    const settlePins = async (outcome: CommitOutcome) => {
      // A pin can be the final borrower of an allocation's recovery record
      // after its last holder transferred to a now-retired durable owner.
      // End that shared duty under the SAME material -> metadata ordering.
      const retirement = writeState.materialRetentionBusy.then(async () => {
        for (const [cid, group] of acquired) {
          await withPreparedCustody(cid, async () => {
            group.commitOwners.delete(owner);
            if (group.holders.size === 0 && group.commitOwners.size === 0) {
              const durablyRetained = outcome === 'committed' &&
                ownRetention !== undefined && await ownRetention(cid) ||
                await materialHasLiveReference(cid);
              for (const custody of [...group.custodies]) {
                if (durablyRetained) await removeCustodyRecord(custody);
                else if (!await reclaimCustody(custody)) fail('PublicationPreparedCustodyPending');
                group.custodies.delete(custody);
                if (group.allocationCustody === custody) group.allocationCustody = undefined;
              }
              if (preparedObjects.get(cid) === group) preparedObjects.delete(cid);
            }
            owner.groups.delete(group);
          });
        }
      });
      writeState.materialRetentionBusy = retirement.catch(() => {});
      await retirement;
      acquired.length = 0;
      owner.pending = false;
      owner.outcome = outcome;
    };
    try {
      // Join physical reclamation before taking any per-CID metadata queue.
      // Verification alone cannot pin an already adopted original: its last
      // durable Result may be retiring while this new Index is installed.
      const acquisition = writeState.materialRetentionBusy.then(async () => {
        for (const cid of new Set(cids)) {
          await withPreparedCustody(cid, async () => {
            let group = preparedObjects.get(cid);
            if (group === undefined) {
              await verifyObject(cid);
              // This is only a temporary retention pin, never new payload
              // custody or permission to unlink the pre-existing original.
              group = {holders: new Set(), commitOwners: new Set(),
                removable: false, committed: false, pendingUnlink: undefined,
                custodies: new Set(), busy: Promise.resolve()};
              preparedObjects.set(cid, group);
            }
            group.commitOwners.add(owner);
            owner.groups.add(group);
            acquired.push([cid, group]);
            owner.pending = true;
          });
        }
      });
      writeState.materialRetentionBusy = acquisition.catch(() => {});
      await acquisition;
    } catch (cause) {
      // No install has started. Return only these temporary commit pins;
      // prepared holders and any failed physical reader keep their own duties.
      await settlePins('uncommitted');
      throw cause;
    }
    const status = () => Object.freeze({
      pending: owner.pending,
      outcome: owner.outcome,
      errors: Object.freeze([...owner.errors]),
    });
    const resolveConfirmed = async (entry: IndexConfirmation | undefined) => {
      if (!owner.pending) return status();
      if (entry?.public_index_entry_cid === indexCid) {
        await adoptPreparedObjects(selected);
        await settlePins('committed');
      } else {
        await settlePins('uncommitted');
      }
      return status();
    };
    return Object.freeze({
      status,
      resolveConfirmed,
      settleAdopted: () => settlePins('committed'),
      async retry() {
        if (!owner.pending) return status();
        try {
          return await resolveConfirmed(await confirmCommittedIndex(key));
        } catch (error) {
          retainFirstAndLatestCleanupError(owner.errors, error);
          throw error;
        }
      },
    });
  };

  return {createPreparedObjectWriter, confirmPreparedMaterials, adoptPreparedObjects, beginPreparedCommit};
}
