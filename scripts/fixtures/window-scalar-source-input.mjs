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
  {name: 'aggregate-operand-row-offset', expectedCode: 'ClientProgramInvalidInput',
    text: 'SELECT amount, LAG(COUNT(*), amount) OVER (ORDER BY amount) AS n FROM records GROUP BY amount'},
].map(item => ({format: 'sql', ...item, name: 'window-scalar-refuse-' + item.name}));
export const windowScalarExecutionFailures = [{name: 'window-scalar-demanded-error', format: 'sql',
  text: 'SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 / (id - 1) AS n FROM records WHERE id > 0 ORDER BY n',
  resultNames: ['main'], sourceReadSessionCount: 1}];

// Star names supplied by the checked parameter schema need not be source
// tokens. The public column value is deliberately unrelated to the rank.
const selectPrivateField = 'aql_select_window_0';
const selectPrivateUpper = 'AQL_SELECT_WINDOW_0';
const selectPrivateDeclarations = field => ({items: {type: 'array', nullable: false,
  max_items: 3, items: {type: 'object', nullable: false,
    fields: {id: number, [field]: nullable}}}});
const selectPrivateRows = field => [{id: 2, [field]: 10}, {id: 1, [field]: 90}];
export const selectPrivateWindowProgram = field => ({version: 'actql/0.1',
  id: 'fixture.select_private_window', params: selectPrivateDeclarations(field),
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {items: {$param: 'items'}}},
    {unnest: {column: 'items', as: 'element'}},
    {derive: {id: {property: {name: 'id', value: {field: 'element'}}},
      [field]: {property: {name: field, value: {field: 'element'}}}}},
    {select: [field, 'id'], as: 'original'},
    {from: 'original', analytic: {partition_by: [], order_by: [
      {field: 'id', dir: 'asc', nulls: 'first'}], functions: {private_rank: {fn: 'row_number'}}}},
    {derive: {pos: {add: [{field: 'private_rank'}, {literal: 1}]}}},
    {select: [field, 'id', 'pos']},
    {sort: [{field: 'id', dir: 'desc', nulls: 'last'}], as: 'out'}],
    results: {rows: {from: 'out', fields: [field, 'id', 'pos']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});
