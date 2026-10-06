// Independently authored machine input and Boolean results. No compiler or
// Graph comparison implementation supplies these expectations.
const number = {type: 'number', nullable: false};
const columns = [{name: 'equal', contract: {type: 'boolean', nullable: false}}];
const result = (rows = [{equal: true}]) => ({comparison: {rows, columns}});
const mapping = {version: 'actql-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'],
    labels: [{name: 'Person', properties: {mode: 'columns',
      columns: [{from: 'p', to: 'p'}]}}]}], edges: []};
const json = JSON.stringify({version: 'actql/0.1', id: 'fixture.graph_equality',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {node_key: number, p: number},
      rows: [{node_key: 1, p: 7}]}, as: 'n'},
    {graph: mapping, as: 'g'},
    {from: 'g', graphs_equal: {with: 'g'}, as: 'same'},
    {from: 'same', select: ['equal'], as: 'projected'},
  ], results: {out: {from: 'projected', fields: ['equal']}}}],
  results: {comparison: {from: {stage: 'main', result: 'out'}}}});
const graph = producer => 'PROPERTY GRAPH (NODE TABLES (' + producer +
  ' AS N KEY (node_key) LABEL Person PROPERTIES (p)))';
const prefix = 'DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = ' + graph('n') + '; ';
const suffix = ' |> SELECT equal |> RESULT comparison';
export const graphEqualitySourceSuccesses = [
  {name: 'graph-equality-json-control', format: 'json', text: json,
    results: result(), sourceReadCount: 0},
  {name: 'graph-equality-terminal-self', format: 'aql-text',
    text: prefix + 'FROM g |> graphs_equal(with: g)' + suffix,
    results: result(), sourceReadCount: 0},
  {name: 'graph-equality-normalized-quoted-data-alias', format: 'aql-text',
    text: prefix + 'DATA `peer graph` = FROM g; DATA same = FROM g |> normalize_graph() |> graphs_equal(with: `peer graph`); FROM same |> WHERE equal |> SELECT equal |> RESULT comparison',
    results: result(), sourceReadCount: 0},
  {name: 'graph-equality-distinct-right-producer', format: 'aql-text',
    text: prefix + 'DATA m = SELECT 2 AS node_key, 7 AS p; DATA h = ' + graph('m') +
      '; FROM g |> graphs_equal(with: h) |> WHERE NOT equal' + suffix,
    results: result([{equal: false}]), sourceReadCount: 0},
  {name: 'graph-equality-empty-graph', format: 'aql-text',
    text: 'DATA n = SELECT CAST(NULL AS FLOAT64) AS node_key, 7 AS p; DATA g = ' +
      graph('n') + '; FROM g |> graphs_equal(with: g)' + suffix,
    results: result(), sourceReadCount: 0},
  {name: 'graph-equality-empty-relation-suffix', format: 'aql-text',
    text: prefix + 'FROM g |> graphs_equal(with: g) |> WHERE FALSE' + suffix,
    results: result([]), sourceReadCount: 0},
];
export const graphEqualitySourceRefusals = [
  ['string-producer', "FROM g |> graphs_equal(with: 'g')" + suffix],
  ['unknown-producer', 'FROM g |> graphs_equal(with: missing)' + suffix],
  ['relation-producer', 'FROM g |> graphs_equal(with: n)' + suffix],
  ['forward-producer', 'DATA same = FROM g |> graphs_equal(with: later); DATA later = FROM g; FROM same' + suffix],
  ['missing-argument', 'FROM g |> graphs_equal()' + suffix],
  ['extra-argument', 'FROM g |> graphs_equal(with: g, extra: true)' + suffix],
  ['graph-column-after-transition', 'FROM g |> graphs_equal(with: g) |> SELECT node_key |> RESULT comparison'],
  ['graph-call-after-transition', 'FROM g |> graphs_equal(with: g) |> node_rows()' + suffix],
  ['incompatible-key-type', "DATA m = SELECT 'two' AS node_key, 7 AS p; DATA h = " +
    graph('m') + '; FROM g |> graphs_equal(with: h)' + suffix],
  // Existing common order-evidence gap, not a source-language restriction.
  // Keep the authored ORDER/LIMIT intact and observe pre-admission rejection.
  ['common-unresolved-order', 'FROM g |> graphs_equal(with: g) |> SELECT equal |> ORDER BY equal |> LIMIT 1 |> RESULT comparison'],
].map(([name, text]) => ({name: 'graph-equality-' + name, format: 'aql-text',
  text: prefix + text}));
