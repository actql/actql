import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, retainedMatrix, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {managedCaseConfiguration} from '../../../benchmarks/retained-results/managed-configuration.mjs';
import {selectReadinessCases} from '../../../benchmarks/retained-results/selection.mjs';
import {sampleControllerMemory} from '../../../benchmarks/retained-results/controller-memory.mjs';
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
      // Source generation is outside execution measurement and outside the
      // controller allocator. Await actual generator exit before starting work.
      await promisify(execFile)(process.execPath,
        [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
          database, fixture.workload, fixture.layout, String(fixture.rows)],
        {timeout: fixture.limits.timeoutMs, maxBuffer: 65536});
      const l = fixture.limits;
      const {limits, input, childLimits} = managedCaseConfiguration(fixture, contracts, database, directory);
      const host = await createManagedExampleHost(limits);
      const memory = sampleControllerMemory();
      let controlMemory;
      try {
        result = await host.run(input, {run: fixture.id, childLimits},
          AbortSignal.timeout(l.timeoutMs)).catch(error => {
          throw new Error(`${fixture.id}: ${error.message} (${error.examplePhase}): ${JSON.stringify(error.cause)}`, {cause: error});
        });
      } finally { controlMemory = memory.stop(); }
      assert.equal(controlMemory.status, 'observed', 'memory sampling must not silently fail');
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
        controlTransport: result.process().transport,
        controlMemory,
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
