// Explicit bounded local experiment. No policy upload, telemetry export or retry.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, writeFile, readFile} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {cpus, release} from 'node:os';
import {promisify} from 'node:util';
import {retainedCase, workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct, admitNativeDirectProduct} from './native-direct-product.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {sha256File} from './release-artifacts.mjs';
import {captureLocalExecution, captureLimitBytes} from './local-profile-capture.mjs';
import {nativeProfileSchedule, profileDigest, validateLocalObservation,
  aggregateLocalProfiles, describeObservationOverhead} from './local-performance-profile.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const destination = resolve(process.argv[2] ?? '');
assert(process.argv.length === 3 && destination !== root &&
  !destination.startsWith(root + sep), 'ExpectedExternalOwnedProfileDirectory');
assert.notEqual(process.env.ACTQL_NATIVE_PROBE_PROFILE, 'debug', 'ProfileRequiresReleaseProbe');
const exec = promisify(execFile), experimentStart = performance.now();
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
assert.equal(await git(['status', '--porcelain']), '', 'ProfileRequiresCleanSource');
const fixture = retainedCase(workloads[2], 'text-1024', 1000);
const eligibility = registeredLocalEligibility(fixture);
assert.equal(eligibility.eligible, false, 'TextFixtureEligibilityChanged');
const binary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest = 'sha256:' + await sha256File(binary);
const buildWitness = JSON.parse(await readFile(join(root, '_build/local-native-profile-build.json'), 'utf8'));
assert.equal(buildWitness.sourceRevision, revision, 'ProfileBuildSourceMismatch');
assert.equal(buildWitness.binaryDigest, binaryDigest, 'ProfileBuildBinaryMismatch');
assert.equal(buildWitness.buildExitCode, 0, 'ProfileBuildUnsuccessful');
const library = join(root, 'adapters/connectors/duckdb/node/node_modules/@duckdb',
  `node-bindings-${process.platform}-${process.arch}`, process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so');
const libraryDigest = 'sha256:' + await sha256File(library);
const instrumentation = ['local-performance-profile.mjs', 'local-profile-capture.mjs',
  'run-local-native-profile.mjs', 'read-local-native-profile.mjs', 'native-direct-product.mjs', 'native-owner-observations.mjs',
  'native-physical-phases.mjs', 'native-cost-observation.mjs'];
const instrumentationRevision = profileDigest(await Promise.all(instrumentation.map(async path =>
  [path, 'sha256:' + await sha256File(join(root, 'benchmarks/retained-results', path))])));
const environment = {platform: process.platform, arch: process.arch, osRelease: release(),
  cpuModels: [...new Set(cpus().map(cpu => cpu.model))], logicalCpus: cpus().length,
  node: process.version, libraryDigest, toolchain: JSON.parse(await readFile(join(root, 'toolchain.json'))),
  experimentConcurrency: 1, providerThreads: 'unknown', competingLoad: 'uncontrolled'};
await mkdir(destination, {mode: 0o700}); // Refuse an existing destination: originals are immutable.
const database = join(destination, 'source.duckdb');
const sourceStart = performance.now();
await exec(process.execPath, [join(root,
  'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'), database,
fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
const sourcePreparationMs = performance.now() - sourceStart;
const inputDigest = 'sha256:' + await sha256File(database);
const controls = {fresh: {residentPolicy: false, nativeRates: ['1000', '1000', '1000']},
  resident: {residentPolicy: true, nativeRates: ['1000', '1000', '1000']}};
const observations = [], schedule = nativeProfileSchedule();
const report = {version: 'actql-local-native-profile-experiment/0.1', revision,
  compiledSourceRevision: revision, buildWitness, binaryDigest, environment, instrumentationRevision,
  schedule, concurrency: 1, caseId: fixture.id, limits: fixture.limits,
  dataStatistics: {source: 'independent synthetic fixture, not inferred runtime statistics',
    rows: fixture.rows, expectedOutput: fixture.identity(), ndv: null, selectivity: null},
  localEligibility: eligibility, controls, sourcePreparationMs,
  freshnessPolicy: {maxAgeMs: 86400000, minimumSamples: 3,
    scope: 'explicit local analysis window, not a scientifically calibrated expiry'},
  observationLimit: 18, perCaptureLimitBytes: captureLimitBytes, checkpointWritesMs: [],
  measurementScopes: {processCycleMs: 'parent preparation through child exit; excludes subsequent local capture/admission',
    coldMs: 'same process cycle minus child cleanup; existing coldMs boundary',
    warmMs: 'same-Run sequential task intervals, not a warm subsequent Run',
    observedEndToEndMs: 'parent preparation, child, Owner admission, local capture and recording; not customer application/Run latency',
    commonSourcePreparation: 'separate cost before all executions',
    aggregate: 'separate parent basic aggregation cost; not an operator interval',
    overlapping: true, osCache: 'uncontrolled'}, observations};
const checkpoint = async () => {
  const started = performance.now();
  await writeFile(join(destination, 'experiment.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  report.checkpointWritesMs.push(performance.now() - started);
};
await checkpoint();
for (const step of schedule) {
  const directory = join(destination, `trial-${step.index}`); await mkdir(directory, {mode: 0o700});
  const conditions = {host: 'native', realization: step.realization, captureMode: step.mode,
    runtimeRevision: revision, binaryDigest, inputDigest, programDigest: profileDigest(fixture.program()),
    inputRows: fixture.rows, schemaLayout: fixture.layout, limitsDigest: profileDigest(fixture.limits),
    instrumentationRevision, measurementScopeRevision: profileDigest(report.measurementScopes),
    environmentDigest: profileDigest(environment), controlDigest: profileDigest(controls[step.realization]),
    concurrency: 1, processState: 'new-process-and-environment', osCache: 'uncontrolled',
    authorizedScope: 'local-synthetic-fixture-only; no export/sharing'};
  const item = {version: 'actql-local-performance-observation/0.1', id: `trial-${step.index}`,
    round: step.round, conditions, observedAt: Date.now(), outcome: 'unobserved', ownerAccepted: false,
    metrics: Object.fromEntries(['processCycleMs', 'coldMs', 'warmMs', 'cleanupMs', 'executionMs',
      'captureMs', 'recordingMs', 'observedEndToEndMs'].map(name => [name, null])),
    capture: {status: 'missing', reason: 'execution-not-completed'}, unknown: []};
  const started = performance.now();
  let rawExecution;
  try {
    const invocation = await prepareNativeDirectProduct({root, fixture, database, directory,
      ...controls[step.realization], phaseObserver: step.mode !== 'off'});
    assert.equal(invocation.binary, binary);
    const execution = await executeNativeDirectProduct(invocation, {root, timeoutMs: fixture.limits.timeoutMs});
    rawExecution = execution;
    const cycleMs = performance.now() - started;
    const product = admitNativeDirectProduct(fixture, invocation, execution);
    const owner = product.ownerCorrespondence;
    assert(owner.observations.choices.every(choice => choice.name === 'duckdb' &&
      choice.resident === (step.realization === 'resident')), 'ExperimentChoiceMismatch');
    const metadata = {id: item.id, revision, binaryDigest, inputDigest, instrumentationRevision,
      expectedRowsCid: fixture.identity().rowsCid, actualRowsCid: product.record.rows_cid,
      candidates: owner.observations.candidates, choices: owner.observations.choices,
      explanations: owner.observations.explanations, holdings: product.taskHoldings,
      attempts: owner.attempts, taskUsages: product.taskUsages,
      acquisition: product.acquisitionChoice, cleanup: product.record.usage};
    item.outcome = 'succeeded'; item.ownerAccepted = true;
    item.candidateSnapshotDigest = profileDigest(metadata.candidates);
    item.mapping = {hostSelection: 'explicit-experiment-condition',
      selectionMode: 'experiment-controlled-real-planner', acquisition: metadata.acquisition,
      candidateProjections: metadata.candidates, choices: metadata.choices,
      explanations: metadata.explanations, attempts: metadata.attempts,
      attemptIdentity: 'unknown-counter-correspondence-only',
      physicalExecutionSite: 'this Native process; no placement-selection claim',
      holdings: metadata.holdings, taskUsages: metadata.taskUsages, finalUsage: metadata.cleanup};
    item.operatorMeasurements = step.mode === 'off' ? {status: 'unknown', reason: 'physical-phase-observer-off'}
      : {status: 'observed', ...nativeCostObservation({status: 'verified-diagnostic', host: 'native',
        selectionInput: {phaseObserver: true}, physicalPhaseEvents: execution.physicalPhaseEvents,
        ownerCorrespondence: owner, taskIntervals: product.taskIntervals,
        result: {cleanup_us: product.record.cleanup_us}, physicalPhases: product.physicalPhases})};
    item.preparation = product.preparation;
    item.capture = await captureLocalExecution({mode: step.mode, directory, metadata,
      stdout: execution.stdout, stderr: execution.stderr});
    Object.assign(item.metrics, {processCycleMs: cycleMs, coldMs: cycleMs - product.cleanupMs,
      warmMs: product.warmMs, cleanupMs: product.cleanupMs, executionMs: product.executionMs,
      captureMs: item.capture.elapsedMs});
    if (!['complete', 'omitted'].includes(item.capture.status)) item.unknown.push('capture-incomplete');
  } catch (error) {
    // A killed process is interrupted, never owner-confirmed Cancelled.
    item.outcome = error.signal || error.killed ? 'interrupted' : 'failed';
    item.ownerAccepted = false;
    item.unknown.push('execution-or-admission-incomplete');
    item.failure = {code: typeof error.code === 'string' || typeof error.code === 'number' ? error.code : null,
      signal: error.signal ?? null, cleanup: 'unknown', elapsedMs: performance.now() - started};
    // Preserve bounded diagnostic bytes without publishing arbitrary exception text.
    const stdout = typeof error.stdout === 'string' ? error.stdout : rawExecution?.stdout ?? '';
    const stderr = typeof error.stderr === 'string' ? error.stderr : rawExecution?.stderr ?? '';
    item.capture = await captureLocalExecution({mode: 'evidence-enabled', directory,
      metadata: item.failure, stdout, stderr});
    item.capture.failureDiagnostic = true;
  }
  const recordingStart = performance.now();
  const recordPath = join(directory, 'observation.json');
  const original = JSON.stringify(item) + '\n';
  assert(Buffer.byteLength(original) <= captureLimitBytes, 'ObservationRecordLimit');
  await writeFile(recordPath, original, {flag: 'wx', mode: 0o600});
  assert.equal(await readFile(recordPath, 'utf8'), original);
  // The record cannot contain the cost of its own write; the enclosing experiment
  // binds that original digest and the separately observed recording interval.
  item.originalRecordDigest = profileDigest(original);
  item.metrics.recordingMs = performance.now() - recordingStart;
  item.metrics.observedEndToEndMs = performance.now() - started;
  validateLocalObservation(item); observations.push(item); await checkpoint();
  console.log(JSON.stringify({trial: step.index, outcome: item.outcome, mode: step.mode,
    realization: step.realization, cycleMs: item.metrics.processCycleMs, capture: item.capture.status}));
  if (!item.ownerAccepted) break; // No new process after unresolved physical responsibility.
}
const aggregateStart = performance.now();
report.profiles = aggregateLocalProfiles(observations, {now: Date.now(), ...report.freshnessPolicy});
report.overhead = describeObservationOverhead(observations);
report.aggregationMs = performance.now() - aggregateStart;
report.modeInvariance = ['fresh', 'resident'].map(realization => {
  const members = observations.filter(item => item.conditions.realization === realization);
  const invariant = item => ({holdings: item.mapping?.holdings, taskUsages: item.mapping?.taskUsages,
    attempts: item.mapping?.attempts, finalUsage: item.mapping?.finalUsage});
  const baseline = members.find(item => item.conditions.captureMode === 'off');
  const baselineDigest = baseline?.ownerAccepted ? profileDigest(invariant(baseline)) : null;
  return {realization, count: members.length, unchanged: baselineDigest !== null &&
    members.every(item => item.ownerAccepted && profileDigest(invariant(item)) === baselineDigest),
    scope: 'exact result holdings, measured work, physical attempt deltas and final ledger usage; no public cancellation claim'};
});
report.provenanceReadback = {sourceUnchanged: inputDigest === 'sha256:' + await sha256File(database),
  binaryUnchanged: binaryDigest === 'sha256:' + await sha256File(binary),
  libraryUnchanged: libraryDigest === 'sha256:' + await sha256File(library),
  sourceRevisionUnchanged: revision === await git(['rev-parse', 'HEAD']) && await git(['status', '--porcelain']) === ''};
report.accepted = observations.length === 18 && observations.every(item => item.ownerAccepted && !item.unknown.length) &&
  report.profiles.length === 6 && report.profiles.every(profile => profile.status === 'descriptive-only') &&
  report.modeInvariance.every(item => item.unchanged) &&
  Object.values(report.provenanceReadback).every(Boolean);
report.experimentElapsedMs = performance.now() - experimentStart;
await checkpoint();
// A final small cost receipt describes the last checkpoint without rewriting it.
await writeFile(join(destination, 'recording-costs.json'), JSON.stringify({
  checkpointWritesMs: report.checkpointWritesMs,
  totalCheckpointMs: report.checkpointWritesMs.reduce((sum, value) => sum + value, 0),
  elapsedThroughFinalCheckpointMs: performance.now() - experimentStart,
  scope: 'includes final experiment checkpoint; excludes this cost receipt write'}, null, 2) + '\n', {flag: 'wx', mode: 0o600});
console.log(JSON.stringify({accepted: report.accepted, executions: observations.length,
  profiles: report.profiles.length, report: join(destination, 'experiment.json')}));
process.exitCode = report.accepted ? 0 : 1;
