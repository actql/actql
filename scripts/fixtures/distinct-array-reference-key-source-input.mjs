// Independent input, Program and results. No compiler output generates them.
const number = {type: 'number', nullable: false};
const sourceRows = [{id: 4, amount: 20}, {id: 2, amount: 10},
  {id: 1, amount: 20}, {id: 3, amount: null}, {id: 0, amount: 99}];
// This explicit bound belongs to the submitted source. Only id is asserted
// unique; duplicate x values must survive until the ordinary DISTINCT owner.
const data = 'DATA limited = FROM records |> WHERE id > 0 '
  + '|> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4; '
  + 'DATA pair = SELECT id, COALESCE(amount, 0) AS x FROM limited; ';
const columns = [{name: 'items', contract: {type: 'array', nullable: false,
  items: number}}];

export const distinctArrayReferenceKeyProgram = {version: 'actql/0.1',
  id: 'fixture.distinct_array_reference_key', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', assert_rows: {unique_by: ['id']}},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
        {take: {count: 4, offset: 0}},
        {derive: {x: {coalesce: [{field: 'amount'}, {literal: 0}]}}},
        {select: ['x']}, {distinct: ['x']},
        {group: {by: [], aggregates: {items: {fn: 'array_agg', field: 'x',
          distinct: true, max_items: 1000000,
          order_by: [{field: 'x', dir: 'desc', nulls: 'last'}]}}}, as: 'out'}],
      results: {rows: {from: 'out', fields: ['items']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};

const success = (name, tail, extra = {}) => ({
  name: 'distinct-array-reference-key-' + name, format: 'aql-text',
  text: data + tail, sourceRows, expected: [{items: [20, 10, 0]}], columns,
  sourceReadSessionCount: 1, ...extra,
});
export const distinctArrayReferenceKeySuccesses = [
  success('independent-json', '', {format: 'json',
    text: JSON.stringify(distinctArrayReferenceKeyProgram)}),
  success('qualified-order', 'SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS '
    + 'ORDER BY p.x DESC) AS items FROM pair AS p'),
  success('qualified-argument', 'SELECT ARRAY_AGG(DISTINCT p.x IGNORE NULLS '
    + 'ORDER BY x DESC) AS items FROM pair AS p'),
  success('quoted-parenthesized', 'SELECT ARRAY_AGG(DISTINCT ((x)) IGNORE NULLS '
    + 'ORDER BY (`p`.`X`) DESC) AS items FROM pair AS p'),
  success('pipe-qualified', 'FROM pair AS p |> AGGREGATE '
    + 'ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY p.x DESC) AS items'),
  success('ascending', 'SELECT ARRAY_AGG(DISTINCT p.x IGNORE NULLS '
    + 'ORDER BY (x) ASC) AS items FROM pair AS p', {expected: [{items: [0, 10, 20]}]}),
  success('filtered', 'SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS '
    + 'ORDER BY p.x DESC) AS items FROM pair AS p WHERE x >= 10',
  {expected: [{items: [20, 10]}]}),
];
export const distinctArrayReferenceKeyRefusals = [
  ['other-input', 'p.id'], ['negated-input', '-p.x'],
].map(([name, order]) => ({name: 'distinct-array-reference-key-refuse-' + name,
  format: 'aql-text', text: data + 'SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS '
    + `ORDER BY ${order}) AS items FROM pair AS p`,
  expectedCode: 'ClientProgramImplementationLimit'}));
