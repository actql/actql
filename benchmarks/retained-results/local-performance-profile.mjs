// Descriptive, condition-scoped local observations; never planner authority.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

export const captureModes = Object.freeze(['off', 'metadata-only', 'evidence-enabled']);
export const profileMetrics = Object.freeze(['processCycleMs', 'coldMs', 'warmMs',
  'cleanupMs', 'executionMs', 'captureMs', 'recordingMs', 'observedEndToEndMs']);
const outcomes = ['succeeded', 'failed', 'cancelled', 'interrupted', 'unobserved'];
export const profileDigest = value => 'sha256:' + createHash('sha256')
  .update(typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value)).digest('hex');
const duration = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;

export function nativeProfileSchedule() {
  return Array.from({length: 3}, (_, round) => {
    const modes = round === 0 ? captureModes : round === 1
      ? [...captureModes].reverse() : [...captureModes.slice(1), captureModes[0]];
    const legs = round % 2 ? ['resident', 'fresh'] : ['fresh', 'resident'];
    return modes.flatMap(mode => legs.map(realization => ({round, mode, realization})));
  }).flat().map((entry, index) => Object.freeze({...entry, index}));
}

export const nativeOperationalSchedule = () => Array.from({length: 3}, (_, round) =>
  ['fresh', 'resident'].map(realization => ({round, mode: 'metadata-only', realization})))
  .flat().map((entry, index) => Object.freeze({...entry, index}));

// Every arm sees the same resident-enabled offer configuration. The intervention
// is recorded separately from conditions; chosen realization stays in mapping.
export function nativeEmpiricalSchedule(stage) {
  assert(['comparison', 'evaluation'].includes(stage));
  const arms = stage === 'comparison' ? ['position-0', 'position-7'] : ['empirical', 'offline-fallback'];
  return Array.from({length:3}, (_, round) => (round % 2 ? [...arms].reverse() : arms)
    .map(arm => ({round, mode:'metadata-only', realization:'resident', arm})))
    .flat().map((entry,index) => Object.freeze({...entry,index}));
}

export function validateLocalObservation(value) {
  assert.equal(value?.version, 'actql-local-performance-observation/0.1');
  assert.equal(typeof value.id, 'string');
  assert(outcomes.includes(value.outcome), 'InvalidObservationOutcome');
  assert(captureModes.includes(value.conditions?.captureMode), 'InvalidCaptureMode');
  assert.equal(value.conditions.host, 'native');
  assert.equal(value.conditions.concurrency, 1);
  assert.equal(value.conditions.osCache, 'uncontrolled');
  for (const key of ['runtimeRevision', 'binaryDigest', 'inputDigest', 'programDigest',
    'instrumentationRevision', 'measurementScopeRevision', 'environmentDigest', 'controlDigest']) {
    assert.equal(typeof value.conditions[key], 'string', `MissingCondition:${key}`);
    assert(value.conditions[key].length > 0, `EmptyCondition:${key}`);
  }
  assert(Number.isSafeInteger(value.conditions.inputRows) && value.conditions.inputRows > 0);
  assert.equal(value.conditions.processState, 'new-process-and-environment');
  assert(Number.isFinite(value.observedAt) && value.observedAt >= 0);
  assert(['complete', 'missing', 'failed', 'omitted'].includes(value.capture?.status));
  assert(Array.isArray(value.unknown));
  for (const metric of profileMetrics) assert(value.metrics[metric] === null ||
    duration(value.metrics[metric]), `InvalidDuration:${metric}`);
  if (value.outcome === 'succeeded') {
    assert.equal(value.ownerAccepted, true, 'UnacceptedSuccess');
    assert.equal(typeof value.candidateSnapshotDigest, 'string');
    assert(Array.isArray(value.mapping?.choices) && value.mapping.choices.length > 0);
    assert.equal(value.mapping.attemptIdentity, 'unknown-counter-correspondence-only');
    assert.equal(value.mapping.hostSelection, 'explicit-experiment-condition');
    assert.equal(value.mapping.selectionMode, 'experiment-controlled-real-planner');
    for (const metric of ['processCycleMs', 'coldMs', 'warmMs', 'cleanupMs']) {
      assert(duration(value.metrics[metric]), `MissingSuccessDuration:${metric}`);
    }
    assert(Math.abs(value.metrics.coldMs + value.metrics.cleanupMs -
      value.metrics.processCycleMs) < 0.000001, 'ColdBoundaryMismatch');
  } else {
    // Censored/failed durations may describe elapsed work, never a completed time.
    assert.equal(value.ownerAccepted, false);
  }
  return value;
}

const descriptive = values => {
  if (!values.length) return {count: 0, median: null, min: null, max: null};
  const ordered = [...values].sort((a, b) => a - b), mid = Math.floor(ordered.length / 2);
  return {count: ordered.length, median: ordered.length % 2 ? ordered[mid]
    : (ordered[mid - 1] + ordered[mid]) / 2, min: ordered[0], max: ordered.at(-1)};
};

