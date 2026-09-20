import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { runFixedCompute, matchesFixedCompute, releaseFixedCompute } from '../fixed-compute.mjs';

const limits = Object.freeze({
  maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 20,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});
const root = fileURLToPath(new URL('../../../../..', import.meta.url));

test('two fixed imports validate both row ceilings and one cumulative cell budget before SQL', async () => {
  let sqlReads = 0;
  const values = [['3ff0000000000000'], ['3ff0000000000000', '4000000000000000']];
  const port = {
    importCount: () => 2,
    rowCount: input => values[input].length,
    columnCount: () => 1,
    createSql: input => { sqlReads++; return `CREATE TEMP TABLE i${input}(x DOUBLE)`; },
    insertSql: input => `INSERT INTO i${input} VALUES (?)`,
    parameter: (input, row, column) => {
      assert.equal(column, 0);
      return { type: { id: 'DOUBLE' }, value: values[input][row] };
    },
    querySql: () => 'SELECT i0.x FROM i0 INNER JOIN i1 ON i0.x=i1.x',
    queryParameters: () => [],
  };
  await assert.rejects(runFixedCompute({ ...port }, limits, { maxRows: 1, maxCells: 3 }, () => {}),
    { code: 'ImportRows' }); // Only the second input exceeds the row ceiling.
  await assert.rejects(runFixedCompute({ ...port }, limits, { maxRows: 2, maxCells: 2 }, () => {}),
    { code: 'ImportCells' });
  assert.equal(sqlReads, 0);
  const chunks = [];
  const consume = chunk => chunks.push(chunk);
  const result = await runFixedCompute(port, limits, { maxRows: 2, maxCells: 3 }, consume);
  try {
    assert.equal(result.value.importedRows, 3);
    assert.equal(result.value.importedCells, 3);
    assert.equal(result.usage.statements, 6); // Two creates, three inserts, one query.
    assert.deepEqual(chunks.flatMap(chunk => chunk.columns[0]), ['3ff0000000000000']);
    assert.equal(matchesFixedCompute(result, port, consume), true);
  } finally { releaseFixedCompute(result); }
});

test('completed scalar imports round-trip exactly through isolated DuckDB transport', async () => {
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/duckdb_scalar_import_fixture_wbtest.mbt',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const fixtures = stdout.split('\n').filter(line => line.startsWith('ACTQL_SCALAR_IMPORT '))
    .map(line => JSON.parse(line.slice('ACTQL_SCALAR_IMPORT '.length)));
  // Fixed physical expectations, not reconstructed from emitted parameters.
  const expected = new Map([
    ['text', ['VARCHAR', '日本語']], ['boolean', ['BOOLEAN', false]],
    ['integer', ['DOUBLE', '4340000000000000']], ['number', ['DOUBLE', 'bff8000000000000']],
    ['decimal', ['DECIMAL', '99999999999999999999999999999999999999']],
    ['date', ['DATE', '11016']], ['timestamp', ['TIMESTAMP_TZ', '-1000']],
  ]);
  assert.deepEqual(fixtures.map(value => value.name), [...expected.keys()]);
  for (const fixture of fixtures) {
    for (const batched of [false, true]) {
    const port = {
      importCount: () => 1,
      rowCount: () => 3, columnCount: () => 1,
      createSql: () => fixture.create, insertSql: () => fixture.insert,
      ...(batched ? {insertBatch: (_input, rows) => ({rows,
        sql: fixture.insert + ', (?)'.repeat(rows - 1)})} : {}),
      parameter: (_input, row, column) => { assert.equal(column, 0); return fixture.rows[row]; },
      // Transport observation only; no semantic Compute completion is issued.
      querySql: () => 'SELECT "x" FROM "fixed"', queryParameters: () => [],
    };
    const chunks = [];
    const consume = chunk => chunks.push(chunk);
    const configuration = batched ? {...limits, maxChunkRows: 2, maxChunkBytes: 4096} : limits;
    const result = await runFixedCompute(port, configuration, { maxRows: 3, maxCells: 3 }, consume);
    try {
      const [type, value] = expected.get(fixture.name);
      assert.equal(matchesFixedCompute(result, port, consume), true);
      assert.equal(result.value.fields[0].type.id, type);
      if (type === 'DECIMAL') assert.deepEqual(result.value.fields[0].type,
        { id: 'DECIMAL', precision: 38, scale: 2 });
      assert.deepEqual(chunks.flatMap(chunk => chunk.columns[0]), [value, null, value], fixture.name);
      assert.equal(result.value.importedCells, 3);
      assert.equal(result.usage.statements, batched ? 4 : 5);
      assert.equal(result.usage.preparations, batched ? 4 : 3);
      assert.equal(result.value.diagnostics.inputs[0].rows, 3);
      assert(result.value.diagnostics.inputs[0].insertMilliseconds <= result.value.diagnostics.inputs[0].milliseconds);
      assert(result.value.diagnostics.queryAndReceiveMilliseconds >= 0);
    } finally { releaseFixedCompute(result); }
    assert.equal(matchesFixedCompute(result, port, consume), false);
    }
  }
});

