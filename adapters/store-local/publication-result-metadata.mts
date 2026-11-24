import {lstat, mkdir, readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import {closedMetadataObjectExtent} from './physical-holding-record-reader.mjs';
import type {IndexReadDemand, PublicationIndexEntry, SelectedIndex} from './publication-index-reader.mjs';
import type {createPublicationSemanticReader, SemanticContract} from './publication-semantic-reader.mjs';
import type {createResultRetirement} from './result-deletion-owner.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, readBounded, writeExclusive} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RetentionRecord = Readonly<{
  version: 'actql-local-result-retention-extension/0.1';
  sequence: number;
  public_index_entry_cid: unknown;
  result_definition_cid: string;
  base_retention_policy_cid: unknown;
  prior_extension_policy_cid: unknown;
  extension_retention_policy_cid: unknown;
  admitted_at: unknown;
}>;
type DurableResultBinding = Readonly<{
  result_definition_cid: unknown;
  material_generation_cid: unknown;
  byte_count: unknown;
  effective_retention_policy_cid: unknown;
  result_schema_cid: string;
}>;
type SelectedResultBinding<Contract> = Readonly<{
  entry: PublicationIndexEntry;
  contract: Contract;
  value: DurableResultBinding;
}>;
type SemanticRead<Contract extends SemanticContract> = ReturnType<typeof createPublicationSemanticReader<Contract>>;
type ResultMetadataPorts<Contract extends SemanticContract> = Readonly<{
  active(): unknown;
  cidHex(value: unknown): string;
  confirmSelectedCommittedIndex(key: WireRunRef, readDemand?: IndexReadDemand<Contract>): Promise<PublicationIndexEntry | undefined>;
  runMetadataDeletionStarted(runDefinitionCid: string): Promise<boolean>;
  readResultDeletion: ReturnType<typeof createResultRetirement>['readResultDeletion'];
  readContract: SemanticRead<Contract>['readContract'];
  readSemanticOriginal: SemanticRead<Contract>['readSemanticOriginal'];
  readSemanticBytes: SemanticRead<Contract>['readSemanticBytes'];
  retentionExtensionDirectory(keyHash: string): string;
  retentionExtensionResultDirectory(keyHash: string, resultDefinitionCid: string): string;
  syncDirectory(path: string): unknown;
  putPublicationContract(name: 'result_retention_policy', wire: string): Promise<Readonly<{contract: Contract}>>;
  materialRetentionCurrent(): Promise<unknown>;
  retainMaterialOperation(operation: Promise<unknown>): void;
}>;

