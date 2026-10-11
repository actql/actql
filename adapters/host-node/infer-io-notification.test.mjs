import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {createInferIoNotification, claimInferIoNotification} from './infer-io-notification.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';

test('physical notification coalesces before registration without carrying an ACK', async () => {
  const notification = createInferIoNotification();
  const port = claimInferIoNotification(notification);
  for (let index = 0; index < 10; index++) assert.equal(notification.notify(), true);
  const first = port.arm();
  assert.equal(await first.promise, undefined);
  assert.throws(() => port.arm(), /InferIoWaitAlreadyOwned/);
  first.dispose();
  const second = port.arm();
  let completed = false;
  second.promise.then(() => { completed = true; });
  await turn();
  assert.equal(completed, false, 'ten notifications do not create ten queued waits');
  notification.notify();
  await second.promise;
  second.dispose();
  port.close();
  assert.equal(notification.notify(), false);
});

test('physical notification permits one nominal claimant and one active waiter', async () => {
  assert.throws(() => claimInferIoNotification({notify() {}}), /InvalidInferIoNotification/);
  const notification = createInferIoNotification();
  const port = claimInferIoNotification(notification);
  assert.throws(() => claimInferIoNotification(notification), /InvalidInferIoNotification/);
  const ticket = port.arm();
  assert.throws(() => port.arm(), /InferIoWaitAlreadyOwned/);
  port.close();
  await ticket.promise;
  ticket.dispose();
  ticket.dispose();
  assert.equal(notification.notify(), false);
  assert.throws(() => port.arm(), /InferIoWaitAlreadyOwned/);
});

test('disposing a non-I/O poll retires its resolver and does not consume future notification', async () => {
  const notification = createInferIoNotification();
  const port = claimInferIoNotification(notification);
  const prior = port.arm();
  prior.dispose();
  await prior.promise;
  notification.notify();
  const current = port.arm();
  prior.dispose();
  await current.promise;
  assert.throws(() => port.arm(), /InferIoWaitAlreadyOwned/);
  current.dispose();
  port.close();
});

// These are explicit physical Core-port doubles, not public execution proof.
// Common Owner/ACK admission is covered separately by the MoonBit entry tests.
function fixture({notification = createInferIoNotification(), signal, onPoll,
  cleanup = () => true, startFailure, omitNotification = false} = {}) {
  const active = {};
  let pending = true, requested = false, stopped = false;
  let advances = 0, starts = 0, cleanups = 0, progress = 0;
  const output = Object.freeze([{answer: 7}]);
  const moon = {
    clientProgramStartScopedInferExecution() {
      starts++;
      return startFailure === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startFailure};
    },
    clientProgramAdvanceInferExecution(owner) {
      assert.equal(owner, active);
      advances++;
      const wasPending = pending;
      onPoll?.(advances, () => { pending = false; notification.notify(); });
      if (requested && !pending) { stopped = true; return {$tag: 1, _0: 'stopped'}; }
      return {$tag: 1, _0: wasPending ? 'await_io' : 'complete'};
    },
    clientProgramInferExecutionPollKind: poll => poll,
    clientProgramInferExecutionOutput: () => output,
    clientProgramCancelInferExecution() { requested = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution() { cleanups++; return {$tag: 1, _0: cleanup()}; },
  };
  const open = () => openNodeInferOperation({moon, preparedProgram: {}, step: 0,
    graph: {}, registry: '', values: '', fragment: '', ordered: '', provider: {}, signal,
    ioNotification: omitNotification ? undefined : notification,
    observeProgress() { progress++; }});
  return {open, notification, output,
    complete() { pending = false; notification.notify(); },
    counts: () => ({advances, starts, cleanups, progress}), stopped: () => stopped};
}

test('notification during the original poll cannot be lost before await', async () => {
  const f = fixture({onPoll: (count, complete) => { if (count === 1) complete(); }});
  const operation = f.open();
  assert.equal(await operation.run(), f.output);
  assert.equal(f.counts().advances, 2);
  await operation.close();
  assert.equal(f.notification.notify(), false);
});

