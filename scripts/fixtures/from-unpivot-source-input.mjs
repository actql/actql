// Independent single-value GoogleSQL UNPIVOT obligations. The JSON controls
// and expected rows are authored from the selected operation, not lowering.
const number = nullable => ({type: 'number', nullable});
const input = {id: number(false), jan: number(true), feb: number(true)};
const rows = [{id: 2, jan: 7, feb: null}, {id: 1, jan: null, feb: 5},
  {id: 2, jan: 7, feb: null}];
const declarations = {rows: {type: 'array', nullable: false, max_items: 3,
  items: {type: 'object', nullable: false, fields: input}}};
const columns = [{name: 'id', contract: number(false)},
  {name: 'amount', contract: number(true)},
  {name: 'month', contract: {type: 'string', nullable: false}}];
const excluded = [{id: 1, amount: 5, month: 'feb'},
  {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}];
const included = [{id: 1, amount: 5, month: 'feb'}, {id: 1, amount: null, month: 'jan'},
  {id: 2, amount: null, month: 'feb'}, {id: 2, amount: null, month: 'feb'},
  {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}];
const wide = '(SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item)';
const include = 'UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb))';
function control(includeNulls) {
  const steps = [{values: {schema: input, rows}, as: 'wide'},
    {from: 'wide', unpivot: {columns: ['jan', 'feb'], keep: ['id'],
      value_column: 'amount', name_column: 'month'}}];
  if (!includeNulls) steps.push({filter: {not: {is_null: {field: 'amount'}}}});
  steps.push({sort: [{field: 'id', dir: 'asc', nulls: 'first'},
    {field: 'month', dir: 'asc', nulls: 'first'}]},
  {select: ['id', 'amount', 'month'], as: 'out'});
  return {version: 'actql/0.1', id: 'fixture.from_unpivot',
    stages: [{id: 'main', inputs: {}, steps,
      results: {rows: {from: 'out', fields: ['id', 'amount', 'month']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const success = (name, text, expected, extra = {}) => ({name: 'from-unpivot-' + name,
  format: 'aql-text', text, expected, columns, parameterDeclarations: declarations,
  parameters: {rows}, sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const joined = [{id: 2, amount: null, month: 'feb', marker: 100},
  {id: 2, amount: null, month: 'feb', marker: 100},
  {id: 2, amount: 7, month: 'jan', marker: 100},
  {id: 2, amount: 7, month: 'jan', marker: 100}];
export const fromUnpivotSuccesses = [
  success('exclude-json-control', JSON.stringify(control(false)), excluded,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('include-json-control', JSON.stringify(control(true)), included,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('default', `SELECT id,amount,month FROM ${wide} UNPIVOT(amount FOR month IN(jan,feb)) ORDER BY id,month`, excluded),
  success('include-alias', `SELECT shaped.id,shaped.amount,shaped.month FROM ${wide} original ${include} AS shaped ORDER BY id,month`, included),
  success('pipe-head', `FROM ${wide} ${include} AS shaped |> SELECT shaped.id,shaped.amount,shaped.month |> ORDER BY id,month`, included),
  success('filtered-limit-offset', `SELECT id,amount,month FROM ${wide} ${include} WHERE amount>5 ORDER BY id,month LIMIT 1 OFFSET 1`,
    [{id: 2, amount: 7, month: 'jan'}]),
  success('empty', `SELECT id,amount,month FROM ${wide} ${include} ORDER BY id,month`, [], {parameters: {rows: []}}),
  success('left-join-port', `SELECT shaped.id,shaped.amount,shaped.month,p.marker FROM ${wide} ${include} shaped JOIN (SELECT 2 AS id,100 AS marker) p ON shaped.id=p.id MAX_OUTPUT_ROWS 10 ORDER BY id,month`, joined,
    {columns: [...columns, {name: 'marker', contract: number(false)}]}),
  success('right-join-port', `SELECT shaped.id,shaped.amount,shaped.month,p.marker FROM (SELECT 2 AS id,100 AS marker) p JOIN ${wide} ${include} shaped ON p.id=shaped.id MAX_OUTPUT_ROWS 10 ORDER BY id,month`, joined,
    {columns: [...columns, {name: 'marker', contract: number(false)}]}),
];
export const fromUnpivotRefusals = [
  {name: 'old-range', text: `SELECT original.id FROM ${wide} original ${include} shaped`},
  {name: 'consumed-column', text: `SELECT shaped.jan FROM ${wide} ${include} shaped`},
  {name: 'qualified-input', text: `SELECT * FROM ${wide} original UNPIVOT(amount FOR month IN(original.jan))`},
  {name: 'destination-collision', text: `SELECT * FROM ${wide} UNPIVOT(amount FOR AMOUNT IN(jan,feb))`},
  {name: 'incompatible-nullability', text: `SELECT * FROM ${wide} UNPIVOT(amount FOR month IN(id,jan))`},
  {name: 'value-table', text: 'WITH a AS (FROM UNNEST([1,2]) element) SELECT * FROM a UNPIVOT(value FOR label IN(a))'},
].map(item => ({...item, name: 'from-unpivot-refusal-' + item.name,
  format: 'aql-text', parameterDeclarations: item.name === 'value-table' ? undefined : declarations,
  parameters: item.name === 'value-table' ? undefined : {rows},
  expectedCode: item.name === 'value-table' ? 'ClientProgramRejected' : 'ClientProgramInvalidInput'}));
