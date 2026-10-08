import {canonicalFields, towardsZero} from './engine.mjs';

// A reviewed successful numeric map instance, not a general expression oracle.
export const derive = {
  name: 'derive',
  enabled: state => state.fields.some(field => state.schema[field].type === 'number'),
  admits: (state, args) => args !== null && typeof args === 'object' && !Array.isArray(args) &&
    Object.keys(args).sort().join(',') === 'field,increment,output' &&
    state.fields.includes(args.field) && state.schema[args.field].type === 'number' &&
    typeof args.output === 'string' && /^d_[A-Za-z_][A-Za-z0-9_]*$/u.test(args.output) &&
    !state.fields.includes(args.output) && Number.isInteger(args.increment) && Math.abs(args.increment) <= 2,
  generate: (next, state) => {
    const fields = state.fields.filter(field => state.schema[field].type === 'number');
    const field = fields[next(fields.length)];
    let output = `d_${field}`;
    while (state.fields.includes(output)) output = `d_${output}`;
    return {field, output, increment: next(5) - 2};
  },
  contract: (state, args) => ({...state, fields: canonicalFields([...state.fields, args.output]),
    schema: {...state.schema, [args.output]: {...state.schema[args.field]}}}),
  syntax: args => ({derive: {[args.output]: {add: [{field: args.field}, {literal: args.increment}]}}}),
  oracle: (rows, args) => rows.map(row => ({...row, values: {...row.values,
    [args.output]: row.values[args.field] === null ? null : row.values[args.field] + args.increment}})),
  shrinks: args => towardsZero(args.increment).map(increment => ({...args, increment})),
};
