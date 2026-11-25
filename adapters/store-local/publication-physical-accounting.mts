import {constants} from 'node:fs';
import type {Stats} from 'node:fs';
import {lstat, open, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';
import {fail} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type AllocationIdentity = Readonly<{cid: string; device: string; inode: string}>;
type PhysicalOriginal = AllocationIdentity & Readonly<{byte_count: number}>;
type PhysicalUsage = Readonly<{bytes: number; objects: number}>;
type Removal = Pick<ReturnType<typeof createPhysicalRetirementOwner<PhysicalOriginal>>,
  'original' | 'settled' | 'unlinkOriginal' | 'retireAfterDirectoryAck'>;
type Removals = ReadonlyMap<unknown, Removal | undefined>;
type Index = Readonly<{
  recordPhysicalObjects(originals: readonly PhysicalOriginal[], options: Readonly<{retainPreparations: boolean}>): PhysicalUsage;
  physicalObject(cid: string, options?: Readonly<{priorLifetime: boolean}>): PhysicalOriginal | undefined;
  beginPhysicalObjectLifetime(): unknown;
  retainPhysicalRemoval(original: PhysicalOriginal): unknown;
  removePhysicalObjects(originals: readonly PhysicalOriginal[]): PhysicalUsage;
}>;

export function createPublicationPhysicalAccounting(
  objectsDirectory: string,
  syncDirectory: (path: string) => unknown,
  currentDeliveryIndex: () => Index | undefined,
  assertPriorPhysicalUnborrowed: (cid: string, original: PhysicalOriginal) => unknown,
) {
  let storedBytes = 0;
  let objectCount = 0;
  let nativePublicationBytes = 0, nativePublicationObjects = 0;
  let physicalBytes = 0, physicalObjects = 0;
  const unconfirmedPhysicalInstalls = new Map<string, PhysicalOriginal>();
  const physicalRemovalOriginals = new Map<string, Removal>();
  const physicalRemovalAcquisitions = new Map<string, Promise<Removal>>();
  const physicalRetirementFences = new Map<string, Set<Removal>>();
  const removalKey = (original: AllocationIdentity) => `${original.cid}\0${original.device}\0${original.inode}`;
  const physicalRemovalFor = (cid: string, original: AllocationIdentity | undefined) => {
    const matches = [...physicalRemovalOriginals.values()].filter(holder =>
      holder.original.cid === cid && (original === undefined ||
        holder.original.device === original.device && holder.original.inode === original.inode));
    if (matches.length > 1) fail('PublicationObjectAccountingMismatch');
    return matches[0];
  };
  const physicalOriginal = (cid: string, bytes: number, state: Stats): PhysicalOriginal => Object.freeze({cid,
    byte_count: bytes, device: String(state.dev), inode: String(state.ino)});
  const accountPhysicalUsage = (usage: PhysicalUsage) => {
    storedBytes += usage.bytes - physicalBytes;
    objectCount += usage.objects - physicalObjects;
    physicalBytes = usage.bytes;
    physicalObjects = usage.objects;
  };
  const accountPhysicalInstall = (original: PhysicalOriginal) => {
    const existing = unconfirmedPhysicalInstalls.get(original.cid);
    if (existing !== undefined) return existing.device === original.device && existing.inode === original.inode;
    unconfirmedPhysicalInstalls.set(original.cid, original);
    storedBytes += original.byte_count;
    objectCount++;
    return true;
  };
  const settlePhysicalInstalls = (originals: readonly PhysicalOriginal[]) => {
    for (const original of originals) {
      const pending = unconfirmedPhysicalInstalls.get(original.cid);
      if (pending === undefined || pending.device !== original.device || pending.inode !== original.inode) continue;
      storedBytes -= pending.byte_count;
      objectCount--;
      unconfirmedPhysicalInstalls.delete(original.cid);
    }
  };
  // These calls follow the actual object directory ACK. A lost native reply
  // retains the same originals and their in-memory charge until cleanup or
  // same-original confirmation; no visible row alone supplies that ACK.
  const confirmPhysicalCapacity = (originals: readonly PhysicalOriginal[], retainPreparations = false) => {
    accountPhysicalUsage(currentDeliveryIndex()!.recordPhysicalObjects(originals, {retainPreparations}));
    settlePhysicalInstalls(originals);
  };
  const rememberPhysicalRemoval = async (cid: string, bytes: number, state?: Stats) => {
    const original = unconfirmedPhysicalInstalls.get(cid) ?? currentDeliveryIndex()!.physicalObject(cid);
    const selected = state === undefined ? original
      : {cid, device: String(state.dev), inode: String(state.ino)};
    const pendingKey = selected === undefined ? undefined : removalKey(selected);
    if (pendingKey !== undefined && physicalRemovalAcquisitions.has(pendingKey)) {
      const pending = await physicalRemovalAcquisitions.get(pendingKey)!;
      if (pending.original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
      return pending;
    }
    const retained = physicalRemovalFor(cid, selected);
    if (retained !== undefined) {
      if (retained.original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
      return retained;
    }
    if (original === undefined) {
      if (state !== undefined) fail('PublicationObjectAccountingMissing');
      return undefined;
    }
    if (original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
    if (state === undefined && currentDeliveryIndex()!.physicalObject(cid,{priorLifetime:true}) !== undefined) {
      // The adopted opening row belongs to a closed prior Store lifetime,
      // not a current allocation whose FD could be reconstructed from a CID.
      // Reconcile only this absent row, under the existing namespace fence;
      // all current allocations and unrelated quota remain unchanged.
      const unborrowed = () => assertPriorPhysicalUnborrowed(cid,original);
      unborrowed();
      currentDeliveryIndex()!.beginPhysicalObjectLifetime();
      currentDeliveryIndex()!.retainPhysicalRemoval(original);
      const key = removalKey(original);
      let absent = false, settled = false, unlinkFlight: Promise<void> | undefined, retireFlight: Promise<void> | undefined;
      const confirmAbsent = async () => {
        unborrowed();
        try {
          await lstat(resolve(objectsDirectory,cid.slice(7)));
          fail('PublicationObjectAccountingMismatch');
        } catch (error) {if((error as CodedCause)?.code!=='ENOENT')throw error;}
        if (!settled) unborrowed();
      };
      const holder = Object.freeze({
        original,
        get settled() {return settled;},
        unlinkOriginal() {
          if (settled) return Promise.resolve();
          return unlinkFlight ??= confirmAbsent().then(() => {absent = true;})
            .finally(() => {unlinkFlight = undefined;});
        },
        retireAfterDirectoryAck() {
          if (settled) return Promise.resolve();
          return retireFlight ??= Promise.resolve().then(async () => {
            if (!absent) fail('PublicationStoreCleanupPending');
            // Recheck after the real directory ACK: even a replacement from
            // outside the fenced Store must never receive this old refund.
            await confirmAbsent();
            if (settled) return;
            unborrowed();
            accountPhysicalUsage(currentDeliveryIndex()!.removePhysicalObjects([original]));
            settled = true;
            physicalRemovalOriginals.delete(key);
            const owners = physicalRetirementFences.get(cid);
            owners?.delete(holder);
            if (owners?.size === 0) physicalRetirementFences.delete(cid);
          }).finally(() => {retireFlight = undefined;});
        },
      });
      physicalRemovalOriginals.set(key,holder);
      const owners = physicalRetirementFences.get(cid) ?? new Set<Removal>();
      owners.add(holder);
      physicalRetirementFences.set(cid,owners);
      return holder;
    }
    if (state === undefined ||
        original.device !== String(state.dev) || original.inode !== String(state.ino)) {
      // A live owner never reconstructs an absent allocation's FD from a CID.
      // Interrupted processes are reconciled by the exclusive opening census
      // and its real directory ACK before this Store admits any new writer.
      fail('PublicationObjectAccountingMismatch');
    }
    const key = removalKey(original);
    if (physicalRemovalAcquisitions.has(key)) return physicalRemovalAcquisitions.get(key);
    const acquisition = (async () => {
      // Persist dirty recovery coverage before any physical unlink. Holding
      // this actual original FD prevents inode reuse through its unlink ACK.
      currentDeliveryIndex()!.beginPhysicalObjectLifetime();
      const handle = await open(resolve(objectsDirectory, cid.slice(7)), constants.O_RDONLY | constants.O_NOFOLLOW);
      const holder = createPhysicalRetirementOwner(original, handle, {
        async pathState() {
          try { return await lstat(resolve(objectsDirectory, cid.slice(7))); }
          catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        },
        unlink: () => unlink(resolve(objectsDirectory, cid.slice(7))),
        fence(owner) {
          const owners = physicalRetirementFences.get(cid) ?? new Set<Removal>();
          owners.add(owner);
          physicalRetirementFences.set(cid, owners);
        },
        releaseQuota(selected) {
          if (physicalRemovalOriginals.get(key) !== holder || selected !== original) {
            fail('PublicationObjectAccountingMismatch');
          }
          accountPhysicalUsage(currentDeliveryIndex()!.removePhysicalObjects([original]));
          settlePhysicalInstalls([original]);
        },
        forget(owner) {
          if (physicalRemovalOriginals.get(key) === owner) physicalRemovalOriginals.delete(key);
          const owners = physicalRetirementFences.get(cid);
          owners?.delete(owner);
          if (owners?.size === 0) physicalRetirementFences.delete(cid);
        },
      });
      physicalRemovalOriginals.set(key, holder);
      try {
        const held = await handle.stat();
        if (!held.isFile() || held.size !== bytes || String(held.dev) !== original.device ||
            String(held.ino) !== original.inode) fail('PublicationObjectAccountingMismatch');
        currentDeliveryIndex()!.retainPhysicalRemoval(original);
        holder.admit();
        return holder;
      } catch (error) {
        try { await holder.abandon(); }
        catch { /* The Store retains this quarantined original and its fence. */ }
        throw error;
      }
    })();
    physicalRemovalAcquisitions.set(key, acquisition);
    try { return await acquisition; }
    finally { physicalRemovalAcquisitions.delete(key); }
  };
  const releasePhysicalCapacity = async (objects: Removals) => {
    const holders = [...objects].map(([cid, holder]) => {
      if (holder === undefined) return undefined;
      if (holder.original?.cid !== cid || typeof holder.retireAfterDirectoryAck !== 'function' ||
          !holder.settled && physicalRemovalOriginals.get(removalKey(holder.original)) !== holder) {
        fail('PublicationObjectAccountingMismatch');
      }
      return holder.settled ? undefined : holder;
    }).filter(Boolean) as Removal[];
    // Each immutable holder owns a single-flight close+quota settlement.
    // Concurrent old continuations cannot pass an await and remove a successor.
    for (const holder of holders) await holder.retireAfterDirectoryAck();
  };
  const syncPhysicalRemovals = async (objects: Removals) => {
    for (const holder of objects.values()) if (holder !== undefined) await holder.unlinkOriginal();
    await syncDirectory(objectsDirectory);
  };
  const confirmPhysicalRemovals = async (objects: Removals) => {
    await syncPhysicalRemovals(objects);
    await releasePhysicalCapacity(objects);
  };
  const accountNativePublication = (usage: PhysicalUsage) => {
    storedBytes += usage.bytes - nativePublicationBytes;
    objectCount += usage.objects - nativePublicationObjects;
    nativePublicationBytes = usage.bytes;
    nativePublicationObjects = usage.objects;
  };

  return {
    capacityUsage: {get storedBytes() {return storedBytes;}, get objectCount() {return objectCount;}},
    unconfirmedPhysicalInstalls, physicalRemovalOriginals, physicalRemovalAcquisitions, physicalRetirementFences,
    physicalOriginal, accountPhysicalUsage, accountPhysicalInstall, settlePhysicalInstalls, confirmPhysicalCapacity,
    // A supplied stat is either matched to an original removal or refused.
    rememberPhysicalRemoval: rememberPhysicalRemoval as
      ((cid: unknown, bytes: number, state: Stats) => Promise<Removal>) & typeof rememberPhysicalRemoval,
    releasePhysicalCapacity, syncPhysicalRemovals, confirmPhysicalRemovals, accountNativePublication,
  };
}
