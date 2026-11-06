// Independent expansion -> JOIN controls. NULL/duplicate elements remain rows;
// ordinary JOIN owners decide matches, null extension, bounds and key evidence.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const nullableString = {type: 'string', nullable: true};
const declarations = {items: {type: 'array', nullable: true, max_items: 3, items: nullableNumber}};
const parameters = {items: [2, null, 2]};
const scalarColumns = [{name: 'element', contract: nullableNumber},
  {name: 'position', contract: number}, {name: 'key', contract: number}];
const scalarExpected = [{element: 2, position: 0, key: 2}, {element: 2, position: 2, key: 2}];
const results = {answer: {from: {stage: 'main', result: 'rows'}}};
const scalarSteps = [
  {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
  {from: 'seed', derive: {array: {$param: 'items'}}},
  {unnest: {column: 'array', as: 'element', with_index: 'position'}, as: 'expanded'},
  {values: {schema: {key: number}, rows: [{key: 2}]}, as: 'keys'},
  {from: 'expanded', join: {with: 'keys', kind: 'inner',
    on: [{left: 'element', right: 'key'}], max_output_rows: 10,
    select: {element: 'left.element', position: 'left.position', key: 'right.key'}}, as: 'joined'},
  {from: 'joined', sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
  {select: ['element', 'position', 'key'], as: 'selected'},
];
export const unnestJoinProgram = {version: 'actql/0.1', id: 'fixture.unnest_join', params: declarations,
  stages: [{id: 'main', inputs: {}, steps: scalarSteps,
    results: {rows: {from: 'selected', fields: ['element', 'position', 'key']}}}], results};
// FULL consumes genuine identity premises from both inputs. OFFSET is checked
// explicitly; assigning a column name alone never invents uniqueness evidence.
const fullColumns = [{name: 'element', contract: nullableNumber},
  {name: 'position', contract: nullableNumber}, {name: 'key', contract: nullableNumber}];
const fullExpected = [{element: 2, position: 0, key: 2}, {element: null, position: 1, key: null},
  {element: 2, position: 2, key: 2}, {element: null, position: null, key: 3}];
export const unnestFullJoinProgram = {version: 'actql/0.1', id: 'fixture.unnest_full_join', params: declarations,
  stages: [{id: 'main', inputs: {}, steps: [scalarSteps[0], scalarSteps[1], scalarSteps[2],
    {from: 'expanded', assert_rows: {unique_by: ['position']}, as: 'expanded_keyed'},
    {values: {schema: {key: number}, rows: [{key: 2}, {key: 3}]}, as: 'keys'},
    {from: 'keys', assert_rows: {unique_by: ['key']}, as: 'keys_keyed'},
    {from: 'expanded_keyed', join: {...scalarSteps[4].join, with: 'keys_keyed', kind: 'full'}, as: 'joined'},
    {from: 'joined', sort: [{field: 'position', dir: 'asc', nulls: 'last'},
      {field: 'key', dir: 'asc', nulls: 'first'}]}, scalarSteps[6],
  ], results: {rows: {from: 'selected', fields: ['element', 'position', 'key']}}}], results};
const fullText = 'WITH keys AS (FROM (SELECT 2 AS key UNION ALL SELECT 3 AS key) keys_input '
  + '|> ASSERT UNIQUE BY (key)) FROM UNNEST(@items) element WITH OFFSET position '
  + '|> ASSERT UNIQUE BY (position) |> FULL JOIN keys k ON element = k.key MAX_OUTPUT_ROWS 10 '
  + '|> SELECT element, position, k.key |> ORDER BY position NULLS LAST, k.key';
const sql = 'SELECT element, position, k.key FROM UNNEST(@items) element WITH OFFSET position '
  + 'JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 ORDER BY position';
const pipe = 'FROM UNNEST(@items) element WITH OFFSET position '
  + '|> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 '
  + '|> SELECT element, position, k.key |> ORDER BY position';
const success = (name, text, extra = {}) => ({name: 'unnest-join-' + name, text, format: 'aql-text',
  parameterDeclarations: declarations, parameters, columns: scalarColumns, expected: scalarExpected,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const object = {type: 'object', nullable: true, fields: {code: number, label: nullableString}};
const objectDeclarations = {objects: {type: 'array', max_items: 4, items: object}};
const objectParameters = {objects: [{code: 2, label: 'b'}, null, {code: 2, label: 'b'}, {code: 1, label: null}]};
const objectColumns = [{name: 'code', contract: nullableNumber}, {name: 'label', contract: nullableString},
  {name: 'position', contract: number}, {name: 'key', contract: number}];
const objectExpected = [{code: 2, label: 'b', position: 0, key: 2}, {code: 2, label: 'b', position: 2, key: 2}];
const objectCase = {parameterDeclarations: objectDeclarations, parameters: objectParameters,
  columns: objectColumns, expected: objectExpected};
const objectSql = 'SELECT e.*, position, k.key FROM UNNEST(@objects) e WITH OFFSET position '
  + 'JOIN (SELECT 2 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 ORDER BY position';
const objectPipe = 'FROM UNNEST(@objects) e WITH OFFSET position '
  + '|> JOIN (SELECT 2 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 '
  + '|> SELECT e.*, position, k.key |> ORDER BY position';
export const unnestObjectJoinProgram = {version: 'actql/0.1', id: 'fixture.unnest_object_join',
  params: objectDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    scalarSteps[0], {from: 'seed', derive: {array: {$param: 'objects'}}},
    {unnest: {column: 'array', as: 'object', with_index: 'position'}},
    {derive: {code: {property: {value: {field: 'object'}, name: 'code'}},
      label: {property: {value: {field: 'object'}, name: 'label'}}}, as: 'expanded'},
    scalarSteps[3], {from: 'expanded', join: {with: 'keys', kind: 'inner',
      on: [{left: 'code', right: 'key'}], max_output_rows: 10,
      select: {code: 'left.code', label: 'left.label', position: 'left.position', key: 'right.key'}}, as: 'joined'},
    scalarSteps[5], {select: ['code', 'label', 'position', 'key'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['code', 'label', 'position', 'key']}}}], results};
export const unnestJoinSuccesses = [
  success('json-control', JSON.stringify(unnestJoinProgram), {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql, {format: 'sql'}), success('pipe', pipe),
  success('quoted', sql.replaceAll('element', '`element`').replaceAll('k.', '`k`.').replace(') k ', ') `k` ')),
  success('empty', sql, {parameters: {items: []}, expected: []}),
  success('null-array', sql, {parameters: {items: null}, expected: []}),
  success('left', sql.replace('JOIN (', 'LEFT JOIN ('), {
    columns: [scalarColumns[0], scalarColumns[1], {name: 'key', contract: nullableNumber}],
    expected: [{element: 2, position: 0, key: 2}, {element: null, position: 1, key: null},
      {element: 2, position: 2, key: 2}],
  }),
  success('right', sql.replace('JOIN (SELECT 2 AS key)', 'RIGHT JOIN (SELECT 2 AS key UNION ALL SELECT 3 AS key)')
    .replace('ORDER BY position', 'ORDER BY position NULLS LAST, k.key'), {
    columns: [scalarColumns[0], {name: 'position', contract: nullableNumber}, scalarColumns[2]],
    expected: [...scalarExpected, {element: null, position: null, key: 3}],
  }),
  success('full-json-control', JSON.stringify(unnestFullJoinProgram), {format: 'json',
    parameterDeclarations: undefined, columns: fullColumns, expected: fullExpected}),
  success('full', fullText, {columns: fullColumns, expected: fullExpected}),
  success('predicate', pipe.replace('|> JOIN', '|> WHERE element = element |> LEFT JOIN'), {
    columns: [scalarColumns[0], scalarColumns[1], {name: 'key', contract: nullableNumber}],
  }),
  success('limit-before-join', pipe.replace('|> JOIN', '|> ORDER BY position |> LIMIT 2 |> JOIN'), {
    expected: [scalarExpected[0]],
  }),
  success('object-json-control', JSON.stringify(unnestObjectJoinProgram), {
    ...objectCase, format: 'json', parameterDeclarations: undefined,
  }),
  success('object-sql', objectSql, {...objectCase, format: 'sql'}),
  success('object-pipe', objectPipe, objectCase),
  success('data', 'WITH joined AS (' + objectPipe + ') FROM joined |> RESULT answer', {...objectCase, resultName: 'answer'}),
  success('whole-object', objectPipe.replace('SELECT e.*,', 'SELECT e AS original, e.*,'), {
    ...objectCase, columns: [{name: 'original',
      contract: {...object, additional_properties: false}}, ...objectColumns],
    expected: objectExpected.map(row => ({original: {code: 2, label: 'b'}, ...row})),
  }),
  success('immutable-range', objectPipe.replace('|> JOIN', '|> SELECT code, label, position |> AS e |> SET code = 99 |> JOIN')
    .replace('SELECT e.*,', 'SELECT code AS current, e.code AS original, e.label,'), {
    ...objectCase, columns: [{name: 'current', contract: number}, {name: 'original', contract: nullableNumber},
      objectColumns[1], objectColumns[2], objectColumns[3]],
    expected: [{current: 99, original: 2, label: 'b', position: 0, key: 2},
      {current: 99, original: 2, label: 'b', position: 2, key: 2}],
  }),
  success('acquired', 'FROM UNNEST(@objects) e WITH OFFSET position '
    + '|> JOIN records r ON e.code = r.id MAX_OUTPUT_ROWS 10 '
    + '|> SELECT e.code, e.label, position, r.amount |> ORDER BY position', {
    ...objectCase, columns: [objectColumns[0], objectColumns[1], objectColumns[2],
      {name: 'amount', contract: nullableNumber}],
    expected: [{code: 2, label: 'b', position: 0, amount: 20}, {code: 2, label: 'b', position: 2, amount: 20},
      {code: 1, label: null, position: 3, amount: 10}],
    sourceRows: [{id: 1, amount: 10}, {id: 2, amount: 20}], sourceReadCount: 1, sourceReadSessionCount: 1,
  }),
];
export const unnestJoinRefusals = [
  objectPipe.replace('|> JOIN', '|> SELECT code |> JOIN'),
  objectPipe.replace('|> JOIN', '|> AS fresh |> JOIN'),
  objectSql.replace('MAX_OUTPUT_ROWS 10', 'MAX_OUTPUT_ROWS 0'),
  objectSql.replace('e.code = k.key', 'e.missing = k.key'),
  objectSql.replace('UNNEST(@objects)', 'UNNEST(1)'),
].map((text, index) => ({name: 'unnest-join-refusal-' + index, format: 'aql-text', text,
  parameterDeclarations: objectDeclarations, parameters: objectParameters,
  expectedCode: 'ClientProgramInvalidInput'}));
