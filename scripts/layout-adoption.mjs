// Apply the pre-registered PERFORMANCE gate to already audited summaries.
// A pass still requires independent semantic/physical gates and remeasurement
// after migration. This module neither authorizes migration nor reads raw samples.
export function evaluateLayoutPerformance(manifest, additional, legacy) {
  if (additional.scope !== 'additional' || legacy.scope !== 'legacy' ||
      additional.manifest_sha256 !== legacy.manifest_sha256 ||
      JSON.stringify(additional.host) !== JSON.stringify(legacy.host) ||
      additional.compiler !== legacy.compiler) {
    throw new Error('Incompatible E2E measurement summaries');
  }
  const targets = ['native', 'js', 'wasm'];
  const candidates = ['B', 'C'];
  const assertCoverage = (summary, casesForTarget) => {
    const expected = new Set(targets.flatMap(target => casesForTarget(target)
      .flatMap(index => candidates.map(candidate => `${target}/${index}/${candidate}`))));
    for (const item of summary.summaries) {
      const key = `${item.target}/${item.case_index}/${item.candidate}`;
      if (!expected.delete(key)) throw new Error(`Unexpected or duplicate comparison: ${key}`);
      for (const name of ['end_to_end_us', 'peak_rss_bytes']) {
        const metric = item.metrics[name];
        if (!metric || metric.pairs !== 7 ||
            ![metric.medianRatio, metric.lower95, metric.upper95].every(x => Number.isFinite(x) && x > 0) ||
            metric.lower95 > metric.upper95 ||
            typeof metric.reproducibleImprovement !== 'boolean' ||
            typeof metric.reproducibleRegression !== 'boolean') {
          throw new Error(`Missing audited metric: ${key}/${name}`);
        }
      }
    }
    if (expected.size) throw new Error('Incomplete mandatory comparison matrix');
  };
  assertCoverage(additional, () => manifest.additional_cases.map((_, i) => i));
  // The exact representative legacy schedule is fixed by the manifest's runner.
  assertCoverage(legacy, target => target === 'native'
    ? Array.from({ length: 12 }, (_, i) => i) : [1, 3, 9, 11]);
  const threshold = 1 - manifest.adoption.required_improvement_fraction;
  if (threshold !== 0.8) throw new Error('Unexpected adoption threshold');
  const all = [...additional.summaries, ...legacy.summaries];
  return candidates.map(candidate => {
    const groups = manifest.adoption.major_groups.map(group => {
      const members = manifest.additional_cases.flatMap((item, index) =>
        item.major_group === group ? [index] : []);
      if (!members.length) throw new Error(`Empty major group: ${group}`);
      const metrics = ['end_to_end_us', 'peak_rss_bytes'].filter(name => members.every(index => {
        const item = additional.summaries.find(item => item.target === 'native' &&
          item.case_index === index && item.candidate === candidate);
        return item.metrics[name].medianRatio <= threshold && item.metrics[name].reproducibleImprovement;
      }));
      return { group, members, qualifying_metrics: metrics };
    });
    const regressions = all.filter(item => item.candidate === candidate &&
      item.metrics.end_to_end_us.reproducibleRegression).map(item => ({
        target: item.target, case_id: item.case_id ?? `legacy-${item.case_index}`,
        median_ratio: item.metrics.end_to_end_us.medianRatio,
        lower95: item.metrics.end_to_end_us.lower95,
        upper95: item.metrics.end_to_end_us.upper95,
      }));
    const hasMajorWin = groups.some(group => group.qualifying_metrics.length > 0);
    return {
      candidate, groups, regressions,
      performance_gate: hasMajorWin && !regressions.length ? 'pass' : 'hold_rows',
      reasons: [
        ...(!hasMajorWin ? ['No complete preselected native major group reaches a reproducible 20% improvement'] : []),
        ...(regressions.length ? ['Reproducible E2E regressions in the mandatory matrix'] : []),
      ],
      migration_authorized: false,
    };
  });
}
