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
