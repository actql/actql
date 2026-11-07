import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {operationTargets, latencySummary, assessLatency as rawAssessLatency, calibrateSqliteComparisonProfile, calibratedLatencyTarget, assessStructure, assessHistory,
  recordOperationMeasurements, assessChunks, assessBoundaries, boundaryExpectations, collectOperationSamples, assessPerformanceEvidence, assessNativeOperations} from './operation-performance.mjs';

import {syntheticSQLiteBaseline} from './fixtures/operation-performance-comparison.mjs';
const baseline = syntheticSQLiteBaseline();
const comparison = {baseline, profile: calibrateSqliteComparisonProfile(baseline)};
const assessLatency = value => rawAssessLatency(value, comparison);
// Synthetic evidence exercises the acceptance oracle, never product latency.
const cohort = 'a'.repeat(64), fixture = 'b'.repeat(64), environment = comparison.profile.environmentSha256, protocol = 'e'.repeat(64);
function series(operation = 'warm-select', count = operationTargets[operation].samples, ms = 4) {
  const entry = comparison.profile.entries.find(row => row.operation === operation);
  const fixtureIdentity = entry?.fixtureSha256 ?? fixture;
  return {operation, mode: 'final', cohortSha256: cohort, fixtureSha256: fixtureIdentity,
    ...(entry ? {expectedSha256: entry.expectedSha256, comparisonMatch: structuredClone(entry.conditions),
      executableSha256: baseline.executableSha256, comparisonSettings: structuredClone(baseline.settings)} : {}),
    environmentSha256: environment, historyProtocolSha256: protocol, profiled: false, load: 'isolated', samples: Array.from({length: count}, (_, iteration) => ({
      iteration, cohortSha256: cohort, fixtureSha256: fixtureIdentity, wallNs: ms * 1e6,
      cpuUserUs: 1000, cpuSystemUs: 200, cpuScope: 'measured-process', pid: 1, hostId: 'host1', stateId: 'state1',
      peakRssBytes: 1024, rssScope: 'synthetic oracle RSS',
      publicTiming: operation.startsWith('warm-')
        ? {kind: operation === 'warm-status' ? 'public-status' : 'public-result', startNs: 1, observedNs: 2, endNs: 3}
        : {kind: 'process-result-close', startNs: 1, observedNs: 2, closeStartNs: 3, closeEndNs: 4, endNs: 5},
      completed: true, verified: true,
    }))};
}
function publicOperation(operation = 'warm-result', id = 'public-call-1') {
  const fullChecks = ['physical-validation', 'current-validation', 'row-admission', 'decode',
    'parse', 'mac', 'hash', 'scope-digest', 'configuration-inventory'].map(kind => ({
      kind, fact: 'original-row', revision: 7, required: true, fullCalls: 1}));
  for (const resource of ['run', 'result/main']) fullChecks.push({kind: 'account-evaluation',
    fact: 'original-account', revision: 'observed-row-7', required: true, fullCalls: 1,
    accountConfigurationCid: 'sha256:' + '1'.repeat(64), policyRevision: 'actual-policy-7',
    tuple: {subject: 'local-reviewer', connection: 'configured-a', operation: 'read', resource,
      run: 'original-run', target: null, authorityScope: 'original-authority'}});
  return {id, operation, complete: true, overflow: false, unrelatedRunRows: 0, unrelatedEffectRows: 0,
    fullChecks, fullTotals: {'physical-validation': 1, 'current-validation': 1, 'account-evaluation': 2,
      'row-admission': 1, decode: 1, parse: 1, mac: 1, hash: 1, 'scope-digest': 1, 'configuration-inventory': 1},
    activity: {materialGetterCalls: 7, materialCacheHits: 6, decodeCalls: 1,
      databaseReads: 3, sqlPrepares: 4}, unchangedStatus: true, statusWrites: 0, revisionBefore: 7, revisionAfter: 7};
}
const histories = () => Object.keys(operationTargets).filter(operation => operation.startsWith('warm-'))
  .flatMap(operation => [1, 10, 100, 1000].map(size => ({operation, size, supported: true, fixtureSha256: fixture,
  targetRowsRead: 3, databaseReads: 3, sqlPrepares: 4, materialGetterCalls: 7, materialCacheHits: 6,
  fullPhysicalValidations: 1, fullCurrentValidations: 1, fullRowAdmissions: 3, decodeCalls: 3,
  fullParses: 1, fullMacValidations: 3, fullHashValidations: 3, fullScopeDigests: 1,
  fullConfigurationInventories: 1, fullAccountEvaluations: 1, unrelatedRunRows: 0, unrelatedEffectRows: 0})));
const chunks = () => [1024, 16384, 262144].map(bytes => ({bytes, chunkBytes: 16384,
  chunks: Math.ceil(bytes / 16384), rows: 1, boundaries: 3, hostCalls: Math.ceil(bytes / 16384) + 4,
  scalarByteCalls: 0, complete: true, overflow: false}));

