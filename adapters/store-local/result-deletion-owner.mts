// One retired Result owns the unlink-to-durable-reclamation transition.
// The Store retains the shared capacity ledger and material-retention queue.
import type {Stats} from 'node:fs';
import {lstat, mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, quantity, readBounded, writeExclusive} from './publication-store-io.mjs';

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

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type ResultReadDemand = Parameters<typeof readBounded>[5];
type ResultDeletionMarker = Readonly<{
  version: 'actql-local-result-deletion/0.1';
  public_index_entry_cid: unknown;
  result_definition_cid: unknown;
  material_generation_cid: unknown;
}>;
type ResultIndexEntry = Readonly<{public_index_entry_cid: unknown; durable_result_binding_cids: readonly unknown[]}>;
type ResultBinding = Readonly<{result_definition_cid: unknown; material_generation_cid: unknown; byte_count: unknown}>;
type IndexContract = Readonly<{identity: unknown}>;
type ResultCleanup = ReturnType<typeof createResultDeletionOwner>;
type RetiredResult = Readonly<{marker: ResultDeletionMarker; cleanup: ResultCleanup; deleted: boolean}>;
type ResultRemoval = Readonly<{unlinkOriginal(): Promise<unknown>}>;
type ResultRetirementIndex<NativeIndex> = Readonly<{
  beginResultDeletionLifetime(): unknown;
  resultDeletionRecoveryRequired(): boolean;
  nativePublicationIndex(keyHash: string): NativeIndex | undefined;
}>;
type PreparedResultOwners = Readonly<{holders: ReadonlySet<unknown>; commitOwners: ReadonlySet<unknown>}>;
type ResultRetirementPorts<NativeIndex, Contract extends IndexContract, Removal extends ResultRemoval> = Readonly<{
  active(): unknown;
  cidHex(cid: unknown): string;
  currentDeliveryIndex(): ResultRetirementIndex<NativeIndex> | undefined;
  resultDeletionDirectory(keyHash: string): string;
  resultDeletionPath(keyHash: string, resultDefinitionCid: unknown): string;
  readOpeningDirectory(path: string): Promise<readonly string[]>;
  readMetadataDeletion(keyHash: string): Promise<unknown>;
  admitNativeIndexOriginal(native: NativeIndex): Readonly<{contract: Contract; entry: ResultIndexEntry}>;
  admitContract(name: 'public_index_entry', wire: string): Contract;
  parseContract(contract: Contract): unknown;
  readContract(cid: unknown, name: 'durable_result_binding'): Promise<Readonly<{contract: Contract}>>;
  requireCommittedResultBinding(key: unknown, resultDefinitionCid: unknown): Promise<Readonly<{
    entry: ResultIndexEntry; value: ResultBinding; }>>;
  syncDirectory(path: string): unknown;
  materialRetentionCurrent(): Promise<unknown>;
  retainMaterialOperation(operation: Promise<unknown>): void;
  activeResultReaders: ReadonlyMap<unknown, number>;
  preparedObjects: ReadonlyMap<unknown, PreparedResultOwners>;
  pendingResultDeletions: Map<string, ResultCleanup>;
  reclaimingMaterialCids: Set<unknown>;
  materialHasLiveReference(cid: unknown): Promise<boolean>;
  objectPath(cid: unknown): string;
  rememberPhysicalRemoval(cid: unknown, bytes: number, state?: Stats): Promise<Removal | undefined>;
  syncPhysicalRemovals(removals: ReadonlyMap<unknown, Removal | undefined>): Promise<unknown>;
  releasePhysicalCapacity(removals: ReadonlyMap<unknown, Removal | undefined>): Promise<unknown>;
}>;

