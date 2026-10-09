import assert from 'node:assert/strict';
import test from 'node:test';
import {closeManagedFixtureExecution} from './managed-fixture-cleanup.mjs';

function fixture(reason = new Error('LocalManagedOutputCleanupPending')) {
  let released = false, closes = 0, cleanups = 0;
  const handle = {status: () => ({pending: !released}),
    retry() { assert.fail('The fixture consumer must use the execution recovery owner'); }};
  const inner = Object.assign(new Error('ManagedExecutionFailed', {cause: reason}),
    {code: 'ManagedExecutionFailed', primaryFailure: reason,
      cleanupErrors: [], cleanupPending: true, cleanupHandle: handle});
  const failure = Object.assign(new Error('ManagedInputReleaseFailed', {cause: inner}),
    {code: 'ManagedInputReleaseFailed', primaryFailure: inner,
      cleanupErrors: [inner], cleanupPending: true, cleanupHandle: handle});
  const execution = {completed: [{task: 1}],
    usage: () => ({attempts: 4n, reservedExecutionBytes: released ? 0n : 128n}),
    async close() { closes++; throw failure; },
    async cleanup() {
      cleanups++;
      if (cleanups === 4) { released = true; inner.cleanupPending = false; }
      return released;
    }, cleanupPending: () => !released};
  return {execution, failure, counts: () => ({closes, cleanups})};
}

test('fixture cleanup retains its first bounded-pending error and uses only explicit recovery', async () => {
  const f = fixture();
  const result = await closeManagedFixtureExecution(f.execution, 60000);
  assert.equal(result.firstCloseFailure, f.failure);
  assert.equal(result.cleanupAttempts, 4);
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 4});
  assert.equal(f.failure.cause.primaryFailure.message, 'LocalManagedOutputCleanupPending');
});

test('fixture cleanup rejects a physical exception hidden under the same outer classification', async () => {
  const f = fixture(new Error('PhysicalReleaseUnavailable'));
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.equal(error.errors[0], f.failure);
    assert.equal(error.errors[1].code, 'ERR_ASSERTION');
    return true;
  });
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 0});
});

test('fixture cleanup retains the original pending failure when explicit recovery rejects', async () => {
  const f = fixture(), recoveryFailure = new Error('RecoveryUnavailable');
  f.execution.cleanup = async () => { throw recoveryFailure; };
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.deepEqual(error.errors, [f.failure, recoveryFailure]);
    return true;
  });
  assert.equal(f.execution.cleanupPending(), true);
  assert.equal(f.counts().closes, 1);
});
