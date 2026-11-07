import assert from 'node:assert/strict';
import test from 'node:test';
import runtime from './ordinary-node-resource-runtime.cjs';

const requirements = Object.freeze({planningWork: 100, attempts: 10, holdings: 10,
  transferBytes: 1000n, retainedBytes: 2000n, executionBytes: 3000n});
const zero = ports => ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0);

test('same Run reports pending and live counters without refunding spent attempts at retirement', () => {
  const prepared = {}, original = runtime.retainOrdinaryManagedRun(prepared, requirements, () => {}, () => false);
  const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), -42);
  assert.equal(ports.report(0, 1, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 10, 1, 0), -42);
  assert.equal(ports.report(0, 1, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 1, 1, 0), 0);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.report(0, 1, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
  assert.equal(ports.status(2), 0);
});

test('ordinary Run keeps same-prepared identity, purpose and managed limits without a preload', () => {
  const prepared = {}, original = runtime.retainOrdinaryManagedRun(prepared, requirements, () => {}, () => false);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, {}), null);
  assert.equal(runtime.prepareOriginalLocalMockModelRunPorts(original, prepared), null);
  const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  assert.equal(ports.limit(4), 2000n);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.status(2), -42); // No invented zero-usage observation.
  assert.equal(ports.report(101, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), -42);
  assert.equal(zero(ports), 0);
  assert.equal(ports.status(2), 0);
  assert.equal(ports.status(1), 1);
});

test('ordinary Run keeps child cleanup separate from logical zero usage and current refusal', () => {
  let childPending = true, current = true;
  const prepared = {}, original = runtime.retainOrdinaryManagedRun(prepared, requirements,
    () => {if (!current) throw new Error('original-current');}, () => childPending);
  const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  assert.equal(zero(ports), 0);
  current = false;
  assert.equal(ports.status(1), 1);
  current = true;
  assert.equal(ports.status(1), 1); // Current failure does not revive the Run.
  assert.equal(ports.status(2), -42);
  childPending = false;
  assert.equal(ports.status(2), 0); // Cleanup does not require currentness.
});

test('ordinary Mock Model uses its separate purpose and the same original unpublished cleanup', () => {
  const prepared = {}, original = runtime.retainOrdinaryManagedRun(prepared, requirements,
    () => {}, () => false, 'local-mock-model');
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  const ports = runtime.prepareOriginalLocalMockModelRunPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.cancelUnpublished(), 0);
  assert.equal(ports.cancelUnpublished(), 0);
  assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
});

test('ordinary Content ports keep their original purpose and physical-child cleanup', () => {
  const prepared = {};
  let childPending = true;
  const original = runtime.retainOrdinaryManagedRun(prepared, requirements,
    () => {}, () => childPending, 'local-content');
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  assert.equal(runtime.prepareOriginalLocalMockModelRunPorts(original, prepared), null);
  assert.equal(runtime.prepareOriginalLocalContentRunPorts(original, {}), null);
  const ports = runtime.prepareOriginalLocalContentRunPorts(original, prepared);
  assert.equal(runtime.prepareOriginalLocalContentRunPorts(original, prepared), null);
  assert.equal(ports.status(0), 0);
  assert.equal(zero(ports), 0);
  assert.equal(ports.status(2), -42);
  childPending = false;
  assert.equal(ports.status(2), 0);
  assert.equal(runtime.prepareOriginalLocalContentRunPorts(original, prepared), null);
});

// One imported callback can retire this same original reentrantly. Its
// successful return is not a current proof after that transition.
test('ordinary retained current calls once and refuses same-callback terminal reentry', () => {
  for (const terminal of ['unpublished', 'admitted-stop']) {
    const prepared = {}, q = {planningWork: 3, attempts: 2, holdings: 2,
      transferBytes: 20n, retainedBytes: 20n, executionBytes: 20n};
    let calls = 0, stop;
    const original = runtime.retainOrdinaryManagedRun(prepared, q, () => {calls++; stop?.();}, () => false);
    const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
    const before = calls;
    assert.equal(ports.status(1), 0); assert.equal(calls, before + 1);
    if (terminal === 'admitted-stop') {
      assert.equal(ports.status(0), 0);
      assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
    }
    stop = () => assert.equal(terminal === 'unpublished' ? ports.cancelUnpublished() : ports.status(2), 0);
    const beforeStop = calls;
    assert.equal(ports.status(1), 1);
    assert.equal(calls, beforeStop + 1);
    assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
    assert.equal(ports.status(1), 1); assert.equal(calls, beforeStop + 1);
  }
});

