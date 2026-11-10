// Independent Graph inputs and complete machine controls. The expected path
// multiplicities are enumerated by keyed edge instances, never frontend output.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const nodes = [{id: 1, payload: {score: 10}}, {id: 2, payload: {score: 20}},
  {id: 3, payload: {score: 30}}, {id: 4, payload: null}, {id: 5, payload: {score: null}}];
const edges = [{key: 10, src: 1, dst: 2}, {key: 11, src: 1, dst: 2},
  {key: 12, src: 3, dst: 1}, {key: 13, src: 1, dst: 1},
  {key: 14, src: 1, dst: 4}, {key: 15, src: 1, dst: 5}];
const declarations = {
  nodes: {type: 'array', nullable: false, max_items: 5,
    items: {type: 'object', nullable: false, fields: {id: number, payload}}},
  edges: {type: 'array', nullable: false, max_items: 6,
    items: {type: 'object', nullable: false, fields: {key: number, src: number, dst: number}}},
};
const parameters = {nodes, edges};
const data = 'WITH objects AS (SELECT item.id AS id, item.payload AS payload '
  + 'FROM UNNEST(@nodes) AS item) , links AS (SELECT link.key AS key, '
  + 'link.src AS src, link.dst AS dst FROM UNNEST(@edges) AS link) ';
const mapping = ', g AS (GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Node PROPERTIES ALL COLUMNS) EDGE TABLES '
  + '(links AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) '
  + 'REFERENCES N LABEL R PROPERTIES (key)))) ';
const tail = (pattern, mode = 'WALK') => `FROM GRAPH g |> MATCH p = ${mode} ${pattern}`
  + ' |> SELECT PATH_LENGTH(p) AS depth |> ORDER BY depth |> RESULT matched';
const columns = [{name: 'depth', contract: number}];
const result = depths => ({matched: {rows: depths.map(depth => ({depth})), columns}});
const repeated = (depth, count) => Array(count).fill(depth);
const sourceCase = (name, pattern, depths, extra = {}) => ({
  name: 'graph-any-direction-' + name, format: 'aql-text', text: data + mapping + tail(pattern),
  parameterDeclarations: declarations, parameters, results: result(depths), sourceReadCount: 0, ...extra,
});
const machine = bounded => ({version: 'actql/0.1', id: 'fixture.graph_any_direction', stages: [{
  id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: nodes}, as: 'objects'},
    {values: {schema: {key: number, src: number, dst: number}, rows: edges}, as: 'links'},
    {graph: {version: 'actql-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Node', properties: {mode: 'all_columns'}}]}],
      edges: [{name: 'E', from: 'links', key: ['key'], source: {definition: 'N', key: ['src']},
        target: {definition: 'N', key: ['dst']}, labels: [{name: 'R', properties: {mode: 'columns',
          columns: [{from: 'key', to: 'key'}]}}]}]}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Node',
      where: {eq: [{field: 'id'}, {literal: 1}]}, bindings: {identity: 'identity'}, fields: ['identity']}, as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'identity'}, path_mode: bounded ? 'trail' : 'walk',
      emit: 'paths', ...(bounded ? {direction: 'both', min_hops: 0, max_hops: 2, edge_types: ['R']}
        : {hops: [{direction: 'both', edge_types: ['R']}]})}, as: 'paths'},
    {from: 'paths', select: [{depth: 'hop_count'}], as: 'depths'},
    {from: 'depths', sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['depth']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}});
const heterogeneous = 'WITH n AS (SELECT 1 AS id, 20 AS score) , e AS (SELECT 10 AS key, 1 AS src, 1 AS dst) '
  + ', g AS (GRAPH (NODE TABLES (n AS S KEY (id) LABEL Start NO PROPERTIES, '
  + 'n AS T KEY (id) LABEL Target PROPERTIES (score)) EDGE TABLES '
  + '(e AS E KEY (key) SOURCE KEY (src) REFERENCES S DESTINATION KEY (dst) REFERENCES T LABEL R NO PROPERTIES))) ';
