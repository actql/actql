// Reuse independently authored constructor/row contracts, never a product
// compiler or evaluator. Expected values follow the existing subtraction law.
import {graphUnionProgram} from './property-graph-union-source-input.mjs';
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const labels = {type: 'array', nullable: false, items: {type: 'string', nullable: false}};
const nodeColumns = nullable => ['p', 'part', 'node_key'].map(name => ({name,
  contract: name === 'p' && nullable ? nullableNumber : number})).concat([{name: 'labels', contract: labels}]);
const edgeColumns = ['w', 'part', 'edge_key'].map(name => ({name, contract: number}))
  .concat([{name: 'labels', contract: labels}]);
const result = (kind, rows, nullable = false) => ({[kind]: {rows,
  columns: kind === 'nodes' ? nodeColumns(nullable) : edgeColumns}});
const node = p => ({p, part: 7, node_key: 1, labels: ['Person']});
const edges = (a, b) => [{w: a, part: 7, edge_key: 10, labels: ['R']},
  {w: b, part: 7, edge_key: 11, labels: ['R']}];
const merge = {node_properties: {p: 'number_sum'}, edge_properties: {w: 'number_sum'}};
export const graphSubtractionProgram = structuredClone(graphUnionProgram);
graphSubtractionProgram.id = 'fixture.graph_subtraction';
graphSubtractionProgram.stages[0].steps[3] = {from: 'g',
  subtract_graphs: {with: 'g', merge}, as: 'combined'};

const prefix = 'DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p; ' +
  'DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w ' +
  'UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; ' +
  'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) ' +
  'EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N ' +
  'DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); ';
const nullablePrefix = prefix.replace('7 AS p', 'CAST(NULL AS FLOAT64) AS p');
const output = kind => kind === 'nodes'
  ? ' |> node_rows() |> SELECT p, part, node_key, labels |> ORDER BY node_key |> RESULT nodes'
  : ' |> edge_rows() |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges';
const textCase = (name, call, kind, rows, extra = {}) => ({
  name: 'graph-subtraction-' + name + '-' + kind, format: 'aql-text',
  text: prefix + 'FROM g |> ' + call + output(kind), results: result(kind, rows),
  sourceReadCount: 0, ...extra});

// Node 1 is removed, node 2 and its self-loop remain; the 1->2 edge must be
// removed by endpoint closure even though it was absent in the peer subgraph.
const subsetPrefix = prefix.replace('1 AS node_key, 7 AS p;',
  '1 AS node_key, 7 AS p UNION ALL SELECT 7 AS part, 2 AS node_key, 9 AS p;')
  .replace('1 AS dst_key, 5 AS w', '2 AS dst_key, 5 AS w')
  .replace('1 AS src_key, 1 AS dst_key, 2 AS w', '2 AS src_key, 2 AS dst_key, 2 AS w');
const peerSelection = 'DATA selected = FROM g |> node_rows() |> WHERE node_key = 1 |> SELECT id; ' +
  'DATA peer = FROM g |> subgraph(nodes: {from: selected, id: "id"}); ';
export const graphSubtractionSubsetProgram = structuredClone(graphSubtractionProgram);
graphSubtractionSubsetProgram.id = 'fixture.graph_subtraction_subset';
const subsetSteps = graphSubtractionSubsetProgram.stages[0].steps;
subsetSteps[0].values.rows.push({part: 7, node_key: 2, p: 9});
subsetSteps[1].values.rows[0].dst_key = 2;
subsetSteps[1].values.rows[1].src_key = 2;
subsetSteps[1].values.rows[1].dst_key = 2;
subsetSteps.splice(3, 1,
  {from: 'g', node_rows: true, as: 'identities'},
  {from: 'identities', filter: {eq: [{field: 'node_key'}, {literal: 1}]}},
  {select: ['id'], as: 'selected'},
  {from: 'g', subgraph: {nodes: {from: 'selected', id: 'id'}}, as: 'peer'},
  {from: 'g', subtract_graphs: {with: 'peer'}, as: 'combined'});
const subsetRows = {nodes: [{p: 9, part: 7, node_key: 2, labels: ['Person']}],
  edges: [{w: 2, part: 7, edge_key: 10, labels: ['R']}]};

