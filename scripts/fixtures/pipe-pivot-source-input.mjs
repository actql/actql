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

pipePivotSuccesses.push(
  success('argument-expression-empty-global',
    "SELECT 1 AS amount,'A' AS axis WHERE FALSE |> PIVOT(SUM(amount + 1) FOR axis IN('A'))",
    [{A: null}], [number('A', true)]),
  success('argument-expression-empty-keyed',
    "SELECT 1 AS product,1 AS amount,'A' AS axis WHERE FALSE |> PIVOT(SUM(amount + 1) FOR axis IN('A'))",
    [], expressionColumns),
);

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
  success('count-star-prefix-range-axis', countStarInput + " |> AS r |> PIVOT(COUNT(*) AS total FOR r.axis IN('B' AS later,'A' AS first)) AS `current` "
    + '|> SELECT current.* |> ORDER BY n NULLS LAST', [{n: 1, total_later: 0, total_first: 1}, {n: null, total_later: 0, total_first: 2}],
    [number('n', true), number('total_later', false), number('total_first', false)]),
  success('count-star-data', 'WITH counts AS (' + countStarSource + ') FROM counts |> SELECT n, A |> ORDER BY n NULLS LAST',
    countStarRows, countStarColumns),
);
pipePivotRefusals.push(...[
  ['non-count-star', "SELECT 'A' AS axis |> PIVOT(SUM(*) FOR axis IN('A'))"],
  ['count-star-missing-axis', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR missing IN('A'))"],
  ['count-star-private-witness', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A')) |> SELECT aql_pivot_row_4"],
  ['count-star-old-range', "SELECT 'A' AS axis |> AS old |> PIVOT(COUNT(*) FOR axis IN('A')) |> SELECT old.axis"],
  ['count-star-parameter-bucket', "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN(@bucket))"],
].map(([name, text]) => ({name: 'pipe-pivot-refuse-' + name, format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput'})));
// Standard FROM postfix uses the same aggregate meaning but gives its table
// expression a new output scope before WHERE, SELECT and surrounding JOINs.
const fromRows = "SELECT 'kale' AS product,51 AS sales,'Q1' AS quarter UNION ALL SELECT 'kale',51,'Q1' UNION ALL SELECT 'kale',CAST(NULL AS FLOAT64),'Q2'";
const fromColumns = [string('product',4),number('second',false),number('first',false)];
pipePivotSuccesses.push(
  success('from-matched-json-control',JSON.stringify(control),[{product:'kale',second:0,first:2}],
    [string('product'),number('second',false),number('first',false)],{format:'json'}),
  success('from-cte-scope', 'WITH sales AS ('+fromRows+") SELECT product,second,first FROM sales PIVOT(COUNT(sales) FOR quarter IN('Q2' AS second,'Q1' AS first)) ORDER BY product",
    [{product:'kale',second:0,first:2}],fromColumns),
  success('from-derived-without-input-alias', 'SELECT product,second,first FROM ('+fromRows+") PIVOT(COUNT(sales) FOR quarter IN('Q2' AS second,'Q1' AS first)) ORDER BY product",
    [{product:'kale',second:0,first:2}],fromColumns),
  success('from-qualified-input-and-output', 'SELECT shaped.product,shaped.second,shaped.first FROM ('+fromRows+") AS original PIVOT(COUNT(original.sales) FOR original.quarter IN('Q2' AS second,'Q1' AS first)) AS shaped WHERE shaped.first=2 ORDER BY shaped.product",
    [{product:'kale',second:0,first:2}],fromColumns),
  success('from-quoted-alias', 'SELECT `ORDER`.product,`ORDER`.second,`ORDER`.first FROM ('+fromRows+") `PIVOT` PIVOT(COUNT(`PIVOT`.sales) FOR `PIVOT`.quarter IN('Q2' AS second,'Q1' AS first)) `ORDER` ORDER BY `ORDER`.product",
    [{product:'kale',second:0,first:2}],fromColumns),
  success('from-pipe-head', 'FROM ('+fromRows+") original PIVOT(COUNT(sales) FOR quarter IN('Q2' AS second,'Q1' AS first)) shaped |> SELECT shaped.product,shaped.second,shaped.first |> ORDER BY product",
    [{product:'kale',second:0,first:2}],fromColumns),
  success('from-filter-on-output', 'WITH sales AS ('+fromRows+") SELECT product,first FROM sales PIVOT(COUNT(sales) FOR quarter IN('Q1' AS first)) WHERE first=99",
    [],[string('product',4),number('first',false)]),
  success('from-empty-global', "SELECT * FROM (SELECT 1 AS sales,'A' AS axis WHERE FALSE) PIVOT(COUNT(sales) FOR axis IN('A'))",
    [{A:0}],[number('A',false)]),
  success('from-empty-keyed', "SELECT product,A FROM (SELECT 1 AS product,1 AS sales,'A' AS axis WHERE FALSE) PIVOT(MIN(sales) FOR axis IN('A'))",
    [],[number('product',false),number('A',true)]),
);
const joinedFromHead = "WITH sales AS (SELECT 1 AS product,2 AS amount,'A' AS axis UNION ALL SELECT 1,3,'A'), products AS (SELECT 1 AS product,100 AS marker UNION ALL SELECT 2,200) ";
const joinedFromColumns=[number('product',false),number('marker',false),number('A',true)];
pipePivotSuccesses.push(
  success('from-right-join-input',joinedFromHead+"SELECT p.product,p.marker,s.A FROM products p JOIN sales PIVOT(SUM(amount) FOR axis IN('A')) s ON p.product=s.product MAX_OUTPUT_ROWS 10 ORDER BY p.product",
    [{product:1,marker:100,A:5}],joinedFromColumns),
  success('from-left-join-input',joinedFromHead+"SELECT s.product,p.marker,s.A FROM sales PIVOT(SUM(amount) FOR axis IN('A')) s JOIN products p ON p.product=s.product MAX_OUTPUT_ROWS 10 ORDER BY s.product",
    [{product:1,marker:100,A:5}],joinedFromColumns),
  success('from-left-join-padding',joinedFromHead+"SELECT p.product,p.marker,s.A FROM products p LEFT JOIN sales PIVOT(SUM(amount) FOR axis IN('A')) s ON p.product=s.product MAX_OUTPUT_ROWS 10 ORDER BY p.product",
    [{product:1,marker:100,A:5},{product:2,marker:200,A:null}],joinedFromColumns),
  success('from-shared-source', "WITH sales AS (SELECT 'kale' AS product,amount AS sales,CASE WHEN id<3 THEN 'Q1' ELSE 'Q2' END AS quarter FROM records WHERE id>0) SELECT product,first,second FROM sales PIVOT(COUNT(sales) FOR quarter IN('Q1' AS first,'Q2' AS second)) WHERE first>0 ORDER BY product",
    [{product:'kale',first:3,second:1}], [string('product',4),number('first',false),number('second',false)],{sourceReadCount:2,sourceReadSessionCount:1,
      sourceRows:[{id:2,amount:10},{id:1,amount:20},{id:3,amount:null},
        {id:4,amount:40},{id:2,amount:10},{id:0,amount:99}]}),
);
for(const [name,source] of [
  ['input-range', 'SELECT old.product FROM ('+fromRows+") old PIVOT(COUNT(old.sales) FOR old.quarter IN('Q1'))"],
  ['consumed-column', 'SELECT sales FROM ('+fromRows+") old PIVOT(COUNT(sales) FOR quarter IN('Q1'))"],
  ['result-has-no-consumed-column', 'SELECT shaped.sales FROM ('+fromRows+") old PIVOT(COUNT(sales) FOR quarter IN('Q1')) shaped"],
  ['unknown-argument', 'SELECT * FROM ('+fromRows+") old PIVOT(COUNT(missing) FOR quarter IN('Q1'))"],
  ['unknown-axis', 'SELECT * FROM ('+fromRows+") old PIVOT(COUNT(sales) FOR missing IN('Q1'))"],
  ['output-name-collision', 'SELECT * FROM ('+fromRows+") old PIVOT(COUNT(sales) FOR quarter IN('Q1' AS product))"],
]) pipePivotRefusals.push({name:'pipe-pivot-refusal-from-'+name,format:'aql-text',text:source,
  expectedCode:'ClientProgramInvalidInput'});

const acquiredFromRows=[{id:2,amount:10},{id:1,amount:20},{id:3,amount:null},
  {id:4,amount:40},{id:2,amount:10},{id:0,amount:99}];
export const fromPivotAcquiredProgram={version:'actql/0.1',id:'fixture.from_pivot_acquired',
  stages:[{id:'capture',inputs:{remote:{connector:'crm/main',resource:'r'}},steps:[
    {from:'remote',filter:{gt:[{field:'id'},{literal:0}]}},
    {select:['id','amount'],as:'captured'},
  ],results:{source:{from:'captured',fields:['id','amount']}}},
  {id:'main',inputs:{records:{result:{stage:'capture',result:'source'}}},steps:[
    {from:'records',derive:{product:{literal:'kale'},sales:{field:'amount'},
      quarter:{case:{when:[{when:{lt:[{field:'id'},{literal:3}]},then:{literal:'Q1'}}],else:{literal:'Q2'}}}}},
    {select:['product','sales','quarter'],as:'rows'},
    {from:'rows',pivot:{index:['product'],column:'quarter',value:'sales',values:['Q1','Q2'],aggregate:'count'}},
    {select:['product',{first:'Q1'},{second:'Q2'}]},
    {filter:{gt:[{field:'first'},{literal:0}]}},
    {sort:[{field:'product',dir:'asc',nulls:'first'}],as:'out'},
  ],results:{rows:{from:'out',fields:['product','first','second']}}}],
  results:{answer:{from:{stage:'main',result:'rows'}}}};
pipePivotSuccesses.push(success('from-shared-source-json-control',JSON.stringify(fromPivotAcquiredProgram),
  [{product:'kale',first:3,second:1}], [string('product',4),number('first',false),number('second',false)],
  {format:'json',sourceReadCount:2,sourceReadSessionCount:1,sourceRows:acquiredFromRows}));

// Projected columns remain distinct even when their source values coincide.
const projectedIdentityControl={"version":"actql/0.1","id":"fixture.pivot_projection_identity","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false},"twin":{"type":"number","nullable":false},"axis":{"type":"string","nullable":false}},"rows":[{"value":1,"twin":1,"axis":"A"},{"value":1,"twin":1,"axis":"A"},{"value":2,"twin":2,"axis":"A"}]},"as":"rows"},{"from":"rows","pivot":{"index":["twin"],"column":"axis","value":"value","values":["A"],"aggregate":"sum"}},{"sort":[{"field":"twin","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["twin","A"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
pipePivotSuccesses.push(
 success('from-projected-identity-json-control',JSON.stringify(projectedIdentityControl),
  [{twin:1,A:2},{twin:2,A:2}],[number('twin',false),number('A',true)],{format:'json'}),
 success('from-projected-identity', "SELECT twin,A FROM (SELECT amount AS value,amount AS twin,axis FROM (SELECT 1 AS amount,'A' AS axis UNION ALL SELECT 1,'A' UNION ALL SELECT 2,'A') original) PIVOT(SUM(value) FOR axis IN('A')) ORDER BY twin",
  [{twin:1,A:2},{twin:2,A:2}],[number('twin',false),number('A',true)]),
);

// Grouping a decoded String literal preserves the same ordinary bucket value.
// Duplicate rows count twice; the NULL sales row does not contribute to COUNT.
const groupedHead = "(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale', 51, 'Q1' UNION ALL SELECT 'kale', CAST(NULL AS FLOAT64), 'Q2')";
pipePivotSuccesses.push(
  success('grouped-string-pipe', groupedHead
    + " |> PIVOT(COUNT(sales) FOR quarter IN ((('Q2')) AS second, (\"Q1\") AS first))",
    [{product: 'kale', second: 0, first: 2}],
    [string('product', 4), number('second', false), number('first', false)]),
  success('grouped-string-from', 'SELECT shaped.product,shaped.second,shaped.first FROM '
    + groupedHead + " PIVOT(COUNT(sales) FOR quarter IN ((('Q2')) AS second, ('Q1') AS first)) AS shaped ORDER BY shaped.product",
    [{product: 'kale', second: 0, first: 2}],
    [string('product', 4), number('second', false), number('first', false)]),
);
for (const [name, value] of [
  ['parameter', '((@p))'], ['number', '((1))'],
  ['null', '((NULL))'], ['computed', "(('Q' || '1'))"],
]) {
  pipePivotRefusals.push({name: 'pipe-pivot-refusal-grouped-string-' + name,
    format: 'aql-text', text: head + " |> PIVOT(COUNT(sales) FOR quarter IN (" + value + '))',
    expectedCode: 'ClientProgramInvalidInput'});
}
