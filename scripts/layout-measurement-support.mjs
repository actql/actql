// Pure validation/scheduling for the release experiment; no process execution.
export function legacyCases(manifest) {
  return manifest.legacy_matrix.rows.flatMap(rows =>
    manifest.legacy_matrix.columns.flatMap(columns =>
      manifest.legacy_matrix.keys.map(keys => ({ rows, columns, same_keys: keys === 'all-equal' }))));
}

export function legacySchedule(manifest, target, smoke) {
  if (!['native', 'js', 'wasm'].includes(target)) throw new Error('Unknown target');
  const cases = legacyCases(manifest);
  const repetitions = smoke ? 1 : manifest.sampling.measured_repetitions;
  if (!Number.isInteger(repetitions) || (!smoke && repetitions < 7)) throw new Error('At least seven samples required');
  const cycle = manifest.sampling.candidate_order_cycle;
  if (cycle.length !== 2 || cycle[0].join() !== 'A,B,C' || cycle[1].join() !== 'C,B,A') {
    throw new Error('Unexpected candidate order cycle');
  }
  const schedule = [];
  for (const [case_index, shape] of cases.entries()) {
    if (smoke ? case_index !== 0 : target !== 'native' &&
        (shape.same_keys || ![100, 10000].includes(shape.rows))) continue;
    for (let repeat = 0; repeat < repetitions; repeat++) {
      for (const candidate of cycle[repeat % cycle.length]) {
        schedule.push({ case_index, ...shape, repeat, candidate });
      }
    }
  }
  return schedule;
}

export function additionalSchedule(manifest, target, smoke) {
  const ids = ['numeric-project-1000', 'numeric-project-10000', 'nullable-1000',
    'nullable-10000', 'numeric-full-add', 'filter-low', 'filter-high', 'short-text',
    'long-text', 'decimal-temporal', 'nested-small-result', 'producer-branches', 'zero-columns'];
  if (!['native', 'js', 'wasm'].includes(target)) throw new Error('Unknown target');
  if (manifest.additional_cases.length !== ids.length ||
      ids.some((id, i) => manifest.additional_cases[i]?.id !== id)) throw new Error('Unexpected additional case inventory');
  // Reuse validation of the predeclared repetition and alternation rules.
  legacySchedule(manifest, target, smoke);
  const repetitions = smoke ? 1 : manifest.sampling.measured_repetitions;
  return ids.flatMap((case_id, case_index) => {
    const { rows, columns } = manifest.additional_cases[case_index];
    return Array.from({ length: repetitions }, (_, repeat) =>
      manifest.sampling.candidate_order_cycle[repeat % 2].map(candidate =>
        ({ case_id, case_index, rows, columns, same_keys: false, repeat, candidate }))).flat();
  });
}

export function peakRssBytes(stderr, platform) {
  const pattern = platform === 'darwin' ? /^\s*(\d+)\s+maximum resident set size\s*$/gm
    : platform === 'linux' ? /^\s*Maximum resident set size \(kbytes\):\s*(\d+)\s*$/gm
      : null;
  if (!pattern) throw new Error('RSS measurement requires macOS or GNU time on Linux');
  const values = [...stderr.matchAll(pattern)];
  if (values.length !== 1) throw new Error('Expected one process RSS record');
  const value = Number(values[0][1]) * (platform === 'linux' ? 1024 : 1);
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Invalid RSS');
  return value;
}

export function checkedSample(stdout, expected) {
  const events = stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
  const measurements = events.filter(event => event.kind === 'layout-sample');
  const results = events.filter(event => event.type === 'result');
  if (measurements.length !== 1 || results.length !== 1 ||
      results[0].file !== 'sequence_profile_wbtest.mbt' || Number(results[0].index) !== 0 || results[0].message !== '') {
    throw new Error('Missing measurement or independent test success');
  }
  const m = measurements[0];
  if (['candidate', 'rows', 'columns', 'same_keys', 'case_id'].some(key => m[key] !== expected[key]) ||
      (expected.case_id !== undefined && m.disposal_included !== true) ||
      !Array.isArray(m.phases_us) || m.phases_us.length !== 5 ||
      m.phases_us.some(n => !Number.isFinite(n) || n < 0) ||
      !Number.isFinite(m.end_to_end_us) || m.end_to_end_us <= 0) throw new Error('Invalid phase measurement');
  if (m.phases_us.reduce((a, b) => a + b, 0) > m.end_to_end_us + 1) {
    throw new Error('Phase clocks exceed their enclosing interval');
  }
  return m;
}

export function checkedPreparedSample(stdout, expected) {
  const events = stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
  const measurements = events.filter(event => event.kind === 'prepared-layout-sample');
  const results = events.filter(event => event.type === 'result');
  if (measurements.length !== 1 || results.length !== 1 ||
      results[0].file !== 'sequence_profile_wbtest.mbt' || Number(results[0].index) !== 0 || results[0].message !== '') {
    throw new Error('Missing prepared measurement or independent test success');
  }
  const m = measurements[0];
  if (['candidate', 'rows', 'columns', 'case_id'].some(key => m[key] !== expected[key]) ||
      m.reused_input !== true || m.fresh_budgets !== true ||
      !Number.isFinite(m.operation_us) || m.operation_us <= 0 ||
      !Number.isFinite(m.warmup_operation_us) || m.warmup_operation_us <= 0 ||
      'end_to_end_us' in m || 'phases_us' in m) {
    throw new Error('Invalid prepared-only measurement');
  }
  return m;
}
