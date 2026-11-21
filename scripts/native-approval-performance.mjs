import assert from 'node:assert/strict';
import {open, writeFile as writeReceiptFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {basename} from 'node:path';
import {latencySummary, resourceSummary, nativeApprovalTarget} from './operation-performance.mjs';
import {peakRssBytes} from './layout-measurement-support.mjs';
import {mockTemplates} from './native-cli-mock-scenario.mjs';

// Harness durations describe the existing sequential consumer, not Native CPU
// or physical cleanup acknowledgement. Scenario durations contain their command
// durations; neither is added to the separately sampled approval latency.
export async function observeNativeMockHarnessPhase(records, phase, action, template) {
  assert(['release-verification', 'source-platform-admission', 'scratch-creation',
    'registry-open', 'installation', 'installed-package-admission', 'scenario', 'shared-file-scenario',
    'installed-integrity', 'registry-close', 'release-project-sequences', 'original-mock-regressions'].includes(phase),
  'Unknown Mock harness phase');
  assert(phase === 'scenario' ? mockTemplates.includes(template) : template === undefined,
    'Mock harness template belongs only to its scenario');
  const record = {phase, ...(template === undefined ? {} : {template}), state: 'running'};
  records.push(record);
  const started = process.hrtime.bigint();
  try {
    const value = await action();
    record.state = 'completed';
    return value;
  } catch (error) {
    record.state = 'failed';
    throw error;
  } finally {
    const wallNs = Number(process.hrtime.bigint() - started);
    if (Number.isSafeInteger(wallNs) && wallNs >= 0) record.wallNs = wallNs;
    else record.observationIssue = 'Monotonic harness duration unavailable';
  }
}

export function nativeMockWorkflowTiming({harnessPhases, scenarios}) {
  assert(Array.isArray(harnessPhases) && harnessPhases.length > 0 &&
    harnessPhases.every(row => row.state === 'completed' && !row.observationIssue &&
      Number.isSafeInteger(row.wallNs) && row.wallNs >= 0), 'Incomplete Mock harness observations');
  assert(harnessPhases.some(row => row.phase === 'registry-close'), 'Registry closure observation missing');
  return {harnessPhases, scenarios: scenarios.map(({template, commands}) => ({template,
    commands: commands.map(({workflowPhase, wallNs, launcherTiming}) => {
      assert(typeof workflowPhase === 'string' && workflowPhase.length > 0 &&
        Number.isSafeInteger(wallNs) && wallNs > 0, 'Original Mock command timing unavailable');
      return {workflowPhase, wallNs, ...(launcherTiming ? {launcherTiming} : {})};
    })}))};
}

// Project only the two finite verifier intervals. No other child stderr, paths,
// command arguments or errors become timing DATA, and this is never admission.
export function nativeReleaseVerificationTiming(stderr) {
  try {
    assert.equal(typeof stderr, 'string');
    const prefix = 'ACTQL_NATIVE_RELEASE_PHASES ';
    const lines = stderr.split('\n').filter(line => line.startsWith(prefix));
    assert.equal(lines.length, 1); assert(lines[0].length <= 2048);
    const value = JSON.parse(lines[0].slice(prefix.length));
    assert.deepEqual(Object.keys(value).sort(), ['artifactVerification', 'sourcePreparation']);
    const phases = {};
    for (const phase of ['sourcePreparation', 'artifactVerification']) {
      const row = value[phase];
      assert.deepEqual(Object.keys(row).sort(), ['state', 'wallNs']);
      assert(phase === 'sourcePreparation' ? row.state === 'completed'
        : ['completed', 'retained'].includes(row.state));
      assert(Number.isSafeInteger(row.wallNs) && row.wallNs >= 0);
      phases[phase] = {state: row.state, wallNs: row.wallNs};
    }
    return {releaseVerificationPhases: phases};
  } catch {
    return {releaseVerificationObservationIssue: 'Release phase observation unavailable or invalid'};
  }
}

// The ordinary and formal paths keep their original command. Tracing is an
// explicit separate Linux diagnostic and cannot select a formal sample.
export function nativeApprovalObservationOptions(extra, platform) {
  const allowed = new Set(['--measure-approval-resources', '--diagnose-approval-syscalls']);
  assert(Array.isArray(extra) && extra.every(value => allowed.has(value)) &&
    new Set(extra).size === extra.length, 'Unknown or duplicate Native observation option');
  const measureResources = extra.includes('--measure-approval-resources');
  const diagnoseSyscalls = extra.includes('--diagnose-approval-syscalls');
  assert(!diagnoseSyscalls || (measureResources && platform === 'linux'),
    'Syscall diagnosis requires explicit Linux resource measurement');
  return {measureResources, diagnoseSyscalls};
}

export function nativeApprovalObservedCommand(command, args, {platform, resources, syscalls} = {}) {
  assert(!syscalls || (resources && platform === 'linux'), 'Syscall diagnosis requires Linux OS sampling');
  assert(!resources || ['linux', 'darwin'].includes(platform), 'Unsupported OS resource sampler');
  const observed = resources ? {command: '/usr/bin/time', args: [...(platform === 'darwin'
    ? ['-l', '-p', '-o', resources] : ['--verbose', '--output', resources]), command, ...args]}
    : {command, args};
  return syscalls ? {command: '/usr/bin/strace', args: ['-f', '-c', '-o', syscalls, '--',
    observed.command, ...observed.args]} : observed;
}

// Only the two original OS-tool text outputs are retained. Neither a private
// Store nor a trace containing syscall arguments is part of this inventory.
export async function retainNativeApprovalObservation(source, destination, kind) {
  assert(['resources', 'syscalls'].includes(kind), 'Unknown Native observation kind');
  const maximum = kind === 'resources' ? 64 * 1024 : 256 * 1024;
  const fd = await open(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await fd.stat();
    assert(before.isFile() && before.size > 0 && before.size <= maximum, 'Invalid OS observation size');
    const bytes = Buffer.alloc(before.size + 1);
    let bytesRead = 0;
    while (bytesRead < bytes.length) {
      const next = await fd.read(bytes, bytesRead, bytes.length - bytesRead, bytesRead);
      if (!next.bytesRead) break;
      bytesRead += next.bytesRead;
    }
    const after = await fd.stat();
    assert(bytesRead === before.size && before.size === after.size &&
      before.mtimeMs === after.mtimeMs && before.ctimeMs === after.ctimeMs,
    'OS observation changed after command exit');
    const body = bytes.subarray(0, bytesRead);
    await writeReceiptFile(destination, body, {flag: 'wx', mode: 0o600});
    return {kind, file: basename(destination), bytes: body.length,
      sha256: createHash('sha256').update(body).digest('hex')};
  } finally {await fd.close();}
}

export function assertNativeApprovalObservation(approval) {
  assert.notEqual(approval.measurement?.diagnosticOnly, true, 'Instrumented diagnosis is not a formal sample');
  assert.equal(approval.resourceObservationIssue, undefined, 'Original OS observation was not retained');
  const files = approval.observationFiles;
  assert(Array.isArray(files) && files.length === 1 && files[0].kind === 'resources',
    'One original OS resource file required');
  assert(Number.isSafeInteger(files[0].bytes) && files[0].bytes > 0 && files[0].bytes <= 64 * 1024);
  assert.match(files[0].file, /^approval-resources-[A-Za-z0-9._-]+\.txt$/u);
  assert.match(files[0].sha256, /^[a-f0-9]{64}$/u);
}

// A diagnostic-only producer binding cannot authorize a formal campaign.
// Local fixed-artifact campaigns without hosted provenance remain separate.
export function assertNativeApprovalAcceptanceBinding(binding) {
  assert.equal(binding.purpose, 'native-approval-acceptance');
  assert.equal(binding.acceptanceEligible, true);
  assert.notEqual(binding.diagnosticOnly, true);
  assert.equal(binding.producerJobConclusion, 'success');
}

// Two ordinary installed fixtures supply a maximum-only smoke check. Their
// process stop/cleanup deadline and the formal 30-sample profile are separate.
export function assessOrdinaryNativeApprovalSmoke(scenarios) {
  const failures = [], samples = [], maximumMs = nativeApprovalTarget.maxMs;
  if (!Array.isArray(scenarios) || scenarios.length !== mockTemplates.length) {
    failures.push('Both original Native mock scenarios are required');
  }
  for (const template of mockTemplates) {
    const selected = Array.isArray(scenarios) ? scenarios.filter(row => row?.template === template) : [];
    if (selected.length !== 1) {
      failures.push(`${template}: one original scenario required`); continue;
    }
    const commands = selected[0].commands;
    const approvals = Array.isArray(commands) ? commands.filter(command =>
      Array.isArray(command?.args) && command.args.includes('approve')) : [];
    if (approvals.length !== 1) {
      failures.push(`${template}: one original approval required`); continue;
    }
    const approval = approvals[0];
    const valid = Number.isSafeInteger(approval.wallNs) && approval.wallNs > 0;
    const completed = approval.code === 0 && approval.signal === null && approval.killed !== true;
    samples.push({template, wallNs: valid ? approval.wallNs : null,
      wallMs: valid ? approval.wallNs / 1e6 : null, completed});
    if (!valid) failures.push(`${template}: original approval timing missing or invalid`);
    if (!completed) failures.push(`${template}: original approval did not complete successfully`);
    if (valid && approval.wallNs > maximumMs * 1e6) {
      failures.push(`${template}: approval maximum exceeds ${maximumMs} ms (${approval.wallNs} ns)`);
    }
  }
  return {purpose: 'ordinary-small-fixture-maximum', maximumMs, samples,
    status: failures.length ? 'failed' : 'passed', failures, formalAcceptance: false};
}

function assessSharedFileNativeApproval({scenarios, harnessPhases}) {
  const failures = [];
  const scenario = Array.isArray(scenarios) && scenarios.length === 1 ? scenarios[0] : undefined;
  const resultRows = scenario?.resultRows ?? null;
  if (!scenario || scenario.template !== undefined || scenario.lockPathAbsent !== true || resultRows !== 1) {
    failures.push('One complete shared-file Mock scenario required');
  }
  const approvals = Array.isArray(scenario?.commands) ? scenario.commands.filter(command =>
    Array.isArray(command?.args) && command.args.includes('approve')) : [];
  const approval = approvals.length === 1 ? approvals[0] : undefined;
  if (!approval || approval.code !== 0 || approval.signal !== null || approval.killed === true) {
    failures.push('One successful shared-file approval required');
  }
  const approvalWallNs = Number.isSafeInteger(approval?.wallNs) && approval.wallNs > 0 ? approval.wallNs : null;
  if (approvalWallNs === null) failures.push('Original shared-file approval timing unavailable');
  const writeCount = Array.isArray(approval?.acceptance?.writes) ? approval.acceptance.writes.length : null;
  if (writeCount !== 3) failures.push('Three original shared-file write observations required');
  for (const phase of ['shared-file-scenario', 'installed-integrity', 'registry-close']) {
    const matches = Array.isArray(harnessPhases) ? harnessPhases.filter(row => row?.phase === phase) : [];
    if (matches.length !== 1 || matches[0].state !== 'completed') {
      failures.push(`One completed ${phase} observation required`);
    }
  }
  return {status: failures.length ? 'failed' : 'passed', approvalWallNs, writeCount, resultRows,
    failures, formalAcceptance: false};
}

// The caller has already closed its children and registry. Persist the original
// observations before a slow smoke fails, and acknowledge scratch only on pass.
export async function publishNativeApprovalReceipt({receipt, receiptFile, measureResources,
  sharedFileMock = false, scratch, writeFile = writeReceiptFile, log = console.log}) {
  assert.equal(receipt.scope === 'local-shared-file-mock-approval-recovery', sharedFileMock,
    'Shared-file Mock receipt requires its own mode');
  assert(!sharedFileMock || !measureResources, 'Shared-file Mock receipt requires its own mode');
  if (sharedFileMock) receipt.sharedFileApproval = assessSharedFileNativeApproval(receipt);
  else if (!measureResources) receipt.approvalSmoke = assessOrdinaryNativeApprovalSmoke(receipt.scenarios);
  await writeFile(receiptFile, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  const assessment = sharedFileMock ? receipt.sharedFileApproval : receipt.approvalSmoke;
  if (!measureResources) assert.equal(assessment.status, 'passed', assessment.failures.join('; '));
  scratch.passed();
  scratch.close();
  log(`Installed Native mock approval/recovery passed: ${receiptFile}`);
}

// The original sampler writes to its own file, leaving Native stderr intact.
// CPU/RSS are OS observations of the Node launcher plus its waited Native child,
// not process.resourceUsage() from the collector or a whole-Host memory claim.
export function approvalResources(text, platform) {
  const cpu = label => {
    const pattern = platform === 'darwin' ? new RegExp('^' + label + ' ([0-9]+(?:\\.[0-9]+)?)$', 'mu')
      : platform === 'linux' ? new RegExp('^\\s*' + (label === 'user' ? 'User' : 'System') + ' time \\(seconds\\): ([0-9]+(?:\\.[0-9]+)?)$', 'mu') : null;
    assert(pattern, 'Approval resource sampling requires macOS or GNU time');
    const values = [...text.matchAll(new RegExp(pattern.source, 'gmu'))];
    assert.equal(values.length, 1, 'One OS CPU observation required');
    const microseconds = Math.round(Number(values[0][1]) * 1000000);
    assert(Number.isSafeInteger(microseconds) && microseconds >= 0);
    return microseconds;
  };
  return {cpuUserUs: cpu('user'), cpuSystemUs: cpu('sys'), cpuScope: 'OS time: exited Node launcher and waited Native child',
    peakRssBytes: peakRssBytes(text, platform), rssScope: 'OS time: peak RSS of exited command and waited Native child'};
}

// Consume only the existing process-local diagnostics from a completed public
// approval. Missing/overflowed diagnostics are unavailable, never zero work.
export function approvalCallCounts(record) {
  assert.equal(record.code, 0, 'Approval did not complete');
  assert.equal(record.signal, null, 'Approval terminated by signal');
  const metadata = [], counters = new Map();
  for (const line of record.stderr.split('\n')) {
    if (line.startsWith('ACTQL_NATIVE_TIMINGS ')) {
      metadata.push(JSON.parse(line.slice('ACTQL_NATIVE_TIMINGS '.length)));
    } else if (line.startsWith('ACTQL_NATIVE_COUNTER ')) {
      const value = JSON.parse(line.slice('ACTQL_NATIVE_COUNTER '.length));
      assert(Number.isInteger(value.tag) && value.tag >= 0 && value.tag < 70 &&
        Number.isSafeInteger(value.count) && value.count >= 0 && !counters.has(value.tag),
      'Missing, invalid or duplicate Native approval counter');
      counters.set(value.tag, value.count);
    }
  }
  assert.equal(metadata.length, 1, 'Approval requires one actual Native process');
  assert.equal(counters.size, 70, 'Incomplete Native approval counter stream');
  const meta = metadata[0];
  assert(Number.isSafeInteger(meta.pid) && meta.pid > 0, 'Actual Native PID missing');
  assert.equal(meta.overflow, false, 'Native counters overflowed');
  assert.equal(meta.initializing_drops, 0, 'Native counter initialization incomplete');
  assert.equal(meta.invalid_tags, 0, 'Invalid Native counter tag');
  assert.equal(meta.invalid_amounts, 0, 'Invalid Native counter amount');
  return {pid: meta.pid, sqlPrepares: counters.get(1), currentCalls: counters.get(18),
    externalBoundaries: counters.get(64), unexpectedHelperRevalidations: counters.get(65), hostAuthorizations: counters.get(22),
    adoptionDigests: counters.get(26), materialAdmissions: counters.get(33),
    sourceValidations: counters.get(37), memberHashes: counters.get(16)};
}

// Inclusive phases may nest; report them individually instead of adding them.
export function approvalPhases(record, {requireCompleted = true} = {}) {
  const rows = record.stderr.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
    .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length)));
  const phases = rows.filter(row => row.tag >= 32 || row.tag === 5 || row.tag === 7);
  assert.equal(phases.length, 9, 'Approval phase observations incomplete');
  assert.equal(new Set(phases.map(row => row.tag)).size, 9, 'Duplicate approval phase');
  for (const row of phases) {
    if (requireCompleted) assert(Number.isSafeInteger(row.begins) && row.begins > 0 && row.begins === row.ends && row.active === 0 && row.unmatched_end === 0,
      'Approval phase missing or unfinished');
    assert(Number.isSafeInteger(row.sql_prepares) && row.sql_prepares >= 0 &&
      Number.isSafeInteger(row.current_calls) && row.current_calls >= 0, 'Phase counter observations missing');
    assert(Number.isSafeInteger(row.inclusive_ns) && row.inclusive_ns >= 0 &&
      Number.isSafeInteger(row.exclusive_ns) && row.exclusive_ns >= 0 && row.exclusive_ns <= row.inclusive_ns);
  }
  return phases;
}

