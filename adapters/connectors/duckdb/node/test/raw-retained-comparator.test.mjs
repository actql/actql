import test from 'node:test';
import assert from 'node:assert/strict';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';
import {runRawRetainedComparator} from '../bench/raw-retained-comparator.mjs';

test('raw comparison preserves every stage and verifies independent output for all nine shapes', async () => {
  for (const workload of workloads) for (const layout of ['narrow', 'numeric-64', 'text-1024']) {
    const fixture = retainedCase(workload, layout, 100);
    const db = await DuckDBInstance.create(':memory:');
    const connection = await db.connect();
    try {
      await connection.run(fixture.createSourceSql);
      const report = await runRawRetainedComparator(connection, workload, layout, 100);
      assert.equal(report.comparator, 'direct-duckdb');
      assert.equal(report.scope, 'raw-engine-diagnostic');
      assert.equal(report.status, 'completed');
      assert.equal(report.materializations, workload === workloads[1] ? 5 : 4);
      assert.deepEqual(report.stages.map(stage => stage.stage), workload === workloads[1]
        ? ['capture', 'a', 'b', 'join', 'count'] : ['capture', 'a', 'b', 'c']);
      for (const key of ['executionMs', 'verificationMs', 'cleanupMs']) {
        assert(Number.isFinite(report[key]) && report[key] >= 0);
      }
      // Transaction-local outputs are cleaned up; the immutable source remains.
      const tables = (await connection.runAndReadAll('SHOW TABLES')).getRowObjects();
      assert.deepEqual(tables, [{name: 'records'}]);
    } finally { connection.closeSync(); db.closeSync(); }
  }
});

test('raw comparison rejects cancellation and incorrect data without publishing timings', async () => {
  const fixture = retainedCase(workloads[2], 'narrow', 100);
  const db = await DuckDBInstance.create(':memory:');
  const connection = await db.connect();
  try {
    await connection.run(fixture.createSourceSql);
    const abort = new AbortController();
    abort.abort();
    await assert.rejects(runRawRetainedComparator(connection, workloads[2], 'narrow', 100, abort.signal),
      {name: 'AbortError'});
    await connection.run('UPDATE records SET payload = -1 WHERE id = 50');
    await assert.rejects(runRawRetainedComparator(connection, workloads[2], 'narrow', 100),
      {code: 'ERR_ASSERTION'});
    assert.deepEqual((await connection.runAndReadAll('SHOW TABLES')).getRowObjects(), [{name: 'records'}]);
  } finally { connection.closeSync(); db.closeSync(); }
});

test('cancellation after native work settles rolls back before another stage can start', async () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const db = await DuckDBInstance.create(':memory:');
  const connection = await db.connect();
  const abort = new AbortController();
  const calls = [];
  try {
    await connection.run(fixture.createSourceSql);
    const observed = {
      interrupt: () => connection.interrupt(),
      async run(sql) {
        calls.push(sql);
        const result = await connection.run(sql);
        if (sql.startsWith('CREATE TEMP')) abort.abort();
        return result;
      },
    };
    await assert.rejects(runRawRetainedComparator(observed, workloads[0], 'narrow', 100, abort.signal),
      {name: 'AbortError'});
    assert.equal(calls.filter(sql => sql.startsWith('CREATE TEMP')).length, 1);
    assert.equal(calls.at(-1), 'ROLLBACK');
    assert.deepEqual((await connection.runAndReadAll('SHOW TABLES')).getRowObjects(), [{name: 'records'}]);
  } finally { connection.closeSync(); db.closeSync(); }
});
