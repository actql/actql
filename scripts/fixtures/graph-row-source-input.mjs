// Authored source and JSON controls, with independent rows/contracts. This
// fixture never calls a compiler, samples a schema or patches a lowered Program.
const number = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const labels = {name: 'labels', contract: {type: 'array', nullable: false,
  items: {type: 'string', nullable: false}}};
const nodeColumns = [number('node_key'), number('p', true), labels];
const nodeResults = {nodes: {rows: [
  {node_key: 1, p: null, labels: ['Owner', 'Person']},
  {node_key: 2, p: 7, labels: ['Owner', 'Person']},
], columns: nodeColumns}};
const nodeData = 'DATA n = SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p; ';
const nodeMapping = 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p) LABEL Owner PROPERTIES (p))); ';
const nodeSource = nodeData + nodeMapping;
const edgeData = 'DATA n = SELECT 1 AS node_key; DATA e = SELECT 11 AS edge_key, 7 AS part, 1 AS src_key, 1 AS dst_key UNION ALL SELECT 10 AS edge_key, 7 AS part, 1 AS src_key, 1 AS dst_key; ';
const edgeMapping = 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES)); ';
const edgeResults = {edges: {rows: [
  {part: 7, edge_key: 10, labels: ['R']}, {part: 7, edge_key: 11, labels: ['R']},
], columns: [number('part'), number('edge_key'), labels]}};

// The machine controls intentionally use direct Values, while the source uses
// ordinary SELECT/UNION producers. Structure/CIDs can differ; meaning cannot.
const nodeDefinition = {name: 'N', from: 'n', key: ['node_key'], labels:
  ['Person', 'Owner'].map(name => ({name, properties: {mode: 'columns',
    columns: [{from: 'p', to: 'p'}]}}))};
const program = (id, steps, fields, name) => JSON.stringify({version: 'actql/0.1', id,
  stages: [{id: 'main', inputs: {}, steps,
    results: {rows: {from: 'selected', fields}}}],
  results: {[name]: {from: {stage: 'main', result: 'rows'}}}});
