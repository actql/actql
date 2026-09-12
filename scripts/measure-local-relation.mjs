// Build the native sequence_scale_wbtest suite before invoking this script.
// Measurements include process startup, checker/lowering, input decoding and
// admission, execution, and independent assertions. They are not kernel-only
// timings or a claim that logical budgets bound the process RSS.
import { spawnSync, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { platform, arch, cpus, release } from 'node:os';
import { performance } from 'node:perf_hooks';

const executable = resolve(process.argv[2] ?? '_build/native/debug/test/execution_relation/execution_relation.whitebox_test.exe');
if (!['darwin', 'linux'].includes(platform())) throw new Error('RSS measurement requires macOS or GNU time on Linux');
const repetitions = 3;
const cases = [];
for (const rows of [100, 1000, 10000]) {
  for (const columns of [2, 64]) {
    for (const same of [true, false]) cases.push({ rows, columns, keys: same ? 'all-equal' : 'all-different' });
  }
}
const measurements = [];
for (const [index, shape] of cases.entries()) {
  const samples = [];
  for (let repeat = 0; repeat < repetitions; repeat++) {
    const started = performance.now();
    const run = spawnSync('/usr/bin/time', [platform() === 'darwin' ? '-l' : '-v', executable, `sequence_scale_wbtest.mbt:${index}-${index + 1}`], {
      encoding: 'utf8', timeout: 60000, maxBuffer: 4 * 1024 * 1024,
    });
    const elapsedMs = performance.now() - started;
    if (run.error || run.status !== 0) throw new Error(`case ${index}: ${run.error ?? run.stderr}`);
    const events = run.stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
    const result = events.filter(event => event.type === 'result');
    if (result.length !== 1 || result[0].file !== 'sequence_scale_wbtest.mbt' || result[0].index !== index || result[0].message !== '') {
      throw new Error(`case ${index} did not independently pass: ${run.stdout}`);
    }
    const match = platform() === 'darwin'
      ? run.stderr.match(/(\d+)\s+maximum resident set size/)
      : run.stderr.match(/Maximum resident set size \(kbytes\):\s*(\d+)/);
    if (!match) throw new Error(`Missing RSS for case ${index}: ${run.stderr}`);
    samples.push({ elapsed_ms: elapsedMs, peak_rss_bytes: Number(match[1]) * (platform() === 'linux' ? 1024 : 1) });
  }
  measurements.push({ ...shape, samples });
}
console.log(JSON.stringify({
  format: 'local-relation-measurement/0.1',
  source_commit: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  working_tree_status: execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim(),
  executable,
  executable_sha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
  test_source_sha256: createHash('sha256').update(readFileSync('src/execution_relation/sequence_scale_wbtest.mbt')).digest('hex'),
  host: { platform: platform(), release: release(), arch: arch(), cpu: cpus()[0]?.model },
  scope: 'fresh process: startup + fixture/check/lower + input capture + sequence execution + assertions; excludes compilation',
  repetitions, measurements,
}, null, 2));
