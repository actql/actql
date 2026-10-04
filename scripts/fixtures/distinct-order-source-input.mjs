// Authored from projected ORDER scope, independently of the query lowerer.
// WHERE excludes 99; DISTINCT collapses two 2s; -amount sorts the already
// negated output as NULL, -1, -2. Reusing the input expression reverses it.
const rows = [{id: 3, amount: 2}, {id: 1, amount: 2},
  {id: 2, amount: 1}, {id: 4, amount: null}, {id: 0, amount: 99}];
const columns = [{name: 'amount', contract: {type: 'number', nullable: true}}];
const fullRows = [{amount: null}, {amount: -1}, {amount: -2}];
const limitedRows = [{amount: -1}, {amount: -2}];
const sql = 'SELECT DISTINCT -amount AS amount FROM records WHERE id > 0 ORDER BY -amount';
const pipe = 'FROM records |> WHERE id > 0 |> SELECT DISTINCT -amount AS amount |> ORDER BY -amount';
// The same operations are written directly as a machine Program. The common
// checker/planner/Host receives them without test-side Program modification.
const program = {version: 'actql/0.1', id: 'fixture.distinct_output_order',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {selected_value: {negate: {field: 'amount'}}}},
      {select: [{amount: 'selected_value'}]}, {distinct: ['amount']},
      {derive: {sort_only: {negate: {field: 'amount'}}}},
      {sort: [{field: 'sort_only', dir: 'asc', nulls: 'first'}]},
      {select: ['amount']}, {take: {count: 2, offset: 1}, as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, format, text, expected, sourceRows = rows) => ({
  name: 'distinct-order-' + name, format, text, sourceRows,
  expected, columns, sourceReadSessionCount: 1,
});
export const distinctOrderSuccesses = [
  success('json-control', 'json', JSON.stringify(program), limitedRows),
  success('sql-limited', 'sql', sql + ' LIMIT 2 OFFSET 1', limitedRows),
  success('pipe-limited', 'aql-text', pipe + ' |> LIMIT 2 OFFSET 1', limitedRows),
  success('sql-null-duplicates', 'sql', sql, fullRows),
  success('sql-empty', 'sql', sql, [], []),
];
export const distinctOrderRefusals = [
  'SELECT DISTINCT -amount AS amount FROM records ORDER BY id + 1',
  'SELECT DISTINCT -amount AS amount FROM records ORDER BY records.amount',
  'FROM records AS original |> SELECT DISTINCT -amount AS amount |> ORDER BY original.amount',
].map((text, index) => ({name: 'distinct-order-unselected-' + index,
  format: 'aql-text', text}));
