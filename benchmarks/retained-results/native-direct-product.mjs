import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {promisify} from 'node:util';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';
import {workloads} from './fixtures.mjs';
import {productAcquisitionMetadata} from
  '../../adapters/connectors/duckdb/node/bench/equivalent-acquisition-metadata.mjs';

// The caller prepares a registered source before the process-cold interval.
// The binary performs application admission, planning, execution, retention,
// downstream reads, and confirmed release inside that interval.
// residentPolicy installs the resident DuckDB profile as a strategy candidate
// for every case alike; the portable strategy still selects where it is used.
export async function prepareNativeDirectProduct({root, fixture, database,
  directory, nativeMs = '1000', localRates, nativeRates,
  residentPolicy = false}) {
  assert(existsSync(database), 'NativeProductSourceUnavailable');
  assert(typeof residentPolicy === 'boolean', 'InvalidNativeResidentPolicy');
  const text = path => readFile(join(root, path), 'utf8');
  const contracts = {
    adoptedText: await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
  const {input, limits, finalTask} = managedCaseConfiguration(
    fixture, contracts, database, directory,
  );
  const adopted = JSON.parse(input.adoptedText);
  const files = {
    'program.json': input.programText,
    'environment.json': input.environmentText,
    'environment.cid': input.environmentCid,
    'parameters.json': input.parameterText,
    'registry.json': JSON.stringify(adopted.registry),
    'values.json': JSON.stringify(adopted.values),
    'fragment.json': JSON.stringify(adopted.fragment),
    'query.json': input.query,
    'evidence.json': input.evidence,
    'two-receipt.json': input.receipts,
  };
  for (const [name, content] of Object.entries(files)) {
    await writeFile(join(directory, name), content);
  }
  const retainedTaskRoot = join(directory, 'retained-task');
  await mkdir(retainedTaskRoot);
  const library = join(root, 'adapters/connectors/duckdb/node/node_modules/@duckdb',
    `node-bindings-${process.platform}-${process.arch}`,
    process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so');
  assert(existsSync(library), `NativeProductDuckDBUnavailable:${library}`);
  const buildProfile = process.env.ACTQL_NATIVE_PROBE_PROFILE === 'debug'
    ? 'debug' : 'release';
  const binary = join(root, `_build/native/${buildProfile}/build/cmd/native_retained_case_probe`,
    'native_retained_case_probe.exe');
  assert(existsSync(binary), 'NativeProductReleaseArtifactUnavailable');
  const data = input.dataProfile;
  const localEligible = registeredLocalEligibility(fixture).eligible;
  const expected = fixture.identity();
  return Object.freeze({binary, expected, finalTask, localEligible,
    arguments: Object.freeze([
      '--application-root', directory,
      '--database', database,
      '--duckdb-library', library,
      '--retained-task-root', retainedTaskRoot,
      '--expected-cid', expected.rowsCid,
      '--expected-tasks', String(finalTask),
      '--native-ms', nativeMs,
      '--local-eligible', String(localEligible),
      '--resident-policy', String(residentPolicy),
      '--local-task-ms', localRates?.join(',') ?? '-',
      '--native-task-ms', nativeRates?.join(',') ?? '-',
      '--source-rows', String(data.source_rows),
      '--task-rows', String(data.task_rows),
      '--columns', String(data.columns),
      '--value-bytes', String(data.value_bytes),
      '--wire-bytes', String(data.wire_bytes),
      '--value-nodes', String(data.value_nodes),
      '--text-bytes', String(data.text_bytes),
      '--work', String(data.work),
      '--entries', String(data.entries),
      '--batch-bytes', String(data.batch_bytes),
      '--planning-work', String(limits.planning_work),
      '--transfer-cap', String(limits.transfer_bytes),
      '--retained-cap', String(limits.retained_bytes),
      '--execution-cap', String(limits.execution_bytes),
    ])});
}

export async function executeNativeDirectProduct(invocation, {root, timeoutMs}) {
  const started = performance.now();
  const {stdout, stderr} = await promisify(execFile)(invocation.binary,
    invocation.arguments, {cwd: root, timeout: timeoutMs, maxBuffer: 1024 * 1024});
  const processCycleMs = performance.now() - started;
  const record = JSON.parse(stdout.trim().split('\n').at(-1));
  assert.equal(record.rows_cid, invocation.expected.rowsCid,
    'NativeProductResultMismatch');
  assert.equal(record.task_count, invocation.finalTask,
    'NativeProductTaskCountMismatch');
  const taskIntervals = stdout.split('\n')
    .filter(line => line.startsWith('task-elapsed-us:'))
    .map(line => {
      const match = /^task-elapsed-us:([1-9][0-9]*):(0|[1-9][0-9]*)$/.exec(line);
      assert(match, 'InvalidNativeProductTaskInterval');
      return {task: Number(match[1]), elapsedMicroseconds: Number(match[2]),
        elapsedMilliseconds: Number(match[2]) / 1000};
    });
  assert.deepEqual(taskIntervals.map(value => value.task),
    Array.from({length: invocation.finalTask}, (_, index) => index + 1));
  return Object.freeze({record, taskIntervals,
    selections: stdout.split('\n').filter(line => line.startsWith('selection:')),
    taskUsages: stdout.split('\n').filter(line => line.startsWith('task-usage:')),
    taskHoldings: stdout.split('\n').filter(line => line.startsWith('task-holding:')),
    taskResidents: stdout.split('\n').filter(line => line.startsWith('task-resident:')),
    processCycleMs, stderr});
}

export function admitNativeDirectProduct(fixture, invocation, execution) {
  const {record, taskIntervals, selections} = execution;
  const expectedTasks = fixture.workload === workloads[1] ? 4 : 3;
  assert.equal(invocation.finalTask, expectedTasks);
  assert.equal(record.rows_cid, fixture.identity().rowsCid);
  assert.equal(record.task_count, expectedTasks);
  for (const key of ['execution_us', 'cleanup_us']) {
    assert(Number.isSafeInteger(record[key]) && record[key] >= 0,
      `InvalidNativeProductInterval:${key}`);
  }
  for (const key of ['planning_work', 'attempts', 'holdings',
    'transferred_bytes', 'uncertain_transfer_bytes',
    'reserved_transfer_bytes', 'held_bytes', 'reserved_retention_bytes',
    'reserved_execution_bytes', 'peak_retention_bytes']) {
    assert(Number.isSafeInteger(record.usage?.[key]) && record.usage[key] >= 0,
      `InvalidNativeProductLedger:${key}`);
  }
  for (const key of ['uncertain_transfer_bytes', 'reserved_transfer_bytes',
    'held_bytes', 'reserved_retention_bytes', 'reserved_execution_bytes']) {
    assert.equal(record.usage[key], 0, `NativeProductCleanupPending:${key}`);
  }
  for (const key of ['guard_work', 'guard_bytes', 'guard_nodes',
    'comparison_work', 'comparison_bytes', 'comparison_nodes',
    'comparison_rows']) {
    assert(Number.isSafeInteger(record.acquisition?.[key]) &&
      record.acquisition[key] >= 0, `InvalidNativeProductAcquisition:${key}`);
  }
  assert.equal(record.acquisition.comparison_rows, fixture.rows);
  const taskUsages = execution.taskUsages.map(line => {
    const match = /^task-usage:([1-9][0-9]*):((?:0|[1-9][0-9]*):){5}(?:0|[1-9][0-9]*)$/.exec(line);
    assert(match, 'InvalidNativeProductTaskUsage');
    const [task, measurementWork, measurementBytes, measurementNodes,
      comparisonWork, comparisonBytes, comparisonNodes] =
      line.slice('task-usage:'.length).split(':').map(Number);
    assert([task, measurementWork, measurementBytes, measurementNodes,
      comparisonWork, comparisonBytes, comparisonNodes].every(value =>
      Number.isSafeInteger(value) && value >= 0), 'InvalidNativeProductTaskUsage');
    return {task, measurementWork, measurementBytes, measurementNodes,
      comparisonWork, comparisonBytes, comparisonNodes};
  });
  const taskHoldings = execution.taskHoldings.map(line => {
    const match = /^task-holding:([1-9][0-9]*):(0|[1-9][0-9]*):(sha256:[0-9a-f]{64}):(0|[1-9][0-9]*)$/.exec(line);
    assert(match, 'InvalidNativeProductTaskHolding');
    return {task: Number(match[1]), rows: Number(match[2]),
      rowsCid: match[3], bytes: Number(match[4])};
  });
  const ids = Array.from({length: expectedTasks}, (_, index) => index + 1);
  assert.deepEqual(taskIntervals.map(value => value.task), ids);
  assert.deepEqual(taskUsages.map(value => value.task), ids);
  assert.deepEqual(taskHoldings.map(value => value.task), ids);
  assert.deepEqual(taskHoldings.map(value => value.rows),
    fixture.workload === workloads[1]
      ? [fixture.cardinalities.a, fixture.cardinalities.b,
        fixture.cardinalities.join, fixture.cardinalities.count]
      : [fixture.cardinalities.a, fixture.cardinalities.b,
        fixture.cardinalities.c]);
  assert.equal(taskHoldings.at(-1).rowsCid, fixture.identity().rowsCid);
  const acquisitionEvidenceMetadata = productAcquisitionMetadata(
    fixture, record.acquisition_evidence);
  const selected = new Map(selections.map(line => {
    const match = /^selection:([1-9][0-9]*):(local|duckdb)$/.exec(line);
    assert(match, 'InvalidNativeProductSelection');
    return [Number(match[1]), match[2]];
  }));
  assert.equal(selected.size, expectedTasks);
  return Object.freeze({record, taskIntervals, taskUsages, taskHoldings,
    selections, selected: ids.map(task => selected.get(task)),
    acquisitionEvidenceMetadata,
    executionMs: record.execution_us / 1000,
    cleanupMs: record.cleanup_us / 1000,
    warmMs: taskIntervals.reduce((sum, value) =>
      sum + value.elapsedMilliseconds, 0),
    processCycleMs: execution.processCycleMs});
}
