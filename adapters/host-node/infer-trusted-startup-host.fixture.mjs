import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {issueInferTrustedRuntimeView, associateInferTrustedStartupView} from './infer-trusted-runtime-view.mjs';

// Actual selected startup, installed Host, SQLite initialization and cleanup.
// Empty Model registration: no Run, Core scope, Model permission or send.
const phase = process.argv[2];
if (!['open-close', 'schema', 'prepare'].includes(phase)) throw new Error('Exact Host fixture phase required');
const directory = await mkdtemp(join(tmpdir(), 'actql-a-selected-startup-host-'));
let host;
let registrations = 0;
let fault;
const options = {directory, authenticate: () => 'owner', registerModelProviders() {
  registrations++;
  return [];
}};
try {
  host = await openInstalledRemoteHttpHost(options);
  // The real Host has associated its startup original. A later private fake
  // supplier cannot become the first supplier or replace that original.
  const foreign = {host: {}, supplier() {}, installation: {}, generation: {},
    runtime: process, moduleLifetime: import.meta, transport() {}, target: 'foreign'};
  assert.throws(() => associateInferTrustedStartupView(issueInferTrustedRuntimeView(foreign), foreign),
    error => error.code === 'InferTrustedStartupChanged');
  await host.close();
  await host.close();
  host = undefined;
  if (phase !== 'open-close') {
    const originalExec = DatabaseSync.prototype.exec;
    const originalPrepare = DatabaseSync.prototype.prepare;
    const originalClose = DatabaseSync.prototype.close;
    const databases = new Set();
    const primary = new Error(`SelectedStartup${phase}Failure`);
    const closeFailure = new Error('SelectedStartupJournalCloseFailure');
    const calls = {schema: 0, prepare: 0, close: 0};
    DatabaseSync.prototype.exec = function(sql) {
      const value = originalExec.call(this, sql);
      if (sql.includes('CREATE TABLE IF NOT EXISTS client_requests')) {
        databases.add(this);
        calls.schema++;
        if (phase === 'schema') throw primary;
      }
      return value;
    };
    DatabaseSync.prototype.prepare = function(sql) {
      if (databases.has(this)) {
        calls.prepare++;
        if (phase === 'prepare') throw primary;
      }
      return originalPrepare.call(this, sql);
    };
    DatabaseSync.prototype.close = function() {
      if (databases.has(this) && ++calls.close <= 2) throw closeFailure;
      return originalClose.call(this);
    };
    fault = {restore() {
      DatabaseSync.prototype.exec = originalExec;
      DatabaseSync.prototype.prepare = originalPrepare;
      DatabaseSync.prototype.close = originalClose;
    }, closeRemaining() {
      for (const db of databases) if (db.isOpen) originalClose.call(db);
    }};
    let failure;
    await assert.rejects(openInstalledRemoteHttpHost(options), error => {
      failure = error;
      assert.equal(error.code, 'InstalledHostInitializationFailed');
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.cleanupPending, true);
      assert.ok(error.cleanupErrors.some(item => item.error === closeFailure));
      return true;
    });
    assert.equal(calls.close, 2);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(calls.close, 3, 'same successful physical close is not repeated');
    assert.equal(databases.size, 1);
    for (const db of databases) assert.equal(db.isOpen, false);
    fault.restore();
    fault = undefined;
  }
  host = await openInstalledRemoteHttpHost(options);
  await host.close();
  await host.close();
  host = undefined;
  assert.equal(registrations, phase === 'open-close' ? 2 : 3);
  console.log(JSON.stringify({phase, registrations, checked: true,
    realHost: true, realSqlite: true, providerCalls: 0, realCoreScopes: 0, publicE2E: 0}));
} finally {
  fault?.restore();
  fault?.closeRemaining();
  if (host !== undefined) await host.close();
  // Only this new, fully stopped fixture namespace; no previous Run/DB/raw.
  await rm(directory, {recursive: true, force: true});
}
