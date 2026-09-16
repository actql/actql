import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {runRetainedComparator} from '../bench/retained-comparator.mjs';

test('installed retained timing leg verifies every workload and independently releases files', async () => {
  const root = new URL('../../../', import.meta.url);
  for (const target of ['connectors/duckdb/host_node', 'retained_host_bridge',
    'process_host_bridge', 'connectors_builtin_node', 'physical_strategy_example']) {
    await promisify(execFile)('moon', ['build', '--target', 'js', '--release', `src/${target}`],
      {cwd: fileURLToPath(root)});
  }
  const text = path => readFile(new URL(path, root), 'utf8');
  const contracts = {adoptedText: await text('adapters/duckdb-node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json')};
  const directory = await mkdtemp(join(tmpdir(), 'actql-retained-comparator-'));
  try {
    for (const workload of workloads) {
      const fixture = retainedCase(workload, 'narrow', 100);
      const database = join(directory, `source-${workloads.indexOf(workload)}.duckdb`);
      await promisify(execFile)(process.execPath,
        [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
          database, workload, 'narrow', '100']);
      const report = await runRetainedComparator(fixture, contracts, database, directory);
      assert.equal(report.status, 'completed');
      assert.equal(report.comparator, 'retained-actql');
      assert.equal(report.scope, 'managed-host-cycle-diagnostic');
      assert.equal(report.expectedRowsCid, fixture.identity().rowsCid);
      assert.equal(report.controlMemory.status, 'observed');
      assert(BigInt(report.controlTransport.receivedBytes) > 0n);
      assert(report.executionMs > 0 && report.cleanupMs >= 0);
      assert.doesNotThrow(() => JSON.stringify(report));
      assert((await readdir(directory)).every(name => /^source-\d\.duckdb$/.test(name)));
    }
    const fixture = retainedCase(workloads[2], 'narrow', 100);
    const incorrectOracle = {...fixture, identity: () => ({...fixture.identity(), rowsCid: 'sha256:wrong'})};
    await assert.rejects(runRetainedComparator(incorrectOracle, contracts,
      join(directory, 'source-2.duckdb'), directory), {code: 'ERR_ASSERTION'});
    assert((await readdir(directory)).every(name => /^source-\d\.duckdb$/.test(name)),
      'a rejected sample still explicitly releases its completed files');
  } finally { await rm(directory, {recursive: true, force: true}); }
});
