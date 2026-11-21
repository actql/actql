import {createHash} from 'node:crypto';
import {link, lstat} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {createNativeMetadataMutationOwner} from './native-metadata-mutation-owner.mjs';
import type {createPreparedHolderRegistry} from './prepared-holder-owner.mjs';
import type {createPreparedObjectOwnership} from './prepared-object-ownership.mjs';
import type {createPreparedSchemaOwner} from './prepared-publication-schema-owner.mjs';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationEvidence} from './publication-evidence-inspection.mjs';
import type {PublicationIndexEntry} from './publication-index-reader.mjs';
import type {createPublicationMetadataDeletionMarkers} from './publication-metadata-deletion-markers.mjs';
import type {createPublicationMetadataInventory, InventoryOriginal} from './publication-metadata-inventory.mjs';
import type {createPublicationObjectWrites} from './publication-object-writes.mjs';
import type {createPublicationProgress} from './publication-progress.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {createPublicationSemanticWrites} from './publication-semantic-writes.mjs';
import type {createResultRetirement} from './result-deletion-owner.mjs';
import type {createRunMetadataInventory} from './run-metadata-inventory.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, PublicationStoreError} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type CommitEntry = PublicationIndexEntry & Readonly<{
  invocation_cid: string; result_manifest_cid: string; run_receipt_cid: string;
  captured_run_cid: string; publication_request_cid: string; publication_attempt_cid: string;
}>;
type Evidence<Contract extends PublicationContract> = ReturnType<typeof createPublicationEvidence<Contract>>;
type FreeEvidence<Contract extends PublicationContract> = Parameters<Evidence<Contract>['verifyCommitEvidence']>[2];
type EffectEvidence<Contract extends PublicationContract> = Parameters<Evidence<Contract>['inspectEffectfulStoredEvidence']>[0];
type SemanticReadPorts<Contract extends PublicationContract> = ReturnType<typeof createPublicationSemanticReader<Contract>>;
type ReadSemantic<Contract extends PublicationContract> = SemanticReadPorts<Contract>['readSemanticOriginal'];
type SemanticOriginal<Contract extends PublicationContract> = Awaited<ReturnType<ReadSemantic<Contract>>>;
type SemanticSelection<Contract extends PublicationContract> = NonNullable<Parameters<ReadSemantic<Contract>>[1]>;
type PreparedOwners = ReturnType<typeof createPreparedObjectOwnership>;
type PreparedOriginal = Parameters<PreparedOwners['adoptPreparedObjects']>[0][number];
type ReserveObjectCapacity = ReturnType<typeof createPublicationObjectWrites>['reserveObjectCapacity'];
type NativeIndexKey = Readonly<{metadata_key: string; namespace_id: string; authority_scope_cid: string; run_cid: string}>;
type NativeIndexBody = Readonly<{semantic_cid: string; name: 'public_index_entry'; wire: string; byte_count: number}>;
type NativeBinding = Readonly<{result_definition_cid: string; binding_cid: string; material_cid: string}>;
type NativeUsage = Readonly<{bytes: number; objects: number}>;
type NativeProgress = Readonly<{attemptCid: string; recordCid: string}>;
type NativeIndexPreparation = Readonly<{
  key: NativeIndexKey; body: NativeIndexBody; original: InventoryOriginal;
  bindings: readonly NativeBinding[]; progress: NativeProgress; reservation: ReturnType<ReserveObjectCapacity>;
}>;
type NativeCommitIndex = Readonly<{
  retainPublicationInventoryFinish(original: InventoryOriginal): unknown;
  publicationAttempt(cid: string): Readonly<{run_cid: string}> | undefined;
  commitNativePublicationIndex(
    key: NativeIndexKey, body: NativeIndexBody, original: InventoryOriginal, bindings: readonly NativeBinding[],
    allowance: NativeUsage, progress: NativeProgress,
  ): Readonly<{usage: NativeUsage; created: boolean}>;
}>;
type CommitControl<Contract> = Readonly<{
  recordAllowsCommit(previous: Contract): unknown;
  publicIndexSameCommittedContent(existing: Contract, candidate: Contract): boolean;
}>;
type CommitPorts<Contract extends PublicationContract> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'admitOriginalContract' | 'parseContract'> &
  Pick<SemanticReadPorts<Contract>, 'readContract' | 'readSemanticOriginal'> &
  Pick<ReturnType<typeof createPublicationProgress<Contract>>, 'latestRecordContract'> &
  Pick<ReturnType<typeof createPublicationMetadataDeletionMarkers>, 'readMetadataDeletion'> &
  Pick<ReturnType<typeof createPublicationMetadataInventory>, 'readCommittedMetadataInventory' | 'publicationRecoveryOriginal' | 'ensureMetadataInventory'> &
  Pick<ReturnType<typeof createRunMetadataInventory<Contract>>, 'bindMetadataContractObjects'> &
  Pick<ReturnType<typeof createPreparedSchemaOwner>, 'adoptPreparedSchemas'> &
  Pick<PreparedOwners, 'beginPreparedCommit' | 'confirmPreparedMaterials' | 'adoptPreparedObjects'> &
  Pick<Evidence<Contract>, 'verifyCommitEvidence' | 'inspectEffectfulStoredEvidence' | 'confirmCapturedContentHoldings'> &
  Pick<ReturnType<typeof createPublicationSemanticWrites>, 'putSemanticBatch'> &
  Pick<ReturnType<typeof createNativeMetadataMutationOwner>, 'writeNativeIndexOriginal'> & Readonly<{
    active(): unknown;
    currentDeliveryIndex(): NativeCommitIndex | undefined;
    contractPath(cid: string): string;
    syncDirectory(path: string): unknown;
    confirmCommittedIndex(key: WireRunRef): Promise<CommitEntry | undefined>;
    readResultDeletion: ReturnType<typeof createResultRetirement>['readResultDeletion'];
    reserveObjectCapacity: ReserveObjectCapacity;
    accountNativePublication(usage: NativeUsage): void;
    withSemanticCommit<Result>(operation: () => Promise<Result>): Promise<Result>;
  }>;

