import { canonicalFields } from './engine.mjs';
export const distinct = {
  name: 'distinct',
  enabled: state => state.fields.length > 0,
  admits: (state, args) => state.fields.length > 0 && args !== null && typeof args === 'object' &&
    !Array.isArray(args) && Object.keys(args).length === 0,
  generate: () => ({}),
  contract: state => ({ ...state, fields: canonicalFields(state.fields) }),
  syntax: () => ({ distinct: true }),
  oracle: rows => {
    const output = [];
    for (const row of rows) {
      const fields = canonicalFields(Object.keys(row.values));
      if (!output.some(prior => fields.every(field => prior.values[field] === row.values[field]))) output.push(row);
    }
    return output;
  },
  shrinks: () => [],
};
