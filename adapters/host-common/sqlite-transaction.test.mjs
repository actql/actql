import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createSqliteTransaction} from './sqlite-transaction.mjs';

test('SQLite automatic rollback is a known body failure', () => {
  const database = new DatabaseSync(':memory:');
  try {
    database.exec('CREATE TABLE items (value TEXT UNIQUE)');
    database.exec(`CREATE TRIGGER reject_item BEFORE INSERT ON items
      BEGIN SELECT RAISE(ROLLBACK, 'rejected'); END`);
    const transaction = createSqliteTransaction(database, 'TestJournal');
    assert.throws(() => transaction.run(() =>
      database.exec("INSERT INTO items VALUES ('x')")),
    error => error.message === 'rejected');
    assert.equal(database.isTransaction, false);
    assert.equal(transaction.connectionUsable, true);
    assert.equal(transaction.run(() =>
      database.prepare('SELECT count(*) AS count FROM items').get().count), 0);
  } finally { database.close(); }
});

test('failed COMMIT stays unknown even when rollback restores connection',
  () => {
    const database = new DatabaseSync(':memory:',
      {enableForeignKeyConstraints: true});
    try {
      database.exec('CREATE TABLE parent (id INTEGER PRIMARY KEY)');
      database.exec(`CREATE TABLE child (parent_id INTEGER,
        FOREIGN KEY (parent_id) REFERENCES parent(id)
        DEFERRABLE INITIALLY DEFERRED)`);
      const transaction = createSqliteTransaction(database, 'TestJournal');
      assert.throws(() => transaction.run(() =>
        database.exec('INSERT INTO child VALUES (7)')), error => {
        assert.equal(error.code, 'TestJournalCommitOutcomeUnknown');
        assert.equal(error.operation, 'commit');
        assert.equal(error.outcome, 'unknown');
        assert.equal(error.connectionUsable, true);
        assert.ok(error.cause instanceof Error);
        return true;
      });
      assert.equal(database.isTransaction, false);
      assert.equal(transaction.run(() =>
        database.prepare('SELECT count(*) AS count FROM child').get().count), 0);
    } finally { database.close(); }
  });

test('COMMIT and ROLLBACK failures preserve both causes and fence writes',
  () => {
    const database = new DatabaseSync(':memory:',
      {enableForeignKeyConstraints: true});
    try {
      database.exec('CREATE TABLE parent (id INTEGER PRIMARY KEY)');
      database.exec(`CREATE TABLE child (parent_id INTEGER,
        FOREIGN KEY (parent_id) REFERENCES parent(id)
        DEFERRABLE INITIALLY DEFERRED)`);
      const rollbackCause = new Error('rollback transport failed');
      const connection = {
        exec(sql) {
          if (sql === 'ROLLBACK') throw rollbackCause;
          return database.exec(sql);
        },
        get isTransaction() { return database.isTransaction; },
      };
      const transaction = createSqliteTransaction(connection, 'TestJournal');
      assert.throws(() => transaction.run(() =>
        database.exec('INSERT INTO child VALUES (7)')), error => {
        assert.equal(error.code, 'TestJournalCommitOutcomeUnknown');
        assert.ok(error.cause instanceof Error);
        assert.equal(error.rollbackCause, rollbackCause);
        assert.equal(error.connectionUsable, false);
        return true;
      });
      assert.equal(database.isTransaction, true);
      assert.throws(() => transaction.run(() =>
        database.exec('INSERT INTO parent VALUES (7)')),
      {code: 'TestJournalConnectionUnusable'});
    } finally { database.close(); }
  });

test('failed state inspection is retained and blocks new operations', () => {
  const database = new DatabaseSync(':memory:');
  const stateCause = new Error('driver state unavailable');
  const connection = {
    exec: sql => database.exec(sql),
    get isTransaction() { throw stateCause; },
  };
  const transaction = createSqliteTransaction(connection, 'TestJournal');
  try {
    assert.throws(() => transaction.run(() => {
      throw new Error('body failed');
    }), error => {
      assert.equal(error.cause.message, 'body failed');
      assert.equal(error.stateCause, stateCause);
      assert.equal(error.outcome, 'unknown');
      return true;
    });
    assert.throws(() => transaction.run(() => {}),
      {code: 'TestJournalConnectionUnusable'});
  } finally { database.close(); }
});

test('primary, rollback, and state-inspection failures remain separate',
  () => {
    const database = new DatabaseSync(':memory:');
    const primary = new Error('body failed');
    const rollbackCause = new Error('rollback failed');
    const stateCause = new Error('state failed');
    let inspections = 0;
    const connection = {
      exec(sql) {
        if (sql === 'ROLLBACK') throw rollbackCause;
        return database.exec(sql);
      },
      get isTransaction() {
        inspections++;
        if (inspections === 2) throw stateCause;
        return database.isTransaction;
      },
    };
    const transaction = createSqliteTransaction(connection, 'TestJournal');
    try {
      assert.throws(() => transaction.run(() => { throw primary; }), error => {
        assert.equal(error.cause, primary);
        assert.equal(error.rollbackCause, rollbackCause);
        assert.equal(error.stateCause, stateCause);
        assert.equal(error.outcome, 'unknown');
        return true;
      });
      assert.throws(() => transaction.run(() => {}),
        {code: 'TestJournalConnectionUnusable'});
    } finally { database.close(); }
  });

// An actual physical COMMIT may complete before its caller loses the reply.
// The retained row is the same original attempt, not permission to send again.
test('lost physical COMMIT reply retains Unknown and the exact original row after reopen', t => {
  const root = mkdtempSync(join(tmpdir(), 'credential-if-commit-'));
  const path = join(root, 'original.sqlite');
  let database = new DatabaseSync(path), complete = false;
  try {
    database.exec('PRAGMA synchronous = FULL');
    database.exec('CREATE TABLE attempts (id TEXT PRIMARY KEY, request TEXT NOT NULL) STRICT');
    const primary = new Error('OriginalCommitReplyLost');
    let commits = 0;
    const connection = {
      exec(sql) {
        database.exec(sql);
        if (sql === 'COMMIT') { commits++; throw primary; }
      },
      get isTransaction() { return database.isTransaction; },
    };
    const transaction = createSqliteTransaction(connection, 'OriginalJournal');
    assert.throws(() => transaction.run(() => {
      database.prepare('INSERT INTO attempts VALUES (?, ?)').run('original-attempt', 'exact-original-request');
    }), error => {
      assert.equal(error.code, 'OriginalJournalCommitOutcomeUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.cause, primary);
      assert.equal(error.connectionUsable, true);
      return true;
    });
    assert.equal(commits, 1);
    database.close();
    database = new DatabaseSync(path);
    const expected = [{id: 'original-attempt', request: 'exact-original-request'}];
    for (let observation = 0; observation < 2; observation++) {
      assert.deepEqual(database.prepare('SELECT id, request FROM attempts').all().map(row => ({...row})), expected);
    }
    assert.equal(commits, 1, 'same-attempt observation performs no new write');
    complete = true;
  } finally {
    database.close();
    if (complete) rmSync(root, {recursive: true, force: true});
    else t.diagnostic(`Unconfirmed original physical fixture retained: ${root}`);
  }
});
