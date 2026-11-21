import {lstat} from 'node:fs/promises';
import {closedMetadataObjectExtent} from './physical-holding-record-reader.mjs';
import type {createPhysicalHoldingRecordReader} from './physical-holding-record-reader.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, quantity, readBounded, writeExclusive} from './publication-store-io.mjs';

type MetadataReadDemand = NonNullable<
  Parameters<ReturnType<typeof createPhysicalHoldingRecordReader>['readPhysicalHoldingAt']>[2]
> & {release(fields: number): unknown};
type CodedCause = Readonly<{code?: unknown}> | null | undefined;

// Keep the old RegExp coercion for wire CIDs. The type leaves their
// representation unknown until the original identity or path check uses them.
type InventorySource = Readonly<{public_index_entry_cid: unknown}>;
type MetadataIdentity = InventorySource & Readonly<{
  namespace_id: string;
  authority_scope_cid: unknown;
  run_definition_cid: unknown;
  publication_attempt_cid: unknown;
}>;
type ContractExtent = Readonly<{semantic_cid: unknown; byte_count: number}>;
export type MetadataContractObject = ContractExtent & (
  Readonly<{physical_cid: unknown}> | Readonly<{native: 'sqlite'; body_sha256: unknown}>
);
type MetadataInventory = MetadataIdentity & Readonly<{
  version: 'actql-local-publication-metadata-inventory/0.1';
  contract_objects: readonly MetadataContractObject[];
  physical_holding_cids: readonly unknown[];
}>;
export type InventoryOriginal = Readonly<{public_index_cid: unknown; inventory_wire: string}>;
type InventoryIndex = Readonly<{
  nativePublicationInventory(cid: unknown, readDemand?: MetadataReadDemand): InventoryOriginal | undefined;
}>;
type HoldingRead = (cid: unknown, readDemand?: MetadataReadDemand) => Promise<unknown>;

export const metadataContractObject = (object: unknown): object is MetadataContractObject => object !== null && typeof object === 'object' &&
  cidPattern.test((object as {semantic_cid: string}).semantic_cid) &&
  quantity((object as {byte_count: unknown}).byte_count) && (
    exactKeys(object, ['semantic_cid','physical_cid','byte_count']) && cidPattern.test(object.physical_cid as string) ||
    exactKeys(object, ['semantic_cid','native','body_sha256','byte_count']) &&
      object.native === 'sqlite' && cidPattern.test(object.body_sha256 as string));

