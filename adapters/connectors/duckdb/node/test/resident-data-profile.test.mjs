import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';
import {managedCaseConfiguration} from '../../../../../benchmarks/retained-results/managed-configuration.mjs';
import {createManagedExampleHost} from '../examples/managed-host.mjs';
import {prepareExampleText} from '../examples/physical-strategy.mjs';
import {runCapturedStrategy} from '../../../../host-node/entry.mjs';
import {inspect} from 'node:util';

test('explicit data profiles select resident reuse with independent retained output', async () => {
  const root = new URL('../../../../../', import.meta.url);
  for (const target of ['connectors/duckdb/host_node', 'retained_host_bridge',
    'process_host_bridge', 'connectors_builtin_node', 'physical_strategy_example',
    'physical_task_manifest_example']) {
    await promisify(execFile)('moon', ['build', '--target', 'js', '--release', `src/${target}`],
      {cwd: fileURLToPath(root)});
  }
  const text = path => readFile(new URL(path, root), 'utf8');
  const contracts = {adoptedText: await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json')};
  const directory = await mkdtemp(join(tmpdir(), 'actql-resident-profile-'));
  try {
    const cases = workloads.map(workload => retainedCase(workload, 'narrow', 1000));
    cases.push(retainedCase(workloads[2], 'numeric-64', 1000),
      retainedCase(workloads[2], 'text-1024', 1000),
      retainedCase(workloads[2], 'numeric-64', 10000));
    for (const [index, fixture] of cases.entries()) {
      const database = join(directory, `source-${index}.duckdb`);
      await promisify(execFile)(process.execPath,
        [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
          database, fixture.workload, fixture.layout, String(fixture.rows)]);
      const config = managedCaseConfiguration(fixture, contracts, database, directory);
      // Resident copies use the separately admitted shared DB allocation.
      // Cumulative task value nodes do not consume that allocation.
      const host = await createManagedExampleHost(config.limits);
      if (fixture.layout === 'text-1024') {
        // Also cover the non-process installed assembly: its offer must cover
        // both the long-text DB copy and independent completion metadata.
        const plan = await prepareExampleText({...config.input, localExportWorkMilliseconds: undefined,
          resident: true, nativeMilliseconds: '20'}, config.childLimits);
        const opened = await plan.open();
        let execution;
        try {
          execution = await runCapturedStrategy(opened.setup, opened.configurations);
          assert.equal(execution.status, 'host-tasks-completed', inspect(execution.failure, {depth: 12}));
        } finally { await execution?.close(); await opened.close(); }
      }
      let result;
      try {
        result = await host.run({...config.input, resident: true, nativeMilliseconds: '20'},
          {run: fixture.id, childLimits: config.childLimits}, AbortSignal.timeout(config.timeoutMs));
        assert.equal(result.report.status, 'host-tasks-completed', JSON.stringify(result.report));
        assert.deepEqual(result.report.completed.map(task => task.realization),
          Array(config.finalTask).fill('duckdb-resident'), fixture.id);
        assert.equal(result.completion(config.finalTask).descriptor.rows_cid, fixture.identity().rowsCid);
        assert.equal(result.process().exited, true);
        assert.equal(result.completion(config.finalTask).retained, true);
        assert.deepEqual(result.report.completed.map(task => task.preparation.imports.length),
          [1, ...Array(config.finalTask - 1).fill(0)]);
        assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
        assert(result.report.completed.every(task =>
          task.phases.directInputScans + task.phases.reusedInputValues >= 1));
        assert(result.report.completed.every(task =>
          task.phases.reusedInputIdentities ===
            task.phases.directInputScans + task.phases.reusedInputValues));
        if (fixture.workload === workloads[2] && fixture.layout === 'numeric-64') {
          const filtered = result.report.completed[1].phases;
          assert.equal(filtered.reusedInputValues, 1);
          assert.equal(filtered.demandColumnScans, 1);
          assert.equal(filtered.directInputScans, 0);
          assert.equal(filtered.nativeSemanticCells, fixture.rows * 65);
        }
      } finally {
        await result?.close();
        if (result) assert.equal(result.cleanupHandle.status().pending, false);
      }
      assert((await readdir(directory)).every(name => /^source-\d\.duckdb$/.test(name)));
      if (fixture.workload === workloads[2] && fixture.layout === 'narrow') {
        // Acquisition and root import cannot borrow a third attempt to start
        // Compute. A cheap resident estimate never overrides the Run ceiling.
        const limited = await createManagedExampleHost(config.limits);
        let rejected;
        try {
          rejected = await limited.run({...config.input, resident: true, nativeMilliseconds: '20'},
            {run: `${fixture.id}/attempt-limit`, childLimits: {...config.childLimits, attempts: 2}},
            AbortSignal.timeout(config.timeoutMs));
          assert.equal(rejected.report.status, 'host-tasks-failed');
          assert.deepEqual(rejected.report.completed, []);
          assert(BigInt(rejected.report.explanation.ledger.attempts) <= 2n);
          assert.equal(rejected.completion(1), undefined);
          assert.equal(rejected.process().exited, true);
          assert.equal(limited.usage().reserved_execution_bytes, 0n);
        } finally {
          await rejected?.close();
          if (rejected) {
            assert.equal(rejected.cleanupHandle.status().pending, false);
            assert.equal(rejected.storageUsage().holdings, 0);
          }
        }
        assert((await readdir(directory)).every(name => /^source-\d\.duckdb$/.test(name)));
      }
    }
  } finally { await rm(directory, {recursive: true, force: true}); }
});
