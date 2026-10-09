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
// Authored GROUP -> ANALYTIC controls. Source order is irrelevant to grouped
// counts/sums; the explicit window and Result ordering determine these rows.
const groupOrder = [{field: 'amount', dir: 'asc', nulls: 'last'}];
const groupedColumns = [{name: 'amount', contract: nullable}, {name: 'n', contract: nullable}];
const lagRows = [{amount: 10, n: null}, {amount: 20, n: 1}, {amount: null, n: 2}];
const sumRows = [{amount: 10, n: 3}, {amount: 20, n: 9}, {amount: null, n: 15}];
function groupedOperandProgram(aggregate, windowFunction, frame) {
  return {version: 'actql/0.1', id: 'fixture.grouped_window_operand',
    stages: [structuredClone(windowScalarProgram.stages[0]),
      {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
        steps: [{from: 'records', group: {by: ['amount'], aggregates: {measured: aggregate}}},
          {analytic: {partition_by: [], order_by: groupOrder, functions: {n: windowFunction},
            ...(frame ? {frame} : {})}},
          {select: ['amount', 'n']}, {sort: groupOrder, as: 'ordered'}],
        results: {rows: {from: 'ordered', fields: ['amount', 'n']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
export const groupedLagOperandProgram = groupedOperandProgram({fn: 'count'},
  {fn: 'lag', expr: {field: 'measured'}});
export const groupedSumOperandProgram = groupedOperandProgram({fn: 'sum', field: 'id'},
  {fn: 'sum', field: 'measured'}, {start: 'unbounded_preceding', end: 'current_row'});
const lagOperandSql = 'SELECT amount, LAG(COUNT(*)) OVER (ORDER BY amount NULLS LAST) AS n '
  + 'FROM records WHERE id > 0 GROUP BY amount ORDER BY amount NULLS LAST';
const operandOrderHead = 'SELECT records.amount AS original, -records.amount AS amount '
  + 'FROM records WHERE id > 0 GROUP BY records.amount ORDER BY LAG(SUM(';
const operandOrderTail = ')) OVER (ORDER BY original NULLS LAST) NULLS LAST, original NULLS LAST';
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
  success('aggregate-operand-lag-json', JSON.stringify(groupedLagOperandProgram),
    {format: 'json', columns: groupedColumns, expected: lagRows}),
  success('aggregate-operand-lag', lagOperandSql, {columns: groupedColumns, expected: lagRows}),
  success('aggregate-operand-sum-json', JSON.stringify(groupedSumOperandProgram),
    {format: 'json', columns: groupedColumns, expected: sumRows}),
  success('aggregate-operand-running-sum', 'SELECT amount, SUM(SUM(id)) OVER '
    + '(ORDER BY amount NULLS LAST ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n '
    + 'FROM records WHERE id > 0 GROUP BY amount ORDER BY amount NULLS LAST',
    {columns: groupedColumns, expected: sumRows}),
  success('aggregate-operand-countif', 'SELECT amount, COUNTIF(COUNT(*) > 1) OVER '
    + '(ORDER BY amount NULLS LAST ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n '
    + 'FROM records WHERE id > 0 GROUP BY amount ORDER BY amount NULLS LAST',
    {columns: [{name: 'amount', contract: nullable}, {name: 'n', contract: number}],
      expected: [{amount: 10, n: 0}, {amount: 20, n: 1}, {amount: null, n: 2}]}),
  success('aggregate-operand-scalar', 'SELECT amount, COALESCE(LAG(COUNT(*)) OVER '
    + '(ORDER BY amount NULLS LAST), 0) + 1 AS n FROM records WHERE id > 0 '
    + 'GROUP BY amount ORDER BY amount NULLS LAST',
    {columns: [{name: 'amount', contract: nullable}, {name: 'n', contract: number}],
      expected: [{amount: 10, n: 1}, {amount: 20, n: 2}, {amount: null, n: 3}]}),
  success('aggregate-operand-named-window', 'SELECT amount, LAG(COUNT(*)) OVER w AS n '
    + 'FROM records WHERE id > 0 GROUP BY amount WINDOW w AS (ORDER BY amount NULLS LAST) '
    + 'ORDER BY amount NULLS LAST', {columns: groupedColumns, expected: lagRows}),
  success('aggregate-operand-typed-empty', lagOperandSql,
    {columns: groupedColumns, sourceRows: [], expected: []}),
  success('aggregate-operand-parameter-offset', lagOperandSql.replace('LAG(COUNT(*))', 'LAG(COUNT(*), @increment)'),
    {...parameterInput, columns: groupedColumns, expected: lagRows}),
  success('aggregate-operand-reused-count', 'SELECT records.amount AS original, COUNT(*) AS amount, '
    + 'LAG(COUNT(*)) OVER (ORDER BY records.amount NULLS LAST) AS n FROM records WHERE id > 0 '
    + 'GROUP BY records.amount ORDER BY original NULLS LAST',
    {columns: [{name: 'original', contract: nullable}, {name: 'amount', contract: number}, {name: 'n', contract: nullable}],
      expected: [{original: 10, amount: 1, n: null}, {original: 20, amount: 2, n: 1}, {original: null, amount: 2, n: 2}]}),
  success('aggregate-operand-order-alias', operandOrderHead + 'amount' + operandOrderTail,
    {columns: [{name: 'original', contract: nullable}, {name: 'amount', contract: nullable}],
      expected: [{original: null, amount: null}, {original: 20, amount: -20}, {original: 10, amount: -10}]}),
  success('aggregate-operand-order-qualified-input', operandOrderHead + 'records.amount' + operandOrderTail,
    {columns: [{name: 'original', contract: nullable}, {name: 'amount', contract: nullable}],
      expected: [{original: 20, amount: -20}, {original: null, amount: null}, {original: 10, amount: -10}]}),
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
  {name: 'ordinary-aggregate-nesting', expectedCode: 'ClientProgramInvalidInput',
    text: 'SELECT SUM(SUM(id)) AS n FROM records'},
  {name: 'aggregate-operand-sibling-alias', expectedCode: 'ClientProgramInvalidInput',
    text: 'SELECT amount AS invented, LAG(SUM(invented)) OVER (ORDER BY id) AS n FROM records GROUP BY id, amount'},
  {name: 'aggregate-operand-pipe-implicit-group', format: 'aql-text', expectedCode: 'ClientProgramInvalidInput',
    text: 'FROM records |> SELECT LAG(COUNT(*)) OVER (ORDER BY id) AS n'},
  {name: 'aggregate-operand-missing-frame', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT SUM(SUM(id)) OVER (ORDER BY amount) AS n FROM records GROUP BY amount'},
  {name: 'aggregate-operand-row-offset', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT amount, LAG(COUNT(*), amount) OVER (ORDER BY amount) AS n FROM records GROUP BY amount'},
].map(item => ({format: 'sql', ...item, name: 'window-scalar-refuse-' + item.name}));
export const windowScalarExecutionFailures = [{name: 'window-scalar-demanded-error', format: 'sql',
  text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 / (id - 1) AS n FROM records WHERE id > 0 ORDER BY n',
  resultNames: ['answer'], sourceReadSessionCount: 1}];

// Pipe EXTEND preserves the current input columns and adds evaluated values.
export const pipeExtendWindowProgram = {version: 'actql/0.1', id: 'fixture.pipe_extend_window',
  stages: [structuredClone(windowScalarProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', analytic: {partition_by: [], order_by: [
        {field: 'amount', dir: 'desc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], functions: {n: {fn: 'row_number'}}}},
        {select: ['amount', 'id', 'n']},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['amount', 'id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const extendedColumns = [{name: 'amount', contract: nullable},
  {name: 'id', contract: number}, {name: 'n', contract: number}];
const extendedRows = [{amount: null, id: 1, n: 4}, {amount: 20, id: 2, n: 1},
  {amount: 10, id: 3, n: 3}, {amount: 20, id: 4, n: 2}, {amount: null, id: 5, n: 5}];
const extendHead = 'FROM records |> WHERE id > 0 |> EXTEND ';
const extendDirect = extendHead + `ROW_NUMBER() OVER (${window}) AS n |> ORDER BY id`;
windowScalarSuccesses.push(
  success('extend-json', JSON.stringify(pipeExtendWindowProgram),
    {format: 'json', columns: extendedColumns, expected: extendedRows}),
  success('extend-inline', extendDirect,
    {format: 'aql-text', columns: extendedColumns, expected: extendedRows}),
  success('extend-named', extendHead + 'ROW_NUMBER() OVER w AS n '
    + `WINDOW base AS (${window}), w AS (base) |> ORDER BY id`,
    {format: 'aql-text', columns: extendedColumns, expected: extendedRows}),
  success('extend-operand', extendHead + `ROW_NUMBER() OVER (${window}) + @increment AS n |> ORDER BY id`,
    {format: 'aql-text', ...parameterInput, columns: extendedColumns,
      expected: [{amount: null, id: 1, n: 5}, {amount: 20, id: 2, n: 2},
        {amount: 10, id: 3, n: 4}, {amount: 20, id: 4, n: 3}, {amount: null, id: 5, n: 6}]}),
  success('extend-empty', extendDirect,
    {format: 'aql-text', sourceRows: [], columns: extendedColumns, expected: []}),
  success('extend-filter-limit', extendHead + `ROW_NUMBER() OVER (${window}) AS n `
    + '|> WHERE n <= 2 |> SELECT id, n |> ORDER BY n |> LIMIT 1',
    {format: 'aql-text', expected: [{id: 2, n: 1}]}),
  success('extend-immutable-receiver', 'FROM records AS before |> WHERE id > 0 |> SET amount = -amount '
    + '|> EXTEND LAG(before.amount) OVER (ORDER BY id) AS before_amount, '
    + 'LAG(amount) OVER (ORDER BY id) AS after_amount |> SELECT id, before_amount, after_amount |> ORDER BY id',
    {format: 'aql-text', columns: [{name: 'id', contract: number},
      {name: 'before_amount', contract: nullable}, {name: 'after_amount', contract: nullable}],
      expected: [{id: 1, before_amount: null, after_amount: null},
        {id: 2, before_amount: null, after_amount: null},
        {id: 3, before_amount: 20, after_amount: -20},
        {id: 4, before_amount: 10, after_amount: -10},
        {id: 5, before_amount: 20, after_amount: -20}]}),
  success('extend-local-declarations', extendHead + 'ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id) '
    + '|> EXTEND RANK() OVER w AS reverse_pos WINDOW w AS (ORDER BY id DESC) '
    + '|> SELECT id, pos, reverse_pos |> ORDER BY id',
    {format: 'aql-text', columns: ['id', 'pos', 'reverse_pos'].map(name => ({name, contract: number})),
      expected: [{id: 1, pos: 1, reverse_pos: 5}, {id: 2, pos: 2, reverse_pos: 4},
        {id: 3, pos: 3, reverse_pos: 3}, {id: 4, pos: 4, reverse_pos: 2}, {id: 5, pos: 5, reverse_pos: 1}]}),
);
windowScalarRefusals.push(...[
  ['extend-existing-name', 'FROM records |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS id'],
  ['extend-sibling-alias', 'FROM records |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS n, n + 1 AS next'],
  ['extend-private-slot', 'FROM records |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS n'],
  ['extend-window-name-leak', 'FROM records |> EXTEND ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> EXTEND RANK() OVER w AS next'],
  ['extend-dropped-range', 'FROM records AS before |> AS current |> EXTEND LAG(before.amount) OVER (ORDER BY id) AS n'],
].map(([name, text]) => ({name: 'window-scalar-refuse-' + name, text,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})));
