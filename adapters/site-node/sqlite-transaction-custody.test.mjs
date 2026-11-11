import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';
import {openSqliteTransferStoreJournal} from './sqlite-transfer-store-journal.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';

const openers = [
  {owner: 'dispatch-journal', prefix: 'RemoteJournal',
    file: 'dispatch-journal.sqlite3', table: 'journal_metadata',
    version: 'actql-remote-site-journal/0.6',
    open: root => openSqliteDispatchJournal(root, {
      siteKey: 'site-a', siteGeneration: 1, runtimeRevision: 'runtime-a',
    })},
  {owner: 'transfer-store-journal', prefix: 'RemoteTransferStoreJournal',
    file: 'transfer-store-journal.sqlite3', table: 'journal_metadata',
    version: 'actql-transfer-store-journal/0.1',
    open: root => openSqliteTransferStoreJournal(root)},
  {owner: 'runtime-bundle-store', prefix: 'RemoteBundleStore',
    file: 'bundles.sqlite3', table: 'metadata',
    version: 'actql-runtime-bundle-store/0.1',
    open: root => openRuntimeBundleStore(root, {
      bundleAuthorities: new Map([['authority-a', new Map([
        ['key-a', generateKeyPairSync('ed25519').publicKey],
      ])]]), targetTriple: 'aarch64-apple-darwin',
    })},
];

// Each fault affects this test process's real SQLite connection. Failed
// initialization files stay available for diagnosis; no Run is replayed.
for (const {owner, prefix, file, table, version, open} of openers) {
  test(`${owner} retains a lost real COMMIT reply without ROLLBACK or replay`,
    async () => {
      const root = await mkdtemp(join(tmpdir(), 'actql-site-commit-reply-'));
      const exec = DatabaseSync.prototype.exec;
      const primary = new Error('CommitReplyLost');
      let commits = 0, rollbacks = 0;
      DatabaseSync.prototype.exec = function(sql) {
        if (sql === 'ROLLBACK') rollbacks++;
        const result = exec.call(this, sql);
        if (sql === 'COMMIT' && ++commits === 1) throw primary;
        return result;
      };
      try {
        await assert.rejects(async () => open(root), error => {
          assert.equal(error.code, `${prefix}CommitOutcomeUnknown`);
          assert.equal(error.cause, primary);
          assert.equal(error.outcome, 'unknown');
          assert.equal(error.connectionUsable, true);
          return true;
        });
      } finally { DatabaseSync.prototype.exec = exec; }
      assert.equal(commits, 1);
      assert.equal(rollbacks, 0);
      const observed = new DatabaseSync(join(root, file), {readOnly: true});
      try {
        assert.equal(observed.prepare(
          `SELECT value FROM ${table} WHERE key = 'schema_version'`,
        ).get().value, version);
      } finally { observed.close(); }
    });

  test(`${owner} rolls back an active failed COMMIT but keeps outcome unknown`,
    async () => {
      const root = await mkdtemp(join(tmpdir(), 'actql-site-commit-active-'));
      const exec = DatabaseSync.prototype.exec;
      const primary = new Error('CommitNotAcknowledged');
      let commits = 0, rollbacks = 0;
      DatabaseSync.prototype.exec = function(sql) {
        if (sql === 'COMMIT') { commits++; throw primary; }
        if (sql === 'ROLLBACK') rollbacks++;
        return exec.call(this, sql);
      };
      try {
        await assert.rejects(async () => open(root), error => {
          assert.equal(error.code, `${prefix}CommitOutcomeUnknown`);
          assert.equal(error.cause, primary);
          assert.equal(error.outcome, 'unknown');
          assert.equal(error.connectionUsable, true);
          return true;
        });
      } finally { DatabaseSync.prototype.exec = exec; }
      assert.equal(commits, 1);
      assert.equal(rollbacks, 1);
      const observed = new DatabaseSync(join(root, file), {readOnly: true});
      try {
        assert.equal(observed.prepare(
          `SELECT value FROM ${table} WHERE key = 'schema_version'`,
        ).get(), undefined);
      } finally { observed.close(); }
    });

  test(`${owner} retains COMMIT and original failed-close custody separately`,
    async () => {
      const root = await mkdtemp(join(tmpdir(), 'actql-site-close-custody-'));
      const exec = DatabaseSync.prototype.exec, close = DatabaseSync.prototype.close;
      const primary = new Error('CommitReplyLost');
      const cleanup = new Error('OriginalClosePending');
      let commits = 0, closes = 0, failure;
      DatabaseSync.prototype.exec = function(sql) {
        const result = exec.call(this, sql);
        if (sql === 'COMMIT' && ++commits === 1) throw primary;
        return result;
      };
      DatabaseSync.prototype.close = function() {
        if (++closes === 1) throw cleanup;
        return close.call(this);
      };
      try {
        await assert.rejects(async () => open(root), error => {
          failure = error;
          assert.equal(error.code, 'SqliteJournalInitializationCleanupPending');
          assert.equal(error.primaryFailure.code, `${prefix}CommitOutcomeUnknown`);
          assert.equal(error.primaryFailure.cause, primary);
          assert.equal(error.primaryFailure.outcome, 'unknown');
          assert.equal(error.cleanupErrors[0].error, cleanup);
          assert.deepEqual(error.cleanupHandle.status().owners, [owner]);
          return true;
        });
        assert.equal(failure.cleanupHandle.retry().pending, false);
        assert.equal(failure.cleanupHandle.retry().pending, false);
        assert.equal(closes, 2);
        assert.equal(commits, 1);
      } finally {
        DatabaseSync.prototype.exec = exec;
        DatabaseSync.prototype.close = close;
      }
    });

  test(`${owner} keeps a post-schema prepare failure and its original database`,
    async () => {
      const root = await mkdtemp(join(tmpdir(), 'actql-site-prepare-custody-'));
      const exec = DatabaseSync.prototype.exec, prepare = DatabaseSync.prototype.prepare;
      const close = DatabaseSync.prototype.close;
      const primary = new Error('OriginalStatementPreparationFailed');
      const cleanup = new Error('OriginalClosePending');
      let committed = false, injected = false, closes = 0, failure;
      DatabaseSync.prototype.exec = function(sql) {
        const result = exec.call(this, sql);
        if (sql === 'COMMIT') committed = true;
        return result;
      };
      DatabaseSync.prototype.prepare = function(sql) {
        // Schema metadata may still need a second transaction. Select only
        // the first retained operation statement after initialization.
        if (committed && !injected && /SELECT .*FROM (?:dispatches|store_uses|bundles)/su.test(sql)) {
          injected = true;
          throw primary;
        }
        return prepare.call(this, sql);
      };
      DatabaseSync.prototype.close = function() {
        if (++closes === 1) throw cleanup;
        return close.call(this);
      };
      try {
        await assert.rejects(async () => open(root), error => {
          failure = error;
          assert.equal(error.code, 'SqliteJournalInitializationCleanupPending');
          assert.equal(error.primaryFailure, primary);
          assert.equal(error.cleanupErrors[0].error, cleanup);
          assert.deepEqual(error.cleanupHandle.status().owners, [owner]);
          return true;
        });
        assert.equal(injected, true);
        assert.equal(failure.cleanupHandle.retry().pending, false);
        assert.equal(closes, 2);
      } finally {
        DatabaseSync.prototype.exec = exec;
        DatabaseSync.prototype.prepare = prepare;
        DatabaseSync.prototype.close = close;
      }
    });
}
