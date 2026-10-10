// Independent single-node Graph definition and zero-hop path oracle.
// No compiler or execution output supplies an expected identity or row.
import {createHash} from 'node:crypto';
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = body => 'sha256:' + createHash('sha256').update(canonical(body)).digest('hex');
const number = {type: 'number', nullable: false};
const json = {type: 'json', nullable: false};
const array = {type: 'array', nullable: false, items: json};
const fields = ['source_id', 'target_id', 'hop_count', 'total_cost', 'node_ids', 'edge_ids'];
const columns = fields.map(name => ({name, contract:
  name.endsWith('_ids') ? array : name.endsWith('_id') ? json : number}));
const values = {schema: {node_key: number}, rows: [{node_key: 1}]};
const node = {name: 'N', from: 'n', key: ['node_key'],
  labels: [{name: 'Node', properties: {mode: 'no_properties'}}]};
const mapping = {version: 'actql-graph-constructor/0.1', nodes: [node], edges: []};
const constructor = {...mapping, nodes: [{name: 'N', input_occurrence: 0,
  key: ['node_key'], labels: node.labels}]};
const domain = producer => cid({constructor, producer_definitions: [producer],
  version: 'actql-graph-definition/0.1'});
const jsonDomain = domain({body: {values}, dependencies: []});
const sourceDomain = domain({body: {select: [{node_key: 'aql_query_expr_0'}]},
  dependencies: [{body: {derive: {aql_query_expr_0: {literal: 1}}},
    dependencies: [{body: {values: {
      schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
      rows: [{aql_source_free_unit: true}],
    }}, dependencies: []}]}]});
const identity = domain => ({definition: 'N', domain, key: [1],
  key_types: [{kind: 'number'}]});
const result = (domain, empty = false) => {
  const id = {$json: identity(domain)};
  return {rows: empty ? [] : [{source_id: id, target_id: id,
    hop_count: 0, total_cost: 0, node_ids: [id], edge_ids: []}], columns};
};
const program = {version: 'actql/0.1', id: 'fixture.graph_shortest',
  stages: [{id: 'main', inputs: {}, steps: [
    {values, as: 'n'}, {graph: mapping, as: 'g'},
    {from: 'g', shortest_path: {source: identity(jsonDomain), target: identity(jsonDomain),
      direction: 'both', max_hops: 1}, as: 'paths'},
    {from: 'paths', select: fields, as: 'a'},
    {from: 'paths', filter: 'hop_count = 0'}, {select: fields, as: 'b'},
  ], results: {a: {from: 'a', fields}, b: {from: 'b', fields}}}],
  results: {a: {from: {stage: 'main', result: 'a'}},
    b: {from: {stage: 'main', result: 'b'}}}};
const source = 'DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH ' +
  '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); ';
const seeds = 'DATA seeds = FROM g |> node_rows() |> SELECT id AS element; ';
const tail = ' |> SELECT ' + fields.join(', ') + ' |> RESULT paths';
const call = selection => "shortest_path(source: {from: seeds, id: 'element'}, " +
  "target: {from: seeds, id: 'element'}, selection: '" + selection +
  "', direction: 'out', max_hops: 2)";
export const graphShortestSourceSuccesses = [
  {name: 'graph-shortest-json-zero-hop-two-consumers', format: 'json',
    text: JSON.stringify(program), results: {a: result(jsonDomain), b: result(jsonDomain)}, sourceReadCount: 0},
  ...['each_pair', 'nearest_per_source', 'nearest_pair'].map(selection => ({
    name: 'graph-shortest-aql-repeated-selector-' + selection, format: 'aql-text',
    text: source + seeds + 'FROM g |> ' + call(selection) + tail,
    results: {paths: result(sourceDomain)}, sourceReadCount: 0,
  })),
  {name: 'graph-shortest-aql-data-empty-target', format: 'aql-text',
    text: source + "DATA paths = FROM g |> shortest_path(source: {where: 'true'}, " +
      "target: {where: 'false'}, selection: 'each_pair', direction: 'in', max_hops: 1); " +
      'FROM paths' + tail,
    results: {paths: result(sourceDomain, true)}, sourceReadCount: 0},
];
export const graphShortestSourceRefusals = [
  ['zero-hops', call('each_pair').replace('max_hops: 2', 'max_hops: 0')],
  ['missing-selection', call('each_pair').replace("selection: 'each_pair', ", '')],
  ['unknown-direction', call('each_pair').replace("'out'", "'invented'")],
  ['missing-selector-field', call('each_pair').replace("id: 'element'", "id: 'missing'")],
  ['missing-property', "shortest_path(source: {where: 'missing = 1'}, target: {where: 'true'}, " +
    "selection: 'each_pair', direction: 'out', max_hops: 1)"],
].map(([name, operation]) => ({name: 'graph-shortest-refuse-' + name,
  format: 'aql-text', text: source + seeds + 'FROM g |> ' + operation + tail}));
