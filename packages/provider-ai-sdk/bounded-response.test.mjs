import assert from 'node:assert/strict';
import test from 'node:test';
import {readBoundedInferResponse} from './_internal/bounded-response.mjs';

const limits = {maxBytes: 8, maxChunkBytes: 4, maxChunks: 8, maxHeaderBytes: 16,
  observedHeaders: ['content-type']};
const bytes = text => new TextEncoder().encode(text);
function fixture(chunks, {readError, cancel} = {}) {
  let reads = 0;
  let cancellations = 0;
  let releases = 0;
  let forbidden = 0;
  const reader = {
    async read() {
      const index = reads++;
      if (readError === index) throw new Error('secret-provider-exception');
      return index < chunks.length ? {done: false, value: chunks[index]}
        : {done: true};
    },
    cancel() { cancellations++; return cancel?.(); },
    releaseLock() { releases++; },
  };
  const response = {status: 200, headers: new Headers({'content-type': 'text/plain'}),
    body: {getReader() { return reader; }}};
  for (const name of ['text', 'json', 'arrayBuffer', 'clone']) {
    response[name] = () => { forbidden++; throw new Error('unbounded'); };
  }
  response.body.tee = () => { forbidden++; throw new Error('tee'); };
  return {response, counts: () => ({reads, cancellations, releases, forbidden})};
}

test('decoded bytes at the exact bound are retained without parsing or cloning', async () => {
  const input = fixture([bytes('abcd'), bytes('efgh')]);
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(new TextDecoder().decode(result.body), 'abcdefgh');
  assert.equal(result.body.buffer.byteLength, 8);
  assert.equal(result.observedBytes, 8);
  assert.equal(result.transportComplete, true);
  assert.equal(result.issue, undefined);
  assert.equal(await result.readerRetirement, true);
  assert.deepEqual(result.headers, [['content-type', 'text/plain']]);
  assert.deepEqual(input.counts(), {reads: 3, cancellations: 0, releases: 1, forbidden: 0});
});

test('one byte over the bound retains the original prefix and no success claim', async () => {
  const input = fixture([bytes('abcd'), bytes('efgh'), bytes('i')]);
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(new TextDecoder().decode(result.body), 'abcdefgh');
  assert.equal(result.observedBytes, 9);
  assert.equal(result.transportComplete, false);
  assert.equal(result.issue, 'InferResponseByteLimit');
  assert.equal(await result.readerRetirement, true);
  assert.deepEqual(input.counts(), {reads: 3, cancellations: 1, releases: 1, forbidden: 0});
});

test('a transport chunk outside its declared envelope is not copied', async () => {
  const input = fixture([bytes('ab'), bytes('cdefg')]);
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(new TextDecoder().decode(result.body), 'ab');
  assert.equal(result.observedBytes, 7);
  assert.equal(result.issue, 'InferResponseChunkLimit');
  assert.equal(result.transportComplete, false);
  await result.readerRetirement;
  assert.equal(input.counts().cancellations, 1);
});

test('empty chunks still consume the finite physical read-count envelope', async () => {
  const input = fixture([bytes(''), bytes(''), bytes(''), bytes('a')]);
  const result = await readBoundedInferResponse(input.response, {...limits, maxChunks: 2});
  assert.equal(result.issue, 'InferResponseChunkCountLimit');
  assert.equal(result.transportComplete, false);
  assert.equal(result.observedBytes, 0);
  assert.equal(result.body.byteLength, 0);
  await result.readerRetirement;
  assert.equal(input.counts().reads, 3);
});

test('the last permitted chunk can be followed by EOF', async () => {
  const input = fixture([bytes('a'), bytes('b')]);
  const result = await readBoundedInferResponse(input.response, {...limits, maxChunks: 2});
  assert.equal(result.transportComplete, true);
  assert.deepEqual(result.body, bytes('ab'));
});

test('the observed byte count includes a chunk refused by the count envelope', async () => {
  const input = fixture([bytes('a'), bytes('bc')]);
  const result = await readBoundedInferResponse(input.response, {...limits, maxChunks: 1});
  assert.equal(result.issue, 'InferResponseChunkCountLimit');
  assert.equal(result.observedBytes, 3);
  assert.deepEqual(result.body, bytes('a'));
  await result.readerRetirement;
});

test('transport failure retains bytes and sanitizes the physical diagnostic', async () => {
  const input = fixture([bytes('a')], {readError: 1});
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(result.issue, 'InferResponseReadFailed');
  assert.equal(new TextDecoder().decode(result.body), 'a');
  assert.equal(result.transportComplete, false);
  assert.ok(!JSON.stringify(result).includes('secret-provider-exception'));
  await result.readerRetirement;
});

test('incomplete observation does not wait for or fabricate reader retirement', async () => {
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const input = fixture([bytes('abcde')], {cancel: () => pending});
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(result.transportComplete, false);
  assert.equal(input.counts().releases, 0);
  finish();
  assert.equal(await result.readerRetirement, true);
  assert.equal(input.counts().releases, 1);
});

test('failed reader cancellation does not report retirement', async () => {
  const input = fixture([bytes('abcde')], {cancel: () => Promise.reject(new Error('secret'))});
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(await result.readerRetirement, false);
  assert.equal(input.counts().releases, 0);
});

