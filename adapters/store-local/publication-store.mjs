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
  unlink,
} from 'node:fs/promises';
import {createHash, randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {
  admitPublicationContract,
  canonicalCid,
  canonicalJson,
  publicationIdentityField,
} from '../host-common/run-publication-contracts.mjs';

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

function validateConfiguration(options) {
  if (!exactKeys(options, [
    'directory',
    'storeAuthorityCid',
    'capacityBytes',
    'maxObjectBytes',
    'maxObjects',
  ]) || typeof options.directory !== 'string' ||
      options.directory.length === 0 ||
      !cidPattern.test(options.storeAuthorityCid) ||
      !quantity(options.capacityBytes) ||
      !quantity(options.maxObjectBytes) || options.maxObjectBytes === 0 ||
      !quantity(options.maxObjects) || options.maxObjects === 0) {
    fail('InvalidPublicationStoreConfiguration');
  }
  return Object.freeze({...options, directory: resolve(options.directory)});
}

function indexKey(value) {
  if (!exactKeys(value, [
    'tenantId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof value.tenantId !== 'string' || value.tenantId.length === 0 ||
      !cidPattern.test(value.authorityScopeCid) ||
      !cidPattern.test(value.runDefinitionCid)) {
    fail('InvalidPublicationIndexKey');
  }
  return canonicalCid({
    tenant_id: value.tenantId,
    authority_scope_cid: value.authorityScopeCid,
    run_definition_cid: value.runDefinitionCid,
  }).slice('sha256:'.length);
}

const transitionAllowed = (previous, next) => {
  if (previous === undefined) return next === 'preparing';
  if (previous === 'preparing') {
    return ['preparing', 'committing', 'failed', 'cancelled'].includes(next);
  }
  if (previous === 'committing') {
    return ['publication_unknown', 'succeeded', 'failed',
      'cancelled'].includes(next);
  }
  if (previous === 'publication_unknown') {
    return ['publication_unknown', 'succeeded', 'failed',
      'cancelled'].includes(next);
  }
  return false;
};

export async function openLocalPublicationStore(supplied) {
  const configuration = validateConfiguration(supplied);
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
  const storeContractBytes = Buffer.from(canonicalJson(storeContract), 'utf8');
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
    let handle;
    let finished = false;
    let busy = Promise.resolve();
    const releaseReservation = () => {
      reservedBytes -= maxBytes;
      reservedObjects--;
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
        try { await handle.close(); } catch {}
        handle = undefined;
      }
      try { await unlink(temporary); }
      catch (error) { if (error?.code !== 'ENOENT') throw error; }
      await syncDirectory(stagingDirectory);
    };
    return Object.freeze({
      append(frame) {
        return queue(async () => {
          await ready;
          if (finished) fail('PublicationObjectWriterClosed');
          const buffer = Buffer.isBuffer(frame) ? Buffer.from(frame) :
            frame instanceof Uint8Array ? Buffer.from(frame) :
              typeof frame === 'string' ? Buffer.from(frame, 'utf8') : null;
          if (buffer === null || bytes + buffer.byteLength > maxBytes) {
            fail('PublicationObjectLimit');
          }
          let offset = 0;
          while (offset < buffer.byteLength) {
            const result = await handle.write(
              buffer, offset, buffer.byteLength - offset, bytes + offset,
            );
            if (result.bytesWritten === 0) fail('IncompletePublicationWrite');
            offset += result.bytesWritten;
          }
          hash.update(buffer);
          bytes += buffer.byteLength;
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
          } finally {
            releaseReservation();
            await cleanupTemporary();
          }
        });
      },
      cancel() {
        return queue(async () => {
          await ready;
          if (finished) return false;
          finished = true;
          releaseReservation();
          await cleanupTemporary();
          return true;
        });
      },
      status: () => Object.freeze({maxBytes, bytes, finished}),
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
    } catch (error) {
      try {
        if (!writer.status().finished) await writer.cancel();
      } catch {}
      throw error;
    }
  };

  const putCanonical = (value, expectedCid) => putBytes(
    Buffer.from(canonicalJson(value), 'utf8'), expectedCid,
  );

  // Semantic contract identities exclude their self-CID field and therefore
  // are deliberately not the physical digest of the stored complete body.
  // The binding is an exclusive hard link to one immutable physical object.
  const putSemantic = async (value, semanticCid) => {
    cidHex(semanticCid);
    const bytes = Buffer.from(canonicalJson(value), 'utf8');
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

  const putPublicationContract = async (name, supplied) => {
    const value = admitPublicationContract(name, supplied);
    const semanticCid = value[publicationIdentityField(name)];
    return Object.freeze({
      value,
      ...await putSemantic(value, semanticCid),
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

  const readJsonObject = async (cid, contractName) => {
    const bytes = await readSemanticBytes(cid);
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationJsonObject', error); }
    return contractName === undefined
      ? value
      : admitPublicationContract(contractName, value);
  };

  const createAttempt = async suppliedAttempt => {
    active();
    const attempt = admitPublicationContract(
      'publication_attempt', suppliedAttempt,
    );
    const stored = await putPublicationContract('publication_attempt', attempt);
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
      if (existing.toString('utf8') !== canonicalJson(attempt)) {
        fail('PublicationAttemptConflict');
      }
      return Object.freeze({attempt, created: false});
    }
  };

  const latestRecord = async attemptCid => {
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
    let parsed;
    try { parsed = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationRecord', error); }
    return admitPublicationContract('publication_record', parsed);
  };

  const appendRecord = async (suppliedRecord, options = {}) => {
    active();
    if (!exactKeys(options, ['uncommittedConfirmed']) ||
        typeof options.uncommittedConfirmed !== 'boolean') {
      fail('InvalidPublicationRecordOptions');
    }
    const record = admitPublicationContract(
      'publication_record', suppliedRecord,
    );
    const directory = attemptPath(record.publication_attempt_cid);
    const attempt = await readJsonObject(
      record.publication_attempt_cid, 'publication_attempt',
    );
    const previous = await latestRecord(record.publication_attempt_cid);
    const expectedSequence = previous === undefined ? 0 : previous.sequence + 1;
    if (record.sequence !== expectedSequence ||
        (previous === undefined
          ? Object.hasOwn(record, 'prior_record_cid')
          : record.prior_record_cid !== previous.publication_record_cid) ||
        !transitionAllowed(previous?.state, record.state) ||
        (['committing', 'publication_unknown'].includes(previous?.state) &&
          ['failed', 'cancelled'].includes(record.state) &&
          options.uncommittedConfirmed !== true)) {
      fail('InvalidPublicationRecordTransition');
    }
    if (attempt.publication_attempt_cid !== record.publication_attempt_cid) {
      fail('PublicationAttemptMismatch');
    }
    await putPublicationContract('publication_record', record);
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
    let parsed;
    try { parsed = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicIndexEntry', error); }
    const entry = admitPublicationContract('public_index_entry', parsed);
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

  const commitIndex = async (suppliedEntry, requiredObjectCids) => {
    active();
    const entry = admitPublicationContract('public_index_entry', suppliedEntry);
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
      entry.publication_request_cid,
      entry.publication_attempt_cid,
    ]) {
      if (!required.has(cid)) fail('IncompletePublicationCommitInventory');
    }
    for (const cid of required) await readSemanticBytes(cid);
    const attempt = await readJsonObject(
      entry.publication_attempt_cid, 'publication_attempt',
    );
    if (attempt.publication_request_cid !== entry.publication_request_cid ||
        attempt.run_definition_cid !== entry.run_definition_cid) {
      fail('PublicationAttemptMismatch');
    }
    const previous = await latestRecord(entry.publication_attempt_cid);
    if (previous?.state !== 'committing') {
      fail('PublicationAttemptNotCommitting');
    }
    await putPublicationContract('public_index_entry', entry);
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

  return Object.freeze({
    storeAuthorityCid: configuration.storeAuthorityCid,
    createObjectWriter,
    putBytes,
    putCanonical,
    putSemantic,
    putPublicationContract,
    verifyObject,
    readSemanticBytes,
    async consumeObject(cid, accept) {
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
    },
    readJsonObject,
    createAttempt,
    latestRecord,
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
    close() { closed = true; },
  });
}
