import test from 'node:test';
import assert from 'node:assert/strict';
import {assessPairedTiming} from './paired-assessment.mjs';

const comparator = 'baseline-actql';
const options = {comparator, field: 'executionMs', mode: 'ratio', threshold: 1};
function samples(ratios) {
  return ratios.map((ratio, index) => ({index, caseId: 'fixed/narrow/10000',
    order: index % 2 ? ['retained-actql', comparator] : [comparator, 'retained-actql'],
    samples: {[comparator]: {status: 'completed', executionMs: 100},
      'retained-actql': {status: 'completed', executionMs: ratio * 100}}}));
}

test('paired confidence gates distinguish pass failure and uncertainty reproducibly', () => {
  const fast = assessPairedTiming(samples(Array(7).fill(0.5)), options);
  assert.equal(fast.status, 'pass');
  assert.equal(fast.lower, 0.5);
  assert.equal(fast.upper, 0.5);
  assert.equal(assessPairedTiming(samples(Array(7).fill(2)), options).status, 'fail');
  const variable = samples([0.4, 1.6, 0.5, 1.5, 0.6, 1.4, 1]);
  const uncertain = assessPairedTiming(variable, options);
  assert.equal(uncertain.status, 'indeterminate');
  assert.deepEqual(uncertain, assessPairedTiming(variable, options));
  assert.equal(uncertain.scope, 'paired-timing-only');
});

test('failed missing malformed and nonalternating samples cannot be omitted into success', () => {
  assert.equal(assessPairedTiming([], options).status, 'incomplete');
  assert.equal(assessPairedTiming(samples(Array(6).fill(0.5)), options).status, 'incomplete');
  for (const mutate of [
    pair => { pair.samples['retained-actql'].status = 'timeout'; },
    pair => { delete pair.samples[comparator]; },
    pair => { pair.samples[comparator].executionMs = 0; },
    pair => { pair.samples['retained-actql'].executionMs = NaN; },
    pair => { pair.caseId = 'different-case'; },
    pair => { pair.index = 0; },
    pair => { pair.order.reverse(); },
  ]) {
    const pairs = samples(Array(7).fill(0.5));
    mutate(pairs[3]);
    assert.equal(assessPairedTiming(pairs, options).status, 'incomplete');
  }
});

test('absolute overhead uses a difference, not a ratio or a raw-engine equivalence claim', () => {
  const pairs = samples(Array(7).fill(1));
  for (const pair of pairs) {
    pair.samples[comparator].warmMs = 2;
    pair.samples['retained-actql'].warmMs = 7;
  }
  const report = assessPairedTiming(pairs, {...options, field: 'warmMs', mode: 'difference', threshold: 10});
  assert.equal(report.status, 'pass');
  assert(Math.abs(report.estimate - 5) < 1e-12);
  assert.throws(() => assessPairedTiming(pairs, {...options, minimumPairs: 1}));
  assert.throws(() => assessPairedTiming(pairs, {...options, resamples: 100}));
  assert.throws(() => assessPairedTiming(pairs, {...options, comparator: 'made-up-baseline'}));
  assert.throws(() => assessPairedTiming(samples(Array(11).fill(1)),
    {...options, resamples: 1000000}), /TimingAssessmentWorkLimit/);
});

test('Native configuration comparison measures complete cycles without relabeling the historical baseline', () => {
  const label = 'uncalibrated-native-selection';
  const pairs = Array.from({length: 7}, (_, index) => ({index, caseId: 'fixed/narrow/100',
    order: index % 2 ? ['retained-actql', label] : [label, 'retained-actql'],
    samples: {[label]: {status: 'completed', processCycleMs: 40},
      'retained-actql': {status: 'completed', processCycleMs: 30}}}));
  const config = {comparator: label, field: 'processCycleMs', mode: 'difference', threshold: 0};
  const report = assessPairedTiming(pairs, config);
  assert.equal(report.status, 'pass');
  assert(Math.abs(report.estimate + 10) < 1e-12);
  assert.equal(report.comparator, label);
  assert.throws(() => assessPairedTiming(pairs, {...config, comparator: 'baseline-actql'}), /InvalidTimingAssessment/);
  pairs[4].samples['retained-actql'].status = 'failed';
  assert.equal(assessPairedTiming(pairs, config).status, 'incomplete');
});

