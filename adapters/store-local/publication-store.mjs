// Durable local publication storage. Prepared objects are content-addressed
// but remain invisible to ordinary Result lookup until an authority-scoped
// public index entry is installed with an exclusive atomic link.
import {
  constants,
} from 'node:fs';
import {
  lstat,
  link,
  mkdir,
  open,
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

const cidPattern = /^sha256:([0-9a-f]{64})$/u;
const recordNamePattern = /^(0|[1-9][0-9]*)\.json$/u;
const custodyNamePattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.json$/u;
const timestampPattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;

export class PublicationStoreError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

const fail = (code, cause) => {
  throw new PublicationStoreError(code, cause);
};
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const cidHex = value => {
  const match = typeof value === 'string' ? cidPattern.exec(value) : null;
  if (!match) fail('InvalidPublicationObjectCid');
  return match[1];
};
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

async function syncDirectoryPath(path) {
  const directory = await open(path, constants.O_RDONLY);
  try { await directory.sync(); }
  finally { await directory.close(); }
}

const localDurability = Object.freeze({syncDirectory: syncDirectoryPath});

async function writeExclusive(path, bytes) {
  const handle = await open(path, constants.O_CREAT | constants.O_EXCL |
    constants.O_WRONLY, 0o600);
  try {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const {bytesWritten} = await handle.write(
        bytes, offset, bytes.byteLength - offset, offset,
      );
      if (bytesWritten === 0) fail('IncompletePublicationWrite');
      offset += bytesWritten;
    }
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function readBounded(path, maximum) {
  const state = await lstat(path);
  if (!state.isFile() || state.size > maximum) {
    fail('InvalidPublicationStoreObject');
  }
  return readFile(path);
}

async function processIsAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid < 1) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') return false;
    if (error?.code === 'EPERM') return true;
    throw error;
  }
}

async function acquireStoreOwnership(root) {
  const ownershipDirectory = resolve(root, 'owner');
  const ownerPath = resolve(ownershipDirectory, 'owner.json');
  const token = randomUUID();
  while (true) {
    try {
      await mkdir(ownershipDirectory, {mode: 0o700});
      const owner = Buffer.from(JSON.stringify({
        version: 'actql-local-publication-store-owner/0.1',
        pid: process.pid,
        token,
      }), 'utf8');
      await writeFile(ownerPath, owner, {flag: 'wx', mode: 0o600});
      await syncDirectoryPath(ownershipDirectory);
      await syncDirectoryPath(root);
      let released = false;
      return Object.freeze({
        async release() {
          if (released) return false;
          let existing;
          try { existing = JSON.parse(await readFile(ownerPath, 'utf8')); }
          catch (error) {
            if (error?.code === 'ENOENT') return false;
            throw error;
          }
          if (existing?.token !== token || existing?.pid !== process.pid) {
            fail('PublicationStoreOwnershipLost');
          }
          await unlink(ownerPath);
          await rmdir(ownershipDirectory);
          await syncDirectoryPath(root);
          released = true;
          return true;
        },
      });
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      let existing;
      try { existing = JSON.parse(await readFile(ownerPath, 'utf8')); }
      catch (readError) {
        if (readError?.code === 'ENOENT') {
          fail('PublicationStoreBusy');
        }
        fail('InvalidPublicationStoreOwner', readError);
      }
      if (existing?.version !== 'actql-local-publication-store-owner/0.1' ||
          typeof existing.token !== 'string' ||
          !Number.isSafeInteger(existing.pid) || existing.pid < 1) {
        fail('InvalidPublicationStoreOwner');
      }
      if (await processIsAlive(existing.pid)) fail('PublicationStoreBusy');
      const stale = resolve(root, `stale-owner-${randomUUID()}`);
      try { await rename(ownershipDirectory, stale); }
      catch (renameError) {
        if (renameError?.code === 'ENOENT') continue;
        throw renameError;
      }
      await rm(stale, {recursive: true, force: false});
      await syncDirectoryPath(root);
    }
  }
}

function validateConfiguration(options) {
  const fields = [
    'directory',
    'storeAuthorityCid',
    'capacityBytes',
    'maxObjectBytes',
    'maxObjects',
    'maxContractNodes',
    'maxContractDepth',
  ];
  if ((!exactKeys(options, fields) &&
      !exactKeys(options, [...fields, 'privateEvidenceKey'])) ||
      options.privateEvidenceKey !== undefined &&
        (!(options.privateEvidenceKey instanceof Uint8Array) ||
          options.privateEvidenceKey.byteLength !== 32) ||
      typeof options.directory !== 'string' ||
      options.directory.length === 0 ||
      !cidPattern.test(options.storeAuthorityCid) ||
      !quantity(options.capacityBytes) ||
      !quantity(options.maxObjectBytes) || options.maxObjectBytes === 0 ||
      !quantity(options.maxObjects) || options.maxObjects === 0 ||
      !quantity(options.maxContractNodes) || options.maxContractNodes === 0 ||
      !quantity(options.maxContractDepth) || options.maxContractDepth === 0) {
    fail('InvalidPublicationStoreConfiguration');
  }
  return Object.freeze({...options, directory: resolve(options.directory),
    privateEvidenceKey: options.privateEvidenceKey === undefined
      ? undefined : Buffer.from(options.privateEvidenceKey)});
}

function validateContractControl(value) {
  if (value === null || typeof value !== 'object' ||
      typeof value.admit !== 'function' ||
      typeof value.recordTransition !== 'function' ||
      typeof value.deliveryTransition !== 'function' ||
      typeof value.deliverySuccessValid !== 'function' ||
      typeof value.trustedClockNotBefore !== 'function' ||
      typeof value.recordAllowsCommit !== 'function' ||
      typeof value.effectFreeCommitValid !== 'function') {
    fail('InvalidPublicationContractControl');
  }
  return value;
}

