import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { evaluateLayoutPerformance } from './layout-adoption.mjs';

const manifest = JSON.parse(readFileSync(new URL('../benchmarks/local-relation/columnar-experiment.json', import.meta.url)));
const metric = () => ({ pairs: 7, medianRatio: 1, lower95: 0.99, upper95: 1.01,
  reproducibleImprovement: false, reproducibleRegression: false });
function fixture() {
  const summary = scope => ({ scope, manifest_sha256: 'same', host: { cpu: 'test' },
    compiler: 'test', summaries: ['native', 'js', 'wasm'].flatMap(target => {
      const indices = scope === 'additional' ? manifest.additional_cases.map((_, i) => i)
        : target === 'native' ? Array.from({ length: 12 }, (_, i) => i) : [1, 3, 9, 11];
      return indices.flatMap(case_index => ['B', 'C'].map(candidate => ({
        target, case_index, candidate,
        case_id: scope === 'additional' ? manifest.additional_cases[case_index].id : `legacy-${case_index}`,
        metrics: { end_to_end_us: metric(), peak_rss_bytes: metric() },
      })));
    }) });
  return [summary('additional'), summary('legacy')];
}
function win(summary, indices, name = 'end_to_end_us') {
  for (const item of summary.summaries) {
    if (item.target === 'native' && item.candidate === 'B' && indices.includes(item.case_index)) {
      Object.assign(item.metrics[name], { medianRatio: 0.8, lower95: 0.78, upper95: 0.82,
        reproducibleImprovement: true });
    }
  }
}

test('requires every member of one preselected group, not handpicked cases', () => {
  const [a, l] = fixture();
  win(a, [0, 2, 8]);
  assert.equal(evaluateLayoutPerformance(manifest, a, l)[0].performance_gate, 'hold_rows');
  win(a, [1]);
  const result = evaluateLayoutPerformance(manifest, a, l);
  assert.equal(result[0].performance_gate, 'pass');
  assert.equal(result[0].migration_authorized, false);
  assert.equal(result[1].performance_gate, 'hold_rows');
});

test('memory-only group wins cannot hide another target E2E regression', () => {
  const [a, l] = fixture();
  win(a, [0, 1], 'peak_rss_bytes');
  assert.equal(evaluateLayoutPerformance(manifest, a, l)[0].performance_gate, 'pass');
  const regression = l.summaries.find(x => x.target === 'wasm' && x.candidate === 'B');
  Object.assign(regression.metrics.end_to_end_us, { medianRatio: 1.01, lower95: 1.001,
    upper95: 1.02, reproducibleRegression: true });
  assert.equal(evaluateLayoutPerformance(manifest, a, l)[0].performance_gate, 'hold_rows');
});

test('rejects missing, duplicated, prepared or incompatible evidence', () => {
  for (const mutate of [
    (a, l) => l.summaries.pop(),
    a => a.summaries.push(a.summaries[0]),
    a => { a.scope = 'prepared'; },
    (a, l) => { l.host.cpu = 'different'; },
    (a, l) => { l.manifest_sha256 = 'different'; },
    a => { a.summaries[0].metrics.end_to_end_us.pairs = 6; },
  ]) {
    const [a, l] = fixture();
    mutate(a, l);
    assert.throws(() => evaluateLayoutPerformance(manifest, a, l));
  }
});
