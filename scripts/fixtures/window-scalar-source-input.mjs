// Independent expectations: WHERE -> windows -> scalar projection ->
// QUALIFY/DISTINCT -> final ORDER/LIMIT. No compiler output creates this control.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const sourceRows = [{id: 4, amount: 20}, {id: 1, amount: null},
  {id: 3, amount: 10}, {id: 2, amount: 20}, {id: 5, amount: null},
  {id: 0, amount: 999}];
const columns = ['id', 'n'].map(name => ({name, contract: number}));
const declarations = {increment: number};
const parameterInput = {parameterDeclarations: declarations, parameters: {increment: 1}};
const expected = [{id: 1, n: 5}, {id: 2, n: 2}, {id: 3, n: 4},
  {id: 4, n: 3}, {id: 5, n: 6}];
export const windowScalarProgram = {version: 'actql/0.1', id: 'fixture.window_scalar',
  params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'desc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], functions: {position: {fn: 'row_number'}}}},
    {derive: {n: {add: [{field: 'position'}, {$param: 'increment'}]}}},
    {select: ['id', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const window = 'ORDER BY amount DESC NULLS LAST, id';
const sql = `SELECT id, ROW_NUMBER() OVER (${window}) + @increment AS n FROM records WHERE id > 0 ORDER BY id`;
const success = (name, text, extra = {}) => ({name: 'window-scalar-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1,
  ...extra});
export const windowScalarSuccesses = [
  success('independent-json', JSON.stringify(windowScalarProgram),
    {format: 'json', parameters: {increment: 1}}),
  success('sql-arithmetic', sql, parameterInput),
  success('pipe-arithmetic',
    `FROM records |> WHERE id > 0 |> SELECT id, ROW_NUMBER() OVER (${window}) + @increment AS n |> ORDER BY id`,
    {format: 'aql-text', ...parameterInput}),
  success('limit-offset', sql + ' LIMIT 3 OFFSET 1', {...parameterInput, expected: expected.slice(1, 4)}),
  success('multiple-windows', 'SELECT id, COALESCE(LAG(amount) OVER (ORDER BY id), 0) '
    + `+ ROW_NUMBER() OVER (${window}) AS n FROM records WHERE id > 0 ORDER BY id`,
    {expected: [{id: 1, n: 4}, {id: 2, n: 1}, {id: 3, n: 23}, {id: 4, n: 12}, {id: 5, n: 25}]}),
  success('named-window-case', 'SELECT id, CASE WHEN ROW_NUMBER() OVER w > 1 THEN amount ELSE 0 END AS n '
    + 'FROM records WHERE id > 0 WINDOW w AS (ORDER BY id) ORDER BY id',
    {columns: [{name: 'id', contract: number}, {name: 'n', contract: nullable}],
      expected: [{id: 1, n: 0}, {id: 2, n: 20}, {id: 3, n: 10}, {id: 4, n: 20}, {id: 5, n: null}]}),
  success('qualify-evaluated-alias', `SELECT id, ROW_NUMBER() OVER (${window}) + @increment AS n `
    + 'FROM records WHERE id > 0 QUALIFY n <= 3 ORDER BY n',
    {...parameterInput, expected: [{id: 2, n: 2}, {id: 4, n: 3}]}),
  success('nullable-navigation', 'SELECT id, LAG(amount) OVER (ORDER BY id) + 1 AS n '
    + 'FROM records WHERE id > 0 ORDER BY id',
    {columns: [{name: 'id', contract: number}, {name: 'n', contract: nullable}],
      expected: [{id: 1, n: null}, {id: 2, n: null}, {id: 3, n: 21}, {id: 4, n: 11}, {id: 5, n: 21}]}),
  success('group-before-window', 'SELECT amount, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST) + COUNT(*) AS n '
    + 'FROM records WHERE id > 0 GROUP BY amount ORDER BY amount NULLS LAST',
    {columns: [{name: 'amount', contract: nullable}, {name: 'n', contract: number}],
      expected: [{amount: 10, n: 2}, {amount: 20, n: 4}, {amount: null, n: 5}]}),
  success('authored-private-name', 'FROM records |> WHERE id > 0 |> EXTEND IFNULL(amount, 100) AS aql_select_window_0 '
    + '|> SELECT id, ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS n |> ORDER BY id',
    {format: 'aql-text', expected: [{id: 1, n: 101}, {id: 2, n: 22}, {id: 3, n: 13}, {id: 4, n: 24}, {id: 5, n: 105}]}),
  success('distinct-window-values', 'SELECT DISTINCT RANK() OVER (ORDER BY amount DESC NULLS LAST) + 1 AS n '
    + 'FROM records WHERE id > 0 ORDER BY n',
    {columns: [{name: 'n', contract: number}], expected: [{n: 2}, {n: 4}, {n: 5}]}),
  success('typed-empty', sql, {...parameterInput, sourceRows: [], expected: []}),
];
export const windowScalarRefusals = [
  {name: 'invalid-ranking-arity', expectedCode: 'ClientProgramInvalidInput',
    text: 'SELECT ROW_NUMBER(id) OVER (ORDER BY id) + 1 AS n FROM records'},
  {name: 'undeclared-parameter', text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + @missing AS n FROM records'},
  {name: 'unused-parameter', expectedCode: 'ClientProgramInvalidInput', ...parameterInput,
    text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 AS n FROM records'},
  {name: 'sibling-window-input', text: 'SELECT amount AS invented, LAG(invented) OVER (ORDER BY id) + 1 AS n FROM records'},
  {name: 'removed-range', format: 'aql-text', text: 'FROM records AS old |> AS current |> SELECT LAG(old.amount) OVER (ORDER BY id) + 1 AS n'},
  {name: 'nested-window', text: 'SELECT LAG(ROW_NUMBER() OVER (ORDER BY id)) OVER (ORDER BY id) + 1 AS n FROM records'},
  {name: 'operand-type', text: "SELECT ROW_NUMBER() OVER (ORDER BY id) + 'x' AS n FROM records"},
].map(item => ({format: 'sql', ...item, name: 'window-scalar-refuse-' + item.name}));
export const windowScalarExecutionFailures = [{name: 'window-scalar-demanded-error', format: 'sql',
  text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 / (id - 1) AS n FROM records WHERE id > 0 ORDER BY n',
  resultNames: ['answer'], sourceReadSessionCount: 1}];
