import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {generateKeyPairSync} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

test('request journal fences admission but retries a failed physical close',
  async t => {
    const root = fileURLToPath(new URL('../../_build/host-init/', import.meta.url));
    await mkdir(root, {recursive: true});
    const directory = await mkdtemp(join(root, 'request-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const journal = openClientRequestJournal(directory);
    const close = DatabaseSync.prototype.close;
    const failure = new Error('RequestJournalCloseFailure');
    let calls = 0;
    DatabaseSync.prototype.close = function () {
      if (++calls === 1) throw failure;
      return close.call(this);
    };
    t.after(() => { DatabaseSync.prototype.close = close; });
    assert.throws(() => journal.close(), error => error === failure);
    assert.throws(() => journal.lookupRunDefinition({}, {}, {}),
      {code: 'ClientRequestJournalClosed'});
    journal.close();
    assert.equal(calls, 2);
    journal.close();
    assert.equal(calls, 2);
  });

test('Checkpoint installation retains its journal before returning an owner',
  async t => {
    const {installRemoteCheckpoints} = await import('./client-checkpoints.mjs');
    const {runtimeCore} = await import('../host-common/runtime-core.mjs');
    const moon = await import('../../_build/js/release/build/' +
      'connectors_builtin_node/connectors_builtin_node.js');
    const root = fileURLToPath(new URL('../../_build/host-init/', import.meta.url));
    await mkdir(root, {recursive: true});
    const directory = await mkdtemp(join(root, 'checkpoint-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    const primary = new Error('ReadResumeInstallationFailure');
    const closeFailure = new Error('CheckpointJournalCloseFailure');
    const close = DatabaseSync.prototype.close;
    let closeCalls = 0;
    DatabaseSync.prototype.close = function () {
      if (++closeCalls === 1) throw closeFailure;
      return close.call(this);
    };
    t.after(() => { DatabaseSync.prototype.close = close; });
    let reads = 0;
    const cid = `sha256:${'a'.repeat(64)}`;
    let failure;
    await assert.rejects(installRemoteCheckpoints({root: directory,
      tenantId: 'tenant', authorityScopeCid: cid, ownerPrincipal: 'owner',
      siteKey: 'site', realizationKey: 'values', environmentCid: cid,
      contractControl: runtimeCore(moon).publicationControl,
      authorization: {
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: 'reviewer', publicKey: keys.publicKey.export({
            type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host-key', privateKey: keys.privateKey.export({
          type: 'pkcs8', format: 'pem'})},
      },
      source: {get context() {
        if (++reads === 2) throw primary;
        return undefined;
      }},
    }), error => {
      failure = error;
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.cause, primary);
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupErrors[0].error, closeFailure);
      return true;
    });
    assert.equal(closeCalls, 1);
    const outer = await retainInstalledHostInitializationFailure(failure, {});
    assert.equal(outer.primaryFailure, primary);
    assert.equal(outer.cleanupPending, false);
    assert.equal(closeCalls, 2);
  });

test('installed Host exposes initialization cause and releases its Store lock',
  async t => {
    const {openInstalledRemoteHttpHost} = await import('./embedded-local.mjs');
    const root = fileURLToPath(new URL('../../_build/host-init/', import.meta.url));
    await mkdir(root, {recursive: true});
    const directory = await mkdtemp(join(root, 'failure-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    await assert.rejects(openInstalledRemoteHttpHost({directory,
      authenticate: () => 'owner', authorization: null}), error => {
      assert.equal(error.code, 'InstalledHostInitializationFailed');
      assert.equal(error.cause.code, 'InvalidRemoteHostAuthorization');
      assert.equal(error.primaryFailure, error.cause);
      assert.equal(error.cleanupPending, false);
      assert.deepEqual(error.cleanupHandle.status().owners, []);
      return true;
    });
    const host = await openInstalledRemoteHttpHost({directory,
      authenticate: () => 'owner'});
    await host.close();
  });

test('initialization does not discard an unresolved primary cleanup owner',
  async () => {
    let closed = 0;
    const primary = Object.assign(new Error('PendingInitialization'),
      {cleanupPending: true});
    const failure = await retainInstalledHostInitializationFailure(primary,
      {journal: {close() { closed++; }}});
    assert.equal(failure.cleanupPending, true);
    assert.equal(closed, 0);
    await failure.cleanupHandle.retry();
    assert.equal(closed, 0);
    assert.equal(failure.cleanupPending, true);
  });

test('initialization keeps its primary error and retries independent closes',
  async () => {
    const primary = new Error('InitializationFailure');
    const journalFailure = new Error('JournalCloseFailure');
    const storeFailure = new Error('StoreCloseFailure');
    let retry = false;
    const calls = [];
    const failure = await retainInstalledHostInitializationFailure(primary, {
      journal: {close() {
        calls.push('journal');
        if (!retry) throw journalFailure;
      }},
      store: {async close() {
        calls.push('store');
        if (!retry) throw storeFailure;
      }},
    });
    assert.equal(failure.cause, primary);
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(calls, ['journal', 'store']);
    assert.deepEqual(failure.cleanupErrors.map(item => item.error),
      [journalFailure, storeFailure]);
    assert.equal(failure.cleanupPending, true);
    retry = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(failure.cleanupPending, false);
    await failure.cleanupHandle.retry();
    assert.deepEqual(calls, ['journal', 'store', 'journal', 'store']);
  });

test('initialization retains journals and Store until active owners settle',
  async () => {
    const calls = [];
    let stopped = false;
    let drained = false;
    const failure = await retainInstalledHostInitializationFailure(
      new Error('CheckpointStartFailure'), {
        checkpoints: {
          async stop() {
            calls.push('stop');
            if (!stopped) throw new Error('StopPending');
          },
          async close() { calls.push('checkpoints'); },
        },
        dispatchOwner: {async drain() {
          calls.push('drain');
          if (!drained) throw new Error('DispatchCleanupPending');
        }},
        journal: {close() { calls.push('journal'); }},
        store: {async close() { calls.push('store'); }},
      });
    assert.deepEqual(calls, ['stop']);
    stopped = true;
    await failure.cleanupHandle.retry();
    assert.deepEqual(calls, ['stop', 'stop', 'drain']);
    assert.equal(failure.cleanupPending, true);
    drained = true;
    const first = failure.cleanupHandle.retry();
    const second = failure.cleanupHandle.retry();
    assert.equal(first, second);
    await Promise.all([first, second]);
    assert.deepEqual(calls,
      ['stop', 'stop', 'drain', 'drain', 'checkpoints', 'journal', 'store']);
    assert.equal(failure.cleanupPending, false);
  });
