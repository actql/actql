import assert from 'node:assert/strict';
import test from 'node:test';
import {retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';

test('completed opening cleanup preserves the original immutable failure', () => {
  const original = Object.freeze(new Error('OriginalOpeningFailure'));
  let retired = 0;
  assert.equal(retainInstalledHostRuntimeFailure(original, () => retired++), original);
  assert.equal(retired, 1);
});

test('actual pending child overrides a false failure flag without an initial retry', async () => {
  let pending = true, retries = 0, retired = 0;
  const child = {status: () => ({pending}), retry() {retries++;}};
  const original = Object.freeze(Object.assign(new Error('OpeningFailed'), {
    cleanupPending: false, cleanupHandle: child,
  }));
  const failure = retainInstalledHostRuntimeFailure(original, () => retired++);
  assert.equal(failure.primaryFailure, original);
  assert.equal(retries, 0);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['initialization', 'runtime']);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(retired, 0);
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retries, 1, 'a confirmed child is not retried');
  assert.equal(retired, 1);
});

test('missing cleanup owner cannot become a successful runtime retirement', async () => {
  let retired = 0;
  const original = Object.freeze(Object.assign(new Error('OpeningFailed'), {cleanupPending: true}));
  const failure = retainInstalledHostRuntimeFailure(original, () => retired++);
  await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
  assert.equal(failure.cleanupError.message, 'InstalledHostInitializationCleanupOwnerMissing');
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(retired, 0);
});

test('same original child methods and receiver remain captured across retry', async () => {
  let statusReads = 0, retryReads = 0, pending = true, retired = 0, retries = 0;
  let release;
  const settled = new Promise(resolve => {release = resolve;});
  const child = {
    get status() {statusReads++; return function() {
      assert.equal(this, child); return {pending};
    };},
    get retry() {retryReads++; return async function() {
      assert.equal(this, child); retries++; await settled; pending = false;
    };},
  };
  const original = Object.freeze(Object.assign(new Error('OpeningFailed'), {cleanupHandle: child}));
  const failure = retainInstalledHostRuntimeFailure(original, () => retired++);
  Object.defineProperties(child, {
    status: {value() {throw new Error('ReplacementStatus');}},
    retry: {value() {throw new Error('ReplacementRetry');}},
  });
  const first = failure.cleanupHandle.retry();
  assert.equal(first, failure.cleanupHandle.retry());
  release();
  assert.equal((await first).pending, false);
  assert.deepEqual({statusReads, retryReads, retries, retired}, {
    statusReads: 1, retryReads: 1, retries: 1, retired: 1,
  });
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retired, 1);
});

test('undefined and malformed child observations retain pending responsibility', async () => {
  let observed, retired = 0;
  const child = {status: () => observed, retry() {}};
  const failure = retainInstalledHostRuntimeFailure({cleanupHandle: child}, () => retired++);
  for (observed of [undefined, {}, {pending: null}, {pending: 0}, {pending: 'false'}]) {
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(retired, 0);
  }
  observed = {pending: false};
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retired, 1);
});

test('failed child retry retains primary facts and only its latest local failure', async () => {
  let pending = true, retired = 0, sequence = 0;
  const child = {status: () => ({pending}), retry() {throw new Error(`Close${++sequence}`);}};
  const primary = Object.freeze(new Error('OriginalPrimary'));
  const failure = retainInstalledHostRuntimeFailure({primaryFailure: primary, cleanupHandle: child}, () => retired++);
  for (let n = 1; n <= 3; n++) {
    await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupHandle.status().errors.length, 1);
    assert.equal(failure.cleanupError.message, `Close${n}`);
    assert.equal(retired, 0);
  }
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(sequence, 3);
  assert.equal(retired, 1);
});

test('runtime retirement failure does not repeat confirmed child cleanup', async () => {
  let pending = true, retries = 0, retireCalls = 0;
  const primary = Object.freeze(new Error('OriginalPrimary'));
  const child = {status: () => ({pending}), retry() {retries++; pending = false;}};
  const failure = retainInstalledHostRuntimeFailure({primaryFailure: primary, cleanupHandle: child}, () => {
    if (++retireCalls === 1) throw new Error('RuntimeRetirementFailed');
  });
  await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
  assert.equal(failure.primaryFailure, primary);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['runtime']);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual({retries, retireCalls}, {retries: 1, retireCalls: 2});
});
