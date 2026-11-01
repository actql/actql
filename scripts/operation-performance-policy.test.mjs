import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {operationTargets, calibrateSqliteComparisonProfile, calibratedLatencyTarget,
  assessLatency, publicLatencyTarget, assessPublicLatencySamples} from './operation-performance.mjs';
import {syntheticSQLiteBaseline, syntheticResultStorageControl} from './fixtures/operation-performance-comparison.mjs';

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
      peakRssBytes: 1024, rssScope: 'synthetic oracle RSS',
      cohortSha256: cohort, fixtureSha256: fixture,
      pid: operation === 'cold-existing' ? iteration + 1 : 1,
      hostId: 'same-warm-host', stateId: operation === 'first-init' ? `new-${iteration}` : 'same-state',
      publicTiming: operation.startsWith('warm-')
        ? {kind: operation === 'warm-status' ? 'public-status' : 'public-result', startNs: 1, observedNs: 2, endNs: 3}
        : {kind: 'process-result-close', startNs: 1, observedNs: 2, closeStartNs: 3, closeEndNs: 4, endNs: 5},
      completed: true, verified: true}))};
}
const comparison = baseline => ({baseline, profile: calibrateSqliteComparisonProfile(baseline)});
function materializedResultControl(baseline) {
  const control = syntheticResultStorageControl(baseline);
  const sha = text => createHash('sha256').update(text).digest('hex');
  control.schemaVersion = 2;
  control.protocol.materialization = {storedFormat: 'json-array-utf8', storedBytes: 10,
    storedSha256: sha('[{"id":1}]'), schemaFormat: 'actql-schema-json-utf8', schemaBytes: 41,
    schemaSha256: sha('{"id":{"nullable":false,"type":"number"}}'), outputFormat: 'jsonl-utf8',
    outputBytes: 9, outputSha256: sha('{"id":1}\n'),
    conversion: 'stored-array-and-schema -> JSONL -> ordinary-JS-records'};
  control.protocolSha256 = createHash('sha256').update(JSON.stringify(control.protocol)).digest('hex');
  for (const sample of control.samples) {
    sample.materialization = {storedBytes: 10, schemaBytes: 41, jsonlBytes: 9, decodedRows: 1,
      outputSha256: sha('{"id":1}\n')};
    sample.events.splice(2, 0, 'stored-array-decoded', 'jsonl-serialized');
  }
  return control;
}
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

