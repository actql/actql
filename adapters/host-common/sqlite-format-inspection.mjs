// SQLite readOnly connections may create -shm or checkpoint during close.
// Never open an unclassified source database with SQLite. Pin read-only file
// descriptors, inspect an isolated DB+WAL copy, and refuse concurrent changes.
import {DatabaseSync} from 'node:sqlite';
import {closeSync, constants, existsSync, fstatSync, lstatSync, mkdtempSync,
  openSync, opendirSync, readSync, realpathSync, rmSync, writeSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, isAbsolute, sep} from 'node:path';
import {throwSqliteInitializationFailure} from './sqlite-transaction.mjs';
import {snapshotSqliteSchemaReadLimits, snapshotSqliteSchemaSqlSupport, inspectBoundedSqliteSchema}
  from './sqlite-schema-resource-bounds.mjs';

const originalRealpath = realpathSync;
const originalNativeRealpath = Object.getOwnPropertyDescriptor(originalRealpath, 'native')?.value;
const nativePathOptions = Object.freeze({__proto__: null, encoding: 'utf8'});
const nativePathApply = Reflect.apply;

const sameFile = (left, right) => ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs']
  .every(key => left[key] === right[key]);

// Original directory inspection shared by the existing SQLite journal Owners.
// Keep complete names, including unrelated entries, for the currentness fence.
// A ceiling is an inspection support bound, not a file-format restriction or
// capacity grant. The same actual Dir owns one lookahead and its close duty.
export function inspectJournalDirectory(directory, {maxEntries = 100_000,
  unavailableCode = 'JournalDirectoryInspectionUnavailable',
  cleanupCode = 'JournalDirectoryInspectionCleanupPending'} = {}) {
  if (!Number.isSafeInteger(maxEntries) || maxEntries < 1) {
    throw Object.assign(new Error('InvalidJournalDirectoryInspectionConfiguration'),
      {code: 'InvalidJournalDirectoryInspectionConfiguration'});
  }
  let original = opendirSync(directory, {bufferSize: 1});
  let originalClose, failed = false, primary;
  const captureClose = () => {
    if (originalClose !== undefined) return;
    const selected = original.closeSync;
    if (typeof selected !== 'function') throw new TypeError('JournalDirectoryCloseUnavailable');
    originalClose = selected;
  };
  const close = () => {
    if (original === undefined) return;
    captureClose();
    if (Reflect.apply(originalClose, original, []) !== undefined) {
      throw new TypeError('JournalDirectoryCleanupPending');
    }
    original = originalClose = undefined;
  };
  let entries;
  try {
    captureClose();
    const read = original.readSync;
    if (typeof read !== 'function') throw new TypeError('JournalDirectoryReadUnavailable');
    entries = [];
    for (;;) {
      const entry = Reflect.apply(read, original, []);
      if (entry === null) break;
      if (entries.length === maxEntries) {
        throw Object.assign(new Error(unavailableCode), {code: unavailableCode});
      }
      entries.push(entry.name);
    }
    entries.sort();
  } catch (cause) { failed = true; primary = cause; }
  try { close(); }
  catch (cause) {
    const first = cause;
    let latest = cause;
    const status = () => Object.freeze({pending: original !== undefined,
      errors: Object.freeze(first === latest ? [first] : [first, latest])});
    const retry = () => {
      try { close(); } catch (error) { latest = error; }
      return status();
    };
    const carrier = Object.assign(new Error(cleanupCode, {cause: failed ? primary : cause}), {
      code: cleanupCode, primaryFailure: failed ? primary : cause,
      cleanupHandle: Object.freeze({status, retry}),
    });
    Object.defineProperty(carrier, 'cleanupPending', {get: () => status().pending});
    throw carrier;
  }
  if (failed) throw primary;
  return entries;
}

