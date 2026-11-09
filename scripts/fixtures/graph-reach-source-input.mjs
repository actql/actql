// Independently authored Programs, identity preimages, ordered rows and schemas.
// No compiler, runtime or Graph algorithm is imported into this oracle.
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
const columns = [{name: 'start_id', contract: json}, {name: 'node_id', contract: json},
  {name: 'depth', contract: number}];
const result = (domain, empty = false) => ({rows: empty ? [] : [{
  start_id: {$json: identity(domain)}, node_id: {$json: identity(domain)}, depth: 0,
}], columns});
const program = {version: 'actql/0.1', id: 'fixture.graph_reach',
  stages: [{id: 'main', inputs: {}, steps: [
    {values, as: 'n'}, {graph: mapping, as: 'g'},
    {from: 'g', reach: {start: identity(jsonDomain), direction: 'both', max_depth: 1}, as: 'reached'},
    {from: 'reached', select: ['start_id', 'node_id', 'depth'], as: 'a'},
    {from: 'reached', filter: 'depth = 0'},
    {select: ['start_id', 'node_id', 'depth'], as: 'b'},
  ], results: {a: {from: 'a', fields: ['start_id', 'node_id', 'depth']},
    b: {from: 'b', fields: ['start_id', 'node_id', 'depth']}}}],
  results: {a: {from: {stage: 'main', result: 'a'}},
    b: {from: {stage: 'main', result: 'b'}}}};
const source = 'WITH n AS (SELECT 1 AS node_key) , g AS (GRAPH ' +
  '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) ';
const seeds = ', seeds AS (FROM g |> node_rows() |> SELECT id AS element) ';
const call = "reach(start: {from: seeds, id: `element`}, direction: 'out', max_depth: 1)";
const tail = ' |> SELECT start_id, node_id, depth |> WHERE depth >= 0 |> ORDER BY depth |> RESULT reached';

// Parallel edges and a self-loop must not duplicate Reach members or replace
// their minimum depths. These are authored directed connectivity expectations.
const connectedValues = [
  {schema: {node_key: number}, rows: [{node_key: 3}, {node_key: 2}, {node_key: 1}]},
  {schema: {edge_key: number, src: number, dst: number}, rows: [
    {edge_key: 13, src: 2, dst: 3}, {edge_key: 12, src: 1, dst: 1},
    {edge_key: 11, src: 1, dst: 2}, {edge_key: 10, src: 1, dst: 2},
  ]},
];
const connectedMapping = {...mapping, edges: [{name: 'E', from: 'e', key: ['edge_key'],
  source: {definition: 'N', key: ['src']}, target: {definition: 'N', key: ['dst']},
  labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]};
const connectedConstructor = structuredClone(connectedMapping);
for (const [index, definition] of [connectedConstructor.nodes[0], connectedConstructor.edges[0]].entries()) {
  delete definition.from;
  definition.input_occurrence = index;
}
const connectedDomain = cid({constructor: connectedConstructor,
  producer_definitions: connectedValues.map(values => ({body: {values}, dependencies: []})),
  version: 'actql-graph-definition/0.1'});
const connectedIdentity = key => ({definition: 'N', domain: connectedDomain,
  key: [key], key_types: [{kind: 'number'}]});
const connectedRows = direction => (direction === 'out' ? [1, 2, 3] : [1]).map((key, depth) => ({
  start_id: {$json: connectedIdentity(1)}, node_id: {$json: connectedIdentity(key)}, depth,
}));
const connectedProgram = direction => ({version: 'actql/0.1', id: 'fixture.graph_reach_connected_' + direction,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: connectedValues[0], as: 'n'}, {values: connectedValues[1], as: 'e'},
    {graph: connectedMapping, as: 'g'},
    {from: 'g', reach: {start: connectedIdentity(1), direction, max_depth: 2}, as: 'reached'},
    {from: 'reached', select: ['start_id', 'node_id', 'depth'], as: 'out'},
  ], results: {out: {from: 'out', fields: ['start_id', 'node_id', 'depth']}}}],
  results: {reached: {from: {stage: 'main', result: 'out'}}}});
