import {constructEffectfulPublication} from '../host-common/run-publication.mjs';
// Durable local publication storage. Prepared objects are content-addressed
// but remain invisible to ordinary Result lookup until an authority-scoped
// public index entry is installed with an exclusive atomic link.
// Existing bounded physical Content reader implementation DATA, not a caller
// allowance or proof of the separate Store metadata/read preparation.
export const physicalContentReadWindowBytes = 65536;
import {
  constants,
} from 'node:fs';
import {
  lstat,
  link,
  mkdir,
  open,
  opendir,
  readdir,
  readFile,
  rename,
  rm,
  rmdir,
  unlink,
  writeFile,
} from 'node:fs/promises';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import {resolve} from 'node:path';
import {Buffer as OriginalBuffer} from 'node:buffer';
import {createPublicationObjectWrites} from './publication-object-writes.mjs';
import {createPreparedObjectOwnership} from './prepared-object-ownership.mjs';
import {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';
import {closedMetadataObjectExtent, createPhysicalHoldingObjectVerifier, createPhysicalHoldingReaders,
  createPhysicalHoldingRecordReader}
  from './physical-holding-record-reader.mjs';
import {createPhysicalHoldingLifecycle, createPhysicalHoldingRecordWriter} from './physical-holding-record-writer.mjs';
import {createPublicationMetadataInventory, createUncommittedPublicationCleanup} from './publication-metadata-inventory.mjs';
import {createPublicationMetadataDeletionMarkers, createPublicationMetadataRetirement}
  from './publication-metadata-deletion-markers.mjs';
import {createEffectCaptureCustodyRecords, createPublicationCustodyRecords} from './publication-custody-records.mjs';
import {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import {createPublicationIndexReader} from './publication-index-reader.mjs';
import {createPublicationResultMetadata} from './publication-result-metadata.mjs';
import {createPublicationContractStore} from './publication-contract-store.mjs';
import {createPublicationProgress} from './publication-progress.mjs';
import {createDeliveryAttemptStore} from './delivery-attempt-store.mjs';
import {createDeliveryRecordStore} from './delivery-record-store.mjs';
import {createManifestReadGrantStore} from './manifest-read-grant-store.mjs';
import {createRunMetadataInventory} from './run-metadata-inventory.mjs';
import {createPublicationReferenceOwner} from './publication-reference-owner.mjs';
import {createPublicationTrustedClock} from './publication-trusted-clock.mjs';
import {createPublicationObjectConsumer} from './publication-object-consumer.mjs';
import {createCommittedResultReaders, createDurableResultBindingVerifier} from './publication-result-reader.mjs';
import {createNativeMetadataMutationOwner} from './native-metadata-mutation-owner.mjs';
import {createPreparedCustodyQueue} from './prepared-custody-queue.mjs';
import {createPreparedHolderRegistry} from './prepared-holder-owner.mjs';
import {createPreparedSchemaOwner} from './prepared-publication-schema-owner.mjs';
import {createResultRetirement} from './result-deletion-owner.mjs';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';
import {cidPattern, exactKeys, fail, localDurability, PublicationStoreError, quantity, readBounded,
  retainStoreOpeningFailure, syncDirectoryPath, writeExclusive} from './publication-store-io.mjs';
import {removeOpeningTree, storeBootstrapAcquisition} from './publication-store-bootstrap.mjs';
import {acquireStoreOwnership} from './publication-store-ownership.mjs';
import {beginPreparedStoreAdoption, releasePreparedOwnership, retainPreparedStoreAdoptionFailure}
  from './prepared-publication-store-ownership.mjs';
import {indexKey, validateConfiguration, validateContractControl} from './publication-store-inputs.mjs';
import {admitExistingStoreFormat, createOriginalStoreStorageBindings, createStoreContract} from './publication-store-format.mjs';
import {createPrivatePublicationEvidence, privateEvidenceWireLimitForObject} from './publication-store-private-evidence.mjs';

export {assertOriginalPreparedLocalPublicationStoreFirstInitialization,
  assertOriginalPreparedLocalPublicationStoreOwnership, captureOriginalLocalExecutionOwner,
  closePreparedLocalPublicationStoreOwnership, originalLocalExecutionOwnerStopped,
  prepareLocalPublicationStoreOwnership} from './prepared-publication-store-ownership.mjs';

export {PublicationStoreError};

// Internal physical adapter primitive, not a Client read/authority entry. Its
// caller funds the complete metadata/decode lifetime before I/O and retains
// any existing failed-close cleanupHandle until confirmed physical close.
// Keep the actual implementation shared with ordinary Store metadata reads.
export {readBounded as readBoundedLocalMetadata};

const originalByteLength = OriginalBuffer.byteLength;
const originalApply = Reflect.apply;

// Read-only facility correspondence for the selected startup. Matching these
// actual imports does not issue a service, key, capacity or permission.
export function assertOriginalLocalPublicationStoreFacilityCurrent(bindings) {
  const originals = {promises: {lstat, link, mkdir, open, opendir, readdir, readFile,
    rename, rm, rmdir, unlink, writeFile},
    crypto: {createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID},
    buffer: {alloc: OriginalBuffer.alloc, allocUnsafe: OriginalBuffer.allocUnsafe,
      allocUnsafeSlow: OriginalBuffer.allocUnsafeSlow, byteLength: originalByteLength,
      concat: OriginalBuffer.concat, from: OriginalBuffer.from, isBuffer: OriginalBuffer.isBuffer}};
  for (const group of Object.keys(originals)) for (const name of Object.keys(originals[group])) {
    if (bindings?.[group]?.[name] !== originals[group][name]) fail('PublicationStoreFacilityChanged');
  }
}
// Physical holdings: Transfer material, Effect source/capture custody,
// encrypted publication evidence, Local continuation evidence, and generated
// or captured Content. These are kinds in the same physical custody owner,
// not additional Source namespaces or independent reference authorities.
const physicalHoldingNamespaces = Object.freeze([
  'remote-transfer', 'effect-source', 'effect-capture',
  'publication-private',
  'local-continuation-private',
  'content',
]);
const localContinuationEvidenceNames = Object.freeze([
  'captured_input', 'invocation_request', 'prepared_invocation',
  'review_projection', 'continuation_record', 'source_capture',
  'original_model_state',
]);
const nativeDeliveryContractNames = Object.freeze([
  'delivery_attempt', 'result_read_grant', 'delivery_record', 'result_delivery_receipt',
]);
// These objects retain their existing file/alias representation. Other
// publication contracts may live in the same Store's native metadata table.
const filePublicationContractNames = Object.freeze(['public_index_entry','schema',
  ...nativeDeliveryContractNames]);
const nativePublicationContract = name => !filePublicationContractNames.includes(name);
const nativeContractRead = name => name === 'public_index_entry' ||
  nativePublicationContract(name) ? 'publication' : nativeDeliveryContractNames.includes(name);
const recordNamePattern = /^(0|[1-9][0-9]*)\.json$/u;
const custodyNamePattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.json$/u;
const timestampPattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;

const cidHex = value => {
  const match = typeof value === 'string' ? cidPattern.exec(value) : null;
  if (!match) fail('InvalidPublicationObjectCid');
  return match[1];
};
// Keep this comparison workspace synchronous and dedicated: a short wire
// must not borrow an unrelated Buffer pool backing across the Store phase.
// Compare encoded bytes, not decoded replacement text or normalized strings.
const exactUtf8WireMatches = (bytes, wire) => {
  const length = Buffer.byteLength(wire, 'utf8');
  if (bytes.byteLength !== length) return false;
  const expected = Buffer.allocUnsafeSlow(length);
  expected.write(wire, 0, length, 'utf8');
  return bytes.equals(expected);
};

export async function openLocalPublicationStore(
  supplied,
  suppliedControl,
  durability = localDurability,
  suppliedBootstrap,
  preparedOriginal,
  operationalCurrent,
) {
  if (operationalCurrent !== undefined) {
    if (typeof operationalCurrent !== 'function') fail('InvalidPublicationStoreCurrent');
    operationalCurrent();
  }
  const prepared = beginPreparedStoreAdoption(preparedOriginal);
  try {
    return await openOriginalLocalPublicationStore(supplied, suppliedControl, durability,
      suppliedBootstrap, prepared, operationalCurrent);
  } catch (cause) {
    retainPreparedStoreAdoptionFailure(prepared, cause);
    throw cause;
  }
}

async function openOriginalLocalPublicationStore(
  supplied,
  suppliedControl,
  durability,
  suppliedBootstrap,
  prepared,
  operationalCurrent,
) {
  operationalCurrent?.();
  const configuration = validateConfiguration(supplied);
  const contractControl = validateContractControl(suppliedControl);
  const readDeliveryOriginal = contractControl.readIssuedDeliveryAttempt;
  const deliveryStartTransition = contractControl.deliveryTransition;
  const openingBootstrap = suppliedBootstrap === undefined ? undefined
    : storeBootstrapAcquisition(suppliedBootstrap, configuration.maxObjectBytes);
  // Adopt the selected exclusion's SAME cumulative directory reader. Creating
  // another view here would reset its history between prepare and Store open.
  // Metadata keeps its existing object bound and acquisition semantics.
  const bootstrap = prepared?.directoryBootstrap === undefined ? openingBootstrap : Object.freeze({
    readDirectory: prepared.directoryBootstrap.readDirectory,
    readMetadata: openingBootstrap?.readMetadata ??
      (path => readBounded(path, configuration.maxObjectBytes)),
  });
  const readOpeningDirectory = bootstrap?.readDirectory ?? readdir;
  const readOpeningMetadata = bootstrap?.readMetadata ??
    (path => readBounded(path, configuration.maxObjectBytes));
  if (!exactKeys(durability, ['syncDirectory']) ||
      typeof durability.syncDirectory !== 'function') {
    fail('InvalidPublicationStoreDurability');
  }
  const syncDirectory = durability.syncDirectory;
  const contractLimits = Object.freeze({
    maxWireBytes: configuration.maxObjectBytes,
    maxNodes: configuration.maxContractNodes,
    maxDepth: configuration.maxContractDepth,
  });
  const root = configuration.directory;
  if (prepared !== undefined && prepared.root !== root) fail('PublicationStoreOwnershipLost');
  if (prepared !== undefined) await prepared.ownership.assertCurrent();
  const objectsDirectory = resolve(root, 'objects');
  const contractsDirectory = resolve(root, 'contracts');
  const stagingDirectory = resolve(root, 'staging');
  const custodyDirectory = resolve(root, 'prepared-custody');
  const captureCustodyDirectory = resolve(root, 'effect-capture-custody');
  const preparedSchemasDirectory = resolve(root, 'prepared-schemas');
  const attemptsDirectory = resolve(root, 'attempts');
  const deliveriesDirectory = resolve(root, 'deliveries');
  const deliveryIndexPath = resolve(root, 'delivery-attempts.sqlite3');
  const deliveryCoveragePath = resolve(root, 'delivery-attempts-index.json');
  const manifestReadsDirectory = resolve(root, 'manifest-reads');
  const indexesDirectory = resolve(root, 'indexes');
  const metadataInventoriesDirectory = resolve(root, 'metadata-inventories');
  const metadataDeletionsDirectory = resolve(root, 'metadata-deletions');
  const physicalHoldingsDirectory = resolve(root, 'physical-holdings');
  const physicalHoldingDeletionsDirectory =
    resolve(root, 'physical-holding-deletions');
  const retentionExtensionsDirectory = resolve(root, 'retention-extensions');
  const deletionsDirectory = resolve(root, 'deletions');
  const clocksDirectory = resolve(root, 'clocks');
  const storeContract = Object.freeze({
    version: 'actql-local-publication-store/0.1',
    isolation: 'execution-namespace',
    store_authority_cid: configuration.storeAuthorityCid,
  });
  const storeContractBytes = Buffer.from(JSON.stringify(storeContract), 'utf8');
  const storeContractPath = resolve(root, 'store.json');
  await admitExistingStoreFormat(root, storeContractPath, storeContract, storeContractBytes,
    prepared, readOpeningDirectory, readOpeningMetadata);
  for (const directory of [root, objectsDirectory, contractsDirectory,
    stagingDirectory, custodyDirectory, captureCustodyDirectory, preparedSchemasDirectory,
    attemptsDirectory, deliveriesDirectory,
    manifestReadsDirectory, indexesDirectory, retentionExtensionsDirectory,
    metadataInventoriesDirectory, metadataDeletionsDirectory,
    physicalHoldingsDirectory, physicalHoldingDeletionsDirectory,
    deletionsDirectory,
    clocksDirectory]) {
    await mkdir(directory, {recursive: true, mode: 0o700});
  }

  const createdStore = await createStoreContract(root, storeContractPath, storeContractBytes,
    configuration, readOpeningMetadata, syncDirectory);

  let storedBytes = 0;
  let objectCount = 0;
  let nativePublicationBytes = 0, nativePublicationObjects = 0;
  let physicalBytes = 0, physicalObjects = 0;
  const unconfirmedPhysicalInstalls = new Map();
  const physicalRemovalOriginals = new Map();
  const physicalRemovalAcquisitions = new Map();
  const physicalRetirementFences = new Map();
  let assertPriorPhysicalUnborrowed = () => fail('PublicationStoreCleanupPending');
  const removalKey = original => `${original.cid}\0${original.device}\0${original.inode}`;
  const physicalRemovalFor = (cid, original) => {
    const matches = [...physicalRemovalOriginals.values()].filter(holder =>
      holder.original.cid === cid && (original === undefined ||
        holder.original.device === original.device && holder.original.inode === original.inode));
    if (matches.length > 1) fail('PublicationObjectAccountingMismatch');
    return matches[0];
  };
  const physicalOriginal = (cid, bytes, state) => Object.freeze({cid,
    byte_count: bytes, device: String(state.dev), inode: String(state.ino)});
  const accountPhysicalUsage = usage => {
    storedBytes += usage.bytes - physicalBytes;
    objectCount += usage.objects - physicalObjects;
    physicalBytes = usage.bytes;
    physicalObjects = usage.objects;
  };
  const accountPhysicalInstall = original => {
    const existing = unconfirmedPhysicalInstalls.get(original.cid);
    if (existing !== undefined) return existing.device === original.device && existing.inode === original.inode;
    unconfirmedPhysicalInstalls.set(original.cid, original);
    storedBytes += original.byte_count;
    objectCount++;
    return true;
  };
  const settlePhysicalInstalls = originals => {
    for (const original of originals) {
      const pending = unconfirmedPhysicalInstalls.get(original.cid);
      if (pending === undefined || pending.device !== original.device || pending.inode !== original.inode) continue;
      storedBytes -= pending.byte_count;
      objectCount--;
      unconfirmedPhysicalInstalls.delete(original.cid);
    }
  };
  // These calls follow the actual object directory ACK. A lost native reply
  // retains the same originals and their in-memory charge until cleanup or
  // same-original confirmation; no visible row alone supplies that ACK.
  const confirmPhysicalCapacity = (originals, retainPreparations = false) => {
    accountPhysicalUsage(deliveryIndex.recordPhysicalObjects(originals, {retainPreparations}));
    settlePhysicalInstalls(originals);
  };
  const rememberPhysicalRemoval = async (cid, bytes, state) => {
    const original = unconfirmedPhysicalInstalls.get(cid) ?? deliveryIndex.physicalObject(cid);
    const selected = state === undefined ? original
      : {cid, device: String(state.dev), inode: String(state.ino)};
    const pendingKey = selected === undefined ? undefined : removalKey(selected);
    if (pendingKey !== undefined && physicalRemovalAcquisitions.has(pendingKey)) {
      const pending = await physicalRemovalAcquisitions.get(pendingKey);
      if (pending.original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
      return pending;
    }
    const retained = physicalRemovalFor(cid, selected);
    if (retained !== undefined) {
      if (retained.original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
      return retained;
    }
    if (original === undefined) {
      if (state !== undefined) fail('PublicationObjectAccountingMissing');
      return undefined;
    }
    if (original.byte_count !== bytes) fail('PublicationObjectAccountingMismatch');
    if (state === undefined && deliveryIndex.physicalObject(cid,{priorLifetime:true}) !== undefined) {
      // The adopted opening row belongs to a closed prior Store lifetime,
      // not a current allocation whose FD could be reconstructed from a CID.
      // Reconcile only this absent row, under the existing namespace fence;
      // all current allocations and unrelated quota remain unchanged.
      const unborrowed = () => assertPriorPhysicalUnborrowed(cid,original);
      unborrowed();
      deliveryIndex.beginPhysicalObjectLifetime();
      deliveryIndex.retainPhysicalRemoval(original);
      const key = removalKey(original);
      let absent = false, settled = false, unlinkFlight, retireFlight;
      const confirmAbsent = async () => {
        unborrowed();
        try {
          await lstat(resolve(objectsDirectory,cid.slice(7)));
          fail('PublicationObjectAccountingMismatch');
        } catch (error) {if(error?.code!=='ENOENT')throw error;}
        if (!settled) unborrowed();
      };
      const holder = Object.freeze({
        original,
        get settled() {return settled;},
        unlinkOriginal() {
          if (settled) return Promise.resolve();
          return unlinkFlight ??= confirmAbsent().then(() => {absent = true;})
            .finally(() => {unlinkFlight = undefined;});
        },
        retireAfterDirectoryAck() {
          if (settled) return Promise.resolve();
          return retireFlight ??= Promise.resolve().then(async () => {
            if (!absent) fail('PublicationStoreCleanupPending');
            // Recheck after the real directory ACK: even a replacement from
            // outside the fenced Store must never receive this old refund.
            await confirmAbsent();
            if (settled) return;
            unborrowed();
            accountPhysicalUsage(deliveryIndex.removePhysicalObjects([original]));
            settled = true;
            physicalRemovalOriginals.delete(key);
            const owners = physicalRetirementFences.get(cid);
            owners?.delete(holder);
            if (owners?.size === 0) physicalRetirementFences.delete(cid);
          }).finally(() => {retireFlight = undefined;});
        },
      });
      physicalRemovalOriginals.set(key,holder);
      const owners = physicalRetirementFences.get(cid) ?? new Set();
      owners.add(holder);
      physicalRetirementFences.set(cid,owners);
      return holder;
    }
    if (state === undefined ||
        original.device !== String(state.dev) || original.inode !== String(state.ino)) {
      // A live owner never reconstructs an absent allocation's FD from a CID.
      // Interrupted processes are reconciled by the exclusive opening census
      // and its real directory ACK before this Store admits any new writer.
      fail('PublicationObjectAccountingMismatch');
    }
    const key = removalKey(original);
    if (physicalRemovalAcquisitions.has(key)) return physicalRemovalAcquisitions.get(key);
    const acquisition = (async () => {
      // Persist dirty recovery coverage before any physical unlink. Holding
      // this actual original FD prevents inode reuse through its unlink ACK.
      deliveryIndex.beginPhysicalObjectLifetime();
      const handle = await open(resolve(objectsDirectory, cid.slice(7)), constants.O_RDONLY | constants.O_NOFOLLOW);
      const holder = createPhysicalRetirementOwner(original, handle, {
        async pathState() {
          try { return await lstat(resolve(objectsDirectory, cid.slice(7))); }
          catch (error) { if (error?.code !== 'ENOENT') throw error; }
        },
        unlink: () => unlink(resolve(objectsDirectory, cid.slice(7))),
        fence(owner) {
          const owners = physicalRetirementFences.get(cid) ?? new Set();
          owners.add(owner);
          physicalRetirementFences.set(cid, owners);
        },
        releaseQuota(selected) {
          if (physicalRemovalOriginals.get(key) !== holder || selected !== original) {
            fail('PublicationObjectAccountingMismatch');
          }
          accountPhysicalUsage(deliveryIndex.removePhysicalObjects([original]));
          settlePhysicalInstalls([original]);
        },
        forget(owner) {
          if (physicalRemovalOriginals.get(key) === owner) physicalRemovalOriginals.delete(key);
          const owners = physicalRetirementFences.get(cid);
          owners?.delete(owner);
          if (owners?.size === 0) physicalRetirementFences.delete(cid);
        },
      });
      physicalRemovalOriginals.set(key, holder);
      try {
        const held = await handle.stat();
        if (!held.isFile() || held.size !== bytes || String(held.dev) !== original.device ||
            String(held.ino) !== original.inode) fail('PublicationObjectAccountingMismatch');
        deliveryIndex.retainPhysicalRemoval(original);
        holder.admit();
        return holder;
      } catch (error) {
        try { await holder.abandon(); }
        catch { /* The Store retains this quarantined original and its fence. */ }
        throw error;
      }
    })();
    physicalRemovalAcquisitions.set(key, acquisition);
    try { return await acquisition; }
    finally { physicalRemovalAcquisitions.delete(key); }
  };
  const releasePhysicalCapacity = async objects => {
    const holders = [...objects].map(([cid, holder]) => {
      if (holder === undefined) return undefined;
      if (holder.original?.cid !== cid || typeof holder.retireAfterDirectoryAck !== 'function' ||
          !holder.settled && physicalRemovalOriginals.get(removalKey(holder.original)) !== holder) {
        fail('PublicationObjectAccountingMismatch');
      }
      return holder.settled ? undefined : holder;
    }).filter(Boolean);
    // Each immutable holder owns a single-flight close+quota settlement.
    // Concurrent old continuations cannot pass an await and remove a successor.
    for (const holder of holders) await holder.retireAfterDirectoryAck();
  };
  const syncPhysicalRemovals = async objects => {
    for (const holder of objects.values()) if (holder !== undefined) await holder.unlinkOriginal();
    await syncDirectory(objectsDirectory);
  };
  const confirmPhysicalRemovals = async objects => {
    await syncPhysicalRemovals(objects);
    await releasePhysicalCapacity(objects);
  };
  const accountNativePublication = usage => {
    storedBytes += usage.bytes - nativePublicationBytes;
    objectCount += usage.objects - nativePublicationObjects;
    nativePublicationBytes = usage.bytes;
    nativePublicationObjects = usage.objects;
  };
  // One process owns the complete capacity authority for this local Store.
  // A dead local owner can be reclaimed, but two live opens never maintain
  // independent counters for the same physical allocation scope.
  let ownership, deliveryIndex;
  // This is file-preparation progress, never cached authorization or durable
  // ACK. A failed same-lifetime preparation remains unresolved until restart.
  const deliveryStarts = new Map();
  if (prepared === undefined) {
    ownership = await acquireStoreOwnership(root, bootstrap, configuration.privateEvidenceKey);
  } else {
    await prepared.ownership.assertCurrent();
    if (prepared.phase !== 'adopting' || prepared.closing || prepared.ownership === undefined) {
      fail('PublicationStoreOwnershipLost');
    }
    prepared.phase = 'adopted';
    ownership = Object.freeze({release: () => releasePreparedOwnership(prepared)});
  }
  try {
  let removedStaging = false;
  for (const name of await readOpeningDirectory(stagingDirectory)) {
    const path = resolve(stagingDirectory, name);
    if (!/^object-[0-9a-f-]{36}$/u.test(name) ||
        !(await lstat(path)).isFile()) {
      fail('InvalidPublicationStagingObject');
    }
    await unlink(path);
    removedStaging = true;
  }
  if (removedStaging) await syncDirectory(stagingDirectory);

  for (const name of await readOpeningDirectory(custodyDirectory)) {
    const path = resolve(custodyDirectory, name);
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedCustody');
    }
  }
  // Opening only observes these names. The selected custody recovery below
  // owns any actual unlink and its acknowledgement.
  let removedSchemaStaging = false;
  for (const name of await readOpeningDirectory(preparedSchemasDirectory)) {
    const path = resolve(preparedSchemasDirectory, name);
    if (/^\.staging-[0-9a-f-]{36}\.json$/u.test(name)) {
      await unlink(path);
      removedSchemaStaging = true;
      continue;
    }
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedSchema');
    }
  }
  if (removedSchemaStaging) await syncDirectory(preparedSchemasDirectory);

  // Delivery coverage and pending recovery below own the selected entries.
  // Ordinary opens must not enumerate every historical delivery directory.
  // Manifest use admission and legacy staging recovery belong to the selected
  // grant. Committed grants are not another all-history opening inventory.
  const openingMetadataDeletionNames = [];
  let removedMetadataStaging = false;
  for (const name of await readOpeningDirectory(metadataDeletionsDirectory)) {
    const path = resolve(metadataDeletionsDirectory, name);
    if (name.startsWith('.staging-')) {
      await unlink(path);
      removedMetadataStaging = true;
      continue;
    }
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(metadataDeletionsDirectory, name))).isFile()) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    openingMetadataDeletionNames.push(name);
  }
  if (removedMetadataStaging) await syncDirectory(metadataDeletionsDirectory);
  // Immutable holdings are checked through their selected original FD, not
  // by enumerating all committed names at every open. Pending deletion
  // records still require bounded opening admission and actual recovery.
  for (const name of await readOpeningDirectory(physicalHoldingDeletionsDirectory)) {
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(physicalHoldingDeletionsDirectory, name))).isFile()) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
  }
  // Each selected extension reader owns its directory types, complete chain
  // and actual Result-directory ACK. Unrelated committed histories are not
  // another ordinary opening admission or durability transition.
  // Result deletion recovery owns its bounded names only after the native
  // lifecycle reports unfinished or legacy cleanup, not on every clean open.
  let removedClockStaging = false;
  for (const name of await readOpeningDirectory(clocksDirectory)) {
    const path = resolve(clocksDirectory, name);
    if (name.startsWith('.staging-')) {
      await rm(path, {force: false});
      removedClockStaging = true;
      continue;
    }
    // The selected clock reader owns its actual file/type/checksum admission.
    // Opening retains only name admission and legacy staging cleanup here.
    if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
      fail('InvalidPublicationClockObservation');
    }
  }
  if (removedClockStaging) await syncDirectory(clocksDirectory);

  let reservedBytes = 0;
  let reservedObjects = 0;
  let closed = false;
  let closeRequested = false, closeFlight;
  const preparedObjects = new Map();
  const preparedSchemas = new Map();
  const preparedObjectOwners = createPreparedHolderRegistry(() => fail('InvalidPublicationPreparedOwner'));
  const reclaimableCustodies = new Map();
  const withPreparedCustody = createPreparedCustodyQueue();
  let semanticCommitBusy = Promise.resolve();
  const withSemanticCommit = operation => {
    const flight = semanticCommitBusy.then(operation);
    semanticCommitBusy = flight.catch(() => {});
    return flight;
  };
  const durablyConfirmedIndexes = new Map();
  let materialRetentionBusy = Promise.resolve();
  let metadataRetentionBusy = Promise.resolve();
  const activeResultReaders = new Map();
  const activePhysicalHoldingReaders = new Map();
  // Same Store lifetime only, not another capacity grant or semantic authority.
  // Keep the original read/failed-close custody until that exact FD closes.
  const activeSemanticReaders = new Set();
  // The same Store retains an unfinished metadata writer's original FD and
  // staging alias. Neither a failed write nor caller error disposal retires it.
  const activePhysicalRecordWriters = new Set();
  const pendingResultDeletions = new Map();
  const pendingMetadataDeletions = new Map();
  const pendingMetadataDeletionMarkers = new Map();
  const metadataDeletionIntents = new Set();
  const pendingMetadataFenceCompletions = new Map();
  let metadataFencesReady = false;
  const pendingPhysicalHoldingDeletions = new Map();
  const pendingUncommittedMetadataCleanups = new Map();
  const reclaimingMaterialCids = new Set();
  assertPriorPhysicalUnborrowed = (cid, original) => {
    const prepared = preparedObjects.get(cid);
    if (reservedObjects !== 0 || activePhysicalRecordWriters.size !== 0 ||
        activeSemanticReaders.size !== 0 || activeResultReaders.size !== 0 ||
        activePhysicalHoldingReaders.size !== 0 || unconfirmedPhysicalInstalls.has(cid) ||
        prepared !== undefined && (prepared.holders.size !== 0 || prepared.commitOwners.size !== 0)) {
      fail('PublicationStoreCleanupPending');
    }
    const prior = deliveryIndex.physicalObject(cid,{priorLifetime:true});
    if (prior?.byte_count !== original.byte_count || prior?.device !== original.device ||
        prior?.inode !== original.inode) fail('PublicationObjectAccountingMismatch');
  };

  const objectPath = cid => resolve(objectsDirectory, cidHex(cid));
  const custodyPath = token => resolve(custodyDirectory, `${token}.json`);
  const preparedSchemaPath = token =>
    resolve(preparedSchemasDirectory, `${token}.json`);
  const contractPath = cid => resolve(contractsDirectory, `${cidHex(cid)}.json`);
  const publicationAttemptPath = cid =>
    resolve(attemptsDirectory, cidHex(cid));
  const deliveryAttemptPath = cid =>
    resolve(deliveriesDirectory, cidHex(cid));
  const metadataInventoryPath = publicIndexEntryCid =>
    resolve(metadataInventoriesDirectory, `${cidHex(publicIndexEntryCid)}.json`);
  const metadataDeletionPath = keyHash =>
    resolve(metadataDeletionsDirectory, `${keyHash}.json`);
  const physicalHoldingPath = holdingCid =>
    resolve(physicalHoldingsDirectory, `${cidHex(holdingCid)}.json`);
  const physicalHoldingDeletionPath = holdingCid => resolve(
    physicalHoldingDeletionsDirectory,
    `${cidHex(holdingCid)}.json`,
  );

  const writePhysicalHoldingRecord = createPhysicalHoldingRecordWriter(
    stagingDirectory, syncDirectory, activePhysicalRecordWriters,
  );
  const retentionExtensionDirectory = keyHash =>
    resolve(retentionExtensionsDirectory, keyHash);
  const retentionExtensionResultDirectory = (
    keyHash,
    resultDefinitionCid,
  ) =>
    resolve(
      retentionExtensionDirectory(keyHash),
      cidHex(resultDefinitionCid),
    );
  const resultDeletionDirectory = keyHash =>
    resolve(deletionsDirectory, keyHash);
  const resultDeletionPath = (keyHash, resultDefinitionCid) =>
    resolve(
      resultDeletionDirectory(keyHash),
      `${cidHex(resultDefinitionCid)}.json`,
    );
  const active = () => {
    // This refusal-only callback is captured from the actual selected Root;
    // it is not itself an issuer and never participates in cleanup ACKs.
    operationalCurrent?.();
    if (closed || closeRequested) fail('PublicationStoreClosed');
  };

  const {parsePhysicalHolding, readPhysicalHoldingAt, admitPhysicalHolding} =
    createPhysicalHoldingRecordReader(configuration, physicalHoldingNamespaces);

  const readPhysicalHolding = (holdingCid, readDemand) =>
    readPhysicalHoldingAt(physicalHoldingPath(holdingCid), holdingCid, readDemand);

  const readPhysicalHoldingDeletion = (holdingCid, readDemand) =>
    readPhysicalHoldingAt(physicalHoldingDeletionPath(holdingCid), holdingCid, readDemand);

  const currentDeliveryIndex = () => deliveryIndex;
  const {stageMetadataInventory, writeNativeIndexOriginal} =
    createNativeMetadataMutationOwner(currentDeliveryIndex, activePhysicalRecordWriters);

  const metadataFencesAreReady = () => metadataFencesReady;
  const {readMetadataDeletion, compactMetadataDeletion, ensureMetadataDeletion, runMetadataDeletionStarted} =
    createPublicationMetadataDeletionMarkers(
      configuration, metadataDeletionPath, metadataDeletionsDirectory, syncDirectory,
      currentDeliveryIndex, metadataFencesAreReady, metadataDeletionIntents,
      pendingMetadataFenceCompletions, timestampPattern,
    );

  const {readMetadataInventory, readCommittedMetadataInventory, requireCommittedMetadataInventory,
    publicationRecoveryOriginal, publicationRecoveryValue, ensureMetadataInventory,
    restoreMetadataInventory, recoverMetadataInventory} = createPublicationMetadataInventory(
    configuration, metadataInventoriesDirectory, metadataInventoryPath, syncDirectory,
    currentDeliveryIndex, stageMetadataInventory, readPhysicalHolding, readPhysicalHoldingDeletion,
    readMetadataDeletion,
  );

  const verifyObject = createPublicationObjectVerifier(
    configuration, objectPath, cidHex, active, activeSemanticReaders, physicalContentReadWindowBytes,
  );

  const trustedClock = createPublicationTrustedClock(configuration, clocksDirectory, contractControl,
    activePhysicalRecordWriters, active, cidHex, syncDirectory);

  const writeState = {
    get storedBytes() {return storedBytes;},
    get objectCount() {return objectCount;},
    get reservedBytes() {return reservedBytes;},
    set reservedBytes(bytes) {reservedBytes = bytes;},
    get reservedObjects() {return reservedObjects;},
    set reservedObjects(objects) {reservedObjects = objects;},
    get materialRetentionBusy() {return materialRetentionBusy;},
    set materialRetentionBusy(operation) {materialRetentionBusy = operation;},
  };
  const {reserveObjectCapacity, createObjectWriter, putBytes} = createPublicationObjectWrites(
    configuration, stagingDirectory, objectsDirectory, writeState, reclaimingMaterialCids, physicalRetirementFences, {
      active, syncDirectory, objectPath, currentDeliveryIndex, physicalOriginal,
      confirmPhysicalCapacity, settlePhysicalInstalls, accountPhysicalInstall, verifyObject,
      get registerCustody() {return registerCustody;},
      get removeCustodyRecord() {return removeCustodyRecord;},
      get reclaimCustody() {return reclaimCustody;},
    },
  );

  const {createPreparedObjectWriter, confirmPreparedMaterials, adoptPreparedObjects, beginPreparedCommit} =
    createPreparedObjectOwnership(preparedObjects, preparedObjectOwners, withPreparedCustody, writeState, {
      createObjectWriter, objectPath, confirmPhysicalRemovals, rememberPhysicalRemoval, verifyObject,
      removeCustodyRecord: (...args) => removeCustodyRecord(...args),
      reclaimCustody: (...args) => reclaimCustody(...args),
      materialHasLiveReference: (...args) => materialHasLiveReference(...args),
      confirmCommittedIndex: (...args) => confirmCommittedIndex(...args),
    });

  // Semantic contract identities exclude their self-CID field and therefore
  // are deliberately not the physical digest of the stored complete body.
  // The binding is an exclusive hard link to one immutable physical object.
  const putSemanticBatch = async (supplied, retainedOriginals, recoveryInventory) => {
    active();
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    // This private caller supplies one semantic body, an admitted delivery
    // group or a bounded publication metadata group. Original generation
    // records precede final-name acquisition in the existing native metadata
    // transaction. No per-item custody file or directory barrier is needed.
    const items = supplied.map(({wire, semanticCid}) => {
      if (typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidPublicationSemanticWire');
      }
      cidHex(semanticCid);
      const bytes = Buffer.from(wire, 'utf8');
      return {wire, semanticCid, bytes,
        cid: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
        handle: undefined, close: undefined, temporary: undefined,
        reservation: undefined, state: undefined, objectLinkAttempted: false,
        accounted: false, objectCreated: false, created: true};
    });
    if (recoveryInventory !== undefined) {
      const retained = deliveryIndex.pendingPublication(recoveryInventory.public_index_cid);
      if (retained?.inventory_wire !== recoveryInventory.inventory_wire) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = publicationRecoveryValue(retained);
      for (const item of items) {
        const member = inventory.contract_objects.find(value => value.semantic_cid === item.semanticCid);
        if (member?.physical_cid !== item.cid || member.byte_count !== item.bytes.byteLength) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
      }
    }
    const writer = {cleanup: undefined, failed: false};
    const dirty = new Set();
    activePhysicalRecordWriters.add(writer);
    const account = item => {
      if (item.accounted) return;
      item.accounted = accountPhysicalInstall(physicalOriginal(item.cid,item.bytes.byteLength,item.state));
    };
    let physicalPreparations, aliasesPublished = false;
    const syncNames = async () => {
      for (const directory of [objectsDirectory, contractsDirectory]) {
        if (!dirty.has(directory)) continue;
        await syncDirectory(directory);
        if (directory === objectsDirectory) {
          confirmPhysicalCapacity(items.filter(item=>item.objectCreated)
            .map(item=>physicalOriginal(item.cid,item.bytes.byteLength,item.state)), true);
        }
        if (directory === contractsDirectory && aliasesPublished) {
          if (physicalPreparations !== undefined) {
            deliveryIndex.finishPhysicalPreparations(physicalPreparations);
            physicalPreparations=undefined;
          }
        }
        dirty.delete(directory);
      }
    };
    let flight, failure;
    const status = () => Object.freeze({pending: dirty.size !== 0 || physicalPreparations!==undefined || items.some(item =>
      item.handle !== undefined || item.temporary !== undefined || item.reservation?.held)});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        let firstFailure, failed = false;
        // Each original FD can retire independently. A failed second close
        // must not retain an already closed unpublished first staging file.
        for (const item of items) {
          try {
            if (item.handle !== undefined) {
              if (item.close === undefined) item.close = item.handle.close;
              if (await Reflect.apply(item.close, item.handle, []) === false) {
                fail('PublicationStoreCleanupPending');
              }
              item.handle = item.close = undefined;
            }
            if (item.objectLinkAttempted && !item.objectCreated) {
              let original;
              try { original = await lstat(objectPath(item.cid)); }
              catch (error) { if (error?.code !== 'ENOENT') throw error; }
              // Observe a lost link reply without reissuing the link/write.
              if (original?.isFile() && original.dev === item.state.dev &&
                  original.ino === item.state.ino) {
                account(item);item.objectCreated=true;
              } else {
                settlePhysicalInstalls([physicalOriginal(item.cid,item.bytes.byteLength,item.state)]);
                item.accounted=false;
              }
            }
            if (item.temporary !== undefined) {
              try { await unlink(item.temporary); }
              catch (error) { if (error?.code !== 'ENOENT') throw error; }
              item.temporary = undefined;
            }
            item.reservation?.release();
          } catch (error) {
            if (!failed) firstFailure = error;
            failed = true;
          }
        }
        // Complete only those original final-name ACKs already attempted.
        // Completed immutable objects remain charged in the Store inventory;
        // a failed semantic publication is not permission to refill capacity.
        try { await syncNames(); } catch (error) {
          if (!failed) firstFailure = error;
          failed = true;
        }
        if (dirty.size===0 && physicalPreparations!==undefined) {
          try {
            const closed = items.every(item => item.handle === undefined && item.temporary === undefined);
            if (closed && !items.some(item => item.objectLinkAttempted)) {
              // A failed stage never attempted installation. Confirm absence
              // before same-original metadata settlement, including Unknown.
              await syncDirectory(objectsDirectory);
              deliveryIndex.finishPhysicalPreparations(physicalPreparations);
              physicalPreparations=undefined;
            } else {
              let settled = true;
              for (const item of items) {
                if (item.preparation === undefined) continue;
                if (item.handle !== undefined || item.temporary !== undefined) {settled = false; continue;}
                if (await reclaimNativePreparation(item.preparation) !== true) settled = false;
              }
              if (settled) physicalPreparations=undefined;
            }
          } catch(error){if(!failed)firstFailure=error;failed=true;}
        }
        if (!status().pending) activePhysicalRecordWriters.delete(writer);
        if (failed) throw firstFailure;
        return status();
      }).finally(() => {
        flight = undefined;
        if (failure !== undefined) failure.cleanupPending = status().pending;
      });
      return flight;
    }});
    try {
      for (const item of items) {
        try {
          const existing = await verifyObject(item.cid);
          if (existing.bytes !== item.bytes.byteLength) fail('PublicationObjectIdentityMismatch');
          continue;
        } catch (error) { if (error?.code !== 'PublicationObjectMissing') throw error; }
        item.reservation = reserveObjectCapacity(item.bytes.byteLength);
        item.temporary = resolve(stagingDirectory, `object-${randomUUID()}`);
        item.handle = await open(item.temporary,
          constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
        item.close = item.handle.close;
        let offset = 0;
        while (offset < item.bytes.byteLength) {
          const {bytesWritten} = await item.handle.write(item.bytes, offset,
            item.bytes.byteLength - offset, offset);
          if (!quantity(bytesWritten) || bytesWritten === 0 ||
              bytesWritten > item.bytes.byteLength - offset) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
        await item.handle.sync();
        item.state = await item.handle.stat();
        if (!item.state.isFile() || item.state.size !== item.bytes.byteLength) {
          fail('IncompletePublicationWrite');
        }
        if (await Reflect.apply(item.close, item.handle, []) === false) {
          fail('PublicationStoreCleanupPending');
        }
        item.handle = item.close = undefined;
      }
      const originals=(recoveryInventory === undefined ? items : [])
        .filter(item=>item.temporary!==undefined).map(item =>
        item.preparation = Object.freeze({...physicalOriginal(item.cid,item.bytes.byteLength,item.state),
          semantic_cid:item.semanticCid}));
      if(originals.length!==0) {
        deliveryIndex.beginPhysicalObjectLifetime();
        physicalPreparations=originals;
        deliveryIndex.stagePhysicalObjects(originals, {durable: true});
      }
      for (const item of items) {
        if (item.temporary === undefined) continue;
        if (reclaimingMaterialCids.has(item.cid) || physicalRetirementFences.has(item.cid)) fail('PublicationObjectReclamationPending');
        item.objectLinkAttempted = true;
        dirty.add(objectsDirectory);
        account(item);
        try { await link(item.temporary, objectPath(item.cid)); item.objectCreated=true; }
        catch (error) {
          if (error?.code !== 'EEXIST') throw error;
          if ((await verifyObject(item.cid)).bytes !== item.bytes.byteLength) {
            fail('PublicationObjectIdentityMismatch');
          }
          settlePhysicalInstalls([physicalOriginal(item.cid,item.bytes.byteLength,item.state)]);
          item.accounted=false;
        }
      }
      await syncNames();
      for (const item of items) {
        dirty.add(contractsDirectory);
        try { await link(objectPath(item.cid), contractPath(item.semanticCid)); }
        catch (error) {
          if (error?.code !== 'EEXIST') throw error;
          item.created = false;
          const existing = await readBounded(contractPath(item.semanticCid), configuration.maxObjectBytes);
          if (!exactUtf8WireMatches(existing, item.wire)) fail('PublicationSemanticIdentityConflict');
        }
      }
      aliasesPublished = true;
      await syncNames();
      // Staging names never establish durable state. They are unlinked only
      // after original close; a name resurrected by a crash is removed by the
      // existing exclusive opening recovery, not interpreted as a commit.
      await cleanup.retry();
      // Only these two newly linked names belong to this successful writer.
      // Its bounded bytes/digest and real file/close/directory ACKs already
      // establish the same-commit inventory fact. Existing aliases still use
      // their actual reader; no observation escapes this operation's map.
      if (retainedOriginals !== undefined) {
        for (const item of items) {
          if (item.objectCreated && item.created) retainedOriginals.set(
            item.semanticCid, Object.freeze({bytes: item.bytes, physicalCid: item.cid}),
          );
        }
      }
      return Object.freeze(items.map(item => Object.freeze({semanticCid: item.semanticCid,
        physical: Object.freeze({cid: item.cid, bytes: item.bytes.byteLength,
          created: item.objectCreated}), created: item.created})));
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      failure = new PublicationStoreError(primary?.code ?? 'PublicationSemanticWriteFailed', primary);
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };

  const putSemantic = async (wire, semanticCid) =>
    (await putSemanticBatch([{wire, semanticCid}]))[0];

  // These immutable inputs were admitted by the existing delivery queue.
  // They share final-name durability, without an exported prepared interval.
  const {admitContract, parseContract, admitOriginalContract, putAdmittedPublicationContract, putPublicationContract,
    putNativePublicationContracts, admitPublicationContracts, putAdmittedPublicationContracts,
    putPublicationContracts, putOriginalPublicationContracts} =
    createPublicationContractStore(configuration, contractControl, contractLimits, activePhysicalRecordWriters, {
      active, currentDeliveryIndex, nativePublicationContract, contractPath,
      readSemanticOriginal: (...args) => readSemanticOriginal(...args), exactUtf8WireMatches,
      reserveObjectCapacity, accountNativePublication, putSemantic, putSemanticBatch,
    });

  const {nativeDeliveryContract, readSemanticOriginal, readSemanticBytes, readContract, readJsonObject} =
    createPublicationSemanticReader(configuration, activeSemanticReaders, physicalContentReadWindowBytes, {
      contractPath, objectPath, active, currentDeliveryIndex, admitContract, admitOriginalContract,
      nativeContractRead, parseContract,
    });

  const verifyDurableResultBinding = createDurableResultBindingVerifier(configuration,
    {parseContract, readSemanticOriginal, cidHex, verifyObject});

  const {createAttempt, beginPublicationAttempt, beginPublicationAttemptWithRecords, latestRecordContract,
    latestRecord, appendRecord, appendInitialPublicationRecords} =
    createPublicationProgress(configuration, attemptsDirectory, recordNamePattern, contractControl, {
      admitContract, parseContract, admitPublicationContracts, putAdmittedPublicationContract, putAdmittedPublicationContracts,
      putNativePublicationContracts, active, currentDeliveryIndex, runMetadataDeletionStarted, publicationAttemptPath, contractPath,
      syncDirectory, nativePublicationContract, readContract,
    });

  const {readFileDeliveryAttemptContract, readDeliveryAttemptContract, deliveryIndexRow, admitDeliveryClaim, restoreDeliveryClaim,
    enqueueDeliveryAdmission, createDeliveryAttempt, beginDeliveryAttempt, lookupDeliveryAttempt, selectDeliveryAttempt} =
    createDeliveryAttemptStore(configuration, deliveriesDirectory, recordNamePattern, contractControl, readDeliveryOriginal,
      deliveryStartTransition, deliveryStarts, activePhysicalRecordWriters, {
        active, currentDeliveryIndex, contractPath, deliveryAttemptPath, exactUtf8WireMatches, syncDirectory,
        runMetadataDeletionStarted, putSemanticBatch, admitContract, parseContract, nativeDeliveryContract, readContract,
        readSemanticBytes, readLatestDeliveryRecordContract: (...args) => readLatestDeliveryRecordContract(...args),
      });

  const initializeDeliveryIndex = async () => {
    let coverage, indexExists = false;
    try {
      const bytes = await readBounded(deliveryCoveragePath,128);
      coverage = JSON.parse(bytes.toString('utf8'));
      if (!exactKeys(coverage,['version','phase']) || coverage.version !== 1 ||
          !['building','ready'].includes(coverage.phase)) fail('DeliveryAttemptIndexUnavailable');
    } catch (error) { if (error?.code !== 'ENOENT') throw error; }
    try {
      const state = await lstat(deliveryIndexPath);
      if (!state.isFile() || state.isSymbolicLink()) fail('DeliveryAttemptIndexUnavailable');
      indexExists = true;
    } catch (error) { if (error?.code !== 'ENOENT') throw error; }
    if (coverage?.phase === 'ready' && !indexExists || coverage === undefined && indexExists) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    const publishCoverage = async phase => {
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
    deliveryIndex = await openDeliveryAttemptIndex(deliveryIndexPath,{
      create: coverage.phase === 'building', maxEntries: configuration.maxObjects,
      maxWireBytes: configuration.maxObjectBytes,
      initializeEmpty: createdStore,
    });
    const migratePhysical=deliveryIndex.physicalObjectUsage().complete===0;
    const recoverPhysical=deliveryIndex.physicalObjectRecoveryRequired();
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
      if(migratePhysical)deliveryIndex.migratePhysicalObjects(originals);
      else{
        await syncDirectory(objectsDirectory);
        deliveryIndex.recoverPhysicalObjects(originals);
      }
    }
    accountPhysicalUsage(deliveryIndex.physicalObjectUsage());
    if (deliveryIndex.needsMigration()) {
      if (coverage.phase !== 'building') fail('DeliveryAttemptIndexUnavailable');
      const rows = [], grants = new Map(), uses = new Map();
      // Building coverage is not an empty native lookup. This explicit
      // migration reads the original legacy files before publishing rows;
      // ordinary lookups still require complete native coverage.
      const readLegacySemantic = cid => readSemanticOriginal(cid,false);
      for (const name of await readdir(deliveriesDirectory)) {
        if (name.startsWith('.staging-')) {
          await removeOpeningTree(resolve(deliveriesDirectory,name),bootstrap);
          continue;
        }
        if (!/^[0-9a-f]{64}$/u.test(name) ||
            !(await lstat(resolve(deliveriesDirectory,name))).isDirectory()) fail('InvalidDeliveryAttemptStore');
        if (rows.length >= configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
        const attemptContract = await readFileDeliveryAttemptContract(`sha256:${name}`);
        const attempt = parseContract(attemptContract);
        let original = grants.get(attempt.result_read_grant_cid);
        if (original === undefined) {
          original = await readContract(attempt.result_read_grant_cid,'result_read_grant',readLegacySemantic);
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
      deliveryIndex.migrate(rows);
    }
    accountNativePublication(deliveryIndex.publicationUsage());
    if (storedBytes > configuration.capacityBytes || objectCount > configuration.maxObjects) {
      fail('PublicationStoreCapacity');
    }
    if (coverage.phase !== 'ready') await publishCoverage('ready');
    if (deliveryIndex.needsPublicationRecoveryMigration()) {
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
        const inventory = await readMetadataInventory(`sha256:${name.slice(0,-5)}`);
        const key = {namespaceId:inventory.namespace_id,
          authorityScopeCid:inventory.authority_scope_cid,runDefinitionCid:inventory.run_definition_cid};
        if ((await confirmCommittedIndex(key))?.public_index_entry_cid !== inventory.public_index_entry_cid) {
          rows.push(publicationRecoveryOriginal(inventory));
        }
      }
      await syncDirectory(metadataInventoriesDirectory);
      deliveryIndex.migratePublicationRecovery(rows);
    }
    // Only a newly adopted private format reads historical retirement markers.
    // Batch progress is idempotent after a lost migration COMMIT; the actual
    // files remain until complete native coverage acknowledges their fences.
    const names = openingMetadataDeletionNames;
    if (deliveryIndex.needsMetadataDeletionFenceMigration()) {
      let rows=[];
      for (const name of names) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name)) fail('InvalidPublicationMetadataDeletionStore');
        const keyHash=name.slice(0,-5),marker=await readMetadataDeletion(keyHash);
        if(marker===undefined)fail('InvalidPublicationMetadataDeletionStore');
        rows.push({metadata_key:keyHash,run_cid:marker.run_definition_cid,
          retired:marker.version==='actql-local-publication-metadata-retired/0.1'?1:0});
        if(rows.length===Math.max(1,configuration.maxObjects)) {
          deliveryIndex.migrateMetadataDeletionFences(rows);rows=[];
        }
      }
      deliveryIndex.migrateMetadataDeletionFences(rows,true);
    }
    metadataFencesReady=true;
    let removed=false;
    for(const name of names) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) fail('InvalidPublicationMetadataDeletionStore');
      const keyHash=name.slice(0,-5),marker=await readMetadataDeletion(keyHash);
      if(marker===undefined)fail('InvalidPublicationMetadataDeletionStore');
      const fence=deliveryIndex.metadataDeletionFence(keyHash);
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
    const pending = deliveryIndex.pending();
    if (pending.length > configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
    for (const row of pending) {
      if (!await runMetadataDeletionStarted(row.run_cid)) await restoreDeliveryClaim(row);
    }
  };

  const {consumeManifestReadGrant} = createManifestReadGrantStore(
    configuration, manifestReadsDirectory, activePhysicalRecordWriters,
    {active, cidHex, runMetadataDeletionStarted, syncDirectory, writePhysicalHoldingRecord,
      admitContract, parseContract, putAdmittedPublicationContract},
  );

  const {readLatestDeliveryRecordContract, latestDeliveryRecordContract, latestDeliveryRecord,
    confirmDeliveryRecord, appendDeliveryRecord, appendDeliveryCompletion} =
    createDeliveryRecordStore(configuration, deliveriesDirectory, recordNamePattern, contractControl, deliveryStarts, {
      active, currentDeliveryIndex, contractPath, deliveryAttemptPath, exactUtf8WireMatches, syncDirectory,
      runMetadataDeletionStarted, putSemantic, putSemanticBatch, admitContract, parseContract, enqueueDeliveryAdmission,
      readDeliveryAttemptContract, readContract, readSemanticBytes,
    });

  const selectedPublicationReads = new WeakMap();
  const {admitNativeIndexOriginal, inspectCommittedIndexRaw, inspectCommittedIndex, confirmCommittedIndex,
    confirmSelectedCommittedIndex, readCommittedPublication, lookupCommittedIndex} =
    createPublicationIndexReader(configuration, indexesDirectory, durablyConfirmedIndexes, selectedPublicationReads, {
      active, currentDeliveryIndex, admitContract, parseContract, readSemanticBytes, exactUtf8WireMatches,
      readMetadataDeletion, requireCommittedMetadataInventory, syncDirectory, writeNativeIndexOriginal,
    });

  // The existing computation owner validates the containing chain first.
  // Here the Store confirms each common-described custody cell, including
  // Content not selected into a public Result. Equal bytes do not substitute
  // another Run/output occurrence's holding or encrypted proof.
  const confirmCapturedContentHoldings = async (captured, definition) => {
    active();
    const context = parseContract(captured).effect_context;
    if (!Object.hasOwn(context, 'content_generations')) return Object.freeze([]);
    if (typeof contractControl.capturedContentGenerationCount !== 'function' ||
        typeof contractControl.capturedContentGenerationStorage !== 'function') {
      fail('PublicationContentInventoryUnsupported');
    }
    const count = contractControl.capturedContentGenerationCount(captured);
    if (!quantity(count) || count < 1) fail('PublicationContentInventoryInvalid');
    const cids = [];
    for (let index = 0; index < count; index++) {
      const binding = contractControl.capturedContentGenerationStorage(captured,
        definition, configuration.storeAuthorityCid, index);
      const holding = await inspectPhysicalHolding(binding.holdingCid);
      if (holding?.namespace !== 'content' ||
          holding.manifest_cid !== binding.manifestCid || holding.objects.length !== 1 ||
          holding.objects[0].cid !== binding.contentCid ||
          BigInt(holding.objects[0].byte_count) !== binding.byteCount) {
        fail('PublicationContentHoldingUnavailable');
      }
      await commitPhysicalHolding(holding, []);
      cids.push(binding.holdingCid);
      for (const proof of binding.bindings) {
        if (await confirmPrivateEvidence(proof) === undefined) {
          fail('PublicationContentEvidenceUnavailable');
        }
        cids.push(proof.holdingCid);
      }
    }
    if (new Set(cids).size !== cids.length) fail('PublicationContentInventoryInvalid');
    return Object.freeze(cids.sort());
  };

  const verifyCommitEvidence = async (
    admitted,
    entry,
    suppliedEvidence,
    required,
    readOriginal = (cid, includeNative) => readSemanticOriginal(cid, includeNative),
  ) => {
    if (!exactKeys(suppliedEvidence, [
      'runDefinition',
      'invocation',
      'definitions',
      'artifacts',
      'derivations',
      'orderings',
      'retentions',
      'durableBindings',
      'manifest',
      'receipt',
      'capturedRun',
    ]) || !Array.isArray(suppliedEvidence.definitions) ||
        suppliedEvidence.definitions.length === 0 ||
        !Array.isArray(suppliedEvidence.artifacts) ||
        suppliedEvidence.artifacts.length === 0 ||
        !Array.isArray(suppliedEvidence.derivations) ||
        !Array.isArray(suppliedEvidence.orderings) ||
        !Array.isArray(suppliedEvidence.retentions) ||
        !Array.isArray(suppliedEvidence.durableBindings) ||
        suppliedEvidence.durableBindings.length === 0) {
      fail('InvalidPublicationCommitEvidence');
    }
    const evidenceContracts = [
      suppliedEvidence.runDefinition,
      suppliedEvidence.invocation,
      ...suppliedEvidence.definitions,
      ...suppliedEvidence.artifacts,
      ...suppliedEvidence.derivations,
      ...suppliedEvidence.orderings,
      ...suppliedEvidence.retentions,
      ...suppliedEvidence.durableBindings,
      suppliedEvidence.manifest,
      suppliedEvidence.receipt,
      suppliedEvidence.capturedRun,
    ];
    for (const contract of evidenceContracts) {
      if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
          typeof contract.name !== 'string' ||
          typeof contract.identityField !== 'string' ||
          !cidPattern.test(contract.identity) ||
          typeof contract.wire !== 'string' ||
          required !== undefined && !required.has(contract.identity)) {
        fail('InvalidPublicationCommitEvidence');
      }
      const persisted = (await readOriginal(contract.identity,
        nativeContractRead(contract.name), contract)).bytes;
      if (!persisted.equals(Buffer.from(contract.wire, 'utf8'))) {
        fail('PublicationCommitEvidenceMismatch');
      }
    }
    const verifiedBindings = [];
    for (const contract of suppliedEvidence.durableBindings) {
      verifiedBindings.push(await verifyDurableResultBinding(contract, readOriginal));
    }
    const attemptStored = await readContract(
      entry.publication_attempt_cid, 'publication_attempt', readOriginal,
    );
    const attempt = attemptStored.value;
    const requestStored = await readContract(
      entry.publication_request_cid, 'publication_request', readOriginal,
    );
    if (attempt.publication_request_cid !== entry.publication_request_cid ||
        attempt.run_definition_cid !== entry.run_definition_cid) {
      fail('PublicationAttemptMismatch');
    }
    let chainValid = false;
    // Same semantic-read custody as native inspection: close cannot release
    // this Store while its owned checker is suspended between quanta.
    const validationReader = {cleanup: undefined};
    activeSemanticReaders.add(validationReader);
    try {
      active();
      chainValid = await contractControl.effectFreeStoredCommitValid(
        suppliedEvidence.runDefinition,
        suppliedEvidence.invocation,
        suppliedEvidence.definitions,
        suppliedEvidence.artifacts,
        suppliedEvidence.derivations,
        suppliedEvidence.orderings,
        suppliedEvidence.retentions,
        suppliedEvidence.durableBindings,
        suppliedEvidence.manifest,
        suppliedEvidence.receipt,
        suppliedEvidence.capturedRun,
        requestStored.contract,
        attemptStored.contract,
        admitted,
        active,
      );
    } catch (error) {
      fail('InvalidPublicationCommitChain', error);
    } finally {
      // The fixed control cancels its exact checker before this promise unwinds.
      activeSemanticReaders.delete(validationReader);
    }
    if (chainValid !== true) fail('InvalidPublicationCommitChain');
    return Object.freeze(verifiedBindings);
  };

  const validateCommittedEvidence = async (
    suppliedIndex,
    suppliedEvidence,
  ) => {
    active();
    if (!exactKeys(suppliedIndex, [
      'name', 'identityField', 'identity', 'wire',
    ]) || suppliedIndex.name !== 'public_index_entry') {
      fail('InvalidCommittedPublicationIndex');
    }
    const admitted = admitContract('public_index_entry', suppliedIndex.wire);
    if (admitted.identity !== suppliedIndex.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const entry = parseContract(admitted);
    const key = {
      namespaceId: entry.namespace_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    };
    const committed = await confirmCommittedIndex(key);
    if (committed?.public_index_entry_cid !== admitted.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const verifiedBindings = await verifyCommitEvidence(
      admitted, entry, suppliedEvidence, undefined,
    );
    const expectedContent = await confirmCapturedContentHoldings(
      suppliedEvidence.capturedRun, suppliedEvidence.runDefinition);
    const inventory = await readCommittedMetadataInventory(committed);
    if (inventory?.physical_holding_cids.join('\0') !== expectedContent.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return true;
  };

  // This is stored-evidence inspection, not physical row-outcome admission
  // or publication commit. The portable control admits the final reference
  // chain; the Store confirms its public bodies and private physical holdings.
  // A caller cannot use this result as an apply or commit permit.
  const inspectEffectfulStoredEvidence = async ({index, chain, preview,
    receipts, privateBinding, effectSources, recoveryResources},
    readOriginal = (cid, includeNative) => readSemanticOriginal(cid, includeNative), retainedIndex) => {
    active();
    if (typeof contractControl.effectfulCommitValid !== 'function' ||
        typeof contractControl.effectPrivateEvidenceBinding !== 'function' ||
        typeof contractControl.capturedEffectSourceHoldingCid !== 'function' ||
        typeof contractControl.capturedEffectSourceArtifactCid !== 'function' ||
        typeof contractControl.capturedEffectSourceStoreAuthorityCid !==
          'function' ||
        !exactKeys(chain, [
          'runDefinition', 'invocation', 'definitions', 'artifacts',
          'derivations', 'orderings', 'retentions', 'durableBindings',
          'manifest', 'computationReceipt', 'capturedRun',
        ]) || !['definitions', 'artifacts', 'derivations', 'orderings',
          'retentions', 'durableBindings'].every(name =>
          Array.isArray(chain[name])) ||
        !exactKeys(receipts, ['setWire', 'memberWires', 'finalWire']) ||
        typeof receipts.setWire !== 'string' ||
        typeof receipts.finalWire !== 'string' ||
        !Array.isArray(receipts.memberWires) ||
        receipts.memberWires.some(wire => typeof wire !== 'string') ||
        !Array.isArray(effectSources) ||
        !exactKeys(privateBinding, [
          'name', 'semanticCid', 'holdingCid', 'wire',
        ])) {
      fail('InvalidEffectfulStoredEvidence');
    }
    if (retainedIndex !== undefined && retainedIndex.contract !== index) {
      fail('InvalidEffectfulStoredEvidence');
    }
    const admittedIndex = retainedIndex === undefined
      ? admitContract('public_index_entry', index?.wire) : retainedIndex.contract;
    if (admittedIndex.identity !== index?.identity) {
      fail('InvalidEffectfulStoredEvidence');
    }
    const entry = retainedIndex === undefined ? parseContract(admittedIndex) : retainedIndex.entry;
    const request = (await readContract(
      entry.publication_request_cid, 'publication_request', readOriginal,
    )).contract;
    const attempt = (await readContract(
      entry.publication_attempt_cid, 'publication_attempt', readOriginal,
    )).contract;
    const finalReceipt = admitContract('run_receipt', receipts.finalWire);
    const setReceipt = admitContract(
      'effect_set_apply_receipt', receipts.setWire,
    );
    const memberReceipts = receipts.memberWires.map(wire =>
      admitContract('effect_apply_receipt', wire));
    const publicContracts = [chain.runDefinition, chain.invocation,
      ...chain.definitions, ...chain.artifacts, ...chain.derivations,
      ...chain.orderings, ...chain.retentions, ...chain.durableBindings,
      chain.manifest, chain.computationReceipt, chain.capturedRun,
      finalReceipt, setReceipt, ...memberReceipts];
    for (const contract of publicContracts) {
      if (!exactKeys(contract, [
        'name', 'identityField', 'identity', 'wire',
      ]) || !cidPattern.test(contract.identity) ||
          !(await readOriginal(contract.identity,
            nativeContractRead(contract.name), contract)).bytes.equals(
            Buffer.from(contract.wire, 'utf8'))) {
        fail('EffectfulCommitEvidenceMismatch');
      }
    }
    const validCommit = recoveryResources === undefined
      ? contractControl.effectfulCommitValid(chain, preview, receipts, request, attempt, admittedIndex, contractLimits)
      : constructEffectfulPublication(recoveryResources, chain.capturedRun, contractControl,
        contractControl.effectfulCommitValid, [chain, preview, receipts, request, attempt, admittedIndex, contractLimits]);
    if (validCommit !== true) {
      fail('InvalidEffectfulCommitChain');
    }
    const expectedPrivate = contractControl.effectPrivateEvidenceBinding(
      preview, configuration.storeAuthorityCid,
    );
    if (Object.keys(privateBinding).some(key =>
      privateBinding[key] !== expectedPrivate[key]) ||
        await confirmPrivateEvidence(privateBinding) === undefined) {
      fail('EffectfulPrivateEvidenceUnavailable');
    }
    const context = parseContract(chain.capturedRun).effect_context;
    const expectedHoldings = Object.values(
      context?.effect_source_holding_cids ?? {},
    );
    if (new Set(expectedHoldings).size !== expectedHoldings.length ||
        effectSources.length !== expectedHoldings.length) {
      fail('InvalidEffectfulSourceInventory');
    }
    const seen = new Set();
    const sourceArtifactCids = [];
    const sourceSchemaCids = [];
    for (const source of effectSources) {
      const holdingCid = contractControl.capturedEffectSourceHoldingCid(source);
      const artifactCid = contractControl.capturedEffectSourceArtifactCid(source);
      if (seen.has(holdingCid) || !expectedHoldings.includes(holdingCid) ||
          contractControl.capturedEffectSourceStoreAuthorityCid(source) !==
            configuration.storeAuthorityCid) {
        fail('InvalidEffectfulSourceInventory');
      }
      seen.add(holdingCid);
      const holding = await inspectPhysicalHolding(holdingCid);
      if (holding?.namespace !== 'effect-source' ||
          holding.manifest_cid !== artifactCid) {
        fail('EffectfulSourceHoldingUnavailable');
      }
      const artifact = (await readContract(
        artifactCid, 'effect_source_artifact', readOriginal,
      )).value;
      await readOriginal(artifact.result_schema_cid, false);
      sourceArtifactCids.push(artifactCid);
      sourceSchemaCids.push(artifact.result_schema_cid);
      await commitPhysicalHolding(holding, []);
    }
    const verifiedBindings = [];
    for (const binding of chain.durableBindings) {
      verifiedBindings.push(await verifyDurableResultBinding(binding, readOriginal));
    }
    let captureHoldingCid;
    let captureRecordHoldingCid;
    let captureRecord;
    if (typeof contractControl.effectComputationCaptureHoldingCid ===
        'function') {
      const candidate = contractControl.effectComputationCaptureHoldingCid(
        chain.runDefinition, configuration.storeAuthorityCid,
      );
      const holding = await inspectPhysicalHolding(candidate);
      if (holding !== undefined) {
        const recordCid = contractControl.effectComputationRecordHoldingCid(
          chain.runDefinition, configuration.storeAuthorityCid);
        try {
          captureRecord = await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, recordCid,
            (_plaintext, read) => JSON.parse(read.releaseBytes()),
          );
        } catch (error) {
          fail('InvalidEffectfulCaptureRecord', error);
        }
        if (captureRecord?.captured_run !== chain.capturedRun.wire ||
            captureRecord?.run_definition !== chain.runDefinition.wire ||
            captureRecord?.store_authority_cid !== configuration.storeAuthorityCid) {
          fail('InvalidEffectfulCaptureRecord');
        }
        const expected = new Map();
        for (const binding of chain.durableBindings) {
          const body = parseContract(binding);
          const prior = expected.get(body.material_generation_cid);
          if (prior !== undefined && prior !== body.byte_count) {
            fail('InvalidEffectfulCaptureHolding');
          }
          expected.set(body.material_generation_cid, body.byte_count);
        }
        for (const binding of contractControl.capturedEffectDependencyPayloadBindings(
          chain.capturedRun, captureRecord.effect_dependency_payloads)) {
          const previous = expected.get(binding.physical_cid);
          if (previous !== undefined && previous !== binding.byte_count) {
            fail('InvalidEffectfulCaptureHolding');
          }
          expected.set(binding.physical_cid, binding.byte_count);
        }
        if (holding.namespace !== 'effect-capture' ||
            holding.manifest_cid !== chain.capturedRun.identity ||
            holding.objects.length !== expected.size ||
            holding.objects.some(object =>
              expected.get(object.cid) !== object.byte_count)) {
          fail('InvalidEffectfulCaptureHolding');
        }
        await commitPhysicalHolding(holding, []);
        captureHoldingCid = candidate;
      }
    }
    if (typeof contractControl.effectComputationRecordHoldingCid ===
        'function') {
      const candidate = contractControl.effectComputationRecordHoldingCid(
        chain.runDefinition, configuration.storeAuthorityCid,
      );
      const holding = await inspectPhysicalHolding(candidate);
      if (holding !== undefined) {
        if (holding.namespace !== 'publication-private' ||
            holding.manifest_cid !== chain.capturedRun.identity ||
            holding.objects.length !== 1) {
          fail('InvalidEffectfulCaptureRecord');
        }
        let record;
        try {
          record = captureRecord ?? await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, candidate,
            (_plaintext, read) => JSON.parse(read.releaseBytes()),
          );
        } catch (error) {
          fail('InvalidEffectfulCaptureRecord', error);
        }
        if (record?.captured_run !== chain.capturedRun.wire ||
            record?.run_definition !== chain.runDefinition.wire ||
            record?.store_authority_cid !== configuration.storeAuthorityCid) {
          fail('InvalidEffectfulCaptureRecord');
        }
        captureRecordHoldingCid = candidate;
      }
    }
    return Object.freeze({index: admittedIndex, finalReceipt,
      verifiedBindings: Object.freeze(verifiedBindings),
      privateHoldingCid: privateBinding.holdingCid,
      captureHoldingCid, captureRecordHoldingCid,
      effectSourceHoldingCids: Object.freeze([...seen]),
      publicContractCids: Object.freeze(publicContracts.map(contract =>
        contract.identity)),
      sourceArtifactCids: Object.freeze(sourceArtifactCids),
      sourceSchemaCids: Object.freeze(sourceSchemaCids)});
  };

  const commitIndexInternal = async (
    suppliedWire,
    requiredObjectCids,
    suppliedEvidence,
    effectfulEvidence,
    indexOriginal,
    preparedHandles = [],
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
    const entry = parseContract(admitted);
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
    const semanticOriginals = new Map();
    const readOriginal = (cid, includeNative = true, retained) => {
      if (!semanticOriginals.has(cid)) {
        semanticOriginals.set(cid, readSemanticOriginal(cid, includeNative, false, retained));
      }
      return semanticOriginals.get(cid);
    };
    let verifiedBindings;
    let physicalHoldingCids = [];
    if (effectfulEvidence === undefined) {
      verifiedBindings = await verifyCommitEvidence(
        admitted, entry, suppliedEvidence, required, readOriginal,
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
    const bindingSchemas = new Map();
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
    const ownRetention = async cid => {
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
    let inventoryOriginal;
    let nativeIndexPreparation;
    const adoptSchemas = async () => {
      await adoptPreparedSchemas(inventorySemanticCids, entry.run_definition_cid);
      deliveryIndex.retainPublicationInventoryFinish(inventoryOriginal);
    };
    return createPublicationCommitOwner({entry, admitted, key}, {
      confirm: confirmCommittedIndex,
      async sameContent(existing, candidate) {
        return contractControl.publicIndexSameCommittedContent(
          (await readContract(existing.public_index_entry_cid,
            'public_index_entry')).contract, candidate,
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
          const schemaCid = bindingSchemas.get(bindingCid) ?? (await readContract(
            bindingCid, 'durable_result_binding', readOriginal,
          )).value.result_schema_cid;
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
        const nativeAttempt = deliveryIndex.publicationAttempt(entry.publication_attempt_cid);
        let legacyIndexBody = false;
        try {await lstat(contractPath(admitted.identity)); legacyIndexBody = true;}
        catch (error) {if (error?.code !== 'ENOENT') throw error;}
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
          writeNativeIndexOriginal(deliveryIndex.commitNativePublicationIndex,
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
  const commitIndex = (suppliedWire, requiredObjectCids, suppliedEvidence, indexOriginal, preparedHandles = []) => {
    if (!Array.isArray(preparedHandles)) fail('InvalidPublicationPreparedOwner');
    const originalHandles = Object.freeze([...preparedHandles]);
    return withSemanticCommit(() => commitIndexInternal(
      suppliedWire, requiredObjectCids, suppliedEvidence, undefined, indexOriginal, originalHandles,
    ));
  };

  const commitEffectfulIndex = (preparation, requiredObjectCids) => {
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

  const validateCommittedEffectfulEvidence = async preparation => {
    active();
    const inspected = await inspectEffectfulStoredEvidence(preparation);
    const entry = parseContract(inspected.index);
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

  const consumeObject = createPublicationObjectConsumer(
    configuration, objectPath, cidHex, active, physicalContentReadWindowBytes,
  );

  const {withCommittedResult, consumeCommittedResult, withCommittedResultRows} =
    createCommittedResultReaders(activeResultReaders, {
      active, cidHex, consumeObject, readSemanticOriginal, verifyDurableResultBinding,
      requireCommittedResultBinding: (...args) => requireCommittedResultBinding(...args),
      requireResultNotDeleted: (...args) => requireResultNotDeleted(...args),
    });

  const {collectRunMetadataContracts, bindMetadataContractObjects, metadataResultBindings, removeRunMetadataDirectories} =
    createRunMetadataInventory(configuration, {attemptsDirectory, deliveriesDirectory, manifestReadsDirectory,
      retentionExtensionsDirectory}, recordNamePattern, deliveryStarts, contractControl, {
      currentDeliveryIndex, publicationAttemptPath, deliveryAttemptPath, contractPath, retentionExtensionDirectory,
      syncDirectory, verifyObject, admitContract, parseContract, readContract, readSemanticOriginal,
      readDeliveryAttemptContract, admitDeliveryClaim,
    });

  const {metadataContractHasLiveReference, metadataHoldingHasOtherOwner, reclaimMetadataContract, materialHasLiveReference} =
    createPublicationReferenceOwner(configuration, {metadataInventoriesDirectory, contractsDirectory, physicalHoldingsDirectory,
      indexesDirectory}, preparedSchemas, {
      currentDeliveryIndex, accountNativePublication, contractPath, objectPath, syncDirectory, rememberPhysicalRemoval,
      confirmPhysicalRemovals, withSemanticCommit, admitNativeIndexOriginal,
      readResultDeletion: (...args) => readResultDeletion(...args), admitContract, parseContract, readContract,
      readMetadataInventory, publicationRecoveryValue, readMetadataDeletion, readPhysicalHoldingAt,
    });

  const verifyPhysicalHoldingObjects = createPhysicalHoldingObjectVerifier(verifyObject);

  const {inspectPhysicalHolding, inspectPhysicalHoldingForRetirement,
    retainPhysicalHoldingReader, consumeSelectedPhysicalHolding, consumePhysicalHolding} =
    createPhysicalHoldingReaders(active, cidHex, readPhysicalHolding, readPhysicalHoldingDeletion,
      verifyPhysicalHoldingObjects, activePhysicalHoldingReaders, consumeObject);

  const materialRetentionCurrent = () => materialRetentionBusy;
  const retainMaterialOperation = operation => { materialRetentionBusy = operation; };

  const {commitPhysicalHolding, sharePhysicalHolding, confirmPhysicalHoldingDirectory,
    retirePhysicalHolding, recoverPhysicalHoldingDeletions} =
    createPhysicalHoldingLifecycle(configuration, physicalHoldingsDirectory, physicalHoldingDeletionsDirectory, {
      active, cidHex, admitPhysicalHolding, readPhysicalHoldingAt, readPhysicalHolding, readPhysicalHoldingDeletion,
      verifyPhysicalHoldingObjects, preparedObjectOwners, preparedObjects, confirmPreparedMaterials, adoptPreparedObjects,
      writePhysicalHoldingRecord, physicalHoldingPath, physicalHoldingDeletionPath, objectPath, syncDirectory,
      activePhysicalRecordWriters, activePhysicalHoldingReaders, retainPhysicalHoldingReader, pendingPhysicalHoldingDeletions,
      materialRetentionCurrent, retainMaterialOperation, materialHasLiveReference, rememberPhysicalRemoval,
      confirmPhysicalRemovals,
    });

  const {privateEvidenceKey, readPrivateEvidence,
    preparePrivateEvidence, prepareModelRawEvidence, prepareLookupRawEvidence,
    readModelRawEvidence, confirmModelRawEvidence, readLookupRawEvidence, confirmLookupRawEvidence,
    confirmModelRawCaptureOriginals, confirmPrivateEvidence} =
    createPrivatePublicationEvidence(configuration, localContinuationEvidenceNames, {
      active, cidHex, readPhysicalHolding, readPhysicalHoldingDeletion, consumeSelectedPhysicalHolding,
      retainPhysicalHoldingReader, confirmPhysicalHoldingDirectory, materialRetentionCurrent, retainMaterialOperation,
      createPreparedObjectWriter, exactUtf8WireMatches, readSemanticBytes,
    });

  const {readEffectCaptureCustody, retainEffectCaptureCustody, listEffectCaptureCustodies,
    forgetEffectCaptureCustody, retireEffectCaptureCustody, clearEffectCaptureCustodyObservation} =
    createEffectCaptureCustodyRecords(configuration, captureCustodyDirectory, stagingDirectory, {
      active, admitContract, cidHex, parsePhysicalHolding, withSemanticCommit, syncDirectory,
      readPhysicalHolding, readPhysicalHoldingDeletion, retirePhysicalHolding,
    });

  const {registerCustody, removeCustodyRecord, reclaimCustody, reclaimNativePreparation, recoverPreparedCustodies} =
    createPublicationCustodyRecords(
      configuration, custodyDirectory, objectsDirectory, contractsDirectory, custodyNamePattern, reclaimableCustodies,
      {
        custodyPath, objectPath, contractPath, currentDeliveryIndex,
        materialRetentionCurrent, retainMaterialOperation,
        syncDirectory, writePhysicalHoldingRecord, physicalOriginal, confirmPhysicalCapacity,
        confirmPhysicalRemovals, rememberPhysicalRemoval, materialHasLiveReference, verifyObject,
      },
    );

  const {adoptPreparedSchemas, putPreparedResultSchema, recoverPreparedSchemas} = createPreparedSchemaOwner(
    configuration, preparedSchemasDirectory, contractsDirectory, objectsDirectory, custodyNamePattern,
    preparedSchemas, preparedObjects, reclaimableCustodies, activePhysicalRecordWriters,
    {active, cidHex, contractPath, objectPath, preparedSchemaPath, syncDirectory,
      withSemanticCommit, currentDeliveryIndex, confirmPhysicalRemovals, rememberPhysicalRemoval,
      metadataContractHasLiveReference, materialHasLiveReference, putSemantic, readSemanticOriginal,
      exactUtf8WireMatches},
  );

  const metadataRetentionCurrent = () => metadataRetentionBusy;
  const retainMetadataOperation = operation => { metadataRetentionBusy = operation; };
  const {retireUncommittedPublication, recoverUncommittedPublications} =
    createUncommittedPublicationCleanup(metadataInventoriesDirectory, pendingUncommittedMetadataCleanups, {
      active, cidHex, currentDeliveryIndex, publicationRecoveryOriginal, publicationRecoveryValue,
      readMetadataInventory, recoverMetadataInventory, restoreMetadataInventory, metadataInventoryPath, syncDirectory,
      inspectCommittedIndexRaw, confirmCommittedIndex, latestRecord, readMetadataDeletion, metadataHoldingHasOtherOwner,
      readPhysicalHolding, readPhysicalHoldingDeletion, reclaimMetadataContract, confirmPhysicalRemovals,
      metadataRetentionCurrent, retainMetadataOperation,
    });

  const {requireCommittedResultBinding, requireResultNotDeleted,
    readCommittedResultRetentionExtension, readCommittedResultDescriptionEvidence, putCommittedResultRetentionExtension} =
    createPublicationResultMetadata(configuration, retentionExtensionsDirectory, recordNamePattern, timestampPattern,
      selectedPublicationReads, {
        active, cidHex, confirmSelectedCommittedIndex, runMetadataDeletionStarted,
        readResultDeletion: (...args) => readResultDeletion(...args),
        readContract, readSemanticOriginal, readSemanticBytes, retentionExtensionDirectory, retentionExtensionResultDirectory,
        syncDirectory, putPublicationContract, materialRetentionCurrent, retainMaterialOperation,
      });

  const {readResultDeletion, createResultDeletionCleanup, retireCommittedResult, recoverRetiredResults} =
    createResultRetirement(configuration, deletionsDirectory, indexesDirectory, {
      active, cidHex, currentDeliveryIndex, resultDeletionDirectory, resultDeletionPath,
      readOpeningDirectory, readMetadataDeletion, admitNativeIndexOriginal, admitContract, parseContract,
      readContract, requireCommittedResultBinding, syncDirectory, materialRetentionCurrent, retainMaterialOperation,
      activeResultReaders, preparedObjects, pendingResultDeletions, reclaimingMaterialCids, materialHasLiveReference,
      objectPath, rememberPhysicalRemoval, syncPhysicalRemovals, releasePhysicalCapacity,
    });

  const {retireCommittedPublicationMetadata, recoverRetiredMetadata} =
    createPublicationMetadataRetirement(configuration, indexesDirectory, deletionsDirectory, metadataInventoriesDirectory,
      metadataDeletionsDirectory, timestampPattern, {
        active, currentDeliveryIndex, pendingMetadataDeletions, pendingMetadataDeletionMarkers,
        pendingMetadataFenceCompletions, metadataDeletionIntents, metadataRetentionCurrent, retainMetadataOperation,
        publicationRecoveryValue, syncPhysicalRemovals, releasePhysicalCapacity, createResultDeletionCleanup,
        metadataHoldingHasOtherOwner, retirePhysicalHolding, removeRunMetadataDirectories, admitContract, syncDirectory,
        durablyConfirmedIndexes, reclaimMetadataContract, resultDeletionDirectory, metadataInventoryPath, compactMetadataDeletion,
        readMetadataDeletion, inspectCommittedIndexRaw, readMetadataInventory, collectRunMetadataContracts, ensureMetadataDeletion,
        metadataResultBindings, bindMetadataContractObjects,
      });

  // Immutable holding bodies are admitted at their selected read. Pending
  // deletion recovery below still owns its exact records and original ACKs;
  // unrelated history is not another ordinary opening admission boundary.
  // Recover process-crash custody before accepting new Store work. A
  // committed or shared allocation survives; an unpublished allocation is
  // reclaimed using its exact recorded generation.
  // Native publication bodies and their persisted capacity are available to
  // the same targeted recovery/retirement paths as legacy file originals.
  await initializeDeliveryIndex();
  const physicalPreparations = deliveryIndex.pendingPhysicalObjects();
  for (const original of physicalPreparations) await reclaimNativePreparation(original);
  if(storedBytes>configuration.capacityBytes||objectCount>configuration.maxObjects) {
    fail('PublicationStoreCapacity');
  }
  await recoverPreparedCustodies();
  await recoverPreparedSchemas();
  // A crash between semantic alias creation and physical-custody handoff
  // leaves both records. Revisit physical custody after alias reclamation.
  await recoverPreparedCustodies();

  // A retiring Transfer holding is unavailable before physical reclamation.
  // Recovery resumes the exact durable cleanup without treating an absent
  // object name as proof that another live holding was released.
  await recoverPhysicalHoldingDeletions();

  // A terminal attempt that never won the public index retains an exact
  // inventory until every unshared metadata allocation is durably reclaimed.
  // Live and outcome-unknown attempts remain available for legal retry.
  await recoverUncommittedPublications();

  // Reconcile durable deletion markers before accepting new Store work. A
  // failed physical cleanup remains owned by the returned Store and can be
  // retried without making the deleted Result visible again.
  await recoverRetiredResults();

  // Metadata deletion markers hide the public index before physical cleanup.
  // Restart resumes every exact contract and payload responsibility recorded
  // by the marker rather than treating an absent index as successful cleanup.
  await recoverRetiredMetadata();

  const storageBindings = createOriginalStoreStorageBindings(
    configuration, storeContractPath, storeContractBytes, contractControl, active, privateEvidenceKey,
  );

  // Qualification follows Store startup, before this Store can reach
  // any physical start. Fresh-format failures never leave a lease-only prefix.
  await (prepared?.ownership ?? ownership).qualifyExecutionOwner();
  if (prepared !== undefined) prepared.recoveryReady = true;
  return Object.freeze({
    storeAuthorityCid: configuration.storeAuthorityCid,
    observeOriginalInstallationPublicationStorageBinding: storageBindings.observeOriginalInstallationPublicationStorageBinding,
    originalInstallationPublicationStorageBindingEvidence: storageBindings.originalInstallationPublicationStorageBindingEvidence,
    observeOriginalModelStorageBinding: storageBindings.observeOriginalModelStorageBinding,
    originalModelStorageBindingEvidence: storageBindings.originalModelStorageBindingEvidence,
    createObjectWriter,
    createPreparedObjectWriter,
    commitPhysicalHolding,
    sharePhysicalHolding,
    inspectPhysicalHolding,
    inspectPhysicalHoldingForRetirement,
    consumePhysicalHolding,
    retirePhysicalHolding,
    retainEffectCaptureCustody,
    readEffectCaptureCustody,
    listEffectCaptureCustodies,
    retireEffectCaptureCustody,
    forgetEffectCaptureCustody,
    recoverPhysicalHoldingDeletions,
    putBytes,
    putSemantic,
    preparePrivateEvidence,
    // Read-only projection of this SAME immutable Store configuration. A
    // caller must still fund export/tree/String/encoding workspace BEFORE
    // allocation and retain its original reservation through actual ACK.
    // No write, grant, reservation, persistence or cleanup is issued here.
    privateEvidenceWireLimit() {
      active();
      return privateEvidenceWireLimitForObject(configuration.maxObjectBytes);
    },
    originalModelStorageDimensions: storageBindings.originalModelStorageDimensions,
    confirmPrivateEvidence,
    prepareModelRawEvidence,
    readModelRawEvidence,
    confirmModelRawEvidence,
    prepareLookupRawEvidence,
    readLookupRawEvidence,
    confirmLookupRawEvidence,
    confirmModelRawCaptureOriginals,
    confirmCapturedContentHoldings,
    putPreparedResultSchema,
    putPublicationContract,
    putPublicationContracts,
    putOriginalPublicationContracts,
    verifyObject,
    observeTrustedClock: trustedClock.observeTrustedClock,
    sampleTrustedClock: trustedClock.sampleTrustedClock,
    readClockObservation: trustedClock.readClockObservation,
    readSemanticBytes,
    readPrivateEvidence,
    consumeObject,
    withCommittedResult,
    withCommittedResultRows,
    consumeCommittedResult,
    readCommittedResultRetentionExtension,
    readCommittedResultDescriptionEvidence,
    putCommittedResultRetentionExtension,
    retireCommittedResult,
    retireCommittedPublicationMetadata,
    recoverPreparedCustodies,
    recoverPreparedSchemas,
    retireUncommittedPublication,
    recoverUncommittedPublications,
    recoverRetiredResults,
    recoverRetiredMetadata,
    readJsonObject,
    async readPublicationContract(cid, name, readDemand) {
      active();
      if (typeof name !== 'string' || name.length === 0) {
        fail('InvalidPublicationContractName');
      }
      return (await readContract(cid, name,
        (semanticCid, includeNative) => readSemanticOriginal(semanticCid, includeNative, false, undefined, readDemand))).contract;
    },
    createAttempt,
    beginPublicationAttempt,
    beginPublicationAttemptWithRecords,
    latestRecord,
    latestRecordContract,
    appendRecord,
    appendInitialPublicationRecords,
    consumeManifestReadGrant,
    createDeliveryAttempt,
    beginDeliveryAttempt,
    lookupDeliveryAttempt,
    latestDeliveryRecord,
    latestDeliveryRecordContract,
    confirmDeliveryRecord,
    appendDeliveryRecord,
    appendDeliveryCompletion,
    commitIndex,
    commitEffectfulIndex,
    validateCommittedEvidence,
    validateCommittedEffectfulEvidence,
    inspectEffectfulStoredEvidence(preparation, readOriginal) {
      return inspectEffectfulStoredEvidence(preparation, readOriginal);
    },
    inspectCommittedIndex,
    confirmCommittedIndex: confirmSelectedCommittedIndex,
    readCommittedPublication,
    lookupCommittedIndex,
    publicationCapacitySupports(requirement) {
      active();
      if (!exactKeys(requirement, [
        'requiredBytes', 'objectCount', 'maxObjectBytes',
      ]) || !quantity(requirement.requiredBytes) ||
          !quantity(requirement.objectCount) ||
          !quantity(requirement.maxObjectBytes)) {
        fail('InvalidPublicationCapacityRequirement');
      }
      return requirement.maxObjectBytes <= configuration.maxObjectBytes &&
        storedBytes + reservedBytes + requirement.requiredBytes <=
          configuration.capacityBytes &&
        objectCount + reservedObjects + requirement.objectCount <=
          configuration.maxObjects;
    },
    status() {
      return Object.freeze({
        storedBytes,
        reservedBytes,
        objectCount,
        reservedObjects,
        capacityBytes: configuration.capacityBytes,
        closed,
      });
    },
    close() {
      if (closeFlight !== undefined) return closeFlight;
      if (closed) return Promise.resolve(true);
      // Snapshot only closed resource counts at the original refusal. These
      // diagnostics neither acknowledge cleanup nor observe/retry an owner.
      const cleanupPendingFailure = cause => Object.assign(
        new PublicationStoreError('PublicationStoreCleanupPending', cause), {
          cleanupDiagnostic: Object.freeze({kind: 'publication-store-close',
            resources: Object.freeze({
              physicalRemovalOriginals: physicalRemovalOriginals.size,
              physicalRemovalAcquisitions: physicalRemovalAcquisitions.size,
              clockObservations: trustedClock.clockObservationsPending,
              reservedObjects: reservedObjects,
              preparedObjects: preparedObjects.size,
              preparedSchemas: preparedSchemas.size,
              reclaimableCustodies: reclaimableCustodies.size,
              resultDeletions: pendingResultDeletions.size,
              metadataDeletions: pendingMetadataDeletions.size,
              uncommittedMetadataCleanups: pendingUncommittedMetadataCleanups.size,
              physicalHoldingDeletions: pendingPhysicalHoldingDeletions.size,
              resultReaders: activeResultReaders.size,
              physicalHoldingReaders: activePhysicalHoldingReaders.size,
              modelStorageBindingReaders: storageBindings.modelStorageBindingReaders,
              installationPublicationStorageBindingReaders: storageBindings.installationPublicationStorageBindingReaders,
              semanticReaders: activeSemanticReaders.size,
              physicalRecordWriters: activePhysicalRecordWriters.size,
            }),
          }),
        });
      closeFlight = Promise.resolve().then(async () => {
        // A failed native writer retains its capacity until its SAME mutation
        // receives a real confirmation. Drain that original before treating its
        // reservation as an independent live user. Healthy in-flight writers
        // and every other unfinished owner still keep the existing close fence.
        const retriedWriters = new Set();
        for (const writer of activePhysicalRecordWriters) {
          if (!writer.failed || writer.cleanup === undefined) continue;
          retriedWriters.add(writer);
          try { await writer.cleanup.retry(); }
          catch (cause) { throw cleanupPendingFailure(cause); }
        }
        if (physicalRemovalOriginals.size !== 0 || physicalRemovalAcquisitions.size !== 0 ||
            trustedClock.clockObservationsPending !== 0 || reservedObjects !== 0 || preparedObjects.size !== 0 ||
            preparedSchemas.size !== 0 ||
            reclaimableCustodies.size !== 0 ||
            pendingResultDeletions.size !== 0 ||
            pendingMetadataDeletions.size !== 0 ||
            pendingUncommittedMetadataCleanups.size !== 0 ||
            pendingPhysicalHoldingDeletions.size !== 0 ||
            activeResultReaders.size !== 0 ||
            activePhysicalHoldingReaders.size !== 0 ||
            storageBindings.modelStorageBindingReaders !== 0 ||
            storageBindings.installationPublicationStorageBindingReaders !== 0) {
          throw cleanupPendingFailure();
        }
        // An unsettled read still owns its FD; close must not interrupt it.
        for (const reader of activeSemanticReaders) {
          if (reader.cleanup === undefined) {
            throw cleanupPendingFailure();
          }
        }
        for (const writer of activePhysicalRecordWriters) {
          if (writer.cleanup === undefined) {
            throw cleanupPendingFailure();
          }
        }
        // Refuse new Store work once retirement starts, but do not report closed
        // or erase the original key until the SAME ownership confirms release.
        // A redacted control-read error cannot drive private cleanup. The same
        // Store retains that original duty and drains close only, never read/send.
        closeRequested = true;
        for (const reader of activeSemanticReaders) {
          try { await reader.cleanup.retry(); }
          catch { throw cleanupPendingFailure(); }
        }
        if (activeSemanticReaders.size !== 0) throw cleanupPendingFailure();
        for (const writer of activePhysicalRecordWriters) {
          if (retriedWriters.has(writer)) continue;
          try { await writer.cleanup.retry(); }
          catch { throw cleanupPendingFailure(); }
        }
        if (activePhysicalRecordWriters.size !== 0) throw cleanupPendingFailure();
        deliveryIndex.retainResultDeletionSeal();
        if (deliveryIndex?.close() !== true) throw cleanupPendingFailure();
        return ownership.release();
      }).then(released => {
        if (released !== true) fail('PublicationStoreOwnershipLost');
        closed = true;
        configuration.privateEvidenceKey?.fill(0);
        storageBindings.clearInstallationPublicationStorageBinding();
        clearEffectCaptureCustodyObservation();
        return true;
      }).finally(() => { closeFlight = undefined; });
      return closeFlight;
    },
  });
  } catch (cause) {
    const primary = deliveryIndex === undefined ? cause : deliveryIndex.retainFailure(cause);
    throw await retainStoreOpeningFailure(primary, ownership,
      configuration.privateEvidenceKey);
  }
}
