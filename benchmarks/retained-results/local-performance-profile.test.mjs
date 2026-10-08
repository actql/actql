import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, writeFile, rm, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeProfileSchedule, aggregateLocalProfiles, profileDigest,
  validateLocalObservation, matchLocalProfile, describeObservationOverhead, localProcessFailureOutcome} from './local-performance-profile.mjs';
import {captureLocalExecution} from './local-profile-capture.mjs';
import {readLocalNativeProfile} from './read-local-native-profile.mjs';
import {retainedCase, workloads} from './fixtures.mjs';

const observation = (index, changes = {}) => ({
  version: 'actql-local-performance-observation/0.1', id: `o-${index}`, round: index,
  observedAt: 1000, outcome: 'succeeded', ownerAccepted: true,
  conditions: {host: 'native', realization: 'resident', captureMode: 'off',
    concurrency: 1, osCache: 'uncontrolled', processState: 'new-process-and-environment',
    runtimeRevision: 'source-a', binaryDigest: 'binary-a', inputDigest: 'input-a',
    inputRows: 1000, programDigest: 'program-a', instrumentationRevision: 'observer-a',
    measurementScopeRevision: 'scope-a', environmentDigest: 'environment-a', controlDigest: 'control-a'},
  metrics: {processCycleMs: 100 + index, coldMs: 95 + index, cleanupMs: 5,
    warmMs: 50, executionMs: 90, captureMs: 0, recordingMs: 1, observedEndToEndMs: 110 + index},
  capture: {status: 'omitted'}, unknown: [], candidateSnapshotDigest: 'snapshot-a',
  mapping: {choices: [{task: 1}], attemptIdentity: 'unknown-counter-correspondence-only',
    hostSelection: 'explicit-experiment-condition', selectionMode: 'experiment-controlled-real-planner'}, ...changes});
const options = {now: 1100, maxAgeMs: 1000, minimumSamples: 3};

test('fixed schedule has exactly three occurrences of each condition and no replacement slot', () => {
  const plan = nativeProfileSchedule(); assert.equal(plan.length, 18);
  for (const realization of ['fresh', 'resident']) for (const mode of ['off', 'metadata-only', 'evidence-enabled']) {
    assert.deepEqual(plan.filter(item => item.realization === realization && item.mode === mode)
      .map(item => item.round), [0, 1, 2]);
  }
  assert.deepEqual(plan.slice(0, 2).map(item => item.realization), ['fresh', 'resident']);
  assert.deepEqual(plan.slice(6, 8).map(item => item.realization), ['resident', 'fresh']);
});

test('three compatible observations produce descriptive median/range, no estimate or precision', () => {
  const [profile] = aggregateLocalProfiles([observation(0), observation(1), observation(2)], options);
  assert.equal(profile.status, 'descriptive-only');
  assert.deepEqual(profile.metrics.processCycleMs, {count: 3, median: 101, min: 100, max: 102, status: 'descriptive-only'});
  assert.equal(profile.plannerEstimate, null); assert.equal(profile.populationFailureRate, null);
  assert.equal(profile.precision, 'not-established');
  assert.equal(profile.attempted, 3);
});

test('failure, cancellation, interruption and unobserved samples never become fast successes', () => {
  const samples = [observation(0), ...['failed', 'cancelled', 'interrupted', 'unobserved'].map((outcome, index) =>
    observation(index + 1, {outcome, ownerAccepted: false,
      metrics: Object.fromEntries(Object.keys(observation(0).metrics).map(key => [key, 0]))}))];
  const [profile] = aggregateLocalProfiles(samples, options);
  assert.equal(profile.status, 'unknown'); assert.equal(profile.attempted, 5);
  assert.equal(profile.metrics.processCycleMs.count, 1); assert.equal(profile.metrics.processCycleMs.min, 100);
  assert.deepEqual(profile.statuses, {succeeded: 1, failed: 1, cancelled: 1, interrupted: 1, unobserved: 1});
});

test('missing or failed capture leaves completed execution visible but profile unknown', () => {
  for (const status of ['missing', 'failed']) {
    const samples = [0, 1, 2].map(index => {
      const value = observation(index); value.conditions.captureMode = 'evidence-enabled';
      value.capture.status = index === 2 ? status : 'complete'; return value;
    });
    const [profile] = aggregateLocalProfiles(samples, options);
    assert.equal(profile.statuses.succeeded, 3); assert.equal(profile.metrics.processCycleMs.count, 2);
    assert(profile.reasons.includes('observation-incomplete')); assert.equal(profile.status, 'unknown');
  }
});

