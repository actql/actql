import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';

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