test('uses nearest-rank p95 and ordinary median from every raw sample', () => {
  const rows = Array.from({length: 100}, (_, n) => ({wallNs: (n + 1) * 1e6, cpuUserUs: 0, cpuSystemUs: 0}));
  assert.deepEqual(latencySummary(rows, 100), {count: 100, medianMs: 50.5, p95Ms: 95,
    maxMs: 100, quantile: 'nearest-rank', minimum: 100});
});
test('one successful sample has no acceptance p95', () => {
  const result = assessLatency(series('warm-select', 1));
  assert.equal(result.status, 'incomplete'); assert.equal(result.summary.p95Ms, null);
});
test('diagnostic SQLite limits never become unmatched public SDK thresholds', () => {
  assert.equal(assessLatency(series('warm-select', 100, 6)).status, 'incomplete');
  assert.equal(assessLatency(series('warm-select', 100, 968)).status, 'failed');
  assert.equal(rawAssessLatency(series()).status, 'incomplete');
  assert.equal(assessLatency(series('warm-decimal-sum')).status, 'incomplete');
  assert.equal(assessLatency(series('warm-result')).status, 'incomplete');
});
test('comparison retains public total, ratio and absolute delta without a false acceptance', () => {
  const value = series('warm-join', 100, 9);
  const result = assessLatency(value);
  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.diagnosticComparison.medianMs, {publicMs: 9, engineMs: 2,
    ratio: 4.5, deltaMs: 7, diagnosticLimitMs: 9, publicAcceptance: 'unmatched'});
  assert.equal(result.target.p95Ms, 200);
});
test('a diagnostic or profiled/loaded run cannot become final acceptance', () => {
  for (const patch of [{mode: 'diagnostic'}, {profiled: true}, {load: 'concurrent'}, {stoppedEarly: true}]) {
    assert.equal(assessLatency({...series(), ...patch}).status, 'incomplete');
  }
});
test('functional failures are retained, not filtered into a faster passed population', () => {
  const rows = series(); rows.samples[40].verified = false;
  const result = assessLatency(rows); assert.equal(result.status, 'failed');
  assert.equal(result.summary.count, 100); assert.equal(result.summary.p95Ms, 4);
  assert.equal(result.verifiedSummary.count, 99); assert.equal(result.verifiedSummary.p95Ms, null);
});
test('rejects mixed artifacts, fixtures, duplicate samples and impossible durations', () => {
  for (const mutate of [r => {r.cohortSha256 = 'd'.repeat(64);}, r => {r.fixtureSha256 = cohort;},
    r => {r.iteration = 0;}, r => {r.wallNs = NaN;}, r => {r.cpuUserUs = -1;}]) {
    const rows = series(); mutate(rows.samples[1]); assert.throws(() => assessLatency(rows));
  }
});
test('warm Host identity and cold process boundaries are different requirements', () => {
  const warm = series(); warm.samples[1].hostId = 'reopened';
  assert.equal(assessLatency(warm).status, 'failed');
  const cold = series('cold-existing', 30, 200);
  assert.equal(assessLatency(cold).status, 'failed');
  cold.samples.forEach((r, n) => {r.pid = n + 1;});
  assert.equal(assessLatency(cold).status, 'passed');
  cold.samples.pop(); assert.equal(assessLatency(cold).status, 'incomplete');
});
test('first-init requires independent states, not thirty opens of existing state', () => {
  const rows = series('first-init', 30, 200); assert.equal(assessLatency(rows).status, 'failed');
  rows.samples.forEach((r, n) => {r.stateId = `fresh${n}`;}); assert.equal(assessLatency(rows).status, 'passed');
});
test('missing counters are incomplete and not silently zero', () => {
  assert.equal(assessStructure({operations: []}).status, 'incomplete');
  assert.equal(assessStructure({frames: [{id: 'getter'}, {id: 'await'}]}).status, 'incomplete');
  const row = publicOperation(); delete row.unrelatedEffectRows;
  assert.equal(assessStructure({operations: [row]}).status, 'incomplete');
  const combined = publicOperation(); delete combined.fullChecks[0].fullCalls;
  combined.fullChecks[0].entriesIncludingCacheHits = 1;
  assert.equal(assessStructure({operations: [combined]}).status, 'incomplete');
  const absent = publicOperation(); delete absent.fullTotals['physical-validation'];
  assert.equal(assessStructure({operations: [absent]}).status, 'incomplete');
});
test('each required unchanged fact runs once across the whole public operation', () => {
  assert.equal(assessStructure({operations: [publicOperation()]}).status, 'passed');
  for (const check of publicOperation().fullChecks) {
    const row = publicOperation(); row.fullChecks.push({...check, frame: 'internal-helper', epoch: 'after-await'});
    assert.equal(assessStructure({operations: [row]}).status, 'failed', check.kind);
  }
});
test('an Account getter alias cannot split the same subject/permission/resource/Run/target', () => {
  const row = publicOperation(), check = row.fullChecks.find(value => value.kind === 'account-evaluation');
  row.fullChecks.push({...check, fact: 'renamed-helper-or-cache-eviction'});
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
});
test('raw Account evaluation cannot reset its budget when incidental Run, target or row context changes', () => {
  const row = publicOperation(), original = row.fullChecks.find(check => check.kind === 'account-evaluation');
  original.tuple = {...original.tuple, run: null, target: null};
  row.fullChecks.push({...original, revision: 'newly-discovered-run-row-8',
    tuple: {...original.tuple, run: 'discovered-run', target: 'discovered-target'}});
  row.fullTotals['account-evaluation'] = 3;
  const result = assessStructure({operations: [row]});
  assert.equal(result.status, 'failed');
  const duplicate = result.operations[0].accountEvaluations.find(check => check.fullCalls === 2);
  assert.deepEqual(duplicate.traceContexts.map(value => [value.run, value.target]),
    [[null, null], ['discovered-run', 'discovered-target']]);
  assert.equal(duplicate.revision, 'actual-policy-7');
  row.fullChecks.filter(check => check.kind === 'account-evaluation').forEach(check => {delete check.policyRevision;});
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
});
test('raw Account material and policy snapshots remain distinct while target-bound facts keep their own identity', () => {
  for (const changed of [{policyRevision: 'actual-policy-8'}, {accountConfigurationCid: 'sha256:' + '3'.repeat(64)}]) {
    const row = publicOperation(), original = row.fullChecks.find(check => check.kind === 'account-evaluation');
    row.fullChecks.push({...original, ...changed});
    row.fullTotals['account-evaluation'] = 3;
    assert.equal(assessStructure({operations: [row]}).status, 'passed');
  }
  const row = publicOperation(), current = row.fullChecks.find(check => check.kind === 'current-validation');
  row.fullChecks.push({...current, fact: 'different-original-bound-Run-and-target'});
  row.fullTotals['current-validation'] = 2;
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  const accounts = row.fullChecks.filter(check => check.kind === 'account-evaluation');
  accounts.forEach(check => {delete check.policyRevision; delete check.fact; delete check.revision;});
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  delete accounts[0].accountConfigurationCid;
  assert.equal(assessStructure({operations: [row]}).status, 'incomplete');
});
test('raw Account optional revision metadata cannot split the same evaluator inputs into passing budgets', () => {
  const row = publicOperation(), original = row.fullChecks.find(check => check.kind === 'account-evaluation');
  const missingRevision = {...original}; delete missingRevision.policyRevision;
  row.fullChecks.push(missingRevision); row.fullTotals['account-evaluation'] = 3;
  const result = assessStructure({operations: [row]});
  assert.equal(result.status, 'incomplete');
  assert(result.missing.some(reason => reason.includes('consistent actual Account policy revision attribution')));
  assert(result.operations[0].incompleteAttribution.includes('account-evaluation'));
});
test('Account connections remain distinct while private frames cannot split one connection permission', () => {
  const row = publicOperation(), original = row.fullChecks.find(check => check.kind === 'account-evaluation');
  row.fullChecks = row.fullChecks.filter(check => check.kind !== 'account-evaluation');
  row.fullChecks.push(original, {...original, tuple: {...original.tuple, connection: 'configured-b'}});
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  row.fullChecks.push({...original, fact: 'another-private-getter', frame: 'after-trusted-read'});
  row.fullTotals['account-evaluation'] = 3;
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
  const absent = publicOperation(); delete absent.fullChecks.find(check => check.kind === 'account-evaluation').tuple.connection;
  assert.throws(() => assessStructure({operations: [absent]}), /exact subject\/connection/u);
});
test('Account authority scopes are explicit or inherited only from the fixed public operation', () => {
  const row = publicOperation();
  const original = row.fullChecks.find(check => check.kind === 'account-evaluation');
  row.fullChecks.push({...original, tuple: {...original.tuple, authorityScope: 'other-authority'}});
  row.fullTotals['account-evaluation'] = 3;
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  const fixed = publicOperation(); fixed.authorityScope = 'original-authority';
  fixed.fullChecks.filter(check => check.kind === 'account-evaluation').forEach(check => {delete check.tuple.authorityScope;});
  assert.equal(assessStructure({operations: [fixed]}).status, 'passed');
  fixed.fullChecks.find(check => check.kind === 'account-evaluation').tuple.authorityScope = 'other-authority';
  assert.throws(() => assessStructure({operations: [fixed]}), /differs from the fixed public operation/u);
  delete row.fullChecks.find(check => check.kind === 'account-evaluation').tuple.authorityScope;
  assert.throws(() => assessStructure({operations: [row]}), /actual authority scope/u);
});
test('pure fact work runs zero heavy checks, without manufacturing an admission', () => {
  const row = publicOperation(); row.fullChecks.forEach(check => {check.required = false; check.fullCalls = 0;});
  Object.keys(row.fullTotals).forEach(kind => {row.fullTotals[kind] = 0;});
  row.activity.decodeCalls = 0;
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  assert.equal(assessStructure({operations: [{...row, fullChecks: []}]}).status, 'passed');
  row.fullChecks[0].fullCalls = 1;
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
});
test('material getters and cache hits are separate from full validation and actual decodes', () => {
  const row = publicOperation(); row.activity = {...row.activity, materialGetterCalls: 100, materialCacheHits: 99,
    databaseReads: 20, sqlPrepares: 30};
  row.fullChecks.push({...row.fullChecks[0], fullCalls: 0});
  const result = assessStructure({operations: [row]});
  assert.equal(result.status, 'passed');
  assert.equal(result.operations[0].fullCallsByKind['physical-validation'], 1);
  assert.equal(result.operations[0].activity.decodeCalls, 1);
  row.activity.materialCacheHits = 101;
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
});
test('decode calls cannot be hidden in DB reads or attributed only to cache entries', () => {
  const row = publicOperation(); row.activity.decodeCalls = 2;
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
  row.fullChecks = row.fullChecks.filter(check => check.kind !== 'decode');
  row.activity.decodeCalls = 1;
  assert.equal(assessStructure({operations: [row]}).status, 'incomplete');
  delete row.activity.sqlPrepares;
  assert.equal(assessStructure({operations: [row]}).status, 'incomplete');
});
test('distinct permissions and changed relevant revisions are not collapsed into one Allow', () => {
  const row = publicOperation();
  const auth = row.fullChecks.filter(check => check.kind === 'account-evaluation');
  assert.deepEqual(auth.map(check => check.tuple.resource), ['run', 'result/main']);
  row.fullChecks.push({...auth[0], policyRevision: 'actual-policy-8'});
  row.fullTotals['account-evaluation'] = 3;
  assert.equal(assessStructure({operations: [row]}).status, 'passed');
  const second = publicOperation('warm-result', 'public-call-2');
  second.fullChecks.find(check => check.kind === 'account-evaluation').fullCalls = 0;
  assert.equal(assessStructure({operations: [publicOperation(), second]}).status, 'failed');
  assert.throws(() => assessStructure({operations: [publicOperation(), publicOperation()]}), /public-operation identity/u);
});
test('Account tuple coverage and full count overflow cannot be replaced by frame identities', () => {
  const row = publicOperation(); delete row.fullChecks.find(check => check.kind === 'account-evaluation').tuple.target;
  assert.throws(() => assessStructure({operations: [row]}), /exact subject/u);
  const huge = publicOperation(); huge.fullChecks[0].fullCalls = Number.MAX_SAFE_INTEGER;
  huge.fullChecks.push({...huge.fullChecks[0]});
  assert.throws(() => assessStructure({operations: [huge]}), /count overflow/u);
});
test('unrelated Run/Effect reads, counter overflow and invented zero admissions refuse', () => {
  for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
    assert.equal(assessStructure({operations: [{...publicOperation(), [key]: 1}]}).status, 'failed');
  }
  assert.equal(assessStructure({operations: [{...publicOperation(), overflow: true}]}).status, 'incomplete');
  const row = publicOperation(); row.fullChecks.find(check => check.kind === 'row-admission').fullCalls = 0;
  assert.equal(assessStructure({operations: [row]}).status, 'failed');
});
test('unchanged status cannot create a durable write or logical revision', () => {
  for (const patch of [{statusWrites: 1}, {revisionAfter: 8}]) {
    assert.equal(assessStructure({operations: [{...publicOperation('warm-status'), ...patch}]}).status, 'failed');
  }
});
test('history gate compares identical targets and bounded supported history', () => {
  assert.equal(assessHistory(histories()).status, 'passed');
  const rows = histories(); rows[3].targetRowsRead = 1000;
  assert.equal(assessHistory(rows).status, 'failed');
  rows[3] = {size: 1000, supported: false, reason: 'existing supported bound'};
  assert.equal(assessHistory(rows).status, 'incomplete');
  assert.equal(assessHistory(rows.slice(0, 3)).status, 'incomplete');
});
test('history fixture changes and unrelated-row scans cannot hide behind latency', () => {
  for (const patch of [{fixtureSha256: cohort}, {unrelatedRunRows: 1}, {fullHashValidations: 1000}, {databaseReads: 1000}, {sqlPrepares: 1000}]) {
    const rows = histories(); Object.assign(rows[2], patch); assert.equal(assessHistory(rows).status, 'failed');
  }
});
test('history coverage requires new-query and saved-read operations independently', () => {
  const rows = histories();
  assert.equal(assessHistory(rows).status, 'passed');
  const saved = rows.filter(row => ['warm-result', 'warm-status'].includes(row.operation));
  const partial = assessHistory(saved);
  assert.equal(partial.status, 'incomplete');
  for (const size of [1, 10, 100, 1000]) assert(partial.missing.includes(`history warm-select ${size}`));
  const legacy = rows.filter(row => row.operation === 'warm-result').map(({operation, ...row}) => row);
  assert.equal(assessHistory(legacy).status, 'incomplete');
  const changed = histories();
  // Different operations may legitimately read different target rows. Each
  // operation must remain independent of its own unrelated-history size.
  changed.filter(row => row.operation === 'warm-select').forEach(row => {
    row.fixtureSha256 = cohort; row.databaseReads = 9;
  });
  assert.equal(assessHistory(changed).status, 'passed');
  for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
    const failed = histories();
    failed.find(row => row.operation === 'warm-select' && row.size === 1000)[key] = 1;
    assert.equal(assessHistory(failed).status, 'failed');
  }
  assert.throws(() => assessHistory([...rows, rows[0]]), /Duplicate/u);
  assert.throws(() => assessHistory([{...rows[0], operation: 'unattributed-helper'}]), /public operation/u);
});
test('bulk transfer gates scale by actual bounded chunks, never bytes', () => {
  assert.equal(assessChunks(chunks()).status, 'passed');
  for (const patch of [{scalarByteCalls: 262144}, {chunks: 262144}, {hostCalls: 262144}, {boundaries: 262144}]) {
    const rows = chunks(); Object.assign(rows[2], patch); assert.equal(assessChunks(rows).status, 'failed');
  }
  const rows = chunks(); delete rows[2].hostCalls; assert.equal(assessChunks(rows).status, 'incomplete');
});
test('boundary gate keeps current Deny, used-row tamper, Unknown and no resend', () => {
  const rows = Object.entries(boundaryExpectations).map(([name, expected]) => ({case: name, ...expected}));
  assert.equal(assessBoundaries(rows).status, 'passed');
  for (const [name, key, value] of [['deny-before-operation', 'sends', 1], ['used-row-tamper', 'outcome', 'succeeded'],
    ['commit-unknown', 'outcome', 'succeeded'], ['send-reply-lost', 'blindResends', 1],
    ['unrelated-row-corruption', 'targetUnrelatedRows', 1], ['unrelated-row-corruption', 'explicitIntegrityDetected', false]]) {
    const changed = structuredClone(rows); changed.find(row => row.case === name)[key] = value;
    assert.equal(assessBoundaries(changed).status, 'failed', name);
  }
  assert.equal(assessBoundaries(rows.slice(1)).status, 'incomplete');
});
test('collector awaits materialized completion and stops an obvious slow diagnostic', async () => {
  const emitted = []; let calls = 0, clock = 0n;
  const result = await collectOperationSamples({operation: 'warm-select', mode: 'diagnostic',
    identity: {cohortSha256: cohort, fixtureSha256: fixture, hostId: 'one'}, stateId: 'dedicated',
    now: () => clock, cpu: () => ({user: calls, system: 0}),
    execute: async () => {await Promise.resolve(); calls++; clock += 1_000_000_000n;},
    emit: row => {emitted.push(row);}});
  assert.equal(calls, 1); assert.equal(emitted[0].wallNs, 1e9);
  assert.equal(result.stoppedEarly, true); assert.match(result.stopReason, /slow diagnostic/u);
});
test('collector retains first functional error without retry', async () => {
  let calls = 0; const rows = [];
  const result = await collectOperationSamples({operation: 'warm-result', mode: 'final',
    identity: {cohortSha256: cohort, fixtureSha256: fixture}, stateId: 'dedicated', now: () => 0n,
    cpu: () => ({user: 0, system: 0}), execute: () => {calls++; throw new Error('Unknown; no resend');},
    emit: row => {rows.push(row);}});
  assert.equal(calls, 1); assert.equal(rows[0].verified, false); assert.match(rows[0].error, /Unknown/u);
  assert.equal(result.stoppedEarly, true);
});
test('a partial packet is incomplete; different runtime cohorts cannot be combined', () => {
  const report = {sourceSha: 'd'.repeat(40), cohortSha256: cohort, environmentSha256: environment,
    historyProtocolSha256: protocol, latency: [series()]};
  assert.equal(assessPerformanceEvidence(report).status, 'incomplete');
  assert.throws(() => assessPerformanceEvidence({...report, structure: {cohortSha256: fixture, operations: [publicOperation()]}}));
  assert.throws(() => assessPerformanceEvidence({...report, latency: [series(), series()]}));
});
test('warm collector cannot manufacture cold child PID or first-init state samples', async () => {
  for (const operation of ['cold-existing', 'first-init']) {
    await assert.rejects(collectOperationSamples({operation, mode: 'final', execute: () => assert.fail('must not execute')}), /warm operations only/u);
  }
});
test('full composition binds functional, latency, structural and faults to one cohort/environment/protocol', () => {
  const identity = {cohortSha256: cohort, environmentSha256: environment, historyProtocolSha256: protocol};
  const latency = Object.keys(operationTargets).map(operation => {
    const value = series(operation, undefined, operation.startsWith('warm') ? 4 : 100);
    if (operation === 'cold-existing') value.samples.forEach((r, n) => {r.pid = n + 1;});
    if (operation === 'first-init') value.samples.forEach((r, n) => {r.stateId = `new${n}`;});
    return value;
  });
  const report = {sourceSha: 'd'.repeat(40), ...identity, latency, comparison,
    functional: {...identity, rows: Object.keys(operationTargets).map(operation => ({operation,
      completed: true, expectedSha256: fixture, actualSha256: fixture}))},
    structure: {...identity, operations: Object.keys(operationTargets).map(operation => publicOperation(operation, operation))}, history: {...identity, rows: histories()},
    chunks: {...identity, rows: chunks()}, boundaries: {...identity,
      rows: Object.entries(boundaryExpectations).map(([name, expected]) => ({case: name, ...expected}))}};
  assert.equal(assessPerformanceEvidence(report).status, 'incomplete');
  assert(assessPerformanceEvidence(report).missing.some(value => value.includes('matched SQLite operation comparator')));
  const partialWork = structuredClone(report); partialWork.structure.operations.pop();
  assert.equal(assessPerformanceEvidence(partialWork).status, 'incomplete');
  for (const section of ['functional', 'structure', 'history', 'chunks', 'boundaries']) {
    for (const key of ['cohortSha256', 'environmentSha256', 'historyProtocolSha256']) {
      const changed = structuredClone(report); changed[section][key] = 'f'.repeat(64);
      assert.throws(() => assessPerformanceEvidence(changed), section + key);
    }
  }
  const changed = structuredClone(report); changed.functional.rows[0].actualSha256 = cohort;
  assert.equal(assessPerformanceEvidence(changed).status, 'failed');
  changed.latency[0].profiled = true;
  assert(assessPerformanceEvidence(changed).missing.some(value => value.includes('uninstrumented')));
});
test('CLI returns nonzero for incomplete evidence and distinguishes malformed cohort data', t => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-performance-cli-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const path = join(dir, 'report.json');
  const report = {sourceSha: 'd'.repeat(40), cohortSha256: cohort, environmentSha256: environment,
    historyProtocolSha256: protocol, latency: [series('warm-select', 1)]};
  writeFileSync(path, JSON.stringify(report));
  let incomplete;
  try { execFileSync(process.execPath, [new URL('./operation-performance.mjs', import.meta.url).pathname, '--input', path], {stdio: 'pipe'}); }
  catch (error) { incomplete = error; }
  assert.equal(incomplete.status, 1); assert.equal(JSON.parse(incomplete.stdout).status, 'incomplete');
  report.latency[0].environmentSha256 = cohort; writeFileSync(path, JSON.stringify(report));
  let malformed;
  try { execFileSync(process.execPath, [new URL('./operation-performance.mjs', import.meta.url).pathname, '--input', path], {stdio: 'pipe'}); }
  catch (error) { malformed = error; }
  assert.equal(malformed.status, 2); assert.match(malformed.stderr.toString(), /environment or history protocol/u);
});
test('exported criteria are immutable and inherited object properties are not operations', () => {
  assert.throws(() => { operationTargets['warm-select'].comparison = 'fixed-200ms'; });
  assert.throws(() => { boundaryExpectations['commit-unknown'].outcome = 'succeeded'; });
  assert.throws(() => assessLatency({...series(), operation: 'toString'}), /Unknown public operation/u);
});


