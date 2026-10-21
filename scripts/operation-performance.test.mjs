import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {operationTargets, latencySummary, assessLatency, assessStructure, assessHistory,
  assessChunks, assessBoundaries, boundaryExpectations, collectOperationSamples, assessPerformanceEvidence} from './operation-performance.mjs';

// Synthetic evidence exercises the acceptance oracle, never product latency.
const cohort = 'a'.repeat(64), fixture = 'b'.repeat(64), environment = 'c'.repeat(64), protocol = 'e'.repeat(64);
function series(operation = 'warm-select', count = operationTargets[operation].samples, ms = 4) {
  return {operation, mode: 'final', cohortSha256: cohort, fixtureSha256: fixture,
    environmentSha256: environment, historyProtocolSha256: protocol, profiled: false, load: 'isolated', samples: Array.from({length: count}, (_, iteration) => ({
      iteration, cohortSha256: cohort, fixtureSha256: fixture, wallNs: ms * 1e6,
      cpuUserUs: 1000, cpuSystemUs: 200, cpuScope: 'measured-process', pid: 1, hostId: 'host1', stateId: 'state1',
      completed: true, verified: true,
    }))};
}
function frame() {
  return {id: 'one', complete: true, overflow: false, unrelatedRunRows: 0, unrelatedEffectRows: 0,
    distinctAuthTuples: 2, distinctAdmittedRows: 3, accountEvaluationsPerTupleMax: 1,
    rowAdmissionsPerRevisionMax: 1, rowDecodePerRevisionMax: 1, rowMacPerRevisionMax: 1,
    rowHashPerRevisionMax: 1, configurationInventories: 1, unchangedStatus: true,
    statusWrites: 0, revisionBefore: 7, revisionAfter: 7};
}
const histories = () => [1, 10, 100, 1000].map(size => ({size, supported: true, fixtureSha256: fixture,
  targetRowsRead: 3, rowAdmissions: 3, decodeCalls: 3, macCalls: 3, hashCalls: 3,
  accountEvaluations: 1, unrelatedRunRows: 0, unrelatedEffectRows: 0}));
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
test('enforces millisecond simple targets rather than a 200ms substitute', () => {
  assert.equal(assessLatency(series()).status, 'passed');
  assert.equal(assessLatency(series('warm-select', 100, 6)).status, 'failed');
  const rows = series(); rows.samples.slice(94).forEach(row => { row.wallNs = 11e6; });
  assert(assessLatency(rows).failures.includes('p95 latency exceeds target'));
});
test('threshold equality passes; small JOIN has its distinct 500ms target', () => {
  assert.equal(assessLatency(series('warm-select', 100, 5)).status, 'passed');
  assert.equal(assessLatency(series('warm-join', 100, 500)).status, 'passed');
  assert.equal(assessLatency(series('warm-join', 100, 501)).status, 'failed');
});
test('a diagnostic or profiled/loaded run cannot become final acceptance', () => {
  for (const patch of [{mode: 'diagnostic'}, {profiled: true}, {load: 'concurrent'}, {stoppedEarly: true}]) {
    assert.equal(assessLatency({...series(), ...patch}).status, 'incomplete');
  }
});
test('functional failures are retained, not filtered into a faster passed population', () => {
  const rows = series(); rows.samples[40].verified = false;
  const result = assessLatency(rows); assert.equal(result.status, 'failed');
  assert.equal(result.summary.count, 99); assert.equal(result.summary.p95Ms, null);
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
  const cold = series('cold-existing', 30, 2000);
  assert.equal(assessLatency(cold).status, 'failed');
  cold.samples.forEach((r, n) => {r.pid = n + 1;});
  assert.equal(assessLatency(cold).status, 'passed');
  cold.samples.pop(); assert.equal(assessLatency(cold).status, 'incomplete');
});
test('first-init requires independent states, not thirty opens of existing state', () => {
  const rows = series('first-init', 30, 5000); assert.equal(assessLatency(rows).status, 'failed');
  rows.samples.forEach((r, n) => {r.stateId = `fresh${n}`;}); assert.equal(assessLatency(rows).status, 'passed');
});
test('missing counters are incomplete and not silently zero', () => {
  assert.equal(assessStructure({frames: []}).status, 'incomplete');
  const row = frame(); delete row.unrelatedEffectRows;
  assert.equal(assessStructure({frames: [row]}).status, 'incomplete');
});
test('counts distinct tuples/rows once per actual frame, not once per whole program', () => {
  assert.equal(assessStructure({frames: [frame(), {...frame(), id: 'dispatch'}]}).status, 'passed');
  for (const key of ['accountEvaluationsPerTupleMax', 'rowAdmissionsPerRevisionMax',
    'rowDecodePerRevisionMax', 'rowMacPerRevisionMax', 'rowHashPerRevisionMax', 'configurationInventories']) {
    assert.equal(assessStructure({frames: [{...frame(), [key]: 2}]}).status, 'failed', key);
  }
});
test('unrelated Run/Effect reads, counter overflow and invented zero admissions refuse', () => {
  for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
    assert.equal(assessStructure({frames: [{...frame(), [key]: 1}]}).status, 'failed');
  }
  assert.equal(assessStructure({frames: [{...frame(), overflow: true}]}).status, 'incomplete');
  assert.equal(assessStructure({frames: [{...frame(), rowAdmissionsPerRevisionMax: 0}]}).status, 'failed');
});
test('unchanged status cannot create a durable write or logical revision', () => {
  for (const patch of [{statusWrites: 1}, {revisionAfter: 8}]) {
    assert.equal(assessStructure({frames: [{...frame(), ...patch}]}).status, 'failed');
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
  for (const patch of [{fixtureSha256: cohort}, {unrelatedRunRows: 1}, {hashCalls: 1000}]) {
    const rows = histories(); Object.assign(rows[2], patch); assert.equal(assessHistory(rows).status, 'failed');
  }
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
  assert.throws(() => assessPerformanceEvidence({...report, structure: {cohortSha256: fixture, frames: [frame()]}}));
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
  const report = {sourceSha: 'd'.repeat(40), ...identity, latency,
    functional: {...identity, rows: Object.keys(operationTargets).map(operation => ({operation,
      completed: true, expectedSha256: fixture, actualSha256: fixture}))},
    structure: {...identity, frames: [frame()]}, history: {...identity, rows: histories()},
    chunks: {...identity, rows: chunks()}, boundaries: {...identity,
      rows: Object.entries(boundaryExpectations).map(([name, expected]) => ({case: name, ...expected}))}};
  assert.equal(assessPerformanceEvidence(report).status, 'passed');
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
  assert.throws(() => { operationTargets['warm-select'].p95Ms = 200; });
  assert.throws(() => { boundaryExpectations['commit-unknown'].outcome = 'succeeded'; });
  assert.throws(() => assessLatency({...series(), operation: 'toString'}), /Unknown public operation/u);
});
