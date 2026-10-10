import {graphUnionProgram} from './graph-union-source-input.mjs';

// Reuse only independently authored input declarations, never union output.
// Graft has no merge policy and self-graft preserves every complete record.
export const graphGraftProgram = structuredClone(graphUnionProgram);
graphGraftProgram.id = 'fixture.graph_graft';
graphGraftProgram.stages[0].steps[3] =
  {from: 'g', graft_graph: {with: 'g'}, as: 'combined'};
const number = {type: 'number', nullable: false};
const labels = {type: 'array', nullable: false, items: {type: 'string', nullable: false}};
const expected = {
  nodes: {rows: [{p: 7, part: 7, node_key: 1, labels: ['Person']}],
    columns: ['p', 'part', 'node_key'].map(name => ({name, contract: number}))
      .concat([{name: 'labels', contract: labels}])},
  edges: {rows: [{w: 2, part: 7, edge_key: 10, labels: ['R']},
    {w: 5, part: 7, edge_key: 11, labels: ['R']}],
    columns: ['w', 'part', 'edge_key'].map(name => ({name, contract: number}))
      .concat([{name: 'labels', contract: labels}])},
};
const prefix = 'DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p; ' +
  'DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w ' +
  'UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; ' +
  'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) ' +
  'EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N ' +
  'DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); ';
const output = {
  nodes: 'FROM combined |> node_rows() |> SELECT p, part, node_key, labels |> RESULT nodes',
  edges: 'FROM combined |> edge_rows() |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges',
};
const empty = structuredClone(graphGraftProgram);
empty.id = 'fixture.graph_graft_empty';
for (const step of empty.stages[0].steps.slice(0, 2)) step.values.rows = [];
export const graphGraftSourceSuccesses = [
  {name: 'graph-graft-independent-json-two-consumers', format: 'json',
    text: JSON.stringify(graphGraftProgram), results: expected, sourceReadCount: 0},
  {name: 'graph-graft-empty-json', format: 'json', text: JSON.stringify(empty),
    results: Object.fromEntries(Object.entries(expected).map(([name, result]) =>
      [name, {...result, rows: []}])), sourceReadCount: 0},
  ...['nodes', 'edges'].map(kind => ({name: 'graph-graft-aql-' + kind, format: 'aql-text',
    text: prefix + 'DATA combined = FROM g |> graft_graph(with: g); ' + output[kind],
    results: {[kind]: expected[kind]}, sourceReadCount: 0})),
  {name: 'graph-graft-terminal-query', format: 'aql-text',
    text: prefix + 'FROM g |> graft_graph(with: g) |> edge_rows() |> WHERE w > 2 ' +
      '|> SELECT edge_key, w |> ORDER BY edge_key |> RESULT selected',
    results: {selected: {rows: [{edge_key: 11, w: 5}],
      columns: ['edge_key', 'w'].map(name => ({name, contract: number}))}}, sourceReadCount: 0},
];
export const graphGraftSourceRefusals = [
  'FROM g |> graft_graph(with: [g]) |> node_rows() |> SELECT p',
  'FROM g |> graft_graph(with: g, merge: {}) |> node_rows() |> SELECT p',
  'FROM g |> graft_graph(with: missing) |> node_rows() |> SELECT p',
  'FROM g |> graft_graph(with: n) |> node_rows() |> SELECT p',
].map((body, index) => ({name: 'graph-graft-refuse-' + index,
  format: 'aql-text', text: prefix + body}));
export const graphGraftSourceExecutionFailures = [{
  name: 'graph-graft-shared-property-conflict', format: 'aql-text',
  text: prefix + "DATA doubled = FROM g |> union_graphs(with: g, merge: {node_properties: {p: 'number_sum'}}); " +
    'DATA combined = FROM doubled |> graft_graph(with: g); ' + output.nodes,
  resultNames: ['nodes'], sourceReadCount: 0,
}];
