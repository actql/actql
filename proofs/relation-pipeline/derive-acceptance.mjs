const stage = (trace, predicate) => trace.expected.stages.some((value, index) =>
  value.operation === 'derive' && predicate(value, index, trace));
const tuple = row => JSON.stringify(Object.keys(row.values).sort().map(field => row.values[field]));
export const deriveAcceptance = {
  variant: 'one numeric snapshot-map addition; fresh output name; integer increment -2..2',
  route: 'SnapshotMap',
  obligations: [
    {id: 'NULL input produces declared nullable NULL', holds: trace => stage(trace, (value, index) =>
      trace.expected.states[index + 1].schema[value.args.output].nullable &&
      value.input.some(row => row.values[value.args.field] === null) &&
      value.output.some(row => row.values[value.args.output] === null))},
    {id: 'nonzero arithmetic retains its source field', holds: trace => stage(trace, value =>
      value.args.increment !== 0 && value.input.some(row => row.values[value.args.field] !== null) &&
      value.output.every((row, index) => row.values[value.args.field] === value.input[index].values[value.args.field]))},
    {id: 'derived field is referenced downstream with nonempty result', holds: trace => stage(trace, (value, index) =>
      value.output.length > 0 && trace.expected.rows.length > 0 &&
      trace.testCase.steps.slice(index + 1).some(step => step.args.field === value.args.output ||
        step.args.fields?.includes(value.args.output) || Object.hasOwn(step.args.mapping ?? {}, value.args.output)))},
    {id: 'duplicates and occurrence order survive arithmetic', holds: trace => stage(trace, value =>
      value.input.some((row, index) => value.input.slice(index + 1).some(other => tuple(row) === tuple(other))) &&
      value.input.length === value.output.length && value.input.every((row, index) => row.id === value.output[index].id))},
    {id: 'empty input retains the complete output contract', holds: trace => stage(trace, (value, index) =>
      value.input.length === 0 && trace.expected.states[index + 1].fields.includes(value.args.output))},
  ],
};
