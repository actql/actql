import assert from 'node:assert/strict';
import test from 'node:test';
import runtime from './ordinary-node-resource-runtime.cjs';

test('publication currentness callback throws become stopping status without escaping Core latch', () => {
  const input = Object.freeze({});
  let fail = false;
  const original = runtime.retainOrdinaryManagedRun(input, {
    planningWork: 0, attempts: 0, holdings: 0,
    transferBytes: 0n, retainedBytes: 100n, executionBytes: 100n,
  }, () => { if (fail) throw new Error('currentness unavailable'); }, () => false, 'local-preparation');
  const ports = runtime.prepareOriginalLocalPreparationPorts(original, input);
  assert.equal(ports.status(0), 0);
  fail = true;
  assert.doesNotThrow(() => assert.equal(ports.status(1), 1));
  assert.equal(runtime.ordinaryManagedRunStatus(original).retiring, true);
  assert.equal(ports.status(1), 1);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);
  assert.equal(ports.status(2), 0);
  assert.equal(runtime.ordinaryManagedRunStatus(original).stopped, true);
});
