import test from 'node:test';
import assert from 'node:assert/strict';
import { computePhysicalCapacity } from '../physical-capacity.mjs';
import { provisionComputeDatabase, validateLimits } from '../session.mjs';

const limits = { memoryBytes: 1000, maxTransportBytes: 10, maxCells: 2,
  maxColumns: 3, maxParameters: 4, maxSqlBytes: 5, maxRows: 2, threads: 1 };

test('physical capacity keeps DB, transport scratch and consumed transfer distinct', () => {
  const cap = computePhysicalCapacity(limits);
  assert.deepEqual(cap, {
    databaseBytes: 1000n, scratchBytes: 2404n, executionBytes: 3404n,
    transferBytes: 10n,
  });
  assert.equal(Object.isFrozen(cap), true);
  assert.equal(computePhysicalCapacity({ ...limits, maxCells: 3 }).scratchBytes, 2660n);
  // Same payload sizes do not allow discounts for unimplemented buffer sharing.
  assert.equal(cap.executionBytes + cap.executionBytes, 6808n);
});

test('capacity rejects invalid or overflowing envelopes before reservation', () => {
  for (const value of [-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => computePhysicalCapacity({ ...limits, maxCells: value }), { code: 'InvalidLimits' });
  }
  assert.throws(() => computePhysicalCapacity({ ...limits, memoryBytes: 0 }), { code: 'InvalidLimits' });
  // Arithmetic stays integer-exact even beyond Number's exact summation range.
  assert.equal(computePhysicalCapacity({ ...limits, maxTransportBytes: Number.MAX_SAFE_INTEGER }).transferBytes,
    9007199254740991n);
});

test('bounded transport capacity is independent of cumulative rows and bytes', () => {
  const config = {...limits, maxRows: 10000, maxCells: 10000, maxTransportBytes: 1000000,
    maxChunkRows: 16, maxChunkBytes: 1024};
  const cap = computePhysicalCapacity(config);
  // 16*3 delivered cells, 2048*3 raw SDK vector cells, 3 fields and 4 parameters.
  assert.equal(cap.scratchBytes, 1024n * 32n + (48n + 6144n + 7n) * 256n + 20n);
  const larger = computePhysicalCapacity({...config, maxRows: 1000000, maxCells: 1000000,
    maxTransportBytes: 100000000});
  assert.equal(larger.scratchBytes, cap.scratchBytes);
  assert.equal(larger.transferBytes, 100000000n);
  assert.equal(computePhysicalCapacity({...config, maxChunkBytes: 1025}).scratchBytes, cap.scratchBytes + 32n);
  // Neither bound alone selects the smaller physical representation policy.
  const whole = computePhysicalCapacity({...config, maxChunkRows: undefined, maxChunkBytes: undefined});
  assert.equal(computePhysicalCapacity({...config, maxChunkBytes: undefined}).scratchBytes, whole.scratchBytes);
  assert.equal(computePhysicalCapacity({...config, maxChunkRows: undefined}).scratchBytes, whole.scratchBytes);
});

test('provider preflight freezes all transport settings before any start or settlement', async () => {
  const source = { ...limits, cancelWaitMs: 0 };
  const fixed = validateLimits(source);
  source.threads = 0;
  assert.equal(fixed.threads, 1);
  assert.equal(Object.isFrozen(fixed), true);
  const events = [];
  for (const invalid of [{ threads: 0 }, { maxRows: -1 }, { cancelWaitMs: -1 }]) {
    await assert.rejects(provisionComputeDatabase({ ...limits, ...invalid }, {
      started() { events.push('started'); },
      settled(value) { events.push(value); },
    }), { code: 'InvalidLimits' });
  }
  assert.deepEqual(events, []);
});
