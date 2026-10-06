// Independent logical Programs, constructor provenance and result contracts.
// No query compiler, Graph kernel or sampled schema creates these expectations.
import {createHash} from 'node:crypto';
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const number = {type: 'number', nullable: false};
const identityContract = {type: 'json', nullable: false};
const noProperties = name => ({name, properties: {mode: 'no_properties'}});
// Two definitions over one Relation remain two nodes, even with the same key.
// E is N->M, L is N->N. The self-loop contributes two total incidences.
const mapping = {version: 'actql-property-graph-constructor/0.1',
  nodes: ['N', 'M'].map(name => ({name, from: 'n', key: ['node_key'],
    labels: [noProperties('Node')]})),
  edges: [['E', 'M'], ['L', 'N']].map(([name, target]) => ({
    name, from: 'n', key: ['edge_key'],
    source: {definition: 'N', key: ['node_key']},
    target: {definition: target, key: ['node_key']},
    labels: [noProperties('R')],
  }))};
const constructor = structuredClone(mapping);
let occurrence = 0;
for (const kind of ['nodes', 'edges']) for (const element of constructor[kind]) {
  delete element.from;
  element.input_occurrence = occurrence++;
}
const nodeValues = {schema: {node_key: number, edge_key: number},
  rows: [{node_key: 1, edge_key: 11}]};
const sourceProducer = {body: {select: [{node_key: 'aql_query_expr_0'},
  {edge_key: 'aql_query_expr_1'}]}, dependencies: [
  {body: {derive: {aql_query_expr_0: {literal: 1}, aql_query_expr_1: {literal: 11}}},
    dependencies: [{body: {values: {
      schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
      rows: [{aql_source_free_unit: true}],
    }}, dependencies: []}]},
]};
const domain = producer => cid({constructor,
  producer_definitions: Array.from({length: 4}, () => producer),
  version: 'actql-property-graph-definition/0.1'});
const sourceDomain = domain(sourceProducer);
const jsonDomain = domain({body: {values: nodeValues}, dependencies: []});
// This helper spells a non-null public JSON cell. SQL NULL bounds markers
// below remain null; constructor provenance is not a typed Result cell.
const identity = (domain, definition) => ({$json: {definition, domain, key: [1],
  key_types: [{kind: 'number'}]}});
const columns = {
  degree: [{name: 'degree', contract: number}, {name: 'node', contract: identityContract}],
  graph_bounds: [{name: 'actual', contract: number},
    {name: 'kind', contract: {type: 'string', nullable: false}},
    {name: 'node_id', contract: {...identityContract, nullable: true}},
    {name: 'max', contract: number}],
  components: [{name: 'component_size', contract: number},
    {name: 'node_id', contract: identityContract}, {name: 'component_id', contract: identityContract}],
};
const degreeRows = (domain, direction) => [
  {degree: direction === 'out' ? 0 : 1, node: identity(domain, 'M')},
  {degree: direction === 'both' ? 3 : direction === 'out' ? 2 : 1, node: identity(domain, 'N')},
];
const boundsRows = domain => [
  {actual: 2, kind: 'nodes', node_id: null, max: 1},
  {actual: 2, kind: 'edges', node_id: null, max: 1},
  {actual: 3, kind: 'degree', node_id: identity(domain, 'N'), max: 2},
];
const componentRows = (domain, kind) => ['M', 'N'].map(name => ({
  component_size: kind === 'weak' ? 2 : 1, node_id: identity(domain, name),
  component_id: identity(domain, kind === 'weak' ? 'M' : name),
}));
const results = (operation, rows) => ({diagnostics: {rows, columns: columns[operation]}});
const graphText = 'PROPERTY GRAPH (NODE TABLES (' +
  'n AS N KEY (node_key) LABEL Node NO PROPERTIES, n AS M KEY (node_key) LABEL Node NO PROPERTIES)' +
  ' EDGE TABLES (n AS E KEY (edge_key) SOURCE KEY (node_key) REFERENCES N DESTINATION KEY (node_key) REFERENCES M LABEL R NO PROPERTIES,' +
  ' n AS L KEY (edge_key) SOURCE KEY (node_key) REFERENCES N DESTINATION KEY (node_key) REFERENCES N LABEL R NO PROPERTIES))';
const prefix = 'DATA n = SELECT 1 AS node_key, 11 AS edge_key; DATA g = ' + graphText + '; ';
const tail = operation => ' |> SELECT ' + columns[operation].map(column => column.name).join(', ') + ' |> RESULT diagnostics';
const program = (operation, body) => JSON.stringify({version: 'actql/0.1',
  id: 'fixture.graph_diagnostics', stages: [{id: 'main', inputs: {}, steps: [
    {values: nodeValues, as: 'n'}, {property_graph: mapping, as: 'g'},
    {from: 'g', [operation]: body, as: 'stats'},
    {from: 'stats', select: columns[operation].map(column => column.name), as: 'selected'},
  ], results: {rows: {from: 'selected', fields: columns[operation].map(column => column.name)}}}],
  results: {diagnostics: {from: {stage: 'main', result: 'rows'}}}});
