// Independent fold results and keys. No graph implementation or lowered
// output generates this oracle. [g,g] means three occurrences including left.
const number = {type: 'number', nullable: false};
const labels = {type: 'array', nullable: false, items: {type: 'string', nullable: false}};
const nodeColumns = ['p', 'part', 'node_key'].map(name => ({name, contract: number}))
  .concat([{name: 'labels', contract: labels}]);
const edgeColumns = ['w', 'part', 'edge_key'].map(name => ({name, contract: number}))
  .concat([{name: 'labels', contract: labels}]);
const nodeValues = {schema: {part: number, node_key: number, p: number},
  rows: [{part: 7, node_key: 1, p: 7}]};
const edgeValues = {schema: {part: number, edge_key: number, src_key: number, dst_key: number, w: number},
  rows: [{part: 7, edge_key: 11, src_key: 1, dst_key: 1, w: 5},
    {part: 7, edge_key: 10, src_key: 1, dst_key: 1, w: 2}]};
const mapping = {version: 'actql-graph-constructor/0.1', nodes: [
  {name: 'N', from: 'n', key: ['part', 'node_key'], labels: [
    {name: 'Person', properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}]}],
  edges: [{name: 'E', from: 'e', key: ['part', 'edge_key'],
    source: {definition: 'N', key: ['part', 'src_key']},
    target: {definition: 'N', key: ['part', 'dst_key']},
    labels: [{name: 'R', properties: {mode: 'columns', columns: [{from: 'w', to: 'w'}]}}]}]};
const merge = strategy => ({node_properties: {p: strategy}, edge_properties: {w: strategy}});
const result = (p, a, b) => ({
  nodes: {rows: [{p, part: 7, node_key: 1, labels: ['Person']}], columns: nodeColumns},
  edges: {rows: [{w: a, part: 7, edge_key: 10, labels: ['R']},
    {w: b, part: 7, edge_key: 11, labels: ['R']}], columns: edgeColumns},
});
export const graphUnionProgram = {version: 'actql/0.1', id: 'fixture.graph_union',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: nodeValues, as: 'n'}, {values: edgeValues, as: 'e'},
    {graph: mapping, as: 'g'},
    {from: 'g', union_graphs: {with: ['g', 'g'], merge: merge('number_sum')}, as: 'combined'},
    {from: 'combined', node_rows: true, as: 'nodes'},
    {from: 'nodes', select: ['p', 'part', 'node_key', 'labels'], as: 'node_projection'},
    {from: 'combined', edge_rows: true},
    {select: ['w', 'part', 'edge_key', 'labels']},
    {sort: [{field: 'edge_key', dir: 'asc', nulls: 'first'}], as: 'edge_projection'},
  ], results: {nodes: {from: 'node_projection', fields: ['p', 'part', 'node_key', 'labels']},
    edges: {from: 'edge_projection', fields: ['w', 'part', 'edge_key', 'labels']}}}],
  results: {nodes: {from: {stage: 'main', result: 'nodes'}},
    edges: {from: {stage: 'main', result: 'edges'}}}};
const data = 'DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p; ' +
  'DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w ' +
  'UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; ';
const definition = 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) ' +
  'EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N ' +
  'DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); ';
const policy = strategy => `{node_properties: {p: '${strategy}'}, edge_properties: {w: '${strategy}'}}`;
// The query-script contract has one terminal query. Both projections have
// independent source submissions; the JSON control also checks both consumers
// and Named Results sharing one Graph in the same Program.
const outputs = {
  nodes: 'FROM combined |> node_rows() |> SELECT p, part, node_key, labels |> RESULT nodes',
  edges: 'FROM combined |> edge_rows() |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges',
};
const textCase = (name, body, results) => ['nodes', 'edges'].map(kind => ({
  name: 'graph-union-' + name + '-' + kind, format: 'aql-text',
  text: data + definition + body + outputs[kind], results: {[kind]: results[kind]}, sourceReadCount: 0}));
export const graphUnionSourceSuccesses = [
  {name: 'graph-union-independent-json', format: 'json', text: JSON.stringify(graphUnionProgram),
    results: result(21, 6, 15), sourceReadCount: 0},
  ...textCase('repeated-peer-list', `DATA combined = FROM g |> union_graphs(with: [g, g], merge: ${policy('number_sum')}); `,
    result(21, 6, 15)),
  ...textCase('single-peer', `DATA combined = FROM g |> union_graphs(with: g, merge: ${policy('number_sum')}); `,
    result(14, 4, 10)),
  ...textCase('quoted-alias', `DATA \`peer graph\` = FROM g; DATA combined = FROM g |> union_graphs(with: \`peer graph\`, merge: ${policy('number_sum')}); `,
    result(14, 4, 10)),
  ...textCase('forward-fold-order', `DATA doubled = FROM g |> union_graphs(with: g, merge: ${policy('number_sum')}); DATA combined = FROM g |> union_graphs(with: [doubled, g], merge: ${policy('number_mean')}); `,
    result(8.75, 2.5, 6.25)),
  ...textCase('reverse-fold-order', `DATA doubled = FROM g |> union_graphs(with: g, merge: ${policy('number_sum')}); DATA combined = FROM g |> union_graphs(with: [g, doubled], merge: ${policy('number_mean')}); `,
    result(10.5, 3, 7.5)),
  {name: 'graph-union-direct-relation-transition', format: 'aql-text',
    text: data + definition + `FROM g |> union_graphs(with: [g, g], merge: ${policy('number_sum')}) |> edge_rows(definition: 'E') |> WHERE w > 10 |> SELECT edge_key, w |> ORDER BY edge_key |> LIMIT 1 |> RESULT selected`,
    results: {selected: {rows: [{edge_key: 11, w: 15}], columns: ['edge_key', 'w'].map(name => ({name, contract: number}))}},
    sourceReadCount: 0},
];
export const graphUnionSourceRefusals = [
  "FROM g |> union_graphs(with: 'g') |> node_rows() |> SELECT p",
  'FROM g |> union_graphs(with: []) |> node_rows() |> SELECT p',
  'FROM g |> union_graphs(with: missing) |> node_rows() |> SELECT p',
  'FROM g |> union_graphs(with: n) |> node_rows() |> SELECT p',
  'DATA combined = FROM g |> union_graphs(with: later); DATA later = FROM g; ' + outputs.nodes,
  'FROM g |> union_graphs(with: g, extra: true) |> node_rows() |> SELECT p',
  "FROM g |> union_graphs(with: g, merge: {node_properties: {p: 'unknown'}}) |> node_rows() |> SELECT p",
  'FROM g |> node_rows() |> union_graphs(with: g) |> SELECT p',
  'DATA m = SELECT 7 AS part, 2 AS node_key, 7 AS p; DATA h = PROPERTY GRAPH (NODE TABLES (m AS N KEY (part, node_key) LABEL Person PROPERTIES (p))); FROM g |> union_graphs(with: h) |> node_rows() |> SELECT p',
].map((body, index) => ({name: 'graph-union-refuse-' + index, format: 'aql-text', text: data + definition + body}));
export const graphUnionSourceExecutionFailures = ['nodes', 'edges'].map(kind => ({name: 'graph-union-unselected-conflict-policy-' + kind,
  format: 'aql-text', text: data + definition +
    `DATA doubled = FROM g |> union_graphs(with: g, merge: ${policy('number_sum')}); DATA combined = FROM doubled |> union_graphs(with: g); ` + outputs[kind],
  resultNames: [kind], sourceReadCount: 0}));
