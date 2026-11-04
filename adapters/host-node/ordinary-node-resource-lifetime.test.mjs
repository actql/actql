import test from 'node:test';
import assert from 'node:assert/strict';
import resources from './ordinary-node-resource-runtime.cjs';

function fixture() {
  const prepared = {};
  const calls = {current: 0, pending: 0};
  let pending = false;
  let failCurrent = false;
  const original = resources.retainOrdinaryManagedRun(prepared, {
    planningWork: 100, attempts: 100, holdings: 100,
    transferBytes: 100n, retainedBytes: 100n, executionBytes: 100n,
  }, () => { calls.current++; if (failCurrent) throw new Error('not current'); },
  () => { calls.pending++; return pending; });
  return {prepared, original, calls, setPending(value) {pending = value;},
    failCurrent() {failCurrent = true;}};
}

test('ordinary resource unpublished cleanup keeps pending duties and stops callbacks only on success', () => {
  const f = fixture();
  assert.equal(resources.prepareOriginalManagedRunPorts(f.original, {}), null);
  const ports = resources.prepareOriginalManagedRunPorts(f.original, f.prepared);
  assert.ok(ports);
  assert.equal(resources.prepareOriginalManagedRunPorts(f.original, f.prepared), null);
  f.setPending(true);
  assert.equal(ports.cancelUnpublished(), -42);
  assert.equal(ports.status(1), 0);
  f.setPending(false);
  assert.equal(ports.cancelUnpublished(), 0);
  const calls = {...f.calls};
  assert.equal(ports.cancelUnpublished(), 0);
  assert.equal(ports.status(1), 1);
  assert.equal(ports.status(0), -42);
  assert.equal(ports.status(2), -42);
  assert.deepEqual(f.calls, calls);
  assert.throws(() => resources.assertOrdinaryManagedRunCurrent(f.original, f.prepared));
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

test('ordinary resource published cleanup requires zero live usage and no pending children', () => {
  const f = fixture();
  const ports = resources.prepareOriginalManagedRunPorts(f.original, f.prepared);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 1n, 0n, 0n, 1n, 0, 0, 0), 0);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 1n, 0, 0, 0), 0);
  f.setPending(true);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.status(1), 0);
  f.setPending(false);
  assert.equal(ports.status(2), 0);
  const calls = {...f.calls};
  assert.equal(ports.status(2), -42);
  assert.equal(ports.cancelUnpublished(), -42);
  assert.equal(ports.status(1), 1);
  assert.deepEqual(f.calls, calls);
});

test('ordinary resource failed currentness preserves pending cleanup and never reopens admission', () => {
  const f = fixture();
  const ports = resources.prepareOriginalManagedRunPorts(f.original, f.prepared);
  f.failCurrent();
  assert.equal(ports.status(1), 1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).retiring, true);
  f.setPending(true);
  assert.equal(ports.cancelUnpublished(), -42);
  f.setPending(false);
  assert.equal(ports.cancelUnpublished(), 0);
  assert.equal(ports.status(0), -42);
});

test('ordinary resource weak original receipt never admits equal-shaped or sibling identities', () => {
  const first = fixture(), sibling = fixture();
  assert.doesNotThrow(() => resources.assertOrdinaryManagedRunCurrent(first.original, first.prepared));
  assert.throws(() => resources.assertOrdinaryManagedRunCurrent(first.original, {...first.prepared}),
    {code: 'NodeManagedRunAdmissionUnavailable'});
  assert.throws(() => resources.assertOrdinaryManagedRunCurrent(first.original, sibling.prepared),
    {code: 'NodeManagedRunAdmissionUnavailable'});
  assert.equal(resources.prepareOriginalManagedRunPorts(first.original, sibling.prepared), null);
  assert.equal(resources.prepareOriginalLocalMockModelRunPorts(first.original, first.prepared), null);
  const ports = resources.prepareOriginalManagedRunPorts(first.original, first.prepared);
  assert.ok(ports);
  assert.equal(ports.cancelUnpublished(), 0);
  assert.equal(resources.prepareOriginalManagedRunPorts(first.original, first.prepared), null);
  assert.throws(() => resources.assertOrdinaryManagedRunCurrent(first.original, first.prepared),
    {code: 'NodeManagedRunAdmissionUnavailable'});
});

test('preparation original has a separate once-only supplier and preserves live debit until cleanup', () => {
  const input = {}, original = resources.retainOrdinaryManagedRun(input, {
    planningWork: 10, attempts: 10, holdings: 10,
    transferBytes: 100n, retainedBytes: 100n, executionBytes: 100n,
  }, () => {}, () => false, 'local-preparation');
  assert.equal(resources.prepareOriginalManagedRunPorts(original, input), null);
  assert.equal(resources.prepareOriginalLocalPreparationPorts(original, {}), null);
  const ports = resources.prepareOriginalLocalPreparationPorts(original, input);
  assert.ok(ports);
  assert.equal(resources.prepareOriginalLocalPreparationPorts(original, input), null);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.status(0), -42);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 30n, 0n, 30n, 0, 1, 0), 0);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 30n, 0, 0, 0), 0);
  assert.equal(ports.status(2), 0);
  assert.equal(resources.prepareOriginalLocalPreparationPorts(original, input), null);
});
