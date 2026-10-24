import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {beginManagedFailureProgress, recordManagedFailureExecutionSettled} from
  '../host-common/managed-failure.mjs';
import {closeCompletedLocalManagedOutput} from './managed-output-custody.mjs';

for (const result of ['released', 'pending', 'error']) {
  test(`completed Local output keeps original cleanup ownership: ${result}`, async () => {
    let release = result === 'released';
    let closed = false;
    let refreshes = 0;
    const primary = new Error('FixturePhysicalReleaseUnavailable');
    const operations = {
      close() { closed = true; },
      settle() { assert.fail('accepted completion cannot settle another execution'); },
      advance() { assert.fail('cleanup cannot advance Compute'); },
      cleanup_refresh() {
        assert.equal(closed, true);
        refreshes++;
        if (result === 'error' && !release) throw primary;
        return release;
      },
    };
    const progress = beginManagedFailureProgress(moon, true, false);
    recordManagedFailureExecutionSettled(progress);
    if (release) {
      closeCompletedLocalManagedOutput(operations, checked, progress);
      assert.equal(refreshes, 1);
      return;
    }
    let failure;
    assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
      progress), error => { failure = error; return error.cleanupPending === true; });
    const handle = failure.cleanupHandle;
    assert.equal(handle.status().pending, true);
    await handle.retry();
    assert.equal(handle.status().pending, true);
    if (result === 'error') assert.equal(failure.primaryFailure, primary);
    release = true;
    await handle.retry();
    assert.equal(handle.status().pending, false);
    assert.equal(failure.cleanupHandle, handle);
    const settled = refreshes;
    await handle.retry();
    assert.equal(refreshes, settled, 'release is not charged twice');
  });
}

test('completed Local output drains progressing finite scratch in the original retry', async () => {
  let remaining = 1024;
  let retired = 0n;
  let closes = 0;
  let yielded = false;
  const operations = {
    close() { closes++; },
    settle() { assert.fail('completed execution must not settle again'); },
    advance() { assert.fail('cleanup must not advance Compute'); },
    cleanup_refresh() {
      const slice = Math.min(64, remaining);
      remaining -= slice;
      retired += BigInt(slice);
      return remaining === 0;
    },
    cleanup_progress() { return retired; },
  };
  const progress = beginManagedFailureProgress(moon, true, false);
  recordManagedFailureExecutionSettled(progress);
  let failure;
  assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
    progress), error => { failure = error; return error.cleanupPending === true; });
  const handle = failure.cleanupHandle;
  setImmediate(() => { yielded = true; });
  const first = handle.retry();
  assert.equal(handle.retry(), first, 'concurrent callers share the original cleanup flight');
  await first;
  assert.equal(handle.status().pending, false);
  assert.equal(remaining, 0);
  assert.equal(yielded, true, 'bounded slices yield to the event loop');
  assert.equal(failure.cleanupHandle, handle);
  assert.equal(closes, 2, 'retry drives cleanup, not another close or Compute');
  const completed = retired;
  await handle.retry();
  assert.equal(retired, completed);
});

test('completed Local output stops automatic drain at a physical cleanup stall', async () => {
  let refreshes = 0;
  let released = false;
  const operations = {
    close() {},
    settle() { assert.fail('completed execution must not settle again'); },
    cleanup_refresh() { refreshes++; return released; },
    cleanup_progress() { return 64n; },
  };
  const progress = beginManagedFailureProgress(moon, true, false);
  recordManagedFailureExecutionSettled(progress);
  let failure;
  assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
    progress), error => { failure = error; return error.cleanupPending === true; });
  const handle = failure.cleanupHandle;
  const before = refreshes;
  await handle.retry();
  assert.equal(handle.status().pending, true);
  assert.ok(refreshes - before <= 2, 'an unchanged physical owner is not polled indefinitely');
  released = true;
  await handle.retry();
  assert.equal(handle.status().pending, false);
});

const {continueLocalManagedFailureCleanup} = await import('./managed-output-custody.mjs');
for (const mode of ['finite', 'blocked', 'stalled', 'error', 'blocked-after-yield']) {
  test(`failed Local finalization continues only original runnable cleanup: ${mode}`, async () => {
    let cursor = 0n, retries = 0, released = false, blocked = mode === 'blocked';
    const primary = Object.assign(new Error('OriginalFinalizationFailure'), {code: 'OriginalFinalizationFailure'});
    const failure = Object.assign(new Error('OwnedFailure', {cause: primary}), {
      primaryFailure: primary, cleanupPending: true,
      cleanupHandle: {
        status() { return {pending: !released, errors: []}; },
        async retry() {
          retries++;
          assert.equal(released, false);
          if (mode === 'error') return {pending: true, errors: [new Error('CleanupError')]};
          if (mode !== 'stalled') cursor += 64n;
          if (cursor >= 640n) released = true;
          failure.cleanupPending = !released;
          return {pending: !released, errors: []};
        },
      },
    });
    const handle = failure.cleanupHandle;
    const operations = {
      cleanup_local_continuation() { return blocked ? -1n : cursor; },
      advance() { assert.fail('cleanup must not repeat Compute'); },
      request_cancel() { assert.fail('cleanup must not replace cancellation authority'); },
    };
    let yielded = false;
    setTimeout(() => { yielded = true; if (mode === 'blocked-after-yield') blocked = true; }, 0);
    assert.equal(await continueLocalManagedFailureCleanup(failure, operations), failure);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(primary.code, 'OriginalFinalizationFailure');
    assert.equal(failure.cleanupHandle, handle);
    if (mode === 'finite') {
      assert.equal(retries, 10); assert.equal(released, true); assert.equal(yielded, true);
    } else {
      assert.equal(released, false);
      assert.ok(retries <= 1, 'blocked or non-progressing owner is not polled');
    }
  });
}

test('failure continuation shares one flight and retains reservation until release witness', async () => {
  let cursor = 0n, charged = true, retries = 0, cancellationRequested = false;
  const failure = {cleanupHandle: {
    status() { return {pending: charged, errors: []}; },
    async retry() {
      assert.equal(charged, true, 'no early reservation refund');
      retries++; cursor += 64n;
      if (cursor === 640n) charged = false;
      return {pending: charged, errors: []};
    },
  }};
  const operations = {cleanup_local_continuation: () => cursor};
  setTimeout(() => {cancellationRequested = true;}, 0);
  const first = continueLocalManagedFailureCleanup(failure, operations);
  assert.equal(continueLocalManagedFailureCleanup(failure, operations), first);
  await first;
  assert.equal(cancellationRequested, true, 'cancellation can run between cleanup slices');
  assert.equal(charged, false); assert.equal(retries, 10);
});