for (const field of ['captureMode', 'runtimeRevision', 'binaryDigest', 'inputRows',
  'instrumentationRevision', 'measurementScopeRevision', 'environmentDigest', 'controlDigest']) {
  test(`incompatible ${field} splits profiles and refuses matching`, () => {
    const samples = [observation(0), observation(1), observation(2)];
    const changed = observation(3);
    changed.conditions[field] = field === 'inputRows' ? 2000 : field === 'captureMode' ? 'metadata-only' : 'different';
    if (field === 'captureMode') changed.capture.status = 'complete';
    const groups = aggregateLocalProfiles([...samples, changed], options);
    assert.equal(groups.length, 2); assert.equal(groups[1].status, 'unknown');
    assert.deepEqual(matchLocalProfile(groups[0], changed.conditions, options),
      {status: 'unknown', reason: 'conditions-mismatch'});
  });
}

test('stale/future observations and stricter query freshness stay unknown', () => {
  const samples = [observation(0), observation(1), observation(2, {observedAt: 2000})];
  const [profile] = aggregateLocalProfiles(samples, options);
  assert.equal(profile.status, 'unknown'); assert(profile.reasons.includes('freshness-insufficient'));
  const [fresh] = aggregateLocalProfiles([observation(0), observation(1), observation(2)], options);
  assert.equal(matchLocalProfile(fresh, fresh.conditions, {now: 9999, maxAgeMs: 1}).status, 'unknown');
  assert.equal(aggregateLocalProfiles([observation(0), observation(1), observation(2)],
    {...options, maxAgeMs: 1})[0].status, 'unknown');
});

test('duplicate observations, negative intervals, unaccepted success and false cold boundary are refused', () => {
  assert.throws(() => aggregateLocalProfiles([observation(0), observation(0)], options), /DuplicateObservation/);
  assert.throws(() => validateLocalObservation(observation(0, {ownerAccepted: false})), /UnacceptedSuccess/);
  const negative = observation(0); negative.metrics.cleanupMs = -1;
  assert.throws(() => validateLocalObservation(negative), /InvalidDuration/);
  const doubled = observation(0); doubled.metrics.coldMs = doubled.metrics.processCycleMs;
  assert.throws(() => validateLocalObservation(doubled), /ColdBoundaryMismatch/);
});

test('overhead keeps all three fixed matched pairs and negative deltas without a bound', () => {
  const records = nativeProfileSchedule().map(step => {
    const item = observation(step.index, {round: step.round}); item.conditions.realization = step.realization;
    item.conditions.captureMode = step.mode;
    item.capture.status = step.mode === 'off' ? 'omitted' : 'complete';
    item.metrics.processCycleMs = step.mode === 'off' ? 100 : 90;
    item.metrics.observedEndToEndMs = step.mode === 'off' ? 101 : 102;
    return item;
  });
  const result = describeObservationOverhead(records);
  assert.equal(result.length, 4); assert(result.every(item => item.pairs.length === 3));
  assert(result.every(item => item.processCycleDelta.median === -10 && item.endToEndDelta.median === 1));
  records[0].outcome = 'interrupted';
  assert.equal(describeObservationOverhead(records)[0].status, 'unknown');
});

test('real bounded Evidence sink saves exactly supplied execution bytes and verifies digests', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-profile-capture-'));
  try {
    const stdout = 'actual-test-owned-stream\r\ne\u0301\n', stderr = 'diagnostic\n';
    const result = await captureLocalExecution({mode: 'evidence-enabled', directory,
      metadata: {source: 'synthetic'}, stdout, stderr});
    assert.equal(result.status, 'complete'); assert.equal(result.files.length, 3);
    assert.equal(await readFile(join(directory, 'stdout.log'), 'utf8'), stdout);
    for (const file of result.files) assert.equal(profileDigest(await readFile(join(directory, file.path))), file.digest);
    const again = await captureLocalExecution({mode: 'evidence-enabled', directory, metadata: {}, stdout: 'different', stderr});
    assert.equal(again.status, 'failed'); assert.equal(await readFile(join(directory, 'stdout.log'), 'utf8'), stdout);
  } finally {await rm(directory, {recursive: true, force: true});}
});

