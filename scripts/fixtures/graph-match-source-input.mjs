// Authored Program controls and expected rows/contracts. No compiler, provider
// or row-sampling implementation supplies these expectations.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const declarations = {a: nullableNumber, b: nullableNumber, c: nullableNumber};
const parameters = {a: 10, b: 20, c: null};
const nodes = [{node_key: 2, p: 10}, {node_key: 1, p: 20}, {node_key: 3, p: null}];
const edges = [{edge_key: 11, src_key: 1, dst_key: 2, weight: 10},
  {edge_key: 10, src_key: 1, dst_key: 2, weight: 20}];
const mapping = {version: 'actql-property-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'], labels: [{name: 'Person',
    properties: {mode: 'columns', columns: ['node_key', 'p'].map(name => ({from: name, to: name}))}}]}],
  edges: [{name: 'E', from: 'e', key: ['edge_key'],
    source: {definition: 'N', columns: ['src_key'], references: ['node_key']},
    destination: {definition: 'N', columns: ['dst_key'], references: ['node_key']},
    labels: [{name: 'R', properties: {mode: 'columns',
      columns: ['edge_key', 'weight'].map(name => ({from: name, to: name}))}}]}]};
const prefix = 'DATA n = SELECT 2 AS node_key, @a AS p '
  + 'UNION ALL SELECT 1 AS node_key, @b AS p '
  + 'UNION ALL SELECT 3 AS node_key, @c AS p; '
  + 'DATA e = SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 10 AS weight '
  + 'UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key, 20 AS weight; '
  + 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (node_key, p)) '
  + 'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N '
  + 'DESTINATION KEY (dst_key) REFERENCES N LABEL R PROPERTIES (edge_key, weight))); ';
const columns = (fields, contracts) => fields.map((name, index) => ({name, contract: contracts[index]}));
const nodeColumns = columns(['p', 'node_key'], [nullableNumber, number]);
const edgeColumns = columns(['weight', 'edge_key'], [number, number]);
const result = (rows, columns) => ({matched: {rows, columns}});
const nodeBody = {definition: 'N', label: 'Person',
  where: {gt: [{field: 'p'}, {literal: 10}]}, fields: ['p', 'node_key']};
