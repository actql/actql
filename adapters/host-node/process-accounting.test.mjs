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


test('usage preserves reserved and live custody counts without admitting them as limit fields', () => {
  const usage = {...emptyProcessUsage(), reserved_attempts: 2,
    live_reservations: 3, live_delegations: 1};
  assert.deepEqual(decodeProcessUsage(encodeProcessUsage(usage)), usage);
  for (const field of ['reserved_attempts', 'live_reservations', 'live_delegations']) {
    const missing = {...usage}; delete missing[field];
    assert.throws(() => encodeProcessUsage(missing), /InvalidProcessAccounting/);
    for (const value of [-1, 0.5, 2147483648, '1']) {
      assert.throws(() => encodeProcessUsage({...usage, [field]: value}), /InvalidProcessAccounting/);
    }
    assert.throws(() => snapshotProcessLimits({...limits(), [field]: 0}), /InvalidProcessAccounting/);
  }
});

test('IPC accounting reads only captured own data and never invokes a caller getter', () => {
  let reads = 0;
  const accessor = {...limits()};
  Object.defineProperty(accessor, 'attempts', {enumerable: true, get() { reads++; return 2; }});
  assert.throws(() => snapshotProcessLimits(accessor), /InvalidProcessAccounting/);
  assert.equal(reads, 0);
  let gets = 0;
  const original = limits();
  const supplied = new Proxy(original, {get() { gets++; throw Error('CallerGetMustNotRun'); }});
  assert.deepEqual(snapshotProcessLimits(supplied), original);
  assert.equal(gets, 0);
});

test('IPC accounting rejects every extra own field including Symbols and nonenumerable data', () => {
  const symbol = {...limits(), [Symbol('foreign authority')]: true};
  const hidden = {...limits()};
  Object.defineProperty(hidden, 'foreign', {value: true});
  for (const supplied of [symbol, hidden]) {
    assert.throws(() => snapshotProcessLimits(supplied), /InvalidProcessAccounting/);
  }
});
