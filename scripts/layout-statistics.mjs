// Paired, deterministic descriptive statistics. This does not establish workload
// completeness, semantic equivalence, provenance, or permission to adopt a layout.
export const bootstrapMethod = Object.freeze({
  statistic: 'median of candidate/baseline ratios in paired samples',
  repetitions: 10000,
  seed: 0x5eeda017,
  interval: 'percentile 95%; nearest-rank 2.5% and 97.5%',
  minimumPairs: 7,
  directionThreshold: 'ceil(6*n/7) paired samples',
});

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : sorted[middle - 1] / 2 + sorted[middle] / 2;
}

export function pairedSummary(baseline, candidate) {
  if (!Array.isArray(baseline) || !Array.isArray(candidate) ||
      baseline.length !== candidate.length || baseline.length < bootstrapMethod.minimumPairs ||
      [...baseline, ...candidate].some(n => !Number.isFinite(n) || n <= 0)) {
    throw new Error('paired positive finite measurements, at least seven, are required');
  }
  const ratios = candidate.map((value, index) => value / baseline[index]);
  if (ratios.some(n => !Number.isFinite(n) || n <= 0)) throw new Error('unrepresentable paired ratio');
  let state = bootstrapMethod.seed;
  const randomIndex = () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return Math.floor((state >>> 0) / 0x100000000 * ratios.length);
  };
  const distribution = Array.from({ length: bootstrapMethod.repetitions }, () =>
    median(Array.from({ length: ratios.length }, () => ratios[randomIndex()])));
  distribution.sort((a, b) => a - b);
  const lower95 = distribution[Math.ceil(distribution.length * 0.025) - 1];
  const upper95 = distribution[Math.ceil(distribution.length * 0.975) - 1];
  const fasterPairs = ratios.filter(n => n < 1).length;
  const slowerPairs = ratios.filter(n => n > 1).length;
  const requiredDirectionPairs = Math.ceil(6 * ratios.length / 7);
  return {
    pairs: ratios.length,
    baselineMedian: median(baseline),
    candidateMedian: median(candidate),
    pairedRatios: ratios,
    medianRatio: median(ratios),
    lower95,
    upper95,
    fasterPairs,
    slowerPairs,
    requiredDirectionPairs,
    reproducibleImprovement: fasterPairs >= requiredDirectionPairs && upper95 < 1,
    reproducibleRegression: slowerPairs >= requiredDirectionPairs && lower95 > 1,
  };
}