export function createPublicationIndexCommit<Contract extends PublicationContract>(
  configuration: Readonly<{maxObjectBytes: number}>,
  indexesDirectory: string,
  contractControl: CommitControl<Contract>,
  preparedObjectOwners: Pick<ReturnType<typeof createPreparedHolderRegistry<PreparedOriginal>>, 'select'>,
  durablyConfirmedIndexes: Map<string, string>,
  {active, currentDeliveryIndex, contractPath, syncDirectory, confirmCommittedIndex, readResultDeletion,
    reserveObjectCapacity, accountNativePublication, withSemanticCommit,
    admitOriginalContract, parseContract, readContract, readSemanticOriginal, latestRecordContract, readMetadataDeletion,
    readCommittedMetadataInventory, publicationRecoveryOriginal, ensureMetadataInventory, bindMetadataContractObjects,
    adoptPreparedSchemas, beginPreparedCommit, confirmPreparedMaterials, adoptPreparedObjects,
    verifyCommitEvidence, inspectEffectfulStoredEvidence, confirmCapturedContentHoldings, putSemanticBatch,
    writeNativeIndexOriginal}: CommitPorts<Contract>,
) {
  const commitIndexInternal = async (
    suppliedWire: string,
    requiredObjectCids: readonly string[],
    suppliedEvidence: FreeEvidence<Contract> | EffectEvidence<Contract>['chain'],
    effectfulEvidence: EffectEvidence<Contract> | undefined,
    indexOriginal: Contract | undefined,
    preparedHandles: readonly object[] = [],
  ) => {
    active();
    if (indexOriginal !== undefined &&
        (!exactKeys(indexOriginal, ['name', 'identityField', 'identity', 'wire']) ||
          indexOriginal.name !== 'public_index_entry' || indexOriginal.wire !== suppliedWire)) {
      fail('InvalidPublicationCommitEvidence');
    }
    const admitted = admitOriginalContract('public_index_entry', suppliedWire, indexOriginal);
    if (indexOriginal !== undefined && (admitted.identity !== indexOriginal.identity ||
        admitted.identityField !== indexOriginal.identityField)) fail('InvalidPublicationCommitEvidence');
    const entry = parseContract(admitted) as CommitEntry;
    const key = {
      namespaceId: entry.namespace_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    };
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) {
      fail('PublicationMetadataDeleted');
    }
    if (!Array.isArray(requiredObjectCids) ||
        new Set(requiredObjectCids).size !== requiredObjectCids.length ||
        requiredObjectCids.some(cid => !cidPattern.test(cid))) {
      fail('InvalidPublicationCommitInventory');
    }
    const required = new Set(requiredObjectCids);
    for (const cid of [
      entry.invocation_cid,
      entry.result_manifest_cid,
      entry.run_receipt_cid,
      entry.captured_run_cid,
      ...entry.durable_result_binding_cids,
      entry.publication_request_cid,
      entry.publication_attempt_cid,
    ]) {
      if (!required.has(cid)) fail('IncompletePublicationCommitInventory');
    }
    // This is the existing serialized commit operation, not a Store-wide
    // cache or authority. Its private bytes never escape to a public caller.
    // Share successful acquisition/close facts across the pure evidence and
    // metadata-inventory phases; a new operation acquires new originals.
    const semanticOriginals = new Map<string, SemanticOriginal<Contract> | Promise<SemanticOriginal<Contract>>>();
    const readOriginal = (cid: string, includeNative: SemanticSelection<Contract> = true, retained?: Contract) => {
      if (!semanticOriginals.has(cid)) {
        semanticOriginals.set(cid, readSemanticOriginal(cid, includeNative, false, retained));
      }
      return semanticOriginals.get(cid)!;
    };
    let verifiedBindings;
    let physicalHoldingCids: string[] = [];
    if (effectfulEvidence === undefined) {
      verifiedBindings = await verifyCommitEvidence(
        admitted, entry, suppliedEvidence as FreeEvidence<Contract>, required, readOriginal,
      );
      physicalHoldingCids = [...await confirmCapturedContentHoldings(
        suppliedEvidence.capturedRun, suppliedEvidence.runDefinition)];
    } else {
      if (effectfulEvidence.index.identity !== admitted.identity) {
        fail('InvalidEffectfulStoredEvidence');
      }
      const inspected = await inspectEffectfulStoredEvidence({
        ...effectfulEvidence, index: admitted,
      }, readOriginal, {contract: admitted, entry});
      for (const cid of [
        ...inspected.publicContractCids,
        ...inspected.sourceArtifactCids,
        ...inspected.sourceSchemaCids,
      ]) {
        if (!required.has(cid)) {
          fail('IncompletePublicationCommitInventory');
        }
      }
      verifiedBindings = inspected.verifiedBindings;
      physicalHoldingCids = [
        inspected.privateHoldingCid,
        ...inspected.effectSourceHoldingCids,
        ...(inspected.captureHoldingCid === undefined ? [] :
          [inspected.captureHoldingCid]),
        ...(inspected.captureRecordHoldingCid === undefined ? [] :
          [inspected.captureRecordHoldingCid]),
        ...await confirmCapturedContentHoldings(suppliedEvidence.capturedRun,
          suppliedEvidence.runDefinition),
      ].sort();
    }
    // Typed evidence establishes its file/native representation first. Only
    // remaining untyped inventory needs the generic native lookup/fallback.
    for (const cid of required) await readOriginal(cid);
    const boundPhysicalCids = verifiedBindings.map(value => value.physical.cid);
    const bindingSchemas = new Map<string, string>();
    for (const value of verifiedBindings) {
      bindingSchemas.set(value.binding.durable_result_binding_cid, value.schema.cid);
    }
    const inventorySemanticCids = Object.freeze([...new Set([
      ...requiredObjectCids,
      admitted.identity,
      ...verifiedBindings.map(value => value.schema.cid),
    ])].sort());
    const previous = await latestRecordContract(entry.publication_attempt_cid);
    if (previous === undefined ||
        contractControl.recordAllowsCommit(previous) !== true) {
      fail('PublicationAttemptNotCommitting');
    }
    const selectedPrepared = preparedObjectOwners.select(preparedHandles,
      new Map(verifiedBindings.map(value => [value.physical.cid, value.physical.bytes])));
    // Reuse this commit's verified original bindings. A known successful
    // Index is immutable; only its exact deletion markers can retire its
    // material ownership. Do not re-admit the same evidence during pin cleanup.
    const ownRetention = async (cid: string) => {
      if (await readMetadataDeletion(keyHash) !== undefined) return false;
      for (const value of verifiedBindings) {
        if (value.physical.cid === cid &&
            await readResultDeletion(keyHash, value.binding.result_definition_cid) === undefined) return true;
      }
      return false;
    };
    const adoptObjects = async () => {
      await confirmPreparedMaterials(boundPhysicalCids);
      await adoptPreparedObjects(selectedPrepared);
    };
    let inventoryOriginal: InventoryOriginal | undefined;
    let nativeIndexPreparation: NativeIndexPreparation | undefined;
    const adoptSchemas = async () => {
      await adoptPreparedSchemas(inventorySemanticCids, entry.run_definition_cid);
      currentDeliveryIndex()!.retainPublicationInventoryFinish(inventoryOriginal!);
    };
    return createPublicationCommitOwner({entry, admitted, key}, {
      confirm: confirmCommittedIndex,
      async sameContent(existing, candidate) {
        return contractControl.publicIndexSameCommittedContent(
          (await readContract(existing.public_index_entry_cid,
            'public_index_entry')).contract!, candidate,
        );
      },
      conflict() { fail('PublicationCommitConflict'); },
      async verifyExistingInventory(existingCommit) {
        const inventory = await readCommittedMetadataInventory(existingCommit);
        const directlyRequired = [
          existingCommit.public_index_entry_cid,
          existingCommit.invocation_cid,
          existingCommit.result_manifest_cid,
          existingCommit.run_receipt_cid,
          existingCommit.captured_run_cid,
          ...existingCommit.durable_result_binding_cids,
          existingCommit.publication_request_cid,
          existingCommit.publication_attempt_cid,
        ];
        for (const bindingCid of
          existingCommit.durable_result_binding_cids) {
          const schemaCid = bindingSchemas.get(bindingCid) ?? ((await readContract(
            bindingCid, 'durable_result_binding', readOriginal,
          )).value as Readonly<{result_schema_cid: string}>).result_schema_cid;
          directlyRequired.push(schemaCid);
        }
        if (inventory === undefined ||
            inventory.public_index_entry_cid !==
              existingCommit.public_index_entry_cid ||
            inventory.physical_holding_cids.join('\0') !==
              physicalHoldingCids.join('\0') ||
            directlyRequired.some(cid =>
              !inventory.contract_objects.some(object =>
                object.semantic_cid === cid))) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
        inventoryOriginal = publicationRecoveryOriginal(inventory);
      },
      async stage() {
        const nativeAttempt = currentDeliveryIndex()!.publicationAttempt(entry.publication_attempt_cid);
        let legacyIndexBody = false;
        try {await lstat(contractPath(admitted.identity)); legacyIndexBody = true;}
        catch (error) {if ((error as CodedCause)?.code !== 'ENOENT') throw error;}
        if (nativeAttempt !== undefined && !legacyIndexBody) {
          if (nativeAttempt.run_cid !== entry.run_definition_cid) fail('PublicationAttemptMismatch');
          const bytes = Buffer.from(admitted.wire,'utf8');
          const objects = await bindMetadataContractObjects(inventorySemanticCids.filter(cid => cid !== admitted.identity),readOriginal);
          const descriptor = Object.freeze({semantic_cid:admitted.identity,native:'sqlite',
            body_sha256:`sha256:${createHash('sha256').update(bytes).digest('hex')}`,byte_count:bytes.byteLength});
          const inventory = Object.freeze({version:'actql-local-publication-metadata-inventory/0.1',
            namespace_id:entry.namespace_id,authority_scope_cid:entry.authority_scope_cid,
            run_definition_cid:entry.run_definition_cid,public_index_entry_cid:admitted.identity,
            publication_attempt_cid:entry.publication_attempt_cid,
            contract_objects:Object.freeze([...objects,descriptor].sort((a,b) => a.semantic_cid.localeCompare(b.semantic_cid))),
            physical_holding_cids:physicalHoldingCids});
          const original = publicationRecoveryOriginal(inventory);
          if (Buffer.byteLength(original.inventory_wire,'utf8') > configuration.maxObjectBytes) fail('PublicationObjectLimit');
          const body = Object.freeze({semantic_cid:admitted.identity,name:'public_index_entry',wire:admitted.wire,byte_count:bytes.byteLength});
          const bindings = Object.freeze(verifiedBindings.map(value => Object.freeze({
            result_definition_cid:value.binding.result_definition_cid,
            binding_cid:value.binding.durable_result_binding_cid,material_cid:value.physical.cid,
          })));
          // This is an intended private inventory, not stored evidence or an
          // ACK. Its bytes and capacity stay owned until the real transaction.
          nativeIndexPreparation = {key:Object.freeze({metadata_key:keyHash,namespace_id:entry.namespace_id,
            authority_scope_cid:entry.authority_scope_cid,run_cid:entry.run_definition_cid}),body,original,bindings,
            progress:Object.freeze({attemptCid:entry.publication_attempt_cid,recordCid:previous.identity}),
            reservation:reserveObjectCapacity(bytes.byteLength)};
          inventoryOriginal = original;
          return;
        }
        // Persist the existing publication inventory BEFORE installing its
        // Index body. This same durable owner already reclaims uncommitted
        // metadata; it needs no duplicate physical preparation transaction.
        const indexBytes = Buffer.from(admitted.wire, 'utf8');
        const indexDescriptors = legacyIndexBody
          ? await bindMetadataContractObjects([admitted.identity], readOriginal)
          : [Object.freeze({semantic_cid:admitted.identity,
            physical_cid:`sha256:${createHash('sha256').update(indexBytes).digest('hex')}`,
            byte_count:indexBytes.byteLength})];
        const inventoryContractObjects = Object.freeze([
          ...await bindMetadataContractObjects(
            inventorySemanticCids.filter(cid => cid !== admitted.identity), readOriginal),
          ...indexDescriptors,
        ].sort((a,b) => a.semantic_cid.localeCompare(b.semantic_cid)));
        const inventory = await ensureMetadataInventory(Object.freeze({
          version: 'actql-local-publication-metadata-inventory/0.1',
          namespace_id: entry.namespace_id,
          authority_scope_cid: entry.authority_scope_cid,
          run_definition_cid: entry.run_definition_cid,
          public_index_entry_cid: admitted.identity,
          publication_attempt_cid: entry.publication_attempt_cid,
          contract_objects: inventoryContractObjects,
          physical_holding_cids: physicalHoldingCids,
        }));
        inventoryOriginal = publicationRecoveryOriginal(inventory);
        await putSemanticBatch([{wire: admitted.wire, semanticCid: admitted.identity}],
          semanticOriginals, inventoryOriginal);
      },
      beginCustody() {
        return beginPreparedCommit(
          boundPhysicalCids, key, entry.public_index_entry_cid, selectedPrepared, ownRetention,
        );
      },
      cancelStage() {nativeIndexPreparation?.reservation.release();},
      async install(markInstalled) {
        if (nativeIndexPreparation !== undefined) {
          const original = nativeIndexPreparation;
          try {active();}
          catch (error) {original.reservation.release(); throw error;}
          writeNativeIndexOriginal(currentDeliveryIndex()!.commitNativePublicationIndex,
            [original.key,original.body,original.original,original.bindings,
              Object.freeze({objects:1,bytes:original.body.byte_count}),original.progress], result => {
              accountNativePublication(result.usage);
              if (result.created) markInstalled();
              durablyConfirmedIndexes.set(keyHash,entry.public_index_entry_cid);
            }, original.reservation);
          return;
        }
        const target = resolve(indexesDirectory, `${keyHash}.json`);
        await link(contractPath(entry.public_index_entry_cid), target);
        markInstalled();
        await syncDirectory(indexesDirectory);
        durablyConfirmedIndexes.set(keyHash, entry.public_index_entry_cid);
      },
      adoptObjects,
      adoptSchemas,
      async adopt() {
        await adoptObjects();
        await adoptSchemas();
      },
      makeFailure: (code, cause) => new PublicationStoreError(code, cause),
    }).commit();
  };

  // A prepared schema cannot be retired between commit evidence validation
  // and installation of the inventory that acquires its durable ownership.
  const commitIndex = (
    suppliedWire: string, requiredObjectCids: readonly string[], suppliedEvidence: FreeEvidence<Contract>,
    indexOriginal?: Contract, preparedHandles: readonly object[] = [],
  ) => {
    if (!Array.isArray(preparedHandles)) fail('InvalidPublicationPreparedOwner');
    const originalHandles = Object.freeze([...preparedHandles]);
    return withSemanticCommit(() => commitIndexInternal(
      suppliedWire, requiredObjectCids, suppliedEvidence, undefined, indexOriginal, originalHandles,
    ));
  };

  const commitEffectfulIndex = (preparation: EffectEvidence<Contract>, requiredObjectCids: readonly string[]) => {
    const keys = ['index', 'chain', 'preview', 'receipts', 'privateBinding', 'effectSources'];
    if (preparation != null && Object.hasOwn(preparation, 'recoveryResources')) keys.push('recoveryResources');
    if (!exactKeys(preparation, keys) || typeof preparation.index?.wire !== 'string') {
      fail('InvalidEffectfulStoredEvidence');
    }
    return withSemanticCommit(() => commitIndexInternal(
      preparation.index.wire, requiredObjectCids, preparation.chain,
      preparation, preparation.index,
    ));
  };

  const validateCommittedEffectfulEvidence = async (preparation: EffectEvidence<Contract>) => {
    active();
    const inspected = await inspectEffectfulStoredEvidence(preparation);
    const entry = parseContract(inspected.index) as CommitEntry;
    const committed = await confirmCommittedIndex({
      namespaceId: entry.namespace_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    });
    if (committed?.public_index_entry_cid !== inspected.index.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const inventory = await readCommittedMetadataInventory(committed);
    const expectedHoldings = [inspected.privateHoldingCid,
      ...inspected.effectSourceHoldingCids,
      ...(inspected.captureHoldingCid === undefined ? [] :
        [inspected.captureHoldingCid]),
      ...(inspected.captureRecordHoldingCid === undefined ? [] :
        [inspected.captureRecordHoldingCid]),
      ...await confirmCapturedContentHoldings(preparation.chain.capturedRun,
        preparation.chain.runDefinition)].sort();
    if (inventory?.physical_holding_cids.join('\0') !==
        expectedHoldings.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return true;
  };

  return {commitIndex, commitEffectfulIndex, validateCommittedEffectfulEvidence};
}
