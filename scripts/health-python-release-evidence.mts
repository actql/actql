import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {constants} from 'node:fs';
import {open} from 'node:fs/promises';
import {basename, dirname, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {digest} from './health-monitor-report.mjs';
import {bindPythonOrdinaryLatency} from './python-release-latency-policy.mjs';

import type {HealthReport} from './health-monitor-report.mjs';

const verifier = fileURLToPath(new URL('./python_release_cohort.py', import.meta.url));
const sha256 = /^[a-f0-9]{64}$/u;
type VerifiedCohort = {manifest_sha256: string; cohort: {
  platform: string; package_version: string;
  wheels: {distribution: string; file: string; bytes: number; sha256: string}[];
}};

async function originalEvidence(path: unknown, sha: unknown, maximum: number) {
  assert(typeof path === 'string' && isAbsolute(path), 'Expected an original Python Health evidence path');
  assert(typeof sha === 'string' && sha256.test(sha), 'Expected an original Python Health evidence digest');
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = await file.stat(), {size} = info;
    assert(info.isFile() && size > 0 && size <= maximum, 'Invalid Python Health evidence size');
    const bytes = Buffer.alloc(size);
    for (let offset = 0; offset < size;) {
      const {bytesRead} = await file.read(bytes, offset, size - offset, offset);
      assert(bytesRead > 0, 'Python Health evidence ended before its recorded size');
      offset += bytesRead;
    }
    assert.equal((await file.stat()).size, size, 'Python Health evidence size changed');
    assert.equal(digest(bytes), sha, 'Changed original Python Health evidence');
    return bytes;
  } finally {await file.close();}
}

// A saved report can point to originals. The report's version and profile
// fields cannot select a latency policy by themselves.
export async function verifiedPythonReleaseMetrics(report: HealthReport, python: string) {
  const selected = new Set<string>();
  if (report.mode !== 'release') return selected;
  const wheels = (report.artifacts ?? []).filter(row => row.artifactKind === 'wheel');
  const original = report.pythonReleaseCohort;
  if (original === undefined) {
    assert(!wheels.some(row => row.version === '0.0.3'), 'Missing original Python Health cohort for v0.0.3');
    return selected;
  }
  const manifest = await originalEvidence(original.path, original.sha256, 1024 * 1024);
  assert.equal(basename(original.path), 'cohort.json', 'Expected the ordinary Python cohort filename');
  const source = report.source?.sha;
  assert(typeof source === 'string' && /^[a-f0-9]{40}$/u.test(source), 'Missing original Python Health source');
  const output = JSON.parse(execFileSync(python, ['-E', '-s', '-B', verifier,
    '--verify-directory', dirname(original.path), '--source', source, '--version', '0.0.3'],
  {encoding: 'utf8', timeout: 60_000, maxBuffer: 2 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
    env: {...process.env, PATH: `${dirname(process.execPath)}:${process.env.PATH ?? ''}`}})) as VerifiedCohort;
  assert.equal(output.manifest_sha256, original.sha256, 'Changed verified Python Health cohort');
  const cohort = output.cohort;
  const expectedPlatform = `${report.environment?.platform}-${report.environment?.architecture}`;
  assert.equal(cohort.platform, expectedPlatform, 'Foreign Python Health cohort platform');
  assert.deepEqual(wheels.map(row => ({distribution: row.name, file: row.file, bytes: row.acquisitionBytes, sha256: row.sha256,
    version: row.version, sourceSha: row.sourceSha})).sort((a, b) => a.distribution.localeCompare(b.distribution)),
  cohort.wheels.map(row => ({...row, version: cohort.package_version, sourceSha: source}))
    .sort((a, b) => a.distribution.localeCompare(b.distribution)),
  'Saved Python Health wheel identities differ from the verified cohort');
  for (const metric of report.metrics.filter(row => row.target === 'python' && row.kind === 'latency')) {
    if (metric.evidenceSha256 === undefined) {
      assert(metric.status && metric.status !== 'pass', 'Missing original Python Health measurements');
      continue;
    }
    const bytes = await originalEvidence(metric.evidence, metric.evidenceSha256, 16 * 1024 * 1024);
    const raw = JSON.parse(bytes.toString('utf8'));
    assert(bindPythonOrdinaryLatency(raw, {adapter: 'python', manifestFile: 'cohort.json',
      sourceSha: source, manifestSha256: original.sha256}, manifest, metric.id));
    assert.equal(raw.environment?.python, report.environment?.pythonRuntime?.version, 'Foreign Python Health interpreter version');
    assert.equal(raw.environment?.pythonExecutableSha256, report.environment?.pythonRuntime?.executableSha256,
      'Foreign Python Health interpreter executable');
    const [series] = raw.latency;
    assert.equal(series.mode, 'final', 'Expected final ordinary Python Health measurements');
    assert.equal(series.profiled, false, 'Expected uninstrumented Python Health measurements');
    assert.equal(series.fixtureSha256, metric.fixtureSha256, 'Foreign Python Health workload');
    assert.deepEqual(series.samples, metric.samples, 'Saved Python Health samples differ from their original measurements');
    if (metric.status === undefined || metric.status === 'pass') {
      assert(!raw.firstFailure && !raw.packageFailure && raw.cleanup?.closed === true && raw.installedPayloadsUnchanged === true,
        'Original Python Health measurements did not complete with unchanged installed payloads');
    }
    selected.add(metric.id);
  }
  return selected;
}