// Exact condition partitioning prevents mode, binary, limits or environment mixing.
export function aggregateLocalProfiles(observations, {now, maxAgeMs, minimumSamples = 3}) {
  assert(Array.isArray(observations) && observations.length <= 18, 'ProfileObservationLimit');
  assert(duration(now) && duration(maxAgeMs) && maxAgeMs > 0, 'InvalidProfileFreshness');
  assert(Number.isSafeInteger(minimumSamples) && minimumSamples >= 1 && minimumSamples <= 18);
  const ids = new Set(), groups = new Map();
  for (const item of observations) {
    validateLocalObservation(item);
    assert(!ids.has(item.id), 'DuplicateObservation'); ids.add(item.id);
    const key = profileDigest(item.conditions);
    const group = groups.get(key) ?? {key, conditions: item.conditions, items: []};
    group.items.push(item); groups.set(key, group);
  }
  return [...groups.values()].map(({key, conditions, items}) => {
    const statuses = Object.fromEntries(outcomes.map(outcome => [outcome,
      items.filter(item => item.outcome === outcome).length]));
    const reasons = [];
    const successes = items.filter(item => item.outcome === 'succeeded');
    const eligible = successes.filter(item => !item.unknown.length &&
      (conditions.captureMode === 'off' ? item.capture.status === 'omitted'
        : item.capture.status === 'complete') &&
      item.observedAt <= now && now - item.observedAt <= maxAgeMs);
    if (items.some(item => item.observedAt > now || now - item.observedAt > maxAgeMs)) reasons.push('freshness-insufficient');
    if (successes.some(item => item.unknown.length ||
      (conditions.captureMode === 'off' ? item.capture.status !== 'omitted'
        : item.capture.status !== 'complete'))) reasons.push('observation-incomplete');
    if (eligible.length < minimumSamples) reasons.push('samples-insufficient');
    const metrics = Object.fromEntries(profileMetrics.map(metric => {
      const summary = descriptive(eligible.map(item => item.metrics[metric]).filter(duration));
      return [metric, {...summary, status: summary.count >= minimumSamples ? 'descriptive-only' : 'unknown'}];
    }));
    return {version: 'actql-local-performance-profile/0.1', key, conditions,
      status: reasons.length ? 'unknown' : 'descriptive-only', reasons, statuses,
      attempted: items.length, compatibleCompleteSuccesses: eligible.length,
      metrics, observationIds: items.map(item => item.id),
      latestObservationAt: Math.max(...items.map(item => item.observedAt)),
      earliestObservationAt: Math.min(...items.map(item => item.observedAt)),
      freshnessPolicy: {maxAgeMs, minimumSamples},
      calibration: 'not-calibrated', precision: 'not-established',
      populationFailureRate: null, plannerEstimate: null};
  });
}

export function matchLocalProfile(profile, conditions, {now, maxAgeMs}) {
  assert.equal(profile.key, profileDigest(profile.conditions), 'ProfileConditionKeyMismatch');
  if (profile.key !== profileDigest(conditions)) return {status: 'unknown', reason: 'conditions-mismatch'};
  if (!duration(now) || !duration(maxAgeMs) || maxAgeMs <= 0 ||
    profile.latestObservationAt > now || now - profile.earliestObservationAt > maxAgeMs) {
    return {status: 'unknown', reason: 'freshness-insufficient'};
  }
  return {status: profile.status, reason: profile.status === 'unknown' ? profile.reasons : null,
    plannerEstimate: null};
}

// Paired diagnostic differences are descriptions, not confidence or causal bounds.
export function describeObservationOverhead(observations) {
  const differences = [];
  for (const realization of ['fresh', 'resident']) {
    for (const mode of captureModes.slice(1)) {
      const paired = [];
      for (let round = 0; round < 3; round++) {
        const items = observations.filter(item => item.round === round &&
          item.conditions.realization === realization);
        const baseline = items.find(item => item.conditions.captureMode === 'off');
        const observed = items.find(item => item.conditions.captureMode === mode);
        if (baseline?.outcome === 'succeeded' && observed?.outcome === 'succeeded' &&
          !baseline.unknown.length && !observed.unknown.length && observed.capture.status === 'complete') {
          const common = value => ({...value.conditions, captureMode: null});
          assert.deepEqual(common(baseline), common(observed), 'OverheadConditionsMismatch');
          paired.push({round, processCycleMs: observed.metrics.processCycleMs - baseline.metrics.processCycleMs,
            observedEndToEndMs: observed.metrics.observedEndToEndMs - baseline.metrics.observedEndToEndMs});
        }
      }
      differences.push({realization, mode, pairs: paired,
        processCycleDelta: descriptive(paired.map(item => item.processCycleMs)),
        endToEndDelta: descriptive(paired.map(item => item.observedEndToEndMs)),
        status: paired.length === 3 ? 'descriptive-only' : 'unknown',
        scope: 'matched local modes; order/environment variation not causally separated; no overhead upper bound'});
    }
  }
  return differences;
}
