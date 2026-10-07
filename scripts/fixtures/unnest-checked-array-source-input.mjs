// Independent common ARRAY/IF/UNNEST controls and selected GoogleSQL value-table
// expectations. The empty cases retain schema without sampling any values.
const scalar = (type, nullable = false) => ({type, nullable});
const number = scalar('number');
const columns = (type, nullable = false) => [
  {name: 'element', contract: scalar(type, nullable)}, {name: 'position', contract: number},
];
const program = (expression, fields = ['element', 'position'], properties = [], params) => ({
  version: 'actql/0.1', id: 'fixture.unnest.checked_array', ...(params ? {params} : {}),
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: scalar('boolean')}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: expression}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    ...(properties.length ? [{derive: Object.fromEntries(properties.map(name => [name,
      {property: {value: {field: 'element'}, name}}]))}] : []),
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: fields, as: 'selected'},
  ], results: {rows: {from: 'selected', fields}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
});
const numeric = program({array: [{literal: 2}, {literal: 1}, {literal: 2}]});
const empty = program({empty_array: {items: scalar('string')}});
const nullable = program({if: [{literal: true}, {array: [{literal: null}]},
  {empty_array: {items: scalar('boolean')}}]});
const declarations = {items: {type: 'array', nullable: true, max_items: 3,
  items: {type: 'object', nullable: true, fields: {
    id: number, label: scalar('string', true),
  }}}};
const values = {items: [{id: 2, label: 'kept'}, null, {id: 2, label: null}]};
const computed = program({if: [{literal: true}, {$param: 'items'}, {$param: 'items'}]},
  ['id', 'label', 'position'], ['id', 'label'], declarations);
export const unnestCheckedArrayPrograms = {numeric, empty, nullable, computed};
const numericRows = [{element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}];
const objectRows = [{id: 2, label: 'kept', position: 0},
  {id: null, label: null, position: 1}, {id: 2, label: null, position: 2}];
const objectColumns = [{name: 'id', contract: scalar('number', true)},
  {name: 'label', contract: scalar('string', true)}, {name: 'position', contract: number}];
const sql = array => `SELECT * FROM UNNEST(${array}) element WITH OFFSET position ORDER BY position`;
const success = (name, text, expected, output, extra = {}) => ({
  name: 'unnest-checked-array-' + name, format: 'sql', text, expected, columns: output,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
export const unnestCheckedArraySuccesses = [
  success('numeric-json', JSON.stringify(numeric), numericRows, columns('number'), {format: 'json'}),
  success('numeric-sql', sql('[2, 1, 2]'), numericRows, columns('number')),
  success('numeric-pipe', 'FROM UNNEST(ARRAY[2, 1, 2]) element WITH OFFSET position |> SELECT * |> ORDER BY position',
    numericRows, columns('number'), {format: 'aql-text'}),
  success('empty-json', JSON.stringify(empty), [], columns('string'), {format: 'json'}),
  success('empty-sql', sql('ARRAY<STRING>[]'), [], columns('string')),
  success('contextual-empty', sql("IF(TRUE, [], ['x'])"), [], columns('string')),
  success('nullable-json', JSON.stringify(nullable), [{element: null, position: 0}], columns('boolean', true), {format: 'json'}),
  success('nullable-sql', sql('ARRAY<BOOL>[NULL]'), [{element: null, position: 0}], columns('boolean', true)),
  success('computed-json', JSON.stringify(computed), objectRows, objectColumns, {format: 'json', parameters: values}),
  success('computed-sql', sql('IF(TRUE, @items, @items)'), objectRows, objectColumns,
    {parameterDeclarations: declarations, parameters: values}),
  success('computed-pipe', 'FROM UNNEST(IF(TRUE, @items, @items)) element WITH OFFSET position |> SELECT element.*, position |> ORDER BY position',
    objectRows, objectColumns, {format: 'aql-text', parameterDeclarations: declarations, parameters: values}),
  success('computed-empty', sql('IF(TRUE, @items, @items)'), [], objectColumns,
    {parameterDeclarations: declarations, parameters: {items: []}}),
  success('computed-null', sql('IF(TRUE, @items, @items)'), [], objectColumns,
    {parameterDeclarations: declarations, parameters: {items: null}}),
];
export const unnestCheckedArrayRefusals = [
  ['untyped-empty', sql('[]')], ['unresolved-null', sql('[NULL]')],
  ['mixed-types', sql("[1, 'wrong']")], ['declared-wrong-type', sql('ARRAY<BOOL>[1]')],
  ['scalar-qualified-star', 'SELECT element.* FROM UNNEST([1, 2]) element'],
].map(([name, text]) => ({name: 'unnest-checked-array-refusal-' + name, format: 'sql', text}));
