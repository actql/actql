// Authored producer trees and snapshots supply expected Delta identities.
// No product compiler, canonicalizer, checker or difference output is imported.
import {createHash} from 'node:crypto';
const number = {type: 'number', nullable: false};
const columns = [{name: 'delta', contract: {type: 'json', nullable: false}}];
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.keys(value).sort()
    .map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const noProperties = [{name: 'Node', properties: {mode: 'none'}}];
const node = {name: 'N', from: 'n', key: ['node_key'], labels: noProperties};
const edge = (name, from) => ({name, from, key: ['edge_key'],
  source: {definition: 'N', key: ['src_key']}, target: {definition: 'N', key: ['dst_key']},
  labels: [{name: 'R', properties: {mode: 'none'}}]});
const mapping = edges => ({version: 'actql-property-graph-constructor/0.1', nodes: [node], edges});
const sourceFree = values => ({body: {select: Object.keys(values).map((key, i) => ({[key]: `aql_query_expr_${i}`}))},
  dependencies: [{body: {derive: Object.fromEntries(Object.values(values).map((value, i) =>
    [`aql_query_expr_${i}`, {literal: value}]))}, dependencies: [{body: {values: {
      schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
      rows: [{aql_source_free_unit: true}]}}, dependencies: []}]}]});
const valuesProducer = (schema, rows) => ({body: {values: {schema, rows}}, dependencies: []});
const law = 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc';
function oracle(construction, producers, edgeKeys, emptyTarget = false) {
  const constructor = structuredClone(construction);
  let occurrence = 0;
  for (const family of ['nodes', 'edges']) for (const definition of constructor[family]) {
    delete definition.from;
    definition.input_occurrence = occurrence++;
  }
  const domain = cid({version: 'actql-property-graph-definition/0.1', constructor, producer_definitions: producers});
  const identity = (definition, key) => ({definition, domain, key: [key], key_types: [{kind: 'number'}]});
  const contract = {version: 'actql-property-graph-contract/0.1', domain,
    identity_law_cid: law, value_law_cid: law,
    node_definitions: [{name: 'N', key_columns: ['node_key'], key_contracts: [number], labels: {Node: []}, properties: {}}],
    edge_definitions: construction.edges.map(({name}) => ({name, key_columns: ['edge_key'], key_contracts: [number],
      labels: {R: []}, properties: {}, source_definition: 'N', target_definition: 'N'}))};
  const nodes = [{id: identity('N', 1), key: [1], props: {}}];
  const edges = edgeKeys.map(([definition, key]) => ({id: identity(definition, key), key: [key],
    src: identity('N', 1), dst: identity('N', 1), props: {}}));
  const snapshot = (ns, es) => ['actql-property-graph-snapshot/0.1', cid(contract), contract, ns, es];
  return {version: 'actql-graph-delta/0.1', graph_contract_cid: cid(contract),
    base_graph_cid: cid(snapshot(nodes, edges)), target_graph_cid: cid(snapshot(emptyTarget ? [] : nodes, emptyTarget ? [] : edges)),
    nodes: {add: [], remove: emptyTarget ? nodes : [], update: []},
    edges: {add: [], remove: emptyTarget ? edges : [], update: []}};
}
const graphText = parallel => 'PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)' +
  (parallel ? ' EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES, f AS F KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES)' : '') + ')';
const prefix = 'DATA n = SELECT 1 AS node_key; DATA g = ' + graphText(false) + '; ';
const parallelPrefix = 'DATA n = SELECT 1 AS node_key; DATA e = SELECT 10 AS edge_key, 1 AS src_key, 1 AS dst_key; DATA f = SELECT 11 AS edge_key, 1 AS src_key, 1 AS dst_key; DATA g = ' + graphText(true) + '; ';
const singleDelta = oracle(mapping([]), [sourceFree({node_key: 1})], []);
const textParallelDelta = empty => oracle(mapping([edge('E', 'e'), edge('F', 'f')]),
  [sourceFree({node_key: 1}), sourceFree({edge_key: 10, src_key: 1, dst_key: 1}),
    sourceFree({edge_key: 11, src_key: 1, dst_key: 1})], [['E', 10], ['F', 11]], empty);
