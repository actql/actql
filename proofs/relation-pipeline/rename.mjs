import { canonicalFields } from './engine.mjs';
const mapped = (mapping, input) => Object.hasOwn(mapping, input) ? mapping[input] : input;

function names(state, mapping) {
  // The adopted expansion uses canonical INPUT names. Public projection order
  // therefore need not be canonical output-name order after a rename.
  return canonicalFields(state.fields).map(input => ({ input, output: mapped(mapping, input) }));
}

function orderAfterRename(order, mapping) {
  return { ...order,
    ...(order.keys ? { keys: order.keys.map(key => ({ ...key, field: mapped(mapping, key.field) })) } : {}),
    ...(order.ties ? { ties: order.ties.map(prior => orderAfterRename(prior, mapping)) } : {}),
  };
}

export const rename = {
  name: 'rename',
  enabled: state => state.fields.length > 0,
  admits: (state, args) => args && args.mapping && typeof args.mapping === 'object' &&
    !Array.isArray(args.mapping) && Object.entries(args.mapping).every(([input, output]) =>
      state.fields.includes(input) && typeof output === 'string' && /^[A-Za-z_][A-Za-z0-9_]*$/.test(output)) &&
    new Set(names(state, args.mapping).map(field => field.output)).size === state.fields.length,
  generate: (next, state) => {
    const fields = canonicalFields(state.fields);
    const mode = next(3);
    if (mode === 0) return { mapping: {} };
    const input = fields[next(fields.length)];
    if (mode === 1 && fields.length > 1) {
      const other = fields[(fields.indexOf(input) + 1) % fields.length];
      return { mapping: { [input]: other, [other]: input } };
    }
    let output = `r_${input}`;
    while (fields.includes(output)) output = `r_${output}`;
    return { mapping: { [input]: output } };
  },
  contract: (state, args) => {
    const projection = names(state, args.mapping);
    return { ...state,
      fields: projection.map(field => field.output),
      schema: Object.fromEntries(projection.map(field => [field.output, { ...state.schema[field.input] }])),
      order: orderAfterRename(state.order, args.mapping),
    };
  },
  syntax: args => ({ rename: { ...args.mapping } }),
  oracle: (rows, args) => rows.map(row => ({ ...row,
    // Read the original row for every output. A swap is simultaneous, never a
    // sequence of assignments into a partially renamed row.
    values: Object.fromEntries(canonicalFields(Object.keys(row.values))
      .map(input => [mapped(args.mapping, input), row.values[input]])),
  })),
  shrinks: args => Object.keys(args.mapping).map(removed => ({
    mapping: Object.fromEntries(Object.entries(args.mapping).filter(([input]) => input !== removed)),
  })),
};
