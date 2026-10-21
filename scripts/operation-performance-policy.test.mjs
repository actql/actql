import assert from 'node:assert/strict';
import test from 'node:test';
import {operationTargets, calibrateSqliteComparisonProfile, calibratedLatencyTarget,
  assessLatency} from './operation-performance.mjs';
import {syntheticSQLiteBaseline} from './fixtures/operation-performance-comparison.mjs';

// Independent arithmetic and policy expectations. Synthetic timings never
// establish a measured baseline or product latency.
const warm = ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum'];
const cohort = '1'.repeat(64), fixture = '2'.repeat(64), environment = '3'.repeat(64);
function evidence(operation, ms = 1) {
  const target = operationTargets[operation];
  return {operation, mode: 'final', profiled: false, load: 'isolated',
    cohortSha256: cohort, fixtureSha256: fixture, environmentSha256: environment,
    samples: Array.from({length: target.samples}, (_, iteration) => ({iteration,
      wallNs: ms * 1e6, cpuUserUs: 0, cpuSystemUs: 0, cpuScope: 'synthetic-oracle-test',
      cohortSha256: cohort, fixtureSha256: fixture,
      pid: operation === 'cold-existing' ? iteration + 1 : 1,
      hostId: 'same-warm-host', stateId: operation === 'first-init' ? `new-${iteration}` : 'same-state',
      completed: true, verified: true}))};
}
const comparison = baseline => ({baseline, profile: calibrateSqliteComparisonProfile(baseline)});
function matchedDiagnostic(operation, control) {
  const entry = control.profile.entries.find(row => row.operation === operation);
  const row = evidence(operation);
  Object.assign(row, {environmentSha256: control.profile.environmentSha256,
    fixtureSha256: entry.fixtureSha256, expectedSha256: entry.expectedSha256,
    executableSha256: control.baseline.executableSha256,
    comparisonSettings: structuredClone(control.profile.settings), comparisonMatch: structuredClone(entry.conditions)});
  row.samples.forEach(sample => {sample.fixtureSha256 = row.fixtureSha256;});
  return row;
}

test('warm targets require measured comparison instead of immutable absolute thresholds', () => {
  for (const operation of warm) {
    assert.deepEqual(operationTargets[operation], {samples: 100, comparison: 'local-sqlite'});
    assert.equal(assessLatency(evidence(operation)).status, 'incomplete');
  }
});
test('diagnostic calibration uses a fixed ratio, raw jitter and one measured minimum control', () => {
  const baseline = syntheticSQLiteBaseline();
  baseline.warm.find(row => row.operation === 'warm-select').samples.slice(94)
    .forEach(row => {row.wallNs = 4e6;});
  const profile = calibrateSqliteComparisonProfile(baseline);
  const select = profile.entries.find(row => row.operation === 'warm-select');
  // median=2, p95=4, jitter=2, minimum control=3; no candidate durations.
  assert.equal(select.noiseMs, 2);
  assert.equal(select.medianMs, 11); // 3*2 + 2 + 3
  assert.equal(select.p95Ms, 17); // 3*4 + 2 + 3
  for (const operation of ['warm-result', 'warm-status']) {
    const entry = profile.entries.find(row => row.operation === operation);
    assert.deepEqual([entry.medianMs, entry.p95Ms], [6, 6]);
    assert.equal(entry.essentialOverhead.medianMs, 0); // pure indexed-read diagnostic only
    assert.match(entry.conditions.durability, /diagnostic/u);
  }
  assert.match(profile.qualification, /not an unconditional SDK SLA/u);
});
test('matching literal data cannot supply missing public durable-transition correspondence', () => {
  const control = comparison(syntheticSQLiteBaseline());
  for (const operation of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union']) {
    const row = matchedDiagnostic(operation, control);
    for (const ms of [0.001, 187, 968]) {
      row.samples.forEach(sample => {sample.wallNs = ms * 1e6;});
      const result = assessLatency(row, control);
      assert.equal(result.status, 'incomplete');
      assert(result.missing.includes('matched minimum public essential-work comparator'));
      assert.equal(result.target.p95Ms, undefined);
    }
  }
  assert.equal(control.profile.entries.some(row => row.operation === 'warm-decimal-sum'), false);
});
test('diagnostic fixed policy cannot be fitted to a candidate or raised in its report', () => {
  const control = comparison(syntheticSQLiteBaseline()), row = matchedDiagnostic('warm-select', control);
  const before = JSON.stringify(control);
  row.samples.forEach(sample => {sample.wallNs = 968e6;});
  assessLatency(row, control);
  assert.equal(JSON.stringify(control), before);
  control.profile.entries[0].p95Ms = 1000;
  assert.throws(() => calibratedLatencyTarget(row, control), /differs from fixed/u);
});
test('runtime, load, exact fixture and observed comparison conditions remain separate matches', () => {
  const control = comparison(syntheticSQLiteBaseline());
  for (const [key, value, expected] of [
    ['environmentSha256', environment, 'environment/load'], ['load', 'concurrent', 'environment/load'],
    ['executableSha256', fixture, 'runtime executable'], ['fixtureSha256', fixture, 'fixture/oracle'],
    ['expectedSha256', fixture, 'fixture/oracle'], ['comparisonSettings', {}, 'transaction/durability'],
    ['comparisonMatch', {}, 'data/indexes/materialization']]) {
    const row = matchedDiagnostic('warm-select', control); row[key] = value;
    assert(calibratedLatencyTarget(row, control).missing.some(reason => reason.includes(expected)), key);
  }
});
test('incomplete, failed, foreign or undersampled comparator observations refuse calibration', () => {
  for (const mutate of [b => {b.cleanup.closed = false;}, b => {b.profiled = true;},
    b => {b.protocolSha256 = fixture;}, b => {b.settings.synchronous = 0;},
    b => {b.warm[0].samples.pop();}, b => {b.warm[0].samples[1].index = 0;},
    b => {b.warm[0].samples[0].verified = false;}, b => {b.warm[0].samples[0].outputSha256 = fixture;}]) {
    const baseline = syntheticSQLiteBaseline(); mutate(baseline);
    assert.throws(() => calibrateSqliteComparisonProfile(baseline));
  }
});
for (const [operation, p95Ms] of [['cold-existing', 2000], ['first-init', 5000], ['mock-workflow', 5000]]) {
  test(`${operation} retains its separately reported guardrail and sample minimum`, () => {
    const row = evidence(operation, p95Ms);
    assert.deepEqual(operationTargets[operation], {samples: 30, p95Ms});
    assert.equal(assessLatency(row).status, 'passed');
    row.samples.slice(28).forEach(sample => {sample.wallNs += 1;});
    assert(assessLatency(row).failures.includes('p95 latency exceeds target'));
    row.samples.pop();
    assert.equal(assessLatency(row).summary.p95Ms, null);
  });
}
