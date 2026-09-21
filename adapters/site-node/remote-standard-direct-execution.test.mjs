import assert from 'node:assert/strict';
import test from 'node:test';
import {createRemoteStandardDirectExecution} from
  './remote-standard-direct-execution.mjs';

function fixture({rejectFrame = false, cleanupResults = [true]} = {}) {
  const dispatch = Object.freeze({kind: 'dispatch'});
  const inputBinding = Object.freeze({kind: 'binding'});
  const claim = Object.freeze({
    destinationReceiptCid: 'receipt-a',
    materialGeneration: 'generation-a',
  });
  const frames = [Buffer.from('one'), Buffer.from('two')];
  const events = [];
  let cleanupIndex = 0;
  const receiver = Object.freeze({
    claim(requestCid) {
      assert.equal(requestCid, 'request-a');
      events.push('claim');
      return claim;
    },
    async consume(requestCid, authorize, accept) {
      assert.equal(requestCid, 'request-a');
      assert.equal(await authorize(claim), true);
      events.push('authorized-before');
      for (let index = 0; index < frames.length; index++) {
        await accept(index, frames[index]);
      }
      assert.equal(await authorize(claim), true);
      events.push('authorized-after');
      return claim;
    },
  });
  const session = Object.freeze({kind: 'session'});
  const failure = Object.freeze({kind: 'failure'});
  const output = Object.freeze({kind: 'output'});
  let physicalAvailable;
  let releasePhysical;
  const control = Object.freeze({
    requestCid(value, binding) {
      assert.equal(value, dispatch);
      assert.equal(binding, inputBinding);
      events.push('request');
      return 'request-a';
    },
    prepare(value, binding, retained, available, release) {
      assert.equal(value, dispatch);
      assert.equal(binding, inputBinding);
      assert.equal(retained, claim);
      physicalAvailable = available;
      releasePhysical = release;
      assert.equal(available(), true);
      events.push('prepare');
      return session;
    },
    authorize(value, retained) {
      assert.equal(value, session);
      assert.equal(retained, claim);
      assert.equal(physicalAvailable(), true);
      return true;
    },
    feed(value, index, frame) {
      assert.equal(value, session);
      assert.equal(frame, frames[index]);
      events.push(`feed-${index}`);
      return !(rejectFrame && index === 1);
    },
    finish(value) {
      assert.equal(value, session);
      assert.equal(releasePhysical(), true);
      assert.equal(physicalAvailable(), false);
      events.push('finish');
      return output;
    },
    cancel(value) {
      assert.equal(value, session);
      events.push('cancel');
      return failure;
    },
    failureCode(value) {
      assert.equal(value, failure);
      return 'standard-input-failed';
    },
    retryFailureCleanup(value) {
      assert.equal(value, failure);
      events.push('retry-cleanup');
      return cleanupResults[Math.min(
        cleanupIndex++,
        cleanupResults.length - 1,
      )];
    },
  });
  return {
    control,
    dispatch,
    events,
    inputBinding,
    output,
    receiver,
  };
}

test('direct input streams exact frames through the opaque task session',
  async () => {
    const setup = fixture();
    const execute = createRemoteStandardDirectExecution(setup);
    assert.equal(await execute({
      dispatch: setup.dispatch,
      inputBinding: setup.inputBinding,
    }), setup.output);
    assert.deepEqual(setup.events, [
      'request',
      'claim',
      'prepare',
      'authorized-before',
      'feed-0',
      'feed-1',
      'authorized-after',
      'finish',
    ]);
  });

test('MoonBit-owned failed input cleanup remains retryable', async () => {
  const setup = fixture({rejectFrame: true, cleanupResults: [false, true]});
  const execute = createRemoteStandardDirectExecution(setup);
  const failure = await execute({
    dispatch: setup.dispatch,
    inputBinding: setup.inputBinding,
  }).catch(error => error);
  assert.equal(failure.code, 'standard-input-failed');
  assert.equal(failure.cleanupPending, true);
  assert.deepEqual(failure.cleanupHandle.status(), {
    pending: true,
    errors: [],
  });
  assert.deepEqual(await failure.cleanupHandle.retry(), {
    pending: false,
    errors: [],
  });
  assert.deepEqual(setup.events, [
    'request',
    'claim',
    'prepare',
    'authorized-before',
    'feed-0',
    'feed-1',
    'cancel',
    'retry-cleanup',
    'retry-cleanup',
  ]);
});
