// Audit one completed measurement subset; never authorize a product migration.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { additionalSchedule, legacySchedule } from './layout-measurement-support.mjs';
import { pairedSummary, bootstrapMethod } from './layout-statistics.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const [mode, path, outputPath] = process.argv.slice(2);
if (![4, 5].includes(process.argv.length) || !['additional', 'legacy', 'prepared', 'prepared-legacy'].includes(mode)) {
  throw new Error('Usage: summarize-layout-report.mjs additional|legacy|prepared|prepared-legacy REPORT.json [SUMMARY.json under _build]');
}
const prepared = mode.startsWith('prepared');
const additional = mode === 'additional' || mode === 'prepared';
const bytes = readFileSync(path);
const report = JSON.parse(bytes);
const hash = input => createHash('sha256').update(input).digest('hex');
const manifestBytes = readFileSync('benchmarks/local-relation/columnar-experiment.json');
const manifest = JSON.parse(manifestBytes);
if (report.status !== 'complete' || report.measured_repetitions !== 7 || report.warmups !== 1 ||
    report.manifest_sha256 !== hash(manifestBytes) || report.working_tree_status !== '' ||
    !/^[a-f0-9]{40}$/.test(report.source_commit) ||
    !/^[a-f0-9]{64}$/.test(report.source_tree_sha256) ||
    !Array.isArray(report.targets) || report.targets.map(t => t.target).join() !== 'native,js,wasm') {
  throw new Error('Incomplete, unpaired, dirty or incompatible measurement provenance');
}
// Verify the complete recorded source tree against its own commit, not HEAD.
// This also permits later benchmark-only work without relabeling old binaries.
const paths = ['src', 'scripts', 'spec', 'vendor', 'moon.mod', 'moon.mod.json',
  'moon.lock', 'toolchain.json', 'benchmarks/local-relation/columnar-experiment.json'];
const git = (args, options = {}) => execFileSync('git', args, options);
const files = git(['ls-tree', '-r', '--name-only', report.source_commit, '--', ...paths],
  { encoding: 'utf8' }).trim().split('\n').sort();
const blobs = git(['cat-file', '--batch'], {
  input: files.map(file => `${report.source_commit}:${file}`).join('\n') + '\n',
  maxBuffer: 100 * 1024 * 1024,
});
const tree = createHash('sha256');
let offset = 0;
for (const file of files) {
  const end = blobs.indexOf(10, offset);
  const header = blobs.subarray(offset, end).toString().split(' ');
  const size = Number(header[2]);
  if (header[1] !== 'blob' || !Number.isSafeInteger(size) || size < 0) throw new Error(`Invalid source blob ${file}`);
  tree.update(file + '\0').update(blobs.subarray(end + 1, end + 1 + size));
  offset = end + 1 + size + 1;
}
if (tree.digest('hex') !== report.source_tree_sha256 ||
    hash(git(['show', `${report.source_commit}:scripts/measure-layouts.mjs`])) !== report.script_sha256) {
  throw new Error('Recorded source or measurement runner does not match its commit');
}
const summaries = [];
for (const target of report.targets) {
  if (!/^[a-f0-9]{64}$/.test(target.artifact_sha256)) throw new Error('Missing executable identity');
  const schedule = (additional ? additionalSchedule : legacySchedule)(manifest, target.target, false);
  if (!Array.isArray(target.samples) || target.samples.length !== schedule.length) throw new Error('Missing samples');
  for (const [index, expected] of schedule.entries()) {
    const sample = target.samples[index];
    for (const key of ['case_id', 'case_index', 'candidate', 'repeat', 'rows', 'columns']) {
      if (sample[key] !== expected[key]) throw new Error(`Wrong pair/order/shape: ${target.target}/${index}/${key}`);
    }
    // The first prepared additional report omitted this redundant false field;
    // never permit omission for legacy all-equal/all-different fixtures.
    if (!(prepared && additional && sample.same_keys === undefined) && sample.same_keys !== expected.same_keys) {
      throw new Error('Mismatched same-key fixture');
    }
    if (![sample.process_wall_ms, sample.peak_rss_bytes].every(n => Number.isFinite(n) && n > 0) ||
        !Number.isSafeInteger(sample.peak_rss_bytes)) throw new Error('Invalid process measurement');
    if (prepared) {
      if (sample.kind !== 'prepared-layout-sample' || sample.reused_input !== true || sample.fresh_budgets !== true ||
          ![sample.operation_us, sample.warmup_operation_us].every(n => Number.isFinite(n) && n > 0) ||
          'end_to_end_us' in sample || 'phases_us' in sample) throw new Error('Invalid prepared-only scope');
    } else if (sample.kind !== 'layout-sample' || sample.disposal_included !== true ||
        !Number.isFinite(sample.end_to_end_us) || sample.end_to_end_us <= 0 ||
        !Array.isArray(sample.phases_us) || sample.phases_us.length !== 5 ||
        sample.phases_us.some(n => !Number.isFinite(n) || n < 0) ||
        sample.phases_us.reduce((a, b) => a + b, 0) > sample.end_to_end_us + 1) {
      throw new Error('Invalid five-phase enclosing disposal scope');
    }
  }
  for (const index of new Set(schedule.map(s => s.case_index))) {
    const byCandidate = Object.fromEntries(['A', 'B', 'C'].map(candidate =>
      [candidate, target.samples.filter(s => s.case_index === index && s.candidate === candidate)]));
    const first = byCandidate.A[0];
    const metrics = prepared ? ['operation_us', 'peak_rss_bytes'] : ['end_to_end_us', 'peak_rss_bytes'];
    for (const candidate of ['B', 'C']) {
      const metricsSummary = Object.fromEntries(metrics.map(metric => [metric,
        pairedSummary(byCandidate.A.map(s => s[metric]), byCandidate[candidate].map(s => s[metric]))]));
      const phases = prepared ? undefined : Object.fromEntries(['A', candidate].map(c => [c,
        Array.from({ length: 5 }, (_, phase) => {
          const values = byCandidate[c].map(s => s.phases_us[phase]).sort((a, b) => a - b);
          return { median_us: values[3], min_us: values[0], max_us: values[6] };
        })]));
      summaries.push({ target: target.target, case_index: index, case_id: first.case_id,
        rows: first.rows, columns: first.columns, same_keys: first.same_keys ?? false,
        candidate, metrics: metricsSummary, phases });
    }
  }
}
const summary = {
  scope: mode, adoption_eligible: false,
  limitation: 'One subset only; prepared operation time/RSS cannot replace enclosing E2E evidence. Apply full semantic, physical and mandatory-matrix checks separately.',
  report_sha256: hash(bytes), source_commit: report.source_commit,
  source_tree_sha256: report.source_tree_sha256, source_files_verified: files.length,
  manifest_sha256: report.manifest_sha256, host: report.host, compiler: report.compiler,
  method: bootstrapMethod, summaries,
};
const destination = outputPath ?? `_build/layout-measurements/${mode}-summary.json`;
if (!resolve(destination).startsWith(resolve('_build') + sep)) throw new Error('Summaries must remain under ignored _build');
mkdirSync(dirname(resolve(destination)), { recursive: true });
writeFileSync(destination, JSON.stringify(summary, null, 2) + '\n');
console.log(`Validated ${report.targets.reduce((n, t) => n + t.samples.length, 0)} samples; summary: ${destination}; not an adoption gate.`);
