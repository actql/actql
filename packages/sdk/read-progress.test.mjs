import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {connect} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('9')};
const profile = {version: 'actql-client-host/0.1', mode: 'remote',
  owner: 'remote', durability: 'durable', scopeRef: 'scope', capabilities: [],
  limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
    maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};

async function result(t, respond) {
  const reads = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json({ref,
      durability: 'durable', revision: 1});
    assert.equal(operation, 'read');
    reads.push(JSON.parse(init.body).attemptId);
    return respond(reads.length);
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/',
    token: 'token'});
  return {result: (await client.attach(ref)).result('answer'), reads};
}

test('120 yielded rows remain a prefix and a fresh read does not append or retry', async t => {
  const text = Array.from({length: 120}, (_, index) => `{"value":${index + 1}}\n`).join('');
  const f = await result(t, number => new Response(text + (number === 1 ? '' : '\x1e')));
  const reader = f.result.rows();
  assert.equal(reader.rowsYielded(), 0);
  const prefix = [];
  await assert.rejects(async () => {
    for await (const row of reader) {
      prefix.push(row);
      assert.equal(reader.rowsYielded(), prefix.length, '[check-mutation:read-progress]');
    }
  }, {code: 'IncompleteResultStream', attemptId: reader.attemptId, rowsYielded: 120});
  assert.equal(reader.state(), 'prefix');
  assert.equal(reader.rowsYielded(), 120);
  assert.equal(f.reads.length, 1);
  const fresh = f.result.rows();
  assert.notEqual(fresh.attemptId, reader.attemptId);
  assert.equal(fresh.rowsYielded(), 0);
  assert.equal(f.reads.length, 1);
  assert.deepEqual(await Array.fromAsync(fresh),
    Array.from({length: 120}, (_, index) => ({value: index + 1})));
  assert.equal(fresh.state(), 'complete');
  assert.equal(fresh.rowsYielded(), 120);
  assert.equal(prefix.length, 120);
  assert.equal(f.reads.length, 2);
});

test('decoding a large chunk does not count rows before they are yielded', async t => {
  const f = await result(t, () => new Response('{"value":1}\n{"value":2}\n\x1e'));
  const reader = f.result.rows();
  const iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual((await iterator.next()).value, {value: 1});
  assert.equal(reader.rowsYielded(), 1, '[check-mutation:read-progress]');
  await iterator.return();
  assert.equal(reader.rowsYielded(), 1);
  assert.equal(reader.state(), 'prefix');
});

test('a malformed row does not increase the yielded count', async t => {
  const f = await result(t, () => new Response('{"value":1}\nnot-json\n\x1e'));
  const reader = f.result.rows();
  await assert.rejects(Array.fromAsync(reader), error =>
    error.attemptId === reader.attemptId && error.rowsYielded === 1);
  assert.equal(reader.rowsYielded(), 1);
});

for (const operation of ['rows', 'all']) {
  test(`${operation} rejects malformed first rows without exposing their data or counting them`, async t => {
    for (const text of ['null', 'false', '0', '""', '[]', '[{"value":1}]',
      '"private-result-fragment"', 'private-result-fragment', '{"value":']) {
      const f = await result(t, () => new Response(text + '\n\x1e'));
      const reader = operation === 'rows' ? f.result.rows() : undefined;
      let failure;
      try {
        if (reader) await Array.fromAsync(reader);
        else await f.result.all();
      } catch (error) { failure = error; }
      assert.equal(failure?.code, 'InvalidResultFrame');
      assert.equal(failure.rowsYielded, 0);
      assert.equal(failure.attemptId, f.reads[0]);
      const frameFailure = reader ? failure.cause : failure.cause.cause;
      assert.equal(frameFailure.code, 'InvalidResultFrame');
      assert.equal(frameFailure.cause, undefined);
      assert.equal(f.reads.length, 1);
      if (reader) {
        assert.equal(reader.state(), 'prefix');
        assert.equal(reader.rowsYielded(), 0);
      }
    }
  });
}

test('valid object rows retain empty records and scalar-valued fields', async t => {
  const f = await result(t, () => new Response('{}\n{"value":null}\n{"value":false}\n{"value":0}\n{"value":""}\n{"value":[]}\n\x1e'));
  const reader = f.result.rows();
  assert.deepEqual(await Array.fromAsync(reader), [{}, {value: null},
    {value: false}, {value: 0}, {value: ''}, {value: []}]);
  assert.equal(reader.state(), 'complete');
  assert.equal(reader.rowsYielded(), 6);
});

for (const [name, text, count] of [
  ['unreturned batch', '{"value":1}\n{"value":2}\n', 0],
  ['one yielded batch and one buffered row',
    '{"value":1}\n{"value":2}\n{"value":3}\n{"value":4}\n', 3],
]) {
  test(`batch failure counts only ${name}`, async t => {
    const f = await result(t, () => new Response(text));
    const reader = f.result.batches();
    const seen = [];
    await assert.rejects(async () => {
      for await (const batch of reader) {
        seen.push(...batch);
        assert.equal(reader.rowsYielded(), seen.length);
      }
    }, {code: 'IncompleteResultStream', attemptId: reader.attemptId, rowsYielded: count});
    assert.equal(reader.rowsYielded(), count, '[check-mutation:batch-progress]');
    assert.equal(seen.length, count);
  });
}

test('a final complete batch includes all returned rows', async t => {
  const f = await result(t, () => new Response('{"value":1}\n{"value":2}\n\x1e'));
  const reader = f.result.batches();
  assert.deepEqual(await Array.fromAsync(reader), [[{value: 1}, {value: 2}]]);
  assert.equal(reader.rowsYielded(), 2);
  assert.equal(reader.state(), 'complete');
});

for (const operation of ['all', 'one', 'scalar']) {
  test(`failed ${operation} returns no rows to its caller`, async t => {
    const f = await result(t, () => new Response('{"value":1}\n'));
    await assert.rejects(f.result[operation](), error =>
      error.code === 'IncompleteResultStream' && error.rowsYielded === 0 &&
      error.attemptId === f.reads[0] && error.cause.rowsYielded === 1);
    assert.equal(f.reads.length, 1);
  });
}

test('yielded progress preserves independent cleanup uncertainty', async t => {
  const cleanupError = new Error('cleanup unknown');
  const f = await result(t, () => new Response(new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('{"value":1}\n\n')); },
    cancel() { throw cleanupError; },
  })));
  const reader = f.result.batches();
  await assert.rejects(Array.fromAsync(reader), error =>
    error.code === 'InvalidResultStream' && error.rowsYielded === 0 &&
    error.cleanupError === cleanupError && error.attemptId === reader.attemptId);
});
