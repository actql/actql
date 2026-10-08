// Independently authored common control and GoogleSQL row-expansion obligations.
// No compiler output is patched; parent identity alone is not a match key.
import {correlatedUnnestStarSuccesses, correlatedUnnestStarRefusals}
  from './correlated-unnest-star-source-input.mjs';
import {joinedUnnestStarSuccesses, joinedUnnestStarRefusals}
  from './joined-unnest-star-source-input.mjs';
const number = {type: 'number', nullable: false};
const element = {type: 'number', nullable: true};
const items = {type: 'array', nullable: true, max_items: 3, items: element};
const parents = {type: 'array', max_items: 4, items: {type: 'object', fields: {id: number, items}}};
const parameterDeclarations = {parents};
const parameters = {parents: [{id: 2, items: [2, null, 2]}, {id: 1, items: [1]},
  {id: 3, items: []}, {id: 4, items: null}]};
const columns = [{name: 'id', contract: number}, {name: 'element', contract: element},
  {name: 'position', contract: number}];
const expected = [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0},
  {id: 2, element: null, position: 1}, {id: 2, element: 2, position: 2}];
export const correlatedUnnestProgram = {version: 'actql/0.1', id: 'fixture.correlated_unnest',
  params: parameterDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {parents: {$param: 'parents'}}},
    {unnest: {column: 'parents', as: 'parent'}},
    {derive: {id: {property: {value: {field: 'parent'}, name: 'id'}},
      original_items: {property: {value: {field: 'parent'}, name: 'items'}}}},
    {derive: {array: {field: 'original_items'}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'element', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// Separate common control for the accepted filter/LIMIT execution failure.
// Its predicate, sort, projection and bound are not compiler-generated.
export const correlatedUnnestFilterLimitProgram = {version: 'actql/0.1',
  id: 'fixture.correlated_unnest_filter_limit', params: parameterDeclarations,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {parents: {$param: 'parents'}}},
    {unnest: {column: 'parents', as: 'parent'}},
    {derive: {id: {property: {value: {field: 'parent'}, name: 'id'}},
      original_items: {property: {value: {field: 'parent'}, name: 'items'}}}},
    {derive: {array: {field: 'original_items'}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    {filter: {not: {is_null: {field: 'element'}}}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'element', 'position']},
    {take: {count: 2, offset: 0}, as: 'limited'},
  ], results: {rows: {from: 'limited', fields: ['id', 'element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'correlated-unnest-' + name,
  format: 'sql', text, parameterDeclarations, parameters, columns, expected,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const sql = 'SELECT p.id, element, position FROM UNNEST(@parents) p '
  + 'CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position';
const pipe = 'FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position '
  + '|> SELECT p.id, element, position |> ORDER BY p.id, position';
export const correlatedUnnestSuccesses = [
  success('json-control', JSON.stringify(correlatedUnnestProgram), {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql),
  success('pipe', pipe, {format: 'aql-text'}),
  success('quoted', sql.replaceAll('p.', '`p`.').replace(') p ', ') `p` ').replaceAll('element', '`element`')),
  success('data', 'DATA expanded = ' + pipe + '; FROM expanded |> RESULT answer', {format: 'aql-text'}),
  success('empty-parents', sql, {parameters: {parents: []}, expected: []}),
  success('empty-arrays', sql, {parameters: {parents: [{id: 1, items: []}, {id: 2, items: null}]}, expected: []}),
  success('filter-limit', sql.replace('ORDER BY', 'WHERE element IS NOT NULL ORDER BY') + ' LIMIT 2',
    {expected: [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0}]}),
  success('filter-limit-json-control', JSON.stringify(correlatedUnnestFilterLimitProgram), {
    format: 'json', parameterDeclarations: undefined,
    expected: [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0}],
  }),
  success('immutable-range', pipe.replace('|> CROSS', '|> SET items = [9] |> CROSS'), {format: 'aql-text'}),
  success('current-column', pipe.replace('|> CROSS', '|> SET items = [9] |> CROSS').replace('UNNEST(p.items)', 'UNNEST(items)'),
    // SET's literal [9] has nonnullable numeric elements; p.items retains its original nullable item contract.
    {format: 'aql-text', columns: [columns[0], {name: 'element', contract: number}, columns[2]],
      expected: [{id: 1, element: 9, position: 0}, {id: 2, element: 9, position: 0},
      {id: 3, element: 9, position: 0}, {id: 4, element: 9, position: 0}]}),
  success('parent-star', sql.replace('p.id, element', 'p.*, element'), {
    columns: [columns[0], {name: 'items', contract: items}, columns[1], columns[2]],
    expected: [{id: 1, items: [1], element: 1, position: 0},
      {id: 2, items: [2, null, 2], element: 2, position: 0},
      {id: 2, items: [2, null, 2], element: null, position: 1},
      {id: 2, items: [2, null, 2], element: 2, position: 2}],
  }),
  success('acquired-parent', 'SELECT r.id, element, position FROM records r '
    + 'CROSS JOIN UNNEST(@items) element WITH OFFSET position ORDER BY r.id, position', {
    parameterDeclarations: {items}, parameters: {items: [2, null, 2]},
    sourceReadCount: 1, sourceReadSessionCount: 1, sourceRows: [{id: 2, amount: 20}, {id: 1, amount: null}],
    expected: [{id: 1, element: 2, position: 0}, {id: 1, element: null, position: 1},
      {id: 1, element: 2, position: 2}, {id: 2, element: 2, position: 0},
      {id: 2, element: null, position: 1}, {id: 2, element: 2, position: 2}],
  }),
  success('joined-parent', 'SELECT r.id, element, position FROM records r '
    + 'JOIN (SELECT 1 AS key) k ON r.id = k.key MAX_OUTPUT_ROWS 4 '
    + 'CROSS JOIN UNNEST(@items) element WITH OFFSET position ORDER BY r.id, position', {
    parameterDeclarations: {items}, parameters: {items: [2, null, 2]},
    sourceReadCount: 1, sourceReadSessionCount: 1, sourceRows: [{id: 2, amount: 20}, {id: 1, amount: null}],
    expected: [{id: 1, element: 2, position: 0}, {id: 1, element: null, position: 1},
      {id: 1, element: 2, position: 2}],
  }),
];
const refusal = (name, text, extra = {}) => ({name: 'correlated-unnest-refusal-' + name,
  format: 'sql', text, parameterDeclarations, parameters, ...extra});
export const correlatedUnnestRefusals = [
  refusal('dropped-range', 'FROM UNNEST(@parents) p |> SELECT id, items '
    + '|> CROSS JOIN UNNEST(p.items) element |> SELECT id, element', {format: 'aql-text'}),
  refusal('duplicate-range', sql.replace('p.items) element', 'p.items) p')),
  refusal('duplicate-offset', sql.replace('OFFSET position', 'OFFSET ELEMENT')),
  refusal('not-array', sql.replace('UNNEST(p.items)', 'UNNEST(p.id)')),
  refusal('missing-property', sql.replace('UNNEST(p.items)', 'UNNEST(p.missing)')),
  refusal('undeclared', sql, {parameterDeclarations: undefined}),
  refusal('array-bound', sql, {parameters: {parents: [{id: 1, items: [1, 2, 3, 4]}]}}),
  refusal('join-after-expansion', sql.replace('ORDER BY', 'CROSS JOIN records r ORDER BY')),
];
correlatedUnnestSuccesses.push(...correlatedUnnestStarSuccesses);
correlatedUnnestRefusals.push(...correlatedUnnestStarRefusals);
correlatedUnnestSuccesses.push(...joinedUnnestStarSuccesses);
correlatedUnnestRefusals.push(...joinedUnnestStarRefusals);
