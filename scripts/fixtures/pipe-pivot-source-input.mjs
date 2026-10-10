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

// Scalar aggregate arguments consume their referenced evaluated input columns,
// not the private derived value as an additional implicit group key.
const expressionRows = [{product: 1, amount: 1, axis: 'A'},
  {product: 1, amount: 2, axis: 'A'}];
export const pivotArgumentExpressionProgram = {
  version: 'actql/0.1', id: 'fixture.pivot_argument_expression', stages: [
    {id: 'main', inputs: {}, steps: [
      {values: {schema: {product: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false}, axis: {type: 'string', nullable: false}},
        rows: expressionRows}, as: 'rows'},
      {from: 'rows', derive: {adjusted: {add: [{field: 'amount'}, {literal: 1}]}}},
      {pivot: {index: ['product'], column: 'axis', value: 'adjusted',
        values: ['A'], aggregate: 'sum'}},
      {sort: [{field: 'product', dir: 'asc', nulls: 'first'}]},
      {select: ['product', 'A'], as: 'out'},
    ], results: {rows: {from: 'out', fields: ['product', 'A']}}},
  ], results: {answer: {from: {stage: 'main', result: 'rows'}}},
};
const expressionHead = "(SELECT 1 AS product,1 AS amount,'A' AS axis UNION ALL SELECT 1,2,'A')";
const expressionColumns = [number('product', false), number('A', true)];
const expressionResult = [{product: 1, A: 5}];
pipePivotSuccesses.push(
  success('argument-expression-json-control', JSON.stringify(pivotArgumentExpressionProgram),
    expressionResult, expressionColumns, {format: 'json'}),
  success('argument-expression-consumption', expressionHead
    + " |> PIVOT(SUM(amount + 1) FOR axis IN('A')) |> ORDER BY product",
    expressionResult, expressionColumns),
  success('argument-expression-multiple-columns',
    "(SELECT 1 AS product,1 AS amount,2 AS bonus,'A' AS axis UNION ALL SELECT 1,2,3,'A')"
    + " |> PIVOT(SUM(amount + bonus) FOR axis IN('A')) |> ORDER BY product",
    [{product: 1, A: 8}], expressionColumns),
  success('argument-expression-constant', expressionHead
    + " |> PIVOT(SUM(1) FOR axis IN('A')) |> ORDER BY product,amount",
    [{product: 1, amount: 1, A: 1}, {product: 1, amount: 2, A: 1}],
    [number('product', false), number('amount', false), number('A', true)]),
  success('argument-expression-immutable-range', expressionHead
    + " |> AS old |> SET amount = 7 |> PIVOT(SUM(old.amount + 1) FOR axis IN('A')) |> ORDER BY product,amount",
    [{product: 1, amount: 7, A: 5}],
    [number('product', false), number('amount', false), number('A', true)]),
  success('argument-expression-current-slot', expressionHead
    + " |> AS old |> SET amount = 7 |> PIVOT(SUM(amount + 1) FOR axis IN('A')) |> ORDER BY product",
    [{product: 1, A: 16}], expressionColumns),
  success('argument-expression-nullable-empty-bucket',
    "(SELECT 1 AS product,CAST(NULL AS FLOAT64) AS amount,'A' AS axis UNION ALL SELECT 1,2,'A')"
    + " |> PIVOT(SUM(amount + 1) FOR axis IN('B','A')) |> ORDER BY product",
    [{product: 1, B: null, A: 3}],
    [number('product', false), number('B', true), number('A', true)]),
  success('argument-expression-private-bucket-collision', expressionHead
    + " |> PIVOT(SUM(amount + 1) FOR axis IN('A' AS aql_pivot_argument_7)) |> ORDER BY product",
    [{product: 1, aql_pivot_argument_7: 5}],
    [number('product', false), number('aql_pivot_argument_7', true)]),
  success('argument-expression-parameter', expressionHead
    + " |> PIVOT(SUM(amount + @offset) FOR axis IN('A')) |> ORDER BY product",
    [{product: 1, A: 7}], expressionColumns, {
      parameterDeclarations: {offset: {type: 'number', nullable: false}},
      parameters: {offset: 2},
    }),
);
const objectDeclarations = {p1: {type: 'object', nullable: true,
  fields: {score: {type: 'number', nullable: true}}},
  p2: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: true}}},
  p3: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: true}}}};
const objectParameters = {p1: {score: 10}, p2: null, p3: {score: null}};
const propertyControl = {version: 'actql/0.1', id: 'fixture.pivot_argument_property',
  params: objectDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {product: {type: 'number', nullable: false}},
      rows: [{product: 1}, {product: 2}, {product: 3}]}, as: 'rows'},
    {from: 'rows', derive: {axis: {literal: 'A'}, payload: {case: {when: [
      {when: {eq: [{field: 'product'}, {literal: 1}]}, then: {$param: 'p1'}},
      {when: {eq: [{field: 'product'}, {literal: 2}]}, then: {$param: 'p2'}},
    ], else: {$param: 'p3'}}}}},
    {derive: {adjusted: {add: [{property: {value: {field: 'payload'}, name: 'score'}}, {literal: 1}]}}},
    {pivot: {index: ['product'], column: 'axis', value: 'adjusted', values: ['A'], aggregate: 'sum'}},
    {sort: [{field: 'product', dir: 'asc', nulls: 'first'}]},
    {select: ['product', 'A'], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['product', 'A']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const propertyResult = [{product: 1, A: 11}, {product: 2, A: null}, {product: 3, A: null}];
pipePivotSuccesses.push(
  success('argument-expression-property-json-control', JSON.stringify(propertyControl),
    propertyResult, expressionColumns, {format: 'json', parameters: objectParameters}),
  success('argument-expression-property-null-propagation',
    "(SELECT 1 AS product,@p1 AS payload,'A' AS axis UNION ALL SELECT 2,@p2,'A' UNION ALL SELECT 3,@p3,'A')"
    + " |> PIVOT(SUM(payload.score + 1) FOR axis IN('A')) |> ORDER BY product",
    propertyResult, expressionColumns,
    {parameterDeclarations: objectDeclarations, parameters: objectParameters}),
);
for (const [name, text] of [
  ['consumed-column', expressionHead + " |> PIVOT(SUM(amount + 1) FOR axis IN('A')) |> SELECT amount"],
  ['old-range-after-pivot', expressionHead + " |> AS old |> PIVOT(SUM(old.amount + 1) FOR axis IN('A')) |> SELECT old.product"],
  ['unknown-expression-column', expressionHead + " |> PIVOT(SUM(missing + 1) FOR axis IN('A'))"],
  ['unregistered-parameter', expressionHead + " |> PIVOT(SUM(amount + @offset) FOR axis IN('A'))"],
  ['nested-aggregate', expressionHead + " |> PIVOT(SUM(MAX(amount) + 1) FOR axis IN('A'))"],
  ['wrong-expression-type', expressionHead + " |> PIVOT(SUM(axis || 'B') FOR axis IN('A'))"],
]) pipePivotRefusals.push({name: 'pipe-pivot-refusal-argument-expression-' + name,
  format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput'});
