import { oracle } from './engine.mjs';
import { sites } from './sites.mjs';
import { connectionAnchor, connectionMismatch } from './mismatch.mjs';
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const oneDistinct = c => c.steps.filter(s => s.op === 'distinct').length === 1;
const firstEdge = c => c.steps.length >= 2 && c.steps.slice(0, 2).some(s => s.op === 'distinct');
function semanticMismatch(c, observed, anchor, registry) {
  if (!oneDistinct(c) || !observed?.checked || !observed.registered || observed.kind !== 'complete') return false;
  const step = c.steps.find(s => s.id === anchor.step && s.op === 'distinct');
  if (!step) return false;
  const expected = oracle(c, registry), index = c.steps.indexOf(step), stage = expected.stages[index];
  const rows = anchor.rows.map(id => stage.input.find(r => r.id === id));
  if (rows.some(r => !r)) return false;
  const field = expected.states[index + 1].fields[0];
  if (anchor.kind === 'distinct compares only first column' && (field !== anchor.field ||
    rows[0].values[field] !== rows[1].values[field] || same(rows[0].values, rows[1].values))) return false;
  // The defect must remain observable on the same two input occurrences. Do
  // not shrink it into another failure or an invisible duplicate identity.
  if (!expected.ids.includes(anchor.rows[0]) || !expected.ids.includes(anchor.rows[1])) return false;
  const wrong = registry.map(d => d.name !== 'distinct' ? d : { ...d, oracle: input => {
    const kept = [];
    for (const row of input) {
      const fields = Object.keys(row.values).sort();
      if (!kept.some(prior => (anchor.kind === 'distinct compares only first column' ? [fields[0]] : fields)
        .every(f => prior.values[f] === row.values[f]))) kept.push(row);
    }
    if (anchor.kind === 'distinct mirrors the first-occurrence keep mask') {
      const first = input.map(row => kept.find(prior => Object.keys(row.values).every(f => prior.values[f] === row.values[f])).id === row.id);
      return input.filter((_, i) => first[input.length - i - 1]);
    }
    return kept;
  } });
  const defect = oracle(c, wrong);
  const finalKeys = anchor.rows.map(id => {
    const row = expected.occurrences.find(r => r.id === id);
    return JSON.stringify(expected.columns.map(f => row.values[f]));
  });
  const keys = result => result.rows.map(row => JSON.stringify(row));
  const good = keys(expected), bad = keys(defect);
  if (anchor.kind === 'distinct compares only first column') {
    if (!finalKeys.some(key => good.filter(k => k === key).length > bad.filter(k => k === key).length)) return false;
  } else {
    if (finalKeys[0] === finalKeys[1] || finalKeys.some(key => good.filter(k => k === key).length !== 1 || bad.filter(k => k === key).length !== 1) ||
      good.indexOf(finalKeys[0]) >= good.indexOf(finalKeys[1]) || bad.indexOf(finalKeys[0]) <= bad.indexOf(finalKeys[1])) return false;
  }
  return same(observed.columns, expected.columns) && !same(expected.rows, defect.rows) && same(observed.rows, defect.rows);

}
function anchorFor(kind, c, observed, registry) {
  if (!oneDistinct(c)) return null;
  const step = c.steps.find(s => s.op === 'distinct'), expected = oracle(c, registry);
  const stage = expected.stages[c.steps.indexOf(step)];
  for (let i = 0; i < stage.input.length; i++) for (let j = i + 1; j < stage.input.length; j++) {
    const anchor = { kind, step: step.id, field: expected.states[c.steps.indexOf(step) + 1].fields[0],
      rows: [stage.input[i].id, stage.input[j].id] };
    if (semanticMismatch(c, observed, anchor, registry)) return anchor;
  }
  return null;
}
export const distinctMutations = [
  { name: 'distinct-first-column-only', path: 'src/execution_relation/bounded_binding_rows.mbt',
    before: 'indices[state.distinct_cursor - 1],\n              indices[state.distinct_cursor],\n              state.sort_orders.length(),',
    after: 'indices[state.distinct_cursor - 1],\n              indices[state.distinct_cursor],\n              1,',
    eligible: oneDistinct,
    anchor: (c, o, registry) => anchorFor('distinct compares only first column', c, o, registry), preserves: semanticMismatch },
  { name: 'distinct-mirrored-keep-mask', path: 'src/execution_relation/bounded_binding_rows.mbt',
    before: 'indices[state.row]\n          } else {\n            state.row\n          }',
    after: 'indices[state.row]\n          } else {\n            count - state.row - 1\n          }',
    eligible: oneDistinct,
    anchor: (c, o, registry) => anchorFor('distinct mirrors the first-occurrence keep mask', c, o, registry), preserves: semanticMismatch },
  { ...sites[0], name: 'distinct-handoff-wrong-port', eligible: firstEdge,
    anchor: c => connectionAnchor(c),
    preserves: (c, o, anchor) => firstEdge(c) && connectionMismatch(c, o, anchor) },
];
