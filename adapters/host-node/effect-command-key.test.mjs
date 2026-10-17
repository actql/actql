import assert from 'node:assert/strict';
import test from 'node:test';
import {advanceEffectCommandKey, retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';

test('Host key caller advances only the same opaque original with a captured method and receiver', async () => {
  const original = Object.freeze({});
  let reads = 0, calls = 0;
  const moon = {
    get clientProgramEffectCommandKeyAdvance() {
      reads++;
      return function (key, quantum) {
        assert.equal(this, moon);
        assert.equal(key, original);
        assert.equal(quantum, 7);
        calls++;
        return {TAG: 0, _0: {_0: calls === 2, _1: 1}};
      };
    },
  };
  await advanceEffectCommandKey(moon, original, undefined, 7);
  assert.equal(reads, 1);
  assert.equal(calls, 2);
  await advanceEffectCommandKey({}, undefined, undefined, 7);
});

test('Host key caller rejects nonprogress and observes cancellation before the next original advance', async () => {
  const original = Object.freeze({});
  await assert.rejects(advanceEffectCommandKey({
    clientProgramEffectCommandKeyAdvance: () => ({TAG: 0, _0: {_0: false, _1: 0}}),
  }, original, undefined, 1), /EffectCommandKeyDidNotAdvance/u);
  const controller = new AbortController();
  let calls = 0;
  const cause = new Error('original request stopped');
  controller.abort(cause);
  await assert.rejects(advanceEffectCommandKey({
    clientProgramEffectCommandKeyAdvance() { calls++; },
  }, original, controller.signal, 1), error => error === cause);
  assert.equal(calls, 0);
});

test('private workspace retirement waits for its exact completion without a physical cleanup acknowledgement', async () => {
  let steps = 0;
  await retireEffectCommandKeyWorkspace(() => ++steps === 3);
  assert.equal(steps, 3);
});

test('failed private retirement preserves the same retry callback and original failure', async () => {
  const originalFailure = new Error('original projection refused');
  const cleanupFailure = new Error('original workspace temporarily unavailable');
  let available = false, calls = 0;
  const originalCleanup = () => {
    calls++;
    if (!available) throw cleanupFailure;
    return true;
  };
  let failure;
  await assert.rejects(retireEffectCommandKeyWorkspace(originalCleanup, originalFailure), error => {
    failure = error;
    return error.cause === originalFailure && error.cleanupError === cleanupFailure;
  });
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cleanupHandle.status().pending, true);
  available = true;
  assert.deepEqual(await failure.cleanupHandle.retry(), {pending: false});
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(calls, 2);
});
