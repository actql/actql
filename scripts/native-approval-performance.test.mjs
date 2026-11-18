import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, mkdtempSync, writeFileSync, existsSync, rmSync, symlinkSync} from 'node:fs';
import {execFileSync, spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {parse} from 'yaml';
import * as performance from './native-approval-performance.mjs';
import {parseCommands} from './verification-actions.mjs';
import {openNativeMockCampaign} from './native-mock-campaign.mjs';
import {nativeApprovalTarget} from './operation-performance.mjs';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalResources, approvalPhases} from './native-approval-performance.mjs';

const sourceSha = 'a'.repeat(40), fixtureSha256 = 'b'.repeat(64), runnerSha256 = 'c'.repeat(64);
const series = () => ({mode: 'final', sourceSha, fixtureSha256, runnerSha256,
  samples: Array.from({length: 30}, (_, iteration) => ({iteration, sourceSha, fixtureSha256,
    runnerSha256, wallNs: 2000000000, cpuUserUs: 1000, cpuSystemUs: 1000, cpuScope: 'synthetic OS sample', peakRssBytes: 4096, rssScope: 'synthetic OS sample', completed: true, verified: true}))});

test('Mock harness observation waits for the original operation and returns its original value', async () => {
  const records = [], original = {installed: true};
  let release;
  const pending = performance.observeNativeMockHarnessPhase(records, 'installation',
    () => new Promise(resolve => { release = resolve; }));
  assert.deepEqual(records, [{phase: 'installation', state: 'running'}]);
  assert.equal(Object.hasOwn(records[0], 'wallNs'), false);
  release(original);
  assert.equal(await pending, original);
  assert.equal(records[0].state, 'completed');
  assert(Number.isSafeInteger(records[0].wallNs) && records[0].wallNs >= 0);
});

test('Mock harness observation retains original failures including unconfirmed registry closure', async () => {
  for (const [phase, template] of [['scenario', 'deal-review-mock'], ['registry-close', undefined]]) {
    const records = [], primary = new Error('original failed operation');
    await assert.rejects(performance.observeNativeMockHarnessPhase(records, phase,
      () => { throw primary; }, template), error => error === primary);
    assert.equal(records[0].state, 'failed');
    assert(Number.isSafeInteger(records[0].wallNs));
    assert.throws(() => performance.nativeMockWorkflowTiming({harnessPhases: records, scenarios: []}), /Incomplete/u);
  }
});

test('Mock workflow timing keeps harness and original command scopes separate and refuses missing observations', () => {
  const receipt = {harnessPhases: [{phase: 'scenario', template: 'deal-review-mock', state: 'completed', wallNs: 100},
    {phase: 'registry-close', state: 'completed', wallNs: 7}], scenarios: [{template: 'deal-review-mock', commands: [
    {workflowPhase: 'approval', wallNs: 20, launcherTiming: {preparation: 2, child: 15, total: 17}},
    {workflowPhase: 'saved-result', wallNs: 9}]}]};
  const result = performance.nativeMockWorkflowTiming(receipt);
  assert.equal(result.harnessPhases, receipt.harnessPhases);
  assert.deepEqual(result.scenarios, receipt.scenarios);
  assert.equal(result.scenarios[0].commands[0].launcherTiming, receipt.scenarios[0].commands[0].launcherTiming);
  for (const mutate of [
    value => { value.harnessPhases.pop(); },
    value => { value.harnessPhases[0].state = 'running'; },
    value => { value.harnessPhases[0].observationIssue = 'unavailable'; },
    value => { delete value.scenarios[0].commands[0].wallNs; },
    value => { delete value.scenarios[0].commands[1].workflowPhase; },
  ]) {
    const changed = structuredClone(receipt); mutate(changed);
    assert.throws(() => performance.nativeMockWorkflowTiming(changed));
  }
});

