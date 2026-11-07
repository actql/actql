// Authored existing Graph operation/JOIN contracts, not compiler output.
import {graphDifferenceSourceSuccesses} from './graph-difference-source-input.mjs';
const number = {type: 'number', nullable: false};
const columns = contract => [{name: 'value', contract}, {name: 'tag', contract: number}];
const rows = value => [{value, tag: 10}, {value, tag: 20}];
const property = [{name: 'Node', properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}];
const mapping = {version: 'actql-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'], labels: property}],
  edges: [{name: 'E', from: 'n', key: ['node_key'],
    source: {definition: 'N', key: ['node_key']}, target: {definition: 'N', key: ['node_key']},
    labels: [{name: 'R', properties: property[0].properties}]}]};
const source = 'WITH n AS (SELECT 1 AS node_key, 7 AS p) '
  + ', r AS (SELECT 20 AS tag UNION ALL SELECT 10 AS tag) '
  + ', g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) '
  + 'EDGE TABLES (n AS E KEY (node_key) SOURCE KEY (node_key) REFERENCES N '
  + 'DESTINATION KEY (node_key) REFERENCES N LABEL R PROPERTIES (p)))) ';
const tail = (field, bound = 10) => ' |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS ' + bound
  + ' |> SELECT l.' + field + ' AS value, rr.tag AS tag |> ORDER BY tag';
const operations = [
  ['degree', {direction: 'out'}, "direction: 'out'", 'degree', 1, number],
  ['components', {kind: 'weak', max_output_rows: 10}, "kind: 'weak', max_output_rows: 10", 'component_size', 1, number],
  ['graph_bounds', {max_nodes: 0}, 'max_nodes: 0', 'actual', 1, number],
  ['graphs_equal', {with: 'g'}, 'with: g', 'equal', true, {type: 'boolean', nullable: false}],
  ['match_nodes', {definition: 'N', where: {literal: true}, fields: ['p']},
    "definition: 'N', where: {literal: true}, fields: [p]", 'p', 7, number],
  ['match_edges', {definition: 'E', fields: ['p']}, "definition: 'E', fields: [p]", 'p', 7, number],
];
function control(operation, arguments_, field) {
  return JSON.stringify({version: 'actql/0.1', id: 'fixture.graph_relation_join',
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {node_key: number, p: number}, rows: [{node_key: 1, p: 7}]}, as: 'n'},
      {values: {schema: {tag: number}, rows: [{tag: 20}, {tag: 10}]}, as: 'r'},
      {graph: mapping, as: 'g'}, {from: 'g', [operation]: arguments_, as: 'stats'},
      {from: 'stats', cross_join: {with: 'r', max_output_rows: 10,
        select: {value: 'left.' + field, tag: 'right.tag'}}, as: 'joined'},
      {from: 'joined', sort: [{field: 'tag', dir: 'asc', nulls: 'first'}], as: 'sorted'},
    ], results: {out: {from: 'sorted', fields: ['value', 'tag']}}}],
    results: {answer: {from: {stage: 'main', result: 'out'}}}});
}
const success = (name, text, expected, contract = number, extra = {}) => ({
  name: 'graph-relation-join-' + name, format: 'aql-text', text, expected, columns: columns(contract),
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra});
export const graphRelationJoinSuccesses = operations.flatMap(([op, arguments_, text, field, value, contract]) => [
  success(op + '-json', control(op, arguments_, field), rows(value), contract, {format: 'json'}),
  success(op + '-text', source + 'FROM g |> ' + op + '(' + text + ')' + tail(field), rows(value), contract),
]);
graphRelationJoinSuccesses.push(
  success('normalized-degree', source + "FROM g |> normalize_graph() |> degree(direction: 'out')" + tail('degree'), rows(1)),
  success('parameter-bounds', source + 'FROM g |> graph_bounds(max_nodes: @p)' + tail('actual'), rows(1), number,
    {parameterDeclarations: {p: number}, parameters: {p: 0}}),
  success('empty-match', source + "FROM g |> match_nodes(definition: 'N', where: {gt: [{field: p}, {literal: 7}]}, fields: [p])"
    + tail('p'), []),
  success('degree-filter-limit', source + "FROM g |> degree(direction: 'out') |> WHERE degree = 1"
    + tail('degree') + ' |> LIMIT 1', [{value: 1, tag: 10}]),
);
// Reuse authored complete Delta oracles. JSON Values and text producers have
// different definition domains; their distinct identities remain independent.
for (const [name, format] of [['json-parallel-unchanged', 'json'], ['terminal-self', 'aql-text']]) {
  const existing = graphDifferenceSourceSuccesses.find(item => item.name === 'graph-difference-' + name);
  let text;
  if (format === 'json') {
    const program = JSON.parse(existing.text);
    program.stages[0].steps.push(
      {values: {schema: {tag: number}, rows: [{tag: 20}, {tag: 10}]}, as: 'r'},
      {from: 'projected', cross_join: {with: 'r', max_output_rows: 10,
        select: {value: 'left.delta', tag: 'right.tag'}}, as: 'joined'},
      {from: 'joined', sort: [{field: 'tag', dir: 'asc', nulls: 'first'}], as: 'sorted'},
    );
    program.stages[0].results.out = {from: 'sorted', fields: ['value', 'tag']};
    program.results = {answer: {from: {stage: 'main', result: 'out'}}};
    text = JSON.stringify(program);
  } else {
    text = existing.text.replace('FROM g |> graph_diff(with: g) |> SELECT delta |> RESULT changes',
      ', r AS (SELECT 20 AS tag UNION ALL SELECT 10 AS tag) FROM g |> graph_diff(with: g)' + tail('delta'));
  }
  graphRelationJoinSuccesses.push(success('graph_diff-' + format, text,
    rows(existing.results.changes.rows[0].delta), {type: 'json', nullable: false}, {format}));
}
export const graphRelationJoinRefusals = [
  ['removed-key', "degree(direction: 'out')" + tail('node_key')],
  ['components-field', "components(kind: 'weak', max_output_rows: 10)" + tail('degree')],
  ['removed-range', "degree(direction: 'out') |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT g.degree"],
  ['degree-direction', "degree(direction: 'invented')" + tail('degree')],
  ['components-kind', "components(kind: 'invented', max_output_rows: 10)" + tail('component_size')],
  ['negative-bound', 'graph_bounds(max_nodes: -1)' + tail('actual')],
  ['fractional-bound', 'graph_bounds(max_nodes: 0.5)' + tail('actual')],
  ['missing-property', "match_nodes(definition: 'N', fields: ['missing'])" + tail('missing')],
  ['invalid-join-bound', "degree(direction: 'out')" + tail('degree', 0)],
].map(([name, call]) => ({name: 'graph-relation-join-' + name, format: 'aql-text', text: source + 'FROM g |> ' + call}));
export const graphRelationJoinExecutionFailures = [{
  name: 'graph-relation-join-explicit-bound-exceeded', format: 'aql-text',
  text: source + "FROM g |> degree(direction: 'out')" + tail('degree', 1),
  resultNames: ['main'], sourceReadSessionCount: 0,
}];
