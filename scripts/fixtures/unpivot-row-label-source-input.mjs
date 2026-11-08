// Independent GoogleSQL row-value-alias obligations; no product lowering is
// imported. A repeated input occurrence must retain its own literal label.
const number = nullable => ({type: 'number', nullable});
const schema = {id: number(false), jan: number(true), feb: number(true)};
const rows = [{id: 2, jan: 7, feb: null}, {id: 1, jan: null, feb: 5},
  {id: 2, jan: 7, feb: null}];
const declarations = {rows: {type: 'array', nullable: false, max_items: 3,
  items: {type: 'object', nullable: false, fields: schema}}};
const columns = [{name: 'id', contract: number(false)},
  {name: 'amount', contract: number(true)},
  {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}}];
// Literal String contracts keep their authored maximum UTF-8 length, including
// typed empty Results. The three label sets have bounds 6, 7 and 4 respectively.
const labelColumns = max => [...columns.slice(0, 2),
  {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: max}}];
const repeated = [{id: 1, amount: null, month: 'first'},
  {id: 1, amount: null, month: 'second'},
  {id: 2, amount: 7, month: 'first'}, {id: 2, amount: 7, month: 'first'},
  {id: 2, amount: 7, month: 'second'}, {id: 2, amount: 7, month: 'second'}];
const same = [{id: 1, amount: null, month: 'same'},
  {id: 1, amount: null, month: 'same'},
  {id: 2, amount: 7, month: 'same'}, {id: 2, amount: 7, month: 'same'},
  {id: 2, amount: 7, month: 'same'}, {id: 2, amount: 7, month: 'same'}];
const renamed = [{id: 1, amount: 5, month: 'current'},
  {id: 1, amount: null, month: 'first'},
  {id: 2, amount: null, month: 'current'}, {id: 2, amount: null, month: 'current'},
  {id: 2, amount: 7, month: 'first'}, {id: 2, amount: 7, month: 'first'}];
const wide = '(SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item)';
const clause = "UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'first',jan 'second'))";
const control = {version: 'actql/0.1', id: 'fixture.unpivot_row_labels',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema, rows}, as: 'wide'},
    {from: 'wide', select: ['id', 'feb', {first_input: 'jan'}, {second_input: 'jan'}]},
    {unpivot: {columns: ['first_input', 'second_input'], keep: ['id', 'feb'],
      value_column: 'amount', name_column: 'private_name'}},
    {derive: {month: {if: [{eq: [{field: 'private_name'}, {literal: 'first_input'}]},
      {literal: 'first'}, {literal: 'second'}]}}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'},
      {field: 'month', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'amount', 'month'], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['id', 'amount', 'month']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, extra = {}) => ({name: 'unpivot-row-label-' + name,
  format: 'aql-text', text, expected, columns, parameterDeclarations: declarations,
  parameters: {rows}, sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const unpivotRowLabelSuccesses = [
  success('json-control', JSON.stringify(control), repeated,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('from-repeated', `SELECT id,amount,month FROM ${wide} ${clause} ORDER BY id,month`, repeated),
  success('pipe-excluded', `FROM ${wide} |> UNPIVOT(amount FOR month IN(jan AS 'first',jan AS 'second')) |> SELECT id,amount,month |> ORDER BY id,month`, repeated.slice(2)),
  success('renamed-default', `FROM ${wide} |> RENAME feb AS current |> UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'first',current)) |> SELECT id,amount,month |> ORDER BY id,month`, renamed, {columns: labelColumns(7)}),
  success('empty', `SELECT id,amount,month FROM ${wide} ${clause} ORDER BY id,month`, [], {parameters: {rows: []}}),
  success('same-label', `SELECT id,amount,month FROM ${wide} UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'same',jan AS 'same')) ORDER BY id,month`, same, {columns: labelColumns(4)}),
];
export const unpivotRowLabelRefusals = [
  {name: 'old-range', text: `SELECT original.id FROM ${wide} original ${clause} shaped`},
  {name: 'consumed-input', text: `SELECT jan FROM ${wide} ${clause}`},
  {name: 'expression-label', text: `SELECT * FROM ${wide} UNPIVOT(amount FOR month IN(jan AS 'a' || 'b'))`},
  {name: 'mixed-types', text: `SELECT * FROM ${wide} UNPIVOT(amount FOR month IN(jan AS 1,feb AS 'b'))`},
  // Above the selected exact Number integer domain: syntax refuses without
  // rounding. Safe integer labels have a separate unsupported lowering gap.
  {name: 'exact-integer-gap', text: `SELECT * FROM ${wide} UNPIVOT(amount FOR month IN(jan AS 9223372036854775807,feb AS 1))`, expectedCode: 'ClientProgramInvalidInput'},
].map(item => ({...item, name: 'unpivot-row-label-refusal-' + item.name,
  format: 'aql-text', parameterDeclarations: declarations, parameters: {rows},
  expectedCode: item.expectedCode ?? 'ClientProgramInvalidInput'}));
