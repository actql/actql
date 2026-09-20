import test from 'node:test';
import assert from 'node:assert/strict';
import {settleObligationRun} from '../bench/obligation-settlement.mjs';

test('all cleanup actions run and retain execution plus cleanup failures', async () => {
  const primary = Error('execution failed'), connection = Error('connection failed');
  const store = Error('holding remains'), visited = [];
  await assert.rejects(settleObligationRun(primary, [
    ['connection-close', () => { visited.push('connection'); throw connection; }],
    ['instance-close', () => { visited.push('instance'); }],
    ['store-revoke', () => { visited.push('revoke'); }],
    ['store-cleanup', async () => { visited.push('cleanup'); throw store; }],
  ]), error => {
    assert(error instanceof AggregateError);
    assert.equal(error.errors[0], primary);
    assert.equal(error.errors[1].cause, connection);
    assert.equal(error.errors[2].cause, store);
    return true;
  });
  assert.deepEqual(visited, ['connection', 'instance', 'revoke', 'cleanup']);
});

test('cleanup failure cannot produce a successful sample; clean failure preserves its cause', async () => {
  await assert.rejects(settleObligationRun(undefined, [
    ['rollback', () => { throw Error('rollback failed'); }],
  ]), /ObligationRunCleanupUnconfirmed/);
  const primary = Error('cancelled');
  await assert.rejects(settleObligationRun(primary, [['close', () => {}]]), error => error === primary);
  await settleObligationRun(undefined, [['close', () => {}]]);
});
