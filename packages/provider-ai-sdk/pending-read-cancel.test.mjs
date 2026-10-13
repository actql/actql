import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {readBoundedInferResponse} from './_internal/bounded-response.mjs';

// Original physical reader double only. Pending read and cancellation remain
// owned until the fixture explicitly settles them; no remote-stop, funding,
// saved-response or public execution observation is issued by this test.
test('cancel exposes the same incomplete raw prefix without awaiting the pending read', async () => {
  const controller = new AbortController();
  const prefix = new Uint8Array([65]);
  let finishRead;
  let finishCancel;
  let reads = 0;
  let cancellations = 0;
  let releases = 0;
  const reader = {
    read() {
      reads++;
      if (reads === 1) return Promise.resolve({done: false, value: prefix});
      return new Promise(resolve => { finishRead = resolve; });
    },
    cancel() {
      cancellations++;
      return new Promise(resolve => { finishCancel = resolve; });
    },
    releaseLock() { releases++; },
  };
  const response = {status: 200, headers: new Headers(),
    body: {getReader: () => reader}};
  let observed;
  const operation = readBoundedInferResponse(response, {
    maxBytes: 8, maxChunkBytes: 4, maxChunks: 2, maxHeaderBytes: 16,
  }, controller.signal).then(value => { observed = value; return value; });
  try {
    for (let i = 0; i < 8 && finishRead === undefined; i++) await turn();
    assert.equal(reads, 2);
    controller.abort();
    for (let i = 0; i < 8 && observed === undefined; i++) await turn();
    assert.notEqual(observed, undefined,
      'Original incomplete observation is still pinned to an unsettled read');
    assert.equal(observed.status, 200);
    assert.deepEqual(observed.body, prefix);
    assert.equal(observed.observedBytes, 1);
    assert.equal(observed.transportComplete, false);
    assert.equal(observed.issue, 'InferResponseReadCancelled');
    assert.equal(cancellations, 1);
    assert.equal(releases, 0);
    assert.equal(reads, 2);
  } finally {
    // Settle the original operations even when the pre-fix assertion fails.
    // This is test teardown, not product proof of a never-settling IO release.
    finishRead?.({done: true});
    const original = await operation;
    finishCancel?.();
    assert.equal(await original.readerRetirement, true);
    assert.equal(releases, 1);
    assert.equal(reads, 2);
  }
});
