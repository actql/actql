import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {runInstalledStrategy} from './strategy.mjs';
import {createInProcessExecutionSite, executionSiteStatus,
  prepareExecutionSitePolicy} from './execution-sites.mjs';

// The task driver is a protocol fixture; Site operations, holdings, close and
// cleanup progress use the real installed MoonBit authority, not the JS control
// fixture. This is lifecycle boundary evidence, not a query execution receipt.
async function retained(close, controlOverride = {}) {
  const setup = {}, registration = {}, material = {};
  let next = 0, complete = false;
  const originalControl = runtimeCore(moon).siteControl;
  const site = createInProcessExecutionSite({key: 'action-boundary', generation: 1,
    runtimeRevision: 'action-boundary/1'});
  const core = {
    siteControl: {...originalControl, ...controlOverride},
    count: () => 2,
    next: () => next++ === 0 ? {index: 1} : undefined,
    task: task => task.index,
    taskCapacity: () => [12n, 0n],
    registration: () => registration,
    completed: () => complete,
    finished: () => complete,
    stop() {}, closeOutputs() {},
    output: () => material,
    usage: () => ({}), explain: () => ({}),
  };
  const report = await runInstalledStrategy({
    setup,
    runtime: {core, sitePolicy: prepareExecutionSitePolicy({sites: [site]}),
      contributions: [{registration, run() {
        complete = true;
        return {close};
      }}]},
  });
  if (controlOverride.hostTaskSuccessAction === undefined) {
    assert.equal(report.status, 'host-tasks-completed');
  }
  return {report, status: () => executionSiteStatus(site)};
}

test('real Common holding releases once after synchronous physical close', async () => {
  let closes = 0;
  const f = await retained(() => { closes++; return 'closed'; });
  assert.equal(f.report.status, 'host-tasks-completed');
  assert.equal(f.status().heldBytes, 12n);
  assert.equal(f.report.close(), undefined);
  f.report.close();
  assert.equal(closes, 1);
  assert.equal(f.status().heldBytes, 0n);
  assert.equal(f.report.cleanupPending(), false);
});

test('real Common holding remains while asynchronous physical close is pending', async () => {
  let done, closes = 0;
  const wait = new Promise(resolve => { done = resolve; });
  const f = await retained(() => { closes++; return wait; });
  const closing = f.report.close();
  assert.equal(f.report.close(), closing);
  assert.equal(f.status().heldBytes, 12n);
  assert.equal(f.report.cleanupPending(), true);
  done();
  await closing;
  assert.equal(closes, 1);
  assert.equal(f.status().heldBytes, 0n);
  assert.equal(await f.report.cleanup(), true);
});

for (const asynchronous of [false, true]) {
  test(`real Common failed ${asynchronous ? 'async' : 'sync'} close retains cleanup until ACK`, async () => {
    let pending = true, closes = 0, retries = 0;
    const cleanupHandle = {status: () => ({pending}), retry() { retries++; }};
    const failure = Object.assign(new Error('physical-close-failed'), {
      cleanupPending: true, cleanupHandle,
    });
    const f = await retained(() => {
      closes++;
      if (asynchronous) return Promise.reject(failure);
      throw failure;
    });
    if (asynchronous) await assert.rejects(f.report.close(), error => error === failure);
    else assert.throws(() => f.report.close(), error => error === failure);
    assert.equal(f.status().heldBytes, 12n);
    assert.equal(await f.report.cleanup(), false);
    assert.equal(f.status().heldBytes, 12n);
    pending = false; // Only the original physical authority confirms release.
    assert.equal(await f.report.cleanup(), true);
    assert.equal(f.status().heldBytes, 0n);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
  });
}

test('failed close without recovery authority never becomes physical release', async () => {
  let closes = 0;
  const f = await retained(() => { closes++; throw undefined; });
  assert.throws(() => f.report.close(), error => error === undefined);
  assert.equal(await f.report.cleanup(), false);
  assert.equal(f.report.cleanupPending(), true);
  assert.equal(f.status().heldBytes, 12n);
  f.report.close();
  assert.equal(closes, 1);
});

test('unknown Common holding action refuses before physical close or release', async () => {
  let corrupt = false, closes = 0, releases = 0;
  const control = runtimeCore(moon).siteControl;
  const f = await retained(() => { closes++; }, {
    retainedHoldingAction: progress => corrupt ? 999 : control.retainedHoldingAction(progress),
    releaseHolding: holding => { releases++; return control.releaseHolding(holding); },
  });
  corrupt = true;
  assert.throws(() => f.report.close(), {code: 'InvalidExecutionSiteHoldingAction'});
  assert.equal(closes, 0);
  assert.equal(releases, 0);
  assert.equal(f.report.cleanupPending(), true);
  assert.equal(f.status().heldBytes, 12n);
});

test('unknown Common task-success action is refused without a success observation', async () => {
  const f = await retained(() => {}, {hostTaskSuccessAction: () => 999});
  assert.equal(f.report.status, 'host-tasks-failed');
  assert.equal(f.report.failure.code, 'InvalidExecutionSiteHostTaskSuccessAction');
  assert.deepEqual(f.report.completed, []);
  f.report.close();
});
