// Independent ordinary Programs and rows. No compiler output is an oracle.
import {aggregatePropertyOrderProgram, aggregatePropertyOrderSuccesses}
  from './aggregate-property-order-source-input.mjs';
const base = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const data = 'DATA objects = SELECT id, '
  + "CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, "
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0; ';
const key = {coalesce: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 0}]};
export const aggregateConditionalOrderProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.aggregate_conditional_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key}}, aggregatePropertyOrderProgram.stages[1].steps[3]],
  }],
};
const sql = "SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects";
const success = (name, tail = sql, extra = {}) => ({...base,
  name: 'aggregate-conditional-order-' + name, text: data + tail,
  expected: [{names: 'c|b|b|a'}], ...extra});
export const aggregateConditionalOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregateConditionalOrderProgram),
    parameterDeclarations: undefined}),
  success('sql'),
  success('quoted-pipe', "FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY `IFNULL`((t.payload).score, 0) NULLS LAST, id) AS names"),
  success('searched-case', sql.replace('COALESCE(payload.score, 0)', 'CASE WHEN id = 1 THEN 0 ELSE payload.score END'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('nested-if', sql.replace('COALESCE(payload.score, 0)', 'IF(payload.score IS NULL, other.score, -payload.score)'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('computed-receiver', sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload, other).score'),
    {expected: [{names: 'b|b|c|a'}]}),
  success('per-call-orders', "SELECT STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS names, "
    + "STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0) DESC, id) AS reverse FROM objects", {
    expected: [{names: 'c|b|b|a', reverse: 'a|b|b|c'}],
    columns: ['names', 'reverse'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS current, "
    + "STRING_AGG(name, '|' ORDER BY IFNULL(before.payload.score, 0), id) AS previous", {
    expected: [{current: 'a|c|b|b', previous: 'c|b|b|a'}],
    columns: ['current', 'previous'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('filtered-argument', sql.replace("name, '|'", "name, '|' WHERE id <= 2"),
    {expected: [{names: 'b|b|a'}]}),
  success('masked-argument', sql.replace("name, '|'", "IF(id / (id - id) = 0, name, name), '|' WHERE FALSE"),
    {expected: [{names: null}]}),
  success('empty', sql, {sourceRows: [], expected: [{names: null}]}),
  success('typed-parameter', sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload.score, @fallback)'), {
    parameterDeclarations: {...base.parameterDeclarations, fallback: {type: 'number', nullable: false}},
    parameters: {...base.parameters, fallback: 0},
  }),
  success('distinct-same-argument', "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(name, 'missing')) AS names FROM objects",
    {expected: [{names: 'a|b|c|missing'}]}),
];
export const aggregateConditionalOrderRefusals = [
  {name: 'condition-type', text: sql.replace('COALESCE(payload.score, 0)', 'IF(id, 0, payload.score)')},
  {name: 'missing-member', text: sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload, other).missing')},
  {name: 'removed-range', text: 'FROM objects AS old |> AS current '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY COALESCE(old.payload.score, 0), id) AS names"},
  {name: 'unsafe-demand', text: sql.replace('COALESCE(payload.score, 0)', 'IF(FALSE, id / 0, id)'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'distinct-different-argument', text: sql.replace('STRING_AGG(name', 'STRING_AGG(DISTINCT name'),
    expectedCode: 'ClientProgramImplementationLimit'},
].map(item => ({format: 'aql-text', parameterDeclarations: base.parameterDeclarations,
  parameters: base.parameters, ...item, name: 'aggregate-conditional-order-refuse-' + item.name,
  text: data + item.text}));
