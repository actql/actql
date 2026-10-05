// Independent definition preimages and path oracles. No compiler, Graph
// implementation, sampled rows or runtime encoder supplies an expectation.
import {createHash} from 'node:crypto';
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const number = {type: 'number', nullable: false};
const json = {type: 'json', nullable: false};
const array = {type: 'array', nullable: false, items: json};
const fields = ['start_id', 'end_id', 'hop_count', 'node_ids', 'edge_ids'];
const columns = fields.map(name => ({name, contract:
  name === 'hop_count' ? number : name.endsWith('_ids') ? array : json}));
const values = [
  {schema: {node_key: number}, rows: [{node_key: 1}]},
  ...[10, 11].map(edge_key => ({schema: {edge_key: number, src: number, dst: number},
    rows: [{edge_key, src: 1, dst: 1}]})),
];
const mapping = {version: 'actql-property-graph-constructor/0.1', nodes: [
  {name: 'N', from: 'n', key: ['node_key'], labels: [{name: 'Node',
    properties: {mode: 'no_properties'}}]},
], edges: ['E', 'F'].map((name, index) => ({name, from: ['e', 'f'][index],
  key: ['edge_key'], source: {definition: 'N', key: ['src']},
  target: {definition: 'N', key: ['dst']}, labels: [{name: 'R',
    properties: {mode: 'no_properties'}}]}))};
const definitionMapping = {...mapping,
  nodes: mapping.nodes.map(({from, ...body}, index) => ({...body, input_occurrence: index})),
  edges: mapping.edges.map(({from, ...body}, index) => ({...body, input_occurrence: index + 1})),
};
const witness = {body: {values: {
  schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
  rows: [{aql_source_free_unit: true}],
}}, dependencies: []};
// FROM-less SELECT: one witness, a derive of the authored literals, then
// the declared projection. These are definitions, not fetched input bytes.
const literalDefinition = row => {
  const producer = {body: {derive: Object.fromEntries(Object.values(row)
    .map((value, index) => ['aql_query_expr_' + index, {literal: value}]))},
  dependencies: [witness]};
  return {body: {select: Object.keys(row).map((name, index) =>
    ({[name]: 'aql_query_expr_' + index}))}, dependencies: [producer]};
};
const domain = producers => cid({constructor: definitionMapping,
  producer_definitions: producers, version: 'actql-property-graph-definition/0.1'});
const sourceDomain = domain(values.map(value => literalDefinition(value.rows[0])));
const jsonDomain = domain(values.map(value => ({body: {values: value}, dependencies: []})));
const identity = (domain, definition, key) =>
  ({definition, domain, key: [key], key_types: [{kind: 'number'}]});
const paths = (domain, sequences) => sequences.map(sequence => ({
  start_id: identity(domain, 'N', 1), end_id: identity(domain, 'N', 1),
  hop_count: sequence.length,
  node_ids: Array.from({length: sequence.length + 1}, () => identity(domain, 'N', 1)),
  edge_ids: sequence.map(index => identity(domain, ['E', 'F'][index], [10, 11][index])),
}));
// Two distinct parallel self-loops. WALK permits four length-two sequences;
// TRAIL permits the two permutations; ACYCLIC permits only the zero-hop path.
const walk = [[0, 0], [0, 1], [1, 0], [1, 1]];
const trail = [[0, 1], [1, 0]];
const source = 'DATA n = SELECT 1 AS node_key; ' +
  'DATA e = SELECT 10 AS edge_key, 1 AS src, 1 AS dst; ' +
  'DATA f = SELECT 11 AS edge_key, 1 AS src, 1 AS dst; ' +
  'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) ' +
  'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES, ' +
  'f AS F KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); ';
const seeds = 'DATA seeds = FROM g |> node_rows() |> SELECT id AS element; ';
// The union must execute the actual shared boundary, not merely its two
// component corpora. Match returns the same admitted identity to the existing
// Relation selector; neither the match nor traversal changes the Graph domain.
const matchedSeeds = seeds.replace('node_rows()',
  "match_nodes(definition: 'N', bindings: {identity: 'id'}, where: {literal: true}, fields: ['id'])");
const call = (mode = 'trail', minimum = 2, maximum = 2) =>
  "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: " + minimum +
  ', max_hops: ' + maximum + ", path_mode: '" + mode + "', emit: 'paths', max_output_rows: 10)";
const tail = ' |> SELECT ' + fields.join(', ') + ' |> RESULT paths';
const results = (domain, sequences) => ({paths: {columns, rows: paths(domain, sequences),
  // No SQL ORDER BY is invented. Compare the full path Relation as a multiset,
  // preserving both multiplicity and the order of identities within each path.
  unordered: true}});
