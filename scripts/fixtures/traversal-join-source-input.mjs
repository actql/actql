// Independent existing traversal/JOIN contracts, not compiler-generated values.
const number = {type: 'number', nullable: false};
const columns = ['depth', 'tag'].map(name => ({name, contract: number}));
const nodes = {schema: {node_key: number}, rows: [{node_key: 1}]};
const edges = {schema: {edge_key: number, src_key: number, dst_key: number},
  rows: [{edge_key: 11, src_key: 1, dst_key: 1}, {edge_key: 10, src_key: 1, dst_key: 1}]};
const rights = {schema: {depth: number, tag: number}, rows: [{depth: 2, tag: 20}, {depth: 2, tag: 10}]};
const mapping = {version: 'actql-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'no_properties'}}]}],
  edges: [{name: 'E', from: 'e', key: ['edge_key'], source: {definition: 'N', key: ['src_key']},
    target: {definition: 'N', key: ['dst_key']}, labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]};
const traversal = emit => ({start: {from: 'seeds', id: 'element'}, direction: 'out',
  min_hops: 2, max_hops: 2, path_mode: 'trail', emit, max_output_rows: 10});
const control = emit => {
  const key = emit === 'nodes' ? 'depth' : 'hop_count';
  return JSON.stringify({version: 'actql/0.1', id: 'fixture.traversal_join_' + emit,
    stages: [{id: 'main', inputs: {}, steps: [
      {values: nodes, as: 'n'}, {values: edges, as: 'e'}, {values: rights, as: 'r'},
      {graph: mapping, as: 'g'}, {from: 'g', node_rows: true, as: 'rows'},
      {from: 'rows', select: [{element: 'id'}], as: 'seeds'},
      {from: 'g', traverse: traversal(emit), as: 'visited'},
      {from: 'visited', join: {with: 'r', kind: 'inner', on: [{left: key, right: 'depth'}],
        max_output_rows: 10, select: {depth: 'left.' + key, tag: 'right.tag'}}, as: 'joined'},
      {from: 'joined', sort: [{field: 'depth', dir: 'asc', nulls: 'first'},
        {field: 'tag', dir: 'asc', nulls: 'first'}], as: 'sorted'},
    ], results: {out: {from: 'sorted', fields: ['depth', 'tag']}}}],
    results: {answer: {from: {stage: 'main', result: 'out'}}}});
};
const source = 'WITH n AS (SELECT 1 AS node_key) '
  + ', e AS (SELECT 11 AS edge_key, 1 AS src_key, 1 AS dst_key UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 1 AS dst_key) '
  + ', r AS (SELECT 2 AS depth, 20 AS tag UNION ALL SELECT 2 AS depth, 10 AS tag) '
  + ', g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) '
  + 'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES))) ';
const seeds = ', seeds AS (FROM g |> node_rows() |> SELECT id AS element) ';
const call = emit => "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 2, max_hops: 2, path_mode: 'trail', emit: '"
  + emit + "', max_output_rows: 10)";
const tail = (key, bound = 10) => ' |> AS v |> JOIN r AS rr ON v.' + key + ' = rr.depth MAX_OUTPUT_ROWS ' + bound
  + ' |> SELECT v.' + key + ' AS depth, rr.tag AS tag |> ORDER BY depth, tag';
const nodeExpected = [{depth: 2, tag: 10}, {depth: 2, tag: 20}];
// Two different keyed TRAIL edge sequences reach the same endpoint; node
// emission deduplicates it, while path emission keeps both choices before JOIN.
const pathExpected = [{depth: 2, tag: 10}, {depth: 2, tag: 10}, {depth: 2, tag: 20}, {depth: 2, tag: 20}];
const success = (name, text, expected, extra = {}) => ({name: 'traversal-join-' + name,
  format: 'aql-text', text, expected, columns, sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const traversalJoinSuccesses = [
  success('nodes-json', control('nodes'), nodeExpected, {format: 'json'}),
  success('nodes-text', source + seeds + 'FROM g |> ' + call('nodes') + tail('depth'), nodeExpected),
  success('paths-json', control('paths'), pathExpected, {format: 'json'}),
  success('paths-text', source + seeds + 'FROM g |> ' + call('paths') + tail('hop_count'), pathExpected),
  success('paths-filter-limit', source + seeds + 'FROM g |> ' + call('paths')
    + ' |> WHERE hop_count = 2' + tail('hop_count') + ' |> LIMIT 3', pathExpected.slice(0, 3)),
  success('nodes-projected', source + seeds + 'FROM g |> ' + call('nodes')
    + ' |> SELECT depth AS level' + tail('level'), nodeExpected),
  success('nodes-empty-selector', source + seeds.replace(' |> SELECT id', ' |> WHERE node_key > 1 |> SELECT id')
    + 'FROM g |> ' + call('nodes') + tail('depth'), []),
  success('nodes-column-order', source + seeds + 'FROM g |> ' + call('nodes') + tail('depth')
    + ' |> SELECT tag, depth', nodeExpected.map(({depth, tag}) => ({tag, depth})),
    {columns: [columns[1], columns[0]]}),
];
export const traversalJoinRefusals = [
  ['nodes-path-field', source + seeds + 'FROM g |> ' + call('nodes') + tail('hop_count')],
  ['paths-node-field', source + seeds + 'FROM g |> ' + call('paths') + tail('depth')],
  ['removed-column', source + seeds + 'FROM g |> ' + call('nodes') + ' |> SELECT depth'
    + ' |> AS v |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT v.start_id'],
  ['removed-range', source + seeds + 'FROM g |> ' + call('nodes')
    + ' |> AS v |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT g.depth'],
  ['invalid-mode', source + seeds + 'FROM g |> ' + call('nodes').replace("'trail'", "'invented'") + tail('depth')],
  ['invalid-join-bound', source + seeds + 'FROM g |> ' + call('nodes') + tail('depth', 0)],
].map(([name, text]) => ({name: 'traversal-join-' + name, format: 'aql-text', text}));
export const traversalJoinExecutionFailures = [{name: 'traversal-join-explicit-bound-exceeded',
  format: 'aql-text', text: source + seeds + 'FROM g |> ' + call('nodes') + tail('depth', 1),
  resultNames: ['main'], sourceReadSessionCount: 0}];
