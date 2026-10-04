// Independent machine expectations for SQL and Pipe grouping. Both queries
// keep the authored predicates, COUNT, key, public field order and sort.
// SQL projects its SELECT before ordering; Pipe orders its current selected
// scope and binds the final Result projection. Semantic equivalence does not
// require byte-identical Programs or matching compilation identities.
const capture = {
  id: 'capture',
  inputs: {remote: {connector: 'crm/main', resource: 'r'}},
  steps: [
    {from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
    {select: ['id', 'amount'], as: 'aql_capture_0'},
  ],
  results: {source: {from: 'aql_capture_0', fields: ['id', 'amount']}},
};
const groupedSteps = [
  {from: 'remote', group: {by: ['id'], aggregates: {n: {fn: 'count'}}}},
  {filter: {gt: [{field: 'n'}, {literal: 1}]}},
];
const order = [{field: 'id', dir: 'asc', nulls: 'first'}];
const program = suffix => ({
  version: 'actql/0.1', id: 'fixture.grouped_query',
  stages: [capture, {
    id: 'main', inputs: {remote: {result: {stage: 'capture', result: 'source'}}},
    steps: [...groupedSteps, ...suffix],
    results: {rows: {from: 'aql_gen_0', fields: ['id', 'n']}},
  }],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
});

export const groupedQueryCases = [
  {
    name: 'SQL',
    source: 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 '
      + 'GROUP BY id HAVING n > 1 ORDER BY id',
    expected: program([{select: ['id', 'n']}, {sort: order, as: 'aql_gen_0'}]),
  },
  {
    name: 'Pipe',
    source: 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n GROUP BY id '
      + '|> WHERE n > 1 |> SELECT id, n |> ORDER BY id',
    expected: program([{sort: order}, {select: ['id', 'n'], as: 'aql_gen_0'}]),
  },
];