export function createPublicationMetadataInventory(
  configuration: Readonly<{maxObjectBytes: number}>,
  metadataInventoriesDirectory: string,
  metadataInventoryPath: (cid: unknown) => string,
  syncDirectory: (path: string) => unknown,
  getDeliveryIndex: () => InventoryIndex | undefined,
  stageMetadataInventory: (original: InventoryOriginal, native: boolean) => unknown,
  readPhysicalHolding: HoldingRead,
  readPhysicalHoldingDeletion: HoldingRead,
  readMetadataDeletion: (key: string) => Promise<unknown>,
) {
  const parseMetadataInventory = (bytes: Buffer): MetadataInventory => {
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationMetadataInventoryStore', error);
    }
    if (!exactKeys(value, [
      'version', 'namespace_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'publication_attempt_cid', 'contract_objects',
      'physical_holding_cids',
    ]) ||
        value.version !== 'actql-local-publication-metadata-inventory/0.1' ||
        typeof value.namespace_id !== 'string' || value.namespace_id.length === 0 ||
        !cidPattern.test(value.authority_scope_cid as string) ||
        !cidPattern.test(value.run_definition_cid as string) ||
        !cidPattern.test(value.public_index_entry_cid as string) ||
        !cidPattern.test(value.publication_attempt_cid as string) ||
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
        !value.contract_objects.some((object: MetadataContractObject) =>
          object.semantic_cid === value.public_index_entry_cid) ||
        !Array.isArray(value.physical_holding_cids) ||
        value.physical_holding_cids.some((cid: unknown) => !cidPattern.test(cid as string)) ||
        new Set(value.physical_holding_cids).size !==
          value.physical_holding_cids.length ||
        [...value.physical_holding_cids].sort().join('\0') !==
          value.physical_holding_cids.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return Object.freeze({
      ...value,
      contract_objects: Object.freeze(value.contract_objects.map((object: MetadataContractObject) =>
        Object.freeze({...object}))),
      physical_holding_cids: Object.freeze([...value.physical_holding_cids]),
    }) as MetadataInventory;
  };

  const readMetadataInventory = async (publicIndexEntryCid: unknown, readDemand?: MetadataReadDemand) => {
    const native = getDeliveryIndex()?.nativePublicationInventory(publicIndexEntryCid, readDemand);
    if (native !== undefined) return publicationRecoveryValue(native);
    let bytes: Awaited<ReturnType<typeof readBounded>>;
    try {
      bytes = await readBounded(
        metadataInventoryPath(publicIndexEntryCid),
        configuration.maxObjectBytes, undefined, undefined, false, readDemand,
      );
    } catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    const inventory = parseMetadataInventory(bytes);
    if (inventory.public_index_entry_cid !== publicIndexEntryCid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return inventory;
  };

  const readCommittedMetadataInventory = async (entry: MetadataIdentity, readDemand?: MetadataReadDemand) => {
    const inventory = await readMetadataInventory(entry.public_index_entry_cid, readDemand);
    if (inventory === undefined ||
        inventory.namespace_id !== entry.namespace_id ||
        inventory.authority_scope_cid !== entry.authority_scope_cid ||
        inventory.run_definition_cid !== entry.run_definition_cid ||
        inventory.publication_attempt_cid !== entry.publication_attempt_cid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    if (readDemand !== undefined) {
      const extent = closedMetadataObjectExtent(inventory);
      for (const object of inventory.contract_objects) {
        const child = closedMetadataObjectExtent(object);
        extent.nodes += child.nodes; extent.textUnits += child.textUnits;
      }
      extent.nodes += inventory.physical_holding_cids.length;
      for (const cid of inventory.physical_holding_cids) extent.textUnits += (cid as {length: number}).length;
      readDemand.data(8, extent.nodes, extent.textUnits);
      readDemand.finish();
    }
    return inventory;
  };

  const requireCommittedMetadataInventory = async (entry: MetadataIdentity, readDemand?: MetadataReadDemand) => {
    const inventory = await readCommittedMetadataInventory(entry, readDemand);
    // Every selected holding is a distinct returned original while examined.
    // The READ caller consumes only presence, then releases that finite role.
    for (const holdingCid of inventory.physical_holding_cids) {
      const deletion = await readPhysicalHoldingDeletion(holdingCid, readDemand);
      if (deletion !== undefined) fail('InvalidPublicationMetadataInventoryStore');
      const holding = await readPhysicalHolding(holdingCid, readDemand);
      if (holding === undefined) fail('InvalidPublicationMetadataInventoryStore');
      readDemand?.release(10);
    }
    // These normal READ callers do not retain the inventory result. Other
    // existing callers omit readDemand and retain their established lifetime.
    readDemand?.release(8);
    return inventory;
  };

  const publicationRecoveryOriginal = (value: InventorySource) => Object.freeze({
    public_index_cid: value.public_index_entry_cid,
    inventory_wire: JSON.stringify(value),
  });

  const ensureMetadataInventoryFile = async (value: InventorySource) => {
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    try {
      await writeExclusive(
        metadataInventoryPath(value.public_index_entry_cid), bytes,
      );
    }
    catch (error) {
      if ((error as CodedCause)?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        metadataInventoryPath(value.public_index_entry_cid),
        configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) {
        fail('PublicationMetadataInventoryConflict');
      }
    }
    await syncDirectory(metadataInventoriesDirectory);
    return parseMetadataInventory(bytes);
  };

  const ensureMetadataInventory = async (value: InventorySource) => {
    const original = publicationRecoveryOriginal(value);
    if (getDeliveryIndex()!.nativePublicationInventory(original.public_index_cid) === undefined) {
      try {
        // Preserve an existing independently adopted file representation.
        await lstat(metadataInventoryPath(original.public_index_cid));
        stageMetadataInventory(original, false);
        return ensureMetadataInventoryFile(value);
      } catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
    }
    // The same native transaction owns both the complete inventory original
    // and its pending lookup. Do not also persist a duplicate inventory file.
    stageMetadataInventory(original, true);
    return publicationRecoveryValue(original);
  };

  const publicationRecoveryValue = (original: InventoryOriginal) => {
    const value = parseMetadataInventory(Buffer.from(original.inventory_wire,'utf8'));
    if (value.public_index_entry_cid !== original.public_index_cid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return value;
  };

  const restoreMetadataInventory = async (original: InventoryOriginal, value: MetadataInventory) => {
    const native = getDeliveryIndex()!.nativePublicationInventory(original.public_index_cid);
    if (native !== undefined) {
      if (native.inventory_wire !== original.inventory_wire) fail('PublicationMetadataInventoryConflict');
      return value;
    }
    const existing = await readMetadataInventory(original.public_index_cid);
    if (existing === undefined) return ensureMetadataInventoryFile(value);
    if (JSON.stringify(existing) !== original.inventory_wire) fail('PublicationMetadataInventoryConflict');
    return existing;
  };

  const recoverMetadataInventory = async (original: InventoryOriginal) => {
    const value = publicationRecoveryValue(original);
    const marker = await readMetadataDeletion(indexKey({namespaceId:value.namespace_id,
      authorityScopeCid:value.authority_scope_cid,runDefinitionCid:value.run_definition_cid}));
    if (marker !== undefined) fail('PublicationMetadataDeleted');
    return restoreMetadataInventory(original,value);
  };

  return {readMetadataInventory, readCommittedMetadataInventory, requireCommittedMetadataInventory,
    publicationRecoveryOriginal, publicationRecoveryValue, ensureMetadataInventory,
    restoreMetadataInventory, recoverMetadataInventory};
}
