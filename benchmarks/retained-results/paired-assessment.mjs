// Timing evidence only. This cannot certify identity, resource accounting,
// comparator equivalence, matrix completeness or whole-experiment acceptance.
// Resample whole pairs so within-pair environmental variation stays paired.
export function assessPairedTiming(pairs, {
  comparator, field, mode, threshold,
  minimumPairs = 7, resamples = 10000, confidence = 0.95, seed = 0x41637451,
}) {
  if (!['baseline-actql', 'direct-duckdb',
    'direct-duckdb-with-identical-obligations-and-independent-holding',
    'uncalibrated-native-selection', 'artifact-read-buffer-64k', 'source-open-read-write', 'native-ascii-word-loop', 'canonical-continuation-rewrap', 'retained-preflight-iterator'].includes(comparator) ||
      !['executionMs', 'warmMs', 'coldMs', 'cleanupMs', 'processCycleMs', 'benchmarkCycleMs', 'databasePreparationMs', 'applicationPreparationMs', 'computeAndIdentityMs'].includes(field) ||
      field === 'processCycleMs' && !['uncalibrated-native-selection', 'artifact-read-buffer-64k', 'source-open-read-write', 'native-ascii-word-loop', 'canonical-continuation-rewrap', 'retained-preflight-iterator'].includes(comparator) ||
      field === 'benchmarkCycleMs' && !['artifact-read-buffer-64k', 'source-open-read-write'].includes(comparator) ||
      field === 'databasePreparationMs' && comparator !== 'source-open-read-write' ||
      ['applicationPreparationMs', 'computeAndIdentityMs'].includes(field) && !['native-ascii-word-loop', 'canonical-continuation-rewrap', 'retained-preflight-iterator'].includes(comparator) ||
      !['ratio', 'difference'].includes(mode) || !Number.isFinite(threshold) ||
      !Number.isSafeInteger(minimumPairs) || minimumPairs < 7 ||
      !Number.isSafeInteger(resamples) || resamples < 10000 || resamples > 1000000 ||
      !Number.isFinite(confidence) || confidence <= 0 || confidence >= 1 ||
      !Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) {
    throw new TypeError('InvalidTimingAssessment');
  }
  const incomplete = reason => Object.freeze({status: 'incomplete', reason,
    scope: 'paired-timing-only', comparator, field, mode});
  if (!Array.isArray(pairs) || pairs.length < minimumPairs) return incomplete('insufficient-pairs');
  if (pairs.length > 10000 || pairs.length * resamples > 10000000) {
    throw new RangeError('TimingAssessmentWorkLimit');
  }
  let caseId, firstOrder;
  const values = [];
  for (let index = 0; index < pairs.length; index++) {
    const pair = pairs[index];
    if (!pair || pair.index !== index || typeof pair.caseId !== 'string' || !pair.caseId.length) {
      return incomplete('invalid-pair-identity');
    }
    caseId ??= pair.caseId;
    if (pair.caseId !== caseId) return incomplete('mixed-cases');
    const order = pair.order;
    if (!Array.isArray(order) || order.length !== 2 ||
        new Set(order).size !== 2 || !order.includes(comparator) || !order.includes('retained-actql')) {
      return incomplete('invalid-comparator-order');
    }
    firstOrder ??= order[0];
    if (order[0] !== (index % 2 === 0 ? firstOrder : firstOrder === comparator ? 'retained-actql' : comparator)) {
      return incomplete('nonalternating-order');
    }
    const reference = pair.samples?.[comparator];
    const retained = pair.samples?.['retained-actql'];
    if (reference?.status !== 'completed' || retained?.status !== 'completed') {
      return incomplete('unsuccessful-sample');
    }
    const a = reference[field], b = retained[field];
    if (!Number.isFinite(a) || a < 0 || !Number.isFinite(b) || b < 0 ||
        (mode === 'ratio' && a === 0)) return incomplete('invalid-duration');
    values.push([a, b]);
  }
  const statistic = indices => {
    let a = 0, b = 0;
    // Sum scaled values to avoid overflowing merely because there are N samples.
    for (const index of indices) {
      a += values[index][0] / values.length;
      b += values[index][1] / values.length;
    }
    return mode === 'ratio' ? b / a : b - a;
  };
  const estimate = statistic(values.map((_, index) => index));
  if (!Number.isFinite(estimate)) return incomplete('nonfinite-statistic');
  let state = seed >>> 0;
  const randomIndex = () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return Math.floor(state / 0x100000000 * values.length);
  };
  const draws = new Array(resamples);
  const indices = new Array(values.length);
  for (let iteration = 0; iteration < resamples; iteration++) {
    for (let index = 0; index < indices.length; index++) indices[index] = randomIndex();
    draws[iteration] = statistic(indices);
    if (!Number.isFinite(draws[iteration])) return incomplete('nonfinite-bootstrap');
  }
  draws.sort((a, b) => a - b);
  const tail = (1 - confidence) / 2;
  const lower = draws[Math.floor(tail * (resamples - 1))];
  const upper = draws[Math.ceil((1 - tail) * (resamples - 1))];
  return Object.freeze({scope: 'paired-timing-only', caseId, comparator, field, mode,
    pairs: values.length, resamples, confidence, seed, threshold, estimate, lower, upper,
    status: upper <= threshold ? 'pass' : lower > threshold ? 'fail' : 'indeterminate'});
}
