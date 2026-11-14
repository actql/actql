import assert from 'node:assert/strict';
import {latencySummary, resourceSummary, nativeApprovalTarget} from './operation-performance.mjs';
import {peakRssBytes} from './layout-measurement-support.mjs';
import {mockTemplates} from './native-cli-mock-scenario.mjs';

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
