// Authored from the existing finite ARRAY, typed empty_array and lazy IF
// contracts. These values, bounds and column order are not compiler output.
const scalar = (type, nullable = false) => ({type, nullable});
const column = (items, max_items) => ({name: 'items', contract: {
  type: 'array', nullable: false, max_items, items,
}});
const numeric = column(scalar('number'), 3);
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
  success('pipe-data', 'DATA expanded = FROM UNNEST(ARRAY[2, 1, 2]) element WITH OFFSET position |> SELECT element, position; FROM expanded |> ORDER BY position |> RESULT answer',
    [{element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}],
    [{name: 'element', contract: scalar('number')}, {name: 'position', contract: scalar('number')}], {format: 'aql-text'}),
];

export const arrayLiteralRefusals = [
  {name: 'heterogeneous', text: "SELECT [1, 'secret-value'] AS items"},
  {name: 'declared-wrong-type', text: 'SELECT ARRAY<BOOL>[1] AS items'},
  {name: 'direct-nested-literal', text: 'SELECT [[1, 2]] AS items', expectedCode: 'ClientProgramUnsupported'},
  {name: 'direct-nested-parameter', text: 'SELECT [@xs] AS items',
    parameterDeclarations: {xs: {type: 'array', max_items: 2, items: scalar('number')}},
    parameters: {xs: [1, 2]}, expectedCode: 'ClientProgramUnsupported'},
  {name: 'malformed', text: 'SELECT [1,] AS items'},
].map(value => ({...value, name: 'array-literal-' + value.name, format: 'sql'}));

// ARRAY<JSON>, exact INT64/default empty typing and additional type annotations
// remain tracked gaps. A shared constructor rejection is not positive support.
