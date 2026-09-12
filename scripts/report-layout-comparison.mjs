// Render compact, reviewable evidence. Raw samples and generated drafts stay ignored.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { evaluateLayoutPerformance } from './layout-adoption.mjs';
import { additionalSchedule, legacySchedule } from './layout-measurement-support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
if (process.argv.length !== 3) throw new Error('Usage: report-layout-comparison.mjs SUMMARY_DIRECTORY');
const directory = resolve(process.argv[2]);
const read = name => JSON.parse(readFileSync(resolve(directory, `${name}-summary.json`)));
const manifest = JSON.parse(readFileSync('benchmarks/local-relation/columnar-experiment.json'));
const modes = ['additional', 'legacy', 'prepared', 'prepared-legacy'];
const inputs = Object.fromEntries(modes.map(mode => [mode, read(mode)]));
const decision = evaluateLayoutPerformance(manifest, inputs.additional, inputs.legacy);
const trafficBytes = readFileSync(resolve(directory, 'traffic-samples.json'));
const traffic = JSON.parse(trafficBytes);
const hash = data => createHash('sha256').update(data).digest('hex');
if (traffic.status !== 'complete' || !/^[a-f0-9]{40}$/.test(traffic.source_commit) ||
    traffic.manifest_sha256 !== inputs.additional.manifest_sha256 ||
    traffic.compiler !== inputs.additional.compiler || traffic.build !== 'release' ||
    traffic.targets?.map(t => t.target).join() !== 'native,js,wasm') throw new Error('Invalid traffic provenance');
if (hash(execFileSync('git', ['show', `${traffic.source_commit}:scripts/measure-layout-traffic.mjs`])) !== traffic.script_sha256) {
  throw new Error('Traffic runner does not match its recorded source');
}
const trafficFields = ['data_arrays', 'validity_arrays', 'validity_capacity', 'column_cell_transfers',
  'selection_arrays', 'selection_index_copies', 'row_cell_transfers', 'row_reference_copies'];
const trafficNative = new Map();
let trafficCount = 0;
for (const target of traffic.targets) {
  if (!/^[a-f0-9]{64}$/.test(target.artifact_sha256)) throw new Error('Missing traffic binary identity');
  const expected = [['additional', additionalSchedule], ['legacy', legacySchedule]].flatMap(([family, schedule]) =>
    schedule(manifest, target.target, false).filter(x => x.repeat === 0).map(x => ({ family, ...x })));
  if (target.samples.length !== expected.length) throw new Error('Incomplete traffic matrix');
  for (let i = 0; i < expected.length; i++) {
    const sample = target.samples[i], e = expected[i];
    if (sample.kind !== 'layout-traffic' || ['family', 'case_index', 'candidate', 'rows', 'columns', 'same_keys'].some(k => sample[k] !== e[k]) ||
        trafficFields.some(k => !Number.isSafeInteger(sample[k]) || sample[k] < 0)) throw new Error('Invalid traffic sample');
    const key = `${sample.family}/${sample.case_index}/${sample.candidate}`;
    if (target.target === 'native') trafficNative.set(key, sample);
    else if (trafficFields.some(k => trafficNative.get(key)?.[k] !== sample[k])) throw new Error('Cross-target traffic disagreement');
    trafficCount++;
  }
}
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
lines.push('## Recorded capacity counters', '',
  'Native counters are shown once; all corresponding repeats and JS/Wasm cases must agree exactly. Store entries and owned capacity have different scopes and must not be added as bytes. A dash means uninstrumented, not zero. Additional cases captured peak owned capacity, not owned live capacity at observation.', '',
  '| Family/case | Layout | Store live entries | Store peak entries | Owned live slots | Owned peak slots | Typed live bytes | Typed peak bytes |',
  '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
const capacityFields = ['retained_slots', 'peak_retained_slots', 'owned_buffer_slots',
  'peak_owned_buffer_slots', 'owned_typed_bytes', 'peak_owned_typed_bytes'];
for (const [mode, file] of [['additional', 'additional-samples.json'], ['legacy', 'legacy-disposal-samples.json']]) {
  const bytes = readFileSync(resolve(directory, file));
  if (hash(bytes) !== inputs[mode].report_sha256) throw new Error('Capacity report differs from audited timing report');
  const raw = JSON.parse(bytes);
  for (const sample of raw.targets[0].samples.filter(s => s.repeat === 0)) {
    for (const target of raw.targets) {
      for (const other of target.samples.filter(s => s.case_index === sample.case_index && s.candidate === sample.candidate)) {
        if (capacityFields.some(k => (other[k] ?? null) !== (sample[k] ?? null))) throw new Error('Capacity counters differ across repeats/targets');
      }
    }
    const name = sample.case_id ?? `${sample.rows}x${sample.columns}-${sample.same_keys ? 'equal' : 'different'}`;
    const values = capacityFields.map(k => {
      if (sample[k] == null) return '—';
      if (!Number.isSafeInteger(sample[k]) || sample[k] < 0) throw new Error('Invalid capacity counter');
      return sample[k];
    });
    lines.push(`| ${mode}/${name} | ${sample.candidate} | ${values.join(' | ')} |`);
  }
}
lines.push('');
const out = resolve('_build/layout-measurements/comparison-report.md');
lines.push('## Data-container construction diagnostics', '',
  `All ${trafficCount} fixed target/case/candidate diagnostics passed independent output assertions. JS/Wasm counters agree exactly with their native counterparts; the native matrix is shown once below.`,
  `Diagnostic source: ${traffic.source_commit}. Report SHA-256: ${hash(trafficBytes)}.`,
  'These are source-level data-array constructions and transfers, not malloc calls or a complete scratch/heap profile. Metadata, scalar temporaries, runtime headers and failed-prefix traffic are excluded. Frozen timings above were collected separately with diagnostic counters disabled.',
  'Cells include NULL adoption and derived output placement, not deep payload copies. Row-reference and selection-index copies are separate units. Validity capacity is bytes in the nominal storage model, not asserted JS heap bytes. See physical-accounting.md for budget and ownership boundaries.', '',
  '| Family/case | Layout | Data arrays | NULL arrays | NULL capacity | Column cell transfers | Selection arrays | Index copies | Row cell transfers | Row refs |',
  '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
for (const sample of trafficNative.values()) {
  const name = sample.family === 'additional' ? manifest.additional_cases[sample.case_index].id
    : `${sample.rows}x${sample.columns}-${sample.same_keys ? 'equal' : 'different'}`;
  lines.push(`| ${sample.family}/${name} | ${sample.candidate} | ${trafficFields.map(k => sample[k]).join(' | ')} |`);
}
lines.push('');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, lines.join('\n').trimEnd() + '\n');
console.log(out);
