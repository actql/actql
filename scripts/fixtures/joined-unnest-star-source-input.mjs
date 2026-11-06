// Independent JOIN -> correlated UNNEST controls, rows and complete contracts.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const nullableString = {type: 'string', nullable: true};
const items = {type: 'array', nullable: true, max_items: 3,
  items: {type: 'object', nullable: true, fields: {code: number, label: nullableString}}};
const parameterDeclarations = {parents: {type: 'array', max_items: 4,
  items: {type: 'object', fields: {id: number, items}}}};
const parameters = {parents: [{id: 2, items: [{code: 20, label: null}, null, {code: 20, label: null}]},
  {id: 1, items: [{code: 10, label: 'a'}]}, {id: 3, items: []}, {id: 4, items: null}]};
const columns = [{name: 'id', contract: number}, {name: 'code', contract: nullableNumber},
  {name: 'label', contract: nullableString}, {name: 'position', contract: number}];
const expected = [{id: 1, code: 10, label: 'a', position: 0},
  {id: 2, code: 20, label: null, position: 0}, {id: 2, code: null, label: null, position: 1},
  {id: 2, code: 20, label: null, position: 2}];
const parentSteps = [
  {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
  {from: 'seed', derive: {parents: {$param: 'parents'}}},
  {unnest: {column: 'parents', as: 'parent'}},
  {derive: {id: {property: {value: {field: 'parent'}, name: 'id'}},
    items: {property: {value: {field: 'parent'}, name: 'items'}}}},
  {select: ['id', 'items'], as: 'parents'},
];
const expansion = [
  {from: 'joined', derive: {array: {field: 'items'}}},
  {unnest: {column: 'array', as: 'element', with_index: 'position'}},
  {derive: {code: {property: {value: {field: 'element'}, name: 'code'}},
    label: {property: {value: {field: 'element'}, name: 'label'}}}},
  {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'position', dir: 'asc', nulls: 'first'}]},
  {select: ['id', 'code', 'label', 'position'], as: 'selected'},
];
const join = withInput => ({from: 'parents', join: {with: withInput, kind: 'inner',
  on: [{left: 'id', right: withInput === 'keys' ? 'key' : 'id'}], max_output_rows: 4,
  select: {id: 'left.id', items: 'left.items', key: `right.${withInput === 'keys' ? 'key' : 'id'}`}}, as: 'joined'});
const main = steps => ({id: 'main', inputs: {}, steps,
  results: {rows: {from: 'selected', fields: columns.map(column => column.name)}}});
const exports = {answer: {from: {stage: 'main', result: 'rows'}}};
export const joinedUnnestStarProgram = {version: 'actql/0.1', id: 'fixture.joined_unnest_star',
  params: parameterDeclarations, stages: [main([...parentSteps,
    {values: {schema: {key: number}, rows: [{key: 1}, {key: 2}]}, as: 'keys'},
    join('keys'), ...expansion])], results: exports};
export const joinedUnnestAcquiredStarProgram = {version: 'actql/0.1', id: 'fixture.joined_unnest_acquired_star',
  params: parameterDeclarations, stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {...main([...parentSteps, join('records'), ...expansion]),
      inputs: {records: {result: {stage: 'capture', result: 'source'}}}},
  ], results: exports};
const binding = 'WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items)';
const head = binding + ' ';
const keys = '(SELECT 1 AS key UNION ALL SELECT 2 AS key)';
const sql = head + `SELECT p.id, e.*, position FROM parents p JOIN ${keys} k `
  + 'ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(p.items) e WITH OFFSET position ORDER BY p.id, position';
const pipe = head + `FROM parents p |> JOIN ${keys} k ON p.id = k.key MAX_OUTPUT_ROWS 4 `
  + '|> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position';
const acquired = binding + ', expanded AS (FROM parents p |> JOIN records r ON p.id = r.id MAX_OUTPUT_ROWS 4 '
  + '|> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position '
  + '|> ORDER BY p.id, position) FROM expanded |> RESULT answer';
const success = (name, text, extra = {}) => ({name: 'joined-unnest-star-' + name, format: 'aql-text',
  text, parameterDeclarations, parameters, columns, expected,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const objectColumnDeclarations = {objects: {type: 'array', max_items: 1,
  items: {type: 'object', fields: {score: number,
    payload: {type: 'object', fields: {score: number}}}}}};
export const joinedStarValueReceiverProgram = {version: 'actql/0.1', id: 'fixture.range_value_contrast',
  params: objectColumnDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {objects: {$param: 'objects'}}},
    {unnest: {column: 'objects', as: 'object'}},
    {derive: {payload: {property: {value: {field: 'object'}, name: 'payload'}}}},
    {derive: {value: {property: {value: {field: 'payload'}, name: 'score'}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}}}], results: exports};
const objectColumn = {parameterDeclarations: objectColumnDeclarations,
  parameters: {objects: [{score: 90, payload: {score: 10}}]},
  columns: [{name: 'value', contract: number}], expected: [{value: 10}]};
export const joinedUnnestStarSuccesses = [
  success('json-control', JSON.stringify(joinedUnnestStarProgram), {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql), success('pipe', pipe),
  success('quoted-parenthesized', sql.replaceAll('p.', '`p`.').replace('parents p ', 'parents `p` ')
    .replace('UNNEST(`p`.items)', 'UNNEST((`p`).`ITEMS`)')),
  success('empty', pipe, {parameters: {parents: []}, expected: []}),
  success('original-range', pipe.replace('|> CROSS', '|> SET items = [9] |> CROSS')),
  success('current-column', pipe.replace('|> CROSS', '|> SET items = [9] |> CROSS')
    .replace('UNNEST(p.items)', 'UNNEST(items)').replace('SELECT p.id, e.*, position', 'SELECT *')
    .replace('ORDER BY p.id, position', 'ORDER BY id, position'), {
    columns: [{name: 'id', contract: number},
      {name: 'items', contract: {type: 'array', nullable: false, max_items: 1, items: number}},
      {name: 'key', contract: number}, {name: 'e', contract: number}, {name: 'position', contract: number}],
    expected: [{id: 1, items: [9], key: 1, e: 9, position: 0}, {id: 2, items: [9], key: 2, e: 9, position: 0}],
  }),
  success('acquired-json-control', JSON.stringify(joinedUnnestAcquiredStarProgram), {
    format: 'json', parameterDeclarations: undefined, sourceReadCount: 1, sourceReadSessionCount: 1,
    sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}],
  }),
  success('acquired-data', acquired, {resultName: 'answer', sourceReadCount: 1, sourceReadSessionCount: 1,
    sourceRows: [{id: 2, amount: null}, {id: 1, amount: 10}]}),
  success('value-receiver-json-control', JSON.stringify(joinedStarValueReceiverProgram), {
    ...objectColumn, format: 'json', parameterDeclarations: undefined,
  }),
  success('value-receiver-contrast', 'FROM UNNEST(@objects) o |> SELECT score, payload '
    + '|> AS payload |> SELECT (payload).score AS value', objectColumn),
];
export const joinedUnnestStarRefusals = [
  sql.replace('UNNEST(p.items)', 'UNNEST(p.id)'),
  pipe.replace('|> CROSS', '|> SELECT id, items |> CROSS'),
  sql.replace('MAX_OUTPUT_ROWS 4', 'MAX_OUTPUT_ROWS 0'),
].map((text, index) => ({name: 'joined-unnest-star-refusal-' + index, format: 'aql-text', text,
  parameterDeclarations, parameters, expectedCode: 'ClientProgramInvalidInput'}));
