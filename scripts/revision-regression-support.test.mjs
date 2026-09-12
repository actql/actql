import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { regressionMetric, revisionCells, supplementalRevisionCells, revisionPairs, revisionGate, revisionMustStop } from './revision-regression-support.mjs';

const manifest = JSON.parse(readFileSync(new URL('../benchmarks/local-relation/columnar-experiment.json', import.meta.url)));
test('inconclusive twenty-one-pair evidence stops further cell collection', () => {
  assert.equal(revisionMustStop([{decision: 'extend'}]), false);
  assert.equal(revisionMustStop([{decision: 'regression'}]), false);
  assert.equal(revisionMustStop([{decision: 'within_tolerance'}, {decision: 'inconclusive'}]), true);
});
test('extension for a second metric never erases an already observed regression', () => {
  assert.equal(revisionGate([{ screening: [{decision: 'regression'}], metrics: [{decision: 'within_tolerance'}] }]), 'regression');
  assert.equal(revisionGate([{ metrics: [{decision: 'inconclusive'}] }]), 'inconclusive');
  assert.throws(() => revisionGate([]));
});
test('required inventory preserves both modes, all targets and A-only alternating revisions', () => {
  const cells = revisionCells(manifest);
  assert.equal(cells.length, 118);
  assert.equal(new Set(cells.map(c => c.id)).size, 118);
  for (const [target, count] of [['native', 50], ['js', 34], ['wasm', 34]]) {
    assert.equal(cells.filter(c => c.target === target).length, count);
  }
  const all = cells.flatMap(c => revisionPairs(c));
  assert.equal(all.length, 1652);
  assert.ok(all.every(s => s.candidate === 'A'));
  assert.deepEqual(all.slice(0, 4).map(s => s.revision), ['baseline', 'candidate', 'candidate', 'baseline']);
  assert.equal(revisionPairs(cells[0], 7, 21).length, 28);
  assert.throws(() => revisionPairs(cells[0], 0, 22));
});

test('supplemental condition ordered and long expressions add exactly eighteen paired cells', () => {
  const cells = supplementalRevisionCells();
  assert.equal(cells.length, 18);
  assert.equal(new Set(cells.map(c => c.id)).size, 18);
  assert.ok(cells.every(c => c.rows === 1000 && c.columns === 2 && c.family === 'supplemental'));
  assert.equal(cells.flatMap(c => revisionPairs(c)).length, 252);
  assert.equal([...revisionCells(manifest), ...cells].flatMap(c => revisionPairs(c)).length, 1904);
});

test('reproducible practical thresholds differ from small reportable regressions', () => {
  const baseline = Array(7).fill(100);
  assert.equal(regressionMetric(baseline, Array(7).fill(104), 'time').decision, 'within_tolerance');
  const threshold = regressionMetric(baseline, Array(7).fill(105), 'time');
  assert.equal(threshold.decision, 'regression');
  assert.equal(threshold.absoluteMedianDifference, 5);
  assert.equal(regressionMetric(baseline, Array(7).fill(109), 'rss').decision, 'within_tolerance');
  assert.equal(regressionMetric(baseline, Array(7).fill(110), 'rss').decision, 'regression');
});

test('mixed evidence extends once, then remains inconclusive rather than passing', () => {
  const varied = [90, 110, 90, 110, 90, 110, 100];
  assert.equal(regressionMetric(Array(7).fill(100), varied, 'time').decision, 'extend');
  assert.equal(regressionMetric(Array(21).fill(100), [...varied, ...varied, ...varied], 'time').decision, 'inconclusive');
  assert.throws(() => regressionMetric(Array(8).fill(100), Array(8).fill(100), 'time'));
  assert.throws(() => regressionMetric(Array(7).fill(100), Array(7).fill(0), 'time'));
});
