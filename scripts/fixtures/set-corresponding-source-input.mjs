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
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 2}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: number}]}),
  positional('typed-empty', 'DATA e = SELECT 0 AS a, CAST(NULL AS FLOAT64) AS b WHERE FALSE '
    + 'UNION ALL SELECT 1 AS x, CAST(NULL AS FLOAT64) AS x WHERE FALSE; '
    + 'FROM e |> ORDER BY a, b', {format: 'aql-text', expected: []}),
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

// Independent COUNT semantics: a single NULL input is counted by COUNT(*)
// and excluded by COUNT(field). Both output columns are nonnullable numbers.
const aggregateColumns = [{name: 'a', contract: number}, {name: 'b', contract: number}];
const aggregateRows = [{a: 0, b: 0}, {a: 1, b: 0}];
export const positionalAggregateProgram = {version: 'actql/0.1', id: 'fixture.aggregate_duplicates',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {nullable_input: {...number, nullable: true}},
      rows: [{nullable_input: null}]}, as: 'input'},
    {from: 'input', group: {by: [], aggregates: {
      one: {fn: 'count'}, zero: {fn: 'count', field: 'nullable_input'},
    }}},
    {select: [{a: 'one'}, {b: 'zero'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'},
      {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const aggregateText = 'SELECT 0 AS a, 0 AS b UNION ALL '
  + 'SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n';
const aggregateQualify = 'DATA r = SELECT 1 AS x; SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL '
  + 'SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n, '
  + 'ROW_NUMBER() OVER (ORDER BY r.x) AS rn FROM r GROUP BY r.x QUALIFY ';
const aggregate = (name, text, extra = {}) => positional('aggregate-' + name, text,
  {columns: aggregateColumns, expected: aggregateRows, ...extra});
setCorrespondingSuccesses.push(
  aggregate('json-control', JSON.stringify(positionalAggregateProgram), {format: 'json'}),
  aggregate('distinct-count-inputs', aggregateText + ' ORDER BY a, b'),
  aggregate('data-case-aliases', 'DATA combined = SELECT 0 AS a, 0 AS b UNION ALL '
    + 'SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS `N`; '
    + 'FROM combined |> ORDER BY a, b', {format: 'aql-text'}),
  aggregate('empty-global', aggregateText + ' WHERE FALSE ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 0, b: 0}]}),
  aggregate('explicit-having-call', aggregateText + ' HAVING COUNT(*) > 0 ORDER BY a, b'),
  aggregate('qualified-input-having', 'DATA r = SELECT 1 AS x; '
    + aggregateText + ' FROM r AS n GROUP BY n.x HAVING n.x > 0 ORDER BY a, b',
    {format: 'aql-text'}),
  aggregate('undemanded-qualify-aliases', aggregateQualify + 'r.x > 0 AND rn = 1 ORDER BY a, b, c',
    {format: 'aql-text', expected: [{a: 0, b: 0, c: 0}, {a: 1, b: 0, c: 1}],
      columns: [...aggregateColumns, {name: 'c', contract: number}]}),
);
setCorrespondingRefusals.push(...[
  {name: 'aggregate-ambiguous-having', text: aggregateText + ' HAVING n > 0'},
  {name: 'aggregate-ambiguous-receiver', text: aggregateText + ' HAVING n.member = 1'},
  {name: 'aggregate-private-having', text: aggregateText + ' HAVING aql_select_aggregate_2 > 0'},
  {name: 'aggregate-ambiguous-qualify', format: 'aql-text', text: aggregateQualify + 'n > 0'},
].map(item => ({...item, name: 'set-corresponding-refuse-' + item.name,
  format: item.format ?? 'sql', expectedCode: 'ClientProgramInvalidInput'})));

// The two window calls consume the same input snapshot, but opposing ORDER
// keys produce different values. Authored duplicate names cannot select a slot.
export const positionalWindowProgram = {version: 'actql/0.1', id: 'fixture.window_duplicates',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', analytic: {partition_by: [],
      order_by: [{field: 'x', dir: 'asc', nulls: 'first'}],
      functions: {up: {fn: 'row_number'}}}},
    {analytic: {partition_by: [], order_by: [{field: 'x', dir: 'desc', nulls: 'last'}],
      functions: {down: {fn: 'row_number'}}}},
    {select: [{a: 'up'}, {b: 'down'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'},
      {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const windowRows = [{a: 0, b: 0}, {a: 1, b: 2}, {a: 2, b: 1}];
const windowHead = 'SELECT 0 AS a, 0 AS b UNION ALL SELECT '
  + 'ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS `N` FROM r';
const window = (name, text, extra = {}) => positional('window-' + name, text,
  {columns: aggregateColumns, expected: windowRows, ...extra});
setCorrespondingSuccesses.push(
  window('json-control', JSON.stringify(positionalWindowProgram), {format: 'json'}),
  window('opposing-orders', 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; '
    + windowHead + ' ORDER BY a, b', {format: 'aql-text'}),
  window('different-functions', 'DATA r = SELECT 1 AS x UNION ALL SELECT 1 AS x; '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, '
    + 'RANK() OVER (ORDER BY x) AS n FROM r ORDER BY a, b',
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 1}, {a: 2, b: 1}]}),
  window('aggregate-functions', 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n, '
    + 'COUNT(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n FROM r ORDER BY a, b',
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 1}, {a: 3, b: 2}],
      columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}]}),
  window('typed-empty', 'DATA r = SELECT 1 AS x WHERE FALSE; '
    + 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r '
    + 'ORDER BY a, b', {format: 'aql-text', expected: []}),
  window('source-orders', 'SELECT 0 AS a, 0 AS b UNION ALL SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n, ROW_NUMBER() OVER (ORDER BY id DESC) AS n '
    + 'FROM records ORDER BY a, b',
    {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}], sourceReadSessionCount: 1}),
);
setCorrespondingRefusals.push(...[
  {name: 'window-ambiguous-qualify', text: windowHead + ' QUALIFY n > 0'},
  {name: 'window-private-qualify', text: windowHead + ' QUALIFY aql_analytic_output_3 > 0'},
].map(item => ({...item, text: 'DATA r = SELECT 1 AS x; ' + item.text,
  name: 'set-corresponding-refuse-' + item.name, format: 'aql-text',
  expectedCode: 'ClientProgramInvalidInput'})));

