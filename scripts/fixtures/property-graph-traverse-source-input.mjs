// Independent authored Programs, definition preimages and results. This file
// imports no compiler, runtime, schema inference or traversal implementation.
import {createHash} from 'node:crypto';
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const number = {type: 'number', nullable: false};
const nodeDefinition = {name: 'N', from: 'n', key: ['node_key'],
  labels: [{name: 'Node', properties: {mode: 'no_properties'}}]};
const mapping = {version: 'actql-property-graph-constructor/0.1',
  nodes: [nodeDefinition], edges: []};
const definitionMapping = {...mapping, nodes: [{name: 'N', input_occurrence: 0,
  key: ['node_key'], labels: nodeDefinition.labels}]};
const nodeValues = {schema: {node_key: number}, rows: [{node_key: 1}]};
// SELECT without FROM uses the already specified Boolean witness, then the
// authored literal and projection. These complete definitions are written
// independently, rather than read from a product-generated Program.
const sourceNodeDefinition = {body: {select: [{node_key: 'aql_query_expr_0'}]},
  dependencies: [{body: {derive: {aql_query_expr_0: {literal: 1}}},
    dependencies: [{body: {values: {
      schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
      rows: [{aql_source_free_unit: true}],
    }}, dependencies: []}]}]};
const domain = producer => cid({constructor: definitionMapping,
  producer_definitions: [producer], version: 'actql-property-graph-definition/0.1'});
const sourceDomain = domain(sourceNodeDefinition);
const jsonDomain = domain({body: {values: nodeValues}, dependencies: []});
// Public JSON cells use the common typed wire; the definition preimage above
// remains semantic data rather than a Result cell.
const identity = domain => ({$json: {definition: 'N', domain, key: [1], key_types: [{kind: 'number'}]}});
const columns = [
  ...['start_id', 'node_id'].map(name => ({name, contract: {type: 'json', nullable: false}})),
  {name: 'depth', contract: number},
];
const result = (domain, empty = false) => ({nodes: {columns,
  rows: empty ? [] : [{start_id: identity(domain), node_id: identity(domain), depth: 0}]}});
const source = 'DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); ';
const seeds = 'DATA seeds = FROM g |> node_rows() |> SELECT id AS element; ';
const call = "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10)";
const tail = ' |> SELECT start_id, node_id, depth |> WHERE depth >= 0 |> ORDER BY depth |> RESULT nodes';
const json = JSON.stringify({version: 'actql/0.1', id: 'fixture.traverse_nodes',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: nodeValues, as: 'n'}, {property_graph: mapping, as: 'g'},
    {from: 'g', node_rows: true, as: 'rows'},
    {from: 'rows', select: [{element: 'id'}], as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'element'}, direction: 'out',
      min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10}, as: 'visited'},
    {from: 'visited', select: ['start_id', 'node_id', 'depth']},
    {filter: {gte: [{field: 'depth'}, {literal: 0}]}},
    {sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {out: {from: 'ordered', fields: ['start_id', 'node_id', 'depth']}}}],
  results: {nodes: {from: {stage: 'main', result: 'out'}}}});
export const graphTraverseSourceSuccesses = [
  {name: 'graph-traverse-nodes-json-control', format: 'json', text: json,
    results: result(jsonDomain), sourceReadCount: 0},
  {name: 'graph-traverse-nodes-data-selector', format: 'aql-text', text: source + seeds + 'FROM g |> ' + call + tail,
    results: result(sourceDomain), sourceReadCount: 0},
  {name: 'graph-traverse-nodes-empty-hop-labels', format: 'aql-text', text: source + seeds + 'DATA visited = FROM g |> ' +
    "traverse(start: {from: seeds, id: 'element'}, hops: [{direction: 'out', edge_types: []}], path_mode: 'walk', emit: 'nodes') |> SELECT start_id, node_id, depth; FROM visited |> ORDER BY depth |> RESULT nodes",
    results: result(sourceDomain, true), sourceReadCount: 0},
  {name: 'graph-traverse-nodes-empty-selector', format: 'aql-text', text: source +
    'DATA seeds = FROM g |> node_rows() |> WHERE node_key > 1 |> SELECT id AS element; FROM g |> ' + call + tail,
    results: result(sourceDomain, true), sourceReadCount: 0},
  {name: 'graph-traverse-nodes-quoted-data-selector', format: 'aql-text', text: source + seeds.replace('seeds', '`seed set`') +
    'FROM g |> ' + call.replace('from: seeds', 'from: `seed set`').replace("'trail'", "'acyclic'") + tail,
    results: result(sourceDomain), sourceReadCount: 0},
];
export const graphTraverseSourceRefusals = [
  ['unknown-selector', call.replace('from: seeds', 'from: missing')],
  ['string-selector-reference', call.replace('from: seeds', "from: 'seeds'")],
  ['missing-selector-column', call.replace("id: 'element'", "id: 'missing'")],
  ['unknown-emission', call.replace("emit: 'nodes'", "emit: 'invented'")],
  ['invalid-hop-bound', call.replace('max_hops: 1', 'max_hops: 0')],
  ['invalid-path-mode', call.replace("'trail'", "'invented'")],
  ['extra-argument', call.replace('max_output_rows: 10', 'max_output_rows: 10, extra: true')],
].map(([name, operation]) => ({name: 'graph-traverse-' + name, format: 'aql-text',
  text: source + seeds + 'FROM g |> ' + operation + tail}));
