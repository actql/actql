import test from 'node:test';
import assert from 'node:assert/strict';
import {finishManagedOutputReceipt} from '../managed-output-finish.mjs';

test('physical receipt adapter yields before the next bounded poll', async () => {
  let calls = 0, yielded = false;
  await finishManagedOutputReceipt(quantum => {
    assert.equal(quantum, 64);
    calls++;
    if (calls === 1) {
      setImmediate(() => { yielded = true; });
      return {_0: false, _1: 64};
    }
    assert.equal(yielded, true);
    return {_0: true, _1: 1};
  });
  assert.equal(calls, 2);
});

test('physical receipt adapter stops polling after cancellation or failure', async () => {
  const controller = new AbortController();
  let calls = 0;
  await assert.rejects(finishManagedOutputReceipt(() => {
    calls++;
    setImmediate(() => controller.abort());
    return {_0: false, _1: 64};
  }, controller.signal), {name: 'AbortError'});
  assert.equal(calls, 1);
  const failure = new Error('typed owner failure');
  await assert.rejects(finishManagedOutputReceipt(() => { throw failure; }),
    error => error === failure);
});

test('physical receipt adapter rejects invalid progress without retry', async () => {
  for (const poll of [null, {_0: 1, _1: 1}, {_0: false, _1: 0},
    {_0: false, _1: 65}, {_0: true, _1: 1.5}]) {
    let calls = 0;
    await assert.rejects(finishManagedOutputReceipt(() => {
      calls++; return poll;
    }), /Invalid managed output finish progress/);
    assert.equal(calls, 1);
  }
});
