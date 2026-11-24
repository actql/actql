import {createHash} from 'node:crypto';
import type {Stats} from 'node:fs';
import {lstat, readdir, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {createPhysicalHoldingRecordReader} from './physical-holding-record-reader.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationIndexReader, PublicationIndexEntry} from './publication-index-reader.mjs';
import type {createPublicationMetadataDeletionMarkers} from './publication-metadata-deletion-markers.mjs';
import type {createPublicationMetadataInventory, InventoryOriginal, MetadataContractObject} from './publication-metadata-inventory.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {fail, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RemovalUsage = Readonly<{bytes: number; objects: number}>;
type NativeContractOriginal = Readonly<{semantic_cid: string; name: string; wire: string; byte_count: number}>;
type NativeMaterialReference = Readonly<{
  metadata_key: string;
  public_index_cid: string;
  binding_cid: string;
  result_definition_cid: string;
}>;
type ResultBinding = Readonly<{material_generation_cid: unknown; result_definition_cid: unknown}>;
type ResultDeletion = Readonly<{public_index_entry_cid: unknown; material_generation_cid: unknown}>;
type AdmitNativeIndex<Contract extends PublicationContract> =
  ReturnType<typeof createPublicationIndexReader<Contract>>['admitNativeIndexOriginal'];
type NativeReferenceIndex<Contract extends PublicationContract> = Readonly<{
  nativePublicationReferenceOwners(kind: 'contract' | 'holding', cid: unknown, excludedCid?: unknown): readonly InventoryOriginal[];
  publicationContract(cid: unknown): NativeContractOriginal | undefined;
  removePublicationContract(original: NativeContractOriginal): RemovalUsage;
  nativePublicationMaterialReferences(
    cid: unknown, afterIndex: string | undefined, afterResult: string | undefined,
  ): readonly NativeMaterialReference[];
  nativePublicationIndex(keyHash: string): Parameters<AdmitNativeIndex<Contract>>[0] | undefined;
}>;
type ReferenceDirectories = Readonly<{
  metadataInventoriesDirectory: string;
  contractsDirectory: string;
  physicalHoldingsDirectory: string;
  indexesDirectory: string;
}>;
type ReferencePorts<Contract extends PublicationContract, Removal> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'admitContract' | 'parseContract'> &
  Pick<ReturnType<typeof createPublicationSemanticReader<Contract>>, 'readContract'> &
  Pick<ReturnType<typeof createPublicationMetadataInventory>, 'readMetadataInventory' | 'publicationRecoveryValue'> &
  Pick<ReturnType<typeof createPublicationMetadataDeletionMarkers>, 'readMetadataDeletion'> &
  Pick<ReturnType<typeof createPhysicalHoldingRecordReader>, 'readPhysicalHoldingAt'> & Readonly<{
    currentDeliveryIndex(): NativeReferenceIndex<Contract> | undefined;
    accountNativePublication(usage: RemovalUsage): void;
    contractPath(cid: unknown): string;
    objectPath(cid: unknown): string;
    syncDirectory(path: string): unknown;
    rememberPhysicalRemoval(cid: unknown, bytes: number, state?: Stats): Promise<Removal | undefined>;
    confirmPhysicalRemovals(removals: ReadonlyMap<unknown, Removal>): Promise<unknown>;
    withSemanticCommit<T>(operation: () => Promise<T>): Promise<T>;
    admitNativeIndexOriginal: AdmitNativeIndex<Contract>;
    readResultDeletion(keyHash: string, resultDefinitionCid: unknown): Promise<ResultDeletion | undefined>;
  }>;

export function createPublicationReferenceOwner<Contract extends PublicationContract, Removal>(
  configuration: Readonly<{maxObjects: number; maxObjectBytes: number}>,
  {metadataInventoriesDirectory, contractsDirectory, physicalHoldingsDirectory, indexesDirectory}: ReferenceDirectories,
  preparedSchemas: ReadonlyMap<unknown, Readonly<{holders: ReadonlySet<unknown>}>>,
  {currentDeliveryIndex, accountNativePublication, contractPath, objectPath, syncDirectory, rememberPhysicalRemoval,
    confirmPhysicalRemovals, withSemanticCommit, admitNativeIndexOriginal, readResultDeletion,
    admitContract, parseContract, readContract, readMetadataInventory, publicationRecoveryValue,
    readMetadataDeletion, readPhysicalHoldingAt}: ReferencePorts<Contract, Removal>,
) {
  const metadataContractHasLiveReference = async (
    semanticCid: unknown,
    excludedPublicIndexEntryCid?: unknown,
  ) => {
    for (const original of currentDeliveryIndex()!.nativePublicationReferenceOwners(
      'contract', semanticCid, excludedPublicIndexEntryCid)) {
      const inventory = publicationRecoveryValue(original);
      if (!inventory.contract_objects.some(object => object.semantic_cid === semanticCid)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const keyHash = indexKey({namespaceId:inventory.namespace_id,
        authorityScopeCid:inventory.authority_scope_cid,runDefinitionCid:inventory.run_definition_cid});
      if (await readMetadataDeletion(keyHash) !== undefined) continue;
      return true;
    }
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = (await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      ))!;
      const keyHash = indexKey({
        namespaceId: inventory.namespace_id,
        authorityScopeCid: inventory.authority_scope_cid,
        runDefinitionCid: inventory.run_definition_cid,
      });
      if (inventory.public_index_entry_cid === excludedPublicIndexEntryCid ||
          await readMetadataDeletion(keyHash) !== undefined) continue;
      if (inventory.contract_objects.some(object =>
        object.semantic_cid === semanticCid)) return true;
    }
    return false;
  };

  const metadataHoldingHasOtherOwner = async (
    holdingCid: unknown, excludedPublicIndexEntryCid: unknown,
  ) => {
    for (const original of currentDeliveryIndex()!.nativePublicationReferenceOwners(
      'holding', holdingCid, excludedPublicIndexEntryCid)) {
      if (!publicationRecoveryValue(original).physical_holding_cids.includes(holdingCid)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      return true;
    }
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = (await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      ))!;
      if (inventory.public_index_entry_cid !==
            excludedPublicIndexEntryCid &&
          inventory.physical_holding_cids.includes(holdingCid)) {
        return true;
      }
    }
    return false;
  };

  const pendingNativeMetadataReclaims = new Map<unknown, NativeContractOriginal>();
  const reclaimMetadataContractInternal = async (
    excludedPublicIndexEntryCid: unknown,
    object: MetadataContractObject,
    unconfirmedObjects: Map<unknown, Removal>,
  ) => {
    if (preparedSchemas.get(object.semantic_cid)?.holders.size! > 0 ||
        await metadataContractHasLiveReference(
      object.semantic_cid, excludedPublicIndexEntryCid,
    )) return;
    if (object.native === 'sqlite') {
      let original = pendingNativeMetadataReclaims.get(object.semantic_cid);
      if (original === undefined) original = currentDeliveryIndex()!.publicationContract(object.semantic_cid);
      if (original === undefined) return; // A durable deletion marker owns this exact idempotent removal.
      if (original.byte_count !== object.byte_count ||
          `sha256:${createHash('sha256').update(original.wire,'utf8').digest('hex')}` !== object.body_sha256) {
        fail('PublicationContractCorrupt');
      }
      pendingNativeMetadataReclaims.set(object.semantic_cid,original);
      accountNativePublication(currentDeliveryIndex()!.removePublicationContract(original));
      pendingNativeMetadataReclaims.delete(object.semantic_cid);
      return;
    }
    const semanticPath = contractPath(object.semantic_cid);
    let semanticState;
    try { semanticState = await lstat(semanticPath); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'ENOENT') throw error;
    }
    if (semanticState !== undefined) {
      if (!semanticState.isFile() ||
          semanticState.size !== object.byte_count) {
        fail('InvalidPublicationContractObject');
      }
      const physicalState = await lstat(objectPath(object.physical_cid));
      if (!physicalState.isFile() ||
          physicalState.dev !== semanticState.dev ||
          physicalState.ino !== semanticState.ino ||
          physicalState.size !== object.byte_count) {
        fail('PublicationContractCorrupt');
      }
      // Another Store directory still needs the canonical contract lookup.
      if (semanticState.nlink > 2) return;
      await unlink(semanticPath);
      await syncDirectory(contractsDirectory);
    }
    let physicalState;
    try { physicalState = await lstat(objectPath(object.physical_cid)); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'ENOENT') throw error;
    }
    if (physicalState === undefined) {
      const removal = await rememberPhysicalRemoval(object.physical_cid,object.byte_count);
      if (removal !== undefined) unconfirmedObjects.set(object.physical_cid, removal);
      return;
    }
    if (!physicalState.isFile() ||
        physicalState.size !== object.byte_count) {
      fail('InvalidPublicationStoreObject');
    }
    if (physicalState.nlink > 1) return;
    const removal = await rememberPhysicalRemoval(object.physical_cid,object.byte_count,physicalState);
    unconfirmedObjects.set(object.physical_cid, removal!);
    await confirmPhysicalRemovals(unconfirmedObjects);
    unconfirmedObjects.clear();
  };

  const reclaimMetadataContract = (...args: Parameters<typeof reclaimMetadataContractInternal>) =>
    withSemanticCommit(() => reclaimMetadataContractInternal(...args));

  const materialHasLiveReference = async (materialCid: unknown) => {
    for (const name of await readdir(physicalHoldingsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      const holding = await readPhysicalHoldingAt(
        resolve(physicalHoldingsDirectory, name),
        `sha256:${name.slice(0, -5)}`,
      );
      if (holding!.objects.some(object => object.cid === materialCid)) {
        return true;
      }
    }
    const bindings = new Map<string, ReturnType<typeof readContract>>();
    const bindingOriginal = (cid: string) => {
      if (!bindings.has(cid)) bindings.set(cid,readContract(cid,'durable_result_binding'));
      return bindings.get(cid)!;
    };
    let afterIndex: string | undefined, afterResult: string | undefined, visited = 0n;
    const maximum = BigInt(configuration.maxObjects) * BigInt(configuration.maxObjects);
    while (true) {
      const rows = currentDeliveryIndex()!.nativePublicationMaterialReferences(materialCid,afterIndex,afterResult);
      if (rows.length === 0) break;
      visited += BigInt(rows.length);
      if (visited > maximum) fail('PublicationStoreObjectLimit');
      for (const reference of rows) {
        const native = currentDeliveryIndex()!.nativePublicationIndex(reference.metadata_key);
        if (native === undefined) {
          if (await readMetadataDeletion(reference.metadata_key) !== undefined) continue;
          fail('InvalidPublicationMetadataInventoryStore');
        }
        const original = admitNativeIndexOriginal(native);
        if (original.contract.identity !== reference.public_index_cid ||
            !original.entry.durable_result_binding_cids.includes(reference.binding_cid)) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
        const binding = (await bindingOriginal(reference.binding_cid)).value as ResultBinding;
        if (binding.material_generation_cid !== materialCid ||
            binding.result_definition_cid !== reference.result_definition_cid) fail('PublicationDurableBindingMismatch');
        const deletion = await readResultDeletion(reference.metadata_key,reference.result_definition_cid);
        if (deletion === undefined) return true;
        if (deletion.public_index_entry_cid !== reference.public_index_cid ||
            deletion.material_generation_cid !== materialCid) fail('InvalidPublicationDeletionStore');
      }
      const last = rows[rows.length - 1];
      afterIndex = last.public_index_cid; afterResult = last.result_definition_cid;
    }
    for (const name of await readdir(indexesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationStoreIndex');
      }
      const keyHash = name.slice(0, -5);
      const bytes = await readBounded(
        resolve(indexesDirectory, name), configuration.maxObjectBytes,
      );
      const indexContract = admitContract(
        'public_index_entry', bytes.toString('utf8'),
      );
      const entry = parseContract(indexContract) as Pick<PublicationIndexEntry, 'durable_result_binding_cids'>;
      for (const bindingCid of entry.durable_result_binding_cids) {
        const binding = (await bindingOriginal(bindingCid)).value as ResultBinding;
        if (binding.material_generation_cid !== materialCid) continue;
        const deletion = await readResultDeletion(
          keyHash, binding.result_definition_cid,
        );
        if (deletion === undefined) return true;
        if (deletion.public_index_entry_cid !== indexContract.identity ||
            deletion.material_generation_cid !==
              binding.material_generation_cid) {
          fail('InvalidPublicationDeletionStore');
        }
      }
    }
    return false;
  };

  return {metadataContractHasLiveReference, metadataHoldingHasOtherOwner, reclaimMetadataContract, materialHasLiveReference};
}