const nativeHash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
function nativeReport(count = 100, ms = 80) {
  const mode = count === 100 ? 'final' : 'diagnostic';
  const environment = {platform: 'synthetic-native-process'};
  const protocol = {selection: 'native-operations', mode, samplesPerOperation: count,
    firstQuery: {text: 'SELECT 0 AS id', expected: [{id: 0}]},
    queries: Array.from({length: count}, (_, index) => ({text: `SELECT ${index + 1} AS id`, expected: [{id: index + 1}]}))};
  const binding = {cohortSha256: cohort, environmentSha256: nativeHash(environment), historyProtocolSha256: nativeHash(protocol)};
  const report = {sourceSha: 'a'.repeat(40), ...binding, selection: 'native-operations', executionPath: 'native-cli',
    mode, environment, historyProtocol: protocol, initialization: {pid: 1, code: 0, wallNs: 1000000},
    cleanup: {closed: true}, packageFailure: null, installedPayloadsUnchanged: true,
    publicCallAttempts: {init: 1, run: count + 1, result: count}, latency: [], functional: {...binding, rows: []}};
  report.firstQuery = {pid: 2, publicOperationId: 'first', stateId: '/synthetic/project', publicRunId: 'run-0',
    completed: true, verified: true, command: {pid: 2, code: 0, wallNs: 1000000, cwd: '/synthetic/project',
      args: ['run', 'first.aql', '--output', 'first.jsonl', '--json']},
    wallNs: 2000000, childWallNs: 1000000, querySha256: nativeHash('SELECT 0 AS id'), expectedSha256: nativeHash([{id: 0}]), actualSha256: nativeHash([{id: 0}])};
  report.firstQuery.queryPath = '/synthetic/project/first.aql';
  report.firstQuery.queryFileSha256 = createHash('sha256').update('SELECT 0 AS id;\n').digest('hex');
  report.firstQuery.outputPath = '/synthetic/project/first.jsonl';
  report.firstQuery.publicResponse = {run: {run_id: 'run-0', status: 'succeeded'}, delivery_status: 'delivered',
    deliveries: [{run_id: 'run-0', status: 'delivered', request: {result: 'answer', result_cid: 'result-0',
      format: 'jsonl', path: report.firstQuery.outputPath}}]};
  report.firstQuery.runRefSha256 = nativeHash({runId: 'run-0'});
  report.firstQuery.resultRefSha256 = nativeHash({runId: 'run-0', resultName: 'answer', resultCid: 'result-0'});
  report.firstQuery.command.stdout = JSON.stringify(report.firstQuery.publicResponse);
  const fresh = Array.from({length: count}, (_, index) => {
    const id = index + 1, runId = `run-${id}`, selected = {runId, resultName: 'answer', resultCid: `result-${id}`};
    return {...binding, iteration: index, publicOperationId: `new-${id}`, stateId: '/synthetic/project', pid: index + 3,
      publicRunId: runId, runRefSha256: nativeHash({runId}), resultRefSha256: nativeHash(selected),
      querySha256: nativeHash(`SELECT ${id} AS id`), expectedSha256: nativeHash([{id}]), actualSha256: nativeHash([{id}]),
      completed: true, verified: true, wallNs: ms * 1e6, childWallNs: (ms - 1) * 1e6,
      cpuUserUs: 1000, cpuSystemUs: 200, cpuScope: 'synthetic child',
      peakRssBytes: 1024, rssScope: 'synthetic child RSS',
      publicTiming: {kind: 'cli-result-exit', startNs: 1, exitNs: 2, observedNs: 3, endNs: 4},
      command: {pid: index + 3, code: 0, wallNs: (ms - 1) * 1e6, cwd: '/synthetic/project',
        args: ['run', `new-${index}.aql`, '--output', `new-${index}.jsonl`, '--json']},
      publicResponse: {run: {run_id: runId, status: 'succeeded'}, delivery_status: 'delivered',
        deliveries: [{run_id: runId, status: 'delivered', request: {result: 'answer', result_cid: selected.resultCid, format: 'jsonl', path: `/synthetic/project/new-${index}.jsonl`}}]}};
  });
  for (const [index, row] of fresh.entries()) {
    row.queryPath = `/synthetic/project/new-${index}.aql`;
    row.queryFileSha256 = createHash('sha256').update(`SELECT ${index + 1} AS id;\n`).digest('hex');
    row.outputPath = `/synthetic/project/new-${index}.jsonl`;
    row.command.stdout = JSON.stringify(row.publicResponse);
  }
  const originals = fresh.slice(0, 3);
  for (const operation of ['cold-new-run', 'cold-result']) {
    const values = operation === 'cold-new-run' ? fresh : Array.from({length: count}, (_, index) => {
      const original = originals[index % originals.length], pid = count + index + 3;
      return {...binding, iteration: index, publicOperationId: `saved-${index}`, stateId: '/synthetic/project', pid,
        ...Object.fromEntries(['publicRunId', 'runRefSha256', 'resultRefSha256', 'expectedSha256', 'actualSha256'].map(key => [key, original[key]])),
        completed: true, verified: true, wallNs: ms * 1e6, childWallNs: (ms - 1) * 1e6,
        cpuUserUs: 1000, cpuSystemUs: 200, cpuScope: 'synthetic child',
        peakRssBytes: 1024, rssScope: 'synthetic child RSS',
        publicTiming: {kind: 'cli-result-exit', startNs: 1, exitNs: 2, observedNs: 3, endNs: 4},
        command: {pid, code: 0, wallNs: (ms - 1) * 1e6, cwd: '/synthetic/project', args: ['result', original.publicRunId, '--result', 'answer', '--format', 'jsonl']}};
    });
    const workload = operation === 'cold-new-run' ? {kind: 'new-durable-run-result-file-rows',
      fixtures: protocol.queries.map(row => ({querySha256: nativeHash(row.text), expectedSha256: nativeHash(row.expected)}))}
      : {kind: 'saved-original-result-rows', originals: originals.map(row => Object.fromEntries(
        ['runRefSha256', 'resultRefSha256', 'expectedSha256'].map(key => [key, row[key]])))};
    const fixtureSha256 = nativeHash(workload);
    for (const row of values) row.fixtureSha256 = fixtureSha256;
    report.latency.push({...binding, operation, mode, fixtureSha256, publicWorkload: workload,
      samples: values, profiled: false, load: 'isolated', stoppedEarly: false});
    report.functional.rows.push({operation, fixtureSha256, completed: true,
      expectedSha256: nativeHash(values.map(row => row.expectedSha256)), actualSha256: nativeHash(values.map(row => row.actualSha256))});
  }
  return report;
}

