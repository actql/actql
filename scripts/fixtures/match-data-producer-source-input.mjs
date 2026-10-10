// Complete source inputs and independent ordinary Program controls. Neither
// lowering nor the evaluator supplies expected rows, types or column order.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const columns = [{name: 'value', contract: nullableNumber}, {name: 'key', contract: number}];
const rows = [{value: null, key: 1}, {value: 7, key: 2}];
const mapping = {version: 'actql-graph-constructor/0.1', nodes: [{name: 'N', from: 'n',
  key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'columns',
    columns: [{from: 'p', to: 'p'}, {from: 'node_key', to: 'node_key'}]}}]}], edges: []};
const data = 'DATA n = SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p; ';
const constructor = 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p, node_key))); ';
const prefix = data + constructor;
const match = 'FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value, a.node_key AS key';
const binding = 'DATA chosen = ' + match + '; ';
const tail = 'FROM chosen |> WHERE key > 0 |> SELECT value, key |> ORDER BY key |> RESULT matched';
const result = (expectedRows = rows, expectedColumns = columns) => ({matched: {rows: expectedRows, columns: expectedColumns}});
const program = (id, steps, fields = ['value', 'key']) => ({version: 'actql/0.1', id,
  stages: [{id: 'main', inputs: {}, steps, results: {out: {from: 'output', fields}}}],
  results: {matched: {from: {stage: 'main', result: 'out'}}}});
const control = program('fixture.match_data.nodes', [
  {values: {schema: {node_key: number, p: nullableNumber}, rows: [{node_key: 2, p: 7}, {node_key: 1, p: null}]}, as: 'n'},
  {graph: mapping, as: 'g'},
  {from: 'g', match_nodes: {definition: 'N', label: 'Node', where: {literal: true}, fields: ['p', 'node_key']}, as: 'matched'},
  {from: 'matched', select: [{value: 'p'}, {key: 'node_key'}], as: 'chosen'},
  {from: 'chosen', filter: {gt: [{field: 'key'}, {literal: 0}]}},
  {select: ['value', 'key']},
  {sort: [{field: 'key', dir: 'asc', nulls: 'first'}], as: 'output'},
]);
const empty = structuredClone(control);
empty.id = 'fixture.match_data.empty';
empty.stages[0].steps[2].match_nodes.where = {gt: [{field: 'node_key'}, {literal: 9}]};
const quote = String.fromCharCode(96);
const sourceCase = (name, text, results = result(), sourceReadCount = 0) => ({
  name: 'match-data-' + name, format: 'aql-text', text, results, sourceReadCount,
});
const jsonCase = (name, value, results) => ({name: 'match-data-' + name,
  format: 'json', text: JSON.stringify(value), results, sourceReadCount: 0});

const pathPrefix = 'DATA n = SELECT 1 AS node_key; '
  + 'DATA e = SELECT 11 AS edge_key, 1 AS src, 1 AS dst UNION ALL SELECT 10 AS edge_key, 1 AS src, 1 AS dst; '
  + 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) '
  + 'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); ';
