import {randomUUID} from 'node:crypto';
import type {BigIntStats, Stats} from 'node:fs';
import {lstat, readdir, rename, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';
import {cidPattern, exactKeys, fail, PublicationStoreError, quantity, readBounded, writeExclusive}
  from './publication-store-io.mjs';
import type {createPhysicalHoldingRecordReader, ReadPhysicalHolding} from './physical-holding-record-reader.mjs';
import type {createPhysicalHoldingLifecycle} from './physical-holding-record-writer.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RecordIdentity = Readonly<{device: string; inode: string; byte_count: number}>;
type PhysicalOriginal = RecordIdentity & Readonly<{cid: string}>;
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
  physicalOriginal(cid: string, bytes: number, state: Stats): PhysicalOriginal;
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
        confirmPhysicalCapacity([physicalOriginal(cid as string,custody.record.byte_count,state)],
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
        confirmPhysicalCapacity([physicalOriginal(record.material_generation_cid as string,record.byte_count,state!)]);
      } else if(state===undefined) {
        const retained=currentDeliveryIndex()!.physicalObject(record.material_generation_cid as string);
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

type CaptureRun = Readonly<{identity: unknown; wire: string}>;
type CaptureRunInput = Readonly<{identity?: unknown; wire?: unknown}> | null | undefined;
type CaptureInodeField = 'dev' | 'ino' | 'size' | 'mtimeNs' | 'ctimeNs';
type CaptureCustodyObservation = Readonly<{wire: string; state: Pick<BigIntStats, CaptureInodeField>}>;
type CaptureCustodyPage = Readonly<{after?: string; limit?: number}>;
type RetireCaptureHolding = ReturnType<typeof createPhysicalHoldingLifecycle>['retirePhysicalHolding'];
type CaptureCustodyCleanupFailure = PublicationStoreError & {
  cleanupPending: boolean;
  cleanupHandle: Awaited<ReturnType<RetireCaptureHolding>>['cleanup'];
};
type CaptureCustodyPorts<Run extends CaptureRun> = Readonly<{
  active(): unknown;
  admitContract(name: 'run_definition', wire: unknown): Run;
  cidHex(cid: unknown): string;
  parsePhysicalHolding: ReturnType<typeof createPhysicalHoldingRecordReader>['parsePhysicalHolding'];
  withSemanticCommit<Value>(operation: () => Promise<Value>): Promise<Value>;
  syncDirectory(path: string): unknown;
  readPhysicalHolding(holdingCid: unknown): ReturnType<ReadPhysicalHolding>;
  readPhysicalHoldingDeletion(holdingCid: unknown): ReturnType<ReadPhysicalHolding>;
  retirePhysicalHolding: RetireCaptureHolding;
}>;

export function createEffectCaptureCustodyRecords<Run extends CaptureRun>(
  configuration: Readonly<{maxObjectBytes: number; storeAuthorityCid: string}>,
  captureCustodyDirectory: string, stagingDirectory: string,
  {active, admitContract, cidHex, parsePhysicalHolding, withSemanticCommit, syncDirectory,
    readPhysicalHolding, readPhysicalHoldingDeletion, retirePhysicalHolding}: CaptureCustodyPorts<Run>,
) {
  // This is physical cleanup custody, not a completed capture or permission
  // to execute. Persist before transferring any prepared object to a holding.
  // Completion transfers responsibility to the admitted private capture.
  const captureCustodyRun = (run: CaptureRunInput) => {
    const admitted = admitContract('run_definition', run?.wire);
    if (admitted.identity !== run?.identity) {
      fail('InvalidEffectCaptureCustody');
    }
    return admitted;
  };
  const captureCustodyPath = (run: Run) => resolve(captureCustodyDirectory,
    `${cidHex(run.identity)}.json`);
  // One same-Store durability observation, not capture completion or authority.
  let lastConfirmedEffectCaptureCustody: CaptureCustodyObservation | undefined;
  const readEffectCaptureCustodyOriginal = async (run: Run) => {
    let bytes;
    try { bytes = await readBounded(captureCustodyPath(run),
      Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)); }
    catch (error) { if ((error as CodedCause)?.code === 'ENOENT') return undefined; throw error; }
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidEffectCaptureCustody', error); }
    if (!exactKeys(value, ['version', 'store_authority_cid',
      'run_definition', 'holdings']) ||
        value.version !== 'actql-effect-capture-custody/0.1' ||
        value.store_authority_cid !== configuration.storeAuthorityCid ||
        value.run_definition !== run.wire || !Array.isArray(value.holdings) ||
        value.holdings.length > 4096) fail('InvalidEffectCaptureCustody');
    const holdings = value.holdings.map((value: unknown) =>
      parsePhysicalHolding(Buffer.from(JSON.stringify(value))));
    if (new Set(holdings.map(value => value.holding_cid)).size !==
        holdings.length || holdings.some(value =>
        !['effect-source', 'effect-capture'].includes(value.namespace))) {
      fail('InvalidEffectCaptureCustody');
    }
    return Object.freeze({...value, holdings: Object.freeze(holdings)});
  };
  const readEffectCaptureCustody = async (suppliedRun: CaptureRunInput) => {
    active();
    return readEffectCaptureCustodyOriginal(captureCustodyRun(suppliedRun));
  };
  const retainEffectCaptureCustody = (suppliedRun: CaptureRunInput, suppliedHoldings: readonly unknown[]) => {
    active();
    const run = captureCustodyRun(suppliedRun);
    const holdings = suppliedHoldings.map(value =>
      parsePhysicalHolding(Buffer.from(JSON.stringify(value))));
    return withSemanticCommit(async () => {
      active();
      const previous = await readEffectCaptureCustodyOriginal(run);
      const records = new Map((previous?.holdings ?? []).map(value =>
        [value.holding_cid, value]));
      for (const holding of holdings) {
        if (!['effect-source', 'effect-capture'].includes(holding.namespace)) {
          fail('InvalidEffectCaptureCustody');
        }
        const old = records.get(holding.holding_cid);
        if (old !== undefined && JSON.stringify(old) !== JSON.stringify(holding)) {
          fail('EffectCaptureCustodyConflict');
        }
        records.set(holding.holding_cid, holding);
      }
      const wire = JSON.stringify({
        version: 'actql-effect-capture-custody/0.1',
        store_authority_cid: configuration.storeAuthorityCid,
        run_definition: run.wire, holdings: [...records.values()],
      });
      const byteLength = Buffer.byteLength(wire, 'utf8');
      if (records.size > 4096 || byteLength >
          Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)) {
        fail('EffectCaptureCustodyLimitExceeded');
      }
      const path = captureCustodyPath(run);
      const confirmed = lastConfirmedEffectCaptureCustody;
      if (previous !== undefined && confirmed?.wire === wire) {
        const current = await lstat(path, {bigint: true});
        if (current.isFile() &&
            (['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'] as const)
              .every(field => current[field] === confirmed.state[field])) return;
      }
      // A failed write/sync/close never publishes or preserves this observation.
      // A changed body, replacement allocation or new Store uses real I/O.
      lastConfirmedEffectCaptureCustody = undefined;
      const bytes = Buffer.from(wire, 'utf8');
      const staging = resolve(stagingDirectory, `object-${randomUUID()}`);
      await writeExclusive(staging, bytes);
      await rename(staging, path);
      await syncDirectory(captureCustodyDirectory);
      const state = await lstat(path, {bigint: true});
      if (!state.isFile() || state.size !== BigInt(byteLength)) {
        fail('InvalidEffectCaptureCustody');
      }
      lastConfirmedEffectCaptureCustody = {wire, state};
    });
  };
  const listEffectCaptureCustodies = async ({after = '', limit = 100}: CaptureCustodyPage = {}) => {
    active();
    if (typeof after !== 'string' || after !== '' && !cidPattern.test(after) ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      fail('InvalidEffectCaptureCustodyPage');
    }
    const names = await readdir(captureCustodyDirectory);
    if (names.some(name => !/^[0-9a-f]{64}\.json$/u.test(name))) {
      fail('InvalidEffectCaptureCustody');
    }
    const selected = names.sort().filter(name =>
      `sha256:${name.slice(0, -5)}` > after).slice(0, limit);
    const result: Run[] = [];
    for (const name of selected) {
      let value: unknown;
      try {
        value = JSON.parse((await readBounded(resolve(captureCustodyDirectory,
          name), Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)))
          .toString('utf8'));
      } catch (error) {
        if ((error as CodedCause)?.code === 'ENOENT') continue;
        fail('InvalidEffectCaptureCustody', error);
      }
      const run = admitContract('run_definition', (value as {run_definition?: unknown}).run_definition);
      if (`${cidHex(run.identity)}.json` !== name) {
        fail('InvalidEffectCaptureCustody');
      }
      if (await readEffectCaptureCustodyOriginal(run) !== undefined) result.push(run);
    }
    return Object.freeze(result);
  };
  const forgetEffectCaptureCustodyOriginal = async (run: Run) => {
    active();
    lastConfirmedEffectCaptureCustody = undefined;
    try { await unlink(captureCustodyPath(run)); }
    catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
    await syncDirectory(captureCustodyDirectory);
  };
  const forgetEffectCaptureCustody = async (suppliedRun: CaptureRunInput) => {
    active();
    const run = captureCustodyRun(suppliedRun);
    await readEffectCaptureCustodyOriginal(run);
    return forgetEffectCaptureCustodyOriginal(run);
  };
  const retireEffectCaptureCustody = async (suppliedRun: CaptureRunInput) => {
    active();
    const run = captureCustodyRun(suppliedRun);
    const record = await readEffectCaptureCustodyOriginal(run);
    if (record === undefined) return false;
    // Validate the entire exact inventory before deleting any holding. A
    // missing record can be progress from an interrupted retirement pass.
    for (const expected of record.holdings) {
      const actual = await readPhysicalHolding(expected.holding_cid) ??
        await readPhysicalHoldingDeletion(expected.holding_cid);
      if (actual !== undefined && JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail('EffectCaptureCustodyConflict');
      }
    }
    for (const holding of record.holdings) {
      const retired = await retirePhysicalHolding(holding.holding_cid as string);
      if (retired.cleanup.status().pending) {
        const error = new PublicationStoreError('EffectCaptureCustodyCleanupPending') as CaptureCustodyCleanupFailure;
        error.cleanupPending = true;
        error.cleanupHandle = retired.cleanup;
        throw error;
      }
    }
    await forgetEffectCaptureCustodyOriginal(run);
    return true;
  };

  return {readEffectCaptureCustody, retainEffectCaptureCustody, listEffectCaptureCustodies,
    forgetEffectCaptureCustody, retireEffectCaptureCustody,
    clearEffectCaptureCustodyObservation() { lastConfirmedEffectCaptureCustody = undefined; }};
}