// Node selector predicates use declared Graph properties, not node_rows key
// aliases. Keep the authored connectivity oracle and give it an explicit
// predicate property; the raw-identity JSON control remains independent.
// A finite array keeps these same three nodes in one generator path. The
// topology and selected finite planning-work/Resource policies stay unchanged.
const connectedSource = 'WITH n AS (SELECT node_key, node_key AS seed FROM UNNEST([3, 2, 1]) node_key) ' +
  ', e AS (SELECT 13 AS edge_key, 2 AS src, 3 AS dst UNION ALL SELECT 12 AS edge_key, 1 AS src, 1 AS dst ' +
  'UNION ALL SELECT 11 AS edge_key, 1 AS src, 2 AS dst UNION ALL SELECT 10 AS edge_key, 1 AS src, 2 AS dst) ' +
  ', g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (seed)) ' +
  'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) ';
export const graphReachSourceSuccesses = [
  {name: 'graph-reach-json-raw-identity-two-consumers', format: 'json',
    text: JSON.stringify(program), results: {a: result(jsonDomain), b: result(jsonDomain)}, sourceReadCount: 0},
  {name: 'graph-reach-aql-relation-selector', format: 'aql-text',
    text: source + seeds + 'FROM g |> ' + call + tail,
    results: {reached: result(sourceDomain)}, sourceReadCount: 0},
  {name: 'graph-reach-aql-data-predicate', format: 'aql-text',
    text: source + ", reached AS (FROM g |> reach(start: {where: 'true'}, direction: 'both', max_depth: 2)) " +
      'FROM reached' + tail,
    results: {reached: result(sourceDomain)}, sourceReadCount: 0},
  {name: 'graph-reach-aql-empty-predicate', format: 'aql-text',
    text: source + "FROM g |> reach(start: {where: 'false'}, direction: 'in', max_depth: 1)" + tail,
    results: {reached: result(sourceDomain, true)}, sourceReadCount: 0},
  {name: 'graph-reach-aql-empty-relation', format: 'aql-text',
    text: source + ', seeds AS (FROM g |> node_rows() |> WHERE node_key > 1 |> SELECT id AS element) ' +
      'FROM g |> ' + call + tail,
    results: {reached: result(sourceDomain, true)}, sourceReadCount: 0},
  ...['out', 'in'].flatMap(direction => [
    {name: 'graph-reach-json-connected-' + direction, format: 'json',
      text: JSON.stringify(connectedProgram(direction)),
      results: {reached: {rows: connectedRows(direction), columns}}, sourceReadCount: 0},
    {name: 'graph-reach-aql-connected-' + direction, format: 'aql-text',
      text: connectedSource + ", reached AS (FROM g |> reach(start: {where: 'seed = 1'}, direction: '" +
        direction + "', max_depth: 2)) FROM reached |> SELECT depth |> ORDER BY depth |> RESULT reached",
      results: {reached: {rows: (direction === 'out' ? [0, 1, 2] : [0]).map(depth => ({depth})),
        columns: [{name: 'depth', contract: number}]}}, sourceReadCount: 0},
  ]),
];
export const graphReachSourceRefusals = [
  ['zero-depth', call.replace('max_depth: 1', 'max_depth: 0')],
  ['unknown-direction', call.replace("'out'", "'invented'")],
  ['missing-selector-field', call.replace("id: `element`", "id: `missing`")],
  ['missing-static-property', "reach(start: {where: 'missing = 1'}, direction: 'out', max_depth: 1)"],
].map(([name, operation]) => ({name: 'graph-reach-refuse-' + name,
  format: 'aql-text', text: source + seeds + 'FROM g |> ' + operation + tail}));
