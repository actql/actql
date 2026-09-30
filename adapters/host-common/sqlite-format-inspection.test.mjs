import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, unlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';

const snapshot = root => Object.fromEntries(readdirSync(root).sort().map(name =>
  [name, readFileSync(join(root, name)).toString('hex')]));
const fixture = t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-format-inspection-test-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const path = join(root, 'journal.sqlite3');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode = WAL; CREATE TABLE metadata (value TEXT NOT NULL) STRICT');
  database.prepare('INSERT INTO metadata VALUES (?)').run('before-wal');
  database.close();
  return {root, path};
};

test('isolated SQLite format inspection reads uncheckpointed WAL without touching source', t => {
  const {root, path} = fixture(t);
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import {DatabaseSync} from 'node:sqlite';
    const database = new DatabaseSync(process.argv[1]);
    database.exec('PRAGMA wal_autocheckpoint = 0');
    database.prepare('UPDATE metadata SET value = ?').run('only-in-wal');
    process.exit(0);
  `, path], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(`${path}-wal`), true);
  unlinkSync(`${path}-shm`);
  const before = snapshot(root);
  assert.throws(() => inspectSqliteSnapshot(path, database => {
    assert.equal(database.prepare('SELECT value FROM metadata').get().value, 'only-in-wal');
    throw Object.assign(new Error('UnsupportedFormat'), {code: 'UnsupportedFormat'});
  }), {code: 'UnsupportedFormat'});
  assert.deepEqual(snapshot(root), before);
  assert.equal(inspectSqliteSnapshot(path, database =>
    database.prepare('SELECT value FROM metadata').get().value), 'only-in-wal');
  assert.deepEqual(snapshot(root), before);
});

test('format inspection refuses a source modified during the isolated read', t => {
  const {path} = fixture(t);
  assert.throws(() => inspectSqliteSnapshot(path, database => {
    assert.equal(database.prepare('SELECT value FROM metadata').get().value, 'before-wal');
    const writer = new DatabaseSync(path);
    try { writer.prepare('UPDATE metadata SET value = ?').run('changed'); }
    finally { writer.close(); }
  }), {code: 'UnknownSqliteJournalFormat'});
});

test('inspection refuses scratch inside the source root before creating any file', t => {
  const {root, path} = fixture(t);
  const before = snapshot(root);
  const previous = process.env.TMPDIR;
  process.env.TMPDIR = root;
  try {
    assert.throws(() => inspectSqliteSnapshot(path, () =>
      assert.fail('unsafe scratch must refuse before opening its copy')),
    {code: 'UnknownSqliteJournalFormat'});
    assert.deepEqual(snapshot(root), before);
  } finally {
    if (previous === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = previous;
  }
});

test('format failure and isolated close failure keep one retryable cleanup owner', t => {
  const {root, path} = fixture(t);
  const before = snapshot(root);
  const close = DatabaseSync.prototype.close;
  let attempts = 0;
  let inspections = 0;
  let isolated;
  let failure;
  DatabaseSync.prototype.close = function() {
    if (++attempts === 1) throw new Error('CLOSE_FAILED');
    return close.call(this);
  };
  try {
    try {
      inspectSqliteSnapshot(path, database => {
        inspections++;
        isolated = dirname(database.prepare('PRAGMA database_list').get().file);
        throw Object.assign(new Error('FORMAT_REFUSED'), {code: 'FORMAT_REFUSED'});
      });
      assert.fail('expected inspection refusal');
    } catch (error) { failure = error; }
    assert.equal(failure.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure.primaryFailure.code, 'FORMAT_REFUSED');
    assert.equal(failure.cleanupErrors[0].error.message, 'CLOSE_FAILED');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(existsSync(isolated), true);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(attempts, 2);
    assert.equal(inspections, 1);
    assert.equal(existsSync(isolated), false);
    assert.deepEqual(snapshot(root), before);
  } finally { DatabaseSync.prototype.close = close; }
});
