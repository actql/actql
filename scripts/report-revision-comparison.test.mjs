import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { auditRevisionReport, renderRevisionReport } from './report-revision-comparison.mjs';
import { revisionCells, supplementalRevisionCells, revisionPairs, regressionMetric } from './revision-regression-support.mjs';

const manifest = JSON.parse(readFileSync(new URL('../benchmarks/local-relation/columnar-experiment.json', import.meta.url)));
function fixture() {
  const raw = new Map();
  const report = {
    status: 'complete', matrix_gate: 'within_tolerance', host: { platform: 'darwin' },
    sources: { baseline: { commit: 'before' }, candidate: { commit: 'after' } },
    samples: [], decisions: [],
  };
  const metrics = ['time', 'rss'].map(m => regressionMetric(Array(7).fill(100), Array(7).fill(100), m));
  for (const cell of [...revisionCells(manifest), ...supplementalRevisionCells()]) {
    report.decisions.push({ id: cell.id, screening: metrics, metrics });
    for (const expected of revisionPairs(cell)) {
      const measurement = {
        kind: cell.mode === 'prepared' ? 'prepared-layout-sample' : 'layout-sample',
        candidate: 'A', rows: cell.rows, columns: cell.columns,
        same_keys: cell.same_keys, ...(cell.case_id ? { case_id: cell.case_id } : {}),
        ...(cell.mode === 'prepared'
          ? { reused_input: true, fresh_budgets: true, operation_us: 100, warmup_operation_us: 100 }
          : { disposal_included: true, phases_us: [10, 10, 10, 10, 10], end_to_end_us: 100 }),
      };
      const name = `${report.samples.length}-${expected.revision}-${cell.target}`;
      raw.set(name + '.stdout', JSON.stringify(measurement) + '\n' + JSON.stringify({
        type: 'result', file: 'sequence_profile_wbtest.mbt', index: 0, message: '',
      }));
      raw.set(name + '.stderr', '100 maximum resident set size\n');
      report.samples.push({ ...expected, raw: name, measurement, peak_rss_bytes: 100, process_wall_ms: 1 });
    }
  }
  return { report, raw, read: path => { assert.ok(raw.has(path)); return raw.get(path); } };
}

test('full matrix is independently reconstructed from successful raw assertions', () => {
  const f = fixture();
  const decisions = auditRevisionReport(f.report, manifest, f.read);
  assert.equal(decisions.length, 136);
  assert.equal(f.report.samples.length, 1904);
  assert.match(renderRevisionReport(f.report, decisions), /1904 measured processes/);
});

test('partial and smoke reports cannot become regression evidence', () => {
  for (const edit of [r => { r.status = 'running'; }, r => { r.status = 'stopped'; }, r => { r.matrix_gate = 'not_evaluated'; },
    r => { r.decisions.pop(); }]) {
    const f = fixture(); edit(f.report);
    assert.throws(() => auditRevisionReport(f.report, manifest, f.read));
  }
});

test('missing raw success, RSS tampering and changed stored timing are rejected', () => {
  for (const edit of [
    f => f.raw.set(f.report.samples[0].raw + '.stdout', JSON.stringify(f.report.samples[0].measurement)),
    f => { f.report.samples[0].peak_rss_bytes++; },
    f => { f.report.samples[0].measurement.end_to_end_us++; },
    f => { f.report.samples[0].raw = '../outside'; },
    f => { f.report.samples[0].revision = 'candidate'; },
  ]) {
    const f = fixture(); edit(f);
    assert.throws(() => auditRevisionReport(f.report, manifest, f.read));
  }
});
