// Values, complete machine controls and multiplicities are authored from the
// Graph/traverse contracts. The frontend never supplies expected Programs.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const payload = {type: 'object', nullable: true,
  fields: {score: nullableNumber}};
const declarations = {a: payload, b: payload, c: payload};
const parameters = {a: {score: 10}, b: {score: 20}, c: null};
const data = 'WITH n AS (SELECT 1 AS id) , e AS ('
  + 'SELECT 10 AS edge_key, 1 AS src, 1 AS dst, 10 AS weight, @a AS payload '
  + 'UNION ALL SELECT 11 AS edge_key, 1 AS src, 1 AS dst, 20 AS weight, @b AS payload '
  + 'UNION ALL SELECT 12 AS edge_key, 1 AS src, 1 AS dst, CAST(NULL AS FLOAT64) AS weight, @c AS payload) ';
const edgeDefinition = 'e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N '
  + 'DESTINATION KEY (dst) REFERENCES N LABEL R PROPERTIES (weight, payload)';
const mapping = (edges = edgeDefinition) => ', g AS (GRAPH ('
  + 'NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) '
  + 'EDGE TABLES (' + edges + '))) ';
const query = (edge, mode = 'WALK') => 'FROM GRAPH g |> MATCH p = ' + mode
  + ' (:Node)' + edge + '(:Node) |> SELECT PATH_LENGTH(p) AS depth '
  + '|> ORDER BY depth |> RESULT paths';
const expected = depths => ({paths: {rows: depths.map(depth => ({depth})),
  columns: [{name: 'depth', contract: number}]}});
const source = (name, edge, depths, extra = {}) => ({
  name: 'graph-edge-predicate-' + name, format: 'aql-text',
  text: data + mapping() + query(edge), parameterDeclarations: declarations,
  parameters, results: expected(depths), sourceReadCount: 0, ...extra,
});
const weightPredicate = {gt: [{field: 'weight'}, {literal: 10}]};
const nullPredicate = {is_null: {field: 'weight'}};
const machine = bounded => ({version: 'actql/0.1', id: 'fixture.graph_edge_predicate',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: [{id: 1}]}, as: 'n'},
    {values: {schema: {edge_key: number, src: number, dst: number,
      weight: nullableNumber, payload}, rows: [
      {edge_key: 10, src: 1, dst: 1, weight: 10, payload: {score: 10}},
      {edge_key: 11, src: 1, dst: 1, weight: 20, payload: {score: 20}},
      {edge_key: 12, src: 1, dst: 1, weight: null, payload: null},
    ]}, as: 'e'},
    {graph: {version: 'actql-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'n', key: ['id'], labels: [{name: 'Node',
        properties: {mode: 'no_properties'}}]}],
      edges: [{name: 'E', from: 'e', key: ['edge_key'],
        source: {definition: 'N', key: ['src']}, target: {definition: 'N', key: ['dst']},
        labels: [{name: 'R', properties: {mode: 'columns', columns: [
          {from: 'weight', to: 'weight'}, {from: 'payload', to: 'payload'},
        ]}}]}]}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Node', where: {literal: true},
      bindings: {identity: 'identity'}, fields: ['identity']}, as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'identity'},
      path_mode: 'walk', emit: 'paths', ...(bounded ? {
        direction: 'out', min_hops: 0, max_hops: 2, edge_types: ['R'], edge_where: weightPredicate,
      } : {hops: [{direction: 'out', edge_types: ['R'], edge_where: weightPredicate},
        {direction: 'out', edge_types: ['R'], edge_where: nullPredicate}]})}, as: 'paths'},
    {from: 'paths', select: [{depth: 'hop_count'}], as: 'depths'},
    {from: 'depths', sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['depth']}}}],
  results: {paths: {from: {stage: 'main', result: 'rows'}}}});
// S has no properties and no rows. Actual row emptiness cannot make its
// statically missing weight eligible for an unfiltered traversal predicate.
const heterogeneousData = data + ', empty_edges AS (FROM e |> WHERE edge_key < 0) ';
const heterogeneousMapping = mapping(edgeDefinition + ', empty_edges AS F KEY (edge_key) '
  + 'SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL S NO PROPERTIES');
export const graphEdgePredicateSuccesses = [
  {name: 'graph-edge-predicate-independent-json-per-hop', format: 'json',
    text: JSON.stringify(machine(false)), results: expected([2]), sourceReadCount: 0},
  {name: 'graph-edge-predicate-independent-json-bounded', format: 'json',
    text: JSON.stringify(machine(true)), results: expected([0, 1, 2]), sourceReadCount: 0},
  source('fixed', '-[:R WHERE weight > 10]->', [1]),
  source('per-hop', '-[:R WHERE weight > 10]->()-[:R WHERE weight IS NULL]->', [2]),
  source('property-map', '-[:R {weight: 20}]->', [1]),
  source('quoted', '-[:`r` WHERE `WEIGHT` > 10]->', [1]),
  source('null-property', '-[:R WHERE weight IS NULL]->', [1]),
  source('nullable-receiver', '-[:R WHERE payload.score IS NULL]->', [1]),
  source('nested-property', '-[:R WHERE payload.score > 10]->', [1]),
  source('parameter', '-[:R WHERE weight > @minimum]->', [1],
    {parameterDeclarations: {...declarations, minimum: number}, parameters: {...parameters, minimum: 10}}),
  source('typed-empty', '-[:R WHERE weight > 100]->', []),
  source('static-label-candidates', '-[:R WHERE weight > 10]->', [1],
    {text: heterogeneousData + heterogeneousMapping + query('-[:R WHERE weight > 10]->')}),
  source('definition-full-property-scope', '-[:Other WHERE weight > 10]->', [1],
    {text: data + mapping(edgeDefinition + ' LABEL Other NO PROPERTIES')
      + query('-[:Other WHERE weight > 10]->')}),
  ...[['WALK', [0, 1, 2]], ['TRAIL', [0, 1]], ['ACYCLIC', [0]]].map(([mode, depths]) =>
    source('bounded-' + mode.toLowerCase(), '-[:R WHERE weight > 10]->{0,2}', depths,
      {text: data + mapping() + query('-[:R WHERE weight > 10]->{0,2}', mode)})),
];
export const graphEdgePredicateRefusals = [
  ...[['foreign-receiver', 'other.weight > 0'], ['missing-receiver', 'missing.score > 0'],
    ['missing-member', 'payload.missing > 0'], ['scalar-receiver', 'weight.score > 0'],
    ['output-alias', 'depth > 0'], ['type-mismatch', "weight = 'high'"],
  ].map(([name, predicate]) => ({name: 'graph-edge-predicate-invalid-' + name,
    format: 'aql-text', text: data + mapping() + query('-[:R WHERE ' + predicate + ']->'),
    parameterDeclarations: declarations, parameters})),
  {name: 'graph-edge-predicate-invalid-static-presence', format: 'aql-text',
    text: heterogeneousData + heterogeneousMapping + query('-[WHERE weight > 10]->'),
    parameterDeclarations: declarations, parameters},
  {name: 'graph-edge-predicate-invalid-named-binding', expectedCode: 'ClientProgramImplementationLimit', format: 'aql-text',
    text: data + mapping() + query('-[edge:R WHERE edge.weight > 10]->'),
    parameterDeclarations: declarations, parameters},
];
