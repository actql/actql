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