const pathResult = result([{value: 2}, {value: 2}], [{name: 'value', contract: number}]);
const pathControl = program('fixture.match_data.trail', [
  {values: {schema: {node_key: number}, rows: [{node_key: 1}]}, as: 'n'},
  {values: {schema: {edge_key: number, src: number, dst: number}, rows: [
    {edge_key: 11, src: 1, dst: 1}, {edge_key: 10, src: 1, dst: 1}]}, as: 'e'},
  {graph: {version: 'actql-graph-constructor/0.1', nodes: [{name: 'N', from: 'n', key: ['node_key'],
    labels: [{name: 'Node', properties: {mode: 'no_properties'}}]}], edges: [{name: 'E', from: 'e', key: ['edge_key'],
    source: {definition: 'N', key: ['src'], references_key: ['node_key']},
    target: {definition: 'N', key: ['dst'], references_key: ['node_key']},
    labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]}, as: 'g'},
  {from: 'g', match_nodes: {definition: 'N', label: 'Node', where: {literal: true},
    bindings: {identity: 'element'}, fields: ['element']}, as: 'seeds'},
  {from: 'g', traverse: {start: {from: 'seeds', id: 'element'}, direction: 'out',
    min_hops: 2, max_hops: 2, edge_types: ['R'], path_mode: 'trail', emit: 'paths'}, as: 'paths'},
  {from: 'paths', select: [{value: 'hop_count'}], as: 'chosen'},
  {from: 'chosen', filter: {gt: [{field: 'value'}, {literal: 1}]}},
  {select: ['value']},
  {sort: [{field: 'value', dir: 'asc', nulls: 'first'}], as: 'output'},
], ['value']);
const acquiredResult = {original: {rows: [{value: 20, key: 2}], columns},
  matched: {rows: [{value: 20, key: 2}], columns}};
const acquiredControl = structuredClone(control);
acquiredControl.id = 'fixture.match_data.reused';
acquiredControl.stages[0].steps[0].values.rows = [{node_key: 2, p: 20}];
acquiredControl.stages[0].results.original = {from: 'chosen', fields: ['value', 'key']};
acquiredControl.results.original = {from: {stage: 'main', result: 'original'}};

export const matchDataProducerSuccesses = [
  jsonCase('nodes-json', control, result()),
  sourceCase('nodes-source', prefix + binding + tail),
  jsonCase('empty-json', empty, result([])),
  sourceCase('empty-source', prefix + binding.replace('(a:Node)', '(a:Node WHERE node_key > 9)') + tail, result([])),
  sourceCase('quoted-relation-star', prefix + binding.replace('chosen', quote + 'picked rows' + quote)
    + 'FROM ' + quote + 'picked rows' + quote + ' |> SELECT * |> ORDER BY key |> RESULT matched'),
  sourceCase('normalized-graph', prefix + binding.replace('g |> MATCH', 'g |> normalize_graph() |> MATCH') + tail),
  jsonCase('parallel-trail-json', pathControl, pathResult),
  sourceCase('parallel-trail-source', pathPrefix
    + 'DATA chosen = FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->{2,2}(:Node) |> SELECT PATH_LENGTH(p) AS value; '
    + 'FROM chosen |> WHERE value > 1 |> SELECT value |> ORDER BY value |> RESULT matched', pathResult),
  jsonCase('reused-json', acquiredControl, acquiredResult),
  // Native acquisition owns validation_scan and native_result in one read
  // session. Neither Result access nor resubmission may create another.
  {...sourceCase('acquired-reused-source', 'DATA n = FROM records |> WHERE id = 2 |> SELECT id AS node_key, amount AS p; '
    + constructor + binding + 'FROM chosen |> RESULT original |> WHERE key > 0 |> SELECT value, key |> ORDER BY key |> RESULT matched', acquiredResult, 2), sourceReadSessionCount: 1},
];
const refusal = (name, text, expectedCode = 'ClientProgramInvalidInput') => ({
  name: 'match-data-invalid-' + name, format: 'aql-text', text: prefix + text, expectedCode,
});
export const matchDataProducerRefusals = [
  refusal('removed-pattern-alias', binding + 'FROM chosen |> SELECT a.p'),
  refusal('removed-property', binding + 'FROM chosen |> SELECT p'),
  refusal('private-identity', binding + 'FROM chosen |> SELECT aql_keyed_identity_2'),
  refusal('implicit-elements', 'DATA chosen = FROM GRAPH g |> MATCH WALK (a:Node); FROM chosen', 'ClientProgramImplementationLimit'),
  refusal('graph-star', 'DATA chosen = FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT *; FROM chosen', 'ClientProgramImplementationLimit'),
  refusal('nested-result', 'DATA chosen = ' + match + ' |> RESULT hidden; FROM chosen', 'ClientProgramImplementationLimit'),
  refusal('duplicate-data-name', binding + binding + 'FROM chosen |> SELECT value'),
];