const machineMapping = mapping([edge('E', 'e')]);
const nodeRows = [{node_key: 1}], edgeRows = [10, 11].map(edge_key => ({edge_key, src_key: 1, dst_key: 1}));
const edgeSchema = {edge_key: number, src_key: number, dst_key: number};
const machineDelta = empty => oracle(machineMapping,
  [valuesProducer({node_key: number}, nodeRows), valuesProducer(edgeSchema, edgeRows)], [['E', 10], ['E', 11]], empty);
const machine = empty => JSON.stringify({version: 'actql/0.1', id: 'fixture.graph_difference', stages: [{id: 'main', inputs: {}, steps: [
  {values: {schema: {node_key: number}, rows: nodeRows}, as: 'n'},
  {values: {schema: edgeSchema, rows: edgeRows}, as: 'e'},
  {property_graph: machineMapping, as: 'g'},
  ...(empty ? [{from: 'g', subtract_graphs: {with: 'g'}, as: 'empty'}] : []),
  {from: 'g', graph_diff: {with: empty ? 'empty' : 'g'}, as: 'changes'},
  {from: 'changes', select: ['delta'], as: 'projected'},
], results: {out: {from: 'projected', fields: ['delta']}}}], results: {changes: {from: {stage: 'main', result: 'out'}}}});
const result = delta => ({changes: {rows: delta === undefined ? [] : [{delta}], columns}});
const item = (name, format, text, delta) => ({name: 'graph-difference-' + name, format, text, results: result(delta), sourceReadCount: 0});
export const graphDifferenceSourceSuccesses = [
  item('json-parallel-unchanged', 'json', machine(false), machineDelta(false)),
  item('json-parallel-removed', 'json', machine(true), machineDelta(true)),
  item('terminal-self', 'aql-text', prefix + 'FROM g |> graph_diff(with: g) |> SELECT delta |> RESULT changes', singleDelta),
  item('quoted-alias-normalized', 'aql-text', prefix + 'DATA `peer graph` = FROM g; DATA changes = FROM g |> normalize_graph() |> graph_diff(with: `peer graph`); FROM changes |> SELECT delta |> RESULT changes', singleDelta),
  item('parallel-removed', 'aql-text', parallelPrefix + 'DATA empty = FROM g |> subtract_graphs(with: g); FROM g |> graph_diff(with: empty) |> SELECT delta |> RESULT changes', textParallelDelta(true)),
  item('empty-typed-relation', 'aql-text', prefix + 'FROM g |> graph_diff(with: g) |> WHERE FALSE |> SELECT delta |> RESULT changes'),
];
export const graphDifferenceSourceRefusals = [
  ['string-producer', "FROM g |> graph_diff(with: 'g') |> SELECT delta"],
  ['unknown-producer', 'FROM g |> graph_diff(with: missing) |> SELECT delta'],
  ['relation-producer', 'FROM g |> graph_diff(with: n) |> SELECT delta'],
  ['forward-producer', 'DATA changes = FROM g |> graph_diff(with: later); DATA later = FROM g; FROM changes |> SELECT delta'],
  ['missing-argument', 'FROM g |> graph_diff() |> SELECT delta'],
  ['extra-argument', 'FROM g |> graph_diff(with: g, extra: true) |> SELECT delta'],
  ['graph-column', 'FROM g |> graph_diff(with: g) |> SELECT node_key'],
  ['repeated-transition', 'FROM g |> graph_diff(with: g) |> node_rows()'],
].map(([name, text]) => ({name: 'graph-difference-' + name, format: 'aql-text', text: prefix + text + ' |> RESULT changes'}));
