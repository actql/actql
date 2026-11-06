// Authored from the existing finite ARRAY, typed empty_array and lazy IF
// contracts. These values, bounds and column order are not compiler output.
const scalar = (type, nullable = false) => ({type, nullable});
const column = (items, max_items) => ({name: 'items', contract: {
  type: 'array', nullable: false, max_items, items,
}});
const numeric = column(scalar('number'), 3);
const numericField = (name, nullable = false) => ({name, contract: scalar('number', nullable)});
const numericCast = value => ({cast: {value: {literal: value}, target: {type: 'number'}}});
const doubleControl = {version: 'actql/0.1', id: 'fixture.double_type', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: scalar('boolean')}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: numericCast(1.25), missing: numericCast(null),
      items: {if: [{literal: true}, {array: [{literal: 2}, {literal: null}, {literal: 2}]},
        {empty_array: {items: scalar('number')}}]}}},
    {select: ['value', 'missing', 'items'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value', 'missing', 'items']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const doubleRows = [{value: 1.25, missing: null, items: [2, null, 2]}];
const doubleColumns = [numericField('value'), numericField('missing', true), column(scalar('number', true), 3)];
const control = {version: 'actql/0.1', id: 'fixture.array_literal', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: scalar('boolean')}, rows: [{unit: true}]}},
    {from: 'seed', derive: {items: {array: [{literal: 2}, {literal: 1}, {literal: 2}]}}},
    {select: ['items'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['items']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'array-literal-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
export const arrayLiteralSuccesses = [
  success('json-control', JSON.stringify(control), [{items: [2, 1, 2]}], [numeric], {format: 'json'}),
  success('brackets', 'SELECT [2, 1, 2] AS items', [{items: [2, 1, 2]}], [numeric]),
  success('keyword', 'SELECT ARRAY[2, 1, 2] AS items', [{items: [2, 1, 2]}], [numeric]),
  success('declared-number', 'SELECT ARRAY<FLOAT64>[2, 1, 2] AS items', [{items: [2, 1, 2]}], [numeric]),
  success('double-json-control', JSON.stringify(doubleControl), doubleRows, doubleColumns, {format: 'json'}),
  ...['FLOAT64', 'DOUBLE', 'dOuBlE'].map((target, index) => success('double-type-' + index,
    `SELECT CAST(1.25 AS ${target}) AS value, CAST(NULL AS ${target}) AS missing, ARRAY<${target}>[2, NULL, 2] AS items`,
    doubleRows, doubleColumns)),
  success('double-empty-array', 'SELECT ARRAY<DOUBLE>[] AS items', [{items: []}], [column(scalar('number'), 0)]),
  success('double-only-null-array', 'SELECT ARRAY<DOUBLE>[NULL] AS items', [{items: [null]}], [column(scalar('number', true), 1)]),
  success('double-string-conversion', "SELECT CAST('1.25' AS DOUBLE) AS value", [{value: 1.25}], [numericField('value')]),
  success('double-typed-empty-result', 'SELECT CAST(NULL AS DOUBLE) AS value WHERE FALSE', [], [numericField('value', true)]),
  success('double-nullable-parameter', 'SELECT CAST(@p AS DOUBLE) AS value', [{value: null}], [numericField('value', true)], {
    parameterDeclarations: {p: scalar('number', true)}, parameters: {p: null},
  }),
  success('double-lazy-cast', "SELECT IF(FALSE, CAST('invalid' AS DOUBLE), CAST(1.25 AS DOUBLE)) AS value",
    [{value: 1.25}], [numericField('value')]),
  success('double-pipe-scope', 'SELECT CAST(1.25 AS DOUBLE) AS value |> WHERE value > 1 |> SELECT value',
    [{value: 1.25}], [numericField('value')], {format: 'aql-text'}),
  success('declared-bool-null', 'SELECT ARRAY<BOOL>[TRUE, NULL] AS items',
    [{items: [true, null]}], [column(scalar('boolean', true), 2)]),
  success('declared-only-null', 'SELECT ARRAY<BOOL>[NULL] AS items',
    [{items: [null]}], [column(scalar('boolean', true), 1)]),
  success('declared-empty', 'SELECT ARRAY<STRING>[] AS items',
    [{items: []}], [column(scalar('string'), 0)]),
  success('empty-rows', 'SELECT [2, 1, 2] AS items WHERE FALSE', [], [numeric]),
  success('expand-offsets', 'SELECT element, position FROM UNNEST([2, 1, 2]) AS element WITH OFFSET position ORDER BY position',
    [{element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}],
    [{name: 'element', contract: scalar('number')}, {name: 'position', contract: scalar('number')}]),
  success('pipe-data', 'WITH expanded AS (FROM UNNEST(ARRAY[2, 1, 2]) element WITH OFFSET position |> SELECT element, position) FROM expanded |> ORDER BY position |> RESULT answer',
    [{element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}],
    [{name: 'element', contract: scalar('number')}, {name: 'position', contract: scalar('number')}], {format: 'aql-text', resultName: 'answer'}),
];

export const arrayLiteralRefusals = [
  {name: 'heterogeneous', text: "SELECT [1, 'secret-value'] AS items"},
  {name: 'declared-wrong-type', text: 'SELECT ARRAY<BOOL>[1] AS items'},
  {name: 'double-wrong-item', text: "SELECT ARRAY<DOUBLE>['secret-value'] AS items"},
  {name: 'double-quoted-cast-type', text: 'SELECT CAST(1 AS `DOUBLE`) AS value'},
  {name: 'double-quoted-array-type', text: 'SELECT ARRAY<`DOUBLE`>[1] AS items'},
  {name: 'double-undeclared-parameter', text: 'SELECT CAST(@p AS DOUBLE) AS value'},
  {name: 'double-wrong-parameter', text: 'SELECT CAST(@p AS DOUBLE) AS value',
    parameterDeclarations: {p: scalar('number')}, parameters: {p: '1.25'}},
  ...['FLOAT', 'FLOAT32'].flatMap(target => [
    {name: 'unsupported-cast-' + target, text: `SELECT CAST(1 AS ${target}) AS value`},
    {name: 'unsupported-array-' + target, text: `SELECT ARRAY<${target}>[1] AS items`},
  ]),
  // Source-only ARRAY profile refusals map to source_unsupported. The current
  // audience-filtered preparation Owner retains ClientProgramRejected unless
  // public checking supplies a disclosable fact; machine ARRAY support alone
  // does not disclose that source-profile refusal.
  {name: 'direct-nested-literal', text: 'SELECT [[1, 2]] AS items', expectedCode: 'ClientProgramRejected'},
  {name: 'direct-nested-parameter', text: 'SELECT [@xs] AS items',
    parameterDeclarations: {xs: {type: 'array', max_items: 2, items: scalar('number')}},
    parameters: {xs: [1, 2]}, expectedCode: 'ClientProgramRejected'},
  {name: 'direct-nested-parameter-reference', text: 'SELECT @matrix AS items',
    parameterDeclarations: {matrix: {type: 'array', max_items: 1,
      items: {type: 'array', max_items: 2, items: scalar('number')}}},
    parameters: {matrix: [[1, 2]]}, expectedCode: 'ClientProgramRejected'},
  {name: 'direct-nested-aggregate', format: 'aql-text',
    text: 'FROM records |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(@xs IGNORE NULLS ORDER BY id) AS items GROUP BY id |> ORDER BY id',
    parameterDeclarations: {xs: {type: 'array', max_items: 2, items: scalar('number')}},
    parameters: {xs: [1, 2]}, expectedCode: 'ClientProgramRejected'},
  {name: 'malformed', text: 'SELECT [1,] AS items'},
].map(value => ({...value, name: 'array-literal-' + value.name, format: value.format ?? 'sql'}));

// ARRAY<JSON>, exact INT64/default empty typing and additional type annotations
// remain tracked gaps. A shared constructor rejection is not positive support.