test('MoonBit completed capture compiles and imports into isolated real DuckDB Compute', async () => {
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/duckdb_transport_fixture_wbtest.mbt',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const lines = stdout.split('\n').filter(line => line.startsWith('ACTQL_DUCKDB_FIXTURE '));
  assert.equal(lines.length, 1);
  const fixture = JSON.parse(lines[0].slice('ACTQL_DUCKDB_FIXTURE '.length));
  const port = {
    importCount: () => 1,
    rowCount: () => fixture.rows.length,
    columnCount: () => fixture.rows[0].length,
    createSql: () => fixture.create,
    insertSql: () => fixture.insert,
    parameter: (_input, row, column) => fixture.rows[row][column],
    querySql: () => fixture.query,
    queryParameters: () => fixture.parameters,
  };
  const chunks = [];
  let result;
  const consume = chunk => {
    assert.equal(matchesFixedCompute(result, port, consume), false);
    chunks.push(chunk);
  };
  result = await runFixedCompute(port, limits, { maxRows: 2, maxCells: 2 }, consume);
  assert.equal(matchesFixedCompute(result, port, consume), true);
  assert.equal(matchesFixedCompute({ ...result }, port, consume), false);
  assert.equal(matchesFixedCompute(result, { ...port }, consume), false);
  assert.equal(matchesFixedCompute(result, port, chunk => consume(chunk)), false);
  assert.deepEqual(result.value.fields, [{ name: 'id', type: { id: 'DOUBLE' } }]);
  assert.deepEqual(chunks.flatMap(chunk => chunk.columns[0]), ['4008000000000000']);
  assert.equal(result.value.importedRows, 2);
  assert.equal(result.value.importedCells, 2);
  assert.equal(result.usage.statements, 4);
  await assert.rejects(runFixedCompute(port, limits, { maxRows: 2, maxCells: 2 }, consume), { code: 'AttemptAlreadyStarted' });
  await assert.rejects(runFixedCompute({ ...port }, limits, { maxRows: 1, maxCells: 2 }, () => {}), { code: 'ImportRows' });
  await assert.rejects(runFixedCompute({ ...port }, limits, { maxRows: 2, maxCells: 1 }, () => {}), { code: 'ImportCells' });
  // A downstream rejection must settle and discard the ephemeral database.
  const failedPort = { ...port };
  await assert.rejects(runFixedCompute(failedPort, limits, { maxRows: 2, maxCells: 2 }, () => {
    throw new Error('receiver rejected chunk');
  }), /receiver rejected chunk/);
  await assert.rejects(runFixedCompute(failedPort, limits, { maxRows: 2, maxCells: 2 }, consume), { code: 'AttemptAlreadyStarted' });
  const retryPort = { ...port };
  const retryConsume = () => {};
  const retry = await runFixedCompute(retryPort, limits, { maxRows: 2, maxCells: 2 }, retryConsume);
  assert.equal(retry.value.importedRows, 2);
  assert.equal(matchesFixedCompute(retry, retryPort, retryConsume), true);
  assert.equal(matchesFixedCompute(retry, port, consume), false);
  releaseFixedCompute(result);
  assert.equal(matchesFixedCompute(result, port, consume), false);
  assert.equal(matchesFixedCompute(retry, retryPort, retryConsume), true);
  releaseFixedCompute(retry);
  assert.equal(matchesFixedCompute(retry, retryPort, retryConsume), false);
  const cancelledPort = { ...port };
  const controller = new AbortController();
  await assert.rejects(runFixedCompute(cancelledPort, limits, { maxRows: 2, maxCells: 2 }, () => {
    controller.abort();
  }, controller.signal));
  await assert.rejects(runFixedCompute(cancelledPort, limits, { maxRows: 2, maxCells: 2 }, consume), { code: 'AttemptAlreadyStarted' });
});
