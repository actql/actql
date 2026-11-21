import {readdir, rm, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createMetadataDeletionOwner} from './metadata-deletion-owner.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import type {createPhysicalHoldingLifecycle} from './physical-holding-record-writer.mjs';
import type {createResultRetirement} from './result-deletion-owner.mjs';
import {metadataContractObject} from './publication-metadata-inventory.mjs';
import type {createPublicationMetadataInventory, InventoryOriginal, MetadataContractObject} from './publication-metadata-inventory.mjs';
import {cidPattern, exactKeys, fail, quantity, readBounded, writeExclusive} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type DeletionResult = Readonly<{
  result_definition_cid: unknown;
  material_generation_cid: unknown;
  byte_count: number;
}>;
type DeletionMarker = Readonly<{
  version: 'actql-local-publication-metadata-deletion/0.1';
  namespace_id: string;
  authority_scope_cid: unknown;
  run_definition_cid: unknown;
  public_index_entry_cid: unknown;
  results: readonly DeletionResult[];
  contract_objects: readonly MetadataContractObject[];
  physical_holding_cids: readonly unknown[];
  requested_at: unknown;
}>;
type RetiredMarker = Readonly<{
  version: 'actql-local-publication-metadata-retired/0.1';
  run_definition_cid: unknown;
  namespace_id?: never;
  authority_scope_cid?: never;
}>;
type MetadataDeletionMarker = DeletionMarker | RetiredMarker;
type MetadataFenceOriginal = Readonly<{metadata_key: string; run_cid: unknown}>;
type MetadataFenceIndex = Readonly<{
  metadataDeletionFence(key: string): Readonly<{retired: 0 | 1; run_cid: string}> | undefined;
  finishMetadataDeletionFence(original: MetadataFenceOriginal): unknown;
  hasRunMetadataDeletionFence(runCid: unknown): boolean;
}>;

