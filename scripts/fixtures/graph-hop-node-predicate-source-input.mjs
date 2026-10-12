// Handwritten per-hop controls and result oracles. Neither compiler output nor
// sampled runtime rows supply the expected expressions, schemas or results.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const nodes = [{id: 1, payload: {score: 0}}, {id: 2, payload: {score: 10}},
  {id: 3, payload: {score: 20}}, {id: 4, payload: null}, {id: 5, payload: {score: null}}];
const edges = [{key: 10, src: 1, dst: 2}, {key: 11, src: 1, dst: 3},
  {key: 12, src: 1, dst: 4}, {key: 13, src: 3, dst: 2}, {key: 14, src: 1, dst: 5}];
const declarations = {
  nodes: {type: 'array', nullable: false, max_items: 5,
    items: {type: 'object', nullable: false, fields: {id: number, payload}}},
  edges: {type: 'array', nullable: false, max_items: 5,
    items: {type: 'object', nullable: false, fields: {key: number, src: number, dst: number}}},
};
const parameters = {nodes, edges};
// Existing typed UNNEST constructs the same rows without unrelated UNION
// branches exhausting the standard 32-task limit. No ceiling is raised.
const data = 'WITH objects AS (SELECT item.id AS id, item.payload AS payload '
  + 'FROM UNNEST(@nodes) AS item) , links AS (SELECT link.key AS key, '
  + 'link.src AS src, link.dst AS dst FROM UNNEST(@edges) AS link) ';
const mapping = ', g AS (GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Node PROPERTIES ALL COLUMNS) EDGE TABLES '
  + '(links AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) '
  + 'REFERENCES N LABEL R NO PROPERTIES))) ';
const tail = pattern => `FROM GRAPH g |> MATCH p = WALK ${pattern}`
  + ' |> SELECT PATH_LENGTH(p) AS depth |> ORDER BY depth |> RESULT matched';
const columns = [{name: 'depth', contract: number}];
const result = rows => ({matched: {rows, columns}});
const one = [{depth: 1}];
const sourceCase = (name, pattern, rows = one, extra = {}) => ({
  name: 'graph-hop-node-' + name, format: 'aql-text', text: data + mapping + tail(pattern),
  parameterDeclarations: declarations, parameters, results: result(rows), sourceReadCount: 0, ...extra,
});
const property = {property: {name: 'score', value: {field: 'payload'}}};
const first = {direction: 'out', edge_types: ['R'], node_where: {gt: [property, {literal: 10}]}};
const machineMapping = {version: 'actql-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Node', properties: {mode: 'all_columns'}}]}],
  edges: [{name: 'E', from: 'links', key: ['key'], source: {definition: 'N', key: ['src']},
    target: {definition: 'N', key: ['dst']}, labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]};
const program = hops => ({version: 'actql/0.1', id: 'fixture.graph_hop_node', stages: [{
  id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: nodes}, as: 'objects'},
    {values: {schema: {key: number, src: number, dst: number}, rows: edges}, as: 'links'},
    {graph: machineMapping, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Node',
      where: {eq: [{field: 'id'}, {literal: 1}]}, bindings: {identity: 'identity'}, fields: ['identity']}, as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'identity'}, path_mode: 'walk', emit: 'paths', hops}, as: 'paths'},
    {from: 'paths', select: [{depth: 'hop_count'}], as: 'depths'},
    {from: 'depths', sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['depth']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}});
const definitionData = 'WITH n AS (SELECT 1 AS id, 20 AS score) '
  + ', e AS (SELECT 10 AS key, 1 AS src, 1 AS dst) ';
const definitionMapping = extra => ', g AS (GRAPH (NODE TABLES '
  + '(n AS S KEY (id) LABEL Start NO PROPERTIES, n AS T KEY (id) LABEL Target PROPERTIES (score)'
  + (extra ? ', n AS U KEY (id) LABEL Other NO PROPERTIES' : '')
  + ') EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES S '
  + 'DESTINATION KEY (dst) REFERENCES T LABEL R NO PROPERTIES'
  + (extra ? ', e AS F KEY (key) SOURCE KEY (src) REFERENCES S DESTINATION KEY (dst) REFERENCES U LABEL R NO PROPERTIES' : '')
  + '))) ';
export const graphHopNodePredicateSuccesses = [
  {name: 'graph-hop-node-json-single', format: 'json', text: JSON.stringify(program([first])),
    results: result(one), sourceReadCount: 0},
  {name: 'graph-hop-node-json-intermediate', format: 'json', text: JSON.stringify(program([
    first, {direction: 'out', edge_types: ['R'], node_where: {eq: [{field: 'id'}, {literal: 2}]}}])),
    results: result([{depth: 2}]), sourceReadCount: 0},
  sourceCase('qualified', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE b.payload.score > 10)'),
  sourceCase('local', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score > 10)'),
  sourceCase('quoted', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE `B`.`PAYLOAD`.`score` > 10)'),
  sourceCase('anonymous', '(a:Node WHERE id = 1)-[:R]->(:Node WHERE payload.score > 10)'),
  sourceCase('property-map', '(a:Node WHERE id = 1)-[:R]->(b:Node {id: 3})'),
  sourceCase('combined-edge-node', '(a:Node WHERE id = 1)-[:R WHERE key = 10]->(b:Node WHERE payload.score > 10)', [],
    {text: data + mapping.replace('LABEL R NO PROPERTIES', 'LABEL R PROPERTIES (key)')
      + tail('(a:Node WHERE id = 1)-[:R WHERE key = 10]->(b:Node WHERE payload.score > 10)')}),
  sourceCase('intermediate', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score > 10)-[:R]->(c:Node {id: 2})', [{depth: 2}]),
  sourceCase('incoming', '(a:Node WHERE id = 2)<-[:R]-(b:Node WHERE payload.score > 10)'),
  sourceCase('null-object-and-member', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score IS NULL)', [{depth: 1}, {depth: 1}]),
  sourceCase('typed-empty', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score > 100)', []),
  sourceCase('parameter', '(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score > @min)', one,
    {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}}),
  {name: 'graph-hop-node-reached-definition', format: 'aql-text',
    text: definitionData + definitionMapping(false) + tail('(:Start)-[:R]->(b:Target WHERE b.score > 10)'),
    results: result(one), sourceReadCount: 0},
];
export const graphHopNodePredicateRefusals = [
  ...['a.payload.score > 10', 'missing.score > 10', 'payload.missing > 0', 'id.score > 0', 'chosen > 0']
    .map((predicate, index) => ({name: 'graph-hop-node-invalid-' + index, format: 'aql-text',
      text: data + mapping + tail(`(a:Node WHERE id = 1)-[:R]->(b:Node WHERE ${predicate})`),
      parameterDeclarations: declarations, parameters})),
  {name: 'graph-hop-node-quantified-endpoint', expectedCode: 'ClientProgramImplementationLimit', format: 'aql-text',
    text: data + mapping + tail('(a:Node WHERE id = 1)-[:R]->{2,2}(b:Node WHERE payload.score > 10)'),
    parameterDeclarations: declarations, parameters},
  {name: 'graph-hop-node-conditional-property', format: 'aql-text',
    text: definitionData + definitionMapping(true) + tail('(:Start)-[:R]->(b WHERE b.score > 10)')},
  {name: 'graph-hop-node-unfiltered-label', expectedCode: 'ClientProgramImplementationLimit', format: 'aql-text',
    text: definitionData + definitionMapping(true) + tail('(:Start)-[:R]->(:Target)')},
];