const edgeBody = {definition: 'E', label: 'R', fields: ['weight', 'edge_key']};
const jsonControl = (operation, body, fields, order) => JSON.stringify({
  version: 'actql/0.1', id: 'fixture.graph_match_' + operation,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {node_key: number, p: nullableNumber}, rows: nodes}, as: 'n'},
    {values: {schema: {edge_key: number, src_key: number, dst_key: number, weight: number}, rows: edges}, as: 'e'},
    {property_graph: mapping, as: 'g'},
    {from: 'g', [operation]: body, as: 'matched'},
    {from: 'matched', select: fields},
    {sort: [{field: order, dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {out: {from: 'ordered', fields}}}],
  results: {matched: {from: {stage: 'main', result: 'out'}}},
});
const sourceCase = (name, query, rows, expectedColumns = nodeColumns, extra = {}) => ({
  name: 'graph-match-' + name, format: 'aql-text', text: prefix + query,
  parameterDeclarations: declarations, parameters, sourceReadCount: 0,
  results: result(rows, expectedColumns), ...extra,
});
const nodeCall = "match_nodes(definition: 'N', label: 'Person', where: {gt: [{field: 'p'}, {literal: 10}]}, fields: ['p', 'node_key'])";
const nodeTail = ' |> SELECT p, node_key |> ORDER BY node_key |> RESULT matched';
const edgeCall = "match_edges(definition: 'E', label: 'R', fields: ['weight', 'edge_key'])";
const edgeTail = ' |> SELECT weight, edge_key |> ORDER BY edge_key |> RESULT matched';
const one = [{p: 20, node_key: 1}];
const parallel = [{weight: 20, edge_key: 10}, {weight: 10, edge_key: 11}];
export const graphMatchSourceSuccesses = [
  {name: 'graph-match-node-independent-json', format: 'json',
    text: jsonControl('match_nodes', nodeBody, ['p', 'node_key'], 'node_key'),
    results: result(one, nodeColumns), sourceReadCount: 0},
  sourceCase('node-predicate-and-field-order', 'FROM g |> ' + nodeCall + nodeTail, one),
  sourceCase('node-null-property', 'FROM g |> ' + nodeCall.replace(
    "{gt: [{field: 'p'}, {literal: 10}]}", "{is_null: {field: 'p'}}") + nodeTail,
    [{p: null, node_key: 3}]),
  sourceCase('node-empty-typed', 'FROM g |> ' + nodeCall.replace('literal: 10', 'literal: 100') + nodeTail, []),
  sourceCase('node-parameter', 'FROM g |> ' + nodeCall.replace('{literal: 10}', '@minimum') + nodeTail,
    one, nodeColumns, {parameterDeclarations: {...declarations, minimum: number},
      parameters: {...parameters, minimum: 10}}),
  sourceCase('node-quoted-data-relation',
    'DATA `selected rows` = FROM `g` |> ' + nodeCall.replace("'N'", "'n'").replace("'Person'", "'person'")
      + ' |> SELECT p AS score, node_key AS key; FROM `selected rows` |> WHERE key > 0 |> ORDER BY key |> RESULT matched',
    [{score: 20, key: 1}], columns(['score', 'key'], [nullableNumber, number])),
  {name: 'graph-match-edge-independent-json', format: 'json',
    text: jsonControl('match_edges', edgeBody, ['weight', 'edge_key'], 'edge_key'),
    results: result(parallel, edgeColumns), sourceReadCount: 0},
  sourceCase('edge-parallel-multiplicity', 'FROM g |> ' + edgeCall + edgeTail, parallel, edgeColumns),
  sourceCase('edge-empty-types', 'FROM g |> ' + edgeCall.replace("label: 'R'", "label: 'R', types: []") + edgeTail, [], edgeColumns),
  sourceCase('edge-predicate', 'FROM g |> ' + edgeCall.replace("label: 'R'",
    "label: 'R', where: {gt: [{field: 'weight'}, {literal: 10}]}") + edgeTail,
    [parallel[0]], edgeColumns),
];
export const graphMatchSourceRefusals = [
  ['unknown-definition', nodeCall.replace("'N'", "'missing'")],
  ['unknown-label', nodeCall.replace("'Person'", "'missing'")],
  ['missing-definition', nodeCall.replace("definition: 'N', ", '')],
  ['missing-predicate', nodeCall.replace("where: {gt: [{field: 'p'}, {literal: 10}]}, ", '')],
  ['missing-property', nodeCall.replace("field: 'p'", "field: 'missing'")],
  ['nonboolean-predicate', nodeCall.replace("{gt: [{field: 'p'}, {literal: 10}]}", '{literal: 1}')],
  ['missing-selected-field', nodeCall.replace("fields: ['p', 'node_key']", "fields: ['missing']")],
  ['duplicate-selected-field', nodeCall.replace("fields: ['p', 'node_key']", "fields: ['p', 'p']")],
  ['empty-fields', nodeCall.replace("fields: ['p', 'node_key']", 'fields: []')],
  ['identity-property-collision', nodeCall.replace("label: 'Person'", "label: 'Person', bindings: {identity: 'p'}")],
  ['extra-argument', nodeCall.replace("label: 'Person'", "label: 'Person', extra: true")],
  ['wrong-edge-type', edgeCall.replace("label: 'R'", "label: 'R', types: [1]")],
  ['relation-is-not-graph', nodeCall, 'n'],
  ['old-graph-property-not-selected', nodeCall + ' |> WHERE weight > 0'],
].map(([name, operation, input = 'g']) => ({
  name: 'graph-match-invalid-' + name, format: 'aql-text',
  text: prefix + 'FROM ' + input + ' |> ' + operation,
  parameterDeclarations: declarations, parameters,
}));
