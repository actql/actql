import assert from 'node:assert/strict';
import test from 'node:test';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

for (const property of ['retry', 'status']) {
  test(`initialization retains the original child and parent when ${property} method capture throws`, async () => {
    const getterFailure = new Error(`Original${property}PropertyFailed`);
    let available = false, retired = false, permitRetirement = false;
    let retries = 0, parentCloses = 0, replacementCalls = 0;
    const child = {};
    const originalRetry = async function() {
      assert.equal(this, child);
      retries++;
      if (permitRetirement) retired = true;
    };
    const originalStatus = function() {
      assert.equal(this, child);
      return {pending: !retired, errors: []};
    };
    for (const [name, value] of [['retry', originalRetry], ['status', originalStatus]]) {
      Object.defineProperty(child, name, {configurable: true, get() {
        if (name === property && !available) throw getterFailure;
        return value;
      }});
    }
    const primary = Object.assign(new Error('OriginalOpeningFailure'), {
      cleanupHandle: child, cleanupPending: true,
    });
    const failure = await retainInstalledHostInitializationFailure(primary, {
      journal: {close() { parentCloses++; }},
    });
    assert.equal(failure.code, 'InstalledHostInitializationFailed');
    assert.equal(failure.cause, primary);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupPending, true);
    assert.deepEqual(failure.cleanupHandle.status().owners, ['initialization', 'journal']);
    assert.ok(failure.cleanupHandle.status().errors.some(item => item.error === getterFailure));
    assert.equal(parentCloses, 0);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(retries, 0);
    available = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(retries, 1);
    assert.equal(parentCloses, 0);
    // Once obtained, both methods and their receiver remain the original
    // ones even if the exception or the same child later changes properties.
    const replacement = {async retry() { replacementCalls++; },
      status() { replacementCalls++; return {pending: false, errors: []}; }};
    primary.cleanupHandle = replacement;
    for (const name of ['retry', 'status']) {
      Object.defineProperty(child, name, {value: replacement[name], configurable: true});
    }
    permitRetirement = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, 2);
    assert.equal(parentCloses, 1);
    assert.equal(replacementCalls, 0);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, 2);
    assert.equal(parentCloses, 1);
  });
}

test('missing original retry remains pending even if its status alone says closed', async () => {
  let closes = 0;
  const primary = Object.assign(new Error('OriginalOpeningFailure'), {
    cleanupPending: true, cleanupHandle: {status: () => ({pending: false, errors: []})},
  });
  const failure = await retainInstalledHostInitializationFailure(primary,
    {journal: {close() { closes++; }}});
  assert.equal(failure.primaryFailure, primary);
  assert.equal(failure.cleanupPending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(closes, 0);
});
