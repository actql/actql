import test from 'node:test';
import assert from 'node:assert/strict';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';

test('retained benchmark source generator and cardinalities agree with actual DuckDB', async () => {
  for (const workload of workloads) for (const layout of ['narrow', 'numeric-64', 'text-1024']) {
    const fixture = retainedCase(workload, layout, 100);
    const db = await DuckDBInstance.create(':memory:');
    const connection = await db.connect();
    try {
      await connection.run(fixture.createSourceSql);
      const rows = (await connection.runAndReadAll('SELECT * FROM records ORDER BY rowid')).getRowObjects();
      assert.deepEqual(rows, Array.from({length: 100}, (_, index) => fixture.sourceRow(index)), fixture.id);
      const sql = workload === workloads[1]
        ? 'SELECT CAST(COUNT(*) AS DOUBLE) AS n, CAST(COUNT(l.id) AS DOUBLE) AS present FROM records l INNER JOIN records r ON l.id = r.id'
        : workload === workloads[0]
        ? 'SELECT id FROM records WHERE id > 97 ORDER BY rowid'
        : 'SELECT * FROM records ORDER BY rowid';
      const result = (await connection.runAndReadAll(sql)).getRowObjects();
      assert.deepEqual(result, Array.from({length: fixture.identity().rows}, (_, index) => fixture.outputRow(index)), fixture.id);
    } finally {
      connection.closeSync();
      db.closeSync();
    }
  }
});