test('off reads no payload; metadata mode stores no raw stream; overflow and sink failure stay explicit', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-profile-modes-'));
  try {
    const off = await captureLocalExecution({mode: 'off', directory,
      get stdout() {throw new Error('forbidden payload access');}});
    assert.equal(off.status, 'omitted'); assert.deepEqual(await readdir(directory), []);
    const limited = await captureLocalExecution({mode: 'evidence-enabled', directory,
      metadata: {}, stdout: 'too large', stderr: '', maxBytes: 1});
    assert.equal(limited.status, 'missing'); assert.deepEqual(await readdir(directory), []);
    const metadata = join(directory, 'metadata'); await mkdir(metadata);
    const small = await captureLocalExecution({mode: 'metadata-only', directory: metadata,
      metadata: {}, stdout: 'must not be saved', stderr: ''});
    assert.equal(small.status, 'complete'); assert.deepEqual(await readdir(metadata), ['capture-metadata.json']);
    const failed = await captureLocalExecution({mode: 'metadata-only', directory: join(directory, 'absent'), metadata: {}});
    assert.equal(failed.status, 'failed');
  } finally {await rm(directory, {recursive: true, force: true});}
});

test('offline partial interrupted experiment stays unknown and altered original is refused', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-profile-offline-'));
  try {
    const step = nativeProfileSchedule()[0], item = observation(0, {
      id: 'trial-0', outcome: 'interrupted', ownerAccepted: false, unknown: ['execution-incomplete'],
      capture: {status: 'missing', reason: 'capture-not-completed'}});
    item.conditions.realization = step.realization;
    item.metrics.recordingMs = null; item.metrics.observedEndToEndMs = null;
    const child = join(directory, item.id); await mkdir(child);
    const original = JSON.stringify(item) + '\n';
    await writeFile(join(child, 'observation.json'), original);
    item.originalRecordDigest = profileDigest(original); item.metrics.recordingMs = 1; item.metrics.observedEndToEndMs = 20;
    const fixture = retainedCase(workloads[2], 'text-1024', 1000);
    const report = {version: 'actql-local-native-profile-experiment/0.1', scheduleKind:'capture-mode-eighteen', schedule: nativeProfileSchedule(),
      caseId: fixture.id, dataStatistics: {expectedOutput: fixture.identity()}, observations: [item],
      revision: item.conditions.runtimeRevision, binaryDigest: item.conditions.binaryDigest,
      instrumentationRevision: item.conditions.instrumentationRevision, freshnessPolicy: {minimumSamples: 3}};
    await writeFile(join(directory, 'experiment.json'), JSON.stringify(report));
    const result = await readLocalNativeProfile(directory, options);
    assert.equal(result.executions, 1); assert.equal(result.profiles[0].status, 'unknown');
    assert.equal(result.profiles[0].statuses.interrupted, 1);
    await writeFile(join(child, 'observation.json'), original + ' ');
    await assert.rejects(readLocalNativeProfile(directory, options), /OriginalObservationMismatch/);
  } finally {await rm(directory, {recursive: true, force: true});}
});

test('an unobserved quantity stays unknown even in a complete execution profile', () => {
  const samples = [0, 1, 2].map(index => {const item = observation(index); item.metrics.executionMs = null; return item;});
  const [profile] = aggregateLocalProfiles(samples, options);
  assert.equal(profile.metrics.executionMs.status, 'unknown'); assert.equal(profile.metrics.executionMs.median, null);
  assert.equal(profile.metrics.processCycleMs.status, 'descriptive-only');
});

test('native crash is a failure; process interruption never confirms cancellation or cleanup', () => {
  assert.equal(localProcessFailureOutcome({signal:'SIGABRT',killed:false}), 'failed');
  assert.equal(localProcessFailureOutcome({signal:'SIGSEGV'}), 'failed');
  assert.equal(localProcessFailureOutcome({code:1}), 'failed');
  for (const signal of ['SIGINT','SIGTERM','SIGKILL']) assert.equal(localProcessFailureOutcome({signal}), 'interrupted');
  assert.equal(localProcessFailureOutcome({killed:true}), 'interrupted');
});
