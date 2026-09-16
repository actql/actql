import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {retainedCase, retainedMatrix, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {benchmarkEnvironment} from '../../../benchmarks/retained-results/environment.mjs';
import {prepareExampleText} from '../examples/physical-strategy.mjs';

test('benchmark schemas and Programs pass the public application checker without source I/O', async () => {
  const root = new URL('../../../', import.meta.url);
  await promisify(execFile)('moon', ['build', '--target', 'js', '--release', 'src/physical_strategy_example'],
    {cwd: fileURLToPath(root)});
  const text = path => readFile(new URL(path, root), 'utf8');
  const contracts = {
    adoptedText: await text('adapters/duckdb-node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
  // Small wide cases catch shape errors cheaply; every preregistered size must
  // also pass the exact public preparation boundary without touching the DB.
  const cases = [...retainedMatrix(), ...workloads.flatMap(workload =>
    ['numeric-64', 'text-1024'].map(layout => retainedCase(workload, layout, 100)))];
  for (const fixture of cases) {
    const environment = benchmarkEnvironment(fixture);
    const l = fixture.limits;
    const input = {...contracts, database: '/benchmark-source-must-not-be-read.duckdb',
      environmentText: environment.text, environmentCid: environment.cid,
      programText: JSON.stringify(fixture.program()), parameterText: JSON.stringify({minimum: fixture.minimum}),
      dataProfile: {source_rows: l.sourceRows, task_rows: l.intermediateRows, columns: l.maxColumns,
        value_bytes: l.maxValueBytes, wire_bytes: l.representationBytes,
        value_nodes: l.cumulativeValueNodes, text_bytes: l.cumulativeValueTextBytes,
        work: l.cumulativeGuardWork, entries: l.cumulativeValueNodes,
        batch_bytes: Math.min(l.batchBytes, l.representationBytes)}};
    const plan = await prepareExampleText(input).catch(error => {
      throw new Error(`${fixture.id}: ${error.message}: ${error.cause?.stack ?? JSON.stringify(error.cause)}`, {cause: error});
    });
    assert.equal(plan.taskIdentities().length, fixture.workload === workloads[1] ? 4 : 3);
    assert.equal(plan.usage().attempts, 0);
  }
});
