// Independently authored common control and GoogleSQL row-expansion obligations.
// No compiler output is patched; parent identity alone is not a match key.
import {correlatedUnnestStarSuccesses, correlatedUnnestStarRefusals}
  from './correlated-unnest-star-source-input.mjs';
import {joinedUnnestStarSuccesses, joinedUnnestStarRefusals}
  from './joined-unnest-star-source-input.mjs';
import {unnestJoinSuccesses, unnestJoinRefusals} from './unnest-join-source-input.mjs';
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
// A conditional INNER expansion is ordinary UNNEST followed by a filter.
// These fixed input rows leave three matches; omitting ON would retain NULL.
const innerSql = 'SELECT p.id, element, position FROM UNNEST(@parents) p '
  + 'INNER JOIN UNNEST(p.items) element WITH OFFSET position ON element = p.id ORDER BY p.id, position';
const innerPipe = 'FROM UNNEST(@parents) p |> JOIN UNNEST(p.items) element WITH OFFSET position '
  + 'ON element = p.id |> SELECT p.id, element, position |> ORDER BY p.id, position';
const innerExpected = [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0},
  {id: 2, element: 2, position: 2}];
export const innerCorrelatedUnnestProgram = {version: 'actql/0.1',
  id: 'fixture.inner_correlated_unnest', params: parameterDeclarations,
  stages: [{id: 'main', inputs: {}, steps: [
    ...correlatedUnnestProgram.stages[0].steps.slice(0, 6),
    {filter: {eq: [{field: 'element'}, {field: 'id'}]}},
    ...correlatedUnnestProgram.stages[0].steps.slice(6),
  ], results: {rows: {from: 'selected', fields: ['id', 'element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// derive adds a fresh value slot; the final projection names it id without
// replacing the original receiver used by the predicate and ordering.
export const innerCorrelatedUnnestImmutableProgram = {version: 'actql/0.1',
  id: 'fixture.inner_correlated_unnest_immutable', params: parameterDeclarations,
  stages: [{id: 'main', inputs: {}, steps: [
    ...correlatedUnnestProgram.stages[0].steps.slice(0, 4),
    {derive: {original_id: {field: 'id'}}},
    {derive: {current_id: {literal: 99}}},
    ...correlatedUnnestProgram.stages[0].steps.slice(4, 6),
    {filter: {eq: [{field: 'element'}, {field: 'original_id'}]}},
    {sort: [{field: 'original_id', dir: 'asc', nulls: 'first'},
      {field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: [{id: 'current_id'}, 'element', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const immutableInnerExpected = [{id: 99, element: 1, position: 0},
  {id: 99, element: 2, position: 0}, {id: 99, element: 2, position: 2}];
export const correlatedUnnestSuccesses = [
  success('json-control', JSON.stringify(correlatedUnnestProgram), {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql),
  success('pipe', pipe, {format: 'aql-text'}),
  success('quoted', sql.replaceAll('p.', '`p`.').replace(') p ', ') `p` ').replaceAll('element', '`element`')),
  success('data', 'WITH expanded AS (' + pipe + ') FROM expanded |> RESULT answer', {format: 'aql-text', resultName: 'answer'}),
  success('empty-parents', sql, {parameters: {parents: []}, expected: []}),
  success('empty-arrays', sql, {parameters: {parents: [{id: 1, items: []}, {id: 2, items: null}]}, expected: []}),
  success('filter-limit', sql.replace('ORDER BY', 'WHERE element IS NOT NULL ORDER BY') + ' LIMIT 2',
    {expected: [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0}]}),
  success('filter-limit-json-control', JSON.stringify(correlatedUnnestFilterLimitProgram), {
    format: 'json', parameterDeclarations: undefined,
    expected: [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0}],
  }),
  success('immutable-range', pipe.replace('|> CROSS', '|> SELECT id, items |> AS p |> SET items = [9] |> CROSS'), {format: 'aql-text'}),
  success('current-column', pipe.replace('|> CROSS', '|> SELECT id, items |> AS p |> SET items = [9] |> CROSS').replace('UNNEST(p.items)', 'UNNEST(items)'),
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
  success('join-after-expansion', sql.replace('ORDER BY',
    'CROSS JOIN records r MAX_OUTPUT_ROWS 10 ORDER BY'), {
    sourceReadCount: 1, sourceReadSessionCount: 1,
    sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}],
    expected: expected.flatMap(row => [{...row}, {...row}]),
  }),
  success('inner-json-control', JSON.stringify(innerCorrelatedUnnestProgram),
    {format: 'json', parameterDeclarations: undefined, expected: innerExpected}),
  success('inner-sql-on', innerSql, {expected: innerExpected}),
  success('inner-pipe-on', innerPipe, {format: 'aql-text', expected: innerExpected}),
  success('inner-no-on', sql.replace('CROSS JOIN', 'INNER JOIN')),
  success('inner-pipe-no-on', pipe.replace('CROSS JOIN', 'JOIN'), {format: 'aql-text'}),
  success('inner-quoted', innerSql.replaceAll('p.', '`p`.').replace(') p ', ') `p` ')
    .replaceAll('element', '`element`'), {expected: innerExpected}),
  success('inner-on-false', innerSql.replace('element = p.id', 'FALSE'), {expected: []}),
  success('inner-empty', innerSql, {parameters: {parents: []}, expected: []}),
  success('inner-immutable-json-control', JSON.stringify(innerCorrelatedUnnestImmutableProgram),
    {format: 'json', parameterDeclarations: undefined, expected: immutableInnerExpected}),
  success('inner-immutable-parent', innerPipe.replace('|> JOIN', '|> SELECT id, items |> AS p |> SET id = 99 |> JOIN')
    .replace('SELECT p.id,', 'SELECT id,'),
    {format: 'aql-text', expected: immutableInnerExpected}),
  success('inner-data', 'WITH expanded AS (' + innerPipe + ') FROM expanded |> RESULT answer',
    {format: 'aql-text', resultName: 'answer', expected: innerExpected}),
  success('inner-ordinary-join-continuation', innerSql.replace('ORDER BY',
    'JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 ORDER BY'),
    {expected: innerExpected.slice(1)}),
  success('inner-acquired-parent', 'SELECT r.id, element, position FROM records r '
    + 'JOIN UNNEST(@items) element WITH OFFSET position ON element = r.id ORDER BY r.id, position', {
    parameterDeclarations: {items}, parameters: {items: [2, null, 2]},
    sourceReadCount: 1, sourceReadSessionCount: 1,
    sourceRows: [{id: 2, amount: 20}, {id: 1, amount: null}], expected: innerExpected.slice(1),
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
  ...[
    innerSql.replace('element = p.id', 'element = p.missing'),
    innerPipe.replace('|> JOIN', '|> SELECT id, items |> JOIN'),
    innerSql.replace('ON element = p.id', 'USING (id)'),
    innerSql.replace('ON element = p.id', 'MAX_OUTPUT_ROWS 10'),
  ].map((text, index) => refusal('inner-' + index, text,
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})),
];
correlatedUnnestSuccesses.push(...correlatedUnnestStarSuccesses);
correlatedUnnestRefusals.push(...correlatedUnnestStarRefusals);
correlatedUnnestSuccesses.push(...joinedUnnestStarSuccesses);
correlatedUnnestRefusals.push(...joinedUnnestStarRefusals);
correlatedUnnestSuccesses.push(...unnestJoinSuccesses);
correlatedUnnestRefusals.push(...unnestJoinRefusals);

// Retained set/CTE schemas come from the common owners, not sampled rows.
export const retainedArrayProgram = {version: 'actql/0.1', id: 'fixture.retained_array',
  params: parameterDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {input: {$param: 'parents'}}},
    {unnest: {column: 'input', as: 'parent'}},
    {derive: {id: {property: {value: {field: 'parent'}, name: 'id'}},
      items: {property: {value: {field: 'parent'}, name: 'items'}}}},
    {select: ['id', 'items'], as: 'parents'},
    {from: 'parents', append: {with: 'parents'}, as: 'combined'},
    {from: 'combined', derive: {children: {field: 'items'}}},
    {unnest: {column: 'children', as: 'element', with_index: 'position'}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'element', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const retainedHead = 'FROM UNNEST(@parents) p |> SELECT id, items '
  + '|> UNION ALL (FROM UNNEST(@parents) p |> SELECT id, items)';
const retainedTail = '|> CROSS JOIN UNNEST(items) element WITH OFFSET position '
  + '|> SELECT * EXCEPT (items) |> ORDER BY id, position';
const retainedRows = [
  {id: 1, element: 1, position: 0}, {id: 1, element: 1, position: 0},
  {id: 2, element: 2, position: 0}, {id: 2, element: 2, position: 0},
  {id: 2, element: null, position: 1}, {id: 2, element: null, position: 1},
  {id: 2, element: 2, position: 2}, {id: 2, element: 2, position: 2},
];
const retainedSuccess = (name, text, extra = {}) => success('retained-' + name, text,
  {format: 'aql-text', expected: retainedRows, ...extra});
export const retainedArraySuccesses = [
  retainedSuccess('json-control', JSON.stringify(retainedArrayProgram), {
    format: 'json', parameterDeclarations: undefined,
  }),
  retainedSuccess('pipe-set-star', retainedHead + ' ' + retainedTail),
  retainedSuccess('pipe-set-filter-limit', retainedHead
    + ' |> CROSS JOIN UNNEST(items) element WITH OFFSET position '
    + '|> WHERE element IS NOT NULL |> SELECT * EXCEPT (items) '
    + '|> ORDER BY id, position |> LIMIT 3', {expected: retainedRows.slice(0, 3)}),
  retainedSuccess('data-set-star', 'WITH expanded AS (' + retainedHead + ' ' + retainedTail
    + ') FROM expanded |> RESULT answer', {resultName: 'answer'}),
  retainedSuccess('empty-set-star', retainedHead + ' ' + retainedTail,
    {parameters: {parents: []}, expected: []}),
  retainedSuccess('cte-array-alias', 'WITH chosen AS (SELECT p.id, p.items AS children '
    + 'FROM UNNEST(@parents) p) SELECT * EXCEPT (children) FROM chosen '
    + 'CROSS JOIN UNNEST(children) element WITH OFFSET position ORDER BY id, position',
    {format: 'sql', expected}),
  retainedSuccess('cte-array-chain', 'WITH first AS (SELECT p.id, p.items FROM UNNEST(@parents) p), '
    + 'chosen AS (SELECT id, items AS children FROM first) FROM chosen '
    + '|> CROSS JOIN UNNEST(children) element WITH OFFSET position '
    + '|> SELECT * EXCEPT (children) |> ORDER BY id, position', {expected}),
  retainedSuccess('cte-current-array', 'WITH chosen AS (SELECT p.id, [9] AS items '
    + 'FROM UNNEST(@parents) p) FROM chosen '
    + '|> CROSS JOIN UNNEST(items) element WITH OFFSET position '
    + '|> SELECT * EXCEPT (items) |> ORDER BY id, position', {
    columns: [columns[0], {name: 'element', contract: number}, columns[2]],
    expected: [{id: 1, element: 9, position: 0}, {id: 2, element: 9, position: 0},
      {id: 3, element: 9, position: 0}, {id: 4, element: 9, position: 0}],
  }),
  retainedSuccess('cte-object-star', 'WITH chosen AS (SELECT element AS payload, position '
    + 'FROM UNNEST(@items) element WITH OFFSET position) '
    + 'SELECT payload.*, position FROM chosen ORDER BY position', {
    format: 'sql',
    parameterDeclarations: {items: {type: 'array', nullable: true, max_items: 3,
      items: {type: 'object', nullable: true, fields: {
        id: number, label: {type: 'string', nullable: true},
      }}}},
    parameters: {items: [{id: 2, label: null}, null, {id: 1, label: 'a'}]},
    columns: [{name: 'id', contract: element},
      {name: 'label', contract: {type: 'string', nullable: true}}, columns[2]],
    expected: [{id: 2, label: null, position: 0}, {id: null, label: null, position: 1},
      {id: 1, label: 'a', position: 2}],
  }),
];
export const retainedArrayRefusals = [
  refusal('retained-dropped-column', 'WITH chosen AS (SELECT p.id FROM UNNEST(@parents) p) '
    + 'FROM chosen |> CROSS JOIN UNNEST(items) element |> SELECT *',
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'}),
  refusal('retained-dropped-range', 'WITH chosen AS (SELECT p.id, p.items FROM UNNEST(@parents) p) '
    + 'FROM chosen c |> SELECT id, items |> CROSS JOIN UNNEST(c.items) element |> SELECT *',
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'}),
];
correlatedUnnestSuccesses.push(...retainedArraySuccesses);
correlatedUnnestRefusals.push(...retainedArrayRefusals);
correlatedUnnestSuccesses.push(success('inner-retained-set', retainedHead
  + ' |> INNER JOIN UNNEST(items) element WITH OFFSET position ON element = id '
  + '|> SELECT * EXCEPT (items) |> ORDER BY id, position', {
  format: 'aql-text', expected: [
    {id: 1, element: 1, position: 0}, {id: 1, element: 1, position: 0},
    {id: 2, element: 2, position: 0}, {id: 2, element: 2, position: 0},
    {id: 2, element: 2, position: 2}, {id: 2, element: 2, position: 2},
  ],
}));
const innerObject = correlatedUnnestStarSuccesses.find(item => item.name === 'correlated-unnest-star-object-sql');
correlatedUnnestSuccesses.push({...innerObject, name: 'correlated-unnest-inner-object-on',
  text: innerObject.text.replace('CROSS JOIN', 'INNER JOIN')
    .replace('ORDER BY', 'ON e.code IS NOT NULL ORDER BY'),
  expected: [{id: 1, code: 10, label: 'a', position: 0},
    {id: 2, code: 20, label: null, position: 0}, {id: 2, code: 20, label: null, position: 2}],
});