test('release timing projects only completed finite intervals and cannot supply acceptance evidence', () => {
  const phases = {sourcePreparation: {state: 'completed', wallNs: 17},
    artifactVerification: {state: 'completed', wallNs: 23}};
  const line = value => 'ACTQL_NATIVE_RELEASE_PHASES ' + JSON.stringify(value) + '\n';
  const result = performance.nativeReleaseVerificationTiming('private child diagnostic\n' + line(phases));
  assert.deepEqual(result, {releaseVerificationPhases: phases});
  assert(!JSON.stringify(result).includes('private child diagnostic'));
  for (const text of ['', line(phases) + line(phases), 'ACTQL_NATIVE_RELEASE_PHASES {\n',
    line({...phases, privatePath: 'excluded'}),
    ...[
      {state: 'failed', wallNs: 17}, {state: 'unexecuted'},
      {state: 'completed', wallNs: -1}, {state: 'completed', wallNs: 1.5},
      {state: 'completed', wallNs: Number.MAX_SAFE_INTEGER + 1},
      {state: 'completed', wallNs: 17, error: 'excluded'},
    ].map(sourcePreparation => line({...phases, sourcePreparation}))]) {
    const invalid = performance.nativeReleaseVerificationTiming(text);
    assert.equal(invalid.releaseVerificationPhases, undefined);
    assert.equal(typeof invalid.releaseVerificationObservationIssue, 'string');
    assert(!JSON.stringify(invalid).includes('excluded'));
  }
});

test('actual release verification keeps its original failure with disabled or failing timing output', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-release-phase-'));
  try {
    const script = "import assert from 'node:assert/strict';" +
      "import {verifyNativeCliRelease} from './scripts/native-cli-release.mjs';" +
      "if(process.argv[2]==='throw')console.error=()=>{throw new Error('observation writer failed');};" +
      "await assert.rejects(verifyNativeCliRelease(process.argv[1]),error=>error.code==='ENOENT');";
    for (const mode of ['disabled', 'enabled', 'throw']) {
      const env = {...process.env}; delete env.ACTQL_CI_NATIVE_RELEASE_PHASES;
      if (mode !== 'disabled') env.ACTQL_CI_NATIVE_RELEASE_PHASES = '1';
      const result = spawnSync(process.execPath, ['--input-type=module', '-e', script, root, mode],
        {env, encoding:'utf8', timeout:10000});
      assert.equal(result.status, 0, result.stderr); assert.equal(result.signal, null);
      if (mode === 'enabled') {
        const prefix = 'ACTQL_NATIVE_RELEASE_PHASES ';
        assert(result.stderr.startsWith(prefix));
        const value = JSON.parse(result.stderr.slice(prefix.length));
        assert.equal(value.sourcePreparation.state, 'failed');
        assert(Number.isSafeInteger(value.sourcePreparation.wallNs) && value.sourcePreparation.wallNs >= 0);
        assert.deepEqual(value.artifactVerification, {state:'unexecuted'});
        assert(!result.stderr.includes(root));
      } else assert.equal(result.stderr, '');
    }
  } finally {rmSync(root, {recursive:true, force:true});}
});

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

function smokeScenarios(wallNs = nativeApprovalTarget.maxMs * 1e6) {
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
    scratch: {passed: () => events.push({kind: 'passed'}), close: () => events.push({kind: 'closed'})},
    log: message => events.push({kind: 'console', message}),
  });
  return {receipt, events, pending};
}

test('ordinary Native smoke persists the original slow approvals before rejecting and never marks them passed', async () => {
  const original = smokeScenarios(nativeApprovalTarget.maxMs * 1e6 + 1);
  const {events, pending} = await installedSmokeTail(original);
  await assert.rejects(pending, error => error.message.includes(`approval maximum exceeds ${nativeApprovalTarget.maxMs} ms`));
  assert.deepEqual(events.map(event => event.kind), ['receipt']);
  assert.deepEqual(events[0].value.scenarios, original);
  assert.equal(events[0].value.approvalSmoke.status, 'failed');
  assert.equal(events[0].value.approvalSmoke.samples.length, 2);
  assert.equal(events[0].options.flag, 'wx');
});

