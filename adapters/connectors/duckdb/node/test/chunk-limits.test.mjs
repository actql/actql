import test from 'node:test';
import assert from 'node:assert/strict';
import {DuckDBDataChunk, DuckDBVarCharVector, DuckDBPreparedStatement} from '@duckdb/node-api';
import sdk from '@duckdb/node-api/package.json' with {type: 'json'};
import {boundedVectorItem, assertBoundedVectorRuntime} from '../bounded-vector.mjs';
import {withComputeDatabase} from '../session.mjs';
import {validateLimits, prepareDuckDBStrategyConfiguration, preparedStrategyConfiguration} from '../configuration.mjs';

const limits = {maxRows: 10000, maxCells: 20000, maxTransportBytes: 2000000,
  maxSqlBytes: 10000, maxParameters: 2, maxColumns: 2,
  memoryBytes: 134217728, threads: 1, maxChunkRows: 17, maxChunkBytes: 8192};

test('bounded transport batches preserve ordered rows and cumulative accounting', async () => {
  const rows = [];
  let chunks = 0;
  const result = await withComputeDatabase(limits, async session => {
    await session.command('SELECT CAST(i AS INTEGER) AS id FROM range(100) r(i) ORDER BY i', [], chunk => {
      assert(chunk.rowCount <= 17);
      chunks++;
      rows.push(...chunk.columns[0]);
    });
    assert.equal(session.usage().rows, 100);
    return session.usage();
  });
  assert.deepEqual(rows, Array.from({length: 100}, (_, index) => String(index)));
  assert(chunks >= 6);
  assert.equal(result.value.chunks, chunks);
  assert.equal(result.value.cells, 100);
});

test('split batches do not populate the chunk-wide SDK value cache', async t => {
  const getColumnVector = DuckDBDataChunk.prototype.getColumnVector;
  const seen = new WeakSet();
  let vectors = 0;
  t.mock.method(DuckDBDataChunk.prototype, 'getColumnVector', function(index) {
    const vector = getColumnVector.call(this, index);
    if (!seen.has(vector)) {
      seen.add(vector);
      vectors++;
      t.mock.method(vector, 'getItem', () => assert.fail('chunk-wide decoded value cache used'));
    }
    return vector;
  });
  const rows = [];
  await withComputeDatabase(limits, async session => {
    await session.command("SELECT 'row-' || CAST(i AS VARCHAR) AS payload FROM range(100) r(i) ORDER BY i", [], chunk => {
      assert(chunk.rowCount <= 17);
      rows.push(...chunk.columns[0]);
    });
  });
  assert(vectors > 0);
  assert.deepEqual(rows, Array.from({length: 100}, (_, index) => `row-${index}`));
});

test('oversized encoded batch is rejected before callback, without refunding work', async () => {
  let called = 0;
  let usage;
  await assert.rejects(withComputeDatabase({...limits, maxChunkBytes: 64}, async session => {
    try { await session.command("SELECT repeat('x', 100) AS payload", [], () => called++); }
    finally { usage = session.usage(); }
  }), {code: 'ChunkBytes'});
  assert.equal(called, 0);
  assert.equal(usage.rows, 1);
  assert(usage.transportBytes > 0);
});

test('oversized UTF-8 values are rejected before the SDK decodes their contents', async t => {
  assertBoundedVectorRuntime();
  let decoded = 0;
  t.mock.method(DuckDBVarCharVector.prototype, 'getItem', () => { decoded++; assert.fail('oversized value decoded'); });
  for (const text of ["repeat('x', 1000000)", "repeat('é', 40)"]) {
    await assert.rejects(withComputeDatabase({...limits, maxChunkBytes: 64},
      session => session.command(`SELECT ${text} AS payload`, [], () => assert.fail('oversized batch delivered'))),
    {code: 'ChunkBytes'});
  }
  assert.equal(decoded, 0);
});