// This is a basic-path work regression, not a latency target. Fixed startup /
// result resumption is separate from actual external callback and signer
// boundaries. A lower helper cannot increase its allowance by doing more work.
export function assertApprovalCallCounts(counts, writes) {
  assert(Number.isSafeInteger(writes) && writes > 0, 'Actual Effect writes required');
  for (const value of Object.values(counts)) assert(Number.isSafeInteger(value) && value >= 0);
  assert.equal(counts.unexpectedHelperRevalidations, 0, 'Unchanged signing helper repeated immutable validation');
  assert(counts.externalBoundaries > 0, 'Actual signing boundary observations missing');
  assert(counts.materialAdmissions > 0, 'Original scoped material admission missing');
  assert(counts.sqlPrepares > 0 && counts.sourceValidations > 0 && counts.currentCalls > 0,
    'Actual mutable/current and original validation observations missing');
  const boundaries = counts.externalBoundaries;
  assert(boundaries <= 32 + 64 * writes, 'External signing boundary count amplified through helpers');
  assert(counts.sourceValidations <= 32 + 2 * boundaries,
    'Immutable Source validation amplified through approval helpers');
  assert(counts.adoptionDigests <= 32 + 2 * boundaries,
    'Immutable adoption validation amplified through approval helpers');
  assert(counts.currentCalls <= 128 + 16 * (boundaries + writes),
    'Current observation amplified through approval helpers');
  assert(counts.sqlPrepares <= 512 + 64 * boundaries + 128 * writes,
    'SQL work amplified through approval helpers');
}

