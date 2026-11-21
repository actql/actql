import {randomUUID} from 'node:crypto';
import type {Stats} from 'node:fs';
import {lstat, readdir, unlink} from 'node:fs/promises';
import type {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';
import {cidPattern, exactKeys, fail, quantity, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RecordIdentity = Readonly<{device: string; inode: string; byte_count: number}>;
type PhysicalOriginal = RecordIdentity & Readonly<{cid: unknown}>;
type NativePreparation = PhysicalOriginal & Readonly<{cid: string; semantic_cid?: string}>;
type CustodyRecord = RecordIdentity & Readonly<{
  material_generation_cid: unknown;
  version?: 'actql-local-prepared-custody/0.1';
}>;
type Removal = Pick<ReturnType<typeof createPhysicalRetirementOwner<PhysicalOriginal>>,
  'original' | 'settled' | 'unlinkOriginal' | 'retireAfterDirectoryAck'>;
type Custody = {
  token: string;
  path?: string;
  record: CustodyRecord;
  nativePreparation?: NativePreparation;
  settlingNative?: boolean;
  accounted: boolean;
  pendingUnlink: boolean;
  removal?: Removal;
  busy: Promise<unknown>;
};
type CustodyIndex = Readonly<{
  beginPhysicalObjectLifetime(): unknown;
  finishPhysicalPreparations(originals: NativePreparation[]): unknown;
  pendingPhysicalObject(original: NativePreparation): NativePreparation | undefined;
  physicalObject(cid: unknown): PhysicalOriginal | undefined;
}>;
type CustodyServices = Readonly<{
  custodyPath(token: string): string;
  objectPath(cid: unknown): string;
  contractPath(cid: string): string;
  currentDeliveryIndex(): CustodyIndex | undefined;
  materialRetentionCurrent(): Promise<unknown>;
  retainMaterialOperation(operation: Promise<unknown>): unknown;
  syncDirectory(path: string): unknown;
  writePhysicalHoldingRecord(path: string, bytes: Buffer, exclusive: boolean, finalDirectory: string): Promise<void>;
  physicalOriginal(cid: unknown, bytes: number, state: Stats): PhysicalOriginal;
  confirmPhysicalCapacity(originals: PhysicalOriginal[], retainPreparations?: boolean): unknown;
  confirmPhysicalRemovals(objects: Map<unknown, Removal | undefined>): Promise<unknown>;
  rememberPhysicalRemoval(cid: unknown, bytes: number, state: Stats): Promise<Removal>;
  materialHasLiveReference(cid: unknown): Promise<boolean>;
  verifyObject(cid: unknown): Promise<unknown>;
}>;

export function createPublicationCustodyRecords(
  configuration: Readonly<{maxObjectBytes: number}>,
  custodyDirectory: string,
  objectsDirectory: string,
  contractsDirectory: string,
  custodyNamePattern: RegExp,
  reclaimableCustodies: Map<string, Custody>,
  {
    custodyPath, objectPath, contractPath, currentDeliveryIndex,
    materialRetentionCurrent, retainMaterialOperation, syncDirectory,
    writePhysicalHoldingRecord, physicalOriginal, confirmPhysicalCapacity,
    confirmPhysicalRemovals, rememberPhysicalRemoval, materialHasLiveReference, verifyObject,
  }: CustodyServices,
) {
  const parseCustodyRecord = (bytes: Buffer): CustodyRecord => {
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationPreparedCustody', error); }
    if (!exactKeys(value, [
      'version', 'material_generation_cid', 'byte_count', 'device', 'inode',
    ]) || value.version !== 'actql-local-prepared-custody/0.1' ||
        !cidPattern.test(value.material_generation_cid as string) ||
        !quantity(value.byte_count) || typeof value.device !== 'string' ||
        !/^(0|[1-9][0-9]*)$/u.test(value.device) ||
        typeof value.inode !== 'string' ||
        !/^(0|[1-9][0-9]*)$/u.test(value.inode)) {
      fail('InvalidPublicationPreparedCustody');
    }
    return Object.freeze(value) as CustodyRecord;
  };

  const registerCustody = async (cid: unknown, bytes: number, state: Stats): Promise<Custody> => {
    currentDeliveryIndex()!.beginPhysicalObjectLifetime();
    const token = randomUUID();
    const record: CustodyRecord = Object.freeze({
      version: 'actql-local-prepared-custody/0.1',
      material_generation_cid: cid,
      byte_count: bytes,
      device: String(state.dev),
      inode: String(state.ino),
    });
    const path = custodyPath(token);
    // Publish a final recovery name only after the original record is complete,
    // synced and closed. An abrupt process stop may leave staging bytes, never
    // a partial final custody. Failed close stays in the same Store duty set.
    await writePhysicalHoldingRecord(path, Buffer.from(JSON.stringify(record), 'utf8'),
      false, custodyDirectory);
    const custody = {
      token,
      path,
      record,
      accounted: false,
      pendingUnlink: false,
      busy: Promise.resolve(),
    };
    reclaimableCustodies.set(token, custody);
    return custody;
  };

  const removeCustodyRecord = async (custody: Custody) => {
    if (custody.nativePreparation !== undefined) {
      custody.settlingNative = true;
      currentDeliveryIndex()!.finishPhysicalPreparations([custody.nativePreparation]);
    } else {
      try { await unlink(custody.path!); }
      catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
      await syncDirectory(custodyDirectory);
    }
    reclaimableCustodies.delete(custody.token);
  };

  const reclaimCustody = (custody: Custody) => {
    const operation = custody.busy.then(async () => {
      if (!reclaimableCustodies.has(custody.token)) return false;
      if (custody.settlingNative) {
        // Retry the same lost metadata settlement before another indexed
        // read. Its physical unlink/alias ACK already completed.
        await removeCustodyRecord(custody);
        return true;
      }
      if (custody.nativePreparation !== undefined &&
          currentDeliveryIndex()!.pendingPhysicalObject(custody.nativePreparation) === undefined) {
        // Another accepted owner settled this same preparation. Retiring the
        // obsolete recovery holder cannot reclaim that owner's allocation.
        reclaimableCustodies.delete(custody.token);
        return true;
      }
      const cid = custody.record.material_generation_cid;
      const confirmUnlink = async () => {
        if (custody.accounted) {
          await confirmPhysicalRemovals(new Map([[cid,custody.removal]]));
          custody.accounted = false;
        }
        custody.pendingUnlink = false;
      };
      if (custody.pendingUnlink) {
        await confirmUnlink();
        await removeCustodyRecord(custody);
        return true;
      }
      let state;
      try { state = await lstat(objectPath(cid)); }
      catch (error) {
        if ((error as CodedCause)?.code !== 'ENOENT') throw error;
        if (custody.accounted) await confirmUnlink();
        await removeCustodyRecord(custody);
        return true;
      }
      if (!state.isFile() || state.size !== custody.record.byte_count) {
        fail('InvalidPublicationPreparedCustody');
      }
      const ownsAllocation = String(state.dev) === custody.record.device &&
        String(state.ino) === custody.record.inode;
      if (ownsAllocation) {
        // Complete the SAME possible installation before indexed reference
        // reads. This also settles its lost native COMMIT reply without
        // replaying a payload write, link, business operation or authority.
        await syncDirectory(objectsDirectory);
        confirmPhysicalCapacity([physicalOriginal(cid,custody.record.byte_count,state)],
          custody.nativePreparation !== undefined);
        custody.accounted = true;
        const semanticCid = custody.nativePreparation?.semantic_cid;
        if (semanticCid !== undefined) {
          let alias;
          try { alias = await lstat(contractPath(semanticCid)); }
          catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
          if (alias !== undefined) {
            if (alias.isFile() && alias.size === state.size &&
                alias.dev === state.dev && alias.ino === state.ino) {
              await verifyObject(cid);
              // This is a fresh ACK of the exact intended alias, not an
              // inference from link count or the interrupted process's reply.
              await syncDirectory(contractsDirectory);
              await removeCustodyRecord(custody);
              return true;
            }
            // A conflicting alias belongs to another allocation. It neither
            // accepts this preparation nor prevents reclaiming this exact
            // unreferenced physical generation below.
          }
        }
        const hasLiveReference = await materialHasLiveReference(cid);
        if (!hasLiveReference) {
          // A second link is not proof that another owner accepted custody.
          // The prepared writer may still own its staging alias.
          if (state.nlink !== 1) {
            return false;
          }
          await verifyObject(cid);
          custody.removal = await rememberPhysicalRemoval(cid, custody.record.byte_count, state);
          custody.pendingUnlink = true;
          await custody.removal!.unlinkOriginal();
          await confirmUnlink();
        }
      }
      await removeCustodyRecord(custody);
      return true;
    });
    custody.busy = operation.catch(() => {});
    return operation;
  };

  const reclaimNativePreparation = (original: NativePreparation) => {
    const operation = materialRetentionCurrent().then(async () => {
      const token = `native:${original.cid}:${original.device}:${original.inode}`;
      let custody = reclaimableCustodies.get(token);
      if (custody === undefined) {
        const current = currentDeliveryIndex()!.physicalObject(original.cid);
        custody = {token, nativePreparation: original,
          record: {material_generation_cid: original.cid, byte_count: original.byte_count,
            device: original.device, inode: original.inode},
          accounted: current?.device === original.device && current?.inode === original.inode &&
            current?.byte_count === original.byte_count,
          pendingUnlink: false, busy: Promise.resolve()};
        reclaimableCustodies.set(token, custody);
      }
      return reclaimCustody(custody);
    });
    retainMaterialOperation(operation.catch(() => {}));
    return operation;
  };

  const recoverPreparedCustodies = async () => {
    const recovered: unknown[] = [];
    for (const name of await readdir(custodyDirectory)) {
      if (!custodyNamePattern.test(name)) {
        fail('InvalidPublicationPreparedCustody');
      }
      const token = name.slice(0, -5);
      const path = custodyPath(token);
      const record = parseCustodyRecord(await readBounded(
        path, configuration.maxObjectBytes,
      ));
      let state;
      try { state = await lstat(objectPath(record.material_generation_cid)); }
      catch (error) {
        if ((error as CodedCause)?.code !== 'ENOENT') throw error;
      }
      let accounted = state !== undefined && state.isFile() &&
        state.size === record.byte_count &&
        String(state.dev) === record.device &&
        String(state.ino) === record.inode;
      if(accounted) {
        await syncDirectory(objectsDirectory);
        confirmPhysicalCapacity([physicalOriginal(record.material_generation_cid,record.byte_count,state!)]);
      } else if(state===undefined) {
        const retained=currentDeliveryIndex()!.physicalObject(record.material_generation_cid);
        accounted=retained!==undefined && retained.byte_count===record.byte_count &&
          retained.device===record.device && retained.inode===record.inode;
      }
      const custody = {
        token,
        path,
        record,
        accounted,
        pendingUnlink: false,
        busy: Promise.resolve(),
      };
      reclaimableCustodies.set(token, custody);
      await reclaimCustody(custody);
      recovered.push(record.material_generation_cid);
    }
    return Object.freeze(recovered);
  };

  return {registerCustody, removeCustodyRecord, reclaimCustody, reclaimNativePreparation, recoverPreparedCustodies};
}
