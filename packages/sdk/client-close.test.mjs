import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {connectInProcess, connect, explainReadFailure} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('9')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [], limits: {
    maxReadWireBytes: 65536, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
    maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
};
async function local(read, release = async () => {}) {
  const calls = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body, signal) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
      if (operation === 'read') return read(body, signal);
      throw new Error(`Unexpected operation ${operation}`);
    }, close: release,
  });
  return {client, calls, result: (await client.attach(ref)).result('answer')};
}

test('close seals synchronously, coalesces and retries the same private lease', async () => {
  const entered = deferred(), finish = deferred();
  let releases = 0;
  const f = await local(() => assert.fail('No read'), async () => {
    releases++;
    if (releases === 1) { entered.resolve(); await finish.promise; throw new Error('LeasePending'); }
  });
  const first = f.client.close(), second = f.client.close();
  assert.equal(first, second);
  await assert.rejects(f.client.attach(ref), {code: 'ClientClosed'});
  await entered.promise;
  const failed = assert.rejects(first, error => {
    assert.equal(error.code, 'ClientCleanupPending');
    assert.equal(error.cleanupPending, true);
    assert.equal(error.cause, undefined);
    assert.equal(error.cleanupHandle, undefined);
    return true;
  });
  finish.resolve(); await failed;
  await f.client.close();
  await f.client.close();
  assert.equal(releases, 2);
  assert.deepEqual(f.calls, ['connect', 'attach']);
});

test('close returns a paused Local reader before releasing its lease', async () => {
  let readers = 0, returns = 0, releases = 0;
  const f = await local((_body, signal) => ({kind: 'rows', frames: {
    async *[Symbol.asyncIterator]() {
      readers++;
      try { yield {value: {n: 7}, byteLength: 7}; signal.throwIfAborted(); yield {value: {n: 8}, byteLength: 7}; }
      finally { readers--; returns++; }
    },
  }}), async () => { assert.equal(readers, 0); releases++; });
  const reader = f.result.rows(), iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual((await iterator.next()).value, {n: 7});
  await f.client.close();
  assert.equal(returns, 1);
  assert.equal(releases, 1);
  assert.equal(reader.rowsYielded(), 1);
  assert.equal(reader.state(), 'prefix');
  assert.deepEqual(await iterator.next(), {done: true, value: undefined});
  assert.equal(f.calls.includes('cancel'), false);
});

test('client-initiated close reports original frame cleanup uncertainty after releasing its lease', async () => {
  const cleanup = new Error('frame cleanup uncertain');
  let returns = 0, releases = 0;
  const f = await local(() => ({kind: 'rows', frames: {
    [Symbol.asyncIterator]() {return {
      async next() {return {done: false, value: {value: {n: 7}, byteLength: 7}};},
      async return() {returns++; throw cleanup;},
    };},
  }}), async () => {releases++;});
  const reader = f.result.rows();
  await reader[Symbol.asyncIterator]().next();
  await assert.rejects(f.client.close(), error => {
    assert.equal(error.code, 'ResultReadCleanupUnknown');
    assert.equal(explainReadFailure(error).observation, 'cleanup_unknown');
    assert.equal(explainReadFailure(error).attemptId, reader.attemptId);
    return true;
  });
  assert.equal(releases, 1);
  assert.equal(returns, 1);
  // Reporting uncertainty supplies no retry witness for this finished iterator.
  await f.client.close();
  assert.equal(releases, 1);
  assert.equal(returns, 1);
  assert.equal(f.calls.includes('cancel'), false);
});

test('original frame cleanup failure survives a pending Client lease', async () => {
  let releases = 0, returns = 0;
  const f = await local(() => ({kind: 'rows', frames: {
    [Symbol.asyncIterator]() {return {
      async next() {return {done: false, value: {value: {n: 1}, byteLength: 7}};},
      async return() {returns++; throw new Error('frame return failed');},
    };},
  }}), async () => {if (++releases === 1) throw new Error('lease pending');});
  const reader = f.result.rows();
  await reader[Symbol.asyncIterator]().next();
  await assert.rejects(f.client.close(), {code: 'ClientCleanupPending'});
  await assert.rejects(f.client.close(), error =>
    explainReadFailure(error).attemptId === reader.attemptId);
  await f.client.close();
  assert.equal(releases, 2);
  assert.equal(returns, 1);
});

test('close preserves each original failed reader disposal', async () => {
  const f = await local(() => ({kind: 'rows', frames: {
    [Symbol.asyncIterator]() {return {
      async next() {return {done: false, value: {value: {n: 1}, byteLength: 7}};},
      async return() {throw new Error('frame return failed');},
    };},
  }}));
  const readers = [f.result.rows(), f.result.rows()];
  for (const reader of readers) await reader[Symbol.asyncIterator]().next();
  await assert.rejects(f.client.close(), error => {
    assert.equal(error.code, 'ResultReadCleanupUnknown');
    assert.ok(error.cleanupError instanceof AggregateError);
    assert.deepEqual(error.cleanupError.errors.map(failure => explainReadFailure(failure).attemptId),
      readers.map(reader => reader.attemptId));
    return true;
  });
  await f.client.close();
});

