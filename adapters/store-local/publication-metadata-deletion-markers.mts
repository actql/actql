import {unlink} from 'node:fs/promises';
import {metadataContractObject} from './publication-metadata-inventory.mjs';
import type {MetadataContractObject} from './publication-metadata-inventory.mjs';
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