const nodeProgram = program('fixture.graph_rows.nodes', [
  {values: {schema: {node_key: {type: 'number', nullable: false},
    p: {type: 'number', nullable: true}}, rows: [{node_key: 2, p: 7}, {node_key: 1, p: null}]}, as: 'n'},
  {graph: {version: 'actql-graph-constructor/0.1', nodes: [nodeDefinition], edges: []}, as: 'g'},
  {from: 'g', node_rows: true, as: 'rows'},
  {from: 'rows', select: ['node_key', 'p', 'labels']},
  {filter: {gt: [{field: 'node_key'}, {literal: 0}]}},
  {sort: [{field: 'node_key', dir: 'asc', nulls: 'first'}], as: 'selected'},
], ['node_key', 'p', 'labels'], 'nodes');
const edgeProgram = program('fixture.graph_rows.edges', [
  {values: {schema: {node_key: {type: 'number', nullable: false}}, rows: [{node_key: 1}]}, as: 'n'},
  {values: {schema: Object.fromEntries(['edge_key', 'part', 'src_key', 'dst_key']
    .map(name => [name, {type: 'number', nullable: false}])), rows: [
    {edge_key: 11, part: 7, src_key: 1, dst_key: 1}, {edge_key: 10, part: 7, src_key: 1, dst_key: 1}]}, as: 'e'},
  {graph: {version: 'actql-graph-constructor/0.1',
    nodes: [{name: 'N', from: 'n', key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'no_properties'}}]}],
    edges: [{name: 'E', from: 'e', key: ['part', 'edge_key'],
      source: {definition: 'N', key: ['src_key']}, target: {definition: 'N', key: ['dst_key']},
      labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]}, as: 'g'},
  {from: 'g', edge_rows: true, as: 'rows'},
  {from: 'rows', select: ['part', 'edge_key', 'labels']},
  {sort: [{field: 'edge_key', dir: 'asc', nulls: 'first'}], as: 'selected'},
], ['part', 'edge_key', 'labels'], 'edges');
export const graphRowSourceSuccesses = [
  {name: 'graph-node-rows-json-control', format: 'json', text: nodeProgram, results: nodeResults, sourceReadCount: 0},
  {name: 'graph-node-rows-null-and-labels', format: 'aql-text', text: nodeSource +
    'FROM g |> node_rows() |> SELECT node_key, p, labels |> WHERE node_key > 0 |> ORDER BY node_key |> RESULT nodes',
    results: nodeResults, sourceReadCount: 0},
  {name: 'graph-edge-rows-json-control', format: 'json', text: edgeProgram, results: edgeResults, sourceReadCount: 0},
  {name: 'graph-edge-rows-composite-parallel-data', format: 'aql-text', text: edgeData + edgeMapping +
    'DATA `rows` = FROM `g` |> EDGE_ROWS() |> SELECT part, edge_key, labels; FROM `rows` |> ORDER BY edge_key |> RESULT edges',
    results: edgeResults, sourceReadCount: 0},
  {name: 'graph-node-rows-typed-empty', format: 'aql-text', text:
    'DATA n = SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p WHERE FALSE; ' + nodeMapping +
    'FROM g |> node_rows() |> SELECT node_key, p, labels |> RESULT nodes',
    results: {nodes: {rows: [], columns: nodeColumns}}, sourceReadCount: 0},
];
const conditional = 'DATA n = SELECT 1 AS node_key, 7 AS p; DATA m = SELECT 2 AS other_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p), m AS M KEY (other_key) LABEL Company NO PROPERTIES)); ';
export const graphRowSourceRefusals = [
  {name: 'graph-row-conditional-property', format: 'aql-text', text: conditional + 'FROM g |> node_rows() |> SELECT p'},
  {name: 'graph-row-conditional-is-not-null', format: 'aql-text', text: conditional + 'FROM g |> node_rows() |> WHERE p IS NOT NULL |> SELECT id'},
  {name: 'graph-row-carrier-mismatch', format: 'aql-text', text: nodeData + 'FROM n |> node_rows() |> SELECT node_key'},
  {name: 'graph-row-unknown-property', format: 'aql-text', text: nodeSource + 'FROM g |> node_rows() |> SELECT missing'},
];

