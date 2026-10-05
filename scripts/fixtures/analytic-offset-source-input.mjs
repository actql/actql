// Navigation expectations follow the admitted LAG/LEAD offset contract.
// Values are independent of compiler output and preserve the NULL row at id=1.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
export const analyticOffsetCapacity = {
  max_analytic_input_wire_bytes: 1048576,
  max_analytic_output_wire_bytes: 1048576,
  max_analytic_partition_wire_bytes: 1048576,
  max_analytic_frame_memberships: 10000,
};
const sourceRows = [{id: 4, amount: 30}, {id: 1, amount: null},
  {id: 3, amount: 20}, {id: 2, amount: 20}, {id: 5, amount: 30},
  {id: 0, amount: 99}];
const expected = [{id: 1, previous: null, next: 20},
  {id: 2, previous: null, next: 20}, {id: 3, previous: null, next: 30},
  {id: 4, previous: 20, next: 30}, {id: 5, previous: 20, next: null}];
const columns = [column('id'), column('previous', nullableNumber),
  column('next', nullableNumber)];
const declarations = {p: number};
// One ordinary capture, then the existing analytic owner. No expression or
// field names are generated from the lowerer for this machine-input control.
export const analyticOffsetProgram = {version: 'actql/0.1',
  id: 'fixture.analytic_offset', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {previous: {fn: 'lag', expr: {field: 'amount'}, offset: 2},
        next: {fn: 'lead', expr: {field: 'amount'}, offset: {$param: 'p'}}}}},
    {select: ['id', 'previous', 'next']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'previous', 'next']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, LAG(amount, ((2))) OVER (ORDER BY id) AS previous, '
  + 'LEAD(amount, (@p)) OVER (ORDER BY id) AS next FROM records '
  + 'WHERE id > 0 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'analytic-offset-' + name,
  format: 'sql', hostProfile: 'analytic-offset', text, sourceRows, expected, columns,
  parameterDeclarations: declarations, parameters: {p: 1},
  sourceReadSessionCount: 1, ...extra});
export const analyticOffsetSuccesses = [
  success('independent-json', JSON.stringify(analyticOffsetProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('sql-literal-parameter', sql),
  success('pipe-parameter-literal', 'FROM records |> WHERE id > 0 |> SELECT id, '
    + 'LAG(amount, ((@p))) OVER (ORDER BY id) AS previous, '
    + 'LEAD(amount, (2)) OVER (ORDER BY id) AS next |> ORDER BY id',
  {format: 'aql-text', parameters: {p: 1}, expected: [
    {id: 1, previous: null, next: 20}, {id: 2, previous: null, next: 30},
    {id: 3, previous: 20, next: 30}, {id: 4, previous: 20, next: null},
    {id: 5, previous: 30, next: null}]}),
  success('zero-preserves-duplicates', 'SELECT id, LAG(amount, (0)) '
    + 'OVER (ORDER BY id) AS previous, LEAD(amount, ((@p))) OVER (ORDER BY id) '
    + 'AS next FROM records WHERE id > 0 ORDER BY id',
  {parameters: {p: 0}, sourceRows: [
    {id: 2, amount: 20}, {id: 1, amount: null}, {id: 2, amount: 20}],
  expected: [{id: 1, previous: null, next: null},
    {id: 2, previous: 20, next: 20}, {id: 2, previous: 20, next: 20}]}),
  success('empty-typed', sql, {sourceRows: [], expected: []}),
];
const parameterText = 'SELECT LAG(amount, ((@p))) OVER (ORDER BY id) AS previous FROM records';
export const analyticOffsetRefusals = [
  {name: 'undeclared', text: parameterText},
  {name: 'missing', text: parameterText, parameterDeclarations: declarations},
  ...[-1, 1.5, null, 9007199254740992, 'private-value'].map((value, index) => ({
    name: 'invalid-parameter-' + index, text: parameterText,
    parameterDeclarations: {p: value === null ? nullableNumber : number},
    parameters: {p: value}})),
  {name: 'dynamic', text: 'SELECT LAG(amount, (id)) OVER (ORDER BY id) AS previous FROM records'},
  {name: 'arithmetic', text: 'SELECT LEAD(amount, (1 + 1)) OVER (ORDER BY id) AS next FROM records'},
].map(item => ({format: 'sql', hostProfile: 'analytic-offset', ...item, name: 'analytic-offset-refuse-' + item.name}));
