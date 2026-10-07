// Independent GoogleSQL UNNEST expectations: NULL/empty arrays yield no rows,
// NULL elements and duplicates remain rows, and explicit offsets restore order.
const declarations = {items: {type: 'array', nullable: true, max_items: 3,
  items: {type: 'number', nullable: true}}};
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const columns = [column('element', true), column('position')];
const rows = [{element: 2, position: 0}, {element: null, position: 1},
  {element: 2, position: 2}];
const control = {version: 'actql/0.1', id: 'fixture.unnest', params: declarations,
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: {$param: 'items'}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['element', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['element', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, output = columns, extra = {}) => ({
  name: 'unnest-' + name, format: 'sql', text, expected, columns: output,
  parameterDeclarations: declarations, parameters: {items: [2, null, 2]},
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const sql = 'SELECT element, position FROM UNNEST(@items) AS element WITH OFFSET AS position ORDER BY position';
export const unnestSuccesses = [
  success('json-control', JSON.stringify(control), rows, columns,
    {format: 'json', parameterDeclarations: undefined}),
  success('sql-duplicates-and-null', sql, rows),
  success('scalar-star-sql',
    'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position', rows),
  success('scalar-star-pipe',
    'FROM UNNEST(@items) element WITH OFFSET position |> SELECT * |> ORDER BY position',
    rows, columns, {format: 'aql-text'}),
  success('scalar-star-empty',
    'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    [], columns, {parameters: {items: []}}),
  success('scalar-star-null-array',
    'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    [], columns, {parameters: {items: null}}),
  success('scalar-star-data-binding',
    'DATA expanded = FROM UNNEST(@items) element WITH OFFSET position |> SELECT *; FROM expanded |> ORDER BY position |> RESULT answer',
    rows, columns, {format: 'aql-text'}),
  success('pipe-duplicates-and-null',
    'FROM UNNEST(@items) AS element WITH OFFSET AS position |> SELECT element, position |> ORDER BY position',
    rows, columns, {format: 'aql-text'}),
  success('empty', sql, [], columns, {parameters: {items: []}}),
  success('null-array', sql, [], columns, {parameters: {items: null}}),
  success('default-offset',
    'SELECT element, offset FROM UNNEST(@items) element WITH OFFSET ORDER BY offset DESC',
    [{element: 2, offset: 2}, {element: null, offset: 1}, {element: 2, offset: 0}],
    [column('element', true), column('offset')]),
  success('predicate-and-current-scope',
    'FROM UNNEST(@items) element WITH OFFSET position |> AS t |> SELECT element, position |> WHERE element IS NOT NULL |> SELECT position AS n, element |> ORDER BY n DESC',
    [{n: 2, element: 2}, {n: 0, element: 2}],
    [column('n'), column('element', true)], {format: 'aql-text'}),
  success('quoted-names-and-hidden-slot-collision',
    'SELECT `aql_unnest_array_3` AS element, `position` FROM UNNEST(@items) AS `aql_unnest_array_3` WITH OFFSET AS `position` ORDER BY `position`',
    rows),
];
const refusal = (name, text, extra = {}) => ({name: 'unnest-refusal-' + name,
  format: 'sql', text, parameterDeclarations: declarations,
  parameters: {items: [2, null, 2]}, ...extra});
export const unnestRefusals = [
  refusal('undeclared', sql, {parameterDeclarations: undefined}),
  refusal('wrong-input-type', sql, {parameterDeclarations: {items: {type: 'number'}}, parameters: {items: 1}}),
  refusal('array-bound', sql, {parameters: {items: [1, 2, 3, 4]}}),
  refusal('duplicate-offset', 'SELECT element FROM UNNEST(@items) element WITH OFFSET AS ELEMENT'),
  refusal('hidden-witness', 'SELECT aql_source_free_unit FROM UNNEST(@items) element'),
  refusal('dropped-alias', 'FROM UNNEST(@items) element WITH OFFSET position |> AS t |> SELECT element, position |> WHERE t.element > 0', {format: 'aql-text'}),
  refusal('struct-missing-field', 'SELECT element.missing FROM UNNEST(@items) element',
    {parameterDeclarations: {items: {type: 'array', max_items: 3,
      items: {type: 'object', fields: {id: {type: 'number'}}}}}, parameters: {items: []}}),
  refusal('scalar-qualified-star', 'SELECT element.* FROM UNNEST(@items) element'),
];

// Independently authored STRUCT value-table control: field expansion preserves
// declaration order and common property nullability, including NULL elements.
const structDeclarations = {items: {type: 'array', nullable: true, max_items: 3,
  items: {type: 'object', nullable: true, fields: {
    id: {type: 'number', nullable: false}, label: {type: 'string', nullable: true},
  }}}};
const structValues = [{id: 2, label: null}, null, {id: 2, label: null}];
const structColumns = [column('id', true),
  {name: 'label', contract: {type: 'string', nullable: true}}, column('position')];
const structRows = [{id: 2, label: null, position: 0},
  {id: null, label: null, position: 1}, {id: 2, label: null, position: 2}];
const structControl = {version: 'actql/0.1', id: 'fixture.unnest.struct', params: structDeclarations,
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: {$param: 'items'}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    {derive: {id: {property: {value: {field: 'element'}, name: 'id'}},
      label: {property: {value: {field: 'element'}, name: 'label'}}}},
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'label', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'label', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const structSuccess = (name, text, expected = structRows, columns = structColumns, extra = {}) =>
  success('struct-' + name, text, expected, columns, {
    parameterDeclarations: structDeclarations, parameters: {items: structValues}, ...extra,
  });
unnestSuccesses.push(
  structSuccess('json-control', JSON.stringify(structControl), structRows, structColumns,
    {format: 'json', parameterDeclarations: undefined}),
  structSuccess('star-sql', 'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position'),
  structSuccess('star-pipe', 'FROM UNNEST(@items) element WITH OFFSET position |> SELECT * |> ORDER BY position', structRows, structColumns, {format: 'aql-text'}),
  structSuccess('qualified-star', 'SELECT element.*, position FROM UNNEST((@items)) element WITH OFFSET position ORDER BY position'),
  structSuccess('empty', 'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position', [], structColumns, {parameters: {items: []}}),
  structSuccess('null-array', 'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position', [], structColumns, {parameters: {items: null}}),
  structSuccess('whole-value', 'SELECT element AS original, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    structValues.map((original, position) => ({original, position})),
    [{name: 'original', contract: structDeclarations.items.items}, column('position')]),
  structSuccess('predicate-except', 'SELECT element.* EXCEPT (label), position FROM UNNEST(@items) element WITH OFFSET position WHERE id IS NOT NULL ORDER BY position',
    [{id: 2, position: 0}, {id: 2, position: 2}], [column('id', true), column('position')]),
  structSuccess('immutable-range', 'FROM UNNEST(@items) element WITH OFFSET position |> SET id = id + 10 |> SELECT id AS current, element.id AS original, position |> ORDER BY position',
    [{current: 12, original: 2, position: 0}, {current: null, original: null, position: 1}, {current: 12, original: 2, position: 2}],
    [column('current', true), column('original', true), column('position')], {format: 'aql-text'}),
  structSuccess('data-binding', 'DATA expanded = FROM UNNEST(@items) element WITH OFFSET position |> SELECT *; FROM expanded |> ORDER BY position |> RESULT answer',
    structRows, structColumns, {format: 'aql-text'}),
);
for (const [name, text] of [
  ['dropped-receiver', 'FROM UNNEST(@items) element |> SELECT id |> WHERE element.label IS NULL'],
  ['replaced-range', 'FROM UNNEST(@items) element |> AS current |> WHERE element.id IS NULL'],
  ['star-is-relation', 'FROM UNNEST(@items) element |> SELECT * |> WHERE element.id IS NULL'],
]) unnestRefusals.push(refusal('struct-' + name, text, {format: 'aql-text',
  parameterDeclarations: structDeclarations, parameters: {items: structValues}}));

const nested = {type: 'object', nullable: true, fields: {
  score: {type: 'number', nullable: true},
}};
const nestedDeclarations = {items: {type: 'array', max_items: 2,
  items: {type: 'object', fields: {id: {type: 'number'}, nested}}}};
unnestSuccesses.push(structSuccess('nested-top-level',
  'SELECT element.*, position FROM UNNEST(@items) AS element WITH OFFSET position ORDER BY position',
  [{id: 1, nested: {score: null}, position: 0}, {id: 2, nested: null, position: 1}],
  [column('id'), {name: 'nested', contract: nested}, column('position')],
  {parameterDeclarations: nestedDeclarations,
    parameters: {items: [{id: 1, nested: {score: null}}, {id: 2, nested: null}]}}));
