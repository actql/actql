import { distinctAcceptance } from './distinct-acceptance.mjs';
import { canonicalFields } from './engine.mjs';
const stage = (trace, op, predicate) => trace.expected.stages.some((s, i) => s.operation === op && predicate(s, i, trace));
export const registrations = {
  distinct: distinctAcceptance,
  filter: { variant: 'numeric gt or constant', route: 'Filter', obligations: [
    { id: 'NULL predicate drops NULL', holds: t => stage(t, 'filter', s => s.args.mode === 'gt' &&
      s.input.some(r => r.values[s.args.field] === null) && s.input.some(r => r.values[s.args.field] !== null && r.values[s.args.field] > s.args.threshold) &&
      !s.output.some(r => r.values[s.args.field] === null)) },
    { id: 'empty output', holds: t => stage(t, 'filter', s => s.input.length > 0 && !s.output.length) },
  ] },
  select: { variant: 'nonempty named projection', route: 'Select', projection: (s, a) => a.fields.map(field => ({ input: field, output: field })), obligations: [
    { id: 'noncanonical projection', holds: t => stage(t, 'select', s => s.args.fields.length > 1 &&
      JSON.stringify(s.args.fields) !== JSON.stringify([...s.args.fields].sort()) && s.output.length > 0) },
  ] },
  sort: { variant: 'one numeric nullable key with owned tie order', route: 'StableSort', obligations: [
    ...['first', 'last'].map(nulls => ({ id: `NULL ${nulls}`, holds: t => stage(t, 'sort', s => s.args.nulls === nulls &&
      s.input.some(r => r.values[s.args.field] === null) && s.input.some(r => r.values[s.args.field] !== null)) })),
    { id: 'distinguishable tie survives downstream', holds: t => stage(t, 'sort', s => s.output.some((a, i) =>
      s.output.slice(i + 1).some(b => a.values[s.args.field] === b.values[s.args.field] &&
        t.expected.occurrences.some(r => r.id === a.id) && t.expected.occurrences.some(r => r.id === b.id) &&
        JSON.stringify(t.expected.occurrences.find(r => r.id === a.id).values) !==
          JSON.stringify(t.expected.occurrences.find(r => r.id === b.id).values)))) },
  ] },
  take: { variant: 'positive count, nonnegative offset, total order', route: 'Limit', obligations: [
    { id: 'offset removes a distinguishable first row', holds: t => stage(t, 'take', s => s.args.offset > 0 &&
      s.input.length > s.args.offset && s.output.length > 0 &&
      JSON.stringify(s.input[0].values) !== JSON.stringify(s.output[0].values)) },
  ] },
  rename: { variant: 'simultaneous named projection', route: 'Select', projection: (s, a) => canonicalFields(s.fields).map(input => ({ input, output: Object.hasOwn(a.mapping, input) ? a.mapping[input] : input })), obligations: [
    { id: 'swap different values and nullability', holds: t => stage(t, 'rename', (s, i) =>
      Object.entries(s.args.mapping).some(([a, b]) => a !== b && s.args.mapping[b] === a &&
        t.expected.states[i].schema[a].nullable !== t.expected.states[i].schema[b].nullable &&
        s.input.some(r => r.values[a] !== r.values[b]))) },
    { id: 'new name is referenced downstream', holds: t => stage(t, 'rename', (s, i) =>
      Object.entries(s.args.mapping).some(([a, b]) => a !== b && !t.expected.states[i].fields.includes(b) &&
        t.testCase.steps.slice(i + 1).some(step => step.args.field === b || step.args.fields?.includes(b)) &&
        s.output.length > 0 && t.expected.rows.length > 0)) },
    { id: 'public projection differs from canonical output order', holds: t => stage(t, 'rename', s =>
      s.output.length > 0 && JSON.stringify(s.columns) !== JSON.stringify([...s.columns].sort()) &&
      t.expected.stages.at(-1) === s) },
    { id: 'empty input contract', holds: t => stage(t, 'rename', s => !s.input.length && Object.keys(s.args.mapping).length > 0) },
    { id: 'all NULL nullable field reaches rename', holds: t => stage(t, 'rename', (s, i) => s.input.length > 0 &&
      Object.keys(s.args.mapping).some(f => t.expected.states[i].schema[f].nullable && s.input.every(r => r.values[f] === null))) },
    { id: 'duplicate rows retain multiplicity', holds: t => stage(t, 'rename', s => s.input.some((r, i) =>
      s.input.slice(i + 1).some(other => JSON.stringify(r.values) === JSON.stringify(other.values))) &&
      s.output.length === s.input.length && Object.keys(s.args.mapping).length > 0) },
  ] },
};
