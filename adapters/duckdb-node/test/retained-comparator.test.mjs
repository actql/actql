import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {runRetainedComparator, closeRetainedSample} from '../bench/retained-comparator.mjs';

const hash = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;

test('sample cleanup permits missing completion but never unconfirmed release', async () => {
  let closed = 0;
  const result = {close: async () => { closed++; },
    cleanupHandle: {status: () => ({pending: false})}, completion: () => undefined};
  assert(await closeRetainedSample(result, 3) >= 0);
  assert.equal(closed, 1);
  await assert.rejects(closeRetainedSample({...result,
    cleanupHandle: {status: () => ({pending: true})}}, 3), {code: 'ERR_ASSERTION'});
  await assert.rejects(closeRetainedSample({...result,
    completion: () => ({retained: true})}, 3), {code: 'ERR_ASSERTION'});
  const failure = Error('close failed');
  await assert.rejects(closeRetainedSample({...result,
    close: async () => { throw failure; }}, 3), error => error === failure);
});

test('retained comparator rejects invalid selection before preparing or executing', async () => {
  for (const options of [null, [], {resident: 'true'}, {nativeMilliseconds: '-1'},
    {nativeMilliseconds: '1.5'}, {nativeMilliseconds: '2147483648'}, {nativeMilliseconds: 20},
    {unknown: true}]) {
    await assert.rejects(runRetainedComparator(undefined, undefined, undefined, undefined, options),
      {code: 'ERR_ASSERTION'});
  }
});

test('managed host-cycle diagnostic reuses identity and independently releases files', async () => {
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
      assert.deepEqual(report.selection, {resident: false, nativeMilliseconds: '1'});
      assert.equal(report.expectedRowsCid, fixture.identity().rowsCid);
      const evidence = report.acquisitionEvidence;
      assert.deepEqual(evidence.receipts.map(value => value.role),
        ['validation_scan', 'native_result']);
      assert.deepEqual(evidence.records.map(value => value.role),
        ['source_validation', 'filter', 'select']);
      assert.equal(evidence.observation.output.row_count,
        fixture.cardinalities.capture);
      assert.equal(evidence.observation.accesses.validation_scan_cid,
        hash(evidence.receipts[0]));
      assert.equal(evidence.observation.accesses.native_result_cid,
        hash(evidence.receipts[1]));
      assert.equal(evidence.observation.coverage.source_validation_evidence_cid,
        hash(evidence.records[0]));
      assert.equal(evidence.observation.coverage.filter_evidence_cid,
        hash(evidence.records[1]));
      assert.equal(evidence.observation.coverage.select_evidence_cid,
        hash(evidence.records[2]));
      assert(report.tasks.every(task => task.phases.inputs.every(input =>
        input.representation === 'verified-file-native-read' && input.parameterInsertRows === 0)));
      for (const input of report.tasks.flatMap(task => task.phases.inputs)) {
        assert.equal(input.validationRows, input.rows);
        assert.equal(input.validationCells, input.rows * (workload === workloads[2] ? 2 : 1));
        assert.equal(input.storedRowJsonDecodes, 0);
        assert.equal(input.logicalCidPasses, 0);
        assert.equal(input.identityReused, true);
        assert.equal(input.physicalIntegrityPasses, 1);
        assert.equal(input.nativeFileReads, 1);
        assert(input.fileBytes > 0);
      }
      assert.equal(report.controlMemory.status, 'observed');
      assert(BigInt(report.controlTransport.receivedBytes) > 0n);
      assert(report.executionMs > 0 && report.cleanupMs >= 0);
      assert(report.warmMs > 0 && report.warmMs <= report.executionMs);
      assert.doesNotThrow(() => JSON.stringify(report));
      assert((await readdir(directory)).every(name => /^source-\d\.duckdb$/.test(name)));
      const reused = await runRetainedComparator(fixture, contracts, database, directory,
        {resident: true, nativeMilliseconds: '20'});
      assert.equal(reused.expectedRowsCid, report.expectedRowsCid);
      assert.equal(reused.scope, report.scope);
      assert.notEqual(reused.selectionHash, report.selectionHash);
      assert.deepEqual(reused.selection, {resident: true, nativeMilliseconds: '20'});
      assert(reused.tasks.every(task => task.realization === 'duckdb-resident'));
      assert.deepEqual(reused.tasks.map(task => task.preparation.imports.length),
        [1, ...Array(reused.tasks.length - 1).fill(0)]);
      assert(reused.executionMs > 0 && reused.cleanupMs >= 0);
      assert(reused.warmMs > 0 && reused.warmMs <= reused.executionMs);
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
