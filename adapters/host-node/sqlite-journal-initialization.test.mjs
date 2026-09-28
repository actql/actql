import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as checkpointRuntime from
  '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js';
import {openSqliteTransferJournal} from
  '../site-node/sqlite-transfer-journal.mjs';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';

const openers = [
  ['coordinator-journal', root => openSqliteCoordinatorDispatchJournal(root,
    {coordinatorAuthority: 'coordinator-a'})],
  ['transfer-journal', root => openSqliteTransferJournal(root,
    {destinationSiteKey: 'site-a', destinationSiteGeneration: 1})],
  ['checkpoint-journal', root => openSqliteCheckpointJournal(root,
    {runtime: checkpointRuntime, authorizeResolution() {},
      attestResolution() {}})],
];

for (const [owner, open] of openers) {
  test(`${owner} keeps COMMIT failure and retries initialization close`,
    async t => {
      const root = await mkdtemp(join(tmpdir(), 'actql-journal-init-'));
      t.after(() => rm(root, {recursive: true, force: true}));
      const exec = DatabaseSync.prototype.exec;
      const close = DatabaseSync.prototype.close;
      const primary = new Error(`${owner}CommitFailure`);
      const cleanup = new Error(`${owner}CloseFailure`);
      let commits = 0;
      let closes = 0;
      DatabaseSync.prototype.exec = function(sql) {
        const result = exec.call(this, sql);
        if (sql === 'COMMIT' && ++commits === 1) throw primary;
        return result;
      };
      DatabaseSync.prototype.close = function() {
        if (++closes === 1) throw cleanup;
        return close.call(this);
      };
      let failure;
      try {
        assert.throws(() => open(root), error => {
          failure = error;
          assert.equal(error.code,
            'SqliteJournalInitializationCleanupPending');
          assert.equal(error.primaryFailure.cause, primary);
          assert.equal(error.primaryFailure.outcome, 'unknown');
          assert.equal(error.cleanupPending, true);
          assert.deepEqual(error.cleanupHandle.status().owners, [owner]);
          assert.equal(error.cleanupErrors[0].error, cleanup);
          return true;
        });
        assert.equal(failure.cleanupHandle.retry().pending, false);
        assert.equal(failure.cleanupPending, false);
        assert.equal(failure.cleanupHandle.retry().pending, false);
        assert.equal(closes, 2);
      } finally {
        DatabaseSync.prototype.exec = exec;
        DatabaseSync.prototype.close = close;
      }
      const reopened = open(root);
      reopened.close();
    });
}

test('Host initialization retains the transaction cause and cleanup owner',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-host-init-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const exec = DatabaseSync.prototype.exec;
    const close = DatabaseSync.prototype.close;
    const primary = new Error('CheckpointCommitFailure');
    const cleanup = new Error('CheckpointCloseFailure');
    let closes = 0;
    DatabaseSync.prototype.exec = function(sql) {
      const result = exec.call(this, sql);
      if (sql === 'COMMIT') throw primary;
      return result;
    };
    DatabaseSync.prototype.close = function() {
      if (++closes <= 2) throw cleanup;
      return close.call(this);
    };
    let inner;
    try {
      assert.throws(() => openSqliteCheckpointJournal(root,
        {runtime: checkpointRuntime, authorizeResolution() {},
          attestResolution() {}}), error => {
        inner = error;
        return true;
      });
      const outer = await retainInstalledHostInitializationFailure(inner, {});
      assert.equal(outer.code, 'InstalledHostInitializationFailed');
      assert.equal(outer.primaryFailure.cause, primary);
      assert.equal(outer.cleanupPending, true);
      assert.equal(outer.cleanupErrors[0].error, cleanup);
      assert.deepEqual(outer.cleanupHandle.status().owners,
        ['initialization']);
      assert.equal((await outer.cleanupHandle.retry()).pending, false);
      assert.equal(outer.cleanupPending, false);
      assert.equal(closes, 3);
    } finally {
      DatabaseSync.prototype.exec = exec;
      DatabaseSync.prototype.close = close;
    }
    const reopened = openSqliteCheckpointJournal(root,
      {runtime: checkpointRuntime, authorizeResolution() {},
        attestResolution() {}});
    reopened.close();
  });
