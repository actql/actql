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
import {createResultDeletionOwner} from './result-deletion-owner.mjs';
import {createMetadataDeletionOwner} from './metadata-deletion-owner.mjs';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';
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

async function acquireStoreOwnership(root, bootstrap, key) {
  const ownershipDirectory = resolve(root, 'owner');
  const ownerPath = resolve(ownershipDirectory, 'owner.json');
  const token = randomUUID();
  // Read before acquiring ownership: a failed identity observation cannot
  // strand a newly created owner. Keep scalars, not the entire Stats object.
  const {dev: rootDevice, ino: rootInode} = await lstat(root, {bigint: true});
  while (true) {
    try {
      await mkdir(ownershipDirectory, {mode: 0o700});
      const owner = Buffer.from(JSON.stringify({
        version: 'actql-local-publication-store-owner/0.1',
        pid: process.pid,
        token,
      }), 'utf8');
      let released = false, ownerRemoved = false, directoryRemoved = false;
      let ownershipDevice, ownershipInode;
      let retirementDirectory, retirementSynced = false;
      let ownerWriter, ownerWriterClose, ownerFileIdentity;
      let retirementReadCleanup, retirementReadFailure;
      let ownerFileCreated = false, ownerWritten = false;
      const ownership = Object.freeze({
        async assertCurrent() {
          if (!ownerWritten || ownerWriter !== undefined || released || ownerRemoved ||
              directoryRemoved || retirementDirectory !== undefined) {
            fail('PublicationStoreOwnershipLost');
          }
          const currentRoot = await lstat(root, {bigint: true});
          const directory = await lstat(ownershipDirectory, {bigint: true});
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
            try { directory = await lstat(ownershipDirectory, {bigint: true}); }
            catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
            if (!directory.isDirectory() || directory.isSymbolicLink()) {
              fail('PublicationStoreOwnershipLost');
            }
            if (!ownerRemoved) {
              if (ownerWritten) {
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
                if (existing?.token !== token || existing?.pid !== process.pid) {
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
            // Record only actually acknowledged phases in this original
            // handle. Never reconstruct an absent record or unlink again.
            if (!ownerRemoved) {
              if (ownerFileCreated) await unlink(ownerPath);
              ownerRemoved = true;
            }
            await rmdir(ownershipDirectory);
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
        await syncDirectoryPath(ownershipDirectory);
        await syncDirectoryPath(root);
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
        ? await readFile(ownerPath, 'utf8') : await bootstrap.readMetadata(ownerPath)); }
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
      if (await processIsAlive(existing.pid)) fail('PublicationStoreBusy');
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
  entry.ownership = await acquireStoreOwnership(root, bootstrap, undefined);
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

  try {
    await writeExclusive(storeContractPath, storeContractBytes);
    await syncDirectory(root);
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
  for (const name of await readOpeningDirectory(objectsDirectory)) {
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
  let ownership, deliveryIndex;
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
  for (const name of await readOpeningDirectory(stagingDirectory)) {
    const path = resolve(stagingDirectory, name);
    if (!/^object-[0-9a-f-]{36}$/u.test(name) ||
        !(await lstat(path)).isFile()) {
      fail('InvalidPublicationStagingObject');
    }
    await unlink(path);
  }
  await syncDirectory(stagingDirectory);

  for (const name of await readOpeningDirectory(custodyDirectory)) {
    const path = resolve(custodyDirectory, name);
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedCustody');
    }
  }
  await syncDirectory(custodyDirectory);
  for (const name of await readOpeningDirectory(preparedSchemasDirectory)) {
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

  // Delivery coverage and pending recovery below own the selected entries.
  // Ordinary opens must not enumerate every historical delivery directory.
  for (const name of await readOpeningDirectory(manifestReadsDirectory)) {
    const path = resolve(manifestReadsDirectory, name);
    if (name.startsWith('.staging-')) {
      await removeOpeningTree(path, bootstrap);
      continue;
    }
    if (!/^[0-9a-f]{64}$/u.test(name) || !(await lstat(path)).isDirectory()) {
      fail('InvalidManifestReadStore');
    }
    for (const useName of await readOpeningDirectory(path)) {
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
  for (const name of await readOpeningDirectory(metadataInventoriesDirectory)) {
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(metadataInventoriesDirectory, name))).isFile()) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
  }
  await syncDirectory(metadataInventoriesDirectory);
  for (const name of await readOpeningDirectory(metadataDeletionsDirectory)) {
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
    for (const name of await readOpeningDirectory(directory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
          !(await lstat(resolve(directory, name))).isFile()) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
    }
    await syncDirectory(directory);
  }
  for (const keyHash of await readOpeningDirectory(retentionExtensionsDirectory)) {
    const directory = resolve(retentionExtensionsDirectory, keyHash);
    if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
        !(await lstat(directory)).isDirectory()) {
      fail('InvalidPublicationRetentionExtensionStore');
    }
    for (const name of await readOpeningDirectory(directory)) {
      const path = resolve(directory, name);
      if (!/^[0-9a-f]{64}$/u.test(name) ||
          !(await lstat(path)).isDirectory()) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      for (const record of await readOpeningDirectory(path)) {
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
  for (const keyHash of await readOpeningDirectory(deletionsDirectory)) {
    const directory = resolve(deletionsDirectory, keyHash);
    if (!/^[0-9a-f]{64}$/u.test(keyHash) ||
        !(await lstat(directory)).isDirectory()) {
      fail('InvalidPublicationDeletionStore');
    }
    for (const name of await readOpeningDirectory(directory)) {
      if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
          !(await lstat(resolve(directory, name))).isFile()) {
        fail('InvalidPublicationDeletionStore');
      }
    }
  }
  await syncDirectory(deletionsDirectory);
  for (const name of await readOpeningDirectory(clocksDirectory)) {
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
  let closeRequested = false, closeFlight;
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
  // One bounded durability observation, not a retained contract or Allow.
  // Each public confirmation still acquires and checks its selected record.
  let lastConfirmedDeliveryRecord;
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

  const writePhysicalHoldingRecord = async (path, bytes, exclusive = true) => {
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
      directory: stagingDirectory, syncDirectory};
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
        await original.syncDirectory(original.directory);
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
    // Publish a final recovery name only after the original record is complete,
    // synced and closed. An abrupt process stop may leave staging bytes, never
    // a partial final custody. Failed close stays in the same Store duty set.
    await writePhysicalHoldingRecord(path, Buffer.from(JSON.stringify(record), 'utf8'), false);
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
      const buffer = Buffer.allocUnsafeSlow(before.size < 65536 ? before.size + 1 : 65536);
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
        await flushClockFile(clockContractCid, snapshot, bytes);
        const current = await readClockSnapshot(clockContractCid);
        if (current?.value.observedAt !== observedAt ||
            !['dev', 'ino', 'size'].every(field => current.state[field] === snapshot.state[field])) {
          fail('PublicationClockUncertain');
        }
        durablyConfirmedClocks.set(clockContractCid, observedAt);
        durablyConfirmedClockFiles.set(clockContractCid, current.state);
        return current.value;
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
        isReclaiming: cid => reclaimingMaterialCids.has(cid),
        registerCustody,
        reclaimCustody,
        verifyObject,
        accountInstalled(bytes, custody) {
          storedBytes += bytes;
          objectCount++;
          if (custody !== undefined) custody.accounted = true;
        },
      },
    );

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
          // A physical holding and its prepared release use the same existing
          // material queue. An awaited directory ACK must not race reclamation.
          const previous = group.busy;
          const operation = materialRetentionBusy.then(() => previous).then(async () => {
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
            // Physical holdings refer to bytes by CID, not inode hard links.
            // A visible holding after a lost commit ACK is still responsibility,
            // not permission to unlink. Keep this exact pending handle until
            // the same commit is confirmed or its holding is lawfully retired.
            if (await materialHasLiveReference(physical.cid)) return false;
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
          materialRetentionBusy = group.busy;
          holder.releasing = operation.catch(error => {
            // Private diagnostics retain the original first and latest
            // failed release, not an unbounded retry log. Keep both roles
            // even when the same Error is reused; status snapshots own their
            // copied arrays. This never settles the original physical duty.
            if (errors.length < 2) errors.push(error);
            else errors[1] = error;
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
  const putSemanticBatch = async supplied => {
    active();
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    // This private caller supplies one semantic body, or one already admitted
    // delivery group. No prepared holder escapes between writes
    // and their final names, so no intermediate durable custody is needed.
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
    const writer = {cleanup: undefined, failed: false};
    const dirty = new Set();
    activePhysicalRecordWriters.add(writer);
    const account = item => {
      if (item.accounted) return;
      storedBytes += item.bytes.byteLength;
      objectCount++;
      item.accounted = item.objectCreated = true;
    };
    const syncNames = async () => {
      for (const directory of [objectsDirectory, contractsDirectory]) {
        if (!dirty.has(directory)) continue;
        await syncDirectory(directory);
        dirty.delete(directory);
      }
    };
    let flight, failure;
    const status = () => Object.freeze({pending: dirty.size !== 0 || items.some(item =>
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
            if (item.objectLinkAttempted && !item.accounted) {
              let original;
              try { original = await lstat(objectPath(item.cid)); }
              catch (error) { if (error?.code !== 'ENOENT') throw error; }
              // Observe a lost link reply without reissuing the link/write.
              if (original?.isFile() && original.dev === item.state.dev &&
                  original.ino === item.state.ino) account(item);
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
      for (const item of items) {
        if (item.temporary === undefined) continue;
        if (reclaimingMaterialCids.has(item.cid)) fail('PublicationObjectReclamationPending');
        item.objectLinkAttempted = true;
        dirty.add(objectsDirectory);
        try { await link(item.temporary, objectPath(item.cid)); account(item); }
        catch (error) {
          if (error?.code !== 'EEXIST') throw error;
          if ((await verifyObject(item.cid)).bytes !== item.bytes.byteLength) {
            fail('PublicationObjectIdentityMismatch');
          }
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
      await syncNames();
      // Staging names never establish durable state. They are unlinked only
      // after original close; a name resurrected by a crash is removed by the
      // existing exclusive opening recovery, not interpreted as a commit.
      await cleanup.retry();
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
    active();
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
          end: before.size - 1, highWaterMark: Math.min(65536, before.size)});
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
      return bytes;
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
    name, semanticCid, holdingCid, index = 0, objectCount = 1,
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
      const holding = await inspectPhysicalHolding(holdingCid);
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
      // The existing holding owns an exact bounded file. Receive directly
      // into one buffer instead of retaining copied chunks plus their concat.
      // No bytes escape before consumePhysicalHolding and AEAD both succeed.
      const bytes = Buffer.alloc(expectedBytes);
      let receivedBytes = 0;
      await consumePhysicalHolding(holdingCid, index, chunk => {
        if (chunk.byteLength > expectedBytes - receivedBytes) {
          fail('PublicationPrivateEvidenceCorrupt');
        }
        bytes.set(chunk, receivedBytes);
        receivedBytes += chunk.byteLength;
      });
      if (receivedBytes !== expectedBytes) {
        fail('PublicationPrivateEvidenceCorrupt');
      }
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
        const plaintext = decipher.update(ciphertext);
        // Authentication must complete before any plaintext escapes. Reuse
        // the owned block only after final succeeds with no additional bytes;
        // otherwise preserve the complete authenticated concatenation.
        const final = decipher.final();
        return final.byteLength === 0 ? plaintext
          : Buffer.concat([plaintext, final]);
      } catch (error) {
        if (error?.code === 'PublicationPrivateEvidenceCorrupt') throw error;
        fail('PublicationPrivateEvidenceCorrupt', error);
      }
    } finally {
      key.fill(0);
    }
  };
  const readPrivateEvidence = (name, semanticCid, holdingCid) =>
    readPrivateEvidenceObject(name, semanticCid, holdingCid);
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
    ]) || typeof binding.wire !== 'string' ||
        Buffer.byteLength(binding.wire, 'utf8') > configuration.maxObjectBytes ||
        !quantity(binding.byteCount) ||
        binding.byteCount > configuration.maxObjectBytes) {
      fail('InvalidPublicationModelRawEvidence');
    }
    for (const cid of [binding.semanticCid, binding.holdingCid, binding.contentCid]) {
      cidHex(cid);
    }
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
    validateModelRawBinding(binding);
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
  const readModelRawEvidence = async binding => {
    active();
    validateModelRawBinding(binding);
    const record = await inspectPhysicalHolding(binding.holdingCid);
    if (record === undefined) return undefined;
    if (record.namespace !== 'publication-private' ||
        record.manifest_cid !== binding.semanticCid || record.objects.length !== 2) {
      fail('PublicationPrivateEvidenceUnavailable');
    }
    if (!exactUtf8WireMatches(await readPrivateEvidenceObject(
      'model_raw_descriptor', binding.semanticCid, binding.holdingCid, 0, 2,
    ), binding.wire)) {
      fail('PublicationPrivateEvidenceConflict');
    }
    const bytes = await readPrivateEvidenceObject(
      'model_raw_content', binding.semanticCid, binding.holdingCid, 1, 2,
    );
    verifyModelRawBytes(binding, bytes);
    return bytes;
  };
  const confirmModelRawEvidence = async binding => {
    const bytes = await readModelRawEvidence(binding);
    if (bytes === undefined) return undefined;
    const record = await inspectPhysicalHolding(binding.holdingCid);
    // A readable directory link is not the nominal saved observation. The
    // adapter may report saved only after this existing durability boundary.
    await commitPhysicalHolding(record, []);
    return Object.freeze({record, bytes});
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

  const readDeliveryAttemptContract = async (attemptCid, retained) => {
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
  const restoreDeliveryClaim = async row => {
    const attemptContract = admitContract('delivery_attempt', row.attempt_wire);
    const grantContract = admitContract('result_read_grant', row.grant_wire);
    const attempt = parseContract(attemptContract), grant = parseContract(grantContract);
    const expected = deliveryIndexRow(attempt,grant,attemptContract,grantContract);
    if (Object.keys(expected).some(name => expected[name] !== row[name]) ||
        attempt.result_read_grant_cid !== grantContract.identity ||
        attempt.run_definition_cid !== grant.run_definition_cid ||
        attempt.result_manifest_cid !== grant.result_manifest_cid ||
        !grant.results.some(result => result.result_name === attempt.result_name &&
          result.result_artifact_cid === attempt.result_artifact_cid)) fail('InvalidDeliveryAttemptIndex');
    await putDeliveryContracts(grantContract,attemptContract);
    await installDeliveryAttempt(attemptContract);
    deliveryIndex.finish(row.logical_key,attemptContract.identity);
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
    });
    if (deliveryIndex.needsMigration()) {
      if (coverage.phase !== 'building') fail('DeliveryAttemptIndexUnavailable');
      const rows = [], grants = new Map(), uses = new Map();
      for (const name of await readdir(deliveriesDirectory)) {
        if (name.startsWith('.staging-')) {
          await removeOpeningTree(resolve(deliveriesDirectory,name),bootstrap);
          continue;
        }
        if (!/^[0-9a-f]{64}$/u.test(name) ||
            !(await lstat(resolve(deliveriesDirectory,name))).isDirectory()) fail('InvalidDeliveryAttemptStore');
        if (rows.length >= configuration.maxObjects) fail('DeliveryAttemptIndexLimit');
        const attemptContract = await readDeliveryAttemptContract(`sha256:${name}`);
        const attempt = parseContract(attemptContract);
        let original = grants.get(attempt.result_read_grant_cid);
        if (original === undefined) {
          original = await readContract(attempt.result_read_grant_cid,'result_read_grant');
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
    if (coverage.phase !== 'ready') await publishCoverage('ready');
    // Only unfinished indexed claims are revisited. No ordinary open scans or
    // re-admits all historical attempts/grants after coverage is complete.
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
    const selected = deliveryIndex.claim(row,grant.max_uses);
    if (!selected.created) fail('DeliveryAttemptConflict');
    // The durable pending claim already owns uniqueness and the grant use.
    // Failure never refunds it. Recovery projects these SAME stored originals;
    // it does not dispatch a stream or invent another attempt.
    await putDeliveryContracts(grantContract,admitted,initial?.streaming);
    await installDeliveryAttempt(admitted,initial?.streaming);
    deliveryIndex.finish(row.logical_key,admitted.identity);
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

  const readLatestDeliveryRecordContract = async (attemptCid, original) => {
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
    const attemptContract = await readDeliveryAttemptContract(
      row.attempt_cid, suppliedAttempt?.contract);
    const attempt = attemptContract === suppliedAttempt?.contract
      ? suppliedAttempt.value : parseContract(attemptContract);
    let grantContract, grant;
    if (suppliedGrant?.contract.identity === row.grant_cid) {
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
    const record = includeProgress
      ? await latestDeliveryRecord(attemptContract.identity) : undefined;
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
    return appendAdmittedDeliveryRecord(contract);
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
    return appendAdmittedDeliveryRecord(contract, {attempt, receipt, record});
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
    if (suppliedReceipt === undefined) await putSemantic(contract.wire, contract.identity);
    else await putSemanticBatch([suppliedReceipt, contract].map(value => ({
      wire: value.wire, semanticCid: value.identity,
    })));
    const target = resolve(directory, `${record.sequence}.json`);
    try { await link(contractPath(record.delivery_record_cid), target); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('DeliveryRecordConflict');
      throw error;
    }
    return confirmAdmittedDeliveryRecord(contract, record, true);
  };

  const readCommittedIndexRaw = async (key, original) => {
    active();
    const path = resolve(indexesDirectory, `${indexKey(key)}.json`);
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
    const semantic = await readSemanticBytes(entry.public_index_entry_cid);
    // The selected Index and its immutable contract alias describe the same
    // fact. Reuse its admission for identical bytes, without skipping the
    // alias's real FD/inode/digest checks or admitting a changed spelling as
    // though it were the original.
    if (!exactUtf8WireMatches(semantic, admitted.wire)) {
      parseContract(admitContract('public_index_entry', semantic.toString('utf8')));
    }
    return {entry, bytes};
  };

  const inspectCommittedIndexRaw = async key =>
    (await readCommittedIndexRaw(key))?.entry;

  const inspectCommittedIndex = async key => {
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) return undefined;
    return inspectCommittedIndexRaw(key);
  };

  const confirmCommittedIndex = async key => {
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
      chainValid = await contractControl.effectFreeCommitValid(
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
      namespaceId: entry.namespace_id,
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
    const expectedContent = await confirmCapturedContentHoldings(
      suppliedEvidence.capturedRun, suppliedEvidence.runDefinition);
    const inventory = await readMetadataInventory(admitted.identity);
    if (inventory?.physical_holding_cids.join('\0') !== expectedContent.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    await adoptPreparedObjects(boundPhysicalCids);
    return true;
  };

  // This is stored-evidence inspection, not physical row-outcome admission
  // or publication commit. The portable control admits the final reference
  // chain; the Store confirms its public bodies and private physical holdings.
  // A caller cannot use this result as an apply or commit permit.
  const inspectEffectfulStoredEvidence = async ({index, chain, preview,
    receipts, privateBinding, effectSources}) => {
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
    const admittedIndex = admitContract('public_index_entry', index?.wire);
    if (admittedIndex.identity !== index?.identity) {
      fail('InvalidEffectfulStoredEvidence');
    }
    const entry = parseContract(admittedIndex);
    const request = (await readContract(
      entry.publication_request_cid, 'publication_request',
    )).contract;
    const attempt = (await readContract(
      entry.publication_attempt_cid, 'publication_attempt',
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
          !(await readSemanticBytes(contract.identity)).equals(
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
        artifactCid, 'effect_source_artifact',
      )).value;
      await readSemanticBytes(artifact.result_schema_cid);
      sourceArtifactCids.push(artifactCid);
      sourceSchemaCids.push(artifact.result_schema_cid);
      await commitPhysicalHolding(holding, []);
    }
    for (const binding of chain.durableBindings) {
      await verifyDurableResultBinding(binding);
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
          captureRecord = JSON.parse((await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, recordCid,
          )).toString('utf8'));
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
          record = captureRecord ?? JSON.parse((await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, candidate,
          )).toString('utf8'));
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
  ) => {
    active();
    const admitted = admitContract('public_index_entry', suppliedWire);
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
    for (const cid of required) await readSemanticBytes(cid);
    let boundPhysicalCids;
    let physicalHoldingCids = [];
    if (effectfulEvidence === undefined) {
      boundPhysicalCids = await verifyCommitEvidence(
        admitted, entry, suppliedEvidence, required,
      );
      physicalHoldingCids = [...await confirmCapturedContentHoldings(
        suppliedEvidence.capturedRun, suppliedEvidence.runDefinition)];
    } else {
      if (effectfulEvidence.index.identity !== admitted.identity) {
        fail('InvalidEffectfulStoredEvidence');
      }
      const inspected = await inspectEffectfulStoredEvidence({
        ...effectfulEvidence, index: admitted,
      });
      for (const cid of [
        ...inspected.publicContractCids,
        ...inspected.sourceArtifactCids,
        ...inspected.sourceSchemaCids,
      ]) {
        if (!required.has(cid)) {
          fail('IncompletePublicationCommitInventory');
        }
      }
      boundPhysicalCids = [];
      for (const binding of suppliedEvidence.durableBindings) {
        const verified = await verifyDurableResultBinding(binding);
        boundPhysicalCids.push(verified.binding.material_generation_cid);
      }
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
    const adoptObjects = () => adoptPreparedObjects(boundPhysicalCids);
    const adoptSchemas = () => adoptPreparedSchemas(
      inventorySemanticCids, entry.run_definition_cid,
    );
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
            inventory.physical_holding_cids.join('\0') !==
              physicalHoldingCids.join('\0') ||
            directlyRequired.some(cid =>
              !inventory.contract_objects.some(object =>
                object.semantic_cid === cid))) {
          fail('InvalidPublicationMetadataInventoryStore');
        }
      },
      async stage() {
        await putPublicationContract('public_index_entry', admitted.wire);
        const inventoryContractObjects = await bindMetadataContractObjects(
          inventorySemanticCids,
        );
        await ensureMetadataInventory(Object.freeze({
          version: 'actql-local-publication-metadata-inventory/0.1',
          namespace_id: entry.namespace_id,
          authority_scope_cid: entry.authority_scope_cid,
          run_definition_cid: entry.run_definition_cid,
          public_index_entry_cid: admitted.identity,
          publication_attempt_cid: entry.publication_attempt_cid,
          contract_objects: inventoryContractObjects,
          physical_holding_cids: physicalHoldingCids,
        }));
      },
      beginCustody() {
        return beginPreparedCommit(
          boundPhysicalCids, key, entry.public_index_entry_cid,
        );
      },
      async install(markInstalled) {
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
  const commitIndex = (...args) =>
    withSemanticCommit(() => commitIndexInternal(...args));

  const commitEffectfulIndex = (preparation, requiredObjectCids) => {
    if (!exactKeys(preparation, [
      'index', 'chain', 'preview', 'receipts', 'privateBinding',
      'effectSources',
    ]) || typeof preparation.index?.wire !== 'string') {
      fail('InvalidEffectfulStoredEvidence');
    }
    return withSemanticCommit(() => commitIndexInternal(
      preparation.index.wire, requiredObjectCids, preparation.chain,
      preparation,
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
    const inventory = await readMetadataInventory(inspected.index.identity);
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
        const buffer = Buffer.allocUnsafeSlow(Math.min(65536, before.size - bytes));
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

  const readRetainedResultExtension = async (
    key,
    resultDefinitionCid,
    metadataOnly = false,
  ) => {
    active();
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid,
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

  const readCommittedResultRetentionExtension = (key, resultDefinitionCid) =>
    readRetainedResultExtension(key, resultDefinitionCid, false);

  // Inspect the retained immutable schema and binding inventory. Payload
  // deletion does not delete publication metadata; no generation is opened,
  // hashed or held as a payload reader by this operation.
  const readCommittedResultDescriptionEvidence = async (key, definitionCid) => {
    active();
    const selected = await requireCommittedResultBinding(key, definitionCid);
    const bindings = await Promise.all(
      selected.entry.durable_result_binding_cids.map(async cid =>
        cid === selected.contract.identity ? selected.contract :
          (await readContract(cid, 'durable_result_binding')).contract));
    const schemaWire = (await readSemanticBytes(
      selected.value.result_schema_cid)).toString('utf8');
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
    deliveryIndex?.forgetRun(runDefinitionCid);
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
      await syncDirectory(physicalHoldingsDirectory);
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
    await syncDirectory(physicalHoldingsDirectory);
    await adoptPreparedObjects([...expected.keys()]);
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
    ]) || !['effect_preview', 'effect_capture', 'effect_catalog', 'credential_raw_observation', 'model_capture_bundle',
      'model_slot_capture', 'model_invocation_evidence', 'model_call_attempt', 'model_attempt_accounting',
      'model_attempt_outcome', 'model_dispatch_authority', 'model_attachment_admission',
      'observation_set', 'run_invocation', 'source_evidence',
      'content_input_artifact', 'content_evidence', 'content_generation',
      'installation_publication'].includes(binding.name) ||
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
    if (!exactUtf8WireMatches(stored, binding.wire)) {
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

  // Retirement validates ownership metadata, not payload usability. A
  // missing or corrupt payload must remain unreadable but may still be
  // retired by its exact owner. This is never a consumption/admission proof.
  const inspectPhysicalHoldingForRetirement = async holdingCid => {
    active();
    cidHex(holdingCid);
    return await readPhysicalHolding(holdingCid) ??
      await readPhysicalHoldingDeletion(holdingCid);
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
    let released = false;
    const closed = () => {
      if (released) return;
      released = true;
      const remaining =
        (activePhysicalHoldingReaders.get(holdingCid) ?? 1) - 1;
      if (remaining === 0) activePhysicalHoldingReaders.delete(holdingCid);
      else activePhysicalHoldingReaders.set(holdingCid, remaining);
    };
    return await consumeObject(record.objects[objectIndex].cid, accept, closed);
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
  const readEffectCaptureCustody = async suppliedRun => {
    active();
    const run = captureCustodyRun(suppliedRun);
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
  const retainEffectCaptureCustody = (suppliedRun, suppliedHoldings) => {
    active();
    const run = captureCustodyRun(suppliedRun);
    const holdings = suppliedHoldings.map(value =>
      parsePhysicalHolding(Buffer.from(JSON.stringify(value))));
    return withSemanticCommit(async () => {
      const previous = await readEffectCaptureCustody(run);
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
      const bytes = Buffer.from(JSON.stringify({
        version: 'actql-effect-capture-custody/0.1',
        store_authority_cid: configuration.storeAuthorityCid,
        run_definition: run.wire, holdings: [...records.values()],
      }));
      if (records.size > 4096 || bytes.length >
          Math.min(configuration.maxObjectBytes, 16 * 1024 * 1024)) {
        fail('EffectCaptureCustodyLimitExceeded');
      }
      const staging = resolve(stagingDirectory, `object-${randomUUID()}`);
      await writeExclusive(staging, bytes);
      await rename(staging, captureCustodyPath(run));
      await syncDirectory(captureCustodyDirectory);
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
      if (await readEffectCaptureCustody(run) !== undefined) result.push(run);
    }
    return Object.freeze(result);
  };
  const forgetEffectCaptureCustody = async suppliedRun => {
    active();
    const run = captureCustodyRun(suppliedRun);
    await readEffectCaptureCustody(run);
    try { await unlink(captureCustodyPath(run)); }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    await syncDirectory(captureCustodyDirectory);
  };
  const retireEffectCaptureCustody = async suppliedRun => {
    const record = await readEffectCaptureCustody(suppliedRun);
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
    await forgetEffectCaptureCustody(suppliedRun);
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
        // Startup validates ownership records, not every Run's payload.
        // inspect/consume/commit still verify bytes before using a holding.
        // A missing or damaged object must not disable unrelated Runs, nor
        // turn its retained recovery responsibility into absent evidence.
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
        namespaceId: inventory.namespace_id,
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
        if (state === undefined) return 'missing';
        if (!state.isFile() || state.size !== expectedBytes) {
          fail('PublicationDurableBindingMismatch');
        }
        // Other Store-owned references can share this inode. Keep the base
        // name and capacity charge while any physical link remains.
        return state.nlink > 1 ? 'shared' : 'exclusive';
      },
      unlink: () => unlink(objectPath(materialCid)),
      syncObjects: () => syncDirectory(objectsDirectory),
      releaseCapacity() {
        storedBytes -= expectedBytes;
        objectCount--;
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
    const cleanup = createMetadataDeletionOwner(marker, {
      serialize(run) {
        const operation = metadataRetentionBusy.then(run);
        metadataRetentionBusy = operation.catch(() => {});
        return operation;
      },
      syncObjects: () => syncDirectory(objectsDirectory),
      releaseUnconfirmed(objects) {
        for (const bytes of objects.values()) {
          storedBytes -= bytes;
          objectCount--;
        }
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
      settle() { pendingMetadataDeletions.delete(keyHash); },
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
      if (await readMetadataDeletion(keyHash) === undefined) {
        for (const holdingCid of inventory.physical_holding_cids) {
          // Validate the index-to-owner link without opening its payloads.
          // Payload availability is checked by the actual Result consumer.
          if (await readPhysicalHoldingDeletion(holdingCid) !== undefined ||
              await readPhysicalHolding(holdingCid) === undefined) {
            fail('InvalidPublicationMetadataInventoryStore');
          }
        }
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

  // The same index must be live when interrupted metadata retirement removes
  // its selected attempt rows. Retired pending claims are not re-published.
  await initializeDeliveryIndex();

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
    latestRecord,
    latestRecordContract,
    appendRecord,
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
    inspectEffectfulStoredEvidence,
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
      if (closeFlight !== undefined) return closeFlight;
      if (closed) return Promise.resolve(true);
      if (clockObservationsPending !== 0 || reservedObjects !== 0 || preparedObjects.size !== 0 ||
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
        return Promise.reject(new PublicationStoreError(
          'PublicationStoreCleanupPending',
        ));
      }
      // An unsettled read still owns its FD; close must not interrupt it.
      for (const reader of activeSemanticReaders) {
        if (reader.cleanup === undefined) {
          return Promise.reject(new PublicationStoreError(
            'PublicationStoreCleanupPending',
          ));
        }
      }
      for (const writer of activePhysicalRecordWriters) {
        if (writer.cleanup === undefined) {
          return Promise.reject(new PublicationStoreError('PublicationStoreCleanupPending'));
        }
      }
      // Refuse new Store work once retirement starts, but do not report closed
      // or erase the original key until the SAME ownership confirms release.
      // A redacted control-read error cannot drive private cleanup. The same
      // Store retains that original duty and drains close only, never read/send.
      closeRequested = true;
      closeFlight = Promise.resolve().then(async () => {
        for (const reader of activeSemanticReaders) {
          try { await reader.cleanup.retry(); }
          catch { fail('PublicationStoreCleanupPending'); }
        }
        if (activeSemanticReaders.size !== 0) fail('PublicationStoreCleanupPending');
        for (const writer of activePhysicalRecordWriters) {
          try { await writer.cleanup.retry(); }
          catch { fail('PublicationStoreCleanupPending'); }
        }
        if (activePhysicalRecordWriters.size !== 0) fail('PublicationStoreCleanupPending');
        if (deliveryIndex?.close() !== true) fail('PublicationStoreCleanupPending');
        return ownership.release();
      }).then(released => {
        if (released !== true) fail('PublicationStoreOwnershipLost');
        closed = true;
        configuration.privateEvidenceKey?.fill(0);
        originalInstallationPublicationStorageBinding = undefined;
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
