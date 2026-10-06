// Independent Group/derive/sort expectations; no rows or Programs are taken
// from the compiler or executor under test.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const columns = names => names.map(name => ({name, contract: number}));
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: null},
  {id: 2, amount: 10}, {id: 3, amount: 20}, {id: 4, amount: 0},
  {id: 1, amount: null}, {id: 0, amount: 999}];
export const orderAggregateExpressionProgram = {version: 'actql/0.1', id: 'fixture.order_aggregate_expression',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['id'], aggregates: {cardinality: {fn: 'count'}}}},
      {derive: {sort_key: {add: [{field: 'cardinality'}, {literal: 1}]}}},
      {sort: [{field: 'sort_key', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'desc', nulls: 'last'}]},
      {select: ['id']}, {take: {count: 3, offset: 1}, as: 'output'}],
    results: {rows: {from: 'output', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, fields, extra = {}) => ({
  name: 'order-aggregate-expression-' + name, format: 'sql', text, expected,
  sourceRows, columns: columns(fields), sourceReadSessionCount: 1, ...extra});
export const orderAggregateExpressionSuccesses = [
  success('independent-json', JSON.stringify(orderAggregateExpressionProgram),
    [{id: 1}, {id: 4}, {id: 2}], ['id'], {format: 'json'}),
  success('hidden-count-limit', 'SELECT id FROM records WHERE id > 0 GROUP BY id ORDER BY COUNT(*) + 1 DESC, id DESC LIMIT 3 OFFSET 1',
    [{id: 1}, {id: 4}, {id: 2}], ['id']),
  success('selected-slot-and-having', 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id HAVING COUNT(*) > 0 ORDER BY COUNT(*) + 1 DESC, id',
    [{id: 1, n: 2}, {id: 3, n: 2}, {id: 2, n: 1}, {id: 4, n: 1}], ['id', 'n']),
  success('alias-argument-collision', 'SELECT -id AS id, SUM(records.id) AS total FROM records WHERE id > 0 GROUP BY records.id ORDER BY SUM(id), id',
    [{id: -3, total: 6}, {id: -4, total: 4}, {id: -2, total: 2}, {id: -1, total: 2}], ['id', 'total'],
    {columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('qualified-argument-control', 'SELECT -id AS id, SUM(records.id) AS total FROM records WHERE id > 0 GROUP BY records.id ORDER BY SUM(records.id), records.id',
    [{id: -1, total: 2}, {id: -2, total: 2}, {id: -4, total: 4}, {id: -3, total: 6}], ['id', 'total'],
    {columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('distinct-selected-expression', 'SELECT DISTINCT COUNT(*) + 1 AS n FROM records WHERE id > 0 GROUP BY id ORDER BY COUNT(*) + 1 DESC',
    [{n: 3}, {n: 2}], ['n']),
  success('nullable-sort', 'SELECT id FROM records WHERE id > 0 GROUP BY id ORDER BY SUM(amount) NULLS LAST, id',
    [{id: 4}, {id: 2}, {id: 3}, {id: 1}], ['id']),
  success('empty-global', 'SELECT 1 AS marker FROM records ORDER BY COUNT(*) + 1',
    [{marker: 1}], ['marker'], {sourceRows: []}),
  success('cte-limit-pipe-tail', 'WITH summary AS (SELECT id FROM records WHERE id > 0 GROUP BY id ORDER BY COUNT(*) DESC, id LIMIT 3) SELECT id FROM summary |> ORDER BY id',
    [{id: 1}, {id: 2}, {id: 3}], ['id'], {format: 'aql-text'}),
  success('declared-parameter', 'SELECT id FROM records WHERE id > 0 GROUP BY id ORDER BY COUNTIF(id > @minimum) DESC, id',
    [{id: 3}, {id: 2}, {id: 4}, {id: 1}], ['id'], {parameterDeclarations: {minimum: number}, parameters: {minimum: 1}}),
];
export const orderAggregateExpressionRefusals = [
  'SELECT DISTINCT id FROM records GROUP BY id ORDER BY COUNT(*)',
  'SELECT id, COUNT(*) AS n FROM records GROUP BY id ORDER BY SUM(n)',
  'SELECT id FROM records ORDER BY COUNT(*)',
  'SELECT id FROM records GROUP BY id ORDER BY COUNTIF(amount)',
  'SELECT id FROM records GROUP BY id ORDER BY COUNTIF(id > @missing)',
].map((text, index) => ({name: 'order-aggregate-expression-refuse-' + index, format: 'sql', text}));
export const orderAggregateExpressionExecutionFailures = [{
  name: 'order-aggregate-expression-demanded-division', format: 'sql',
  text: 'SELECT id FROM records GROUP BY id ORDER BY COUNT(*) / 0', resultNames: ['answer'], sourceReadSessionCount: 1,
}];
