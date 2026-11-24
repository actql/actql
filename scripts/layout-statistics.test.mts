import test from 'node:test';
import assert from 'node:assert/strict';
import { pairedSummary, bootstrapMethod } from './layout-statistics.mjs';

test('paired proportional changes preserve exact ratios across changing baseline speeds', () => {
  const baseline = [100, 200, 300, 400, 500, 600, 700];
  const improvement = pairedSummary(baseline, baseline.map(n => n * 0.75));
  assert.equal(improvement.medianRatio, 0.75);
  assert.equal(improvement.lower95, 0.75);
  assert.equal(improvement.upper95, 0.75);
  assert.equal(improvement.reproducibleImprovement, true);
  assert.equal(improvement.reproducibleRegression, false);
  const regression = pairedSummary(baseline, baseline.map(n => n * 1.25));
  assert.equal(regression.reproducibleRegression, true);
  assert.equal(regression.reproducibleImprovement, false);
});

test('equal and mixed directions cannot become reproducible wins from a good median', () => {
  const baseline = Array(7).fill(100);
  const equal = pairedSummary(baseline, baseline);
  assert.equal(equal.reproducibleImprovement, false);
  assert.equal(equal.reproducibleRegression, false);
  const mixed = pairedSummary(baseline, [60, 60, 60, 60, 60, 101, 101]);
  assert.equal(mixed.medianRatio, 0.6);
  assert.equal(mixed.fasterPairs, 5);
  assert.equal(mixed.reproducibleImprovement, false);
  assert.deepEqual(mixed, pairedSummary(baseline, [60, 60, 60, 60, 60, 101, 101]));
  assert.equal(bootstrapMethod.repetitions, 10000);
});

test('a six-pair direction is necessary but the confidence interval must also exclude one', () => {
  const result = pairedSummary(Array(7).fill(100), [70, 75, 80, 85, 90, 95, 100]);
  assert.equal(result.fasterPairs, 6);
  assert.equal(result.requiredDirectionPairs, 6);
  assert.equal(result.reproducibleImprovement, result.upper95 < 1);
  const larger = pairedSummary(Array(14).fill(100), Array(14).fill(90));
  assert.equal(larger.requiredDirectionPairs, 12);
});

test('missing unpaired nonpositive and nonfinite observations are refused', () => {
  const base = Array(7).fill(1);
  for (const input of [[], Array(6).fill(1), Array(8).fill(1), [0, ...base.slice(1)],
    [-1, ...base.slice(1)], [NaN, ...base.slice(1)], [Infinity, ...base.slice(1)]]) {
    assert.throws(() => pairedSummary(base, input));
  }
  assert.throws(() => pairedSummary(Array(7).fill(Number.MIN_VALUE), Array(7).fill(Number.MAX_VALUE)));
});