function indexKey(value) {
  if (!exactKeys(value, [
    'tenantId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof value.tenantId !== 'string' || value.tenantId.length === 0 ||
      !cidPattern.test(value.authorityScopeCid) ||
      !cidPattern.test(value.runDefinitionCid)) {
    fail('InvalidPublicationIndexKey');
  }
  const hash = createHash('sha256');
  hash.update('actql-local-public-index-key/0.1\0', 'utf8');
  for (const text of [value.tenantId, value.authorityScopeCid,
    value.runDefinitionCid]) {
    const bytes = Buffer.from(text, 'utf8');
    const length = Buffer.alloc(8);
    length.writeBigUInt64BE(BigInt(bytes.byteLength));
    hash.update(length);
    hash.update(bytes);
  }
  return hash.digest('hex');
}

export async function openLocalPublicationStore(
  supplied,
  suppliedControl,
  durability = localDurability,
) {
  const configuration = validateConfiguration(supplied);
  const contractControl = validateContractControl(suppliedControl);
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
  const objectsDirectory = resolve(root, 'objects');
  const contractsDirectory = resolve(root, 'contracts');
  const stagingDirectory = resolve(root, 'staging');
  const custodyDirectory = resolve(root, 'prepared-custody');
  const preparedSchemasDirectory = resolve(root, 'prepared-schemas');
  const attemptsDirectory = resolve(root, 'attempts');
  const deliveriesDirectory = resolve(root, 'deliveries');
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
  for (const directory of [root, objectsDirectory, contractsDirectory,
    stagingDirectory, custodyDirectory, preparedSchemasDirectory,
    attemptsDirectory, deliveriesDirectory,
    manifestReadsDirectory, indexesDirectory, retentionExtensionsDirectory,
    metadataInventoriesDirectory, metadataDeletionsDirectory,
    physicalHoldingsDirectory, physicalHoldingDeletionsDirectory,
    deletionsDirectory,
    clocksDirectory]) {
    await mkdir(directory, {recursive: true, mode: 0o700});
  }

  const storeContract = Object.freeze({
    version: 'actql-local-publication-store/0.1',
    store_authority_cid: configuration.storeAuthorityCid,
  });
  const storeContractBytes = Buffer.from(JSON.stringify(storeContract), 'utf8');
  const storeContractPath = resolve(root, 'store.json');
  try {
    await writeExclusive(storeContractPath, storeContractBytes);
    await syncDirectory(root);
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    const existing = await readBounded(
      storeContractPath, configuration.maxObjectBytes,
    );
    if (!existing.equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
  }

  let storedBytes = 0;
  let objectCount = 0;
  for (const name of await readdir(objectsDirectory)) {
    if (!/^[0-9a-f]{64}$/u.test(name)) {
      fail('InvalidPublicationStoreObject');
    }
    const state = await lstat(resolve(objectsDirectory, name));
    if (!state.isFile() || !quantity(state.size) ||
        state.size > configuration.maxObjectBytes ||
        storedBytes + state.size > configuration.capacityBytes) {
      fail('InvalidPublicationStoreObject');
    }
    storedBytes += state.size;
    objectCount++;
  }
  if (objectCount > configuration.maxObjects) {
    fail('PublicationStoreObjectLimit');
  }

  // One process owns the complete capacity authority for this local Store.
  // A dead local owner can be reclaimed, but two live opens never maintain
  // independent counters for the same physical allocation scope.
  const ownership = await acquireStoreOwnership(root);

  for (const name of await readdir(stagingDirectory)) {
    const path = resolve(stagingDirectory, name);
    if (!/^object-[0-9a-f-]{36}$/u.test(name) ||
        !(await lstat(path)).isFile()) {
      fail('InvalidPublicationStagingObject');
    }
    await unlink(path);
  }
  await syncDirectory(stagingDirectory);

  for (const name of await readdir(custodyDirectory)) {
    const path = resolve(custodyDirectory, name);
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedCustody');
    }
  }
  await syncDirectory(custodyDirectory);
  for (const name of await readdir(preparedSchemasDirectory)) {
    const path = resolve(preparedSchemasDirectory, name);
    if (/^\.staging-[0-9a-f-]{36}\.json$/u.test(name)) {
      await unlink(path);
      continue;
    }
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedSchema');
    }
  }
  await syncDirectory(preparedSchemasDirectory);

  for (const name of await readdir(deliveriesDirectory)) {
    const path = resolve(deliveriesDirectory, name);
    if (name.startsWith('.staging-')) {
      await rm(path, {recursive: true, force: false});
      continue;
    }
    if (!/^[0-9a-f]{64}$/u.test(name) || !(await lstat(path)).isDirectory()) {
      fail('InvalidDeliveryAttemptStore');
    }
  }
  await syncDirectory(deliveriesDirectory);
  for (const name of await readdir(manifestReadsDirectory)) {
    const path = resolve(manifestReadsDirectory, name);
    if (name.startsWith('.staging-')) {
      await rm(path, {recursive: true, force: false});
      continue;
    }
    if (!/^[0-9a-f]{64}$/u.test(name) || !(await lstat(path)).isDirectory()) {
      fail('InvalidManifestReadStore');
    }
    for (const useName of await readdir(path)) {
      if (useName.startsWith('.staging-')) {
        await rm(resolve(path, useName), {force: false});
        continue;
      }
      if (!/^[0-9a-f]{64}\.json$/u.test(useName) ||
          !(await lstat(resolve(path, useName))).isFile()) {
        fail('InvalidManifestReadStore');
      }
    }
  }
  await syncDirectory(manifestReadsDirectory);
  for (const name of await readdir(metadataInventoriesDirectory)) {
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(metadataInventoriesDirectory, name))).isFile()) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
  }
  await syncDirectory(metadataInventoriesDirectory);
  for (const name of await readdir(metadataDeletionsDirectory)) {
    const path = resolve(metadataDeletionsDirectory, name);
    if (name.startsWith('.staging-')) {
      await unlink(path);
      continue;
    }
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(metadataDeletionsDirectory, name))).isFile()) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
  }
  await syncDirectory(metadataDeletionsDirectory);
  for (const directory of [
    physicalHoldingsDirectory,
    physicalHoldingDeletionsDirectory,
  ]) {
    for (const name of await readdir(directory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
          !(await lstat(resolve(directory, name))).isFile()) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
    }
    await syncDirectory(directory);
  }
  for (const keyHash of await readdir(retentionExtensionsDirectory)) {
    const directory = resolve(retentionExtensionsDirectory, keyHash);
    if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
        !(await lstat(directory)).isDirectory()) {
      fail('InvalidPublicationRetentionExtensionStore');
    }
    for (const name of await readdir(directory)) {
      const path = resolve(directory, name);
      if (!/^[0-9a-f]{64}$/u.test(name) ||
          !(await lstat(path)).isDirectory()) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      for (const record of await readdir(path)) {
        if (!recordNamePattern.test(record) ||
            !(await lstat(resolve(path, record))).isFile()) {
          fail('InvalidPublicationRetentionExtensionStore');
        }
      }
      await syncDirectory(path);
    }
    await syncDirectory(directory);
  }
  await syncDirectory(retentionExtensionsDirectory);
  for (const keyHash of await readdir(deletionsDirectory)) {
    const directory = resolve(deletionsDirectory, keyHash);
    if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
        !(await lstat(directory)).isDirectory()) {
      fail('InvalidPublicationDeletionStore');
    }
    for (const name of await readdir(directory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
          !(await lstat(resolve(directory, name))).isFile()) {
        fail('InvalidPublicationDeletionStore');
      }
    }
  }
  await syncDirectory(deletionsDirectory);
  for (const name of await readdir(clocksDirectory)) {
    const path = resolve(clocksDirectory, name);
    if (name.startsWith('.staging-')) {
      await rm(path, {force: false});
      continue;
    }
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(path)).isFile()) {
      fail('InvalidPublicationClockObservation');
    }
  }
  await syncDirectory(clocksDirectory);

  let reservedBytes = 0;
  let reservedObjects = 0;
  let closed = false;
  const preparedObjects = new Map();
  const preparedSchemas = new Map();
  const preparedObjectOwners = new WeakMap();
  const reclaimableCustodies = new Map();
  let semanticCommitBusy = Promise.resolve();
  const withSemanticCommit = operation => {
    const flight = semanticCommitBusy.then(operation);
    semanticCommitBusy = flight.catch(() => {});
    return flight;
  };
  const durablyConfirmedIndexes = new Map();
  const durablyConfirmedClocks = new Map();
  let deliveryAdmissionBusy = Promise.resolve();
  let manifestReadAdmissionBusy = Promise.resolve();
  let clockObservationBusy = Promise.resolve();
  let materialRetentionBusy = Promise.resolve();
  let metadataRetentionBusy = Promise.resolve();
  const activeResultReaders = new Map();
  const activePhysicalHoldingReaders = new Map();
  const pendingResultDeletions = new Map();
  const pendingMetadataDeletions = new Map();
  const pendingPhysicalHoldingDeletions = new Map();
  const pendingUncommittedMetadataCleanups = new Map();
  const reclaimingMaterialCids = new Set();

  const objectPath = cid => resolve(objectsDirectory, cidHex(cid));
  const custodyPath = token => resolve(custodyDirectory, `${token}.json`);
  const preparedSchemaPath = token =>
    resolve(preparedSchemasDirectory, `${token}.json`);
  const contractPath = cid => resolve(contractsDirectory, `${cidHex(cid)}.json`);
  const publicationAttemptPath = cid =>
    resolve(attemptsDirectory, cidHex(cid));
  const deliveryAttemptPath = cid =>
    resolve(deliveriesDirectory, cidHex(cid));
  const manifestReadGrantPath = cid =>
    resolve(manifestReadsDirectory, cidHex(cid));
  const clockObservationPath = cid =>
    resolve(clocksDirectory, `${cidHex(cid)}.json`);
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
    if (closed) fail('PublicationStoreClosed');
  };

  const parsePhysicalHolding = bytes => {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationPhysicalHoldingStore', error);
    }
    if (!exactKeys(value, [
      'version', 'namespace', 'holding_cid', 'manifest_cid', 'objects',
    ]) ||
        value.version !== 'actql-local-physical-holding/0.1' ||
        !['remote-transfer', 'publication-private', 'effect-source']
          .includes(value.namespace) ||
        !cidPattern.test(value.holding_cid) ||
        !cidPattern.test(value.manifest_cid) ||
        !Array.isArray(value.objects) ||
        value.objects.length > configuration.maxObjects ||
        value.objects.some(object => !exactKeys(object, [
          'cid', 'byte_count',
        ]) || !cidPattern.test(object.cid) ||
          !quantity(object.byte_count) ||
          object.byte_count > configuration.maxObjectBytes)) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const sizes = new Map();
    for (const object of value.objects) {
      const existing = sizes.get(object.cid);
      if (existing !== undefined && existing !== object.byte_count) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      sizes.set(object.cid, object.byte_count);
    }
    return Object.freeze({
      ...value,
      objects: Object.freeze(value.objects.map(object =>
        Object.freeze({...object}))),
    });
  };

  const readPhysicalHoldingAt = async path => {
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    return parsePhysicalHolding(bytes);
  };

  const readPhysicalHolding = holdingCid =>
    readPhysicalHoldingAt(physicalHoldingPath(holdingCid));

  const readPhysicalHoldingDeletion = holdingCid =>
    readPhysicalHoldingAt(physicalHoldingDeletionPath(holdingCid));

  const parseMetadataInventory = bytes => {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationMetadataInventoryStore', error);
    }
    if (!exactKeys(value, [
      'version', 'tenant_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'publication_attempt_cid', 'contract_objects',
    ]) ||
        value.version !== 'actql-local-publication-metadata-inventory/0.1' ||
        typeof value.tenant_id !== 'string' || value.tenant_id.length === 0 ||
        !cidPattern.test(value.authority_scope_cid) ||
        !cidPattern.test(value.run_definition_cid) ||
        !cidPattern.test(value.public_index_entry_cid) ||
        !cidPattern.test(value.publication_attempt_cid) ||
        !Array.isArray(value.contract_objects) ||
        value.contract_objects.length === 0 ||
        value.contract_objects.some(object => !exactKeys(object, [
          'semantic_cid', 'physical_cid', 'byte_count',
        ]) || !cidPattern.test(object.semantic_cid) ||
          !cidPattern.test(object.physical_cid) ||
          !quantity(object.byte_count)) ||
        new Set(value.contract_objects.map(object => object.semantic_cid))
          .size !== value.contract_objects.length ||
        [...value.contract_objects]
          .sort((left, right) =>
            left.semantic_cid.localeCompare(right.semantic_cid))
          .map(object => object.semantic_cid).join('\0') !==
          value.contract_objects.map(object => object.semantic_cid).join('\0') ||
        !value.contract_objects.some(object =>
          object.semantic_cid === value.public_index_entry_cid)) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return Object.freeze({
      ...value,
      contract_objects: Object.freeze(value.contract_objects.map(object =>
        Object.freeze({...object}))),
    });
  };

  const readMetadataInventory = async publicIndexEntryCid => {
    let bytes;
    try {
      bytes = await readBounded(
        metadataInventoryPath(publicIndexEntryCid),
        configuration.maxObjectBytes,
      );
    } catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    return parseMetadataInventory(bytes);
  };

  const ensureMetadataInventory = async value => {
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
      if (error?.code !== 'EEXIST') throw error;
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

  const readMetadataDeletion = async keyHash => {
    let bytes;
    try {
      bytes = await readBounded(
        metadataDeletionPath(keyHash), configuration.maxObjectBytes,
      );
    } catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationMetadataDeletionStore', error);
    }
    if (exactKeys(value, ['version', 'run_definition_cid']) &&
        value.version ===
          'actql-local-publication-metadata-retired/0.1' &&
        cidPattern.test(value.run_definition_cid)) {
      return Object.freeze(value);
    }
    if (!exactKeys(value, [
      'version', 'tenant_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'results', 'contract_objects', 'requested_at',
    ]) ||
        value.version !== 'actql-local-publication-metadata-deletion/0.1' ||
        typeof value.tenant_id !== 'string' || value.tenant_id.length === 0 ||
        !cidPattern.test(value.authority_scope_cid) ||
        !cidPattern.test(value.run_definition_cid) ||
        !cidPattern.test(value.public_index_entry_cid) ||
        !Array.isArray(value.results) || value.results.length === 0 ||
        value.results.some(result => !exactKeys(result, [
          'result_definition_cid', 'material_generation_cid', 'byte_count',
        ]) || !cidPattern.test(result.result_definition_cid) ||
          !cidPattern.test(result.material_generation_cid) ||
          !quantity(result.byte_count)) ||
        new Set(value.results.map(result => result.result_definition_cid))
          .size !== value.results.length ||
        !Array.isArray(value.contract_objects) ||
        value.contract_objects.length === 0 ||
        value.contract_objects.some(object => !exactKeys(object, [
          'semantic_cid', 'physical_cid', 'byte_count',
        ]) || !cidPattern.test(object.semantic_cid) ||
          !cidPattern.test(object.physical_cid) ||
          !quantity(object.byte_count)) ||
        new Set(value.contract_objects.map(object => object.semantic_cid))
          .size !== value.contract_objects.length ||
        [...value.contract_objects]
          .sort((left, right) =>
            left.semantic_cid.localeCompare(right.semantic_cid))
          .map(object => object.semantic_cid).join('\0') !==
          value.contract_objects.map(object => object.semantic_cid).join('\0') ||
        !timestampPattern.test(value.requested_at)) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    return Object.freeze(value);
  };

  const compactMetadataDeletion = async (keyHash, runDefinitionCid) => {
    const value = Object.freeze({
      version: 'actql-local-publication-metadata-retired/0.1',
      run_definition_cid: runDefinitionCid,
    });
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    const staging = resolve(
      metadataDeletionsDirectory,
      `.staging-${randomUUID()}`,
    );
    try {
      await writeExclusive(staging, bytes);
      await rename(staging, metadataDeletionPath(keyHash));
      await syncDirectory(metadataDeletionsDirectory);
    } finally {
      try { await unlink(staging); }
      catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
    }
    return value;
  };

  const ensureMetadataDeletion = async (keyHash, value) => {
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    try { await writeExclusive(metadataDeletionPath(keyHash), bytes); }
    catch (error) {
      if (error?.code !== 'EEXIST') throw error;
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

  const runMetadataDeletionStarted = async runDefinitionCid => {
    for (const name of await readdir(metadataDeletionsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataDeletionStore');
      }
      const value = await readMetadataDeletion(name.slice(0, -5));
      if (value.run_definition_cid === runDefinitionCid) return true;
    }
    return false;
  };

  const parseCustodyRecord = bytes => {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationPreparedCustody', error); }
    if (!exactKeys(value, [
      'version', 'material_generation_cid', 'byte_count', 'device', 'inode',
    ]) || value.version !== 'actql-local-prepared-custody/0.1' ||
        !cidPattern.test(value.material_generation_cid) ||
        !quantity(value.byte_count) || typeof value.device !== 'string' ||
        !/^(0|[1-9][0-9]*)$/u.test(value.device) ||
        typeof value.inode !== 'string' ||
        !/^(0|[1-9][0-9]*)$/u.test(value.inode)) {
      fail('InvalidPublicationPreparedCustody');
    }
    return Object.freeze(value);
  };

  const registerCustody = async (cid, bytes, state) => {
    const token = randomUUID();
    const record = Object.freeze({
      version: 'actql-local-prepared-custody/0.1',
      material_generation_cid: cid,
      byte_count: bytes,
      device: String(state.dev),
      inode: String(state.ino),
    });
    const path = custodyPath(token);
    await writeExclusive(path, Buffer.from(JSON.stringify(record), 'utf8'));
    await syncDirectory(custodyDirectory);
    const custody = {
      token,
      path,
      record,
      accounted: false,
      pendingUnlink: false,
      busy: Promise.resolve(),
    };
    reclaimableCustodies.set(token, custody);
    return custody;
  };

  const removeCustodyRecord = async custody => {
    try { await unlink(custody.path); }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    await syncDirectory(custodyDirectory);
    reclaimableCustodies.delete(custody.token);
  };

  const reclaimCustody = custody => {
    const operation = custody.busy.then(async () => {
      if (!reclaimableCustodies.has(custody.token)) return false;
      const cid = custody.record.material_generation_cid;
      const confirmUnlink = async () => {
        await syncDirectory(objectsDirectory);
        if (custody.accounted) {
          storedBytes -= custody.record.byte_count;
          objectCount--;
          custody.accounted = false;
        }
        custody.pendingUnlink = false;
      };
      if (custody.pendingUnlink) {
        await confirmUnlink();
        await removeCustodyRecord(custody);
        return true;
      }
      let state;
      try { state = await lstat(objectPath(cid)); }
      catch (error) {
        if (error?.code !== 'ENOENT') throw error;
        if (custody.accounted) await confirmUnlink();
        await removeCustodyRecord(custody);
        return true;
      }
      if (!state.isFile() || state.size !== custody.record.byte_count) {
        fail('InvalidPublicationPreparedCustody');
      }
      const ownsAllocation = String(state.dev) === custody.record.device &&
        String(state.ino) === custody.record.inode;
      if (ownsAllocation) {
        const hasLiveReference = await materialHasLiveReference(cid);
        if (!hasLiveReference) {
          // A second link is not proof that another owner accepted custody.
          // The prepared writer may still own its staging alias.
          if (state.nlink !== 1) return false;
          await verifyObject(cid);
          await unlink(objectPath(cid));
          custody.pendingUnlink = true;
          await confirmUnlink();
        }
      }
      await removeCustodyRecord(custody);
      return true;
    });
    custody.busy = operation.catch(() => {});
    return operation;
  };

  const verifyObject = async cid => {
    const path = objectPath(cid);
    let state;
    try { state = await lstat(path); }
    catch (error) {
      if (error?.code === 'ENOENT') fail('PublicationObjectMissing');
      throw error;
    }
    if (!state.isFile() || state.size > configuration.maxObjectBytes) {
      fail('InvalidPublicationStoreObject');
    }
    const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const hash = createHash('sha256');
    let bytes = 0;
    try {
      const before = await handle.stat();
      const stream = handle.createReadStream({autoClose: false});
      for await (const chunk of stream) {
        hash.update(chunk);
        bytes += chunk.byteLength;
      }
      const after = await handle.stat();
      if (!before.isFile() || !after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || bytes !== after.size ||
          hash.digest('hex') !== cidHex(cid)) {
        fail('PublicationObjectCorrupt');
      }
      return Object.freeze({cid, bytes});
    } finally {
      await handle.close();
    }
  };

  const readClockObservation = async clockContractCid => {
    let bytes;
    try {
      bytes = await readBounded(
        clockObservationPath(clockContractCid),
        configuration.maxObjectBytes,
      );
    } catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationClockObservation', error); }
    if (!exactKeys(value, ['clockContractCid', 'observedAt']) ||
        value.clockContractCid !== clockContractCid ||
        typeof value.observedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, value.observedAt,
        ) !== true) {
      fail('InvalidPublicationClockObservation');
    }
    return Object.freeze(value);
  };

  const observeTrustedClock = (clockContractCid, observedAt) => {
    active();
    cidHex(clockContractCid);
    if (typeof observedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, observedAt,
        ) !== true) {
      fail('InvalidPublicationClockObservation');
    }
    const operation = clockObservationBusy.then(async () => {
      const previous = await readClockObservation(clockContractCid);
      if (contractControl.trustedClockNotBefore(
        previous?.observedAt, observedAt,
      ) !== true) {
        fail('PublicationClockUncertain');
      }
      const confirmed = durablyConfirmedClocks.get(clockContractCid);
      if (previous?.observedAt === observedAt) {
        if (confirmed !== observedAt) {
          await syncDirectory(clocksDirectory);
          const current = await readClockObservation(clockContractCid);
          if (current?.observedAt !== observedAt) {
            fail('PublicationClockUncertain');
          }
          durablyConfirmedClocks.set(clockContractCid, observedAt);
        }
        return previous;
      }
      const value = Object.freeze({clockContractCid, observedAt});
      const bytes = Buffer.from(JSON.stringify(value), 'utf8');
      if (bytes.byteLength > configuration.maxObjectBytes) {
        fail('PublicationObjectLimit');
      }
      const staging = resolve(clocksDirectory, `.staging-${randomUUID()}`);
      try {
        await writeExclusive(staging, bytes);
        await rename(staging, clockObservationPath(clockContractCid));
        await syncDirectory(clocksDirectory);
      } catch (error) {
        try { await unlink(staging); }
        catch (cleanupError) {
          if (cleanupError?.code !== 'ENOENT') throw cleanupError;
        }
        throw error;
      }
      const current = await readClockObservation(clockContractCid);
      if (current?.observedAt !== observedAt) {
        fail('PublicationClockUncertain');
      }
      durablyConfirmedClocks.set(clockContractCid, observedAt);
      return current;
    });
    clockObservationBusy = operation.catch(() => {});
    return operation;
  };

  const createObjectWriter = (maxBytes, trackCustody = false) => {
    active();
    if (!quantity(maxBytes) || maxBytes > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    if (objectCount + reservedObjects >= configuration.maxObjects) {
      fail('PublicationStoreObjectLimit');
    }
    if (storedBytes + reservedBytes + maxBytes >
        configuration.capacityBytes) {
      fail('PublicationStoreCapacity');
    }
    reservedBytes += maxBytes;
    reservedObjects++;
    const temporary = resolve(stagingDirectory, `object-${randomUUID()}`);
    const hash = createHash('sha256');
    let bytes = 0;
    let acceptedBytes = 0;
    let handle;
    let finished = false;
    let cleanupPending = false;
    let reservationHeld = true;
    let custody;
    let busy = Promise.resolve();
    const releaseReservation = () => {
      if (!reservationHeld) return;
      reservedBytes -= maxBytes;
      reservedObjects--;
      reservationHeld = false;
    };
    const start = async () => {
      try {
        handle = await open(
          temporary,
          constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY,
          0o600,
        );
      } catch (error) {
        finished = true;
        releaseReservation();
        throw error;
      }
    };
    const ready = start();
    const queue = operation => {
      const result = busy.then(operation);
      busy = result.catch(() => {});
      return result;
    };
    const cleanupTemporary = async () => {
      if (handle) {
        await handle.close();
        handle = undefined;
      }
      try { await unlink(temporary); }
      catch (error) { if (error?.code !== 'ENOENT') throw error; }
      await syncDirectory(stagingDirectory);
    };
    const cleanupAndRelease = async () => {
      try {
        await cleanupTemporary();
        cleanupPending = false;
        releaseReservation();
      } catch (error) {
        cleanupPending = true;
        throw error;
      }
    };
    return Object.freeze({
      append(frame) {
        let length;
        if (Buffer.isBuffer(frame) || frame instanceof Uint8Array) {
          length = frame.byteLength;
        } else if (typeof frame === 'string') {
          length = Buffer.byteLength(frame, 'utf8');
        } else {
          return queue(async () => fail('PublicationObjectLimit'));
        }
        if (finished || length > maxBytes - acceptedBytes) {
          return queue(async () => {
            if (finished) fail('PublicationObjectWriterClosed');
            fail('PublicationObjectLimit');
          });
        }
        // Snapshot caller-owned mutable input only after its exact size is
        // known to fit. No rejected frame can force an unbounded copy.
        const buffer = Buffer.isBuffer(frame) ? Buffer.from(frame) :
          frame instanceof Uint8Array ? Buffer.from(frame) :
            Buffer.from(frame, 'utf8');
        acceptedBytes += length;
        return queue(async () => {
          await ready;
          if (finished) fail('PublicationObjectWriterClosed');
          try {
            let offset = 0;
            while (offset < buffer.byteLength) {
              const result = await handle.write(
                buffer, offset, buffer.byteLength - offset, bytes + offset,
              );
              if (result.bytesWritten === 0) {
                fail('IncompletePublicationWrite');
              }
              offset += result.bytesWritten;
            }
            hash.update(buffer);
            bytes += buffer.byteLength;
          } catch (error) {
            finished = true;
            throw error;
          }
        });
      },
      seal(expectedCid) {
        return queue(async () => {
          await ready;
          if (finished) fail('PublicationObjectWriterClosed');
          finished = true;
          let installed = false;
          let result;
          let failed = false;
          let primaryFailure;
          try {
            await handle.sync();
            const state = await handle.stat();
            if (!state.isFile() || state.size !== bytes) {
              fail('IncompletePublicationWrite');
            }
            await handle.close();
            handle = undefined;
            const cid = `sha256:${hash.digest('hex')}`;
            if (expectedCid !== undefined && expectedCid !== cid) {
              fail('PublicationObjectIdentityMismatch');
            }
            if (reclaimingMaterialCids.has(cid)) {
              fail('PublicationObjectReclamationPending');
            }
            if (trackCustody) {
              custody = await registerCustody(cid, bytes, state);
            }
            const finalPath = objectPath(cid);
            try {
              await link(temporary, finalPath);
              installed = true;
              storedBytes += bytes;
              objectCount++;
              if (custody !== undefined) custody.accounted = true;
              await syncDirectory(objectsDirectory);
            } catch (error) {
              if (error?.code !== 'EEXIST') throw error;
              const existing = await verifyObject(cid);
              if (existing.bytes !== bytes) {
                fail('PublicationObjectIdentityMismatch');
              }
            }
            result = custody === undefined
              ? Object.freeze({cid, bytes, created: installed})
              : Object.freeze({cid, bytes, created: installed, custody});
          } catch (error) {
            failed = true;
            primaryFailure = error;
          }
          if (failed) {
            try { await cleanupAndRelease(); }
            catch { cleanupPending = true; }
            if (!reservationHeld && custody !== undefined) {
              try {
                if (await reclaimCustody(custody)) custody = undefined;
                else cleanupPending = true;
              } catch { cleanupPending = true; }
            }
            throw primaryFailure;
          }
          await cleanupAndRelease();
          custody = undefined;
          return result;
        });
      },
      cancel() {
        return queue(async () => {
          try { await ready; }
          catch (error) {
            if (!reservationHeld) return false;
            throw error;
          }
          if (finished && !reservationHeld && custody === undefined) {
            return false;
          }
          finished = true;
          if (reservationHeld) await cleanupAndRelease();
          if (custody !== undefined) {
            if (await reclaimCustody(custody)) {
              custody = undefined;
              cleanupPending = false;
            } else {
              cleanupPending = true;
              fail('PublicationPreparedCustodyPending');
            }
          }
          return true;
        });
      },
      status: () => Object.freeze({
        maxBytes,
        bytes,
        finished,
        cleanupPending,
        reservationHeld,
        custodyPending: custody !== undefined,
      }),
    });
  };

  const createPreparedObjectWriter = maxBytes => {
    const writer = createObjectWriter(maxBytes, true);
    return Object.freeze({
      append: frame => writer.append(frame),
      cancel: () => writer.cancel(),
      status: () => writer.status(),
      async seal(expectedCid) {
        const physical = await writer.seal(expectedCid);
        let group = preparedObjects.get(physical.cid);
        if (group === undefined) {
          group = {
            holders: new Set(),
            commitOwners: new Set(),
            removable: physical.created,
            committed: false,
            pendingUnlink: undefined,
            custodies: new Set(),
            busy: Promise.resolve(),
          };
          preparedObjects.set(physical.cid, group);
        } else if (physical.created) {
          group.removable = true;
        }
        if (physical.custody !== undefined) {
          group.custodies.add(physical.custody);
        }
        const errors = [];
        const holder = {active: true, releasing: undefined};
        group.holders.add(holder);
        const state = () => Object.freeze({
          pending: holder.active,
          errors: Object.freeze([...errors]),
        });
        const clearCustodies = async () => {
          for (const custody of [...group.custodies]) {
            await removeCustodyRecord(custody);
            group.custodies.delete(custody);
          }
        };
        const finishPendingUnlink = async () => {
          const pending = group.pendingUnlink;
          if (pending === undefined) return;
          if (!pending.accounted) {
            await syncDirectory(objectsDirectory);
            storedBytes -= pending.bytes;
            objectCount--;
            pending.accounted = true;
          }
          await clearCustodies();
          pending.owner.active = false;
          group.holders.delete(pending.owner);
          group.pendingUnlink = undefined;
        };
        const release = () => {
          if (!holder.active) return Promise.resolve(false);
          if (holder.releasing !== undefined) return holder.releasing;
          const operation = group.busy.then(async () => {
            if (!holder.active) return false;
            await finishPendingUnlink();
            if (!holder.active) {
              if (group.holders.size === 0 &&
                  group.commitOwners.size === 0) {
                preparedObjects.delete(physical.cid);
              }
              return true;
            }
            if (group.commitOwners.size > 0) return false;
            if (group.committed || group.holders.size > 1 ||
                !group.removable) {
              const finalHolder = group.holders.size === 1 &&
                group.commitOwners.size === 0;
              if (finalHolder) await clearCustodies();
              group.holders.delete(holder);
              holder.active = false;
              if (finalHolder) {
                preparedObjects.delete(physical.cid);
              }
              return true;
            }
            const path = objectPath(physical.cid);
            const before = await lstat(path);
            if (!before.isFile() || before.size !== physical.bytes) {
              fail('InvalidPublicationStoreObject');
            }
            // Semantic contracts and public index entries are hard links to
            // their physical object. Never reclaim an allocation with another
            // filesystem owner, even if the prepared holder is the creator.
            if (before.nlink !== 1) {
              group.holders.delete(holder);
              holder.active = false;
              preparedObjects.delete(physical.cid);
              return true;
            }
            await unlink(path);
            group.removable = false;
            group.pendingUnlink = {
              owner: holder,
              bytes: before.size,
              accounted: false,
            };
            await finishPendingUnlink();
            if (group.holders.size === 0 &&
                group.commitOwners.size === 0) {
              preparedObjects.delete(physical.cid);
            }
            return true;
          });
          group.busy = operation.catch(() => {});
          holder.releasing = operation.catch(error => {
            errors.push(error);
            throw error;
          }).finally(() => { holder.releasing = undefined; });
          return holder.releasing;
        };
        const prepared = Object.freeze({
          cid: physical.cid,
          status: state,
          release,
          async retry() {
            if (holder.active) await release();
            return state();
          },
        });
        preparedObjectOwners.set(prepared, Object.freeze({
          cid: physical.cid,
          bytes: physical.bytes,
        }));
        return Object.freeze({
          cid: physical.cid,
          bytes: physical.bytes,
          created: physical.created,
          prepared,
        });
      },
    });
  };

  const adoptPreparedObjects = async cids => {
    for (const cid of cids) {
      const group = preparedObjects.get(cid);
      if (group === undefined) continue;
      for (const custody of [...group.custodies]) {
        await removeCustodyRecord(custody);
        group.custodies.delete(custody);
      }
      group.committed = true;
      for (const owner of group.commitOwners) {
        owner.groups.delete(group);
        if (owner.groups.size === 0) {
          owner.pending = false;
          owner.outcome = 'committed';
        }
      }
      group.commitOwners.clear();
      for (const holder of group.holders) holder.active = false;
      group.holders.clear();
      preparedObjects.delete(cid);
    }
  };

  const beginPreparedCommit = (cids, key, indexCid) => {
    const owner = {
      pending: false,
      outcome: undefined,
      groups: new Set(),
      errors: [],
    };
    for (const cid of new Set(cids)) {
      const group = preparedObjects.get(cid);
      if (group === undefined || group.committed) continue;
      group.commitOwners.add(owner);
      owner.groups.add(group);
      owner.pending = true;
    }
    const settleUncommitted = () => {
      for (const group of owner.groups) group.commitOwners.delete(owner);
      owner.groups.clear();
      owner.pending = false;
      owner.outcome = 'uncommitted';
    };
    const status = () => Object.freeze({
      pending: owner.pending,
      outcome: owner.outcome,
      errors: Object.freeze([...owner.errors]),
    });
    const resolveConfirmed = async entry => {
      if (!owner.pending) return status();
      if (entry?.public_index_entry_cid === indexCid) {
        await adoptPreparedObjects(cids);
      } else {
        settleUncommitted();
      }
      return status();
    };
    return Object.freeze({
      status,
      resolveConfirmed,
      async retry() {
        if (!owner.pending) return status();
        try {
          return await resolveConfirmed(await confirmCommittedIndex(key));
        } catch (error) {
          owner.errors.push(error);
          throw error;
        }
      },
    });
  };

  const commitCustodyFailure = (primary, custody, reconciliation) => {
    if (custody.status().pending !== true) return primary;
    const code = typeof primary?.code === 'string'
      ? primary.code : 'PublicationCommitUnknown';
    const failure = new PublicationStoreError(code, primary);
    failure.primaryFailure = primary;
    failure.reconciliationFailure = reconciliation;
    failure.cleanupPending = true;
    failure.cleanupErrors = Object.freeze(
      reconciliation === undefined ? [] : [reconciliation],
    );
    failure.cleanupHandle = custody;
    return failure;
  };

  const putBytesInternal = async (value, expectedCid, trackCustody) => {
    const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value);
    const cid = `sha256:${createHash('sha256').update(buffer).digest('hex')}`;
    if (expectedCid !== undefined && expectedCid !== cid) {
      fail('PublicationObjectIdentityMismatch');
    }
    try {
      const existing = await verifyObject(cid);
      if (existing.bytes !== buffer.byteLength) {
        fail('PublicationObjectIdentityMismatch');
      }
      return Object.freeze({...existing, created: false});
    } catch (error) {
      if (error?.code !== 'PublicationObjectMissing') throw error;
    }
    const writer = createObjectWriter(buffer.byteLength, trackCustody);
    try {
      await writer.append(buffer);
      return await writer.seal(cid);
    } catch (primaryFailure) {
      const cleanupErrors = [];
      try {
        const status = writer.status();
        if (status.reservationHeld || status.custodyPending) {
          await writer.cancel();
        }
      } catch (error) { cleanupErrors.push(error); }
      if (!writer.status().reservationHeld &&
          !writer.status().custodyPending) throw primaryFailure;
      const code = typeof primaryFailure?.code === 'string'
        ? primaryFailure.code : 'PublicationObjectWriteFailed';
      const failure = new PublicationStoreError(code, primaryFailure);
      failure.primaryFailure = primaryFailure;
      const status = () => Object.freeze({
        pending: writer.status().reservationHeld ||
          writer.status().custodyPending,
        errors: Object.freeze([...cleanupErrors]),
      });
      const cleanupHandle = Object.freeze({
        status,
        async retry() {
          if (writer.status().reservationHeld ||
              writer.status().custodyPending) {
            try { await writer.cancel(); }
            catch (error) { cleanupErrors.push(error); }
          }
          failure.cleanupPending = status().pending;
          failure.cleanupErrors = status().errors;
          return status();
        },
      });
      failure.cleanupPending = true;
      failure.cleanupErrors = status().errors;
      failure.cleanupHandle = cleanupHandle;
      throw failure;
    }
  };

  const putBytes = (value, expectedCid) =>
    putBytesInternal(value, expectedCid, false);

  // Semantic contract identities exclude their self-CID field and therefore
  // are deliberately not the physical digest of the stored complete body.
  // The binding is an exclusive hard link to one immutable physical object.
  const putSemantic = async (wire, semanticCid) => {
    if (typeof wire !== 'string' ||
        Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
      fail('InvalidPublicationSemanticWire');
    }
    cidHex(semanticCid);
    const bytes = Buffer.from(wire, 'utf8');
    const physical = await putBytesInternal(bytes, undefined, true);
    const target = contractPath(semanticCid);
    let created = true;
    try {
      try {
        await link(objectPath(physical.cid), target);
      } catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        created = false;
        const existing = await readBounded(
          target, configuration.maxObjectBytes,
        );
        if (!existing.equals(bytes)) {
          fail('PublicationSemanticIdentityConflict');
        }
      }
      await syncDirectory(contractsDirectory);
      if (physical.custody !== undefined) {
        await removeCustodyRecord(physical.custody);
      }
      const visible = Object.freeze({
        cid: physical.cid,
        bytes: physical.bytes,
        created: physical.created,
      });
      return Object.freeze({semanticCid, physical: visible, created});
    } catch (error) {
      if (physical.custody === undefined ||
          !reclaimableCustodies.has(physical.custody.token)) throw error;
      const cleanupErrors = [];
      try { await reclaimCustody(physical.custody); }
      catch (cleanupError) { cleanupErrors.push(cleanupError); }
      if (!reclaimableCustodies.has(physical.custody.token)) throw error;
      const failure = new PublicationStoreError(
        typeof error?.code === 'string'
          ? error.code : 'PublicationSemanticWriteFailed',
        error,
      );
      failure.primaryFailure = error;
      const status = () => Object.freeze({
        pending: reclaimableCustodies.has(physical.custody.token),
        errors: Object.freeze([...cleanupErrors]),
      });
      failure.cleanupPending = true;
      failure.cleanupErrors = status().errors;
      failure.cleanupHandle = Object.freeze({
        status,
        async retry() {
          try { await reclaimCustody(physical.custody); }
          catch (cleanupError) {
            cleanupErrors.push(cleanupError);
            throw cleanupError;
          } finally {
            failure.cleanupPending = status().pending;
            failure.cleanupErrors = status().errors;
          }
          return status();
        },
      });
      throw failure;
    }
  };

  const parsePreparedSchema = bytes => {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationPreparedSchema', error); }
    if (!exactKeys(value, [
      'version', 'semantic_cid', 'physical_cid', 'byte_count', 'removable',
      'run_definition_cid', 'device', 'inode',
    ]) || value.version !== 'actql-local-prepared-schema/0.1' ||
        !cidPattern.test(value.semantic_cid) ||
        !cidPattern.test(value.physical_cid) ||
        value.semantic_cid !== value.physical_cid ||
        !cidPattern.test(value.run_definition_cid) ||
        !quantity(value.byte_count) ||
        typeof value.removable !== 'boolean' ||
        ![value.device, value.inode].every(part => part === null ||
          (typeof part === 'string' && /^(0|[1-9][0-9]*)$/u.test(part))) ||
        (value.device === null) !== (value.inode === null)) {
      fail('InvalidPublicationPreparedSchema');
    }
    return Object.freeze(value);
  };

  const releasePreparedSchema = (group, holder) => {
    if (!holder.active) return Promise.resolve(false);
    if (holder.releasing !== undefined) return holder.releasing;
    const flight = withSemanticCommit(async () => {
      if (!holder.active) return false;
      if (group.unconfirmedPhysical !== undefined) {
        await syncDirectory(objectsDirectory);
        storedBytes -= group.unconfirmedPhysical.bytes;
        objectCount--;
        for (const custody of reclaimableCustodies.values()) {
          if (custody.record.material_generation_cid ===
                group.record.physical_cid &&
              custody.record.device === group.unconfirmedPhysical.device &&
              custody.record.inode === group.unconfirmedPhysical.inode) {
            custody.accounted = false;
          }
        }
        group.unconfirmedPhysical = undefined;
        group.generationRetired = true;
      }
      if (group.pendingAliasSync) {
        await syncDirectory(contractsDirectory);
        group.pendingAliasSync = false;
      }
      if (group.holders.size === 1 && group.removable &&
          !await metadataContractHasLiveReference(
            group.record.semantic_cid, undefined,
          )) {
        const semanticPath = contractPath(group.record.semantic_cid);
        const physicalPath = objectPath(group.record.physical_cid);
        let physical;
        try { physical = await lstat(physicalPath); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
        let semantic;
        try { semantic = await lstat(semanticPath); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
        if (semantic !== undefined) {
          if (physical === undefined || !semantic.isFile() ||
              !physical.isFile() ||
              semantic.size !== group.record.byte_count ||
              physical.size !== group.record.byte_count ||
              semantic.dev !== physical.dev ||
              semantic.ino !== physical.ino) {
            fail('PublicationContractCorrupt');
          }
          if (group.generation !== undefined &&
              (group.generation.device !== String(physical.dev) ||
                group.generation.inode !== String(physical.ino))) {
            group.generationRetired = true;
          }
          if (!group.generationRetired) {
            group.generation = {
              device: String(physical.dev), inode: String(physical.ino),
            };
            await unlink(semanticPath);
            group.pendingAliasSync = true;
            await syncDirectory(contractsDirectory);
            group.pendingAliasSync = false;
          }
        }
        if (!group.generationRetired && physical !== undefined &&
            group.generation !== undefined &&
            String(physical.dev) === group.generation.device &&
            String(physical.ino) === group.generation.inode &&
            physical.nlink <= 2 &&
            !(preparedObjects.get(group.record.physical_cid)?.holders.size > 0) &&
            !await materialHasLiveReference(group.record.physical_cid)) {
          const remaining = await lstat(physicalPath);
          if (remaining.nlink === 1) {
            await unlink(physicalPath);
            group.unconfirmedPhysical = {
              bytes: group.record.byte_count,
              device: String(remaining.dev),
              inode: String(remaining.ino),
            };
            await syncDirectory(objectsDirectory);
            storedBytes -= group.unconfirmedPhysical.bytes;
            objectCount--;
            for (const custody of reclaimableCustodies.values()) {
              if (custody.record.material_generation_cid ===
                    group.record.physical_cid &&
                  custody.record.device === group.unconfirmedPhysical.device &&
                  custody.record.inode === group.unconfirmedPhysical.inode) {
                custody.accounted = false;
              }
            }
            group.unconfirmedPhysical = undefined;
          }
        }
      }
      try { await unlink(holder.path); }
      catch (error) { if (error?.code !== 'ENOENT') throw error; }
      await syncDirectory(preparedSchemasDirectory);
      group.holders.delete(holder);
      holder.active = false;
      if (group.holders.size === 0) {
        preparedSchemas.delete(group.record.semantic_cid);
      }
      return true;
    });
    holder.releasing = flight.catch(error => {
      holder.errors.push(error);
      throw error;
    }).finally(() => { holder.releasing = undefined; });
    return holder.releasing;
  };

  const preparedSchemaHandle = (group, holder) => Object.freeze({
    status: () => Object.freeze({
      pending: holder.active,
      errors: Object.freeze([...holder.errors]),
    }),
    release: () => releasePreparedSchema(group, holder),
    async retry() {
      if (holder.active) await releasePreparedSchema(group, holder);
      return Object.freeze({
        pending: holder.active,
        errors: Object.freeze([...holder.errors]),
      });
    },
  });

  const adoptPreparedSchemas = async (cids, runDefinitionCid) => {
    for (const cid of new Set(cids)) {
      const group = preparedSchemas.get(cid);
      if (group === undefined) continue;
      const adopted = [...group.holders].filter(holder =>
        holder.runDefinitionCid === runDefinitionCid);
      for (const holder of adopted) {
        try { await unlink(holder.path); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
      }
      await syncDirectory(preparedSchemasDirectory);
      for (const holder of adopted) {
        holder.active = false;
        group.holders.delete(holder);
      }
      if (group.holders.size === 0) preparedSchemas.delete(cid);
    }
  };

  const putPreparedResultSchema = (wire, semanticCid, runDefinitionCid) =>
    withSemanticCommit(async () => {
      active();
      if (typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidPublicationSemanticWire');
      }
      cidHex(semanticCid);
      cidHex(runDefinitionCid);
      const bytes = Buffer.from(wire, 'utf8');
      const physicalCid = `sha256:${createHash('sha256')
        .update(bytes).digest('hex')}`;
      if (semanticCid !== physicalCid) {
        fail('PublicationObjectIdentityMismatch');
      }
      let group = preparedSchemas.get(semanticCid);
      if (group === undefined) {
        let existing;
        try { existing = await lstat(contractPath(semanticCid)); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
        group = {
          record: Object.freeze({
            version: 'actql-local-prepared-schema/0.1',
            semantic_cid: semanticCid,
            physical_cid: physicalCid,
            byte_count: bytes.byteLength,
            removable: existing === undefined,
            run_definition_cid: runDefinitionCid,
            device: null,
            inode: null,
          }),
          removable: existing === undefined,
          holders: new Set(),
          unconfirmedPhysical: undefined,
          pendingAliasSync: false,
          generation: undefined,
          generationRetired: false,
        };
        preparedSchemas.set(semanticCid, group);
      }
      const token = randomUUID();
      const holder = {
        path: preparedSchemaPath(token), active: true,
        releasing: undefined, errors: [], runDefinitionCid,
      };
      const record = Object.freeze({
        ...group.record, run_definition_cid: runDefinitionCid,
      });
      group.holders.add(holder);
      const prepared = preparedSchemaHandle(group, holder);
      try {
        await writeExclusive(holder.path,
          Buffer.from(JSON.stringify(record), 'utf8'));
        await syncDirectory(preparedSchemasDirectory);
        const stored = await putSemantic(wire, semanticCid);
        const physical = await lstat(objectPath(physicalCid));
        const semantic = await lstat(contractPath(semanticCid));
        if (!physical.isFile() || !semantic.isFile() ||
            physical.dev !== semantic.dev ||
            physical.ino !== semantic.ino ||
            physical.size !== bytes.byteLength) {
          fail('PublicationPreparedSchemaGenerationMismatch');
        }
        const generation = {
          device: String(physical.dev), inode: String(physical.ino),
        };
        if (group.generation !== undefined &&
            (group.generation.device !== generation.device ||
              group.generation.inode !== generation.inode)) {
          fail('PublicationPreparedSchemaGenerationMismatch');
        }
        const staged = resolve(preparedSchemasDirectory,
          `.staging-${randomUUID()}.json`);
        await writeExclusive(staged, Buffer.from(JSON.stringify({
          ...record, ...generation,
        }), 'utf8'));
        await rename(staged, holder.path);
        await syncDirectory(preparedSchemasDirectory);
        group.generation = generation;
        return Object.freeze({...stored, prepared});
      } catch (error) {
        // The marker remains durable if either physical or alias cleanup
        // cannot be confirmed. The caller can retry without resending data.
        const failure = new PublicationStoreError(
          typeof error?.code === 'string'
            ? error.code : 'PublicationPreparedSchemaFailed', error,
        );
        failure.cleanupPending = true;
        failure.cleanupHandle = Object.freeze({
          status: () => Object.freeze({
            pending: prepared.status().pending ||
              error?.cleanupHandle?.status()?.pending === true,
            errors: Object.freeze([
              ...prepared.status().errors,
              ...(error?.cleanupHandle?.status()?.errors ?? []),
            ]),
          }),
          async retry() {
            if (prepared.status().pending) await prepared.retry();
            if (error?.cleanupHandle?.status()?.pending === true) {
              await error.cleanupHandle.retry();
            }
            return this.status();
          },
        });
        failure.primaryFailure = error;
        throw failure;
      }
    });

  const admitContract = (name, wire) => {
    if (typeof name !== 'string' || typeof wire !== 'string' ||
        Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
      fail('InvalidPublicationContractWire');
    }
    let contract;
    try { contract = contractControl.admit(name, wire, contractLimits); }
    catch (error) { fail('InvalidPublicationContract', error); }
    if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
        contract.name !== name || typeof contract.identityField !== 'string' ||
        !cidPattern.test(contract.identity) || typeof contract.wire !== 'string' ||
        Buffer.byteLength(contract.wire, 'utf8') >
          configuration.maxObjectBytes) {
      fail('InvalidPublicationContractControlResult');
    }
    return contract;
  };

  const parseContract = contract => {
    let value;
    try { value = JSON.parse(contract.wire); }
    catch (error) { fail('InvalidPublicationContractControlResult', error); }
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        value[contract.identityField] !== contract.identity) {
      fail('InvalidPublicationContractControlResult');
    }
    return value;
  };

  const putPublicationContract = async (name, suppliedWire) => {
    const contract = admitContract(name, suppliedWire);
    const value = parseContract(contract);
    const semanticCid = contract.identity;
    return Object.freeze({
      value,
      contract,
      ...await putSemantic(contract.wire, semanticCid),
    });
  };

  const readSemanticBytes = async cid => {
    const path = contractPath(cid);
    let handle;
    try { handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW); }
    catch (error) {
      if (error?.code === 'ENOENT') fail('PublicationContractMissing');
      throw error;
    }
    try {
      const before = await handle.stat();
      if (!before.isFile() || before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationContractObject');
      }
      const chunks = [];
      const hash = createHash('sha256');
      let size = 0;
      const stream = handle.createReadStream({autoClose: false});
      for await (const chunk of stream) {
        chunks.push(chunk);
        hash.update(chunk);
        size += chunk.byteLength;
      }
      const after = await handle.stat();
      const physicalCid = `sha256:${hash.digest('hex')}`;
      const physical = await lstat(objectPath(physicalCid));
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || size !== after.size ||
          physical.dev !== after.dev || physical.ino !== after.ino) {
        fail('PublicationContractCorrupt');
      }
      await verifyObject(physicalCid);
      return Buffer.concat(chunks, size);
    } finally {
      await handle.close();
    }
  };

  // Private evidence uses the prepared-object and physical-holding custody
  // already used by Transfer. A semantic alias before a durable owner would
  // strand ciphertext on a crash, so this path never creates one.
  const privateEvidenceAad = (name, semanticCid) => Buffer.from(
    `actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`,
    'utf8',
  );
  const privateEvidenceKey = () => {
    if (configuration.privateEvidenceKey === undefined) {
      fail('PublicationPrivateEvidenceKeyUnavailable');
    }
    return configuration.privateEvidenceKey;
  };
  const privateEvidenceField = (value, bytes) => {
    if (typeof value !== 'string' ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u
          .test(value)) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    const decoded = Buffer.from(value, 'base64');
    if ((bytes !== undefined && decoded.byteLength !== bytes) ||
        decoded.toString('base64') !== value) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    return decoded;
  };
  const readPrivateEvidence = async (name, semanticCid, holdingCid) => {
    active();
    if (typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name)) {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(semanticCid);
    cidHex(holdingCid);
    const key = Buffer.from(privateEvidenceKey());
    try {
      const holding = await inspectPhysicalHolding(holdingCid);
      if (holding?.namespace !== 'publication-private' ||
          holding.manifest_cid !== semanticCid ||
          holding.objects.length !== 1) {
        fail('PublicationPrivateEvidenceUnavailable');
      }
      const chunks = [];
      await consumePhysicalHolding(holdingCid, 0,
        chunk => chunks.push(Buffer.from(chunk)));
      try {
        const bytes = Buffer.concat(chunks);
        let envelope;
        try { envelope = JSON.parse(bytes.toString('utf8')); }
        catch (error) { fail('PublicationPrivateEvidenceCorrupt', error); }
        if (!exactKeys(envelope, ['version', 'nonce', 'tag', 'ciphertext']) ||
            envelope.version !== 'actql-private-publication-evidence/0.1') {
          fail('PublicationPrivateEvidenceCorrupt');
        }
        const nonce = privateEvidenceField(envelope.nonce, 12);
        const tag = privateEvidenceField(envelope.tag, 16);
        const ciphertext = privateEvidenceField(envelope.ciphertext);
        const decipher = createDecipheriv('aes-256-gcm', key, nonce);
        decipher.setAAD(privateEvidenceAad(name, semanticCid));
        decipher.setAuthTag(tag);
        return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (error) {
        if (error?.code === 'PublicationPrivateEvidenceCorrupt') throw error;
        fail('PublicationPrivateEvidenceCorrupt', error);
      }
    } finally {
      key.fill(0);
    }
  };
  const preparePrivateEvidence = async (name, wire, semanticCid) => {
    active();
    if (typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name) ||
        typeof wire !== 'string' ||
        Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(semanticCid);
    const key = privateEvidenceKey();
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, nonce);
    cipher.setAAD(privateEvidenceAad(name, semanticCid));
    const ciphertext = Buffer.concat([
      cipher.update(wire, 'utf8'), cipher.final(),
    ]);
    const envelope = Buffer.from(JSON.stringify({
      version: 'actql-private-publication-evidence/0.1',
      nonce: nonce.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    }), 'utf8');
    if (envelope.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    const writer = createPreparedObjectWriter(envelope.byteLength);
    try {
      await writer.append(envelope);
      const stored = await writer.seal();
      return Object.freeze({
        semanticCid, physicalCid: stored.cid,
        bytes: stored.bytes, prepared: stored.prepared,
      });
    } catch (error) {
      try { await writer.cancel(); }
      catch (cleanupError) {
        error.cleanupFailure = cleanupError;
      }
      throw error;
    }
  };

  const readContract = async (cid, contractName) => {
    const bytes = await readSemanticBytes(cid);
    const wire = bytes.toString('utf8');
    if (contractName === undefined) {
      let value;
      try { value = JSON.parse(wire); }
      catch (error) { fail('InvalidPublicationJsonObject', error); }
      return Object.freeze({wire, value});
    }
    const contract = admitContract(contractName, wire);
    return Object.freeze({wire: contract.wire,
      value: parseContract(contract), contract});
  };

  const readJsonObject = async (cid, contractName) =>
    (await readContract(cid, contractName)).value;

  const verifyDurableResultBinding = async contract => {
    if (contract.name !== 'durable_result_binding') {
      fail('InvalidPublicationCommitEvidence');
    }
    const binding = parseContract(contract);
    if (binding.store_authority_cid !== configuration.storeAuthorityCid ||
        binding.physical_sha256 !== cidHex(binding.material_generation_cid)) {
      fail('PublicationDurableBindingMismatch');
    }
    const physical = await verifyObject(binding.material_generation_cid);
    if (physical.bytes !== binding.byte_count) {
      fail('PublicationDurableBindingMismatch');
    }
    const schemaBytes = await readSemanticBytes(binding.result_schema_cid);
    const schemaCid = `sha256:${createHash('sha256')
      .update(schemaBytes).digest('hex')}`;
    if (schemaCid !== binding.result_schema_cid) {
      fail('PublicationDurableBindingMismatch');
    }
    let schema;
    try { schema = JSON.parse(schemaBytes.toString('utf8')); }
    catch (error) { fail('PublicationDurableBindingMismatch', error); }
    if (schema === null || typeof schema !== 'object' ||
        Array.isArray(schema) || !Array.isArray(binding.result_fields) ||
        binding.result_fields.length !== Object.keys(schema).length ||
        binding.result_fields.some(field =>
          typeof field !== 'string' ||
          !Object.prototype.hasOwnProperty.call(schema, field))) {
      fail('PublicationDurableBindingMismatch');
    }
    return Object.freeze({
      binding,
      physical,
      schema: Object.freeze({
        cid: schemaCid,
        wire: schemaBytes.toString('utf8'),
      }),
    });
  };

  const createAttempt = async suppliedWire => {
    active();
    const admitted = admitContract('publication_attempt', suppliedWire);
    const attempt = parseContract(admitted);
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const stored = await putPublicationContract(
      'publication_attempt', admitted.wire,
    );
    const directory = publicationAttemptPath(
      attempt.publication_attempt_cid,
    );
    await mkdir(directory, {recursive: true, mode: 0o700});
    try {
      await link(contractPath(stored.semanticCid), resolve(directory, 'attempt.json'));
      await syncDirectory(directory);
      await syncDirectory(attemptsDirectory);
      return Object.freeze({attempt, created: true});
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        resolve(directory, 'attempt.json'), configuration.maxObjectBytes,
      );
      if (existing.toString('utf8') !== admitted.wire) {
        fail('PublicationAttemptConflict');
      }
      return Object.freeze({attempt, created: false});
    }
  };

  const latestRecordContract = async attemptCid => {
    active();
    const directory = publicationAttemptPath(attemptCid);
    const entries = await readdir(directory);
    if (entries.some(name => name !== 'attempt.json' &&
        !recordNamePattern.test(name))) {
      fail('InvalidPublicationRecord');
    }
    const names = entries
      .filter(name => recordNamePattern.test(name))
      .map(name => ({name, sequence: Number(name.slice(0, -5))}))
      .filter(value => Number.isSafeInteger(value.sequence))
      .sort((left, right) => left.sequence - right.sequence);
    if (names.length === 0) return undefined;
    for (let index = 0; index < names.length; index++) {
      if (names[index].sequence !== index) fail('PublicationRecordGap');
    }
    const bytes = await readBounded(
      resolve(directory, names.at(-1).name), configuration.maxObjectBytes,
    );
    try {
      return admitContract('publication_record', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidPublicationRecord', error);
    }
  };

  const latestRecord = async attemptCid => {
    const contract = await latestRecordContract(attemptCid);
    return contract === undefined ? undefined : parseContract(contract);
  };

  const appendRecord = async (suppliedWire, options = {}) => {
    active();
    if (!exactKeys(options, ['uncommittedConfirmed']) ||
        typeof options.uncommittedConfirmed !== 'boolean') {
      fail('InvalidPublicationRecordOptions');
    }
    const contract = admitContract('publication_record', suppliedWire);
    const record = parseContract(contract);
    const directory = publicationAttemptPath(
      record.publication_attempt_cid,
    );
    const attempt = (await readContract(
      record.publication_attempt_cid, 'publication_attempt',
    )).value;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const previous = await latestRecordContract(
      record.publication_attempt_cid,
    );
    if (contractControl.recordTransition(
      previous,
      contract,
      options.uncommittedConfirmed,
    ) !== true) {
      fail('InvalidPublicationRecordTransition');
    }
    if (attempt.publication_attempt_cid !== record.publication_attempt_cid) {
      fail('PublicationAttemptMismatch');
    }
    await putPublicationContract('publication_record', contract.wire);
    const target = resolve(directory, `${record.sequence}.json`);
    try { await link(contractPath(record.publication_record_cid), target); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('PublicationRecordConflict');
      throw error;
    }
    await syncDirectory(directory);
    return record;
  };

  const readDeliveryAttemptContract = async attemptCid => {
    const bytes = await readBounded(
      resolve(deliveryAttemptPath(attemptCid), 'attempt.json'),
      configuration.maxObjectBytes,
    );
    try {
      return admitContract('delivery_attempt', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidDeliveryAttempt', error);
    }
  };

  const createDeliveryAttempt = (suppliedWire, suppliedGrantWire) => {
    active();
    const operation = deliveryAdmissionBusy.then(async () => {
      const admitted = admitContract('delivery_attempt', suppliedWire);
      const attempt = parseContract(admitted);
      const grantContract = admitContract(
        'result_read_grant', suppliedGrantWire,
      );
      const grant = parseContract(grantContract);
      if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
        fail('PublicationMetadataDeleted');
      }
      if (attempt.result_read_grant_cid !== grantContract.identity) {
        fail('DeliveryGrantMismatch');
      }
      const target = deliveryAttemptPath(attempt.delivery_attempt_cid);
      try {
        const existing = await readDeliveryAttemptContract(
          attempt.delivery_attempt_cid,
        );
        if (existing.wire !== admitted.wire) {
          fail('DeliveryAttemptConflict');
        }
        return Object.freeze({attempt, created: false});
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }

      let uses = 0;
      for (const name of await readdir(deliveriesDirectory)) {
        if (!/^[0-9a-f]{64}$/u.test(name)) continue;
        const existing = await readDeliveryAttemptContract(
          `sha256:${name}`,
        );
        if (parseContract(existing).result_read_grant_cid ===
            grantContract.identity) {
          uses++;
        }
      }
      if (uses >= grant.max_uses) fail('DeliveryGrantUseLimit');

      await putPublicationContract(
        'result_read_grant', grantContract.wire,
      );
      await putPublicationContract('delivery_attempt', admitted.wire);
      const staging = resolve(
        deliveriesDirectory, `.staging-${randomUUID()}`,
      );
      await mkdir(staging, {mode: 0o700});
      try {
        await link(
          contractPath(admitted.identity),
          resolve(staging, 'attempt.json'),
        );
        await syncDirectory(staging);
        await rename(staging, target);
        await syncDirectory(deliveriesDirectory);
      } catch (error) {
        try { await rm(staging, {recursive: true, force: false}); }
        catch (cleanupError) {
          if (cleanupError?.code !== 'ENOENT') throw cleanupError;
        }
        if (error?.code !== 'EEXIST') throw error;
        const existing = await readDeliveryAttemptContract(
          attempt.delivery_attempt_cid,
        );
        if (existing.wire !== admitted.wire) {
          fail('DeliveryAttemptConflict');
        }
        return Object.freeze({attempt, created: false});
      }
      return Object.freeze({attempt, created: true});
    });
    deliveryAdmissionBusy = operation.catch(() => {});
    return operation;
  };

  const consumeManifestReadGrant = (suppliedWire, attemptId) => {
    active();
    if (typeof attemptId !== 'string' || attemptId.length === 0 ||
        attemptId.length > 256) {
      fail('InvalidManifestReadAttempt');
    }
    const operation = manifestReadAdmissionBusy.then(async () => {
      const admitted = admitContract('manifest_read_grant', suppliedWire);
      const grant = parseContract(admitted);
      if (await runMetadataDeletionStarted(grant.run_definition_cid)) {
        fail('PublicationMetadataDeleted');
      }
      await putPublicationContract('manifest_read_grant', admitted.wire);
      const directory = manifestReadGrantPath(admitted.identity);
      let createdDirectory = false;
      try {
        await mkdir(directory, {mode: 0o700});
        createdDirectory = true;
      } catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        if (!(await lstat(directory)).isDirectory()) {
          fail('InvalidManifestReadStore');
        }
      }
      if (createdDirectory) await syncDirectory(manifestReadsDirectory);
      const attemptDigest = createHash('sha256')
        .update(attemptId, 'utf8').digest('hex');
      const target = resolve(directory, `${attemptDigest}.json`);
      const value = Object.freeze({
        manifestReadGrantCid: admitted.identity,
        attemptId,
      });
      const bytes = Buffer.from(JSON.stringify(value), 'utf8');
      try {
        const existing = await readBounded(
          target, configuration.maxObjectBytes,
        );
        if (!existing.equals(bytes)) fail('ManifestReadAttemptConflict');
        return Object.freeze({grant, created: false, idempotent: true});
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
      const uses = (await readdir(directory)).filter(name =>
        /^[0-9a-f]{64}\.json$/u.test(name)).length;
      if (uses >= grant.max_uses) fail('ManifestReadGrantUseLimit');
      const staging = resolve(directory, `.staging-${randomUUID()}`);
      try {
        await writeExclusive(staging, bytes);
        await rename(staging, target);
        await syncDirectory(directory);
      } catch (error) {
        try { await unlink(staging); }
        catch (cleanupError) {
          if (cleanupError?.code !== 'ENOENT') throw cleanupError;
        }
        throw error;
      }
      return Object.freeze({grant, created: true, idempotent: false});
    });
    manifestReadAdmissionBusy = operation.catch(() => {});
    return operation;
  };

  const latestDeliveryRecordContract = async attemptCid => {
    active();
    const directory = deliveryAttemptPath(attemptCid);
    const entries = await readdir(directory);
    if (entries.some(name => name !== 'attempt.json' &&
        !recordNamePattern.test(name))) {
      fail('InvalidDeliveryRecord');
    }
    const names = entries
      .filter(name => recordNamePattern.test(name))
      .map(name => ({name, sequence: Number(name.slice(0, -5))}))
      .filter(value => Number.isSafeInteger(value.sequence))
      .sort((left, right) => left.sequence - right.sequence);
    if (names.length === 0) return undefined;
    for (let index = 0; index < names.length; index++) {
      if (names[index].sequence !== index) fail('DeliveryRecordGap');
    }
    const bytes = await readBounded(
      resolve(directory, names.at(-1).name), configuration.maxObjectBytes,
    );
    try {
      return admitContract('delivery_record', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidDeliveryRecord', error);
    }
  };

  const latestDeliveryRecord = async attemptCid => {
    const contract = await latestDeliveryRecordContract(attemptCid);
    return contract === undefined ? undefined : parseContract(contract);
  };

  const lookupDeliveryAttempt = async query => {
    active();
    if (!exactKeys(query, [
      'indexKey', 'principalId', 'purpose', 'resultName', 'attemptId',
    ]) || !exactKeys(query.indexKey, [
      'tenantId', 'authorityScopeCid', 'runDefinitionCid',
    ]) || typeof query.indexKey.tenantId !== 'string' ||
        query.indexKey.tenantId.length === 0 ||
        !cidPattern.test(query.indexKey.authorityScopeCid) ||
        !cidPattern.test(query.indexKey.runDefinitionCid) ||
        typeof query.principalId !== 'string' || !query.principalId ||
        typeof query.purpose !== 'string' || !query.purpose ||
        typeof query.resultName !== 'string' || !query.resultName ||
        typeof query.attemptId !== 'string' || !query.attemptId ||
        query.attemptId.length > 256) {
      fail('InvalidDeliveryAttemptLookup');
    }
    let match;
    for (const name of await readdir(deliveriesDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) continue;
      const attempt = parseContract(await readDeliveryAttemptContract(
        `sha256:${name}`,
      ));
      if (attempt.attempt_id !== query.attemptId ||
          attempt.run_definition_cid !== query.indexKey.runDefinitionCid ||
          attempt.result_name !== query.resultName) continue;
      const grant = (await readContract(
        attempt.result_read_grant_cid, 'result_read_grant',
      )).value;
      if (grant.tenant_id !== query.indexKey.tenantId ||
          grant.authority_scope_cid !== query.indexKey.authorityScopeCid ||
          grant.principal_id !== query.principalId ||
          grant.purpose !== query.purpose ||
          grant.run_definition_cid !== query.indexKey.runDefinitionCid ||
          grant.result_manifest_cid !== attempt.result_manifest_cid) continue;
      if (match !== undefined) fail('AmbiguousDeliveryAttemptLookup');
      const record = await latestDeliveryRecord(attempt.delivery_attempt_cid);
      const hostReleaseReceipt = record?.result_delivery_receipt_cid ===
        undefined ? undefined : (await readContract(
          record.result_delivery_receipt_cid,
          'result_delivery_receipt',
        )).value;
      match = Object.freeze({attempt, record, hostReleaseReceipt});
    }
    return match;
  };

  const confirmDeliveryRecord = async suppliedWire => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    const record = parseContract(contract);
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const target = resolve(directory, `${record.sequence}.json`);
    let installed;
    try {
      const bytes = await readBounded(target, configuration.maxObjectBytes);
      installed = admitContract(
        'delivery_record', bytes.toString('utf8'),
      );
    } catch (error) {
      if (error?.code === 'ENOENT') {
        fail('DeliveryRecordMissing', error);
      }
      throw error;
    }
    if (installed.identity !== contract.identity ||
        installed.wire !== contract.wire) {
      fail('DeliveryRecordConflict');
    }
    // A directory entry may be visible before its containing directory is
    // durable. Re-sync the exact immutable record, then verify that the same
    // record remains installed before acknowledging it.
    await syncDirectory(directory);
    const confirmed = await readBounded(
      target, configuration.maxObjectBytes,
    );
    const admitted = admitContract(
      'delivery_record', confirmed.toString('utf8'),
    );
    if (admitted.identity !== contract.identity ||
        admitted.wire !== contract.wire) {
      fail('DeliveryRecordDurabilityMismatch');
    }
    return record;
  };

  const appendDeliveryRecord = async suppliedWire => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    const record = parseContract(contract);
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const attempt = parseContract(await readDeliveryAttemptContract(
      record.delivery_attempt_cid,
    ));
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const previous = await latestDeliveryRecordContract(
      record.delivery_attempt_cid,
    );
    if (previous?.identity === contract.identity) {
      return confirmDeliveryRecord(contract.wire);
    }
    if (contractControl.deliveryTransition(previous, contract) !== true) {
      fail('InvalidDeliveryRecordTransition');
    }
    if (attempt.delivery_attempt_cid !== record.delivery_attempt_cid) {
      fail('DeliveryAttemptMismatch');
    }
    if (record.state === 'succeeded') {
      const receipt = (await readContract(
        record.result_delivery_receipt_cid,
        'result_delivery_receipt',
      )).contract;
      const attemptContract = await readDeliveryAttemptContract(
        record.delivery_attempt_cid,
      );
      if (contractControl.deliverySuccessValid(
        attemptContract, receipt, contract,
      ) !== true) {
        fail('InvalidDeliverySuccessEvidence');
      }
    }
    await putPublicationContract('delivery_record', contract.wire);
    const target = resolve(directory, `${record.sequence}.json`);
    try { await link(contractPath(record.delivery_record_cid), target); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('DeliveryRecordConflict');
      throw error;
    }
    return confirmDeliveryRecord(contract.wire);
  };

  const inspectCommittedIndexRaw = async key => {
    active();
    const path = resolve(indexesDirectory, `${indexKey(key)}.json`);
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    const admitted = admitContract(
      'public_index_entry', bytes.toString('utf8'),
    );
    const entry = parseContract(admitted);
    if (entry.tenant_id !== key.tenantId ||
        entry.authority_scope_cid !== key.authorityScopeCid ||
        entry.run_definition_cid !== key.runDefinitionCid) {
      fail('PublicIndexBindingMismatch');
    }
    await readJsonObject(entry.public_index_entry_cid, 'public_index_entry');
    return entry;
  };

  const inspectCommittedIndex = async key => {
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) return undefined;
    return inspectCommittedIndexRaw(key);
  };

  const confirmCommittedIndex = async key => {
    active();
    const entry = await inspectCommittedIndex(key);
    if (entry === undefined) return undefined;
    const keyHash = indexKey(key);
    const durableCid = durablyConfirmedIndexes.get(keyHash);
    if (durableCid !== undefined &&
        durableCid !== entry.public_index_entry_cid) {
      fail('PublicIndexDurabilityMismatch');
    }
    if (durableCid === undefined) {
      // Visibility is not durability. Synchronize the exact containing
      // directory and then ensure that the same immutable entry is still
      // installed before reporting a durable commit.
      await syncDirectory(indexesDirectory);
      const confirmed = await inspectCommittedIndex(key);
      if (confirmed?.public_index_entry_cid !==
          entry.public_index_entry_cid) {
        fail('PublicIndexDurabilityMismatch');
      }
      durablyConfirmedIndexes.set(keyHash, entry.public_index_entry_cid);
    }
    return entry;
  };

  const lookupCommittedIndex = async (key, authorize) => {
    active();
    if (typeof authorize !== 'function' || authorize(Object.freeze({...key})) !== true) {
      fail('PublicationLookupDenied');
    }
    const entry = await confirmCommittedIndex(key);
    if (entry === undefined || authorize(Object.freeze({...key, entry})) !== true) {
      // Missing and unauthorized entries deliberately share one external code.
      fail('PublicationLookupDenied');
    }
    return entry;
  };

  const readResultRetentionExtension = async (
    keyHash,
    resultDefinitionCid,
  ) => {
    const directory = retentionExtensionResultDirectory(
      keyHash, resultDefinitionCid,
    );
    let names;
    try { names = await readdir(directory); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
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
    let previous;
    for (let index = 0; index < records.length; index++) {
      if (records[index].sequence !== index) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      const bytes = await readBounded(
        resolve(directory, records[index].name),
        configuration.maxObjectBytes,
      );
      let value;
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
          !cidPattern.test(value.public_index_entry_cid) ||
          value.result_definition_cid !== resultDefinitionCid ||
          !cidPattern.test(value.base_retention_policy_cid) ||
          (value.prior_extension_policy_cid !== null &&
            !cidPattern.test(value.prior_extension_policy_cid)) ||
          !cidPattern.test(value.extension_retention_policy_cid) ||
          !timestampPattern.test(value.admitted_at) ||
          value.prior_extension_policy_cid !==
            (previous?.extension_retention_policy_cid ?? null)) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      previous = Object.freeze(value);
    }
    return previous;
  };

  const readResultDeletion = async (keyHash, resultDefinitionCid) => {
    const path = resultDeletionPath(keyHash, resultDefinitionCid);
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationDeletionStore', error); }
    if (!exactKeys(value, [
      'version', 'public_index_entry_cid', 'result_definition_cid',
      'material_generation_cid',
    ]) || value.version !== 'actql-local-result-deletion/0.1' ||
        !cidPattern.test(value.public_index_entry_cid) ||
        value.result_definition_cid !== resultDefinitionCid ||
        !cidPattern.test(value.material_generation_cid)) {
      fail('InvalidPublicationDeletionStore');
    }
    return Object.freeze(value);
  };

  const requireCommittedResultBinding = async (
    key,
    resultDefinitionCid,
  ) => {
    cidHex(resultDefinitionCid);
    const entry = await confirmCommittedIndex(key);
    if (entry === undefined) fail('PublicationLookupDenied');
    const matches = [];
    for (const bindingCid of entry.durable_result_binding_cids) {
      const contract = (await readContract(
        bindingCid, 'durable_result_binding',
      )).contract;
      const value = parseContract(contract);
      if (value.result_definition_cid === resultDefinitionCid) {
        matches.push({contract, value});
      }
    }
    if (matches.length !== 1) fail('PublicationLookupDenied');
    return Object.freeze({entry, ...matches[0]});
  };

  const requireResultNotDeleted = async (
    keyHash,
    selected,
    resultDefinitionCid,
  ) => {
    const deletion = await readResultDeletion(
      keyHash, resultDefinitionCid,
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

  const verifyCommitEvidence = async (
    admitted,
    entry,
    suppliedEvidence,
    required,
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
      const persisted = await readSemanticBytes(contract.identity);
      if (!persisted.equals(Buffer.from(contract.wire, 'utf8'))) {
        fail('PublicationCommitEvidenceMismatch');
      }
    }
    const boundPhysicalCids = [];
    for (const contract of suppliedEvidence.durableBindings) {
      const verified = await verifyDurableResultBinding(contract);
      boundPhysicalCids.push(verified.binding.material_generation_cid);
    }
    const attemptStored = await readContract(
      entry.publication_attempt_cid, 'publication_attempt',
    );
    const attempt = attemptStored.value;
    const requestStored = await readContract(
      entry.publication_request_cid, 'publication_request',
    );
    if (attempt.publication_request_cid !== entry.publication_request_cid ||
        attempt.run_definition_cid !== entry.run_definition_cid) {
      fail('PublicationAttemptMismatch');
    }
    let chainValid = false;
    try {
      chainValid = contractControl.effectFreeCommitValid(
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
        contractLimits,
      );
    } catch (error) {
      fail('InvalidPublicationCommitChain', error);
    }
    if (chainValid !== true) fail('InvalidPublicationCommitChain');
    return boundPhysicalCids;
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
      tenantId: entry.tenant_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    };
    const committed = await confirmCommittedIndex(key);
    if (committed?.public_index_entry_cid !== admitted.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const boundPhysicalCids = await verifyCommitEvidence(
      admitted, entry, suppliedEvidence, undefined,
    );
    await adoptPreparedObjects(boundPhysicalCids);
    return true;
  };

  const commitIndexInternal = async (
    suppliedWire,
    requiredObjectCids,
    suppliedEvidence,
  ) => {
    active();
    const admitted = admitContract('public_index_entry', suppliedWire);
    const entry = parseContract(admitted);
    const key = {
      tenantId: entry.tenant_id,
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
    for (const cid of required) await readSemanticBytes(cid);
    const boundPhysicalCids = await verifyCommitEvidence(
      admitted, entry, suppliedEvidence, required,
    );
    const inventorySemanticCids = Object.freeze([...new Set([
      ...requiredObjectCids,
      admitted.identity,
      ...suppliedEvidence.durableBindings.map(contract =>
        parseContract(contract).result_schema_cid),
    ])].sort());
    const previous = await latestRecordContract(entry.publication_attempt_cid);
    if (previous === undefined ||
        contractControl.recordAllowsCommit(previous) !== true) {
      fail('PublicationAttemptNotCommitting');
    }
    const existingCommit = await confirmCommittedIndex(key);
    if (existingCommit !== undefined) {
      if (existingCommit.invocation_cid !== entry.invocation_cid ||
          existingCommit.result_manifest_cid !== entry.result_manifest_cid ||
          existingCommit.publication_request_cid !==
            entry.publication_request_cid) {
        fail('PublicationCommitConflict');
      }
      const inventory = await readMetadataInventory(
        existingCommit.public_index_entry_cid,
      );
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
        const binding = (await readContract(
          bindingCid, 'durable_result_binding',
        )).value;
        directlyRequired.push(binding.result_schema_cid);
      }
      if (inventory === undefined ||
          inventory.public_index_entry_cid !==
            existingCommit.public_index_entry_cid ||
          directlyRequired.some(cid =>
            !inventory.contract_objects.some(object =>
              object.semantic_cid === cid))) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      await adoptPreparedObjects(boundPhysicalCids);
      await adoptPreparedSchemas(
        inventorySemanticCids, entry.run_definition_cid,
      );
      return Object.freeze({
        entry: existingCommit,
        committed: false,
        idempotent: true,
      });
    }
    await putPublicationContract('public_index_entry', admitted.wire);
    const inventoryContractObjects = await bindMetadataContractObjects(
      inventorySemanticCids,
    );
    await ensureMetadataInventory(Object.freeze({
      version: 'actql-local-publication-metadata-inventory/0.1',
      tenant_id: entry.tenant_id,
      authority_scope_cid: entry.authority_scope_cid,
      run_definition_cid: entry.run_definition_cid,
      public_index_entry_cid: admitted.identity,
      publication_attempt_cid: entry.publication_attempt_cid,
      contract_objects: inventoryContractObjects,
    }));
    const target = resolve(indexesDirectory, `${keyHash}.json`);
    const custody = beginPreparedCommit(
      boundPhysicalCids, key, entry.public_index_entry_cid,
    );
    let installed = false;
    try {
      await link(contractPath(entry.public_index_entry_cid), target);
      installed = true;
      await syncDirectory(indexesDirectory);
      durablyConfirmedIndexes.set(
        keyHash, entry.public_index_entry_cid,
      );
      await adoptPreparedObjects(boundPhysicalCids);
      await adoptPreparedSchemas(
        inventorySemanticCids, entry.run_definition_cid,
      );
      return Object.freeze({entry, committed: true, idempotent: false});
    } catch (error) {
      let existing;
      try { existing = await confirmCommittedIndex(key); }
      catch (reconciliation) {
        throw commitCustodyFailure(error, custody, reconciliation);
      }
      if (existing === undefined) {
        await custody.resolveConfirmed(undefined);
        throw error;
      }
      if (existing.invocation_cid !== entry.invocation_cid ||
          existing.result_manifest_cid !== entry.result_manifest_cid ||
          existing.publication_request_cid !== entry.publication_request_cid) {
        await custody.resolveConfirmed(existing);
        fail('PublicationCommitConflict');
      }
      try { await adoptPreparedObjects(boundPhysicalCids); }
      catch (reconciliation) {
        throw commitCustodyFailure(error, custody, reconciliation);
      }
      await adoptPreparedSchemas(
        inventorySemanticCids, entry.run_definition_cid,
      );
      return Object.freeze({
        entry: existing,
        committed: installed,
        idempotent: !installed,
      });
    }
  };

  // A prepared schema cannot be retired between commit evidence validation
  // and installation of the inventory that acquires its durable ownership.
  const commitIndex = (...args) =>
    withSemanticCommit(() => commitIndexInternal(...args));

  const consumeObject = async (cid, accept) => {
    active();
    if (typeof accept !== 'function') fail('InvalidPublicationObjectConsumer');
    const path = objectPath(cid);
    const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const hash = createHash('sha256');
    let bytes = 0;
    try {
      const before = await handle.stat();
      if (!before.isFile() || before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationStoreObject');
      }
      const stream = handle.createReadStream({autoClose: false});
      for await (const chunk of stream) {
        hash.update(chunk);
        await accept(chunk);
        bytes += chunk.byteLength;
      }
      const after = await handle.stat();
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || bytes !== after.size ||
          hash.digest('hex') !== cidHex(cid)) {
        fail('PublicationObjectCorrupt');
      }
      return Object.freeze({cid, bytes});
    } finally {
      await handle.close();
    }
  };

  const withCommittedResult = async (
    key,
    resultDefinitionCid,
    authorize,
    use,
  ) => {
    active();
    cidHex(resultDefinitionCid);
    if (typeof authorize !== 'function' || typeof use !== 'function') {
      fail('InvalidPublicationObjectConsumer');
    }
    const request = Object.freeze({...key, resultDefinitionCid});
    if (authorize(request) !== true) fail('PublicationLookupDenied');
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid,
    );
    const keyHash = indexKey(key);
    await requireResultNotDeleted(
      keyHash, selected, resultDefinitionCid,
    );
    const authorization = Object.freeze({
      ...request,
      durableResultBindingCid: selected.contract.identity,
      logicalResultCid: selected.value.logical_result_cid,
      resultSchemaCid: selected.value.result_schema_cid,
    });
    if (authorize(authorization) !== true) fail('PublicationLookupDenied');
    const materialCid = selected.value.material_generation_cid;
    activeResultReaders.set(
      materialCid, (activeResultReaders.get(materialCid) ?? 0) + 1,
    );
    try {
      const verified = await verifyDurableResultBinding(selected.contract);
      await requireResultNotDeleted(
        keyHash, selected, resultDefinitionCid,
      );
      const metadata = Object.freeze({
        durableResultBindingCid: selected.contract.identity,
        logicalResultCid: verified.binding.logical_result_cid,
        resultSchemaCid: verified.binding.result_schema_cid,
        resultSchemaWire: verified.schema.wire,
        resultFields: Object.freeze([...verified.binding.result_fields]),
        rowCount: verified.binding.row_count,
        payloadBytes: verified.physical.bytes,
      });
      let scopeOpen = true;
      let consumed = false;
      const consume = async accept => {
        if (!scopeOpen || consumed || typeof accept !== 'function') {
          fail('InvalidPublicationObjectConsumer');
        }
        consumed = true;
        return consumeObject(materialCid, accept);
      };
      try { return await use(metadata, consume); }
      finally { scopeOpen = false; }
    } finally {
      const remaining = (activeResultReaders.get(materialCid) ?? 1) - 1;
      if (remaining === 0) activeResultReaders.delete(materialCid);
      else activeResultReaders.set(materialCid, remaining);
    }
  };

  const consumeCommittedResult = async (
    key,
    resultDefinitionCid,
    authorize,
    accept,
  ) => withCommittedResult(
    key,
    resultDefinitionCid,
    authorize,
    async (metadata, consume) => {
      const consumed = await consume(accept);
      return Object.freeze({
        durableResultBindingCid: metadata.durableResultBindingCid,
        logicalResultCid: metadata.logicalResultCid,
        resultSchemaCid: metadata.resultSchemaCid,
        resultSchemaWire: metadata.resultSchemaWire,
        resultFields: metadata.resultFields,
        rowCount: metadata.rowCount,
        bytes: consumed.bytes,
      });
    },
  );

  const withCommittedResultRows = async (
    key,
    resultDefinitionCid,
    authorize,
    frameLimits,
    use,
    frameControl,
  ) => {
    if (!exactKeys(frameLimits, [
      'maxRowBytes', 'maxDepth', 'maxFrameBytes',
    ]) || !Object.values(frameLimits).every(quantity) ||
        typeof use !== 'function' || frameControl === null ||
        typeof frameControl !== 'object' ||
        typeof frameControl.prepareDurableResultRowFrames !== 'function' ||
        typeof frameControl.feedDurableResultRowFrames !== 'function' ||
        typeof frameControl.finishDurableResultRowFrames !== 'function' ||
        typeof frameControl.cancelDurableResultRowFrames !== 'function') {
      fail('InvalidPublicationRowConsumer');
    }
    return withCommittedResult(
      key,
      resultDefinitionCid,
      authorize,
      async (metadata, consume) => {
        let scopeOpen = true;
        let rowsConsumed = false;
        const readRows = async accept => {
          if (!scopeOpen || rowsConsumed || typeof accept !== 'function') {
            fail('InvalidPublicationRowConsumer');
          }
          rowsConsumed = true;
          const frames = frameControl.prepareDurableResultRowFrames({
            maxBytes: metadata.payloadBytes,
            maxRows: metadata.rowCount,
            maxRowBytes: frameLimits.maxRowBytes,
            maxDepth: frameLimits.maxDepth,
            maxFrameBytes: frameLimits.maxFrameBytes,
          });
          let rowIndex = 0;
          try {
            const physical = await consume(async chunk => {
              const rows = frameControl.feedDurableResultRowFrames(
                frames, chunk,
              );
              for (const row of rows) {
                await accept(row, rowIndex);
                rowIndex++;
              }
            });
            const summary = frameControl.finishDurableResultRowFrames(frames);
            if (summary.rows !== metadata.rowCount ||
                summary.bytes !== physical.bytes) {
              fail('PublicationDurableBindingMismatch');
            }
            return summary;
          } catch (error) {
            frameControl.cancelDurableResultRowFrames(frames);
            throw error;
          }
        };
        try { return await use(metadata, readRows); }
        finally { scopeOpen = false; }
      },
    );
  };

  const readCommittedResultRetentionExtension = async (
    key,
    resultDefinitionCid,
  ) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid,
    );
    const keyHash = indexKey(key);
    await requireResultNotDeleted(
      keyHash, selected, resultDefinitionCid,
    );
    const record = await readResultRetentionExtension(
      keyHash, resultDefinitionCid,
    );
    if (record === undefined) return undefined;
    if (record.public_index_entry_cid !==
        selected.entry.public_index_entry_cid ||
        record.base_retention_policy_cid !==
          selected.value.effective_retention_policy_cid) {
      fail('InvalidPublicationRetentionExtensionStore');
    }
    const extension = await readContract(
      record.extension_retention_policy_cid,
      'result_retention_policy',
    );
    return Object.freeze({record, extension: extension.contract});
  };

  const putCommittedResultRetentionExtension = async (
    key,
    resultDefinitionCid,
    expectedPriorExtensionCid,
    extension,
    admittedAt,
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
    const operation = materialRetentionBusy.then(async () => {
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
        return Object.freeze({record: current, extension, idempotent: true});
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
        if (error?.code !== 'EEXIST' ||
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
        if (error?.code !== 'EEXIST' ||
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
        if (error?.code !== 'EEXIST') throw error;
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
    materialRetentionBusy = operation.catch(() => {});
    return operation;
  };

  const collectRunMetadataContracts = async (
    runDefinitionCid,
    keyHash,
    initial,
  ) => {
    const collected = new Set(initial);
    for (const name of await readdir(attemptsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidPublicationAttemptStore');
      }
      const attemptCid = `sha256:${name}`;
      const attempt = await readContract(attemptCid, 'publication_attempt');
      if (attempt.value.run_definition_cid !== runDefinitionCid) continue;
      collected.add(attemptCid);
      collected.add(attempt.value.publication_request_cid);
      const directory = publicationAttemptPath(attemptCid);
      for (const recordName of await readdir(directory)) {
        if (recordName === 'attempt.json') continue;
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidPublicationRecord');
        }
        const record = admitContract(
          'publication_record',
          (await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'),
        );
        collected.add(record.identity);
      }
    }
    for (const name of await readdir(deliveriesDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidDeliveryAttemptStore');
      }
      const attemptCid = `sha256:${name}`;
      const attempt = await readDeliveryAttemptContract(attemptCid);
      const value = parseContract(attempt);
      if (value.run_definition_cid !== runDefinitionCid) continue;
      collected.add(attemptCid);
      collected.add(value.result_read_grant_cid);
      const directory = deliveryAttemptPath(attemptCid);
      for (const recordName of await readdir(directory)) {
        if (recordName === 'attempt.json') continue;
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidDeliveryRecord');
        }
        const record = admitContract(
          'delivery_record',
          (await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'),
        );
        const recordValue = parseContract(record);
        collected.add(record.identity);
        if (recordValue.result_delivery_receipt_cid !== undefined) {
          collected.add(recordValue.result_delivery_receipt_cid);
        }
      }
    }
    for (const name of await readdir(manifestReadsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidManifestReadStore');
      }
      const grantCid = `sha256:${name}`;
      const grant = await readContract(grantCid, 'manifest_read_grant');
      if (grant.value.run_definition_cid === runDefinitionCid) {
        collected.add(grantCid);
      }
    }
    const extensionRoot = retentionExtensionDirectory(keyHash);
    let resultDirectories = [];
    try { resultDirectories = await readdir(extensionRoot); }
    catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
    for (const resultName of resultDirectories) {
      if (!/^[0-9a-f]{64}$/u.test(resultName)) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      const directory = resolve(extensionRoot, resultName);
      for (const recordName of await readdir(directory)) {
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidPublicationRetentionExtensionStore');
        }
        let record;
        try {
          record = JSON.parse((await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'));
        } catch (error) {
          fail('InvalidPublicationRetentionExtensionStore', error);
        }
        if (!cidPattern.test(record?.extension_retention_policy_cid)) {
          fail('InvalidPublicationRetentionExtensionStore');
        }
        collected.add(record.extension_retention_policy_cid);
      }
    }
    return Object.freeze([...collected].sort());
  };

  const bindMetadataContractObjects = async contractCids => {
    const objects = [];
    for (const semanticCid of contractCids) {
      const bytes = await readSemanticBytes(semanticCid);
      const physicalCid = `sha256:${createHash('sha256')
        .update(bytes).digest('hex')}`;
      const physical = await verifyObject(physicalCid);
      if (physical.bytes !== bytes.byteLength) {
        fail('PublicationContractCorrupt');
      }
      objects.push(Object.freeze({
        semantic_cid: semanticCid,
        physical_cid: physicalCid,
        byte_count: physical.bytes,
      }));
    }
    return Object.freeze(objects);
  };

  const metadataResultBindings = async entry => {
    const results = [];
    for (const bindingCid of entry.durable_result_binding_cids) {
      const binding = parseContract((await readContract(
        bindingCid, 'durable_result_binding',
      )).contract);
      if (!quantity(binding.byte_count)) {
        fail('InvalidPublicationDurableBinding');
      }
      results.push(Object.freeze({
        result_definition_cid: binding.result_definition_cid,
        material_generation_cid: binding.material_generation_cid,
        byte_count: binding.byte_count,
      }));
    }
    return Object.freeze(results.sort((left, right) =>
      left.result_definition_cid.localeCompare(right.result_definition_cid)));
  };

  const removeRunMetadataDirectories = async (
    runDefinitionCid,
    keyHash,
  ) => {
    for (const name of await readdir(attemptsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidPublicationAttemptStore');
      }
      const attempt = await readContract(
        `sha256:${name}`, 'publication_attempt',
      );
      if (attempt.value.run_definition_cid === runDefinitionCid) {
        await rm(resolve(attemptsDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(attemptsDirectory);
    for (const name of await readdir(deliveriesDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidDeliveryAttemptStore');
      }
      const attempt = await readDeliveryAttemptContract(`sha256:${name}`);
      if (parseContract(attempt).run_definition_cid === runDefinitionCid) {
        await rm(resolve(deliveriesDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(deliveriesDirectory);
    for (const name of await readdir(manifestReadsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidManifestReadStore');
      }
      const grant = await readContract(
        `sha256:${name}`, 'manifest_read_grant',
      );
      if (grant.value.run_definition_cid === runDefinitionCid) {
        await rm(resolve(manifestReadsDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(manifestReadsDirectory);
    try {
      await rm(retentionExtensionDirectory(keyHash), {
        recursive: true, force: false,
      });
      await syncDirectory(retentionExtensionsDirectory);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  };

  const metadataContractHasLiveReference = async (
    semanticCid,
    excludedPublicIndexEntryCid,
  ) => {
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      );
      const keyHash = indexKey({
        tenantId: inventory.tenant_id,
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

  const reclaimMetadataContractInternal = async (
    excludedPublicIndexEntryCid,
    object,
    unconfirmedObjects,
  ) => {
    if (preparedSchemas.get(object.semantic_cid)?.holders.size > 0 ||
        await metadataContractHasLiveReference(
      object.semantic_cid, excludedPublicIndexEntryCid,
    )) return;
    const semanticPath = contractPath(object.semantic_cid);
    let semanticState;
    try { semanticState = await lstat(semanticPath); }
    catch (error) {
      if (error?.code !== 'ENOENT') throw error;
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
      if (error?.code !== 'ENOENT') throw error;
    }
    if (physicalState === undefined) return;
    if (!physicalState.isFile() ||
        physicalState.size !== object.byte_count) {
      fail('InvalidPublicationStoreObject');
    }
    if (physicalState.nlink > 1) return;
    await unlink(objectPath(object.physical_cid));
    unconfirmedObjects.set(object.physical_cid, object.byte_count);
    await syncDirectory(objectsDirectory);
    if (unconfirmedObjects.delete(object.physical_cid)) {
      storedBytes -= object.byte_count;
      objectCount--;
    }
  };

  const reclaimMetadataContract = (...args) =>
    withSemanticCommit(() => reclaimMetadataContractInternal(...args));

  const materialHasLiveReference = async materialCid => {
    for (const name of await readdir(physicalHoldingsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      const holding = await readPhysicalHoldingAt(
        resolve(physicalHoldingsDirectory, name),
      );
      if (holding.objects.some(object => object.cid === materialCid)) {
        return true;
      }
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
      const entry = parseContract(indexContract);
      for (const bindingCid of entry.durable_result_binding_cids) {
        const binding = parseContract((await readContract(
          bindingCid, 'durable_result_binding',
        )).contract);
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

  const admitPhysicalHolding = value => {
    if (!exactKeys(value, [
      'version', 'namespace', 'holding_cid', 'manifest_cid', 'objects',
    ]) || !Array.isArray(value.objects) ||
        value.objects.some(object => !exactKeys(object, [
          'cid', 'byte_count',
        ]))) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const record = {
      version: value.version,
      namespace: value.namespace,
      holding_cid: value.holding_cid,
      manifest_cid: value.manifest_cid,
      objects: value.objects.map(object => ({
        cid: object?.cid,
        byte_count: object?.byte_count,
      })),
    };
    const bytes = Buffer.from(JSON.stringify(record), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    return Object.freeze({
      record: parsePhysicalHolding(bytes),
      bytes,
    });
  };

  const verifyPhysicalHoldingObjects = async record => {
    const verified = new Map();
    for (const object of record.objects) {
      if (verified.has(object.cid)) continue;
      const physical = await verifyObject(object.cid);
      if (physical.bytes !== object.byte_count) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      verified.set(object.cid, physical);
    }
    return verified;
  };

  const commitPhysicalHolding = async (value, prepared) => {
    active();
    const admitted = admitPhysicalHolding(value);
    const record = admitted.record;
    if (await readPhysicalHoldingDeletion(record.holding_cid) !== undefined) {
      fail('PublicationPhysicalHoldingRetiring');
    }
    const current = await readPhysicalHolding(record.holding_cid);
    if (current !== undefined) {
      if (!Buffer.from(JSON.stringify(current), 'utf8').equals(
        admitted.bytes,
      )) {
        fail('PublicationPhysicalHoldingConflict');
      }
      await verifyPhysicalHoldingObjects(current);
      await syncDirectory(physicalHoldingsDirectory);
      await adoptPreparedObjects([...new Set(
        current.objects.map(object => object.cid),
      )]);
      return Object.freeze({record: current, created: false});
    }
    if (!Array.isArray(prepared)) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const expected = new Map();
    for (const object of record.objects) {
      if (!expected.has(object.cid)) {
        expected.set(object.cid, object.byte_count);
      }
    }
    const supplied = new Map();
    for (const handle of prepared) {
      const owner = preparedObjectOwners.get(handle);
      if (owner === undefined || supplied.has(owner.cid) ||
          handle.status().pending !== true) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
      supplied.set(owner.cid, owner.bytes);
    }
    if (supplied.size !== expected.size) {
      fail('InvalidPublicationPhysicalHoldingOwner');
    }
    for (const [cid, bytes] of expected) {
      if (supplied.get(cid) !== bytes) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
    }
    await verifyPhysicalHoldingObjects(record);
    try {
      await writeExclusive(
        physicalHoldingPath(record.holding_cid),
        admitted.bytes,
      );
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const installed = await readBounded(
        physicalHoldingPath(record.holding_cid),
        configuration.maxObjectBytes,
      );
      if (!installed.equals(admitted.bytes)) {
        fail('PublicationPhysicalHoldingConflict');
      }
    }
    await syncDirectory(physicalHoldingsDirectory);
    await adoptPreparedObjects([...expected.keys()]);
    return Object.freeze({record, created: true});
  };

  // Reconcile a private holding by exact admitted wire, then confirm its
  // directory durability. A visible link alone is not a committed holding.
  const confirmPrivateEvidence = async binding => {
    active();
    if (!exactKeys(binding, [
      'name', 'semanticCid', 'holdingCid', 'wire',
    ]) || binding.name !== 'effect_preview' ||
        typeof binding.wire !== 'string') {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(binding.semanticCid);
    cidHex(binding.holdingCid);
    const record = await inspectPhysicalHolding(binding.holdingCid);
    if (record === undefined) return undefined;
    if (record.namespace !== 'publication-private' ||
        record.manifest_cid !== binding.semanticCid ||
        record.objects.length !== 1) {
      fail('PublicationPrivateEvidenceUnavailable');
    }
    const stored = await readPrivateEvidence(
      binding.name, binding.semanticCid, binding.holdingCid,
    );
    if (!stored.equals(Buffer.from(binding.wire, 'utf8'))) {
      fail('PublicationPrivateEvidenceConflict');
    }
    await commitPhysicalHolding(record, []);
    return record;
  };

  const sharePhysicalHolding = async (sourceHoldingCid, value) => {
    active();
    cidHex(sourceHoldingCid);
    const admitted = admitPhysicalHolding(value);
    const record = admitted.record;
    if (sourceHoldingCid === record.holding_cid) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const operation = materialRetentionBusy.then(async () => {
      if (await readPhysicalHoldingDeletion(sourceHoldingCid) !== undefined ||
          await readPhysicalHoldingDeletion(record.holding_cid) !== undefined) {
        fail('PublicationPhysicalHoldingRetiring');
      }
      const source = await readPhysicalHolding(sourceHoldingCid);
      if (source === undefined) {
        fail('PublicationPhysicalHoldingUnavailable');
      }
      const expectedObjects = Buffer.from(JSON.stringify(source.objects));
      const requestedObjects = Buffer.from(JSON.stringify(record.objects));
      if (source.manifest_cid !== record.manifest_cid ||
          !expectedObjects.equals(requestedObjects)) {
        fail('PublicationPhysicalHoldingConflict');
      }
      const current = await readPhysicalHolding(record.holding_cid);
      if (current !== undefined) {
        if (!Buffer.from(JSON.stringify(current), 'utf8').equals(
          admitted.bytes,
        )) {
          fail('PublicationPhysicalHoldingConflict');
        }
        await verifyPhysicalHoldingObjects(current);
        await syncDirectory(physicalHoldingsDirectory);
        return Object.freeze({record: current, created: false});
      }
      await verifyPhysicalHoldingObjects(source);
      try {
        await writeExclusive(
          physicalHoldingPath(record.holding_cid),
          admitted.bytes,
        );
      } catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        const installed = await readBounded(
          physicalHoldingPath(record.holding_cid),
          configuration.maxObjectBytes,
        );
        if (!installed.equals(admitted.bytes)) {
          fail('PublicationPhysicalHoldingConflict');
        }
      }
      await syncDirectory(physicalHoldingsDirectory);
      return Object.freeze({record, created: true});
    });
    materialRetentionBusy = operation.catch(() => {});
    return await operation;
  };

  const inspectPhysicalHolding = async holdingCid => {
    active();
    cidHex(holdingCid);
    if (await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
      return undefined;
    }
    const record = await readPhysicalHolding(holdingCid);
    if (record === undefined) return undefined;
    await verifyPhysicalHoldingObjects(record);
    return record;
  };

  const consumePhysicalHolding = async (
    holdingCid,
    objectIndex,
    accept,
  ) => {
    active();
    if (!quantity(objectIndex) || typeof accept !== 'function') {
      fail('InvalidPublicationPhysicalHoldingRead');
    }
    const record = await inspectPhysicalHolding(holdingCid);
    if (record === undefined || objectIndex >= record.objects.length) {
      fail('PublicationPhysicalHoldingUnavailable');
    }
    activePhysicalHoldingReaders.set(
      holdingCid,
      (activePhysicalHoldingReaders.get(holdingCid) ?? 0) + 1,
    );
    try {
      return await consumeObject(record.objects[objectIndex].cid, accept);
    } finally {
      const remaining =
        (activePhysicalHoldingReaders.get(holdingCid) ?? 1) - 1;
      if (remaining === 0) activePhysicalHoldingReaders.delete(holdingCid);
      else activePhysicalHoldingReaders.set(holdingCid, remaining);
    }
  };

  const ensurePhysicalHoldingDeletion = async record => {
    const bytes = Buffer.from(JSON.stringify(record), 'utf8');
    const path = physicalHoldingDeletionPath(record.holding_cid);
    try { await writeExclusive(path, bytes); }
    catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        path,
        configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) {
        fail('PublicationPhysicalHoldingConflict');
      }
    }
    await syncDirectory(physicalHoldingDeletionsDirectory);
  };

  const createPhysicalHoldingDeletionCleanup = record => {
    const existing = pendingPhysicalHoldingDeletions.get(record.holding_cid);
    if (existing !== undefined) return existing;
    let pending = true;
    const errors = [];
    const unconfirmedObjects = new Map();
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const cleanup = Object.freeze({
      status,
      async retry() {
        if (!pending) return status();
        const operation = materialRetentionBusy.then(async () => {
          await ensurePhysicalHoldingDeletion(record);
          if ((activePhysicalHoldingReaders.get(record.holding_cid) ?? 0) !==
              0) return;
          const current = await readPhysicalHolding(record.holding_cid);
          if (current !== undefined) {
            const currentBytes = Buffer.from(JSON.stringify(current), 'utf8');
            const expectedBytes = Buffer.from(JSON.stringify(record), 'utf8');
            if (!currentBytes.equals(expectedBytes)) {
              fail('PublicationPhysicalHoldingConflict');
            }
            await unlink(physicalHoldingPath(record.holding_cid));
            await syncDirectory(physicalHoldingsDirectory);
          }
          const unique = new Map();
          for (const object of record.objects) {
            if (!unique.has(object.cid)) {
              unique.set(object.cid, object.byte_count);
            }
          }
          for (const [cid, bytes] of unique) {
            if (unconfirmedObjects.has(cid)) continue;
            const prepared = preparedObjects.get(cid);
            if (prepared !== undefined &&
                (prepared.holders.size !== 0 ||
                  prepared.commitOwners.size !== 0)) continue;
            if (await materialHasLiveReference(cid)) continue;
            let state;
            try { state = await lstat(objectPath(cid)); }
            catch (error) {
              if (error?.code !== 'ENOENT') throw error;
            }
            if (state === undefined) continue;
            if (!state.isFile() || state.size !== bytes) {
              fail('InvalidPublicationStoreObject');
            }
            if (state.nlink > 1) continue;
            await unlink(objectPath(cid));
            unconfirmedObjects.set(cid, bytes);
          }
          if (unconfirmedObjects.size !== 0) {
            await syncDirectory(objectsDirectory);
            for (const bytes of unconfirmedObjects.values()) {
              storedBytes -= bytes;
              objectCount--;
            }
            unconfirmedObjects.clear();
          }
          await unlink(physicalHoldingDeletionPath(record.holding_cid));
          await syncDirectory(physicalHoldingDeletionsDirectory);
          pending = false;
          pendingPhysicalHoldingDeletions.delete(record.holding_cid);
        });
        materialRetentionBusy = operation.catch(() => {});
        try { await operation; }
        catch (error) {
          errors.push(error);
          throw error;
        }
        return status();
      },
    });
    pendingPhysicalHoldingDeletions.set(record.holding_cid, cleanup);
    return cleanup;
  };

  const retirePhysicalHolding = async holdingCid => {
    active();
    cidHex(holdingCid);
    const record = await readPhysicalHolding(holdingCid) ??
      await readPhysicalHoldingDeletion(holdingCid);
    if (record === undefined) {
      const cleanup = Object.freeze({
        status: () => Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        }),
        retry: () => Promise.resolve(Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        })),
      });
      return Object.freeze({record, cleanup, deleted: true});
    }
    const cleanup = createPhysicalHoldingDeletionCleanup(record);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      record,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const recoverPhysicalHoldingDeletions = async () => {
    active();
    const recovered = [];
    for (const name of await readdir(physicalHoldingDeletionsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      const record = await readPhysicalHoldingAt(
        resolve(physicalHoldingDeletionsDirectory, name),
      );
      const cleanup = createPhysicalHoldingDeletionCleanup(record);
      try { await cleanup.retry(); }
      catch {}
      recovered.push(cleanup);
    }
    return Object.freeze(recovered);
  };

  const validatePhysicalHoldingStore = async () => {
    for (const directory of [
      physicalHoldingsDirectory,
      physicalHoldingDeletionsDirectory,
    ]) {
      for (const name of await readdir(directory)) {
        const record = await readPhysicalHoldingAt(resolve(directory, name));
        if (`${cidHex(record.holding_cid)}.json` !== name) {
          fail('InvalidPublicationPhysicalHoldingStore');
        }
        if (directory === physicalHoldingsDirectory &&
            await readPhysicalHoldingDeletion(record.holding_cid) ===
              undefined) {
          await verifyPhysicalHoldingObjects(record);
        }
      }
    }
  };

  const recoverPreparedCustodies = async () => {
    const recovered = [];
    for (const name of await readdir(custodyDirectory)) {
      if (!custodyNamePattern.test(name)) {
        fail('InvalidPublicationPreparedCustody');
      }
      const token = name.slice(0, -5);
      const path = custodyPath(token);
      const record = parseCustodyRecord(await readBounded(
        path, configuration.maxObjectBytes,
      ));
      let state;
      try { state = await lstat(objectPath(record.material_generation_cid)); }
      catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
      const accounted = state !== undefined && state.isFile() &&
        state.size === record.byte_count &&
        String(state.dev) === record.device &&
        String(state.ino) === record.inode;
      const custody = {
        token,
        path,
        record,
        accounted,
        pendingUnlink: false,
        busy: Promise.resolve(),
      };
      reclaimableCustodies.set(token, custody);
      await reclaimCustody(custody);
      recovered.push(record.material_generation_cid);
    }
    return Object.freeze(recovered);
  };

  const recoverPreparedSchemas = async () => {
    await syncDirectory(contractsDirectory);
    await syncDirectory(objectsDirectory);
    const recovered = [];
    for (const name of await readdir(preparedSchemasDirectory)) {
      if (!custodyNamePattern.test(name)) {
        fail('InvalidPublicationPreparedSchema');
      }
      const path = resolve(preparedSchemasDirectory, name);
      const record = parsePreparedSchema(await readBounded(
        path, configuration.maxObjectBytes,
      ));
      let group = preparedSchemas.get(record.semantic_cid);
      if (group === undefined) {
        group = {
          record, removable: record.removable,
          holders: new Set(), unconfirmedPhysical: undefined,
          pendingAliasSync: false,
          generation: record.device === null ? undefined : {
            device: record.device, inode: record.inode,
          },
          generationRetired: false,
        };
        preparedSchemas.set(record.semantic_cid, group);
      } else if (group.record.physical_cid !== record.physical_cid ||
          group.record.byte_count !== record.byte_count ||
          group.removable !== record.removable ||
          (group.generation !== undefined && record.device !== null &&
            (group.generation.device !== record.device ||
              group.generation.inode !== record.inode))) {
        fail('InvalidPublicationPreparedSchema');
      }
      if (record.device !== null) {
        group.generation = {
          device: record.device, inode: record.inode,
        };
      }
      const holder = {
        path, active: true, releasing: undefined, errors: [],
        runDefinitionCid: record.run_definition_cid,
      };
      group.holders.add(holder);
      recovered.push({group, holder});
    }
    for (const {group, holder} of recovered) {
      await releasePreparedSchema(group, holder);
    }
    return Object.freeze(recovered.map(({group}) =>
      group.record.semantic_cid));
  };

  const createUncommittedMetadataCleanup = async inventory => {
    const inventoryCid = inventory.public_index_entry_cid;
    const existing = pendingUncommittedMetadataCleanups.get(inventoryCid);
    if (existing !== undefined) return existing;
    let pending = true;
    const errors = [];
    const unconfirmedObjects = new Map();
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const cleanup = Object.freeze({
      status,
      retry() {
        if (!pending) return Promise.resolve(status());
        const operation = metadataRetentionBusy.then(async () => {
          if (!pending) return status();
          const key = {
            tenantId: inventory.tenant_id,
            authorityScopeCid: inventory.authority_scope_cid,
            runDefinitionCid: inventory.run_definition_cid,
          };
          const committed = await inspectCommittedIndexRaw(key);
          if (committed?.public_index_entry_cid === inventoryCid) {
            fail('PublicationMetadataAlreadyCommitted');
          }
          const attempt = await latestRecord(inventory.publication_attempt_cid);
          if (!['failed', 'cancelled'].includes(attempt?.state)) {
            fail('PublicationUncommittedMetadataLive');
          }
          for (const object of inventory.contract_objects) {
            await reclaimMetadataContract(
              inventoryCid, object, unconfirmedObjects,
            );
          }
          if (unconfirmedObjects.size !== 0) {
            await syncDirectory(objectsDirectory);
            for (const bytes of unconfirmedObjects.values()) {
              storedBytes -= bytes;
              objectCount--;
            }
            unconfirmedObjects.clear();
          }
          try {
            await unlink(metadataInventoryPath(inventoryCid));
            await syncDirectory(metadataInventoriesDirectory);
          } catch (error) {
            if (error?.code !== 'ENOENT') throw error;
          }
          pending = false;
          pendingUncommittedMetadataCleanups.delete(inventoryCid);
          return status();
        });
        metadataRetentionBusy = operation.catch(() => {});
        return operation.catch(error => {
          errors.push(error);
          throw error;
        });
      },
    });
    pendingUncommittedMetadataCleanups.set(inventoryCid, cleanup);
    return cleanup;
  };

  const retireUncommittedPublication = async publicIndexEntryCid => {
    active();
    cidHex(publicIndexEntryCid);
    const inventory = await readMetadataInventory(publicIndexEntryCid);
    if (inventory === undefined) {
      const cleanup = Object.freeze({
        status: () => Object.freeze({pending: false, errors: Object.freeze([])}),
        retry: () => Promise.resolve(Object.freeze({
          pending: false,
          errors: Object.freeze([]),
        })),
      });
      return Object.freeze({inventory, cleanup, deleted: true});
    }
    const cleanup = await createUncommittedMetadataCleanup(inventory);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      inventory,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const recoverUncommittedPublications = async () => {
    active();
    const recovered = [];
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      );
      const key = {
        tenantId: inventory.tenant_id,
        authorityScopeCid: inventory.authority_scope_cid,
        runDefinitionCid: inventory.run_definition_cid,
      };
      if ((await inspectCommittedIndexRaw(key))?.public_index_entry_cid ===
          inventory.public_index_entry_cid) continue;
      const attempt = await latestRecord(inventory.publication_attempt_cid);
      if (!['failed', 'cancelled'].includes(attempt?.state)) continue;
      const cleanup = await createUncommittedMetadataCleanup(inventory);
      try { await cleanup.retry(); }
      catch {}
      recovered.push(cleanup);
    }
    return Object.freeze(recovered);
  };

  const ensureResultDeletionMarker = async (
    keyHash,
    resultDefinitionCid,
    value,
  ) => {
    const directory = resultDeletionDirectory(keyHash);
    let createdDirectory = false;
    try {
      await mkdir(directory, {mode: 0o700});
      createdDirectory = true;
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      if (!(await lstat(directory)).isDirectory()) {
        fail('InvalidPublicationDeletionStore');
      }
    }
    if (createdDirectory) await syncDirectory(deletionsDirectory);
    const path = resultDeletionPath(keyHash, resultDefinitionCid);
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    try { await writeExclusive(path, bytes); }
    catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        path, configuration.maxObjectBytes,
      );
      if (!existing.equals(bytes)) fail('PublicationDeletionConflict');
    }
    await syncDirectory(directory);
    return path;
  };

  const createResultDeletionCleanup = async (
    keyHash,
    resultDefinitionCid,
    marker,
    expectedBytes,
  ) => {
    const materialCid = marker.material_generation_cid;
    const deletionKey = `${keyHash}/${cidHex(resultDefinitionCid)}`;
    const existing = pendingResultDeletions.get(deletionKey);
    if (existing !== undefined) {
      return Object.freeze({marker, cleanup: existing, deleted: false});
    }
    let pending = true;
    let unlinked = false;
    let accounted = false;
    const errors = [];
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const cleanup = Object.freeze({
      status,
      async retry() {
        if (!pending) return status();
        const operation = materialRetentionBusy.then(async () => {
          await ensureResultDeletionMarker(
            keyHash, resultDefinitionCid, marker,
          );
          if ((activeResultReaders.get(materialCid) ?? 0) !== 0) return;
          const prepared = preparedObjects.get(materialCid);
          if (prepared !== undefined &&
              (prepared.holders.size !== 0 ||
                prepared.commitOwners.size !== 0)) return;
          if (await materialHasLiveReference(materialCid)) {
            pending = false;
            pendingResultDeletions.delete(deletionKey);
            return;
          }
          const currentPrepared = preparedObjects.get(materialCid);
          if (currentPrepared !== undefined &&
              (currentPrepared.holders.size !== 0 ||
                currentPrepared.commitOwners.size !== 0)) return;
          reclaimingMaterialCids.add(materialCid);
          const path = objectPath(materialCid);
          if (!unlinked) {
            let state;
            try { state = await lstat(path); }
            catch (error) {
              if (error?.code !== 'ENOENT') throw error;
            }
            if (state === undefined) {
              pending = false;
              pendingResultDeletions.delete(deletionKey);
              reclaimingMaterialCids.delete(materialCid);
              return;
            }
            if (!state.isFile() || state.size !== expectedBytes) {
              fail('PublicationDurableBindingMismatch');
            }
            // A semantic contract or another Store-owned physical reference
            // can share this inode without appearing in the Result index.
            // Removing the base name would not reclaim that allocation, so
            // retain both the object path and its capacity charge.
            if (state.nlink > 1) {
              pending = false;
              pendingResultDeletions.delete(deletionKey);
              reclaimingMaterialCids.delete(materialCid);
              return;
            }
            await unlink(path);
            unlinked = true;
          }
          await syncDirectory(objectsDirectory);
          if (!accounted) {
            storedBytes -= expectedBytes;
            objectCount--;
            accounted = true;
          }
          pending = false;
          pendingResultDeletions.delete(deletionKey);
          reclaimingMaterialCids.delete(materialCid);
        });
        materialRetentionBusy = operation.catch(() => {});
        try { await operation; }
        catch (error) {
          errors.push(error);
          throw error;
        }
        return status();
      },
    });
    pendingResultDeletions.set(deletionKey, cleanup);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      marker,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const retireCommittedResult = async (key, resultDefinitionCid) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid,
    );
    const expectedBytes = selected.value.byte_count;
    if (!quantity(expectedBytes)) fail('InvalidPublicationDurableBinding');
    return createResultDeletionCleanup(
      indexKey(key),
      resultDefinitionCid,
      Object.freeze({
        version: 'actql-local-result-deletion/0.1',
        public_index_entry_cid: selected.entry.public_index_entry_cid,
        result_definition_cid: resultDefinitionCid,
        material_generation_cid: selected.value.material_generation_cid,
      }),
      expectedBytes,
    );
  };

  const recoverRetiredResults = async () => {
    active();
    const recovered = [];
    for (const keyHash of await readdir(deletionsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(keyHash)) {
        fail('InvalidPublicationDeletionStore');
      }
      let indexBytes;
      try {
        indexBytes = await readBounded(
          resolve(indexesDirectory, `${keyHash}.json`),
          configuration.maxObjectBytes,
        );
      } catch (error) {
        if (error?.code === 'ENOENT' &&
            await readMetadataDeletion(keyHash) !== undefined) continue;
        throw error;
      }
      const indexContract = admitContract(
        'public_index_entry', indexBytes.toString('utf8'),
      );
      const entry = parseContract(indexContract);
      for (const name of await readdir(resultDeletionDirectory(keyHash))) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
          fail('InvalidPublicationDeletionStore');
        }
        const resultDefinitionCid = `sha256:${name.slice(0, -5)}`;
        const marker = await readResultDeletion(
          keyHash, resultDefinitionCid,
        );
        if (marker.public_index_entry_cid !== indexContract.identity) {
          fail('InvalidPublicationDeletionStore');
        }
        const matches = [];
        for (const bindingCid of entry.durable_result_binding_cids) {
          const binding = parseContract((await readContract(
            bindingCid, 'durable_result_binding',
          )).contract);
          if (binding.result_definition_cid === resultDefinitionCid) {
            matches.push(binding);
          }
        }
        if (matches.length !== 1 ||
            matches[0].material_generation_cid !==
              marker.material_generation_cid ||
            !quantity(matches[0].byte_count)) {
          fail('InvalidPublicationDeletionStore');
        }
        recovered.push(await createResultDeletionCleanup(
          keyHash,
          resultDefinitionCid,
          marker,
          matches[0].byte_count,
        ));
      }
    }
    return Object.freeze(recovered);
  };

  const createMetadataDeletionCleanup = async (keyHash, marker) => {
    const existing = pendingMetadataDeletions.get(keyHash);
    if (existing !== undefined) {
      return Object.freeze({marker, cleanup: existing, deleted: false});
    }
    let pending = true;
    const errors = [];
    const unconfirmedObjects = new Map();
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const cleanup = Object.freeze({
      status,
      async retry() {
        if (!pending) return status();
        const operation = metadataRetentionBusy.then(async () => {
          if (unconfirmedObjects.size !== 0) {
            await syncDirectory(objectsDirectory);
            for (const bytes of unconfirmedObjects.values()) {
              storedBytes -= bytes;
              objectCount--;
            }
            unconfirmedObjects.clear();
          }
          for (const result of marker.results) {
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
            if (retired.cleanup.status().pending) {
              await retired.cleanup.retry();
            }
            if (retired.cleanup.status().pending) return;
          }
          await removeRunMetadataDirectories(
            marker.run_definition_cid, keyHash,
          );
          const indexPath = resolve(indexesDirectory, `${keyHash}.json`);
          let indexBytes;
          try {
            indexBytes = await readBounded(
              indexPath, configuration.maxObjectBytes,
            );
          } catch (error) {
            if (error?.code !== 'ENOENT') throw error;
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
          for (const object of marker.contract_objects) {
            await reclaimMetadataContract(
              marker.public_index_entry_cid, object, unconfirmedObjects,
            );
          }
          if (unconfirmedObjects.size !== 0) {
            await syncDirectory(objectsDirectory);
            for (const bytes of unconfirmedObjects.values()) {
              storedBytes -= bytes;
              objectCount--;
            }
            unconfirmedObjects.clear();
          }
          try {
            await rm(resultDeletionDirectory(keyHash), {
              recursive: true, force: false,
            });
            await syncDirectory(deletionsDirectory);
          } catch (error) {
            if (error?.code !== 'ENOENT') throw error;
          }
          try {
            await unlink(metadataInventoryPath(marker.public_index_entry_cid));
            await syncDirectory(metadataInventoriesDirectory);
          } catch (error) {
            if (error?.code !== 'ENOENT') throw error;
          }
          await compactMetadataDeletion(keyHash, marker.run_definition_cid);
          pending = false;
          pendingMetadataDeletions.delete(keyHash);
        });
        metadataRetentionBusy = operation.catch(() => {});
        try { await operation; }
        catch (error) {
          errors.push(error);
          throw error;
        }
        return status();
      },
    });
    pendingMetadataDeletions.set(keyHash, cleanup);
    try { await cleanup.retry(); }
    catch {}
    return Object.freeze({
      marker,
      cleanup,
      deleted: cleanup.status().pending === false,
    });
  };

  const retireCommittedPublicationMetadata = async (key, requestedAt) => {
    active();
    if (!timestampPattern.test(requestedAt)) {
      fail('InvalidPublicationMetadataDeletion');
    }
    const keyHash = indexKey(key);
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
        tenant_id: entry.tenant_id,
        authority_scope_cid: entry.authority_scope_cid,
        run_definition_cid: entry.run_definition_cid,
        public_index_entry_cid: entry.public_index_entry_cid,
        results: await metadataResultBindings(entry),
        contract_objects: await bindMetadataContractObjects(contractCids),
        requested_at: requestedAt,
      }));
    }
    if (marker.tenant_id !== key.tenantId ||
        marker.authority_scope_cid !== key.authorityScopeCid ||
        marker.run_definition_cid !== key.runDefinitionCid) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    return createMetadataDeletionCleanup(keyHash, marker);
  };

  const recoverRetiredMetadata = async () => {
    active();
    const recovered = [];
    for (const name of await readdir(metadataDeletionsDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataDeletionStore');
      }
      const keyHash = name.slice(0, -5);
      const marker = await readMetadataDeletion(keyHash);
      if (marker.version !==
          'actql-local-publication-metadata-retired/0.1') {
        recovered.push(await createMetadataDeletionCleanup(keyHash, marker));
      }
    }
    return Object.freeze(recovered);
  };

  const validateCommittedMetadataInventories = async () => {
    for (const name of await readdir(indexesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationStoreIndex');
      }
      const keyHash = name.slice(0, -5);
      const index = admitContract(
        'public_index_entry',
        (await readBounded(
          resolve(indexesDirectory, name), configuration.maxObjectBytes,
        )).toString('utf8'),
      );
      const inventory = await readMetadataInventory(index.identity);
      if (inventory === undefined ||
          inventory.public_index_entry_cid !== index.identity) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
    }
  };

  await validatePhysicalHoldingStore();

  // Recover process-crash custody before accepting new Store work. A
  // committed or shared allocation survives; an unpublished allocation is
  // reclaimed using its exact recorded generation.
  await recoverPreparedCustodies();
  await recoverPreparedSchemas();
  // A crash between semantic alias creation and physical-custody handoff
  // leaves both records. Revisit physical custody after alias reclamation.
  await recoverPreparedCustodies();

  // A retiring Transfer holding is unavailable before physical reclamation.
  // Recovery resumes the exact durable cleanup without treating an absent
  // object name as proof that another live holding was released.
  await recoverPhysicalHoldingDeletions();

  await validateCommittedMetadataInventories();

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

  return Object.freeze({
    storeAuthorityCid: configuration.storeAuthorityCid,
    createObjectWriter,
    createPreparedObjectWriter,
    commitPhysicalHolding,
    sharePhysicalHolding,
    inspectPhysicalHolding,
    consumePhysicalHolding,
    retirePhysicalHolding,
    recoverPhysicalHoldingDeletions,
    putBytes,
    putSemantic,
    preparePrivateEvidence,
    confirmPrivateEvidence,
    putPreparedResultSchema,
    putPublicationContract,
    verifyObject,
    observeTrustedClock,
    readClockObservation,
    readSemanticBytes,
    readPrivateEvidence,
    consumeObject,
    withCommittedResult,
    withCommittedResultRows,
    consumeCommittedResult,
    readCommittedResultRetentionExtension,
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
    async readPublicationContract(cid, name) {
      active();
      if (typeof name !== 'string' || name.length === 0) {
        fail('InvalidPublicationContractName');
      }
      return (await readContract(cid, name)).contract;
    },
    createAttempt,
    latestRecord,
    latestRecordContract,
    appendRecord,
    consumeManifestReadGrant,
    createDeliveryAttempt,
    lookupDeliveryAttempt,
    latestDeliveryRecord,
    latestDeliveryRecordContract,
    confirmDeliveryRecord,
    appendDeliveryRecord,
    commitIndex,
    validateCommittedEvidence,
    inspectCommittedIndex,
    confirmCommittedIndex,
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
      closed = true;
      if (reservedObjects !== 0 || preparedObjects.size !== 0 ||
          preparedSchemas.size !== 0 ||
          reclaimableCustodies.size !== 0 ||
          pendingResultDeletions.size !== 0 ||
          pendingMetadataDeletions.size !== 0 ||
          pendingPhysicalHoldingDeletions.size !== 0 ||
          activeResultReaders.size !== 0 ||
          activePhysicalHoldingReaders.size !== 0) {
        return Promise.reject(new PublicationStoreError(
          'PublicationStoreCleanupPending',
        ));
      }
      return Promise.resolve(ownership.release()).finally(() => {
        configuration.privateEvidenceKey?.fill(0);
      });
    },
  });
}
