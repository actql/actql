// Local descriptive references. No planner selection, Source access or exporter.
import assert from 'node:assert/strict';
import {open, constants} from 'node:fs/promises';
import {join} from 'node:path';
import {readLocalNativeProfile} from './read-local-native-profile.mjs';
import {profileDigest} from './local-performance-profile.mjs';

export async function loadLocalOperationalProfile(directory, options) {
  // The directory is supplied by the trusted caller, never by a sidecar.
  const admitted = await readLocalNativeProfile(directory, options);
  const file = await open(join(directory, 'experiment.json'), constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    assert((await file.stat()).size <= 40 * 1024 * 1024, 'OperationalProfileLimit');
    const bytes = await file.readFile(); assert(bytes.length <= 40 * 1024 * 1024);
    assert.equal(profileDigest(bytes), admitted.reportDigest, 'ProfileChangedDuringAdmission');
    const report = JSON.parse(bytes);
    assert.equal(report.revision, admitted.revision);
    return freeze({report, admitted, profileRevision: profileDigest(bytes)});
  } finally {await file.close();}
}

const freeze = value => {
  if (value && typeof value === 'object') {Object.values(value).forEach(freeze); Object.freeze(value);}
  return value;
};

const summary = values => {
  if (!values.length) return {median_ms: null, minimum_ms: null, maximum_ms: null};
  assert(values.every(value => Number.isFinite(value) && value >= 0));
  const sorted = [...values].sort((a, b) => a - b), middle = Math.floor(sorted.length / 2);
  return {median_ms: sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2,
    minimum_ms: sorted[0], maximum_ms: sorted.at(-1)};
};

export function localOperationalTemplate({profile, conditions, task, candidates, now, maxAgeMs = 86400000}) {
  assert(Number.isSafeInteger(now) && now >= 0 && Number.isSafeInteger(maxAgeMs) && maxAgeMs > 0 && maxAgeMs <= 86400000);
  assert(Number.isSafeInteger(task) && task > 0);
  const body = JSON.parse(candidates.canonical_json);
  assert.equal(profileDigest(candidates.canonical_json), candidates.cid, 'CandidateBytesMismatch');
  assert.equal(body[0], 'actql-policy-candidates/0.1');
  assert(profile.report.observations.length > 0, 'ProfileHasNoObservations');
  const compatible = profile.report.observations.filter(item =>
    profileDigest(item.conditions) === profileDigest(conditions));
  const oldest = Math.min(...(compatible.length ? compatible : profile.report.observations).map(o => o.observedAt));
  const newest = Math.max(...(compatible.length ? compatible : profile.report.observations).map(o => o.observedAt));
  const complete = compatible.filter(item => item.outcome === 'succeeded' && item.ownerAccepted &&
    !item.unknown.length && item.capture.status === 'complete' && item.operatorMeasurements.status === 'observed');
  const commonReason = !compatible.length ? 'conditions-mismatch' : conditions.captureMode === 'off'
    ? 'physical-phase-observer-off' : now < newest || now - oldest > maxAgeMs
      ? 'freshness-insufficient' : complete.length < 3 ? 'samples-insufficient' : null;
  const entries = [];
  for (const assignment of body[5]) {
    if (!assignment[5][task]) continue;
    const position = assignment[0];
    const attributed = complete.filter(item => {
      const snapshot = item.mapping.candidateProjections.find(p => p.task === task);
      const choice = item.mapping.choices.find(p => p.task === task);
      return snapshot && profileDigest(JSON.stringify(snapshot.body)) === candidates.cid &&
        choice?.position === position && snapshot.body[5].some(a => a[0] === position);
    });
    for (const quantity of ['task-processing', 'task-release', 'resident-preparation', 'resident-import']) {
      const values = attributed.map(item => {
        const cost = item.operatorMeasurements;
        const measured = cost.tasks.find(p => p.task === task);
        if (quantity === 'task-processing') return measured?.executionMicroseconds / 1000;
        if (quantity === 'task-release') return measured?.releaseMicroseconds / 1000;
        const phase = quantity === 'resident-preparation' ? 'environment' : 'import';
        const actual = cost.physicalPhases?.intervals.filter(p => p.task === task && p.phase === phase);
        return actual?.length ? actual.reduce((sum, p) => sum + p.elapsedMicroseconds, 0) / 1000 : null;
      });
      const valid = values.filter(v => Number.isFinite(v) && v >= 0);
      const reason = commonReason ?? (attributed.length < 3 ? 'candidate-attribution-insufficient'
        : valid.length < 3 ? 'quantity-unobserved' : null);
      entries.push({position, task, quantity, status: reason ? 'unknown' : 'reference', reason: reason ?? '',
        ...summary(reason ? [] : valid), sample_count: valid.length});
    }
  }
  assert(entries.length <= 64, 'EstimateEntryLimit');
  const template = {version: 'actql-operational-estimate/0.1', profile_revision: profile.profileRevision,
    candidate_snapshot_cid: candidates.cid, conditions, oldest_ms: String(oldest), newest_ms: String(newest),
    max_age_ms: String(maxAgeMs), capture_ms: summary(complete.map(o => o.metrics.captureMs)).median_ms,
    overhead: 'unknown-no-off-comparison', entries};
  assert(Buffer.byteLength(JSON.stringify(template)) <= 60 * 1024, 'EstimateTemplateLimit');
  return template;
}

export function bindOperationalTemplate(template, pending) {
  assert.equal(template.candidate_snapshot_cid, pending.candidate_set_cid, 'SnapshotBindingMismatch');
  const body = {binding: {...pending}, ...template};
  assert(Buffer.byteLength(JSON.stringify(body)) <= 65536, 'EstimateBodyLimit');
  return body;
}