export function assessNativeApproval(series) {
  assert(['diagnostic', 'final'].includes(series.mode));
  assert.match(series.sourceSha, /^[a-f0-9]{40}$/u);
  assert.match(series.fixtureSha256, /^[a-f0-9]{64}$/u);
  assert.match(series.runnerSha256, /^[a-f0-9]{64}$/u);
  const seen = new Set(), failures = [], missing = [];
  for (const sample of series.samples) {
    assert(Number.isInteger(sample.iteration) && sample.iteration >= 0 && !seen.has(sample.iteration));
    seen.add(sample.iteration);
    assert.equal(sample.sourceSha, series.sourceSha, 'Mixed Native approval source');
    assert.equal(sample.fixtureSha256, series.fixtureSha256, 'Mixed Native approval fixture');
    assert.equal(sample.runnerSha256, series.runnerSha256, 'Mixed Native approval runner');
    assert(Number.isSafeInteger(sample.wallNs) && sample.wallNs >= 0);
    if (sample.completed !== true || sample.verified !== true) failures.push(`sample ${sample.iteration}: approval or Result oracle failed`);
  }
  // Failed and slow samples remain in the same raw population.
  const summary = latencySummary(series.samples.map(sample => ({...sample, cpuUserUs: sample.cpuUserUs ?? 0, cpuSystemUs: sample.cpuSystemUs ?? 0})), nativeApprovalTarget.samples);
  const resources = resourceSummary(series.samples, nativeApprovalTarget.samples);
  if (!resources.cpu.available) missing.push('actual command CPU observations');
  if (!resources.rss.available) missing.push('actual command peak RSS observations');
  if (series.mode !== 'final') missing.push('diagnostic only');
  if (series.samples.length !== nativeApprovalTarget.samples) missing.push('30 actual approval samples');
  if (summary.p95Ms !== null && summary.p95Ms > nativeApprovalTarget.p95Ms) failures.push(`approval p95 exceeds ${nativeApprovalTarget.p95Ms} ms`);
  if (summary.maxMs !== null && summary.maxMs > nativeApprovalTarget.maxMs) failures.push(`approval maximum exceeds ${nativeApprovalTarget.maxMs} ms`);
  return {status: failures.length ? 'failed' : missing.length ? 'incomplete' : 'passed',
    target: nativeApprovalTarget, summary, resources, failures, missing};
}
