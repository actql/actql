import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import {readBoundedInferResponse as common} from '../adapters/host-common/model-response-reader.mjs';
import {readBoundedInferResponse as ai} from '../packages/provider-ai-sdk/_internal/bounded-response.mjs';
import {readBoundedInferResponse as http} from '../packages/provider-http/_internal/bounded-response.mjs';

const source = new URL('../adapters/host-common/model-response-reader.mjs', import.meta.url);
test('independent physical reader copies remain byte-identical to their single source', () => {
  const original = readFileSync(source);
  for (const path of ['../packages/provider-ai-sdk/_internal/bounded-response.mjs',
    '../packages/provider-http/_internal/bounded-response.mjs']) {
    assert.deepEqual(readFileSync(new URL(path, import.meta.url)), original);
  }
});

// Direct physical reader conformance, not SDK/Core/Store/public admission.
// Every fixture settles its original operations in teardown, never pretending
// that a permanently unresponsive implementation has physically retired.
for (const [name, read] of [['Common', common], ['AI SDK copy', ai], ['independent HTTP copy', http]]) {
  test(`${name} abort exposes exact prefix but cancel alone cannot retire pending read`, async () => {
    const controller = new AbortController();
    let finishRead;
    let finishCancel;
    let releases = 0;
    let reads = 0;
    let cancellations = 0;
    const response = {status: 200, headers: new Headers(), body: {getReader() {
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
    const operation = read(response, {maxBytes: 8, maxChunkBytes: 4, maxChunks: 2,
      maxHeaderBytes: 16}, controller.signal).then(value => { observed = value; return value; });
    try {
      for (let i = 0; i < 8 && finishRead === undefined; i++) await turn();
      assert.equal(reads, 2);
      controller.abort();
      for (let i = 0; i < 8 && observed === undefined; i++) await turn();
      assert.notEqual(observed, undefined);
      assert.deepEqual(observed.body, new Uint8Array([65]));
      assert.equal(observed.transportComplete, false);
      assert.equal(observed.issue, 'InferResponseReadCancelled');
      finishCancel();
      for (let i = 0; i < 4; i++) await turn();
      assert.equal(releases, 0);
      assert.equal(cancellations, 1);
      finishRead({done: false, value: new Uint8Array([66])});
      assert.equal(await observed.readerRetirement, true);
      assert.equal(releases, 1);
      assert.equal(reads, 2);
      assert.deepEqual(observed.body, new Uint8Array([65]));
      assert.equal(observed.observedBytes, 1);
      assert.equal(observed.transportComplete, false);
    } finally {
      finishRead?.({done: true});
      const original = await operation;
      finishCancel?.();
      await original.readerRetirement;
    }
  });
}
