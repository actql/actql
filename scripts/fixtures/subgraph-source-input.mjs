// Independent logical Programs and literal rows/contracts. This fixture neither
// compiles source nor patches a generated Program or samples an output schema.
import {createHash} from 'node:crypto';
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const nodeColumns = [{name: 'node_key', contract: number},
  {name: 'p', contract: nullableNumber}];
const edgeColumns = [{name: 'edge_key', contract: number}, {name: 'w', contract: number}];
const properties = names => ({mode: 'columns', columns: names.map(name => ({from: name, to: name}))});
const nodes = [{node_key: 3, p: null}, {node_key: 2, p: 20}, {node_key: 1, p: 10}];
const edges = [
  {edge_key: 11, src_key: 1, dst_key: 2, w: 20},
  {edge_key: 10, src_key: 1, dst_key: 2, w: 10},
  {edge_key: 12, src_key: 2, dst_key: 3, w: 40},
  {edge_key: 13, src_key: 2, dst_key: 2, w: 30},
];
const constructor = {version: 'actql-property-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'],
    labels: [{name: 'Node', properties: properties(['p'])}]}],
  edges: [{name: 'E', from: 'e', key: ['edge_key'],
    source: {definition: 'N', key: ['src_key']},
    target: {definition: 'N', key: ['dst_key']},
    labels: [{name: 'R', properties: properties(['w'])}]}]};
const construction = [
  {values: {schema: {node_key: number, p: nullableNumber}, rows: nodes}, as: 'n'},
  {values: {schema: Object.fromEntries(['edge_key', 'src_key', 'dst_key', 'w']
    .map(name => [name, number])), rows: edges}, as: 'e'},
  {property_graph: constructor, as: 'g'},
];
const program = (edgeOutput, edgePredicate) => {
  const fields = edgeOutput ? ['edge_key', 'w'] : ['node_key', 'p'];
  return JSON.stringify({version: 'actql/0.1', id: 'fixture.subgraph',
    stages: [{id: 'main', inputs: {}, steps: [...construction,
      {from: 'g', node_rows: true, as: 'all_nodes'},
      {from: 'all_nodes', filter: {lte: [{field: 'node_key'}, {literal: 2}]}},
      {select: ['id'], as: 'selected'},
      {from: 'g', subgraph: {nodes: {from: 'selected', id: 'id'},
        ...(edgePredicate ? {edges: {gt: [{field: 'w'}, {literal: 10}]}} : {})}, as: 'slice'},
      {from: 'slice', [edgeOutput ? 'edge_rows' : 'node_rows']: true, as: 'rows'},
      {from: 'rows', select: fields},
      {sort: [{field: fields[0], dir: 'asc', nulls: 'first'}], as: 'published'},
    ], results: {out: {from: 'published', fields}}}],
    results: {answer: {from: {stage: 'main', result: 'out'}}}});
};
// The selected Host profile allows 32 physical tasks. Keep each source case
// bounded without raising that limit; the larger original source is retained
// as a TaskLimit refusal, rather than silently presented as an execution pass.
const prefix = 'DATA n = SELECT 2 AS node_key, 20 AS p ' +
  'UNION ALL SELECT 1 AS node_key, IF(TRUE, 10, CAST(NULL AS FLOAT64)) AS p; ' +
  'DATA e = SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 20 AS w ' +
  'UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key, 10 AS w ' +
  'UNION ALL SELECT 13 AS edge_key, 2 AS src_key, 2 AS dst_key, 30 AS w; ' +
  'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) ' +
  'EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N ' +
  'DESTINATION KEY (dst_key) REFERENCES N LABEL R PROPERTIES (w))); ';
const selected = predicate => 'DATA selected = FROM g |> node_rows() |> WHERE ' +
  predicate + ' |> SELECT id; ';
const tail = edgeOutput => ' |> ' + (edgeOutput ? 'edge_rows() |> SELECT edge_key, w |> ORDER BY edge_key'
  : 'node_rows() |> SELECT node_key, p |> ORDER BY node_key') + ' |> RESULT answer';