test('pending physical I/O waits without timer polling or progress callbacks', async () => {
  const f = fixture();
  const operation = f.open();
  const running = operation.run();
  assert.equal(operation.run(), running, 'one original drive flight');
  await turn(); await turn();
  assert.deepEqual(f.counts(), {advances: 1, starts: 1, cleanups: 0, progress: 0});
  f.complete();
  assert.equal(await running, f.output);
  assert.equal(f.counts().advances, 2);
  await operation.close();
});

test('a stale coalesced wake triggers at most one additional original poll', async () => {
  const f = fixture();
  f.notification.notify();
  const operation = f.open();
  const running = operation.run();
  await turn(); await turn();
  assert.equal(f.counts().advances, 2);
  assert.equal(f.counts().progress, 0);
  f.complete();
  assert.equal(await running, f.output);
  await operation.close();
});

test('cancellation wakes once but retains pending physical save and cleanup responsibility', async () => {
  const controller = new AbortController();
  const f = fixture({signal: controller.signal});
  const operation = f.open();
  const running = operation.run();
  const failure = assert.rejects(running, error => error === controller.signal.reason);
  await turn();
  controller.abort(new Error('OriginalRequestCancelled'));
  const closing = operation.close();
  let closed = false;
  closing.then(() => { closed = true; });
  await turn(); await turn();
  assert.equal(f.counts().advances, 2, 'sticky stop is not another wake every iteration');
  assert.equal(f.stopped(), false);
  assert.equal(operation.cleanup(), false);
  assert.equal(f.counts().cleanups, 0);
  assert.equal(closed, false);
  f.complete();
  await failure;
  await closing;
  assert.equal(f.counts().starts, 1);
  assert.equal(f.counts().cleanups, 1);
  assert.equal(f.notification.notify(), false);
});

test('stop without run drains owned I/O only after its actual completion notification', async () => {
  const f = fixture();
  const operation = f.open();
  const stopping = operation.stop();
  await turn(); await turn();
  assert.equal(f.counts().advances, 2, 'stop wake is coalesced once before polling');
  assert.equal(f.stopped(), false);
  f.complete();
  await stopping;
  assert.equal(operation.cleanup(), true);
  assert.equal(f.counts().starts, 1);
});

test('cleanup failure retains notifier until original Core reclamation succeeds', async () => {
  let available = false;
  const f = fixture({cleanup: () => available});
  const operation = f.open();
  f.complete();
  assert.equal(await operation.run(), f.output);
  await operation.stop();
  assert.equal(operation.cleanup(), false);
  assert.equal(f.notification.notify(), true);
  const before = f.counts().advances;
  available = true;
  assert.equal(operation.cleanup(), true);
  assert.equal(operation.cleanup(), true);
  assert.equal(f.counts().advances, before, 'cleanup retry does not run Compute');
  assert.equal(f.counts().cleanups, 2);
  assert.equal(f.notification.notify(), false);
});

test('uninstalled I/O profile refuses AwaitIo without pretending it is approval Waiting', async () => {
  const f = fixture({omitNotification: true});
  const operation = f.open();
  await assert.rejects(operation.run(), /InferIoNotificationUnavailable/);
  assert.equal(operation.cleanupPending(), true);
  assert.equal(operation.cleanup(), false);
  await assert.rejects(operation.stop(), /ClientDispatchCleanupPending/);
  assert.equal(f.counts().cleanups, 0);
  f.complete();
  await operation.stop();
  assert.equal(operation.cleanup(), true);
});

test('foreign or previously claimed notifier is refused before constructing Core', async () => {
  const foreign = fixture({notification: {notify() {}}});
  assert.throws(foreign.open, /InvalidInferIoNotification/);
  assert.equal(foreign.counts().starts, 0);
  const f = fixture();
  const operation = f.open();
  assert.throws(f.open, /InvalidInferIoNotification/);
  assert.equal(f.counts().starts, 1);
  assert.equal(operation.cleanupPending(), true);
  f.complete();
  await operation.close();
});

test('failed Core construction retires an unused physical notifier', () => {
  const f = fixture({startFailure: 'OriginalStartRefusal'});
  assert.throws(f.open);
  assert.equal(f.counts().starts, 1);
  assert.equal(f.notification.notify(), false);
});