test('bounded vector adaptation refuses unknown layouts before reading a value', () => {
  const vector = new DuckDBVarCharVector(new DataView(new ArrayBuffer(15)),
    {itemValid: () => true}, undefined, 0, 1);
  assert.throws(() => boundedVectorItem(vector, 0, {id: 'VARCHAR'}, 100),
    {code: 'UnsupportedBoundedVectorRuntime'});
});

test('unknown SDK versions and oversized native chunks cannot use bounded admission', async t => {
  const version = sdk.version;
  try {
    sdk.version = 'unreviewed';
    assert.throws(assertBoundedVectorRuntime, {code: 'UnsupportedBoundedVectorRuntime'});
  } finally { sdk.version = version; }
  const original = Object.getOwnPropertyDescriptor(DuckDBDataChunk.prototype, 'rowCount');
  t.mock.method(DuckDBDataChunk.prototype, 'getColumnVector', () => assert.fail('oversized native vector allocated'));
  Object.defineProperty(DuckDBDataChunk.prototype, 'rowCount', {...original,
    get() { return original.get.call(this) === 0 ? 0 : 2049; }});
  try {
    await assert.rejects(withComputeDatabase(limits, session =>
      session.command('SELECT 1 AS n', [], () => assert.fail('oversized chunk delivered'))),
    {code: 'NativeChunkRows'});
  } finally { Object.defineProperty(DuckDBDataChunk.prototype, 'rowCount', original); }
});

test('bounded parameters and metadata fail before native parameter binding or delivery', async t => {
  t.mock.method(DuckDBPreparedStatement.prototype, 'bindVarchar', () => assert.fail('oversized parameter bound'));
  let used = 0;
  await assert.rejects(withComputeDatabase({...limits, maxChunkBytes: 64}, session =>
    session.command('SELECT ? AS v', [{type: {id: 'VARCHAR'}, value: 'x'.repeat(10000)}], () => used++)),
  {code: 'ChunkBytes'});
  await assert.rejects(withComputeDatabase({...limits, maxChunkBytes: 64}, session =>
    session.command('SELECT 1 AS a_very_long_output_name, 2 AS another_long_output_name', [], () => used++)),
  {code: 'ChunkBytes'});
  assert.equal(used, 0);
});

test('bounded VARCHAR slices preserve null, inline, indirect and Unicode values', async () => {
  const actual = [];
  await withComputeDatabase(limits, session => session.command(
    "SELECT unnest([NULL, '', 'abcdefghijkl', 'abcdefghijklm', '日本語', '🙂']) AS payload", [],
    chunk => actual.push(...chunk.columns[0])));
  assert.deepEqual(actual, [null, '', 'abcdefghijkl', 'abcdefghijklm', '日本語', '🙂']);
});

test('chunk limits are validated and snapshotted by the connector configuration', () => {
  for (const value of [0, -1, 1.5, Infinity]) {
    assert.throws(() => validateLimits({...limits, maxChunkRows: value}), {code: 'InvalidLimits'});
    assert.throws(() => validateLimits({...limits, maxChunkBytes: value}), {code: 'InvalidLimits'});
  }
  const supplied = {...limits};
  const prepared = prepareDuckDBStrategyConfiguration({transportLimits: supplied,
    importLimits: {maxRows: 100, maxCells: 100}});
  supplied.maxChunkRows = 9999;
  supplied.maxChunkBytes = 999999;
  assert.equal(preparedStrategyConfiguration(prepared).transportLimits.maxChunkRows, 17);
  assert.equal(preparedStrategyConfiguration(prepared).transportLimits.maxChunkBytes, 8192);
});

test('cancellation between split batches stops delivery without refunding fetched rows', async () => {
  const controller = new AbortController();
  let calls = 0, usage;
  await assert.rejects(withComputeDatabase(limits, async session => {
    try {
      await session.command('SELECT CAST(i AS INTEGER) AS id FROM range(100) r(i)', [], () => {
        calls++;
        controller.abort();
      });
    } finally { usage = session.usage(); }
  }, controller.signal), {code: 'Cancelled'});
  assert.equal(calls, 1);
  assert.equal(usage.rows, 100);
  assert.equal(usage.chunks, 1);
});
