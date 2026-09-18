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
import {createHash, randomUUID} from 'node:crypto';
import {resolve} from 'node:path';

const cidPattern = /^sha256:([0-9a-f]{64})$/u;
const recordNamePattern = /^(0|[1-9][0-9]*)\.json$/u;

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

async function syncDirectory(path) {
  const directory = await open(path, constants.O_RDONLY);
  try { await directory.sync(); }
  finally { await directory.close(); }
}

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
      await syncDirectory(ownershipDirectory);
      await syncDirectory(root);
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
          await syncDirectory(root);
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
      await syncDirectory(root);
    }
  }
}

function validateConfiguration(options) {
  if (!exactKeys(options, [
    'directory',
    'storeAuthorityCid',
    'capacityBytes',
    'maxObjectBytes',
    'maxObjects',
    'maxContractNodes',
    'maxContractDepth',
  ]) || typeof options.directory !== 'string' ||
      options.directory.length === 0 ||
      !cidPattern.test(options.storeAuthorityCid) ||
      !quantity(options.capacityBytes) ||
      !quantity(options.maxObjectBytes) || options.maxObjectBytes === 0 ||
      !quantity(options.maxObjects) || options.maxObjects === 0 ||
      !quantity(options.maxContractNodes) || options.maxContractNodes === 0 ||
      !quantity(options.maxContractDepth) || options.maxContractDepth === 0) {
    fail('InvalidPublicationStoreConfiguration');
  }
  return Object.freeze({...options, directory: resolve(options.directory)});
}

