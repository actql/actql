import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';

const root = fileURLToPath(new URL('../../..', import.meta.url));

test('main canonical group vectors agree with Local and real DuckDB ordering', async () => {
  const corpus = JSON.parse(await readFile(new URL('../../../portability/corpus/group-canonical-order.json', import.meta.url), 'utf8'));
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/group_canonical_corpus_wbtest.mbt', '--deny-warn',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const queries = stdout.split('\n').filter(line => line.startsWith('ACTQL_GROUP_CORPUS '))
    .map(line => JSON.parse(line.slice('ACTQL_GROUP_CORPUS '.length)));
  assert.deepEqual(queries.map(q => q.id), corpus.cases.map(c => c.id));
  for (const c of corpus.cases) {
    const sql = queries.find(q => q.id === c.id).sql;
    const names = c.by.length ? [...c.by].sort() : ['x'];
    const expected = c.expected_keys.map((key, i) => ({
      ...Object.fromEntries(c.by.map((name, j) => [name, key[j]])), n: c.expected_counts[i],
    }));
    const db = await DuckDBInstance.create(':memory:');
    const connection = await db.connect();
    try {
      await connection.run(`CREATE TABLE fixed(${names.map(n => `"${n}" DOUBLE`).join(',')})`);
      for (const rows of [c.rows, [...c.rows].reverse()]) {
        await connection.run('DELETE FROM fixed');
        if (rows.length) {
          // Restricted independently authored numeric/NULL vectors, not user SQL.
          for (const row of rows) for (const name of names) {
            assert(row[name] === null || (typeof row[name] === 'number' && Number.isFinite(row[name])));
          }
          await connection.run(`INSERT INTO fixed VALUES ${rows.map(row =>
            `(${names.map(n => row[n] === null ? 'NULL' : String(row[n])).join(',')})`).join(',')}`);
        }
        assert.deepEqual((await connection.runAndReadAll(sql)).getRowObjects(), expected, c.id);
      }
    } finally { connection.closeSync(); db.closeSync(); }
  }
});
