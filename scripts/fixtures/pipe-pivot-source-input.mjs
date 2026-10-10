// Independent selected-profile PIVOT values and schema expectations.
const number = (name, nullable) => ({name, contract: {type: 'number', nullable}});
const string = (name, maxBytes) => ({name, contract: {type: 'string', nullable: false,
  ...(maxBytes === undefined ? {} : {max_utf8_bytes: maxBytes})}});
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'pipe-pivot-' + name, format: 'aql-text', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const duplicateRows = [{product: 'kale', sales: 51, quarter: 'Q1'},
  {product: 'kale', sales: 51, quarter: 'Q1'},
  {product: 'kale', sales: null, quarter: 'Q2'}];
const control = {version: 'actql/0.1', id: 'fixture.pipe_pivot', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {product: {type: 'string', nullable: false},
      sales: {type: 'number', nullable: true}, quarter: {type: 'string', nullable: false}},
      rows: duplicateRows}, as: 'sales'},
    {from: 'sales', pivot: {index: ['product'], column: 'quarter', value: 'sales',
      values: ['Q2', 'Q1'], aggregate: 'count'}},
    {select: ['product', {second: 'Q2'}, {first: 'Q1'}], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['product', 'second', 'first']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// Text literal 'kale' has an independently known four-byte UTF-8 bound.
// The explicit machine schema above deliberately has no such bound.
const head = "SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter";
export const pipePivotSuccesses = [
  success('duplicate-null-json-control', JSON.stringify(control),
    [{product: 'kale', second: 0, first: 2}],
    [string('product'), number('second', false), number('first', false)], {format: 'json'}),
  success('min-missing-authored-order', head + " |> PIVOT(MIN(sales) FOR quarter IN ('Q2', 'Q1'))",
    [{product: 'kale', Q2: null, Q1: 51}],
    [string('product', 4), number('Q2', true), number('Q1', true)]),
  success('prefix-and-range', head + " |> PIVOT(COUNT(sales) AS n FOR quarter IN ('Q2' AS second, 'Q1' AS first)) AS shaped |> SELECT shaped.*",
    [{product: 'kale', n_second: 0, n_first: 1}],
    [string('product', 4), number('n_second', false), number('n_first', false)]),
  success('current-value', head + " |> SET sales = 99 |> RENAME quarter AS phase |> PIVOT(MAX(sales) FOR phase IN ('Q1' AS present))",
    [{product: 'kale', present: 99}], [string('product', 4), number('present', true)]),
  success('nullable-input', "SELECT CAST(NULL AS FLOAT64) AS sales, 'Q1' AS quarter |> PIVOT(MIN(sales) FOR quarter IN ('Q1'))",
    [{Q1: null}], [number('Q1', true)]),
  success('empty-global', "SELECT 1 AS sales, 'Q1' AS quarter WHERE FALSE |> PIVOT(COUNT(sales) FOR quarter IN ('Q2','Q1'))",
    [{Q2: 0, Q1: 0}], [number('Q2', false), number('Q1', false)]),
  success('empty-keyed', head + " WHERE FALSE |> PIVOT(MIN(sales) FOR quarter IN ('Q2','Q1'))",
    [], [string('product', 4), number('Q2', true), number('Q1', true)]),
  success('duplicate-null-source',
    "(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale' AS product, CAST(NULL AS FLOAT64) AS sales, 'Q2' AS quarter) |> PIVOT(COUNT(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
    [{product: 'kale', second: 0, first: 2}],
    [string('product', 4), number('second', false), number('first', false)]),
];
export const pipePivotRefusals = [
  {name: 'old-range', tail: " |> AS old |> PIVOT(COUNT(sales) FOR quarter IN ('Q1')) |> SELECT old.product"},
  {name: 'consumed-field', tail: " |> PIVOT(COUNT(sales) FOR quarter IN ('Q1')) |> SELECT sales"},
  {name: 'unknown-argument', tail: " |> PIVOT(COUNT(missing) FOR quarter IN ('Q1'))"},
  {name: 'unknown-axis', tail: " |> PIVOT(COUNT(sales) FOR missing IN ('Q1'))"},
  {name: 'result-name-collision', tail: " |> PIVOT(COUNT(sales) FOR quarter IN ('Q1' AS product))"},
  {name: 'duplicate-result-name', tail: " |> PIVOT(COUNT(sales) FOR quarter IN ('Q1' AS X,'Q2' AS x))"},
  {name: 'non-string-axis', tail: " |> PIVOT(COUNT(sales) FOR sales IN ('Q1'))"},
  {name: 'parameter-axis-value', tail: " |> PIVOT(COUNT(sales) FOR quarter IN (@p))"},
].map(({name, tail}) => ({name: 'pipe-pivot-refusal-' + name,
  format: 'aql-text', text: head + tail, expectedCode: 'ClientProgramInvalidInput'}));

// Retain the exact formerly refused positional-operand source as a positive
// case once terminal anonymous expressions cross ordinary ordinal alignment.
pipePivotSuccesses.push(success('anonymous-set-operands',
  "(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale', 51, 'Q1' UNION ALL SELECT 'kale', CAST(NULL AS FLOAT64), 'Q2') |> PIVOT(COUNT(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
  [{product: 'kale', second: 0, first: 2}],
  [string('product', 4), number('second', false), number('first', false)]));

// Independent COUNT expectations: each source-free SELECT starts from one row.
// COUNT(*) is one, COUNT(NULL) is zero; filtering that row before global COUNT
// retains one aggregate output containing zero, not NULL or an absent bucket.
const countIdentityControl = {version: 'actql/0.1', id: 'fixture.pipe_pivot_count', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {sales: {type: 'number', nullable: false},
      other: {type: 'number', nullable: false}, quarter: {type: 'string', nullable: false}},
      rows: [{sales: 1, other: 0, quarter: 'Q1'}, {sales: 1, other: 0, quarter: 'Q2'}]}, as: 'counts'},
    {from: 'counts', pivot: {index: ['other'], column: 'quarter', value: 'sales',
      values: ['Q2', 'Q1'], aggregate: 'max'}},
    {select: ['other', {second: 'Q2'}, {first: 'Q1'}], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['other', 'second', 'first']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
pipePivotSuccesses.push(
  success('anonymous-count-json-control', JSON.stringify(countIdentityControl),
    [{other: 0, second: 1, first: 1}],
    [number('other', false), number('second', true), number('first', true)], {format: 'json'}),
  success('anonymous-count-empty-source',
    "(SELECT COUNT(*) AS sales, 'Q1' AS quarter UNION ALL SELECT COUNT(*), 'Q2' WHERE FALSE) |> PIVOT(MAX(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
    [{second: 0, first: 1}], [number('second', true), number('first', true)]),
  success('anonymous-count-identity-source',
    "(SELECT COUNT(*) AS sales, COUNT(CAST(NULL AS FLOAT64)) AS other, 'Q1' AS quarter UNION ALL SELECT COUNT(*), COUNT(CAST(NULL AS FLOAT64)), 'Q2') |> PIVOT(MAX(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
    [{other: 0, second: 1, first: 1}],
    [number('other', false), number('second', true), number('first', true)]),
);

// Scope controls for the aggregate operands feeding the existing PIVOT cohort.
// These complete SELECTs isolate HAVING name visibility before downstream use.
const havingRowsControl = {version: 'actql/0.1', id: 'fixture.set_having_scope', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {n: {type: 'number', nullable: false}}, rows: [{n: 1}, {n: 0}]}, as: 'rows'},
    {from: 'rows', sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'sorted'},
  ], results: {rows: {from: 'sorted', fields: ['n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
pipePivotSuccesses.push(
  success('aggregate-having-json-control', JSON.stringify(havingRowsControl),
    [{n: 0}, {n: 1}], [number('n', false)], {format: 'json'}),
  success('anonymous-aggregate-having-call',
    'SELECT 0 AS n UNION ALL SELECT COUNT(*) HAVING COUNT(*) > 0 ORDER BY n',
    [{n: 0}, {n: 1}], [number('n', false)]),
  success('authored-aggregate-having-alias',
    'SELECT 0 AS n UNION ALL SELECT COUNT(*) AS aql_set_aggregate_0 HAVING aql_set_aggregate_0 > 0 ORDER BY n',
    [{n: 0}, {n: 1}], [number('n', false)]),
);
for (const [name, reference] of [
  ['bare', 'aql_set_aggregate_0'], ['case', 'AQL_SET_AGGREGATE_0'],
  ['quoted', '`aql_set_aggregate_0`'],
]) {
  pipePivotRefusals.push({name: 'pipe-pivot-refusal-anonymous-aggregate-having-' + name,
    format: 'aql-text', text: 'SELECT 0 AS n UNION ALL SELECT COUNT(*) HAVING ' + reference + ' > 0',
    expectedCode: 'ClientProgramInvalidInput'});
}

// COUNT(*) consumes no user column. Its independent control counts a private
// nonnullable witness, preserving n as an implicit key even when n is NULL.
export const pivotCountStarProgram = {"version":"actql/0.1","id":"fixture.pivot_count_star","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":true},"axis":{"type":"string","nullable":false}},"rows":[{"n":null,"axis":"A"},{"n":null,"axis":"A"},{"n":1,"axis":"A"}]},"as":"rows"},{"from":"rows","derive":{"row_witness":{"literal":1}}},{"pivot":{"index":["n"],"column":"axis","value":"row_witness","values":["A"],"aggregate":"count"}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}]},{"select":["n","A"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n","A"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const countStarRows = [{n: 1, A: 1}, {n: null, A: 2}];
const countStarColumns = [number('n', true), number('A', false)];
const countStarSource = "(SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis UNION ALL SELECT CAST(NULL AS FLOAT64),'A' UNION ALL SELECT 1,'A') |> PIVOT(COUNT(*) FOR axis IN('A')) |> ORDER BY n NULLS LAST";
const countStarInput = "(SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis UNION ALL SELECT CAST(NULL AS FLOAT64),'A' UNION ALL SELECT 1,'A')";
pipePivotSuccesses.push(
  success('count-star-json-control', JSON.stringify(pivotCountStarProgram), countStarRows, countStarColumns, {format: 'json'}),
  success('count-star-null-rows', countStarSource, countStarRows, countStarColumns),
  // COUNT(n) consumes n and excludes its NULLs; it is not the row count above.
  success('column-count-contrast', countStarInput + " |> PIVOT(COUNT(n) FOR axis IN('A'))", [{A: 1}], [number('A', false)]),
  success('count-star-empty-global', "SELECT 'A' AS axis WHERE FALSE |> PIVOT(COUNT(*) AS n FOR axis IN('B' AS later,'A' AS first))",
    [{n_later: 0, n_first: 0}], [number('n_later', false), number('n_first', false)]),
  success('count-star-empty-keyed', countStarInput + " |> WHERE FALSE |> PIVOT(COUNT(*) FOR axis IN('A')) |> ORDER BY n NULLS LAST",
    [], countStarColumns),
  success('count-star-private-shaped-key', "SELECT 9 AS aql_pivot_row_4,'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A'))",
    [{aql_pivot_row_4: 9, A: 1}], [number('aql_pivot_row_4', false), number('A', false)]),
  success('count-star-private-shaped-bucket', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A' AS aql_pivot_row_4))",
    [{aql_pivot_row_4: 1}], [number('aql_pivot_row_4', false)]),
  success('count-star-prefix-range-axis', countStarInput + " |> AS r |> PIVOT(COUNT(*) AS total FOR r.axis IN('B' AS later,'A' AS first)) AS current "
    + '|> SELECT current.* |> ORDER BY n NULLS LAST', [{n: 1, total_later: 0, total_first: 1}, {n: null, total_later: 0, total_first: 2}],
    [number('n', true), number('total_later', false), number('total_first', false)]),
  success('count-star-data', 'DATA counts = ' + countStarSource + '; FROM counts |> SELECT n, A |> ORDER BY n NULLS LAST',
    countStarRows, countStarColumns),
);
pipePivotRefusals.push(...[
  ['non-count-star', "SELECT 'A' AS axis |> PIVOT(SUM(*) FOR axis IN('A'))"],
  ['count-star-missing-axis', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR missing IN('A'))"],
  ['count-star-private-witness', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A')) |> SELECT aql_pivot_row_4"],
  ['count-star-old-range', "SELECT 'A' AS axis |> AS old |> PIVOT(COUNT(*) FOR axis IN('A')) |> SELECT old.axis"],
  ['count-star-parameter-bucket', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN(@bucket))"],
].map(([name, text]) => ({name: 'pipe-pivot-refuse-' + name, format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput'})));