test('ordinary Native smoke accepts its maximum and refuses one nanosecond above without a p95 claim', () => {
  const scenarios = smokeScenarios(), original = structuredClone(scenarios);
  const passed = performance.assessOrdinaryNativeApprovalSmoke(scenarios);
  assert.equal(passed.status, 'passed');
  assert.equal(passed.maximumMs, nativeApprovalTarget.maxMs);
  assert.equal(passed.formalAcceptance, false); assert.equal(passed.samples.length, 2);
  assert.equal(Object.hasOwn(passed, 'p95Ms'), false);
  assert.deepEqual(scenarios, original);
  for (let index = 0; index < 2; index++) {
    const slow = structuredClone(scenarios); slow[index].commands[0].wallNs++;
    const result = performance.assessOrdinaryNativeApprovalSmoke(slow);
    assert.equal(result.status, 'failed'); assert.equal(result.samples[index].wallNs, nativeApprovalTarget.maxMs * 1e6 + 1);
    assert(result.failures.some(reason => reason.includes(`approval maximum exceeds ${nativeApprovalTarget.maxMs} ms`)));
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
  assert.deepEqual(passed.events.map(event => event.kind), ['receipt', 'passed', 'closed', 'console']);
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
  assert.deepEqual(formal.events.map(event => event.kind), ['receipt', 'passed', 'closed', 'console']);
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
  const owners = parse(ci).jobs.lint.steps.flatMap(step =>
    parseCommands(step.run ?? '').commands.map(command => ({step, argv: command.argv})))
    .filter(({argv}) => argv.includes('scripts/native-cli-interface-check.test.mjs'));
  assert.equal(owners.length, 1, 'Original admission controls need one existing lint owner');
  const {step, argv} = owners[0];
  assert.equal(step.if, undefined); assert.equal(step['continue-on-error'], undefined);
  assert.deepEqual(argv.slice(0, 4), ['node', 'scripts/local-checks.mjs', 'test', 'node']);
  const timeout = Number(argv[argv.indexOf('--timeout-seconds') + 1]);
  assert(timeout > 0 && timeout <= parse(ci).jobs.lint['timeout-minutes'] * 60);
  assert(argv.includes('--') && argv.includes('--test-name-pattern'));
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
  const slow = series(); slow.samples[0].wallNs = (nativeApprovalTarget.maxMs + 1000) * 1e6;
  slow.samples[0].verified = false;
  const result = assessNativeApproval(slow);
  assert.equal(result.status, 'failed'); assert.equal(result.summary.maxMs, nativeApprovalTarget.maxMs + 1000);
  assert(result.failures.some(value => value.includes('oracle failed')));
  assert(result.failures.some(value => value.includes('maximum')));
  const p95 = series(); p95.samples[0].wallNs = p95.samples[1].wallNs = nativeApprovalTarget.p95Ms * 1e6 + 1;
  assert(assessNativeApproval(p95).failures.some(value => value.includes('p95')));
});

test('Native approval accepts its p95 boundary and rejects one nanosecond above it', () => {
  assert.deepEqual(nativeApprovalTarget, {samples: 30, p95Ms: 6000, maxMs: 10000});
  assert.equal(assessNativeApproval(series()).status, 'passed');
  const selected = series();
  selected.samples[0].wallNs = selected.samples[1].wallNs = nativeApprovalTarget.p95Ms * 1e6;
  assert.equal(assessNativeApproval(selected).status, 'passed');
  selected.samples[0].wallNs++;
  selected.samples[1].wallNs++;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'failed');
  assert.deepEqual(result.failures, [`approval p95 exceeds ${nativeApprovalTarget.p95Ms} ms`]);
  assert.equal(result.summary.count, 30);
  assert.equal(result.summary.p95Ms, nativeApprovalTarget.p95Ms + 0.000001);
});

