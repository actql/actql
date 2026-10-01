// Test generation only. No production evaluator, comparator or checker import.
export const schema = Object.freeze({ extra: { type: 'number', nullable: false },
  k: { type: 'number', nullable: true }, tag: { type: 'number', nullable: false } });
export const clone = x => JSON.parse(JSON.stringify(x));
export const canonicalFields = fields => [...fields].sort();
export const towardsZero = n => n === 0 ? [] : [0,
  ...Array.from({ length: Math.abs(n) - 1 }, (_, i) => (i + 1) * Math.sign(n))];
export function random(seed) {
  let state = seed >>> 0 || 1;
  return n => {
    state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
    return (state >>> 0) % n;
  };
}
export function initialState() {
  return { fields: Object.keys(schema), schema: clone(schema),
    producer: 'prior', order: { origin: 'prior', kind: 'owned Values occurrence', total: true, ties: [] } };
}
export function inspect(testCase, registry) {
  if (testCase.rows.length > 6 || !testCase.rows.every(row => typeof row.id === 'string' &&
      JSON.stringify(Object.keys(row.values).sort()) === JSON.stringify(Object.keys(schema).sort()) &&
      Object.keys(schema).every(field => row.values[field] === null
        ? schema[field].nullable : Number.isInteger(row.values[field]) && Math.abs(row.values[field]) <= 2))) throw new Error('Outside row domain');
  if (new Set(testCase.rows.map(row => row.id)).size !== testCase.rows.length) throw new Error('Duplicate occurrence id');
  if (!testCase.steps.length || testCase.steps.length > 5) throw new Error('Outside length domain');
  if (new Set(testCase.steps.map(s => s.id)).size !== testCase.steps.length ||
      testCase.steps.some(s => typeof s.id !== 'string')) throw new Error('Invalid operation occurrence id');
  let state = initialState();
  const states = [clone(state)];
  for (const [index, step] of testCase.steps.entries()) {
    const descriptor = registry.find(d => d.name === step.op);
    if (!descriptor || !descriptor.admits(state, step.args)) throw new Error('Unmet operation premise');
    state = descriptor.contract(state, step.args, `s${index}`);
    state.producer = `s${index}`;
    states.push(clone(state));
  }
  return states;
}
export function oracle(testCase, registry) {
  const states = inspect(testCase, registry);
  let rows = clone(testCase.rows);
  const stages = [];
  for (const [index, step] of testCase.steps.entries()) {
    const descriptor = registry.find(d => d.name === step.op);
    const input = clone(rows);
    rows = descriptor.oracle(rows, step.args);
    stages.push({ operation: step.op, args: clone(step.args), input, output: clone(rows), ids: rows.map(r => r.id),
      columns: states[index + 1].fields, rows: rows.map(r => states[index + 1].fields.map(f => r.values[f])) });
  }
  return { ...stages.at(-1), occurrences: rows, stages, states };
}
export function program(testCase, registry) {
  const states = inspect(testCase, registry);
  return { source: JSON.stringify([{ values: { schema, rows: testCase.rows.map(r => r.values) }, as: 'seed' }]),
    steps: JSON.stringify(testCase.steps.map((step, index) => ({
      from: states[index].producer, ...registry.find(d => d.name === step.op).syntax(step.args), as: `s${index}`,
    }))), states };
}
function rows(next, index) {
  const output = [];
  for (let i = 0, count = next(7); i < count; i++) {
    const values = i > 0 && next(4) === 0 ? clone(output.at(-1).values)
      : { extra: next(5) - 2, k: next(4) === 0 ? null : next(5) - 2, tag: next(5) - 2 };
    output.push({ id: `${index}:r${i}`, values });
  }
  return output;
}
function build(next, registry, inputRows, length, names, id) {
  let state = initialState();
  const steps = [];
  for (let index = 0; index < length; index++) {
    const available = registry.filter(d => d.enabled(state));
    const descriptor = names ? available.find(d => d.name === names[index]) : available[next(available.length)];
    if (!descriptor) throw new Error('Coverage construction cannot satisfy premise');
    const args = descriptor.generate(next, state);
    steps.push({ id: `n${index}`, op: descriptor.name, args });
    state = descriptor.contract(state, args, `s${index}`);
    state.producer = `s${index}`;
  }
  const result = { id, rows: inputRows, steps };
  inspect(result, registry);
  return result;
}
export function generate(registry, seed = 105106, count = 48) {
  const next = random(seed);
  const result = [];
  const profiles = [[], [{ extra: 0, k: null, tag: 1 }, { extra: 0, k: null, tag: -1 }],
    [{ extra: 1, k: 1, tag: 1 }, { extra: 1, k: 1, tag: 1 }],
    [{ extra: 0, k: 1, tag: 2 }, { extra: 0, k: 1, tag: -1 }, { extra: 0, k: 1, tag: 0 }],
    [{ extra: 1, k: null, tag: 0 }, { extra: 0, k: -1, tag: 1 }, { extra: -1, k: 1, tag: 0 }]];
  // Same enumeration for any registry; no operation-specific combination list.
  for (const left of registry) for (const right of registry) {
    const input = profiles[result.length % profiles.length].map((values, i) => ({ id: `${result.length}:r${i}`, values: clone(values) }));
    result.push(build(next, registry, input, 2,
      [left.name, right.name], `pair:${left.name}/${right.name}`));
  }
  for (let i = 0; i < count; i++) result.push(build(next, registry, rows(next, i), 2 + next(3), null, `seed:${seed}:${i}`));
  return result;
}
export function candidates(testCase, registry) {
  const values = [];
  const add = candidate => {
    try { inspect(candidate, registry); } catch { return; }
    values.push(candidate);
  };
  for (let i = 0; i < testCase.steps.length; i++) {
    const value = clone(testCase); value.steps.splice(i, 1); add(value);
  }
  for (let i = 0; i < testCase.rows.length; i++) {
    const value = clone(testCase); value.rows.splice(i, 1); add(value);
  }
  for (const [i, row] of testCase.rows.entries()) for (const field of Object.keys(schema)) {
    if (schema[field].nullable && row.values[field] !== null) {
      const value = clone(testCase); value.rows[i].values[field] = null; add(value);
    }
    // Strictly decrease absolute magnitude; NULL is already an atomic value.
    if (row.values[field] !== null) for (const scalar of towardsZero(row.values[field])) {
      const value = clone(testCase); value.rows[i].values[field] = scalar; add(value);
    }
  }
  // Reduce an equality class together: otherwise a tied pair cannot shrink
  // its common key without losing the very order mismatch being preserved.
  for (const field of Object.keys(schema)) for (const old of new Set(testCase.rows.map(r => r.values[field]))) {
    const smaller = old === null ? [] : [...towardsZero(old), ...(schema[field].nullable ? [null] : [])];
    for (const scalar of smaller) {
      const value = clone(testCase);
      value.rows.forEach(row => { if (row.values[field] === old) row.values[field] = scalar; });
      add(value);
    }
  }
  const states = inspect(testCase, registry);
  for (const [i, step] of testCase.steps.entries()) {
    for (const args of registry.find(d => d.name === step.op).shrinks(step.args, states[i])) {
      const value = clone(testCase); value.steps[i].args = args; add(value);
    }
  }
  const unique = new Map(values.map(value => [JSON.stringify(value), value]));
  unique.delete(JSON.stringify(testCase));
  return [...unique.values()];
}
export async function shrink(testCase, registry, observe, preserves) {
  let current = clone(testCase);
  const history = [];
  while (true) {
    const reductions = candidates(current, registry);
    const observations = reductions.length ? await observe(reductions) : [];
    const index = reductions.findIndex((value, i) => preserves(value, observations[i]));
    history.push({ attempted: reductions.length, accepted: index });
    if (index < 0) return { original: testCase, minimal: current, history,
      localMinimal: true, finalCandidates: reductions, finalObservations: observations };
    current = reductions[index];
  }
}