test('close returns a paused batch wrapper and discards its buffered next row', async () => {
  let returns = 0;
  const f = await local(() => ({kind: 'rows', frames: {
    async *[Symbol.asyncIterator]() {
      try { for (const n of [7, 8, 9]) yield {value: {n}, byteLength: 7}; }
      finally { returns++; }
    },
  }}));
  const reader = f.result.batches({maxBatchRows: 1});
  const iterator = reader[Symbol.asyncIterator]();
  const first = (await iterator.next()).value;
  assert.deepEqual(first, [{n: 7}]);
  await f.client.close();
  assert.deepEqual(first, [{n: 7}]);
  assert.equal(returns, 1);
  assert.equal(reader.rowsYielded(), 1);
  assert.deepEqual(await iterator.next(), {done: true, value: undefined});
});

test('close aborts an opening and retains its original read attempt', async () => {
  const opened = deferred();
  const f = await local((body, signal) => new Promise((_yes, no) => {
    opened.resolve(body.attemptId);
    signal.addEventListener('abort', () => no(signal.reason), {once: true});
  }));
  const reader = f.result.rows(), next = reader[Symbol.asyncIterator]().next();
  const refused = assert.rejects(next, error => {
    assert.equal(error.attemptId, reader.attemptId);
    assert.equal(error.rowsYielded, 0);
    assert.equal(explainReadFailure(error).observation, 'read_open_unknown');
    return true;
  });
  assert.equal(await opened.promise, reader.attemptId);
  await f.client.close(); await refused;
  assert.equal(reader.state(), 'open_unknown');
  assert.equal(f.calls.filter(call => call === 'read').length, 1);
});

test('failed reader cleanup retains its private retry before lease release', async () => {
  let ready = false, cleanupCalls = 0, releases = 0;
  const f = await local(() => ({kind: 'rows', frames: {
    async *[Symbol.asyncIterator]() { yield {value: {n: 7}, byteLength: 7}; },
  }, async close() { cleanupCalls++; if (!ready) throw new Error('StillOwned'); }}),
  async () => { releases++; });
  const reader = f.result.rows();
  await reader[Symbol.asyncIterator]().next();
  await assert.rejects(f.client.close(), {code: 'ClientCleanupPending'});
  assert.equal(releases, 0);
  assert.equal(reader.rowsYielded(), 1);
  const before = cleanupCalls;
  ready = true;
  await f.client.close();
  assert.equal(cleanupCalls, before + 1);
  assert.equal(releases, 1);
});

test('close never opens an unused reader and async disposal is the same close', async () => {
  const f = await local(() => assert.fail('No read'));
  const reader = f.result.rows();
  assert.equal(f.client.close, f.client[Symbol.asyncDispose]);
  await f.client[Symbol.asyncDispose]();
  assert.equal(reader.state(), 'not_started');
  assert.equal(f.calls.includes('read'), false);
  await assert.rejects(Array.fromAsync(reader), {code: 'ClientClosed'});
});

test('Remote close waits for response-reader cancellation but sends no Host close', async t => {
  const cancelled = deferred(), finish = deferred();
  const calls = [];
  mock.method(globalThis, 'fetch', async (url) => {
    const operation = url.pathname.split('/').at(-1); calls.push(operation);
    if (operation === 'connect') return Response.json({...profile, mode: 'remote', owner: 'remote'});
    if (operation === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
    assert.equal(operation, 'read');
    return new Response(new ReadableStream({start(controller) {
      controller.enqueue(new TextEncoder().encode('{"n":7}\n'));
    }, async cancel() {cancelled.resolve(); await finish.promise;}}));
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://example.invalid/', token: 'token'});
  const reader = (await client.attach(ref)).result('answer').rows();
  await reader[Symbol.asyncIterator]().next();
  let closed = false;
  const closing = client.close().then(() => {closed = true;});
  await cancelled.promise;
  assert.equal(closed, false);
  finish.resolve(); await closing;
  assert.equal(reader.rowsYielded(), 1);
  assert.deepEqual(calls, ['connect', 'attach', 'read']);
});

test('Remote disposal keeps cancellation uncertainty on the original read without a fabricated retry owner', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json({...profile, mode: 'remote', owner: 'remote'});
    if (operation === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
    assert.equal(operation, 'read');
    return new Response(new ReadableStream({start(controller) {
      controller.enqueue(new TextEncoder().encode('{"n":7}\n'));
    }, cancel() {throw new Error('transport cleanup uncertain');}}));
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://example.invalid/', token: 'token'});
  const reader = (await client.attach(ref)).result('answer').rows();
  const iterator = reader[Symbol.asyncIterator]();
  await iterator.next();
  let failure;
  await assert.rejects(iterator.return(), error => {failure = error; return true;});
  await client.close(); await client.close();
  assert.equal(explainReadFailure(failure).observation, 'cleanup_unknown');
  assert.equal(explainReadFailure(failure).attemptId, reader.attemptId);
  assert.equal(explainReadFailure(failure).rowsYielded, 1);
});
