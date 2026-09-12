// Render compact, reviewable evidence. Raw samples and generated drafts stay ignored.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { evaluateLayoutPerformance } from './layout-adoption.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
if (process.argv.length !== 3) throw new Error('Usage: report-layout-comparison.mjs SUMMARY_DIRECTORY');
const directory = resolve(process.argv[2]);
const read = name => JSON.parse(readFileSync(resolve(directory, `${name}-summary.json`)));
const manifest = JSON.parse(readFileSync('benchmarks/local-relation/columnar-experiment.json'));
const modes = ['additional', 'legacy', 'prepared', 'prepared-legacy'];
const inputs = Object.fromEntries(modes.map(mode => [mode, read(mode)]));
const decision = evaluateLayoutPerformance(manifest, inputs.additional, inputs.legacy);
for (const [preparedMode, e2eMode] of [['prepared', 'additional'], ['prepared-legacy', 'legacy']]) {
  const p = inputs[preparedMode], e = inputs[e2eMode];
  if (p.scope !== preparedMode || p.manifest_sha256 !== e.manifest_sha256 ||
      JSON.stringify(p.host) !== JSON.stringify(e.host) || p.compiler !== e.compiler) {
    throw new Error('Prepared evidence differs from the E2E matrix');
  }
  const key = item => `${item.target}/${item.case_index}/${item.candidate}`;
  const expected = new Set(e.summaries.map(key));
  for (const item of p.summaries) {
    if (!expected.delete(key(item)) || !item.metrics.operation_us || item.metrics.operation_us.pairs !== 7) {
      throw new Error('Invalid prepared coverage');
    }
  }
  if (expected.size) throw new Error('Missing prepared cases');
}
const lines = ['# Local Relation layout comparison', '',
  '## Performance decision', '',
  ...decision.map(d => `- ${d.candidate}: **${d.performance_gate}**. ${d.reasons.join('; ')}. Regressions: ${d.regressions.length}.`),
  '', 'This is the fixed performance gate, not permission to migrate. Product execution remains rows. No new operation, Host, Arrow or SIMD implementation is implied.', '',
  '## Measurement conditions', '',
  `Host: ${JSON.stringify(inputs.additional.host)}. Compiler: ${inputs.additional.compiler}.`,
  'Release builds; seven paired repeats per case, A/B/C alternating with C/B/A. One warmup and a fresh runtime process per sample. Ratios are medians of paired candidate/A ratios, not ratios of independent medians.',
  'The interval is a deterministic paired-bootstrap 95% interval (10,000 resamples). A directional result additionally requires at least six of seven pairs in that direction.',
  'E2E includes input preparation, import, evaluation, observation and owner disposal. Prepared time measures operation execution with reused imported buffers and fresh budgets; it is not E2E.',
  'RSS is the peak of the entire fresh process, including warmup. It is not an operation-specific allocation measurement.', '',
  '## Provenance', '', '| Subset | Source commit | Raw report SHA-256 |', '| --- | --- | --- |',
  ...modes.map(mode => `| ${mode} | ${inputs[mode].source_commit} | ${inputs[mode].report_sha256} |`), '',
  `Manifest SHA-256: ${inputs.additional.manifest_sha256}. Raw reports retain binary/runtime identities and every sample. Historical pre-disposal measurements are not used.`, '',
  '## All fixed comparisons', '',
  'Ratios below one favor the candidate. CI is the paired 95% interval. A and candidate absolute times are separate medians in microseconds. RSS is shown as candidate/A ratio. “Win”/“regression” mean reproducible direction, not necessarily a 20% change.', '',
];
const n = x => Number(x.toFixed(3));
const state = m => m.reproducibleRegression ? 'regression' : m.reproducibleImprovement ? 'win' : 'mixed';
for (const mode of modes) {
  const prepared = mode.startsWith('prepared');
  lines.push(`### ${mode}`, '', '| Target | Case | Candidate | A µs | Candidate µs | Ratio [CI] | Direction | RSS ratio |', '| --- | --- | --- | ---: | ---: | --- | --- | ---: |');
  for (const item of inputs[mode].summaries) {
    const m = item.metrics[prepared ? 'operation_us' : 'end_to_end_us'];
    const name = item.case_id ?? `${item.rows}x${item.columns}-${item.same_keys ? 'equal' : 'different'}`;
    lines.push(`| ${item.target} | ${name} | ${item.candidate} | ${n(m.baselineMedian)} | ${n(m.candidateMedian)} | ${n(m.medianRatio)} [${n(m.lower95)}, ${n(m.upper95)}] | ${state(m)} | ${n(item.metrics.peak_rss_bytes.medianRatio)} |`);
  }
  lines.push('');
}
lines.push('## Five-phase detail', '', 'Each cell is median [min, max] microseconds. Phase sums need not equal enclosing E2E: disposal and between-phase work are included only by the enclosing clock.', '');
for (const mode of ['additional', 'legacy']) {
  lines.push(`### ${mode}`, '', '| Target | Case | Layout | Fixture | Prepare | Import | Execute | Observe |', '| --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const item of inputs[mode].summaries) {
    const name = item.case_id ?? `${item.rows}x${item.columns}-${item.same_keys ? 'equal' : 'different'}`;
    for (const layout of item.candidate === 'B' ? ['A', 'B'] : ['C']) {
      lines.push(`| ${item.target} | ${name} | ${layout} | ${item.phases[layout].map(p => `${n(p.median_us)} [${n(p.min_us)}, ${n(p.max_us)}]`).join(' | ')} |`);
    }
  }
  lines.push('');
}
const out = resolve('_build/layout-measurements/comparison-report.md');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, lines.join('\n') + '\n');
console.log(out);
