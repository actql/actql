import {randomUUID} from 'node:crypto';
import type {Stats} from 'node:fs';
import {lstat, readdir, rename, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {createDeliveryAttemptStore} from './delivery-attempt-store.mjs';
import type {createPhysicalHoldingRecordWriter} from './physical-holding-record-writer.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationMetadataDeletionMarkers} from './publication-metadata-deletion-markers.mjs';
import type {createPublicationMetadataInventory, InventoryOriginal} from './publication-metadata-inventory.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import {removeOpeningTree} from './publication-store-bootstrap.mjs';
import {exactKeys, fail, quantity, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type CoveragePhase = 'building' | 'ready';
type Coverage = Readonly<{version: 1; phase: CoveragePhase}>;
type PhysicalOriginal = Readonly<{cid: string; byte_count: number; device: string; inode: string}>;
type IndexUsage = Readonly<{bytes: number; objects: number}>;
type FenceRow = Readonly<{metadata_key: string; run_cid: unknown; retired: 0 | 1}>;
type DeliveryPorts<Contract extends PublicationContract> = ReturnType<typeof createDeliveryAttemptStore<Contract>>;
type DeliveryGroup<Contract extends PublicationContract> = Readonly<{
  value: Parameters<DeliveryPorts<Contract>['deliveryIndexRow']>[1];
  contract: Contract;
}>;
type StartupIndex<Contract extends PublicationContract> = Readonly<{
  physicalObjectUsage(): IndexUsage & Readonly<{complete: 0 | 1}>;
  physicalObjectRecoveryRequired(): boolean;
  migratePhysicalObjects(originals: readonly PhysicalOriginal[]): unknown;
  recoverPhysicalObjects(originals: readonly PhysicalOriginal[]): unknown;
  needsMigration(): boolean;
  migrate(rows: readonly ReturnType<DeliveryPorts<Contract>['deliveryIndexRow']>[]): unknown;
  publicationUsage(): IndexUsage;
  needsPublicationRecoveryMigration(): boolean;
  migratePublicationRecovery(rows: readonly InventoryOriginal[]): unknown;
  needsMetadataDeletionFenceMigration(): boolean;
  migrateMetadataDeletionFences(rows: readonly FenceRow[], complete?: boolean): unknown;
  metadataDeletionFence(keyHash: string): Pick<FenceRow, 'run_cid' | 'retired'> | undefined;
  pending(): readonly Parameters<DeliveryPorts<Contract>['restoreDeliveryClaim']>[0][];
}>;
type StartupPaths = Readonly<{
  root: string;
  deliveryCoveragePath: string;
  deliveryIndexPath: string;
  stagingDirectory: string;
  objectsDirectory: string;
  deliveriesDirectory: string;
  metadataInventoriesDirectory: string;
  metadataDeletionsDirectory: string;
}>;
type StartupPorts<Contract extends PublicationContract> =
  Pick<DeliveryPorts<Contract>, 'readFileDeliveryAttemptContract' | 'deliveryIndexRow' | 'restoreDeliveryClaim'> &
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'parseContract'> &
  Pick<ReturnType<typeof createPublicationSemanticReader<Contract>>, 'readSemanticOriginal' | 'readContract'> &
  Pick<ReturnType<typeof createPublicationMetadataInventory>, 'readMetadataInventory' | 'publicationRecoveryOriginal'> &
  Pick<ReturnType<typeof createPublicationMetadataDeletionMarkers>, 'readMetadataDeletion' | 'runMetadataDeletionStarted'> & Readonly<{
    openDeliveryAttemptIndex(path: string, options: Readonly<{
      create: boolean; maxEntries: number; maxWireBytes: number; initializeEmpty: boolean;
    }>): Promise<StartupIndex<Contract>>;
    bootstrap: Parameters<typeof removeOpeningTree>[1];
    readOpeningDirectory(path: string): Promise<readonly string[]>;
    writePhysicalHoldingRecord: ReturnType<typeof createPhysicalHoldingRecordWriter>;
    syncDirectory(path: string): unknown;
    physicalOriginal(cid: string, bytes: number, state: Stats): PhysicalOriginal;
    accountPhysicalUsage(usage: IndexUsage): void;
    accountNativePublication(usage: IndexUsage): void;
    confirmCommittedIndex(key: Readonly<{namespaceId: string; authorityScopeCid: unknown; runDefinitionCid: unknown}>):
      Promise<Readonly<{public_index_entry_cid: unknown}> | undefined>;
    metadataDeletionPath(keyHash: string): string;
  }>;

export function createPublicationIndexStartup<Contract extends PublicationContract>(
  configuration: Readonly<{maxObjects: number; maxObjectBytes: number; capacityBytes: number}>,
  {root, deliveryCoveragePath, deliveryIndexPath, stagingDirectory, objectsDirectory, deliveriesDirectory,
    metadataInventoriesDirectory, metadataDeletionsDirectory}: StartupPaths,
  createdStore: boolean,
  indexState: {deliveryIndex: StartupIndex<Contract> | undefined; set metadataFencesReady(value: boolean)},
  writeState: Readonly<{storedBytes: number; objectCount: number}>,
  metadataDeletionIntents: Set<unknown>,
  openingMetadataDeletionNames: string[],
  {openDeliveryAttemptIndex, bootstrap, readOpeningDirectory, writePhysicalHoldingRecord,
    syncDirectory, physicalOriginal, accountPhysicalUsage, accountNativePublication, confirmCommittedIndex, metadataDeletionPath,
    readFileDeliveryAttemptContract, deliveryIndexRow, restoreDeliveryClaim, parseContract, readSemanticOriginal, readContract,
    readMetadataInventory, publicationRecoveryOriginal, readMetadataDeletion, runMetadataDeletionStarted}: StartupPorts<Contract>,
) {
  const initializeDeliveryIndex = async () => {
    let coverage: Coverage | undefined, indexExists = false;
    try {
      const bytes = await readBounded(deliveryCoveragePath,128);
      coverage = JSON.parse(bytes.toString('utf8'));
      if (!exactKeys(coverage,['version','phase']) || coverage.version !== 1 ||
          !['building','ready'].includes(coverage.phase)) fail('DeliveryAttemptIndexUnavailable');
    } catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
    try {
      const state = await lstat(deliveryIndexPath);
      if (!state.isFile() || state.isSymbolicLink()) fail('DeliveryAttemptIndexUnavailable');
      indexExists = true;
    } catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
    if (coverage?.phase === 'ready' && !indexExists || coverage === undefined && indexExists) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    const publishCoverage = async (phase: CoveragePhase) => {
      const staging = resolve(stagingDirectory,`object-${randomUUID()}`);
      await writePhysicalHoldingRecord(staging,Buffer.from(JSON.stringify({version:1,phase}),'utf8'));
      await rename(staging,deliveryCoveragePath);
      await syncDirectory(root);
    };
    // An explicit one-time legacy migration has a durable building intent.
    // Ready coverage is never recreated from a missing adopted database.
    if (coverage === undefined) {
      await publishCoverage('building');
      coverage = {version:1,phase:'building'};
    }
    indexState.deliveryIndex = await openDeliveryAttemptIndex(deliveryIndexPath,{
      create: coverage.phase === 'building', maxEntries: configuration.maxObjects,
      maxWireBytes: configuration.maxObjectBytes,
      initializeEmpty: createdStore,
    });
    const migratePhysical=indexState.deliveryIndex!.physicalObjectUsage().complete===0;
    const recoverPhysical=indexState.deliveryIndex!.physicalObjectRecoveryRequired();
    if(migratePhysical&&recoverPhysical)fail('DeliveryAttemptIndexUnavailable');
    if (migratePhysical || recoverPhysical) {
      const originals = [];
      let bytes = 0;
      // Only first adoption or an actually unsealed prior owned lifetime
      // permits this bounded physical census. Clean opening uses its index;
      // missing adopted metadata never requests reconstruction.
      for (const name of await readOpeningDirectory(objectsDirectory)) {
        if (!/^[0-9a-f]{64}$/u.test(name)) fail('InvalidPublicationStoreObject');
        const state = await lstat(resolve(objectsDirectory, name));
        if (!state.isFile() || !quantity(state.size) || state.size > configuration.maxObjectBytes ||
            bytes + state.size > configuration.capacityBytes) fail('InvalidPublicationStoreObject');
        if (originals.length === configuration.maxObjects) fail('PublicationStoreObjectLimit');
        bytes += state.size;
        originals.push(physicalOriginal(`sha256:${name}`, state.size, state));
      }
      if(migratePhysical)indexState.deliveryIndex!.migratePhysicalObjects(originals);
      else{
        await syncDirectory(objectsDirectory);
        indexState.deliveryIndex!.recoverPhysicalObjects(originals);
      }
    }
    accountPhysicalUsage(indexState.deliveryIndex!.physicalObjectUsage());
    if (indexState.deliveryIndex!.needsMigration()) {
      if (coverage.phase !== 'building') fail('DeliveryAttemptIndexUnavailable');
      const rows: ReturnType<DeliveryPorts<Contract>['deliveryIndexRow']>[] = [], grants = new Map<string, DeliveryGroup<Contract>>(), uses = new Map<string, number>();
      // Building coverage is not an empty native lookup. This explicit
      // migration reads the original legacy files before publishing rows;
      // ordinary lookups still require complete native coverage.
      const readLegacySemantic = (cid: string) => readSemanticOriginal(cid,false);
      for (const name of await readdir(deliveriesDirectory)) {
        if (name.startsWith('.staging-')) {
          await removeOpeningTree(resolve(deliveriesDirectory,name),bootstrap);
          continue;
        }
        if (!/^[0-9a-f]{64}$/u.test(name) ||
            !(await lstat(resolve(deliveriesDirectory,name))).isDirectory()) fail('InvalidDeliveryAttemptStore');
        if (rows.length >= configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
        const attemptContract = await readFileDeliveryAttemptContract(`sha256:${name}`);
        const attempt = parseContract(attemptContract) as Parameters<DeliveryPorts<Contract>['deliveryIndexRow']>[0];
        let original = grants.get(attempt.result_read_grant_cid);
        if (original === undefined) {
          original = await readContract(attempt.result_read_grant_cid,'result_read_grant',readLegacySemantic) as DeliveryGroup<Contract>;
          grants.set(attempt.result_read_grant_cid,original);
        }
        const grant = original.value;
        if (grant.run_definition_cid !== attempt.run_definition_cid ||
            grant.result_manifest_cid !== attempt.result_manifest_cid ||
            !grant.results.some(result => result.result_name === attempt.result_name &&
              result.result_artifact_cid === attempt.result_artifact_cid)) fail('DeliveryGrantMismatch');
        const count = (uses.get(original.contract.identity) ?? 0) + 1;
        if (count > grant.max_uses) fail('DeliveryGrantUseLimit');
        uses.set(original.contract.identity,count);
        rows.push(deliveryIndexRow(attempt,grant,attemptContract,original.contract));
      }
      await syncDirectory(deliveriesDirectory);
      indexState.deliveryIndex!.migrate(rows);
    }
    accountNativePublication(indexState.deliveryIndex!.publicationUsage());
    if (writeState.storedBytes > configuration.capacityBytes || writeState.objectCount > configuration.maxObjects) {
      fail('PublicationStoreCapacity');
    }
    if (coverage.phase !== 'ready') await publishCoverage('ready');
    if (indexState.deliveryIndex!.needsPublicationRecoveryMigration()) {
      // Only the unadopted private format permits this bounded one-time
      // history classification. Later opens consume native pending rows.
      const rows = [];
      const names = await readOpeningDirectory(metadataInventoriesDirectory);
      if (names.length > configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
      for (const name of names) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
            !(await lstat(resolve(metadataInventoriesDirectory,name))).isFile()) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
        const inventory = (await readMetadataInventory(`sha256:${name.slice(0,-5)}`))!;
        const key = {namespaceId:inventory.namespace_id,
          authorityScopeCid:inventory.authority_scope_cid,runDefinitionCid:inventory.run_definition_cid};
        if ((await confirmCommittedIndex(key))?.public_index_entry_cid !== inventory.public_index_entry_cid) {
          rows.push(publicationRecoveryOriginal(inventory));
        }
      }
      await syncDirectory(metadataInventoriesDirectory);
      indexState.deliveryIndex!.migratePublicationRecovery(rows);
    }
    // Only a newly adopted private format reads historical retirement markers.
    // Batch progress is idempotent after a lost migration COMMIT; the actual
    // files remain until complete native coverage acknowledges their fences.
    const names = openingMetadataDeletionNames;
    if (indexState.deliveryIndex!.needsMetadataDeletionFenceMigration()) {
      let rows: FenceRow[]=[];
      for (const name of names) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name)) fail('InvalidPublicationMetadataDeletionStore');
        const keyHash=name.slice(0,-5),marker=await readMetadataDeletion(keyHash);
        if(marker===undefined)fail('InvalidPublicationMetadataDeletionStore');
        rows.push({metadata_key:keyHash,run_cid:marker.run_definition_cid,
          retired:marker.version==='actql-local-publication-metadata-retired/0.1'?1:0});
        if(rows.length===Math.max(1,configuration.maxObjects)) {
          indexState.deliveryIndex!.migrateMetadataDeletionFences(rows);rows=[];
        }
      }
      indexState.deliveryIndex!.migrateMetadataDeletionFences(rows,true);
    }
    indexState.metadataFencesReady=true;
    let removed=false;
    for(const name of names) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) fail('InvalidPublicationMetadataDeletionStore');
      const keyHash=name.slice(0,-5),marker=await readMetadataDeletion(keyHash);
      if(marker===undefined)fail('InvalidPublicationMetadataDeletionStore');
      const fence=indexState.deliveryIndex!.metadataDeletionFence(keyHash);
      if(fence!==undefined&&fence.run_cid!==marker.run_definition_cid)fail('InvalidPublicationMetadataDeletionStore');
      if(marker.version==='actql-local-publication-metadata-retired/0.1') {
        if(fence?.retired!==1)fail('InvalidPublicationMetadataDeletionStore');
        await unlink(metadataDeletionPath(keyHash));removed=true;
      } else {
        // A crash after the full marker ACK but before its indexed transfer
        // still hides this Run before any pending delivery can be restored.
        metadataDeletionIntents.add(marker.run_definition_cid);
      }
    }
    if(removed)await syncDirectory(metadataDeletionsDirectory);
    names.length=0;
    // Later opens see only pending physical cleanup files, never retired
    // history. Delivery restoration consumes the exact indexed Run fence.
    const pending = indexState.deliveryIndex!.pending();
    if (pending.length > configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
    for (const row of pending) {
      if (!await runMetadataDeletionStarted(row.run_cid)) await restoreDeliveryClaim(row);
    }
  };

  return initializeDeliveryIndex;
}
