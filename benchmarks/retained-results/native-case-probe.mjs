import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {retainedCase, retainedMatrix, workloads} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';

// Registered-case native product-path diagnostic. It now retains task output
// independently; formal four-comparator acceptance remains a separate run.
const [caseId, ...extra] = process.argv.slice(2);
if (!caseId) throw new TypeError('Expected one exact registered case ID');
const options = new Map();
for (const arg of extra) {
  if (arg === '--training' && !options.has('training')) {
    options.set('training', true);
    continue;
  }
  const match = /^--(native-ms|local-task-ms|native-task-ms)=(.+)$/.exec(arg);
  if (!match || options.has(match[1])) throw new TypeError('InvalidNativeProbeOption');
  options.set(match[1], match[2]);
}
const registered = retainedMatrix().find(item => item.id === caseId);
let fixture = registered;
if (!fixture && options.get('training') === true) {
  const [workload, layout, rowText, ...remaining] = caseId.split('/');
  if (remaining.length || !/^[1-9][0-9]*$/.test(rowText ?? '')) {
    throw new TypeError('InvalidNativeTrainingCase');
  }
  fixture = retainedCase(workload, layout, Number(rowText));
}
if (!fixture) throw new TypeError(`Unknown registered case: ${caseId}`);
const nativeMs = options.get('native-ms') ?? '1000';
const rates = name => {
  const raw = options.get(name);
  if (raw === undefined) return undefined;
  const values = raw.split(',');
  if (!values.every(value => /^(0|[1-9][0-9]*)$/.test(value) &&
      BigInt(value) <= 2147483647n)) throw new TypeError('InvalidNativeProbeRate');
  return values;
};
if (!/^(0|[1-9][0-9]*)$/.test(nativeMs) ||
    BigInt(nativeMs) > 2147483647n) throw new TypeError('InvalidNativeProbeEstimate');
const localRates = rates('local-task-ms');
const nativeRates = rates('native-task-ms');
const localEligible = registeredLocalEligibility(fixture).eligible;
const expectedTasks = fixture.workload === workloads[1] ? 4 : 3;
if (localRates && (!localEligible || localRates.length !== expectedTasks) ||
    nativeRates && (nativeRates.length !== expectedTasks ||
      localEligible && !localRates)) throw new TypeError('IncompleteNativeProbeProfile');
const root = fileURLToPath(new URL('../../', import.meta.url));
const scratchRoot = resolve(process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir(),
  'actql-native-retained-case-probe');
await mkdir(scratchRoot, {recursive: true});
const directory = await mkdtemp(join(scratchRoot, 'run-'));
const run = promisify(execFile);
const text = path => readFile(join(root, path), 'utf8');

try {
  const contracts = {
    adoptedText: await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
  const database = join(directory, 'source.duckdb');
  const retainedTaskRoot = join(directory, 'retained-task');
  await mkdir(retainedTaskRoot);
  await run(process.execPath, [
    join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
    database, fixture.workload, fixture.layout, String(fixture.rows),
  ], {cwd: root, timeout: fixture.limits.timeoutMs});
  const {input, limits, finalTask} = managedCaseConfiguration(
    fixture, contracts, database, directory,
  );
  assert.equal(finalTask, expectedTasks);
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
  const libraryName = process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so';
  const library = join(root, 'adapters/connectors/duckdb/node/node_modules/@duckdb',
    `node-bindings-${process.platform}-${process.arch}`, libraryName);
  assert(existsSync(library), `native DuckDB library unavailable: ${library}`);
  const buildProfile = process.env.ACTQL_NATIVE_PROBE_PROFILE === 'debug'
    ? 'debug' : 'release';
  const binary = join(root, `_build/native/${buildProfile}/build/cmd/native_retained_case_probe`,
    'native_retained_case_probe.exe');
  assert(existsSync(binary), 'build src/cmd/native_retained_case_probe --target native --release first');
  const expected = fixture.identity(); // Independent oracle remains outside the child timer.
  const started = performance.now();
  const data = input.dataProfile;
  const {stdout} = await run(binary, [
    '--application-root', directory,
    '--database', database,
    '--duckdb-library', library,
    '--retained-task-root', retainedTaskRoot,
    '--expected-cid', expected.rowsCid,
    '--expected-tasks', String(finalTask),
    '--native-ms', nativeMs,
    '--local-eligible', String(localEligible),
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
  ], {cwd: root, timeout: fixture.limits.timeoutMs, maxBuffer: 65536});
  const elapsedMilliseconds = performance.now() - started;
  const result = JSON.parse(stdout.trim().split('\n').at(-1));
  const selections = stdout.split('\n').filter(line => line.startsWith('selection:'));
  const taskIntervals = stdout.split('\n')
    .filter(line => line.startsWith('task-elapsed-us:'))
    .map(line => {
      const match = /^task-elapsed-us:([1-9][0-9]*):(0|[1-9][0-9]*)$/.exec(line);
      assert(match, 'InvalidNativeTaskInterval');
      const elapsedMicroseconds = Number(match[2]);
      assert(Number.isSafeInteger(elapsedMicroseconds));
      return {task: Number(match[1]), elapsedMicroseconds,
        elapsedMilliseconds: elapsedMicroseconds / 1000};
    });
  assert.equal(result.rows_cid, expected.rowsCid);
  assert.equal(result.task_count, finalTask);
  assert.deepEqual(taskIntervals.map(value => value.task),
    Array.from({length: finalTask}, (_, index) => index + 1));
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', status: 'verified-diagnostic', case: fixture.id,
    scope: registered ? 'registered-feasibility' : 'calibration-training',
    elapsedMilliseconds, taskIntervals, selections, result,
    selectionInput: {nativeMs, localEligible, localRates, nativeRates},
  }));
} catch (error) {
  const output = String(error.stdout ?? '').trim().split('\n');
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', status: 'failed', case: fixture.id,
    name: error.name,
    message: error.stdout ? undefined : error.message?.split('\n')[0],
    code: error.code ?? null, signal: error.signal ?? null,
    phases: output.filter(line => line.startsWith('phase:')),
    strategyRejections: output.filter(line => line.startsWith('strategy-rejection:')),
    terminal: output.at(-1),
  }));
  process.exitCode = 1;
} finally {
  await rm(directory, {recursive: true, force: true});
}