// Anonymous window values have no clause alias. Positional alignment publishes
// the first operand's a/b names; these are independently authored expectations.
const anonymousAnalyticHead = 'SELECT 0 AS a, 0 AS b UNION ALL SELECT '
  + 'ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r';
const anonymousAnalytic = (name, text, extra = {}) => positional('anonymous-analytic-' + name, text,
  {columns: aggregateColumns, expected: windowRows, ...extra});
setCorrespondingSuccesses.push(
  anonymousAnalytic('opposing-orders', 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; '
    + anonymousAnalyticHead + ' ORDER BY a, b', {format: 'aql-text'}),
  anonymousAnalytic('scoped-pipe', 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; '
    + 'SELECT 0 AS a, 0 AS b |> UNION ALL (FROM r |> AS original |> SET x = -x '
    + '|> SELECT ROW_NUMBER() OVER (ORDER BY original.x), ROW_NUMBER() OVER (ORDER BY x)) '
    + '|> ORDER BY a, b', {format: 'aql-text'}),
  anonymousAnalytic('named-qualify', 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), '
    + 'ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r QUALIFY n > 0 ORDER BY a, b',
    {format: 'aql-text'}),
  anonymousAnalytic('typed-empty', 'DATA r = SELECT 1 AS x WHERE FALSE; '
    + 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), '
    + 'ROW_NUMBER() OVER (ORDER BY x DESC) FROM r ORDER BY a, b',
    {format: 'aql-text', expected: []}),
  anonymousAnalytic('source-orders', 'SELECT 0 AS a, 0 AS b UNION ALL SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY id), ROW_NUMBER() OVER (ORDER BY id DESC) '
    + 'FROM records ORDER BY a, b',
    {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}], sourceReadSessionCount: 1}),
);
setCorrespondingRefusals.push(...[
  {name: 'anonymous-analytic-private-slot', field: 'aql_analytic_output_1'},
  {name: 'anonymous-analytic-private-projection', field: 'aql_set_anonymous_3'},
].map(item => ({name: 'set-corresponding-refuse-' + item.name, format: 'aql-text',
  text: 'DATA r = SELECT 1 AS x; ' + anonymousAnalyticHead + ' QUALIFY ' + item.field + ' > 0',
  expectedCode: 'ClientProgramInvalidInput'})));