test('warm targets require both absolute public E2E limits and measured comparison', () => {
  for (const operation of warm) {
    assert.deepEqual(operationTargets[operation], {samples: 100, comparison: 'local-sqlite',
      publicEndToEnd: true, p95Ms: 200, maxMs: 200});
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
      assert.equal(result.status, ms > 200 ? 'failed' : 'incomplete');
      assert(result.missing.includes('matched minimum public essential-work comparator'));
      assert.equal(result.target.p95Ms, 200);
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
test('Result storage control derives a whole-control limit without double-counting the indexed read', () => {
  const baseline = syntheticSQLiteBaseline(), control = syntheticResultStorageControl(baseline);
  control.samples.slice(94).forEach(row => {row.wallNs = 6e6;});
  const result = calibrateSqliteComparisonProfile(baseline, control).resultStorage;
  assert.equal(result.summary.medianMs, 4); assert.equal(result.summary.p95Ms, 6);
  assert.equal(result.noiseMs, 2);
  assert.equal(result.diagnosticLimits.medianMs, 14); // 3*4 + 2, not another indexed read
  assert.equal(result.diagnosticLimits.p95Ms, 20); // 3*6 + 2
  assert.match(result.coverage, /excludes Account/u);
});
test('Result storage evidence retains public total and incomplete non-storage work coverage', () => {
  const baseline = syntheticSQLiteBaseline(), resultControl = syntheticResultStorageControl(baseline);
  const control = {baseline, resultControl, profile: calibrateSqliteComparisonProfile(baseline, resultControl)};
  const row = matchedDiagnostic('warm-result', control);
  row.samples.forEach(sample => {sample.wallNs = 20e6;});
  const absent = assessLatency(row, control);
  assert(absent.missing.includes('actual Result key/body/group correspondence'));
  row.resultStorageMatch = structuredClone(control.profile.resultStorage.conditions);
  const result = assessLatency(row, control);
  assert.equal(result.status, 'incomplete');
  assert(result.missing.includes('required public work coverage outside the storage control'));
  assert.deepEqual(result.resultStorage.medianMs, {publicMs: 20, storageControlMs: 4, ratio: 5,
    deltaMs: 16, diagnosticLimitMs: 12, publicAcceptance: 'unmatched'});
  assert.equal(result.target.p95Ms, 200);
});
test('Result storage success samples cannot hide failed cleanup, changed groups, foreign runtime or missing raw facts', () => {
  for (const mutate of [c => {c.cleanup.closed = false;}, c => {c.failure = {message: 'close failed'};},
    c => {c.profiled = true;}, c => {c.executableSha256 = fixture;}, c => {c.settings = {...c.settings, synchronous: 0};},
    c => {c.ownerMapping.groups.reverse();}, c => {c.protocolSha256 = fixture;}, c => {c.samples.pop();},
    c => {c.samples[0].counts.commits = 2;}, c => {c.samples[0].counts.rollbacks = 1;},
    c => {c.samples[0].events.reverse();}, c => {c.samples[0].verified = false;},
    c => {c.samples[0].phases.clock.commitNs = 10;}, c => {c.samples[0].wallNs = 0;},
    c => {c.samples[1].attemptCid = c.samples[0].attemptCid;}, c => {c.samples[1].pid = 2;}]) {
    const baseline = syntheticSQLiteBaseline(), control = syntheticResultStorageControl(baseline);
    mutate(control); assert.throws(() => calibrateSqliteComparisonProfile(baseline, control));
  }
});
test('Result v2 binds stored array, schema and output conversion without relabeling v1 profiles', () => {
  const baseline = syntheticSQLiteBaseline(), resultControl = materializedResultControl(baseline);
  const legacyControl = syntheticResultStorageControl(baseline);
  legacyControl.protocol.materialization = 'indexed JSONL payload -> all ordinary JS rows; literal oracle inside timed operation';
  legacyControl.protocolSha256 = createHash('sha256').update(JSON.stringify(legacyControl.protocol)).digest('hex');
  const legacy = calibrateSqliteComparisonProfile(baseline, legacyControl).resultStorage;
  const fixed = {baseline, resultControl, profile: calibrateSqliteComparisonProfile(baseline, resultControl)};
  assert.equal(Object.hasOwn(legacy.conditions, 'materialization'), false);
  assert.deepEqual(fixed.profile.resultStorage.conditions.materialization, resultControl.protocol.materialization);
  const row = matchedDiagnostic('warm-result', fixed);
  row.resultStorageMatch = structuredClone(legacy.conditions);
  assert(calibratedLatencyTarget(row, fixed).missing.includes('actual Result key/body/group correspondence'));
  row.resultStorageMatch = structuredClone(fixed.profile.resultStorage.conditions);
  const result = assessLatency(row, fixed);
  assert.equal(result.status, 'incomplete');
  assert(!result.missing.includes('actual Result key/body/group correspondence'));
  assert(result.missing.includes('required public work coverage outside the storage control'));
  assert.equal(resultControl.protocol.payload, '{"id":1}\n');
  assert.equal(fixed.profile.resultStorage.diagnosticLimits.medianMs, legacy.diagnosticLimits.medianMs);
});
test('Result v2 refuses missing or changed materialization observations, stages and version attribution', () => {
  for (const mutate of [c => {delete c.protocol.materialization;}, c => {c.schemaVersion = 1;},
    c => {c.schemaVersion = 3;}, c => {c.protocol.materialization.storedBytes = 9;},
    c => {c.protocol.materialization.schemaSha256 = fixture;},
    c => {c.protocol.materialization.outputSha256 = fixture;},
    c => {c.protocol.materialization.conversion = 'direct JSONL read';},
    c => {delete c.samples[0].materialization;}, c => {c.samples[0].materialization.storedBytes = 9;},
    c => {c.samples[0].materialization.schemaBytes = 0;}, c => {c.samples[0].materialization.jsonlBytes = 10;},
    c => {c.samples[0].materialization.decodedRows = 0;},
    c => {c.samples[0].materialization.outputSha256 = fixture;},
    c => {c.samples[0].events.splice(2, 1);}, c => {c.samples[0].events.reverse();}]) {
    const baseline = syntheticSQLiteBaseline(), control = materializedResultControl(baseline);
    mutate(control);
    control.protocolSha256 = createHash('sha256').update(JSON.stringify(control.protocol)).digest('hex');
    assert.throws(() => calibrateSqliteComparisonProfile(baseline, control));
  }
  const baseline = syntheticSQLiteBaseline(), legacy = syntheticResultStorageControl(baseline);
  legacy.samples[0].materialization = {storedBytes: 10};
  assert.throws(() => calibrateSqliteComparisonProfile(baseline, legacy));
});
test('synchronization comparison records explicit modes and refuses unmatched or missing fullfsync settings', () => {
  const baseline = syntheticSQLiteBaseline(); baseline.settings.fullfsync = 1;
  const control = syntheticResultStorageControl(baseline);
  const profile = calibrateSqliteComparisonProfile(baseline, control);
  assert.equal(profile.resultStorage.conditions.settings.fullfsync, 1);
  assert.equal(profile.resultStorage.conditions.settings.checkpoint_fullfsync, 0);
  assert.match(profile.resultStorage.qualification, /not an unconditional SDK SLA/u);
  control.settings = {...control.settings, fullfsync: 0};
  assert.throws(() => calibrateSqliteComparisonProfile(baseline, control), /durability differs/u);
  for (const key of ['fullfsync', 'checkpoint_fullfsync']) {
    const missing = syntheticSQLiteBaseline(); delete missing.settings[key];
    assert.throws(() => calibrateSqliteComparisonProfile(missing), /synchronization settings/u);
  }
});
test('synchronization requests cannot relabel a different measured mode', () => {
  const baseline = syntheticSQLiteBaseline();
  baseline.protocol.fullfsyncRequested = true;
  baseline.protocolSha256 = createHash('sha256').update(JSON.stringify(baseline.protocol)).digest('hex');
  assert.throws(() => calibrateSqliteComparisonProfile(baseline), /requested\/readback/u);
  baseline.settings.fullfsync = 1;
  const control = syntheticResultStorageControl(baseline);
  control.protocol.fullfsyncRequested = false;
  control.protocolSha256 = createHash('sha256').update(JSON.stringify(control.protocol)).digest('hex');
  assert.throws(() => calibrateSqliteComparisonProfile(baseline, control), /requested\/readback/u);
});
test('checkpoint synchronization differences remain visible when fullfsync makes them equivalent', () => {
  const baseline = syntheticSQLiteBaseline(); baseline.settings.fullfsync = 1;
  const resultControl = syntheticResultStorageControl(baseline);
  resultControl.settings = {...resultControl.settings, checkpoint_fullfsync: 1};
  const before = JSON.stringify({baseline, resultControl});
  const control = {baseline, resultControl, profile: calibrateSqliteComparisonProfile(baseline, resultControl)};
  const expected = {matched: true, equivalentDifferences: [{setting: 'checkpoint_fullfsync', observed: 1,
    comparator: 0, reason: 'fullfsync=1 selects full synchronization for all sync operations'}]};
  assert.deepEqual(control.profile.resultStorage.synchronizationComparison, expected);
  assert.equal(control.profile.settings.checkpoint_fullfsync, 0);
  assert.equal(control.profile.resultStorage.conditions.settings.checkpoint_fullfsync, 1);
  const row = matchedDiagnostic('warm-result', control);
  row.comparisonSettings.checkpoint_fullfsync = 1;
  row.resultStorageMatch = structuredClone(control.profile.resultStorage.conditions);
  row.resultStorageMatch.settings.checkpoint_fullfsync = 0;
  const assessed = assessLatency(row, control);
  assert.deepEqual(assessed.target.synchronizationComparison, expected);
  assert.deepEqual(assessed.target.resultStorageSynchronizationComparison.equivalentDifferences,
    [{...expected.equivalentDifferences[0], observed: 0, comparator: 1}]);
  assert(!assessed.missing.includes('matched stated transaction/durability settings'));
  assert(!assessed.missing.includes('actual Result key/body/group correspondence'));
  assert.equal(assessed.status, 'incomplete'); // No public essential-work or speed acceptance.
  assert.equal(JSON.stringify({baseline, resultControl}), before);
  const {resultStorage, ...withoutControl} = control.profile;
  assert.deepEqual(withoutControl, calibrateSqliteComparisonProfile(baseline));
});
test('checkpoint equivalence refuses missing, invalid, fullfsync-off and unrelated setting differences', () => {
  const baseline = syntheticSQLiteBaseline(); baseline.settings.fullfsync = 1;
  const control = comparison(baseline);
  for (const mutate of [s => {delete s.checkpoint_fullfsync;}, s => {s.checkpoint_fullfsync = 2;},
    s => {s.checkpoint_fullfsync = '1';}, s => {s.fullfsync = 0;}, s => {delete s.fullfsync;},
    s => {s.synchronous = 1;}, s => {s.sqliteVersion += '-foreign';}, s => {s.extra = true;}]) {
    const row = matchedDiagnostic('warm-select', control);
    row.comparisonSettings.checkpoint_fullfsync = 1;
    mutate(row.comparisonSettings);
    assert(calibratedLatencyTarget(row, control).missing.includes('matched stated transaction/durability settings'));
  }
  const off = syntheticSQLiteBaseline(), offControl = comparison(off);
  const row = matchedDiagnostic('warm-select', offControl); row.comparisonSettings.checkpoint_fullfsync = 1;
  assert(calibratedLatencyTarget(row, offControl).missing.includes('matched stated transaction/durability settings'));
  for (const b of [baseline, off]) {
    const result = syntheticResultStorageControl(b);
    result.settings = {...result.settings, checkpoint_fullfsync: b.settings.fullfsync ? 2 : 1};
    assert.throws(() => calibrateSqliteComparisonProfile(b, result), /durability differs/u);
  }
  const resultControl = syntheticResultStorageControl(baseline);
  const withResult = {baseline, resultControl, profile: calibrateSqliteComparisonProfile(baseline, resultControl)};
  const resultRow = matchedDiagnostic('warm-result', withResult);
  resultRow.resultStorageMatch = structuredClone(withResult.profile.resultStorage.conditions);
  resultRow.resultStorageMatch.settings.checkpoint_fullfsync = 1;
  resultRow.resultStorageMatch.bodyBytes.clock += 1;
  assert(calibratedLatencyTarget(resultRow, withResult).missing.includes('actual Result key/body/group correspondence'));
});
for (const [operation, p95Ms] of [['cold-existing', 200], ['first-init', 200], ['mock-workflow', 5000]]) {
  test(`${operation} retains its separately reported guardrail and sample minimum`, () => {
    const row = evidence(operation, p95Ms);
    assert.deepEqual(operationTargets[operation], operation === 'mock-workflow' ? {samples: 30, p95Ms}
      : {samples: 30, publicEndToEnd: true, p95Ms, maxMs: 200});
    assert.equal(assessLatency(row).status, 'passed');
    row.samples.slice(28).forEach(sample => {sample.wallNs += 1;});
    assert(assessLatency(row).failures.includes('p95 latency exceeds target'));
    row.samples.pop();
    assert.equal(assessLatency(row).summary.p95Ms, null);
  });
}

test('public cold 300ms p95 and 400ms maximum fail even below the old two-second guardrail', () => {
  const row = evidence('cold-existing', 300); row.samples.at(-1).wallNs = 400e6;
  const result = assessLatency(row);
  assert.equal(result.status, 'failed');
  assert.equal(result.summary.p95Ms, 300); assert.equal(result.summary.maxMs, 400);
  assert(result.failures.includes('public E2E p95 exceeds 200ms'));
  assert(result.failures.includes('public E2E observed max exceeds 200ms'));
});
test('a fast warm median or p95 cannot hide slow cold or one over-budget maximum', () => {
  const warm = evidence('warm-select', 5); warm.samples.at(-1).wallNs = 201e6;
  const observed = assessLatency(warm); assert.equal(observed.summary.p95Ms, 5);
  assert.equal(observed.status, 'failed'); assert.equal(observed.summary.maxMs, 201);
  assert.equal(assessLatency(evidence('cold-existing', 1000)).status, 'failed');
  assert.deepEqual(publicLatencyTarget, {p95Ms: 200, maxMs: 200});
});
test('every original raw sample remains in statistics, including a slow failed oracle', () => {
  const row = evidence('cold-existing', 5);
  Object.assign(row.samples.at(-1), {wallNs: 900e6, verified: false, completed: false});
  const result = assessLatency(row); assert.equal(result.status, 'failed');
  assert.equal(result.summary.count, 30); assert.equal(result.summary.maxMs, 900);
  assert.equal(result.verifiedSummary.count, 29);
});
test('clipped Result clocks and work deferred past the first close cannot qualify public E2E', () => {
  for (const timing of [
    {kind: 'public-result', startNs: 1, observedNs: 300e6, endNs: 2},
    {kind: 'process-result-close', startNs: 1, observedNs: 8, closeStartNs: 3, closeEndNs: 9, endNs: 10},
    {kind: 'process-result-close', startNs: 1, observedNs: 2, closeStartNs: 3, closeEndNs: 300e6, endNs: 300e6},
  ]) {
    const operation = timing.kind === 'public-result' ? 'warm-select' : 'cold-existing';
    const row = evidence(operation, 5); row.samples[0].publicTiming = timing;
    assert.equal(assessLatency(row).status, 'failed');
  }
  const row = evidence('cold-existing', 5); delete row.samples[0].publicTiming;
  assert.equal(assessLatency(row).status, 'incomplete');
  assert.equal(assessPublicLatencySamples(row.samples, 30, row.operation).missing.length, 1);
});
