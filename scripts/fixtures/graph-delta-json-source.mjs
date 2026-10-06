import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';

// Independently authored producer, contract and snapshots. Expected identities
// use the admitted definition preimage, never a compiler or runtime response.
const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const seed = {schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
  rows: [{aql_source_free_unit: true}]};
const derive = {aql_query_expr_0: {literal: 1}, aql_query_expr_1: {literal: 7}};
const select = [{node_key: 'aql_query_expr_0'}, {p: 'aql_query_expr_1'}];
const constructor = {version: 'actql-property-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'aql_data_0', key: ['node_key'], labels: [{name: 'Person',
    properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}]}], edges: []};
const mapping = structuredClone(constructor);
delete mapping.nodes[0].from;
mapping.nodes[0].input_occurrence = 0;
const domain = cid({constructor: mapping, producer_definitions: [{body: {select},
  dependencies: [{body: {derive}, dependencies: [{body: {values: seed}, dependencies: []}]}]}],
version: 'actql-property-graph-definition/0.1'});
const number = {type: 'number', nullable: false};
const identityLaw = 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc';
const contract = {version: 'actql-property-graph-contract/0.1', domain,
  identity_law_cid: identityLaw, value_law_cid: identityLaw,
  node_definitions: [{name: 'N', key_columns: ['node_key'], key_contracts: [number],
    labels: {Person: ['p']}, properties: {p: number}}], edge_definitions: []};
const contractCid = cid(contract);
const id = {definition: 'N', domain, key: [1], key_types: [{kind: 'number'}]};
const before = {id, key: [1], props: {p: 7}};
const after = {id, key: [1], props: {p: 8}};
const snapshot = node => ['actql-property-graph-snapshot/0.1', contractCid, contract, [node], []];
const delta = {version: 'actql-graph-delta/0.1', graph_contract_cid: contractCid,
  base_graph_cid: cid(snapshot(before)), target_graph_cid: cid(snapshot(after)),
  nodes: {add: [], remove: [], update: [{before, after}]}, edges: {add: [], remove: [], update: []}};
const deltaText = canonicalText(delta);

export const graphDeltaJsonSource = 'DATA n = SELECT 1 AS node_key, 7 AS p; '
  + 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); '
  + "DATA changes = SELECT JSON r'''" + deltaText + "''' AS delta; "
  + 'FROM g |> apply_graph_delta(with: changes, field: "delta") '
  + '|> node_rows() |> SELECT p, node_key |> RESULT answer';

export const graphDeltaJsonProgram = {version: 'actql/0.1', id: 'fixture.query_pair',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: seed, as: 'aql_script_seed_1'},
    {from: 'aql_script_seed_1', derive}, {select, as: 'aql_data_0'},
    {property_graph: constructor, as: 'aql_data_2'},
    {values: seed, as: 'aql_script_seed_4'},
    {from: 'aql_script_seed_4', derive: {aql_query_expr_0: {typed_literal: {type: 'json', value: deltaText}}}},
    {select: [{delta: 'aql_query_expr_0'}], as: 'aql_data_3'},
    {from: 'aql_data_2', apply_graph_delta: {with: 'aql_data_3', field: 'delta'}, as: 'aql_sga_5'},
    {from: 'aql_sga_5', node_rows: true, as: 'aql_sga_6'},
    {from: 'aql_sga_6', select: ['p', 'node_key']},
    {select: ['p', 'node_key'], as: 'aql_script_result'},
  ], results: {rows: {from: 'aql_script_result', fields: ['p', 'node_key']}}}],
results: {answer: {from: {stage: 'main', result: 'rows'}}}};

const expected = [{p: 8, node_key: 1}];
const columns = ['p', 'node_key'].map(name => ({name, contract: number}));
export const graphDeltaJsonSuccesses = [
  {name: 'graph-delta-authored-json-source', format: 'aql-text', text: graphDeltaJsonSource,
    expected, columns, sourceReadCount: 0},
  {name: 'graph-delta-authored-json-program', format: 'json', text: JSON.stringify(graphDeltaJsonProgram),
    expected, columns, sourceReadCount: 0},
];
