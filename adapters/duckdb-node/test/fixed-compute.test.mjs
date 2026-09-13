import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { runFixedCompute } from '../fixed-compute.mjs';

const limits = Object.freeze({
  maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 20,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});
const root = fileURLToPath(new URL('../../..', import.meta.url));

test('MoonBit completed capture compiles and imports into isolated real DuckDB Compute', async () => {
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/duckdb_transport_fixture_wbtest.mbt',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const lines = stdout.split('\n').filter(line => line.startsWith('ACTQL_DUCKDB_FIXTURE '));
  assert.equal(lines.length, 1);
  const fixture = JSON.parse(lines[0].slice('ACTQL_DUCKDB_FIXTURE '.length));
  const port = {
    rowCount: () => fixture.rows.length,
    columnCount: () => fixture.rows[0].length,
    createSql: () => fixture.create,
    insertSql: () => fixture.insert,
    parameter: (row, column) => fixture.rows[row][column],
    querySql: () => fixture.query,
    queryParameters: () => fixture.parameters,
  };
  const chunks = [];
  const result = await runFixedCompute(port, limits, { maxRows: 2, maxCells: 2 }, chunk => chunks.push(chunk));
  assert.deepEqual(result.value.fields, [{ name: 'id', type: { id: 'DOUBLE' } }]);
  assert.deepEqual(chunks.flatMap(chunk => chunk.columns[0]), ['4008000000000000']);
  assert.equal(result.value.importedRows, 2);
  assert.equal(result.value.importedCells, 2);
  assert.equal(result.usage.statements, 4);
  await assert.rejects(runFixedCompute(port, limits, { maxRows: 1, maxCells: 2 }, () => {}), { code: 'ImportRows' });
  await assert.rejects(runFixedCompute(port, limits, { maxRows: 2, maxCells: 1 }, () => {}), { code: 'ImportCells' });
  // A downstream rejection must settle and discard the ephemeral database.
  await assert.rejects(runFixedCompute(port, limits, { maxRows: 2, maxCells: 2 }, () => {
    throw new Error('receiver rejected chunk');
  }), /receiver rejected chunk/);
  const retry = await runFixedCompute(port, limits, { maxRows: 2, maxCells: 2 }, () => {});
  assert.equal(retry.value.importedRows, 2);
});
