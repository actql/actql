import {unnestCheckedArraySuccesses, unnestCheckedArrayRefusals}
  from './unnest-checked-array-source-input.mjs';
// Independent GoogleSQL UNNEST expectations: NULL/empty arrays yield no rows,
// NULL elements and duplicates remain rows, and explicit offsets restore order.
import {unnestParameterPathSuccesses, unnestParameterPathRefusals}
  from './unnest-parameter-path-source-input.mjs';
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
const renamedColumns = [column('next', true), column('position')];
const renamedRows = [{next: 2, position: 0}, {next: null, position: 1}, {next: 2, position: 2}];
// Independent normal Program: only the public projection name changes.
const renameControl = {...control, stages: [{...control.stages[0],
  steps: [...control.stages[0].steps.slice(0, -1),
    {select: [{next: 'element'}, 'position'], as: 'selected'}],
  results: {rows: {from: 'selected', fields: ['next', 'position']}}}]};
const offsetColumns = [column('element', true), column('next')];
const offsetRows = rows.map(row => ({element: row.element, next: row.position}));
// Independent normal Program: rename the emitted offset only at projection.
const offsetControl = {...control, stages: [{...control.stages[0],
  steps: [...control.stages[0].steps.slice(0, -1),
    {select: ['element', {next: 'position'}], as: 'selected'}],
  results: {rows: {from: 'selected', fields: ['element', 'next']}}}]};
