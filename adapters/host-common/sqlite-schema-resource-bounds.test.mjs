import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import fs from 'node:fs';
import {appendFileSync, readFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';
import {openClientRequestJournal} from '../host-node/client-request-journal.mjs';

const defaults = Object.freeze({maxSchemaBytes: 1024 * 1024,
  maxSchemaEntries: 256, maxSchemaPages: 256, maxWalFrames: 131072});
const options = changes => ({maxSourceBytes: 64 * 1024 * 1024,
  schemaReadLimits: {...defaults, ...changes}});
async function fixture({wal = false, tables = 2, pageSize = 4096} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'sqlite-schema-original-', label: 'same-copy pre-native schema resource bounds',
  });
  const path = join(scratch.path, 'source.sqlite3');
  const database = new DatabaseSync(path);
  database.exec(`PRAGMA page_size = ${pageSize}`);
  if (wal) database.exec('PRAGMA journal_mode = WAL');
  database.exec('CREATE TABLE t0(value TEXT)');
  if (wal) database.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  for (let index = 1; index < tables; index++) database.exec(`CREATE TABLE t${index}(value TEXT)`);
  if (!wal) database.close();
  return {scratch, path, database, close() {if (database.isOpen) database.close();}};
}
function countTables(database) {
  return database.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'").get().n;
}
function beforeNativeOpen(body) {
  const open = DatabaseSync.prototype.open;
  let opens = 0;
  DatabaseSync.prototype.open = function () {opens++; return Reflect.apply(open, this, []);};
  try {body(); return opens;} finally {DatabaseSync.prototype.open = open;}
}

// Real independent SQLite-written files and WALs. Resource inspection uses
// only original-copy FDs before native open, and supplies no facility issuer,
// SQL semantic admission, capacity, Run permission or normal Host positive.
test('schema footprint inspection precedes native open and leaves original bytes unchanged', async () => {
  const f = await fixture();
  const before = readFileSync(f.path);
  try {
    assert.equal(beforeNativeOpen(() => {
      assert.equal(inspectSqliteSnapshot(f.path, countTables, options()), 2);
    }), 1);
    assert.deepEqual(readFileSync(f.path), before);
  } finally {f.close();}
  f.scratch.passed();
});

for (const [name, changes] of [['payload', {maxSchemaBytes: 1}], ['entries', {maxSchemaEntries: 1}]]) {
  test('unsupported schema ' + name + ' refuses before native open, not after decoding', async () => {
    const f = await fixture();
    const before = readFileSync(f.path);
    try {
      assert.equal(beforeNativeOpen(() => {
        assert.throws(() => inspectSqliteSnapshot(f.path, countTables, options(changes)),
          {code: 'SqliteSchemaPreparationUnavailable'});
      }), 0);
      assert.deepEqual(readFileSync(f.path), before);
      // The same valid input still works on the unchanged unselected route.
      assert.equal(inspectSqliteSnapshot(f.path, countTables), 2);
    } finally {f.close();}
    f.scratch.passed();
  });
}

test('schema traversal follows original interior-table pages with a pre-read visit bound', async () => {
  const f = await fixture({tables: 100, pageSize: 512});
  try {
    assert.equal(inspectSqliteSnapshot(f.path, countTables, options()), 100);
    assert.equal(beforeNativeOpen(() => {
      assert.throws(() => inspectSqliteSnapshot(f.path, countTables, options({maxSchemaPages: 1})),
        {code: 'SqliteSchemaPreparationUnavailable'});
    }), 0);
  } finally {f.close();}
  f.scratch.passed();
});

// Build a controlled trailer only in this new disposable fixture. The valid
// committed WAL prefix was written by SQLite. Use a page from its checkpointed
// one-table main DB, so trusting the last frame instead of the last valid
// commit would undercount schema entries. This is not old-state recovery.
function appendSmallerSchemaTail(f, validChecksum) {
  const walPath = f.path + '-wal', wal = readFileSync(walPath), db = readFileSync(f.path);
  const p = wal.readUInt32BE(8), frameSize = p + 24;
  assert(wal.length >= 32 + frameSize);
  assert.equal((wal.length - 32) % frameSize, 0);
  const frame = Buffer.alloc(frameSize);
  frame.writeUInt32BE(1, 0);
  frame.writeUInt32BE(validChecksum ? 0 : db.readUInt32BE(28), 4);
  frame.writeUInt32BE(wal.readUInt32BE(16), 8);
  frame.writeUInt32BE(wal.readUInt32BE(20), 12);
  db.copy(frame, 24, 0, p);
  const previous = wal.length - frameSize;
  let a = wal.readUInt32BE(previous + 16), b = wal.readUInt32BE(previous + 20);
  const little = wal.readUInt32BE(0) === 0x377f0682;
  for (const bytes of [frame.subarray(0, 8), frame.subarray(24)]) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for (let offset = 0; offset < bytes.length; offset += 8) {
      a = (a + view.getUint32(offset, little) + b) >>> 0;
      b = (b + view.getUint32(offset + 4, little) + a) >>> 0;
    }
  }
  frame.writeUInt32BE(validChecksum ? a : (a ^ 1) >>> 0, 16);
  frame.writeUInt32BE(b, 20);
  appendFileSync(walPath, frame);
}

