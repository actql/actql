// Independent typed rows and a handwritten machine control. No compiler or
// provider output is used to construct these expectations.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const rows = [{id: 2, payload: {score: 10}}, {id: 1, payload: {score: 20}},
  {id: 3, payload: null}, {id: 4, payload: {score: null}}];
const declarations = {a: payload, b: payload, c: payload, d: payload};
const parameters = {a: {score: 10}, b: {score: 20}, c: null, d: {score: null}};
const columns = [{name: 'id', contract: number}];
const data = 'DATA objects = SELECT 2 AS id, @a AS payload '
  + 'UNION ALL SELECT 1 AS id, @b AS payload '
  + 'UNION ALL SELECT 3 AS id, @c AS payload '
  + 'UNION ALL SELECT 4 AS id, @d AS payload; ';
const mapping = 'DATA g = PROPERTY GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))); ';
const tail = (pattern, selection = 'a.id', output = 'id') =>
  `FROM GRAPH g |> MATCH WALK ${pattern} |> SELECT ${selection} AS ${output}`
  + ` |> ORDER BY ${output} |> RESULT matched`;
const selected = [{id: 1}];
const result = expected => ({matched: {rows: expected, columns}});
const sourceCase = (name, pattern, expected = selected, extra = {}) => ({
  name: 'graph-property-predicate-' + name, format: 'aql-text',
  text: data + mapping + tail(pattern), parameterDeclarations: declarations,
  parameters, results: result(expected), sourceReadCount: 0, ...extra,
});
const program = {version: 'actql/0.1', id: 'fixture.graph_property_predicate',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows}, as: 'objects'},
    {graph: {version: 'actql-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Person',
        properties: {mode: 'columns', columns: [{from: 'id', to: 'id'}, {from: 'payload', to: 'payload'}]}}]}],
      edges: []}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Person',
      where: {gt: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 10}]},
      fields: ['id']}, as: 'matched'},
    {from: 'matched', sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}};
export const graphPropertyPredicateSuccesses = [
  {name: 'graph-property-predicate-independent-json', format: 'json',
    text: JSON.stringify(program), results: result(selected), sourceReadCount: 0},
  sourceCase('qualified', '(a:Person WHERE a.payload.score > 10)'),
  sourceCase('unqualified', '(a:Person WHERE payload.score > 10)'),
  sourceCase('quoted', '(a:Person WHERE `A`.`PAYLOAD`.`score` > 10)'),
  sourceCase('anonymous', '(:Person WHERE payload.score > 10)', selected,
    {text: data + mapping + tail('(:Person WHERE payload.score > 10)', 'id')}),
  sourceCase('null-receiver-and-member',
    '(a:Person WHERE payload.score IS NULL)', [{id: 3}, {id: 4}]),
  sourceCase('ordinary-three-valued-or',
    '(a:Person WHERE payload.score IS NULL OR payload.score > 10)',
    [{id: 1}, {id: 3}, {id: 4}]),
  sourceCase('typed-empty', '(a:Person WHERE payload.score > 100)', []),
  sourceCase('parameter', '(a:Person WHERE payload.score > @min)', selected,
    {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}}),
];
export const graphPropertyPredicateRefusals = [
  ['foreign-receiver', 'other.payload.score > 0'],
  ['missing-receiver', 'missing.score > 0'],
  ['missing-member', 'payload.missing > 0'],
  ['scalar-receiver', 'id.score > 0'],
  ['selected-alias', 'chosen > 0'],
].map(([name, predicate]) => ({name: 'graph-property-predicate-invalid-' + name,
  format: 'aql-text', text: data + mapping + tail(`(a:Person WHERE ${predicate})`, 'a.id', 'chosen'),
  parameterDeclarations: declarations, parameters}));
