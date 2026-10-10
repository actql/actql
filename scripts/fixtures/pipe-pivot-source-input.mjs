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
