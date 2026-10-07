// Independently authored parameter/property/UNNEST controls. NULL containers
// yield no rows; NULL elements and duplicates retain their original offsets.
const item = {type: 'object', nullable: true, fields: {
  id: {type: 'number', nullable: false}, label: {type: 'string', nullable: true},
}};
const declarations = {payload: {type: 'object', nullable: true, fields: {
  nested: {type: 'object', nullable: true, fields: {
    items: {type: 'array', nullable: true, max_items: 3, items: item},
  }},
}}};
const parameters = {payload: {nested: {items: [{id: 2, label: 'kept'}, null, {id: 2, label: null}]}}};
const columns = [{name: 'id', contract: {type: 'number', nullable: true}},
  {name: 'label', contract: {type: 'string', nullable: true}},
  {name: 'position', contract: {type: 'number', nullable: false}}];
const expected = [{id: 2, label: 'kept', position: 0},
  {id: null, label: null, position: 1}, {id: 2, label: null, position: 2}];
export const unnestParameterPathProgram = {version: 'actql/0.1', id: 'fixture.unnest.parameter_path',
  params: declarations, stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {array: {property: {value: {property: {
      value: {$param: 'payload'}, name: 'nested'}}, name: 'items'}}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}},
    {derive: {id: {property: {value: {field: 'element'}, name: 'id'}},
      label: {property: {value: {field: 'element'}, name: 'label'}}}},
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'label', 'position'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'label', 'position']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT element.*, position FROM UNNEST(@payload.nested.items) element WITH OFFSET position ORDER BY position';
const success = (name, text = sql, extra = {}) => ({name: 'unnest-parameter-path-' + name,
  format: 'sql', text, parameterDeclarations: declarations, parameters, columns, expected,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const unnestParameterPathSuccesses = [
  success('json-control', JSON.stringify(unnestParameterPathProgram), {format: 'json', parameterDeclarations: undefined}),
  success('sql'),
  success('pipe', 'FROM UNNEST(@payload.nested.items) element WITH OFFSET position |> SELECT element.*, position |> ORDER BY position', {format: 'aql-text'}),
  success('quoted-parentheses', 'SELECT * FROM UNNEST(((@payload).`nested`).`items`) element WITH OFFSET position ORDER BY position'),
  success('null-parent', sql, {parameters: {payload: null}, expected: []}),
  success('null-container', sql, {parameters: {payload: {nested: null}}, expected: []}),
  success('null-array', sql, {parameters: {payload: {nested: {items: null}}}, expected: []}),
  success('empty-array', sql, {parameters: {payload: {nested: {items: []}}}, expected: []}),
];
const refusal = (name, text = sql, extra = {}) => ({name: 'unnest-parameter-path-refusal-' + name,
  format: 'sql', text, parameterDeclarations: declarations, parameters, ...extra});
export const unnestParameterPathRefusals = [
  refusal('undeclared', sql, {parameterDeclarations: undefined}),
  refusal('unknown-property', sql.replace('.items)', '.missing)')),
  refusal('non-array', sql.replace('.nested.items)', '.nested)')),
  refusal('bound', sql, {parameters: {payload: {nested: {items: [null, null, null, null]}}}}),
  refusal('field-type', sql, {parameters: {payload: {nested: {items: [{id: 'wrong', label: null}]}}}}),
];
