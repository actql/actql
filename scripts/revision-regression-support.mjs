// Pure A-vs-A cross-revision schedule and preregistered decision rules.
import { legacySchedule, additionalSchedule } from './layout-measurement-support.mjs';
import { pairedSummary } from './layout-statistics.mjs';

export const regressionPolicy = Object.freeze({
  initialPairs: 7,
  maximumPairs: 21,
  timeRatio: 1.05,
  rssRatio: 1.10,
});

export function revisionGate(decisions) {
  if (!decisions.length) throw new Error('No completed cells');
  const observations = decisions.flatMap(d => [...(d.screening ?? []), ...d.metrics]);
  if (observations.some(m => m.decision === 'regression')) return 'regression';
  if (decisions.some(d => d.metrics.some(m => m.decision !== 'within_tolerance'))) return 'inconclusive';
  return 'within_tolerance';
}

export function revisionCells(manifest) {
  if (manifest.sampling.measured_repetitions !== regressionPolicy.initialPairs) {
    throw new Error('Historical inventory must retain seven-pair sampling');
  }
  return ['native', 'js', 'wasm'].flatMap(target =>
    [['legacy', legacySchedule], ['additional', additionalSchedule]].flatMap(([family, schedule]) =>
      schedule(manifest, target, false)
        .filter(s => s.candidate === 'A' && s.repeat === 0)
        .flatMap(s => ['e2e', 'prepared'].map(mode => ({
          ...s, target, family, mode,
          id: `${target}/${family}/${s.case_index}/${mode}`,
        })))));
}

export function revisionPairs(cell, from = 0, until = regressionPolicy.initialPairs) {
  if (!Number.isInteger(from) || !Number.isInteger(until) || from < 0 ||
      until <= from || until > regressionPolicy.maximumPairs) {
    throw new Error('Invalid fixed pair range');
  }
  return Array.from({ length: until - from }, (_, i) => {
    const repeat = from + i;
    return (repeat % 2 === 0 ? ['baseline', 'candidate'] : ['candidate', 'baseline'])
      .map(revision => ({ ...cell, repeat, revision, candidate: 'A' }));
  }).flat();
}

export function regressionMetric(baseline, candidate, metric) {
  const threshold = metric === 'time' ? regressionPolicy.timeRatio
    : metric === 'rss' ? regressionPolicy.rssRatio : null;
  if (threshold === null) throw new Error('Unknown regression metric');
  if (![regressionPolicy.initialPairs, regressionPolicy.maximumPairs].includes(baseline.length)) {
    throw new Error('A decision requires exactly seven or twenty-one pairs');
  }
  const stats = pairedSummary(baseline, candidate);
  const decision = stats.medianRatio >= threshold && stats.reproducibleRegression
    ? 'regression'
    : stats.upper95 < threshold ? 'within_tolerance'
      : baseline.length === regressionPolicy.initialPairs ? 'extend' : 'inconclusive';
  return { ...stats, metric, threshold, decision,
    absoluteMedianDifference: stats.candidateMedian - stats.baselineMedian };
}
