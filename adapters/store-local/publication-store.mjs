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
import {createPublicationSemanticWrites} from './publication-semantic-writes.mjs';
import {createPublicationIndexStartup} from './publication-index-startup.mjs';
import {createPublicationEvidence} from './publication-evidence-inspection.mjs';
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
import {createPublicationIndexCommit} from './publication-index-commit.mjs';
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

  const {putSemanticBatch, putSemantic} = createPublicationSemanticWrites(
    configuration, {stagingDirectory, objectsDirectory, contractsDirectory}, activePhysicalRecordWriters,
    reclaimingMaterialCids, physicalRetirementFences, {
      active, cidHex, currentDeliveryIndex, objectPath, contractPath, physicalOriginal, accountPhysicalInstall,
      settlePhysicalInstalls, confirmPhysicalCapacity, syncDirectory, reserveObjectCapacity, verifyObject, exactUtf8WireMatches,
      publicationRecoveryValue, reclaimNativePreparation: (...args) => reclaimNativePreparation(...args),
    },
  );

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

  const initializeDeliveryIndex = createPublicationIndexStartup(
    configuration, {root, deliveryCoveragePath, deliveryIndexPath, stagingDirectory, objectsDirectory, deliveriesDirectory,
      metadataInventoriesDirectory, metadataDeletionsDirectory}, createdStore, {
      get deliveryIndex() {return deliveryIndex;},
      set deliveryIndex(index) {deliveryIndex = index;},
      set metadataFencesReady(ready) {metadataFencesReady = ready;},
    }, writeState, metadataDeletionIntents, openingMetadataDeletionNames, {
      openDeliveryAttemptIndex, bootstrap, readOpeningDirectory, writePhysicalHoldingRecord,
      syncDirectory, physicalOriginal, accountPhysicalUsage, accountNativePublication,
      confirmCommittedIndex: (...args) => confirmCommittedIndex(...args), metadataDeletionPath,
      readFileDeliveryAttemptContract, deliveryIndexRow, restoreDeliveryClaim, parseContract, readSemanticOriginal, readContract,
      readMetadataInventory, publicationRecoveryOriginal, readMetadataDeletion, runMetadataDeletionStarted,
    },
  );

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
  const {confirmCapturedContentHoldings, verifyCommitEvidence, validateCommittedEvidence, inspectEffectfulStoredEvidence} =
    createPublicationEvidence(configuration, contractControl, contractLimits, activeSemanticReaders, {
      active, admitContract, parseContract, readContract, readSemanticOriginal, nativeContractRead,
      verifyDurableResultBinding, confirmCommittedIndex, readCommittedMetadataInventory,
      inspectPhysicalHolding: (...args) => inspectPhysicalHolding(...args),
      commitPhysicalHolding: (...args) => commitPhysicalHolding(...args),
      confirmPrivateEvidence: (...args) => confirmPrivateEvidence(...args),
      readPrivateEvidence: (...args) => readPrivateEvidence(...args),
    });

  const {commitIndex, commitEffectfulIndex, validateCommittedEffectfulEvidence} =
    createPublicationIndexCommit(configuration, indexesDirectory, contractControl, preparedObjectOwners,
      durablyConfirmedIndexes, {
        active, currentDeliveryIndex, contractPath, syncDirectory, confirmCommittedIndex,
        readResultDeletion: (...args) => readResultDeletion(...args),
        reserveObjectCapacity, accountNativePublication, withSemanticCommit,
        admitOriginalContract, parseContract, readContract, readSemanticOriginal, latestRecordContract, readMetadataDeletion,
        readCommittedMetadataInventory, publicationRecoveryOriginal, ensureMetadataInventory,
        bindMetadataContractObjects: (...args) => bindMetadataContractObjects(...args),
        adoptPreparedSchemas: (...args) => adoptPreparedSchemas(...args),
        beginPreparedCommit, confirmPreparedMaterials, adoptPreparedObjects,
        verifyCommitEvidence, inspectEffectfulStoredEvidence, confirmCapturedContentHoldings, putSemanticBatch,
        writeNativeIndexOriginal,
      });

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
