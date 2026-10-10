// Independent GoogleSQL CORRESPONDING expectations. Unmatched names are
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
const sql = left + ' UNION ALL CORRESPONDING ' + right + order;
const success = (name, text, extra = {}) => ({name: 'set-corresponding-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
// This hand-authored control captures one shared Source and selects common
// columns before ordinary append. Its topology is not copied from lowering.
export const setCorrespondingProgram = {version: 'actql/0.1', id: 'fixture.set_corresponding',
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
const chain = "SELECT 1 AS x, 2 AS ignored UNION ALL CORRESPONDING SELECT 3 AS x, 'text' AS ignored UNION ALL CORRESPONDING SELECT 4 AS x";
export const setCorrespondingSuccesses = [
  success('independent-json', JSON.stringify(setCorrespondingProgram), {format: 'json'}),
  success('sql-default', sql),
  success('sql-strict', 'SELECT id, amount FROM records WHERE id > 1 UNION ALL STRICT CORRESPONDING SELECT amount, id FROM records WHERE id <= 2' + order),
  success('sql-intersect', 'SELECT id, amount, 10 AS left_only FROM records INTERSECT DISTINCT CORRESPONDING ' + right + order,
    {expected: [{id: 2, amount: 20}, {id: 1, amount: null}]}),
  success('sql-except', 'SELECT id, amount, 10 AS left_only FROM records EXCEPT DISTINCT CORRESPONDING ' + right + order,
    {expected: [{id: 3, amount: 30}]}),
  success('pipe-explicit-inner', 'FROM records |> WHERE id > 1 |> SELECT id, amount, 10 AS left_only '
    + '|> INNER UNION ALL CORRESPONDING (FROM records |> WHERE id <= 2 |> SELECT amount, id, 20 AS right_only)'
    + '|> ORDER BY amount NULLS LAST, id', {format: 'aql-text'}),
  success('data-by-case', 'DATA combined = ' + left + ' UNION ALL CORRESPONDING BY (`AMOUNT`, ID) ' + right
    + '; FROM combined |> ORDER BY AMOUNT NULLS LAST, ID', {format: 'aql-text',
      expected: expected.map(row => ({AMOUNT: row.amount, ID: row.id})),
      columns: [{name: 'AMOUNT', contract: {...number, nullable: true}}, {name: 'ID', contract: number}]}),
  success('pipe-strict-by', 'FROM records |> WHERE id > 1 |> SELECT id, amount '
    + '|> UNION ALL STRICT CORRESPONDING BY (`AMOUNT`, ID) (FROM records |> WHERE id <= 2 |> SELECT amount, id) '
    + '|> ORDER BY AMOUNT NULLS LAST, ID', {format: 'aql-text',
      expected: expected.map(row => ({AMOUNT: row.amount, ID: row.id})),
      columns: [{name: 'AMOUNT', contract: {...number, nullable: true}}, {name: 'ID', contract: number}]}),
  success('cte-output-scope', 'WITH chosen AS (' + left + ' UNION ALL CORRESPONDING ' + right
    + ') SELECT id, amount FROM chosen' + order),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('parameter-limit', 'SELECT id, amount, 10 AS left_only FROM records WHERE id >= @min '
    + 'UNION ALL CORRESPONDING SELECT amount, id, 20 AS right_only FROM records WHERE id >= @min'
    + order + ' LIMIT 2 OFFSET 1', {parameterDeclarations: {min: number}, parameters: {min: 2},
      expected: [{id: 2, amount: 20}, {id: 3, amount: 30}]}),
  success('sql-global-common-type', chain + ' ORDER BY x', {expected: [{x: 1}, {x: 3}, {x: 4}],
    columns: [{name: 'x', contract: number}], sourceReadSessionCount: 0, sourceReadCount: 0}),
];
export const setCorrespondingRefusals = [
  {name: 'empty-intersection', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id FROM records UNION ALL CORRESPONDING SELECT amount FROM records'},
  {name: 'missing-by', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL CORRESPONDING BY (amount) SELECT id FROM records'},
  {name: 'duplicate-by-case', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL CORRESPONDING BY (`id`, ID) SELECT amount, id FROM records'},
  {name: 'strict-extra', expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT id, amount FROM records UNION ALL STRICT CORRESPONDING BY (id) SELECT id, amount FROM records'},
  {name: 'inner-strict', text: 'SELECT id FROM records INNER UNION ALL STRICT CORRESPONDING SELECT id FROM records'},
  {name: 'wrong-common-type', text: "SELECT id FROM records UNION ALL CORRESPONDING SELECT 'wrong' AS id, amount FROM records"},
  {name: 'dropped-column', text: left + ' UNION ALL CORRESPONDING ' + right + ' ORDER BY left_only'},
  {name: 'undeclared-parameter', text: 'SELECT id FROM records WHERE id >= @missing UNION ALL CORRESPONDING SELECT id, amount FROM records'},
].map(item => ({format: 'sql', ...item, name: 'set-corresponding-refuse-' + item.name}));

// Positional operands have no name-matching obligation. The duplicate right
// aliases describe two distinct values, not one field to keep or overwrite.
const positionalColumns = [{name: 'a', contract: number},
  {name: 'b', contract: {...number, nullable: true}}];
const positionalRows = [{a: 0, b: 0}, {a: 1, b: null}];
const positionalProgram = {version: 'actql/0.1', id: 'fixture.positional_duplicates',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {a: number, b: {...number, nullable: true}}, rows: positionalRows}, as: 'seed'},
    {from: 'seed', sort: [{field: 'a', dir: 'asc', nulls: 'first'},
      {field: 'b', dir: 'asc', nulls: 'last'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const positional = (name, text, extra = {}) => success('positional-' + name, text,
  {sourceRows: [], sourceReadSessionCount: 0, columns: positionalColumns,
    expected: positionalRows, ...extra});
setCorrespondingSuccesses.push(
  positional('json-control', JSON.stringify(positionalProgram), {format: 'json'}),
  positional('duplicate-aliases', 'SELECT 0 AS a, 0 AS b UNION ALL '
    + 'SELECT 1 AS x, CAST(NULL AS FLOAT64) AS `X` ORDER BY a, b NULLS LAST'),
  positional('scoped-current-and-original', 'DATA n = SELECT 1 AS x; '
    + 'FROM n |> SELECT 0 AS a, 0 AS b |> UNION ALL (FROM n AS original '
    + '|> SET x = x + 1 |> SELECT original.x AS x, x AS `X`) |> ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 1, b: 2}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: number}]}),
  positional('typed-empty', 'DATA e = SELECT 0 AS a, CAST(NULL AS FLOAT64) AS b WHERE FALSE '
    + 'UNION ALL SELECT 1 AS x, CAST(NULL AS FLOAT64) AS x WHERE FALSE; '
    + 'FROM e |> ORDER BY a, b', {expected: []}),
  positional('shared-source', 'SELECT 0 AS a, 0 AS b UNION ALL '
    + 'SELECT id AS repeated, amount AS repeated FROM records WHERE id > 0 ORDER BY a, b NULLS LAST',
    {sourceRows, sourceReadSessionCount: 1,
      expected: [{a: 0, b: 0}, {a: 1, b: null}, {a: 2, b: 20},
        {a: 3, b: 30}, {a: 3, b: 30}]}),
);
setCorrespondingRefusals.push(...[
  {name: 'positional-public-duplicates', text: 'SELECT 1 AS x, 2 AS x'},
  {name: 'positional-by-name-duplicates',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL BY NAME SELECT 1 AS a, 2 AS a'},
  {name: 'positional-private-output',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL SELECT 1 AS x, 2 AS x ORDER BY aql_set_duplicate_2'},
].map(item => ({...item, name: 'set-corresponding-refuse-' + item.name,
  format: 'sql', expectedCode: 'ClientProgramInvalidInput'})));
