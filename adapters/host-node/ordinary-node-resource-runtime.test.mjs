import assert from 'node:assert/strict';
import test from 'node:test';
import runtime from './ordinary-node-resource-runtime.cjs';

const requirements = Object.freeze({planningWork: 100, attempts: 10, holdings: 10,
  transferBytes: 1000n, retainedBytes: 2000n, executionBytes: 3000n});
const zero = ports => ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n);

test('ordinary Run keeps same-prepared identity, purpose and managed limits without a preload', () => {
  const prepared = {}, original = runtime.retainOrdinaryManagedRun(prepared, requirements, () => {}, () => false);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, {}), null);
  assert.equal(runtime.prepareOriginalLocalMockModelRunPorts(original, prepared), null);
  const ports = runtime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, prepared), null);
  assert.equal(ports.limit(4), 2000n);
  assert.equal(ports.status(0), 0);
  assert.equal(ports.status(2), -42); // No invented zero-usage observation.
  assert.equal(ports.report(101, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), -42);
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
