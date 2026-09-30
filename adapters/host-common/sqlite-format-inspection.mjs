// SQLite readOnly connections may create -shm or checkpoint during close.
// Never open an unclassified source database with SQLite. Pin read-only file
// descriptors, inspect an isolated DB+WAL copy, and refuse concurrent changes.
import {DatabaseSync} from 'node:sqlite';
import {closeSync, constants, existsSync, fstatSync, lstatSync, mkdtempSync,
  openSync, readSync, realpathSync, rmSync, writeSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, isAbsolute, sep} from 'node:path';
import {throwSqliteInitializationFailure} from './sqlite-transaction.mjs';

const sameFile = (left, right) => ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs']
  .every(key => left[key] === right[key]);

export function inspectSqliteSnapshot(databasePath, inspect, {
  code = 'UnknownSqliteJournalFormat',
  validateSource = () => true,
} = {}) {
  const fail = cause => {
    throw Object.assign(new Error(code, {cause}), {code, path: databasePath});
  };
  const sources = [];
  const outputs = [];
  const walPath = `${databasePath}-wal`;
  let isolated;
  let database;
  let result;
  const complete = new Error('SqliteSnapshotInspectionComplete');
  let primaryFailure = complete;
  const cleanup = {
    close() {
      if (database !== undefined) {
        database.close();
        database = undefined;
      }
      while (sources.length !== 0) {
        closeSync(sources.at(-1).fd);
        sources.pop();
      }
      while (outputs.length !== 0) {
        closeSync(outputs.at(-1));
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
    for (const path of hadWal ? [databasePath, walPath] : [databasePath]) {
      const fd = openSync(path, constants.O_RDONLY |
        (constants.O_NOFOLLOW ?? 0));
      const source = {path, fd};
      sources.push(source);
      const identity = fstatSync(fd, {bigint: true});
      source.identity = identity;
      if (!identity.isFile() ||
          identity.size > BigInt(Number.MAX_SAFE_INTEGER)) fail();
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
      outputs.push(output);
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
        closeSync(output);
        outputs.pop();
      }
    }
    database = new DatabaseSync(join(isolated, basename(databasePath)),
      {open: true, readOnly: true});
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
