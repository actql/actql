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

// Parentheses preserve operand ownership and ordinal values. These results
// are authored from the same two input rows as the independent JSON control.
const parenthesized = (name, text, extra = {}) => positional('parenthesized-' + name,
  text, {format: 'aql-text', columns: aggregateColumns, expected: windowRows, ...extra});
const parenthesizedInput = 'DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; ';
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
  parenthesized('typed-empty', 'DATA r = SELECT 1 AS x WHERE FALSE; '
    + 'SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL (SELECT '
    + 'ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r) '
    + 'ORDER BY a, b', {expected: []}),
);
setCorrespondingRefusals.push(
  {name: 'set-corresponding-refuse-parenthesized-by-name', format: 'aql-text',
    text: 'DATA r = SELECT 1 AS x; SELECT 0 AS a UNION ALL BY NAME '
      + '(SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r)',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'set-corresponding-refuse-parenthesized-authored-cte', format: 'aql-text',
    text: 'DATA r = SELECT 1 AS x; WITH hidden AS '
      + '(SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r) '
      + 'SELECT 0 AS a UNION ALL (SELECT * FROM hidden)',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'set-corresponding-refuse-parenthesized-private-qualify', format: 'aql-text',
    text: 'DATA r = SELECT 1 AS x; SELECT 0 AS a UNION ALL '
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
