// Independently authored GoogleSQL single-value UNPIVOT expectations. Common
// unpivot retains NULL; the source's default adds the ordinary exclusion filter.
const number = nullable => ({type: 'number', nullable});
const input = {id: number(false), jan: number(true), feb: number(true)};
const declarations = {rows: {type: 'array', nullable: false, max_items: 3,
  items: {type: 'object', nullable: false, fields: input}}};
const rows = [{id: 2, jan: 7, feb: null}, {id: 1, jan: null, feb: 5},
  {id: 2, jan: 7, feb: null}];
const columns = [{name: 'id', contract: number(false)},
  {name: 'amount', contract: number(true)},
  {name: 'month', contract: {type: 'string', nullable: false}}];
const excluded = [{id: 1, amount: 5, month: 'feb'},
  {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}];
const included = [{id: 1, amount: 5, month: 'feb'},
  {id: 1, amount: null, month: 'jan'},
  {id: 2, amount: null, month: 'feb'}, {id: 2, amount: null, month: 'feb'},
  {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}];
const head = 'FROM UNNEST(@rows) AS item |> SELECT item.id AS id, item.jan AS jan, item.feb AS feb';
const order = ' |> ORDER BY id, month';
function control(includeNulls) {
  const steps = [{values: {schema: input, rows}, as: 'wide'},
    {from: 'wide', unpivot: {columns: ['jan', 'feb'], keep: ['id'],
      name_column: 'month', value_column: 'amount'}}];
  if (!includeNulls) steps.push({filter: {not: {is_null: {field: 'amount'}}}});
  steps.push({sort: [{field: 'id', dir: 'asc', nulls: 'first'},
    {field: 'month', dir: 'asc', nulls: 'first'}]},
  {select: ['id', 'amount', 'month'], as: 'out'});
  return {version: 'actql/0.1', id: 'fixture.pipe_unpivot',
    stages: [{id: 'main', inputs: {}, steps,
      results: {rows: {from: 'out', fields: ['id', 'amount', 'month']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const success = (name, text, expected, extra = {}) => ({name: 'pipe-unpivot-' + name,
  format: 'aql-text', text, expected, columns, parameterDeclarations: declarations,
  parameters: {rows}, sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const pipeUnpivotSuccesses = [
  success('exclude-json-control', JSON.stringify(control(false)), excluded,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('include-json-control', JSON.stringify(control(true)), included,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('default', head + ' |> UNPIVOT(amount FOR month IN (jan,feb))' + order, excluded),
  success('explicit-exclude', head + ' |> UNPIVOT EXCLUDE NULLS(amount FOR month IN (jan,feb))' + order, excluded),
  success('include-and-range', head + ' |> UNPIVOT INCLUDE NULLS(amount FOR month IN (jan,feb)) AS reshaped |> SELECT reshaped.id, reshaped.amount, reshaped.month' + order, included),
  success('empty', head + ' |> UNPIVOT INCLUDE NULLS(amount FOR month IN (jan,feb))' + order,
    [], {parameters: {rows: []}}),
  success('current-slots-and-labels', head + ' |> SET jan = jan + 100 |> RENAME feb AS february |> UNPIVOT INCLUDE NULLS(amount FOR month IN (jan,february))' + order,
    [{id: 1, amount: 5, month: 'february'}, {id: 1, amount: null, month: 'jan'},
      {id: 2, amount: null, month: 'february'}, {id: 2, amount: null, month: 'february'},
      {id: 2, amount: 107, month: 'jan'}, {id: 2, amount: 107, month: 'jan'}]),
];
export const pipeUnpivotRefusals = [
  {name: 'removed-input', suffix: ' |> UNPIVOT(amount FOR month IN (jan,feb)) |> SELECT jan'},
  {name: 'old-range', suffix: ' |> AS old |> UNPIVOT(amount FOR month IN (jan,feb)) |> SELECT old.id'},
  {name: 'generated-name-collision', suffix: ' |> UNPIVOT(amount FOR AMOUNT IN (jan,feb))'},
  {name: 'incompatible-nullability', suffix: ' |> UNPIVOT(amount FOR month IN (id,jan))'},
  {name: 'incompatible-types', suffix: " |> EXTEND 'text' AS label |> UNPIVOT(amount FOR month IN (label,jan))"},
  {name: 'qualified-input', suffix: ' |> UNPIVOT(amount FOR month IN (item.jan))'},
].map(({name, suffix}) => ({name: 'pipe-unpivot-refusal-' + name, text: head + suffix,
  format: 'aql-text', parameterDeclarations: declarations, parameters: {rows},
  expectedCode: 'ClientProgramInvalidInput'}));
