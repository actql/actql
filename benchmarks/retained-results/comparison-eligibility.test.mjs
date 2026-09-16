import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedMatrix} from './fixtures.mjs';
import {comparisonEligibility} from './comparison-eligibility.mjs';

test('approved exception applies to exactly nine baseline cases, never to new execution', () => {
  const reports = retainedMatrix().map(f => comparisonEligibility(f.id));
  assert.equal(reports.length, 27);
  assert.equal(reports.filter(r => r.baseline.status === 'ratio-not-computable').length, 9);
  for (const report of reports) {
    assert.equal(report.retained, 'incomplete');
    assert.equal(report.equivalent.status, 'undetermined');
    assert.equal(report.performanceAcceptance, false);
    if (report.baseline.capacity) {
      assert.equal(report.baseline.capacity.retentionBytes, '1073741824');
      assert(BigInt(report.baseline.capacity.lowerBoundBytes) > 1073741824n);
    }
  }
});

test('baseline exclusion cannot turn retained failures or missing comparator into passes', () => {
  const id = 'fixed-join-count-shrinking-intermediate/narrow/1000000';
  for (const status of ['timeout', 'capacity-refused', 'unsupported', 'failed']) {
    const report = comparisonEligibility(id, {retained: {status}});
    assert.equal(report.retained, 'incomplete');
    assert.equal(report.performanceAcceptance, false);
  }
  const completed = comparisonEligibility(id, {retained: {status: 'completed'}});
  assert.equal(completed.baseline.status, 'ratio-not-computable');
  assert.equal(completed.equivalent.status, 'undetermined');
  assert.equal(completed.performanceAcceptance, false);
});

test('reported completions still require equivalence and paired timing evidence', () => {
  const report = comparisonEligibility('fixed-join-count-shrinking-intermediate/narrow/100', {
    retained: {status: 'completed'}, baseline: {status: 'completed'}, equivalent: {status: 'completed'},
  });
  assert.equal(report.baseline.status, 'paired-samples-required');
  assert.equal(report.equivalent.status, 'equivalence-and-paired-samples-required');
  assert.equal(report.performanceAcceptance, false);
});

test('contradictory baseline completion and unregistered cases cannot be accepted', () => {
  const report = comparisonEligibility('fixed-join-count-shrinking-intermediate/narrow/1000000', {
    baseline: {status: 'completed'}, retained: {status: 'completed'},
  });
  assert.equal(report.baseline.status, 'conflicting-capacity-evidence');
  assert.throws(() => comparisonEligibility('unknown'), /UnregisteredCase/);
});