test('artifact comparison keeps benchmark work distinct from the Native cycle and rejects missing work', () => {
  const label = 'artifact-read-buffer-64k';
  const pairs = Array.from({length: 7}, (_, index) => ({index, caseId: 'fixed/narrow/100',
    order: index % 2 ? ['retained-actql', label] : [label, 'retained-actql'],
    samples: {[label]: {status: 'completed', benchmarkCycleMs: 100, processCycleMs: 30},
      'retained-actql': {status: 'completed', benchmarkCycleMs: 80, processCycleMs: 30}}}));
  const config = {comparator: label, mode: 'difference', threshold: 0};
  assert(Math.abs(assessPairedTiming(pairs, {...config, field: 'benchmarkCycleMs'}).upper + 20) < 1e-12);
  assert.equal(assessPairedTiming(pairs, {...config, field: 'processCycleMs'}).upper, 0);
  assert.throws(() => assessPairedTiming(pairs, {...config, comparator: 'baseline-actql',
    field: 'benchmarkCycleMs'}), /InvalidTimingAssessment/);
  delete pairs[3].samples[label].benchmarkCycleMs;
  assert.equal(assessPairedTiming(pairs, {...config, field: 'benchmarkCycleMs'}).status, 'incomplete');
});

test('source-open comparison separates database preparation from the complete Native cycle', () => {
  const label = 'source-open-read-write';
  const pairs = Array.from({length: 7}, (_, index) => ({index, caseId: 'fixed/narrow/100',
    order: index % 2 ? ['retained-actql', label] : [label, 'retained-actql'],
    samples: {[label]: {status: 'completed', databasePreparationMs: 5, processCycleMs: 30},
      'retained-actql': {status: 'completed', databasePreparationMs: 1, processCycleMs: 30}}}));
  const config = {comparator: label, mode: 'difference', threshold: 0};
  assert(Math.abs(assessPairedTiming(pairs, {...config, field: 'databasePreparationMs'}).upper + 4) < 1e-12);
  assert.equal(assessPairedTiming(pairs, {...config, field: 'processCycleMs'}).upper, 0);
  delete pairs[2].samples[label].processCycleMs;
  assert.equal(assessPairedTiming(pairs, {...config, field: 'processCycleMs'}).status, 'incomplete');
  assert.throws(() => assessPairedTiming(pairs, {...config, comparator: 'baseline-actql',
    field: 'databasePreparationMs'}), /InvalidTimingAssessment/);
});


test('Native algorithm preparation improvement cannot substitute for complete-cycle improvement', () => {
  for (const comparator of ['native-ascii-word-loop', 'canonical-continuation-rewrap', 'retained-preflight-iterator', 'bounded-text-retention', 'native-per-row-drain']) {
    const pairs = Array.from({length: 21}, (_, index) => ({index, caseId: 'fixed/narrow/100',
      order: index % 2 ? ['retained-actql', comparator] : [comparator, 'retained-actql'],
      samples: {[comparator]: {status: 'completed', processCycleMs: 30, applicationPreparationMs: 6},
        'retained-actql': {status: 'completed', processCycleMs: 30, applicationPreparationMs: 4}}}));
    const options = {comparator, mode: 'difference', threshold: 0, minimumPairs: 21};
    assert.equal(assessPairedTiming(pairs, {...options, field: 'processCycleMs'}).upper, 0);
    assert(Math.abs(assessPairedTiming(pairs, {...options, field: 'applicationPreparationMs'}).upper + 2) < 1e-12);
    assert.throws(() => assessPairedTiming(pairs, {...options, field: 'benchmarkCycleMs'}), /InvalidTimingAssessment/);
    assert.throws(() => assessPairedTiming(pairs, {...options, comparator: 'baseline-actql',
      field: 'applicationPreparationMs'}), /InvalidTimingAssessment/);
    delete pairs[5].samples[comparator].applicationPreparationMs;
    assert.equal(assessPairedTiming(pairs, {...options, field: 'applicationPreparationMs'}).status, 'incomplete');
  }
});
