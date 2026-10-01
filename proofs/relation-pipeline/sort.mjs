import { canonicalFields } from './engine.mjs';
export function compare(a, b, args) {
  if (a === b) return 0;
  if (a === null) return args.nulls === 'first' ? -1 : 1;
  if (b === null) return args.nulls === 'first' ? 1 : -1;
  return (a < b ? -1 : 1) * (args.dir === 'asc' ? 1 : -1);
}
export const sort = {
  name: 'sort', enabled: s => s.fields.length > 0 && s.order.total,
  admits: (s, a) => s.fields.includes(a.field) && s.order.total &&
    ['asc', 'desc'].includes(a.dir) && ['first', 'last'].includes(a.nulls),
  generate: (next, s) => ({ field: s.fields[next(s.fields.length)], dir: next(2) ? 'asc' : 'desc', nulls: next(2) ? 'first' : 'last' }),
  contract: (s, a, producer) => ({ ...s, fields: canonicalFields(s.fields),
    order: { origin: producer, kind: 'sort', total: true, keys: [{ ...a }], ties: [s.order] } }),
  syntax: a => ({ sort: [{ ...a }] }),
  oracle: (rows, args) => {
    const output = [];
    // Independent insertion sort. Strict comparison preserves the owned input
    // occurrence witness on ties; no reliance on a JS engine's stable sort.
    for (const row of rows) {
      let i = output.length;
      while (i > 0 && compare(row.values[args.field], output[i - 1].values[args.field], args) < 0) i--;
      output.splice(i, 0, row);
    }
    return output;
  },
  shrinks: a => [...(a.dir === 'desc' ? [{ ...a, dir: 'asc' }] : []),
    ...(a.nulls === 'last' ? [{ ...a, nulls: 'first' }] : [])],
};
