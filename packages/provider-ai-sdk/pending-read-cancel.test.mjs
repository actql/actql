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

test('cancel acknowledgement alone does not retire an abort-ignoring read or adopt its late chunk', async () => {
  const controller = new AbortController();
  let finishRead;
  let finishCancel;
  let reads = 0;
  let cancellations = 0;
  let releases = 0;
  const response = {status: 503, headers: new Headers(), body: {getReader() {
    return {
      read() {
        reads++;
        if (reads === 1) return Promise.resolve({done: false, value: new Uint8Array([65])});
        return new Promise(resolve => { finishRead = resolve; });
      },
      cancel() { cancellations++; return new Promise(resolve => { finishCancel = resolve; }); },
      releaseLock() { releases++; },
    };
  }}};
  let observed;
  const operation = readBoundedInferResponse(response, {
    maxBytes: 8, maxChunkBytes: 4, maxChunks: 2, maxHeaderBytes: 16,
  }, controller.signal).then(value => { observed = value; return value; });
  try {
    for (let i = 0; i < 8 && finishRead === undefined; i++) await turn();
    controller.abort();
    for (let i = 0; i < 8 && observed === undefined; i++) await turn();
    assert.notEqual(observed, undefined);
    let retired = false;
    observed.readerRetirement.then(() => { retired = true; });
    finishCancel();
    for (let i = 0; i < 4; i++) await turn();
    assert.equal(retired, false);
    assert.equal(releases, 0);
    assert.equal(cancellations, 1);
    assert.equal(observed.status, 503);
    assert.deepEqual(observed.body, new Uint8Array([65]));
    assert.equal(observed.observedBytes, 1);
    assert.equal(observed.transportComplete, false);
    assert.equal(observed.issue, 'InferResponseReadCancelled');
    finishRead({done: false, value: new Uint8Array([66, 67])});
    assert.equal(await observed.readerRetirement, true);
    assert.equal(releases, 1);
    assert.equal(reads, 2);
    assert.deepEqual(observed.body, new Uint8Array([65]));
    assert.equal(observed.observedBytes, 1);
    assert.equal(observed.transportComplete, false);
    assert.equal(await observed.retryReaderRetirement(), true);
    assert.equal(cancellations, 1);
  } finally {
    finishRead?.({done: true});
    const original = await operation;
    finishCancel?.();
    await original.readerRetirement;
  }
});

test('failed cancel retains the same outstanding read and retries cleanup without a fresh read', async () => {
  const controller = new AbortController();
  let rejectRead;
  let reads = 0;
  let cancellations = 0;
  let releases = 0;
  const response = {status: 200, headers: new Headers(), body: {getReader() {
    return {
      read() { reads++; return new Promise((_, reject) => { rejectRead = reject; }); },
      cancel() {
        cancellations++;
        return cancellations === 1 ? Promise.reject(new Error('private-cancel-error'))
          : Promise.resolve();
      },
      releaseLock() { releases++; },
    };
  }}};
  let observed;
  const operation = readBoundedInferResponse(response, {
    maxBytes: 8, maxChunkBytes: 4, maxChunks: 2, maxHeaderBytes: 16,
  }, controller.signal).then(value => { observed = value; return value; });
  try {
    controller.abort();
    for (let i = 0; i < 8 && observed === undefined; i++) await turn();
    assert.notEqual(observed, undefined);
    assert.equal(await observed.readerRetirement, false);
    assert.equal(releases, 0);
    assert.equal(reads, 1);
    assert.equal(cancellations, 1);
    const cleanup = observed.retryReaderRetirement();
    let retired = false;
    cleanup.then(() => { retired = true; });
    for (let i = 0; i < 4; i++) await turn();
    assert.equal(retired, false);
    assert.equal(releases, 0);
    rejectRead(new Error('private-late-read-error'));
    assert.equal(await cleanup, true);
    assert.equal(releases, 1);
    assert.equal(reads, 1);
    assert.equal(cancellations, 2);
    assert.equal(observed.transportComplete, false);
    assert.equal(observed.issue, 'InferResponseReadCancelled');
    assert.equal(observed.observedBytes, 0);
    assert.equal(observed.body.byteLength, 0);
  } finally {
    rejectRead?.(new Error('private-fixture-teardown'));
    const original = await operation;
    await original.retryReaderRetirement();
  }
});
