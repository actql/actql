import { canonicalFields, towardsZero } from './engine.mjs';
export const filter = {
  name: 'filter', enabled: s => s.fields.length > 0,
  admits: (s, a) => ['true', 'false', 'gt'].includes(a.mode) &&
    (a.mode !== 'gt' || s.fields.includes(a.field) && Number.isInteger(a.threshold) && Math.abs(a.threshold) <= 2),
  generate: (next, s) => next(4) === 0 ? { mode: next(2) ? 'true' : 'false' }
    : { mode: 'gt', field: s.fields[next(s.fields.length)], threshold: next(5) - 2 },
  contract: s => ({ ...s, fields: canonicalFields(s.fields) }),
  syntax: a => ({ filter: a.mode === 'gt' ? `${a.field} > ${a.threshold}` : a.mode }),
  oracle: (rows, a) => rows.filter(r => a.mode === 'true' ||
    a.mode === 'gt' && r.values[a.field] !== null && r.values[a.field] > a.threshold),
  shrinks: a => a.mode === 'gt' ? towardsZero(a.threshold).map(threshold => ({ ...a, threshold })) : [],
};
