// Independent ordinary Programs and results. Signs, receiver identity and
// duplicate exclusion are authored obligations, not compiler-generated values.
import {aggregatePropertyOrderArrayProgram, aggregatePropertyOrderSuccesses}
  from './aggregate-property-order-source-input.mjs';
const base = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const data = 'WITH objects AS (SELECT id, '
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0) ';
const bounded = 'FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 ';
const parameters = {...base.parameters, p4: {score: 10}};
const sourceRows = base.sourceRows.filter((row, index) => index !== 4);
const columns = [{name: 'items', contract: {type: 'array', nullable: false,
  items: {type: 'number', nullable: false}}}];
const negated = {negate: {property: {name: 'score', value: {field: 'payload'}}}};
export const distinctSignedOrderProgram = {
  ...aggregatePropertyOrderArrayProgram, id: 'fixture.distinct_signed_order',
  stages: [aggregatePropertyOrderArrayProgram.stages[0], {
    ...aggregatePropertyOrderArrayProgram.stages[1],
    steps: [...aggregatePropertyOrderArrayProgram.stages[1].steps.slice(0, 5),
      {derive: {key: negated}},
      {group: {by: [], aggregates: {items: {fn: 'array_agg', expr: negated,
        distinct: true, max_items: 1000000,
        order_by: [{field: 'key', dir: 'asc', nulls: 'first'}]}}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['items']}},
  }],
};
const success = (name, tail, extra = {}) => ({...base,
  name: 'distinct-signed-order-' + name, text: data + tail, sourceRows,
  parameters, columns, expected: [{items: [-20, -10]}], ...extra});
const aggregate = (argument, key, direction = '') =>
  '|> AGGREGATE ARRAY_AGG(DISTINCT ' + argument + ' IGNORE NULLS ORDER BY '
  + key + direction + ') AS items';
export const distinctSignedOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(distinctSignedOrderProgram),
    parameterDeclarations: undefined}),
  success('qualified-pipe', bounded + aggregate('-payload.score', '-o.payload.score')),
  success('parenthesized-property', bounded + aggregate('-(payload).score', '-o.payload.`SCORE`')),
  success('sql', ', keyed AS (' + bounded + ') '
    + 'SELECT ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -k.payload.score) AS items FROM keyed AS k'),
  success('descending', bounded + aggregate('-o.payload.score', '-((payload)).score', ' DESC NULLS LAST'),
    {expected: [{items: [-10, -20]}]}),
  success('positive-qualified', bounded + aggregate('+payload.score', '+o.payload.score'),
    {expected: [{items: [10, 20]}]}),
  success('nested-signs', bounded + aggregate('-(-payload.score)', '-(-o.payload.score)'),
    {expected: [{items: [10, 20]}]}),
  success('direct-id', bounded + aggregate('-id', '-o.id', ' DESC'),
    {expected: [{items: [-1, -2, -3, -4]}]}),
  success('filtered', bounded + '|> AGGREGATE ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS '
    + 'WHERE id = 1 ORDER BY -o.payload.score) AS items', {expected: [{items: [-20]}]}),
  success('empty', bounded + aggregate('-payload.score', '-o.payload.score'),
    {sourceRows: [], expected: [{items: []}]}),
];
export const distinctSignedOrderRefusals = [
  ['different-sign', bounded + aggregate('-payload.score', '+o.payload.score')],
  ['different-receiver', bounded + aggregate('-payload.score', '-o.other.score')],
  ['current-versus-snapshot', 'FROM objects AS old |> ASSERT UNIQUE BY (id) |> SET payload = other '
    + aggregate('-payload.score', '-old.payload.score')],
  ['different-nesting', bounded + aggregate('-payload.score', '-(-o.payload.score)')],
  ['object-versus-range', ', colliding AS (SELECT id, payload, other.score AS score FROM objects) '
    + 'FROM colliding AS payload |> ASSERT UNIQUE BY (id) '
    + aggregate('-(payload.payload).score', '-payload.score')],
].map(([name, tail]) => ({name: 'distinct-signed-order-refuse-' + name,
  format: 'aql-text', text: data + tail, parameterDeclarations: base.parameterDeclarations,
  parameters, expectedCode: 'ClientProgramImplementationLimit'}));
