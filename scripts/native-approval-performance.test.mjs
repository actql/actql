import assert from 'node:assert/strict';
import test from 'node:test';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalResources, approvalPhases} from './native-approval-performance.mjs';

const sourceSha = 'a'.repeat(40), fixtureSha256 = 'b'.repeat(64), runnerSha256 = 'c'.repeat(64);
const series = () => ({mode: 'final', sourceSha, fixtureSha256, runnerSha256,
  samples: Array.from({length: 30}, (_, iteration) => ({iteration, sourceSha, fixtureSha256,
    runnerSha256, wallNs: 4000000000, cpuUserUs: 1000, cpuSystemUs: 1000, cpuScope: 'synthetic OS sample', peakRssBytes: 4096, rssScope: 'synthetic OS sample', completed: true, verified: true}))});

test('Native approval target requires thirty verified samples on the same source fixture and runner', () => {
  assert.equal(assessNativeApproval(series()).status, 'passed');
  const short = series(); short.samples.pop();
  const result = assessNativeApproval(short);
  assert.equal(result.status, 'incomplete'); assert.equal(result.summary.p95Ms, null);
  for (const field of ['sourceSha', 'fixtureSha256', 'runnerSha256']) {
    const mixed = series(); mixed.samples[0][field] = 'd'.repeat(field === 'sourceSha' ? 40 : 64);
    assert.throws(() => assessNativeApproval(mixed), /Mixed Native approval/u);
  }
});

test('Native approval enforces both p95 and maximum without dropping slow failures', () => {
  const slow = series(); slow.samples[0].wallNs = 11000000000;
  slow.samples[0].verified = false;
  const result = assessNativeApproval(slow);
  assert.equal(result.status, 'failed'); assert.equal(result.summary.maxMs, 11000);
  assert(result.failures.some(value => value.includes('oracle failed')));
  assert(result.failures.some(value => value.includes('maximum')));
  const p95 = series(); p95.samples[0].wallNs = p95.samples[1].wallNs = 6000000000;
  assert(assessNativeApproval(p95).failures.some(value => value.includes('p95')));
});

test('Native approval diagnostic samples do not supply a final acceptance p95', () => {
  const selected = series(); selected.mode = 'diagnostic'; selected.samples.length = 3;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'incomplete'); assert.equal(result.summary.p95Ms, null);
  assert(result.missing.includes('diagnostic only'));
  selected.samples.push({...selected.samples[0]});
  assert.throws(() => assessNativeApproval(selected));
});

test('Native approval call bounds retain mutable SQL while refusing helper amplification', () => {
  const counts = {pid: 1, sqlPrepares: 300, currentCalls: 50, externalBoundaries: 4, unexpectedHelperRevalidations: 0,
    hostAuthorizations: 1, adoptionDigests: 10, materialAdmissions: 1, sourceValidations: 8, memberHashes: 11};
  assertApprovalCallCounts(counts, 2);
  assert.throws(() => assertApprovalCallCounts({...counts, unexpectedHelperRevalidations: 1}, 2), /repeated immutable/u);
  for (const field of ['sqlPrepares', 'currentCalls', 'sourceValidations', 'adoptionDigests']) {
    assert.throws(() => assertApprovalCallCounts({...counts, [field]: 100000}, 2), /amplified/u);
  }
  for (const field of ['sqlPrepares', 'currentCalls', 'sourceValidations', 'externalBoundaries', 'materialAdmissions']) {
    assert.throws(() => assertApprovalCallCounts({...counts, [field]: 0}, 2), /missing/u);
  }
  assert.throws(() => assertApprovalCallCounts(counts, 0));
});

test('Native approval counters refuse incomplete overflowed duplicated or signalled observations', () => {
  const counters = Array.from({length: 70}, (_, tag) => ({tag, name: 'fixture', count: tag + 1}));
  const metadata = {pid: 123, overflow: false, initializing_drops: 0, invalid_tags: 0, invalid_amounts: 0};
  const record = () => ({code: 0, signal: null, stderr: 'ACTQL_NATIVE_TIMINGS ' + JSON.stringify(metadata) + '\n' +
    counters.map(value => 'ACTQL_NATIVE_COUNTER ' + JSON.stringify(value) + '\n').join('')});
  assert.equal(approvalCallCounts(record()).sqlPrepares, 2);
  const missing = record(); missing.stderr = missing.stderr.split('\n').slice(0, -2).join('\n');
  assert.throws(() => approvalCallCounts(missing), /Incomplete/u);
  const duplicate = record(); duplicate.stderr += 'ACTQL_NATIVE_COUNTER ' + JSON.stringify(counters[0]) + '\n';
  assert.throws(() => approvalCallCounts(duplicate), /duplicate/u);
  assert.throws(() => approvalCallCounts({...record(), signal: 'SIGKILL'}), /signal/u);
  metadata.overflow = true;
  assert.throws(() => approvalCallCounts(record()), /overflow/u);
});


test('OS approval resources retain actual command scope and reject unavailable measurements', () => {
  const mac = approvalResources('real 1.20\nuser 0.30\nsys 0.10\n 4096 maximum resident set size\n', 'darwin');
  assert.equal(mac.cpuUserUs, 300000); assert.equal(mac.cpuSystemUs, 100000); assert.equal(mac.peakRssBytes, 4096);
  const linux = approvalResources(' User time (seconds): 0.30\n System time (seconds): 0.10\n Maximum resident set size (kbytes): 4096\n', 'linux');
  assert.equal(linux.peakRssBytes, 4194304);
  assert.throws(() => approvalResources('', 'darwin'));
  assert.throws(() => approvalResources('user 0.3\nsys 0.1\n', 'linux'));
});


test('approval phases require complete actual boundaries and retain inclusive durations separately', () => {
  const rows = [5, 7, 32, 33, 34, 35, 36, 37, 38].map(tag => ({tag, name: 'synthetic policy fixture',
    begins: 1, ends: 1, active: 0, overlap: 0, unmatched_end: 0, inclusive_ns: 10, exclusive_ns: 2, sql_prepares: 3, current_calls: 2}));
  const record = () => ({stderr: rows.map(row => 'ACTQL_NATIVE_PHASE ' + JSON.stringify(row)).join('\n')});
  assert.equal(approvalPhases(record()).length, 9);
  rows[0].active = 1;
  assert.equal(approvalPhases(record(), {requireCompleted: false}).length, 9, 'Optional timing precision is not functional acceptance');
  assert.throws(() => approvalPhases(record()), /unfinished/u);
  rows.shift();
  assert.throws(() => approvalPhases(record()), /incomplete/u);
});