test('Native approval accepts its maximum boundary and rejects one nanosecond above it', () => {
  const selected = series(); selected.samples[0].wallNs = nativeApprovalTarget.maxMs * 1e6;
  assert.equal(assessNativeApproval(selected).status, 'passed');
  selected.samples[0].wallNs++;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'failed');
  assert.deepEqual(result.failures, [`approval maximum exceeds ${nativeApprovalTarget.maxMs} ms`]);
  assert.equal(result.summary.count, 30);
  assert.equal(result.summary.p95Ms, 2000);
  assert.equal(result.summary.maxMs, nativeApprovalTarget.maxMs + 0.000001);
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


test('syscall diagnosis is a separate explicit Linux resource mode with closed options', () => {
  assert.deepEqual(performance.nativeApprovalObservationOptions([], 'linux'),
    {measureResources: false, diagnoseSyscalls: false});
  assert.deepEqual(performance.nativeApprovalObservationOptions(['--measure-approval-resources'], 'darwin'),
    {measureResources: true, diagnoseSyscalls: false});
  assert.deepEqual(performance.nativeApprovalObservationOptions(
    ['--measure-approval-resources', '--diagnose-approval-syscalls'], 'linux'),
  {measureResources: true, diagnoseSyscalls: true});
  for (const extra of [['--diagnose-approval-syscalls'], ['--unknown'],
    ['--measure-approval-resources', '--measure-approval-resources']]) {
    assert.throws(() => performance.nativeApprovalObservationOptions(extra, 'linux'));
  }
  assert.throws(() => performance.nativeApprovalObservationOptions(
    ['--measure-approval-resources', '--diagnose-approval-syscalls'], 'darwin'));
});

test('ordinary and formal commands stay untraced while the separate diagnostic wraps the same OS sampled command', () => {
  const command = '/original/node', args = ['/original/actql', 'approve', 'same-run', '--wait', '--json'];
  assert.deepEqual(performance.nativeApprovalObservedCommand(command, args), {command, args});
  const formal = performance.nativeApprovalObservedCommand(command, args,
    {platform: 'linux', resources: '/owned/resources.txt'});
  assert.deepEqual(formal, {command: '/usr/bin/time', args:
    ['--verbose', '--output', '/owned/resources.txt', command, ...args]});
  const diagnostic = performance.nativeApprovalObservedCommand(command, args,
    {platform: 'linux', resources: '/owned/resources.txt', syscalls: '/owned/syscalls.txt'});
  assert.deepEqual(diagnostic, {command: '/usr/bin/strace', args:
    ['-f', '-c', '-o', '/owned/syscalls.txt', '--', formal.command, ...formal.args]});
  assert.deepEqual(performance.nativeApprovalObservedCommand(command, args,
    {platform: 'darwin', resources: '/owned/resources.txt'}), {command: '/usr/bin/time', args:
    ['-l', '-p', '-o', '/owned/resources.txt', command, ...args]});
  assert.throws(() => performance.nativeApprovalObservedCommand(command, args, {syscalls: '/owned/trace'}));
  assert.throws(() => performance.nativeApprovalObservedCommand(command, args,
    {platform: 'darwin', resources: '/owned/time', syscalls: '/owned/trace'}));
});

test('raw OS observations retain original faults filesystem blocks context switches and summary errors after scratch removal', async t => {
  const root = mkdtempSync(join(tmpdir(), 'native-resource-retention-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const text = ' User time (seconds): 0.30\n System time (seconds): 0.10\n' +
    ' Maximum resident set size (kbytes): 4096\n Major (requiring I/O) page faults: 4\n' +
    ' Minor (reclaiming a frame) page faults: 12\n Voluntary context switches: 3\n' +
    ' Involuntary context switches: 2\n File system inputs: 8\n File system outputs: 24\n';
  const source = join(root, 'original-time.txt'), output = join(root, 'approval-resources-case.txt');
  writeFileSync(source, text);
  const record = await performance.retainNativeApprovalObservation(source, output, 'resources');
  assert.equal(record.file, 'approval-resources-case.txt');
  assert.equal(record.bytes, Buffer.byteLength(text));
  assert.equal(record.sha256, (await import('node:crypto')).createHash('sha256').update(text).digest('hex'));
  rmSync(source); assert.equal(readFileSync(output, 'utf8'), text);
  const summary = ' % time     seconds  usecs/call     calls    errors syscall\n 80.00 0.800000 1 800000 0 getpid\n';
  writeFileSync(source, summary);
  const syscallOutput = join(root, 'approval-syscalls-case.txt');
  const syscallRecord = await performance.retainNativeApprovalObservation(source, syscallOutput, 'syscalls');
  assert.equal(syscallRecord.kind, 'syscalls'); assert.equal(readFileSync(syscallOutput, 'utf8'), summary);
  await assert.rejects(performance.retainNativeApprovalObservation(source, syscallOutput, 'syscalls'), {code: 'EEXIST'});
  await assert.rejects(performance.retainNativeApprovalObservation(source, join(root, 'unknown'), 'store'));
  const link = join(root, 'link'); symlinkSync(source, link);
  await assert.rejects(performance.retainNativeApprovalObservation(link, join(root, 'linked'), 'resources'));
  writeFileSync(source, Buffer.alloc(64 * 1024 + 1));
  await assert.rejects(performance.retainNativeApprovalObservation(source, join(root, 'oversized'), 'resources'));
  assert.equal(existsSync(join(root, 'oversized')), false);
});

test('formal samples reject instrumented diagnostics and unavailable original resource files', () => {
  const approval = {measurement: {sampler: '/usr/bin/time', wallIncludesSampler: true},
    observationFiles: [{kind: 'resources', file: 'approval-resources-original.txt', bytes: 100, sha256: 'a'.repeat(64)}]};
  performance.assertNativeApprovalObservation(approval);
  for (const change of [row => {row.measurement.diagnosticOnly = true;},
    row => {row.resourceObservationIssue = 'retention failed';}, row => {row.observationFiles = [];},
    row => {row.observationFiles[0].kind = 'syscalls';}, row => {row.observationFiles[0].sha256 = 'wrong';}]) {
    const changed = structuredClone(approval); change(changed);
    assert.throws(() => performance.assertNativeApprovalObservation(changed));
  }
});

test('required CI preserves the formal failure and runs at most one separate fresh diagnostic against the same artifact', () => {
  const job = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8')).jobs['native-cli-linux-local-mock'];
  const formal = job.steps.find(step => step.id === 'approval_profile');
  assert(formal && !formal.run.includes('strace') && !formal.run.includes('--diagnose-approval-syscalls'));
  assert.equal(formal['continue-on-error'], undefined);
  const diagnostics = job.steps.filter(step => step.run?.includes('--diagnose-approval-syscalls'));
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0].if, "${{ failure() && steps.approval_profile.outcome == 'failure' }}");
  assert(diagnostics[0].run.includes('--measure-approval-resources'));
  assert(diagnostics[0].run.includes('"$RUNNER_TEMP/native-cli-linux-local/release"'));
  assert(diagnostics[0].run.includes('timeout 300s'));
  assert.equal(diagnostics[0]['continue-on-error'], undefined);
  const upload = job.steps.find(step => step.name === 'Retain complete Native approval samples and original Mock receipts');
  for (const pattern of ['approval-resources-*.txt', 'approval-syscalls-*.txt', 'mock-syscalls-*.json']) assert(upload.with.path.includes(pattern));
  assert.equal(upload.if, 'always()');
});


test('retained artifact timing remains distinct from original full artifact verification', () => {
  const phases = {sourcePreparation: {state: 'completed', wallNs: 17},
    artifactVerification: {state: 'retained', wallNs: 9}};
  assert.deepEqual(performance.nativeReleaseVerificationTiming('ACTQL_NATIVE_RELEASE_PHASES ' + JSON.stringify(phases)),
    {releaseVerificationPhases: phases});
  phases.sourcePreparation.state = 'retained';
  assert.equal(performance.nativeReleaseVerificationTiming('ACTQL_NATIVE_RELEASE_PHASES ' + JSON.stringify(phases))
    .releaseVerificationPhases, undefined, 'Full Source checks cannot be relabeled as retained');
});

test('Native receipt never emits completion before its original scratch close or hides a cleanup refusal', async () => {
  const original = new Error('original scratch close failed'), events = [];
  await assert.rejects(performance.publishNativeApprovalReceipt({receipt: {scenarios: smokeScenarios()},
    receiptFile: '/owned-release/receipt.json', measureResources: true,
    writeFile: async () => {events.push('receipt');},
    scratch: {passed() {events.push('passed');}, close() {events.push('close'); throw original;}},
    log: () => events.push('completion'),
  }), error => error === original);
  assert.deepEqual(events, ['receipt', 'passed', 'close']);
});

function campaignProcessFixture(t, body) {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-mock-process-control-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const script = join(root, 'fixture.mjs');
  writeFileSync(script, `
import {writeFileSync, existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {serveNativeMockCampaign} from ${JSON.stringify(new URL('./native-mock-campaign.mjs', import.meta.url).href)};
import {captureNativeMockCommand} from ${JSON.stringify(new URL('./native-cli-mock-scenario.mjs', import.meta.url).href)};
import {createOwnedScratch} from ${JSON.stringify(new URL('./owned-scratch.mjs', import.meta.url).href)};
import {openReleaseTestRegistry} from ${JSON.stringify(new URL('./release-test-registry.mjs', import.meta.url).href)};
const root = process.argv[2], count = Number(process.argv.at(-1));
writeFileSync(join(root, 'worker-pid'), String(process.pid));
await serveNativeMockCampaign(count, async consume => {
  for (let index = 0; index < count; index++) await consume(index, async () => {
    ${body}
  });
});
`);
  return {root, script};
}

async function assertObservedProcessAbsent(path) {
  assert(existsSync(path), 'The original child must actually have started');
  const pid = Number(readFileSync(path, 'utf8'));
  assert(Number.isInteger(pid) && pid > 0);
  const until = Date.now() + 2000;
  while (Date.now() < until) {
    try {process.kill(pid, 0);}
    catch (error) {assert.equal(error.code, 'ESRCH'); return;}
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.fail('Original owned test process remained after campaign close');
}

test('Native Mock retained fixture confirms fresh registry and scratch close before ordered completion', async t => {
  const f = campaignProcessFixture(t, `
const scratch = await createOwnedScratch({parent: root, prefix: 'iteration-', label: 'Mock component control'});
const registry = await openReleaseTestRegistry([]);
await registry.close(); scratch.passed(); scratch.close();
if (existsSync(scratch.path)) throw new Error('original scratch did not close');
const receiptFile = join(root, 'receipt-' + index + '.json');
writeFileSync(receiptFile, JSON.stringify({index, pid: process.pid, scratch: scratch.path}));
console.log('Installed Native mock approval/recovery passed: ' + receiptFile);
return receiptFile;
`);
  const campaign = openNativeMockCampaign({...f, directory: f.root, count: 2, cwd: f.root, timeoutMs: 5000, killGraceMs: 500});
  const first = campaign.run(0);
  await assert.rejects(campaign.run(0), /overlapping|replayed/u);
  const original = await first, second = await campaign.run(1);
  assert.equal(original.status, 0, original.stderr); assert.equal(second.status, 0, second.stderr);
  assert.notEqual(original.receiptFile, second.receiptFile);
  const receipts = [original, second].map(value => JSON.parse(readFileSync(value.receiptFile, 'utf8')));
  assert.deepEqual(receipts.map(value => value.index), [0, 1]);
  assert.equal(receipts[0].pid, receipts[1].pid);
  assert.notEqual(receipts[0].scratch, receipts[1].scratch);
  assert(receipts.every(value => !existsSync(value.scratch)));
  assert.deepEqual(await campaign.close(), {code: 0, signal: null});
  await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
  await assert.rejects(campaign.run(0), /Closed/u);
});

test('Native Mock external watchdog stops synchronous Source work and its actual inherited child', async t => {
  const f = campaignProcessFixture(t, `
execFileSync(process.execPath, ['-e',
  'require("node:fs").writeFileSync(process.argv[1], String(process.pid)); setInterval(()=>{},1000);',
  join(root, 'command-pid')]);
throw new Error('blocked child unexpectedly returned');
`);
  const campaign = openNativeMockCampaign({...f, directory: f.root, count: 1, cwd: f.root, timeoutMs: 1000, killGraceMs: 500});
  const result = await campaign.run(0);
  assert.equal(result.error?.code, 'ETIMEDOUT');
  await assert.rejects(campaign.close(), error => error === result.error);
  await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
  await assertObservedProcessAbsent(join(f.root, 'command-pid'));
});

test('Native Mock watchdog retains timeout and joins the original detached Native command group', async t => {
  const f = campaignProcessFixture(t, `
await captureNativeMockCommand(process.execPath, ['-e',
  'require("node:fs").writeFileSync(process.argv[1], String(process.pid)); setInterval(()=>{},1000);',
  join(root, 'command-pid')], {cwd: root, env: process.env,
    stderrPath: join(root, 'original.stderr'), timeout: 5000});
throw new Error('owned command unexpectedly returned');
`);
  const campaign = openNativeMockCampaign({...f, directory: f.root, count: 1, cwd: f.root, timeoutMs: 1000, killGraceMs: 500});
  const result = await campaign.run(0);
  assert.equal(result.error?.code, 'ETIMEDOUT');
  await assert.rejects(campaign.close(), error => error === result.error);
  await assertObservedProcessAbsent(join(f.root, 'command-pid'));
  await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
});

test('Native Mock foreign completion and output overflow stop without a replay', async t => {
  for (const [body, expected] of [
    [`process.send({type: 'completed', iteration: 99, receiptFile: '/foreign'}); await new Promise(()=>{});`, /Foreign Native Mock iteration/u],
    [`process.stdout.write('x'.repeat(9 * 1024 ** 2)); await new Promise(()=>{});`, /output limit/u],
    [`process.exit(0);`, /did not complete its campaign/u],
  ]) {
    const f = campaignProcessFixture(t, body);
    const campaign = openNativeMockCampaign({...f, directory: f.root, count: 1, cwd: f.root, timeoutMs: 5000, killGraceMs: 500});
    const result = await campaign.run(0);
    assert.match(result.error?.message ?? '', expected);
    assert(Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr) <= 8 * 1024 ** 2);
    await assert.rejects(campaign.close(), error => error === result.error);
    await assert.rejects(campaign.run(0), /Closed/u);
    await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
  }
});


test('Native Mock original parent loss stops the retained fixture and its detached command without replay', async t => {
  const f = campaignProcessFixture(t, `
await captureNativeMockCommand(process.execPath, ['-e',
  'require("node:fs").writeFileSync(process.argv[1], String(process.pid)); setInterval(()=>{},1000);',
  join(root, 'command-pid')], {cwd: root, env: process.env,
    stderrPath: join(root, 'original.stderr'), timeout: 10000});
throw new Error('lost parent must never complete');
`);
  const parent = join(f.root, 'parent.mjs'), identities = join(f.root, 'owned-identities.json');
  writeFileSync(parent, `
import {execFileSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {openNativeMockCampaign} from ${JSON.stringify(new URL('./native-mock-campaign.mjs', import.meta.url).href)};
const root=${JSON.stringify(f.root)};
const campaign=openNativeMockCampaign({script:${JSON.stringify(f.script)},directory:root,count:1,cwd:root,timeoutMs:5000,killGraceMs:500});
void campaign.run(0);
const until=Date.now()+3000;
while(!existsSync(join(root,'command-pid'))&&Date.now()<until)await new Promise(resolve=>setTimeout(resolve,20));
if(!existsSync(join(root,'command-pid')))throw new Error('original command did not start');
const originals=['worker-pid','command-pid'].map(name=>{
  const pid=Number(readFileSync(join(root,name),'utf8'));
  return {pid,observation:execFileSync('ps',['-p',String(pid),'-o','lstart=','-o','command='],{encoding:'utf8'}).trim()};
});
writeFileSync(${JSON.stringify(identities)},JSON.stringify(originals));
process.exit(0);
`);
  let observed = [];
  // Failure cleanup can signal only an observed PID/start/command containing
  // this unique authored fixture root. Never guess from a stale PID alone.
  t.after(() => {
    for (const original of observed) {
      let current;
      try {current = execFileSync('ps', ['-p', String(original.pid), '-o', 'lstart=', '-o', 'command='],
        {encoding: 'utf8'}).trim();} catch {continue;}
      if (current === original.observation && current.includes(f.root)) {
        try {process.kill(original.pid, 'SIGKILL');} catch (error) {if (error.code !== 'ESRCH') throw error;}
      }
    }
  });
  const result = spawnSync(process.execPath, [parent], {cwd: f.root, encoding: 'utf8', timeout: 5000});
  if (existsSync(identities)) observed = JSON.parse(readFileSync(identities));
  assert.equal(result.error, undefined); assert.equal(result.signal, null); assert.equal(result.status, 0, result.stderr);
  await assertObservedProcessAbsent(join(f.root, 'command-pid'));
  await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
  assert(!existsSync(join(f.root, 'receipt-0.json')));
});


test('Native Mock final process failure retains its original stderr after the last completion', async t => {
  const f = campaignProcessFixture(t, `return join(root, 'component-receipt.json');`);
  writeFileSync(f.script, readFileSync(f.script, 'utf8') + '\nthrow new Error("original final fixture cause");\n');
  const campaign = openNativeMockCampaign({...f, directory: f.root, count: 1, cwd: f.root, timeoutMs: 5000, killGraceMs: 500});
  const completed = await campaign.run(0);
  assert.equal(completed.status, 0, completed.stderr);
  await assert.rejects(campaign.close(), error => {
    assert.equal(error.status, 1);
    assert.match(error.stderr, /original final fixture cause/u);
    return true;
  });
  await assertObservedProcessAbsent(join(f.root, 'worker-pid'));
});