const control = JSON.stringify({version: 'actql/0.1', id: 'fixture.traverse_paths',
  stages: [{id: 'main', inputs: {}, steps: [
    ...values.map((value, index) => ({values: value, as: ['n', 'e', 'f'][index]})),
    {property_graph: mapping, as: 'g'},
    {from: 'g', node_rows: true, as: 'nodes'},
    {from: 'nodes', select: [{element: 'id'}], as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'element'}, direction: 'out',
      min_hops: 2, max_hops: 2, path_mode: 'trail', emit: 'paths', max_output_rows: 10}, as: 'visited'},
    {from: 'visited', select: fields, as: 'output'},
  ], results: {out: {from: 'output', fields}}}],
  results: {paths: {from: {stage: 'main', result: 'out'}}}});
export const graphTraversePathSuccesses = [
  {name: 'graph-traverse-paths-json-control', format: 'json', text: control,
    results: results(jsonDomain, trail), sourceReadCount: 0},
  {name: 'graph-traverse-paths-named-match-selector', format: 'aql-text',
    text: source + matchedSeeds + 'FROM g |> ' + call() + tail,
    results: results(sourceDomain, trail), sourceReadCount: 0},
  ...[['walk', 2, walk], ['trail', 2, trail], ['acyclic', 0, [[]]], ['acyclic', 1, []]]
    .map(([mode, minimum, sequences]) => ({
      name: 'graph-traverse-paths-' + mode + '-' + minimum, format: 'aql-text',
      text: source + seeds + 'FROM g |> ' + call(mode, minimum) + tail,
      results: results(sourceDomain, sequences), sourceReadCount: 0,
    })),
  {name: 'graph-traverse-paths-quoted-data-reordered-columns', format: 'aql-text',
    text: source + seeds.replace('seeds', '`seed set`') + 'DATA visited = FROM g |> ' +
      call().replace('from: seeds', 'from: `seed set`') + '; FROM visited' +
      ' |> WHERE hop_count > 1 |> SELECT edge_ids, node_ids, hop_count |> ORDER BY hop_count |> RESULT paths',
    results: {paths: {columns: [columns[4], columns[3], columns[2]],
      rows: paths(sourceDomain, trail).map(({edge_ids, node_ids, hop_count}) =>
        ({edge_ids, node_ids, hop_count})), unordered: true}}, sourceReadCount: 0},
  {name: 'graph-traverse-paths-empty-selector', format: 'aql-text',
    text: source + seeds.replace('SELECT id AS element', 'WHERE node_key > 1 |> SELECT id AS element') +
      'FROM g |> ' + call() + tail, results: results(sourceDomain, []), sourceReadCount: 0},
  {name: 'graph-traverse-paths-ordered-hops-empty-label-set', format: 'aql-text',
    text: source + seeds + 'FROM g |> ' +
      "traverse(start: {from: seeds, id: 'element'}, hops: [{direction: 'out', edge_types: []}], path_mode: 'walk', emit: 'paths')" + tail,
    results: results(sourceDomain, []), sourceReadCount: 0},
];
export const graphTraversePathRefusals = [
  ['unknown-selector', call().replace('from: seeds', 'from: missing')],
  ['string-selector-reference', call().replace('from: seeds', "from: 'seeds'")],
  ['missing-selector-column', call().replace("id: 'element'", "id: 'missing'")],
  ['missing-emission', call().replace(", emit: 'paths'", '')],
  ['unknown-emission', call().replace("emit: 'paths'", "emit: 'invented'")],
  ['parameter-emission', call().replace("emit: 'paths'", 'emit: @emission')],
  ['invalid-hop-bound', call().replace('max_hops: 2', 'max_hops: 1')],
  ['invalid-path-mode', call().replace("'trail'", "'invented'")],
  ['extra-argument', call().replace('max_output_rows: 10', 'max_output_rows: 10, extra: true')],
].map(([name, operation]) => ({name: 'graph-traverse-paths-' + name, format: 'aql-text',
  text: source + seeds + 'FROM g |> ' + operation + tail}));
for (const name of ['depth', 'node_id']) graphTraversePathRefusals.push({
  name: 'graph-traverse-paths-node-field-' + name, format: 'aql-text',
  text: source + seeds + 'FROM g |> ' + call() + ' |> SELECT ' + name + ' |> RESULT paths',
});
graphTraversePathRefusals.push(...[
  ['matched-missing-selector-column', call().replace("id: 'element'", "id: 'missing'") + tail],
  ['matched-node-only-output', call() + ' |> SELECT depth |> RESULT paths'],
].map(([name, suffix]) => ({name: 'graph-traverse-paths-' + name,
  format: 'aql-text', text: source + matchedSeeds + 'FROM g |> ' + suffix})));
