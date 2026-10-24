import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {latencySummary} from './operation-performance.mjs';

export const digest = value => createHash('sha256').update(value).digest('hex');
export const jsonDigest = value => digest(JSON.stringify(value));
export const statuses = ['pass', 'warning', 'regression', 'incomplete', 'error'];
const rank = status => statuses.indexOf(status);
export const exitStatus = status => ({pass: 0, warning: 0, regression: 1, incomplete: 2, error: 3})[status] ?? 3;
export const worst = rows => rows.reduce((a, row) => rank(row.status) > rank(a) ? row.status : a, 'pass');

export function summarize(samples, minimum) {
  // The existing summary validates CPU columns, although its statistics use
  // wall time only. Absent child CPU stays absent in the retained observation.
  const summary = latencySummary(samples.map(row => ({...row,
    cpuUserUs: row.cpuUserUs ?? 0, cpuSystemUs: row.cpuSystemUs ?? 0})), minimum);
  return {...summary, referenceRangeMs: samples.length
    ? [Math.min(...samples.map(row => row.wallNs / 1e6)), summary.maxMs] : null};
}

export function assessMeasurements(report) {
  if (!Array.isArray(report.metrics) || report.metrics.length === 0) return [{target: 'report', metric: 'required-measurements',
    required: true, status: 'incomplete', reason: 'No required measurements observed', evidence: null}];
  return report.metrics.map(metric => {
    let status = metric.status ?? 'pass', reason = metric.reason ?? 'Observed required measurement';
    if (!statuses.includes(status)) {status = 'error'; reason = 'Invalid collector status';}
    if (status === 'pass') {
      if (metric.kind === 'latency') {
        if (!Array.isArray(metric.samples) || !metric.samples.length ||
            metric.samples.some(row => !row.verified || !row.completed ||
              !Number.isSafeInteger(row.wallNs) || row.wallNs < 0)) {
          status = 'error'; reason = 'Collector did not verify every public sample';
        } else if (metric.samples.length !== metric.requiredSamples) {
          status = 'incomplete'; reason = `Required ${metric.requiredSamples} samples; observed ${metric.samples.length}`;
        }
      } else if (!Number.isFinite(metric.value) || metric.value < 0) {
        status = 'incomplete'; reason = 'Actual nonnegative measurement missing';
      }
      if (!metric.evidence || !metric.fixtureSha256) {
        status = 'incomplete'; reason = 'Measurement identity/evidence missing';
      }
    }
    return {target: metric.target, metric: metric.id, required: metric.required, status, reason,
      evidence: metric.evidence ?? null};
  });
}

const environmentFields = ['platform', 'architecture', 'osRelease', 'cpuModel', 'logicalCpus',
  'node', 'nodeExecutableSha256', 'python', 'moon', 'toolchainSha256', 'buildSettings'];
export function compareReports(base, current, policy) {
  assert(base?.format === 'actql-health/0.1' && current?.format === 'actql-health/0.1', 'Unsupported report format');
  const reasons = [];
  for (const key of environmentFields) {
    if (base.environment?.[key] == null || current.environment?.[key] == null ||
        String(base.environment[key]).startsWith('unavailable') || String(current.environment[key]).startsWith('unavailable') ||
        jsonDigest(base.environment[key]) !== jsonDigest(current.environment[key])) reasons.push(`environment.${key}`);
  }
  if (base.mode !== current.mode) reasons.push('mode/sample methodology');
  if (base.methodologySha256 !== current.methodologySha256) reasons.push('fixture/methodology digest');
  if (base.source?.dirty || current.source?.dirty) reasons.push('dirty source is diagnostic');
  if (!base.source?.sha || !current.source?.sha) reasons.push('missing source identity');
  if (!base.baseline?.id || !base.baseline?.reason || base.baseline?.reviewed !== true) reasons.push('reviewed baseline id/reason absent');
  if (base.sourceChanged || current.sourceChanged || base.environmentChanged || current.environmentChanged) reasons.push('source/environment changed during measurement');
  for (const [label, report] of [['base', base], ['current', current]]) {
    if (!report.installedPayloadsUnchanged || !report.sourceAfter || !report.environmentAfter) reasons.push(`${label}: before/after custody observation missing`);
    if (report.sourceAfter && jsonDigest(report.sourceAfter) !== jsonDigest(report.source)) reasons.push(`${label}: source before/after differs`);
    if (report.environmentAfter && jsonDigest(report.environmentAfter) !== jsonDigest(report.environment)) reasons.push(`${label}: environment before/after differs`);
    if (assessMeasurements(report).some(row => row.required && ['error', 'incomplete'].includes(row.status))) reasons.push(`${label}: incomplete required measurements`);
    for (const artifact of report.artifacts ?? []) {
      if (artifact.sourceSha !== report.source.sha || !/^[a-f0-9]{64}$/u.test(artifact.sha256 ?? '')) reasons.push(`${label}: unbound artifact ${artifact.name}`);
    }
  }
  if (reasons.length) return {available: true, comparable: false, baselineId: base.baseline?.id ?? null,
    status: 'incomplete', reasons, verdicts: []};
  const verdicts = [];
  for (const metric of current.metrics) {
    if (metric.status && metric.status !== 'pass') continue;
    const previous = base.metrics.find(row => row.id === metric.id && row.target === metric.target);
    if (!previous || previous.kind !== metric.kind || previous.artifactKind !== metric.artifactKind ||
        previous.fixtureSha256 !== metric.fixtureSha256 || previous.unit !== metric.unit) {
      verdicts.push({metric: metric.id, target: metric.target, status: 'incomplete', reason: 'No compatible baseline metric'}); continue;
    }
    const before = metric.kind === 'latency' ? summarize(previous.samples, previous.requiredSamples).medianMs : previous.value;
    const after = metric.kind === 'latency' ? summarize(metric.samples, metric.requiredSamples).medianMs : metric.value;
    if (!Number.isFinite(before) || before <= 0 || !Number.isFinite(after)) {
      verdicts.push({metric: metric.id, target: metric.target, status: 'incomplete', reason: 'No positive measured baseline denominator'}); continue;
    }
    const absoluteDelta = after - before, relativeDelta = absoluteDelta / before;
    let status = 'pass', reason = 'Within configured comparison thresholds';
    if (metric.kind === 'size') {
      const threshold = metric.artifactKind === 'browser-gzip' ? policy.size.browserGzip : policy.size.package;
      if (relativeDelta >= threshold.regression) status = 'regression';
      else if (relativeDelta >= threshold.warning) status = 'warning';
    } else if (metric.kind === 'latency') {
      const threshold = metric.temperature === 'cold' ? policy.performance.cold : policy.performance.warm;
      if (relativeDelta >= threshold.relative && absoluteDelta >= threshold.absoluteMs) status = 'warning';
      reason = 'Reference median only; formal performance acceptance remains separate';
    } else if (metric.kind === 'rss' && relativeDelta >= policy.performance.rssRelative) status = 'warning';
    verdicts.push({metric: metric.id, target: metric.target, status, reason,
      before, after, absoluteDelta, relativeDelta, unit: metric.kind === 'latency' ? 'ms' : metric.unit,
      evidence: metric.evidence});
  }
  return {available: true, comparable: true, baselineId: base.baseline.id, status: worst(verdicts), reasons: [], verdicts};
}

