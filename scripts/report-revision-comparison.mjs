// Revalidate complete paired measurements against raw assertions before reporting.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkedSample, checkedPreparedSample, peakRssBytes } from './layout-measurement-support.mjs';
import { revisionCells, supplementalRevisionCells, revisionPairs, regressionMetric, revisionGate } from './revision-regression-support.mjs';

export function auditRevisionReport(report, manifest, readRaw) {
  assert.equal(report.status, 'complete', 'A partial run is not a completed comparison');
  assert.notEqual(report.matrix_gate, 'not_evaluated', 'Smoke is not regression evidence');
  const cells = [...revisionCells(manifest), ...supplementalRevisionCells()];
  assert.equal(report.decisions.length, cells.length, 'Full required case matrix');
  const recomputed = [];
  let offset = 0;
  for (const [i, cell] of cells.entries()) {
    const decision = report.decisions[i];
    assert.equal(decision.id, cell.id);
    const samples = report.samples.filter(s => s.id === cell.id);
    assert.ok([14, 42].includes(samples.length), 'Exactly 7 or 21 complete pairs');
    const pairs = samples.length / 2;
    const order = revisionPairs(cell, 0, pairs);
    for (const [j, expected] of order.entries()) {
      const sample = samples[j];
      assert.equal(report.samples[offset++], sample, 'Recorded execution order must remain paired');
      for (const [key, value] of Object.entries(expected)) assert.deepEqual(sample[key], value, `Wrong ${key}`);
      assert.match(sample.raw, /^\d+-(baseline|candidate)-(native|js|wasm)$/);
      const measurement = (cell.mode === 'prepared' ? checkedPreparedSample : checkedSample)(readRaw(sample.raw + '.stdout'), expected);
      assert.deepEqual(sample.measurement, measurement, 'Stored values match independently successful raw output');
      assert.equal(sample.peak_rss_bytes, peakRssBytes(readRaw(sample.raw + '.stderr'), report.host.platform));
      assert.ok(Number.isFinite(sample.process_wall_ms) && sample.process_wall_ms > 0);
    }
    const summarize = n => ['time', 'rss'].map(metric => {
      const values = revision => samples.filter(s => s.revision === revision).slice(0, n)
        .map(s => metric === 'rss' ? s.peak_rss_bytes : cell.mode === 'prepared' ? s.measurement.operation_us : s.measurement.end_to_end_us);
      return regressionMetric(values('baseline'), values('candidate'), metric);
    });
    const screening = summarize(7);
    assert.equal(pairs, screening.some(m => m.decision === 'extend') ? 21 : 7, 'No discretionary repeat selection');
    const metrics = pairs === 7 ? screening : summarize(21);
    assert.deepEqual(decision, { id: cell.id, screening, metrics });
    recomputed.push(decision);
  }
  assert.equal(offset, report.samples.length, 'No hidden extra samples');
  assert.equal(report.matrix_gate, revisionGate(recomputed));
  return recomputed;
}

export function renderRevisionReport(report, decisions) {
  const lines = ['# Row execution revision comparison', '',
    `Baseline: ${report.sources.baseline.commit}. Candidate: ${report.sources.candidate.commit}.`, '',
    `Gate: **${report.matrix_gate}**. ${report.samples.length} measured processes; ${decisions.length} case/mode/target cells.`, '',
    'Time is microseconds (E2E or prepared operation as labelled). RSS is whole-process peak bytes; build is excluded. Intervals are descriptive paired-bootstrap ratio intervals, not family-wise guarantees.', '',
    '| Case / target / mode | Metric | Pairs | Before median | After median | Absolute difference | Paired ratio | 95% ratio interval | Decision |',
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |'];
  for (const d of decisions) for (const m of d.metrics) {
    lines.push(`| ${d.id} | ${m.metric} | ${m.pairs} | ${m.baselineMedian.toFixed(3)} | ${m.candidateMedian.toFixed(3)} | ${m.absoluteMedianDifference.toFixed(3)} | ${m.medianRatio.toFixed(4)} | ${m.lower95.toFixed(4)}–${m.upper95.toFixed(4)} | ${m.decision} |`);
  }
  lines.push('', 'Seven-pair screening results remain in the raw report. A regression seen then is not erased by a later extension for another metric. No column-adoption or completion-boundary conformance claim follows from timing evidence.', '');
  return lines.join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3) throw new Error('Usage: report-revision-comparison.mjs REPORT_JSON');
  const path = resolve(process.argv[2]);
  const report = JSON.parse(readFileSync(path));
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const manifest = JSON.parse(readFileSync(resolve(root, 'benchmarks/local-relation/columnar-experiment.json')));
  const decisions = auditRevisionReport(report, manifest, f => readFileSync(resolve(dirname(path), f), 'utf8'));
  process.stdout.write(renderRevisionReport(report, decisions));
}