export function createPublicationMetadataDeletionMarkers(
  configuration: Readonly<{maxObjectBytes: number}>,
  metadataDeletionPath: (key: string) => string,
  metadataDeletionsDirectory: string,
  syncDirectory: (path: string) => unknown,
  currentDeliveryIndex: () => MetadataFenceIndex | undefined,
  metadataFencesAreReady: () => boolean,
  metadataDeletionIntents: Set<unknown>,
  pendingMetadataFenceCompletions: Map<string, MetadataFenceOriginal>,
  timestampPattern: RegExp,
) {
  const readMetadataDeletion = async (
    keyHash: string, readDemand?: Parameters<typeof readBounded>[5],
  ): Promise<MetadataDeletionMarker | undefined> => {
    let bytes: Awaited<ReturnType<typeof readBounded>>;
    try {
      bytes = await readBounded(
        metadataDeletionPath(keyHash), configuration.maxObjectBytes, undefined, undefined, false, readDemand,
      );
    } catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') {
        if (!metadataFencesAreReady()) return undefined;
        const fence = currentDeliveryIndex()!.metadataDeletionFence(keyHash);
        if (fence === undefined) return undefined;
        if (fence.retired !== 1) fail('InvalidPublicationMetadataDeletionStore');
        return Object.freeze({version:'actql-local-publication-metadata-retired/0.1',
          run_definition_cid:fence.run_cid});
      }
      throw error;
    }
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationMetadataDeletionStore', error);
    }
    if (exactKeys(value, ['version', 'run_definition_cid']) &&
        value.version ===
          'actql-local-publication-metadata-retired/0.1' &&
        cidPattern.test(value.run_definition_cid as string)) {
      return Object.freeze(value) as RetiredMarker;
    }
    if (!exactKeys(value, [
      'version', 'namespace_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'results', 'contract_objects',
      'physical_holding_cids', 'requested_at',
    ]) ||
        value.version !== 'actql-local-publication-metadata-deletion/0.1' ||
        typeof value.namespace_id !== 'string' || value.namespace_id.length === 0 ||
        !cidPattern.test(value.authority_scope_cid as string) ||
        !cidPattern.test(value.run_definition_cid as string) ||
        !cidPattern.test(value.public_index_entry_cid as string) ||
        !Array.isArray(value.results) || value.results.length === 0 ||
        value.results.some((result: unknown) => !exactKeys(result, [
          'result_definition_cid', 'material_generation_cid', 'byte_count',
        ]) || !cidPattern.test(result.result_definition_cid as string) ||
          !cidPattern.test(result.material_generation_cid as string) ||
          !quantity(result.byte_count)) ||
        new Set(value.results.map((result: DeletionResult) => result.result_definition_cid))
          .size !== value.results.length ||
        !Array.isArray(value.contract_objects) ||
        value.contract_objects.length === 0 ||
        value.contract_objects.some((object: unknown) => !metadataContractObject(object)) ||
        new Set(value.contract_objects.map((object: MetadataContractObject) => object.semantic_cid))
          .size !== value.contract_objects.length ||
        [...value.contract_objects]
          .sort((left: MetadataContractObject, right: MetadataContractObject) =>
            (left.semantic_cid as string).localeCompare(right.semantic_cid as string))
          .map((object: MetadataContractObject) => object.semantic_cid).join('\0') !==
        value.contract_objects.map((object: MetadataContractObject) => object.semantic_cid).join('\0') ||
        !Array.isArray(value.physical_holding_cids) ||
        value.physical_holding_cids.some((cid: unknown) => !cidPattern.test(cid as string)) ||
        new Set(value.physical_holding_cids).size !==
          value.physical_holding_cids.length ||
        [...value.physical_holding_cids].sort().join('\0') !==
          value.physical_holding_cids.join('\0') ||
        !timestampPattern.test(value.requested_at as string)) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    return Object.freeze(value) as DeletionMarker;
  };

  const compactMetadataDeletion = async (keyHash: string, runDefinitionCid: unknown): Promise<RetiredMarker> => {
    const value: RetiredMarker = Object.freeze({
      version: 'actql-local-publication-metadata-retired/0.1',
      run_definition_cid: runDefinitionCid,
    });
    const original = Object.freeze({metadata_key:keyHash,run_cid:runDefinitionCid});
    pendingMetadataFenceCompletions.set(keyHash,original);
    currentDeliveryIndex()!.finishMetadataDeletionFence(original);
    pendingMetadataFenceCompletions.delete(keyHash);
    try { await unlink(metadataDeletionPath(keyHash)); }
    catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
    // Absence after a lost unlink/ACK reply is not its directory ACK.
    await syncDirectory(metadataDeletionsDirectory);
    return value;
  };

  const ensureMetadataDeletion = async (keyHash: string, value: DeletionMarker) => {
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    metadataDeletionIntents.add(value.run_definition_cid);
    try { await writeExclusive(metadataDeletionPath(keyHash), bytes); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        metadataDeletionPath(keyHash), configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) {
        fail('PublicationMetadataDeletionConflict');
      }
    }
    await syncDirectory(metadataDeletionsDirectory);
    return readMetadataDeletion(keyHash);
  };

  const runMetadataDeletionStarted = async (runDefinitionCid: unknown) => {
    return metadataDeletionIntents.has(runDefinitionCid) ||
      currentDeliveryIndex()!.hasRunMetadataDeletionFence(runDefinitionCid);
  };
  return {readMetadataDeletion, compactMetadataDeletion, ensureMetadataDeletion, runMetadataDeletionStarted};
}

type MetadataRetirementKey = Readonly<{namespaceId: unknown; authorityScopeCid: unknown; runDefinitionCid: unknown}>;
type MetadataRetirementEntry = Readonly<{namespace_id: string; authority_scope_cid: unknown; run_definition_cid: unknown;
  public_index_entry_cid: unknown}>;
