// Independent values and ordinary Program controls for correlated star scope.
// Neither the controls nor their expected schema/rows use compiler output.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const nullableString = {type: 'string', nullable: true};
const scalarItems = {type: 'array', nullable: true, max_items: 3, items: nullableNumber};
const objectItems = {type: 'array', nullable: true, max_items: 3,
  items: {type: 'object', nullable: true, fields: {code: number, label: nullableString}}};
const declarations = items => ({parents: {type: 'array', max_items: 4,
  items: {type: 'object', fields: {id: number, items}}}});
const scalarParameters = {parents: [{id: 2, items: [2, null, 2]}, {id: 1, items: [1]},
  {id: 3, items: []}, {id: 4, items: null}]};
const objectParameters = {parents: [
  {id: 2, items: [{code: 20, label: null}, null, {code: 20, label: null}]},
  {id: 1, items: [{code: 10, label: 'a'}]}, {id: 3, items: []}, {id: 4, items: null},
]};
const scalarColumns = [{name: 'id', contract: number}, {name: 'items', contract: scalarItems},
  {name: 'element', contract: nullableNumber}, {name: 'position', contract: number}];
const objectColumns = [{name: 'id', contract: number}, {name: 'code', contract: nullableNumber},
  {name: 'label', contract: nullableString}, {name: 'position', contract: number}];
const scalarRows = [{id: 1, items: [1], element: 1, position: 0},
  {id: 2, items: [2, null, 2], element: 2, position: 0},
  {id: 2, items: [2, null, 2], element: null, position: 1},
  {id: 2, items: [2, null, 2], element: 2, position: 2}];
const objectRows = [{id: 1, code: 10, label: 'a', position: 0},
  {id: 2, code: 20, label: null, position: 0},
  {id: 2, code: null, label: null, position: 1},
  {id: 2, code: 20, label: null, position: 2}];
const order = [{field: 'id', dir: 'asc', nulls: 'first'},
  {field: 'position', dir: 'asc', nulls: 'first'}];
const parentSteps = [
  {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
  {from: 'seed', derive: {parents: {$param: 'parents'}}},
  {unnest: {column: 'parents', as: 'parent'}},
  {derive: {id: {property: {value: {field: 'parent'}, name: 'id'}},
    original_items: {property: {value: {field: 'parent'}, name: 'items'}}}},
  {derive: {array: {field: 'original_items'}}},
  {unnest: {column: 'array', as: 'element', with_index: 'position'}},
];
const objectFields = {derive: {code: {property: {value: {field: 'element'}, name: 'code'}},
  label: {property: {value: {field: 'element'}, name: 'label'}}}};
const control = (id, items, fields, middle, select) => ({version: 'actql/0.1', id,
  params: declarations(items), stages: [{id: 'main', inputs: {}, steps: [
    ...parentSteps, ...middle, {sort: order}, {select, as: 'selected'},
  ], results: {rows: {from: 'selected', fields}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});
export const correlatedUnnestScalarStarProgram = control('fixture.correlated_unnest_scalar_star',
  scalarItems, ['id', 'items', 'element', 'position'], [],
  ['id', {items: 'original_items'}, 'element', 'position']);
export const correlatedUnnestObjectStarProgram = control('fixture.correlated_unnest_object_star',
  objectItems, ['id', 'code', 'label', 'position'], [objectFields],
  ['id', 'code', 'label', 'position']);
const success = (name, text, items, parameters, columns, expected, extra = {}) => ({
  name: 'correlated-unnest-star-' + name, format: 'sql', text,
  parameterDeclarations: declarations(items), parameters, columns, expected,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const scalarSql = 'SELECT * FROM UNNEST(@parents) p '
  + 'CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position';
const scalarPipe = 'FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position '
  + '|> SELECT * |> ORDER BY p.id, position';
const objectSql = 'SELECT p.id, e.*, position FROM UNNEST(@parents) p '
  + 'CROSS JOIN UNNEST(p.items) e WITH OFFSET position ORDER BY p.id, position';
const objectPipe = 'FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position '
  + '|> SELECT p.id, e.*, position |> ORDER BY p.id, position';
const scalar = (name, text, extra) => success(name, text, scalarItems, scalarParameters,
  scalarColumns, scalarRows, extra);
const object = (name, text, extra) => success(name, text, objectItems, objectParameters,
  objectColumns, objectRows, extra);
export const correlatedUnnestStarSuccesses = [
  scalar('scalar-json-control', JSON.stringify(correlatedUnnestScalarStarProgram),
    {format: 'json', parameterDeclarations: undefined}),
  scalar('scalar-sql', scalarSql),
  scalar('scalar-pipe', scalarPipe, {format: 'aql-text'}),
  object('object-json-control', JSON.stringify(correlatedUnnestObjectStarProgram),
    {format: 'json', parameterDeclarations: undefined}),
  object('object-sql', objectSql),
  object('object-pipe', objectPipe, {format: 'aql-text'}),
  object('quoted-parenthesized', objectSql.replaceAll('p.', '`p`.')
    .replace(') p ', ') `p` ').replace('UNNEST(`p`.items)', 'UNNEST((`p`).`ITEMS`)')),
  object('empty-parents', objectSql, {parameters: {parents: []}, expected: []}),
  object('empty-arrays', objectSql,
    {parameters: {parents: [{id: 1, items: []}, {id: 2, items: null}]}, expected: []}),
  object('immutable-range', objectPipe.replace('|> CROSS', '|> SELECT id, items |> AS p |> SET items = [9] |> CROSS'),
    {format: 'aql-text'}),
  object('current-column', 'FROM UNNEST(@parents) p |> SELECT id, items |> AS p |> SET items = [9] '
    + '|> CROSS JOIN UNNEST(items) e WITH OFFSET position |> SELECT * |> ORDER BY id, position', {
    format: 'aql-text', columns: [{name: 'id', contract: number},
      {name: 'items', contract: {type: 'array', nullable: false, max_items: 1, items: number}},
      {name: 'e', contract: number}, {name: 'position', contract: number}],
    expected: [1, 2, 3, 4].map(id => ({id, items: [9], e: 9, position: 0})),
  }),
  object('data', 'WITH expanded AS (' + objectPipe + ') FROM expanded |> RESULT answer',
    {format: 'aql-text', resultName: 'answer'}),
  object('filter-limit', objectSql.replace('ORDER BY', 'WHERE e.code IS NOT NULL ORDER BY') + ' LIMIT 2',
    {expected: [{id: 1, code: 10, label: 'a', position: 0}, {id: 2, code: 20, label: null, position: 0}]}),
];
export const correlatedUnnestStarRefusals = [
  {name: 'correlated-unnest-star-refusal-non-array', format: 'sql',
    text: scalarSql.replace('UNNEST(p.items)', 'UNNEST(p.id)'),
    parameterDeclarations: declarations(scalarItems), parameters: scalarParameters,
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'correlated-unnest-star-refusal-dropped-range', format: 'aql-text',
    text: 'FROM UNNEST(@parents) p |> SELECT id, items '
      + '|> CROSS JOIN UNNEST(p.items) e |> SELECT *',
    parameterDeclarations: declarations(objectItems), parameters: objectParameters,
    expectedCode: 'ClientProgramInvalidInput'},
];
