// Independent value-table expectations: CTEs retain the original scalar or
// nullable object, while their former receiver names stay inside the body.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const parameters = {items: [2, null, 2]};
const declarations = {items: {type: 'array', nullable: true, max_items: 3, items: nullableNumber}};
const columns = [{name: 'value', contract: nullableNumber}];
const rows = [{value: null}, {value: 2}, {value: 2}];
const results = {answer: {from: {stage: 'main', result: 'rows'}}};
export const cteValueTableControl = {version: 'actql/0.1', id: 'fixture.cte_value_table',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {element: nullableNumber}, rows: [{element: 2}, {element: null}, {element: 2}]}, as: 'elements'},
    {from: 'elements', sort: [{field: 'element', dir: 'asc', nulls: 'first'}]},
    {select: [{value: 'element'}], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['value']}}}], results};
export const cteValueTableJoinControl = {version: 'actql/0.1', id: 'fixture.cte_value_table_join',
  stages: [{id: 'main', inputs: {}, steps: [
    cteValueTableControl.stages[0].steps[0],
    {from: 'elements', join: {with: 'elements', kind: 'inner', on: [{left: 'element', right: 'element'}],
      max_output_rows: 10, select: {value: 'left.element'}}, as: 'joined'},
    {from: 'joined', sort: [{field: 'value', dir: 'asc', nulls: 'first'}], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['value']}}}], results};
const success = (name, text, extra = {}) => ({name: 'cte-value-table-' + name, format: 'sql', text,
  parameterDeclarations: declarations, parameters, expected: rows, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
const scalar = 'WITH a AS (FROM UNNEST(@items) old_l) SELECT l AS value FROM a AS l ORDER BY value NULLS FIRST';
const joined = 'WITH a AS (FROM UNNEST(@items) old_l) SELECT l AS value FROM a AS l '
  + 'JOIN a AS r ON ((l))=(r) MAX_OUTPUT_ROWS 10 ORDER BY value';
const object = {type: 'object', nullable: true, fields: {id: number, label: {type: 'string', nullable: true}}};
const objectCase = {parameterDeclarations: {items: {type: 'array', nullable: true, max_items: 3, items: object}},
  parameters: {items: [{id: 2, label: 'kept'}, null, {id: 2, label: null}]},
  columns: [{name: 'value', contract: {...object, additional_properties: false}}, {name: 'id', contract: nullableNumber}],
  expected: [{value: null, id: null}, {value: {id: 2, label: null}, id: 2}, {value: {id: 2, label: 'kept'}, id: 2}]};
export const cteValueTableObjectControl = {version: 'actql/0.1', id: 'fixture.cte_value_table_object',
  params: objectCase.parameterDeclarations, stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'seed'},
    {from: 'seed', derive: {items: {$param: 'items'}}},
    {unnest: {column: 'items', as: 'element'}},
    {derive: {id: {property: {value: {field: 'element'}, name: 'id'}},
      label: {property: {value: {field: 'element'}, name: 'label'}}}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'label', dir: 'asc', nulls: 'first'}]},
    {select: [{value: 'element'}, 'id'], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['value', 'id']}}}], results};
export const cteValueTableSuccesses = [
  success('json-control', JSON.stringify(cteValueTableControl), {format: 'json', parameterDeclarations: undefined, parameters: undefined}),
  success('scalar', scalar),
  success('quoted-pipe', 'WITH a AS (FROM UNNEST(@items) old_l) FROM a AS `L` |> SELECT `L` AS value |> ORDER BY value NULLS FIRST', {format: 'aql-text'}),
  success('empty', scalar, {parameters: {items: []}, expected: []}),
  success('null-array', scalar, {parameters: {items: null}, expected: []}),
  success('join-json-control', JSON.stringify(cteValueTableJoinControl), {format: 'json', parameterDeclarations: undefined,
    parameters: undefined, columns: [{name: 'value', contract: nullableNumber}], expected: [{value: 2}, {value: 2}, {value: 2}, {value: 2}]}),
  success('shared-join', joined, {columns: [{name: 'value', contract: nullableNumber}], expected: [{value: 2}, {value: 2}, {value: 2}, {value: 2}]}),
  success('object-json-control', JSON.stringify(cteValueTableObjectControl), {...objectCase, format: 'json', parameterDeclarations: undefined}),
  success('nullable-object', 'WITH a AS (FROM UNNEST(@items) old_l) SELECT l AS value,l.id AS id FROM a AS l ORDER BY id NULLS FIRST,value.label NULLS FIRST', objectCase),
];
export const cteValueTableRefusals = [
  {name: 'cte-value-table-former-receiver', format: 'sql', parameterDeclarations: declarations, parameters,
    text: 'WITH a AS (FROM UNNEST(@items) old_l) SELECT old_l FROM a AS l', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'cte-value-table-scalar-star', format: 'sql', parameterDeclarations: declarations, parameters,
    text: 'WITH a AS (FROM UNNEST(@items) old_l) SELECT l.* FROM a AS l', expectedCode: 'ClientProgramInvalidInput'},
];
