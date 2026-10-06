// Authored from ordinary Group/derive semantics, input multiplicity and NULL.
// Neither expected Programs nor rows are generated from product output.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const columns = names => names.map(name => ({name, contract: number}));
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: null},
  {id: 2, amount: 10}, {id: 3, amount: 20}, {id: 4, amount: 0},
  {id: 1, amount: null}, {id: 0, amount: 999}];
export const selectAggregateExpressionProgram = {version: 'actql/0.1', id: 'fixture.select_aggregate_expression',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates: {cardinality: {fn: 'count'}}}},
      {derive: {next: {add: [{field: 'cardinality'}, {literal: 1}]}}},
      {select: ['next'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['next']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, fields, extra = {}) => ({
  name: 'select-aggregate-expression-' + name, format: 'sql', text, expected,
  sourceRows, columns: columns(fields), sourceReadSessionCount: 1, ...extra});
export const selectAggregateExpressionSuccesses = [
  success('independent-json', JSON.stringify(selectAggregateExpressionProgram), [{next: 7}], ['next'], {format: 'json'}),
  success('count-arithmetic', 'SELECT COUNT(*) + 1 AS next FROM records WHERE id > 0', [{next: 7}], ['next']),
  success('repeated-distinct-limit', 'SELECT id, COUNT(*) AS n, COUNT(*) + 1 AS next, COUNT(DISTINCT amount) + COUNT(DISTINCT amount) AS doubled FROM records WHERE id > 0 GROUP BY id HAVING next > 1 ORDER BY id DESC LIMIT 3 OFFSET 1',
    [{id: 3, n: 2, next: 3, doubled: 2}, {id: 2, n: 1, next: 2, doubled: 2}, {id: 1, n: 2, next: 3, doubled: 0}], ['id', 'n', 'next', 'doubled']),
  success('alias-input-collision', 'SELECT -id AS id, SUM(id) + SUM(records.id) AS total FROM records WHERE id > 0 GROUP BY records.id HAVING total > 5 ORDER BY id',
    [{id: -4, total: 8}, {id: -3, total: 12}], ['id', 'total'],
    {columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('nullable-coalesce', 'SELECT id, COALESCE(SUM(amount), 0) + 1 AS total FROM records WHERE id > 0 GROUP BY id ORDER BY id',
    [{id: 1, total: 1}, {id: 2, total: 11}, {id: 3, total: 41}, {id: 4, total: 1}], ['id', 'total']),
  success('empty-global', 'SELECT COUNT(*) + 1 AS next, SUM(amount) + 1 AS total FROM records',
    [{next: 1, total: null}], ['next', 'total'], {sourceRows: [], columns: [...columns(['next']), {name: 'total', contract: nullableNumber}]}),
  success('cte-pipe-tail', 'WITH summary AS (SELECT COUNT(*) + 1 AS n FROM records WHERE id > 0) SELECT n FROM summary |> SELECT n + 1 AS next |> ORDER BY next',
    [{next: 8}], ['next'], {format: 'aql-text'}),
  success('declared-parameter', 'SELECT COUNTIF(id > @minimum) + 1 AS next FROM records',
    [{next: 5}], ['next'], {parameterDeclarations: {minimum: number}, parameters: {minimum: 1}}),
  success('source-free', 'SELECT COUNT(*) + 1 AS n', [{n: 2}], ['n'], {sourceReadSessionCount: 0}),
];
export const selectAggregateExpressionRefusals = [
  'SELECT COUNT(*) + 1 AS n, n + 1 AS next FROM records',
  'SELECT SUM(amount) + id AS n FROM records',
  'SELECT COUNTIF(id) + 1 AS n FROM records',
  'SELECT COUNTIF(id > @missing) + 1 AS n FROM records',
  'SELECT COUNT(*) + 1 AS n FROM records WHERE COUNT(*) > 0',
].map((text, index) => ({name: 'select-aggregate-expression-refuse-' + index, format: 'sql', text}));
export const selectAggregateExpressionExecutionFailures = [{
  name: 'select-aggregate-expression-demanded-division', format: 'sql',
  text: 'SELECT COUNT(*) / 0 AS n FROM records', resultNames: ['answer'], sourceReadSessionCount: 1,
}];
