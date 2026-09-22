import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));

test('nullable comparisons agree between Local and real DuckDB', async () => {
  const {stdout} = await promisify(execFile)('moon', [
    'test', '--target', 'js',
    'src/query_integration/filter_null_differential_wbtest.mbt', '--deny-warn',
  ], {cwd: root, maxBuffer: 2 * 1024 * 1024});
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const fixtures = stdout.split('\n')
    .filter(line => line.startsWith('ACTQL_FILTER_NULL '))
    .map(line => JSON.parse(line.slice('ACTQL_FILTER_NULL '.length)));
  assert.equal(fixtures.length, 8);
  const expected = new Map([
    ['=', [0]], ['<>', [-1, 1]], ['<=', [-1, 0]], ['>=', [0, 1]],
  ]);
  const db = await DuckDBInstance.create(':memory:');
  const connection = await db.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run(
      'INSERT INTO records VALUES (0,NULL),(1,-1),(2,0),(3,1)',
    );
    for (const fixture of fixtures) {
      const statement = await connection.prepare(fixture.sql);
      if (fixture.nullParameter) statement.bindNull(1);
      else statement.bindDouble(1, 0);
      const rows = (await statement.runAndReadAll()).getRowObjects();
      assert.deepEqual(
        rows.map(row => row.amount),
        fixture.nullParameter ? [] : expected.get(fixture.operator),
      );
    }
  } finally {
    connection.closeSync();
    db.closeSync();
  }
});
