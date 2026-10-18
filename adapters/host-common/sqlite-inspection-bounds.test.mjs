import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {syncBuiltinESMExports} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';

async function fixture() {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'sqlite-inspection-bound-', label: 'original bounded SQLite inspection'});
  const path = join(scratch.path, 'original.sqlite3');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE original(value TEXT NOT NULL) STRICT;');
  database.prepare('INSERT INTO original VALUES (?)').run('same-original');
  return {scratch, path, database};
}
const snapshot = directory => Object.fromEntries(fs.readdirSync(directory).sort().map(name =>
  [name, fs.readFileSync(join(directory, name)).toString('hex')]));

test('combined actual DB and WAL extent refuses before scratch copying or the SQLite inspector', async () => {
  const {scratch, path, database} = await fixture();
  const total = fs.statSync(path).size + fs.statSync(path+'-wal').size;
  const before = snapshot(scratch.path);
  let called = 0;
  try {
    assert.throws(() => inspectSqliteSnapshot(path, () => called++, {maxSourceBytes: total-1}),
      {code: 'SqliteSnapshotInspectionUnavailable'});
    assert.equal(called, 0);
    assert.deepEqual(snapshot(scratch.path), before);
    assert.equal(inspectSqliteSnapshot(path,
      copy => copy.prepare('SELECT value FROM original').get().value, {maxSourceBytes: total}), 'same-original');
    assert.deepEqual(snapshot(scratch.path), before);
  } finally { database.close(); }
  scratch.passed();
});

test('invalid copy ceilings refuse before attempting a physical source', () => {
  for (const maxSourceBytes of [0, -1, NaN, Infinity, 1.5]) {
    assert.throws(() => inspectSqliteSnapshot('/no-original-needed', () => assert.fail(), {maxSourceBytes}),
      {code: 'InvalidSqliteSnapshotInspectionConfiguration'});
  }
});

for (const mode of ['false', 'throw']) test('extent refusal retains actual source FD '+mode+' close and retries no reads', async () => {
  const {scratch, path, database} = await fixture();
  database.close();
  const open = fs.openSync, close = fs.closeSync, read = fs.readSync;
  let fd, allow = false, closes = 0, reads = 0, failure;
  const originalCause = Object.freeze(new Error('OriginalInspectionCloseRefusal'));
  fs.openSync = function(selected, ...args) {
    const value = Reflect.apply(open, fs, [selected, ...args]);
    if (selected === path) fd = value;
    return value;
  };
  fs.closeSync = function(value) {
    if (value === fd) {
      closes++;
      fs.closeSync = () => undefined; syncBuiltinESMExports();
      if (!allow) { if (mode === 'throw') throw originalCause; return false; }
    }
    return Reflect.apply(close, fs, [value]);
  };
  fs.readSync = function(...args) { reads++; return Reflect.apply(read, fs, args); };
  syncBuiltinESMExports();
  try {
    try { inspectSqliteSnapshot(path, () => assert.fail(), {maxSourceBytes: 1}); }
    catch (cause) { failure = cause; }
    assert.equal(failure.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure.primaryFailure.code, 'SqliteSnapshotInspectionUnavailable');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(failure.cleanupHandle.retry().pending, true);
    allow = true;
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(closes, 3); assert.equal(reads, 0);
  } finally {
    allow = true; if (failure?.cleanupHandle.status().pending) failure.cleanupHandle.retry();
    fs.openSync = open; fs.closeSync = close; fs.readSync = read; syncBuiltinESMExports();
  }
  scratch.passed();
});