const textCase = (name, operation, argumentsText, rows, extra = {}) => ({
  name: 'graph-diagnostics-' + name, format: 'aql-text',
  text: prefix + 'FROM g |> ' + operation + '(' + argumentsText + ')' + tail(operation),
  results: results(operation, rows), sourceReadCount: 0, ...extra,
});
const parameterDeclarations = {p: {type: 'number'}};
export const graphDiagnosticSourceSuccesses = [
  ...[
    ['degree', {direction: 'both'}, degreeRows(jsonDomain, 'both')],
    ['graph_bounds', {max_nodes: 1, max_edges: 1, max_degree: 2}, boundsRows(jsonDomain)],
    ['components', {kind: 'strong', max_output_rows: 2}, componentRows(jsonDomain, 'strong')],
  ].map(([operation, body, rows]) => ({
    name: 'graph-diagnostics-json-' + operation, format: 'json',
    text: program(operation, body), results: results(operation, rows), sourceReadCount: 0,
  })),
  ...['in', 'out', 'both'].map(direction => textCase('degree-' + direction,
    'degree', 'direction: "' + direction + '"', degreeRows(sourceDomain, direction))),
  ...['weak', 'strong'].map(kind => textCase('components-' + kind,
    'components', 'kind: "' + kind + '", max_output_rows: 2', componentRows(sourceDomain, kind))),
  textCase('bounds-violations', 'graph_bounds', 'max_nodes: 1, max_edges: 1, max_degree: 2',
    boundsRows(sourceDomain)),
  textCase('bounds-exact-satisfied', 'graph_bounds', 'max_nodes: 2, max_edges: 2, max_degree: 3', []),
  textCase('bounds-parameter-zero', 'graph_bounds', 'max_nodes: @p',
    [{actual: 2, kind: 'nodes', node_id: null, max: 0}],
    {parameterDeclarations, parameters: {p: 0}}),
  {name: 'graph-diagnostics-quoted-data-normalized-suffix', format: 'aql-text',
    text: prefix + 'DATA `stats` = FROM g |> normalize_graph() |> degree(direction: "out"); FROM `stats` |> WHERE degree > 0 |> SELECT degree, node |> ORDER BY degree DESC |> LIMIT 1 |> RESULT diagnostics',
    results: results('degree', [degreeRows(sourceDomain, 'out')[1]]), sourceReadCount: 0},
  {name: 'graph-diagnostics-empty-typed-graph', format: 'aql-text',
    text: prefix.replace('11 AS edge_key;', '11 AS edge_key WHERE FALSE;') +
      'FROM g |> graph_bounds(max_nodes: 0, max_edges: 0, max_degree: 0)' + tail('graph_bounds'),
    results: results('graph_bounds', []), sourceReadCount: 0},
];
export const graphDiagnosticSourceRefusals = [
  ...[
    ['degree-missing', 'degree()' + tail('degree')],
    ['degree-invalid', 'degree(direction: "invented")' + tail('degree')],
    ['degree-extra', 'degree(direction: "out", extra: true)' + tail('degree')],
    ['bounds-missing', 'graph_bounds()' + tail('graph_bounds')],
    ['bounds-negative', 'graph_bounds(max_nodes: -1)' + tail('graph_bounds')],
    ['bounds-fractional', 'graph_bounds(max_edges: 1.5)' + tail('graph_bounds')],
    ['components-kind', 'components(kind: "invented")' + tail('components')],
    ['components-zero-guard', 'components(kind: "weak", max_output_rows: 0)' + tail('components')],
    ['lost-graph-column', 'degree(direction: "both") |> SELECT node_key |> RESULT diagnostics'],
    ['second-graph-call', 'degree(direction: "both") |> edge_rows() |> SELECT id |> RESULT diagnostics'],
  ].map(([name, suffix]) => ({name: 'graph-diagnostics-' + name, format: 'aql-text',
    text: prefix + 'FROM g |> ' + suffix})),
  ...[
    ['undeclared', {}],
    ['missing', {parameterDeclarations}],
    ['wrong-type', {parameterDeclarations, parameters: {p: 'zero'}}],
    ['negative', {parameterDeclarations, parameters: {p: -1}}],
  ].map(([name, extra]) => ({name: 'graph-diagnostics-parameter-' + name, format: 'aql-text',
    text: prefix + 'FROM g |> graph_bounds(max_nodes: @p)' + tail('graph_bounds'), ...extra})),
];
export const graphDiagnosticSourceExecutionFailures = [
  {name: 'graph-diagnostics-components-author-guard', format: 'aql-text',
    text: prefix + 'FROM g |> components(kind: "weak", max_output_rows: 1)' + tail('components'),
    resultNames: ['diagnostics'], sourceReadSessionCount: 0},
];
