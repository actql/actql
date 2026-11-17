import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, mkdtempSync, writeFileSync, existsSync, rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {parse} from 'yaml';
import * as performance from './native-approval-performance.mjs';
import {nativeApprovalTarget} from './operation-performance.mjs';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalResources, approvalPhases} from './native-approval-performance.mjs';

const sourceSha = 'a'.repeat(40), fixtureSha256 = 'b'.repeat(64), runnerSha256 = 'c'.repeat(64);
const series = () => ({mode: 'final', sourceSha, fixtureSha256, runnerSha256,
  samples: Array.from({length: 30}, (_, iteration) => ({iteration, sourceSha, fixtureSha256,
    runnerSha256, wallNs: 2000000000, cpuUserUs: 1000, cpuSystemUs: 1000, cpuScope: 'synthetic OS sample', peakRssBytes: 4096, rssScope: 'synthetic OS sample', completed: true, verified: true}))});

test('formal collector refuses a diagnostic binding before any artifact or workflow executes', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-formal-binding-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const binding = join(root, 'binding.json'), output = join(root, 'must-not-exist.json');
  writeFileSync(binding, JSON.stringify({purpose: 'native-approval-cpu-diagnostic', diagnosticOnly: true,
    acceptanceEligible: false, producerJobConclusion: 'failure'}));
  const run = spawnSync(process.execPath, ['scripts/test-native-approval-performance.mjs',
    '--normal', join(root, 'no-artifact'), '--output', output, '--runner', 'test-only', '--binding', binding],
  {encoding: 'utf8', timeout: 5000});
  assert.notEqual(run.status, 0); assert.match(run.stderr, /native-approval-acceptance/u);
  assert.doesNotMatch(run.stderr, /ENOENT/u); assert.equal(existsSync(output), false);
});

function smokeScenarios(wallNs = 3000000000) {
  return ['deal-review-mock', 'churn-risk-mock'].map(template => ({template,
    commands: [{args: ['original-launcher', 'approve', 'original-checkpoint', '--wait', '--json'],
      code: 0, signal: null, wallNs}]}));
}

async function installedSmokeTail(scenarios, measureResources = false, writeFailure) {
  const receipt = {scenarios}, events = [];
  const pending = performance.publishNativeApprovalReceipt({receipt,
    receiptFile: '/original-release/mock-install-linux-x64-gnu-1.json', measureResources,
    writeFile: async (path, bytes, options) => {
      if (writeFailure) throw writeFailure;
      events.push({kind: 'receipt', path, value: JSON.parse(bytes), options});
    },
    scratch: {passed: () => events.push({kind: 'passed'})},
    log: message => events.push({kind: 'console', message}),
  });
  return {receipt, events, pending};
}

test('ordinary Native smoke persists the original slow approvals before rejecting and never marks them passed', async () => {
  const original = smokeScenarios(6000000000);
  const {events, pending} = await installedSmokeTail(original);
  await assert.rejects(pending, /approval maximum exceeds 3000 ms/u);
  assert.deepEqual(events.map(event => event.kind), ['receipt']);
  assert.deepEqual(events[0].value.scenarios, original);
  assert.equal(events[0].value.approvalSmoke.status, 'failed');
  assert.equal(events[0].value.approvalSmoke.samples.length, 2);
  assert.equal(events[0].options.flag, 'wx');
});

test('ordinary Native smoke accepts three seconds and refuses one nanosecond above without a p95 claim', () => {
  const scenarios = smokeScenarios(), original = structuredClone(scenarios);
  const passed = performance.assessOrdinaryNativeApprovalSmoke(scenarios);
  assert.equal(passed.status, 'passed'); assert.equal(passed.maximumMs, 3000);
  assert.equal(passed.maximumMs, nativeApprovalTarget.maxMs);
  assert.equal(passed.formalAcceptance, false); assert.equal(passed.samples.length, 2);
  assert.equal(Object.hasOwn(passed, 'p95Ms'), false);
  assert.deepEqual(scenarios, original);
  for (let index = 0; index < 2; index++) {
    const slow = structuredClone(scenarios); slow[index].commands[0].wallNs++;
    const result = performance.assessOrdinaryNativeApprovalSmoke(slow);
    assert.equal(result.status, 'failed'); assert.equal(result.samples[index].wallNs, 3000000001);
    assert(result.failures.some(reason => reason.includes('approval maximum exceeds 3000 ms')));
  }
});

test('ordinary Native smoke cannot pass missing invalid failed or duplicate original timing', () => {
  for (const wallNs of [undefined, null, 0, -1, NaN, Infinity, 1.5, '1000']) {
    const selected = smokeScenarios(); selected[0].commands[0].wallNs = wallNs;
    assert.equal(performance.assessOrdinaryNativeApprovalSmoke(selected).status, 'failed');
  }
  for (const change of [command => {command.code = 1;}, command => {command.signal = 'SIGTERM';},
    command => {delete command.signal;}, command => {command.killed = true;}]) {
    const selected = smokeScenarios(); change(selected[0].commands[0]);
    assert.equal(performance.assessOrdinaryNativeApprovalSmoke(selected).status, 'failed');
  }
  for (const selected of [null, [], smokeScenarios().slice(1), [...smokeScenarios(), smokeScenarios()[0]],
    [smokeScenarios()[0], smokeScenarios()[0]]]) {
    assert.equal(performance.assessOrdinaryNativeApprovalSmoke(selected).status, 'failed');
  }
  for (const commands of [null, [], [...smokeScenarios()[0].commands, ...smokeScenarios()[0].commands]]) {
    const selected = smokeScenarios(); selected[0].commands = commands;
    assert.equal(performance.assessOrdinaryNativeApprovalSmoke(selected).status, 'failed');
  }
});

