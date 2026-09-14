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
