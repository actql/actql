// Independent rows and contracts follow the pinned GoogleSQL clause scopes.
// ORDER's inline windows run before QUALIFY; Pipe/set windows see current rows.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const col = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 4, amount: 20}, {id: 1, amount: null},
  {id: 3, amount: 10}, {id: 2, amount: 20}, {id: 5, amount: null},
  {id: 0, amount: 999}];
const expected = [{id: 5}, {id: 1}, {id: 3}, {id: 4}, {id: 2}];
const window = 'ORDER BY amount DESC NULLS LAST, id';
const sql = `SELECT id FROM records WHERE id > 0 ORDER BY ROW_NUMBER() OVER (${window}) DESC`;
export const orderWindowProgram = {version: 'actql/0.1', id: 'fixture.order_window',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'desc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], functions: {position: {fn: 'row_number'}}}},
    {sort: [{field: 'position', dir: 'desc', nulls: 'last'}]},
    {select: ['id'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'order-window-' + name,
  format: 'sql', text, sourceRows, expected, columns: [col('id')],
  sourceReadSessionCount: 1, ...extra});
const aliasRows = [{id: 5, amount: null}, {id: 1, amount: null},
  {id: 3, amount: -10}, {id: 4, amount: -20}, {id: 2, amount: -20}];
export const orderWindowSuccesses = [
  success('independent-json', JSON.stringify(orderWindowProgram), {format: 'json'}),
  success('sql-hidden-call', sql),
  success('string-agg-bounded-frame', "SELECT id FROM records WHERE id > 0 "
    + "ORDER BY STRING_AGG('x', '|') OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) DESC, id DESC",
  {expected: [{id: 5}, {id: 4}, {id: 3}, {id: 2}, {id: 1}]}),
  success('pipe-current-input', `FROM records |> WHERE id > 0 |> ORDER BY ROW_NUMBER() OVER (${window}) DESC |> SELECT id`, {format: 'aql-text'}),
  success('select-alias-collision', 'SELECT id, -amount AS amount FROM records WHERE id > 0 '
    + 'ORDER BY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) DESC',
  {expected: aliasRows, columns: [col('id'), col('amount', nullable)]}),
  success('qualified-input-control', 'SELECT id, -amount AS amount FROM records WHERE id > 0 '
    + 'ORDER BY ROW_NUMBER() OVER (ORDER BY records.amount NULLS LAST, id) DESC',
  {expected: [{id: 5, amount: null}, {id: 1, amount: null}, {id: 4, amount: -20},
    {id: 2, amount: -20}, {id: 3, amount: -10}], columns: [col('id'), col('amount', nullable)]}),
  success('pipe-projected-alias', 'FROM records |> WHERE id > 0 |> SELECT id, -amount AS amount '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) DESC |> SELECT *',
  {format: 'aql-text', expected: aliasRows, columns: [col('id'), col('amount', nullable)]}),
  success('nullable-argument-alias', 'SELECT id, -amount AS n FROM records WHERE id > 0 '
    + 'ORDER BY LAG(n) OVER (ORDER BY id) NULLS LAST, id',
  {columns: [col('id'), col('n', nullable)], expected: [{id: 3, n: -10}, {id: 5, n: null},
    {id: 4, n: -20}, {id: 1, n: null}, {id: 2, n: -20}]}),
  success('qualify-after-order-window', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY n <> 2 '
    + 'ORDER BY LAG(amount) OVER (ORDER BY id) NULLS LAST, id',
  {columns: [col('id'), col('n')], expected: [{id: 4, n: 4}, {id: 3, n: 3}, {id: 5, n: 5}, {id: 1, n: 1}]}),
  success('group-before-alias-window', 'SELECT amount, COUNT(*) + 1 AS total FROM records '
    + 'WHERE id > 0 GROUP BY amount ORDER BY ROW_NUMBER() OVER (ORDER BY total, amount NULLS LAST) DESC',
  {columns: [col('amount', nullable), col('total')], expected: [{amount: null, total: 3},
    {amount: 20, total: 3}, {amount: 10, total: 2}]}),
  success('pipe-distinct-current-rows', 'FROM records |> WHERE id > 0 |> SELECT DISTINCT amount '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST) DESC |> SELECT *',
  {format: 'aql-text', expected: [{amount: null}, {amount: 20}, {amount: 10}], columns: [col('amount', nullable)]}),
  success('set-combined-duplicates', 'SELECT id FROM records WHERE id > 0 UNION ALL '
    + 'SELECT id FROM records WHERE id > 0 ORDER BY RANK() OVER (ORDER BY id DESC) DESC, id',
  {expected: [{id: 1}, {id: 1}, {id: 2}, {id: 2}, {id: 3}, {id: 3}, {id: 4}, {id: 4}, {id: 5}, {id: 5}]}),
  success('parameter-and-offset', `SELECT id FROM records WHERE id > 0 ORDER BY ROW_NUMBER() OVER (${window}) + @shift DESC LIMIT 3 OFFSET 1`,
  {parameterDeclarations: {shift: number}, parameters: {shift: 7}, expected: [{id: 1}, {id: 3}, {id: 4}]}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const orderWindowRefusals = [
  {name: 'select-distinct', text: 'SELECT DISTINCT id FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id)'},
  {name: 'named-window', text: 'SELECT id FROM records WINDOW w AS (ORDER BY id) ORDER BY ROW_NUMBER() OVER w'},
  // UnsupportedAnalytic is disclosed as an implementation limit by the
  // existing bound-input check. Do not broaden generic accepted input codes.
  {name: 'window-alias-nesting', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) AS n FROM records ORDER BY LAG(n) OVER (ORDER BY id)'},
  {name: 'embedded-window-alias-nesting', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 AS n FROM records ORDER BY ROW_NUMBER() OVER (PARTITION BY n ORDER BY id)'},
  {name: 'removed-column', format: 'aql-text', text: 'FROM records |> SELECT id |> ORDER BY ROW_NUMBER() OVER (ORDER BY amount)'},
  {name: 'ranking-arity', expectedCode: 'ClientProgramInvalidInput', text: 'SELECT id FROM records ORDER BY ROW_NUMBER(id) OVER (ORDER BY id)'},
  {name: 'undeclared-parameter', text: 'SELECT id FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id) + @missing'},
].map(item => ({format: 'sql', ...item, name: 'order-window-refuse-' + item.name}));