export function inspectSqliteSnapshot(databasePath, inspect, {
  code = 'UnknownSqliteJournalFormat',
  validateSource = () => true,
  maxSourceBytes = Number.MAX_SAFE_INTEGER,
  unavailableCode = 'SqliteSnapshotInspectionUnavailable',
  schemaReadLimits,
  schemaSqlSupport,
  assertCurrent,
  temporaryDirectory,
} = {}) {
  if (!Number.isSafeInteger(maxSourceBytes) || maxSourceBytes < 1 ||
      typeof unavailableCode !== 'string' || unavailableCode.length === 0 ||
      assertCurrent !== undefined && typeof assertCurrent !== 'function' ||
      temporaryDirectory !== undefined && (typeof temporaryDirectory !== 'string' ||
        temporaryDirectory.length === 0 || temporaryDirectory.length > 4096 ||
        !isAbsolute(temporaryDirectory) || temporaryDirectory.includes('\0'))) {
    throw Object.assign(new Error('InvalidSqliteSnapshotInspectionConfiguration'),
      {code: 'InvalidSqliteSnapshotInspectionConfiguration'});
  }
  schemaReadLimits = snapshotSqliteSchemaReadLimits(schemaReadLimits);
  schemaSqlSupport = snapshotSqliteSchemaSqlSupport(schemaSqlSupport, schemaReadLimits);
  assertCurrent?.();
  if (assertCurrent !== undefined && typeof originalNativeRealpath !== 'function') {
    throw new TypeError('SqliteInspectionNativePathUnavailable');
  }
  const fail = cause => {
    throw Object.assign(new Error(code, {cause}), {code, path: databasePath});
  };
  const sources = [];
  const outputs = [];
  const walPath = `${databasePath}-wal`;
  let isolated;
  let database;
  let databaseClose;
  let databaseIsOpen;
  const captureDatabaseCleanup = () => {
    databaseClose ??= database.close;
    databaseIsOpen ??= Object.getOwnPropertyDescriptor(database, 'isOpen')?.get;
    if (typeof databaseClose !== 'function' || typeof databaseIsOpen !== 'function') {
      throw new TypeError('SqliteInspectionDatabaseCloseUnavailable');
    }
  };
  let result;
  const complete = new Error('SqliteSnapshotInspectionComplete');
  let primaryFailure = complete;
  const closeFile = original => {
    if (original.closeObserved === true) return;
    if (original.closeAttempted === true) {
      // A numeric FD may already have been consumed/reused when close throws.
      // Retry observes the same Unknown, never another close of that number.
      if (original.closeFailed === true) throw original.closeFailure;
      throw original.closeUnknown;
    }
    original.closeUnknown = new TypeError('SqliteInspectionFileCloseUnknown');
    original.closeAttempted = true;
    try {
      if (Reflect.apply(original.close, undefined, [original.fd]) !== undefined) {
        throw original.closeUnknown;
      }
      original.closeObserved = true;
    } catch (cause) {
      original.closeFailed = true;
      original.closeFailure = cause;
      throw cause;
    }
  };
  const cleanup = {
    close() {
      if (database !== undefined) {
        // Capture once before handing the database to the inspector. Retry
        // only that original close; a later replacement is not an ACK.
        captureDatabaseCleanup();
        const opened = Reflect.apply(databaseIsOpen, database, []);
        if (typeof opened !== 'boolean' ||
            opened && (Reflect.apply(databaseClose, database, []) !== undefined ||
              Reflect.apply(databaseIsOpen, database, []) !== false)) {
          throw new TypeError('SqliteInspectionDatabaseCleanupPending');
        }
        database = databaseClose = databaseIsOpen = undefined;
      }
      while (sources.length !== 0) {
        closeFile(sources.at(-1));
        sources.pop();
      }
      while (outputs.length !== 0) {
        closeFile(outputs.at(-1));
        outputs.pop();
      }
      if (isolated !== undefined) {
        rmSync(isolated, {recursive: true, force: true});
        isolated = undefined;
      }
    },
  };
  try {
    if (existsSync(`${databasePath}-journal`)) fail();
    const hadWal = existsSync(walPath);
    let retainedSourceBytes = 0n;
    for (const path of hadWal ? [databasePath, walPath] : [databasePath]) {
      const fd = openSync(path, constants.O_RDONLY |
        (constants.O_NOFOLLOW ?? 0));
      const source = {path, fd, close: closeSync};
      sources.push(source);
      const identity = fstatSync(fd, {bigint: true});
      source.identity = identity;
      if (!identity.isFile() ||
          identity.size > BigInt(Number.MAX_SAFE_INTEGER)) fail();
      retainedSourceBytes += identity.size;
      // The original pinned DB and WAL coexist with their isolated copies.
      // Refuse their combined extent before allocating scratch or invoking
      // SQLite; an inspection limit is neither a format rule nor funding.
      if (retainedSourceBytes > BigInt(maxSourceBytes)) {
        throw Object.assign(new Error(unavailableCode), {code: unavailableCode});
      }
    }
    // The selected original avoids the JS symlink walk's growing managed
    // path history. Native path/allocator/stack coverage is still required.
    // A selected Root retains this original before native image acquisition.
    // Do not reacquire ambient TMPDIR after that selection. The path itself
    // is neither a filesystem supplier nor an operational admission.
    const scratchOriginal = temporaryDirectory === undefined ? tmpdir() : temporaryDirectory;
    const scratch = assertCurrent === undefined ? realpathSync(scratchOriginal) :
      nativePathApply(originalNativeRealpath, originalRealpath, [scratchOriginal, nativePathOptions]);
    const sourceDirectory = assertCurrent === undefined ? realpathSync(dirname(databasePath)) :
      nativePathApply(originalNativeRealpath, originalRealpath, [dirname(databasePath), nativePathOptions]);
    const withinSource = relative(sourceDirectory, scratch);
    if (withinSource === '' ||
        (withinSource !== '..' && !withinSource.startsWith(`..${sep}`) &&
          !isAbsolute(withinSource))) fail();
    isolated = mkdtempSync(join(scratch, 'actql-journal-format-'));
    // One original backing serves both DB and WAL copying. Falling out of a
    // loop iteration is not a physical release of a previous Buffer backing.
    const chunk = Buffer.allocUnsafe(64 * 1024);
    for (const source of sources) {
      const output = openSync(join(isolated, basename(source.path)), 'wx', 0o600);
      const originalOutput = {fd: output, close: closeSync};
      outputs.push(originalOutput);
      try {
        let offset = 0;
        while (offset < Number(source.identity.size)) {
          const count = readSync(source.fd, chunk, 0,
            Math.min(chunk.length, Number(source.identity.size) - offset),
            offset);
          if (count === 0) fail();
          let written = 0;
          while (written < count) {
            const countWritten = writeSync(output, chunk, written, count - written);
            if (countWritten === 0) fail();
            written += countWritten;
          }
          offset += count;
        }
      } finally {
        closeFile(originalOutput);
        outputs.pop();
      }
    }
    if (schemaReadLimits !== undefined) {
      // The same isolated-copy Owner retains these original read FDs before
      // the schema walk. They coexist with the pinned source FDs, and close
      // before native SQLite construction; failure stays under cleanup below.
      const copies = [];
      for (const source of sources) {
        const fd = openSync(join(isolated, basename(source.path)), constants.O_RDONLY |
          (constants.O_NOFOLLOW ?? 0));
        outputs.push({fd, close: closeSync});
        copies.push({fd, bytes: Number(source.identity.size)});
      }
      inspectBoundedSqliteSchema(copies[0], copies[1], schemaReadLimits, maxSourceBytes, schemaSqlSupport);
      while (outputs.length !== 0) {
        closeFile(outputs.at(-1));
        outputs.pop();
      }
    }
    assertCurrent?.();
    // Keep the selected constructor's internal options closed: native Get
    // otherwise consults inherited callbacks before its wrapper is returned.
    database = new DatabaseSync(join(isolated, basename(databasePath)),
      assertCurrent === undefined ? {open: false, readOnly: true} :
        {__proto__: null, open: false, readOnly: true});
    // The original wrapper and cleanup are retained before native open can
    // acquire a connection and then fail. GC is not its close acknowledgement.
    captureDatabaseCleanup();
    // The selected own-DDL facility keeps temporary Btrees in this same
    // connection's memory domain, including during cold schema inspection.
    // Capture operations before open can invoke native/current callbacks.
    const databasePrepare = schemaSqlSupport === undefined ? undefined : database.prepare;
    const databaseExec = schemaSqlSupport === undefined ? undefined : database.exec;
    if (schemaSqlSupport !== undefined &&
        (typeof databasePrepare !== 'function' || typeof databaseExec !== 'function')) {
      throw new TypeError('SqliteInspectionTemporaryUnavailable');
    }
    assertCurrent?.();
    const databaseOpen = database.open;
    if (typeof databaseOpen !== 'function' ||
        Reflect.apply(databaseOpen, database, []) !== undefined ||
        Reflect.apply(databaseIsOpen, database, []) !== true) {
      throw new TypeError('SqliteInspectionDatabaseOpenUnavailable');
    }
    assertCurrent?.();
    if (schemaSqlSupport !== undefined) {
      const supportedStatement = Reflect.apply(databasePrepare, database,
        ["SELECT sqlite_compileoption_used('TEMP_STORE=1') AS supported"]);
      const supportedGet = supportedStatement.get;
      if (typeof supportedGet !== 'function' ||
          Reflect.apply(supportedGet, supportedStatement, [])?.supported !== 1) {
        throw Object.assign(new Error('SqliteInspectionTemporaryUnavailable'),
          {code: 'SqliteInspectionTemporaryUnavailable'});
      }
      assertCurrent?.();
      Reflect.apply(databaseExec, database, ['PRAGMA temp_store = MEMORY']);
      assertCurrent?.();
      const effectiveStatement = Reflect.apply(databasePrepare, database, ['PRAGMA temp_store']);
      const effectiveGet = effectiveStatement.get;
      if (typeof effectiveGet !== 'function' ||
          Reflect.apply(effectiveGet, effectiveStatement, [])?.temp_store !== 2) {
        throw Object.assign(new Error('SqliteInspectionTemporaryUnavailable'),
          {code: 'SqliteInspectionTemporaryUnavailable'});
      }
      assertCurrent?.();
    }
    result = inspect(database);
    if (existsSync(`${databasePath}-journal`) ||
        existsSync(walPath) !== hadWal || !validateSource() ||
        sources.some(source => !sameFile(source.identity,
          fstatSync(source.fd, {bigint: true})) ||
          !sameFile(source.identity,
            lstatSync(source.path, {bigint: true})))) fail();
  } catch (cause) {
    // A missing/malformed schema or invalid SQLite file is a format refusal,
    // not an untyped SQLite exception escaping the journal boundary. Keep the
    // original driver cause, including when inspection cleanup also fails.
    primaryFailure = typeof cause?.code === 'string' &&
      cause.code.startsWith('ERR_SQLITE') ? Object.assign(
        new Error(code, {cause}), {code, path: databasePath}) : cause;
  }
  // Reuse the same retryable initialization cleanup owner, including for the
  // isolated inspection database. Never mask classification failure with close.
  try {
    throwSqliteInitializationFailure(cleanup, primaryFailure,
      'sqlite-format-inspection');
  } catch (failure) {
    if (failure !== complete) throw failure;
  }
  return result;
}
