// Independent keyed inputs, machine controls and multiplicities. R and S
// definitions ensure an empty abbreviated edge never acquires a label filter.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const nodes = [{id: 1, payload: {score: 10}}, {id: 2, payload: {score: 20}},
  {id: 3, payload: null}];
const rEdges = [{key: 10, src: 1, dst: 2}, {key: 11, src: 1, dst: 2},
  {key: 12, src: 3, dst: 1}, {key: 13, src: 1, dst: 1}];
const sEdges = [{key: 20, src: 1, dst: 3}];
const edgeSchema = {key: number, src: number, dst: number};
const declarations = {nodes: {type: 'array', nullable: false, max_items: 3,
  items: {type: 'object', nullable: false, fields: {id: number, payload}}},
  rEdges: {type: 'array', nullable: false, max_items: 4,
    items: {type: 'object', nullable: false, fields: edgeSchema}},
  sEdges: {type: 'array', nullable: false, max_items: 1,
    items: {type: 'object', nullable: false, fields: edgeSchema}}};
const parameters = {nodes, rEdges, sEdges};
const data = 'DATA objects = SELECT item.id AS id, item.payload AS payload '
  + 'FROM UNNEST(@nodes) AS item; DATA links = SELECT link.key AS key, '
  + 'link.src AS src, link.dst AS dst FROM UNNEST(@rEdges) AS link; '
  + 'DATA other_links = SELECT link.key AS key, link.src AS src, link.dst AS dst '
  + 'FROM UNNEST(@sEdges) AS link; ';
const mapping = 'DATA g = PROPERTY GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Node PROPERTIES ALL COLUMNS) EDGE TABLES '
  + '(links AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) '
  + 'REFERENCES N LABEL R NO PROPERTIES, other_links AS F KEY (key) '
  + 'SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL S NO PROPERTIES)); ';
const tail = (pattern, mode = '') => `FROM GRAPH g |> MATCH p = ${mode} ${pattern}`
  + ' |> SELECT PATH_LENGTH(p) AS depth |> ORDER BY depth |> RESULT matched';
const result = depths => ({matched: {rows: depths.map(depth => ({depth})),
  columns: [{name: 'depth', contract: number}]}});
const oneHop = count => Array(count).fill(1);
const sourceCase = (name, pattern, depths, mode = '', values = parameters) => ({
  name: 'graph-abbreviated-' + name, format: 'aql-text', text: data + mapping + tail(pattern, mode),
  parameterDeclarations: declarations, parameters: values, results: result(depths), sourceReadCount: 0,
});
const bounded = {nodes: [nodes[0]], rEdges: [{key: 10, src: 1, dst: 1}],
  sEdges: [{key: 20, src: 1, dst: 1}]};
function machine(direction, mode = 'walk', quantified = false) {
  const values = quantified ? bounded : parameters;
  return {version: 'actql/0.1', id: 'fixture.graph_abbreviated', stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: values.nodes}, as: 'objects'},
    {values: {schema: edgeSchema, rows: values.rEdges}, as: 'links'},
    {values: {schema: edgeSchema, rows: values.sEdges}, as: 'other_links'},
    {graph: {version: 'actql-graph-constructor/0.1', nodes: [{name: 'N', from: 'objects', key: ['id'],
      labels: [{name: 'Node', properties: {mode: 'all_columns'}}]}], edges: [
      {name: 'E', from: 'links', key: ['key'], source: {definition: 'N', key: ['src']},
        target: {definition: 'N', key: ['dst']}, labels: [{name: 'R', properties: {mode: 'no_properties'}}]},
      {name: 'F', from: 'other_links', key: ['key'], source: {definition: 'N', key: ['src']},
        target: {definition: 'N', key: ['dst']}, labels: [{name: 'S', properties: {mode: 'no_properties'}}]},
    ]}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Node',
      where: {eq: [{field: 'id'}, {literal: 1}]}, bindings: {identity: 'identity'}, fields: ['identity']}, as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'identity'}, path_mode: mode, emit: 'paths',
      ...(quantified ? {direction, min_hops: 0, max_hops: 2} : {hops: [{direction}]})}, as: 'paths'},
    {from: 'paths', select: [{depth: 'hop_count'}], as: 'depths'},
    {from: 'depths', sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['depth']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}};
}
export const graphAbbreviatedSuccesses = [
  ...[['out', '->', '-[]->', 4], ['in', '<-', '<-[]-', 2], ['both', '-', '-[]-', 5]]
    .flatMap(([direction, edge, full, count]) => [
      {name: 'graph-abbreviated-json-' + direction, format: 'json', text: JSON.stringify(machine(direction)),
        results: result(oneHop(count)), sourceReadCount: 0},
      sourceCase('full-' + direction, '(a:Node WHERE id = 1)' + full + '(b:Node)', oneHop(count)),
      sourceCase(direction, '(a:Node WHERE id = 1)' + edge + '(b:Node)', oneHop(count)),
    ]),
  sourceCase('quoted-node-predicate', '(a:Node WHERE id = 1)-(`b`:Node WHERE `B`.`PAYLOAD`.`score` > 15)', [1, 1]),
  sourceCase('nullable-node-predicate', '(a:Node WHERE id = 1)-(b:Node WHERE payload.score IS NULL)', [1, 1]),
  sourceCase('typed-empty', '(a:Node WHERE id = 1)->(b:Node WHERE payload.score > 100)', []),
  sourceCase('mixed-full-two-hop', '(a:Node WHERE id = 1)-(b:Node WHERE id = 2)<-[]-(c:Node WHERE id = 1)', [2, 2, 2, 2], 'WALK'),
  ...[['WALK', [0, 1, 1, 2, 2, 2, 2]], ['TRAIL', [0, 1, 1, 2, 2]], ['ACYCLIC', [0]]]
    .map(([mode, depths]) => sourceCase('bounded-' + mode.toLowerCase(),
      '(a:Node WHERE id = 1)-{0,2}(b:Node)', depths, mode, bounded)),
  {name: 'graph-abbreviated-json-bounded-trail', format: 'json', text: JSON.stringify(machine('both', 'trail', true)),
    results: result([0, 1, 1, 2, 2]), sourceReadCount: 0},
];
export const graphAbbreviatedRefusals = [
  ...['<->', '->>', '-:R', '-*', '->{1,}'].map((edge, index) => ({
    name: 'graph-abbreviated-invalid-' + index, format: 'aql-text',
    text: data + mapping + tail('(a:Node WHERE id = 1)' + edge + '(b:Node)'),
    parameterDeclarations: declarations, parameters,
  })),
  ...[['terminal-quantified-predicate', '(a:Node WHERE id = 1)->{2,2}(b:Node WHERE payload.score > 10)'],
    ['foreign-receiver', '(a:Node WHERE id = 1)->(b:Node WHERE a.payload.score > 10)'],
    ['unknown-member', '(a:Node WHERE id = 1)->(b:Node WHERE payload.missing > 10)']]
    .map(([name, pattern]) => ({name: 'graph-abbreviated-' + name, format: 'aql-text',
      text: data + mapping + tail(pattern), parameterDeclarations: declarations, parameters})),
];
