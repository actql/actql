import test from 'node:test';
import assert from 'node:assert/strict';
import {createImportBatch} from '../import-batch.mjs';
import {runFixedCompute, releaseFixedCompute} from '../fixed-compute.mjs';

const limits = {maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 1000, maxParameters: 8, maxColumns: 2, maxChunkRows: 4, maxChunkBytes: 4096,
  memoryBytes: 128 * 1024 * 1024, threads: 1};
const sql = rows => ({rows, sql: `INSERT INTO imported VALUES ${Array(rows).fill('(?)').join(', ')}`});
const parameter = value => ({type: {id: 'VARCHAR'}, value});

test('import batches snapshot rows and bound both bytes and row count', async () => {
  const written = [];
  const batch = createImportBatch(1, 2, limits, sql, async (_sql, parameters) => {
    written.push(parameters.map(value => value.value));
  });
  const row = parameter('original');
  await batch.append([row]);
  row.value = 'mutated';
  await batch.append([parameter(null)]);
  await batch.append([parameter('last')]);
  await batch.finish();
  assert.deepEqual(written, [['original', null], ['last']]);
  await assert.rejects(batch.append([parameter('late')]), {code: 'ImportBatchUnavailable'});

  const narrow = [];
  const bounded = createImportBatch(1, 4, {...limits, maxChunkBytes: 90}, sql,
    async (_sql, parameters) => narrow.push(parameters.length));
  for (let i = 0; i < 3; i++) await bounded.append([parameter('日本語')]);
  await bounded.finish();
  assert.deepEqual(narrow, [1, 1, 1]);
  const oversized = createImportBatch(1, 4, {...limits, maxChunkBytes: 90}, sql, () => assert.fail());
  await assert.rejects(oversized.append([parameter('x'.repeat(100))]), {code: 'ChunkBytes'});
});

test('failed or cancelled batch does not retry or accept further rows', async () => {
  let writes = 0;
  const failed = createImportBatch(1, 2, limits, sql, async () => { writes++; throw Error('native failure'); });
  await failed.append([parameter('1')]);
  await assert.rejects(failed.append([parameter('2')]), /native failure/);
  await assert.rejects(failed.finish(), {code: 'ImportBatchUnavailable'});
  assert.equal(writes, 1);
  const abort = new AbortController();
  const cancelled = createImportBatch(1, 2, limits, sql, async () => { writes++; abort.abort(); }, abort.signal);
  await cancelled.append([parameter('1')]);
  await assert.rejects(cancelled.append([parameter('2')]), {name: 'AbortError'});
  await assert.rejects(cancelled.append([parameter('3')]), {code: 'ImportBatchUnavailable'});
  assert.equal(writes, 2);
});

test('real batched fixed import preserves duplicate and NULL order with fewer native commands', async () => {
  const values = ['3', null, '3', '1', '2', null, '1', '3', '0'];
  const makePort = batched => ({
    importCount: () => 1, rowCount: () => values.length, columnCount: () => 1,
    createSql: () => 'CREATE TEMP TABLE imported(i BIGINT)', insertSql: () => sql(1).sql,
    ...(batched ? {insertBatch: (_input, rows) => sql(rows)} : {}),
    parameter: (_input, row) => ({type: {id: 'BIGINT'}, value: values[row]}),
    querySql: () => 'SELECT i FROM imported', queryParameters: () => [],
  });
  const outputs = [];
  for (const batched of [false, true]) {
    const got = [];
    const result = await runFixedCompute(makePort(batched), limits, {maxRows: 9, maxCells: 9},
      chunk => got.push(...chunk.columns[0]));
    try {
      assert.deepEqual(got, values);
      assert.equal(result.value.importedRows, 9);
      assert.equal(result.value.importedCells, 9);
      assert.equal(result.usage.statements, batched ? 5 : 11);
      assert.equal(result.value.diagnostics.inputs[0].batchRows, batched ? 4 : 1);
      outputs.push(result.usage);
    } finally { releaseFixedCompute(result); }
  }
  assert(outputs[1].transportBytes < outputs[0].transportBytes);
  let created = 0;
  const bad = {...makePort(true), insertBatch: () => ({rows: 5, sql: sql(5).sql}),
    createSql: () => { created++; return ''; }};
  await assert.rejects(runFixedCompute(bad, limits, {maxRows: 9, maxCells: 9}, () => {}), {code: 'InvalidImportBatch'});
  assert.equal(created, 0);
});

test('partial streamed batch is never queried after a receiving failure', async () => {
  let queried = 0;
  const port = {
    importCount: () => 1, rowCount: () => 4, columnCount: () => 1,
    createSql: () => 'CREATE TEMP TABLE imported(i BIGINT)', insertSql: () => sql(1).sql,
    insertBatch: (_input, rows) => sql(rows),
    async consumeInput(_input, accept) {
      await accept([{type: {id: 'BIGINT'}, value: '1'}]);
      throw Error('retained input failed validation');
    },
    parameter: () => assert.fail('no row-storage fallback'),
    querySql: () => { queried++; return 'SELECT * FROM imported'; }, queryParameters: () => [],
  };
  await assert.rejects(runFixedCompute(port, limits, {maxRows: 4, maxCells: 4}, () => assert.fail()),
    /retained input failed validation/);
  assert.equal(queried, 0);
  await assert.rejects(runFixedCompute(port, limits, {maxRows: 4, maxCells: 4}, () => {}),
    {code: 'AttemptAlreadyStarted'});
});
