// Authored from the selected membership law, not compiler/runtime output.
// NULL container and empty ARRAY mean an empty set; a NULL item means unknown
// unless another item matches. Duplicate input rows must remain duplicates.
const rows = [{id: 1, amount: null}, {id: 2, amount: 1},
  {id: 3, amount: 2}, {id: 3, amount: 2}];
const array = {type: 'array', nullable: true, max_items: 3,
  items: {type: 'number', nullable: true}};
const declarations = {xs: array};
const idColumn = {name: 'id', contract: {type: 'number', nullable: false}};
const flags = ['included', 'excluded'].map(name => ({name,
  contract: {type: 'boolean', nullable: true}}));
const columns = [idColumn, ...flags];
const matching = [{id: 1, included: null, excluded: null},
  {id: 2, included: null, excluded: null},
  {id: 3, included: true, excluded: false},
  {id: 3, included: true, excluded: false}];
const empty = [{id: 1, included: false, excluded: true},
  {id: 2, included: false, excluded: true},
  {id: 3, included: false, excluded: true},
  {id: 3, included: false, excluded: true}];
const unknown = [{id: 1, included: null, excluded: null},
  {id: 2, included: null, excluded: null},
  {id: 3, included: null, excluded: null},
  {id: 3, included: null, excluded: null}];
const projection = 'SELECT id, amount IN UNNEST((@xs)) AS included, '
  + 'amount NOT IN UNNEST(@xs) AS excluded FROM records ORDER BY id';
// Independent two-stage machine input retains the original Source and both
// array-parameter operands. No source lowering is patched by the harness.
const control = {version: 'actql/0.1', id: 'fixture.in_unnest', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {
      included: {in: [{field: 'amount'}, {$param: 'xs'}]},
      excluded: {not_in: [{field: 'amount'}, {$param: 'xs'}]}}},
    {select: ['id', 'included', 'excluded']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'included', 'excluded']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, extra = {}) => ({
  name: 'in-unnest-' + name, format: 'sql', text, expected, columns,
  sourceRows: rows, sourceReadSessionCount: 1,
  parameterDeclarations: declarations, parameters: {xs: [2, null]}, ...extra,
});
export const inUnnestSuccesses = [
  success('json-control', JSON.stringify(control), matching,
    {format: 'json', parameterDeclarations: undefined}),
  success('sql-projection', projection, matching),
  success('pipe-projection', 'FROM records |> SELECT id, '
    + 'amount IN UNNEST(@xs) AS included, amount NOT IN UNNEST((@xs)) AS excluded '
    + '|> ORDER BY id', matching, {format: 'aql-text'}),
  success('filter-duplicates', 'SELECT id FROM records '
    + 'WHERE amount IN UNNEST(@xs) ORDER BY id', [{id: 3}, {id: 3}],
    {columns: [idColumn]}),
  success('empty-array', projection, empty, {parameters: {xs: []}}),
  success('null-array', projection, empty, {parameters: {xs: null}}),
  success('null-item', projection, unknown, {parameters: {xs: [null]}}),
  success('non-null-items', projection, [
    {id: 1, included: null, excluded: null},
    {id: 2, included: false, excluded: true},
    {id: 3, included: true, excluded: false},
    {id: 3, included: true, excluded: false},
  ], {parameters: {xs: [2]}}),
  success('empty-input', projection, [], {sourceRows: []}),
  success('proven-empty-null-left', 'SELECT CAST(NULL AS FLOAT64) IN UNNEST(@xs) AS included, '
    + 'CAST(NULL AS FLOAT64) NOT IN UNNEST(@xs) AS excluded',
    [{included: false, excluded: true}], {
      parameterDeclarations: {xs: {...array, max_items: 0}}, parameters: {xs: []},
      sourceReadCount: 0, sourceReadSessionCount: 0,
      columns: flags.map(column => ({...column, contract: {type: 'boolean', nullable: false}})),
    }),
];
export const inUnnestRefusals = [
  {name: 'undeclared', text: projection, parameters: {xs: [2]}},
  {name: 'missing-value', text: projection, parameterDeclarations: declarations},
  {name: 'wrong-value', text: projection, parameterDeclarations: declarations,
    parameters: {xs: ['secret-value']}},
  {name: 'bound-exceeded', text: projection, parameterDeclarations: declarations,
    parameters: {xs: [1, 2, 3, 4]}},
  {name: 'scalar-rhs', text: projection,
    parameterDeclarations: {xs: {type: 'number'}}, parameters: {xs: 2}},
  {name: 'wrong-item-domain', text: projection,
    parameterDeclarations: {xs: {...array, items: {type: 'boolean'}}}, parameters: {xs: [true]}},
  {name: 'multiple-arguments', text: 'SELECT 1 IN UNNEST(@xs, @xs) AS included',
    parameterDeclarations: declarations, parameters: {xs: [1]}},
  {name: 'general-array-expression-gap', text: 'SELECT 1 IN UNNEST(IF(TRUE, @xs, @xs)) AS included',
    parameterDeclarations: declarations, parameters: {xs: [1]}},
].map(item => ({...item, name: 'in-unnest-' + item.name, format: 'sql'}));
export const inUnnestExecutionFailures = [{name: 'in-unnest-demanded-left-on-empty-set',
  format: 'sql', text: 'SELECT (1 / 0) IN UNNEST(@xs) AS included',
  parameterDeclarations: {xs: {...array, max_items: 0}}, parameters: {xs: []},
  resultNames: ['answer'], sourceReadSessionCount: 0}];
