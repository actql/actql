// Independently authored positional tuple obligations. No product compiler or
// evaluator contributes to these rows, contracts or machine controls.
const number = nullable => ({type: 'number', nullable});
const string = nullable => ({type: 'string', nullable});
const schema = {id: number(false), jan_amount: number(true), jan_note: string(true),
  feb_amount: number(true), feb_note: string(true)};
const rows = [{id: 2, jan_amount: null, jan_note: null, feb_amount: 7, feb_note: 'B'},
  {id: 1, jan_amount: 5, jan_note: null, feb_amount: null, feb_note: 'kept'},
  {id: 2, jan_amount: null, jan_note: null, feb_amount: 7, feb_note: 'B'}];
const declarations = {rows: {type: 'array', nullable: false, max_items: 3,
  items: {type: 'object', nullable: false, fields: schema}}};
const exclude = [{"id": 1, "amount": null, "note": "kept", "month": "Feb"}, {"id": 1, "amount": 5, "note": null, "month": "Jan"}, {"id": 2, "amount": 7, "note": "B", "month": "Feb"}, {"id": 2, "amount": 7, "note": "B", "month": "Feb"}];
const include = [{"id": 1, "amount": null, "note": "kept", "month": "Feb"}, {"id": 1, "amount": 5, "note": null, "month": "Jan"}, {"id": 2, "amount": 7, "note": "B", "month": "Feb"}, {"id": 2, "amount": 7, "note": "B", "month": "Feb"}, {"id": 2, "amount": null, "note": null, "month": "Jan"}, {"id": 2, "amount": null, "note": null, "month": "Jan"}];
const columns = [{"name": "id", "contract": {"type": "number", "nullable": false}}, {"name": "amount", "contract": {"type": "number", "nullable": true}}, {"name": "note", "contract": {"type": "string", "nullable": true}}, {"name": "month", "contract": {"type": "string", "nullable": false, "max_utf8_bytes": 3}}];
const control = {"version":"actql/0.1","id":"fixture.multi_column_unpivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"jan_amount":{"type":"number","nullable":true},"jan_note":{"type":"string","nullable":true},"feb_amount":{"type":"number","nullable":true},"feb_note":{"type":"string","nullable":true}},"rows":[{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"},{"id":1,"jan_amount":5,"jan_note":null,"feb_amount":null,"feb_note":"kept"},{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"}]},"as":"wide"},{"from":"wide","derive":{"private_jan":{"object":{"amount":{"field":"jan_amount"},"note":{"field":"jan_note"}}},"private_feb":{"object":{"amount":{"field":"feb_amount"},"note":{"field":"feb_note"}}}}},{"select":["id","private_jan","private_feb"]},{"unpivot":{"columns":["private_jan","private_feb"],"keep":["id"],"name_column":"private_name","value_column":"private_bundle"}},{"derive":{"amount":{"property":{"value":{"field":"private_bundle"},"name":"amount"}},"note":{"property":{"value":{"field":"private_bundle"},"name":"note"}},"month":{"if":[{"eq":[{"field":"private_name"},{"literal":"private_jan"}]},{"literal":"Jan"},{"literal":"Feb"}]}}},{"filter":{"or":[{"not":{"is_null":{"field":"amount"}}},{"not":{"is_null":{"field":"note"}}}]}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"month","dir":"asc","nulls":"first"}]},{"select":["id","amount","note","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","amount","note","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const includedControl = structuredClone(control);
includedControl.stages[0].steps.splice(5, 1);
const select = 'SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item';
const data = `DATA wide = ${select};`;
const tuple = "((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb'))";
const defaults = '((amount,note) FOR month IN ((jan_amount,jan_note),(feb_amount,feb_note)))';
const defaultRows = exclude.map(row => ({...row,
  month: row.month === 'Jan' ? 'jan_amount_jan_note' : 'feb_amount_feb_note'}));
const renamedRows = exclude.map(row => ({...row,
  month: row.month === 'Jan' ? 'jan_amount_first_note' : 'feb_amount_feb_note'}));
// Literal bounds come from the authored names: 19 and 21 UTF-8 bytes.
const labelColumns = max => [...columns.slice(0, 3),
  {name: 'month', contract: {...string(false), max_utf8_bytes: max}}];
const success = (name, text, expected, extra = {}) => ({
  name: 'unpivot-multicolumn-' + name, format: 'aql-text', text, expected, columns,
  parameterDeclarations: declarations, parameters: {rows},
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const unpivotMulticolumnSuccesses = [
  success('json-exclude-control', JSON.stringify(control), exclude,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('json-include-control', JSON.stringify(includedControl), include,
    {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('data-from-exclude', `${data} SELECT id,amount,note,month FROM wide UNPIVOT ${tuple} ORDER BY id,month`, exclude),
  success('pipe-include-fresh-range', `FROM (${select}) original |> UNPIVOT INCLUDE NULLS ${tuple} |> AS shaped |> SELECT shaped.id,shaped.amount,shaped.note,shaped.month |> ORDER BY id,month`, include),
  success('default-labels', `FROM (${select}) |> UNPIVOT ${defaults} |> ORDER BY id,month`, defaultRows, {columns: labelColumns(19)}),
  success('renamed-default-labels', `FROM (${select}) |> RENAME jan_note AS first_note |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,first_note),(feb_amount,feb_note))) |> ORDER BY id,month`, renamedRows, {columns: labelColumns(21)}),
  success('typed-empty', `${data} SELECT id,amount,note,month FROM wide UNPIVOT ${tuple} ORDER BY id,month`, [], {parameters: {rows: []}}),
];
const nullableDeclarations = structuredClone(declarations);
nullableDeclarations.rows.items.fields.jan_amount.nullable = false;
export const unpivotMulticolumnRefusals = [
  {name: 'arity', text: `FROM (${select}) |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note),feb_amount))`},
  {name: 'output-collision', text: `FROM (${select}) |> UNPIVOT ((amount,amount) FOR month IN ((jan_amount,jan_note),(feb_amount,feb_note)))`},
  {name: 'old-range', text: `FROM (${select}) original |> UNPIVOT ${tuple} |> SELECT original.id`},
  {name: 'consumed-input', text: `FROM (${select}) |> UNPIVOT ${tuple} |> SELECT jan_amount`},
  {name: 'corresponding-type', text: `FROM (${select}) |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note),(feb_note,feb_amount)))`},
  // This is an unadopted common-contract gap, not a frontend cast opportunity.
  {name: 'corresponding-nullability-gap', text: `FROM (${select}) |> UNPIVOT ${tuple}`,
    parameterDeclarations: nullableDeclarations, parameters: {rows: [rows[1]]}},
].map(item => ({format: 'aql-text', parameterDeclarations: declarations,
  parameters: {rows}, expectedCode: 'ClientProgramInvalidInput', ...item,
  name: 'unpivot-multicolumn-refusal-' + item.name}));
