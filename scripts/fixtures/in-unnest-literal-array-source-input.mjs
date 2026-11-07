import {inUnnestSuccesses, inUnnestRefusals, inUnnestExecutionFailures}
  from './in-unnest-source-input.mjs';

// Independent membership truth table and ordinary Program control. Array
// constructors are not evaluated by the oracle or regenerated from lowering.
const boolean = (name, nullable = true) => ({name, contract: {type: 'boolean', nullable}});
const truthColumns = ['included', 'excluded', 'unknown', 'null_left'].map(name => boolean(name));
const truth = [{included: true, excluded: false, unknown: null, null_left: null}];
const declarations = {p: {type: 'number', nullable: true}};
const parameters = {p: -2};
const expressions = {
  included: {in: [{literal: 2}, {literal: [null, 2, 2]}]},
  excluded: {not_in: [{literal: 2}, {literal: [null, 2, 2]}]},
  unknown: {in: [{literal: 1}, {literal: [2, null, {$param: 'p'}]}]},
  null_left: {not_in: [{cast: {value: {literal: null}, target: {type: 'number'}}},
    {literal: [2, 3]}]},
};
const control = {version: 'actql/0.1', id: 'fixture.in_unnest_literal_array', params: declarations,
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: expressions}, {select: Object.keys(expressions), as: 'selected'},
  ], results: {rows: {from: 'selected', fields: Object.keys(expressions)}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const projection = array => `2 IN UNNEST(${array('[NULL, 2, 2]')}) AS included, `
  + `2 NOT IN UNNEST(${array('[NULL, 2, 2]')}) AS excluded, `
  + `1 IN UNNEST(${array('[2, NULL, @p]')}) AS unknown, `
  + `CAST(NULL AS FLOAT64) NOT IN UNNEST(${array('[2, 3]')}) AS null_left`;
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'in-unnest-literal-array-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const arrayParameters = {parameterDeclarations: {
  xs: {type: 'array', nullable: false, max_items: 2, items: {type: 'number', nullable: false}},
  ys: {type: 'array', nullable: false, max_items: 2, items: {type: 'number', nullable: false}},
}, parameters: {xs: [2], ys: [7]}};
export const inUnnestLiteralArraySuccesses = [
  success('general-element', 'SELECT 2 IN UNNEST([1 + 1]) AS found',
    [{found: true}], [boolean('found', false)]),
  success('array-field',
    'WITH records AS (SELECT @xs AS xs, @ys AS ys) SELECT 2 IN UNNEST(xs) AS included FROM records',
    [{included: true}], [boolean('included', false)], arrayParameters),
  success('conditional-array', 'SELECT 2 IN UNNEST(IF(TRUE, @xs, @ys)) AS included',
    [{included: true}], [boolean('included', false)], arrayParameters),
  success('lazy-array-branch', 'SELECT 2 IN UNNEST(IF(TRUE, [2], [1 / 0])) AS included',
    [{included: true}], [boolean('included', false)]),
  success('json-control', JSON.stringify(control), truth, truthColumns,
    {format: 'json', parameters}),
  success('null-and-match', 'SELECT ' + projection(value => value), truth, truthColumns,
    {parameterDeclarations: declarations, parameters}),
  success('keyword-and-grouped-atoms', 'SELECT ' + projection(value => '(ARRAY' + value + ')'),
    truth, truthColumns, {parameterDeclarations: declarations, parameters}),
  success('empty-set-with-null-left',
    'SELECT CAST(NULL AS FLOAT64) IN UNNEST([]) AS included, CAST(NULL AS FLOAT64) NOT IN UNNEST(ARRAY[]) AS excluded',
    [{included: false, excluded: true}], [boolean('included', false), boolean('excluded', false)]),
  success('ordinary-array-retains-constructor', 'SELECT [2, 1, 2] AS items, 2 IN UNNEST([2, 1, 2]) AS found',
    [{items: [2, 1, 2], found: true}], [{name: 'items', contract: {type: 'array', nullable: false,
      max_items: 3, items: {type: 'number', nullable: false}}}, boolean('found', false)]),
  success('empty-input', 'SELECT ' + projection(value => value) + ' WHERE FALSE', [], truthColumns,
    {parameterDeclarations: declarations, parameters}),
  success('where-source-once', 'SELECT id FROM records WHERE amount IN UNNEST([20, 30]) ORDER BY id',
    [{id: 2}, {id: 3}, {id: 3}], [{name: 'id', contract: {type: 'number', nullable: false}}],
    {sourceReadCount: 1, sourceReadSessionCount: 1}),
  success('pipe-signed-atoms', 'SELECT 2 AS needle |> SELECT needle IN UNNEST([-(2), +((2)), ((@p))]) AS found |> RESULT answer',
    [{found: true}], [boolean('found')], {format: 'aql-text', parameterDeclarations: declarations, parameters}),
  success('string-null', "SELECT 'x' IN UNNEST(['x', 'x', NULL]) AS found", [{found: true}], [boolean('found')]),
  success('parameter-array-keeps-existing-contract',
    'SELECT CAST(NULL AS FLOAT64) IN UNNEST(@xs) AS included, CAST(NULL AS FLOAT64) NOT IN UNNEST(@xs) AS excluded',
    [{included: false, excluded: true}], [boolean('included'), boolean('excluded')],
    {parameterDeclarations: {xs: {type: 'array', nullable: true, max_items: 2,
      items: {type: 'number', nullable: true}}}, parameters: {xs: null}}),
  // SQL expression signs use the existing canonical-zero numeric lowering.
  // This does not admit negative-zero JSON literals or Parameter values.
  success('negative-zero', 'SELECT 2 IN UNNEST([-(0)]) AS found',
    [{found: false}], [boolean('found', false)]),
];
export const inUnnestLiteralArrayRefusals = [
  {name: 'annotation-not-erased', text: 'SELECT 2 IN UNNEST(ARRAY<STRING>[1]) AS found'},
  {name: 'mixed-types', text: 'SELECT 2 IN UNNEST([1, TRUE]) AS found'},
  {name: 'undeclared', text: 'SELECT 2 IN UNNEST([@missing]) AS found'},
  {name: 'wrong-parameter-value', text: 'SELECT 2 IN UNNEST([@p]) AS found',
    parameterDeclarations: declarations, parameters: {p: 'wrong-type'}},
  {name: 'nonfinite', text: 'SELECT 2 IN UNNEST([1e9999]) AS found'},
].map(value => ({...value, name: 'in-unnest-literal-array-' + value.name, format: 'sql'}));

// SQL uses its public default main; this Pipe case explicitly authors answer.
for (const fixture of inUnnestLiteralArraySuccesses) {
  if (fixture.format === 'sql') {
    fixture.results = {main: {rows: fixture.expected, columns: fixture.columns}};
  } else if (fixture.name === 'in-unnest-literal-array-pipe-signed-atoms') {
    fixture.results = {answer: {rows: fixture.expected, columns: fixture.columns}};
  }
}

// Keep whole-ARRAY parameter boundaries in the same active membership corpus.
inUnnestLiteralArraySuccesses.push(...inUnnestSuccesses);
inUnnestLiteralArrayRefusals.push(...inUnnestRefusals);
export const inUnnestLiteralArrayExecutionFailures = inUnnestExecutionFailures;