const selectPrivateSql = 'SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM UNNEST(@items) e';
const selectPrivatePipe = 'FROM UNNEST(@items) e |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos';
const selectPrivateExpected = field => [{[field]: 10, id: 2, pos: 3}, {[field]: 90, id: 1, pos: 2}];
const selectPrivateSuccess = (name, field, text, extra = {}) => success('schema-private-' + name, text, {
  parameterDeclarations: selectPrivateDeclarations(field), parameters: {items: selectPrivateRows(field)},
  expected: selectPrivateExpected(field), columns: [{name: field, contract: nullable},
    {name: 'id', contract: number}, {name: 'pos', contract: number}],
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
windowScalarSuccesses.push(
  selectPrivateSuccess('json', selectPrivateField, JSON.stringify(selectPrivateWindowProgram(selectPrivateField)),
    {format: 'json', parameterDeclarations: undefined}),
  selectPrivateSuccess('upper-json', selectPrivateUpper, JSON.stringify(selectPrivateWindowProgram(selectPrivateUpper)),
    {format: 'json', parameterDeclarations: undefined}),
  selectPrivateSuccess('sql', selectPrivateField, selectPrivateSql + ' ORDER BY id DESC'),
  selectPrivateSuccess('pipe', selectPrivateField, selectPrivatePipe + ' |> ORDER BY id DESC', {format: 'aql-text'}),
  selectPrivateSuccess('upper-pipe', selectPrivateUpper, selectPrivatePipe + ' |> ORDER BY id DESC', {format: 'aql-text'}),
  selectPrivateSuccess('group-all', selectPrivateField, selectPrivateSql + ' GROUP BY ALL ORDER BY id DESC'),
  selectPrivateSuccess('named', selectPrivateField,
    selectPrivatePipe.replace('OVER (ORDER BY id)', 'OVER w') + ' WINDOW w AS (ORDER BY id) |> ORDER BY id DESC',
    {format: 'aql-text'}),
  selectPrivateSuccess('nullable', selectPrivateField, selectPrivatePipe + ' |> ORDER BY id DESC', {
    format: 'aql-text', parameters: {items: [{id: 2, [selectPrivateField]: null}, {id: 1, [selectPrivateField]: 90}]},
    expected: [{[selectPrivateField]: null, id: 2, pos: 3}, {[selectPrivateField]: 90, id: 1, pos: 2}]}),
  selectPrivateSuccess('empty', selectPrivateField, selectPrivatePipe + ' |> ORDER BY id DESC',
    {format: 'aql-text', parameters: {items: []}, expected: []}),
  selectPrivateSuccess('duplicates', selectPrivateField, selectPrivatePipe + ' |> ORDER BY id DESC, pos DESC', {
    format: 'aql-text', parameters: {items: [...selectPrivateRows(selectPrivateField), {id: 2, [selectPrivateField]: 10}]},
    expected: [{[selectPrivateField]: 10, id: 2, pos: 4}, {[selectPrivateField]: 10, id: 2, pos: 3},
      {[selectPrivateField]: 90, id: 1, pos: 2}]}),
  selectPrivateSuccess('authored-over-key', selectPrivateField,
    selectPrivatePipe.replace('ORDER BY id)', 'ORDER BY aql_select_window_0)') + ' |> ORDER BY id DESC',
    {format: 'aql-text', expected: [{[selectPrivateField]: 10, id: 2, pos: 2}, {[selectPrivateField]: 90, id: 1, pos: 3}]}),
  selectPrivateSuccess('qualified-user-value', selectPrivateField,
    selectPrivatePipe.replace('+ 1 AS pos', '+ r.aql_select_window_0 AS pos') + ' |> ORDER BY id DESC',
    {format: 'aql-text', columns: [{name: selectPrivateField, contract: nullable},
      {name: 'id', contract: number}, {name: 'pos', contract: nullable}],
      expected: [{[selectPrivateField]: 10, id: 2, pos: 12}, {[selectPrivateField]: 90, id: 1, pos: 91}]}),
);
windowScalarRefusals.push({name: 'window-scalar-refuse-schema-private-slot', format: 'aql-text',
  text: selectPrivatePipe + ' |> SELECT id, aql_analytic_output_3 AS leaked',
  parameterDeclarations: selectPrivateDeclarations(selectPrivateField), parameters: {items: selectPrivateRows(selectPrivateField)},
  expectedCode: 'ClientProgramInvalidInput'});

// QUALIFY demands the same evaluated SELECT value that final projection uses.
// The ordinary Program control computes that value once, then filters it.
export const qualifyPrivateWindowProgram = field => {
  const program = selectPrivateWindowProgram(field);
  program.id = 'fixture.qualify_private_window';
  program.stages[0].steps.splice(7, 0, {filter: {gt: [{field: 'pos'}, {literal: 2}]}});
  return program;
};
const qualifyPrivateSql = selectPrivateSql + ' QUALIFY pos > 2 ORDER BY id DESC';
const qualifyPrivateSuccess = (name, field = selectPrivateField, extra = {}) =>
  selectPrivateSuccess('qualify-' + name, field, qualifyPrivateSql, {
    expected: [{[field]: 10, id: 2, pos: 3}], ...extra});
windowScalarSuccesses.push(
  qualifyPrivateSuccess('json', selectPrivateField, {
    text: JSON.stringify(qualifyPrivateWindowProgram(selectPrivateField)), format: 'json', parameterDeclarations: undefined}),
  qualifyPrivateSuccess('upper-json', selectPrivateUpper, {
    text: JSON.stringify(qualifyPrivateWindowProgram(selectPrivateUpper)), format: 'json', parameterDeclarations: undefined}),
  qualifyPrivateSuccess('sql'),
  qualifyPrivateSuccess('upper-sql', selectPrivateUpper),
  qualifyPrivateSuccess('group-all', selectPrivateField, {
    text: selectPrivateSql + ' GROUP BY ALL QUALIFY pos > 2 ORDER BY id DESC'}),
  qualifyPrivateSuccess('upper-group-all', selectPrivateUpper, {
    text: selectPrivateSql + ' GROUP BY ALL QUALIFY pos > 2 ORDER BY id DESC'}),
  qualifyPrivateSuccess('named-quoted', selectPrivateField, {
    text: selectPrivateSql.replace('OVER (ORDER BY id)', 'OVER w').replace('AS pos', 'AS `pos`')
      + ' QUALIFY `pos` > 2 WINDOW w AS (ORDER BY id) ORDER BY id DESC'}),
  qualifyPrivateSuccess('nullable', selectPrivateField, {
    parameters: {items: [{id: 2, [selectPrivateField]: null}, {id: 1, [selectPrivateField]: 90}]},
    expected: [{[selectPrivateField]: null, id: 2, pos: 3}]}),
  qualifyPrivateSuccess('empty', selectPrivateField, {parameters: {items: []}, expected: []}),
  qualifyPrivateSuccess('duplicates', selectPrivateField, {
    text: selectPrivateSql + ' QUALIFY pos > 2 ORDER BY id DESC, pos DESC',
    parameters: {items: [...selectPrivateRows(selectPrivateField), {id: 2, [selectPrivateField]: 10}]},
    expected: [{[selectPrivateField]: 10, id: 2, pos: 4}, {[selectPrivateField]: 10, id: 2, pos: 3}]}),
  qualifyPrivateSuccess('qualified-user', selectPrivateField, {
    text: 'SELECT *, ROW_NUMBER() OVER (ORDER BY e.id) + e.aql_select_window_0 AS pos FROM UNNEST(@items) e '
      + 'QUALIFY pos > 50 ORDER BY id DESC',
    columns: [{name: selectPrivateField, contract: nullable}, {name: 'id', contract: number}, {name: 'pos', contract: nullable}],
    expected: [{[selectPrivateField]: 90, id: 1, pos: 91}]}),
);
for (const [name, text, expectedCode] of [
  ['private-slot', selectPrivateSql + ' QUALIFY pos > 2 ORDER BY aql_qualify_expr_4', 'ClientProgramInvalidInput'],
  ['window-alias-input', selectPrivateSql + ' ORDER BY ROW_NUMBER() OVER (ORDER BY pos)', 'ClientProgramImplementationLimit'],
]) windowScalarRefusals.push({name: 'window-scalar-refuse-schema-private-qualify-' + name, text, format: 'sql',
  parameterDeclarations: selectPrivateDeclarations(selectPrivateField), parameters: {items: selectPrivateRows(selectPrivateField)},
  expectedCode});

// Independent controls for the three Pipe consumers. The input user value
// must survive; only the separate evaluated rank drives filtering/updates.
const pipePrivateFields = {where: 'aql_pipe_where_window_0', extend: 'aql_select_window_0',
  set: 'aql_pipe_set_window_0'};
export function pipePrivateWindowProgram(kind, field = pipePrivateFields[kind]) {
  const base = selectPrivateWindowProgram(field);
  const inputs = structuredClone(base.stages[0].steps.slice(0, 5));
  const steps = [...inputs, {from: 'original', analytic: {partition_by: [], order_by: [
    {field: 'id', dir: 'asc', nulls: 'first'}], functions: {private_rank: {fn: 'row_number'}}}}];
  let fields = [field, 'id'];
  if (kind === 'where') steps.push({filter: {eq: [{field: 'private_rank'}, {literal: 1}]}});
  else if (kind === 'extend') {
    steps.push({derive: {pos: {add: [{field: 'private_rank'}, {literal: 1}]}}});
    fields = [...fields, 'pos'];
  } else if (kind === 'set') steps.push({derive: {assigned_id: {add: [{field: 'private_rank'}, {literal: 10}]}}});
  else throw new Error('unknown independent Pipe window control');
  steps.push({select: kind === 'set' ? [field, {id: 'assigned_id'}] : fields},
    {sort: [{field: 'id', dir: 'desc', nulls: 'last'}], as: 'out'});
  return {version: 'actql/0.1', id: 'fixture.pipe_private_window', params: selectPrivateDeclarations(field),
    stages: [{id: 'main', inputs: {}, steps, results: {rows: {from: 'out', fields}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const pipePrivateOperations = {
  where: 'WHERE ROW_NUMBER() OVER (ORDER BY id) = 1',
  extend: 'EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos',
  set: 'SET id = ROW_NUMBER() OVER (ORDER BY id) + 10',
};
const pipePrivateHead = 'FROM UNNEST(@items) e |> AS r |> ';
// SET edits ordinary columns, not implicit members of a value table.
const pipePrivateSetHead = 'FROM UNNEST(@items) e |> SELECT * |> AS r |> ';
const pipePrivateInput = kind => kind === 'set' ? pipePrivateSetHead : pipePrivateHead;
const pipePrivateExpected = (kind, field) => kind === 'where' ? [{[field]: 90, id: 1}]
  : kind === 'extend' ? [{[field]: 10, id: 2, pos: 3}, {[field]: 90, id: 1, pos: 2}]
    : [{[field]: 10, id: 12}, {[field]: 90, id: 11}];
const pipePrivateSuccess = (name, kind, field = pipePrivateFields[kind], extra = {}) =>
  success('pipe-schema-private-' + name, pipePrivateInput(kind) + pipePrivateOperations[kind] + ' |> ORDER BY id DESC', {
    format: 'aql-text', parameterDeclarations: selectPrivateDeclarations(field), parameters: {items: selectPrivateRows(field)},
    expected: pipePrivateExpected(kind, field), columns: [{name: field, contract: nullable}, {name: 'id', contract: number},
      ...(kind === 'extend' ? [{name: 'pos', contract: number}] : [])],
    sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
for (const kind of ['where', 'extend', 'set']) {
  const field = pipePrivateFields[kind];
  windowScalarSuccesses.push(
    pipePrivateSuccess(kind + '-json', kind, field, {format: 'json', parameterDeclarations: undefined,
      text: JSON.stringify(pipePrivateWindowProgram(kind))}),
    pipePrivateSuccess(kind, kind),
    pipePrivateSuccess(kind + '-uppercase', kind, field.toUpperCase()),
  );
  const slot = kind === 'extend' ? 'aql_analytic_output_3' : 'aql_analytic_output_2';
  windowScalarRefusals.push({name: 'window-scalar-refuse-pipe-schema-private-' + kind, format: 'aql-text',
    text: pipePrivateInput(kind) + pipePrivateOperations[kind] + ' |> SELECT ' + slot,
    parameterDeclarations: selectPrivateDeclarations(field), parameters: {items: selectPrivateRows(field)},
    expectedCode: 'ClientProgramInvalidInput'});
}
windowScalarSuccesses.push(
  pipePrivateSuccess('where-nullable', 'where', undefined, {
    parameters: {items: [{id: 2, aql_pipe_where_window_0: 10}, {id: 1, aql_pipe_where_window_0: null}]},
    expected: [{aql_pipe_where_window_0: null, id: 1}]}),
  pipePrivateSuccess('set-empty', 'set', undefined, {parameters: {items: []}, expected: []}),
  pipePrivateSuccess('set-immutable', 'set', undefined, {
    text: pipePrivateSetHead + pipePrivateOperations.set + ' |> SELECT r.id AS original, * |> ORDER BY id DESC',
    columns: [{name: 'original', contract: number}, {name: 'aql_pipe_set_window_0', contract: nullable}, {name: 'id', contract: number}],
    expected: [{original: 2, aql_pipe_set_window_0: 10, id: 12}, {original: 1, aql_pipe_set_window_0: 90, id: 11}]}),
  pipePrivateSuccess('extend-authored-key', 'extend', undefined, {
    text: pipePrivateHead + 'EXTEND ROW_NUMBER() OVER (ORDER BY aql_select_window_0) + 1 AS pos |> ORDER BY id DESC',
    expected: [{aql_select_window_0: 10, id: 2, pos: 2}, {aql_select_window_0: 90, id: 1, pos: 3}]}),
);

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

// Named Pipe SELECT uses the same independent ordinary Analytic Program.
export const pipeSelectNamedWindowProgram = {version: 'actql/0.1', id: 'fixture.pipe_select_named_window',
  stages: [structuredClone(windowScalarProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', analytic: {partition_by: [], order_by: [
        {field: 'amount', dir: 'desc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], functions: {n: {fn: 'row_number'}}}},
        {select: ['id', 'n']}, {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const namedRows = [{id: 1, n: 4}, {id: 2, n: 1}, {id: 3, n: 3}, {id: 4, n: 2}, {id: 5, n: 5}];
const namedSelectHead = 'FROM records |> WHERE id > 0 |> SELECT ';
const namedSelectDirect = namedSelectHead + `id, ROW_NUMBER() OVER w AS n WINDOW w AS (${window}) |> ORDER BY id`;
windowScalarSuccesses.push(
  success('pipe-named-json', JSON.stringify(pipeSelectNamedWindowProgram), {format: 'json', expected: namedRows}),
  success('pipe-named-direct', namedSelectDirect, {format: 'aql-text', expected: namedRows}),
  success('pipe-named-operand', namedSelectHead + `id, ROW_NUMBER() OVER w + @increment AS n WINDOW w AS (${window}) |> ORDER BY id`,
    {format: 'aql-text', ...parameterInput}),
  success('pipe-named-empty', namedSelectDirect, {format: 'aql-text', sourceRows: [], expected: []}),
  success('pipe-named-quoted-inheritance', namedSelectHead + 'id, ROW_NUMBER() OVER (`W`) AS n '
    + `WINDOW base AS (${window}), w AS base |> ORDER BY id`, {format: 'aql-text', expected: namedRows}),
  success('pipe-named-local-declarations', namedSelectHead + 'id, ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id) '
    + '|> SELECT id, pos, RANK() OVER w AS reverse_pos WINDOW w AS (ORDER BY id DESC) |> ORDER BY id',
    {format: 'aql-text', columns: ['id', 'pos', 'reverse_pos'].map(name => ({name, contract: number})),
      expected: [{id: 1, pos: 1, reverse_pos: 5}, {id: 2, pos: 2, reverse_pos: 4},
        {id: 3, pos: 3, reverse_pos: 3}, {id: 4, pos: 4, reverse_pos: 2}, {id: 5, pos: 5, reverse_pos: 1}]}),
  success('pipe-named-star-replace', namedSelectHead + `* REPLACE (ROW_NUMBER() OVER w AS amount) WINDOW w AS (${window}) |> ORDER BY id`,
    {format: 'aql-text', columns: ['amount', 'id'].map(name => ({name, contract: number})),
      expected: [{amount: 4, id: 1}, {amount: 1, id: 2}, {amount: 3, id: 3}, {amount: 2, id: 4}, {amount: 5, id: 5}]}),
  success('pipe-named-nullable', namedSelectHead + 'id, LAG(amount) OVER w + 1 AS n WINDOW w AS (ORDER BY id) |> ORDER BY id',
    {format: 'aql-text', columns: [{name: 'id', contract: number}, {name: 'n', contract: nullable}],
      expected: [{id: 1, n: null}, {id: 2, n: null}, {id: 3, n: 21}, {id: 4, n: 11}, {id: 5, n: 21}]}),
);
windowScalarRefusals.push(...[
  ['pipe-named-window-leak', 'FROM records |> SELECT id, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> SELECT ROW_NUMBER() OVER w AS next'],
  ['pipe-named-duplicate', 'FROM records |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id), `W` AS (ORDER BY amount)'],
  ['pipe-named-sibling-key', 'FROM records |> SELECT amount AS invented, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY invented)'],
  ['pipe-named-dropped-range', 'FROM records AS old |> AS current |> SELECT LAG(old.amount) OVER w AS n WINDOW w AS (ORDER BY id)'],
  ['pipe-named-private-slot', 'FROM records |> SELECT ROW_NUMBER() OVER w + aql_select_window_0 AS n WINDOW w AS (ORDER BY id)'],
].map(([name, text]) => ({name: 'window-scalar-refuse-' + name, text,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})));

// Predicate-only windows retain the current row; no private column is exported.
export const pipeWhereWindowProgram = {version: 'actql/0.1', id: 'fixture.pipe_where_window',
  stages: [structuredClone(windowScalarProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', analytic: {partition_by: [], order_by: [
        {field: 'amount', dir: 'desc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], functions: {position: {fn: 'row_number'}}}},
        {filter: {lte: [{field: 'position'}, {literal: 3}]}},
        {select: ['amount', 'id']}, {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const whereColumns = [{name: 'amount', contract: nullable}, {name: 'id', contract: number}];
const whereRows = [{amount: 20, id: 2}, {amount: 10, id: 3}, {amount: 20, id: 4}];
const whereWindowHead = 'FROM records |> WHERE id > 0 |> WHERE ';
const whereWindowDirect = whereWindowHead + `ROW_NUMBER() OVER (${window}) <= 3 |> ORDER BY id`;
windowScalarSuccesses.push(
  success('where-window-json', JSON.stringify(pipeWhereWindowProgram), {format: 'json', columns: whereColumns, expected: whereRows}),
  success('where-window-direct', whereWindowDirect, {format: 'aql-text', columns: whereColumns, expected: whereRows}),
  success('where-window-parameter', whereWindowHead + `ROW_NUMBER() OVER (${window}) <= @top |> ORDER BY id`,
    {format: 'aql-text', parameterDeclarations: {top: number}, parameters: {top: 2}, columns: whereColumns,
      expected: [{amount: 20, id: 2}, {amount: 20, id: 4}]}),
  success('where-window-empty', whereWindowDirect, {format: 'aql-text', sourceRows: [], columns: whereColumns, expected: []}),
  success('where-window-nullable', whereWindowHead + 'LAG(amount) OVER (ORDER BY id) > 15 |> ORDER BY id',
    {format: 'aql-text', columns: whereColumns, expected: [{amount: 10, id: 3}, {amount: null, id: 5}]}),
  success('where-window-multiple', whereWindowHead + `ROW_NUMBER() OVER (${window}) <= 3 AND ROW_NUMBER() OVER (ORDER BY id) <= 3 |> ORDER BY id`,
    {format: 'aql-text', columns: whereColumns, expected: [{amount: 20, id: 2}, {amount: 10, id: 3}]}),
  success('where-window-sequential', whereWindowHead + `ROW_NUMBER() OVER (${window}) <= 3 |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> ORDER BY id`,
    {format: 'aql-text', columns: whereColumns, expected: [{amount: 20, id: 2}]}),
  success('where-window-immutable-range', 'FROM records AS before |> WHERE id > 0 |> SET amount = -amount '
    + '|> WHERE LAG(before.amount) OVER (ORDER BY id) > 15 |> ORDER BY id',
    {format: 'aql-text', columns: whereColumns, expected: [{amount: -10, id: 3}, {amount: null, id: 5}]}),
  success('where-window-authored-private-name', 'FROM records |> WHERE id > 0 |> EXTEND amount AS aql_pipe_where_window_0 '
    + '|> WHERE ROW_NUMBER() OVER (ORDER BY id) <= 2 |> SELECT id, aql_pipe_where_window_0 AS n |> ORDER BY id',
    {format: 'aql-text', columns: [{name: 'id', contract: number}, {name: 'n', contract: nullable}],
      expected: [{id: 1, n: null}, {id: 2, n: 20}]}),
);
windowScalarRefusals.push(...[
  ['where-window-missing-input', 'FROM records |> WHERE LAG(missing) OVER (ORDER BY id) > 0'],
  ['where-window-projected-input', 'FROM records |> SELECT id |> WHERE LAG(amount) OVER (ORDER BY id) > 0'],
  ['where-window-private-slot', 'FROM records |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> SELECT aql_pipe_where_window_0'],
  ['where-window-dropped-range', 'FROM records AS old |> AS current |> WHERE LAG(old.amount) OVER (ORDER BY id) > 0'],
  ['where-window-declaration-leak', 'FROM records |> SELECT id, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> WHERE ROW_NUMBER() OVER w = 1'],
].map(([name, text]) => ({name: 'window-scalar-refuse-' + name, text,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})),
{name: 'window-scalar-refuse-where-window-missing-frame', format: 'aql-text',
  text: 'FROM records |> WHERE SUM(amount) OVER (ORDER BY id) > 0', expectedCode: 'ClientProgramImplementationLimit'});

// Independent SET control keeps the captured row and replaces only amount.
export const pipeSetWindowProgram = {version: 'actql/0.1', id: 'fixture.pipe_set_window',
  stages: [structuredClone(windowScalarProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', analytic: {partition_by: [], order_by: [
        {field: 'amount', dir: 'desc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], functions: {position: {fn: 'row_number'}}}},
        {derive: {next_amount: {field: 'position'}}},
        {select: [{amount: 'next_amount'}, 'id']},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const setColumns = ['amount', 'id'].map(name => ({name, contract: number}));
const setRows = [{amount: 4, id: 1}, {amount: 1, id: 2}, {amount: 3, id: 3},
  {amount: 2, id: 4}, {amount: 5, id: 5}];
const setWindowHead = 'FROM records |> WHERE id > 0 |> SET amount = ';
const setWindowDirect = setWindowHead + `ROW_NUMBER() OVER (${window}) |> ORDER BY id`;
windowScalarSuccesses.push(
  success('set-window-json', JSON.stringify(pipeSetWindowProgram), {format: 'json', columns: setColumns, expected: setRows}),
  success('set-window-direct', setWindowDirect, {format: 'aql-text', columns: setColumns, expected: setRows}),
  success('set-window-operand', setWindowHead + `ROW_NUMBER() OVER (${window}) + 1 |> ORDER BY id`,
    {format: 'aql-text', columns: setColumns, expected: setRows.map(row => ({...row, amount: row.amount + 1}))}),
  success('set-window-parameter', setWindowHead + `ROW_NUMBER() OVER (${window}) + @increment |> ORDER BY id`,
    {format: 'aql-text', ...parameterInput, columns: setColumns, expected: setRows.map(row => ({...row, amount: row.amount + 1}))}),
  success('set-window-empty', setWindowDirect, {format: 'aql-text', sourceRows: [], columns: setColumns, expected: []}),
  success('set-window-nullable', setWindowHead + 'LAG(amount) OVER (ORDER BY id) |> ORDER BY id',
    {format: 'aql-text', columns: whereColumns, expected: [{amount: null, id: 1}, {amount: null, id: 2},
      {amount: 20, id: 3}, {amount: 10, id: 4}, {amount: 20, id: 5}]}),
  success('set-window-sibling-input', 'FROM records |> WHERE id > 0 '
    + '|> SET amount = ROW_NUMBER() OVER (ORDER BY id), id = amount |> ORDER BY amount',
    {format: 'aql-text', columns: [{name: 'amount', contract: number}, {name: 'id', contract: nullable}],
      expected: [{amount: 1, id: null}, {amount: 2, id: 20}, {amount: 3, id: 10}, {amount: 4, id: 20}, {amount: 5, id: null}]}),
  success('set-window-immutable-range', 'FROM records AS before |> WHERE id > 0 '
    + '|> SET amount = ROW_NUMBER() OVER (ORDER BY id) |> SELECT id, before.amount AS original, amount |> ORDER BY id',
    {format: 'aql-text', columns: [{name: 'id', contract: number}, {name: 'original', contract: nullable}, {name: 'amount', contract: number}],
      expected: [{id: 1, original: null, amount: 1}, {id: 2, original: 20, amount: 2}, {id: 3, original: 10, amount: 3},
        {id: 4, original: 20, amount: 4}, {id: 5, original: null, amount: 5}]}),
  success('set-window-authored-private-name', 'FROM records |> WHERE id > 0 |> EXTEND amount AS aql_pipe_set_window_0 '
    + '|> SET amount = ROW_NUMBER() OVER (ORDER BY id) + aql_pipe_set_window_0 |> SELECT id, amount |> ORDER BY id',
    {format: 'aql-text', columns: [{name: 'id', contract: number}, {name: 'amount', contract: nullable}],
      expected: [{id: 1, amount: null}, {id: 2, amount: 22}, {id: 3, amount: 13}, {id: 4, amount: 24}, {id: 5, amount: null}]}),
);
windowScalarRefusals.push(...[
  ['set-window-missing-target', 'FROM records |> SET missing = ROW_NUMBER() OVER (ORDER BY id)'],
  ['set-window-duplicate-target', 'FROM records |> SET amount = ROW_NUMBER() OVER (ORDER BY id), amount = 1'],
  ['set-window-missing-input', 'FROM records |> SET amount = LAG(missing) OVER (ORDER BY id)'],
  ['set-window-projected-input', 'FROM records |> SELECT id |> SET id = LAG(amount) OVER (ORDER BY id)'],
  ['set-window-dropped-range', 'FROM records AS old |> AS current |> SET amount = LAG(old.amount) OVER (ORDER BY id)'],
  ['set-window-private-slot', 'FROM records |> SET amount = ROW_NUMBER() OVER (ORDER BY id) |> SELECT aql_pipe_set_window_0'],
  ['set-window-declaration-leak', 'FROM records |> SELECT id, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> SET id = ROW_NUMBER() OVER w'],
].map(([name, text]) => ({name: 'window-scalar-refuse-' + name, text,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})),
{name: 'window-scalar-refuse-set-window-missing-frame', format: 'aql-text',
  text: 'FROM records |> SET amount = SUM(amount) OVER (ORDER BY id)', expectedCode: 'ClientProgramImplementationLimit'});

windowScalarRefusals.push({name: 'window-scalar-refuse-implicit-member-set', format: 'aql-text',
  text: pipePrivateHead + pipePrivateOperations.set + ' |> ORDER BY id DESC',
  parameterDeclarations: selectPrivateDeclarations(pipePrivateFields.set),
  parameters: {items: selectPrivateRows(pipePrivateFields.set)},
  expectedCode: 'ClientProgramInvalidInput'});