test('ordinary Native smoke publishes inclusive-boundary success but retains invalid timing as failure', async () => {
  const passed = await installedSmokeTail(smokeScenarios()); await passed.pending;
  assert.deepEqual(passed.events.map(event => event.kind), ['receipt', 'passed', 'console']);
  assert.equal(passed.events[0].value.approvalSmoke.status, 'passed');
  const invalid = smokeScenarios(); delete invalid[0].commands[0].wallNs;
  const failed = await installedSmokeTail(invalid);
  await assert.rejects(failed.pending, /original approval timing missing or invalid/u);
  assert.deepEqual(failed.events.map(event => event.kind), ['receipt']);
  assert.equal(failed.events[0].value.approvalSmoke.status, 'failed');
});

test('ordinary Native smoke leaves formal slow samples and earlier receipt errors intact', async () => {
  const original = smokeScenarios(30000000000);
  const formal = await installedSmokeTail(original, true); await formal.pending;
  assert.deepEqual(formal.events.map(event => event.kind), ['receipt', 'passed', 'console']);
  assert.deepEqual(formal.events[0].value.scenarios, original);
  assert.equal(Object.hasOwn(formal.events[0].value, 'approvalSmoke'), false);
  const primary = new Error('original receipt write failure');
  const failed = await installedSmokeTail(original, false, primary);
  await assert.rejects(failed.pending, error => error === primary);
  assert.deepEqual(failed.events, []);
});

test('required Native CI selects the full original formal campaign and keeps stop bounds separate', () => {
  const consumer = readFileSync(new URL('./test-native-cli-mock-install.mjs', import.meta.url), 'utf8');
  const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const collector = readFileSync(new URL('./test-native-approval-performance.mjs', import.meta.url), 'utf8');
  assert.match(consumer, /async function run\(command, args, cwd = root, timeoutMs = 120_000\)/u);
  assert(consumer.indexOf('await registry.close()') < consumer.indexOf('const receiptFile = join(directory,'));
  const job = parse(ci).jobs['native-cli-linux-local-mock'];
  const formal = job.steps.find(step => step.run?.includes('node scripts/test-native-approval-performance.mjs'));
  assert(formal && formal['continue-on-error'] === undefined);
  assert(formal.run.includes('--binding') && !formal.run.includes('--diagnostic'));
  assert.equal(formal.env?.TMPDIR, undefined);
  assert.match(collector, /count = values\.diagnostic \? 3 : 30/u);
  assert.match(collector, /'--measure-approval-resources'/u);
});

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

test('Native approval accepts two seconds p95 and rejects one nanosecond above it', () => {
  assert.deepEqual(nativeApprovalTarget, {samples: 30, p95Ms: 2000, maxMs: 3000});
  assert.equal(assessNativeApproval(series()).status, 'passed');
  const selected = series();
  selected.samples[0].wallNs = selected.samples[1].wallNs = 2000000001;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'failed');
  assert.deepEqual(result.failures, ['approval p95 exceeds 2000 ms']);
  assert.equal(result.summary.count, 30);
  assert.equal(result.summary.p95Ms, 2000.000001);
});

test('Native approval accepts three seconds maximum and rejects one nanosecond above it', () => {
  const selected = series(); selected.samples[0].wallNs = 3000000000;
  assert.equal(assessNativeApproval(selected).status, 'passed');
  selected.samples[0].wallNs++;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'failed');
  assert.deepEqual(result.failures, ['approval maximum exceeds 3000 ms']);
  assert.equal(result.summary.count, 30);
  assert.equal(result.summary.p95Ms, 2000);
  assert.equal(result.summary.maxMs, 3000.000001);
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


test('approval work allowance rejects one extra digest or helper independently of observations', () => {
  const boundaries = 3;
  const fixedAndBoundaryWork = 32 + 2 * boundaries;
  const counts = {pid: 1, sqlPrepares: 300, currentCalls: 50, externalBoundaries: boundaries,
    unexpectedHelperRevalidations: 0, hostAuthorizations: 0, adoptionDigests: fixedAndBoundaryWork,
    materialAdmissions: 1, sourceValidations: fixedAndBoundaryWork, memberHashes: 11};
  assertApprovalCallCounts(counts, 1);
  assert.throws(() => assertApprovalCallCounts({...counts, adoptionDigests: fixedAndBoundaryWork + 1}, 1),
    /adoption validation amplified/u);
  assert.throws(() => assertApprovalCallCounts({...counts, sourceValidations: fixedAndBoundaryWork + 1}, 1),
    /Source validation amplified/u);
  assert.throws(() => assertApprovalCallCounts({...counts, unexpectedHelperRevalidations: 1}, 1),
    /repeated immutable/u);
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
