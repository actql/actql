import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, retainedMatrix, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {benchmarkEnvironment} from '../../../benchmarks/retained-results/environment.mjs';
import {selectReadinessCases} from '../../../benchmarks/retained-results/selection.mjs';
import {createManagedExampleHost} from '../examples/managed-host.mjs';
import {createManagedProcessHost} from '../../host-node/process-capacity.mjs';

// Correctness smoke, not a performance sample. The data, Program and expected
// identity are the same independent fixtures used by the registered experiment.
test('retained benchmark shapes execute in a managed process and retain exact result identities', async () => {
  const matrix = process.env.ACTQL_RETAINED_CASES ?? 'smoke';
  assert(['smoke', 'registered'].includes(matrix), 'ACTQL_RETAINED_CASES must be smoke or registered');
  const root = new URL('../../../', import.meta.url);
  for (const target of ['connectors/duckdb/host_node', 'retained_host_bridge',
    'process_host_bridge', 'connectors_builtin_node', 'physical_strategy_example']) {
    await promisify(execFile)('moon', ['build', '--target', 'js', '--release', `src/${target}`],
      {cwd: fileURLToPath(root)});
  }
  const text = path => readFile(new URL(path, root), 'utf8');
  const contracts = {
    adoptedText: await text('adapters/duckdb-node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
  const smoke = [100, 1000].flatMap(rows => workloads.flatMap(workload =>
    ['narrow', 'numeric-64', 'text-1024'].map(layout => retainedCase(workload, layout, rows))));
  smoke.push(...workloads.flatMap(workload => ['narrow', 'numeric-64', 'text-1024']
    .map(layout => retainedCase(workload, layout, 10000))));
  const {cases, scope} = selectReadinessCases(matrix === 'registered' ? retainedMatrix() : smoke,
    process.env.ACTQL_RETAINED_CASE);
  console.log('retained-benchmark-scope', JSON.stringify({matrix, scope, caseCount: cases.length}));
  for (const fixture of cases) {
    const started = performance.now();
    console.log('retained-benchmark', JSON.stringify({phase: 'starting', matrix, case: fixture.id}));
    const {workload} = fixture;
    const directory = await mkdtemp(join(tmpdir(), 'actql-retained-benchmark-'));
    let result;
    try {
      const database = join(directory, 'source.duckdb');
      const db = await DuckDBInstance.create(database);
      const connection = await db.connect();
      try { await connection.run(fixture.createSourceSql); }
      finally { connection.closeSync(); db.closeSync(); }
      const l = fixture.limits;
      const environment = benchmarkEnvironment(fixture);
      const taskCount = workload === workloads[1] ? 4 : 3;
      const computeTransfer = 3 * l.representationBytes +
        2 * l.intermediateRows * (128 * l.maxColumns + 256) + 8192;
      // Join preflight charges the supplied validation work before input scans;
      // it is additional to graph/search planning, not a free execution check.
      const limits = {planning_work: 100000 + l.cumulativeGuardWork, attempts: 12, holdings: 12,
        transfer_bytes: BigInt(3 * l.representationBytes + (taskCount + 1) * computeTransfer),
        retained_bytes: 1073741824n, execution_bytes: 4294967296n};
      const host = await createManagedExampleHost(limits);
      const batchBytes = Math.min(l.batchBytes, l.representationBytes);
      const input = {...contracts, database,
        environmentText: environment.text, environmentCid: environment.cid,
        programText: JSON.stringify(fixture.program()), parameterText: JSON.stringify({minimum: fixture.minimum}),
        nativeMilliseconds: '1', localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0',
        retainedWorkMilliseconds: '0',
        dataProfile: {source_rows: l.sourceRows, task_rows: l.intermediateRows, columns: l.maxColumns,
          value_bytes: l.maxValueBytes, wire_bytes: l.representationBytes,
          value_nodes: l.cumulativeValueNodes, text_bytes: l.cumulativeValueTextBytes,
          work: l.cumulativeGuardWork, entries: l.cumulativeValueNodes, batch_bytes: batchBytes},
        retainedOutput: {parentDirectory: directory, maxFrameBytes: batchBytes,
          wire: {max_bytes: l.representationBytes, max_nodes: l.cumulativeValueNodes, max_depth: 64,
            max_columns: l.maxColumns, max_order_work: l.cumulativeGuardWork}},
      };
      result = await host.run(input, {run: fixture.id, childLimits: {...limits, attempts: 10}},
        AbortSignal.timeout(l.timeoutMs)).catch(error => {
        throw new Error(`${fixture.id}: ${error.message} (${error.examplePhase}): ${JSON.stringify(error.cause)}`, {cause: error});
      });
      assert.equal(result.report.status, 'host-tasks-completed', `${fixture.id}: ${JSON.stringify(result.report)}`);
      const final = result.completion(workload === workloads[1] ? 4 : 3);
      assert.equal(final.descriptor.rows, fixture.identity().rows, fixture.id);
      assert.equal(final.descriptor.rows_cid, fixture.identity().rowsCid, fixture.id);
      assert.equal(final.retained, true);
      assert.equal(result.process().exited, true);
      assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
      if (workload === workloads[2] && fixture.layout === 'numeric-64') {
        const reading = result.prepareReader(1);
        const readerHost = await createManagedProcessHost(limits);
        const fresh = await readerHost.start({
          entry: new URL('../examples/managed-reader.mjs', import.meta.url), run: fixture.id,
          frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
          maxRequests: 1, maxHostCalls: 3, graceMs: 1000, startupMs: 10000,
          hostService: reading.service,
        }, {retainedBytes: 0n, executionBytes: limits.execution_bytes,
          childLimits: {...limits, retained_bytes: 0n, holdings: 0, attempts: 1}});
        reading.observe(fresh);
        let expectedReadBytes;
        try {
          const verified = await fresh.request({task: 1, consumer: {task: 3, port: 0},
            application: {...input, database: `${database}.must-not-be-read`}}, AbortSignal.timeout(l.timeoutMs))
            .catch(error => { throw new Error(`${fixture.id}: readmission ${JSON.stringify(error.cause)}`, {cause: error}); });
          assert.equal(verified.kind, 'completion-readmitted', fixture.id);
          assert.equal(verified.rows_cid, fixture.identity().rowsCid, fixture.id);
          assert.equal(verified.rows, fixture.rows, fixture.id);
          assert.equal(verified.producer_bound, true, fixture.id);
          assert.equal(verified.producer_read_bytes, verified.bytes, fixture.id);
          expectedReadBytes = BigInt(verified.bytes) * 2n;
        } finally { await fresh.close(); }
        assert.equal(reading.cleanupHandle.status().pending, false, fixture.id);
        assert.equal(readerHost.usage().reserved_execution_bytes, 0n, fixture.id);
        assert.equal(readerHost.usage().transferred_bytes, expectedReadBytes, fixture.id);
        assert.equal(result.completion(1).retained, true, fixture.id);
      }
      await result.close();
      assert.equal(result.cleanupHandle.status().pending, false);
      assert.equal(result.completion(workload === workloads[1] ? 4 : 3).retained, false);
      assert.deepEqual(await readdir(directory), ['source.duckdb']);
      // Diagnostic wall time includes fixture setup, readmission and cleanup.
      // It is not a sample for the preregistered performance comparison.
      console.log('retained-benchmark', JSON.stringify({phase: 'verified', matrix, case: fixture.id,
        diagnosticMilliseconds: performance.now() - started,
        tasks: result.report.completed}));
    } catch (error) {
      console.log('retained-benchmark', JSON.stringify({phase: 'failed', matrix, case: fixture.id,
        diagnosticMilliseconds: performance.now() - started, message: error?.message ?? String(error)}));
      throw error;
    } finally {
      await result?.close();
      await rm(directory, {recursive: true, force: true});
    }
  }
});
