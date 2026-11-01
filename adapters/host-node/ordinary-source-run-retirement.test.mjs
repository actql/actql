import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import resourceRuntime from './ordinary-node-resource-runtime.cjs';

async function fixture() {
  const originals = {};
  const request = {};
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator() {}, request() {return request;},
    requirements() {return {planningWork: 10, attempts: 10, holdings: 10,
      transferBytes: 100n, retainedBytes: 100n, executionBytes: 100n};},
  }, false);
  const receipt = view.beforeSourceSnapshot('program', {}, {});
  const body = {};
  view.bindSourceSnapshot(receipt, body);
  view.bindSourceRequest(receipt, body, request);
  return {view, receipt, body, request};
}

test('ordinary source Run retirement waits for actual stop after producer completion', async () => {
  const f = await fixture();
  const prepared = {};
  const original = f.view.prepareRun(prepared);
  const ports = resourceRuntime.prepareOriginalManagedRunPorts(original, prepared);
  f.view.finishSourceProducer(f.receipt, 'returned');
  // The producer request must remain valid for the live Run currentness check.
  assert.equal(ports.status(1), 0);
  assert.throws(() => f.view.retireRun(prepared, original), /CleanupPending/);
  assert.equal(ports.cancelUnpublished(), 0);
  f.view.retireRun(prepared, original);
  f.view.retireRun(prepared, original);
  assert.throws(() => f.view.retireRun(prepared, {}), /ForeignInstalledSourceProducer/);
  assert.throws(() => f.view.prepareRun(prepared), /ForeignInstalledModelPreparation/);
  assert.deepEqual(await f.view.close(), {pending: false});
});

test('ordinary source Run retirement preserves nonzero usage and sibling Run custody', async () => {
  const f = await fixture();
  const first = {}, second = {};
  const a = f.view.prepareRun(first), b = f.view.prepareRun(second);
  const portsA = resourceRuntime.prepareOriginalManagedRunPorts(a, first);
  const portsB = resourceRuntime.prepareOriginalManagedRunPorts(b, second);
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.equal(portsA.status(0), 0);
  assert.equal(portsA.report(0, 0, 0, 0n, 0n, 0n, 1n, 0n, 0n, 1n, 0, 0, 0), 0);
  assert.equal(portsA.status(2), -42);
  assert.throws(() => f.view.retireRun(first, a), /CleanupPending/);
  assert.equal(portsA.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 1n, 0, 0, 0), 0);
  assert.equal(portsA.status(2), 0);
  f.view.retireRun(first, a);
  assert.equal(portsB.status(1), 0);
  assert.throws(() => f.view.retireRun(second, a), /ForeignInstalledSourceProducer/);
  assert.equal(portsB.cancelUnpublished(), 0);
  f.view.retireRun(second, b);
  assert.deepEqual(await f.view.close(), {pending: false});
});

test('ordinary source Run retirement before producer finish keeps receipt lifecycle original', async () => {
  const f = await fixture();
  const prepared = {};
  const original = f.view.prepareRun(prepared);
  const ports = resourceRuntime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(ports.cancelUnpublished(), 0);
  f.view.retireRun(prepared, original);
  assert.throws(() => f.view.retireRun({}, original), /ForeignInstalledSourceProducer/);
  f.view.finishSourceProducer(f.receipt, 'returned');
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.throws(() => f.view.bindSourceRequest(f.receipt, f.body, {}), /ForeignInstalledSourceProducer/);
  assert.deepEqual(await f.view.close(), {pending: false});
});

test('ordinary installation close retains admitted Run until original stop and then retires references', async () => {
  const f = await fixture();
  const prepared = {};
  const original = f.view.prepareRun(prepared);
  const ports = resourceRuntime.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.deepEqual(await f.view.close(), {pending: true});
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
  assert.equal(ports.status(2), 0);
  assert.deepEqual(await f.view.close(), {pending: false});
  assert.deepEqual(await f.view.close(), {pending: false});
});