// Two keyed self-loops distinguish every path mode with a small complete
// result; self-loops must not be counted twice for direction both.
const boundedParameters = {nodes: [nodes[0]], edges: [
  {key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1},
]};
// The larger input yields twenty paths and 124 identity occurrences before
// projection. Each occurrence remains logically charged. The installed
// storage's 10,000-byte ceiling is not a cumulative traversal-output policy,
// and max_value_bytes applies to each top-level value, not the whole result.
export const graphAnyDirectionCompleteWalk = sourceCase('bounded-walk-complete-identities',
  '(a:Node WHERE id = 1)-[:R]-{0,2}(b:Node)', [0, ...repeated(1, 6), ...repeated(2, 13)]);
export const graphAnyDirectionExecutionFailures = [];
export const graphAnyDirectionSuccesses = [
  {name: 'graph-any-direction-json-fixed', format: 'json', text: JSON.stringify(machine(false)),
    results: result(repeated(1, 6)), sourceReadCount: 0},
  {name: 'graph-any-direction-json-bounded-trail', format: 'json', text: JSON.stringify(machine(true)),
    results: result([0, ...repeated(1, 6), ...repeated(2, 7)]), sourceReadCount: 0},
  sourceCase('outgoing-control', '(a:Node WHERE id = 1)-[:R]->(b:Node)', repeated(1, 5)),
  sourceCase('incoming-control', '(a:Node WHERE id = 1)<-[:R]-(b:Node)', repeated(1, 2)),
  sourceCase('fixed', '(a:Node WHERE id = 1)-[:R]-(b:Node)', repeated(1, 6)),
  sourceCase('edge-node-predicates', '(a:Node WHERE id = 1)-[:R WHERE key > 10]-(b:Node WHERE b.payload.score > 10)', [1, 1]),
  sourceCase('quoted', '(a:Node WHERE id = 1)-[:`r`]-(`b`:Node WHERE `B`.`PAYLOAD`.`score` > 10)', [1, 1, 1]),
  sourceCase('null-object-and-member', '(a:Node WHERE id = 1)-[:R]-(b:Node WHERE payload.score IS NULL)', [1, 1]),
  sourceCase('typed-empty', '(a:Node WHERE id = 1)-[:R]-(b:Node WHERE payload.score > 100)', []),
  ...[['WALK', 2, 4], ['TRAIL', 2, 2], ['ACYCLIC', 0, 0]].map(([mode, one, two]) =>
    sourceCase('bounded-' + mode.toLowerCase(), '(a:Node WHERE id = 1)-[:R]-{0,2}(b:Node)',
      [0, ...repeated(1, one), ...repeated(2, two)],
      {text: data + mapping + tail('(a:Node WHERE id = 1)-[:R]-{0,2}(b:Node)', mode),
        parameters: boundedParameters})),
  graphAnyDirectionCompleteWalk,
];
export const graphAnyDirectionRefusals = [
  ...['<-[]->', '-[]-*', '-[]-{1,}', '-[e:R]-{0,2}'].map((edge, index) => ({
    name: 'graph-any-direction-invalid-shape-' + index, format: 'aql-text',
    text: data + mapping + tail('(a:Node WHERE id = 1)' + edge + '(b:Node)'),
    parameterDeclarations: declarations, parameters,
  })),
  {name: 'graph-any-direction-conditional-reached-property', format: 'aql-text',
    text: heterogeneous + tail('(:Start)-[:R]-(b WHERE b.score > 10)')},
  {name: 'graph-any-direction-unfiltered-reached-label', expectedCode: 'ClientProgramImplementationLimit', format: 'aql-text',
    text: heterogeneous + tail('(:Start)-[:R]-(:Target)')},
  {name: 'graph-any-direction-foreign-receiver', format: 'aql-text',
    text: data + mapping + tail('(a:Node WHERE id = 1)-[:R]-(b WHERE a.payload.score > 10)'),
    parameterDeclarations: declarations, parameters},
];
