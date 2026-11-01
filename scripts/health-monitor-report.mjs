import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {latencySummary, assessPublicLatencySamples, resourceSummary} from './operation-performance.mjs';

export const digest = value => createHash('sha256').update(value).digest('hex');
export const jsonDigest = value => digest(JSON.stringify(value));
export const statuses = ['pass', 'warning', 'regression', 'incomplete', 'error'];
const rank = status => statuses.indexOf(status);
const profilePolicy = JSON.parse(readFileSync(new URL('../benchmarks/health/config.json', import.meta.url)));
export const exitStatus = status => ({pass: 0, warning: 0, regression: 1, incomplete: 2, error: 3})[status] ?? 3;
export const worst = rows => rows.reduce((a, row) => rank(row.status) > rank(a) ? row.status : a, 'pass');

export function summarize(samples, minimum) {
  // The existing summary validates CPU columns, although its statistics use
  // wall time only. Absent child CPU stays absent in the retained observation.
  const summary = latencySummary(samples.map(row => ({...row,
    cpuUserUs: row.cpuUserUs ?? 0, cpuSystemUs: row.cpuSystemUs ?? 0})), minimum);
  return {...summary, ...resourceSummary(samples, minimum), referenceRangeMs: samples.length
    ? [Math.min(...samples.map(row => row.wallNs / 1e6)), summary.maxMs] : null};
}

const publicLatencyMetric = metric => metric.kind === 'latency' &&
  (metric.id.startsWith('warm-') || ['first-init', 'cold-existing', 'cold-new-run', 'cold-result',
    'cold-process-first-result-close'].includes(metric.id));

