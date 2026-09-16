import test from 'node:test';
import assert from 'node:assert/strict';
import {snapshotProcessLimits, encodeProcessLimits, decodeProcessLimits,
  encodeProcessUsage, decodeProcessUsage, emptyProcessUsage} from './process-accounting.mjs';

const limits = () => ({planning_work: 1, attempts: 2, holdings: 3,
  transfer_bytes: 4n, retained_bytes: 5n, execution_bytes: 6n});

test('private accounting snapshots exact bounded primitives without narrowing Int64 values', () => {
  const supplied = {...limits(), transfer_bytes: 9223372036854775807n};
  const snapshot = snapshotProcessLimits(supplied);
  supplied.attempts = 999;
  assert.equal(snapshot.attempts, 2);
  assert(Object.isFrozen(snapshot));
  assert.deepEqual(decodeProcessLimits(encodeProcessLimits(snapshot)), snapshot);
  const usage = {...emptyProcessUsage(), transferred_bytes: 9223372036854775807n};
  assert.deepEqual(decodeProcessUsage(encodeProcessUsage(usage)), usage);
});

test('accounting rejects ambiguous encodings extra authority fields and numeric overflow', () => {
  for (const transfer_bytes of ['00', '-1', '1e3', '1.0', '9223372036854775808', 4, null]) {
    assert.throws(() => decodeProcessLimits({...encodeProcessLimits(limits()), transfer_bytes}), /InvalidProcessAccounting/);
  }
  for (const attempts of [-1, 0.5, Infinity, NaN, 2147483648, '2']) {
    assert.throws(() => snapshotProcessLimits({...limits(), attempts}), /InvalidProcessAccounting/);
  }
  assert.throws(() => snapshotProcessLimits({...limits(), verifier: () => true}), /InvalidProcessAccounting/);
  assert.throws(() => decodeProcessUsage({...encodeProcessUsage(emptyProcessUsage()), owner: 'another-run'}), /InvalidProcessAccounting/);
  assert.throws(() => encodeProcessUsage({...emptyProcessUsage(), held_bytes: -1n}), /InvalidProcessAccounting/);
});
