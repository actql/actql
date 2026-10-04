// Authored rows, type contracts and machine Program: no compiler/provider
// output is used to derive expectations.
const number = {type: 'number', nullable: false};
const score = {...number, nullable: true};
const payload = {type: 'object', nullable: true, fields: {score}};
const rows = [{id: 2, payload: {score: 10}}, {id: 1, payload: {score: 20}},
  {id: 3, payload: null}, {id: 4, payload: {score: null}}];
const declarations = {a: payload, b: payload, c: payload, d: payload};
const parameters = {a: {score: 10}, b: {score: 20}, c: null, d: {score: null}};
const columns = [{name: 'id', contract: number}, {name: 'score', contract: score}];
const expected = [{id: 1, score: 20}, {id: 2, score: 10},
  {id: 3, score: null}, {id: 4, score: null}];
const data = 'DATA objects = SELECT 2 AS id, @a AS payload '
  + 'UNION ALL SELECT 1 AS id, @b AS payload '
  + 'UNION ALL SELECT 3 AS id, @c AS payload '
  + 'UNION ALL SELECT 4 AS id, @d AS payload; ';
const graph = 'DATA g = PROPERTY GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))); ';
const head = data + graph + 'FROM GRAPH g |> MATCH WALK (a:Person) |> ';
const result = values => ({matched: {rows: values, columns}});
const sourceCase = (name, tail, values = expected, extra = {}) => ({
  name: 'graph-projection-property-' + name, format: 'aql-text',
  text: head + tail + ' |> ORDER BY id |> RESULT matched',
  parameterDeclarations: declarations, parameters,
  results: result(values), sourceReadCount: 0, ...extra,
});
const program = {version: 'actql/0.1', id: 'fixture.graph_projection_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows}, as: 'objects'},
    {property_graph: {version: 'actql-property-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Person',
        properties: {mode: 'columns', columns: [{from: 'id', to: 'id'}, {from: 'payload', to: 'payload'}]}}]}],
      edges: []}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Person',
      where: {literal: true}, fields: ['id', 'payload']}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {name: 'score', value: {field: 'payload'}}}}},
    {select: ['id', 'score']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}};
export const graphProjectionPropertySuccesses = [
  {name: 'graph-projection-property-independent-json', format: 'json',
    text: JSON.stringify(program), results: result(expected), sourceReadCount: 0},
  sourceCase('qualified', 'SELECT a.id AS id, a.payload.score AS score'),
  sourceCase('local', 'SELECT id, payload.score AS score'),
  sourceCase('quoted', 'SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`score` AS score'),
  sourceCase('identity-macro-and-parameter',
    'WHERE NODE_ID(a) IS NOT NULL AND a.payload.score > @min '
      + '|> SELECT a.id AS id, a.payload.score AS score', [{id: 1, score: 20}],
    {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}}),
  sourceCase('null-receiver-and-member',
    'WHERE a.payload.score IS NULL |> SELECT a.id AS id, a.payload.score AS score',
    [{id: 3, score: null}, {id: 4, score: null}]),
  sourceCase('typed-empty',
    'WHERE a.payload.score > 100 |> SELECT a.id AS id, a.payload.score AS score', []),
  sourceCase('projected-object-current-scope',
    'SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.score AS score'),
];
export const graphProjectionPropertyRefusals = [
  ['foreign-receiver', 'SELECT other.payload.score AS score'],
  ['missing-member', 'SELECT a.payload.missing AS score'],
  ['scalar-receiver', 'SELECT a.id.score AS score'],
  ['removed-graph-variable', 'SELECT a.id AS id |> WHERE a.payload.score > 0'],
  ['same-select-alias', 'SELECT a.payload AS kept, kept.score AS score'],
].map(([name, tail]) => ({name: 'graph-projection-property-invalid-' + name,
  format: 'aql-text', text: head + tail, parameterDeclarations: declarations, parameters}));
