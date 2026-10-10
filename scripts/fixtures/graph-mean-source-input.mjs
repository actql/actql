import {graphGraftProgram} from './graph-graft-source-input.mjs';

// Only authored declarations are reused. No Graft, Mean, compiler, or Host
// result supplies an expected value or determines the output schema.
export const graphMeanProgram = structuredClone(graphGraftProgram);
graphMeanProgram.id = 'fixture.graph_mean';
const properties = {nodes: {p: {mean: {missing: 'exclude', nulls: 'exclude'}}},
  edges: {w: {mean: {missing: 'exclude', nulls: 'exclude'}}}};
graphMeanProgram.stages[0].steps[3] = {
  mean_graphs: {with: ['g', 'g', 'g'], weights: [1, 2, 0],
    support: {nodes: 1, edges: 1}, properties}, as: 'combined',
};
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const labels = {type: 'array', nullable: false,
  items: {type: 'string', nullable: false}};
const results = {
  nodes: {rows: [{p: 7, part: 7, node_key: 1, labels: ['Person']}],
    columns: [{name: 'p', contract: nullableNumber},
      ...['part', 'node_key'].map(name => ({name, contract: number})),
      {name: 'labels', contract: labels}]},
  edges: {rows: [{w: 2, part: 7, edge_key: 10, labels: ['R']},
    {w: 5, part: 7, edge_key: 11, labels: ['R']}],
    columns: [{name: 'w', contract: nullableNumber},
      ...['part', 'edge_key'].map(name => ({name, contract: number})),
      {name: 'labels', contract: labels}]},
};
const prefix = 'DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p; ' +
  'DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w ' +
  'UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; ' +
  'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) ' +
  'EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N ' +
  'DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); ';
const call = 'mean_graphs(with: [g, g, g], weights: [1, 2, 0], ' +
  "support: {nodes: 1, edges: 1}, properties: {nodes: {p: {mean: {missing: 'exclude', nulls: 'exclude'}}}, " +
  "edges: {w: {mean: {missing: 'exclude', nulls: 'exclude'}}}})";
const empty = structuredClone(graphMeanProgram);
empty.id = 'fixture.graph_mean_empty';
for (const step of empty.stages[0].steps.slice(0, 2)) step.values.rows = [];

// Independently authored public acceptance controls. Registration is not an
// execution receipt; the delivery record reports which boundaries were run.
export const graphMeanSourceOracles = [
  {name: 'graph-mean-json-explicit-repeated-samples-two-consumers', format: 'json',
    text: JSON.stringify(graphMeanProgram), results, sourceReadCount: 0},
  {name: 'graph-mean-json-empty-graphs', format: 'json', text: JSON.stringify(empty),
    results: Object.fromEntries(Object.entries(results).map(([name, result]) =>
      [name, {...result, rows: []}])), sourceReadCount: 0},
  ...['nodes', 'edges'].map(kind => ({name: 'graph-mean-aql-generator-' + kind,
    format: 'aql-text', text: prefix + 'DATA combined = ' + call + '; ' +
      (kind === 'nodes'
        ? 'FROM combined |> node_rows() |> SELECT p, part, node_key, labels |> RESULT nodes'
        : 'FROM combined |> edge_rows() |> WHERE w > 0 |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges'),
    results: {[kind]: results[kind]}, sourceReadCount: 0})),
];

export const graphMeanSourceRefusalOracles = [
  prefix + 'DATA combined = FROM g |> ' + call + '; FROM combined |> node_rows() |> SELECT node_key',
  prefix + 'DATA combined = ' + call.replace('[1, 2, 0]', '[0, 0, 0]') + '; FROM combined |> node_rows() |> SELECT node_key',
  prefix + 'DATA combined = ' + call.replace('[g, g, g]', '[g, missing, g]') + '; FROM combined |> node_rows() |> SELECT node_key',
];

export const graphMeanSourceRefusals = graphMeanSourceRefusalOracles.map((text, index) => ({
  name: ['graph-mean-refuse-implicit-input', 'graph-mean-refuse-zero-weights',
    'graph-mean-refuse-unknown-sample'][index], format: 'aql-text', text,
}));