type MetadataRetirementIndex = Readonly<{
  finishMetadataDeletionFence(completion: MetadataFenceOriginal): unknown;
  pendingPublication(publicIndexCid: unknown): InventoryOriginal | undefined;
  nativePublicationInventory(publicIndexCid: unknown): InventoryOriginal | undefined;
  retireNativePublicationInventory(original: InventoryOriginal | undefined, fence: MetadataFenceOriginal): unknown;
}>;
type MetadataRetirementCleanup = ReturnType<typeof createMetadataDeletionOwner>;
type MetadataRetirementResult = Readonly<{marker: DeletionMarker; cleanup: MetadataRetirementCleanup; deleted: boolean}>;
type ExistingMarkerPorts = ReturnType<typeof createPublicationMetadataDeletionMarkers>;
type ExistingInventoryPorts = ReturnType<typeof createPublicationMetadataInventory>;
type MetadataRetirementPorts<Entry extends MetadataRetirementEntry, Removal> =
  Pick<ExistingMarkerPorts, 'readMetadataDeletion' | 'ensureMetadataDeletion' | 'compactMetadataDeletion'> &
  Pick<ExistingInventoryPorts, 'publicationRecoveryValue' | 'readMetadataInventory'> & Readonly<{
    active(): unknown;
    currentDeliveryIndex(): MetadataRetirementIndex | undefined;
    pendingMetadataDeletions: Map<string, MetadataRetirementCleanup>;
    pendingMetadataDeletionMarkers: Map<string, DeletionMarker>;
    pendingMetadataFenceCompletions: Map<string, MetadataFenceOriginal>;
    metadataDeletionIntents: Set<unknown>;
    metadataRetentionCurrent(): Promise<unknown>;
    retainMetadataOperation(operation: Promise<unknown>): void;
    syncPhysicalRemovals(objects: ReadonlyMap<unknown, Removal>): Promise<unknown>;
    releasePhysicalCapacity(objects: ReadonlyMap<unknown, Removal>): Promise<unknown>;
    createResultDeletionCleanup: ReturnType<typeof createResultRetirement>['createResultDeletionCleanup'];
    metadataHoldingHasOtherOwner(holdingCid: unknown, excludedCid: unknown): Promise<boolean>;
    retirePhysicalHolding: ReturnType<typeof createPhysicalHoldingLifecycle>['retirePhysicalHolding'];
    removeRunMetadataDirectories(runCid: unknown, keyHash: string): Promise<unknown>;
    admitContract(name: 'public_index_entry', wire: string): Readonly<{identity: unknown}>;
    syncDirectory(path: string): unknown;
    durablyConfirmedIndexes: Map<string, unknown>;
    reclaimMetadataContract(excludedCid: unknown, object: MetadataContractObject, unconfirmedObjects: Map<string, Removal>): Promise<unknown>;
    resultDeletionDirectory(keyHash: string): string;
    metadataInventoryPath(cid: unknown): string;
    inspectCommittedIndexRaw(key: MetadataRetirementKey): Promise<Entry | undefined>;
    collectRunMetadataContracts(runCid: unknown, keyHash: string, inventoryCids: readonly unknown[]): Promise<readonly unknown[]>;
    metadataResultBindings(entry: Entry): Promise<readonly DeletionResult[]>;
    bindMetadataContractObjects(contractCids: readonly unknown[]): Promise<readonly MetadataContractObject[]>;
  }>;

