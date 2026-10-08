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
import {loadLocalOperationalProfile, localOperationalTemplate} from './operational-estimates.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct, admitNativeDirectProduct} from './native-direct-product.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {sha256File} from './release-artifacts.mjs';
import {captureLocalExecution, captureLimitBytes} from './local-profile-capture.mjs';
import {nativeProfileSchedule, nativeOperationalSchedule, nativeEmpiricalSchedule, localProcessFailureOutcome, profileDigest, validateLocalObservation,
  aggregateLocalProfiles, describeObservationOverhead} from './local-performance-profile.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const destination = resolve(process.argv[2] ?? '');
const operational = process.argv[3] === '--operational-six';
const empiricalStage = process.argv[3] === '--empirical-comparison' ? 'comparison'
  : process.argv[3] === '--empirical-evaluation' ? 'evaluation' : null;
assert((process.argv.length === 3 || process.argv.length === 4 && (operational || empiricalStage === 'comparison') || process.argv.length === 5 && empiricalStage === 'evaluation') && destination !== root &&
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
const comparison = empiricalStage === 'evaluation' ? await loadLocalOperationalProfile(resolve(process.argv[4])) : null;
if (comparison) {assert.equal(comparison.report.revision,revision);assert.equal(comparison.report.binaryDigest,binaryDigest);
  assert.equal(comparison.report.scheduleKind,'empirical-comparison');assert(comparison.report.accepted);
  assert.equal(comparison.report.observations.length,6);}
await mkdir(destination, {mode: 0o700}); // Refuse an existing destination: originals are immutable.
const database = comparison ? join(resolve(process.argv[4]),'source.duckdb') : join(destination, 'source.duckdb');
const sourceStart = performance.now();
if (!comparison) await exec(process.execPath, [join(root,
  'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'), database,
fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
const sourcePreparationMs = performance.now() - sourceStart;
const inputDigest = 'sha256:' + await sha256File(database);
const controls = {fresh: {residentPolicy: false, nativeRates: ['1000', '1000', '1000']},
  resident: {residentPolicy: true, nativeRates: ['1000', '1000', '1000']}};
if (empiricalStage) controls.resident = {residentPolicy:true,nativeRates:['1','1','1'],
  residentEstimates:{preparationMilliseconds:'1000',cleanupMilliseconds:'1000',
    taskMilliseconds:['1000','1000','1000'],importMilliseconds:['1000','1000','1000','1000']}};
const observations = [], schedule = empiricalStage ? nativeEmpiricalSchedule(empiricalStage)
  : operational ? nativeOperationalSchedule() : nativeProfileSchedule();

const report = {version: 'actql-local-native-profile-experiment/0.1', revision,
  compiledSourceRevision: revision, buildWitness, binaryDigest, environment, instrumentationRevision,
  schedule, scheduleKind: empiricalStage ? 'empirical-'+empiricalStage : operational ? 'operational-six' : 'capture-mode-eighteen',
  concurrency: 1, caseId: fixture.id, limits: fixture.limits,
  dataStatistics: {source: 'independent synthetic fixture, not inferred runtime statistics',
    rows: fixture.rows, expectedOutput: fixture.identity(), ndv: null, selectivity: null},
  localEligibility: eligibility, controls, sourcePreparationMs,
  freshnessPolicy: {maxAgeMs: 86400000, minimumSamples: 3,
    scope: 'explicit local analysis window, not a scientifically calibrated expiry'},
  empiricalPlan: empiricalStage ? {objective:'first-task-processing-median',intervention:'first position only; later tasks use current common offline choice',conditionsScope:'same offered profile; selected realization/position are interventions in mapping',fallback:'preconfigured-offline-on-incomplete-reference',ties:'lowest-position',profileOriginal:comparison?.profileRevision??null,profileReadbackAndAggregationMs:comparison?.admitted.readbackAndAggregationMs??null,phase:empiricalStage,calibrated:false} : null,
  observationLimit: schedule.length, perCaptureLimitBytes: captureLimitBytes, checkpointWritesMs: [],
  measurementScopes: {processCycleMs: 'parent preparation through child exit; excludes subsequent local capture/admission',
    coldMs: 'same process cycle minus child cleanup; existing coldMs boundary',
    warmMs: 'same-Run sequential task intervals, not a warm subsequent Run',
    observedEndToEndMs: 'parent preparation, child, Owner admission, local capture and recording; not customer application/Run latency',
    commonSourcePreparation: 'separate cost before all executions',
    aggregate: 'separate parent basic aggregation cost; not an operator interval',
    empiricalCosts: 'raw stream persistence/digests and template derivation/persistence measured separately; overlap end-to-end/process-cycle, not task processing',
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
    let templatePreparationMs = 0;
    let invocation = await prepareNativeDirectProduct({root, fixture, database, directory,
      ...controls[step.realization], phaseObserver: step.mode !== 'off'});
    if (empiricalStage) {
      const extra = ['--empirical-mode',step.arm.startsWith('position-') ? 'forced' : 'empirical',
        '--empirical-fallback','offline','--sqlite-library','/usr/lib/libsqlite3.dylib'];
      if (empiricalStage === 'comparison') extra.push('--empirical-position',step.arm.slice('position-'.length));
      if (empiricalStage === 'evaluation') {
        const templateStarted=performance.now();
        const first = comparison.report.observations[0].mapping.candidateProjections.find(p=>p.task===1);
        const candidates={canonical_json:JSON.stringify(first.body),cid:profileDigest(JSON.stringify(first.body))};
        const template=localOperationalTemplate({profile:comparison,
          conditions:step.arm==='offline-fallback'&&step.round===0 ? {...conditions,inputDigest:'different-input'} : conditions,
          task:1,candidates,now:Date.now()});
        if (step.arm==='offline-fallback'&&step.round===1) {
          template.entries=template.entries.map(entry=>entry.position===7&&entry.quantity==='task-processing'
            ? {...entry,status:'unknown',reason:'quantity-unobserved',median_ms:null,minimum_ms:null,maximum_ms:null} : entry);
        }
        if (step.arm==='offline-fallback'&&step.round===2) {template.oldest_ms='0';template.newest_ms='0';}

        const bytes=JSON.stringify(template);await writeFile(join(directory,'task-1.json'),bytes,{flag:'wx',mode:0o600});
        extra.push('--empirical-profile-root',directory,'--empirical-profile-revision',comparison.profileRevision,
          '--empirical-template-pin',profileDigest(bytes));
        templatePreparationMs=performance.now()-templateStarted;
      }
      invocation={...invocation,arguments:[...invocation.arguments,...extra]};
    }
    assert.equal(invocation.binary, binary);
    const execution = await executeNativeDirectProduct(invocation, {root, timeoutMs: fixture.limits.timeoutMs});
    rawExecution = execution;
    const cycleMs = performance.now() - started;
    const product = admitNativeDirectProduct(fixture, invocation, execution);
    const owner = product.ownerCorrespondence;
    if (!empiricalStage) assert(owner.observations.choices.every(choice => choice.name === 'duckdb' &&
      choice.resident === (step.realization === 'resident')), 'ExperimentChoiceMismatch');
    else {
      const first=owner.observations.candidates.find(p=>p.task===1);
      assert.deepEqual(first.body[5].map(c=>c[0]).sort((a,b)=>a-b),[0,7],'ChangedEmpiricalCandidateSet');
      const baseline=observations[0]?.mapping.candidateProjections.find(p=>p.task===1)?.body;
      if (baseline) assert.deepEqual(first.body,baseline,'EmpiricalSnapshotDrift');
      if (comparison) assert.deepEqual(first.body,comparison.report.observations[0].mapping.candidateProjections.find(p=>p.task===1).body,'ComparisonSnapshotMismatch');
      if (empiricalStage==='comparison') assert.equal(owner.observations.choices[0].position,Number(step.arm.slice('position-'.length)));
      if (step.arm==='offline-fallback') assert.equal(owner.observations.choices[0].position,0,'ControlledOfflineBaselineChanged');
    }
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
      : {status: 'observed', physicalPhases: product.physicalPhases,
        ...nativeCostObservation({status: 'verified-diagnostic', host: 'native',
        selectionInput: {phaseObserver: true}, physicalPhaseEvents: execution.physicalPhaseEvents,
        ownerCorrespondence: owner, taskIntervals: product.taskIntervals,
        result: {cleanup_us: product.record.cleanup_us}, physicalPhases: product.physicalPhases})};
    item.preparation = product.preparation;
    if (empiricalStage) {
      item.intervention={phase:empiricalStage,arm:step.arm};
      const lines=prefix=>execution.stdout.split('\n').filter(line=>line.startsWith(prefix)).map(line=>line.slice(prefix.length));
      item.empirical={rankings:lines('empirical-ranking:').map(JSON.parse),responses:lines('empirical-response:').map(JSON.parse),
        sidecars:lines('empirical-sidecar:').map(JSON.parse),fallbacks:lines('empirical-fallback:'),
        revokedRequests:lines('empirical-old-request-refused:'),oldStateRefusals:lines('empirical-old-state-refused:'),
        consultationMicroseconds:lines('empirical-consult-us:').map(Number)};
      const rawRecordingStarted=performance.now();
      await writeFile(join(directory,'native-stdout.log'),execution.stdout,{flag:'wx',mode:0o600});
      await writeFile(join(directory,'native-stderr.log'),execution.stderr,{flag:'wx',mode:0o600});
      item.rawEvidence={stdoutDigest:profileDigest(execution.stdout),stderrDigest:profileDigest(execution.stderr),
        stdoutBytes:Buffer.byteLength(execution.stdout),stderrBytes:Buffer.byteLength(execution.stderr),
        recordingAndDigestMs:performance.now()-rawRecordingStarted};
      item.empirical.templatePreparationMs=templatePreparationMs;
    }
    item.capture = await captureLocalExecution({mode: step.mode, directory, metadata,
      stdout: execution.stdout, stderr: execution.stderr});
    Object.assign(item.metrics, {processCycleMs: cycleMs, coldMs: cycleMs - product.cleanupMs,
      warmMs: product.warmMs, cleanupMs: product.cleanupMs, executionMs: product.executionMs,
      captureMs: item.capture.elapsedMs});
    if (!['complete', 'omitted'].includes(item.capture.status)) item.unknown.push('capture-incomplete');
  } catch (error) {
    // A killed process is interrupted, never owner-confirmed Cancelled.
    item.outcome = localProcessFailureOutcome(error);
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
  const baseline = operational || empiricalStage ? members[0] : members.find(item => item.conditions.captureMode === 'off');
  const baselineDigest = baseline?.ownerAccepted ? profileDigest(invariant(baseline)) : null;
  return {realization, count: members.length, unchanged: baselineDigest !== null &&
    members.every(item => item.ownerAccepted && profileDigest(invariant(item)) === baselineDigest),
    scope: 'exact result holdings, measured work, physical attempt deltas and final ledger usage; no public cancellation claim'};
});
if (empiricalStage) report.modeInvariance = [{scope:'off/on invariance unmeasured; treatment-specific attempts and work individually admitted',unchanged:null}];
report.provenanceReadback = {sourceUnchanged: inputDigest === 'sha256:' + await sha256File(database),
  binaryUnchanged: binaryDigest === 'sha256:' + await sha256File(binary),
  libraryUnchanged: libraryDigest === 'sha256:' + await sha256File(library),
  sourceRevisionUnchanged: revision === await git(['rev-parse', 'HEAD']) && await git(['status', '--porcelain']) === ''};
report.accepted = observations.length === schedule.length && observations.every(item => item.ownerAccepted && !item.unknown.length) &&
  report.profiles.length === (empiricalStage ? 1 : operational ? 2 : 6) && report.profiles.every(profile => profile.status === 'descriptive-only') &&
  (empiricalStage ? true : report.modeInvariance.every(item => item.unchanged)) &&
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
