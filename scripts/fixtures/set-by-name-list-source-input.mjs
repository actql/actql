// Expectations are authored from strict GoogleSQL BY NAME ON matching.
// Equal names pair their values; the ON list supplies output spelling/order.
const number = {type: 'number', nullable: false};
const columns = [{name: 'amount', contract: {...number, nullable: true}}, {name: 'id', contract: number}];
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const expected = [{amount: 20, id: 2}, {amount: 20, id: 2},
  {amount: 30, id: 3}, {amount: 30, id: 3}, {amount: null, id: 1}];
const left = 'SELECT id, amount FROM records WHERE id > 1';
const right = 'SELECT amount, id FROM records WHERE id <= 2';
const order = ' ORDER BY amount NULLS LAST, id';
const sql = left + ' UNION ALL BY NAME ON (amount, id) ' + right + order;
const success = (name, text, extra = {}) => ({name: 'set-by-name-list-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
// This control uses ordinary shared input, filters, select, append and sort.
// Its Stage structure is independent of the frontend's generated topology.
export const setByNameListProgram = {version: 'actql/0.1', id: 'fixture.set_by_name_list',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: {gt: [{field: 'id'}, {literal: 1}]}},
      {select: ['amount', 'id'], as: 'left'},
      {from: 'records', filter: {lte: [{field: 'id'}, {literal: 2}]}},
      {select: ['amount', 'id'], as: 'right'},
      {from: 'left', append: {with: 'right'}},
      {sort: [{field: 'amount', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['amount', 'id'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const setByNameListSuccesses = [
  success('independent-json', JSON.stringify(setByNameListProgram), {format: 'json'}),
  success('sql-union-all', sql),
  success('sql-union-distinct', left + ' UNION DISTINCT BY NAME ON (amount, id) ' + right + order,
    {expected: [{amount: 20, id: 2}, {amount: 30, id: 3}, {amount: null, id: 1}]}),
  success('sql-intersect', 'SELECT id, amount FROM records INTERSECT DISTINCT BY NAME ON (amount, id) ' + right + order,
    {expected: [{amount: 20, id: 2}, {amount: null, id: 1}]}),
  success('sql-except', 'SELECT id, amount FROM records EXCEPT DISTINCT BY NAME ON (amount, id) ' + right + order,
    {expected: [{amount: 30, id: 3}]}),
  success('pipe-union-all', 'FROM records |> WHERE id > 1 |> SELECT id, amount '
    + '|> UNION ALL BY NAME ON (amount, id) (FROM records |> WHERE id <= 2 |> SELECT amount, id)'
    + '|> ORDER BY amount NULLS LAST, id', {format: 'aql-text'}),
  success('data-quoted-case', 'DATA combined = ' + left
    + ' UNION ALL BY NAME ON (`AMOUNT`, ID) ' + right
    + '; FROM combined |> ORDER BY AMOUNT NULLS LAST, ID', {format: 'aql-text',
      expected: expected.map(row => ({AMOUNT: row.amount, ID: row.id})),
      columns: [{name: 'AMOUNT', contract: {...number, nullable: true}}, {name: 'ID', contract: number}]}),
  success('cte-output-scope', 'WITH chosen AS (' + left + ' UNION ALL BY NAME ON (amount, id) ' + right
    + ') SELECT amount, id FROM chosen' + order),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('parameter-limit', 'SELECT id, amount FROM records WHERE id >= @min '
    + 'UNION ALL BY NAME ON (amount, id) SELECT amount, id FROM records WHERE id >= @min'
    + order + ' LIMIT 2 OFFSET 1', {parameterDeclarations: {min: number}, parameters: {min: 2},
      expected: [{amount: 20, id: 2}, {amount: 30, id: 3}]}),
];
export const setByNameListRefusals = [
  {name: 'incomplete-list', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL BY NAME ON (id) SELECT id, amount FROM records'},
  {name: 'missing-right', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL BY NAME ON (id, amount) SELECT id FROM records'},
  {name: 'duplicate-case', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL BY NAME ON (`id`, ID) SELECT id, amount FROM records'},
  {name: 'qualified-name', text: 'SELECT id FROM records UNION ALL BY NAME ON (records.id) SELECT id FROM records'},
  {name: 'empty-list', text: 'SELECT id FROM records UNION ALL BY NAME ON () SELECT id FROM records'},
  {name: 'wrong-type', text: "SELECT id, amount FROM records UNION ALL BY NAME ON (amount, id) SELECT 'wrong' AS amount, id FROM records"},
  {name: 'removed-range', text: 'SELECT id, amount FROM records UNION ALL BY NAME ON (amount, id) SELECT amount, id FROM records ORDER BY records.amount'},
  {name: 'undeclared-parameter', text: 'SELECT id, amount FROM records WHERE id >= @missing UNION ALL BY NAME ON (amount, id) SELECT amount, id FROM records'},
].map(item => ({format: 'sql', ...item, name: 'set-by-name-list-refuse-' + item.name}));
