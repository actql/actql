import { canonicalFields, towardsZero } from './engine.mjs';
export const take = {
  name: 'take', enabled: s => s.order.total,
  admits: (s, a) => s.order.total && Number.isInteger(a.count) && a.count >= 1 && a.count <= 3 &&
    Number.isInteger(a.offset) && a.offset >= 0 && a.offset <= 2,
  generate: next => ({ count: 1 + next(3), offset: next(3) }),
  contract: s => ({ ...s, fields: canonicalFields(s.fields) }),
  syntax: a => ({ take: { count: a.count, offset: a.offset } }),
  oracle: (rows, a) => rows.slice(a.offset, a.offset + a.count),
  shrinks: a => [...Array.from({ length: a.count - 1 }, (_, i) => ({ ...a, count: i + 1 })),
    ...towardsZero(a.offset).map(offset => ({ ...a, offset }))],
};