export const graphSubtractionSourceSuccesses = [
  {name: 'graph-subtraction-independent-json', format: 'json', text: JSON.stringify(graphSubtractionProgram),
    results: {...result('nodes', [node(14)]), ...result('edges', edges(4, 10))}, sourceReadCount: 0},
  {name: 'graph-subtraction-independent-subset-json', format: 'json', text: JSON.stringify(graphSubtractionSubsetProgram),
    results: {...result('nodes', subsetRows.nodes), ...result('edges', subsetRows.edges)}, sourceReadCount: 0},
  ...['nodes', 'edges'].map(kind => textCase('self-default-removal', 'subtract_graphs(with: g)', kind, [])),
  textCase('explicit-equality-retains-node', "subtract_graphs(with: g, merge: {node_properties: {p: 'exact_equal'}})", 'nodes', [node(7)]),
  textCase('node-policy-does-not-retain-edges', "subtract_graphs(with: g, merge: {node_properties: {p: 'exact_equal'}})", 'edges', []),
  textCase('edge-policy-cannot-resurrect-nodes', "subtract_graphs(with: g, merge: {edge_properties: {w: 'exact_equal'}})", 'edges', []),
  ...['nodes', 'edges'].map(kind => textCase('quoted-data-numeric-policy', '', kind,
    kind === 'nodes' ? [node(14)] : edges(4, 10), {
      text: prefix + 'DATA `peer graph` = FROM g; DATA remaining = FROM g |> ' +
        "subtract_graphs(with: `peer graph`, merge: {node_properties: {p: 'number_sum'}, edge_properties: {w: 'number_sum'}}); FROM remaining" + output(kind)})),
  ...['nodes', 'edges'].map(kind => textCase('nonempty-subset-and-endpoint-closure', '', kind, subsetRows[kind], {
    text: subsetPrefix + peerSelection + 'FROM g |> subtract_graphs(with: peer)' + output(kind)})),
  textCase('zero-is-retained-value', '', 'nodes', [node(0)], {
    text: prefix.replace('7 AS p', '0 AS p') + "FROM g |> subtract_graphs(with: g, merge: {node_properties: {p: 'number_sum'}})" + output('nodes')}),
  textCase('nullable-empty-contract', '', 'nodes', [], {
    text: nullablePrefix + 'FROM g |> subtract_graphs(with: g)' + output('nodes'), results: result('nodes', [], true)}),
];

export const graphSubtractionSourceRefusals = [
  ['string-peer', "subtract_graphs(with: 'g')", 'ClientProgramInvalidInput'],
  ['list-peer', 'subtract_graphs(with: [g])', 'ClientProgramUnsupported'],
  ['empty-peer-list', 'subtract_graphs(with: [])', 'ClientProgramUnsupported'],
  ['missing-peer', 'subtract_graphs()', 'ClientProgramUnsupported'],
  ['unknown-peer', 'subtract_graphs(with: missing)', 'ClientProgramRejected'],
  ['relation-peer', 'subtract_graphs(with: n)', 'ClientProgramRejected'],
  ['extra-argument', 'subtract_graphs(with: g, extra: true)', 'ClientProgramUnsupported'],
  ['lost-graph-scope', 'node_rows() |> subtract_graphs(with: g)', 'ClientProgramUnsupported'],
].map(([name, call, expectedCode]) => ({name: 'graph-subtraction-' + name, format: 'aql-text',
  text: prefix + 'FROM g |> ' + call + output('nodes'), expectedCode})).concat([
  {name: 'graph-subtraction-forward-peer', format: 'aql-text', expectedCode: 'ClientProgramRejected',
    text: prefix + 'DATA remaining = FROM g |> subtract_graphs(with: later); DATA later = FROM g; FROM remaining' + output('nodes')},
  {name: 'graph-subtraction-unknown-policy', format: 'aql-text',
    text: prefix + "FROM g |> subtract_graphs(with: g, merge: {node_properties: {p: 'unknown'}})" + output('nodes')},
]);
export const graphSubtractionSourceExecutionFailures = [
  {name: 'graph-subtraction-null-is-not-zero', format: 'aql-text', text: nullablePrefix +
    "FROM g |> subtract_graphs(with: g, merge: {node_properties: {p: 'number_sum'}})" + output('nodes'),
    resultNames: ['nodes'], sourceReadCount: 0},
  {name: 'graph-subtraction-conflict-needs-policy', format: 'aql-text', text: prefix +
    "DATA doubled = FROM g |> union_graphs(with: g, merge: {node_properties: {p: 'number_sum'}, edge_properties: {w: 'number_sum'}}); FROM doubled |> subtract_graphs(with: g)" + output('edges'),
    resultNames: ['edges'], sourceReadCount: 0},
];