const result = (edgeOutput, rows) => ({answer: {rows, columns: edgeOutput ? edgeColumns : nodeColumns}});
const nodeSubset = [{node_key: 1, p: 10}, {node_key: 2, p: 20}];
const inducedEdges = [{edge_key: 10, w: 10}, {edge_key: 11, w: 20}, {edge_key: 13, w: 30}];
const filteredEdges = [{edge_key: 11, w: 20}, {edge_key: 13, w: 30}];
const textCase = (name, body, edgeOutput, rows, extra = {}) => ({
  name: 'subgraph-' + name, format: 'aql-text', text: prefix + body,
  results: result(edgeOutput, rows), sourceReadCount: 0, ...extra,
});
// A valid explicit identity is derived from an independently authored admitted
// definition/producer preimage, never from a returned Graph row or compiler.
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const singleConstructor = {version: 'actql-property-graph-constructor/0.1',
  nodes: [{name: 'N', input_occurrence: 0, key: ['node_key'],
    labels: [{name: 'Node', properties: properties(['p'])}]}], edges: []};
const singleProducer = {body: {select: [{node_key: 'aql_query_expr_0'}, {p: 'aql_query_expr_1'}]},
  dependencies: [{body: {derive: {aql_query_expr_0: {literal: 1}, aql_query_expr_1: {literal: 7}}},
    dependencies: [{body: {values: {schema: {aql_source_free_unit: {type: 'boolean', nullable: false}},
      rows: [{aql_source_free_unit: true}]}}, dependencies: []}]}]};
const singleDomain = 'sha256:' + createHash('sha256').update(canonical({
  constructor: singleConstructor, producer_definitions: [singleProducer],
  version: 'actql-property-graph-definition/0.1'})).digest('hex');
const singleIdentity = {definition: 'N', domain: singleDomain, key: [1], key_types: [{kind: 'number'}]};
const taskBoundSource = prefix
  .replace('SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, IF(TRUE, 10, CAST(NULL AS FLOAT64)) AS p',
    'SELECT 3 AS node_key, CAST(NULL AS FLOAT64) AS p UNION ALL SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, 10 AS p')
  .replace('UNION ALL SELECT 13 AS edge_key',
    'UNION ALL SELECT 12 AS edge_key, 2 AS src_key, 3 AS dst_key, 40 AS w UNION ALL SELECT 13 AS edge_key');
