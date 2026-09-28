import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  './sqlite-transaction.mjs';

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

test('initialization retries post-close durability without closing twice',
  () => {
    const primary = new Error('prepare failed');
    const syncFailure = new Error('directory sync failed');
    let closes = 0;
    let syncs = 0;
    let failure;
    assert.throws(() => throwSqliteInitializationFailure({
      close() { closes++; },
    }, primary, 'test-journal', () => {
      if (++syncs === 1) throw syncFailure;
    }), error => {
      failure = error;
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.cleanupErrors[0].error, syncFailure);
      assert.equal(error.cleanupPending, true);
      return true;
    });
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(closes, 1);
    assert.equal(syncs, 2);
  });
