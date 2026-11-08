// Durable local publication storage. Prepared objects are content-addressed
// but remain invisible to ordinary Result lookup until an authority-scoped
// public index entry is installed with an exclusive atomic link.
// Existing bounded physical Content reader implementation DATA, not a caller
// allowance or proof of the separate Store metadata/read preparation.
export const physicalContentReadWindowBytes = 65536;
import {openPublicationOwnerLease} from './publication-owner-lease.mjs';
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
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectory}
  from '../host-node/host-journal-directory.mjs';
import {createObjectWriterOwner} from './object-writer-owner.mjs';
import {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';
import {createPreparedCustodyQueue} from './prepared-custody-queue.mjs';
import {createPreparedHolderRegistry} from './prepared-holder-owner.mjs';
import {createResultDeletionOwner} from './result-deletion-owner.mjs';
import {createMetadataDeletionOwner} from './metadata-deletion-owner.mjs';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

// Internal physical adapter primitive, not a Client read/authority entry. Its
// caller funds the complete metadata/decode lifetime before I/O and retains
// any existing failed-close cleanupHandle until confirmed physical close.
// Keep the actual implementation shared with ordinary Store metadata reads.
export {readBounded as readBoundedLocalMetadata};

const cidPattern = /^sha256:([0-9a-f]{64})$/u;
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
const metadataContractObject = object => object !== null && typeof object === 'object' &&
  cidPattern.test(object.semantic_cid) && quantity(object.byte_count) && (
    exactKeys(object, ['semantic_cid','physical_cid','byte_count']) && cidPattern.test(object.physical_cid) ||
    exactKeys(object, ['semantic_cid','native','body_sha256','byte_count']) &&
      object.native === 'sqlite' && cidPattern.test(object.body_sha256));
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

// The existing Store's synchronous encoding phase. Only its complete envelope
// crosses into writer/FD/ACK waits; crypto and Base64 segment temporaries do not
// belong to that async frame. This retires references, not capacity, physical
// GC, a pending writer or the original borrowed input's independent custody.
function encodePrivateEvidenceEnvelope(input, isWire, key, aad, maximum) {
  // The caller already checked the complete encrypted extent. A short wire
  // must not borrow a larger shared pool backing for this encoding lifetime.
  // Keep its exact UTF-8 snapshot; the original String and codec controls are
  // still separate funded components, not released by this extent check.
  const bytes = isWire ? Buffer.allocUnsafeSlow(Buffer.byteLength(input, 'utf8')) : input;
  if (isWire) bytes.write(input, 0, bytes.byteLength, 'utf8');
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(aad);
  const encrypted = cipher.update(bytes);
  const final = cipher.final();
  const ciphertext = final.byteLength === 0 ? encrypted
    : Buffer.concat([encrypted, final]);
  // Every variable segment is Base64 ASCII. Preserve the historical field
  // order and bytes without a second complete JSON String/envelope backing.
  const segments = [
    '{"version":"actql-private-publication-evidence/0.1","nonce":"',
    nonce.toString('base64'),
    '","tag":"',
    cipher.getAuthTag().toString('base64'),
    '","ciphertext":"',
    ciphertext.toString('base64'),
    '"}',
  ];
  const envelopeBytes = segments.reduce((total, segment) => total + segment.length, 0);
  if (!Number.isSafeInteger(envelopeBytes) || envelopeBytes > maximum) {
    fail('PublicationObjectLimit');
  }
  const envelope = Buffer.alloc(envelopeBytes);
  let envelopeOffset = 0;
  for (const segment of segments) {
    envelopeOffset += envelope.write(segment, envelopeOffset, 'ascii');
  }
  if (envelopeOffset !== envelopeBytes) fail('PublicationPrivateEvidenceCorrupt');
  return envelope;
}

// Exact extent of the SAME closed format, not memory funding or a lease.
// Its 128 fixed ASCII bytes include the nonce/tag; ciphertext uses Base64.
// Inverting before multiplication keeps the calculation safe at large limits.
function privateEvidenceWireLimitForObject(maximum) {
  if (maximum < 128) fail('PublicationObjectLimit');
  return 3 * Math.floor((maximum - 128) / 4);
}

// Recovery facade of the SAME Store writer, not another cleanup/capacity
// owner. A failed private preparation has no prepared object to return yet.
// Keep its original reservation/FD/custody reachable, and expose only cleanup.
function retainPrivateWriterCleanup(writer) {
  let original = writer;
  let flight;
  const pending = () => {
    if (original === undefined) return false;
    const state = original.status();
    return state.reservationHeld || state.custodyPending || state.cleanupPending;
  };
  const release = () => {
    if (flight !== undefined) return flight;
    if (!pending()) {
      original = undefined;
      return Promise.resolve(false);
    }
    const actual = original;
    flight = Promise.resolve().then(() => actual.cancel()).then(result => {
      if (pending()) fail('PublicationPrivateWriterCleanupPending');
      // An escaped retired facade must not keep the original writer/Store
      // graph after the actual same cleanup has settled its responsibilities.
      original = undefined;
      return result;
    }).finally(() => { flight = undefined; });
    return flight;
  };
  const cleanup = Object.freeze({
    status: () => Object.freeze({pending: pending()}),
    release,
    async retry() { await release(); return cleanup.status(); },
  });
  return cleanup;
}

// A bounded view of the two original private-preparation duties: descriptor
// writer cleanup and the already prepared content. The same child owners
// perform retirement; this facade cannot write, commit or return their loans.
function retainPrivateRawCleanup(descriptor, content) {
  let originals = [descriptor, content];
  let flight;
  const pending = () => originals?.some(handle => handle.status().pending) === true;
  const release = () => {
    if (flight !== undefined) return flight;
    if (originals === undefined) return Promise.resolve(false);
    flight = Promise.resolve().then(async () => {
      for (const handle of originals) {
        if (handle.status().pending) await handle.release();
      }
      if (pending()) fail('PublicationPrivateWriterCleanupPending');
      // Clear both references after their actual retirement, including on an
      // escaped facade. A false or thrown child release keeps the same pair.
      originals = undefined;
      return true;
    }).finally(() => { flight = undefined; });
    return flight;
  };
  const cleanup = Object.freeze({
    status: () => Object.freeze({pending: pending()}),
    release,
    async retry() { await release(); return cleanup.status(); },
  });
  return cleanup;
}

async function syncDirectoryPath(path) {
  const directory = await open(path, constants.O_RDONLY);
  let syncFailure, syncFailed = false;
  try { await directory.sync(); }
  catch (cause) { syncFailed = true; syncFailure = cause; }
  try {
    if (await directory.close() === false) fail('PublicationDirectorySyncCleanupPending');
  } catch (closeFailure) {
    // Keep this already-acquired FD, not a pathname reopen or repeated sync.
    // Its initialization/publication caller still owns all surrounding duty.
    let original = directory, flight;
    const status = () => Object.freeze({pending: original !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      if (original === undefined) return Promise.resolve(status());
      flight = Promise.resolve().then(() => original.close()).then(result => {
        if (result === false) fail('PublicationDirectorySyncCleanupPending');
        original = undefined;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    const primary = syncFailed ? syncFailure : closeFailure;
    let failure;
    try {
      failure = primary !== null && typeof primary === 'object' &&
        Object.isExtensible(primary) && primary.cleanupHandle === undefined &&
        ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
          const field = Object.getOwnPropertyDescriptor(primary, name);
          return field === undefined || field.writable === true;
        }) ? primary : new Error('PublicationDirectorySyncCleanupPending', {cause: primary});
      Object.defineProperties(failure, {
        cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
          {writable: true, enumerable: true, configurable: true}), value: cleanup},
        cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
          {writable: true, enumerable: true, configurable: true}), value: true},
        cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
          {writable: true, enumerable: true, configurable: true}), value: closeFailure},
      });
      if (failure !== primary) Object.defineProperty(failure, 'primaryFailure', {value: primary});
    } catch {
      // Presentation must never mask raw thrown values or original FD duty.
      failure = Object.assign(new Error('PublicationDirectorySyncCleanupPending', {cause: primary}),
        {code: 'PublicationDirectorySyncCleanupPending', primaryFailure: primary,
          cleanupHandle: cleanup, cleanupPending: true, cleanupError: closeFailure});
    }
    throw failure;
  }
  if (syncFailed) throw syncFailure;
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

async function readBounded(path, maximum, closed, signal, ownerOnly = false) {
  if (!quantity(maximum)) {
    fail('InvalidPublicationStoreObject');
  }
  if (signal !== undefined && !(signal instanceof AbortSignal)) {
    fail('InvalidPublicationMetadataSignal');
  }
  // Pin the original allocation before allocating its bounded output. A
  // nonblocking open also refuses a raced-in FIFO without waiting for a writer.
  let handle;
  try {
    signal?.throwIfAborted();
    handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW |
      constants.O_NONBLOCK);
  } catch (error) {
    closed?.(); // No original FD was acquired.
    throw error;
  }
  let readFailure;
  let readFailed = false;
  let originalClose;
  const captureClose = () => {
    if (originalClose !== undefined) return;
    const method = handle.close;
    if (typeof method !== 'function') fail('PublicationMetadataReaderCleanupPending');
    originalClose = method;
  };
  try {
    captureClose();
    signal?.throwIfAborted();
    const before = await handle.stat({bigint: true});
    signal?.throwIfAborted();
    if (!before.isFile() || before.size < 0n ||
        before.size > BigInt(maximum)) {
      fail('InvalidPublicationStoreObject');
    }
    // The installation key's existing owner-only rule must hold on THIS FD,
    // not only on a pathname observed before its asynchronous acquisition.
    if (ownerOnly && (before.mode & 0o077n) !== 0n) {
      fail('PrivateEvidenceKeyExposed');
    }
    const sameFile = state => state.isFile() &&
      state.dev === before.dev && state.ino === before.ino &&
      state.size === before.size && state.mtimeNs === before.mtimeNs &&
      state.ctimeNs === before.ctimeNs;
    if (!sameFile(await lstat(path, {bigint: true}))) {
      fail('InvalidPublicationStoreObject');
    }
    signal?.throwIfAborted();
    const size = Number(before.size);
    // Avoid pooled backing and growth/concatenation. The one-byte probe is a
    // separate bounded allocation; neither buffer is a byte-capacity grant.
    const bytes = Buffer.allocUnsafeSlow(size);
    let offset = 0;
    while (offset < size) {
      signal?.throwIfAborted();
      const {bytesRead} = await handle.read(bytes, offset, size - offset, offset);
      signal?.throwIfAborted();
      if (!Number.isSafeInteger(bytesRead) || bytesRead <= 0 ||
          bytesRead > size - offset) {
        fail('InvalidPublicationStoreObject');
      }
      offset += bytesRead;
    }
    signal?.throwIfAborted();
    const probe = Buffer.allocUnsafeSlow(1);
    const {bytesRead} = await handle.read(probe, 0, 1, size);
    signal?.throwIfAborted();
    if (bytesRead !== 0) fail('InvalidPublicationStoreObject');
    const after = await handle.stat({bigint: true});
    signal?.throwIfAborted();
    if (ownerOnly && (after.mode & 0o077n) !== 0n) {
      fail('PrivateEvidenceKeyExposed');
    }
    if (!sameFile(after)) fail('InvalidPublicationStoreObject');
    const pathAfter = await lstat(path, {bigint: true});
    signal?.throwIfAborted();
    if (!sameFile(pathAfter)) fail('InvalidPublicationStoreObject');
    return bytes;
  } catch (error) {
    readFailed = true;
    readFailure = error;
    throw error;
  } finally {
    try {
      captureClose();
      if (await originalApply(originalClose, handle, []) === false) fail('PublicationMetadataReaderCleanupPending');
    } catch (closeFailure) {
      // Retain exactly this failed FD, not a pathname reopen or another read.
      // As for the existing object reader, the original caller's reservation
      // and custody stay live until confirmed close. This control/frame and
      // any escaped error are part of the original funded read inventory.
      let original = handle;
      let closeOriginal = originalClose;
      let retire = closed;
      let flight;
      const status = () => Object.freeze({pending: original !== undefined});
      const cleanup = Object.freeze({
        status,
        retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(() => {
            // Retry the successfully captured original only. If its getter
            // never yielded a method, custody stays with this same handle.
            if (closeOriginal === undefined) {
              const method = original.close;
              if (typeof method !== 'function') fail('PublicationMetadataReaderCleanupPending');
              closeOriginal = method;
            }
            return originalApply(closeOriginal, original, []);
          }).then(result => {
            if (result === false) fail('PublicationMetadataReaderCleanupPending');
            original = closeOriginal = undefined;
            const acknowledge = retire;
            retire = undefined;
            acknowledge?.();
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        },
      });
      const primary = readFailed ? readFailure : closeFailure;
      let failure;
      try {
        failure = primary !== null && typeof primary === 'object' &&
          Object.isExtensible(primary) && primary.cleanupHandle === undefined &&
          ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
            const field = Object.getOwnPropertyDescriptor(primary, name);
            return field === undefined || field.writable === true;
          })
          ? primary : new Error('PublicationMetadataReaderCleanupPending', {cause: primary});
        // Define own data fields: inherited setters can silently discard an
        // assignment even on an ordinary extensible Error subclass. Preserve
        // existing writable own-field attributes and ordinary error identity.
        Object.defineProperties(failure, {
          cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
            {writable: true, enumerable: true, configurable: true}), value: cleanup},
          cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
            {writable: true, enumerable: true, configurable: true}), value: true},
          cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
            {writable: true, enumerable: true, configurable: true}), value: closeFailure},
        });
      } catch {
        // Readonly fields/accessors must not mask the original read failure
        // or discard the same FD. The fresh wrapper owns diagnostics only.
        failure = new Error('PublicationMetadataReaderCleanupPending', {cause: primary});
        Object.defineProperties(failure, {
          cleanupHandle: {value: cleanup, writable: true, enumerable: true, configurable: true},
          cleanupPending: {value: true, writable: true, enumerable: true, configurable: true},
          cleanupError: {value: closeFailure, writable: true, enumerable: true, configurable: true},
        });
      }
      throw failure;
    }
    closed?.();
  }
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

