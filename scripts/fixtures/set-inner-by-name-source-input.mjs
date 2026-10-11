// Independent GoogleSQL INNER BY NAME expectations. Unmatched names are
// excluded before common set typing; matching never changes a row's values.
const number = {type: 'number', nullable: false};
const columns = [{name: 'id', contract: number},
  {name: 'amount', contract: {...number, nullable: true}}];
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const expected = [{id: 2, amount: 20}, {id: 2, amount: 20},
  {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 1, amount: null}];
const left = 'SELECT id, amount, 10 AS left_only FROM records WHERE id > 1';
const right = 'SELECT amount, id, 20 AS right_only FROM records WHERE id <= 2';
const order = ' ORDER BY amount NULLS LAST, id';
const sql = left + ' INNER UNION ALL BY NAME ' + right + order;
const success = (name, text, extra = {}) => ({name: 'set-inner-by-name-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
// This hand-authored control captures one shared Source and selects common
// columns before ordinary append. Its topology is not copied from lowering.
export const setInnerByNameProgram = {version: 'actql/0.1', id: 'fixture.set_inner_by_name',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: {gt: [{field: 'id'}, {literal: 1}]}},
      {select: ['id', 'amount'], as: 'left'},
      {from: 'records', filter: {lte: [{field: 'id'}, {literal: 2}]}},
      {select: ['id', 'amount'], as: 'right'},
      {from: 'left', append: {with: 'right'}},
      {sort: [{field: 'amount', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['id', 'amount'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const chain = "SELECT 1 AS x, 2 AS ignored INNER UNION ALL BY NAME SELECT 3 AS x, 'text' AS ignored INNER UNION ALL BY NAME SELECT 4 AS x";
const chainExpectation = {expected: [{x: 1}, {x: 3}, {x: 4}],
  columns: [{name: 'x', contract: number}], sourceReadSessionCount: 0, sourceReadCount: 0};
export const setInnerByNameSuccesses = [
  success('independent-json', JSON.stringify(setInnerByNameProgram), {format: 'json'}),
  success('sql-union-all', sql),
  success('sql-union-distinct', left + ' INNER UNION DISTINCT BY NAME ' + right + order,
    {expected: [{id: 2, amount: 20}, {id: 3, amount: 30}, {id: 1, amount: null}]}),
  success('sql-intersect', 'SELECT id, amount, 10 AS left_only FROM records INNER INTERSECT DISTINCT BY NAME ' + right + order,
    {expected: [{id: 2, amount: 20}, {id: 1, amount: null}]}),
  success('sql-except', 'SELECT id, amount, 10 AS left_only FROM records INNER EXCEPT DISTINCT BY NAME ' + right + order,
    {expected: [{id: 3, amount: 30}]}),
  success('pipe-union-all', 'FROM records |> WHERE id > 1 |> SELECT id, amount, 10 AS left_only '
    + '|> INNER UNION ALL BY NAME (FROM records |> WHERE id <= 2 |> SELECT amount, id, 20 AS right_only)'
    + '|> ORDER BY amount NULLS LAST, id', {format: 'aql-text'}),
  success('data-on-quoted-case', 'WITH combined AS (' + left
    + ' INNER UNION ALL BY NAME ON (`AMOUNT`, ID) ' + right
    + ') FROM combined |> ORDER BY AMOUNT NULLS LAST, ID', {format: 'aql-text',
      expected: expected.map(row => ({AMOUNT: row.amount, ID: row.id})),
      columns: [{name: 'AMOUNT', contract: {...number, nullable: true}}, {name: 'ID', contract: number}]}),
  success('cte-output-scope', 'WITH chosen AS (' + left + ' INNER UNION ALL BY NAME ' + right
    + ') SELECT id, amount FROM chosen' + order),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('parameter-limit', 'SELECT id, amount, 10 AS left_only FROM records WHERE id >= @min '
    + 'INNER UNION ALL BY NAME SELECT amount, id, 20 AS right_only FROM records WHERE id >= @min'
    + order + ' LIMIT 2 OFFSET 1', {parameterDeclarations: {min: number}, parameters: {min: 2},
      expected: [{id: 2, amount: 20}, {id: 3, amount: 30}]}),
  success('sql-global-common-type', chain + ' ORDER BY x', chainExpectation),
  success('data-global-common-type', 'WITH combined AS (' + chain + ') FROM combined |> ORDER BY x',
    {...chainExpectation, format: 'aql-text'}),
];
export const setInnerByNameRefusals = [
  {name: 'empty-intersection', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id FROM records INNER UNION ALL BY NAME SELECT amount FROM records'},
  {name: 'missing-on', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records INNER UNION ALL BY NAME ON (amount) SELECT id FROM records'},
  {name: 'duplicate-on-case', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records INNER UNION ALL BY NAME ON (`id`, ID) SELECT amount, id FROM records'},
  {name: 'without-by-name', text: 'SELECT id FROM records INNER UNION ALL SELECT id FROM records'},
  {name: 'wrong-common-type', text: "SELECT id FROM records INNER UNION ALL BY NAME SELECT 'wrong' AS id, amount FROM records"},
  {name: 'pipe-intermediate-type', text: "SELECT 1 AS x, 2 AS ignored |> INNER UNION ALL BY NAME (SELECT 3 AS x, 'text' AS ignored) |> INNER UNION ALL BY NAME (SELECT 4 AS x)"},
  {name: 'dropped-column', text: left + ' INNER UNION ALL BY NAME ' + right + ' ORDER BY left_only'},
  {name: 'undeclared-parameter', text: 'SELECT id FROM records WHERE id >= @missing INNER UNION ALL BY NAME SELECT id, amount FROM records'},
].map(item => ({format: 'sql', ...item, name: 'set-inner-by-name-refuse-' + item.name}));