test('Native public process gate keeps its targets and full acceptance separate', () => {
  const passed = assessNativeOperations(nativeReport());
  assert.equal(passed.status, 'passed'); assert.equal(passed.target.medianMs, 100); assert.equal(passed.target.p95Ms, 200);
  assert.equal(passed.fullPerformanceAccepted, false); assert.equal(passed.releaseAccepted, false);
  assert(passed.unverified.includes('matched SQLite public-operation comparator'));
  const short = assessNativeOperations(nativeReport(3));
  assert.equal(short.status, 'incomplete'); assert.equal(short.checks['cold-new-run'].summary.p95Ms, null);
  const slow = assessNativeOperations(nativeReport(100, 250));
  assert.equal(slow.status, 'failed'); assert(slow.failures.some(row => row.includes('median latency')));
});

test('Native public process gate rejects mixed identities and replaced saved targets', () => {
  for (const mutate of [report => { report.latency[0].samples[0].cohortSha256 = 'f'.repeat(64); },
    report => { report.latency[1].samples[0].publicRunId = 'another-run'; },
    report => { report.latency[0].samples[0].querySha256 = 'f'.repeat(64); },
    report => { delete report.firstQuery.command; },
    report => { report.latency[1].samples[0].command.wallNs = 1; }]) {
    const report = nativeReport(); mutate(report); assert.throws(() => assessNativeOperations(report));
  }
  const reused = nativeReport(); reused.latency[1].samples[0].pid = reused.firstQuery.pid;
  reused.latency[1].samples[0].command.pid = reused.firstQuery.pid;
  assert.equal(assessNativeOperations(reused).status, 'failed');
  const malformedState = nativeReport(); malformedState.latency[1].samples[0].stateId = 'another-project';
  assert.throws(() => assessNativeOperations(malformedState), /Saved Native target or rows differ/u);
  const state = nativeReport(); state.latency[1].samples[0].stateId = 'another-project';
  state.latency[1].samples[0].command.cwd = 'another-project';
  const changedProject = assessNativeOperations(state);
  assert.equal(changedProject.status, 'failed');
  assert(changedProject.failures.includes('Native routes must retain the same actual project state'));
});