export const unnestSuccesses = [
  success('offset-rename-json-control', JSON.stringify(offsetControl), offsetRows, offsetColumns,
    {format: 'json', parameterDeclarations: undefined}),
  success('offset-rename-after-select',
    'FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME position AS next |> ORDER BY next',
    offsetRows, offsetColumns, {format: 'aql-text'}),
  success('offset-rename-after-as',
    'FROM UNNEST(@items) element WITH OFFSET position |> AS row |> RENAME position AS next |> SELECT element, next |> ORDER BY next',
    offsetRows, offsetColumns, {format: 'aql-text'}),
  success('offset-rename-after-set',
    'FROM UNNEST(@items) element WITH OFFSET position |> SET position = position + 10 |> RENAME position AS next |> SELECT element, next |> ORDER BY next',
    offsetRows.map(row => ({...row, next: row.next + 10})), offsetColumns, {format: 'aql-text'}),
  success('offset-default-after-select',
    'FROM UNNEST(@items) element WITH OFFSET |> SELECT element, offset |> RENAME offset AS next |> ORDER BY next',
    offsetRows, offsetColumns, {format: 'aql-text'}),
  success('offset-rename-empty',
    'FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME position AS next |> ORDER BY next',
    [], offsetColumns, {format: 'aql-text', parameters: {items: []}}),
  success('offset-drop-allows-new-range',
    'FROM UNNEST(@items) element WITH OFFSET position |> DROP position |> CROSS JOIN UNNEST([10]) position WITH OFFSET index |> SELECT element, position, index |> ORDER BY element NULLS LAST',
    [{element: 2, position: 10, index: 0}, {element: 2, position: 10, index: 0},
      {element: null, position: 10, index: 0}],
    [column('element', true), column('position'), column('index')], {format: 'aql-text'}),
  success('json-control', JSON.stringify(control), rows, columns,
    {format: 'json', parameterDeclarations: undefined}),
  success('scalar-rename-json-control', JSON.stringify(renameControl), renamedRows, renamedColumns,
    {format: 'json', parameterDeclarations: undefined}),
  success('scalar-rename-after-select',
    'FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME element AS next |> ORDER BY position',
    renamedRows, renamedColumns, {format: 'aql-text'}),
  success('scalar-rename-after-as',
    'FROM UNNEST(@items) element WITH OFFSET position |> AS row |> RENAME element AS next |> ORDER BY position',
    renamedRows, renamedColumns, {format: 'aql-text'}),
  success('scalar-rename-after-set',
    'FROM UNNEST(@items) element WITH OFFSET position |> SET element = 100 |> RENAME element AS next |> SELECT * |> ORDER BY position',
    [{next: 100, position: 0}, {next: 100, position: 1}, {next: 100, position: 2}],
    [column('next'), column('position')], {format: 'aql-text'}),
  success('scalar-drop-removes-range',
    'FROM UNNEST(@items) element WITH OFFSET position |> DROP element |> SELECT position |> RENAME position AS next |> SELECT * |> ORDER BY next',
    [{next: 0}, {next: 1}, {next: 2}], [column('next')], {format: 'aql-text'}),
  success('scalar-distinct-keeps-values',
    'FROM UNNEST(@items) element WITH OFFSET position |> DROP position |> DISTINCT |> SELECT element AS next |> ORDER BY next NULLS LAST',
    [{next: 2}, {next: null}], [column('next', true)], {format: 'aql-text'}),
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
    'WITH expanded AS (FROM UNNEST(@items) element WITH OFFSET position |> SELECT *) FROM expanded |> ORDER BY position |> RESULT answer',
    rows, columns, {format: 'aql-text', resultName: 'answer'}),
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
  ...[
    'FROM UNNEST(@items) element WITH OFFSET position |> RENAME position AS next |> SELECT element, next |> ORDER BY next',
    'FROM UNNEST(@items) element WITH OFFSET `Position` |> RENAME `POSITION` AS next |> SELECT element, next |> ORDER BY next',
    'FROM UNNEST(@items) element WITH OFFSET |> RENAME offset AS next |> SELECT element, next |> ORDER BY next',
    'FROM UNNEST(@items) element WITH OFFSET position |> DROP element |> RENAME position AS next |> SELECT next |> ORDER BY next',
    'FROM UNNEST(@items) element WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 |> RENAME position AS next |> SELECT element, next |> ORDER BY next',
    'FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) position |> SELECT element',
    'FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) other WITH OFFSET position |> SELECT element',
    'FROM UNNEST(@items) element |> CROSS JOIN UNNEST(@items) other WITH OFFSET element |> SELECT other',
  ].map((text, index) => refusal('offset-range-' + index, text,
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})),
  ...['element', '`element`', '`ELEMENT`'].map((name, index) =>
    refusal('scalar-rename-range-' + index,
      'FROM UNNEST(@items) ' + name + ' WITH OFFSET position |> RENAME ' + name + ' AS next |> SELECT next, position |> ORDER BY position',
      {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'})),
  refusal('scalar-rename-range-after-join',
    'FROM UNNEST(@items) element WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 |> RENAME element AS next |> SELECT next, position',
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'}),
  refusal('scalar-range-duplicate-unnest',
    'FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) element |> SELECT position',
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'}),
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
// admitted object field order and common property nullability, including NULL elements.
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
  structSuccess('non-null-string', 'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    [{id: 2, label: 'kept', position: 0}, {id: null, label: null, position: 1},
      {id: 2, label: null, position: 2}], structColumns,
    {parameters: {items: [{id: 2, label: 'kept'}, null, {id: 2, label: null}]}}),
  structSuccess('whole-value', 'SELECT element AS original, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    structValues.map((original, position) => ({original, position})),
    [{name: 'original', contract: {...structDeclarations.items.items,
      additional_properties: false}}, column('position')]),
  structSuccess('predicate-except', 'SELECT element.* EXCEPT (label), position FROM UNNEST(@items) element WITH OFFSET position WHERE id IS NOT NULL ORDER BY position',
    [{id: 2, position: 0}, {id: 2, position: 2}], [column('id', true), column('position')]),
  structSuccess('immutable-range', 'FROM UNNEST(@items) element WITH OFFSET position |> SELECT id, position |> AS input |> SET id = id + 10 |> SELECT id AS current, input.id AS original, position |> ORDER BY position',
    [{current: 12, original: 2, position: 0}, {current: null, original: null, position: 1}, {current: 12, original: 2, position: 2}],
    [column('current', true), column('original', true), column('position')], {format: 'aql-text'}),
  structSuccess('data-binding', 'WITH expanded AS (FROM UNNEST(@items) element WITH OFFSET position |> SELECT *) FROM expanded |> ORDER BY position |> RESULT answer',
    structRows, structColumns, {format: 'aql-text', resultName: 'answer'}),
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
  [column('id'), {name: 'nested', contract: {...nested, additional_properties: false}}, column('position')],
  {parameterDeclarations: nestedDeclarations,
    parameters: {items: [{id: 1, nested: {score: null}}, {id: 2, nested: null}]}}));

unnestSuccesses.push(...unnestParameterPathSuccesses);
unnestRefusals.push(...unnestParameterPathRefusals);

unnestSuccesses.push(...unnestCheckedArraySuccesses);
unnestRefusals.push(...unnestCheckedArrayRefusals);

// ORDER positions count actual value-table columns, not implicit object fields.
// The label order deliberately opposes the offset order. These expectations and
// ordinary JSON ports are authored independently of the frontend's private slots.
const ordinalParameters = {items: [{id: 2, label: 'z'}, null, {id: 1, label: 'a'}]};
const ordinalRows = [{id: 2, label: 'z', position: 0},
  {id: null, label: null, position: 1}, {id: 1, label: 'a', position: 2}];
const ordinalControl = {version: 'actql/0.1', id: 'fixture.unnest.ordinal', params: structDeclarations,
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: {$param: 'items'}}},
    {unnest: {column: 'array', as: 'whole', with_index: 'position'}},
    {derive: {id: {property: {value: {field: 'whole'}, name: 'id'}},
      label: {property: {value: {field: 'whole'}, name: 'label'}}}},
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'label', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'label', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const ordinalHead = 'FROM UNNEST(@items) element WITH OFFSET position';
const ordinalSuccess = (name, text, extra = {}) => structSuccess('ordinal-' + name, text,
  extra.expected ?? ordinalRows, extra.columns ?? structColumns,
  {format: 'aql-text', parameters: ordinalParameters, ...extra});
unnestSuccesses.push(
  ordinalSuccess('json-control', JSON.stringify(ordinalControl),
    {format: 'json', parameterDeclarations: undefined}),
  ordinalSuccess('offset-before-select', `${ordinalHead} |> ORDER BY 2 |> SELECT element.*, position`),
  ordinalSuccess('signed-quoted',
    'FROM UNNEST(@items) `element` WITH OFFSET `position` |> ORDER BY (+2) |> SELECT `element`.*, `position`'),
  ordinalSuccess('projected-members', `${ordinalHead} |> SELECT element.*, position |> ORDER BY 2`,
    {expected: [{id: null, label: null, position: 1}, {id: 1, label: 'a', position: 2},
      {id: 2, label: 'z', position: 0}]}),
  ordinalSuccess('reordered-projection', `${ordinalHead} |> SELECT position, element.* |> ORDER BY 1`,
    {expected: [{position: 0, id: 2, label: 'z'}, {position: 1, id: null, label: null},
      {position: 2, id: 1, label: 'a'}], columns: [column('position'), ...structColumns.slice(0, 2)]}),
  ordinalSuccess('same-named-offset',
    'FROM UNNEST(@items) element WITH OFFSET id |> ORDER BY 2 |> SELECT element.id AS original, id AS position',
    {expected: [{original: 2, position: 0}, {original: null, position: 1}, {original: 1, position: 2}],
      columns: [column('original', true), column('position')]}),
  ordinalSuccess('drop-value', `${ordinalHead} |> DROP element |> ORDER BY 1 |> SELECT position`,
    {expected: [{position: 0}, {position: 1}, {position: 2}], columns: [column('position')]}),
  ordinalSuccess('extend-column',
    `${ordinalHead} |> EXTEND 10 - position AS extra |> ORDER BY 3 |> SELECT element.*, position, extra`,
    {expected: [{id: 1, label: 'a', position: 2, extra: 8},
      {id: null, label: null, position: 1, extra: 9}, {id: 2, label: 'z', position: 0, extra: 10}],
      columns: [...structColumns, column('extra')]}),
  ordinalSuccess('set-offset',
    `${ordinalHead} |> SET position = 10 - position |> ORDER BY 2 |> SELECT element.*, position`,
    {expected: [{id: 1, label: 'a', position: 8}, {id: null, label: null, position: 9},
      {id: 2, label: 'z', position: 10}]}),
  ordinalSuccess('join-remapping',
    `${ordinalHead} |> JOIN (SELECT 2 AS key UNION ALL SELECT 1 AS key) k ON element.id = k.key MAX_OUTPUT_ROWS 3 |> ORDER BY 2 |> SELECT element.*, position`,
    {expected: [{id: 2, label: 'z', position: 0}, {id: 1, label: 'a', position: 2}]}),
  ordinalSuccess('empty-objects', `${ordinalHead} |> ORDER BY 2 DESC |> SELECT position`,
    {parameterDeclarations: {items: {type: 'array', nullable: true, max_items: 3,
      items: {type: 'object', nullable: true, fields: {}}}},
      parameters: {items: [{}, null]}, expected: [{position: 1}, {position: 0}], columns: [column('position')]}),
  ordinalSuccess('null-array', `${ordinalHead} |> ORDER BY 2 |> SELECT element.*, position`,
    {parameters: {items: null}, expected: []}),
);
for (const [name, text] of [
  ['outside-actual-columns', `${ordinalHead} |> ORDER BY 3 |> SELECT element.*, position`],
  ['without-offset', 'FROM UNNEST(@items) element |> ORDER BY 2 |> SELECT element.*'],
  ['after-drop', `${ordinalHead} |> DROP element |> ORDER BY 2 |> SELECT position`],
]) unnestRefusals.push(refusal('ordinal-' + name, text,
  {format: 'aql-text', parameterDeclarations: structDeclarations, parameters: ordinalParameters,
    // The requested position exceeds the actual columns at this Pipe boundary.
    expectedCode: 'ClientProgramInvalidInput'}));

// Independent range/field collision obligations. A value-table range denotes
// its original object even when the object exposes a same-named scalar field.
const receiverItem = {type: 'object', nullable: true, fields: {
  element: {type: 'number', nullable: true}, id: {type: 'number', nullable: false},
}};
const receiverDeclarations = {items: {type: 'array', nullable: true, max_items: 4, items: receiverItem}};
const receiverParameters = {items: [{element: null, id: 2}, null,
  {element: 9, id: 1}, {element: 9, id: 1}]};
const receiverColumns = [{name: 'original', contract: {...receiverItem, additional_properties: false}},
  column('field_value', true), column('position')];
const receiverRows = [
  {original: {element: null, id: 2}, field_value: null, position: 0},
  {original: null, field_value: null, position: 1},
  {original: {element: 9, id: 1}, field_value: 9, position: 2},
  {original: {element: 9, id: 1}, field_value: 9, position: 3},
];
export const unnestReceiverProgram = {version: 'actql/0.1', id: 'fixture.unnest.receiver',
  params: receiverDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: {$param: 'items'}}},
    {unnest: {column: 'array', as: 'receiver', with_index: 'position'}},
    {derive: {member: {property: {value: {field: 'receiver'}, name: 'element'}}}},
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: [{original: 'receiver'}, {field_value: 'member'}, 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['original', 'field_value', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const receiverSql = 'SELECT element AS original, element.element AS field_value, position '
  + 'FROM UNNEST(@items) element WITH OFFSET position ORDER BY position';
const receiverPipe = 'FROM UNNEST(@items) element WITH OFFSET position '
  + '|> SELECT element AS original, element.element AS field_value, position |> ORDER BY position';
const receiverSuccess = (name, text, extra = {}) => ({name: 'unnest-receiver-' + name,
  format: 'sql', text, parameterDeclarations: receiverDeclarations, parameters: receiverParameters,
  expected: receiverRows, columns: receiverColumns, sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const receiverStarColumns = [column('element', true), column('id', true), column('position')];
const receiverStarRows = [{element: null, id: 2, position: 0},
  {element: null, id: null, position: 1}, {element: 9, id: 1, position: 2},
  {element: 9, id: 1, position: 3}];
export const unnestReceiverSuccesses = [
  receiverSuccess('json-control', JSON.stringify(unnestReceiverProgram),
    {format: 'json', parameterDeclarations: undefined}),
  receiverSuccess('sql', receiverSql),
  receiverSuccess('pipe', receiverPipe, {format: 'aql-text'}),
  receiverSuccess('quoted', receiverSql.replaceAll('element', '`ELEMENT`')),
  receiverSuccess('parenthesized', receiverSql.replace('element AS original, element.element',
    '(element) AS original, (element).element')),
  receiverSuccess('null-predicate', receiverSql.replace('ORDER BY', 'WHERE element IS NOT NULL ORDER BY'),
    {expected: [receiverRows[0], receiverRows[2], receiverRows[3]]}),
  receiverSuccess('star', 'SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position',
    {expected: receiverStarRows, columns: receiverStarColumns}),
  receiverSuccess('qualified-star', 'SELECT element.*, position FROM UNNEST(@items) element '
    + 'WITH OFFSET position ORDER BY position', {expected: receiverStarRows, columns: receiverStarColumns}),
  receiverSuccess('set-retains-original', receiverPipe.replace('|> SELECT', '|> SET position = position + 10 |> SELECT'),
    {format: 'aql-text', expected: receiverRows.map(row => ({...row, position: row.position + 10}))}),
  receiverSuccess('set-current-star', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> SET element = 100 |> SELECT * |> ORDER BY position', {format: 'aql-text',
    expected: [0, 1, 2, 3].map(position => ({element: 100, position})),
    columns: [column('element'), column('position')]}),
  // Independent normal Program: replace the UNNEST value column, then select
  // that one column and the offset. No object member remains in the current row.
  receiverSuccess('set-json-control', JSON.stringify({version: 'actql/0.1',
    id: 'fixture.unnest.set.value', params: receiverDeclarations, stages: [{id: 'main',
      inputs: {}, steps: [
        {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
        {from: 'seed', derive: {array: {$param: 'items'}}},
        {unnest: {column: 'array', as: 'element', with_index: 'position'}},
        {derive: {replacement: {literal: 100}}},
        {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
        {select: [{element: 'replacement'}, 'position'], as: 'selected'},
      ], results: {rows: {from: 'selected', fields: ['element', 'position']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}}),
    {format: 'json', parameterDeclarations: undefined,
      expected: [0, 1, 2, 3].map(position => ({element: 100, position})),
      columns: [column('element'), column('position')]}),
  receiverSuccess('set-quoted-whole', 'FROM UNNEST(@items) `element` WITH OFFSET position '
    + '|> SET `ELEMENT` = 100 |> SELECT * |> ORDER BY position', {format: 'aql-text',
    expected: [0, 1, 2, 3].map(position => ({element: 100, position})),
    columns: [column('element'), column('position')]}),
  receiverSuccess('set-noncolliding-name', 'FROM UNNEST(@items) row WITH OFFSET position '
    + '|> SET row = 100 |> SELECT * |> ORDER BY position', {format: 'aql-text',
    expected: [0, 1, 2, 3].map(position => ({row: 100, position})),
    columns: [column('row'), column('position')]}),
  receiverSuccess('set-empty', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> SET element = 100 |> SELECT * |> ORDER BY position', {format: 'aql-text',
    parameters: {items: []}, expected: [], columns: [column('element'), column('position')]}),
  receiverSuccess('set-empty-object-elements', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> SET element = 100 |> SELECT * |> ORDER BY position', {format: 'aql-text',
    parameterDeclarations: {items: {type: 'array', nullable: true, max_items: 4,
      items: {type: 'object', nullable: true, fields: {}}}},
    parameters: {items: [{}, null]}, expected: [{element: 100, position: 0}, {element: 100, position: 1}],
    columns: [column('element'), column('position')]}),
  receiverSuccess('set-object-value', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> SET element = @replacement |> SELECT * |> ORDER BY position', {format: 'aql-text',
    parameterDeclarations: {...receiverDeclarations, replacement: {type: 'object', nullable: false,
      fields: {id: {type: 'number', nullable: false}}}},
    parameters: {...receiverParameters, replacement: {id: 99}},
    expected: [0, 1, 2, 3].map(position => ({element: {id: 99}, position})),
    columns: [{name: 'element', contract: {type: 'object', nullable: false,
      additional_properties: false, fields: {id: {type: 'number', nullable: false}}}}, column('position')]}),
  receiverSuccess('set-siblings-original-object', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> SET element = 100, position = element.id |> SELECT * |> ORDER BY position NULLS LAST',
    {format: 'aql-text', expected: [{element: 100, position: 1}, {element: 100, position: 1},
      {element: 100, position: 2}, {element: 100, position: null}],
    columns: [column('element'), column('position', true)]}),
  receiverSuccess('drop-whole', 'FROM UNNEST(@items) element WITH OFFSET position '
    + '|> DROP element |> SELECT * |> ORDER BY position', {format: 'aql-text',
    expected: [0, 1, 2, 3].map(position => ({position})), columns: [column('position')]}),
  receiverSuccess('empty', receiverSql, {parameters: {items: []}, expected: []}),
  receiverSuccess('null-array', receiverSql, {parameters: {items: null}, expected: []}),
];
export const unnestReceiverRefusals = [
  ...[
    ['set-implicit-field', 'SET id = 100'],
    ['drop-implicit-field', 'DROP id'],
    ['rename-implicit-field', 'RENAME id AS next'],
    ['set-scalar-member', 'SET element = 100 |> WHERE element.element IS NULL'],
  ].map(([name, operation]) => ({name: 'unnest-receiver-refusal-' + name,
    format: 'aql-text', text: 'FROM UNNEST(@items) element WITH OFFSET position |> '
      + operation + ' |> SELECT position'})),
  {name: 'unnest-receiver-refusal-select-ends-range', format: 'aql-text',
    text: 'FROM UNNEST(@items) element |> SELECT id |> WHERE element IS NOT NULL'},
  {name: 'unnest-receiver-refusal-as-ends-range', format: 'aql-text',
    text: 'FROM UNNEST(@items) element |> AS current |> SELECT (element).id AS id'},
  {name: 'unnest-receiver-refusal-missing-member', format: 'sql',
    text: 'SELECT (element).missing AS missing FROM UNNEST(@items) element'},
].map(value => ({...value, parameterDeclarations: receiverDeclarations,
  parameters: receiverParameters, expectedCode: 'ClientProgramInvalidInput'}));
unnestSuccesses.push(...unnestReceiverSuccesses);
unnestRefusals.push(...unnestReceiverRefusals);

// Scalar range receivers outrank same-named implicit parent fields. This
// independent Program selects the real element/index; no text output is used.
const precedenceDeclarations = {parents: {type: 'array', nullable: true, max_items: 1,
  items: {type: 'object', nullable: false, fields: {
    element: {type: 'number', nullable: false}, position: {type: 'number', nullable: false},
    items: declarations.items,
  }}}};
const precedenceParameters = {parents: [{element: 100, position: 50, items: [2, null, 1]}]};
const precedenceFields = ['element', 'original', 'position', 'original_position'];
const precedenceColumns = [column('element', true), column('original'),
  column('position'), column('original_position')];
const precedenceRows = [{element: 2, original: 100, position: 0, original_position: 50},
  {element: null, original: 100, position: 1, original_position: 50},
  {element: 1, original: 100, position: 2, original_position: 50}];
const precedencePrefix = [
  {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
  {from: 'seed', derive: {parents: {$param: 'parents'}}},
  {unnest: {column: 'parents', as: 'parent'}},
  {derive: {array: {property: {value: {field: 'parent'}, name: 'items'}},
    original: {property: {value: {field: 'parent'}, name: 'element'}},
    original_position: {property: {value: {field: 'parent'}, name: 'position'}}}},
  {unnest: {column: 'array', as: 'element', with_index: 'position'}},
];
const precedenceProgram = {version: 'actql/0.1', id: 'fixture.unnest.scalar_receiver',
  params: precedenceDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    ...precedencePrefix,
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: precedenceFields, as: 'selected'},
  ], results: {rows: {from: 'selected', fields: precedenceFields}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const precedenceSelect = 'SELECT element, p.element AS original, position, p.position AS original_position';
const precedenceFrom = 'FROM UNNEST(@parents) p CROSS JOIN UNNEST(p.items) element WITH OFFSET position';
const precedencePipe = 'FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position';
const precedenceSuccess = (name, text, extra = {}) => ({
  name: 'unnest-scalar-receiver-' + name, format: 'aql-text', text,
  expected: precedenceRows, columns: precedenceColumns,
  parameterDeclarations: precedenceDeclarations, parameters: precedenceParameters,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
unnestSuccesses.push(
  precedenceSuccess('json-control', JSON.stringify(precedenceProgram),
    {format: 'json', parameterDeclarations: undefined}),
  precedenceSuccess('pipe', `${precedencePipe} |> ${precedenceSelect} |> ORDER BY position`),
  precedenceSuccess('sql', `${precedenceSelect} ${precedenceFrom} ORDER BY position`, {format: 'sql'}),
  precedenceSuccess('quoted',
    'FROM UNNEST(@parents) `P` |> CROSS JOIN UNNEST(`p`.items) `ELEMENT` WITH OFFSET `POSITION` '
      + '|> SELECT `element` AS element, p.element AS original, `position` AS position, p.position AS original_position |> ORDER BY position'),
  precedenceSuccess('predicate', `${precedencePipe} |> WHERE element > 1 |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [precedenceRows[0]]}),
  precedenceSuccess('offset-predicate', `${precedencePipe} |> WHERE position = 1 |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [precedenceRows[1]]}),
  precedenceSuccess('computed-predicate', `${precedencePipe} |> WHERE element + 1 > 2 |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [precedenceRows[0]]}),
  precedenceSuccess('receiver-order', `${precedencePipe} |> ORDER BY element NULLS LAST |> ${precedenceSelect}`,
    {expected: [precedenceRows[2], precedenceRows[0], precedenceRows[1]]}),
  precedenceSuccess('empty', `${precedencePipe} |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [], parameters: {parents: []}}),
  precedenceSuccess('null-parent-array', `${precedencePipe} |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [], parameters: {parents: null}}),
  precedenceSuccess('join-remapping', `${precedencePipe} |> WHERE position = 0 `
    + '|> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 3 '
    + `|> WHERE position = 0 |> ${precedenceSelect} |> ORDER BY position`,
    {expected: [precedenceRows[0]]}),
  precedenceSuccess('group-sql', `SELECT element, COUNT(*) AS n ${precedenceFrom} GROUP BY element ORDER BY element NULLS LAST`,
    {format: 'sql', expected: [{element: 1, n: 1}, {element: 2, n: 1}, {element: null, n: 1}],
      columns: [column('element', true), column('n')]}),
  precedenceSuccess('group-pipe', `${precedencePipe} |> AGGREGATE COUNT(*) AS n GROUP BY element |> ORDER BY element NULLS LAST`,
    {expected: [{element: 1, n: 1}, {element: 2, n: 1}, {element: null, n: 1}],
      columns: [column('element', true), column('n')]}),
);
unnestRefusals.push(...[
  ['removed-element', `${precedencePipe} |> SELECT p.element AS original |> WHERE element > 0`],
  ['removed-offset', `${precedencePipe} |> SELECT p.position AS original_position |> WHERE position = 0`],
  ['removed-parent-range', `${precedencePipe} |> ${precedenceSelect} |> WHERE p.element > 0`],
  ['scalar-member', `${precedencePipe} |> SELECT element.missing AS missing`],
].map(([name, text]) => ({name: 'unnest-refusal-scalar-receiver-' + name, text,
  format: 'aql-text', parameterDeclarations: precedenceDeclarations, parameters: precedenceParameters,
  expectedCode: 'ClientProgramInvalidInput'})));


// Pipe AS is a name-list operation, not a value projection. A single value
// table stays one value table; a mixed table admits its former range as a
// current whole column while preserving the original field-expanding star.
const asParameters = {items: [{id: 2, label: 'z'}, null, {id: 1, label: 'a'}]};
const asObjectContract = {...structDeclarations.items.items, additional_properties: false};
const asWholeColumns = [{name: 'original', contract: asObjectContract}, column('position')];
const asWholeRows = [{original: {id: 2, label: 'z'}, position: 0},
  {original: null, position: 1}, {original: {id: 1, label: 'a'}, position: 2}];
const asHead = 'FROM UNNEST(@items) element WITH OFFSET position |> AS current';
// Both controls are independent common Programs, with no AS computation.
const asScalarControl = {version: 'actql/0.1', id: 'fixture.unnest.as.scalar',
  params: declarations, stages: [{id: 'main', inputs: {}, steps: [
    control.stages[0].steps[0], control.stages[0].steps[1],
    {unnest: {column: 'array', as: 'element'}},
    {filter: {gt: [{field: 'element'}, {literal: 0}]}},
    {sort: [{field: 'element', dir: 'asc', nulls: 'first'}]},
    {select: [{value: 'element'}], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const asWholeControl = {...structControl, id: 'fixture.unnest.as.whole',
  stages: [{...structControl.stages[0], steps: [
    ...structControl.stages[0].steps.slice(0, 3),
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: [{original: 'element'}, 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['original', 'position']}}}]};
const asSuccess = (name, text, expected = asWholeRows, columns = asWholeColumns, extra = {}) =>
  structSuccess('as-' + name, text, expected, columns,
    {format: 'aql-text', parameters: asParameters, ...extra});
unnestSuccesses.push(
  success('as-scalar-json-control', JSON.stringify(asScalarControl), [{value: 1}, {value: 2}],
    [column('value', true)], {format: 'json', parameterDeclarations: undefined, parameters: {items: [2, null, 1]}}),
  success('as-scalar-repeated', 'FROM UNNEST(@items) element |> AS first |> AS `Current` '
    + '|> WHERE `CURRENT` > 0 |> SELECT current AS value |> ORDER BY value',
    [{value: 1}, {value: 2}], [column('value', true)], {format: 'aql-text', parameters: {items: [2, null, 1]}}),
  asSuccess('whole-json-control', JSON.stringify(asWholeControl), asWholeRows, asWholeColumns,
    {format: 'json', parameterDeclarations: undefined}),
  asSuccess('single-whole', 'FROM UNNEST(@items) element |> AS current '
    + '|> SELECT current AS original, id |> ORDER BY id NULLS LAST',
    [{original: {id: 1, label: 'a'}, id: 1}, {original: {id: 2, label: 'z'}, id: 2}, {original: null, id: null}],
    [{name: 'original', contract: asObjectContract}, column('id', true)]),
  asSuccess('mixed-qualified-whole', `${asHead} |> SELECT current.element AS original, position |> ORDER BY position`),
  asSuccess('mixed-renamed-whole', `${asHead} |> RENAME element AS next |> SELECT next AS original, position |> ORDER BY position`),
  asSuccess('qualified-original-after-rename', `${asHead} |> RENAME element AS next |> SELECT current.element AS original, position |> ORDER BY position`),
  asSuccess('repeated-object', `${asHead} |> AS next |> SELECT next.element AS original, position |> ORDER BY position`),
  ...['*', 'current.*'].map((star, index) => asSuccess('star-' + index,
    `${asHead} |> SELECT ${star} |> ORDER BY position`,
    [{id: 2, label: 'z', position: 0}, {id: null, label: null, position: 1}, {id: 1, label: 'a', position: 2}], structColumns)),
  asSuccess('immutable-star-after-set', `${asHead} |> SET element = 100 |> SELECT current.* |> ORDER BY position`,
    [{id: 2, label: 'z', position: 0}, {id: null, label: null, position: 1}, {id: 1, label: 'a', position: 2}], structColumns),
  asSuccess('set-whole-current-star', `${asHead} |> SET element = 100 |> SELECT * |> ORDER BY position`,
    [{element: 100, position: 0}, {element: 100, position: 1}, {element: 100, position: 2}],
    [column('element'), column('position')]),
  asSuccess('drop-whole', `${asHead} |> DROP element |> SELECT * |> ORDER BY position`,
    [{position: 0}, {position: 1}, {position: 2}], [column('position')]),
  asSuccess('qualified-star-after-join', `${asHead} |> JOIN (SELECT 2 AS key) k ON current.id = k.key MAX_OUTPUT_ROWS 3 `
    + '|> SELECT current.* |> ORDER BY position', [{id: 2, label: 'z', position: 0}], structColumns),
  asSuccess('typed-empty', `${asHead} |> SELECT current.element AS original, position |> ORDER BY position`,
    [], asWholeColumns, {parameters: {items: []}}),
  asSuccess('typed-null-array', `${asHead} |> SELECT current.element AS original, position |> ORDER BY position`,
    [], asWholeColumns, {parameters: {items: null}}),
  asSuccess('empty-objects', `${asHead} |> SELECT current.element AS original, position |> ORDER BY position`,
    [{original: {}, position: 0}, {original: null, position: 1}],
    [{name: 'original', contract: {type: 'object', nullable: true, fields: {}, additional_properties: false}}, column('position')],
    {parameterDeclarations: {items: {...structDeclarations.items, max_items: 2,
      items: {type: 'object', nullable: true, fields: {}}}}, parameters: {items: [{}, null]}}),
  receiverSuccess('as-whole-field-collision', 'FROM UNNEST(@items) element WITH OFFSET position |> AS current '
    + '|> SELECT element AS original, current.element.element AS field_value, position |> ORDER BY position', {format: 'aql-text'}),
);
unnestRefusals.push(
  refusal('as-single-rename-range', 'FROM UNNEST(@items) element |> AS current |> RENAME current AS next |> SELECT next',
    {format: 'aql-text', expectedCode: 'ClientProgramInvalidInput'}),
  refusal('as-implicit-member-edit', `${asHead} |> SET id = 100 |> SELECT position`,
    {format: 'aql-text', parameterDeclarations: structDeclarations, parameters: asParameters,
      expectedCode: 'ClientProgramInvalidInput'}),
  refusal('as-select-removed-range', `${asHead} |> SELECT id |> WHERE current.element IS NOT NULL`,
    {format: 'aql-text', parameterDeclarations: structDeclarations, parameters: asParameters,
      expectedCode: 'ClientProgramInvalidInput'}),
);