export function createResultRetirement<NativeIndex, Contract extends IndexContract, Removal extends ResultRemoval>(
  configuration: Readonly<{maxObjectBytes: number}>,
  deletionsDirectory: string,
  indexesDirectory: string,
  {active, cidHex, currentDeliveryIndex, resultDeletionDirectory, resultDeletionPath,
    readOpeningDirectory, readMetadataDeletion, admitNativeIndexOriginal, admitContract, parseContract,
    readContract, requireCommittedResultBinding, syncDirectory, materialRetentionCurrent, retainMaterialOperation,
    activeResultReaders, preparedObjects, pendingResultDeletions, reclaimingMaterialCids, materialHasLiveReference,
    objectPath, rememberPhysicalRemoval, syncPhysicalRemovals, releasePhysicalCapacity}:
    ResultRetirementPorts<NativeIndex, Contract, Removal>,
) {
  const readResultDeletion = async (keyHash: string, resultDefinitionCid: unknown, readDemand?: ResultReadDemand) => {
    let directory;
    try {directory = await lstat(resultDeletionDirectory(keyHash));}
    catch (error) {if ((error as CodedCause)?.code === 'ENOENT') return undefined; throw error;}
    if (!directory.isDirectory() || directory.isSymbolicLink()) fail('InvalidPublicationDeletionStore');
    const path = resultDeletionPath(keyHash, resultDefinitionCid);
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes, undefined, undefined, false, readDemand); }
    catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationDeletionStore', error); }
    if (!exactKeys(value, [
      'version', 'public_index_entry_cid', 'result_definition_cid',
      'material_generation_cid',
    ]) || value.version !== 'actql-local-result-deletion/0.1' ||
        !cidPattern.test(value.public_index_entry_cid as string) ||
        value.result_definition_cid !== resultDefinitionCid ||
        !cidPattern.test(value.material_generation_cid as string)) {
      fail('InvalidPublicationDeletionStore');
    }
    return Object.freeze(value) as ResultDeletionMarker;
  };

  const ensureResultDeletionMarker = async (
    keyHash: string,
    resultDefinitionCid: unknown,
    value: ResultDeletionMarker,
  ) => {
    // Persist recovery intent before any marker or physical cleanup. Native
    // close alone cannot seal it; the Store waits for every original child.
    currentDeliveryIndex()!.beginResultDeletionLifetime();
    const directory = resultDeletionDirectory(keyHash);
    let createdDirectory = false;
    try {
      await mkdir(directory, {mode: 0o700});
      createdDirectory = true;
    } catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      if (!(await lstat(directory)).isDirectory()) {
        fail('InvalidPublicationDeletionStore');
      }
    }
    if (createdDirectory) await syncDirectory(deletionsDirectory);
    const path = resultDeletionPath(keyHash, resultDefinitionCid);
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    try { await writeExclusive(path, bytes); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        path, configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) fail('PublicationDeletionConflict');
    }
    await syncDirectory(directory);
    return path;
  };

  const createResultDeletionCleanup = async (
    keyHash: string,
    resultDefinitionCid: unknown,
    marker: ResultDeletionMarker,
    expectedBytes: number,
  ) => {
    const materialCid = marker.material_generation_cid;
    const deletionKey = `${keyHash}/${cidHex(resultDefinitionCid)}`;
    const existing = pendingResultDeletions.get(deletionKey);
    if (existing !== undefined) {
      return Object.freeze({marker, cleanup: existing, deleted: false});
    }
    let physicalRemoval: Removal | undefined;
    const cleanup = createResultDeletionOwner({
      serialize(run) {
        const operation = materialRetentionCurrent().then(run);
        retainMaterialOperation(operation.catch(() => {}));
        return operation;
      },
      ensureMarker: () => ensureResultDeletionMarker(
        keyHash, resultDefinitionCid, marker,
      ),
      async retention() {
        if ((activeResultReaders.get(materialCid) ?? 0) !== 0) return 'wait';
        const prepared = preparedObjects.get(materialCid);
        if (prepared !== undefined &&
            (prepared.holders.size !== 0 ||
              prepared.commitOwners.size !== 0)) return 'wait';
        if (await materialHasLiveReference(materialCid)) {
          return 'settled';
        }
        const currentPrepared = preparedObjects.get(materialCid);
        return currentPrepared !== undefined &&
          (currentPrepared.holders.size !== 0 ||
            currentPrepared.commitOwners.size !== 0) ? 'wait' : 'free';
      },
      markReclaiming() { reclaimingMaterialCids.add(materialCid); },
      async inspectAllocation() {
        let state;
        try { state = await lstat(objectPath(materialCid)); }
        catch (error) {
          if ((error as CodedCause)?.code !== 'ENOENT') throw error;
        }
        if (state === undefined) {
          physicalRemoval = await rememberPhysicalRemoval(materialCid,expectedBytes);
          return physicalRemoval === undefined ? 'missing' : 'missing-unconfirmed';
        }
        if (!state.isFile() || state.size !== expectedBytes) {
          fail('PublicationDurableBindingMismatch');
        }
        // Other Store-owned references can share this inode. Keep the base
        // name and capacity charge while any physical link remains.
        if(state.nlink>1)return 'shared';
        physicalRemoval = await rememberPhysicalRemoval(materialCid,expectedBytes,state);
        return 'exclusive';
      },
      unlink: () => physicalRemoval!.unlinkOriginal(),
      syncObjects: () => syncPhysicalRemovals(new Map([[materialCid, physicalRemoval]])),
      releaseCapacity() {
        return releasePhysicalCapacity(new Map([[materialCid, physicalRemoval]]));
      },
      settle(clearReclaiming) {
        pendingResultDeletions.delete(deletionKey);
        if (clearReclaiming) reclaimingMaterialCids.delete(materialCid);
      },
    });
    pendingResultDeletions.set(deletionKey, cleanup);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      marker,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const retireCommittedResult = async (key: unknown, resultDefinitionCid: unknown) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid,
    );
    const expectedBytes = selected.value.byte_count;
    if (!quantity(expectedBytes)) fail('InvalidPublicationDurableBinding');
    return createResultDeletionCleanup(
      indexKey(key),
      resultDefinitionCid,
      Object.freeze({
        version: 'actql-local-result-deletion/0.1',
        public_index_entry_cid: selected.entry.public_index_entry_cid,
        result_definition_cid: resultDefinitionCid,
        material_generation_cid: selected.value.material_generation_cid,
      }),
      expectedBytes,
    );
  };

  const recoverRetiredResults = async () => {
    active();
    const recovered: RetiredResult[] = [];
    if (!currentDeliveryIndex()!.resultDeletionRecoveryRequired()) return Object.freeze(recovered);
    for (const keyHash of await readOpeningDirectory(deletionsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
          !(await lstat(resultDeletionDirectory(keyHash))).isDirectory()) {
        fail('InvalidPublicationDeletionStore');
      }
      let indexBytes;
      const nativeIndex = currentDeliveryIndex()!.nativePublicationIndex(keyHash);
      try {
        if (nativeIndex === undefined) indexBytes = await readBounded(
          resolve(indexesDirectory, `${keyHash}.json`), configuration.maxObjectBytes);
      } catch (error) {
        if ((error as CodedCause)?.code === 'ENOENT' &&
            await readMetadataDeletion(keyHash) !== undefined) continue;
        throw error;
      }
      const nativeOriginal = nativeIndex === undefined ? undefined : admitNativeIndexOriginal(nativeIndex);
      const indexContract = nativeOriginal?.contract ?? admitContract('public_index_entry',indexBytes!.toString('utf8'));
      const entry = (nativeOriginal?.entry ?? parseContract(indexContract)) as ResultIndexEntry;
      for (const name of await readOpeningDirectory(resultDeletionDirectory(keyHash))) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
            !(await lstat(resolve(resultDeletionDirectory(keyHash), name))).isFile()) {
          fail('InvalidPublicationDeletionStore');
        }
        const resultDefinitionCid = `sha256:${name.slice(0, -5)}`;
        const marker = (await readResultDeletion(
          keyHash, resultDefinitionCid,
        ))!;
        if (marker.public_index_entry_cid !== indexContract.identity) {
          fail('InvalidPublicationDeletionStore');
        }
        const matches: ResultBinding[] = [];
        for (const bindingCid of entry.durable_result_binding_cids) {
          const binding = parseContract((await readContract(
            bindingCid, 'durable_result_binding',
          )).contract) as ResultBinding;
          if (binding.result_definition_cid === resultDefinitionCid) {
            matches.push(binding);
          }
        }
        if (matches.length !== 1 ||
            matches[0].material_generation_cid !==
              marker.material_generation_cid ||
            !quantity(matches[0].byte_count)) {
          fail('InvalidPublicationDeletionStore');
        }
        recovered.push(await createResultDeletionCleanup(
          keyHash,
          resultDefinitionCid,
          marker,
          matches[0].byte_count,
        ));
      }
    }
    return Object.freeze(recovered);
  };

  return {readResultDeletion, retireCommittedResult, recoverRetiredResults};
}
