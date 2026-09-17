import test from 'node:test';
import assert from 'node:assert/strict';
import {ownedHostFailure} from '../failure-envelope.mjs';

test('Host failure envelope preserves every falsy throwable', () => {
  for (const reason of [null, undefined, false, 0, '']) {
    const failure = ownedHostFailure(reason, 'ManagedStrategyFailed');
    assert.equal(failure.code, 'ManagedStrategyFailed');
    assert.equal(failure.primaryFailure, reason);
    assert.equal(failure.cause, reason);
    assert.deepEqual(failure.cleanupErrors, []);
  }
});

test('Host failure envelope never mutates a frozen failure', () => {
  const cleanup = Object.freeze({status: () => ({pending: true})});
  const reason = Object.freeze(Object.assign(new Error('original'), {
    code: 'Cancelled',
    cleanupPending: true,
    cleanupHandle: cleanup,
    cleanupErrors: Object.freeze([new Error('earlier cleanup')]),
  }));
  const failure = ownedHostFailure(reason, 'ManagedStrategyFailed');
  assert.notEqual(failure, reason);
  assert.equal(failure.code, 'Cancelled');
  assert.equal(failure.primaryFailure, reason);
  assert.equal(failure.cause, reason);
  assert.equal(failure.cleanupHandle, cleanup);
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cleanupErrors.length, 1);
});