export function createPublicationMetadataRetirement<Entry extends MetadataRetirementEntry, Removal>(
  configuration: Readonly<{maxObjectBytes: number}>,
  indexesDirectory: string, deletionsDirectory: string, metadataInventoriesDirectory: string,
  metadataDeletionsDirectory: string, timestampPattern: RegExp,
  {active, currentDeliveryIndex, pendingMetadataDeletions, pendingMetadataDeletionMarkers,
    pendingMetadataFenceCompletions, metadataDeletionIntents, metadataRetentionCurrent, retainMetadataOperation,
    publicationRecoveryValue, syncPhysicalRemovals, releasePhysicalCapacity, createResultDeletionCleanup,
    metadataHoldingHasOtherOwner, retirePhysicalHolding, removeRunMetadataDirectories, admitContract, syncDirectory,
    durablyConfirmedIndexes, reclaimMetadataContract, resultDeletionDirectory, metadataInventoryPath, compactMetadataDeletion,
    readMetadataDeletion, inspectCommittedIndexRaw, readMetadataInventory, collectRunMetadataContracts, ensureMetadataDeletion,
    metadataResultBindings, bindMetadataContractObjects}: MetadataRetirementPorts<Entry, Removal>,
) {
  const createMetadataDeletionCleanup = async (keyHash: string, marker: DeletionMarker) => {
    const existing = pendingMetadataDeletions.get(keyHash);
    if (existing !== undefined) {
      return Object.freeze({marker, cleanup: existing, deleted: false});
    }
    let recoveryOriginal: InventoryOriginal | undefined, recoveryCaptured = false, recoveryTransferred = false;
    const cleanup = createMetadataDeletionOwner<DeletionResult, MetadataContractObject, Removal, unknown>(marker, {
      serialize(run) {
        const operation = metadataRetentionCurrent().then(async () => {
          const completion=pendingMetadataFenceCompletions.get(keyHash);
          if(completion!==undefined) {
            currentDeliveryIndex()!.finishMetadataDeletionFence(completion);
            pendingMetadataFenceCompletions.delete(keyHash);
          }
          if (!recoveryTransferred) {
            if(!recoveryCaptured) {
              recoveryOriginal = currentDeliveryIndex()!.pendingPublication(marker.public_index_entry_cid) ??
                currentDeliveryIndex()!.nativePublicationInventory(marker.public_index_entry_cid);
              recoveryCaptured=true;
            }
            if (recoveryOriginal !== undefined) {
              const inventory = publicationRecoveryValue(recoveryOriginal);
              if (inventory.namespace_id !== marker.namespace_id ||
                  inventory.authority_scope_cid !== marker.authority_scope_cid ||
                  inventory.run_definition_cid !== marker.run_definition_cid ||
                  inventory.physical_holding_cids.join('\0') !== marker.physical_holding_cids.join('\0') ||
                  inventory.contract_objects.some(object => !marker.contract_objects.some(
                    member => member.semantic_cid === object.semantic_cid))) {
                fail('InvalidPublicationMetadataDeletionStore');
              }
              // The same durable marker now owns all cleanup. Settle its
              // pending lookup row before physical work so an Unknown retry
              // reaches this exact native mutation before any other DB read.
            }
            currentDeliveryIndex()!.retireNativePublicationInventory(recoveryOriginal,
              {metadata_key:keyHash,run_cid:marker.run_definition_cid});
            metadataDeletionIntents.delete(marker.run_definition_cid);
            recoveryTransferred = true;
          }
          return run();
        });
        retainMetadataOperation(operation.catch(() => {}));
        return operation;
      },
      syncObjects: objects => syncPhysicalRemovals(objects),
      releaseUnconfirmed(objects) {
        return releasePhysicalCapacity(objects);
      },
      async retireResult(result) {
        const retired = await createResultDeletionCleanup(
          keyHash,
          result.result_definition_cid,
          Object.freeze({
            version: 'actql-local-result-deletion/0.1',
            public_index_entry_cid: marker.public_index_entry_cid,
            result_definition_cid: result.result_definition_cid,
            material_generation_cid: result.material_generation_cid,
          }),
          result.byte_count,
        );
        if (retired.cleanup.status().pending) await retired.cleanup.retry();
        return !retired.cleanup.status().pending;
      },
      async retireHolding(holdingCid) {
        if (await metadataHoldingHasOtherOwner(
          holdingCid, marker.public_index_entry_cid,
        )) return true;
        const retired = await retirePhysicalHolding(holdingCid as string);
        return !retired.cleanup.status().pending;
      },
      removeRunDirectories: () => removeRunMetadataDirectories(
        marker.run_definition_cid, keyHash,
      ),
      async removeIndex() {
        const indexPath = resolve(indexesDirectory, `${keyHash}.json`);
        let indexBytes;
        try {
          indexBytes = await readBounded(
            indexPath, configuration.maxObjectBytes,
          );
        } catch (error) {
          if ((error as CodedCause)?.code !== 'ENOENT') throw error;
        }
        if (indexBytes !== undefined) {
          const index = admitContract(
            'public_index_entry', indexBytes.toString('utf8'),
          );
          if (index.identity !== marker.public_index_entry_cid) {
            fail('InvalidPublicationMetadataDeletionStore');
          }
          await unlink(indexPath);
          await syncDirectory(indexesDirectory);
        }
        durablyConfirmedIndexes.delete(keyHash);
      },
      reclaimContract: (object, unconfirmedObjects) =>
        reclaimMetadataContract(
          marker.public_index_entry_cid, object, unconfirmedObjects,
        ),
      async removeResultDeletionDirectory() {
        try {
          await rm(resultDeletionDirectory(keyHash), {
            recursive: true, force: false,
          });
          await syncDirectory(deletionsDirectory);
        } catch (error) {
          if ((error as CodedCause)?.code !== 'ENOENT') throw error;
        }
      },
      async removeInventory() {
        try {
          await unlink(metadataInventoryPath(marker.public_index_entry_cid));
          await syncDirectory(metadataInventoriesDirectory);
        } catch (error) {
          if ((error as CodedCause)?.code !== 'ENOENT') throw error;
        }
      },
      compactMarker: () => compactMetadataDeletion(
        keyHash, marker.run_definition_cid,
      ),
      settle() {
        pendingMetadataDeletions.delete(keyHash);
        pendingMetadataDeletionMarkers.delete(keyHash);
      },
    });
    pendingMetadataDeletions.set(keyHash, cleanup);
    pendingMetadataDeletionMarkers.set(keyHash, marker);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      marker,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const retireCommittedPublicationMetadata = async (key: MetadataRetirementKey, requestedAt: unknown) => {
    active();
    if (!timestampPattern.test(requestedAt as string)) {
      fail('InvalidPublicationMetadataDeletion');
    }
    const keyHash = indexKey(key);
    const pending=pendingMetadataDeletions.get(keyHash);
    if(pending!==undefined) return Object.freeze({marker:pendingMetadataDeletionMarkers.get(keyHash),
      cleanup:pending,deleted:false});
    let marker = await readMetadataDeletion(keyHash);
    if (marker?.version ===
        'actql-local-publication-metadata-retired/0.1') {
      const cleanup = Object.freeze({
        status: () => Object.freeze({pending: false, errors: Object.freeze([])}),
        retry: () => Promise.resolve(Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        })),
      });
      return Object.freeze({marker, cleanup, deleted: true});
    }
    if (marker === undefined) {
      const entry = await inspectCommittedIndexRaw(key);
      if (entry === undefined) fail('PublicationLookupDenied');
      const inventory = await readMetadataInventory(
        entry.public_index_entry_cid,
      );
      if (inventory === undefined ||
          inventory.public_index_entry_cid !==
            entry.public_index_entry_cid) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const contractCids = await collectRunMetadataContracts(
        entry.run_definition_cid,
        keyHash,
        inventory.contract_objects.map(object => object.semantic_cid),
      );
      marker = await ensureMetadataDeletion(keyHash, Object.freeze({
        version: 'actql-local-publication-metadata-deletion/0.1',
        namespace_id: entry.namespace_id,
        authority_scope_cid: entry.authority_scope_cid,
        run_definition_cid: entry.run_definition_cid,
        public_index_entry_cid: entry.public_index_entry_cid,
        results: await metadataResultBindings(entry),
        contract_objects: await bindMetadataContractObjects(contractCids),
        physical_holding_cids: inventory.physical_holding_cids,
        requested_at: requestedAt,
      }));
    }
    // A retired marker from the reread has no namespace or authority fields.
    // It must take the existing identity-mismatch path for this selected key.
    if (marker!.namespace_id !== key.namespaceId ||
        marker!.authority_scope_cid !== key.authorityScopeCid ||
        marker!.run_definition_cid !== key.runDefinitionCid) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    return createMetadataDeletionCleanup(keyHash, marker as DeletionMarker);
  };

  const recoverRetiredMetadata = async () => {
    active();
    const recovered: MetadataRetirementResult[] = [];
    for (const name of await readdir(metadataDeletionsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataDeletionStore');
      }
      const keyHash = name.slice(0, -5);
      const marker = (await readMetadataDeletion(keyHash))!;
      if (marker.version !==
          'actql-local-publication-metadata-retired/0.1') {
        recovered.push(await createMetadataDeletionCleanup(keyHash, marker));
      }
    }
    return Object.freeze(recovered);
  };

  return {retireCommittedPublicationMetadata, recoverRetiredMetadata};
}
