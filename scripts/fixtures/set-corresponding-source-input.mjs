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
  success('data-by-case', 'WITH combined AS (' + left + ' UNION ALL CORRESPONDING BY (`AMOUNT`, ID) ' + right
    + ') FROM combined |> ORDER BY AMOUNT NULLS LAST, ID', {format: 'aql-text',
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
  positional('scoped-current-and-original', 'WITH n AS (SELECT 1 AS x) '
    + 'FROM n |> SELECT 0 AS a, 0 AS b |> UNION ALL (FROM n AS original '
    + '|> SET x = x + 1 |> SELECT original.x AS x, x AS `X`) |> ORDER BY a, b',
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 2}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: number}]}),
  positional('typed-empty', 'WITH e AS (SELECT 0 AS a, CAST(NULL AS FLOAT64) AS b WHERE FALSE '
    + 'UNION ALL SELECT 1 AS x, CAST(NULL AS FLOAT64) AS x WHERE FALSE) '
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
const aggregateQualify = 'WITH r AS (SELECT 1 AS x) SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL '
  + 'SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n, '
  + 'ROW_NUMBER() OVER (ORDER BY r.x) AS rn FROM r GROUP BY r.x QUALIFY ';
const aggregate = (name, text, extra = {}) => positional('aggregate-' + name, text,
  {columns: aggregateColumns, expected: aggregateRows, ...extra});
setCorrespondingSuccesses.push(
  aggregate('json-control', JSON.stringify(positionalAggregateProgram), {format: 'json'}),
  aggregate('distinct-count-inputs', aggregateText + ' ORDER BY a, b'),
  aggregate('data-case-aliases', 'WITH combined AS (SELECT 0 AS a, 0 AS b UNION ALL '
    + 'SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS `N`) '
    + 'FROM combined |> ORDER BY a, b', {format: 'aql-text'}),
  aggregate('empty-global', aggregateText + ' WHERE FALSE ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 0, b: 0}]}),
  aggregate('explicit-having-call', aggregateText + ' HAVING COUNT(*) > 0 ORDER BY a, b'),
  aggregate('qualified-input-having', 'WITH r AS (SELECT 1 AS x) '
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
  window('opposing-orders', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) '
    + windowHead + ' ORDER BY a, b', {format: 'aql-text'}),
  window('different-functions', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 1 AS x) '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, '
    + 'RANK() OVER (ORDER BY x) AS n FROM r ORDER BY a, b',
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 1}, {a: 2, b: 1}]}),
  window('aggregate-functions', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n, '
    + 'COUNT(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n FROM r ORDER BY a, b',
    {format: 'aql-text', expected: [{a: 0, b: 0}, {a: 1, b: 1}, {a: 3, b: 2}],
      columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}]}),
  window('typed-empty', 'WITH r AS (SELECT 1 AS x WHERE FALSE) '
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
].map(item => ({...item, text: 'WITH r AS (SELECT 1 AS x) ' + item.text,
  name: 'set-corresponding-refuse-' + item.name, format: 'aql-text',
  expectedCode: 'ClientProgramInvalidInput'})));

// Anonymous window values have no clause alias. Positional alignment publishes
// the first operand's a/b names; these are independently authored expectations.
const anonymousAnalyticHead = 'SELECT 0 AS a, 0 AS b UNION ALL SELECT '
  + 'ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r';
const anonymousAnalytic = (name, text, extra = {}) => positional('anonymous-analytic-' + name, text,
  {columns: aggregateColumns, expected: windowRows, ...extra});
setCorrespondingSuccesses.push(
  anonymousAnalytic('opposing-orders', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) '
    + anonymousAnalyticHead + ' ORDER BY a, b', {format: 'aql-text'}),
  anonymousAnalytic('scoped-pipe', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) '
    + 'SELECT 0 AS a, 0 AS b |> UNION ALL (FROM r |> AS original |> SET x = -x '
    + '|> SELECT ROW_NUMBER() OVER (ORDER BY original.x), ROW_NUMBER() OVER (ORDER BY x)) '
    + '|> ORDER BY a, b', {format: 'aql-text'}),
  anonymousAnalytic('named-qualify', 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) '
    + 'SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), '
    + 'ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r QUALIFY n > 0 ORDER BY a, b',
    {format: 'aql-text'}),
  anonymousAnalytic('typed-empty', 'WITH r AS (SELECT 1 AS x WHERE FALSE) '
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
  text: 'WITH r AS (SELECT 1 AS x) ' + anonymousAnalyticHead + ' QUALIFY ' + item.field + ' > 0',
  expectedCode: 'ClientProgramInvalidInput'})));

// Parentheses preserve operand ownership and ordinal values. These results
// are authored from the same two input rows as the independent JSON control.
const parenthesized = (name, text, extra = {}) => positional('parenthesized-' + name,
  text, {format: 'aql-text', columns: aggregateColumns, expected: windowRows, ...extra});
const parenthesizedInput = 'WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) ';
setCorrespondingSuccesses.push(
  parenthesized('scoped-windows', parenthesizedInput + 'SELECT 0 AS a, 0 AS b UNION ALL '
    + '(FROM r |> AS original |> SET x = x + 10 |> SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY original.x), ROW_NUMBER() OVER (ORDER BY x DESC)) '
    + 'ORDER BY a, b'),
  parenthesized('nested-set', parenthesizedInput + 'SELECT 0 AS a, 0 AS b UNION ALL '
    + '(SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r '
    + 'UNION ALL SELECT 3 AS a, 4 AS b) ORDER BY a, b',
    {expected: [...windowRows, {a: 3, b: 4}]}),
  parenthesized('anonymous-aggregate', parenthesizedInput + 'SELECT 0 AS a, 0 AS b '
    + 'UNION ALL ((SELECT SUM(x), COUNT(x) FROM r)) ORDER BY a, b',
    // SUM has a nullable result even for a nonnullable argument: an empty
    // global group returns NULL. COUNT remains nonnullable; UNION joins both.
    {expected: [{a: 0, b: 0}, {a: 3, b: 2}],
      columns: [{name: 'a', contract: {...number, nullable: true}},
        {name: 'b', contract: number}]}),
  parenthesized('anonymous-scalars', parenthesizedInput + 'SELECT 0 AS a, 0 AS b '
    + 'UNION ALL (SELECT x + 10, -x FROM r) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}]}),
  parenthesized('source-windows', 'SELECT 0 AS a, 0 AS b UNION ALL '
    + '((SELECT ROW_NUMBER() OVER (ORDER BY id), ROW_NUMBER() OVER (ORDER BY id DESC) '
    + 'FROM records)) ORDER BY a, b',
    {format: 'sql', sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}], sourceReadSessionCount: 1}),
  parenthesized('typed-empty', 'WITH r AS (SELECT 1 AS x WHERE FALSE) '
    + 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r) '
    + 'ORDER BY a, b', {expected: []}),
);
setCorrespondingRefusals.push(
  {name: 'set-corresponding-refuse-parenthesized-by-name', format: 'aql-text',
    text: 'WITH r AS (SELECT 1 AS x) SELECT 0 AS a UNION ALL BY NAME '
      + '(SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r)',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'set-corresponding-refuse-parenthesized-authored-cte', format: 'aql-text',
    text: 'WITH r AS (SELECT 1 AS x), hidden AS '
      + '(SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r) '
      + 'SELECT 0 AS a UNION ALL (SELECT * FROM hidden)',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'set-corresponding-refuse-parenthesized-private-qualify', format: 'aql-text',
    text: 'WITH r AS (SELECT 1 AS x) SELECT 0 AS a UNION ALL '
      + '(SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r QUALIFY aql_analytic_output_1 > 0)',
    expectedCode: 'ClientProgramInvalidInput'},
);