test('Native public process gate retains failed or missing original provenance and work', () => {
  const packageFailure = nativeReport(); packageFailure.packageFailure = 'actual changed payload';
  assert.equal(assessNativeOperations(packageFailure).status, 'failed');
  const missing = nativeReport(); delete missing.installedPayloadsUnchanged;
  assert.equal(assessNativeOperations(missing).status, 'incomplete');
  const missingInit = nativeReport(); delete missingInit.initialization.pid;
  assert.equal(assessNativeOperations(missingInit).status, 'incomplete');
  const unknown = nativeReport(); unknown.firstFailure = {message: 'original Unknown'};
  unknown.latency = unknown.latency.slice(0, 1);
  unknown.latency[0].samples = unknown.latency[0].samples.slice(0, 1);
  Object.assign(unknown.latency[0].samples[0], {completed: false, verified: false});
  unknown.publicCallAttempts = {init: 1, run: 2, result: 0};
  unknown.functional.rows = [{...unknown.functional.rows[0], completed: false}];
  assert.equal(assessNativeOperations(unknown).status, 'failed');
});


test('Native provenance binds the separate first returned Run and Result', () => {
  assert.equal(assessNativeOperations(nativeReport()).status, 'passed');
  for (const mutate of [
    row => { delete row.publicRunId; delete row.publicResponse; },
    row => { delete row.publicResponse; },
    row => { row.publicResponse.run.run_id = 'another-run'; },
    row => { row.resultRefSha256 = 'f'.repeat(64); },
    row => { row.publicResponse.deliveries[0].request.result_cid = 'another-result'; },
    row => { row.publicResponse.deliveries[0].request.path = '/another-output'; },
    row => { row.command.args = ['result', 'another-run']; },
    row => { delete row.queryFileSha256; },
  ]) {
    const report = nativeReport(); mutate(report.firstQuery);
    if (report.firstQuery.publicResponse) report.firstQuery.command.stdout = JSON.stringify(report.firstQuery.publicResponse);
    assert.throws(() => assessNativeOperations(report));
  }
});