test('cleanup failure retains the same reader and retries without reading again', async () => {
  let attempts = 0;
  const input = fixture([bytes('abcde')], {cancel: () => {
    if (attempts++ === 0) throw new Error('secret');
  }});
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(await result.readerRetirement, false);
  assert.equal(await result.retryReaderRetirement(), true);
  assert.equal(await result.retryReaderRetirement(), true);
  assert.deepEqual(input.counts(), {reads: 1, cancellations: 2, releases: 1, forbidden: 0});
  assert.equal(result.transportComplete, false);
});

test('status and bounded header originals cannot change across the body await', async () => {
  let resolveRead;
  const input = fixture([]);
  input.response.body.getReader = () => ({
    read: () => new Promise(resolve => { resolveRead = resolve; }),
    releaseLock() {},
  });
  const pending = readBoundedInferResponse(input.response, limits);
  input.response.status = 503;
  input.response.headers.set('content-type', 'changed');
  resolveRead({done: true});
  const result = await pending;
  assert.equal(result.status, 200);
  assert.deepEqual(result.headers, [['content-type', 'text/plain']]);
});

test('empty and Unicode transport bodies are not NULL or normalized', async () => {
  const empty = await readBoundedInferResponse(fixture([]).response, limits);
  assert.equal(empty.body.byteLength, 0);
  assert.equal(empty.transportComplete, true);
  const original = 'e\u0301\r\n';
  const unicode = await readBoundedInferResponse(fixture([bytes(original)]).response,
    {...limits, maxChunkBytes: 8});
  assert.deepEqual(unicode.body, bytes(original));
});

test('Content-Length does not bypass decoded byte limits', async () => {
  const input = fixture([bytes('abcd'), bytes('efgh'), bytes('i')]);
  input.response.headers.set('content-length', '1');
  input.response.headers.set('content-encoding', 'gzip');
  const result = await readBoundedInferResponse(input.response, limits);
  assert.equal(result.issue, 'InferResponseByteLimit');
  assert.deepEqual(result.headers, [['content-type', 'text/plain']]);
  await result.readerRetirement;
});

test('headers and malformed configuration refuse before reading the body', async () => {
  for (const changed of [{maxBytes: 0}, {maxChunkBytes: 9}, {maxChunks: 0},
    {observedHeaders: ['Content-Type']}, {observedHeaders: ['a', 'a']},
    {maxHeaderBytes: 1}]) {
    const input = fixture([bytes('a')]);
    await assert.rejects(readBoundedInferResponse(input.response, {...limits, ...changed}));
    assert.equal(input.counts().reads, 0);
  }
});

test('real Response streams use the same finite physical reader', async () => {
  const response = new Response(new ReadableStream({start(controller) {
    controller.enqueue(bytes('a')); controller.enqueue(bytes('bc')); controller.close();
  }}), {status: 200, headers: {'content-type': 'text/plain'}});
  const result = await readBoundedInferResponse(response, limits);
  assert.deepEqual(result.body, bytes('abc'));
  assert.equal(result.transportComplete, true);
  assert.equal(await result.readerRetirement, true);
});

test('an actual bodyless HTTP response remains empty transport, not a NULL answer', async () => {
  const result = await readBoundedInferResponse(new Response(null, {status: 204}), limits);
  assert.equal(result.status, 204);
  assert.equal(result.transportComplete, true);
  assert.equal(result.body.byteLength, 0);
  assert.equal(await result.readerRetirement, true);
  assert.equal(Object.hasOwn(result, 'value'), false);
});

test('raw invalid UTF-8 is retained without replacement or premature JSON decoding', async () => {
  const original = Uint8Array.of(255, 254, 0);
  const result = await readBoundedInferResponse(fixture([original]).response, limits);
  assert.deepEqual(result.body, original);
  assert.equal(result.transportComplete, true);
});

test('abort during reading retains an incomplete original without claiming EOF or reader release', async () => {
  const controller = new AbortController();
  let finishRead;
  let finishCancel;
  let releases = 0;
  const response = {status: 200, headers: new Headers(), body: {getReader() {
    return {read: () => new Promise(resolve => { finishRead = resolve; }),
      cancel: () => new Promise(resolve => { finishCancel = resolve; }),
      releaseLock() { releases++; }};
  }}};
  const operation = readBoundedInferResponse(response, limits, controller.signal);
  controller.abort();
  finishRead({done: true});
  const original = await operation;
  assert.equal(original.transportComplete, false);
  assert.equal(original.issue, 'InferResponseReadCancelled');
  assert.equal(releases, 0);
  finishCancel();
  assert.equal(await original.readerRetirement, true);
  assert.equal(releases, 1);
});

test('an already aborted reader does not issue a physical read or a success observation', async () => {
  const controller = new AbortController();
  controller.abort();
  const input = fixture([bytes('secret')]);
  const original = await readBoundedInferResponse(input.response, limits, controller.signal);
  assert.equal(original.issue, 'InferResponseReadCancelled');
  assert.equal(original.transportComplete, false);
  assert.equal(input.counts().reads, 0);
  assert.equal(await original.readerRetirement, true);
});
