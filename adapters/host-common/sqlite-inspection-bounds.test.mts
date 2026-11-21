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
const snapshot = (directory: string) => Object.fromEntries(fs.readdirSync(directory).sort().map(name =>
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
      copy => copy.prepare('SELECT value FROM original').get()!.value, {maxSourceBytes: total}), 'same-original');
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

for (const mode of ['false', 'throw']) test('extent refusal retains actual source FD '+mode+' close Unknown without retrying the numeric FD', async () => {
  const {scratch, path, database} = await fixture();
  database.close();
  const open = fs.openSync, close = fs.closeSync, read = fs.readSync;
  let fd: number | undefined, closes = 0, replacementCloses = 0, reads = 0,
    failure: {code: string; primaryFailure: {code: string}; cleanupHandle: {
    status(): {pending: boolean; errors: readonly {error: Error}[]};
    retry(): {pending: boolean; errors: readonly {error: Error}[]};
  }} | undefined;
  const originalCause = Object.freeze(new Error('OriginalInspectionCloseRefusal'));
  fs.openSync = function(selected, ...args) {
    const value = Reflect.apply(open, fs, [selected, ...args]);
    if (selected === path) fd = value;
    return value;
  };
  fs.closeSync = function(value) {
    if (value === fd) {
      closes++;
      fs.closeSync = replacement => {
        if (replacement === fd) { replacementCloses++; return; }
        return Reflect.apply(close, fs, [replacement]);
      };
      syncBuiltinESMExports();
      if (mode === 'throw') throw originalCause;
      return false;
    }
    return Reflect.apply(close, fs, [value]);
  };
  fs.readSync = function(...args: unknown[]) { reads++; return Reflect.apply(read, fs, args); } as typeof read;
  syncBuiltinESMExports();
  try {
    try { inspectSqliteSnapshot(path, () => assert.fail(), {maxSourceBytes: 1}); }
    catch (cause) { failure = cause as typeof failure; }
    assert.equal(failure!.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure!.primaryFailure.code, 'SqliteSnapshotInspectionUnavailable');
    const status = failure!.cleanupHandle.status();
    assert.equal(status.pending, true);
    const firstClose = status.errors[0].error;
    if (mode === 'throw') assert.equal(firstClose, originalCause);
    else assert.match(firstClose.message, /^SqliteInspectionFileCloseUnknown$/u);
    for (let attempt = 0; attempt < 2; attempt++) {
      const observed = failure!.cleanupHandle.retry();
      assert.equal(observed.pending, true);
      assert.equal(observed.errors[0]?.error, firstClose);
      assert(observed.errors.every(({error}) => error === firstClose));
    }
    assert.equal(closes, 1); assert.equal(replacementCloses, 0); assert.equal(reads, 0);
    assert.equal(fs.fstatSync(fd!).isFile(), true);
  } finally {
    fs.openSync = open; fs.closeSync = close; fs.readSync = read; syncBuiltinESMExports();
    // The injected closer left this fixture's FD open. Teardown is not a product close ACK.
    if (closes !== 0) Reflect.apply(close, fs, [fd]);
  }
  scratch.passed();
});