test('Native provenance binds each NEW command query and output', () => {
  for (const mutate of [
    row => { row.command.args = ['result', 'another-run']; },
    row => { row.command.args[1] = 'new-1.aql'; },
    row => { row.command.args[3] = 'new-1.jsonl'; },
    row => { row.command.cwd = '/another-project'; },
    row => { row.queryPath = '/another-query'; },
    row => { row.queryFileSha256 = 'f'.repeat(64); },
    row => { row.outputPath = '/another-output'; },
    row => { row.publicResponse.deliveries[0].request.format = 'csv'; row.command.stdout = JSON.stringify(row.publicResponse); },
    row => { row.command.stdout = JSON.stringify({run: {run_id: 'another-run'}}); },
  ]) {
    const report = nativeReport(); mutate(report.latency[0].samples[0]);
    assert.throws(() => assessNativeOperations(report));
  }
});

test('record-only retains slow verified repetitions without claiming acceptance p95', async () => {
  let clock = 0n;
  const collected = await collectOperationSamples({operation: 'warm-select', mode: 'record-only',
    now: () => clock, cpu: () => ({user: 0, system: 0}),
    execute: () => {clock += 1_000_000_000n;}, emit: () => {}});
  assert.equal(collected.stoppedEarly, false);
  const summary = recordOperationMeasurements({operation: 'warm-select', mode: 'record-only', ...collected});
  assert.equal(summary.count, 3); assert.equal(summary.medianMs, 1000);
  assert.equal(summary.maxMs, 1000); assert.equal(summary.p95Ms, null);
  assert.equal(summary.acceptanceAssessed, false); assert(summary.resources.rss.available);
  assert.throws(() => recordOperationMeasurements({operation: 'warm-select', mode: 'record-only', samples: []}));
});
test('record-only stops failed public operation without retry and cannot summarize it as success', async () => {
  let calls = 0;
  const collected = await collectOperationSamples({operation: 'warm-result', mode: 'record-only',
    execute: () => {calls++; throw new Error('Unknown');}, emit: () => {}});
  assert.equal(calls, 1); assert.equal(collected.stoppedEarly, true);
  assert.throws(() => recordOperationMeasurements({operation: 'warm-result', mode: 'record-only', ...collected}));
});