// Independent input x=1,2: ORDER x DESC LIMIT 1 chooses x=2, whereas ORDER
// on the evaluated -x DESC chooses x=1. LIMIT/OFFSET stay inside the operand.
export const positionalOrderLimitProgram = {version: 'actql/0.1', id: 'fixture.positional_order_limit',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {sort: [{field: 'x', dir: 'desc', nulls: 'last'}]},
    {take: {count: 1, offset: 0}},
    {select: [{a: 'neg'}], as: 'right'},
    {values: {schema: {a: number}, rows: [{a: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const limited = (name, text, extra = {}) => success('positional-limited-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}], expected: [{a: -2}, {a: 0}], ...extra});
const limitedScalar = 'SELECT 0 AS a UNION ALL (SELECT -id FROM records ORDER BY ';
setCorrespondingSuccesses.push(
  limited('json-control', JSON.stringify(positionalOrderLimitProgram),
    {format: 'json', sourceReadSessionCount: 0}),
  limited('source-scalar', limitedScalar + 'id DESC LIMIT 1) ORDER BY a'),
  limited('ordinal-scalar', limitedScalar + '1 DESC LIMIT 1) ORDER BY a',
    {expected: [{a: -1}, {a: 0}]}),
  limited('parameter-offset', limitedScalar + 'id DESC LIMIT @take OFFSET @skip) ORDER BY a',
    {parameterDeclarations: {take: number, skip: number}, parameters: {take: 1, skip: 1},
      expected: [{a: -1}, {a: 0}]}),
  limited('source-window', 'SELECT 0 AS a UNION ALL (SELECT ROW_NUMBER() OVER (ORDER BY id) '
    + 'FROM records ORDER BY id DESC LIMIT 1) ORDER BY a', {expected: [{a: 0}, {a: 2}]}),
  limited('source-aggregate', 'SELECT 0 AS a, 0 AS b UNION ALL (SELECT SUM(id), COUNT(id) '
    + 'FROM records ORDER BY 1 DESC LIMIT 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 3, b: 2}]}),
  limited('duplicate-ordinal', 'SELECT 0 AS a, 0 AS b UNION ALL (SELECT id AS v, -id AS `V` '
    + 'FROM records ORDER BY 1 DESC LIMIT 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  limited('output-alias', 'SELECT 0 AS a UNION ALL (SELECT -id AS id FROM records '
    + 'ORDER BY id DESC LIMIT 1) ORDER BY a', {expected: [{a: -1}, {a: 0}]}),
  limited('qualified-input', 'SELECT 0 AS a UNION ALL (SELECT -id AS id FROM records '
    + 'ORDER BY records.id DESC LIMIT 1) ORDER BY a'),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_2', '`AQL_SET_ANONYMOUS_2`', 'aql_set_anonymous_2.member'].map((field, index) => ({
    name: 'set-corresponding-refuse-limited-private-' + index, format: 'sql',
    text: limitedScalar + field + ' LIMIT 1) ORDER BY a', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-limited-duplicate-alias', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (SELECT id AS v, -id AS `V` FROM records '
      + 'ORDER BY v LIMIT 1) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);


// Independent star control selects the evaluated negation twice without
// re-evaluation. The positional alignment gives it the public left name a.
export const positionalStarProgram = {version: 'actql/0.1', id: 'fixture.positional_star',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {select: ['neg']}, {select: ['neg']}, {select: [{a: 'neg'}], as: 'right'},
    {values: {schema: {a: number}, rows: [{a: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const starTail = (name, text, extra = {}) => success('positional-star-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}], expected: [{a: -2}, {a: -1}, {a: 0}], ...extra});
const starScalar = 'SELECT 0 AS a UNION ALL (FROM records |> SELECT -id |> SELECT *';
setCorrespondingSuccesses.push(
  starTail('json-control', JSON.stringify(positionalStarProgram), {format: 'json', sourceReadSessionCount: 0}),
  starTail('source-scalar', starScalar + ') ORDER BY a'),
  starTail('repeated-star-limit', starScalar + ' |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a',
    {expected: [{a: -1}, {a: 0}]}),
  starTail('distinct', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT -id |> SELECT DISTINCT *) ORDER BY a',
    {sourceRows: [{id: 2, amount: 20}, {id: 2, amount: 20}, {id: 1, amount: 10}]}),
  starTail('window', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT ROW_NUMBER() OVER (ORDER BY id) '
    + '|> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a', {expected: [{a: 0}, {a: 2}]}),
  starTail('aggregate', 'SELECT 0 AS a, 0 AS b UNION ALL (SELECT SUM(id), COUNT(id) FROM records |> SELECT *) ORDER BY a, b',
    {columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 3, b: 2}]}),
  starTail('duplicate-ordinal', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V` '
    + '|> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}], expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  starTail('nullable', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT -amount |> SELECT *) ORDER BY a NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: {...number, nullable: true}}], expected: [{a: -10}, {a: 0}, {a: null}]}),
  starTail('typed-empty', 'SELECT 0 AS a WHERE FALSE UNION ALL (FROM records |> SELECT -id |> SELECT *) ORDER BY a',
    {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_2', '`AQL_SET_ANONYMOUS_2`', 'aql_set_anonymous_2.member'].map((field, index) => ({
    name: 'set-corresponding-refuse-star-private-' + index, format: 'sql',
    text: starScalar + ' |> ORDER BY ' + field + ') ORDER BY a', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-star-duplicate-alias', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V` '
      + '|> SELECT * |> ORDER BY v) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);

// The right-hand filter cannot remove the left zero or regain discarded
// input columns. NULL is an unknown Boolean predicate, so it selects no rows.
export const positionalFilterProgram = {version: 'actql/0.1', id: 'fixture.positional_filter',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {select: [{a: 'neg'}]},
    {filter: {literal: false}, as: 'right'},
    {values: {schema: {a: number}, rows: [{a: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const filtered = (name, text, extra = {}) => limited('filtered-' + name, text,
  {format: 'aql-text', expected: [{a: 0}], ...extra});
const filteredHead = 'SELECT 0 AS a UNION ALL (FROM records |> SELECT -id |> WHERE ';
setCorrespondingSuccesses.push(
  filtered('json-control', JSON.stringify(positionalFilterProgram), {format: 'json', sourceReadSessionCount: 0}),
  filtered('false', filteredHead + 'FALSE) ORDER BY a'),
  filtered('true', filteredHead + 'TRUE) ORDER BY a', {expected: [{a: -2}, {a: -1}, {a: 0}]}),
  filtered('null-predicate', filteredHead + 'CAST(NULL AS BOOL)) ORDER BY a'),
  filtered('kept-alias', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS original '
    + '|> SELECT id AS kept, -id |> WHERE kept = 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 1, b: -1}]}),
  filtered('window', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY id), -id |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  filtered('duplicate-ordinal', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V` |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
      expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
);
setCorrespondingRefusals.push(
  ...['id', 'original.id', 'aql_set_anonymous_3'].map((receiver, index) => ({
    name: 'set-corresponding-refuse-filtered-receiver-' + index, format: 'aql-text',
    text: 'SELECT 0 AS a UNION ALL (FROM records |> AS original |> SELECT -id '
      + '|> WHERE ' + receiver + ' > 0) ORDER BY a', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-filtered-duplicate-alias', format: 'aql-text',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V` '
      + '|> WHERE v > 0) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);

// EXCEPT names authored columns; anonymous values remain ordinal-only. The
// independent JSON control projects already evaluated values before append.
export const positionalExclusionProgram = {version: 'actql/0.1', id: 'fixture.positional_exclusion',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {select: [{kept: 'x'}, 'neg']}, {select: ['neg']},
    {select: [{a: 'neg'}], as: 'right'},
    {values: {schema: {a: number}, rows: [{a: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const exclusion = (name, text, extra = {}) => success('positional-exclusion-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}], expected: [{a: -2}, {a: -1}, {a: 0}], ...extra});
const exclusionHead = 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, -id |> SELECT * EXCEPT (';
setCorrespondingSuccesses.push(
  exclusion('json-control', JSON.stringify(positionalExclusionProgram), {format: 'json', sourceReadSessionCount: 0}),
  exclusion('source-scalar', exclusionHead + 'kept)) ORDER BY a'),
  exclusion('quoted-repeated-limit', exclusionHead + '`KEPT`) |> SELECT * |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a',
    {expected: [{a: -1}, {a: 0}]}),
  exclusion('duplicate-aliases', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, id + 10 '
    + '|> SELECT * EXCEPT (v)) ORDER BY a', {expected: [{a: 0}, {a: 11}, {a: 12}]}),
  exclusion('distinct', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, -id |> SELECT DISTINCT * EXCEPT (kept)) ORDER BY a',
    {sourceRows: [{id: 2, amount: 20}, {id: 2, amount: 20}, {id: 1, amount: 10}]}),
  exclusion('analytic', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, ROW_NUMBER() OVER (ORDER BY id) '
    + '|> SELECT * EXCEPT (kept) |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a', {expected: [{a: 0}, {a: 2}]}),
  exclusion('global', 'SELECT 0 AS a UNION ALL (SELECT COUNT(id) AS kept, SUM(id) FROM records |> SELECT * EXCEPT (kept)) ORDER BY a',
    {columns: [{name: 'a', contract: {...number, nullable: true}}], expected: [{a: 0}, {a: 3}]}),
  exclusion('nullable', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, -amount |> SELECT * EXCEPT (kept)) ORDER BY a NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: {...number, nullable: true}}], expected: [{a: -10}, {a: 0}, {a: null}]}),
  exclusion('typed-empty', 'SELECT 0 AS a WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id |> SELECT * EXCEPT (kept)) ORDER BY a',
    {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_4', '`AQL_SET_ANONYMOUS_4`', 'missing'].map((field, index) => ({
    name: 'set-corresponding-refuse-exclusion-name-' + index, format: 'sql',
    text: exclusionHead + field + ')) ORDER BY a', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-exclusion-dropped-alias', format: 'sql',
    text: exclusionHead + 'kept) |> ORDER BY kept) ORDER BY a', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-exclusion-old-range', format: 'sql',
    text: 'SELECT 0 AS a UNION ALL (FROM records |> AS old |> SELECT id AS kept, -id '
      + '|> SELECT * EXCEPT (kept) |> ORDER BY old.id) ORDER BY a', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-exclusion-retained-duplicate', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, id + 10 AS dropped '
      + '|> SELECT * EXCEPT (dropped) |> ORDER BY v) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);

// REPLACE changes only the named value. The anonymous negation is evaluated
// before replacement and remains the second positional column.
export const positionalReplacementProgram = {version: 'actql/0.1', id: 'fixture.positional_replacement',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {select: [{kept: 'x'}, 'neg']},
    {derive: {changed: {add: [{field: 'kept'}, {literal: 10}]}}},
    {select: [{kept: 'changed'}, 'neg']},
    {select: [{a: 'kept'}, {b: 'neg'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const replacement = (name, text, extra = {}) => success('positional-replacement-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}], ...extra});
const replacementHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id |> SELECT * REPLACE (';
setCorrespondingSuccesses.push(
  replacement('json-control', JSON.stringify(positionalReplacementProgram), {format: 'json', sourceReadSessionCount: 0}),
  replacement('source-scalar', replacementHead + 'kept + 10 AS kept)) ORDER BY a, b'),
  replacement('quoted-chain-limit', replacementHead + 'kept + 10 AS `KEPT`) |> SELECT * |> WHERE kept > 11 |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 12, b: -2}]}),
  replacement('simultaneous', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS first, amount AS second, -id |> SELECT * REPLACE (second AS first, first AS second)) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 10, b: 1, c: -1}, {a: 20, b: 2, c: -2}]}),
  replacement('excluded-names', 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS dropped, amount AS kept, -id '
    + '|> SELECT * EXCEPT (dropped) REPLACE (kept + 1 AS kept) |> SELECT * EXCEPT (kept)) ORDER BY a',
    {columns: [{name: 'a', contract: number}], expected: [{a: -2}, {a: -1}, {a: 0}]}),
  replacement('retained-duplicates', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept |> SELECT * REPLACE (kept + 1 AS kept)) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 12}, {a: 2, b: -2, c: 13}]}),
  replacement('distinct', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> SELECT DISTINCT * REPLACE (0 AS kept)) ORDER BY a, b',
    {sourceRows: [{id: 2, amount: 20}, {id: 2, amount: 20}, {id: 1, amount: 10}],
      expected: [{a: 0, b: -2}, {a: 0, b: -1}, {a: 0, b: 0}]}),
  replacement('nullable', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount '
    + '|> SELECT * REPLACE (kept + 10 AS kept)) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0}, {a: 11, b: -10}, {a: 12, b: null}]}),
  replacement('value-type', "SELECT 'anchor' AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id "
    + "|> SELECT * REPLACE ('changed' AS kept)) ORDER BY a, b",
    // Literal UTF-8 bounds are 6 for anchor and 7 for changed; append keeps 7.
    {columns: [{name: 'a', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}}, {name: 'b', contract: number}],
      expected: [{a: 'anchor', b: 0}, {a: 'changed', b: -2}, {a: 'changed', b: -1}]}),
  replacement('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> SELECT * REPLACE (kept + 10 AS kept)) ORDER BY a, b', {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['0 AS aql_set_anonymous_4', '0 AS `AQL_SET_ANONYMOUS_4`', 'kept + aql_set_anonymous_4 AS kept', '1 AS kept, 2 AS `KEPT`'].map((value, index) => ({
    name: 'set-corresponding-refuse-replacement-private-' + index, format: 'sql',
    text: replacementHead + value + ')) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput',
  })),
  ...['0 AS v', 'v + 1 AS kept'].map((value, index) => ({
    name: 'set-corresponding-refuse-replacement-ambiguous-' + index, format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, id + 10 AS kept '
      + '|> SELECT * REPLACE (' + value + ')) ORDER BY a, b, c', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-replacement-excluded-target', format: 'sql',
    text: 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, -id '
      + '|> SELECT * EXCEPT (kept) REPLACE (0 AS kept)) ORDER BY a', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-replacement-old-range', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS old |> SELECT id AS kept, -id '
      + '|> SELECT * REPLACE (old.id AS kept)) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);

// Window replacement reads the current named input and retains the anonymous
// value. The JSON control uses existing analytic/projection operations only.
export const positionalWindowReplacementProgram = {version: 'actql/0.1', id: 'fixture.positional_window_replacement',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'x'}}}},
    {select: [{kept: 'x'}, 'neg']},
    {analytic: {partition_by: [], order_by: [{field: 'kept', dir: 'desc', nulls: 'last'}], functions: {rank: {fn: 'row_number'}}}},
    {select: [{a: 'rank'}, {b: 'neg'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const windowReplacement = (name, text, extra = {}) => success('positional-analytic-replacement-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 1, b: -2}, {a: 2, b: -1}], ...extra});
const windowReplacementHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id |> SELECT * REPLACE (';
setCorrespondingSuccesses.push(
  windowReplacement('json-control', JSON.stringify(positionalWindowReplacementProgram), {format: 'json', sourceReadSessionCount: 0}),
  windowReplacement('source', windowReplacementHead + 'ROW_NUMBER() OVER (ORDER BY kept DESC) AS kept)) ORDER BY a, b'),
  windowReplacement('expression', windowReplacementHead + 'ROW_NUMBER() OVER (ORDER BY kept DESC) + 5 AS kept)) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 6, b: -2}, {a: 7, b: -1}]}),
  windowReplacement('named-window-filter', windowReplacementHead + 'ROW_NUMBER() OVER w AS `KEPT`) WINDOW w AS (ORDER BY kept DESC) '
    + '|> SELECT * |> WHERE kept > 1) ORDER BY a, b', {expected: [{a: 0, b: 0}, {a: 2, b: -1}]}),
  windowReplacement('opposing-windows', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS first, amount AS second, -id |> SELECT * REPLACE '
    + '(ROW_NUMBER() OVER (ORDER BY first DESC) AS first, ROW_NUMBER() OVER (ORDER BY second) AS second)) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: 2, c: -2}, {a: 2, b: 1, c: -1}]}),
  windowReplacement('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY kept DESC) AS kept)) ORDER BY a, b', {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  {name: 'set-corresponding-refuse-analytic-replacement-private', format: 'sql',
    text: windowReplacementHead + 'ROW_NUMBER() OVER (ORDER BY aql_set_anonymous_4) AS kept)) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-analytic-replacement-old-range', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS old |> SELECT id AS kept, -id '
      + '|> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY old.id) AS kept)) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-analytic-replacement-ambiguous', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, amount AS kept '
      + '|> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY v) AS kept)) ORDER BY a, b, c', expectedCode: 'ClientProgramInvalidInput'},
);

// SET reads the pre-assignment snapshot; anonymous values retain their ordinal.
const positionalSet = (name, text, extra = {}) => success('positional-pipe-set-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}], ...extra});
const positionalSetHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id |> SET ';
setCorrespondingSuccesses.push(
  positionalSet('json-control', JSON.stringify(positionalReplacementProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalSet('source', positionalSetHead + 'kept = kept + 10) ORDER BY a, b'),
  // Current -id selects original id=1. Reusing the earlier -id selects id=2.
  positionalSet('current-expression-limit', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS id, -id |> SET id = -id |> ORDER BY -id |> LIMIT 1) ORDER BY a, b',
    {expected: [{a: -1, b: -1}, {a: 0, b: 0}]}),
  positionalSet('quoted-chain-limit', positionalSetHead + '`KEPT` = kept + 10 |> WHERE kept > 11 |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 12, b: -2}]}),
  positionalSet('simultaneous', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS first, amount AS second, -id |> SET first = second, second = first) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 10, b: 1, c: -1}, {a: 20, b: 2, c: -2}]}),
  positionalSet('retained-duplicates', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept |> SET kept = kept + 1) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 12}, {a: 2, b: -2, c: 13}]}),
  positionalSet('nullable', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount '
    + '|> SET kept = kept + 10) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0}, {a: 11, b: -10}, {a: 12, b: null}]}),
  positionalSet('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> SET kept = kept + 10) ORDER BY a, b', {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_4 = 0', '`AQL_SET_ANONYMOUS_4` = 0', 'kept = aql_set_anonymous_4 + 1', 'kept = 1, `KEPT` = 2'].map((value, index) => ({
    name: 'set-corresponding-refuse-pipe-set-private-' + index, format: 'sql',
    text: positionalSetHead + value + ') ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput',
  })),
  ...['v = 0', 'kept = v + 1'].map((value, index) => ({
    name: 'set-corresponding-refuse-pipe-set-ambiguous-' + index, format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, id + 10 AS kept '
      + '|> SET ' + value + ') ORDER BY a, b, c', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-pipe-set-old-range', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS old |> SELECT id AS kept, -id '
      + '|> SET kept = old.id) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);


// DROP removes authored names, retaining anonymous values at their positions.
export const positionalDropProgram = {version: 'actql/0.1', id: 'fixture.positional_drop',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, amount: number}, rows: [{id: 2, amount: 20}, {id: 1, amount: 10}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'id'}}}},
    {select: [{kept: 'id'}, {removed: 'amount'}, 'neg']},
    {drop: ['removed']}, {select: [{a: 'kept'}, {b: 'neg'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const positionalDrop = (name, text, extra = {}) => success('positional-pipe-drop-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 1, b: -1}, {a: 2, b: -2}], ...extra});
const positionalDropHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, amount AS removed, -id |> DROP ';
setCorrespondingSuccesses.push(
  positionalDrop('json-control', JSON.stringify(positionalDropProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalDrop('source', positionalDropHead + 'removed) ORDER BY a, b'),
  positionalDrop('duplicates-removed', 'SELECT 0 AS a UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 |> DROP `v`) ORDER BY a',
    {columns: [{name: 'a', contract: number}], expected: [{a: 0}, {a: 11}, {a: 12}]}),
  positionalDrop('duplicates-retained', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, amount AS removed |> DROP removed) ORDER BY a, b'),
  positionalDrop('chain-ordinal-limit', 'SELECT 0 AS a UNION ALL (FROM records '
    + '|> SELECT id AS first, amount AS second, -id |> DROP first |> DROP `SECOND` '
    + '|> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a',
    {columns: [{name: 'a', contract: number}], expected: [{a: -1}, {a: 0}]}),
  positionalDrop('filter-expression-limit', positionalDropHead + 'removed |> WHERE kept > 1 |> ORDER BY -kept |> LIMIT 1) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  positionalDrop('nullable', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, id + 10 AS removed, -amount '
    + '|> DROP removed) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: null}]}),
  positionalDrop('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, amount AS removed, -id '
    + '|> DROP removed) ORDER BY a, b', {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_6', '`AQL_SET_ANONYMOUS_6`', 'removed, `REMOVED`'].map((value, index) => ({
    name: 'set-corresponding-refuse-pipe-drop-target-' + index, format: 'sql',
    text: positionalDropHead + value + ') ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-pipe-drop-removed', format: 'sql',
    text: 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS kept, -id |> DROP kept |> WHERE kept > 0) ORDER BY a',
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-drop-input-order', format: 'sql',
    text: 'SELECT 0 AS a UNION ALL (FROM records |> SELECT id AS id, -id |> DROP id |> ORDER BY id) ORDER BY a',
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-drop-old-range', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS old |> SELECT id AS kept, amount AS removed, -id '
      + '|> DROP removed |> WHERE old.id > 0) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-drop-ambiguous-order', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, amount AS removed '
      + '|> DROP removed |> ORDER BY v) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
);

// RENAME changes authored lookup, retaining values and their ordinal positions.
// This ordinary JSON control is authored independently of text lowering.
export const positionalRenameProgram = {version: 'actql/0.1', id: 'fixture.positional_rename',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: [{id: 2}, {id: 1}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'id'}}}},
    {select: [{kept: 'id'}, 'neg']},
    {select: [{renamed: 'kept'}, 'neg']},
    {select: [{a: 'renamed'}, {b: 'neg'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const positionalRename = (name, text, extra = {}) => success('positional-pipe-rename-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 1, b: -1}, {a: 2, b: -2}], ...extra});
const positionalRenameHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id |> RENAME ';
setCorrespondingSuccesses.push(
  positionalRename('json-control', JSON.stringify(positionalRenameProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalRename('source', positionalRenameHead + 'kept AS renamed) ORDER BY a, b'),
  // WHERE and ORDER must use renamed -id, not the original positive input id.
  positionalRename('current-expression-limit', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT -id AS kept, id + 10 |> RENAME kept AS id |> WHERE id < 0 |> ORDER BY -id |> LIMIT 1) ORDER BY a, b',
    {expected: [{a: -1, b: 11}, {a: 0, b: 0}]}),
  positionalRename('quoted-chain', positionalRenameHead + '`KEPT` AS first |> RENAME first AS result '
    + '|> WHERE result > 1) ORDER BY a, b', {expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  positionalRename('introduced-duplicates', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS kept, amount AS other, -id |> RENAME other AS kept |> ORDER BY 2 DESC |> LIMIT 1) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 2, b: 20, c: -2}]}),
  positionalRename('private-shaped-anonymous-destination', positionalRenameHead + 'kept AS `AQL_SET_ANONYMOUS_4` '
    + '|> WHERE aql_set_anonymous_4 > 1) ORDER BY a, b', {expected: [{a: 0, b: 0}, {a: 2, b: -2}]}),
  positionalRename('private-shaped-duplicate-destination', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept |> RENAME kept AS `AQL_SET_DUPLICATE_5` '
    + '|> WHERE aql_set_duplicate_5 > 11) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 2, b: -2, c: 12}]}),
  positionalRename('introduced-duplicates-drop', 'SELECT 0 AS a UNION ALL (FROM records '
    + '|> SELECT id AS first, amount AS second, -id |> RENAME first AS kept, second AS kept |> DROP kept) ORDER BY a',
    {columns: [{name: 'a', contract: number}], expected: [{a: -2}, {a: -1}, {a: 0}]}),
  positionalRename('nullable', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount '
    + '|> RENAME kept AS renamed) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: null}]}),
  positionalRename('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> RENAME kept AS renamed) ORDER BY a, b', {sourceRows: [], expected: []}),
);
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_4 AS next', '`AQL_SET_ANONYMOUS_4` AS next', 'kept AS first, `KEPT` AS second'].map((value, index) => ({
    name: 'set-corresponding-refuse-pipe-rename-target-' + index, format: 'sql',
    text: positionalRenameHead + value + ') ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-pipe-rename-original-duplicate', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V` '
      + '|> RENAME v AS changed) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  ...['WHERE kept > 0', 'RENAME kept AS changed'].map((tail, index) => ({
    name: 'set-corresponding-refuse-pipe-rename-introduced-duplicate-' + index, format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS kept, amount AS other, -id '
      + '|> RENAME other AS kept |> ' + tail + ') ORDER BY a, b, c', expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'set-corresponding-refuse-pipe-rename-removed', format: 'sql',
    text: positionalRenameHead + 'kept AS renamed |> WHERE kept > 0) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-rename-old-range', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> AS old |> SELECT id AS kept, -id '
      + '|> RENAME kept AS renamed |> WHERE old.id > 0) ORDER BY a, b', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-rename-anonymous-private-value', format: 'sql',
    text: positionalRenameHead + 'kept AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_5 > 0) ORDER BY a, b',
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'set-corresponding-refuse-pipe-rename-duplicate-private-value', format: 'sql',
    text: 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS v, -id AS `V`, id + 10 AS kept '
      + '|> RENAME kept AS aql_set_duplicate_5 |> WHERE aql_set_duplicate_6 > 0) ORDER BY a, b, c',
    expectedCode: 'ClientProgramInvalidInput'},
);


// Pure Pipe tails retain ordinal values; only authored names qualify a range.
export const positionalExtendProgram = {version: 'actql/0.1', id: 'fixture.positional_extend',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: [{id: 2}, {id: 1}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'id'}}}},
    {select: [{kept: 'id'}, 'neg']},
    {derive: {extra: {add: [{field: 'kept'}, {literal: 10}]}}},
    {select: [{a: 'kept'}, {b: 'neg'}, {c: 'extra'}], as: 'right'},
    {values: {schema: {a: number, b: number, c: number}, rows: [{a: 0, b: 0, c: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'},
      {field: 'c', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b', 'c']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const positionalAsProgram = {version: 'actql/0.1', id: 'fixture.positional_as',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: [{id: 2}, {id: 1}]}, as: 'input'},
    {from: 'input', derive: {neg: {negate: {field: 'id'}}}},
    {select: [{kept: 'id'}, 'neg']},
    {filter: {gt: [{field: 'kept'}, {literal: 1}]}},
    {select: [{a: 'kept'}, {b: 'neg'}], as: 'right'},
    {values: {schema: {a: number, b: number}, rows: [{a: 0, b: 0}]}, as: 'left'},
    {from: 'left', append: {with: 'right'}},
    {sort: [{field: 'a', dir: 'asc', nulls: 'first'}, {field: 'b', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['a', 'b']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const pureTailColumns = [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}];
const pureTail = (name, text, extra = {}) => success('positional-pure-tail-' + name, text,
  {sourceRows: [{id: 2, amount: 20}, {id: 1, amount: 10}], columns: pureTailColumns,
    expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 11}, {a: 2, b: -2, c: 12}], ...extra});
const asTail = (name, text, extra = {}) => pureTail(name, text,
  {columns: pureTailColumns.slice(0, 2), expected: [{a: 0, b: 0}, {a: 2, b: -2}], ...extra});
const pureExtendHead = 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS kept, -id |> EXTEND ';
const pureAsHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id |> AS ';
setCorrespondingSuccesses.push(
  pureTail('extend-json-control', JSON.stringify(positionalExtendProgram), {format: 'json', sourceReadSessionCount: 0}),
  asTail('as-json-control', JSON.stringify(positionalAsProgram), {format: 'json', sourceReadSessionCount: 0}),
  pureTail('extend-source', pureExtendHead + 'kept + 10 AS extra) ORDER BY a, b, c'),
  asTail('as-source', pureAsHead + 'r |> WHERE r.kept > 1) ORDER BY a, b', {format: 'aql-text'}),
  // Current kept is negative. Original positive id would remove these rows.
  pureTail('extend-current-parameter-limit', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT -id AS kept, id + 10 |> EXTEND kept + @bump AS extra |> WHERE kept < 0 '
    + '|> ORDER BY -kept |> LIMIT 1) ORDER BY a, b, c',
    {parameterDeclarations: {bump: number}, parameters: {bump: 10}, expected: [{a: -1, b: 11, c: 9}, {a: 0, b: 0, c: 0}]}),
  pureTail('extend-siblings', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS kept, -id |> EXTEND kept + 1 AS first, kept + 10 AS second) ORDER BY a, b, c, d',
    {columns: [...pureTailColumns, {name: 'd', contract: number}],
      expected: [{a: 0, b: 0, c: 0, d: 0}, {a: 1, b: -1, c: 2, d: 11}, {a: 2, b: -2, c: 3, d: 12}]}),
  pureTail('extend-private-shaped-anonymous-destination', pureExtendHead + 'kept + 10 AS `AQL_SET_ANONYMOUS_4` '
    + '|> AS r |> WHERE r.aql_set_anonymous_4 > 11) ORDER BY a, b, c',
    {expected: [{a: 0, b: 0, c: 0}, {a: 2, b: -2, c: 12}]}),
  pureTail('extend-private-shaped-duplicate-destination', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept |> EXTEND kept + 1 AS `AQL_SET_DUPLICATE_5` '
    + '|> AS r |> WHERE r.aql_set_duplicate_5 > 12) ORDER BY a, b, c, d',
    {columns: [...pureTailColumns, {name: 'd', contract: number}], expected: [{a: 0, b: 0, c: 0, d: 0}, {a: 2, b: -2, c: 12, d: 13}]}),
  asTail('as-immutable-set', pureAsHead + 'r |> SET kept = kept + 10 |> WHERE r.kept = 2) ORDER BY a, b',
    {expected: [{a: 0, b: 0}, {a: 12, b: -2}]}),
  asTail('as-quoted-rebind', pureAsHead + '`First` |> AS `Second` |> WHERE second.kept > 1) ORDER BY a, b'),
  asTail('as-private-shaped-authored-column', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS aql_set_anonymous_4, -id |> AS r |> WHERE r.aql_set_anonymous_4 > 1) ORDER BY a, b'),
  pureTail('extend-window', pureExtendHead + 'ROW_NUMBER() OVER (ORDER BY kept DESC) AS rank) ORDER BY a, b, c',
    {expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 2}, {a: 2, b: -2, c: 1}]}),
  pureTail('nullable', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS kept, -amount '
    + '|> EXTEND kept + 10 AS extra |> AS r |> WHERE r.kept > 0) ORDER BY a, b NULLS LAST, c',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [pureTailColumns[0], {name: 'b', contract: {...number, nullable: true}}, pureTailColumns[2]],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 11}, {a: 2, b: null, c: 12}]}),
  pureTail('typed-empty', 'SELECT 0 AS a, 0 AS b, 0 AS c WHERE FALSE UNION ALL (FROM records '
    + '|> SELECT id AS kept, -id |> EXTEND kept + 10 AS extra |> AS r) ORDER BY a, b, c', {sourceRows: [], expected: []}),
);
const refusePureTail = (name, text) => ({name: 'set-corresponding-refuse-pure-tail-' + name,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  ...['aql_set_anonymous_4 + 1 AS extra', '`AQL_SET_ANONYMOUS_4` + 1 AS extra'].map((value, index) =>
    refusePureTail('extend-private-' + index, pureExtendHead + value + ') ORDER BY a, b, c')),
  refusePureTail('extend-ambiguous', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V` |> EXTEND v + 1 AS extra) ORDER BY a, b, c'),
  refusePureTail('extend-duplicate-destination', pureExtendHead + 'kept + 1 AS kept) ORDER BY a, b, c'),
  refusePureTail('extend-sibling', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS kept, -id |> EXTEND kept + 1 AS first, first + 1 AS second) ORDER BY a, b, c, d'),
  refusePureTail('extend-dropped-input', pureExtendHead + 'id + 1 AS extra) ORDER BY a, b, c'),
  refusePureTail('as-displaced', pureAsHead + 'first |> AS second |> WHERE first.kept > 0) ORDER BY a, b'),
  refusePureTail('as-dropped-input', pureAsHead + 'r |> WHERE r.id > 0) ORDER BY a, b'),
  ...['aql_set_anonymous_4', '`AQL_SET_ANONYMOUS_4`'].map((name, index) =>
    refusePureTail('as-private-' + index, pureAsHead + 'r |> WHERE r.' + name + ' > 0) ORDER BY a, b')),
  refusePureTail('reserved-anonymous-private', pureExtendHead + 'kept + 10 AS aql_set_anonymous_4 '
    + '|> AS r |> WHERE r.aql_set_anonymous_5 > 0) ORDER BY a, b, c'),
  refusePureTail('reserved-duplicate-private', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept |> EXTEND kept + 1 AS aql_set_duplicate_5 '
    + '|> AS r |> WHERE r.aql_set_duplicate_6 > 0) ORDER BY a, b, c, d'),
  ...['WHERE r.v > 0', 'EXTEND r.v + 1 AS extra |> DROP extra'].map((tail, index) =>
    refusePureTail('as-ambiguous-' + index, 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
      + '|> SELECT id AS v, -id AS `V` |> AS r |> ' + tail + ') ORDER BY a, b')),
  refusePureTail('undeclared-parameter', pureExtendHead + 'kept + @missing AS extra) ORDER BY a, b, c'),
);

// A hidden ORDER window consumes the current projected snapshot, not discarded input.
export const positionalOrderWindowProgram = {"version":"actql/0.1","id":"fixture.positional_order_window","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},"neg"]},{"analytic":{"partition_by":[],"order_by":[{"field":"kept","dir":"desc","nulls":"last"}],"functions":{"position":{"fn":"row_number"}}}},{"sort":[{"field":"position","dir":"asc","nulls":"first"}]},{"take":{"count":1,"offset":0}},{"select":[{"a":"kept"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const orderWindow = (name, text, extra = {}) => success('positional-order-window-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}],
    columns: [{name: 'a', contract: number}, {name: 'b', contract: number}],
    expected: [{a: 0, b: 0}, {a: 2, b: -2}], ...extra});
const positionalOrderHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -id ';
setCorrespondingSuccesses.push(
  orderWindow('json-control', JSON.stringify(positionalOrderWindowProgram), {format: 'json', sourceReadSessionCount: 0}),
  orderWindow('source', positionalOrderHead + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a, b'),
  orderWindow('immutable-range', positionalOrderHead + '|> AS r |> SET kept = -kept '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY r.kept DESC) |> LIMIT 1) ORDER BY a, b',
    {format: 'aql-text', expected: [{a: -2, b: -2}, {a: 0, b: 0}]}),
  orderWindow('scalar-parameter-offset', positionalOrderHead
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept) + @shift DESC |> LIMIT 1 OFFSET 1) ORDER BY a, b',
    {sourceRows: [{id: 3, amount: 30}, {id: 1, amount: 10}, {id: 2, amount: 20}],
      parameterDeclarations: {shift: number}, parameters: {shift: 10}}),
  orderWindow('duplicate-authored-columns', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, id + 10 AS kept '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a, b, c',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: 0, b: 0, c: 0}, {a: 2, b: -2, c: 12}]}),
  orderWindow('private-shaped-authored-column', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS aql_order_window_0, -id '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY aql_order_window_0 DESC) |> LIMIT 1) ORDER BY a, b'),
  orderWindow('nullable', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0}, {a: 2, b: null}]}),
  orderWindow('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records |> SELECT id AS kept, -id '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a, b', {sourceRows: [], expected: []}),
);
const refuseOrderWindow = (name, text) => ({name: 'set-corresponding-refuse-order-window-' + name,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refuseOrderWindow('private-anonymous', positionalOrderHead
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY aql_set_anonymous_4) |> LIMIT 1) ORDER BY a, b'),
  refuseOrderWindow('dropped-input', positionalOrderHead
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY id) |> LIMIT 1) ORDER BY a, b'),
  refuseOrderWindow('ambiguous', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS v, -id AS `V` '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY v) |> LIMIT 1) ORDER BY a, b'),
  refuseOrderWindow('displaced-range', positionalOrderHead + '|> AS before |> AS current '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY before.kept) |> LIMIT 1) ORDER BY a, b'),
  refuseOrderWindow('private-window', positionalOrderHead + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY kept) '
    + '|> WHERE aql_order_window_0 > 0) ORDER BY a, b'),
  refuseOrderWindow('qualified-private-anonymous', positionalOrderHead + '|> AS r '
    + '|> ORDER BY ROW_NUMBER() OVER (ORDER BY r.aql_set_anonymous_4) |> LIMIT 1) ORDER BY a, b'),
);

// DISTINCT compares both named and anonymous occurrences, not just authored keys.
export const positionalDistinctProgram = {"version":"actql/0.1","id":"fixture.positional_distinct","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":1,"y":20},{"x":1,"y":10}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}}}},{"select":[{"kept":"x"},"neg"]},{"distinct":["kept","neg"]},{"select":[{"a":"kept"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const positionalDistinctColumns = [{name: 'a', contract: number},
  {name: 'b', contract: {...number, nullable: true}}];
const positionalDistinct = (name, text, extra = {}) => success('positional-pipe-distinct-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 1, amount: 20}, {id: 1, amount: 10}],
    columns: positionalDistinctColumns, expected: [{a: 0, b: 0}, {a: 1, b: -20}, {a: 1, b: -10}], ...extra});
const positionalDistinctHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount ';
setCorrespondingSuccesses.push(
  positionalDistinct('json-control', JSON.stringify(positionalDistinctProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalDistinct('anonymous-source', positionalDistinctHead + '|> DISTINCT) ORDER BY a, b NULLS LAST'),
  positionalDistinct('duplicate-aliases', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> DISTINCT) ORDER BY a, b NULLS LAST'),
  positionalDistinct('surviving-range', positionalDistinctHead + '|> AS r |> DISTINCT '
    + '|> WHERE r.kept > 0) ORDER BY a, b NULLS LAST', {format: 'aql-text'}),
  positionalDistinct('displaced-value-not-an-equality-key', positionalDistinctHead + '|> AS r |> SET kept = 1 '
    + '|> DISTINCT) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 2, amount: 10}, {id: 1, amount: 10}], expected: [{a: 0, b: 0}, {a: 1, b: -10}]}),
  // DROP follows DISTINCT. Different complete rows can become equal afterward.
  positionalDistinct('drop-keeps-result-multiplicity', 'SELECT 0 AS a UNION ALL (FROM records '
    + '|> SELECT id AS v, -id AS `V`, amount + 1 |> DISTINCT |> DROP v) ORDER BY a',
    {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 10}, {id: 1, amount: 10}],
      columns: [{name: 'a', contract: {...number, nullable: true}}], expected: [{a: 0}, {a: 11}, {a: 11}]}),
  positionalDistinct('nullable', positionalDistinctHead + '|> DISTINCT) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 1, amount: null}, {id: 1, amount: 10}, {id: 1, amount: null}],
      expected: [{a: 0, b: 0}, {a: 1, b: -10}, {a: 1, b: null}]}),
  positionalDistinct('typed-empty', 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (FROM records '
    + '|> SELECT id AS kept, -amount |> DISTINCT) ORDER BY a, b NULLS LAST', {sourceRows: [], expected: []}),
  positionalDistinct('parameter-order-limit', positionalDistinctHead + '|> DISTINCT |> WHERE kept > @min '
    + '|> ORDER BY -kept, 2 ASC NULLS LAST |> LIMIT 1 OFFSET @skip) ORDER BY a, b NULLS LAST',
    {sourceRows: [{id: 1, amount: 10}, {id: 1, amount: 20}, {id: 2, amount: 30}, {id: 2, amount: 30}],
      parameterDeclarations: {min: number, skip: number}, parameters: {min: 0, skip: 1},
      expected: [{a: 0, b: 0}, {a: 1, b: -20}]}),
);
const refusePositionalDistinct = (name, text) => ({name: 'set-corresponding-refuse-pipe-distinct-' + name,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refusePositionalDistinct('private-anonymous', positionalDistinctHead
    + '|> DISTINCT |> WHERE aql_set_anonymous_4 > 0) ORDER BY a, b'),
  refusePositionalDistinct('ambiguous', 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> DISTINCT |> WHERE v > 0) ORDER BY a, b'),
  refusePositionalDistinct('dropped-input', positionalDistinctHead + '|> DISTINCT |> WHERE amount > 0) ORDER BY a, b'),
  refusePositionalDistinct('displaced-range', positionalDistinctHead + '|> AS before |> AS current '
    + '|> DISTINCT |> WHERE before.kept > 0) ORDER BY a, b'),
  refusePositionalDistinct('pruned-range-value', positionalDistinctHead + '|> AS r |> SET kept = 1 '
    + '|> DISTINCT |> WHERE r.kept > 0) ORDER BY a, b'),
  refusePositionalDistinct('qualified-private-anonymous', positionalDistinctHead + '|> AS r '
    + '|> DISTINCT |> WHERE r.aql_set_anonymous_4 > 0) ORDER BY a, b'),
);

// Correlated UNNEST expands current occurrences without renaming anonymous values.
export const positionalUnnestProgram = {"version":"actql/0.1","id":"fixture.positional_unnest","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":2,"y":20}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}}}},{"select":[{"kept":"x"},"neg"]},{"derive":{"items":{"array":[{"literal":10},{"literal":20}]}}},{"unnest":{"column":"items","as":"element"}},{"select":[{"a":"kept"},{"b":"neg"},{"c":"element"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false},"c":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0,"c":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"},{"field":"c","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b","c"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const positionalUnnestColumns = [{name: 'a', contract: number},
  {name: 'b', contract: {...number, nullable: true}}, {name: 'c', contract: number}];
const positionalUnnest = (name, text, extra = {}) => success('positional-pipe-unnest-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}], columns: positionalUnnestColumns,
    expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 10}, {a: 1, b: -10, c: 20},
      {a: 2, b: -20, c: 10}, {a: 2, b: -20, c: 20}], ...extra});
const positionalUnnestHead = 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records |> SELECT id AS kept, -amount ';
const positionalUnnestTail = '|> SELECT *) ORDER BY a, b NULLS LAST, c NULLS LAST';
setCorrespondingSuccesses.push(
  positionalUnnest('json-control', JSON.stringify(positionalUnnestProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalUnnest('anonymous-source', positionalUnnestHead + '|> CROSS JOIN UNNEST([10,20]) AS element ' + positionalUnnestTail),
  positionalUnnest('duplicate-aliases', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> CROSS JOIN UNNEST([10,20]) AS element ' + positionalUnnestTail),
  positionalUnnest('current-values-offset', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS kept, -amount |> CROSS JOIN UNNEST([kept,kept+1]) AS element WITH OFFSET position '
    + '|> SELECT *) ORDER BY a, b NULLS LAST, c, d', {format: 'aql-text',
      columns: [...positionalUnnestColumns, {name: 'd', contract: number}],
      expected: [{a: 0, b: 0, c: 0, d: 0}, {a: 1, b: -10, c: 1, d: 0}, {a: 1, b: -10, c: 2, d: 1},
        {a: 2, b: -20, c: 2, d: 0}, {a: 2, b: -20, c: 3, d: 1}]}),
  positionalUnnest('immutable-range', positionalUnnestHead + '|> AS r |> SET kept = 7 '
    + '|> CROSS JOIN UNNEST([r.kept]) AS element ' + positionalUnnestTail,
    {expected: [{a: 0, b: 0, c: 0}, {a: 7, b: -20, c: 2}, {a: 7, b: -10, c: 1}]}),
  positionalUnnest('inner-predicate', positionalUnnestHead + '|> INNER JOIN UNNEST([NULL,1,2]) AS element ON element = kept '
    + positionalUnnestTail, {columns: [...positionalUnnestColumns.slice(0, 2), {name: 'c', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 1}, {a: 2, b: -20, c: 2}]}),
  positionalUnnest('nullable-elements', positionalUnnestHead + '|> CROSS JOIN UNNEST([10,NULL]) AS element ' + positionalUnnestTail,
    {columns: [...positionalUnnestColumns.slice(0, 2), {name: 'c', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 10}, {a: 1, b: -10, c: null},
        {a: 2, b: -20, c: 10}, {a: 2, b: -20, c: null}]}),
  positionalUnnest('duplicate-elements', positionalUnnestHead + '|> CROSS JOIN UNNEST([10,10]) AS element ' + positionalUnnestTail,
    {expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 10}, {a: 1, b: -10, c: 10},
      {a: 2, b: -20, c: 10}, {a: 2, b: -20, c: 10}]}),
  positionalUnnest('typed-empty', 'SELECT 0 AS a, 0 AS b, 0 AS c WHERE FALSE UNION ALL (FROM records '
    + '|> SELECT id AS kept, -amount |> CROSS JOIN UNNEST([10,20]) AS element ' + positionalUnnestTail,
    {sourceRows: [], expected: []}),
  positionalUnnest('private-shaped-element', positionalUnnestHead + '|> CROSS JOIN UNNEST([10,20]) AS aql_set_anonymous_4 '
    + '|> WHERE aql_set_anonymous_4 > 0 ' + positionalUnnestTail),
  positionalUnnest('private-shaped-offset', 'SELECT 0 AS a, 0 AS b, 0 AS c, 0 AS d UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> CROSS JOIN UNNEST([10]) AS element WITH OFFSET aql_set_duplicate_2 '
    + '|> SELECT *) ORDER BY a, b NULLS LAST, c, d',
    {columns: [...positionalUnnestColumns, {name: 'd', contract: number}],
      expected: [{a: 0, b: 0, c: 0, d: 0}, {a: 1, b: -10, c: 10, d: 0}, {a: 2, b: -20, c: 10, d: 0}]}),
  positionalUnnest('nullable-parent', positionalUnnestHead + '|> CROSS JOIN UNNEST([10,20]) AS element ' + positionalUnnestTail,
    {sourceRows: [{id: 1, amount: null}], expected: [{a: 0, b: 0, c: 0},
      {a: 1, b: null, c: 10}, {a: 1, b: null, c: 20}]}),
);
const refusePositionalUnnest = (name, text) => ({name: 'set-corresponding-refuse-pipe-unnest-' + name,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refusePositionalUnnest('private-anonymous', positionalUnnestHead + '|> CROSS JOIN UNNEST([aql_set_anonymous_4]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('ambiguous', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> CROSS JOIN UNNEST([v]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('qualified-ambiguous', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS v, -amount AS `V` |> AS r |> CROSS JOIN UNNEST([r.v]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('dropped-input', positionalUnnestHead + '|> CROSS JOIN UNNEST([amount]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('old-range', positionalUnnestHead + '|> CROSS JOIN UNNEST([records.id]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('qualified-private-anonymous', positionalUnnestHead + '|> AS r '
    + '|> CROSS JOIN UNNEST([r.aql_set_anonymous_4]) AS element ' + positionalUnnestTail),
  refusePositionalUnnest('non-array', positionalUnnestHead + '|> CROSS JOIN UNNEST(kept) AS element ' + positionalUnnestTail),
);

// Kept anonymous occurrences retain ordinal meaning through ordinary UNPIVOT.
export const positionalUnpivotProgram = {"version":"actql/0.1","id":"fixture.positional_unpivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":2,"y":20}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}}}},{"select":[{"kept":"x"},"neg"]},{"unpivot":{"columns":["kept"],"keep":["neg"],"value_column":"value","name_column":"label"}},{"select":[{"a":"neg"},{"b":"value"},{"c":"label"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false},"c":{"type":"string","nullable":false}},"rows":[{"a":0,"b":0,"c":"anchor"}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"},{"field":"c","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b","c"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const positionalUnpivotColumns = [{name: 'a', contract: {...number, nullable: true}},
  {name: 'b', contract: number}, {name: 'c', contract: {type: 'string', nullable: false}}];
const positionalUnpivot = (name, text, extra = {}) => success('positional-pipe-unpivot-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}], columns: positionalUnpivotColumns,
    expected: [{a: -20, b: 2, c: 'kept'}, {a: -10, b: 1, c: 'kept'}, {a: 0, b: 0, c: 'anchor'}], ...extra});
const positionalUnpivotHead = "SELECT 0 AS a, 0 AS b, 'anchor' AS c UNION ALL (FROM records |> SELECT id AS kept, -amount ";
const positionalUnpivotTail = '|> SELECT *) ORDER BY a NULLS LAST, b NULLS LAST, c';
const nullableUnpivotHead = "SELECT 0 AS a, 0 AS b, 'anchor' AS c UNION ALL (FROM records |> SELECT amount AS target, -id ";
const nullableUnpivotColumns = [{name: 'a', contract: number},
  {name: 'b', contract: {...number, nullable: true}}, {name: 'c', contract: {type: 'string', nullable: false}}];
setCorrespondingSuccesses.push(
  positionalUnpivot('json-control', JSON.stringify(positionalUnpivotProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalUnpivot('anonymous-source', positionalUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) ' + positionalUnpivotTail),
  positionalUnpivot('current-renamed-label', positionalUnpivotHead + '|> SET kept = 7 |> RENAME kept AS renamed '
    + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(renamed)) AS fresh ' + positionalUnpivotTail,
    {format: 'aql-text', expected: [{a: -20, b: 7, c: 'renamed'}, {a: -10, b: 7, c: 'renamed'}, {a: 0, b: 0, c: 'anchor'}]}),
  positionalUnpivot('private-shaped-destination', positionalUnpivotHead
    + '|> UNPIVOT INCLUDE NULLS(aql_set_anonymous_4 FOR label IN(kept)) |> WHERE aql_set_anonymous_4 > 0 ' + positionalUnpivotTail),
  positionalUnpivot('repeated-selected-column', positionalUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(kept,kept)) ' + positionalUnpivotTail,
    {expected: [{a: -20, b: 2, c: 'kept'}, {a: -20, b: 2, c: 'kept'},
      {a: -10, b: 1, c: 'kept'}, {a: -10, b: 1, c: 'kept'}, {a: 0, b: 0, c: 'anchor'}]}),
  positionalUnpivot('kept-duplicate-aliases', "SELECT 0 AS a, 0 AS b, 0 AS c, 'anchor' AS d UNION ALL (FROM records "
    + '|> SELECT id AS v, -id AS `V`, amount AS target |> UNPIVOT INCLUDE NULLS(value FOR label IN(target)) '
    + '|> SELECT *) ORDER BY a, b, c NULLS LAST, d',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number},
      {name: 'c', contract: {...number, nullable: true}}, {name: 'd', contract: {type: 'string', nullable: false}}],
      expected: [{a: 0, b: 0, c: 0, d: 'anchor'}, {a: 1, b: -1, c: 10, d: 'target'}, {a: 2, b: -2, c: 20, d: 'target'}]}),
  positionalUnpivot('nullable-selected-value', nullableUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(target)) ' + positionalUnpivotTail,
    {sourceRows: [{id: 1, amount: null}, {id: 2, amount: 20}], columns: nullableUnpivotColumns,
      expected: [{a: -2, b: 20, c: 'target'}, {a: -1, b: null, c: 'target'}, {a: 0, b: 0, c: 'anchor'}]}),
  positionalUnpivot('exclude-null-selected-value', nullableUnpivotHead + '|> UNPIVOT(value FOR label IN(target)) ' + positionalUnpivotTail,
    {sourceRows: [{id: 1, amount: null}, {id: 2, amount: 20}], columns: nullableUnpivotColumns,
      expected: [{a: -2, b: 20, c: 'target'}, {a: 0, b: 0, c: 'anchor'}]}),
  positionalUnpivot('typed-empty', "SELECT 0 AS a, 0 AS b, 'anchor' AS c WHERE FALSE UNION ALL (FROM records "
    + '|> SELECT id AS kept, -amount |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) ' + positionalUnpivotTail,
    {sourceRows: [], expected: []}),
);
const refusePositionalUnpivot = (name, text) => ({name: 'set-corresponding-refuse-pipe-unpivot-' + name,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refusePositionalUnpivot('private-anonymous', positionalUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(aql_set_anonymous_4)) ' + positionalUnpivotTail),
  refusePositionalUnpivot('ambiguous', "SELECT 0 AS a, 0 AS b, 'anchor' AS c UNION ALL (FROM records "
    + '|> SELECT id AS v, -amount AS `V` |> UNPIVOT INCLUDE NULLS(value FOR label IN(v)) ' + positionalUnpivotTail),
  refusePositionalUnpivot('old-range', positionalUnpivotHead + '|> AS old |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) '
    + '|> WHERE old.kept > 0 ' + positionalUnpivotTail),
  refusePositionalUnpivot('removed-column', positionalUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) '
    + '|> WHERE kept > 0 ' + positionalUnpivotTail),
  refusePositionalUnpivot('qualified-private-anonymous', positionalUnpivotHead + '|> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) '
    + '|> AS fresh |> WHERE fresh.aql_set_anonymous_4 > 0 ' + positionalUnpivotTail),
);

// Generated UNPIVOT names may collide with kept names; positions retain both values.
export const positionalUnpivotCollisionProgram = {"version":"actql/0.1","id":"fixture.positional_unpivot_name_collision","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":2,"y":20}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}}}},{"select":[{"kept":"x"},{"extra":"y"},"neg"]},{"unpivot":{"columns":["kept"],"keep":["extra","neg"],"value_column":"expanded","name_column":"label"}},{"select":[{"a":"extra"},{"b":"neg"},{"c":"expanded"},{"d":"label"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false},"c":{"type":"number","nullable":false},"d":{"type":"string","nullable":false}},"rows":[{"a":0,"b":0,"c":0,"d":"anchor"}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"},{"field":"c","dir":"asc","nulls":"first"},{"field":"d","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b","c","d"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const unpivotCollisionColumns = [{name: 'a', contract: {...number, nullable: true}},
  {name: 'b', contract: {...number, nullable: true}}, {name: 'c', contract: number},
  {name: 'd', contract: {type: 'string', nullable: false}}];
const unpivotCollision = (name, text, extra = {}) => success('positional-unpivot-name-collision-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}], columns: unpivotCollisionColumns,
    expected: [{a: 0, b: 0, c: 0, d: 'anchor'}, {a: 10, b: -10, c: 1, d: 'kept'},
      {a: 20, b: -20, c: 2, d: 'kept'}], ...extra});
const unpivotCollisionHead = "SELECT 0 AS a, 0 AS b, 0 AS c, 'anchor' AS d UNION ALL (FROM records "
  + '|> SELECT id AS kept, amount AS extra, -amount |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) ';
const unpivotCollisionTail = '|> SELECT *) ORDER BY a NULLS LAST, b NULLS LAST, c, d';
setCorrespondingSuccesses.push(
  unpivotCollision('json-control', JSON.stringify(positionalUnpivotCollisionProgram), {format: 'json', sourceReadSessionCount: 0}),
  unpivotCollision('value-column', unpivotCollisionHead + unpivotCollisionTail),
  unpivotCollision('name-column', "SELECT 'anchor' AS a, 0 AS b, 0 AS c, 'anchor' AS d UNION ALL (FROM records "
    + "|> SELECT id AS kept, 'user' AS extra, -amount |> UNPIVOT INCLUDE NULLS(value FOR extra IN(kept)) "
    + '|> SELECT *) ORDER BY a, b NULLS LAST, c, d',
    {columns: [{name: 'a', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}}, ...unpivotCollisionColumns.slice(1)],
      expected: [{a: 'anchor', b: 0, c: 0, d: 'anchor'}, {a: 'user', b: -20, c: 2, d: 'kept'},
        {a: 'user', b: -10, c: 1, d: 'kept'}]}),
  unpivotCollision('qualified-star', unpivotCollisionHead + '|> AS fresh |> SELECT fresh.*) '
    + 'ORDER BY a NULLS LAST, b NULLS LAST, c, d', {format: 'aql-text'}),
  unpivotCollision('immutable-star', unpivotCollisionHead + "|> AS fresh |> SET label = 'changed' "
    + "|> WHERE fresh.label = 'kept' |> SELECT fresh.*) ORDER BY a NULLS LAST, b NULLS LAST, c, d"),
  unpivotCollision('distinct-complete-row', unpivotCollisionHead + '|> DISTINCT ' + unpivotCollisionTail,
    {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 10}, {id: 1, amount: 10}],
      expected: [{a: 0, b: 0, c: 0, d: 'anchor'}, {a: 10, b: -10, c: 1, d: 'kept'}, {a: 10, b: -10, c: 2, d: 'kept'}]}),
  unpivotCollision('drop-all-matching-occurrences', "SELECT 0 AS a, 'anchor' AS b UNION ALL (FROM records "
    + '|> SELECT id AS kept, amount AS extra, -amount |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) '
    + '|> DROP extra |> SELECT *) ORDER BY a NULLS LAST, b',
    {columns: [unpivotCollisionColumns[0], {name: 'b', contract: {type: 'string', nullable: false}}],
      expected: [{a: -20, b: 'kept'}, {a: -10, b: 'kept'}, {a: 0, b: 'anchor'}]}),
  unpivotCollision('nullable-kept-values', unpivotCollisionHead + unpivotCollisionTail,
    {sourceRows: [{id: 1, amount: null}], expected: [{a: 0, b: 0, c: 0, d: 'anchor'}, {a: null, b: null, c: 1, d: 'kept'}]}),
  unpivotCollision('typed-empty', unpivotCollisionHead.replace("'anchor' AS d UNION", "'anchor' AS d WHERE FALSE UNION")
    + unpivotCollisionTail, {sourceRows: [], expected: []}),
);
const refuseUnpivotCollision = (name, tail) => ({name: 'set-corresponding-refuse-unpivot-name-collision-' + name,
  format: 'sql', text: unpivotCollisionHead + tail + unpivotCollisionTail, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refuseUnpivotCollision('ambiguous-bare', '|> WHERE extra > 0 '),
  refuseUnpivotCollision('ambiguous-qualified', '|> AS fresh |> WHERE fresh.extra > 0 '),
  refuseUnpivotCollision('ambiguous-rename', '|> RENAME extra AS renamed '),
  refuseUnpivotCollision('ambiguous-set', '|> SET extra = 1 '),
  refuseUnpivotCollision('displaced-range', '|> AS old |> AS fresh |> WHERE old.extra > 0 '),
  refuseUnpivotCollision('private-duplicate', '|> AS fresh |> WHERE fresh.aql_set_duplicate_8 > 0 '),
);

// ASSERT validates existing current/range keys without renaming positional values.
export const positionalAssertProgram = {"version":"actql/0.1","id":"fixture.positional_assert","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":2,"y":20}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}}}},{"select":[{"kept":"x"},"neg"]},{"assert_rows":{"unique_by":["kept"]}},{"select":[{"a":"kept"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const positionalAssertColumns = [{name: 'a', contract: number},
  {name: 'b', contract: {...number, nullable: true}}];
const positionalAssert = (name, text, extra = {}) => success('positional-pipe-assert-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}], columns: positionalAssertColumns,
    expected: [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: -20}], ...extra});
const positionalAssertHead = 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS kept, -amount ';
const positionalAssertTail = '|> SELECT *) ORDER BY a, b NULLS LAST';
setCorrespondingSuccesses.push(
  positionalAssert('json-control', JSON.stringify(positionalAssertProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalAssert('anonymous-source', positionalAssertHead + '|> ASSERT UNIQUE BY(kept) ' + positionalAssertTail),
  positionalAssert('qualified-star', positionalAssertHead + '|> AS r |> ASSERT UNIQUE BY(r.kept) '
    + '|> SELECT r.*) ORDER BY a, b NULLS LAST', {format: 'aql-text'}),
  positionalAssert('immutable-key', positionalAssertHead + '|> AS r |> SET kept = 7 '
    + '|> ASSERT UNIQUE BY(r.kept) ' + positionalAssertTail,
    {expected: [{a: 0, b: 0}, {a: 7, b: -20}, {a: 7, b: -10}]}),
  positionalAssert('renamed-current-key', positionalAssertHead + '|> RENAME kept AS current_key '
    + '|> ASSERT UNIQUE BY(current_key) ' + positionalAssertTail),
  positionalAssert('duplicate-values-separate-key', 'SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records '
    + '|> SELECT id AS kept, amount AS v, -amount AS `V` |> ASSERT UNIQUE BY(kept) |> SELECT *) ORDER BY a, b NULLS LAST, c NULLS LAST',
    {columns: [...positionalAssertColumns, {name: 'c', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: 10, c: -10}, {a: 2, b: 20, c: -20}]}),
  positionalAssert('nullable-nonkey', positionalAssertHead + '|> ASSERT UNIQUE BY(kept) ' + positionalAssertTail,
    {sourceRows: [{id: 1, amount: null}], expected: [{a: 0, b: 0}, {a: 1, b: null}]}),
  positionalAssert('typed-empty', positionalAssertHead.replace('AS b UNION', 'AS b WHERE FALSE UNION')
    + '|> ASSERT UNIQUE BY(kept) ' + positionalAssertTail, {sourceRows: [], expected: []}),
  positionalAssert('parameter-filter-limit', positionalAssertHead + '|> WHERE kept > @min |> ASSERT UNIQUE BY(kept) '
    + '|> ORDER BY kept DESC |> LIMIT 1 ' + positionalAssertTail,
    {parameterDeclarations: {min: number}, parameters: {min: 0}, expected: [{a: 0, b: 0}, {a: 2, b: -20}]}),
);
const refusePositionalAssert = (name, projection, key) => ({name: 'set-corresponding-refuse-pipe-assert-' + name,
  format: 'sql', text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT ' + projection
    + ' |> ASSERT UNIQUE BY(' + key + ') ' + positionalAssertTail, expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refusePositionalAssert('private-anonymous', 'id AS kept, -amount', 'aql_set_anonymous_4'),
  refusePositionalAssert('ambiguous-bare', 'id AS v, -amount AS `V`', 'v'),
  refusePositionalAssert('ambiguous-qualified', 'id AS v, -amount AS `V` |> AS r', 'r.v'),
  refusePositionalAssert('dropped-input', 'id AS kept, -amount', 'id'),
  refusePositionalAssert('displaced-range', 'id AS kept, -amount |> AS before |> AS current', 'before.kept'),
  refusePositionalAssert('qualified-private', 'id AS kept, -amount |> AS r', 'r.aql_set_anonymous_4'),
);
// Invalid data is accepted for execution, then rejected by the existing ASSERT
// Owner. It must not publish either operand or silently deduplicate the input.
const duplicateAssertProgram = structuredClone(positionalAssertProgram);
duplicateAssertProgram.stages[0].steps[0].values.rows = [{x: 1, y: 10}, {x: 1, y: 20}];
export const setCorrespondingExecutionFailures = [
  {name: 'set-corresponding-positional-assert-duplicate-json', format: 'json',
    text: JSON.stringify(duplicateAssertProgram), resultNames: ['answer'], sourceReadSessionCount: 0},
  {name: 'set-corresponding-positional-assert-duplicate-source', format: 'sql',
    text: positionalAssertHead + '|> ASSERT UNIQUE BY(kept) ' + positionalAssertTail,
    sourceRows: [{id: 1, amount: 10}, {id: 1, amount: 20}], resultNames: ['main'], sourceReadSessionCount: 1},
];

// Unconsumed anonymous values are implicit PIVOT keys, never dropped grouping data.
export const positionalPivotProgram = {"version":"actql/0.1","id":"fixture.positional_pivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":true}},"rows":[{"x":1,"y":10},{"x":2,"y":20},{"x":3,"y":10}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"y"}},"axis":{"literal":"A"}}},{"select":[{"amount":"x"},"neg","axis"]},{"pivot":{"index":["neg"],"column":"axis","value":"amount","values":["A"],"aggregate":"sum"}},{"select":[{"a":"neg"},{"b":"A"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const positionalPivotColumns = [{name: 'a', contract: {...number, nullable: true}},
  {name: 'b', contract: {...number, nullable: true}}];
const positionalPivot = (name, text, extra = {}) => success('positional-pipe-pivot-' + name, text,
  {sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}, {id: 3, amount: 10}],
    columns: positionalPivotColumns, expected: [{a: -20, b: 2}, {a: -10, b: 4}, {a: 0, b: 0}], ...extra});
const positionalPivotHead = "SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT id AS value, -amount, 'A' AS axis ";
const positionalPivotTail = '|> SELECT *) ORDER BY a NULLS LAST, b NULLS LAST';
setCorrespondingSuccesses.push(
  positionalPivot('json-control', JSON.stringify(positionalPivotProgram), {format: 'json', sourceReadSessionCount: 0}),
  positionalPivot('anonymous-group', positionalPivotHead + "|> PIVOT(SUM(value) AS total FOR axis IN('A')) " + positionalPivotTail),
  positionalPivot('duplicate-group-occurrences', "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records "
    + "|> SELECT id AS v, -id AS `V`, amount AS value, 'A' AS axis |> PIVOT(SUM(value) AS total FOR axis IN('A')) "
    + '|> SELECT *) ORDER BY a, b, c NULLS LAST',
    {columns: [{name: 'a', contract: number}, {name: 'b', contract: number}, {name: 'c', contract: {...number, nullable: true}}],
      expected: [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 10}, {a: 2, b: -2, c: 20}, {a: 3, b: -3, c: 10}]}),
  positionalPivot('immutable-aggregate-current-key', "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records "
    + "|> SELECT id AS value, -amount, 'A' AS axis |> AS r |> SET value = 7 "
    + "|> PIVOT(SUM(r.value) AS total FOR axis IN('A')) |> SELECT *) ORDER BY a, b NULLS LAST, c NULLS LAST",
    {format: 'aql-text', columns: [{name: 'a', contract: number}, {name: 'b', contract: {...number, nullable: true}},
      {name: 'c', contract: {...number, nullable: true}}], expected: [{a: 0, b: 0, c: 0}, {a: 7, b: -20, c: 2}, {a: 7, b: -10, c: 4}]}),
  positionalPivot('current-aggregate', positionalPivotHead + "|> SET value = 7 |> PIVOT(SUM(value) AS total FOR axis IN('A')) " + positionalPivotTail,
    {expected: [{a: -20, b: 7}, {a: -10, b: 14}, {a: 0, b: 0}]}),
  positionalPivot('bucket-declaration-order', "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM records "
    + "|> SELECT id AS value, -amount, 'A' AS axis |> PIVOT(COUNT(value) AS n FOR axis IN('B' AS later,'A' AS first)) "
    + '|> SELECT *) ORDER BY a NULLS LAST, b, c',
    {columns: [{name: 'a', contract: {...number, nullable: true}}, {name: 'b', contract: number}, {name: 'c', contract: number}],
      expected: [{a: -20, b: 0, c: 1}, {a: -10, b: 0, c: 2}, {a: 0, b: 0, c: 0}]}),
  positionalPivot('private-shaped-bucket-name', positionalPivotHead + "|> PIVOT(SUM(value) FOR axis IN('A' AS aql_set_anonymous_5)) " + positionalPivotTail),
  positionalPivot('nullable-group-key', positionalPivotHead + "|> PIVOT(SUM(value) AS total FOR axis IN('A')) " + positionalPivotTail,
    {sourceRows: [{id: 1, amount: null}], expected: [{a: 0, b: 0}, {a: null, b: 1}]}),
  positionalPivot('typed-empty-keyed', positionalPivotHead.replace('AS b UNION', 'AS b WHERE FALSE UNION')
    + "|> PIVOT(SUM(value) AS total FOR axis IN('A')) " + positionalPivotTail, {sourceRows: [], expected: []}),
);
const refusePositionalPivot = (name, projection, argument, axis, buckets, tail = '') => ({
  name: 'set-corresponding-refuse-pipe-pivot-' + name, format: 'sql',
  text: 'SELECT 0 AS a, 0 AS b UNION ALL (FROM records |> SELECT ' + projection
    + ' |> PIVOT(SUM(' + argument + ') FOR ' + axis + ' IN(' + buckets + ')) ' + tail + positionalPivotTail,
  expectedCode: 'ClientProgramInvalidInput'});
setCorrespondingRefusals.push(
  refusePositionalPivot('private-argument', "id AS value, -amount, 'A' AS axis", 'aql_set_anonymous_5', 'axis', "'A'"),
  refusePositionalPivot('ambiguous-argument', "id AS v, -id AS `V`, amount AS value, 'A' AS axis", 'v', 'axis', "'A'"),
  refusePositionalPivot('ambiguous-axis', "id AS value, -amount, 'A' AS axis, 'B' AS `AXIS`", 'value', 'axis', "'A'"),
  refusePositionalPivot('qualified-ambiguous', "id AS v, -id AS `V`, amount AS value, 'A' AS axis |> AS r", 'r.v', 'axis', "'A'"),
  refusePositionalPivot('logical-output-collision', "id AS v, -id AS `V`, amount AS value, 'A' AS axis", 'value', 'axis', "'A' AS v"),
  refusePositionalPivot('dropped-input', "id AS value, -amount, 'A' AS axis", 'amount', 'axis', "'A'"),
  refusePositionalPivot('old-output-range', "id AS value, -amount, 'A' AS axis |> AS old", 'value', 'axis', "'A'", '|> WHERE old.value > 0 '),
);