export function finishReport(report) {
  report.verdicts = assessMeasurements(report);
  const required = report.verdicts.filter(row => row.required || row.status === 'error');
  const rows = [...required, ...(report.errors ?? []).map(error => ({status: 'error', ...error}))];
  if (report.comparison?.available) rows.push({status: report.comparison.status});
  if (report.sourceChanged || report.environmentChanged) rows.push({status: 'error'});
  report.status = worst(rows);
  report.exitCode = exitStatus(report.status);
  report.formalAcceptance = false;
  return report;
}

const escape = value => String(value ?? '').replaceAll('|', '\\|').replaceAll('\n', ' ');
export function markdown(report) {
  const lines = [`# ActQL Health ${report.mode}`, '', `Status: **${report.status}**. Source: \`${report.source?.sha ?? 'unavailable'}\`${report.source?.dirty ? ' (dirty diagnostic)' : ''}.`,
    '', report.comparison?.available ? `Baseline: ${escape(report.comparison.baselineId)}; comparable: ${report.comparison.comparable}.`
      : 'Comparison unavailable: no reviewed baseline selected. Measurements do not establish absence of regressions.',
    '', '| Target | Metric | Observation | Status | Reason |', '| --- | --- | --- | --- | --- |'];
  for (const row of report.verdicts ?? []) {
    const metric = report.metrics.find(metric => metric.id === row.metric && metric.target === row.target);
    const summary = metric?.kind === 'latency' && metric.samples?.length ? summarize(metric.samples, metric.requiredSamples) : null;
    const value = summary ? `${summary.count}/${metric.requiredSamples}; median ${summary.medianMs.toFixed(3)} ms; range ${summary.referenceRangeMs.map(n => n.toFixed(3)).join('–')} ms`
      : metric?.value == null ? 'unmeasured' : `${metric.value} ${metric.unit}`;
    lines.push(`| ${escape(row.target)} | ${escape(row.metric)} | ${value} | ${row.status} | ${escape(row.reason)} |`);
  }
  for (const row of report.comparison?.verdicts ?? []) lines.push(`| ${escape(row.target)} | Δ ${escape(row.metric)} | ${row.absoluteDelta ?? 'unknown'} ${row.unit ?? ''}; ${row.relativeDelta == null ? '' : (row.relativeDelta * 100).toFixed(2) + '%'} | ${row.status} | ${escape(row.reason)} |`);
  for (const reason of report.comparison?.reasons ?? []) lines.push('', `Non-comparable: ${escape(reason)}.`);
  for (const error of report.errors ?? []) lines.push('', `Error (${escape(error.target)}): ${escape(error.message)}`);
  lines.push('', 'Build/packaging is separate from process and operation measurements. Small-sample ranges are diagnostic; no formal acceptance, SQLite equivalence, p95 promotion or automatic baseline update.', '');
  return lines.join('\n');
}

export async function saveReport(directory, report) {
  await mkdir(directory, {recursive: true});
  await writeFile(join(directory, 'report.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  await writeFile(join(directory, 'summary.md'), markdown(report), {mode: 0o600});
}