// Definition selection proves p's presence only within N. Label selection
// includes both N and M, retaining nullable p and Conditional q separately.
const selectedData = "DATA n = SELECT 2 AS key, 7 AS p UNION ALL SELECT 1 AS key, CAST(NULL AS FLOAT64) AS p; DATA m = SELECT 3 AS key, 9 AS p, 'company' AS q; ";
const selectedMapping = 'DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (key) LABEL Person PROPERTIES (p), m AS M KEY (key) LABEL PERSON PROPERTIES (p) LABEL Company PROPERTIES (q))); ';
const selectedSteps = [
  {values: {schema: {key: {type: 'number', nullable: false}, p: {type: 'number', nullable: true}},
    rows: [{key: 2, p: 7}, {key: 1, p: null}]}, as: 'n'},
  {values: {schema: {key: {type: 'number', nullable: false}, p: {type: 'number', nullable: false}, q: {type: 'string', nullable: false}},
    rows: [{key: 3, p: 9, q: 'company'}]}, as: 'm'},
  {graph: {version: 'actql-graph-constructor/0.1', nodes: [
    {name: 'N', from: 'n', key: ['key'], labels: [{name: 'Person', properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}]},
    {name: 'M', from: 'm', key: ['key'], labels: [
      {name: 'PERSON', properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}},
      {name: 'Company', properties: {mode: 'columns', columns: [{from: 'q', to: 'q'}]}},
    ]},
  ], edges: []}, as: 'g'},
];
const selectedColumns = [number('key'), number('p', true)];
const selectedRows = [{key: 1, p: null}, {key: 2, p: 7}];
const selectedResult = rows => ({selected: {rows, columns: selectedColumns}});
const selectedProgram = selector => program('fixture.graph_rows.selection', [
  ...selectedSteps,
  {from: 'g', node_rows: selector, as: 'rows'},
  // Projection removes Conditional q before ordinary Relation filtering.
  {from: 'rows', select: ['key', 'p']},
  {filter: 'p IS NULL OR p > 0'},
  {sort: [{field: 'key', dir: 'asc', nulls: 'first'}], as: 'selected'},
], ['key', 'p'], 'selected');
const selectedTail = ' |> SELECT key, p |> WHERE p IS NULL OR p > 0 |> ORDER BY key |> RESULT selected';
const edgeSelectedControl = JSON.parse(edgeProgram);
edgeSelectedControl.stages[0].steps[3].edge_rows = {definition: 'E'};
graphRowSourceSuccesses.push(
  {name: 'graph-node-definition-json-control', format: 'json', text: selectedProgram({definition: 'N'}), results: selectedResult(selectedRows), sourceReadCount: 0},
  {name: 'graph-node-definition-source', format: 'aql-text', text: selectedData + selectedMapping + "FROM g |> node_rows(definition: 'n')" + selectedTail, results: selectedResult(selectedRows), sourceReadCount: 0},
  {name: 'graph-node-label-json-control', format: 'json', text: selectedProgram({label: 'person'}), results: selectedResult([...selectedRows, {key: 3, p: 9}]), sourceReadCount: 0},
  {name: 'graph-node-label-source', format: 'aql-text', text: selectedData + selectedMapping + 'FROM g |> node_rows(label: "pErSoN")' + selectedTail, results: selectedResult([...selectedRows, {key: 3, p: 9}]), sourceReadCount: 0},
  {name: 'graph-edge-definition-json-control', format: 'json', text: JSON.stringify(edgeSelectedControl), results: edgeResults, sourceReadCount: 0},
  {name: 'graph-edge-definition-source', format: 'aql-text', text: edgeData + edgeMapping + 'FROM `g` |> edge_rows(definition: "e") |> SELECT part, edge_key, labels |> ORDER BY edge_key |> RESULT edges', results: edgeResults, sourceReadCount: 0},
  {name: 'graph-edge-label-source', format: 'aql-text', text: edgeData + edgeMapping + "DATA rows = FROM g |> edge_rows(label: 'r') |> SELECT part, edge_key, labels; FROM rows |> ORDER BY edge_key |> RESULT edges", results: edgeResults, sourceReadCount: 0},
  {name: 'graph-node-definition-empty', format: 'aql-text', text: "DATA n = SELECT 1 AS key, CAST(NULL AS FLOAT64) AS p WHERE FALSE; DATA m = SELECT 3 AS key, 9 AS p, 'company' AS q; " + selectedMapping + "FROM g |> node_rows(definition: 'N')" + selectedTail, results: selectedResult([]), sourceReadCount: 0},
);
for (const [name, tail] of [
  ['unknown-definition', "node_rows(definition: 'missing') |> SELECT id"],
  ['wrong-kind', "node_rows(definition: 'E') |> SELECT id"],
  ['unknown-label', "node_rows(label: 'missing') |> SELECT id"],
  ['both-selectors', "node_rows(definition: 'N', label: 'Person') |> SELECT id"],
  ['non-string-selector', 'node_rows(label: 1) |> SELECT id'],
  ['label-conditional-property', "node_rows(label: 'Person') |> SELECT q"],
  ['label-conditional-predicate', "node_rows(label: 'Person') |> WHERE q IS NOT NULL |> SELECT key"],
]) graphRowSourceRefusals.push({name: `graph-row-${name}`, format: 'aql-text',
  text: (name === 'wrong-kind' ? edgeData + edgeMapping : selectedData + selectedMapping) + 'FROM g |> ' + tail});
