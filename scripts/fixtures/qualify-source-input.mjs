// Authored from QUALIFY's window -> filter -> DISTINCT -> order/limit rules.
// The ordinary JSON control and result contracts do not use compiler output.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
export const qualifyProgram = {version: 'actql/0.1', id: 'fixture.qualify',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], functions: {n: {fn: 'row_number'}}}},
    {filter: {lte: [{field: 'n'}, {literal: 2}]}}, {select: ['id', 'n']},
    {sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS n '
  + 'FROM records WHERE id > 0 QUALIFY n <= 2 ORDER BY n';
const success = (name, text, extra = {}) => ({name: 'qualify-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1,
  expected: [{id: 2, n: 1}, {id: 3, n: 2}], columns: [column('id'), column('n')], ...extra});
export const qualifySuccesses = [
  success('independent-json', JSON.stringify(qualifyProgram), {format: 'json'}),
  success('window-alias', sql, {format: 'sql'}),
  success('alias-collision', 'SELECT amount, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS id '
    + 'FROM records WHERE id > 0 QUALIFY id = 1 ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: 20, id: 1}],
  }),
  success('qualified-input-control', 'SELECT amount, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS id '
    + 'FROM records WHERE id > 0 QUALIFY records.id = 1 ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: null, id: 4}],
  }),
  success('scalar-alias-reuse', 'SELECT -id AS id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY id < -1 ORDER BY id, n', {
    expected: [{id: -3, n: 3}, {id: -3, n: 4}, {id: -2, n: 2}],
  }),
  success('hidden-window', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) = 1 ORDER BY id', {
    columns: [column('id')], expected: [{id: 2}],
  }),
  success('nullable-filter-and-duplicates', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY amount > 25 AND n > 0 ORDER BY n', {
    expected: [{id: 3, n: 3}, {id: 3, n: 4}],
  }),
  success('null-predicate', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY CAST(NULL AS BOOL) AND n > 0 ORDER BY n', {expected: []}),
  success('distinct-order-limit', 'SELECT DISTINCT amount FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY id) <= 4 ORDER BY amount NULLS LAST LIMIT 1 OFFSET 1', {
    columns: [column('amount', nullable)], expected: [{amount: 30}],
  }),
  success('group-having-hidden-aggregate', 'SELECT id, COUNT(*) AS total, '
    + 'ROW_NUMBER() OVER (ORDER BY id DESC) AS n FROM records WHERE id > 0 '
    + 'GROUP BY id HAVING total > 0 QUALIFY n <= 2 AND COUNT(*) > 0 ORDER BY id', {
    columns: [column('id'), column('total'), column('n')],
    expected: [{id: 2, total: 1, n: 2}, {id: 3, total: 2, n: 1}],
  }),
  success('cte-and-pipe', 'WITH chosen AS (SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) = 1) '
    + 'FROM chosen |> SELECT id |> ORDER BY id', {columns: [column('id')], expected: [{id: 2}]}),
  success('join', 'SELECT l.id, ROW_NUMBER() OVER (ORDER BY l.id) AS n FROM records AS l '
    + 'JOIN (SELECT 2 AS k UNION ALL SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + 'QUALIFY n <= 2 ORDER BY n', {expected: [{id: 2, n: 1}, {id: 3, n: 2}]}),
  success('undemanded-select-error', 'SELECT 1 / (id - 1) AS ratio, '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 QUALIFY n > 1 ORDER BY n', {
    columns: [column('ratio'), column('n')],
    expected: [{ratio: 1, n: 2}, {ratio: 0.5, n: 3}, {ratio: 0.5, n: 4}],
  }),
  success('qualified-range-does-not-demand-alias', 'SELECT 1 / (id - 1) AS records, '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 '
    + 'QUALIFY records.id > 1 ORDER BY n', {
    columns: [column('records'), column('n')],
    expected: [{records: 1, n: 2}, {records: 0.5, n: 3}, {records: 0.5, n: 4}],
  }),
  success('qualified-object-does-not-demand-alias',
    'DATA objects = SELECT 2 AS id, @a AS payload UNION ALL SELECT 1 AS id, @b AS payload '
    + 'UNION ALL SELECT 3 AS id, @c AS payload; '
    + 'SELECT 1 / (id - 1) AS objects, ROW_NUMBER() OVER (ORDER BY id) AS n FROM objects '
    + 'QUALIFY objects.id > 1 AND objects.payload.score > 5 ORDER BY n', {
    hostProfile: 'analytic-property', sourceReadCount: 0, sourceReadSessionCount: 0,
    parameterDeclarations: Object.fromEntries(['a', 'b', 'c'].map(name => [name,
      {type: 'object', nullable: true, fields: {score: number}}])),
    parameters: {a: {score: 10}, b: {score: 20}, c: null},
    columns: [column('objects'), column('n')], expected: [{objects: 1, n: 2}],
  }),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const qualifyRefusals = [
  'SELECT id FROM records QUALIFY id > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY missing > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY n',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY @missing > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY SUM(n) > 0',
].map((text, index) => ({name: 'qualify-refuse-' + index, format: 'aql-text', text}));
export const qualifyExecutionFailures = [{name: 'qualify-demanded-error', format: 'aql-text',
  text: 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 '
    + 'QUALIFY 1 / (id - 1) > 0 AND n > 0 ORDER BY n',
  resultNames: ['answer'], sourceReadSessionCount: 1}];