// One physical opening's acquisition controls, not a capacity Owner/grant.
// Names and metadata are conservatively kept in this opening's raw footprint
// until it completes: no earlier Buffer/String/Promise retirement is assumed.
// The original Host envelope separately funds decode/tree/backing, the one
// excess Dirent/EOF probe, FD/Dir/cleanup controls and generated Host baseline.
function storeBootstrapAcquisition(supplied, maxMetadataBytes, directoryInspection) {
  if (!exactKeys(supplied, ['maxWireBytes', 'maxDirectoryEntries']) ||
      !quantity(supplied.maxWireBytes) || supplied.maxWireBytes === 0 ||
      !quantity(supplied.maxDirectoryEntries)) {
    fail('InvalidPublicationStoreBootstrapBounds');
  }
  // Capture before I/O. A mutated argument never widens this opening.
  const {maxWireBytes, maxDirectoryEntries} = supplied;
  if (directoryInspection !== undefined) {
    assertHostJournalDirectoryInspector(directoryInspection, maxDirectoryEntries);
  }
  let entries = 0, rawBytes = 0;
  const readMetadata = async path => {
    const bytes = await readBounded(path,
      Math.min(maxMetadataBytes, maxWireBytes - rawBytes));
    rawBytes += bytes.byteLength;
    return bytes;
  };
  const readDirectory = async path => {
    if (directoryInspection !== undefined) {
      // The same Root owns this nominal native view and its cumulative scan
      // allowance before acquisition. A whole scan's retained names/backing
      // precedes these Store processing bounds; it is not a stock Dir lease.
      // Unknown close propagates the view's original cleanup duty unchanged.
      const names = inspectHostJournalDirectory(directoryInspection, path, maxDirectoryEntries);
      for (const name of names) {
        if (entries === maxDirectoryEntries) fail('PublicationStoreBootstrapEntriesLimit');
        entries++;
        const bytes = originalApply(originalByteLength, OriginalBuffer, [name, 'utf8']);
        if (!Number.isSafeInteger(bytes) || bytes < name.length || bytes > maxWireBytes - rawBytes) {
          fail('PublicationStoreBootstrapWireLimit');
        }
        rawBytes += bytes;
      }
      return names;
    }
    const directory = await opendir(path, {encoding: 'buffer', bufferSize: 1});
    let primary, failed = false;
    try {
      const names = [];
      for (;;) {
        const entry = await directory.read();
        if (entry === null) break;
        // Count every actually acquired entry, before filtering or descent.
        // The one excess native Dirent is a separately funded refusal probe.
        if (entries === maxDirectoryEntries) fail('PublicationStoreBootstrapEntriesLimit');
        entries++;
        if (!(entry.name instanceof Uint8Array) ||
            entry.name.byteLength > maxWireBytes - rawBytes) {
          fail('PublicationStoreBootstrapWireLimit');
        }
        rawBytes += entry.name.byteLength;
        let name;
        try { name = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(entry.name); }
        catch (cause) { fail('InvalidPublicationStoreDirectoryName', cause); }
        names.push(name);
      }
      return names;
    } catch (cause) { primary = cause; failed = true; throw cause; }
    finally {
      try {
        if (await directory.close() === false) fail('PublicationStoreBootstrapCleanupPending');
      }
      catch (closeFailure) {
        let original = directory, flight;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(() => original.close()).then(result => {
            if (result === false) fail('PublicationStoreBootstrapCleanupPending');
            original = undefined;
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
        const reason = failed ? primary : closeFailure;
        const failure = reason !== null && typeof reason === 'object' &&
          Object.isExtensible(reason) && reason.cleanupHandle === undefined
          ? reason : new Error('PublicationStoreBootstrapCleanupPending', {cause: reason});
        failure.cleanupHandle = cleanup;
        failure.cleanupPending = true;
        failure.cleanupError = closeFailure;
        throw failure;
      }
    }
  };
  return Object.freeze({readMetadata, readDirectory});
}

// Use the same cumulative opening scan for old temporary trees too. Native
// recursive rm would acquire their entries behind the physical clamp. This
// retains existing cleanup semantics; it creates no new cleanup authority.
async function removeOpeningTree(path, bootstrap) {
  if (bootstrap === undefined) return rm(path, {recursive: true, force: false});
  const state = await lstat(path);
  if (state.isDirectory() && !state.isSymbolicLink()) {
    for (const name of await bootstrap.readDirectory(path)) {
      await removeOpeningTree(resolve(path, name), bootstrap);
    }
    await rmdir(path);
  } else await unlink(path);
}

async function acquireStoreOwnership(root, bootstrap, key, fresh = false, directoryInspection) {
  let lease, metadata, failureCleanup, qualificationAttempted = false;
  const release = async () => {
    if (failureCleanup !== undefined) {
      const result = await failureCleanup.retry();
      if (result?.pending !== false) fail('PublicationStoreCleanupPending');
      failureCleanup = undefined;
    }
    // A consumed/uncertain native metadata child must drain before its
    // original directory/token, lease, key or root may retire.
    lease?.drainMetadata();
    if (metadata !== undefined) {
      if (await metadata.release() !== true) return false;
      metadata = undefined;
    }
    return lease?.close() ?? true;
  };
  try {
    qualificationAttempted = !fresh;
    lease = openPublicationOwnerLease(root, directoryInspection, fresh);
    metadata = await acquireStoreMetadataOwnership(root, bootstrap, key, lease);
    const token = metadata.token;
    return Object.freeze({
      async assertCurrent() {lease?.current(); await metadata.assertCurrent(); lease?.current();},
      async qualifyExecutionOwner() {
        if (!qualificationAttempted) {
          qualificationAttempted = true;
          try {
            if (lease === undefined) lease = openPublicationOwnerLease(root, directoryInspection);
            else if (!lease.qualify()) lease = undefined;
            if (lease?.anchor !== undefined) await metadata.attachLease(lease);
          } catch (cause) {failureCleanup = cause?.cleanupHandle; throw cause;}
        }
        lease?.current();
      },
      release,
      executionReceipt() {if (lease?.anchor === undefined) return undefined; lease.current(); if (metadata === undefined) fail('PublicationStoreOwnershipLost');
        return Object.freeze({token, anchor: lease.anchor});},
      priorExecutionStopped(receipt) {
        if (lease?.anchor === undefined) return false;
        try {
          lease.current(); return metadata !== undefined && typeof receipt?.token === 'string' &&
            receipt.token !== token && lease.matches(receipt.anchor);
        } catch (cause) {
          if (['PublicationStoreLeaseChanged','PublicationStoreLeaseUnavailable','LocalFileOriginalChanged'].includes(cause?.code)) return false;
          throw cause;
        }
      },
    });
  } catch (cause) {
    failureCleanup = cause?.cleanupHandle;
    throw await retainStoreOpeningFailure(cause, Object.freeze({release}), key);
  }
}

async function acquireStoreMetadataOwnership(root, bootstrap, key, lease) {
  const ownershipDirectory = resolve(root, 'owner');
  const finalOwnerPath = resolve(ownershipDirectory, 'owner.json');
  const token = randomUUID();
  // Read before acquiring ownership: a failed identity observation cannot
  // strand a newly created owner. Keep scalars, not the entire Stats object.
  const {dev: rootDevice, ino: rootInode} = await lstat(root, {bigint: true});
  while (true) {
    let directoryPath = ownershipDirectory, ownerPath = finalOwnerPath;
    let staging = false;
    try {
      if (lease !== undefined) {
        // An existence check selects old-owner validation; only the native
        // no-replace rename below is the publication condition.
        try {await lstat(directoryPath); throw Object.assign(new Error('Owner exists'), {code: 'EEXIST'});}
        catch (cause) {if (cause?.code !== 'ENOENT') throw cause;}
        directoryPath = resolve(root, `.owner-opening-${token}`);
        ownerPath = resolve(directoryPath, 'owner.json');
        staging = true;
      }
      await mkdir(directoryPath, {mode: 0o700});
      const owner = Buffer.from(JSON.stringify({
        version: 'actql-local-publication-store-owner/0.1',
        pid: process.pid,
        token,
        ...(lease?.anchor === undefined ? {} : {leaseAnchor: lease.anchor}),
      }), 'utf8');
      let released = false, ownerRemoved = false, directoryRemoved = false;
      let ownershipDevice, ownershipInode;
      let retirementDirectory, retirementSynced = false;
      let ownerWriter, ownerWriterClose, ownerFileIdentity;
      let retirementReadCleanup, retirementReadFailure;
      let ownerFileCreated = false, ownerWritten = false;
      let leaseStaging, leaseStagingIdentity;
      const ownership = Object.freeze({
        token,
        async attachLease(currentLease) {
          await ownership.assertCurrent(); currentLease.current();
          const bytes = Buffer.from(JSON.stringify({version: 'actql-local-publication-store-owner/0.1',
            pid: process.pid, token, leaseAnchor: currentLease.anchor}), 'utf8');
          leaseStaging = resolve(directoryPath, `.lease-${token}.json`);
          ownerWriter = await open(leaseStaging, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
          ownerWriterClose = ownerWriter.close;
          const original = await ownerWriter.stat({bigint: true});
          leaseStagingIdentity = {dev: original.dev, ino: original.ino};
          let offset = 0;
          while (offset < bytes.byteLength) {
            const {bytesWritten} = await ownerWriter.write(bytes, offset, bytes.byteLength - offset, offset);
            if (bytesWritten === 0) fail('IncompletePublicationWrite');
            offset += bytesWritten;
          }
          await ownerWriter.sync();
          const written = await ownerWriter.stat({bigint: true});
          const replacement = Object.fromEntries(['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name => [name, written[name]]));
          if (await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) fail('PublicationStoreCleanupPending');
          ownerWriter = undefined;
          await ownership.assertCurrent(); currentLease.current();
          currentLease.replaceMetadata(`.lease-${token}.json`, ownerFileIdentity, replacement,
            {dev: ownershipDevice, ino: ownershipInode}, () => {
            // Commit precedes any child-close or durability failure. Cleanup
            // owns this exact replacement without another rename/reissue.
            ownerFileIdentity = replacement;
            leaseStaging = leaseStagingIdentity = undefined;
          });
          const committed = await lstat(ownerPath, {bigint: true});
          if (committed.dev !== replacement.dev || committed.ino !== replacement.ino ||
              !committed.isFile() || committed.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
          ownerFileIdentity = Object.fromEntries(['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name => [name, committed[name]]));
          await syncDirectoryPath(directoryPath); currentLease.current();
        },
        async assertCurrent() {
          if (!ownerWritten || ownerWriter !== undefined || released || ownerRemoved ||
              directoryRemoved || retirementDirectory !== undefined) {
            fail('PublicationStoreOwnershipLost');
          }
          const currentRoot = await lstat(root, {bigint: true});
          const directory = await lstat(directoryPath, {bigint: true});
          if (!currentRoot.isDirectory() || currentRoot.isSymbolicLink() ||
              currentRoot.dev !== rootDevice || currentRoot.ino !== rootInode ||
              !directory.isDirectory() || directory.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
          const before = await lstat(ownerPath, {bigint: true});
          const sameFile = state => state.isFile() && !state.isSymbolicLink() &&
            ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].every(name => state[name] === ownerFileIdentity?.[name]);
          if (!sameFile(before)) fail('PublicationStoreOwnershipLost');
          const existing = JSON.parse(await readBounded(ownerPath, 4096));
          if (!sameFile(await lstat(ownerPath, {bigint: true}))) fail('PublicationStoreOwnershipLost');
          if (existing?.token !== token || existing?.pid !== process.pid) fail('PublicationStoreOwnershipLost');
          if (ownershipDevice === undefined) {
            ownershipDevice = directory.dev;
            ownershipInode = directory.ino;
          } else if (directory.dev !== ownershipDevice || directory.ino !== ownershipInode) {
            fail('PublicationStoreOwnershipLost');
          }
        },
        async release() {
          if (released) return false;
          if (retirementReadCleanup !== undefined) {
            const child = retirementReadCleanup;
            const acknowledged = state => {
              const pending = state !== null && typeof state === 'object'
                ? Object.getOwnPropertyDescriptor(state, 'pending') : undefined;
              return pending !== undefined && Object.hasOwn(pending, 'value') && pending.value === false;
            };
            if (child.status === undefined || child.retry === undefined) throw retirementReadFailure;
            let state = await originalApply(child.status, child.handle, []);
            if (!acknowledged(state)) state = await originalApply(child.retry, child.handle, []);
            if (!acknowledged(state)) throw retirementReadFailure;
            retirementReadCleanup = retirementReadFailure = undefined;
          }
          // The opener owns this exact metadata writer even if writing or
          // closing failed before an ownership handle could be returned.
          if (ownerWriter !== undefined) {
            ownerWriterClose ??= ownerWriter.close;
            if (typeof ownerWriterClose !== 'function' ||
                await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) {
              fail('PublicationStoreCleanupPending');
            }
            ownerWriter = undefined;
          }
          // This FD is already owned independently of the current pathname.
          // Drain it even if root has vanished or names a foreign directory;
          // successful FD close alone does not retire the Store or its key.
          if (retirementDirectory !== undefined) {
            if (await retirementDirectory.close() === false) fail('PublicationStoreCleanupPending');
            retirementDirectory = undefined;
          }
          let currentRoot;
          try { currentRoot = await lstat(root, {bigint: true}); }
          catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
          if (!currentRoot.isDirectory() || currentRoot.dev !== rootDevice ||
              currentRoot.ino !== rootInode) fail('PublicationStoreOwnershipLost');
          if (retirementSynced) {
            released = true;
            return true;
          }
          if (!directoryRemoved) {
            let directory;
            try { directory = await lstat(directoryPath, {bigint: true}); }
            catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
            if (!directory.isDirectory() || directory.isSymbolicLink()) {
              fail('PublicationStoreOwnershipLost');
            }
            if (!ownerRemoved) {
              if (ownerWritten) {
                const sameOwnerFile = state => state.isFile() && !state.isSymbolicLink() &&
                  state.dev === ownerFileIdentity?.dev && state.ino === ownerFileIdentity?.ino;
                if (!sameOwnerFile(await lstat(ownerPath, {bigint: true}))) fail('PublicationStoreOwnershipLost');
                let existing;
                try { existing = JSON.parse(bootstrap === undefined
                  ? await readFile(ownerPath, 'utf8') : await readBounded(ownerPath, 4096)); }
                catch (error) {
                  const handle = error !== null && typeof error === 'object'
                    ? Object.getOwnPropertyDescriptor(error, 'cleanupHandle')?.value : undefined;
                  if (handle !== undefined) {
                    const status = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
                    const retry = Object.getOwnPropertyDescriptor(handle, 'retry')?.value;
                    retirementReadCleanup = {handle,
                      status: typeof status === 'function' ? status : undefined,
                      retry: typeof retry === 'function' ? retry : undefined};
                    retirementReadFailure = error;
                    throw error;
                  }
                  if (error?.code === 'ENOENT') return false;
                  throw error;
                }
                if (!sameOwnerFile(await lstat(ownerPath, {bigint: true})) ||
                    existing?.token !== token || existing?.pid !== process.pid) {
                  fail('PublicationStoreOwnershipLost');
                }
              } else if (ownerFileCreated) {
                // Incomplete bytes do not contain a readable token yet. Only
                // the exact file identity from our own writer may be removed.
                const state = await lstat(ownerPath, {bigint: true});
                if (ownerFileIdentity === undefined || !state.isFile() || state.isSymbolicLink() ||
                    state.dev !== ownerFileIdentity.dev || state.ino !== ownerFileIdentity.ino) {
                  fail('PublicationStoreOwnershipLost');
                }
              } else {
                try { await lstat(ownerPath); fail('PublicationStoreOwnershipLost'); }
                catch (cause) { if (cause?.code !== 'ENOENT') throw cause; }
              }
            }
            if (ownershipDevice === undefined) {
              ownershipDevice = directory.dev;
              ownershipInode = directory.ino;
            } else if (directory.dev !== ownershipDevice || directory.ino !== ownershipInode) {
              fail('PublicationStoreOwnershipLost');
            }
            if (leaseStaging !== undefined) {
              const state = await lstat(leaseStaging, {bigint: true});
              if (!state.isFile() || state.isSymbolicLink() ||
                  state.dev !== leaseStagingIdentity?.dev || state.ino !== leaseStagingIdentity?.ino) {
                fail('PublicationStoreOwnershipLost');
              }
              await unlink(leaseStaging);
              leaseStaging = leaseStagingIdentity = undefined;
            }
            // Record only actually acknowledged phases in this original
            // handle. Never reconstruct an absent record or unlink again.
            if (!ownerRemoved) {
              if (ownerFileCreated) await unlink(ownerPath);
              ownerRemoved = true;
            }
            await rmdir(directoryPath);
            directoryRemoved = true;
          }
          // A successor may now own root/owner. It must never be inspected
          // or removed by this old handle's remaining durability retry.
          retirementDirectory = await open(root, constants.O_RDONLY);
          let syncFailure, syncFailed = false;
          try {
            const physical = await retirementDirectory.stat({bigint: true});
            if (!physical.isDirectory() || physical.dev !== rootDevice || physical.ino !== rootInode) {
              fail('PublicationStoreOwnershipLost');
            }
            await retirementDirectory.sync();
            retirementSynced = true;
          } catch (cause) { syncFailed = true; syncFailure = cause; }
          try {
            if (await retirementDirectory.close() === false) fail('PublicationStoreCleanupPending');
            retirementDirectory = undefined;
          } catch (closeFailure) {
            if (!syncFailed) throw closeFailure;
            const failure = new PublicationStoreError('PublicationStoreCleanupPending', syncFailure);
            failure.primaryFailure = syncFailure;
            failure.cleanupError = closeFailure;
            throw failure;
          }
          if (syncFailed) throw syncFailure;
          released = true;
          return true;
        },
      });
      try {
        const originalDirectory = await lstat(directoryPath, {bigint: true});
        if (!originalDirectory.isDirectory() || originalDirectory.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
        ownershipDevice = originalDirectory.dev; ownershipInode = originalDirectory.ino;
        ownerWriter = await open(ownerPath, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
        ownerFileCreated = true;
        ownerWriterClose = ownerWriter.close;
        if (typeof ownerWriterClose !== 'function') fail('PublicationStoreCleanupPending');
        const physical = await ownerWriter.stat({bigint: true});
        ownerFileIdentity = {dev: physical.dev, ino: physical.ino};
        let offset = 0;
        while (offset < owner.byteLength) {
          const {bytesWritten} = await ownerWriter.write(owner, offset, owner.byteLength - offset, offset);
          if (bytesWritten === 0) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
        await ownerWriter.sync();
        const written = await ownerWriter.stat({bigint: true});
        ownerFileIdentity = Object.fromEntries(
          ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name => [name, written[name]]));
        if (await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) fail('PublicationStoreCleanupPending');
        ownerWriter = undefined;
        ownerWritten = true;
        await syncDirectoryPath(directoryPath);
        if (staging) {
          lease.publishDirectory(`.owner-opening-${token}`, {dev: ownershipDevice, ino: ownershipInode});
          directoryPath = ownershipDirectory; ownerPath = finalOwnerPath; staging = false;
        }
        await syncDirectoryPath(root);
        // A fresh preparer may still own another unpublished stage before
        // qualifying its kernel lease. Our lease proves no custody or stop
        // for that writer: only its original handle may retire its stage.
        return ownership;
      } catch (cause) {
        // The original token/release closure exists before either awaited
        // durability operation. Drain its failed FD before retiring ownership.
        throw await retainStoreOpeningFailure(cause, ownership, key);
      }
    } catch (error) {
      if (error?.cleanupHandle !== undefined) throw error;
      if (error?.code !== 'EEXIST') throw error;
      let existing;
      try { existing = JSON.parse(bootstrap === undefined
        ? await readFile(finalOwnerPath, 'utf8') : await bootstrap.readMetadata(finalOwnerPath)); }
      catch (readError) {
        if (readError?.cleanupHandle !== undefined) throw readError;
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
      // New owners may be reclaimed only under the SAME stable lock. Legacy
      // metadata retains its prior conservative live-PID refusal, but cannot
      // supply a new execution-stop receipt.
      if (existing.leaseAnchor !== undefined) {
        if (lease === undefined) fail('PublicationStoreBusy');
        if (!lease.matches(existing.leaseAnchor)) fail('PublicationStoreLeaseChanged');
      } else if (await processIsAlive(existing.pid)) fail('PublicationStoreBusy');
      const stale = resolve(root, `stale-owner-${randomUUID()}`);
      try { await rename(ownershipDirectory, stale); }
      catch (renameError) {
        if (renameError?.code === 'ENOENT') continue;
        throw renameError;
      }
      await removeOpeningTree(stale, bootstrap);
      await syncDirectoryPath(root);
    }
  }
}

// An opener can fail after acquiring the existing Store owner but before it
// returns a Store. Keep that SAME ownership and any failed physical reader;
// retry only cleanup, never reopen initialization or invent completed custody.
async function retainStoreOpeningFailure(cause, ownership, key) {
  let original = ownership;
  const reader = cause?.cleanupHandle;
  let flight, cleanupError;
  const status = () => Object.freeze({pending: original !== undefined ||
    reader?.status().pending === true});
  const retry = () => {
    if (flight !== undefined) return flight;
    if (!status().pending) { key?.fill(0); return Promise.resolve(status()); }
    flight = Promise.resolve().then(async () => {
      if (reader?.status().pending) {
        await reader.retry();
        if (reader.status().pending) fail('PublicationStoreCleanupPending');
      }
      if (original !== undefined) {
        const released = await original.release();
        // Absence/false is not proof of this opener's successful cleanup.
        if (released !== true) fail('PublicationStoreOwnershipLost');
        original = undefined;
      }
      key?.fill(0);
      return status();
    }).finally(() => { flight = undefined; });
    return flight;
  };
  try { await retry(); }
  catch (error) { cleanupError = error; }
  if (!status().pending) return cause;
  const failure = new Error('PublicationStoreOpeningCleanupPending', {cause});
  failure.code = cause?.code ?? 'PublicationStoreOpeningCleanupPending';
  failure.primaryFailure = cause !== null && typeof cause === 'object' &&
    Object.hasOwn(cause, 'primaryFailure') ? cause.primaryFailure : cause;
  failure.cleanupPending = true;
  failure.cleanupError = cleanupError;
  failure.cleanupHandle = Object.freeze({status, retry});
  return failure;
}

// A prepared original is only the existing physical exclusion duty. It is
// neither a Store/capacity authority nor permission to initialize a format,
// create keys, publish, or repair an unknown prefix.
const preparedStoreOwnerships = new WeakMap();
function originalPreparedStoreOwnership(original) {
  const entry = preparedStoreOwnerships.get(original);
  if (entry === undefined) fail('PublicationStoreOwnershipLost');
  return entry;
}
function preparedOwnershipStatus(entry) {
  return Object.freeze({pending: entry.ownership !== undefined || entry.child !== undefined,
    adopted: entry.phase === 'adopted'});
}
async function releasePreparedOwnership(entry) {
  if (entry.releaseFlight !== undefined) return entry.releaseFlight;
  if (entry.ownership === undefined) return true;
  entry.closing = true;
  entry.releaseFlight = Promise.resolve().then(async () => {
    // The selected Host may share this SAME exclusion with its Journal.
    // Payload cleanup must still run independently, but cannot release the
    // original owner while the retained Journal's physical close is pending.
    // This dependency only delays release; it issues no capacity/authority.
    if (entry.dependency !== undefined) {
      const observation = await Reflect.apply(entry.dependencyStatus, entry.dependency, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('PublicationStoreCleanupPending');
      }
      entry.dependency = entry.dependencyStatus = undefined;
    }
    if (await entry.ownership.release() !== true) fail('PublicationStoreOwnershipLost');
    entry.ownership = undefined;
    entry.phase = 'closed';
    return true;
  }).finally(() => { entry.releaseFlight = undefined; });
  return entry.releaseFlight;
}
export function assertOriginalPreparedLocalPublicationStoreOwnership(original, directory) {
  const entry = originalPreparedStoreOwnership(original);
  if (entry.root !== resolve(directory) || entry.closing ||
      entry.ownership === undefined || !['prepared', 'adopting', 'adopted'].includes(entry.phase)) {
    fail('PublicationStoreOwnershipLost');
  }
}
// Private original custody only: no caller-provided owner or copied flag can
// issue a start receipt or turn a missing execution observation into a stop.
export function captureOriginalLocalExecutionOwner(original) {
  const entry = originalPreparedStoreOwnership(original);
  assertOriginalPreparedLocalPublicationStoreOwnership(original, entry.root);
  return entry.ownership.executionReceipt();
}
export function originalLocalExecutionOwnerStopped(original, receipt) {
  const entry = originalPreparedStoreOwnership(original);
  assertOriginalPreparedLocalPublicationStoreOwnership(original, entry.root);
  return entry.recoveryReady === true && entry.ownership.priorExecutionStopped(receipt);
}
// Only this actual prepared Owner can select first private-key setup. An
// absent key/path or caller flag cannot make an existing Store never-adopted.
export async function assertOriginalPreparedLocalPublicationStoreFirstInitialization(original, directory) {
  assertOriginalPreparedLocalPublicationStoreOwnership(original, directory);
  const entry = originalPreparedStoreOwnership(original);
  await entry.ownership.assertCurrent();
  assertOriginalPreparedLocalPublicationStoreOwnership(original, directory);
  if (!entry.fresh || entry.phase !== 'prepared') {
    fail('PublicationStoreFirstInitializationUnavailable');
  }
}
export async function prepareLocalPublicationStoreOwnership(directory, bounds, dependency, directoryInspection) {
  if (typeof directory !== 'string' || directory.length === 0) fail('InvalidPublicationStoreConfiguration');
  // Capture before any acquisition/callback. The actual Root supplies its
  // original close-only observation, never a replacement DB or public flag.
  const dependencyProperty = dependency !== null && typeof dependency === 'object'
    ? Object.getOwnPropertyDescriptor(dependency, 'status') : undefined;
  if (dependency !== undefined && (dependencyProperty === undefined ||
      !Object.hasOwn(dependencyProperty, 'value') || typeof dependencyProperty.value !== 'function')) {
    fail('InvalidPublicationStoreConfiguration');
  }
  const dependencyStatus = dependencyProperty?.value;
  const root = resolve(directory);
  if (bounds === undefined && directoryInspection !== undefined) {
    fail('InvalidPublicationStoreBootstrapBounds');
  }
  // Ordinary installed Hosts move this same exclusion before their Journal
  // without selecting a resource recipe or changing their existing intake.
  // Selected operational callers still supply their explicit finite bounds.
  const bootstrap = bounds === undefined ? Object.freeze({
    readDirectory: readdir, readMetadata: path => readBounded(path, 4096),
  }) : storeBootstrapAcquisition(bounds, 4096, directoryInspection);
  let names;
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) fail('UnknownPublicationStoreFormat');
    names = await bootstrap.readDirectory(root);
  } catch (cause) {
    if (cause?.code !== 'ENOENT') throw cause;
    await mkdir(root, {recursive: true, mode: 0o700});
    names = await bootstrap.readDirectory(root);
  }
  const fresh = names.length === 0;
  if (!fresh) {
    if (!names.includes('store.json')) fail('UnknownPublicationStoreFormat');
    const contract = JSON.parse(await bootstrap.readMetadata(resolve(root, 'store.json')));
    if (!exactKeys(contract, ['version', 'isolation', 'store_authority_cid']) ||
        contract.version !== 'actql-local-publication-store/0.1' ||
        contract.isolation !== 'execution-namespace' || !cidPattern.test(contract.store_authority_cid)) {
      fail('UnknownPublicationStoreFormat');
    }
  }
  const original = Object.freeze(Object.create(null));
  const entry = {root, fresh, ownership: undefined, phase: 'prepared',
    directoryBootstrap: directoryInspection === undefined ? undefined : bootstrap,
    dependency, dependencyStatus,
    closing: false, releaseFlight: undefined, cleanupFlight: undefined,
    child: undefined, childStatus: undefined, childRetry: undefined, unknownChild: false};
  preparedStoreOwnerships.set(original, entry);
  entry.ownership = await acquireStoreOwnership(root, bootstrap, undefined, fresh, directoryInspection);
  try { await entry.ownership.assertCurrent(); }
  catch (cause) {
    entry.closing = true;
    throw await retainStoreOpeningFailure(cause,
      Object.freeze({release: () => releasePreparedOwnership(entry)}), undefined);
  }
  return original;
}
export function closePreparedLocalPublicationStoreOwnership(original) {
  const entry = originalPreparedStoreOwnership(original);
  entry.closing = true;
  if (entry.cleanupFlight !== undefined) return entry.cleanupFlight;
  entry.cleanupFlight = Promise.resolve().then(async () => {
    if (entry.unknownChild) return preparedOwnershipStatus(entry);
    if (entry.child !== undefined) {
      let state = await Reflect.apply(entry.childStatus, entry.child, []);
      if (state?.pending !== false) state = await Reflect.apply(entry.childRetry, entry.child, []);
      if (state?.pending !== false) return preparedOwnershipStatus(entry);
      entry.child = entry.childStatus = entry.childRetry = undefined;
    }
    // A live/adopting Store owns its children and the same original release.
    // Parent close cannot certify or interrupt that Store's physical work.
    if (entry.phase !== 'adopted' && entry.phase !== 'adopting') {
      await releasePreparedOwnership(entry);
    }
    return preparedOwnershipStatus(entry);
  }).finally(() => { entry.cleanupFlight = undefined; });
  return entry.cleanupFlight;
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
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof value.namespaceId !== 'string' || value.namespaceId.length === 0 ||
      !cidPattern.test(value.authorityScopeCid) ||
      !cidPattern.test(value.runDefinitionCid)) {
    fail('InvalidPublicationIndexKey');
  }
  const hash = createHash('sha256');
  hash.update('actql-local-public-index-key/0.1\0', 'utf8');
  for (const text of [value.namespaceId, value.authorityScopeCid,
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
  suppliedBootstrap,
  preparedOriginal,
  operationalCurrent,
) {
  if (operationalCurrent !== undefined) {
    if (typeof operationalCurrent !== 'function') fail('InvalidPublicationStoreCurrent');
    operationalCurrent();
  }
  const prepared = preparedOriginal === undefined ? undefined : originalPreparedStoreOwnership(preparedOriginal);
  if (prepared !== undefined) {
    if (prepared.phase !== 'prepared' || prepared.closing) fail('PublicationStoreOwnershipLost');
    prepared.phase = 'adopting';
  }
  try {
    return await openOriginalLocalPublicationStore(supplied, suppliedControl, durability,
      suppliedBootstrap, prepared, operationalCurrent);
  } catch (cause) {
    if (prepared !== undefined && prepared.ownership !== undefined) {
      // Retain any original failed child before observing its cleanup ports.
      // Parent retirement never erases an unreadable/pending child carrier.
      try {
        const property = cause !== null && typeof cause === 'object'
          ? Object.getOwnPropertyDescriptor(cause, 'cleanupHandle') : undefined;
        if (property !== undefined) {
          if (!Object.hasOwn(property, 'value')) throw new TypeError('UnobservedStoreCleanup');
          prepared.child = property.value;
          prepared.childStatus = prepared.child.status;
          prepared.childRetry = prepared.child.retry;
          if (typeof prepared.childStatus !== 'function' || typeof prepared.childRetry !== 'function') {
            throw new TypeError('UnobservedStoreCleanup');
          }
        }
      } catch { prepared.unknownChild = true; }
      if (prepared.phase === 'adopting') prepared.phase = 'prepared';
      prepared.closing = true;
    }
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
  let existingNames;
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) {
      fail('UnknownPublicationStoreFormat');
    }
    existingNames = await readOpeningDirectory(root);
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  // Only the same still-held original may explain this exact fresh prefix.
  // Ordinary opens and cold owner-only directories retain their old refusal.
  const preparedFreshPrefix = prepared !== undefined && prepared.fresh &&
    prepared.phase === 'adopting' && prepared.ownership !== undefined &&
    existingNames?.length === 1 && existingNames[0] === 'owner';
  if (existingNames?.length > 0 && !preparedFreshPrefix) {
    if (!existingNames.includes('store.json')) {
      const legacy = existingNames.some(name => [
        'objects', 'contracts', 'indexes', 'staging', 'owner',
      ].includes(name));
      throw Object.assign(new Error(legacy ?
        'LegacyPublicationStoreFormat' : 'UnknownPublicationStoreFormat'), {
        code: legacy ? 'LegacyPublicationStoreFormat' :
          'UnknownPublicationStoreFormat', target: root,
      });
    }
    let previous;
    try {
      previous = JSON.parse(await readOpeningMetadata(storeContractPath));
    } catch (cause) {
      const failure = Object.assign(new Error('UnknownPublicationStoreFormat',
        {cause}), {code: 'UnknownPublicationStoreFormat', target: root});
      // This reader precedes Store ownership. The same original failed FD
      // must remain visible to installed initialization cleanup; wrapping a
      // format refusal must not make that cleanup appear complete.
      if (cause?.cleanupHandle !== undefined) {
        failure.cleanupHandle = cause.cleanupHandle;
        failure.cleanupPending = true;
        failure.cleanupError = cause.cleanupError;
        failure.primaryFailure = cause.primaryFailure ?? cause;
      }
      throw failure;
    }
    if (previous?.version === storeContract.version &&
        previous?.isolation === undefined &&
        typeof previous?.store_authority_cid === 'string') {
      throw Object.assign(new Error('LegacyPublicationStoreFormat'), {
        code: 'LegacyPublicationStoreFormat', target: root});
    }
    if (!exactKeys(previous, ['version', 'isolation',
      'store_authority_cid']) ||
        previous.version !== storeContract.version ||
        previous.isolation !== storeContract.isolation) {
      throw Object.assign(new Error('UnknownPublicationStoreFormat'), {
        code: 'UnknownPublicationStoreFormat', target: root});
    }
    if (!Buffer.from(JSON.stringify(previous), 'utf8')
      .equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
  }
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

  let createdStore = false;
  try {
    await writeExclusive(storeContractPath, storeContractBytes);
    await syncDirectory(root);
    createdStore = true;
  } catch (error) {
    if (error?.cleanupHandle !== undefined) {
      throw await retainStoreOpeningFailure(error, undefined, configuration.privateEvidenceKey);
    }
    if (error?.code !== 'EEXIST') throw error;
    const existing = await readOpeningMetadata(storeContractPath);
    if (!existing.equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
  }

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
  // One bounded durability observation, not a retained contract or Allow.
  // Each public confirmation still acquires and checks its selected record.
  let lastConfirmedDeliveryRecord;
  let lastConfirmedManifestRead;
  const durablyConfirmedClocks = new Map();
  const durablyConfirmedClockFiles = new Map();
  let deliveryAdmissionBusy = Promise.resolve();
  let manifestReadAdmissionBusy = Promise.resolve();
  let clockObservationBusy = Promise.resolve();
  let clockObservationsPending = 0;
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

  const writePhysicalHoldingRecord = async (path, bytes, exclusive = true, finalDirectory) => {
    // Existing holding publication retains its exclusive preparation fence.
    // Independent prepared-object custodies historically write concurrently;
    // they share this same Store's FD duties without a new serialization owner.
    if (exclusive && activePhysicalRecordWriters.size !== 0) fail('PublicationStoreCleanupPending');
    // A failed duty can outlive its payload reservation. Refuse another
    // metadata FD before acquisition until that original duty actually retires;
    // healthy in-flight writes are not a serialization fence.
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    const temporary = resolve(stagingDirectory, `object-${randomUUID()}`);
    let handle, flight;
    const writer = {cleanup: undefined, failed: false};
    activePhysicalRecordWriters.add(writer);
    let original = {writers: activePhysicalRecordWriters, writer, temporary,
      directory: stagingDirectory, syncDirectory, finalNameAcknowledged: false};
    const status = () => Object.freeze({pending: original !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      if (!status().pending) return Promise.resolve(status());
      flight = Promise.resolve().then(async () => {
        if (handle !== undefined) {
          if (await handle.close() === false) fail('PublicationStoreCleanupPending');
          handle = undefined;
        }
        try { await unlink(original.temporary); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
        // A real final-name ACK retains these same synced bytes. Its removed
        // temporary alias is not another durable allocation; exclusive open
        // recovery already removes a crash-resurrected staging alias. Failed
        // publication and unselected holding writers keep their original ACK.
        if (!original.finalNameAcknowledged) {
          await original.syncDirectory(original.directory);
        }
        original.writers.delete(original.writer);
        original = undefined;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    try {
      handle = await open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const {bytesWritten} = await handle.write(bytes, offset, bytes.byteLength - offset, offset);
        if (!Number.isSafeInteger(bytesWritten) || bytesWritten <= 0 ||
            bytesWritten > bytes.byteLength - offset) fail('IncompletePublicationWrite');
        offset += bytesWritten;
      }
      await handle.sync();
      if (await handle.close() === false) fail('PublicationStoreCleanupPending');
      handle = undefined;
      // Final names are exclusive links to complete, synced, closed bytes.
      // The containing holding directory still needs its original separate
      // durability ACK before prepared ownership can be adopted.
      await link(temporary, path);
      if (finalDirectory !== undefined) {
        await syncDirectory(finalDirectory);
        original.finalNameAcknowledged = true;
      }
      writer.cleanup = cleanup;
      await cleanup.retry();
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary);
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };
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
        !physicalHoldingNamespaces.includes(value.namespace) ||
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

  const readPhysicalHoldingAt = async (path, holdingCid) => {
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    const record = parsePhysicalHolding(bytes);
    if (record.holding_cid !== holdingCid) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    return record;
  };

  const readPhysicalHolding = holdingCid =>
    readPhysicalHoldingAt(physicalHoldingPath(holdingCid), holdingCid);

  const readPhysicalHoldingDeletion = holdingCid =>
    readPhysicalHoldingAt(physicalHoldingDeletionPath(holdingCid), holdingCid);

  const parseMetadataInventory = bytes => {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationMetadataInventoryStore', error);
    }
    if (!exactKeys(value, [
      'version', 'namespace_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'publication_attempt_cid', 'contract_objects',
      'physical_holding_cids',
    ]) ||
        value.version !== 'actql-local-publication-metadata-inventory/0.1' ||
        typeof value.namespace_id !== 'string' || value.namespace_id.length === 0 ||
        !cidPattern.test(value.authority_scope_cid) ||
        !cidPattern.test(value.run_definition_cid) ||
        !cidPattern.test(value.public_index_entry_cid) ||
        !cidPattern.test(value.publication_attempt_cid) ||
        !Array.isArray(value.contract_objects) ||
        value.contract_objects.length === 0 ||
        value.contract_objects.some(object => !metadataContractObject(object)) ||
        new Set(value.contract_objects.map(object => object.semantic_cid))
          .size !== value.contract_objects.length ||
        [...value.contract_objects]
          .sort((left, right) =>
            left.semantic_cid.localeCompare(right.semantic_cid))
          .map(object => object.semantic_cid).join('\0') !==
          value.contract_objects.map(object => object.semantic_cid).join('\0') ||
        !value.contract_objects.some(object =>
          object.semantic_cid === value.public_index_entry_cid) ||
        !Array.isArray(value.physical_holding_cids) ||
        value.physical_holding_cids.some(cid => !cidPattern.test(cid)) ||
        new Set(value.physical_holding_cids).size !==
          value.physical_holding_cids.length ||
        [...value.physical_holding_cids].sort().join('\0') !==
          value.physical_holding_cids.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return Object.freeze({
      ...value,
      contract_objects: Object.freeze(value.contract_objects.map(object =>
        Object.freeze({...object}))),
      physical_holding_cids: Object.freeze([...value.physical_holding_cids]),
    });
  };

  const readMetadataInventory = async publicIndexEntryCid => {
    const native = deliveryIndex?.nativePublicationInventory(publicIndexEntryCid);
    if (native !== undefined) return publicationRecoveryValue(native);
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
    const inventory = parseMetadataInventory(bytes);
    if (inventory.public_index_entry_cid !== publicIndexEntryCid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return inventory;
  };

  const readCommittedMetadataInventory = async entry => {
    const inventory = await readMetadataInventory(entry.public_index_entry_cid);
    if (inventory === undefined ||
        inventory.namespace_id !== entry.namespace_id ||
        inventory.authority_scope_cid !== entry.authority_scope_cid ||
        inventory.run_definition_cid !== entry.run_definition_cid ||
        inventory.publication_attempt_cid !== entry.publication_attempt_cid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return inventory;
  };

  const requireCommittedMetadataInventory = async entry => {
    const inventory = await readCommittedMetadataInventory(entry);
    // Only this selected publication's owner links belong to the read.
    // Payload availability remains the actual Result consumer's duty.
    for (const holdingCid of inventory.physical_holding_cids) {
      if (await readPhysicalHoldingDeletion(holdingCid) !== undefined ||
          await readPhysicalHolding(holdingCid) === undefined) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
    }
    return inventory;
  };

  const publicationRecoveryOriginal = value => Object.freeze({
    public_index_cid: value.public_index_entry_cid,
    inventory_wire: JSON.stringify(value),
  });

  const ensureMetadataInventoryFile = async value => {
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

  const stageMetadataInventory = (original, native) => {
    const index = deliveryIndex;
    const stage = native ? index.stageNativePublicationInventory : index.stagePublicationInventory;
    const writer = {failed: false, cleanup: undefined};
    activePhysicalRecordWriters.add(writer);
    try { Reflect.apply(stage, index, [original]); }
    catch (primary) {
      if (primary?.outcome !== 'unknown') {
        activePhysicalRecordWriters.delete(writer);
        throw primary;
      }
      // stage() precedes the Index commit's payload-custody owner. Keep its
      // SAME native mutation here, not only inside an inaccessible DB latch.
      // Finalization confirms storage only; it never publishes or reruns a Run.
      writer.failed = true;
      let pending = true, flight;
      const failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown', primary);
      const status = () => Object.freeze({pending});
      writer.cleanup = Object.freeze({status, retry() {
        if (flight !== undefined) return flight;
        flight = Promise.resolve().then(() => {
          if (pending) {
            Reflect.apply(stage, index, [original]);
            pending = false;
            activePhysicalRecordWriters.delete(writer);
          }
          return status();
        }).finally(() => {
          failure.cleanupPending = pending;
          flight = undefined;
        });
        return flight;
      }});
      failure.outcome = 'unknown';
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = writer.cleanup;
      throw failure;
    }
    activePhysicalRecordWriters.delete(writer);
  };

  const writeNativeIndexOriginal = (method, args, acknowledge, reservation) => {
    const metadataKey = args[0].metadata_key;
    for (const retained of activePhysicalRecordWriters) {
      if (retained.nativeIndexKey === metadataKey && retained.failed) {
        reservation?.release();
        throw retained.failure;
      }
    }
    const index = deliveryIndex, writer = {failed:false,cleanup:undefined,nativeIndexKey:metadataKey};
    let pending = true, flight, failure;
    const status = () => Object.freeze({pending});
    const finish = () => {
      const result = Reflect.apply(method,index,args);
      acknowledge(result);
      reservation?.release();
      pending = false;
      activePhysicalRecordWriters.delete(writer);
      return result;
    };
    writer.cleanup = Object.freeze({status,retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(() => {
        if (pending) finish();
        return status();
      }).finally(() => {if (failure !== undefined) failure.cleanupPending = pending; flight = undefined;});
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try {return finish();}
    catch (primary) {
      if (primary?.outcome !== 'unknown') {
        reservation?.release(); pending = false; activePhysicalRecordWriters.delete(writer); throw primary;
      }
      writer.failed = true;
      failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown',primary);
      failure.outcome = 'unknown'; failure.primaryFailure = primary;
      failure.cleanupPending = true; failure.cleanupHandle = writer.cleanup;
      writer.failure = failure;
      throw failure;
    }
  };

  const ensureMetadataInventory = async value => {
    const original = publicationRecoveryOriginal(value);
    if (deliveryIndex.nativePublicationInventory(original.public_index_cid) === undefined) {
      try {
        // Preserve an existing independently adopted file representation.
        await lstat(metadataInventoryPath(original.public_index_cid));
        stageMetadataInventory(original, false);
        return ensureMetadataInventoryFile(value);
      } catch (error) { if (error?.code !== 'ENOENT') throw error; }
    }
    // The same native transaction owns both the complete inventory original
    // and its pending lookup. Do not also persist a duplicate inventory file.
    stageMetadataInventory(original, true);
    return publicationRecoveryValue(original);
  };

  const publicationRecoveryValue = original => {
    const value = parseMetadataInventory(Buffer.from(original.inventory_wire,'utf8'));
    if (value.public_index_entry_cid !== original.public_index_cid) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return value;
  };

  const restoreMetadataInventory = async (original, value) => {
    const native = deliveryIndex.nativePublicationInventory(original.public_index_cid);
    if (native !== undefined) {
      if (native.inventory_wire !== original.inventory_wire) fail('PublicationMetadataInventoryConflict');
      return value;
    }
    const existing = await readMetadataInventory(original.public_index_cid);
    if (existing === undefined) return ensureMetadataInventoryFile(value);
    if (JSON.stringify(existing) !== original.inventory_wire) fail('PublicationMetadataInventoryConflict');
    return existing;
  };

  const recoverMetadataInventory = async original => {
    const value = publicationRecoveryValue(original);
    const marker = await readMetadataDeletion(indexKey({namespaceId:value.namespace_id,
      authorityScopeCid:value.authority_scope_cid,runDefinitionCid:value.run_definition_cid}));
    if (marker !== undefined) fail('PublicationMetadataDeleted');
    return restoreMetadataInventory(original,value);
  };

  const readMetadataDeletion = async keyHash => {
    let bytes;
    try {
      bytes = await readBounded(
        metadataDeletionPath(keyHash), configuration.maxObjectBytes,
      );
    } catch (error) {
      if (error?.code === 'ENOENT') {
        if (!metadataFencesReady) return undefined;
        const fence = deliveryIndex.metadataDeletionFence(keyHash);
        if (fence === undefined) return undefined;
        if (fence.retired !== 1) fail('InvalidPublicationMetadataDeletionStore');
        return Object.freeze({version:'actql-local-publication-metadata-retired/0.1',
          run_definition_cid:fence.run_cid});
      }
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
      'version', 'namespace_id', 'authority_scope_cid', 'run_definition_cid',
      'public_index_entry_cid', 'results', 'contract_objects',
      'physical_holding_cids', 'requested_at',
    ]) ||
        value.version !== 'actql-local-publication-metadata-deletion/0.1' ||
        typeof value.namespace_id !== 'string' || value.namespace_id.length === 0 ||
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
        value.contract_objects.some(object => !metadataContractObject(object)) ||
        new Set(value.contract_objects.map(object => object.semantic_cid))
          .size !== value.contract_objects.length ||
        [...value.contract_objects]
          .sort((left, right) =>
            left.semantic_cid.localeCompare(right.semantic_cid))
          .map(object => object.semantic_cid).join('\0') !==
        value.contract_objects.map(object => object.semantic_cid).join('\0') ||
        !Array.isArray(value.physical_holding_cids) ||
        value.physical_holding_cids.some(cid => !cidPattern.test(cid)) ||
        new Set(value.physical_holding_cids).size !==
          value.physical_holding_cids.length ||
        [...value.physical_holding_cids].sort().join('\0') !==
          value.physical_holding_cids.join('\0') ||
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
    const original = Object.freeze({metadata_key:keyHash,run_cid:runDefinitionCid});
    pendingMetadataFenceCompletions.set(keyHash,original);
    deliveryIndex.finishMetadataDeletionFence(original);
    pendingMetadataFenceCompletions.delete(keyHash);
    try { await unlink(metadataDeletionPath(keyHash)); }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    // Absence after a lost unlink/ACK reply is not its directory ACK.
    await syncDirectory(metadataDeletionsDirectory);
    return value;
  };

  const ensureMetadataDeletion = async (keyHash, value) => {
    const bytes = Buffer.from(JSON.stringify(value), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    metadataDeletionIntents.add(value.run_definition_cid);
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
    return metadataDeletionIntents.has(runDefinitionCid) ||
      deliveryIndex.hasRunMetadataDeletionFence(runDefinitionCid);
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
    deliveryIndex.beginPhysicalObjectLifetime();
    const token = randomUUID();
    const record = Object.freeze({
      version: 'actql-local-prepared-custody/0.1',
      material_generation_cid: cid,
      byte_count: bytes,
      device: String(state.dev),
      inode: String(state.ino),
    });
    const path = custodyPath(token);
    // Publish a final recovery name only after the original record is complete,
    // synced and closed. An abrupt process stop may leave staging bytes, never
    // a partial final custody. Failed close stays in the same Store duty set.
    await writePhysicalHoldingRecord(path, Buffer.from(JSON.stringify(record), 'utf8'),
      false, custodyDirectory);
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
    if (custody.nativePreparation !== undefined) {
      custody.settlingNative = true;
      deliveryIndex.finishPhysicalPreparations([custody.nativePreparation]);
    } else {
      try { await unlink(custody.path); }
      catch (error) { if (error?.code !== 'ENOENT') throw error; }
      await syncDirectory(custodyDirectory);
    }
    reclaimableCustodies.delete(custody.token);
  };

  const reclaimCustody = custody => {
    const operation = custody.busy.then(async () => {
      if (!reclaimableCustodies.has(custody.token)) return false;
      if (custody.settlingNative) {
        // Retry the same lost metadata settlement before another indexed
        // read. Its physical unlink/alias ACK already completed.
        await removeCustodyRecord(custody);
        return true;
      }
      if (custody.nativePreparation !== undefined &&
          deliveryIndex.pendingPhysicalObject(custody.nativePreparation) === undefined) {
        // Another accepted owner settled this same preparation. Retiring the
        // obsolete recovery holder cannot reclaim that owner's allocation.
        reclaimableCustodies.delete(custody.token);
        return true;
      }
      const cid = custody.record.material_generation_cid;
      const confirmUnlink = async () => {
        if (custody.accounted) {
          await confirmPhysicalRemovals(new Map([[cid,custody.removal]]));
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
        // Complete the SAME possible installation before indexed reference
        // reads. This also settles its lost native COMMIT reply without
        // replaying a payload write, link, business operation or authority.
        await syncDirectory(objectsDirectory);
        confirmPhysicalCapacity([physicalOriginal(cid,custody.record.byte_count,state)],
          custody.nativePreparation !== undefined);
        custody.accounted = true;
        const semanticCid = custody.nativePreparation?.semantic_cid;
        if (semanticCid !== undefined) {
          let alias;
          try { alias = await lstat(contractPath(semanticCid)); }
          catch (error) { if (error?.code !== 'ENOENT') throw error; }
          if (alias !== undefined) {
            if (alias.isFile() && alias.size === state.size &&
                alias.dev === state.dev && alias.ino === state.ino) {
              await verifyObject(cid);
              // This is a fresh ACK of the exact intended alias, not an
              // inference from link count or the interrupted process's reply.
              await syncDirectory(contractsDirectory);
              await removeCustodyRecord(custody);
              return true;
            }
            // A conflicting alias belongs to another allocation. It neither
            // accepts this preparation nor prevents reclaiming this exact
            // unreferenced physical generation below.
          }
        }
        const hasLiveReference = await materialHasLiveReference(cid);
        if (!hasLiveReference) {
          // A second link is not proof that another owner accepted custody.
          // The prepared writer may still own its staging alias.
          if (state.nlink !== 1) {
            return false;
          }
          await verifyObject(cid);
          custody.removal = await rememberPhysicalRemoval(cid, custody.record.byte_count, state);
          custody.pendingUnlink = true;
          await custody.removal.unlinkOriginal();
          await confirmUnlink();
        }
      }
      await removeCustodyRecord(custody);
      return true;
    });
    custody.busy = operation.catch(() => {});
    return operation;
  };

  const reclaimNativePreparation = original => {
    const operation = materialRetentionBusy.then(async () => {
      const token = `native:${original.cid}:${original.device}:${original.inode}`;
      let custody = reclaimableCustodies.get(token);
      if (custody === undefined) {
        const current = deliveryIndex.physicalObject(original.cid);
        custody = {token, nativePreparation: original,
          record: {material_generation_cid: original.cid, byte_count: original.byte_count,
            device: original.device, inode: original.inode},
          accounted: current?.device === original.device && current?.inode === original.inode &&
            current?.byte_count === original.byte_count,
          pendingUnlink: false, busy: Promise.resolve()};
        reclaimableCustodies.set(token, custody);
      }
      return reclaimCustody(custody);
    });
    materialRetentionBusy = operation.catch(() => {});
    return operation;
  };

  const verifyObject = async cid => {
    const path = objectPath(cid);
    active();
    // Borrow the same Store's existing private reader-duty collection. The
    // verifier owns its FD independently of an enclosing semantic/Result read.
    const reader = {cleanup: undefined, failure: undefined};
    activeSemanticReaders.add(reader);
    let handle, readFailure, readFailed = false;
    try {
      let state;
      try { state = await lstat(path); }
      catch (error) {
        if (error?.code === 'ENOENT') fail('PublicationObjectMissing');
        throw error;
      }
      if (!state.isFile() || !quantity(state.size) ||
          state.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationStoreObject');
      }
      handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW |
        constants.O_NONBLOCK);
      const hash = createHash('sha256');
      let bytes = 0;
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes ||
          before.dev !== state.dev || before.ino !== state.ino ||
          before.size !== state.size || before.mtimeMs !== state.mtimeMs) {
        fail('InvalidPublicationStoreObject');
      }
      // This same-FD verifier keeps one explicit overflow-probe byte so growth
      // is still refused before hashing it. Fund W+1 acquisition separately;
      // neither the accepted W nor a later clamp pays for that sentinel.
      // Nothing escapes this verifier's synchronous hash update. Reuse this
      // dedicated backing for short reads instead of a stream's shrink copy
      // or queued next backing; only the same original read is in flight.
      const buffer = Buffer.allocUnsafeSlow(before.size < physicalContentReadWindowBytes ? before.size + 1 : physicalContentReadWindowBytes);
      for (;;) {
        const remaining = before.size - bytes;
        const requested = remaining < buffer.byteLength ? remaining + 1 : buffer.byteLength;
        const {bytesRead} = await handle.read(buffer, 0, requested, bytes);
        if (!quantity(bytesRead) || bytesRead > requested) fail('PublicationObjectCorrupt');
        if (bytesRead === 0) break;
        // Refuse the original overflow probe before hashing any of that
        // read's bytes. The single backing includes its separately funded
        // sentinel even for an initially empty object.
        if (bytesRead > remaining ||
            bytesRead > configuration.maxObjectBytes - bytes) {
          fail('PublicationObjectCorrupt');
        }
        const chunk = bytesRead === buffer.byteLength ? buffer : buffer.subarray(0, bytesRead);
        hash.update(chunk);
        bytes += bytesRead;
      }
      const after = await handle.stat();
      if (!before.isFile() || !after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || bytes !== after.size ||
          hash.digest('hex') !== cidHex(cid)) {
        fail('PublicationObjectCorrupt');
      }
      return Object.freeze({cid, bytes});
    } catch (error) {
      readFailure = error;
      readFailed = true;
      throw error;
    } finally {
      if (handle === undefined) {
        activeSemanticReaders.delete(reader); // No original FD was acquired.
      } else {
        try {
          if (await handle.close() === false) fail('PublicationStoreCleanupPending');
          activeSemanticReaders.delete(reader);
        } catch (closeFailure) {
          // Keep the original FD/primary inside this Store before decorating
          // an outward failure. Retry only close; never verify or open again.
          let original = handle, flight;
          const status = () => Object.freeze({pending: original !== undefined});
          const cleanup = Object.freeze({status, retry() {
            if (flight !== undefined) return flight;
            if (original === undefined) return Promise.resolve(status());
            flight = Promise.resolve().then(async () => {
              if (await original.close() === false) fail('PublicationStoreCleanupPending');
              original = undefined;
              activeSemanticReaders.delete(reader);
              reader.cleanup = reader.failure = undefined;
              return status();
            }).finally(() => { flight = undefined; });
            return flight;
          }});
          const primary = readFailed ? readFailure : closeFailure;
          reader.cleanup = cleanup;
          reader.failure = primary;
          let failure;
          try {
            failure = primary !== null && typeof primary === 'object' &&
              Object.isExtensible(primary) && primary.cleanupHandle === undefined &&
              ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
                const field = Object.getOwnPropertyDescriptor(primary, name);
                return field === undefined || field.writable === true;
              })
              ? primary : new Error('PublicationStoreCleanupPending', {cause: primary});
            failure.cleanupHandle = cleanup;
            failure.cleanupPending = true;
            failure.cleanupError = closeFailure;
          } catch {
            failure = new Error('PublicationStoreCleanupPending', {cause: primary});
            failure.cleanupHandle = cleanup;
            failure.cleanupPending = true;
            failure.cleanupError = closeFailure;
          }
          reader.failure = failure;
          throw failure;
        }
      }
    }
  };

  // One bounded metadata snapshot. A cache hit still checks the physical file;
  // inode, size and both timestamps prevent reuse after replacement or mutation.
  let lastClockObservation;
  const sameClockFile = (left, right) => ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs']
    .every(field => left[field] === right[field]);
  const readClockSnapshot = async clockContractCid => {
    const path = clockObservationPath(clockContractCid);
    let before;
    try {
      before = await lstat(path, {bigint: true});
    } catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    if (!before.isFile() || before.size > BigInt(configuration.maxObjectBytes)) {
      fail('InvalidPublicationStoreObject');
    }
    if (lastClockObservation?.clockContractCid === clockContractCid &&
        sameClockFile(lastClockObservation.state, before)) {
      return lastClockObservation;
    }
    // Keep this original metadata size as the receive ceiling, not merely the
    // Store-wide limit. Growth cannot allocate a larger readFile buffer before
    // the clock/cache mutation check below observes it.
    const bytes = await readBounded(path, Number(before.size));
    const after = await lstat(path, {bigint: true});
    if (!sameClockFile(before, after)) fail('PublicationClockUncertain');
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationClockObservation', error); }
    const checksummed = exactKeys(value, ['clockContractCid', 'observedAt', 'contentSha256']);
    if ((!checksummed && !exactKeys(value, ['clockContractCid', 'observedAt'])) ||
        value.clockContractCid !== clockContractCid ||
        typeof value.observedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, value.observedAt,
        ) !== true) {
      fail('InvalidPublicationClockObservation');
    }
    const observation = Object.freeze({clockContractCid, observedAt: value.observedAt});
    if (checksummed && value.contentSha256 !== createHash('sha256')
      .update(JSON.stringify(observation), 'utf8').digest('hex')) {
      fail('InvalidPublicationClockObservation');
    }
    lastClockObservation = {clockContractCid, state: after, value: observation, checksummed};
    return lastClockObservation;
  };
  const readClockObservation = async clockContractCid =>
    (await readClockSnapshot(clockContractCid))?.value;

  // A confirmed directory entry needs no new directory commit when neither
  // name nor inode changes. Flush every new value on that SAME file instead.
  // Its checksum detects interrupted fixed-length writes; a torn record is
  // unavailable, never an excuse to recover an older floor or create a clock.
  const flushClockFile = async (clockContractCid, snapshot, bytes) => {
    const writer = {cleanup: undefined, failed: false};
    let handle, closeOriginal, flight;
    const status = () => Object.freeze({pending: handle !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        if (handle !== undefined) {
          if (await Reflect.apply(closeOriginal, handle, []) === false) {
            fail('PublicationStoreCleanupPending');
          }
          handle = undefined;
          closeOriginal = undefined;
        }
        activePhysicalRecordWriters.delete(writer);
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try {
      handle = await open(clockObservationPath(clockContractCid),
        constants.O_RDWR | constants.O_NOFOLLOW);
      closeOriginal = handle.close;
      const before = await handle.stat({bigint: true});
      if (!before.isFile() || !sameClockFile(before, snapshot.state) ||
          bytes !== undefined && BigInt(bytes.byteLength) !== before.size) {
        fail('PublicationClockUncertain');
      }
      if (bytes !== undefined) {
        let offset = 0;
        while (offset < bytes.byteLength) {
          const {bytesWritten} = await handle.write(bytes, offset,
            bytes.byteLength - offset, offset);
          if (!Number.isSafeInteger(bytesWritten) || bytesWritten <= 0 ||
              bytesWritten > bytes.byteLength - offset) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
      }
      await handle.sync();
      const written = bytes === undefined ? undefined : await handle.stat({bigint: true});
      if (written !== undefined && (!written.isFile() || written.dev !== before.dev || written.ino !== before.ino ||
          written.size !== before.size)) fail('PublicationClockUncertain');
      await cleanup.retry();
      if (written === undefined) return;
      const current = await lstat(clockObservationPath(clockContractCid), {bigint: true});
      if (!current.isFile() || !sameClockFile(written,current)) fail('PublicationClockUncertain');
      return current;
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary);
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };

  const updateTrustedClock = (clockContractCid, suppliedAt, sample) => {
    active();
    cidHex(clockContractCid);
    if (sample === undefined && (typeof suppliedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, suppliedAt,
        ) !== true)) {
      fail('InvalidPublicationClockObservation');
    }
    clockObservationsPending++;
    const operation = clockObservationBusy.then(async () => {
      for (const writer of activePhysicalRecordWriters) {
        if (writer.failed) fail('PublicationStoreCleanupPending');
      }
      const confirmed = durablyConfirmedClocks.get(clockContractCid);
      const snapshot = await readClockSnapshot(clockContractCid);
      const previous = snapshot?.value;
      // The same queue reads the latest original floor BEFORE sampling. A
      // concurrent accepted observation cannot make an earlier caller sample
      // into a false rollback. A returned sample still owns the full commit.
      const observedAt = sample === undefined ? suppliedAt : sample();
      if (sample !== undefined && (typeof observedAt !== 'string' ||
          contractControl.trustedClockNotBefore(undefined, observedAt) !== true)) {
        fail('InvalidPublicationClockObservation');
      }
      const confirmedFile = durablyConfirmedClockFiles.get(clockContractCid);
      const sameConfirmedInode = confirmedFile !== undefined && snapshot !== undefined &&
        ['dev', 'ino', 'size'].every(field => confirmedFile[field] === snapshot.state[field]);
      // A known durable floor cannot disappear or move backwards while this
      // owner is live. Missing history is not a fresh clock admission.
      if (confirmed !== undefined && (previous === undefined ||
          !contractControl.trustedClockNotBefore(confirmed, previous.observedAt))) {
        fail('PublicationClockUncertain');
      }
      if (contractControl.trustedClockNotBefore(
        previous?.observedAt, observedAt,
      ) !== true) {
        fail('PublicationClockUncertain');
      }
      if (previous?.observedAt === observedAt) {
        if (confirmed !== observedAt || !sameClockFile(confirmedFile ?? {}, snapshot.state)) {
          if (snapshot.checksummed) await flushClockFile(clockContractCid, snapshot);
          if (!sameConfirmedInode) await syncDirectory(clocksDirectory);
          const current = await readClockSnapshot(clockContractCid);
          if (current?.value.observedAt !== observedAt ||
              !['dev', 'ino', 'size'].every(field =>
                current.state[field] === snapshot.state[field])) {
            fail('PublicationClockUncertain');
          }
          durablyConfirmedClocks.set(clockContractCid, observedAt);
          durablyConfirmedClockFiles.set(clockContractCid, current.state);
        }
        return previous;
      }
      const value = Object.freeze({clockContractCid, observedAt});
      const plain = JSON.stringify(value);
      const checked = Buffer.from(JSON.stringify({...value,
        contentSha256: createHash('sha256').update(plain, 'utf8').digest('hex')}), 'utf8');
      // Preserve small legacy Store configurations rather than imposing a new
      // limit. They retain the original atomic replacement protocol.
      const bytes = checked.byteLength <= configuration.maxObjectBytes
        ? checked : Buffer.from(plain, 'utf8');
      if (bytes.byteLength > configuration.maxObjectBytes) {
        fail('PublicationObjectLimit');
      }
      if (snapshot?.checksummed && sameConfirmedInode &&
          snapshot.state.size === BigInt(bytes.byteLength)) {
        const state = await flushClockFile(clockContractCid, snapshot, bytes);
        // This same original FD wrote the already typed value and really
        // synced/closed it. Trusted internal I/O is not another wire input.
        // Keep its physical version so the next operation still detects any
        // intervening change and reads/adopts that new original normally.
        lastClockObservation = {clockContractCid,state,value,checksummed:true};
        durablyConfirmedClocks.set(clockContractCid, observedAt);
        durablyConfirmedClockFiles.set(clockContractCid, state);
        return value;
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
      const current = await readClockSnapshot(clockContractCid);
      if (current?.value.observedAt !== observedAt) {
        fail('PublicationClockUncertain');
      }
      durablyConfirmedClocks.set(clockContractCid, observedAt);
      durablyConfirmedClockFiles.set(clockContractCid, current.state);
      return current.value;
    });
    clockObservationBusy = operation.catch(() => {});
    return operation.finally(() => { clockObservationsPending--; });
  };
  const observeTrustedClock = (clockContractCid, observedAt) =>
    updateTrustedClock(clockContractCid, observedAt);
  const sampleTrustedClock = (clockContractCid, sample) => {
    if (typeof sample !== 'function') fail('InvalidPublicationClockObservation');
    return updateTrustedClock(clockContractCid, undefined, sample)
      .then(observation => observation.observedAt);
  };

  const reserveObjectCapacity = maxBytes => {
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
    let held = true;
    return Object.freeze({
      get held() { return held; },
      release() {
        if (!held) return false;
        reservedBytes -= maxBytes;
        reservedObjects--;
        held = false;
        return true;
      },
    });
  };

  const createObjectWriter = (maxBytes, trackCustody = false) =>
    createObjectWriterOwner(
      maxBytes,
      trackCustody,
      reserveObjectCapacity(maxBytes),
      {
        stagingDirectory,
        objectsDirectory,
        open,
        link,
        unlink,
        syncDirectory,
        fail,
        objectPath,
        isReclaiming: cid => reclaimingMaterialCids.has(cid) || physicalRetirementFences.has(cid),
        registerCustody,
        protectInstallation: true,
        async confirmInstalled(cid, bytes, state, custody, installed) {
          if (installed) confirmPhysicalCapacity([physicalOriginal(cid, bytes, state)]);
          else if (!trackCustody) {
            const selected = await lstat(objectPath(cid));
            const original = physicalOriginal(cid, bytes, selected);
            if (deliveryIndex.pendingPhysicalObject(original) !== undefined) {
              const adoption = materialRetentionBusy.then(async () => {
                // A cleanup may have won while this writer was waiting. Only
                // the still-present original can become its accepted object.
                await verifyObject(cid);
                const current = await lstat(objectPath(cid));
                if (current.dev !== selected.dev || current.ino !== selected.ino || current.size !== bytes) {
                  fail('PublicationObjectAccountingMismatch');
                }
                confirmPhysicalCapacity([original]);
              });
              materialRetentionBusy = adoption.catch(() => {});
              await adoption;
            }
          }
        },
        discardInstallation(cid, bytes, state, custody) {
          settlePhysicalInstalls([physicalOriginal(cid, bytes, state)]);
          if (custody !== undefined) custody.accounted = false;
        },
        finishUntrackedCustody: removeCustodyRecord,
        reclaimCustody,
        verifyObject,
        accountInstalled(bytes, custody, cid, state) {
          const accounted = accountPhysicalInstall(physicalOriginal(cid, bytes, state));
          if (custody !== undefined) custody.accounted = accounted;
        },
      },
    );

  // The recovery record for the installed allocation is shared by every
  // live holder of that generation. A losing seal's temporary inode record
  // cannot replace it. Retiring its first holder transfers this SAME recovery
  // duty to the remaining group, without new bytes or durable authority.
  const retirePreparedHolderCustody = async (group, holder) => {
    const finalHolder = group.holders.size === 1 && group.commitOwners.size === 0;
    const selected = finalHolder ? [...group.custodies]
      : holder.custody === undefined || holder.custody === group.allocationCustody
        ? [] : [holder.custody];
    for (const custody of selected) {
      await removeCustodyRecord(custody);
      group.custodies.delete(custody);
      if (group.allocationCustody === custody) group.allocationCustody = undefined;
    }
    holder.custody = undefined;
  };

  const createPreparedObjectWriter = maxBytes => {
    const writer = createObjectWriter(maxBytes, true);
    return Object.freeze({
      append: frame => writer.append(frame),
      cancel: () => writer.cancel(),
      status: () => writer.status(),
      async seal(expectedCid) {
        const physical = await writer.seal(expectedCid);
        // Join the current generation only after any prior adoption/release
        // finished. Never append to a snapshot that is already being retired.
        const {group, holder} = await withPreparedCustody(physical.cid, () => {
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
            if (physical.created) group.allocationCustody = physical.custody;
          }
          const holder = {active: true, releasing: undefined, custody: physical.custody};
          group.holders.add(holder);
          return {group, holder};
        });
        const errors = [];
        const state = () => Object.freeze({
          pending: holder.active,
          errors: Object.freeze([...errors]),
        });
        const clearCustodies = () => retirePreparedHolderCustody(group, holder);
        const finishPendingUnlink = async () => {
          const pending = group.pendingUnlink;
          if (pending === undefined) return;
          if (!pending.accounted) {
            await confirmPhysicalRemovals(new Map([[physical.cid,pending.removal]]));
            pending.accounted = true;
          }
          await clearCustodies();
          pending.owner.active = false;
          preparedObjectOwners.forgetHolder(pending.owner);
          group.holders.delete(pending.owner);
          group.pendingUnlink = undefined;
        };
        const release = () => {
          if (!holder.active) return Promise.resolve(false);
          if (holder.releasing !== undefined) return holder.releasing;
          // A physical holding and its prepared release use the same existing
          // material queue. An awaited directory ACK must not race reclamation.
          const previous = group.busy;
          const operation = materialRetentionBusy.then(() => previous).then(() =>
            withPreparedCustody(physical.cid, async () => {
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
            const adoptedStillRetained = group.committed &&
              await materialHasLiveReference(physical.cid);
            if (adoptedStillRetained || group.holders.size > 1 ||
                !group.removable) {
              const finalHolder = group.holders.size === 1 &&
                group.commitOwners.size === 0;
              await clearCustodies();
              group.holders.delete(holder);
              holder.active = false;
              preparedObjectOwners.forgetHolder(holder);
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
              await clearCustodies();
              group.holders.delete(holder);
              holder.active = false;
              preparedObjectOwners.forgetHolder(holder);
              preparedObjects.delete(physical.cid);
              return true;
            }
            // Physical holdings refer to bytes by CID, not inode hard links.
            // A visible holding after a lost commit ACK is still responsibility,
            // not permission to unlink. Keep this exact pending handle until
            // the same commit is confirmed or its holding is lawfully retired.
            if (await materialHasLiveReference(physical.cid)) return false;
            const removal = await rememberPhysicalRemoval(physical.cid, before.size, before);
            group.pendingUnlink = {
              removal,
              owner: holder,
              bytes: before.size,
              accounted: false,
            };
            await removal.unlinkOriginal();
            group.removable = false;
            await finishPendingUnlink();
            if (group.holders.size === 0 &&
                group.commitOwners.size === 0) {
              preparedObjects.delete(physical.cid);
            }
            return true;
          }));
          group.busy = operation.catch(() => {});
          materialRetentionBusy = group.busy;
          holder.releasing = operation.catch(error => {
            // Private diagnostics retain the original first and latest
            // failed release, not an unbounded retry log. Keep both roles
            // even when the same Error is reused; status snapshots own their
            // copied arrays. This never settles the original physical duty.
            retainFirstAndLatestCleanupError(errors, error);
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
        preparedObjectOwners.register(prepared, {
          cid: physical.cid,
          bytes: physical.bytes, group, holder,
        });
        return Object.freeze({
          cid: physical.cid,
          bytes: physical.bytes,
          created: physical.created,
          prepared,
        });
      },
    });
  };

  // A durable witness can make an original holder releasable, but it cannot
  // choose that holder's terminal transition. The handle still owns release.
  const confirmPreparedMaterials = async cids => {
    for (const cid of new Set(cids)) await withPreparedCustody(cid, () => {
      const group = preparedObjects.get(cid);
      if (group !== undefined) group.committed = true;
    });
  };

  // A durable adoption witness transfers only the selected original holders.
  // Neither a CID match nor a read/confirmation grants another holder's duty.
  const adoptPreparedObjects = async selected => {
    for (const original of selected) {
      const {cid, group, holder} = original;
      await withPreparedCustody(cid, async () => {
        if (!holder.active) return;
        if (preparedObjects.get(cid) !== group || !group.holders.has(holder)) {
          fail('InvalidPublicationPreparedOwner');
        }
        await retirePreparedHolderCustody(group, holder);
        group.committed = true;
        holder.active = false;
        preparedObjectOwners.forgetHolder(holder);
        group.holders.delete(holder);
        if (group.holders.size === 0 && group.commitOwners.size === 0) preparedObjects.delete(cid);
      });
    }
  };

  const beginPreparedCommit = async (cids, key, indexCid, selected = [], ownRetention) => {
    const owner = {
      pending: false,
      outcome: undefined,
      groups: new Set(),
      errors: [],
    };
    const acquired = [];
    const settlePins = async outcome => {
      // A pin can be the final borrower of an allocation's recovery record
      // after its last holder transferred to a now-retired durable owner.
      // End that shared duty under the SAME material -> metadata ordering.
      const retirement = materialRetentionBusy.then(async () => {
        for (const [cid, group] of acquired) {
          await withPreparedCustody(cid, async () => {
            group.commitOwners.delete(owner);
            if (group.holders.size === 0 && group.commitOwners.size === 0) {
              const durablyRetained = outcome === 'committed' &&
                ownRetention !== undefined && await ownRetention(cid) ||
                await materialHasLiveReference(cid);
              for (const custody of [...group.custodies]) {
                if (durablyRetained) await removeCustodyRecord(custody);
                else if (!await reclaimCustody(custody)) fail('PublicationPreparedCustodyPending');
                group.custodies.delete(custody);
                if (group.allocationCustody === custody) group.allocationCustody = undefined;
              }
              if (preparedObjects.get(cid) === group) preparedObjects.delete(cid);
            }
            owner.groups.delete(group);
          });
        }
      });
      materialRetentionBusy = retirement.catch(() => {});
      await retirement;
      acquired.length = 0;
      owner.pending = false;
      owner.outcome = outcome;
    };
    try {
      // Join physical reclamation before taking any per-CID metadata queue.
      // Verification alone cannot pin an already adopted original: its last
      // durable Result may be retiring while this new Index is installed.
      const acquisition = materialRetentionBusy.then(async () => {
        for (const cid of new Set(cids)) {
          await withPreparedCustody(cid, async () => {
            let group = preparedObjects.get(cid);
            if (group === undefined) {
              await verifyObject(cid);
              // This is only a temporary retention pin, never new payload
              // custody or permission to unlink the pre-existing original.
              group = {holders: new Set(), commitOwners: new Set(),
                removable: false, committed: false, pendingUnlink: undefined,
                custodies: new Set(), busy: Promise.resolve()};
              preparedObjects.set(cid, group);
            }
            group.commitOwners.add(owner);
            owner.groups.add(group);
            acquired.push([cid, group]);
            owner.pending = true;
          });
        }
      });
      materialRetentionBusy = acquisition.catch(() => {});
      await acquisition;
    } catch (cause) {
      // No install has started. Return only these temporary commit pins;
      // prepared holders and any failed physical reader keep their own duties.
      await settlePins('uncommitted');
      throw cause;
    }
    const status = () => Object.freeze({
      pending: owner.pending,
      outcome: owner.outcome,
      errors: Object.freeze([...owner.errors]),
    });
    const resolveConfirmed = async entry => {
      if (!owner.pending) return status();
      if (entry?.public_index_entry_cid === indexCid) {
        await adoptPreparedObjects(selected);
        await settlePins('committed');
      } else {
        await settlePins('uncommitted');
      }
      return status();
    };
    return Object.freeze({
      status,
      resolveConfirmed,
      settleAdopted: () => settlePins('committed'),
      async retry() {
        if (!owner.pending) return status();
        try {
          return await resolveConfirmed(await confirmCommittedIndex(key));
        } catch (error) {
          retainFirstAndLatestCleanupError(owner.errors, error);
          throw error;
        }
      },
    });
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
      } catch (error) { retainFirstAndLatestCleanupError(cleanupErrors, error); }
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
            catch (error) { retainFirstAndLatestCleanupError(cleanupErrors, error); }
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
  const putDeliveryContracts = async (grant, attempt, streaming) => {
    await putSemanticBatch([grant, attempt, ...(streaming === undefined ? [] : [streaming])].map(contract => ({
      wire: contract.wire, semanticCid: contract.identity,
    })));
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
        await confirmPhysicalRemovals(new Map([[group.record.physical_cid,group.unconfirmedPhysical.removal]]));
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
        if (!group.generationRetired && physical === undefined &&
            group.generation !== undefined) {
          // A crash can leave the original quota row after unlink, before
          // its directory ACK. Only this prepared generation can settle it;
          // absence never refunds a successor with the same content CID.
          const original = deliveryIndex.physicalObject(group.record.physical_cid);
          if (original !== undefined &&
              original.byte_count === group.record.byte_count &&
              original.device === group.generation.device &&
              original.inode === group.generation.inode) {
            const removal = await rememberPhysicalRemoval(group.record.physical_cid, group.record.byte_count);
            group.unconfirmedPhysical = {bytes: group.record.byte_count, ...group.generation, removal};
            await confirmPhysicalRemovals(new Map([[group.record.physical_cid, removal]]));
            group.unconfirmedPhysical = undefined;
          }
          group.generationRetired = true;
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
            const removal = await rememberPhysicalRemoval(group.record.physical_cid,group.record.byte_count,remaining);
            group.unconfirmedPhysical = {
              removal,
              bytes: group.record.byte_count,
              device: String(remaining.dev),
              inode: String(remaining.ino),
            };
            await confirmPhysicalRemovals(new Map([[group.record.physical_cid, removal]]));
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
      if (holder.path !== undefined) {
        try { await unlink(holder.path); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
        await syncDirectory(preparedSchemasDirectory);
      }
      group.holders.delete(holder);
      holder.active = false;
      if (group.holders.size === 0) {
        preparedSchemas.delete(group.record.semantic_cid);
      }
      return true;
    });
    holder.releasing = flight.catch(error => {
      retainFirstAndLatestCleanupError(holder.errors, error);
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
      const durable = adopted.filter(holder => holder.path !== undefined);
      for (const holder of durable) {
        try { await unlink(holder.path); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
      }
      if (durable.length !== 0) await syncDirectory(preparedSchemasDirectory);
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
        // A visible link from an unsettled writer is not a durable original.
        // Keep the existing write/ACK protocol until those duties complete.
        path: group.removable || activePhysicalRecordWriters.size !== 0
          ? preparedSchemaPath(token) : undefined,
        active: true,
        releasing: undefined, errors: [], runDefinitionCid,
      };
      const record = Object.freeze({
        ...group.record, run_definition_cid: runDefinitionCid,
      });
      group.holders.add(holder);
      const prepared = preparedSchemaHandle(group, holder);
      try {
        let stored, generation;
        if (holder.path !== undefined) {
          // Newly created bytes need the existing crash-reclamation marker.
          await writeExclusive(holder.path,
            Buffer.from(JSON.stringify(record), 'utf8'));
          await syncDirectory(preparedSchemasDirectory);
          stored = await putSemantic(wire, semanticCid);
        } else {
          // An already owned immutable schema creates no new durable state.
          // Acquire this operation's real original; retain its live holder,
          // without rewriting crash markers for an allocation we cannot delete.
          const original = await readSemanticOriginal(semanticCid, false, true);
          if (original.physicalCid !== physicalCid ||
              !exactUtf8WireMatches(original.bytes, wire)) {
            fail('PublicationObjectIdentityMismatch');
          }
          stored = Object.freeze({semanticCid, physical: Object.freeze({
            cid: physicalCid, bytes: original.bytes.byteLength, created: false,
          }), created: false});
          generation = original.generation;
        }
        if (generation === undefined) {
          // A writer still needs its actual final aliases observed. An
          // existing body's reader already checked these same inode/extent
          // facts while acquiring its bytes in this preparation.
          const physical = await lstat(objectPath(physicalCid));
          const semantic = await lstat(contractPath(semanticCid));
          if (!physical.isFile() || !semantic.isFile() ||
              physical.dev !== semantic.dev ||
              physical.ino !== semantic.ino ||
              physical.size !== bytes.byteLength) {
            fail('PublicationPreparedSchemaGenerationMismatch');
          }
          generation = Object.freeze({
            device: String(physical.dev), inode: String(physical.ino),
          });
        }
        if (group.generation !== undefined &&
            (group.generation.device !== generation.device ||
              group.generation.inode !== generation.inode)) {
          fail('PublicationPreparedSchemaGenerationMismatch');
        }
        if (holder.path !== undefined) {
          const staged = resolve(preparedSchemasDirectory,
            `.staging-${randomUUID()}.json`);
          await writeExclusive(staged, Buffer.from(JSON.stringify({
            ...record, ...generation,
          }), 'utf8'));
          await rename(staged, holder.path);
          await syncDirectory(preparedSchemasDirectory);
        }
        group.generation = generation;
        return Object.freeze({...stored, prepared});
      } catch (error) {
        // A new allocation keeps its durable marker. Every path retains the
        // same acquired reader/holder cleanup without resending any data.
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
    try {
      // UTF-8 wire extent bounds JSON value-node count (including containers).
      // Preserve an explicitly narrower configured policy. This does not grant
      // parser memory: admission remains the selected Store service operation,
      // under its object limit and existing opaque runtime support envelope.
      const wireBytes = Buffer.byteLength(wire, 'utf8');
      contract = contractControl.admit(name, wire, Object.freeze({
        ...contractLimits, maxNodes: Math.min(contractLimits.maxNodes, wireBytes),
      }));
    }
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

  const admitOriginalContract = (name, wire, original) => {
    let contract;
    if (original !== undefined && typeof contractControl.admitOriginal === 'function') {
      try { contract = contractControl.admitOriginal(original, contractLimits); }
      catch (error) { fail('InvalidPublicationContract', error); }
      if (contract !== undefined &&
          (contract !== original || !Object.isFrozen(contract) ||
            typeof contract.name !== 'string' || contract.name !== name ||
            typeof contract.identityField !== 'string' ||
            !cidPattern.test(contract.identity) || contract.wire !== wire ||
            typeof contract.wire !== 'string' ||
            Buffer.byteLength(contract.wire, 'utf8') > configuration.maxObjectBytes)) {
        fail('InvalidPublicationContractControlResult');
      }
    }
    // Unrecognized originals and legacy controls still use full admission.
    // An actual refusal or malformed nominal response never takes this path.
    return contract ?? admitContract(name, wire);
  };

  // Only this Store's private incoming-contract admission supplies these
  // facts. Physical persistence remains the same original operation.
  const putAdmittedPublicationContract = async (contract, value) => {
    const semanticCid = contract.identity;
    if (nativePublicationContract(contract.name) && deliveryIndex?.publicationContract(semanticCid) !== undefined) {
      return (await putNativePublicationContracts([Object.freeze({contract,value})]))[0];
    }
    return Object.freeze({
      value,
      contract,
      ...await putSemantic(contract.wire, semanticCid),
    });
  };

  const putPublicationContract = async (name, suppliedWire) => {
    const contract = admitContract(name, suppliedWire);
    return putAdmittedPublicationContract(contract, parseContract(contract));
  };

  const putNativePublicationContracts = async (admitted, progress) => {
    active();
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    const entries = [], results = [], reservations = [];
    let selection;
    let reservationBytes = 0;
    try {
      for (const original of admitted) {
        const {contract} = original;
        // Existing file originals remain files. Do not duplicate their charge
        // or silently replace an independently adopted physical representation.
        try {
          await lstat(contractPath(contract.identity));
          const retained = await readSemanticOriginal(contract.identity, false);
          if (!exactUtf8WireMatches(retained.bytes, contract.wire)) fail('PublicationSemanticIdentityConflict');
          results.push(Object.freeze({...original, semanticCid:contract.identity, storage:'file', created:false}));
          continue;
        } catch (error) { if (error?.code !== 'ENOENT') throw error; }
        const entry = Object.freeze({semantic_cid:contract.identity,name:contract.name,
          wire:contract.wire,byte_count:Buffer.byteLength(contract.wire,'utf8')});
        entries.push(entry);
        results.push(Object.freeze({...original, semanticCid:contract.identity, storage:'sqlite'}));
      }
      // Files retain their original representation. Select only the remaining
      // native keys together for quota preflight; mutation still owns its
      // actual selected-row conflict check and durable transaction.
      selection = entries.length === 0 ? undefined :
        deliveryIndex.publicationContracts(entries.map(entry => entry.semantic_cid));
      const selected = new Map((selection ?? []).map(entry => [entry.semantic_cid, entry]));
      for (const entry of entries) {
        const existing = selected.get(entry.semantic_cid);
        if (existing !== undefined && (existing.name !== entry.name || existing.wire !== entry.wire)) {
          fail('PublicationSemanticIdentityConflict');
        }
        if (existing === undefined) {
          reservations.push(reserveObjectCapacity(entry.byte_count));
          reservationBytes += entry.byte_count;
        }
      }
      for (let index = 0; index < results.length; index++) {
        const result = results[index];
        if (result.storage === 'sqlite') results[index] = Object.freeze({...result,
          created:!selected.has(result.semanticCid)});
      }
    } catch (error) {
      for (const reservation of reservations) reservation.release();
      throw error;
    }
    if (entries.length === 0 && progress === undefined) return Object.freeze(results);
    const originalEntries = Object.freeze(entries);
    const allowance = Object.freeze({objects:reservations.length,bytes:reservationBytes});
    const writer = {failed:false,cleanup:undefined};
    let pending = true, flight, failure, progressCreated;
    const finish = () => {
      const usage = deliveryIndex.putPublicationContracts(originalEntries,allowance,progress,selection);
      progressCreated = usage.progressCreated;
      accountNativePublication(usage);
      for (const reservation of reservations) reservation.release();
      pending = false;
      activePhysicalRecordWriters.delete(writer);
    };
    const status = () => Object.freeze({pending});
    writer.cleanup = Object.freeze({status,retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(() => {
        if (pending) finish();
        if (failure !== undefined) failure.cleanupPending = pending;
        return status();
      })
        .finally(() => { flight = undefined; });
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try { finish(); }
    catch (error) {
      if (error?.outcome !== 'unknown') {
        for (const reservation of reservations) reservation.release();
        pending = false;
        activePhysicalRecordWriters.delete(writer);
        throw error;
      }
      writer.failed = true;
      // The same bodies and capacity reservation remain owned until an actual
      // same-database write confirms their outcome. Visibility is not an ACK.
      failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown',error);
      failure.outcome = 'unknown';
      failure.primaryFailure = error;
      failure.cleanupPending = true;
      failure.cleanupHandle = writer.cleanup;
      throw failure;
    }
    return Object.freeze(results.map(result => progress === undefined ? result :
      Object.freeze({...result,progressCreated})));
  };

  const admitPublicationContracts = (supplied, originals) => {
    active();
    if (!Array.isArray(supplied)) fail('InvalidPublicationContractWire');
    const count = supplied.length;
    if (!Number.isSafeInteger(count) || count < 0 || count > configuration.maxObjects) {
      fail('PublicationStoreObjectLimit');
    }
    // Own the finite input before an admission callback or physical await.
    const inputs = Array.from({length: count}, (_, index) => {
      const input = supplied[index];
      if (!exactKeys(input, originals
        ? ['name', 'identityField', 'identity', 'wire'] : ['name', 'wire'])) {
        fail('InvalidPublicationContractWire');
      }
      return Object.freeze({name: input.name, wire: input.wire,
        original: originals ? input : undefined});
    });
    const admitted = [], identities = new Map(), wires = new Map();
    let bytes = 0n;
    for (const input of inputs) {
      const sameWire = wires.get(input.wire);
      if (sameWire !== undefined && sameWire.contract.name === input.name) continue;
      const contract = admitOriginalContract(input.name, input.wire, input.original);
      const value = parseContract(contract);
      const previous = identities.get(contract.identity);
      if (previous !== undefined) {
        if (previous.contract.name !== contract.name || previous.contract.wire !== contract.wire) {
          fail('PublicationSemanticIdentityConflict');
        }
        continue;
      }
      bytes += BigInt(Buffer.byteLength(contract.wire, 'utf8'));
      if (bytes > BigInt(configuration.capacityBytes)) fail('PublicationStoreCapacity');
      const original = Object.freeze({contract, value});
      admitted.push(original);
      identities.set(contract.identity, original);
      wires.set(input.wire, original);
    }
    return admitted;
  };

  const putAdmittedPublicationContracts = async (admitted, originals, progress) => {
    const nativeOnly = admitted.every(({contract}) => nativePublicationContract(contract.name));
    if (originals && nativeOnly) {
      return putNativePublicationContracts(admitted, progress);
    }
    const existingNative = new Map();
    for (const original of admitted) {
      const {contract} = original;
      if (!nativePublicationContract(contract.name)) continue;
      const retained = deliveryIndex.publicationContract(contract.identity);
      if (retained === undefined) continue;
      if (retained.name !== contract.name || retained.wire !== contract.wire) {
        fail('PublicationSemanticIdentityConflict');
      }
      existingNative.set(contract.identity,Object.freeze({...original,
        semanticCid:contract.identity,storage:'sqlite',created:false}));
    }
    if (nativeOnly && existingNative.size !== 0) return putNativePublicationContracts(admitted, progress);
    // A legacy file member does not turn an already native sibling into a
    // second file allocation. Only the remaining original files enter the
    // unchanged physical batch and its actual capacity/ACK protocol.
    const stored = await putSemanticBatch(admitted.filter(({contract}) =>
      !existingNative.has(contract.identity)).map(({contract}) => ({
      wire: contract.wire, semanticCid: contract.identity,
    })));
    let physicalIndex = 0;
    return Object.freeze(admitted.map(original => existingNative.get(original.contract.identity) ??
      Object.freeze({...original,...stored[physicalIndex++]})));
  };

  const putPublicationContractBatch = async (supplied, originals) =>
    putAdmittedPublicationContracts(admitPublicationContracts(supplied, originals), originals);

  const putPublicationContracts = supplied => putPublicationContractBatch(supplied, false);
  const putOriginalPublicationContracts = supplied => putPublicationContractBatch(supplied, true);

  const admitNativeContract = (native, cid, name, retained) => {
    if (native === undefined) return undefined;
    if (name !== undefined && native.name !== name) fail('InvalidDeliveryAttemptIndex');
    const contract = retained?.identity === cid && retained.name === native.name && retained.wire === native.wire
      ? retained : admitContract(native.name,native.wire);
    if (contract.identity !== cid) fail('InvalidDeliveryAttemptIndex');
    return contract;
  };
  const nativeDeliveryContract = (cid, name, retained) =>
    admitNativeContract(deliveryIndex?.contract(cid), cid, name, retained);

  const readSemanticOriginal = async function readSemanticBytes(cid, includeNative = true, retainGeneration = false, retained) {
    const path = contractPath(cid);
    active();
    // A typed publication read already selected its table. A missing row may
    // fall back to the original file, without probing unrelated deliveries.
    const nativeRecord = includeNative === 'publication'
      ? deliveryIndex?.publicationContract(cid)
      : includeNative ? deliveryIndex?.contract(cid) : undefined;
    // A commit may already hold this same immutable issued contract. Compare
    // the actual selected row before asking its original control to reuse it;
    // changed rows and unknown/copy/legacy originals keep full admission.
    const native = nativeRecord !== undefined && retained?.identity === cid &&
      retained.name === nativeRecord.name && retained.wire === nativeRecord.wire
      ? admitOriginalContract(nativeRecord.name, nativeRecord.wire, retained)
      : admitNativeContract(nativeRecord,cid);
    if (native !== undefined && native.identity !== cid) fail('InvalidDeliveryAttemptIndex');
    if (native !== undefined) return Object.freeze({bytes: Buffer.from(native.wire,'utf8'), native,
      publication: includeNative === 'publication' || nativeRecord.publication === true});
    // This is the original read duty in the same Store lifetime. Keep its
    // private failure reachable even when a public ingress redacts the Error.
    const reader = {cleanup: undefined, failure: undefined};
    activeSemanticReaders.add(reader);
    let handle;
    try { handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW); }
    catch (error) {
      activeSemanticReaders.delete(reader); // No original FD was acquired.
      if (error?.code === 'ENOENT') fail('PublicationContractMissing');
      throw error;
    }
    let readFailure, readFailed = false;
    try {
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationContractObject');
      }
      // The original FD extent bounds both acquisition and the private output
      // before copying. A small contract must not acquire a default64KiB
      // stream backing or return an unrelated pooled backing.
      const bytes = Buffer.allocUnsafeSlow(before.size);
      const hash = createHash('sha256');
      let size = 0;
      if (before.size > 0) {
        const stream = handle.createReadStream({autoClose: false,
          end: before.size - 1, highWaterMark: Math.min(physicalContentReadWindowBytes, before.size)});
        for await (const chunk of stream) {
          if (chunk.byteLength > before.size - size ||
              chunk.byteLength > configuration.maxObjectBytes - size) {
            fail('PublicationContractCorrupt');
          }
          chunk.copy(bytes, size);
          hash.update(chunk);
          size += chunk.byteLength;
        }
      }
      const after = await handle.stat();
      const physicalCid = `sha256:${hash.digest('hex')}`;
      const physical = await lstat(objectPath(physicalCid));
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || size !== after.size ||
          physical.dev !== after.dev || physical.ino !== after.ino ||
          physical.size !== after.size || physical.mtimeMs !== after.mtimeMs) {
        fail('PublicationContractCorrupt');
      }
      // This original FD already supplied every hashed byte, and the digest's
      // object path names the same unchanged hard-linked allocation. Reopening
      // that allocation to hash it again adds no independent fact. A later
      // read still acquires and validates its own original; no Store-wide
      // successful-digest cache substitutes for that observation.
      if (retainGeneration) return Object.freeze({bytes, physicalCid, generation: Object.freeze({
        device: String(after.dev), inode: String(after.ino),
      })});
      return Object.freeze({bytes, physicalCid});
    } catch (error) {
      readFailure = error;
      readFailed = true;
      throw error;
    } finally {
      try {
        if (await handle.close() === false) fail('PublicationSemanticReaderCleanupPending');
        activeSemanticReaders.delete(reader);
      } catch (closeFailure) {
        // Preserve this same original FD and primary failure. Cleanup retries
        // close only: never reopen, reread, or release the Store on rejection.
        let original = handle, flight;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(async () => {
            if (await original.close() === false) fail('PublicationSemanticReaderCleanupPending');
            original = undefined;
            activeSemanticReaders.delete(reader);
            reader.cleanup = reader.failure = undefined;
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
        const primary = readFailed ? readFailure : closeFailure;
        // Own the duty before inspecting/decorating the outward Error. An
        // ordinary extensible Error can already have a readonly cleanup field.
        reader.cleanup = cleanup;
        reader.failure = primary;
        let failure;
        try {
          failure = primary !== null && typeof primary === 'object' &&
            Object.isExtensible(primary) && primary.cleanupHandle === undefined &&
            ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
              const field = Object.getOwnPropertyDescriptor(primary, name);
              return field === undefined || field.writable === true;
            })
            ? primary : new Error('PublicationSemanticReaderCleanupPending', {cause: primary});
          failure.cleanupHandle = cleanup;
          failure.cleanupPending = true;
          failure.cleanupError = closeFailure;
        } catch {
          failure = new Error('PublicationSemanticReaderCleanupPending', {cause: primary});
          failure.cleanupHandle = cleanup;
          failure.cleanupPending = true;
          failure.cleanupError = closeFailure;
        }
        reader.failure = failure;
        throw failure;
      }
    }
  };

  // Public callers receive their own mutable bytes. The private observation
  // also retains the digest of this exact allocation after its real FD close.
  const readSemanticBytes = async (cid, includeNative = true) =>
    (await readSemanticOriginal(cid, includeNative)).bytes;

  // Private evidence uses the prepared-object and physical-holding custody
  // already used by Transfer. A semantic alias before a durable owner would
  // strand ciphertext on a crash, so this path never creates one.
  // The Local continuation namespace holds only Local continuation evidence.
  const privateEvidenceHolding = (holding, name) =>
    holding?.namespace === 'publication-private' ||
    (holding?.namespace === 'local-continuation-private' &&
      localContinuationEvidenceNames.includes(name));
  const privateEvidenceAad = (name, semanticCid) => {
    const text = `actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`;
    // Preserve the exact historical preimage without borrowing a larger pool
    // slab through crypto/read/cleanup. String/control and crypto scratch are
    // still separate original-envelope costs; exact extent is not a grant.
    const bytes = Buffer.allocUnsafeSlow(Buffer.byteLength(text, 'utf8'));
    bytes.write(text, 0, bytes.byteLength, 'utf8');
    return bytes;
  };
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
    // The bounded envelope and strict alphabet above fix the decoded extent.
    // Noncanonical padding bits still fail the same round-trip check below.
    // Keep nonce/tag/ciphertext on dedicated backings, not shared pool slices.
    const length = value.length / 4 * 3 - (value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0);
    if (bytes !== undefined && length !== bytes) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    const decoded = Buffer.allocUnsafeSlow(length);
    if (decoded.write(value, 0, length, 'base64') !== length ||
        decoded.toString('base64') !== value) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    return decoded;
  };
  const readPrivateEvidenceObject = async (
    name, semanticCid, holdingCid, index = 0, objectCount = 1, originalHolding,
    retainOriginalRead,
  ) => {
    active();
    if (typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name)) {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(semanticCid);
    cidHex(holdingCid);
    // This private getter reads the same immutable Store configuration with
    // no await/caller callback between size validation and copying. Do not add
    // an original-key alias to the async reader frame; only its copy escapes.
    const key = Buffer.allocUnsafeSlow(privateEvidenceKey().byteLength);
    key.set(privateEvidenceKey());
    try {
      // No plaintext or application callback escapes this private acquisition.
      // Admit the selected holding once; consume/hash its ciphertext once on
      // the original FD below, then authenticate AEAD before returning bytes.
      let holding = originalHolding;
      if (holding === undefined) {
        if (await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
          fail('PublicationPrivateEvidenceUnavailable');
        }
        holding = await readPhysicalHolding(holdingCid);
      }
      if (!privateEvidenceHolding(holding, name) ||
          holding.manifest_cid !== semanticCid ||
          holding.objects.length !== objectCount) {
        fail('PublicationPrivateEvidenceUnavailable');
      }
      const expectedBytes = holding.objects[index].byte_count;
      if (!Number.isSafeInteger(expectedBytes) || expectedBytes < 0 ||
          expectedBytes > configuration.maxObjectBytes) {
        fail('PublicationPrivateEvidenceCorrupt');
      }
      if (retainOriginalRead !== undefined) {
        retainOriginalRead(holding);
        active();
      }
      // The existing holding owns an exact bounded file. Receive directly
      // into one buffer instead of retaining copied chunks plus their concat.
      // No bytes escape before the same physical read/close and AEAD succeed.
      const bytes = Buffer.alloc(expectedBytes);
      let receivedBytes = 0;
      try {
        await consumeSelectedPhysicalHolding(holding, index, chunk => {
          if (chunk.byteLength > expectedBytes - receivedBytes) {
            fail('InvalidPublicationPhysicalHoldingStore');
          }
          bytes.set(chunk, receivedBytes);
          receivedBytes += chunk.byteLength;
        });
      } catch (error) {
        if (error?.code === 'ENOENT' && error.cleanupHandle === undefined) {
          fail('PublicationObjectMissing', error);
        }
        throw error;
      }
      if (receivedBytes !== expectedBytes) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      let plaintext;
      try {
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
        plaintext = decipher.update(ciphertext);
        // Authentication must complete before any plaintext escapes. Reuse
        // the owned block only after final succeeds with no additional bytes;
        // otherwise preserve the complete authenticated concatenation.
        const final = decipher.final();
        return final.byteLength === 0 ? plaintext
          : Buffer.concat([plaintext, final]);
      } catch (error) {
        // update() can materialize unauthenticated plaintext before final()
        // rejects. That failed child never reaches the outer consumer, so its
        // SAME backing must be retired here rather than at consumer cleanup.
        plaintext?.fill(0);
        if (error?.code === 'PublicationPrivateEvidenceCorrupt') throw error;
        fail('PublicationPrivateEvidenceCorrupt', error);
      }
    } finally {
      key.fill(0);
    }
  };
  const readPrivateEvidence = async (name, semanticCid, holdingCid, consume, beforeRead) => {
    if (consume === undefined) {
      if (beforeRead !== undefined) fail('InvalidPublicationPrivateEvidence');
      return readPrivateEvidenceObject(name, semanticCid, holdingCid);
    }
    active();
    if (typeof consume !== 'function') fail('InvalidPublicationPrivateEvidence');
    cidHex(holdingCid);
    // The existing reader census protects this SAME private holding until
    // its trusted consumer has completed decode/admission, including awaits.
    // It supplies no memory credit or semantic/physical cleanup ACK. The
    // caller's original Request/Run reservation must precede acquisition.
    const release = retainPhysicalHoldingReader(holdingCid);
    let plaintext, wire, record, reading = true;
    const releaseBytes = () => {
      if (!reading) fail('PublicationPrivateEvidenceUnavailable');
      if (wire === undefined) {
        wire = plaintext.toString('utf8');
        plaintext.fill(0);
        plaintext = undefined;
      }
      return wire;
    };
    const context = Object.freeze({releaseBytes,
      confirm(binding) {
        if (!reading) fail('PublicationPrivateEvidenceUnavailable');
        if (!exactKeys(binding, ['name', 'semanticCid', 'holdingCid', 'wire']) ||
            binding.name !== name || binding.semanticCid !== semanticCid ||
            binding.holdingCid !== holdingCid || binding.wire !== releaseBytes()) {
          fail('PublicationPrivateEvidenceConflict');
        }
        const operation = materialRetentionBusy.then(async () => {
          active();
          if (!reading) fail('PublicationPrivateEvidenceUnavailable');
          // This reader has already consumed/hashed/authenticated the SAME
          // immutable holding. Its original reader census still excludes
          // retirement; confirm that record without a second decrypt/parse.
          await confirmPhysicalHoldingDirectory(record);
          return record;
        });
        materialRetentionBusy = operation.catch(() => {});
        return operation;
      }});
    try {
      plaintext = await readPrivateEvidenceObject(name, semanticCid, holdingCid, 0, 1,
        undefined, original => {
          record = original;
          if (beforeRead !== undefined) {
            if (typeof beforeRead !== 'function' || beforeRead(original.objects[0].byte_count) !== undefined) {
              fail('InvalidPublicationPrivateEvidence');
            }
          }
        });
      return await consume(plaintext, context);
    } finally {
      // This overload never hands byte custody to its caller. Typed values
      // may retain their own strings; the temporary decrypted backing stops
      // here even when decode or its original child rejects.
      plaintext?.fill(0);
      reading = false;
      plaintext = wire = record = undefined;
      release();
    }
  };
  const preparePrivateEvidenceInput = async (name, input, semanticCid, isWire) => {
    active();
    if (typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name) ||
        (!isWire && !(input instanceof Uint8Array))) {
      fail('InvalidPublicationPrivateEvidence');
    }
    const byteLength = isWire ? Buffer.byteLength(input, 'utf8') : input.byteLength;
    if (byteLength > configuration.maxObjectBytes) {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(semanticCid);
    const key = privateEvidenceKey();
    // Share this exact original Store bound with upstream private exporters.
    // Preserve validation/key priority, bytes/AAD and refusal before copying,
    // crypto or Base64 construction. A clamp is not a memory reservation.
    if (byteLength > privateEvidenceWireLimitForObject(configuration.maxObjectBytes)) {
      fail('PublicationObjectLimit');
    }
    const envelope = encodePrivateEvidenceEnvelope(input, isWire, key,
      privateEvidenceAad(name, semanticCid), configuration.maxObjectBytes);
    const writer = createPreparedObjectWriter(envelope.byteLength);
    try {
      await writer.append(envelope);
      const stored = await writer.seal();
      return Object.freeze({
        semanticCid, physicalCid: stored.cid,
        bytes: stored.bytes, prepared: stored.prepared,
      });
    } catch (error) {
      let cleanupFailure;
      try { await writer.cancel(); }
      catch (cleanupError) { cleanupFailure = cleanupError; }
      const state = writer.status();
      const pending = state.reservationHeld || state.custodyPending || state.cleanupPending;
      if (!pending && cleanupFailure === undefined) throw error;
      const failure = error !== null && typeof error === 'object' &&
        Object.isExtensible(error) ? error
        : new PublicationStoreError(error?.code ??
          'PublicationPrivateEvidencePreparationFailed', error);
      if (cleanupFailure !== undefined) failure.cleanupFailure = cleanupFailure;
      if (pending) {
        failure.cleanupPending = true;
        failure.cleanupHandle = retainPrivateWriterCleanup(writer);
      }
      throw failure;
    }
  };
  const preparePrivateEvidenceBytes = (name, bytes, semanticCid) =>
    preparePrivateEvidenceInput(name, bytes, semanticCid, false);
  // The historical String path retains exactly its old encoding and AAD.
  const preparePrivateEvidence = (name, wire, semanticCid) => {
    active();
    if (typeof wire !== 'string' ||
        Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
      fail('InvalidPublicationPrivateEvidence');
    }
    return preparePrivateEvidenceInput(name, wire, semanticCid, true);
  };

  // The portable Model/Publication issuer supplies the admitted descriptor
  // binding. This physical port proves exact bytes and Store durability only;
  // it cannot select a policy, authorize capture, or issue a Model receipt.
  const validateModelRawBinding = binding => {
    if (!exactKeys(binding, [
      'semanticCid', 'holdingCid', 'wire', 'contentCid', 'byteCount',
    ])) fail('InvalidPublicationModelRawEvidence');
    binding = Object.freeze({...binding});
    if (typeof binding.wire !== 'string' ||
        Buffer.byteLength(binding.wire, 'utf8') > configuration.maxObjectBytes ||
        !quantity(binding.byteCount) ||
        binding.byteCount > configuration.maxObjectBytes) {
      fail('InvalidPublicationModelRawEvidence');
    }
    for (const cid of [binding.semanticCid, binding.holdingCid, binding.contentCid]) {
      cidHex(cid);
    }
    return binding;
  };
  const verifyModelRawBytes = (binding, bytes) => {
    if (!(bytes instanceof Uint8Array) || bytes.byteLength !== binding.byteCount ||
        `sha256:${createHash('sha256').update(bytes).digest('hex')}` !==
          binding.contentCid) {
      fail('PublicationModelRawContentMismatch');
    }
  };
  const prepareModelRawEvidence = async (binding, bytes) => {
    active();
    binding = validateModelRawBinding(binding);
    verifyModelRawBytes(binding, bytes);
    // Hash and encrypt the same borrowed physical bytes before the first
    // await. No caller callback can change the content between these steps.
    const content = await preparePrivateEvidenceBytes(
      'model_raw_content', bytes, binding.semanticCid,
    );
    try {
      const descriptor = await preparePrivateEvidence(
        'model_raw_descriptor', binding.wire, binding.semanticCid,
      );
      return Object.freeze([descriptor, content]);
    } catch (error) {
      const descriptorCleanup = error?.cleanupPending === true ? error.cleanupHandle : undefined;
      let cleanupFailure;
      let cleanupPending;
      try {
        await content.prepared.release();
        cleanupPending = content.prepared.status().pending !== false;
      }
      catch (cleanupError) {
        cleanupFailure = cleanupError;
        cleanupPending = true;
      }
      if (!cleanupPending) throw error;
      // False release can retain a visible-but-unconfirmed holding. Export
      // that same retry handle, just as for a thrown cleanup failure. A frozen
      // primary cannot accept fields, but its original cause must survive.
      const failure = error !== null && typeof error === 'object' &&
        Object.isExtensible(error) ? error
        : new PublicationStoreError(error?.code ??
          'PublicationModelRawEvidencePreparationFailed', error);
      if (cleanupFailure !== undefined) {
        if (failure.cleanupFailure === undefined) failure.cleanupFailure = cleanupFailure;
        else failure.contentCleanupFailure = cleanupFailure;
      }
      failure.cleanupPending = true;
      // This error comes from the same closed private Store preparation, not
      // a packet/caller-provided handle. Do not replace its still-owned
      // descriptor writer with only the earlier content's cleanup reference.
      failure.cleanupHandle = descriptorCleanup === undefined
        ? content.prepared
        : retainPrivateRawCleanup(descriptorCleanup, content.prepared);
      throw failure;
    }
  };
  const readModelRawEvidenceOriginal = async (binding, confirm = false) => {
    active();
    if (await readPhysicalHoldingDeletion(binding.holdingCid) !== undefined) return undefined;
    const record = await readPhysicalHolding(binding.holdingCid);
    if (record === undefined) return undefined;
    if (record.namespace !== 'publication-private' ||
        record.manifest_cid !== binding.semanticCid || record.objects.length !== 2) {
      fail('PublicationPrivateEvidenceUnavailable');
    }
    const release = retainPhysicalHoldingReader(binding.holdingCid);
    try {
      if (!exactUtf8WireMatches(await readPrivateEvidenceObject(
        'model_raw_descriptor', binding.semanticCid, binding.holdingCid, 0, 2, record,
      ), binding.wire)) {
        fail('PublicationPrivateEvidenceConflict');
      }
      const bytes = await readPrivateEvidenceObject(
        'model_raw_content', binding.semanticCid, binding.holdingCid, 1, 2, record,
      );
      verifyModelRawBytes(binding, bytes);
      if (confirm) {
        // This exact metadata and both payloads belong to the same operation.
        // Confirmation still requires its original directory ACK and adoption.
        await confirmPhysicalHoldingDirectory(record);
      }
      return Object.freeze({record, bytes});
    } finally {release();}
  };
  const readModelRawEvidence = async binding => {
    active();
    return (await readModelRawEvidenceOriginal(validateModelRawBinding(binding)))?.bytes;
  };
  const confirmModelRawEvidence = async binding => {
    active();
    const original = validateModelRawBinding(binding);
    const operation = materialRetentionBusy.then(() => readModelRawEvidenceOriginal(original, true));
    materialRetentionBusy = operation.catch(() => {});
    return operation;
  };

  // Availability of exact common-owner-admitted originals, not policy
  // selection or permission. Keep this check separate from raw-cell commit:
  // semantic adoption and physical persistence are different observations.
  const confirmModelRawCaptureOriginals = async (originals, storeAuthorityCid) => {
    active();
    const kinds = ['retention_contract', 'metadata_retention_policy',
      'clock_contract', 'data_policy'];
    if (storeAuthorityCid !== configuration.storeAuthorityCid ||
        !Array.isArray(originals) || originals.length !== kinds.length) {
      fail('InvalidPublicationModelRawOriginals');
    }
    // Freeze the finite expected references before any Store await. This does
    // not clone body trees or reinterpret a body in a JS policy evaluator.
    const expected = originals.map((original, index) => {
      if (!exactKeys(original, ['kind', 'cid', 'wire']) ||
          original.kind !== kinds[index] || typeof original.wire !== 'string' ||
          Buffer.byteLength(original.wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidPublicationModelRawOriginals');
      }
      cidHex(original.cid);
      return Object.freeze({...original});
    });
    for (const original of expected) {
      if (!exactUtf8WireMatches(await readSemanticBytes(original.cid), original.wire)) {
        fail('PublicationModelRawOriginalMismatch');
      }
    }
    return true;
  };

  const readContract = async (cid, contractName, readOriginal = readSemanticOriginal) => {
    const includeNative = contractName === undefined || nativeContractRead(contractName);
    const original = await readOriginal(cid, includeNative);
    const native = original.native;
    if (native !== undefined) {
      if (contractName !== undefined && native.name !== contractName) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({wire:native.wire,value:parseContract(native),contract:native});
    }
    const bytes = original.bytes;
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

  const verifyDurableResultBinding = async (contract, readOriginal = readSemanticOriginal, retainedBinding) => {
    if (contract.name !== 'durable_result_binding') {
      fail('InvalidPublicationCommitEvidence');
    }
    // Only the private selected reader supplies this same already parsed
    // body. Other internal callers still interpret their own contract here.
    const binding = retainedBinding === undefined ? parseContract(contract) : retainedBinding;
    if (binding.store_authority_cid !== configuration.storeAuthorityCid ||
        binding.physical_sha256 !== cidHex(binding.material_generation_cid)) {
      fail('PublicationDurableBindingMismatch');
    }
    const physical = await verifyObject(binding.material_generation_cid);
    if (physical.bytes !== binding.byte_count) {
      fail('PublicationDurableBindingMismatch');
    }
    const original = await readOriginal(binding.result_schema_cid, false);
    const schemaBytes = original.bytes;
    const schemaCid = original.physicalCid ?? `sha256:${createHash('sha256')
      .update(schemaBytes).digest('hex')}`;
    if (schemaCid !== binding.result_schema_cid) {
      fail('PublicationDurableBindingMismatch');
    }
    const schemaWire = schemaBytes.toString('utf8');
    let schema;
    try { schema = JSON.parse(schemaWire); }
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
        wire: schemaWire,
      }),
    });
  };

  const createAdmittedAttempt = async (admitted, retainedAttempt) => {
    const attempt = retainedAttempt ?? parseContract(admitted);
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    // An independently adopted file original keeps its legacy link protocol.
    // New attempts need no second physical copy or directory locator: their
    // exact CID is the existing native metadata primary key.
    let fileOriginal = false;
    try { await lstat(contractPath(admitted.identity)); fileOriginal = true; }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    if (!fileOriginal) {
      const stored = (await putNativePublicationContracts([Object.freeze({contract:admitted,value:attempt})],
        Object.freeze({kind:'attempt',attemptCid:admitted.identity,runCid:attempt.run_definition_cid})))[0];
      return Object.freeze({attempt,created:stored.progressCreated});
    }
    const stored = await putAdmittedPublicationContract(admitted, attempt);
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

  const createAttempt = async suppliedWire => {
    active();
    return createAdmittedAttempt(admitContract('publication_attempt', suppliedWire));
  };

  const beginPublicationAttempt = async (supplied, attemptOriginal, initialRecords) => {
    if (!Array.isArray(supplied)) fail('InvalidPublicationContractWire');
    if (initialRecords !== undefined && (!Array.isArray(initialRecords) || initialRecords.length !== 2)) {
      fail('InvalidPublicationRecord');
    }
    if (supplied.length >= configuration.maxObjects) fail('PublicationStoreObjectLimit');
    const admitted = admitPublicationContracts([...supplied, attemptOriginal], true);
    const selected = admitted.find(({contract}) => contract.identity === attemptOriginal.identity &&
      contract.name === 'publication_attempt');
    if (selected === undefined) fail('InvalidPublicationContract');
    let records;
    if (initialRecords !== undefined) {
      records = admitPublicationContracts(initialRecords,true);
      if (records.length !== 2 || records.some(({contract}) => contract.name !== 'publication_record')) fail('InvalidPublicationRecord');
      const [first, second] = records;
      if (first.value.publication_attempt_cid !== selected.contract.identity ||
          second.value.publication_attempt_cid !== selected.contract.identity) fail('PublicationAttemptMismatch');
      if (first.value.sequence !== 0 || first.value.state !== 'preparing' ||
          second.value.sequence !== 1 || !['committing','cancelled'].includes(second.value.state) ||
          contractControl.recordTransition(undefined,first.contract,false) !== true ||
          contractControl.recordTransition(first.contract,second.contract,false) !== true) {
        fail('InvalidPublicationRecordTransition');
      }
      for (const record of records) {
        const prior=admitted.find(({contract})=>contract.identity===record.contract.identity);
        if (prior!==undefined && (prior.contract.name!==record.contract.name || prior.contract.wire!==record.contract.wire)) {
          fail('PublicationSemanticIdentityConflict');
        }
      }
    }
    if (await runMetadataDeletionStarted(selected.value.run_definition_cid)) fail('PublicationMetadataDeleted');
    let fileAttempt = false;
    try { await lstat(contractPath(selected.contract.identity)); fileAttempt = true; }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    // Independently adopted file attempts keep their original file progress.
    // Only an all-native setup joins the bodies and attempt locator in one
    // existing transaction; either path returns after its actual acknowledgements.
    if (fileAttempt || admitted.some(({contract}) => !nativePublicationContract(contract.name))) {
      // Do not preinstall progress bodies as native metadata for a file-backed
      // attempt: its original append path must still create and ACK the files
      // that its sequence links select.
      try {
        await putAdmittedPublicationContracts(admitted, true);
      } catch (error) {
        // This original mutation contains setup only, not the proposed pair.
        // Its caller must confirm exactly that group after a lost reply.
        if (records !== undefined && error instanceof PublicationStoreError &&
            error.code === 'PublicationMetadataCommitOutcomeUnknown' && error.outcome === 'unknown') {
          Object.defineProperty(error,'publicationStartKind',{value:'setup'});
        }
        throw error;
      }
      const created = await createAdmittedAttempt(selected.contract, selected.value);
      if (records !== undefined && !(await readdir(publicationAttemptPath(selected.contract.identity)))
        .some(name => recordNamePattern.test(name))) await appendInitialPublicationRecords(initialRecords);
      return created;
    }
    const existingProgress = records !== undefined &&
      deliveryIndex.publicationAttempt(selected.contract.identity) !== undefined &&
      deliveryIndex.latestPublicationRecord(selected.contract.identity) !== undefined;
    const initial = existingProgress ? undefined : records;
    const combined = initial === undefined ? admitted : [...admitted,
      ...initial.filter(value => !admitted.some(({contract})=>contract.identity===value.contract.identity))];
    if (combined.length > configuration.maxObjects) fail('PublicationStoreObjectLimit');
    let stored;
    try {
      stored = await putAdmittedPublicationContracts(combined, true,
      Object.freeze({kind: initial === undefined ? 'attempt' : 'initial-attempt',
        attemptCid: selected.contract.identity, runCid: selected.value.run_definition_cid,
        ...(initial === undefined ? {} : {records:Object.freeze(initial.map(({contract,value},sequence)=>
          Object.freeze({previousCid:sequence === 0 ? null : records[0].contract.identity,
            recordCid:contract.identity,sequence:value.sequence})))})}));
    } catch (error) {
      if (existingProgress && error instanceof PublicationStoreError &&
          error.code === 'PublicationMetadataCommitOutcomeUnknown' && error.outcome === 'unknown') {
        Object.defineProperty(error,'publicationStartKind',{value:'setup'});
      }
      throw error;
    }
    return Object.freeze({attempt: selected.value,
      created: stored.find(value => value.semanticCid === selected.contract.identity).progressCreated});
  };

  const beginPublicationAttemptWithRecords = (supplied, attemptOriginal, records) => {
    if (!Array.isArray(records) || records.length !== 2) fail('InvalidPublicationRecord');
    return beginPublicationAttempt(supplied, attemptOriginal, records);
  };

  const latestRecordContract = async attemptCid => {
    active();
    if (deliveryIndex.publicationAttempt(attemptCid) !== undefined) {
      const row = deliveryIndex.latestPublicationRecord(attemptCid);
      if (row === undefined) return undefined;
      const selected = await readContract(row.record_cid,'publication_record');
      if (selected.value.publication_attempt_cid !== attemptCid || selected.value.sequence !== row.sequence) {
        fail('InvalidPublicationRecord');
      }
      return selected.contract;
    }
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
    if (deliveryIndex.publicationAttempt(record.publication_attempt_cid) !== undefined) {
      await putNativePublicationContracts([Object.freeze({contract,value:record})],Object.freeze({
        kind:'record',attemptCid:record.publication_attempt_cid,previousCid:previous?.identity ?? null,
        recordCid:contract.identity,sequence:record.sequence,
      }));
      return record;
    }
    await putAdmittedPublicationContract(contract, record);
    const target = resolve(directory, `${record.sequence}.json`);
    try { await link(contractPath(record.publication_record_cid), target); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('PublicationRecordConflict');
      throw error;
    }
    await syncDirectory(directory);
    return record;
  };

  const appendInitialPublicationRecords = async supplied => {
    if (!Array.isArray(supplied) || supplied.length !== 2) fail('InvalidPublicationRecord');
    const admitted = admitPublicationContracts(supplied, true);
    if (admitted.length !== 2 || admitted.some(({contract})=>contract.name !== 'publication_record')) {
      fail('InvalidPublicationRecord');
    }
    const [first, second] = admitted;
    const attemptCid = first.value.publication_attempt_cid;
    if (second.value.publication_attempt_cid !== attemptCid) fail('PublicationAttemptMismatch');
    if (first.value.sequence !== 0 || first.value.state !== 'preparing' || second.value.sequence !== 1 ||
        !['committing','cancelled'].includes(second.value.state)) fail('InvalidPublicationRecord');
    const attempt = (await readContract(attemptCid, 'publication_attempt')).value;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) fail('PublicationMetadataDeleted');
    const previous = await latestRecordContract(attemptCid);
    if (previous !== undefined || contractControl.recordTransition(undefined, first.contract, false) !== true ||
        contractControl.recordTransition(first.contract, second.contract, false) !== true) {
      fail('InvalidPublicationRecordTransition');
    }
    if (deliveryIndex.publicationAttempt(attemptCid) === undefined) {
      // File-backed attempts keep their existing independently durable protocol.
      for (const {contract} of admitted) await appendRecord(contract.wire, {uncommittedConfirmed:false});
    } else {
      await putNativePublicationContracts(admitted, Object.freeze({kind:'initial-records',attemptCid,
        records:Object.freeze(admitted.map(({contract,value},sequence)=>Object.freeze({
          previousCid:sequence === 0 ? null : first.contract.identity,
          recordCid:contract.identity,sequence:value.sequence,
        })))}));
    }
    return second.value;
  };

  const readFileDeliveryAttemptContract = async (attemptCid, retained) => {
    const bytes = await readBounded(
      resolve(deliveryAttemptPath(attemptCid), 'attempt.json'),
      configuration.maxObjectBytes,
    );
    try {
      const contract = retained !== undefined && exactUtf8WireMatches(bytes, retained.wire)
        ? retained : admitContract('delivery_attempt', bytes.toString('utf8'));
      if (contract.identity !== attemptCid) fail('InvalidDeliveryAttempt');
      return contract;
    } catch (error) {
      fail('InvalidDeliveryAttempt', error);
    }
  };

  const readDeliveryAttemptContract = async (attemptCid, retained) =>
    nativeDeliveryContract(attemptCid,'delivery_attempt',retained) ??
      readFileDeliveryAttemptContract(attemptCid,retained);

  const deliveryLogicalKey = query => JSON.stringify([
    query.indexKey.namespaceId, query.indexKey.authorityScopeCid,
    query.indexKey.runDefinitionCid, query.principalId, query.purpose,
    query.resultName, query.attemptId,
  ]);
  const deliveryQuery = (attempt, grant) => ({
    indexKey: {namespaceId: grant.namespace_id, authorityScopeCid: grant.authority_scope_cid,
      runDefinitionCid: attempt.run_definition_cid},
    principalId: grant.principal_id, purpose: grant.purpose,
    resultName: attempt.result_name, attemptId: attempt.attempt_id,
  });
  const deliveryIndexRow = (attempt, grant, attemptContract, grantContract) => ({
    logical_key: deliveryLogicalKey(deliveryQuery(attempt, grant)),
    attempt_cid: attemptContract.identity, grant_cid: grantContract.identity,
    run_cid: attempt.run_definition_cid,
    attempt_wire: attemptContract.wire, grant_wire: grantContract.wire,
  });
  const installDeliveryAttempt = async (admitted, streaming) => {
    const writer = {cleanup: undefined, failed: false};
    activePhysicalRecordWriters.add(writer);
    let retainedChild = false;
    try {
    const target = deliveryAttemptPath(admitted.identity);
    const linkInitialRecord = async directory => {
      if (streaming === undefined) return;
      const path = resolve(directory, '0.json');
      try {await link(contractPath(streaming.identity), path);}
      catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        if (!exactUtf8WireMatches(await readBounded(path, configuration.maxObjectBytes), streaming.wire)) {
          fail('DeliveryRecordConflict');
        }
      }
    };
    try {
      const retained = await readDeliveryAttemptContract(admitted.identity, admitted);
      if (retained.wire !== admitted.wire) fail('DeliveryAttemptConflict');
      await linkInitialRecord(target);
      await syncDirectory(target);
      await syncDirectory(deliveriesDirectory);
      return;
    } catch (error) { if (error?.code !== 'ENOENT') throw error; }
    // A pending claim determines its one original staging alias. Recovery can
    // revisit that alias without scanning unrelated directories on every open.
    const staging = resolve(deliveriesDirectory, `.staging-${admitted.identity.slice(7)}`);
    try { await mkdir(staging, {mode: 0o700}); }
    catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      if (!(await lstat(staging)).isDirectory()) fail('InvalidDeliveryAttemptStore');
    }
    try {
      try { await link(contractPath(admitted.identity), resolve(staging, 'attempt.json')); }
      catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        const bytes = await readBounded(resolve(staging,'attempt.json'),configuration.maxObjectBytes);
        if (!exactUtf8WireMatches(bytes,admitted.wire)) fail('DeliveryAttemptConflict');
      }
      await linkInitialRecord(staging);
      await syncDirectory(staging);
      await rename(staging, target);
      await syncDirectory(deliveriesDirectory);
    } catch (primary) {
      if (primary?.code !== 'EEXIST') throw primary;
      await rm(staging, {recursive: true, force: false});
      const retained = await readDeliveryAttemptContract(admitted.identity, admitted);
      if (retained.wire !== admitted.wire) fail('DeliveryAttemptConflict');
      await linkInitialRecord(target);
      await syncDirectory(target);
      await syncDirectory(deliveriesDirectory);
    }
    } catch (primary) {
      const child = primary?.cleanupHandle;
      if (child !== undefined) {
        const statusOriginal = child.status, retryOriginal = child.retry;
        let pending = true, flight;
        const status = () => Object.freeze({pending});
        writer.failed = retainedChild = true;
        writer.cleanup = Object.freeze({status,retry() {
          if (flight !== undefined) return flight;
          flight = Promise.resolve().then(async () => {
            if (!pending) return status();
            if (typeof statusOriginal !== 'function' || typeof retryOriginal !== 'function') {
              fail('PublicationStoreCleanupPending');
            }
            await Reflect.apply(retryOriginal,child,[]);
            const observation = await Reflect.apply(statusOriginal,child,[]);
            const descriptor = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation,'pending') : undefined;
            if (descriptor?.value !== false) fail('PublicationStoreCleanupPending');
            pending = false;
            activePhysicalRecordWriters.delete(writer);
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
      }
      throw primary;
    } finally {
      if (!retainedChild) activePhysicalRecordWriters.delete(writer);
    }
  };
  const admitDeliveryClaim = (row, suppliedAttempt, suppliedGrant) => {
    const attemptContract = suppliedAttempt?.contract.identity === row.attempt_cid && suppliedAttempt.contract.wire === row.attempt_wire
      ? suppliedAttempt.contract : admitContract('delivery_attempt', row.attempt_wire);
    const grantContract = suppliedGrant?.contract.identity === row.grant_cid && suppliedGrant.contract.wire === row.grant_wire
      ? suppliedGrant.contract : admitContract('result_read_grant', row.grant_wire);
    const attempt = attemptContract === suppliedAttempt?.contract ? suppliedAttempt.value : parseContract(attemptContract);
    const grant = grantContract === suppliedGrant?.contract ? suppliedGrant.value : parseContract(grantContract);
    const expected = deliveryIndexRow(attempt,grant,attemptContract,grantContract);
    if (Object.keys(expected).some(name => expected[name] !== row[name]) ||
        attempt.result_read_grant_cid !== grantContract.identity ||
        attempt.run_definition_cid !== grant.run_definition_cid ||
        attempt.result_manifest_cid !== grant.result_manifest_cid ||
        !grant.results.some(result => result.result_name === attempt.result_name &&
          result.result_artifact_cid === attempt.result_artifact_cid)) fail('InvalidDeliveryAttemptIndex');
    let streaming, streamingRecord;
    if (row.initial_wire != null) {
      streaming = admitContract('delivery_record',row.initial_wire);
      const record = streamingRecord = parseContract(streaming);
      if (row.initial_cid != null && streaming.identity !== row.initial_cid ||
          record.delivery_attempt_cid !== attemptContract.identity ||
          record.sequence !== 0 || record.state !== 'streaming' ||
          Reflect.apply(deliveryStartTransition,contractControl,[undefined,streaming]) !== true) {
        fail('InvalidDeliveryAttemptIndex');
      }
    }
    return {attemptContract,attempt,grantContract,grant,streaming,streamingRecord};
  };
  const restoreDeliveryClaim = async row => {
    const {attemptContract,attempt,grantContract,grant,streaming} = admitDeliveryClaim(row);
    await putDeliveryContracts(grantContract,attemptContract,streaming);
    await installDeliveryAttempt(attemptContract,streaming);
    if (row.ready === 0) deliveryIndex.finish(row.logical_key,attemptContract.identity);
    return {attemptContract,attempt,grantContract,grant};
  };

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

  const enqueueDeliveryAdmission = action => {
    active();
    const operation = deliveryAdmissionBusy.then(action);
    deliveryAdmissionBusy = operation.catch(() => {});
    return operation;
  };
  const createAdmittedDeliveryAttempt = async (admitted, grantContract, initial) => {
    const attempt = parseContract(admitted);
    const grant = parseContract(grantContract);
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    if (attempt.result_read_grant_cid !== grantContract.identity ||
        attempt.run_definition_cid !== grant.run_definition_cid ||
        attempt.result_manifest_cid !== grant.result_manifest_cid ||
        !grant.results.some(result => result.result_name === attempt.result_name &&
          result.result_artifact_cid === attempt.result_artifact_cid)) {
      fail('DeliveryGrantMismatch');
    }
    const {match: retained} = await selectDeliveryAttempt(
      deliveryQuery(attempt,grant), {contract: admitted, value: attempt},
      {contract: grantContract, value: grant}, false);
    if (retained !== undefined) {
      // Both originals were admitted. Compare every scalar field, restoring
      // only the selected birth/identity, rather than hash the same body again.
      const keys = Object.keys(attempt);
      if (keys.length !== Object.keys(retained.attempt).length ||
          keys.some(name => name !== 'requested_at' && name !== 'delivery_attempt_cid' &&
            attempt[name] !== retained.attempt[name])) fail('DeliveryAttemptConflict');
      return Object.freeze({attempt: retained.attempt, created: false});
    }
    if (deliveryIndex === undefined) fail('DeliveryAttemptIndexUnavailable');
    const row = deliveryIndexRow(attempt,grant,admitted,grantContract);
    const progress = initial === undefined ? undefined :
      {runCid:attempt.run_definition_cid,phase:'preparing'};
    if (progress !== undefined) deliveryStarts.set(admitted.identity,progress);
    try {
      const selected = deliveryIndex.claim(row,grant.max_uses,initial?.streaming.wire,initial?.streaming.identity);
      if (!selected.created) fail('DeliveryAttemptConflict');
      // This SAME transaction owns uniqueness, use quota and the original
      // initial state. Its native COMMIT is the durable metadata original;
      // no duplicate contract file or alias ACK is required for joint START.
      // Legacy callers retain their original physical representation.
      if (initial === undefined) {
        await putDeliveryContracts(grantContract,admitted);
        await installDeliveryAttempt(admitted);
        deliveryIndex.finish(row.logical_key,admitted.identity);
      } else progress.phase = 'installed';
    } catch (error) {
      if (progress !== undefined) progress.phase = 'failed';
      throw error;
    }
    return Object.freeze(initial === undefined ? {attempt, created: true} :
      {original: initial.original, created: true});
  };
  const createDeliveryAttempt = (suppliedWire, suppliedGrantWire) => enqueueDeliveryAdmission(() =>
    createAdmittedDeliveryAttempt(admitContract('delivery_attempt', suppliedWire),
      admitContract('result_read_grant', suppliedGrantWire)));
  const beginDeliveryAttempt = (original, streaming) => {
    active();
    let facts;
    try {
      facts = Reflect.apply(readDeliveryOriginal, contractControl, [original]);
      if (Reflect.apply(deliveryStartTransition, contractControl, [undefined, streaming]) !== true) {
        fail('InvalidDeliveryStartEvidence');
      }
    } catch (cause) {fail('InvalidDeliveryStartEvidence', cause);}
    for (const contract of [facts.grant, facts.attempt, streaming]) {
      if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
          !Object.isFrozen(contract) || typeof contract.wire !== 'string' ||
          Buffer.byteLength(contract.wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidDeliveryStartEvidence');
      }
    }
    const record = parseContract(streaming);
    if (streaming.name !== 'delivery_record' || record.delivery_attempt_cid !== facts.attempt.identity ||
        record.sequence !== 0 || record.state !== 'streaming') fail('InvalidDeliveryStartEvidence');
    return enqueueDeliveryAdmission(() => createAdmittedDeliveryAttempt(facts.attempt, facts.grant,
      {original, streaming}));
  };

  const consumeManifestReadGrant = (suppliedWire, attemptId) => {
    active();
    if (typeof attemptId !== 'string' || attemptId.length === 0 ||
        attemptId.length > 256) {
      fail('InvalidManifestReadAttempt');
    }
    const operation = manifestReadAdmissionBusy.then(async () => {
      for (const pending of activePhysicalRecordWriters) {
        if (pending.failed) fail('PublicationStoreCleanupPending');
      }
      const admitted = admitContract('manifest_read_grant', suppliedWire);
      const grant = parseContract(admitted);
      if (await runMetadataDeletionStarted(grant.run_definition_cid)) {
        fail('PublicationMetadataDeleted');
      }
      await putAdmittedPublicationContract(admitted, grant);
      const writer = {failed: false, cleanup: undefined};
      activePhysicalRecordWriters.add(writer);
      let retainedChild = false;
      try {
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
        // Visibility after a lost sync reply is not durability. Only this
        // Store's real ACK of the same immutable target avoids another ACK.
        if (lastConfirmedManifestRead !== target) {
          await syncDirectory(directory);
          if (!(await readBounded(target, configuration.maxObjectBytes)).equals(bytes)) {
            fail('ManifestReadAttemptConflict');
          }
          lastConfirmedManifestRead = target;
        }
        return Object.freeze({grant, created: false, idempotent: true});
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
      let uses = 0, recovered = false;
      for (const name of await readdir(directory)) {
        if (name.startsWith('.staging-')) {
          await unlink(resolve(directory, name));
          recovered = true;
        } else {
          if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
              !(await lstat(resolve(directory, name))).isFile()) {
            fail('InvalidManifestReadStore');
          }
          uses++;
        }
      }
      if (recovered) await syncDirectory(directory);
      if (uses >= grant.max_uses) fail('ManifestReadGrantUseLimit');
      // Reuse the existing Store writer's FD/temporary/final-link custody.
      // Future writes leave no private per-grant staging traversal at open.
      await writePhysicalHoldingRecord(target, bytes, false, directory);
      lastConfirmedManifestRead = target;
      return Object.freeze({grant, created: true, idempotent: false});
      } catch (primary) {
        const child = primary?.cleanupHandle;
        if (child === undefined) throw primary;
        const childStatus = child.status, childRetry = child.retry;
        let pending = true, flight;
        const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary);
        failure.primaryFailure = primary;
        failure.cleanupPending = true;
        writer.failed = retainedChild = true;
        const status = () => Object.freeze({pending});
        writer.cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (!pending) return Promise.resolve(status());
          flight = Promise.resolve().then(async () => {
            if (typeof childStatus !== 'function' || typeof childRetry !== 'function') {
              fail('PublicationStoreCleanupPending');
            }
            await Reflect.apply(childRetry, child, []);
            const observation = await Reflect.apply(childStatus, child, []);
            const descriptor = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
            if (descriptor?.value !== false) fail('PublicationStoreCleanupPending');
            pending = false;
            activePhysicalRecordWriters.delete(writer);
            return status();
          }).finally(() => {failure.cleanupPending = pending; flight = undefined;});
          return flight;
        }});
        failure.cleanupHandle = writer.cleanup;
        throw failure;
      } finally {
        if (!retainedChild) activePhysicalRecordWriters.delete(writer);
      }
    });
    manifestReadAdmissionBusy = operation.catch(() => {});
    return operation;
  };

  const readLatestDeliveryRecordContract = async (attemptCid, original, retainedBirth, retainedBirthValue) => {
    active();
    const completed=deliveryIndex?.completion(attemptCid);
    if(completed!==undefined) {
      const retained=original?.contract;
      const contract=retained?.identity===completed.record_cid && retained.wire===completed.record_wire
        ? retained : admitContract('delivery_record',completed.record_wire);
      const record=parseContract(contract);
      if(contract.identity!==completed.record_cid || record.delivery_attempt_cid!==attemptCid ||
          record.sequence!==1 || record.state!=='succeeded' || record.result_delivery_receipt_cid!==completed.receipt_cid) {
        fail('InvalidDeliveryAttemptIndex');
      }
      return contract;
    }
    const directory = deliveryAttemptPath(attemptCid);
    const row = deliveryIndex?.attempt(attemptCid);
    let initial;
    if (row?.initial_cid != null) {
      initial = retainedBirth ?? admitContract('delivery_record',row.initial_wire);
      const record = retainedBirthValue ?? parseContract(initial);
      if (initial.identity !== row.initial_cid || initial.wire !== row.initial_wire ||
          record.delivery_attempt_cid !== attemptCid || record.sequence !== 0 || record.state !== 'streaming') {
        fail('InvalidDeliveryAttemptIndex');
      }
    }
    let entries;
    try {entries = await readdir(directory);}
    catch(error) {if(error?.code !== 'ENOENT' || initial === undefined) throw error; entries=[];}
    if (entries.some(name => name !== 'attempt.json' &&
        !recordNamePattern.test(name))) {
      fail('InvalidDeliveryRecord');
    }
    const names = entries
      .filter(name => recordNamePattern.test(name))
      .map(name => ({name, sequence: Number(name.slice(0, -5))}))
      .filter(value => Number.isSafeInteger(value.sequence))
      .sort((left, right) => left.sequence - right.sequence);
    if (names.length === 0) return initial;
    for (let index = 0; index < names.length; index++) {
      if (names[index].sequence !== index + (initial === undefined ? 0 : 1)) fail('DeliveryRecordGap');
    }
    const bytes = await readBounded(
      resolve(directory, names.at(-1).name), configuration.maxObjectBytes,
    );
    const retained = original?.contract;
    if (original !== undefined) original.bytes = bytes;
    // An append already admitted its immutable input. Equal canonical bytes
    // are the same fact in this operation, not a second contract admission.
    if (retained !== undefined && exactUtf8WireMatches(bytes, retained.wire)) {
      return retained;
    }
    try {
      return admitContract('delivery_record', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidDeliveryRecord', error);
    }
  };

  const latestDeliveryRecordContract = attemptCid =>
    readLatestDeliveryRecordContract(attemptCid);

  const latestDeliveryRecord = async attemptCid => {
    const contract = await latestDeliveryRecordContract(attemptCid);
    return contract === undefined ? undefined : parseContract(contract);
  };

  const lookupDeliveryAttempt = async query => {
    active();
    if (!exactKeys(query, [
      'indexKey', 'principalId', 'purpose', 'resultName', 'attemptId',
    ]) || !exactKeys(query.indexKey, [
      'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
    ]) || typeof query.indexKey.namespaceId !== 'string' ||
        query.indexKey.namespaceId.length === 0 ||
        !cidPattern.test(query.indexKey.authorityScopeCid) ||
        !cidPattern.test(query.indexKey.runDefinitionCid) ||
        typeof query.principalId !== 'string' || !query.principalId ||
        typeof query.purpose !== 'string' || !query.purpose ||
        typeof query.resultName !== 'string' || !query.resultName ||
        typeof query.attemptId !== 'string' || !query.attemptId ||
        query.attemptId.length > 256) {
      fail('InvalidDeliveryAttemptLookup');
    }
    return (await selectDeliveryAttempt(query)).match;
  };

  // The native index is complete before this Store escapes. Each public
  // selection reads only its exact target and referenced grant, never unrelated
  // attempt history. The same admission queue owns transactional claim changes.
  const selectDeliveryAttempt = async (query, suppliedAttempt, suppliedGrant,
    includeProgress = true) => {
    if (deliveryIndex === undefined) fail('DeliveryAttemptIndexUnavailable');
    const key = deliveryLogicalKey(query);
    const row = deliveryIndex.lookup(key);
    if (row === undefined) return {match: undefined};
    if (row.ready !== 1) fail('ResultDeliveryAttemptUnresolved');
    let recovered;
    if (row.initial_cid != null) {
      const progress = deliveryStarts.get(row.attempt_cid);
      if (progress !== undefined && progress.phase !== 'installed') fail('ResultDeliveryAttemptUnresolved');
      recovered = admitDeliveryClaim(row,suppliedAttempt,suppliedGrant);
    } else if (row.initial_wire != null) {
      let progress = deliveryStarts.get(row.attempt_cid);
      if (progress === undefined) {
        // Recovery is target-specific, not an O(history) ordinary-open pass.
        // Latch before any await/reentry and retain failure for this lifetime.
        progress = {runCid:row.run_cid,phase:'preparing'};
        deliveryStarts.set(row.attempt_cid,progress);
        try {
          if (await runMetadataDeletionStarted(row.run_cid)) fail('PublicationMetadataDeleted');
          recovered = await restoreDeliveryClaim(row);
          progress.phase = 'installed';
        } catch (error) { progress.phase = 'failed'; throw error; }
      } else if (progress.phase !== 'installed') fail('ResultDeliveryAttemptUnresolved');
    }
    const attemptContract = recovered?.attemptContract ?? await readDeliveryAttemptContract(
      row.attempt_cid, suppliedAttempt?.contract);
    const attempt = recovered?.attempt ?? (attemptContract === suppliedAttempt?.contract
      ? suppliedAttempt.value : parseContract(attemptContract));
    let grantContract, grant;
    if (recovered !== undefined) {
      grantContract = recovered.grantContract;
      grant = recovered.grant;
    } else if (suppliedGrant?.contract.identity === row.grant_cid) {
      const bytes = await readSemanticBytes(row.grant_cid);
      grantContract = exactUtf8WireMatches(bytes,suppliedGrant.contract.wire)
        ? suppliedGrant.contract : admitContract('result_read_grant',bytes.toString('utf8'));
      grant = grantContract === suppliedGrant.contract ? suppliedGrant.value : parseContract(grantContract);
    } else {
      const original = await readContract(row.grant_cid,'result_read_grant');
      grantContract = original.contract;
      grant = original.value;
    }
    const expected = deliveryIndexRow(attempt,grant,attemptContract,grantContract);
    if (Object.keys(expected).some(name => expected[name] !== row[name]) ||
        attempt.result_read_grant_cid !== row.grant_cid ||
        grant.run_definition_cid !== attempt.run_definition_cid ||
        grant.result_manifest_cid !== attempt.result_manifest_cid) {
      fail('InvalidDeliveryAttemptIndex');
    }
    const recordContract = includeProgress ? await readLatestDeliveryRecordContract(
      attemptContract.identity,undefined,row.initial_cid == null ? undefined : recovered.streaming,
      row.initial_cid == null ? undefined : recovered.streamingRecord) : undefined;
    const record = recordContract === undefined ? undefined : recordContract === recovered?.streaming
      ? recovered.streamingRecord : parseContract(recordContract);
    const hostReleaseReceipt = record?.result_delivery_receipt_cid === undefined
      ? undefined : (await readContract(record.result_delivery_receipt_cid,
        'result_delivery_receipt')).value;
    return {match: Object.freeze({attempt,record,hostReleaseReceipt})};
  };

  const confirmDeliveryRecord = async suppliedWire => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    const record = parseContract(contract);
    return confirmAdmittedDeliveryRecord(contract, record, false);
  };

  const confirmAdmittedDeliveryRecord = async (contract, record, observed) => {
    if(deliveryIndex?.confirmRecord(record.delivery_attempt_cid,contract.identity,contract.wire)===true) return record;
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const target = resolve(directory, `${record.sequence}.json`);
    let previousBytes = Buffer.isBuffer(observed) ? observed : undefined;
    const matches = bytes => {
      if (exactUtf8WireMatches(bytes, contract.wire)) return true;
      // Preserve existing admission of another valid wire spelling. Only a
      // distinct acquired wire needs this fallback; identical rereads reuse it.
      const admitted = admitContract('delivery_record', bytes.toString('utf8'));
      return admitted.identity === contract.identity && admitted.wire === contract.wire;
    };
    if (observed === false) {
      let bytes;
      try { bytes = await readBounded(target, configuration.maxObjectBytes); }
      catch (error) {
        if (error?.code === 'ENOENT') fail('DeliveryRecordMissing', error);
        throw error;
      }
      if (!matches(bytes)) fail('DeliveryRecordConflict');
      previousBytes = bytes;
    }
    if (previousBytes !== undefined &&
        lastConfirmedDeliveryRecord === contract.identity) return record;
    // A directory entry may be visible before its containing directory is
    // durable. Unless this Store already confirmed this immutable record,
    // sync its directory and check the same original before acknowledging it.
    await syncDirectory(directory);
    const confirmed = await readBounded(
      target, configuration.maxObjectBytes,
    );
    // The input was admitted once. Trusted I/O and its directory ACK do not
    // require parsing/hashing identical bytes again; changed bytes still fail.
    if (!(previousBytes !== undefined && confirmed.equals(previousBytes)) &&
        !matches(confirmed)) {
      fail('DeliveryRecordDurabilityMismatch');
    }
    lastConfirmedDeliveryRecord = contract.identity;
    return record;
  };

  const appendDeliveryRecord = async suppliedWire => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    return enqueueDeliveryAdmission(()=>appendAdmittedDeliveryRecord(contract));
  };

  const appendDeliveryCompletion = async (attempt, receipt, contract) => {
    active();
    for (const [original, name, identityField] of [
      [attempt, 'delivery_attempt', 'delivery_attempt_cid'],
      [receipt, 'result_delivery_receipt', 'result_delivery_receipt_cid'],
      [contract, 'delivery_record', 'delivery_record_cid'],
    ]) {
      if (!exactKeys(original, ['name', 'identityField', 'identity', 'wire']) ||
          !Object.isFrozen(original) || original.name !== name ||
          original.identityField !== identityField || !cidPattern.test(original.identity) ||
          typeof original.wire !== 'string' ||
          Buffer.byteLength(original.wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidDeliverySuccessEvidence');
      }
    }
    let valid = false;
    try { valid = contractControl.deliverySuccessValid(attempt, receipt, contract) === true; }
    catch (error) { fail('InvalidDeliverySuccessEvidence', error); }
    if (!valid) fail('InvalidDeliverySuccessEvidence');
    const record = parseContract(contract);
    if (record.state !== 'succeeded') fail('InvalidDeliverySuccessEvidence');
    return enqueueDeliveryAdmission(()=>{
      const progress=deliveryStarts.get(attempt.identity), pending=progress?.completion;
      if(pending!==undefined) {
        if(pending.attempt!==attempt || pending.receipt!==receipt || pending.contract!==contract) {
          fail('ResultDeliveryAttemptUnresolved');
        }
        deliveryIndex.complete(pending.entry);
        progress.completion=undefined;
        return record;
      }
      return appendAdmittedDeliveryRecord(contract, {attempt, receipt, record});
    });
  };

  const appendAdmittedDeliveryRecord = async (contract, completion) => {
    const suppliedReceipt = completion?.receipt;
    const record = completion?.record ?? parseContract(contract);
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const attemptContract = await readDeliveryAttemptContract(
      record.delivery_attempt_cid, completion?.attempt,
    );
    const attempt = parseContract(attemptContract);
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const original = {contract, bytes: undefined};
    const previous = await readLatestDeliveryRecordContract(
      record.delivery_attempt_cid, original,
    );
    if (completion !== undefined && attemptContract !== completion.attempt) {
      let valid = false;
      try {
        valid = record.state === 'succeeded' &&
          contractControl.deliverySuccessValid(attemptContract, suppliedReceipt, contract) === true;
      } catch (error) { fail('InvalidDeliverySuccessEvidence', error); }
      if (!valid) fail('InvalidDeliverySuccessEvidence');
    }
    if (previous?.identity === contract.identity) {
      if (suppliedReceipt !== undefined && !exactUtf8WireMatches(
        await readSemanticBytes(suppliedReceipt.identity), suppliedReceipt.wire,
      )) fail('InvalidDeliverySuccessEvidence');
      return confirmAdmittedDeliveryRecord(contract, record, original.bytes);
    }
    if (contractControl.deliveryTransition(previous, contract) !== true) {
      fail('InvalidDeliveryRecordTransition');
    }
    if (attempt.delivery_attempt_cid !== record.delivery_attempt_cid) {
      fail('DeliveryAttemptMismatch');
    }
    if (record.state === 'succeeded' && suppliedReceipt === undefined) {
      const receipt = (await readContract(
        record.result_delivery_receipt_cid,
        'result_delivery_receipt',
      )).contract;
      if (contractControl.deliverySuccessValid(
        attemptContract, receipt, contract,
      ) !== true) {
        fail('InvalidDeliverySuccessEvidence');
      }
    }
    const native=deliveryIndex?.attempt(record.delivery_attempt_cid);
    if(completion!==undefined && record.sequence===1 && native?.initial_cid===previous?.identity) {
      const progress=deliveryStarts.get(record.delivery_attempt_cid) ?? {runCid:attempt.run_definition_cid,phase:'installed'};
      deliveryStarts.set(record.delivery_attempt_cid,progress);
      const entry=Object.freeze({attempt_cid:record.delivery_attempt_cid,prior_cid:previous.identity,
        record_cid:contract.identity,record_wire:contract.wire,
        receipt_cid:suppliedReceipt.identity,receipt_wire:suppliedReceipt.wire});
      try {deliveryIndex.complete(entry);}
      catch(error) {
        // Retain these SAME nominal inputs for storage-only finalization.
        // A retry cannot send again, reissue a receipt or replace this duty.
        progress.completion=Object.freeze({attempt:completion.attempt,receipt:suppliedReceipt,contract,entry});
        throw error;
      }
      return record;
    }
    if (suppliedReceipt === undefined) await putSemantic(contract.wire, contract.identity);
    else await putSemanticBatch([suppliedReceipt, contract].map(value => ({
      wire: value.wire, semanticCid: value.identity,
    })));
    const target = resolve(directory, `${record.sequence}.json`);
    // Native START has no alias directory. Its first later record owns this
    // directory ACK; a failed ACK remains pending even when mkdir is visible.
    const start=deliveryStarts.get(record.delivery_attempt_cid);
    if(deliveryIndex?.attempt(record.delivery_attempt_cid)?.initial_cid != null &&
        start?.recordDirectoryAcknowledged !== true) {
      try {await mkdir(directory,{mode:0o700});}
      catch(error) {if(error?.code!=='EEXIST') throw error;}
      await syncDirectory(deliveriesDirectory);
      const progress=start ?? {runCid:attempt.run_definition_cid,phase:'installed'};
      progress.recordDirectoryAcknowledged=true;
      deliveryStarts.set(record.delivery_attempt_cid,progress);
    }
    try { await link(contractPath(record.delivery_record_cid), target); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('DeliveryRecordConflict');
      throw error;
    }
    return confirmAdmittedDeliveryRecord(contract, record, true);
  };

  const admitNativeIndexOriginal = (native, expectedKey) => {
    const admitted = admitContract('public_index_entry',native.body.wire), entry = parseContract(admitted);
    const key = {namespaceId:entry.namespace_id,authorityScopeCid:entry.authority_scope_cid,runDefinitionCid:entry.run_definition_cid};
    if (native.body.semantic_cid !== admitted.identity || indexKey(key) !== native.metadata_key ||
        native.namespace_id !== key.namespaceId || native.authority_scope_cid !== key.authorityScopeCid ||
        native.run_cid !== key.runDefinitionCid || expectedKey !== undefined &&
        ['namespaceId','authorityScopeCid','runDefinitionCid'].some(field => key[field] !== expectedKey[field])) {
      fail('PublicIndexBindingMismatch');
    }
    return {entry,bytes:Buffer.from(native.body.wire,'utf8'),contract:admitted,native};
  };

  const readCommittedIndexRaw = async (key, original) => {
    active();
    const keyHash = indexKey(key), path = resolve(indexesDirectory, `${keyHash}.json`);
    const native = deliveryIndex.nativePublicationIndex(keyHash);
    if (native !== undefined) {
      try {await lstat(path);}
      catch (error) {
        if (error?.code === 'ENOENT') return admitNativeIndexOriginal(native,key);
        throw error;
      }
      fail('PublicIndexBindingMismatch');
    }
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    if (original !== undefined && bytes.equals(original.bytes)) return original;
    const admitted = admitContract(
      'public_index_entry', bytes.toString('utf8'),
    );
    const entry = parseContract(admitted);
    if (entry.namespace_id !== key.namespaceId ||
        entry.authority_scope_cid !== key.authorityScopeCid ||
        entry.run_definition_cid !== key.runDefinitionCid) {
      fail('PublicIndexBindingMismatch');
    }
    const semantic = await readSemanticBytes(entry.public_index_entry_cid, false);
    // The selected Index and its immutable contract alias describe the same
    // fact. Reuse its admission for identical bytes, without skipping the
    // alias's real FD/inode/digest checks or admitting a changed spelling as
    // though it were the original.
    if (!exactUtf8WireMatches(semantic, admitted.wire)) {
      parseContract(admitContract('public_index_entry', semantic.toString('utf8')));
    }
    return {entry, bytes, contract: admitted};
  };

  const inspectCommittedIndexRaw = async key =>
    (await readCommittedIndexRaw(key))?.entry;

  const inspectCommittedIndex = async key => {
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) return undefined;
    const entry = await inspectCommittedIndexRaw(key);
    if (entry !== undefined) await requireCommittedMetadataInventory(entry);
    return entry;
  };

  const confirmCommittedIndexOriginal = async key => {
    active();
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) return undefined;
    const original = await readCommittedIndexRaw(key);
    if (original === undefined) return undefined;
    const {entry} = original;
    const durableCid = durablyConfirmedIndexes.get(keyHash);
    if (durableCid !== undefined &&
        durableCid !== entry.public_index_entry_cid) {
      fail('PublicIndexDurabilityMismatch');
    }
    if (durableCid === undefined) {
      if (original.native !== undefined) {
        writeNativeIndexOriginal(deliveryIndex.confirmNativePublicationIndex,[original.native], () => {
          durablyConfirmedIndexes.set(keyHash,entry.public_index_entry_cid);
        });
        return original;
      }
      // Visibility is not durability. Synchronize the exact containing
      // directory and then ensure that the same immutable entry is still
      // installed before reporting a durable commit.
      await syncDirectory(indexesDirectory);
      const confirmed = await readMetadataDeletion(keyHash) === undefined
        ? (await readCommittedIndexRaw(key, original))?.entry : undefined;
      if (confirmed?.public_index_entry_cid !==
          entry.public_index_entry_cid) {
        fail('PublicIndexDurabilityMismatch');
      }
      durablyConfirmedIndexes.set(keyHash, entry.public_index_entry_cid);
    }
    return original;
  };

  const confirmCommittedIndex = async key =>
    (await confirmCommittedIndexOriginal(key))?.entry;

  const confirmSelectedCommittedIndex = async key => {
    const entry = await confirmCommittedIndex(key);
    if (entry !== undefined) await requireCommittedMetadataInventory(entry);
    return entry;
  };

  const selectedPublicationReads = new WeakMap();
  const readCommittedPublication = async key => {
    // The selected body's nominal admission already belongs to this read.
    // Return that original, not another public raw-wire read/admission.
    const original = await confirmCommittedIndexOriginal(Object.freeze({...key}));
    if (original === undefined) return undefined;
    await requireCommittedMetadataInventory(original.entry);
    Object.freeze(original.entry.durable_result_binding_cids);
    const selected = Object.freeze({entry: Object.freeze(original.entry), index: original.contract});
    // One nested metadata lookup may consume this same Store acquisition.
    // It is neither a reusable read cache nor an authorization/ACK issuer.
    selectedPublicationReads.set(selected, selected.entry);
    return selected;
  };

  const lookupCommittedIndex = async (key, authorize) => {
    active();
    if (typeof authorize !== 'function' || authorize(Object.freeze({...key})) !== true) {
      fail('PublicationLookupDenied');
    }
    const entry = await confirmSelectedCommittedIndex(key);
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
    try {
      if (!(await lstat(retentionExtensionDirectory(keyHash))).isDirectory() ||
          !(await lstat(directory)).isDirectory()) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      names = await readdir(directory);
    }
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
    let directory;
    try {directory = await lstat(resultDeletionDirectory(keyHash));}
    catch (error) {if (error?.code === 'ENOENT') return undefined; throw error;}
    if (!directory.isDirectory() || directory.isSymbolicLink()) fail('InvalidPublicationDeletionStore');
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
    publication,
  ) => {
    cidHex(resultDefinitionCid);
    let entry;
    if (publication === undefined) entry = await confirmSelectedCommittedIndex(key);
    else {
      active();
      entry = selectedPublicationReads.get(publication);
      if (entry === undefined || entry.namespace_id !== key.namespaceId ||
          entry.authority_scope_cid !== key.authorityScopeCid ||
          entry.run_definition_cid !== key.runDefinitionCid) fail('PublicationLookupDenied');
      selectedPublicationReads.delete(publication);
      // Real same-Store retirement invalidates the observation. This indexed
      // fence does not reacquire/admit/hash the unchanged immutable Index.
      if (await runMetadataDeletionStarted(entry.run_definition_cid)) fail('PublicationLookupDenied');
    }
    if (entry === undefined) fail('PublicationLookupDenied');
    const matches = [];
    for (const bindingCid of entry.durable_result_binding_cids) {
      const {contract, value} = await readContract(
        bindingCid, 'durable_result_binding',
      );
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
    receipts, privateBinding, effectSources},
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
    if (contractControl.effectfulCommitValid(
      chain, preview, receipts, request, attempt, admittedIndex,
      contractLimits,
    ) !== true) {
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
    if (!exactKeys(preparation, [
      'index', 'chain', 'preview', 'receipts', 'privateBinding',
      'effectSources',
    ]) || typeof preparation.index?.wire !== 'string') {
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

  const consumeObject = async (cid, accept, closed) => {
    let handle;
    try {
      active();
      if (typeof accept !== 'function') fail('InvalidPublicationObjectConsumer');
      const path = objectPath(cid);
      handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    } catch (error) {
      closed?.(); // No original FD was acquired.
      throw error;
    }
    const hash = createHash('sha256');
    let bytes = 0;
    let readFailure;
    let readFailed = false;
    try {
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationStoreObject');
      }
      // One dedicated backing per bounded piece, filled on this SAME FD.
      // A ReadStream can allocate a second backing for a short read and read
      // ahead while accept is pending. Here short reads fill the original
      // piece, and no following piece is acquired until its callback returns.
      // Do not reuse a delivered backing: the consumer can retain its alias.
      while (bytes < before.size) {
        const buffer = Buffer.allocUnsafeSlow(Math.min(physicalContentReadWindowBytes, before.size - bytes));
        let filled = 0;
        while (filled < buffer.byteLength) {
          const requested = buffer.byteLength - filled;
          const {bytesRead} = await handle.read(buffer, filled, requested, bytes + filled);
          if (!quantity(bytesRead) || bytesRead > requested) fail('PublicationObjectCorrupt');
          if (bytesRead === 0) break;
          filled += bytesRead;
        }
        if (filled === 0) break;
        // Preserve delivery of an original prefix on truncation, followed by
        // the existing size/hash/version refusal. subarray adds only a view;
        // it neither copies a short piece nor proves retirement of its backing.
        const chunk = filled === buffer.byteLength ? buffer : buffer.subarray(0, filled);
        hash.update(chunk);
        await accept(chunk);
        bytes += filled;
        if (filled < buffer.byteLength) break;
      }
      const after = await handle.stat();
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || bytes !== after.size ||
          hash.digest('hex') !== cidHex(cid)) {
        fail('PublicationObjectCorrupt');
      }
      return Object.freeze({cid, bytes});
    } catch (error) {
      readFailure = error;
      readFailed = true;
      throw error;
    } finally {
      try {
        if (await handle.close() === false) fail('PublicationStoreCleanupPending');
        closed?.();
      } catch (closeFailure) {
        // A view of this SAME original read/FD, not a replacement reader,
        // cleanup owner or proof of successful consumption. Keep its existing
        // active-reader count until close succeeds; never reopen by path.
        let original = handle;
        let retire = closed;
        let flight;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({
          status,
          retry() {
            if (flight !== undefined) return flight;
            if (original === undefined) return Promise.resolve(status());
            flight = Promise.resolve().then(async () => {
              if (await original.close() === false) fail('PublicationStoreCleanupPending');
              original = undefined;
              const acknowledge = retire;
              retire = undefined;
              acknowledge?.();
              return status();
            }).finally(() => { flight = undefined; });
            return flight;
          },
        });
        const primary = readFailed ? readFailure : closeFailure;
        // Preserve ordinary mutable failures, but never let existing readonly
        // fields or hostile accessors discard the same original FD duty.
        let failure;
        try {
          failure = primary !== null && typeof primary === 'object' &&
            Object.isExtensible(primary) && primary.cleanupHandle === undefined &&
            ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
              const field = Object.getOwnPropertyDescriptor(primary, name);
              return field === undefined || field.writable === true;
            })
            ? primary : new Error('PublicationObjectReaderCleanupPending', {cause: primary});
          // Ordinary inherited setters may silently discard assignments. Own
          // data fields preserve the same FD duty and mutable primary identity.
          Object.defineProperties(failure, {
            cleanupHandle: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupHandle') ??
              {writable: true, enumerable: true, configurable: true}), value: cleanup},
            cleanupPending: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupPending') ??
              {writable: true, enumerable: true, configurable: true}), value: true},
            cleanupError: {...(Object.getOwnPropertyDescriptor(failure, 'cleanupError') ??
              {writable: true, enumerable: true, configurable: true}), value: closeFailure},
          });
        } catch {
          failure = new Error('PublicationObjectReaderCleanupPending', {cause: primary});
          Object.defineProperties(failure, {
            cleanupHandle: {value: cleanup, writable: true, enumerable: true, configurable: true},
            cleanupPending: {value: true, writable: true, enumerable: true, configurable: true},
            cleanupError: {value: closeFailure, writable: true, enumerable: true, configurable: true},
          });
        }
        throw failure;
      }
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
    let scopeActive = true, physicalReadPending = false, readerRetired = false;
    const retireReader = () => {
      if (scopeActive || physicalReadPending || readerRetired) return;
      readerRetired = true;
      const remaining = (activeResultReaders.get(materialCid) ?? 1) - 1;
      if (remaining === 0) activeResultReaders.delete(materialCid);
      else activeResultReaders.set(materialCid, remaining);
    };
    try {
      const verified = await verifyDurableResultBinding(selected.contract, undefined, selected.value);
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
        physicalReadPending = true;
        return consumeObject(materialCid, accept, () => {
          // Scope completion alone is not the consuming FD's close ACK.
          // A failed close keeps this same reader until its original cleanup
          // callback acknowledges retirement, without reopening or rereading.
          physicalReadPending = false;
          retireReader();
        });
      };
      try { return await use(metadata, consume); }
      finally { scopeOpen = false; }
    } finally {
      scopeActive = false;
      retireReader();
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

  const readRetainedResultExtension = async (
    key,
    resultDefinitionCid,
    metadataOnly = false,
    publication,
  ) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid, publication,
    );
    const keyHash = indexKey(key);
    if (!metadataOnly) {
      await requireResultNotDeleted(keyHash, selected, resultDefinitionCid);
    }
    return readSelectedResultRetentionExtension(
      selected, keyHash, resultDefinitionCid,
    );
  };

  const readSelectedResultRetentionExtension = async (
    selected, keyHash, resultDefinitionCid,
  ) => {
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

  const readCommittedResultRetentionExtension = (key, resultDefinitionCid, publication) =>
    readRetainedResultExtension(key, resultDefinitionCid, false, publication);

  // Inspect the retained immutable schema and binding inventory. Payload
  // deletion does not delete publication metadata; no generation is opened,
  // hashed or held as a payload reader by this operation.
  const readCommittedResultDescriptionEvidence = async (key, definitionCid, publication) => {
    active();
    const selected = await requireCommittedResultBinding(key, definitionCid, publication);
    const bindings = await Promise.all(
      selected.entry.durable_result_binding_cids.map(async cid =>
        cid === selected.contract.identity ? selected.contract :
          (await readContract(cid, 'durable_result_binding')).contract));
    const schemaWire = (await readSemanticBytes(
      selected.value.result_schema_cid, false)).toString('utf8');
    const definition = (await readContract(
      definitionCid, 'result_definition')).contract;
    const retained = await readSelectedResultRetentionExtension(
      selected, indexKey(key), definitionCid);
    return Object.freeze({bindings, schemaWire, definition, retained});
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
    for (const row of deliveryIndex.publicationAttemptsForRun(runDefinitionCid)) {
      const attempt = (await readContract(row.attempt_cid,'publication_attempt')).value;
      if (attempt.run_definition_cid !== runDefinitionCid) fail('PublicationAttemptMismatch');
      collected.add(row.attempt_cid);
      collected.add(attempt.publication_request_cid);
      for (const record of deliveryIndex.publicationRecords(row.attempt_cid)) {
        const admitted = (await readContract(record.record_cid,'publication_record')).contract;
        if (parseContract(admitted).publication_attempt_cid !== row.attempt_cid) fail('PublicationAttemptMismatch');
        collected.add(admitted.identity);
      }
    }
    // Native originals retire in the SAME indexed Run deletion transaction.
    // Identify their exact bodies without allocating temporary shadow files
    // or requiring spare object-file quota merely to delete native metadata.
    for (const row of deliveryIndex?.run(runDefinitionCid) ?? []) {
      if (row.initial_cid == null) continue;
      const {attemptContract,grantContract,streaming}=admitDeliveryClaim(row);
      for(const contract of [grantContract,attemptContract,streaming]) collected.add(contract.identity);
      const completed=deliveryIndex.completion(row.attempt_cid);
      if(completed!==undefined) {
        const record=admitContract('delivery_record',completed.record_wire);
        const receipt=admitContract('result_delivery_receipt',completed.receipt_wire);
        if(record.identity!==completed.record_cid || receipt.identity!==completed.receipt_cid ||
            contractControl.deliverySuccessValid(attemptContract,receipt,record)!==true) fail('InvalidDeliveryAttemptIndex');
        collected.add(record.identity);collected.add(receipt.identity);
      }
    }
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

  const bindMetadataContractObjects = async (contractCids, readOriginal = readSemanticOriginal) => {
    const objects = [];
    for (const semanticCid of contractCids) {
      const original = await readOriginal(semanticCid);
      if (original.publication === true) {
        objects.push(Object.freeze({semantic_cid:semanticCid,native:'sqlite',
          body_sha256:`sha256:${createHash('sha256').update(original.bytes).digest('hex')}`,
          byte_count:original.bytes.byteLength}));
        continue;
      }
      if(original.native !== undefined) {
        try {await lstat(contractPath(semanticCid));}
        catch(error) {if(error?.code==='ENOENT') continue; throw error;}
        // Only an independently present real file enters the physical-file
        // inventory. Native body identity is never a fabricated file/ACK.
      }
      const bytes = original.bytes;
      const physicalCid = original.physicalCid ?? `sha256:${createHash('sha256')
        .update(bytes).digest('hex')}`;
      const physical = original.physicalCid === undefined
        ? await verifyObject(physicalCid) : {cid: physicalCid, bytes: bytes.byteLength};
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
    deliveryIndex?.forgetRun(runDefinitionCid);
    for (const [attemptCid,progress] of deliveryStarts) {
      if (progress.runCid === runDefinitionCid) deliveryStarts.delete(attemptCid);
    }
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
    for (const original of deliveryIndex.nativePublicationReferenceOwners(
      'contract', semanticCid, excludedPublicIndexEntryCid)) {
      const inventory = publicationRecoveryValue(original);
      if (!inventory.contract_objects.some(object => object.semantic_cid === semanticCid)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const keyHash = indexKey({namespaceId:inventory.namespace_id,
        authorityScopeCid:inventory.authority_scope_cid,runDefinitionCid:inventory.run_definition_cid});
      if (await readMetadataDeletion(keyHash) !== undefined) continue;
      return true;
    }
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      );
      const keyHash = indexKey({
        namespaceId: inventory.namespace_id,
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

  const metadataHoldingHasOtherOwner = async (
    holdingCid, excludedPublicIndexEntryCid,
  ) => {
    for (const original of deliveryIndex.nativePublicationReferenceOwners(
      'holding', holdingCid, excludedPublicIndexEntryCid)) {
      if (!publicationRecoveryValue(original).physical_holding_cids.includes(holdingCid)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      return true;
    }
    for (const name of await readdir(metadataInventoriesDirectory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
        fail('InvalidPublicationMetadataInventoryStore');
      }
      const inventory = await readMetadataInventory(
        `sha256:${name.slice(0, -5)}`,
      );
      if (inventory.public_index_entry_cid !==
            excludedPublicIndexEntryCid &&
          inventory.physical_holding_cids.includes(holdingCid)) {
        return true;
      }
    }
    return false;
  };

  const pendingNativeMetadataReclaims = new Map();
  const reclaimMetadataContractInternal = async (
    excludedPublicIndexEntryCid,
    object,
    unconfirmedObjects,
  ) => {
    if (preparedSchemas.get(object.semantic_cid)?.holders.size > 0 ||
        await metadataContractHasLiveReference(
      object.semantic_cid, excludedPublicIndexEntryCid,
    )) return;
    if (object.native === 'sqlite') {
      let original = pendingNativeMetadataReclaims.get(object.semantic_cid);
      if (original === undefined) original = deliveryIndex.publicationContract(object.semantic_cid);
      if (original === undefined) return; // A durable deletion marker owns this exact idempotent removal.
      if (original.byte_count !== object.byte_count ||
          `sha256:${createHash('sha256').update(original.wire,'utf8').digest('hex')}` !== object.body_sha256) {
        fail('PublicationContractCorrupt');
      }
      pendingNativeMetadataReclaims.set(object.semantic_cid,original);
      accountNativePublication(deliveryIndex.removePublicationContract(original));
      pendingNativeMetadataReclaims.delete(object.semantic_cid);
      return;
    }
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
    if (physicalState === undefined) {
      const removal = await rememberPhysicalRemoval(object.physical_cid,object.byte_count);
      if (removal !== undefined) unconfirmedObjects.set(object.physical_cid, removal);
      return;
    }
    if (!physicalState.isFile() ||
        physicalState.size !== object.byte_count) {
      fail('InvalidPublicationStoreObject');
    }
    if (physicalState.nlink > 1) return;
    const removal = await rememberPhysicalRemoval(object.physical_cid,object.byte_count,physicalState);
    unconfirmedObjects.set(object.physical_cid, removal);
    await confirmPhysicalRemovals(unconfirmedObjects);
    unconfirmedObjects.clear();
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
        `sha256:${name.slice(0, -5)}`,
      );
      if (holding.objects.some(object => object.cid === materialCid)) {
        return true;
      }
    }
    const bindings = new Map();
    const bindingOriginal = cid => {
      if (!bindings.has(cid)) bindings.set(cid,readContract(cid,'durable_result_binding'));
      return bindings.get(cid);
    };
    let afterIndex, afterResult, visited = 0n;
    const maximum = BigInt(configuration.maxObjects) * BigInt(configuration.maxObjects);
    while (true) {
      const rows = deliveryIndex.nativePublicationMaterialReferences(materialCid,afterIndex,afterResult);
      if (rows.length === 0) break;
      visited += BigInt(rows.length);
      if (visited > maximum) fail('PublicationStoreObjectLimit');
      for (const reference of rows) {
        const native = deliveryIndex.nativePublicationIndex(reference.metadata_key);
        if (native === undefined) {
          if (await readMetadataDeletion(reference.metadata_key) !== undefined) continue;
          fail('InvalidPublicationMetadataInventoryStore');
        }
        const original = admitNativeIndexOriginal(native);
        if (original.contract.identity !== reference.public_index_cid ||
            !original.entry.durable_result_binding_cids.includes(reference.binding_cid)) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
        const binding = (await bindingOriginal(reference.binding_cid)).value;
        if (binding.material_generation_cid !== materialCid ||
            binding.result_definition_cid !== reference.result_definition_cid) fail('PublicationDurableBindingMismatch');
        const deletion = await readResultDeletion(reference.metadata_key,reference.result_definition_cid);
        if (deletion === undefined) return true;
        if (deletion.public_index_entry_cid !== reference.public_index_cid ||
            deletion.material_generation_cid !== materialCid) fail('InvalidPublicationDeletionStore');
      }
      const last = rows[rows.length - 1];
      afterIndex = last.public_index_cid; afterResult = last.result_definition_cid;
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
        const binding = (await bindingOriginal(bindingCid)).value;
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

  const commitPhysicalHoldingInternal = async (
    value, prepared, borrowedHoldingCids,
  ) => {
    active();
    if (!Array.isArray(borrowedHoldingCids) ||
        new Set(borrowedHoldingCids).size !== borrowedHoldingCids.length ||
        borrowedHoldingCids.some(cid => !cidPattern.test(cid))) {
      fail('InvalidPublicationPhysicalHoldingOwner');
    }
    const admitted = admitPhysicalHolding(value);
    const record = admitted.record;
    if (await readPhysicalHoldingDeletion(record.holding_cid) !== undefined) {
      fail('PublicationPhysicalHoldingRetiring');
    }
    const selected = preparedObjectOwners.select(prepared,
      new Map(record.objects.map(object => [object.cid, object.byte_count])));
    const retainSelected = () => {
      preparedObjectOwners.retainTransfer(record.holding_cid, selected);
    };
    const current = await readPhysicalHolding(record.holding_cid);
    if (current !== undefined) {
      if (!Buffer.from(JSON.stringify(current), 'utf8').equals(
        admitted.bytes,
      )) {
        fail('PublicationPhysicalHoldingConflict');
      }
      await verifyPhysicalHoldingObjects(current);
      retainSelected();
      await confirmPhysicalHoldingDirectory(current);
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
      const owner = preparedObjectOwners.original(handle);
      if (owner === undefined || supplied.has(owner.cid)) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
      if (handle.status().pending === true) {
        supplied.set(owner.cid, owner.bytes);
      } else if (borrowedHoldingCids.length === 0) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
    }
    const borrowed = new Map();
    for (const holdingCid of borrowedHoldingCids) {
      if (await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
        fail('PublicationPhysicalHoldingRetiring');
      }
      const source = await readPhysicalHolding(holdingCid);
      if (source === undefined) {
        fail('PublicationPhysicalHoldingUnavailable');
      }
      await verifyPhysicalHoldingObjects(source);
      for (const object of source.objects) {
        if (expected.get(object.cid) === object.byte_count) {
          borrowed.set(object.cid, object.byte_count);
        }
      }
    }
    if (borrowedHoldingCids.length !== 0) {
      await confirmPhysicalHoldingDirectory(record, false);
    }
    for (const [cid, bytes] of expected) {
      if (supplied.get(cid) !== bytes && borrowed.get(cid) !== bytes) {
        fail('InvalidPublicationPhysicalHoldingOwner');
      }
    }
    if ([...supplied].some(([cid, bytes]) => expected.get(cid) !== bytes)) {
      fail('InvalidPublicationPhysicalHoldingOwner');
    }
    await verifyPhysicalHoldingObjects(record);
    retainSelected();
    try {
      await writePhysicalHoldingRecord(
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
    await confirmPhysicalHoldingDirectory(record);
    return Object.freeze({record, created: true});
  };

  const commitPhysicalHolding = (value, prepared,
    borrowedHoldingCids = []) => {
    const operation = materialRetentionBusy.then(() =>
      commitPhysicalHoldingInternal(value, prepared, borrowedHoldingCids));
    materialRetentionBusy = operation.catch(() => {});
    return operation;
  };

  // Reconcile a private holding by exact admitted wire, then confirm its
  // directory durability. A visible link alone is not a committed holding.
  const confirmPrivateEvidence = async binding => {
    active();
    if (!exactKeys(binding, [
      'name', 'semanticCid', 'holdingCid', 'wire',
    ])) fail('InvalidPublicationPrivateEvidence');
    const original = Object.freeze({...binding});
    if (!['effect_preview', 'effect_capture', 'effect_catalog', 'credential_raw_observation', 'model_capture_bundle',
      'model_slot_capture', 'model_invocation_evidence', 'model_call_attempt', 'model_attempt_accounting',
      'model_attempt_outcome', 'model_dispatch_authority', 'model_attachment_admission',
      'observation_set', 'run_invocation', 'source_evidence',
      'content_input_artifact', 'content_evidence', 'content_generation',
      'installation_publication'].includes(original.name) ||
        typeof original.wire !== 'string') {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(original.semanticCid);
    cidHex(original.holdingCid);
    const operation = materialRetentionBusy.then(async () => {
      active();
      if (await readPhysicalHoldingDeletion(original.holdingCid) !== undefined) return undefined;
      const record = await readPhysicalHolding(original.holdingCid);
      if (record === undefined) return undefined;
      if (record.namespace !== 'publication-private' ||
          record.manifest_cid !== original.semanticCid || record.objects.length !== 1) {
        fail('PublicationPrivateEvidenceUnavailable');
      }
      const release = retainPhysicalHoldingReader(original.holdingCid);
      let stored;
      try {
        stored = await readPrivateEvidenceObject(
          original.name, original.semanticCid, original.holdingCid, 0, 1, record,
        );
        if (!exactUtf8WireMatches(stored, original.wire)) fail('PublicationPrivateEvidenceConflict');
        // The same serialized operation retains its actual read facts through
        // the real directory ACK, excluding retirement until adoption finishes.
        await confirmPhysicalHoldingDirectory(record);
        return record;
      } finally {
        stored?.fill(0);
        stored = undefined;
        release();
      }
    });
    materialRetentionBusy = operation.catch(() => {});
    return operation;
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
        await confirmPhysicalHoldingDirectory(current, false);
        return Object.freeze({record: current, created: false});
      }
      await verifyPhysicalHoldingObjects(source);
      try {
        await writePhysicalHoldingRecord(
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
      await confirmPhysicalHoldingDirectory(record, false);
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

  // Retirement validates ownership metadata, not payload usability. A
  // missing or corrupt payload must remain unreadable but may still be
  // retired by its exact owner. This is never a consumption/admission proof.
  const inspectPhysicalHoldingForRetirement = async holdingCid => {
    active();
    cidHex(holdingCid);
    return await readPhysicalHolding(holdingCid) ??
      await readPhysicalHoldingDeletion(holdingCid);
  };

  const retainPhysicalHoldingReader = holdingCid => {
    activePhysicalHoldingReaders.set(
      holdingCid,
      (activePhysicalHoldingReaders.get(holdingCid) ?? 0) + 1,
    );
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const remaining =
        (activePhysicalHoldingReaders.get(holdingCid) ?? 1) - 1;
      if (remaining === 0) activePhysicalHoldingReaders.delete(holdingCid);
      else activePhysicalHoldingReaders.set(holdingCid, remaining);
    };
  };

  const confirmPhysicalHoldingDirectory = async (record, adopt = true) => {
    try {
      await syncDirectory(physicalHoldingsDirectory);
      if (adopt) {
        await confirmPreparedMaterials(record.objects.map(object => object.cid));
        const selected = preparedObjectOwners.pendingTransfer(record.holding_cid);
        if (selected !== undefined) {
          await adoptPreparedObjects(selected);
          preparedObjectOwners.finishTransfer(record.holding_cid);
        }
      }
    } catch (primary) {
      const child = primary?.cleanupHandle;
      if (child === undefined) throw primary;
      // The existing publication scope ends on rejection, but this SAME
      // acquired directory FD still prevents Store and holding retirement.
      // Reuse the Store's failed-writer custody; cleanup confirms no evidence.
      const release = retainPhysicalHoldingReader(record.holding_cid);
      let original = child, retry = child.retry, observe = child.status;
      let pending = true, flight;
      const writer = {failed: true, cleanup: undefined};
      const failure = new PublicationStoreError('PublicationPrivateConfirmationCleanupPending', primary);
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      if (primary.outcome === 'unknown') failure.outcome = 'unknown';
      const status = () => Object.freeze({pending});
      writer.cleanup = Object.freeze({status, retry() {
        if (flight !== undefined) return flight;
        if (!pending) return Promise.resolve(status());
        flight = Promise.resolve().then(async () => {
          if (typeof retry !== 'function' || typeof observe !== 'function') {
            fail('PublicationPrivateConfirmationCleanupPending');
          }
          await Reflect.apply(retry, original, []);
          const observed = await Reflect.apply(observe, original, []);
          const descriptor = observed !== null && typeof observed === 'object'
            ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
          if (descriptor?.value !== false) fail('PublicationPrivateConfirmationCleanupPending');
          pending = false;
          release();
          activePhysicalRecordWriters.delete(writer);
          original = retry = observe = undefined;
          return status();
        }).finally(() => {failure.cleanupPending = pending; flight = undefined;});
        return flight;
      }});
      failure.cleanupHandle = writer.cleanup;
      activePhysicalRecordWriters.add(writer);
      throw failure;
    }
  };

  // Private selected metadata only. Public consumers still perform their
  // original full inspection before application callbacks can receive bytes.
  const consumeSelectedPhysicalHolding = async (record, objectIndex, accept) => {
    const closed = retainPhysicalHoldingReader(record.holding_cid);
    return await consumeObject(record.objects[objectIndex].cid, accept, closed);
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
    return consumeSelectedPhysicalHolding(record, objectIndex, accept);
  };

  const ensurePhysicalHoldingDeletion = async record => {
    const bytes = Buffer.from(JSON.stringify(record), 'utf8');
    const path = physicalHoldingDeletionPath(record.holding_cid);
    try { await writePhysicalHoldingRecord(path, bytes); }
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
            if (state === undefined) {
              const removal = await rememberPhysicalRemoval(cid,bytes);
              if (removal !== undefined) unconfirmedObjects.set(cid, removal);
              continue;
            }
            if (!state.isFile() || state.size !== bytes) {
              fail('InvalidPublicationStoreObject');
            }
            if (state.nlink > 1) continue;
            const removal = await rememberPhysicalRemoval(cid,bytes,state);
            unconfirmedObjects.set(cid, removal);
            await removal.unlinkOriginal();
          }
          if (unconfirmedObjects.size !== 0) {
            await confirmPhysicalRemovals(unconfirmedObjects);
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

  // This is physical cleanup custody, not a completed capture or permission
  // to execute. Persist before transferring any prepared object to a holding.
  // Completion transfers responsibility to the admitted private capture.
  const captureCustodyRun = run => {
    const admitted = admitContract('run_definition', run?.wire);
    if (admitted.identity !== run?.identity) {
      fail('InvalidEffectCaptureCustody');
    }
    return admitted;
  };
  const captureCustodyPath = run => resolve(captureCustodyDirectory,
    `${cidHex(run.identity)}.json`);
  // One same-Store durability observation, not capture completion or authority.
  let lastConfirmedEffectCaptureCustody;
  const readEffectCaptureCustodyOriginal = async run => {
    let bytes;
    try { bytes = await readBounded(captureCustodyPath(run),
      Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)); }
    catch (error) { if (error?.code === 'ENOENT') return undefined; throw error; }
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidEffectCaptureCustody', error); }
    if (!exactKeys(value, ['version', 'store_authority_cid',
      'run_definition', 'holdings']) ||
        value.version !== 'actql-effect-capture-custody/0.1' ||
        value.store_authority_cid !== configuration.storeAuthorityCid ||
        value.run_definition !== run.wire || !Array.isArray(value.holdings) ||
        value.holdings.length > 4096) fail('InvalidEffectCaptureCustody');
    const holdings = value.holdings.map(value =>
      parsePhysicalHolding(Buffer.from(JSON.stringify(value))));
    if (new Set(holdings.map(value => value.holding_cid)).size !==
        holdings.length || holdings.some(value =>
        !['effect-source', 'effect-capture'].includes(value.namespace))) {
      fail('InvalidEffectCaptureCustody');
    }
    return Object.freeze({...value, holdings: Object.freeze(holdings)});
  };
  const readEffectCaptureCustody = async suppliedRun => {
    active();
    return readEffectCaptureCustodyOriginal(captureCustodyRun(suppliedRun));
  };
  const retainEffectCaptureCustody = (suppliedRun, suppliedHoldings) => {
    active();
    const run = captureCustodyRun(suppliedRun);
    const holdings = suppliedHoldings.map(value =>
      parsePhysicalHolding(Buffer.from(JSON.stringify(value))));
    return withSemanticCommit(async () => {
      active();
      const previous = await readEffectCaptureCustodyOriginal(run);
      const records = new Map((previous?.holdings ?? []).map(value =>
        [value.holding_cid, value]));
      for (const holding of holdings) {
        if (!['effect-source', 'effect-capture'].includes(holding.namespace)) {
          fail('InvalidEffectCaptureCustody');
        }
        const old = records.get(holding.holding_cid);
        if (old !== undefined && JSON.stringify(old) !== JSON.stringify(holding)) {
          fail('EffectCaptureCustodyConflict');
        }
        records.set(holding.holding_cid, holding);
      }
      const wire = JSON.stringify({
        version: 'actql-effect-capture-custody/0.1',
        store_authority_cid: configuration.storeAuthorityCid,
        run_definition: run.wire, holdings: [...records.values()],
      });
      const byteLength = Buffer.byteLength(wire, 'utf8');
      if (records.size > 4096 || byteLength >
          Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)) {
        fail('EffectCaptureCustodyLimitExceeded');
      }
      const path = captureCustodyPath(run);
      const confirmed = lastConfirmedEffectCaptureCustody;
      if (previous !== undefined && confirmed?.wire === wire) {
        const current = await lstat(path, {bigint: true});
        if (current.isFile() &&
            ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs']
              .every(field => current[field] === confirmed.state[field])) return;
      }
      // A failed write/sync/close never publishes or preserves this observation.
      // A changed body, replacement allocation or new Store uses real I/O.
      lastConfirmedEffectCaptureCustody = undefined;
      const bytes = Buffer.from(wire, 'utf8');
      const staging = resolve(stagingDirectory, `object-${randomUUID()}`);
      await writeExclusive(staging, bytes);
      await rename(staging, path);
      await syncDirectory(captureCustodyDirectory);
      const state = await lstat(path, {bigint: true});
      if (!state.isFile() || state.size !== BigInt(byteLength)) {
        fail('InvalidEffectCaptureCustody');
      }
      lastConfirmedEffectCaptureCustody = {wire, state};
    });
  };
  const listEffectCaptureCustodies = async ({after = '', limit = 100} = {}) => {
    active();
    if (typeof after !== 'string' || after !== '' && !cidPattern.test(after) ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      fail('InvalidEffectCaptureCustodyPage');
    }
    const names = await readdir(captureCustodyDirectory);
    if (names.some(name => !/^[0-9a-f]{64}\.json$/u.test(name))) {
      fail('InvalidEffectCaptureCustody');
    }
    const selected = names.sort().filter(name =>
      `sha256:${name.slice(0, -5)}` > after).slice(0, limit);
    const result = [];
    for (const name of selected) {
      let value;
      try {
        value = JSON.parse((await readBounded(resolve(captureCustodyDirectory,
          name), Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)))
          .toString('utf8'));
      } catch (error) {
        if (error?.code === 'ENOENT') continue;
        fail('InvalidEffectCaptureCustody', error);
      }
      const run = admitContract('run_definition', value.run_definition);
      if (`${cidHex(run.identity)}.json` !== name) {
        fail('InvalidEffectCaptureCustody');
      }
      if (await readEffectCaptureCustodyOriginal(run) !== undefined) result.push(run);
    }
    return Object.freeze(result);
  };
  const forgetEffectCaptureCustodyOriginal = async run => {
    active();
    lastConfirmedEffectCaptureCustody = undefined;
    try { await unlink(captureCustodyPath(run)); }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    await syncDirectory(captureCustodyDirectory);
  };
  const forgetEffectCaptureCustody = async suppliedRun => {
    active();
    const run = captureCustodyRun(suppliedRun);
    await readEffectCaptureCustodyOriginal(run);
    return forgetEffectCaptureCustodyOriginal(run);
  };
  const retireEffectCaptureCustody = async suppliedRun => {
    active();
    const run = captureCustodyRun(suppliedRun);
    const record = await readEffectCaptureCustodyOriginal(run);
    if (record === undefined) return false;
    // Validate the entire exact inventory before deleting any holding. A
    // missing record can be progress from an interrupted retirement pass.
    for (const expected of record.holdings) {
      const actual = await readPhysicalHolding(expected.holding_cid) ??
        await readPhysicalHoldingDeletion(expected.holding_cid);
      if (actual !== undefined && JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail('EffectCaptureCustodyConflict');
      }
    }
    for (const holding of record.holdings) {
      const retired = await retirePhysicalHolding(holding.holding_cid);
      if (retired.cleanup.status().pending) {
        const error = new PublicationStoreError('EffectCaptureCustodyCleanupPending');
        error.cleanupPending = true;
        error.cleanupHandle = retired.cleanup;
        throw error;
      }
    }
    await forgetEffectCaptureCustodyOriginal(run);
    return true;
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
        `sha256:${name.slice(0, -5)}`,
      );
      const cleanup = createPhysicalHoldingDeletionCleanup(record);
      try { await cleanup.retry(); }
      catch {}
      recovered.push(cleanup);
    }
    return Object.freeze(recovered);
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
      let accounted = state !== undefined && state.isFile() &&
        state.size === record.byte_count &&
        String(state.dev) === record.device &&
        String(state.ino) === record.inode;
      if(accounted) {
        await syncDirectory(objectsDirectory);
        confirmPhysicalCapacity([physicalOriginal(record.material_generation_cid,record.byte_count,state)]);
      } else if(state===undefined) {
        const retained=deliveryIndex.physicalObject(record.material_generation_cid);
        accounted=retained!==undefined && retained.byte_count===record.byte_count &&
          retained.device===record.device && retained.inode===record.inode;
      }
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
    const names = await readdir(preparedSchemasDirectory);
    // No pending original means there is no schema recovery transition to
    // confirm. Selected reads and later mutations keep their own real ACKs.
    if (names.length === 0) return Object.freeze([]);
    await syncDirectory(contractsDirectory);
    await syncDirectory(objectsDirectory);
    const recovered = [];
    for (const name of names) {
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
    let pending = true, inventoryRetired = false;
    const recoveryOriginal = publicationRecoveryOriginal(inventory);
    const errors = [];
    const unconfirmedObjects = new Map();
    const status = () => Object.freeze({
      pending,
      errors: Object.freeze([...errors]),
    });
    const finishInventory = () => {
      deliveryIndex.retireNativePublicationInventory(recoveryOriginal);
      pending = false;
      pendingUncommittedMetadataCleanups.delete(inventoryCid);
      return status();
    };
    const cleanup = Object.freeze({
      status,
      retry() {
        if (!pending) return Promise.resolve(status());
        const operation = metadataRetentionBusy.then(async () => {
          if (!pending) return status();
          // No other indexed read may precede this same-original Unknown
          // retry after all physical metadata retirement was acknowledged.
          if (inventoryRetired) return finishInventory();
          const key = {
            namespaceId: inventory.namespace_id,
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
          for (const holdingCid of inventory.physical_holding_cids) {
            if (await metadataHoldingHasOtherOwner(
              holdingCid, inventoryCid,
            )) continue;
            if (await readPhysicalHolding(holdingCid) !== undefined ||
                await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
              fail('PublicationPhysicalHoldingCleanupRequired');
            }
          }
          for (const object of inventory.contract_objects) {
            await reclaimMetadataContract(
              inventoryCid, object, unconfirmedObjects,
            );
          }
          if (unconfirmedObjects.size !== 0) {
            await confirmPhysicalRemovals(unconfirmedObjects);
            unconfirmedObjects.clear();
          }
          try {
            await unlink(metadataInventoryPath(inventoryCid));
            await syncDirectory(metadataInventoriesDirectory);
          } catch (error) {
            if (error?.code !== 'ENOENT') throw error;
          }
          inventoryRetired = true;
          return finishInventory();
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
    const original = deliveryIndex.pendingPublication(publicIndexEntryCid);
    const inventory = original === undefined ? await readMetadataInventory(publicIndexEntryCid)
      : await recoverMetadataInventory(original);
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
    for (const original of deliveryIndex.pendingPublications()) {
      const retained = publicationRecoveryValue(original);
      const key = {
        namespaceId: retained.namespace_id,
        authorityScopeCid: retained.authority_scope_cid,
        runDefinitionCid: retained.run_definition_cid,
      };
      // The already durable deletion marker owns retirement. Do not restore
      // an inventory file it has physically retired, or read its removed Run.
      const marker = await readMetadataDeletion(indexKey(key));
      if (marker !== undefined) {
        if (marker.version !== 'actql-local-publication-metadata-deletion/0.1' ||
            marker.namespace_id !== retained.namespace_id ||
            marker.authority_scope_cid !== retained.authority_scope_cid ||
            marker.run_definition_cid !== retained.run_definition_cid ||
            marker.public_index_entry_cid !== retained.public_index_entry_cid) {
          fail('InvalidPublicationMetadataDeletionStore');
        }
        continue;
      }
      const inventory = await restoreMetadataInventory(original,retained);
      if ((await confirmCommittedIndex(key))?.public_index_entry_cid ===
          inventory.public_index_entry_cid) {
        deliveryIndex.finishPublicationInventory(original);
        continue;
      }
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
    // Persist recovery intent before any marker or physical cleanup. Native
    // close alone cannot seal it; the Store waits for every original child.
    deliveryIndex.beginResultDeletionLifetime();
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
    let physicalRemoval;
    const cleanup = createResultDeletionOwner({
      serialize(run) {
        const operation = materialRetentionBusy.then(run);
        materialRetentionBusy = operation.catch(() => {});
        return operation;
      },
      ensureMarker: () => ensureResultDeletionMarker(
        keyHash, resultDefinitionCid, marker,
      ),
      async retention() {
        if ((activeResultReaders.get(materialCid) ?? 0) !== 0) return 'wait';
        const prepared = preparedObjects.get(materialCid);
        if (prepared !== undefined &&
            (prepared.holders.size !== 0 ||
              prepared.commitOwners.size !== 0)) return 'wait';
        if (await materialHasLiveReference(materialCid)) {
          return 'settled';
        }
        const currentPrepared = preparedObjects.get(materialCid);
        return currentPrepared !== undefined &&
          (currentPrepared.holders.size !== 0 ||
            currentPrepared.commitOwners.size !== 0) ? 'wait' : 'free';
      },
      markReclaiming() { reclaimingMaterialCids.add(materialCid); },
      async inspectAllocation() {
        let state;
        try { state = await lstat(objectPath(materialCid)); }
        catch (error) {
          if (error?.code !== 'ENOENT') throw error;
        }
        if (state === undefined) {
          physicalRemoval = await rememberPhysicalRemoval(materialCid,expectedBytes);
          return physicalRemoval === undefined ? 'missing' : 'missing-unconfirmed';
        }
        if (!state.isFile() || state.size !== expectedBytes) {
          fail('PublicationDurableBindingMismatch');
        }
        // Other Store-owned references can share this inode. Keep the base
        // name and capacity charge while any physical link remains.
        if(state.nlink>1)return 'shared';
        physicalRemoval = await rememberPhysicalRemoval(materialCid,expectedBytes,state);
        return 'exclusive';
      },
      unlink: () => physicalRemoval.unlinkOriginal(),
      syncObjects: () => syncPhysicalRemovals(new Map([[materialCid, physicalRemoval]])),
      releaseCapacity() {
        return releasePhysicalCapacity(new Map([[materialCid, physicalRemoval]]));
      },
      settle(clearReclaiming) {
        pendingResultDeletions.delete(deletionKey);
        if (clearReclaiming) reclaimingMaterialCids.delete(materialCid);
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
    if (!deliveryIndex.resultDeletionRecoveryRequired()) return Object.freeze(recovered);
    for (const keyHash of await readOpeningDirectory(deletionsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
          !(await lstat(resultDeletionDirectory(keyHash))).isDirectory()) {
        fail('InvalidPublicationDeletionStore');
      }
      let indexBytes;
      const nativeIndex = deliveryIndex.nativePublicationIndex(keyHash);
      try {
        if (nativeIndex === undefined) indexBytes = await readBounded(
          resolve(indexesDirectory, `${keyHash}.json`), configuration.maxObjectBytes);
      } catch (error) {
        if (error?.code === 'ENOENT' &&
            await readMetadataDeletion(keyHash) !== undefined) continue;
        throw error;
      }
      const nativeOriginal = nativeIndex === undefined ? undefined : admitNativeIndexOriginal(nativeIndex);
      const indexContract = nativeOriginal?.contract ?? admitContract('public_index_entry',indexBytes.toString('utf8'));
      const entry = nativeOriginal?.entry ?? parseContract(indexContract);
      for (const name of await readOpeningDirectory(resultDeletionDirectory(keyHash))) {
        if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
            !(await lstat(resolve(resultDeletionDirectory(keyHash), name))).isFile()) {
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
    let recoveryOriginal, recoveryCaptured = false, recoveryTransferred = false;
    const cleanup = createMetadataDeletionOwner(marker, {
      serialize(run) {
        const operation = metadataRetentionBusy.then(async () => {
          const completion=pendingMetadataFenceCompletions.get(keyHash);
          if(completion!==undefined) {
            deliveryIndex.finishMetadataDeletionFence(completion);
            pendingMetadataFenceCompletions.delete(keyHash);
          }
          if (!recoveryTransferred) {
            if(!recoveryCaptured) {
              recoveryOriginal = deliveryIndex.pendingPublication(marker.public_index_entry_cid) ??
                deliveryIndex.nativePublicationInventory(marker.public_index_entry_cid);
              recoveryCaptured=true;
            }
            if (recoveryOriginal !== undefined) {
              const inventory = publicationRecoveryValue(recoveryOriginal);
              if (inventory.namespace_id !== marker.namespace_id ||
                  inventory.authority_scope_cid !== marker.authority_scope_cid ||
                  inventory.run_definition_cid !== marker.run_definition_cid ||
                  inventory.physical_holding_cids.join('\0') !== marker.physical_holding_cids.join('\0') ||
                  inventory.contract_objects.some(object => !marker.contract_objects.some(
                    member => member.semantic_cid === object.semantic_cid))) {
                fail('InvalidPublicationMetadataDeletionStore');
              }
              // The same durable marker now owns all cleanup. Settle its
              // pending lookup row before physical work so an Unknown retry
              // reaches this exact native mutation before any other DB read.
            }
            deliveryIndex.retireNativePublicationInventory(recoveryOriginal,
              {metadata_key:keyHash,run_cid:marker.run_definition_cid});
            metadataDeletionIntents.delete(marker.run_definition_cid);
            recoveryTransferred = true;
          }
          return run();
        });
        metadataRetentionBusy = operation.catch(() => {});
        return operation;
      },
      syncObjects: objects => syncPhysicalRemovals(objects),
      releaseUnconfirmed(objects) {
        return releasePhysicalCapacity(objects);
      },
      async retireResult(result) {
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
        if (retired.cleanup.status().pending) await retired.cleanup.retry();
        return !retired.cleanup.status().pending;
      },
      async retireHolding(holdingCid) {
        if (await metadataHoldingHasOtherOwner(
          holdingCid, marker.public_index_entry_cid,
        )) return true;
        const retired = await retirePhysicalHolding(holdingCid);
        return !retired.cleanup.status().pending;
      },
      removeRunDirectories: () => removeRunMetadataDirectories(
        marker.run_definition_cid, keyHash,
      ),
      async removeIndex() {
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
      },
      reclaimContract: (object, unconfirmedObjects) =>
        reclaimMetadataContract(
          marker.public_index_entry_cid, object, unconfirmedObjects,
        ),
      async removeResultDeletionDirectory() {
        try {
          await rm(resultDeletionDirectory(keyHash), {
            recursive: true, force: false,
          });
          await syncDirectory(deletionsDirectory);
        } catch (error) {
          if (error?.code !== 'ENOENT') throw error;
        }
      },
      async removeInventory() {
        try {
          await unlink(metadataInventoryPath(marker.public_index_entry_cid));
          await syncDirectory(metadataInventoriesDirectory);
        } catch (error) {
          if (error?.code !== 'ENOENT') throw error;
        }
      },
      compactMarker: () => compactMetadataDeletion(
        keyHash, marker.run_definition_cid,
      ),
      settle() {
        pendingMetadataDeletions.delete(keyHash);
        pendingMetadataDeletionMarkers.delete(keyHash);
      },
    });
    pendingMetadataDeletions.set(keyHash, cleanup);
    pendingMetadataDeletionMarkers.set(keyHash, marker);
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
    const pending=pendingMetadataDeletions.get(keyHash);
    if(pending!==undefined) return Object.freeze({marker:pendingMetadataDeletionMarkers.get(keyHash),
      cleanup:pending,deleted:false});
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
        namespace_id: entry.namespace_id,
        authority_scope_cid: entry.authority_scope_cid,
        run_definition_cid: entry.run_definition_cid,
        public_index_entry_cid: entry.public_index_entry_cid,
        results: await metadataResultBindings(entry),
        contract_objects: await bindMetadataContractObjects(contractCids),
        physical_holding_cids: inventory.physical_holding_cids,
        requested_at: requestedAt,
      }));
    }
    if (marker.namespace_id !== key.namespaceId ||
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

  // One bounded semantic view per actual Store admission. The escaped handle
  // carries no key/path and must be presented to this same live Store owner.
  let originalModelStorageBinding;
  // This existing Store's original binding readers stay owned during read and
  // failed-close cleanup. Count/callback/error/control holding is not a new
  // physical byte allowance, and must be included in the installed envelope.
  let originalModelStorageBindingReaders = 0;
  const observeOriginalModelStorageBinding = async () => {
    active();
    if (originalModelStorageBindingReaders !== 0) {
      fail('PublicationStoreCleanupPending');
    }
    originalModelStorageBindingReaders++;
    const bytes = await readBounded(storeContractPath, 256, () => {
      originalModelStorageBindingReaders--;
    });
    const current = JSON.parse(bytes);
    active();
    if (!exactKeys(current, ['version', 'isolation', 'store_authority_cid']) ||
        !Buffer.from(JSON.stringify(current), 'utf8').equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
    if (originalModelStorageBinding === undefined) {
      const evidence = contractControl.sealRunEvidence('model_original_storage_binding',
        JSON.stringify({version: 'actql-model-original-storage-binding/0.1',
          store_contract_wire: storeContractBytes.toString('utf8'),
          store_contract_cid: `sha256:${createHash('sha256').update(storeContractBytes).digest('hex')}`,
          store_authority_cid: configuration.storeAuthorityCid,
          key_generation_cid: `sha256:${createHash('sha256').update(privateEvidenceKey()).digest('hex')}`,
          private_namespace: 'local-continuation-private'}),
        {maxWireBytes: 2048, maxNodes: 32, maxDepth: 2});
      originalModelStorageBinding = {evidence, handle: Object.freeze({
        kind: 'model-original-storage-binding', identity: evidence.identity,
        wire: evidence.wire})};
    }
    return originalModelStorageBinding.handle;
  };

  // Read-only original Store observation for the separate installation
  // publication Owner. This is not Model RunEvidence or a semantic issuer.
  // A caller must fund the read/hash/control overlap and independently admit
  // its publication, installation and generation before using these DATA.
  let originalInstallationPublicationStorageBinding;
  let originalInstallationPublicationStorageBindingReaders = 0;
  const observeOriginalInstallationPublicationStorageBinding = async () => {
    active();
    if (originalInstallationPublicationStorageBindingReaders !== 0) {
      fail('PublicationStoreCleanupPending');
    }
    originalInstallationPublicationStorageBindingReaders++;
    const bytes = await readBounded(storeContractPath, 256, () => {
      originalInstallationPublicationStorageBindingReaders--;
    });
    active();
    // Preserve the exact immutable original contract wire, not a parsed and
    // reserialized replacement. readBounded retains its same FD on failed close.
    if (!bytes.equals(storeContractBytes)) fail('PublicationStoreAuthorityMismatch');
    if (originalInstallationPublicationStorageBinding === undefined) {
      const evidence = Object.freeze({
        storeContractWire: storeContractBytes.toString('utf8'),
        storeAuthorityCid: configuration.storeAuthorityCid,
        keyGenerationCid: `sha256:${createHash('sha256').update(privateEvidenceKey()).digest('hex')}`,
        privateNamespace: 'publication-private',
      });
      originalInstallationPublicationStorageBinding = {evidence,
        handle: Object.freeze({kind: 'installation-publication-storage-binding'})};
    }
    return originalInstallationPublicationStorageBinding.handle;
  };

  // Qualification follows Store startup, before this Store can reach
  // any physical start. Fresh-format failures never leave a lease-only prefix.
  await (prepared?.ownership ?? ownership).qualifyExecutionOwner();
  if (prepared !== undefined) prepared.recoveryReady = true;
  return Object.freeze({
    storeAuthorityCid: configuration.storeAuthorityCid,
    observeOriginalInstallationPublicationStorageBinding,
    originalInstallationPublicationStorageBindingEvidence(handle) {
      active();
      if (originalInstallationPublicationStorageBinding === undefined ||
          handle !== originalInstallationPublicationStorageBinding.handle) {
        fail('ForeignOriginalInstallationPublicationStorageBinding');
      }
      return originalInstallationPublicationStorageBinding.evidence;
    },
    observeOriginalModelStorageBinding,
    originalModelStorageBindingEvidence(handle) {
      active();
      if (originalModelStorageBinding === undefined ||
          handle !== originalModelStorageBinding.handle) {
        fail('ForeignOriginalModelStorageBinding');
      }
      return originalModelStorageBinding.evidence;
    },
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
    // Private Host DATA from this exact Store, not caller-supplied profile
    // dimensions or authenticated storage evidence. The original installation
    // must bind the receiver and fund this record, UTF-8 scan workspace and
    // all derived paths/encodings before using it in an envelope. No path or
    // key bytes escape, and no I/O, reservation, ACK or permission is issued.
    originalModelStorageDimensions() {
      active();
      const key = privateEvidenceKey();
      const namespace = 'local-continuation-private';
      return Object.freeze({
        directoryCodeUnits: configuration.directory.length,
        directoryUtf8Bytes: Buffer.byteLength(configuration.directory, 'utf8'),
        privateNamespaceCodeUnits: namespace.length,
        privateNamespaceUtf8Bytes: Buffer.byteLength(namespace, 'utf8'),
        privateKeyBytes: key.byteLength,
      });
    },
    confirmPrivateEvidence,
    prepareModelRawEvidence,
    readModelRawEvidence,
    confirmModelRawEvidence,
    confirmModelRawCaptureOriginals,
    confirmCapturedContentHoldings,
    putPreparedResultSchema,
    putPublicationContract,
    putPublicationContracts,
    putOriginalPublicationContracts,
    verifyObject,
    observeTrustedClock,
    sampleTrustedClock,
    readClockObservation,
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
    async readPublicationContract(cid, name) {
      active();
      if (typeof name !== 'string' || name.length === 0) {
        fail('InvalidPublicationContractName');
      }
      return (await readContract(cid, name)).contract;
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
          catch (cause) { fail('PublicationStoreCleanupPending', cause); }
        }
        if (physicalRemovalOriginals.size !== 0 || physicalRemovalAcquisitions.size !== 0 ||
            clockObservationsPending !== 0 || reservedObjects !== 0 || preparedObjects.size !== 0 ||
            preparedSchemas.size !== 0 ||
            reclaimableCustodies.size !== 0 ||
            pendingResultDeletions.size !== 0 ||
            pendingMetadataDeletions.size !== 0 ||
            pendingUncommittedMetadataCleanups.size !== 0 ||
            pendingPhysicalHoldingDeletions.size !== 0 ||
            activeResultReaders.size !== 0 ||
            activePhysicalHoldingReaders.size !== 0 ||
            originalModelStorageBindingReaders !== 0 ||
            originalInstallationPublicationStorageBindingReaders !== 0) {
          throw new PublicationStoreError(
            'PublicationStoreCleanupPending',
          );
        }
        // An unsettled read still owns its FD; close must not interrupt it.
        for (const reader of activeSemanticReaders) {
          if (reader.cleanup === undefined) {
            throw new PublicationStoreError(
              'PublicationStoreCleanupPending',
            );
          }
        }
        for (const writer of activePhysicalRecordWriters) {
          if (writer.cleanup === undefined) {
            throw new PublicationStoreError('PublicationStoreCleanupPending');
          }
        }
        // Refuse new Store work once retirement starts, but do not report closed
        // or erase the original key until the SAME ownership confirms release.
        // A redacted control-read error cannot drive private cleanup. The same
        // Store retains that original duty and drains close only, never read/send.
        closeRequested = true;
        for (const reader of activeSemanticReaders) {
          try { await reader.cleanup.retry(); }
          catch { fail('PublicationStoreCleanupPending'); }
        }
        if (activeSemanticReaders.size !== 0) fail('PublicationStoreCleanupPending');
        for (const writer of activePhysicalRecordWriters) {
          if (retriedWriters.has(writer)) continue;
          try { await writer.cleanup.retry(); }
          catch { fail('PublicationStoreCleanupPending'); }
        }
        if (activePhysicalRecordWriters.size !== 0) fail('PublicationStoreCleanupPending');
        deliveryIndex.retainResultDeletionSeal();
        if (deliveryIndex?.close() !== true) fail('PublicationStoreCleanupPending');
        return ownership.release();
      }).then(released => {
        if (released !== true) fail('PublicationStoreOwnershipLost');
        closed = true;
        configuration.privateEvidenceKey?.fill(0);
        originalInstallationPublicationStorageBinding = undefined;
        lastConfirmedEffectCaptureCustody = undefined;
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
