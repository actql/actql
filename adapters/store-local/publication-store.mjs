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
import {createPublicationPhysicalAccounting} from './publication-physical-accounting.mjs';
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
import {readOpeningStoreInventory, recoverPublicationStoreOnOpen, storeBootstrapAcquisition} from './publication-store-bootstrap.mjs';
import {acquireStoreOwnership} from './publication-store-ownership.mjs';
import {beginPreparedStoreAdoption, releasePreparedOwnership, retainPreparedStoreAdoptionFailure}
  from './prepared-publication-store-ownership.mjs';
import {indexKey, validateConfiguration, validateContractControl} from './publication-store-inputs.mjs';
import {admitExistingStoreFormat, createOriginalStoreStorageBindings, createStoreContract} from './publication-store-format.mjs';
import {createPrivatePublicationEvidence} from './publication-store-private-evidence.mjs';
import {createPublicationStoreInterface} from './publication-store-interface.mjs';

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

  let assertPriorPhysicalUnborrowed = () => fail('PublicationStoreCleanupPending');
  const currentDeliveryIndex = () => deliveryIndex;
  const {capacityUsage, unconfirmedPhysicalInstalls, physicalRemovalOriginals, physicalRemovalAcquisitions,
    physicalRetirementFences, physicalOriginal, accountPhysicalUsage, accountPhysicalInstall,
    settlePhysicalInstalls, confirmPhysicalCapacity, rememberPhysicalRemoval, releasePhysicalCapacity,
    syncPhysicalRemovals, confirmPhysicalRemovals, accountNativePublication} =
    createPublicationPhysicalAccounting(objectsDirectory, syncDirectory, currentDeliveryIndex,
      (...args) => assertPriorPhysicalUnborrowed(...args));

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
  const openingMetadataDeletionNames = await readOpeningStoreInventory({
    stagingDirectory, custodyDirectory, preparedSchemasDirectory, metadataDeletionsDirectory,
    physicalHoldingDeletionsDirectory, clocksDirectory,
  }, custodyNamePattern, readOpeningDirectory, syncDirectory);

  let reservedBytes = 0;
  let reservedObjects = 0;
  const lifecycleState = {closed: false, closeRequested: false, closeFlight: undefined};
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
    if (lifecycleState.closed || lifecycleState.closeRequested) fail('PublicationStoreClosed');
  };

  const {parsePhysicalHolding, readPhysicalHoldingAt, admitPhysicalHolding} =
    createPhysicalHoldingRecordReader(configuration, physicalHoldingNamespaces);

  const readPhysicalHolding = (holdingCid, readDemand) =>
    readPhysicalHoldingAt(physicalHoldingPath(holdingCid), holdingCid, readDemand);

  const readPhysicalHoldingDeletion = (holdingCid, readDemand) =>
    readPhysicalHoldingAt(physicalHoldingDeletionPath(holdingCid), holdingCid, readDemand);

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
    get storedBytes() {return capacityUsage.storedBytes;},
    get objectCount() {return capacityUsage.objectCount;},
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

  await recoverPublicationStoreOnOpen(configuration, capacityUsage, {
    initializeDeliveryIndex, currentDeliveryIndex, reclaimNativePreparation, recoverPreparedCustodies,
    recoverPreparedSchemas, recoverPhysicalHoldingDeletions, recoverUncommittedPublications, recoverRetiredResults,
    recoverRetiredMetadata,
  });

  const storageBindings = createOriginalStoreStorageBindings(
    configuration, storeContractPath, storeContractBytes, contractControl, active, privateEvidenceKey,
  );

  // Qualification follows Store startup, before this Store can reach
  // any physical start. Fresh-format failures never leave a lease-only prefix.
  await (prepared?.ownership ?? ownership).qualifyExecutionOwner();
  if (prepared !== undefined) prepared.recoveryReady = true;
  const {privateEvidenceWireLimit, readPublicationContract, inspectEffectfulStoredEvidence: inspectStoredEffectEvidence,
    publicationCapacitySupports, status, close} = createPublicationStoreInterface(
    configuration, lifecycleState, writeState, trustedClock, storageBindings, ownership, {
      physicalRemovalOriginals, physicalRemovalAcquisitions, preparedObjects, preparedSchemas, reclaimableCustodies,
      pendingResultDeletions, pendingMetadataDeletions, pendingUncommittedMetadataCleanups, pendingPhysicalHoldingDeletions,
      activeResultReaders, activePhysicalHoldingReaders, activeSemanticReaders, activePhysicalRecordWriters,
    }, {active, currentDeliveryIndex, clearEffectCaptureCustodyObservation, readContract, readSemanticOriginal,
      inspectEffectfulStoredEvidence},
  );
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
    privateEvidenceWireLimit,
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
    readPublicationContract,
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
    inspectEffectfulStoredEvidence: inspectStoredEffectEvidence,
    inspectCommittedIndex,
    confirmCommittedIndex: confirmSelectedCommittedIndex,
    readCommittedPublication,
    lookupCommittedIndex,
    publicationCapacitySupports,
    status,
    close,
  });
  } catch (cause) {
    const primary = deliveryIndex === undefined ? cause : deliveryIndex.retainFailure(cause);
    throw await retainStoreOpeningFailure(primary, ownership,
      configuration.privateEvidenceKey);
  }
}
