import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

type Input = Record<string, unknown>;
function object(value: unknown): Input {
  assert(value && typeof value === 'object' && !Array.isArray(value), 'Expected an ordinary Python evidence record');
  return value as Input;
}

export const pythonReleaseLatencyProfile = 'python-v0.0.3-public';
export function pythonReleaseLatencyApplies(packageVersion: unknown) {
  return packageVersion === '0.0.3';
}

type Limits = Readonly<{p95Ms: number; maxMs: number}>;

const retainedOperation = Object.freeze({p95Ms: 500, maxMs: 1000});
const warmOperation = Object.freeze({p95Ms: 1000, maxMs: 2000});
const reopenedProcess = Object.freeze({p95Ms: 2000, maxMs: 4000});
const initializedProcess = Object.freeze({p95Ms: 5000, maxMs: 8000});

export function pythonReleaseLatencyLimits(operation: string): Limits {
  if (operation === 'warm-result' || operation === 'warm-status') return retainedOperation;
  if (operation === 'cold-existing') return reopenedProcess;
  if (operation === 'first-init') return initializedProcess;
  assert(operation.startsWith('warm-'), 'Unsupported ordinary Python public operation');
  return warmOperation;
}

export function bindPythonOrdinaryLatency(reportValue: unknown, sourceValue: unknown, originalCohort: Buffer, operation: string) {
  const report = object(reportValue), source = object(sourceValue);
  const manifest = object(JSON.parse(originalCohort.toString('utf8')) as unknown);
  const cohortSha256 = createHash('sha256').update(originalCohort).digest('hex');
  assert.equal(source.adapter, 'python', 'Expected the selected ordinary Python artifact');
  assert.equal(source.manifestFile, 'cohort.json', 'Expected the original Python cohort file');
  assert.equal(source.manifestSha256, cohortSha256, 'Foreign ordinary Python cohort bytes');
  assert.equal(report.cohortSha256, cohortSha256, 'Foreign ordinary Python report cohort');
  assert.equal(manifest.source_sha, source.sourceSha, 'Foreign ordinary Python cohort source');
  assert.equal(report.sourceSha, source.sourceSha, 'Foreign ordinary Python report source');
  assert(typeof manifest.package_version === 'string' && /^[A-Za-z0-9.+!-]+$/u.test(manifest.package_version),
    'Expected the version of the originally selected wheel');
  assert.equal(report.executionPath, 'python-sdk', 'Expected ordinary Python SDK evidence');
  const protocol = object(report.protocol);
  assert.equal(protocol.adapter, 'python', 'Expected ordinary Python measurement protocol');
  assert(Array.isArray(report.latency) && report.latency.length === 1, 'Expected one Python operation report');
  const series = object(report.latency[0]);
  assert.equal(protocol.operation, operation, 'Foreign ordinary Python operation protocol');
  assert.equal(series.operation, operation, 'Foreign ordinary Python operation');
  assert(typeof series.operation === 'string' && Array.isArray(series.samples), 'Expected original Python samples');
  if (series.operation === 'cold-existing' || series.operation === 'first-init') {
    for (const value of series.samples) {
      const sample = object(value);
      if (sample.verified === true && sample.completed === true && sample.publicTiming !== undefined) {
        assert.equal(object(sample.publicTiming).kind, 'process-result-close', 'Expected Python Result and first-close clocks');
      }
    }
  }
  if (!pythonReleaseLatencyApplies(manifest.package_version)) return;
  return {profile: pythonReleaseLatencyProfile, packageVersion: manifest.package_version, sourceSha: source.sourceSha,
    cohortSha256};
}
