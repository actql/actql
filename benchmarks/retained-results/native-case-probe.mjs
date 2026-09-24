import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {retainedCase, retainedMatrix, workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct,
  admitNativeDirectProduct} from './native-direct-product.mjs';

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
  const match = /^--(native-ms|local-task-ms|native-task-ms|source-database)=(.+)$/.exec(arg);
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

try {
  const database = options.has('source-database')
    ? resolve(options.get('source-database')) : join(directory, 'source.duckdb');
  if (options.has('source-database')) {
    assert(existsSync(database), 'NativeMatchedSourceUnavailable');
  } else {
    await run(process.execPath, [
      join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows),
    ], {cwd: root, timeout: fixture.limits.timeoutMs});
  }
  const invocation = await prepareNativeDirectProduct({root, fixture,
    database, directory, nativeMs, localRates, nativeRates});
  assert.equal(invocation.finalTask, expectedTasks);
  assert.equal(invocation.localEligible, localEligible);
  const execution = await executeNativeDirectProduct(invocation,
    {root, timeoutMs: fixture.limits.timeoutMs});
  const admitted = admitNativeDirectProduct(fixture, invocation, execution);
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', status: 'verified-diagnostic', case: fixture.id,
    scope: registered ? 'registered-feasibility' : 'calibration-training',
    elapsedMilliseconds: admitted.processCycleMs,
    executionMilliseconds: admitted.executionMs,
    cleanupMilliseconds: admitted.cleanupMs,
    taskIntervals: admitted.taskIntervals,
    taskUsages: admitted.taskUsages,
    taskHoldings: admitted.taskHoldings,
    selections: admitted.selections,
    result: admitted.record,
    acquisitionEvidenceMetadata: admitted.acquisitionEvidenceMetadata,
    sourceMode: options.has('source-database') ? 'existing' : 'generated',
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
