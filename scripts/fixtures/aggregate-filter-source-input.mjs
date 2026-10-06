// Independent Group and analytic expectations from aggregate-local filtering.
// A query WHERE must not replace filters that select different contributors.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 2, amount: 2}, {id: 1, amount: 2},
  {id: 3, amount: -1}, {id: 4, amount: null}, {id: 0, amount: 100}];
const positive = {gt: [{field: 'amount'}, {literal: 0}]};
const aggregates = {positive: {fn: 'count', filter: positive},
  total: {fn: 'sum', field: 'amount', distinct: true, filter: positive},
  null_rows: {fn: 'count', filter: {is_null: {field: 'amount'}}}, all_rows: {fn: 'count'}};
export const aggregateFilterProgram = {version: 'actql/0.1', id: 'fixture.aggregate_filter',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates}},
      {select: ['positive', 'total', 'null_rows', 'all_rows'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['positive', 'total', 'null_rows', 'all_rows']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const projection = 'COUNT(* WHERE amount > 0) AS positive, '
  + 'SUM(DISTINCT amount WHERE amount > 0) AS total, '
  + 'COUNT(* WHERE amount IS NULL) AS null_rows, COUNT(*) AS all_rows';
const expected = [{positive: 2, total: 2, null_rows: 1, all_rows: 4}];
const columns = [column('positive'), column('total', nullableNumber), column('null_rows'), column('all_rows')];
const success = (name, text, extra = {}) => ({name: 'aggregate-filter-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const aggregateFilterSuccesses = [
  success('independent-json', JSON.stringify(aggregateFilterProgram), {format: 'json'}),
  success('sql-independent-filters', `SELECT ${projection} FROM records WHERE id > 0`),
  success('pipe-independent-filters', `FROM records |> WHERE id > 0 |> AGGREGATE ${projection}`, {format: 'aql-text'}),
  success('qualified-input', 'SELECT COUNT(* WHERE r.amount > 0) AS n FROM records AS r WHERE id > 0',
    {expected: [{n: 2}], columns: [column('n')]}),
  success('empty-global', `SELECT ${projection} FROM records`, {sourceRows: [],
    expected: [{positive: 0, total: null, null_rows: 0, all_rows: 0}]}),
  success('null-parameter', 'SELECT COUNT(* WHERE @keep) AS n', {
    expected: [{n: 0}], columns: [column('n')], sourceReadSessionCount: 0,
    parameterDeclarations: {keep: {type: 'boolean', nullable: true}}, parameters: {keep: null},
  }),
  success('skipped-argument', 'SELECT COUNT(* WHERE TRUE) AS n, SUM(1 / 0 WHERE FALSE) AS total', {
    expected: [{n: 1, total: null}], columns: [column('n'), column('total', nullableNumber)],
    sourceReadSessionCount: 0,
  }),
  success('retained-alias-value', 'FROM records |> WHERE id > 0 |> AS before |> SET amount = 0 '
    + '|> AGGREGATE COUNT(* WHERE before.amount > 0) AS originals, COUNT(* WHERE amount > 0) AS current', {
    format: 'aql-text', expected: [{originals: 2, current: 0}], columns: [column('originals'), column('current')],
  }),
  success('analytic-caller', 'SELECT id, COUNT(* WHERE amount > 0) OVER '
    + '(ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n '
    + 'FROM records WHERE id > 0 ORDER BY id', {
    expected: [{id: 1, n: 1}, {id: 2, n: 2}, {id: 3, n: 2}, {id: 4, n: 2}],
    columns: [column('id'), column('n')],
  }),
  success('filtered-keyed-array', 'FROM records |> WHERE id > 0 |> ASSERT UNIQUE BY (id) '
    + '|> ORDER BY id |> LIMIT 4 |> AGGREGATE '
    + 'ARRAY_AGG(DISTINCT id IGNORE NULLS WHERE amount > 0 ORDER BY id) AS ids', {
    format: 'aql-text', expected: [{ids: [1, 2]}],
    columns: [column('ids', {type: 'array', nullable: false, items: number})],
  }),
];
export const aggregateFilterRefusals = [
  'SELECT COUNT(* WHERE amount) AS n FROM records',
  'SELECT COUNT(* WHERE missing > 0) AS n FROM records',
  'SELECT COUNT(* WHERE @missing) AS n FROM records',
  'SELECT COUNT(*) AS n, SUM(amount WHERE n > 0) AS total FROM records',
  'FROM records |> AS old |> AS current |> AGGREGATE COUNT(* WHERE old.amount > 0) AS n',
].map((text, index) => ({name: 'aggregate-filter-refuse-' + index, format: 'aql-text', text}));
export const aggregateFilterExecutionFailures = [{name: 'aggregate-filter-demanded-argument', format: 'sql',
  text: 'SELECT SUM(1 / 0 WHERE TRUE) AS total', resultNames: ['answer'], sourceReadSessionCount: 0}];