function validateContractControl(value) {
  if (value === null || typeof value !== 'object' ||
      typeof value.admit !== 'function' ||
      typeof value.recordTransition !== 'function' ||
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

export async function openLocalPublicationStore(supplied, suppliedControl) {
  const configuration = validateConfiguration(supplied);
  const contractControl = validateContractControl(suppliedControl);
  const contractLimits = Object.freeze({
    maxWireBytes: configuration.maxObjectBytes,
    maxNodes: configuration.maxContractNodes,
    maxDepth: configuration.maxContractDepth,
  });
  const root = configuration.directory;
  const objectsDirectory = resolve(root, 'objects');
  const contractsDirectory = resolve(root, 'contracts');
  const stagingDirectory = resolve(root, 'staging');
  const attemptsDirectory = resolve(root, 'attempts');
  const indexesDirectory = resolve(root, 'indexes');
  for (const directory of [root, objectsDirectory, contractsDirectory,
    stagingDirectory, attemptsDirectory, indexesDirectory]) {
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

  let reservedBytes = 0;
  let reservedObjects = 0;
  let closed = false;

  const objectPath = cid => resolve(objectsDirectory, cidHex(cid));
  const contractPath = cid => resolve(contractsDirectory, `${cidHex(cid)}.json`);
  const attemptPath = cid => resolve(attemptsDirectory, cidHex(cid));
  const active = () => {
    if (closed) fail('PublicationStoreClosed');
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

  const createObjectWriter = maxBytes => {
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
            const finalPath = objectPath(cid);
            try {
              await link(temporary, finalPath);
              installed = true;
              storedBytes += bytes;
              objectCount++;
              await syncDirectory(objectsDirectory);
            } catch (error) {
              if (error?.code !== 'EEXIST') throw error;
              const existing = await verifyObject(cid);
              if (existing.bytes !== bytes) {
                fail('PublicationObjectIdentityMismatch');
              }
            }
            return Object.freeze({cid, bytes, created: installed});
          } finally { await cleanupAndRelease(); }
        });
      },
      cancel() {
        return queue(async () => {
          try { await ready; }
          catch (error) {
            if (!reservationHeld) return false;
            throw error;
          }
          if (finished && !reservationHeld) return false;
          finished = true;
          await cleanupAndRelease();
          return true;
        });
      },
      status: () => Object.freeze({
        maxBytes,
        bytes,
        finished,
        cleanupPending,
        reservationHeld,
      }),
    });
  };

  const putBytes = async (value, expectedCid) => {
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
    const writer = createObjectWriter(buffer.byteLength);
    try {
      await writer.append(buffer);
      return await writer.seal(cid);
    } catch (primaryFailure) {
      const cleanupErrors = [];
      try {
        const status = writer.status();
        if (status.reservationHeld) await writer.cancel();
      } catch (error) { cleanupErrors.push(error); }
      if (!writer.status().reservationHeld) throw primaryFailure;
      const code = typeof primaryFailure?.code === 'string'
        ? primaryFailure.code : 'PublicationObjectWriteFailed';
      const failure = new PublicationStoreError(code, primaryFailure);
      failure.primaryFailure = primaryFailure;
      const status = () => Object.freeze({
        pending: writer.status().reservationHeld,
        errors: Object.freeze([...cleanupErrors]),
      });
      const cleanupHandle = Object.freeze({
        status,
        async retry() {
          if (writer.status().reservationHeld) {
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
    const physical = await putBytes(bytes);
    const target = contractPath(semanticCid);
    try {
      await link(objectPath(physical.cid), target);
      await syncDirectory(contractsDirectory);
      return Object.freeze({semanticCid, physical, created: true});
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const existing = await readBounded(target, configuration.maxObjectBytes);
      if (!existing.equals(bytes)) fail('PublicationSemanticIdentityConflict');
      return Object.freeze({semanticCid, physical, created: false});
    }
  };

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
    return Object.freeze({binding, physical});
  };

  const createAttempt = async suppliedWire => {
    active();
    const admitted = admitContract('publication_attempt', suppliedWire);
    const attempt = parseContract(admitted);
    const stored = await putPublicationContract(
      'publication_attempt', admitted.wire,
    );
    const directory = attemptPath(attempt.publication_attempt_cid);
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
    const directory = attemptPath(attemptCid);
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
    const directory = attemptPath(record.publication_attempt_cid);
    const attempt = (await readContract(
      record.publication_attempt_cid, 'publication_attempt',
    )).value;
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

  const inspectCommittedIndex = async key => {
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

  const lookupCommittedIndex = async (key, authorize) => {
    active();
    if (typeof authorize !== 'function' || authorize(Object.freeze({...key})) !== true) {
      fail('PublicationLookupDenied');
    }
    const entry = await inspectCommittedIndex(key);
    if (entry === undefined || authorize(Object.freeze({...key, entry})) !== true) {
      // Missing and unauthorized entries deliberately share one external code.
      fail('PublicationLookupDenied');
    }
    return entry;
  };

  const commitIndex = async (
    suppliedWire,
    requiredObjectCids,
    suppliedEvidence,
  ) => {
    active();
    const admitted = admitContract('public_index_entry', suppliedWire);
    const entry = parseContract(admitted);
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
          !required.has(contract.identity)) {
        fail('InvalidPublicationCommitEvidence');
      }
      const persisted = await readSemanticBytes(contract.identity);
      if (!persisted.equals(Buffer.from(contract.wire, 'utf8'))) {
        fail('PublicationCommitEvidenceMismatch');
      }
    }
    for (const contract of suppliedEvidence.durableBindings) {
      await verifyDurableResultBinding(contract);
    }
    for (const cid of required) await readSemanticBytes(cid);
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
    const previous = await latestRecordContract(entry.publication_attempt_cid);
    if (previous === undefined ||
        contractControl.recordAllowsCommit(previous) !== true) {
      fail('PublicationAttemptNotCommitting');
    }
    await putPublicationContract('public_index_entry', admitted.wire);
    const key = {
      tenantId: entry.tenant_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    };
    const target = resolve(indexesDirectory, `${indexKey(key)}.json`);
    try {
      await link(contractPath(entry.public_index_entry_cid), target);
      await syncDirectory(indexesDirectory);
      return Object.freeze({entry, committed: true, idempotent: false});
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const existing = await inspectCommittedIndex(key);
      if (existing.invocation_cid !== entry.invocation_cid ||
          existing.result_manifest_cid !== entry.result_manifest_cid ||
          existing.publication_request_cid !== entry.publication_request_cid) {
        fail('PublicationCommitConflict');
      }
      return Object.freeze({
        entry: existing,
        committed: false,
        idempotent: true,
      });
    }
  };

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

  const consumeCommittedResult = async (
    key,
    resultDefinitionCid,
    authorize,
    accept,
  ) => {
    active();
    cidHex(resultDefinitionCid);
    if (typeof authorize !== 'function' || typeof accept !== 'function') {
      fail('InvalidPublicationObjectConsumer');
    }
    const request = Object.freeze({...key, resultDefinitionCid});
    if (authorize(request) !== true) fail('PublicationLookupDenied');
    const entry = await inspectCommittedIndex(key);
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
    const selected = matches[0];
    const authorization = Object.freeze({
      ...request,
      durableResultBindingCid: selected.contract.identity,
      logicalResultCid: selected.value.logical_result_cid,
      resultSchemaCid: selected.value.result_schema_cid,
    });
    if (authorize(authorization) !== true) fail('PublicationLookupDenied');
    const verified = await verifyDurableResultBinding(selected.contract);
    const consumed = await consumeObject(
      verified.binding.material_generation_cid, accept,
    );
    return Object.freeze({
      durableResultBindingCid: selected.contract.identity,
      logicalResultCid: verified.binding.logical_result_cid,
      resultSchemaCid: verified.binding.result_schema_cid,
      rowCount: verified.binding.row_count,
      bytes: consumed.bytes,
    });
  };

  return Object.freeze({
    storeAuthorityCid: configuration.storeAuthorityCid,
    createObjectWriter,
    putBytes,
    putSemantic,
    putPublicationContract,
    verifyObject,
    readSemanticBytes,
    consumeObject,
    consumeCommittedResult,
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
    commitIndex,
    inspectCommittedIndex,
    lookupCommittedIndex,
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
      if (reservedObjects !== 0) {
        return Promise.reject(new PublicationStoreError(
          'PublicationStoreCleanupPending',
        ));
      }
      return ownership.release();
    },
  });
}
