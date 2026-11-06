// Independent Graph->Relation->JOIN fixtures: no lowerer calls or Program patching.
const number = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const nodeBinding = 'WITH n AS (SELECT 2 AS node_key, 8 AS p UNION ALL SELECT 1 AS node_key, 7 AS p)';
const rightBinding = ', r AS (SELECT 1 AS key, 10 AS tag UNION ALL SELECT 1 AS key, 20 AS tag UNION ALL SELECT 2 AS key, 30 AS tag)';
const mapping = ', g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))) ';
const nodePrefix = nodeBinding + rightBinding + mapping;
const tail = ' |> AS l |> JOIN r AS rr ON l.node_key = rr.key MAX_OUTPUT_ROWS 10 |> SELECT l.node_key AS node, rr.tag AS tag |> ORDER BY node, tag';
const expected = [{node: 1, tag: 10}, {node: 1, tag: 20}, {node: 2, tag: 30}];
const columns = [number('node'), number('tag')];
const success = (name, text, rows = expected, schema = columns, extra = {}) => ({
  name: 'graph-rows-join-' + name, format: 'aql-text', text, expected: rows, columns: schema,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const constructor = {version: 'actql-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'nodes', key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}]}], edges: []};
const nodes = {schema: {node_key: {type: 'number', nullable: false}, p: {type: 'number', nullable: false}}, rows: [{node_key: 2, p: 8}, {node_key: 1, p: 7}]};
const rights = {schema: {key: {type: 'number', nullable: false}, tag: {type: 'number', nullable: false}}, rows: [{key: 1, tag: 10}, {key: 1, tag: 20}, {key: 2, tag: 30}]};
function program(name, steps, fields) {
  return JSON.stringify({version: 'actql/0.1', id: 'fixture.graph_rows_join_' + name,
    stages: [{id: 'main', inputs: {}, steps, results: {rows: {from: 'selected', fields}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}});
}
const nodeSteps = [{values: nodes, as: 'nodes'}, {values: rights, as: 'rights'}, {graph: constructor, as: 'g'},
  {from: 'g', node_rows: {definition: 'N'}, as: 'row_input'},
  {from: 'row_input', join: {with: 'rights', kind: 'inner', on: [{left: 'node_key', right: 'key'}], max_output_rows: 10, select: {node: 'left.node_key', tag: 'right.tag'}}, as: 'joined'},
  {from: 'joined', sort: [{field: 'node', dir: 'asc', nulls: 'first'}, {field: 'tag', dir: 'asc', nulls: 'first'}], as: 'selected'}];
export const graphRowsJoinSuccesses = [
  success('node-json', program('node', nodeSteps, ['node', 'tag']), expected, columns, {format: 'json'}),
  success('node-prefix', nodePrefix + "FROM g |> node_rows(definition: 'N')" + tail),
  success('node-projected', nodePrefix + 'FROM g |> node_rows() |> SELECT node_key' + tail),
  success('node-cte', nodePrefix + ", picked AS (FROM g |> node_rows(definition: 'N') |> SELECT node_key) SELECT l.node_key AS node, rr.tag AS tag FROM picked AS l JOIN r AS rr ON l.node_key = rr.key MAX_OUTPUT_ROWS 10 ORDER BY node, tag"),
  success('node-filter-limit', nodePrefix + 'FROM g |> node_rows() |> WHERE node_key = 1' + tail + ' |> LIMIT 1', [{node: 1, tag: 10}]),
  success('node-empty', nodeBinding.replace('SELECT 2 AS node_key, 8 AS p UNION ALL SELECT 1 AS node_key, 7 AS p', 'SELECT 1 AS node_key, 7 AS p WHERE FALSE') + rightBinding + mapping + 'FROM g |> node_rows()' + tail, []),
];
const edgeBinding = 'WITH n AS (SELECT 1 AS node_key), e AS (SELECT 11 AS edge_key, 1 AS src_key, 1 AS dst_key UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 1 AS dst_key)';
const edgeRight = ', r AS (SELECT 10 AS key, 10 AS tag UNION ALL SELECT 10 AS key, 20 AS tag UNION ALL SELECT 11 AS key, 30 AS tag)';
const edgeMapping = ', g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES))) ';
const edgeSteps = [{values: {schema: {node_key: {type: 'number', nullable: false}}, rows: [{node_key: 1}]}, as: 'nodes'},
  {values: {schema: {edge_key: {type: 'number', nullable: false}, src_key: {type: 'number', nullable: false}, dst_key: {type: 'number', nullable: false}}, rows: [{edge_key: 11, src_key: 1, dst_key: 1}, {edge_key: 10, src_key: 1, dst_key: 1}]}, as: 'edges'},
  {values: {...rights, rows: [{key: 10, tag: 10}, {key: 10, tag: 20}, {key: 11, tag: 30}]}, as: 'rights'},
  {graph: {version: 'actql-graph-constructor/0.1', nodes: [{name: 'N', from: 'nodes', key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'no_properties'}}]}],
    edges: [{name: 'E', from: 'edges', key: ['edge_key'], source: {definition: 'N', key: ['src_key']}, target: {definition: 'N', key: ['dst_key']}, labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]}, as: 'g'},
  {from: 'g', edge_rows: {definition: 'E'}, as: 'row_input'},
  {from: 'row_input', join: {with: 'rights', kind: 'inner', on: [{left: 'edge_key', right: 'key'}], max_output_rows: 10, select: {edge: 'left.edge_key', tag: 'right.tag'}}, as: 'joined'},
  {from: 'joined', sort: [{field: 'edge', dir: 'asc', nulls: 'first'}, {field: 'tag', dir: 'asc', nulls: 'first'}], as: 'selected'}];
const edgeExpected = [{edge: 10, tag: 10}, {edge: 10, tag: 20}, {edge: 11, tag: 30}];
graphRowsJoinSuccesses.push(
  success('edge-json', program('edge', edgeSteps, ['edge', 'tag']), edgeExpected, [number('edge'), number('tag')], {format: 'json'}),
  success('edge-prefix', edgeBinding + edgeRight + edgeMapping + "FROM g |> edge_rows(definition: 'E') |> AS l |> JOIN r AS rr ON l.edge_key = rr.key MAX_OUTPUT_ROWS 10 |> SELECT l.edge_key AS edge, rr.tag AS tag |> ORDER BY edge, tag", edgeExpected, [number('edge'), number('tag')]),
);
export const graphRowsJoinRefusals = [
  ['removed-column', nodePrefix + 'FROM g |> node_rows() |> SELECT node_key |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l.p'],
  ['removed-range', nodePrefix + 'FROM g |> node_rows() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT g.node_key'],
  ['shadowed-graph', nodePrefix + ', probe AS (WITH g AS (SELECT 1 AS id) FROM g |> node_rows() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l.node_key) FROM probe'],
  ['graph-returning-input', nodePrefix + 'FROM g |> normalize_graph() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT rr.tag'],
  ['invalid-bound', nodePrefix + 'FROM g |> node_rows() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 0 |> SELECT rr.tag'],
].map(([name, text]) => ({name: 'graph-rows-join-' + name, format: 'aql-text', text,
  // A Relation shadow cannot supply the common Graph Bridge's required Carrier.
  ...(name === 'shadowed-graph' ? {expectedCode: 'ClientProgramInvalidInput'} : {}),
}));
export const graphRowsJoinExecutionFailures = [{name: 'graph-rows-join-explicit-bound-exceeded', format: 'aql-text',
  text: nodePrefix + 'FROM g |> node_rows()' + tail.replace('MAX_OUTPUT_ROWS 10', 'MAX_OUTPUT_ROWS 2'),
  resultNames: ['main'], sourceReadSessionCount: 0}];

const sourceRows = [{id: 2, amount: 20}, {id: 1, amount: 10}, {id: 3, amount: null}];
const sourcePrefix = 'WITH n AS (FROM records |> SELECT id AS node_key, amount AS p), r AS (FROM records |> WHERE id = 1 |> SELECT id AS key, amount AS tag)' + mapping;
const sourceTail = 'FROM g |> node_rows() |> AS l |> JOIN r AS rr ON l.node_key = rr.key MAX_OUTPUT_ROWS 10 |> SELECT l.node_key AS node, rr.tag AS tag, l.p AS value |> ORDER BY node, tag';
const capturedControl = {version: 'actql/0.1', id: 'fixture.graph_rows_join_capture', stages: [
  {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}}, steps: [
    {from: 'records', select: [{node_key: 'id'}, {p: 'amount'}], as: 'nodes'},
    {from: 'records', filter: {eq: [{field: 'id'}, {literal: 1}]}},
    {select: [{key: 'id'}, {tag: 'amount'}], as: 'rights'},
    {graph: constructor, as: 'g'}, {from: 'g', node_rows: true, as: 'row_input'},
    {from: 'row_input', join: {with: 'rights', kind: 'inner', on: [{left: 'node_key', right: 'key'}], max_output_rows: 10,
      select: {node: 'left.node_key', tag: 'right.tag', value: 'left.p'}}, as: 'joined'},
    {from: 'joined', sort: [{field: 'node', dir: 'asc', nulls: 'first'}, {field: 'tag', dir: 'asc', nulls: 'first'}], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['node', 'tag', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const capturedExpected = [{node: 1, tag: 10, value: 10}];
const capturedColumns = [number('node'), number('tag', true), number('value', true)];
const captured = {sourceRows, sourceReadCount: 1, sourceReadSessionCount: 1};
graphRowsJoinSuccesses.push(
  success('shared-source-json', JSON.stringify(capturedControl), capturedExpected, capturedColumns, {format: 'json', ...captured}),
  success('shared-source-text', sourcePrefix + sourceTail, capturedExpected, capturedColumns, captured),
);