export function assessMeasurements(report) {
  if (!Array.isArray(report.metrics) || report.metrics.length === 0) return [{target: 'report', metric: 'required-measurements',
    required: true, status: 'incomplete', reason: 'No required measurements observed', evidence: null}];
  return report.metrics.map(metric => {
    let status = metric.status ?? 'pass', reason = metric.reason ?? 'Observed required measurement';
    if (!statuses.includes(status)) {status = 'error'; reason = 'Invalid collector status';}
    if (typeof metric.id !== 'string' || !metric.id.length) {status = 'error'; reason = 'Invalid measurement identity';}
    if (status === 'pass') {
      if (metric.kind === 'latency') {
        if (!Array.isArray(metric.samples) || !metric.samples.length ||
            metric.samples.some(row => !row.verified || !row.completed ||
              !Number.isSafeInteger(row.wallNs) || row.wallNs < 0)) {
          status = 'error'; reason = 'Collector did not verify every public sample';
        } else if (metric.samples.length !== metric.requiredSamples) {
          status = 'incomplete'; reason = `Required ${metric.requiredSamples} samples; observed ${metric.samples.length}`;
        } else if (report.mode === 'release' && publicLatencyMetric(metric)) {
          try {
            const checked = assessPublicLatencySamples(metric.samples, metric.requiredSamples, metric.id);
            if (checked.failures.length) {status = 'regression'; reason = checked.failures.join('; ');}
            else if (checked.missing.length) {status = 'incomplete'; reason = checked.missing.join('; ');}
            else {
              const resources = resourceSummary(metric.samples, metric.requiredSamples);
              if (!resources.cpu.available || !resources.rss.available) {
                status = 'incomplete'; reason = 'Actual scoped CPU/peak RSS observations missing';
              }
            }
          } catch (error) {status = 'error'; reason = error.message;}
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

// Fixed monitor profile, independent of a saved report's required flags/counts.
// This is the command's inventory, not a validator for product contracts.
export function measurementProfile(mode, environment = {}) {
  const size = (id, target, artifactKind) => ({id, target, kind: 'size', artifactKind, unit: 'bytes', required: true});
  const latency = (id, cold = false, target = 'node-local') => ({id, target, kind: 'latency', unit: 'ms', required: true,
    temperature: cold ? 'cold' : 'warm', requiredSamples: profilePolicy[mode]?.[cold ? 'coldSamples' : 'warmSamples']});
  const rows = [...['client-wire', 'sdk', 'node', 'run-host-core', 'local-node'].map(name => size('tarball:@actql/' + name, '@actql/' + name, 'npm')),
    size('installed:node-local', 'node-local', 'installed'), size('installed:remote-sdk', 'remote-sdk', 'installed'),
    size('browser-raw', 'remote-sdk', 'browser'), size('browser-gzip', 'remote-sdk', 'browser-gzip'),
    {id: 'peak-rss', target: 'node-local', kind: 'rss', unit: 'bytes', required: true}];
  if (mode === 'quick') return [...rows,
    ...['warm-select', 'warm-join', 'warm-aggregate', 'warm-saved', 'warm-status'].map(id => latency(id)),
    ...['cold-process-first-result-close', 'cold-host-initialization', 'cold-first-query', 'cold-first-close', 'mock-workflow'].map(id => latency(id, true))];
  if (mode !== 'release') return [];
  rows.push(...['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode'].map(id => latency(id)),
    ...['first-init', 'cold-existing', 'mock-workflow'].map(id => latency(id, true)));
  for (const target of ['native', 'python']) rows.push(...['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode'].map(id => latency(id, false, target)));
  rows.push(...['first-init', 'cold-existing'].map(id => latency(id, true, 'python')));
  rows.push(...['cold-new-run', 'cold-result'].map(id => ({...latency(id, true, 'native'), requiredSamples: 100})),
    ...['init-separate', 'first-query-separate'].map(id => ({id, target: 'native', kind: 'reference', unit: 'ms', required: true})));
  rows.push(...['actql', 'actql-sdk', 'actql-local-runtime'].map(id => size(id, 'python', 'wheel')));
  rows.push(size('installed:python-products', 'python', 'installed'));
  const key = {'darwin-arm64': 'darwin-arm64', 'linux-x64': 'linux-x64-gnu'}[environment.platform + '-' + environment.architecture];
  if (key) rows.push(size('actql', 'native', 'npm'), size('@actql/cli-' + key, 'native', 'npm'),
    size('@actql/cli-' + key + ':bin/actql-native-client', 'native', 'native'),
    size('installed:actql', 'native', 'installed'), size('installed:@actql/cli-' + key, 'native', 'installed'));
  else rows.push(size('native-platform-artifacts', 'native', 'native'));
  return rows;
}

function profileAssessment(report) {
  const mode = report.mode === 'compare' ? report.measuredMode : report.mode;
  if (!['quick', 'release'].includes(mode)) return assessMeasurements(report);
  const metrics = Array.isArray(report.metrics) ? report.metrics : [];
  const output = [], keys = new Set();
  for (const expected of measurementProfile(mode, report.environment)) {
    const key = expected.target + ':' + expected.id; keys.add(key);
    const found = metrics.filter(row => row.id === expected.id && row.target === expected.target);
    if (found.length !== 1) {
      output.push({metric: expected.id, target: expected.target, required: true, status: 'incomplete',
        reason: found.length ? 'Duplicate required profile measurement' : 'Required profile measurement absent'}); continue;
    }
    const metric = found[0];
    if (metric.kind === 'latency' && metric.samples?.some(row => !row.verified || !row.completed)) {
      output.push({metric: expected.id, target: expected.target, required: true, status: 'error',
        reason: 'Original public sample failed verification/completion', evidence: metric.evidence}); continue;
    }
    if (metric.kind !== expected.kind || metric.unit !== expected.unit ||
        (expected.artifactKind && metric.artifactKind !== expected.artifactKind) ||
        (expected.temperature && metric.temperature !== expected.temperature) ||
        (expected.kind === 'latency' && metric.requiredSamples !== expected.requiredSamples)) {
      output.push({metric: expected.id, target: expected.target, required: true, status: 'incomplete',
        reason: 'Saved measurement does not match fixed command profile/counts', evidence: metric.evidence}); continue;
    }
    output.push(...assessMeasurements({mode, metrics: [{...metric, ...expected}]}));
  }
  output.push(...assessMeasurements({mode, metrics: metrics.filter(row => !keys.has(row.target + ':' + row.id))}).filter(row => row.metric !== 'required-measurements'));
  if (mode === 'release') {
    const platformKey = {'darwin-arm64': 'darwin-arm64', 'linux-x64': 'linux-x64-gnu'}[
      report.environment?.platform + '-' + report.environment?.architecture];
    const names = ['actql', '@actql/cli-' + platformKey].sort();
    const artifacts = (report.artifacts ?? []).filter(row => row.name === 'native-products-installed');
    const before = artifacts.length === 1 ? artifacts[0] : undefined, after = report.nativeInstalledInventoryAfter;
    const valid = observation => platformKey && observation?.sourceSha === report.source?.sha &&
      observation.platform === platformKey && typeof observation.cohortSha256 === 'string' &&
      /^[a-f0-9]{64}$/u.test(observation.cohortSha256) &&
      jsonDigest(Object.keys(observation.packages ?? {}).sort()) === jsonDigest(names) &&
      Object.values(observation.packages).every(row => Number.isSafeInteger(row?.installedBytes) && row.installedBytes > 0 &&
        Number.isSafeInteger(row?.payloads) && row.payloads > 0 && typeof row?.inventorySha256 === 'string' &&
        /^[a-f0-9]{64}$/u.test(row.inventorySha256));
    const changed = report.nativeInstalledPayloadsUnchanged === false ||
      (before?.sha256 && after && before.sha256 !== jsonDigest(after));
    if (changed || report.nativeInstalledPayloadsUnchanged !== true || !valid(before?.installedInventory) || !valid(after) ||
        before.sourceSha !== report.source?.sha || before.sha256 !== jsonDigest(before.installedInventory) ||
        before.installedBytes !== names.reduce((sum, name) => sum + before.installedInventory.packages[name].installedBytes, 0) ||
        names.some(name => metrics.find(row => row.target === 'native' && row.id === 'installed:' + name)?.value !==
          before.installedInventory.packages[name].installedBytes)) {
      output.push({metric: 'native-installed-custody', target: 'native', required: true,
        status: changed ? 'error' : 'incomplete', reason: changed
          ? 'Native installed product payloads or selected cohort changed after collection'
          : 'Native installed before/after identity observation missing or inconsistent'});
    }
  }
  if (mode === 'release') {
    const artifacts = (report.artifacts ?? []).filter(row => row.name === 'python-products-installed');
    const before = artifacts.length === 1 ? artifacts[0] : undefined;
    const after = report.pythonInstalledInventoryAfter;
    const metric = metrics.find(row => row.target === 'python' && row.id === 'installed:python-products');
    const valid = snapshot => Array.isArray(snapshot?.files) && snapshot.files.length > 0 &&
      Number.isSafeInteger(snapshot.bytes) && snapshot.bytes > 0 &&
      jsonDigest(snapshot.files) === snapshot.sha256 &&
      snapshot.files.every(row => Number.isSafeInteger(row?.bytes) && row.bytes >= 0) &&
      snapshot.files.reduce((sum, row) => sum + row.bytes, 0) === snapshot.bytes;
    const changed = report.pythonInstalledPayloadsUnchanged === false ||
      (before?.sha256 && after?.sha256 && before.sha256 !== after.sha256);
    if (changed || report.pythonInstalledPayloadsUnchanged !== true || !valid(before?.installedInventory) ||
        !valid(after) || before?.sourceSha !== report.source?.sha || before?.sha256 !== before?.installedInventory?.sha256 ||
        before?.installedBytes !== metric?.value || after?.bytes !== metric?.value) {
      output.push({metric: 'python-installed-custody', target: 'python', required: true,
        status: changed ? 'error' : 'incomplete', reason: changed
          ? 'Python installed product namespaces changed after collection'
          : 'Python installed before/after identity observation missing or inconsistent'});
    }
  }
  if (mode === 'release' && !metrics.some(row => row.target === 'python' && row.artifactKind === 'wasm' && Number.isFinite(row.value))) {
    output.push({metric: 'distributed-wasm', target: 'python', required: true, status: 'incomplete', reason: 'Required actual distributed Wasm measurement absent'});
  }
  return output;
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
  if (base.mode === 'release' || current.mode === 'release' ||
      base.environment?.pythonRuntime !== undefined || current.environment?.pythonRuntime !== undefined) {
    const valid = value => value !== null && typeof value === 'object' &&
      typeof value.version === 'string' && typeof value.executableSha256 === 'string' &&
      /^\d+\.\d+\.\d+[a-z0-9.+-]*$/iu.test(value.version ?? '') &&
      /^[a-f0-9]{64}$/u.test(value.executableSha256 ?? '');
    if (!valid(base.environment?.pythonRuntime) || !valid(current.environment?.pythonRuntime) ||
        jsonDigest(base.environment.pythonRuntime) !== jsonDigest(current.environment.pythonRuntime)) {
      reasons.push('environment.pythonRuntime');
    }
  }
  if (base.mode !== current.mode) reasons.push('mode/sample methodology');
  if (base.methodologySha256 !== current.methodologySha256) reasons.push('fixture/methodology digest');
  if (base.source?.dirty || current.source?.dirty) reasons.push('dirty source is diagnostic');
  if (!base.source?.sha || !current.source?.sha) reasons.push('missing source identity');
  if (!base.baseline?.id || !base.baseline?.reason || base.baseline?.reviewed !== true) reasons.push('reviewed baseline id/reason absent');
  if (base.sourceChanged || current.sourceChanged || base.environmentChanged || current.environmentChanged) reasons.push('source/environment changed during measurement');
  for (const [label, report] of [['base', base], ['current', current]]) {
    if (report.errors?.length || report.status === 'error' ||
        (report.guardExitCode != null && report.guardExitCode !== exitStatus(report.status))) reasons.push(`${label}: collector/guard errors retained`);
    if (!report.installedPayloadsUnchanged || !report.sourceAfter || !report.environmentAfter) reasons.push(`${label}: before/after custody observation missing`);
    if (report.sourceAfter && jsonDigest(report.sourceAfter) !== jsonDigest(report.source)) reasons.push(`${label}: source before/after differs`);
    if (report.environmentAfter && jsonDigest(report.environmentAfter) !== jsonDigest(report.environment)) reasons.push(`${label}: environment before/after differs`);
    if (profileAssessment(report).some(row => row.required && row.status !== 'pass')) reasons.push(`${label}: incomplete required profile measurements`);
    for (const artifact of report.artifacts ?? []) {
      if (artifact.sourceSha !== report.source.sha || !/^[a-f0-9]{64}$/u.test(artifact.sha256 ?? '')) reasons.push(`${label}: unbound artifact ${artifact.name}`);
    }
  }
  if (reasons.length) return {available: true, comparable: false, baselineId: base.baseline?.id ?? null,
    status: 'incomplete', reasons, verdicts: []};
  const verdicts = [];
  for (const metric of current.metrics) {
    if (metric.kind === 'reference') continue; // Build/preparation timing is reference-only, never a size/runtime gate.
    if (metric.status && metric.status !== 'pass') continue;
    const previous = base.metrics.find(row => row.id === metric.id && row.target === metric.target);
    if (!previous || previous.kind !== metric.kind || previous.artifactKind !== metric.artifactKind ||
        previous.fixtureSha256 !== metric.fixtureSha256 || previous.unit !== metric.unit) {
      verdicts.push({metric: metric.id, target: metric.target, status: 'incomplete', reason: 'No compatible baseline metric'}); continue;
    }
    const beforeSummary = metric.kind === 'latency' ? summarize(previous.samples, previous.requiredSamples) : null;
    const afterSummary = metric.kind === 'latency' ? summarize(metric.samples, metric.requiredSamples) : null;
    if (current.mode === 'release' && beforeSummary &&
        (jsonDigest(beforeSummary.cpu.scopes) !== jsonDigest(afterSummary.cpu.scopes) ||
         jsonDigest(beforeSummary.rss.scopes) !== jsonDigest(afterSummary.rss.scopes))) {
      verdicts.push({metric: metric.id, target: metric.target, status: 'incomplete',
        reason: 'CPU/RSS observation scopes differ; do not compare unlike measurements'}); continue;
    }
    const before = beforeSummary ? beforeSummary.medianMs : previous.value;
    const after = afterSummary ? afterSummary.medianMs : metric.value;
    if (!Number.isFinite(before) || before <= 0 || !Number.isFinite(after)) {
      verdicts.push({metric: metric.id, target: metric.target, status: 'incomplete', reason: 'No positive measured baseline denominator'}); continue;
    }
    const absoluteDelta = after - before, relativeDelta = absoluteDelta / before;
    let status = 'pass', reason = 'Within configured comparison thresholds';
    if (metric.kind === 'size') {
      const threshold = metric.artifactKind === 'browser-gzip' ? policy.size.browserGzip
        : ['npm', 'wheel', 'native', 'wasm'].includes(metric.artifactKind) ? policy.size.package : null;
      if (threshold && relativeDelta >= threshold.regression) status = 'regression';
      else if (threshold && relativeDelta >= threshold.warning) status = 'warning';
      if (!threshold) reason = 'Reference size delta; no configured gate for this artifact kind';
    } else if (metric.kind === 'latency') {
      const threshold = metric.temperature === 'cold' ? policy.performance.cold : policy.performance.warm;
      const statistics = current.mode === 'release' ? ['medianMs', 'p95Ms', 'maxMs'] : ['medianMs'];
      const regressed = statistics.filter(key => Number.isFinite(beforeSummary[key]) && beforeSummary[key] > 0 &&
        (afterSummary[key] - beforeSummary[key]) / beforeSummary[key] >= threshold.relative &&
        afterSummary[key] - beforeSummary[key] >= threshold.absoluteMs);
      if (regressed.length) status = current.mode === 'release' ? 'regression' : 'warning';
      reason = current.mode === 'release'
        ? `Matched median/p95/max comparison${regressed.length ? ': regressed ' + regressed.join(', ') : ''}`
        : 'Reference median only; formal performance acceptance remains separate';
    } else if (metric.kind === 'rss' && relativeDelta >= policy.performance.rssRelative) status = 'warning';
    verdicts.push({metric: metric.id, target: metric.target, status, reason,
      before, after, absoluteDelta, relativeDelta, unit: metric.kind === 'latency' ? 'ms' : metric.unit,
      ...(beforeSummary ? {statistics: Object.fromEntries(['medianMs', 'p95Ms', 'maxMs'].map(key => [key,
        {before: beforeSummary[key], after: afterSummary[key],
          absoluteDelta: beforeSummary[key] === null || afterSummary[key] === null ? null : afterSummary[key] - beforeSummary[key]}])),
      cpu: {before: beforeSummary.cpu, after: afterSummary.cpu},
      rss: {before: beforeSummary.rss, after: afterSummary.rss}} : {}),
      evidence: metric.evidence});
  }
  return {available: true, comparable: true, baselineId: base.baseline.id, status: worst(verdicts), reasons: [], verdicts};
}

export function finishReport(report) {
  report.verdicts = profileAssessment(report);
  if ((report.mode === 'release' || report.mode === 'compare' && report.measuredMode === 'release') &&
      (!report.comparison?.available || report.comparison.comparable !== true)) {
    report.verdicts.push({metric: 'matched-performance-baseline', target: 'report', required: true,
      status: 'incomplete', reason: 'Final performance requires an actual reviewed comparable baseline; absence is not a pass'});
  }
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
    const value = summary ? `${summary.count}/${metric.requiredSamples}; median ${summary.medianMs.toFixed(3)} ms; p95 ${summary.p95Ms === null ? 'unverified' : summary.p95Ms.toFixed(3) + ' ms'}; max ${summary.maxMs.toFixed(3)} ms; CPU ${summary.cpu.available ? summary.cpu.medianMs.toFixed(3) + ' ms median' : 'unavailable'}`
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
