// Benchmark-only raw engine reference. Never an ActQL completion issuer or an
// equivalent-obligations comparator. Call with a dedicated, prepared connection.
import assert from 'node:assert/strict';
import {retainedCase, workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';

export async function runRawRetainedComparator(connection, workload, layout, rows, signal) {
  const fixture = retainedCase(workload, layout, rows);
  const selected = workload === workloads[2] ? fixture.fields.join(', ') : 'id';
  const stages = [
    ['capture', `SELECT ${selected} FROM records WHERE id > ${fixture.minimum} ORDER BY rowid`],
    ['a', `SELECT ${selected} FROM bench_capture WHERE id >= 0 ORDER BY rowid`],
    ['b', `SELECT ${selected} FROM bench_capture WHERE id >= 0 ORDER BY rowid`],
    ...(workload === workloads[1] ? [
      ['join', 'SELECT l.id FROM bench_a l INNER JOIN bench_b r ON l.id = r.id ORDER BY l.rowid, r.rowid'],
      ['count', 'SELECT CAST(COUNT(*) AS DOUBLE) AS n, CAST(COUNT(id) AS DOUBLE) AS present FROM bench_join'],
    ] : [['c', `SELECT ${selected} FROM bench_a WHERE id >= 0 ORDER BY rowid`]]),
  ];
  signal?.throwIfAborted();
  let timedOut = false;
  const interrupt = () => connection.interrupt();
  const timer = setTimeout(() => { timedOut = true; interrupt(); }, fixture.limits.timeoutMs);
  signal?.addEventListener('abort', interrupt, {once: true});
  const check = () => {
    signal?.throwIfAborted();
    if (timedOut) throw Error('RawComparatorTimeout');
  };
  let transaction = false;
  let report;
  try {
    const started = performance.now();
    await connection.run('BEGIN TRANSACTION');
    transaction = true;
    const timings = [];
    for (const [stage, query] of stages) {
      check();
      const before = performance.now();
      await connection.run(`CREATE TEMP TABLE bench_${stage} AS ${query}`);
      check();
      timings.push(Object.freeze({stage, milliseconds: performance.now() - before}));
    }
    const executionMs = performance.now() - started;
    // Verification is outside raw compute timing, but cannot be skipped or
    // converted to a successful timing sample after a failure. Read in chunks.
    const verificationStarted = performance.now();
    for (const [stage] of stages) {
      check();
      const count = await connection.runAndReadAll(`SELECT COUNT(*) AS n FROM bench_${stage}`);
      assert.equal(count.getRowObjects()[0].n, BigInt(fixture.cardinalities[stage]), `${fixture.id}/${stage}`);
    }
    const result = await connection.stream(`SELECT * FROM bench_${stages.at(-1)[0]} ORDER BY rowid`);
    const names = result.columnNames();
    let observedRows = 0;
    for await (const chunk of result) {
      check();
      for (const row of chunk.getRowObjects(names)) {
        assert.deepEqual(row, fixture.outputRow(observedRows++), fixture.id);
      }
    }
    assert.equal(observedRows, workload === workloads[1] ? 1 : fixture.cardinalities.capture);
    check();
    report = {comparator: 'direct-duckdb', scope: 'raw-engine-diagnostic', caseId: fixture.id,
      status: 'completed', executionMs, verificationMs: performance.now() - verificationStarted,
      stages: Object.freeze(timings), materializations: stages.length, observedRows,
      excludes: Object.freeze(['source-setup', 'process-start', 'ActQL-validation', 'logical-identities',
        'independent-holding', 'admission', 'logical-budget-checks'])};
  } finally {
    // Settle the in-flight native operation before cleanup; no Promise.race
    // abandons an active query. Rollback failure must prevent a completed sample.
    clearTimeout(timer);
    signal?.removeEventListener('abort', interrupt);
    if (transaction) {
      const cleanupStarted = performance.now();
      await connection.run('ROLLBACK');
      if (report) report.cleanupMs = performance.now() - cleanupStarted;
    }
  }
  return Object.freeze(report);
}
