// Authored source, ordinary JSON controls and rows. Negating a numeric key
// reverses its order while preserving NULLs; no compiler output is an oracle.
import {aggregatePropertyOrderProgram, aggregatePropertyOrderArrayProgram,
  aggregatePropertyOrderSuccesses} from './aggregate-property-order-source-input.mjs';
const base = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const data = 'WITH objects AS (SELECT id, '
  + "CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, "
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0) ';
const negative = {negate: {property: {name: 'score', value: {field: 'payload'}}}};
export const aggregateSignedOrderProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.aggregate_signed_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key: negative}}, aggregatePropertyOrderProgram.stages[1].steps[3]],
  }],
};
export const aggregateSignedArrayOrderProgram = {
  ...aggregatePropertyOrderArrayProgram, id: 'fixture.aggregate_signed_array_order',
  stages: [aggregatePropertyOrderArrayProgram.stages[0], {
    ...aggregatePropertyOrderArrayProgram.stages[1],
    steps: [...aggregatePropertyOrderArrayProgram.stages[1].steps.slice(0, 5),
      {derive: {key: negative}}, aggregatePropertyOrderArrayProgram.stages[1].steps[6]],
  }],
};
const success = (name, tail, extra = {}) => ({...base,
  name: 'aggregate-signed-order-' + name, text: data + tail,
  expected: [{names: 'a|b|b|c'}], ...extra});
const sql = "SELECT STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names FROM objects";
export const aggregateSignedOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregateSignedOrderProgram),
    parameterDeclarations: undefined}),
  success('sql', sql),
  success('positive-qualified-pipe', "FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY +((before.payload).score) NULLS LAST, id) AS names",
    {expected: [{names: 'b|b|a|c'}]}),
  success('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS `current`, "
    + "STRING_AGG(name, '|' ORDER BY -before.payload.score NULLS LAST, id) AS previous", {
    expected: [{current: 'b|b|c|a', previous: 'a|b|b|c'}],
    columns: ['current', 'previous'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('input-over-sibling', "SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names FROM objects", {
    expected: [{payload: 5, names: 'a|b|b|c'}],
    columns: [{name: 'payload', contract: {type: 'number', nullable: false}}, ...base.columns],
  }),
  success('direct-column', "SELECT STRING_AGG(name, '|' ORDER BY -id NULLS LAST, id) AS names FROM objects",
    {expected: [{names: 'c|b|b|a'}]}),
  success('nested-signs', sql.replace('-payload.score', '-(-payload.score)'),
    {expected: [{names: 'b|b|a|c'}]}),
  success('nulls-first', sql.replace('NULLS LAST', 'NULLS FIRST'),
    {expected: [{names: 'c|a|b|b'}]}),
  success('filtered-argument', sql.replace("name, '|'", "name, '|' WHERE id <= 2"),
    {expected: [{names: 'a|b|b'}]}),
  success('empty', sql, {sourceRows: [], expected: [{names: null}]}),
  success('masked-argument', sql.replace("name, '|'", "IF(id / (id - id) = 0, name, name), '|' WHERE FALSE"),
    {expected: [{names: null}]}),
  success('independent-array-json', '', {format: 'json', text: JSON.stringify(aggregateSignedArrayOrderProgram),
    parameterDeclarations: undefined, sourceRows: base.sourceRows.filter((row, index) => index !== 4),
    expected: [{ids: [1, 2, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
  success('keyed-array', 'FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
    + '|> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY -payload.score NULLS LAST, id) AS ids', {
    sourceRows: base.sourceRows.filter((row, index) => index !== 4), expected: [{ids: [1, 2, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
  success('nullable-parameter', sql.replace('-payload.score', '-@key'), {
    parameterDeclarations: {...base.parameterDeclarations, key: {type: 'number', nullable: true}},
    parameters: {...base.parameters, key: null}, expected: [{names: 'a|b|b|c'}],
  }),
];
export const aggregateSignedOrderRefusals = [
  {name: 'nonnumeric-string', text: sql.replace('-payload.score', '-name')},
  {name: 'nonnumeric-object', text: sql.replace('-payload.score', '+payload')},
  {name: 'missing-property', text: sql.replace('-payload.score', '-payload.missing')},
  {name: 'removed-range', text: 'FROM objects AS old |> AS current '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY -old.payload.score, id) AS names"},
  {name: 'binary-expression', text: sql.replace('-payload.score', '-(id + 1)'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'numeric-ordinal', text: sql.replace('-payload.score NULLS LAST, id', '-1'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'distinct-different-argument', text: sql.replace('STRING_AGG(name', 'STRING_AGG(DISTINCT name'),
    expectedCode: 'ClientProgramImplementationLimit'},
].map(item => ({format: 'aql-text', parameterDeclarations: base.parameterDeclarations,
  parameters: base.parameters, ...item, name: 'aggregate-signed-order-refuse-' + item.name,
  text: data + item.text}));
