export const select = {
  name: 'select', enabled: s => s.fields.length > 0,
  admits: (s, a) => Array.isArray(a.fields) && a.fields.length > 0 &&
    new Set(a.fields).size === a.fields.length && a.fields.every(f => s.fields.includes(f)),
  generate: (next, s) => {
    const fields = [...s.fields];
    for (let i = fields.length - 1; i > 0; i--) { const j = next(i + 1); [fields[i], fields[j]] = [fields[j], fields[i]]; }
    return { fields: fields.slice(0, 1 + next(fields.length)) };
  },
  contract: (s, a) => ({ ...s, fields: [...a.fields], schema: Object.fromEntries(a.fields.map(f => [f, s.schema[f]])) }),
  syntax: a => ({ select: a.fields }),
  oracle: (rows, a) => rows.map(r => ({ ...r, values: Object.fromEntries(a.fields.map(f => [f, r.values[f]])) })),
  shrinks: a => a.fields.length > 1 ? a.fields.map((_, i) => ({ fields: a.fields.filter((_, j) => i !== j) })) : [],
};