// These are separate original-admission boundaries, not a reused proof from
// retainedPorts.current. Original cleanup still owns the same terminal duty.
test('ordinary original assertion cannot return current after its callback retires that same Run', () => {
  for (const terminal of ['unpublished', 'admitted-stop']) {
    const prepared = {}; let stop, calls = 0;
    const original = runtime.retainOrdinaryManagedRun(prepared, requirements, () => {calls++; stop?.();}, () => false);
    const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
    if (terminal === 'admitted-stop') {assert.equal(ports.status(0), 0); assert.equal(zero(ports), 0);}
    const before = calls; runtime.assertOrdinaryManagedRunCurrent(original, prepared);
    assert.equal(calls, before + 1);
    stop = () => assert.equal(terminal === 'unpublished' ? ports.cancelUnpublished() : ports.status(2), 0);
    const beforeStop = calls;
    assert.throws(() => runtime.assertOrdinaryManagedRunCurrent(original, prepared),
      {code: 'NodeManagedRunAdmissionUnavailable'});
    assert.equal(calls, beforeStop + 1);
    assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
  }
});

test('ordinary original port selection refuses when same-callback reentry already took the sole ports', () => {
  const prepared = {}; let selecting = false, inner, calls = 0, original;
  original = runtime.retainOrdinaryManagedRun(prepared, requirements, () => {
    calls++;
    if (!selecting) return;
    selecting = false; inner = runtime.prepareOriginalManagedRunPorts(original, prepared);
    assert.notEqual(inner, null);
  }, () => false);
  selecting = true; const before = calls;
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  assert.equal(calls, before + 2); // Two distinct calls; neither repeats current.
  assert.notEqual(inner, null);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  assert.equal(calls, before + 2);
  assert.equal(inner.cancelUnpublished(), 0);
  assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
});

test('ordinary preparation keeps charged transfer history without pinning completed cleanup', () => {
  const prepared = {};
  let childPending = true;
  const original = runtime.retainOrdinaryManagedRun(prepared, requirements,
    () => {}, () => childPending, 'local-preparation');
  const ports = runtime.prepareOriginalLocalPreparationPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  // These are the original completed Run's cumulative counters. Stop must not
  // require a second, fabricated zero-history report to retire that same Run.
  const report = ({transferred = 7n, uncertain = 19n, reservedTransfer = 0n,
    held = 0n, retention = 0n, execution = 0n, holdings = 0,
    attempts = 0, reservations = 0, delegations = 0} = {}) =>
    ports.report(1, 1, holdings, transferred, uncertain, reservedTransfer,
      held, retention, execution, 21n, attempts, reservations, delegations);
  assert.equal(report(), 0);
  assert.equal(ports.status(2), -42); // Physical child cleanup is still required.
  childPending = false;
  for (const pending of [{reservedTransfer: 1n}, {held: 1n}, {retention: 1n},
    {execution: 1n}, {holdings: 1}, {attempts: 1}, {reservations: 1}, {delegations: 1}]) {
    assert.equal(report(pending), 0);
    assert.equal(ports.status(2), -42);
  }
  assert.equal(report(), 0);
  // Keeping historical uncertainty out of stop's live projection must never
  // remove it from the existing transfer quota or accept a replacement report.
  assert.equal(report({transferred: 982n}), -42);
  assert.equal(report({uncertain: 994n}), -42);
  assert.equal(report({reservedTransfer: 975n}), -42);
  assert.equal(ports.status(2), 0);
  assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
  assert.equal(ports.status(1), 1);
  assert.equal(report(), -42);
  assert.equal(runtime.prepareOriginalLocalPreparationPorts(original, prepared), null);
});
