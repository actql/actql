import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedCase, retainedMatrix, workloads} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';
import {equivalentExecutionCapacity} from
  '../bench/equivalent-capacity.mjs';

test('equivalent capacity admits one DB and simultaneous bounded scratch', () => {
  for (const fixture of retainedMatrix()) {
    const capacity = equivalentExecutionCapacity(fixture);
    assert.equal(capacity.databaseBytes,
      BigInt(fixture.limits.executionMemoryBytes) / 2n);
    assert(capacity.scratchBytes > 0n);
    assert.equal(capacity.admittedBytes,
      capacity.databaseBytes + capacity.scratchBytes);
    assert(capacity.admittedBytes <= capacity.limitBytes);
    assert.equal(capacity.maxChunkRows, 128);
    assert.equal(capacity.maxSqlBytes, fixture.limits.batchBytes);
    assert.equal(Object.isFrozen(capacity), true);
  }
});

test('equivalent capacity rejects malformed and insufficient envelopes', () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  assert.throws(() => equivalentExecutionCapacity({
    ...fixture,
    limits: {...fixture.limits, executionMemoryBytes: 1},
  }), /InvalidEquivalentCapacityInput/);
  assert.throws(() => equivalentExecutionCapacity({
    ...fixture,
    limits: {
      ...fixture.limits,
      executionMemoryBytes: 1024,
      batchBytes: 1024,
    },
  }), /EquivalentExecutionCapacityExceeded/);
});
