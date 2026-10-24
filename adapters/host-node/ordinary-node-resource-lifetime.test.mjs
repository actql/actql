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
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 1n, 0n, 0n, 1n), 0);
  assert.equal(ports.status(2), -42);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 1n), 0);
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
