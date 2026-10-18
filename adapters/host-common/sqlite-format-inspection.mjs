// SQLite readOnly connections may create -shm or checkpoint during close.
// Never open an unclassified source database with SQLite. Pin read-only file
// descriptors, inspect an isolated DB+WAL copy, and refuse concurrent changes.
import {DatabaseSync} from 'node:sqlite';
import {closeSync, constants, existsSync, fstatSync, lstatSync, mkdtempSync,
  openSync, opendirSync, readSync, realpathSync, rmSync, writeSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, isAbsolute, sep} from 'node:path';
import {throwSqliteInitializationFailure} from './sqlite-transaction.mjs';

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
} = {}) {
  if (!Number.isSafeInteger(maxSourceBytes) || maxSourceBytes < 1 ||
      typeof unavailableCode !== 'string' || unavailableCode.length === 0) {
    throw Object.assign(new Error('InvalidSqliteSnapshotInspectionConfiguration'),
      {code: 'InvalidSqliteSnapshotInspectionConfiguration'});
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
  let result;
  const complete = new Error('SqliteSnapshotInspectionComplete');
  let primaryFailure = complete;
  const closeFile = original => {
    if (Reflect.apply(original.close, undefined, [original.fd]) !== undefined) {
      throw new TypeError('SqliteInspectionFileCleanupPending');
    }
  };
  const cleanup = {
    close() {
      if (database !== undefined) {
        // Capture once before handing the database to the inspector. Retry
        // only that original close; a later replacement is not an ACK.
        databaseClose ??= database.close;
        if (typeof databaseClose !== 'function' ||
            Reflect.apply(databaseClose, database, []) !== undefined) {
          throw new TypeError('SqliteInspectionDatabaseCleanupPending');
        }
        database = databaseClose = undefined;
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
    const scratch = realpathSync(tmpdir());
    const sourceDirectory = realpathSync(dirname(databasePath));
    const withinSource = relative(sourceDirectory, scratch);
    if (withinSource === '' ||
        (withinSource !== '..' && !withinSource.startsWith(`..${sep}`) &&
          !isAbsolute(withinSource))) fail();
    isolated = mkdtempSync(join(scratch, 'actql-journal-format-'));
    for (const source of sources) {
      const output = openSync(join(isolated, basename(source.path)), 'wx', 0o600);
      const originalOutput = {fd: output, close: closeSync};
      outputs.push(originalOutput);
      try {
        const chunk = Buffer.allocUnsafe(64 * 1024);
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
    database = new DatabaseSync(join(isolated, basename(databasePath)),
      {open: true, readOnly: true});
    databaseClose = database.close;
    if (typeof databaseClose !== 'function') {
      throw new TypeError('SqliteInspectionDatabaseCloseUnavailable');
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