for (const tail of ['none', 'uncommitted', 'invalid-checksum']) {
  test('schema budget uses the same last committed WAL prefix with ' + tail + ' tail', async () => {
    const f = await fixture({wal: true});
    if (tail !== 'none') appendSmallerSchemaTail(f, tail === 'uncommitted');
    const dbBefore = readFileSync(f.path), walBefore = readFileSync(f.path + '-wal');
    try {
      assert.equal(inspectSqliteSnapshot(f.path, countTables, options()), 2);
      assert.equal(beforeNativeOpen(() => {
        assert.throws(() => inspectSqliteSnapshot(f.path, countTables,
          options({maxSchemaEntries: 1})), {code: 'SqliteSchemaPreparationUnavailable'});
      }), 0);
      assert.deepEqual(readFileSync(f.path), dbBefore);
      assert.deepEqual(readFileSync(f.path + '-wal'), walBefore);
    } finally {f.close();}
    f.scratch.passed();
  });
}

test('same Journal reopen consumes schema support bounds without replacing format or original rows', async () => {
  const f = await fixture({tables: 1});
  f.close();
  const directory = join(f.scratch.path, 'requests');
  let journal = openClientRequestJournal(directory);
  journal.close();
  journal = undefined;
  try {
    assert.equal(beforeNativeOpen(() => {
      assert.throws(() => {
        journal = openClientRequestJournal(directory, {maxDatabaseBytes: 64 * 1024 * 1024,
          primarySchemaLimits: {...defaults, maxSchemaBytes: 1}});
      }, {code: 'SqliteSchemaPreparationUnavailable'});
    }), 0);
    journal = openClientRequestJournal(directory, {maxDatabaseBytes: 64 * 1024 * 1024,
      primarySchemaLimits: defaults});
  } finally {journal?.close();}
  f.scratch.passed();
});

for (const mode of ['false', 'throw']) {
  test('schema copy FD ' + mode + ' close stays with its original owner before native open', async () => {
    const f = await fixture();
    const open = fs.openSync, close = fs.closeSync;
    let selected, failure, permit = false, closes = 0;
    fs.openSync = function (path, flags, ...rest) {
      const fd = Reflect.apply(open, this, [path, flags, ...rest]);
      if (String(path).includes('actql-journal-format-') && typeof flags === 'number') selected = fd;
      return fd;
    };
    fs.closeSync = function (fd) {
      if (fd === selected) {
        closes++;
        if (!permit) {
          if (mode === 'throw') throw new Error('OriginalSchemaCopyClosePending');
          return false;
        }
      }
      return Reflect.apply(close, this, [fd]);
    };
    syncBuiltinESMExports();
    try {
      assert.equal(beforeNativeOpen(() => {
        assert.throws(() => inspectSqliteSnapshot(f.path, countTables, options()), error => {
          failure = error;
          return error.cleanupHandle?.status().pending === true;
        });
      }), 0);
      assert.equal(fs.fstatSync(selected).isFile(), true);
      const attempts = closes;
      // The fixed close callback, not a later property replacement, owns ACK.
      fs.closeSync = () => undefined;
      syncBuiltinESMExports();
      assert.equal(failure.cleanupHandle.retry().pending, true);
      assert.equal(closes, attempts + 1);
      permit = true;
      assert.equal(failure.cleanupHandle.retry().pending, false);
      assert.throws(() => fs.fstatSync(selected), {code: 'EBADF'});
      assert.equal(failure.cleanupHandle.retry().pending, false);
      assert.equal(closes, attempts + 2);
    } finally {
      permit = true;
      failure?.cleanupHandle?.retry();
      fs.openSync = open;
      fs.closeSync = close;
      syncBuiltinESMExports();
      f.close();
    }
    f.scratch.passed();
  });
}

test('DB and WAL copying reuse one backing instead of assuming loop-local backing retirement', async () => {
  const f = await fixture({wal: true});
  const open = fs.openSync, read = fs.readSync;
  const sources = new Set(), backings = new Set();
  fs.openSync = function (path, flags, ...rest) {
    const fd = Reflect.apply(open, this, [path, flags, ...rest]);
    if (path === f.path || path === f.path + '-wal') sources.add(fd);
    return fd;
  };
  fs.readSync = function (fd, bytes, ...rest) {
    if (sources.has(fd)) backings.add(bytes.buffer);
    return Reflect.apply(read, this, [fd, bytes, ...rest]);
  };
  syncBuiltinESMExports();
  try {
    assert.equal(inspectSqliteSnapshot(f.path, countTables, options()), 2);
    assert.equal(sources.size, 2);
    assert.equal(backings.size, 1);
  } finally {
    fs.openSync = open;
    fs.readSync = read;
    syncBuiltinESMExports();
    f.close();
  }
  f.scratch.passed();
});
