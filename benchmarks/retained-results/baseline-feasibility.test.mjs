import test from 'node:test';
import assert from 'node:assert/strict';
import {baselineRetentionFeasibility, verifyBaselineCapacityEvidence} from './baseline-feasibility.mjs';
import {retainedMatrix, workloads} from './fixtures.mjs';

test('baseline lower-bound derivation is tied to the exact receiver and capacity policy', () => {
  assert.equal(verifyBaselineCapacityEvidence().revision, 'b87584fed46217659589315c1f819994dc0cfe77');
});

test('nine registered baseline cases cannot fit the unchanged one-GiB retention ceiling', () => {
  const cases = retainedMatrix().map(f => baselineRetentionFeasibility(f.workload, f.layout, f.rows));
  assert.equal(cases.filter(value => value.status === 'impossible-under-declared-retention').length, 9);
  const wide = baselineRetentionFeasibility(workloads[0], 'numeric-64', 100000);
  assert.equal(wide.lowerBoundBytes, '3328000000');
  assert.equal(wide.textBytes, '0');
  assert.equal(wide.performanceAcceptance, false);
  const text = baselineRetentionFeasibility(workloads[0], 'text-1024', 100000);
  assert.equal(text.lowerBoundBytes, '1792000000');
  assert.equal(baselineRetentionFeasibility(workloads[0], 'narrow', 1000000).lowerBoundBytes, '1536000000');
});

test('not ruled out is never reported as executable or passing', () => {
  const result = baselineRetentionFeasibility(workloads[0], 'numeric-64', 10000);
  assert.equal(result.status, 'not-ruled-out');
  assert.equal(result.performanceAcceptance, false);
  assert.equal(baselineRetentionFeasibility(workloads[0], 'numeric-64', 100000, 3328000000n).status,
    'not-ruled-out');
  assert.throws(() => baselineRetentionFeasibility(workloads[0], 'narrow', 100, 1073741824), /InvalidRetention/);
});
