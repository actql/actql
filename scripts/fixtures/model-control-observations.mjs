// Observation assertions only. No counters or quotes grant capacity.
import assert from 'node:assert/strict';

export function assertModelRequestSnapshotRefusal(observations, receipt, memory) {
  assert.equal(receipt.outcome, undefined); assert.equal(receipt.input, undefined);
  assert.equal(receipt.attempt, undefined);
  assert.equal(observations.length, 1);
  const original = observations[0];
  const fields = ['requiredRetentionBytes', 'requiredExecutionBytes',
    'availableRetentionBytes', 'availableExecutionBytes'];
  assert.deepEqual(Object.keys(original).sort(), ['phase', 'dimension', ...fields].sort());
  assert.equal(original.phase, 'request_snapshot');
  assert(['retention', 'execution'].includes(original.dimension));
  const [requiredRetention, requiredExecution, availableRetention, availableExecution] = fields.map(name => {
    const value = original[name]; assert.equal(typeof value, 'string');
    assert(/^(?:0|[1-9][0-9]{0,18})$/u.test(value));
    const amount = BigInt(value); assert(amount <= 9223372036854775807n); return amount;
  });
  assert(availableRetention <= BigInt(memory.retainedBytes));
  assert(availableExecution <= BigInt(memory.executionBytes));
  assert(original.dimension === 'retention' ? requiredRetention > availableRetention
    : requiredRetention <= availableRetention && requiredExecution > availableExecution);
  return {...original, verified: true, scope: 'request_snapshot', classification: 'resource_limit'};
}
