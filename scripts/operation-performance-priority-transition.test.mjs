import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {assessPriorityTransition, assessPerformanceEvidence, priorityTransitionTarget} from './operation-performance.mjs';

// Synthetic reports test the assessor, not ordinary product performance.
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const sourceSha = 'a'.repeat(40), operations = ['warm-select', 'warm-result'];
function work(operation) {
  return {id: operation, operation, complete: true, overflow: false, unrelatedRunRows: 0, unrelatedEffectRows: 0,
    fullChecks: [], fullTotals: Object.fromEntries(['physical-validation', 'current-validation', 'account-evaluation',
      'row-admission', 'decode', 'parse', 'mac', 'hash', 'scope-digest', 'configuration-inventory'].map(kind => [kind, 0])),
    activity: {materialGetterCalls: 0, materialCacheHits: 0, decodeCalls: 0, databaseReads: 0, sqlPrepares: 0}};
}
function report(platform) {
  const identity = {cohortSha256: hash([platform, 'ordinary']), environmentSha256: hash([platform, 'environment']),
    historyProtocolSha256: hash('fixed public experiment')};
  const variants = [1, 2, 3].map(id => ({querySha256: hash(`SELECT ${id} AS id`), expectedSha256: hash([{id}])}));
  const originals = variants.map((row, id) => ({runRefSha256: hash(['seed-run', id]),
    resultRefSha256: hash(['seed-result', id]), expectedSha256: row.expectedSha256}));
  const latency = operations.map(operation => {
    const publicWorkload = operation === 'warm-select' ? {kind: 'new-durable-run-result-rows', fixtures: variants}
      : {kind: 'saved-original-result-rows', originals};
    const fixtureSha256 = hash(publicWorkload);
    return {...identity, operation, mode: 'final', fixtureSha256,
    profiled: false, load: 'isolated', stoppedEarly: false,
    publicWorkload,
    firstQuery: {publicOperationId: 'first-query', pid: 42, hostId: 'opened-host', stateId: 'new-state',
      wallNs: 3_000_000_000, cpuUserUs: 400_000, cpuSystemUs: 10_000, cpuScope: 'actual SDK process',
      runRefSha256: hash('first-run'), resultRefSha256: hash('first-result'),
      completed: true, verified: true, expectedSha256: variants[0].expectedSha256, actualSha256: variants[0].expectedSha256},
    samples: Array.from({length: 100}, (_, iteration) => {
      const variant = variants[iteration % 3], original = originals[iteration % 3];
      return {...identity, iteration, fixtureSha256,
        publicOperationId: `${operation}-${iteration}`, pid: 42, hostId: 'opened-host', stateId: 'new-state',
        wallNs: 200_000_000, cpuUserUs: 1000, cpuSystemUs: 10, cpuScope: 'actual SDK process',
        completed: true, verified: true, querySha256: variant.querySha256,
        expectedSha256: variant.expectedSha256, actualSha256: variant.expectedSha256,
        runRefSha256: operation === 'warm-select' ? hash(['new-run', iteration]) : original.runRefSha256,
        resultRefSha256: operation === 'warm-select' ? hash(['new-result', iteration]) : original.resultRefSha256};
    })};
  });
  const history = operations.flatMap(operation => [1, 10, 100, 1000].map(size => ({operation, size, supported: true,
    fixtureSha256: hash(operation), targetRowsRead: 1, databaseReads: 1, sqlPrepares: 1,
    materialGetterCalls: 1, materialCacheHits: 0, decodeCalls: 1, fullPhysicalValidations: 1,
    fullCurrentValidations: 1, fullRowAdmissions: 1, fullParses: 0, fullMacValidations: 1,
    fullHashValidations: 1, fullScopeDigests: 1, fullConfigurationInventories: 1,
    fullAccountEvaluations: 1, unrelatedRunRows: 0, unrelatedEffectRows: 0})));
  return {sourceSha, ...identity, executionPath: `${platform}-sdk`, installedPayloadsUnchanged: true,
    cleanup: {closed: true}, priorityConditions: {startedHost: true, noCompetingLargeBuild: true,
      guaranteesUnchanged: true, boundedTemporaryGrowth: true}, latency,
    functional: {...identity, rows: latency.map(series => ({operation: series.operation, completed: true,
      fixtureSha256: series.fixtureSha256, expectedSha256: hash(series.samples.map(row => row.expectedSha256)),
      actualSha256: hash(series.samples.map(row => row.actualSha256))}))},
    structure: {...identity, operations: operations.map(work)}, history: {...identity, rows: history},
    boundaries: {...identity, rows: [
      {case: 'deny-before-operation', outcome: 'rejected', sends: 0},
      {case: 'target-before-dispatch', outcome: 'rejected', sends: 0},
      {case: 'commit-unknown', outcome: 'unknown', blindResends: 0},
      {case: 'send-reply-lost', outcome: 'unknown', blindResends: 0},
      {case: 'reopen-cache-miss', sameRun: true, newRuns: 0},
      {case: 'cancel-or-budget', additionalWorkStopped: true, cleanupPossible: true, overwrittenAsSuccess: false}]},
    prioritySafety: {...identity, rows: [{case: 'no-preapproval-write', writesBeforeApproval: 0,
      explicitSignedApproval: true, previewTargetMatched: true}]}};
}
const input = () => ({sourceSha, platforms: {node: [report('node')], python: [report('python')]}});

