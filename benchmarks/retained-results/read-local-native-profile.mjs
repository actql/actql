// Offline readback: original records remain immutable and no execution is launched.
import assert from 'node:assert/strict';
import {open, constants} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
import {nativeOwnerObservations, admitNativeOwnerObservations} from './native-owner-observations.mjs';
import {retainedCase, workloads} from './fixtures.mjs';
import {profileDigest, nativeProfileSchedule, nativeOperationalSchedule, nativeEmpiricalSchedule, validateLocalObservation,
  aggregateLocalProfiles, describeObservationOverhead} from './local-performance-profile.mjs';
import {captureLimitBytes} from './local-profile-capture.mjs';

async function boundedRead(path, maximum) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    assert(stat.isFile() && stat.size <= maximum, 'ProfileReadLimit');
    const bytes = await file.readFile(); assert(bytes.length <= maximum, 'ProfileReadLimit');
    return bytes;
  } finally {await file.close();}
}

export async function readLocalNativeProfile(directory, {now = Date.now(), maxAgeMs = 86400000} = {}) {
  const started = performance.now();
  const reportBytes = await boundedRead(join(directory, 'experiment.json'), 40 * 1024 * 1024);
  const report = JSON.parse(reportBytes);
  assert.equal(report.version, 'actql-local-native-profile-experiment/0.1');
  assert(['operational-six','capture-mode-eighteen','empirical-comparison','empirical-evaluation'].includes(report.scheduleKind), 'UnknownExperimentSchedule');
  assert.deepEqual(report.schedule, report.scheduleKind.startsWith('empirical-')
    ? nativeEmpiricalSchedule(report.scheduleKind.slice('empirical-'.length))
    : report.scheduleKind === 'operational-six' ? nativeOperationalSchedule() : nativeProfileSchedule(), 'ChangedExperimentSchedule');
  assert(report.observations.length <= 18);
  const fixture = retainedCase(workloads[2], 'text-1024', 1000);
  assert.equal(report.caseId, fixture.id);
  assert.deepEqual(report.dataStatistics.expectedOutput, fixture.identity(), 'IndependentExpectedOutputMismatch');
  for (const [index, item] of report.observations.entries()) {
    validateLocalObservation(item);
    const step = report.schedule[index];
    assert.equal(item.id, `trial-${index}`); assert.equal(item.round, step.round);
    assert.equal(item.conditions.captureMode, step.mode);
    assert.equal(item.conditions.realization, step.realization);
    if (report.scheduleKind.startsWith('empirical-') && item.outcome==='succeeded') {
      assert.deepEqual(item.intervention,{phase:report.scheduleKind.slice('empirical-'.length),arm:step.arm});
      const child=join(directory,item.id), stdout=await boundedRead(join(child,'native-stdout.log'),captureLimitBytes);
      const stderr=await boundedRead(join(child,'native-stderr.log'),captureLimitBytes);
      assert.equal(profileDigest(stdout),item.rawEvidence.stdoutDigest,'EmpiricalOriginalStreamMismatch');
      assert.equal(profileDigest(stderr),item.rawEvidence.stderrDigest,'EmpiricalOriginalStreamMismatch');
      const terminal=JSON.parse(stdout.toString('utf8').trim().split('\n').at(-1));
      assert.equal(terminal.rows_cid,fixture.identity().rowsCid);assert.deepEqual(terminal.usage,item.mapping.finalUsage);
      const owner=admitNativeOwnerObservations(nativeOwnerObservations(stdout.toString('utf8')),
        item.mapping.holdings,item.mapping.choices.map(choice=>choice.name),terminal.usage);
      assert.deepEqual(owner.observations.choices,item.mapping.choices);assert.deepEqual(owner.attempts,item.mapping.attempts);
      assert.deepEqual(owner.observations.candidates,item.mapping.candidateProjections);
    }
    assert.equal(item.conditions.runtimeRevision, report.revision);
    assert.equal(item.conditions.binaryDigest, report.binaryDigest);
    assert.equal(item.conditions.instrumentationRevision, report.instrumentationRevision);
    const child = join(directory, item.id);
    const bytes = await boundedRead(join(child, 'observation.json'), captureLimitBytes);
    assert.equal(profileDigest(bytes), item.originalRecordDigest, 'OriginalObservationMismatch');
    const original = JSON.parse(bytes);
    const projected = structuredClone(item); delete projected.originalRecordDigest;
    projected.metrics.recordingMs = null; projected.metrics.observedEndToEndMs = null;
    assert.deepEqual(original, projected, 'ObservationProjectionMismatch');
    if (item.capture.status === 'complete') {
      const expected = step.mode === 'metadata-only' && !item.capture.failureDiagnostic ? ['capture-metadata.json']
        : ['capture-metadata.json', 'stdout.log', 'stderr.log'];
      assert.deepEqual(item.capture.files.map(file => file.path), expected, 'CaptureMemberMismatch');
      assert(item.capture.bytes <= captureLimitBytes);
      let total = 0; const contents = new Map();
      for (const file of item.capture.files) {
        const raw = await boundedRead(join(child, file.path), captureLimitBytes);
        assert.equal(raw.length, file.bytes); assert.equal(profileDigest(raw), file.digest, 'CaptureDigestMismatch');
        total += raw.length; contents.set(file.path, raw.toString('utf8'));
      }
      assert.equal(total, item.capture.bytes);
      const metadata = JSON.parse(contents.get('capture-metadata.json'));
      if (item.outcome !== 'succeeded') {
        assert.equal(item.capture.failureDiagnostic, true);
        assert.deepEqual(metadata, item.failure);
        continue;
      }
      assert.equal(metadata.actualRowsCid, fixture.identity().rowsCid);
      assert.equal(metadata.expectedRowsCid, fixture.identity().rowsCid);
      assert.deepEqual(metadata.candidates, item.mapping.candidateProjections);
      assert.deepEqual(metadata.choices, item.mapping.choices);
      assert.equal(profileDigest(metadata.candidates), item.candidateSnapshotDigest);
      if (step.mode === 'evidence-enabled') {
        const stdout = contents.get('stdout.log');
        const terminal = JSON.parse(stdout.trim().split('\n').at(-1));
        assert.equal(terminal.rows_cid, fixture.identity().rowsCid);
        assert.deepEqual(terminal.usage, item.mapping.finalUsage);
        const owner = admitNativeOwnerObservations(nativeOwnerObservations(stdout),
          item.mapping.holdings, item.mapping.choices.map(choice => choice.name), terminal.usage);
        assert.deepEqual(owner.attempts, item.mapping.attempts);
        assert.deepEqual(owner.observations.candidates, metadata.candidates);
        assert.deepEqual(owner.observations.choices, metadata.choices);
      }
    }
  }
  const profiles = aggregateLocalProfiles(report.observations,
    {now, maxAgeMs, minimumSamples: report.freshnessPolicy.minimumSamples});
  return {revision: report.revision, reportDigest: profileDigest(reportBytes), executions: report.observations.length,
    profiles, overhead: describeObservationOverhead(report.observations),
    readbackAndAggregationMs: performance.now() - started,
    scope: 'offline local readback; no Actions provenance or empirical planner admission'};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv.length, 3, 'ExpectedLocalProfileDirectory');
  console.log(JSON.stringify(await readLocalNativeProfile(resolve(process.argv[2])), null, 2));
}