export const subgraphSourceSuccesses = [
  {name: 'subgraph-json-nodes', format: 'json', text: program(false, false),
    results: result(false, nodeSubset), sourceReadCount: 0},
  {name: 'subgraph-json-filtered-edges', format: 'json', text: program(true, true),
    results: result(true, filteredEdges), sourceReadCount: 0},
  textCase('inline-node-subset', selected('node_key <= 2') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(false), false, nodeSubset),
  textCase('parallel-and-induced-edges', selected('node_key <= 2') +
    'DATA slice = FROM g |> subgraph(nodes: {from: selected, id: "id"}); FROM slice' + tail(true),
    true, inducedEdges),
  textCase('quoted-data-normalized-edge-predicate', selected('node_key <= 2') +
    'DATA `chosen ids` = FROM selected; DATA `slice` = FROM g |> normalize_graph() ' +
    '|> subgraph(nodes: {from: `chosen ids`, id: "id"}, edges: {gt: [{field: "w"}, {literal: 10}]}); FROM `slice`' + tail(true),
    true, filteredEdges),
  textCase('nullable-property', selected('node_key >= 2') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(false),
    false, [{node_key: 2, p: 20}, {node_key: 3, p: null}], {
      text: prefix.replace('SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, IF(TRUE, 10, CAST(NULL AS FLOAT64)) AS p',
        'SELECT 3 AS node_key, CAST(NULL AS FLOAT64) AS p UNION ALL SELECT 2 AS node_key, 20 AS p') +
        selected('node_key >= 2') + 'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(false),
    }),
  {...textCase('match-label-after-selection', selected('node_key <= 2') +
    'FROM GRAPH g |> subgraph(nodes: {from: selected, id: "id"}) |> MATCH WALK (a:Node) ' +
    '|> SELECT a.p AS p |> ORDER BY p |> RESULT answer', false, nodeSubset),
    results: {answer: {rows: [{p: 10}, {p: 20}], columns: [{name: 'p', contract: nullableNumber}]}}},
  textCase('empty-typed-nodes', selected('FALSE') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(false), false, []),
  textCase('empty-typed-edges', selected('FALSE') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(true), true, []),
  textCase('induction-excludes-missing-endpoint', selected('node_key = 2') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(true),
    true, [{edge_key: 13, w: 30}]),
  textCase('edge-predicate-parameter', selected('node_key <= 2') +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"}, edges: {gt: [{field: "w"}, @minimum]})' + tail(true),
    true, filteredEdges, {parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 10}}),
  textCase('duplicate-selector-identities', selected('node_key <= 2').replace('selected', 'chosen') +
    'DATA selected = SELECT id FROM chosen UNION ALL SELECT id FROM chosen; ' +
    'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(true),
    true, [{edge_key: 10, w: 10}, {edge_key: 11, w: 20}], {
      text: prefix.replace('UNION ALL SELECT 13 AS edge_key, 2 AS src_key, 2 AS dst_key, 30 AS w; ', '; ') +
        selected('node_key <= 2').replace('selected', 'chosen') +
        'DATA selected = SELECT id FROM chosen UNION ALL SELECT id FROM chosen; ' +
        'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(true),
    }),
  {name: 'subgraph-explicit-typed-identity', format: 'aql-text',
    text: 'DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH ' +
      '(NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))); ' +
      'FROM g |> subgraph(nodes: {ids: [' + JSON.stringify(singleIdentity) + ']})' + tail(false),
    results: {answer: {rows: [{node_key: 1, p: 7}], columns:
      [{name: 'node_key', contract: number}, {name: 'p', contract: number}]}}, sourceReadCount: 0},
];
export const subgraphSourceRefusals = [
  ...[
    ['missing-nodes', 'subgraph()'],
    ['empty-explicit-ids', 'subgraph(nodes: {ids: []})'],
    ['missing-column', 'subgraph(nodes: {from: selected, id: "missing"})'],
    ['wrong-key-type', 'subgraph(nodes: {from: selected, id: "node_key"})'],
    ['unknown-producer', 'subgraph(nodes: {from: missing, id: "id"})'],
    ['string-producer', 'subgraph(nodes: {from: "selected", id: "id"})'],
    ['graph-as-relation', 'subgraph(nodes: {from: g, id: "id"})'],
    ['nonboolean-edge-predicate', 'subgraph(nodes: {from: selected, id: "id"}, edges: {literal: 1})'],
    ['missing-edge-property', 'subgraph(nodes: {from: selected, id: "id"}, edges: {field: "missing"})'],
    ['extra-argument', 'subgraph(nodes: {from: selected, id: "id"}, extra: true)'],
    // This is an existing common support gap, not a permanent language limit.
    ['common-where-selector-gap', 'subgraph(nodes: {where: {literal: true}})'],
  ].map(([name, call]) => ({name: 'subgraph-' + name, format: 'aql-text',
    text: prefix + 'DATA selected = FROM g |> node_rows() |> SELECT id, node_key; FROM g |> ' + call + tail(false)})),
  {name: 'subgraph-forward-selector', format: 'aql-text', text: prefix +
    'DATA slice = FROM g |> subgraph(nodes: {from: later, id: "id"}); DATA later = FROM g |> node_rows(); FROM slice' + tail(false)},
  {name: 'subgraph-after-relation-transition', format: 'aql-text', text: prefix +
    'FROM g |> node_rows() |> subgraph(nodes: {ids: []}) |> SELECT node_key |> RESULT answer'},
  // Semantic checking succeeds; the installed task profile refuses this
  // unchanged larger source with TaskLimit before durable Run admission.
  {name: 'subgraph-task-profile-bound', format: 'aql-text', text: taskBoundSource +
    selected('node_key <= 2') + 'FROM g |> subgraph(nodes: {from: selected, id: "id"})' + tail(false)},
  // literal is opaque data, not a wrapper that evaluates parameter syntax.
  {name: 'subgraph-object-literal-is-not-scalar-parameter', format: 'aql-text',
    text: prefix + selected('node_key <= 2') +
      'FROM g |> subgraph(nodes: {from: selected, id: "id"}, edges: {gt: [{field: "w"}, {literal: @minimum}]})' + tail(true),
    parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 10}},
];
const collidingControl = JSON.parse(program(false, false));
collidingControl.stages[0].steps[2].property_graph.nodes[0].labels[0].properties =
  properties(['node_key', 'p']);
subgraphSourceRefusals.push({name: 'subgraph-key-property-row-collision', format: 'json',
  text: JSON.stringify(collidingControl)});
// Membership is data-dependent. The common identity admission may accept JSON,
// but no node has this scalar identity; execution must fail without a Result.
export const subgraphSourceExecutionFailures = [{
  name: 'subgraph-missing-explicit-identity', format: 'aql-text', text: prefix +
    'FROM g |> subgraph(nodes: {ids: [1]})' + tail(false),
  resultNames: ['answer'], sourceReadSessionCount: 0,
}];