export function createPublicationResultMetadata<Contract extends SemanticContract>(
  configuration: Readonly<{maxObjectBytes: number}>,
  retentionExtensionsDirectory: string,
  recordNamePattern: RegExp,
  timestampPattern: RegExp,
  selectedPublicationReads: WeakMap<SelectedIndex<Contract>, PublicationIndexEntry>,
  {active, cidHex, confirmSelectedCommittedIndex, runMetadataDeletionStarted, readResultDeletion,
    readContract, readSemanticOriginal, readSemanticBytes, retentionExtensionDirectory, retentionExtensionResultDirectory,
    syncDirectory, putPublicationContract, materialRetentionCurrent, retainMaterialOperation}: ResultMetadataPorts<Contract>,
) {
  const readResultRetentionExtension = async (
    keyHash: string,
    resultDefinitionCid: string,
    readDemand?: IndexReadDemand<Contract>,
  ) => {
    const directory = retentionExtensionResultDirectory(
      keyHash, resultDefinitionCid,
    );
    let names;
    try {
      if (!(await lstat(retentionExtensionDirectory(keyHash))).isDirectory() ||
          !(await lstat(directory)).isDirectory()) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      names = await readdir(directory);
    }
    catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    await syncDirectory(directory);
    const records = names.map(name => {
      const match = recordNamePattern.exec(name);
      if (!match) fail('InvalidPublicationRetentionExtensionStore');
      return {name, sequence: Number(match[1])};
    }).sort((left, right) => left.sequence - right.sequence);
    if (records.length === 0) {
      fail('InvalidPublicationRetentionExtensionStore');
    }
    let previous: RetentionRecord | undefined;
    for (let index = 0; index < records.length; index++) {
      if (records[index].sequence !== index) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      const bytes = await readBounded(
        resolve(directory, records[index].name),
        configuration.maxObjectBytes, undefined, undefined, false, readDemand,
      );
      let value: unknown;
      try { value = JSON.parse(bytes.toString('utf8')); }
      catch (error) {
        fail('InvalidPublicationRetentionExtensionStore', error);
      }
      if (!exactKeys(value, [
        'version', 'sequence', 'public_index_entry_cid',
        'result_definition_cid', 'base_retention_policy_cid',
        'prior_extension_policy_cid', 'extension_retention_policy_cid',
        'admitted_at',
      ]) ||
          value.version !==
            'actql-local-result-retention-extension/0.1' ||
          value.sequence !== index ||
          !cidPattern.test(value.public_index_entry_cid as string) ||
          value.result_definition_cid !== resultDefinitionCid ||
          !cidPattern.test(value.base_retention_policy_cid as string) ||
          (value.prior_extension_policy_cid !== null &&
            !cidPattern.test(value.prior_extension_policy_cid as string)) ||
          !cidPattern.test(value.extension_retention_policy_cid as string) ||
          !timestampPattern.test(value.admitted_at as string) ||
          value.prior_extension_policy_cid !==
            (previous?.extension_retention_policy_cid ?? null)) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      previous = Object.freeze(value) as RetentionRecord;
      if (readDemand !== undefined) {
        const extent = closedMetadataObjectExtent(previous);
        readDemand.data(11, extent.nodes, extent.textUnits);
        readDemand.finish();
      }
    }
    return previous;
  };

  const requireCommittedResultBinding = async (
    key: WireRunRef,
    resultDefinitionCid: string,
    publication?: unknown,
    readDemand?: IndexReadDemand<Contract>,
  ): Promise<SelectedResultBinding<Contract>> => {
    cidHex(resultDefinitionCid);
    let entry;
    if (publication === undefined) entry = await confirmSelectedCommittedIndex(key, readDemand);
    else {
      active();
      entry = selectedPublicationReads.get(publication as SelectedIndex<Contract>);
      if (entry === undefined || entry.namespace_id !== key.namespaceId ||
          entry.authority_scope_cid !== key.authorityScopeCid ||
          entry.run_definition_cid !== key.runDefinitionCid) fail('PublicationLookupDenied');
      selectedPublicationReads.delete(publication as SelectedIndex<Contract>);
      // Real same-Store retirement invalidates the observation. This indexed
      // fence does not reacquire/admit/hash the unchanged immutable Index.
      if (await runMetadataDeletionStarted(entry.run_definition_cid)) fail('PublicationLookupDenied');
    }
    if (entry === undefined) fail('PublicationLookupDenied');
    const matches: {contract: Contract; value: DurableResultBinding}[] = [];
    for (const bindingCid of entry.durable_result_binding_cids) {
      const {contract, value} = await readContract(
        bindingCid, 'durable_result_binding',
        (cid, includeNative) => readSemanticOriginal(cid, includeNative, false, undefined, readDemand),
      ) as Readonly<{contract: Contract; value: DurableResultBinding}>;
      if (value.result_definition_cid === resultDefinitionCid) {
        if (matches.length !== 0) fail('PublicationLookupDenied');
        matches.push({contract, value});
        readDemand?.retain(7, contract, 2);
      }
      readDemand?.finish();
    }
    if (matches.length !== 1) fail('PublicationLookupDenied');
    return Object.freeze({entry, ...matches[0]});
  };

  const requireResultNotDeleted = async (
    keyHash: string,
    selected: SelectedResultBinding<Contract>,
    resultDefinitionCid: string,
    readDemand?: IndexReadDemand<Contract>,
  ) => {
    const deletion = await readResultDeletion(
      keyHash, resultDefinitionCid, readDemand,
    );
    if (deletion === undefined) return;
    if (deletion.public_index_entry_cid !==
        selected.entry.public_index_entry_cid ||
        deletion.material_generation_cid !==
          selected.value.material_generation_cid) {
      fail('InvalidPublicationDeletionStore');
    }
    fail('PublicationObjectMissing');
  };

  const readRetainedResultExtension = async (
    key: WireRunRef,
    resultDefinitionCid: string,
    metadataOnly = false,
    publication?: unknown,
    readDemand?: IndexReadDemand<Contract>,
  ) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid, publication, readDemand,
    );
    const keyHash = indexKey(key);
    if (!metadataOnly) {
      await requireResultNotDeleted(keyHash, selected, resultDefinitionCid, readDemand);
    }
    const result = await readSelectedResultRetentionExtension(
      selected, keyHash, resultDefinitionCid, readDemand,
    );
    readDemand?.release(7);
    return result;
  };

  const readSelectedResultRetentionExtension = async (
    selected: SelectedResultBinding<Contract>, keyHash: string,
    resultDefinitionCid: string, readDemand?: IndexReadDemand<Contract>,
  ) => {
    const record = await readResultRetentionExtension(
      keyHash, resultDefinitionCid, readDemand,
    );
    if (record === undefined) return undefined;
    if (record.public_index_entry_cid !==
        selected.entry.public_index_entry_cid ||
        record.base_retention_policy_cid !==
          selected.value.effective_retention_policy_cid) {
      fail('InvalidPublicationRetentionExtensionStore');
    }
    const extension = await readContract(
      record.extension_retention_policy_cid as string,
      'result_retention_policy',
      (cid, includeNative) => readSemanticOriginal(cid, includeNative, false, undefined, readDemand),
    );
    readDemand?.retain(4, extension.contract!, 1);
    readDemand?.finish();
    return Object.freeze({record, extension: extension.contract!});
  };

  const readCommittedResultRetentionExtension = (
    key: WireRunRef, resultDefinitionCid: string, publication?: unknown, readDemand?: IndexReadDemand<Contract>,
  ) =>
    readRetainedResultExtension(key, resultDefinitionCid, false, publication, readDemand);

  // Inspect the retained immutable schema and binding inventory. Payload
  // deletion does not delete publication metadata; no generation is opened,
  // hashed or held as a payload reader by this operation.
  const readCommittedResultDescriptionEvidence = async (key: WireRunRef, definitionCid: string, publication?: unknown) => {
    active();
    const selected = await requireCommittedResultBinding(key, definitionCid, publication);
    const bindings = await Promise.all(
      selected.entry.durable_result_binding_cids.map(async cid =>
        cid === selected.contract.identity ? selected.contract :
          (await readContract(cid, 'durable_result_binding')).contract!));
    const schemaWire = (await readSemanticBytes(
      selected.value.result_schema_cid, false)).toString('utf8');
    const definition = (await readContract(
      definitionCid, 'result_definition')).contract!;
    const retained = await readSelectedResultRetentionExtension(
      selected, indexKey(key), definitionCid);
    return Object.freeze({bindings, schemaWire, definition, retained});
  };

  const putCommittedResultRetentionExtension = async (
    key: WireRunRef,
    resultDefinitionCid: string,
    expectedPriorExtensionCid: string | undefined,
    extension: Contract,
    admittedAt: string,
  ) => {
    active();
    if ((expectedPriorExtensionCid !== undefined &&
          !cidPattern.test(expectedPriorExtensionCid)) ||
        extension === null || typeof extension !== 'object' ||
        extension.name !== 'result_retention_policy' ||
        !cidPattern.test(extension.identity) ||
        typeof extension.wire !== 'string' ||
        !timestampPattern.test(admittedAt)) {
      fail('InvalidPublicationRetentionExtension');
    }
    const operation = materialRetentionCurrent().then(async () => {
      const selected = await requireCommittedResultBinding(
        key, resultDefinitionCid,
      );
      const keyHash = indexKey(key);
      await requireResultNotDeleted(
        keyHash, selected, resultDefinitionCid,
      );
      const current = await readResultRetentionExtension(
        keyHash, resultDefinitionCid,
      );
      if (current?.public_index_entry_cid !== undefined &&
          (current.public_index_entry_cid !==
              selected.entry.public_index_entry_cid ||
            current.base_retention_policy_cid !==
              selected.value.effective_retention_policy_cid)) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      const currentCid = current?.extension_retention_policy_cid;
      if (currentCid !== expectedPriorExtensionCid) {
        fail('PublicationRetentionExtensionConflict');
      }
      if (currentCid === extension.identity) {
        return Object.freeze({record: current!, extension, idempotent: true});
      }
      const stored = await putPublicationContract(
        'result_retention_policy', extension.wire,
      );
      if (stored.contract.identity !== extension.identity) {
        fail('InvalidPublicationRetentionExtension');
      }
      const parent = retentionExtensionDirectory(keyHash);
      let parentCreated = false;
      try {
        await mkdir(parent, {mode: 0o700});
        parentCreated = true;
      } catch (error) {
        if ((error as CodedCause)?.code !== 'EEXIST' ||
            !(await lstat(parent)).isDirectory()) throw error;
      }
      if (parentCreated) await syncDirectory(retentionExtensionsDirectory);
      const directory = retentionExtensionResultDirectory(
        keyHash, resultDefinitionCid,
      );
      let directoryCreated = false;
      try {
        await mkdir(directory, {mode: 0o700});
        directoryCreated = true;
      } catch (error) {
        if ((error as CodedCause)?.code !== 'EEXIST' ||
            !(await lstat(directory)).isDirectory()) throw error;
      }
      if (directoryCreated) await syncDirectory(parent);
      const record = Object.freeze({
        version: 'actql-local-result-retention-extension/0.1',
        sequence: (current?.sequence ?? -1) + 1,
        public_index_entry_cid: selected.entry.public_index_entry_cid,
        result_definition_cid: resultDefinitionCid,
        base_retention_policy_cid:
          selected.value.effective_retention_policy_cid,
        prior_extension_policy_cid: currentCid ?? null,
        extension_retention_policy_cid: extension.identity,
        admitted_at: admittedAt,
      });
      const bytes = Buffer.from(JSON.stringify(record), 'utf8');
      if (bytes.byteLength > configuration.maxObjectBytes) {
        fail('PublicationObjectLimit');
      }
      const path = resolve(directory, `${record.sequence}.json`);
      try { await writeExclusive(path, bytes); }
      catch (error) {
        if ((error as CodedCause)?.code !== 'EEXIST') throw error;
        const existing = await readBounded(
          path, configuration.maxObjectBytes,
        );
        if (!existing.equals(bytes)) {
          fail('PublicationRetentionExtensionConflict');
        }
      }
      await syncDirectory(directory);
      return Object.freeze({record, extension, idempotent: false});
    });
    retainMaterialOperation(operation.catch(() => {}));
    return operation;
  };

  return {requireCommittedResultBinding, requireResultNotDeleted,
    readCommittedResultRetentionExtension, readCommittedResultDescriptionEvidence, putCommittedResultRetentionExtension};
}