test('a complete synthetic phase reports its limited purpose and never release acceptance', () => {
  const value = input(), actual = assessPriorityTransition(value);
  assert.equal(actual.status, 'passed');
  assert.deepEqual(actual.target, {samples: 100, medianMs: 250, p95Ms: 500});
  assert.deepEqual(priorityTransitionTarget, actual.target);
  assert.equal(actual.purpose, 'priority-transition-only');
  assert.equal(actual.releaseAccepted, false); assert.equal(actual.fullPerformanceAccepted, false);
  assert.equal(actual.gates.node.checks['warm-select latency'].summary.p95Ms, 200);
  assert.equal(actual.gates.node.checks['warm-select workload'].firstQueryMs, 3000);
  assert.notEqual(assessPerformanceEvidence(value.platforms.node[0]).status, 'passed');
});
test('both ordinary platforms and both raw public routes are mandatory', () => {
  for (const platform of ['node', 'python']) {
    const missing = input(); delete missing.platforms[platform];
    assert.equal(assessPriorityTransition(missing).status, 'incomplete');
    for (const operation of operations) {
      const value = input(); value.platforms[platform][0].latency = value.platforms[platform][0].latency.filter(row => row.operation !== operation);
      assert.equal(assessPriorityTransition(value).status, 'incomplete');
    }
  }
});
test('median and p95 ceilings apply independently to each platform and public route', () => {
  for (const platform of ['node', 'python']) for (const operation of operations) {
    for (const mutate of [rows => rows.forEach(row => {row.wallNs = 251_000_000;}),
      rows => rows.slice(94).forEach(row => {row.wallNs = 501_000_000;})]) {
      const value = input(); mutate(value.platforms[platform][0].latency.find(row => row.operation === operation).samples);
      assert.equal(assessPriorityTransition(value).status, 'failed');
    }
  }
});
test('first query is separate and cannot fill a missing warm sample or be blended into it', () => {
  const short = input(); short.platforms.node[0].latency[0].samples.pop();
  short.platforms.node[0].functional.rows[0].expectedSha256 = hash(short.platforms.node[0].latency[0].samples.map(row => row.expectedSha256));
  short.platforms.node[0].functional.rows[0].actualSha256 = hash(short.platforms.node[0].latency[0].samples.map(row => row.actualSha256));
  const actual = assessPriorityTransition(short);
  assert.equal(actual.status, 'incomplete'); assert.equal(actual.gates.node.checks['warm-select latency'].summary.p95Ms, null);
  for (const mutate of [row => {delete row.firstQuery;}, row => {delete row.firstQuery.publicOperationId;}]) {
    const value = input(); mutate(value.platforms.node[0].latency[0]);
    assert.equal(assessPriorityTransition(value).status, 'incomplete');
  }
  const blended = input(), row = blended.platforms.node[0].latency[0]; row.firstQuery.publicOperationId = row.samples[0].publicOperationId;
  assert.equal(assessPriorityTransition(blended).status, 'failed');
});
test('fixed-value repetition, reused new Runs and changed saved originals cannot qualify', () => {
  for (const mutate of [
    rows => rows.forEach(row => {row.querySha256 = rows[0].querySha256; row.expectedSha256 = rows[0].expectedSha256; row.actualSha256 = rows[0].actualSha256;}),
    rows => {rows[1].runRefSha256 = rows[0].runRefSha256;},
    rows => {rows[1].actualSha256 = hash('wrong');},
  ]) {
    const value = input(); mutate(value.platforms.node[0].latency[0].samples);
    assert.notEqual(assessPriorityTransition(value).status, 'passed');
  }
  const saved = input(); saved.platforms.python[0].latency[1].samples[0].runRefSha256 = hash('another-run');
  assert.equal(assessPriorityTransition(saved).status, 'failed');
  const single = input(), series = single.platforms.python[0].latency[1];
  series.samples.forEach(row => Object.assign(row, series.publicWorkload.originals[0], {actualSha256: series.publicWorkload.originals[0].expectedSha256}));
  single.platforms.python[0].functional.rows[1].expectedSha256 = hash(series.samples.map(row => row.expectedSha256));
  single.platforms.python[0].functional.rows[1].actualSha256 = hash(series.samples.map(row => row.actualSha256));
  assert.equal(assessPriorityTransition(single).status, 'incomplete');
});
test('workload identity and functional population cannot be replaced by a different successful oracle', () => {
  for (const mutate of [
    report => {report.latency[0].publicWorkload.fixtures.push({querySha256: hash('another query'), expectedSha256: hash('another value')});},
    report => {report.functional.rows[0].fixtureSha256 = hash('another fixture');},
    report => {report.functional.rows[0].expectedSha256 = hash('another passing population'); report.functional.rows[0].actualSha256 = hash('another passing population');},
    report => {report.latency[0].samples[0].runRefSha256 = report.latency[0].firstQuery.runRefSha256;},
    report => {report.latency[0].samples[0].resultRefSha256 = report.latency[0].firstQuery.resultRefSha256;},
    report => {report.latency[0].samples[1].stateId = 'another-state';},
  ]) {
    const value = input(); mutate(value.platforms.node[0]); assert.equal(assessPriorityTransition(value).status, 'failed');
  }
  for (const mutate of [report => {delete report.functional.rows[0].fixtureSha256;},
    report => {delete report.latency[0].firstQuery.runRefSha256;}]) {
    const value = input(); mutate(value.platforms.node[0]); assert.equal(assessPriorityTransition(value).status, 'incomplete');
  }
});
test('missing current collector metadata is incomplete rather than inferred from fixed SQL', () => {
  for (const key of ['publicWorkload', 'firstQuery']) {
    const value = input(); delete value.platforms.node[0].latency[0][key];
    assert.equal(assessPriorityTransition(value).status, 'incomplete');
  }
  const value = input(); delete value.platforms.python[0].priorityConditions;
  assert.equal(assessPriorityTransition(value).status, 'incomplete');
});
test('diagnostic, profiled, loaded and early-stop data cannot become a phase distribution', () => {
  for (const patch of [{mode: 'diagnostic'}, {profiled: true}, {load: 'concurrent'}, {stoppedEarly: true}]) {
    const value = input(); Object.assign(value.platforms.node[0].latency[0], patch);
    assert.equal(assessPriorityTransition(value).status, 'incomplete');
  }
  const value = input(); value.platforms.python[0].priorityConditions.noCompetingLargeBuild = false;
  assert.equal(assessPriorityTransition(value).status, 'incomplete');
});
test('mixed source/cohort/environment and wrong section binding are refused', () => {
  for (const mutate of [r => {r.sourceSha = 'b'.repeat(40);},
    r => {r.latency[0].cohortSha256 = hash('other');}, r => {r.structure.environmentSha256 = hash('other');}]) {
    const value = input(); mutate(value.platforms.python[0]); assert.throws(() => assessPriorityTransition(value));
  }
  const value = input(), original = value.platforms.python[0];
  value.platforms.python.push({...original, historyProtocolSha256: hash('another-history'), latency: [],
    functional: undefined, structure: undefined, history: undefined, boundaries: undefined, prioritySafety: undefined});
  assert.equal(assessPriorityTransition(value).status, 'incomplete');
});
test('once-work, history, actual Deny, approval, Unknown and original cleanup remain required', () => {
  for (const key of ['structure', 'history', 'boundaries', 'prioritySafety', 'cleanup']) {
    const value = input(); delete value.platforms.node[0][key];
    assert.equal(assessPriorityTransition(value).status, 'incomplete');
  }
  for (const mutate of [r => {r.history.rows[0].unrelatedRunRows = 1;},
    r => {r.prioritySafety.rows[0].writesBeforeApproval = 1;},
    r => {r.boundaries.rows.find(row => row.case === 'commit-unknown').blindResends = 1;},
    r => {const operation = r.structure.operations[0];
      operation.fullChecks = [{kind: 'current-validation', fact: 'same-original', revision: 1, required: true, fullCalls: 2}];
      operation.fullTotals['current-validation'] = 2;},
    r => {r.installedPayloadsUnchanged = false; r.packageFailure = 'payload changed';},
    r => {r.priorityConditions.boundedTemporaryGrowth = false;}]) {
    const value = input(); mutate(value.platforms.node[0]); assert.equal(assessPriorityTransition(value).status, 'failed');
  }
});
test('CLI has an explicit selection and missing raw artifacts remain nonzero', () => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-priority-assessment-'));
  try {
    const file = join(directory, 'input.json'), output = join(directory, 'output.json');
    writeFileSync(file, JSON.stringify(input()));
    const command = ['scripts/operation-performance.mjs', '--priority-transition', file, '--output', output];
    const passed = spawnSync(process.execPath, command, {encoding: 'utf8'});
    assert.equal(passed.status, 0, passed.stderr); assert.equal(JSON.parse(readFileSync(output)).releaseAccepted, false);
    writeFileSync(file, JSON.stringify({sourceSha, platforms: {}}));
    const missing = spawnSync(process.execPath, ['scripts/operation-performance.mjs', '--priority-transition', file], {encoding: 'utf8'});
    assert.equal(missing.status, 1); assert.equal(JSON.parse(missing.stdout).status, 'incomplete');
    writeFileSync(file, JSON.stringify(input()));
    const release = spawnSync(process.execPath, ['scripts/operation-performance.mjs', '--input', file], {encoding: 'utf8'});
    assert.notEqual(release.status, 0); assert(!release.stdout.includes('"status": "passed"'));
  } finally {rmSync(directory, {recursive: true, force: true});}
});
