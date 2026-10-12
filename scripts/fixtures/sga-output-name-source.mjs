// Supplemental authored OutputName controls. Typed identity is observed through
// ordinary IS NOT NULL; no product-generated identity/domain oracle is used.
const number = {type: 'number', nullable: false};
const boolean = {type: 'boolean', nullable: false};
const rows = [{node_key: 1, bound: true}, {node_key: 2, bound: true}];
const columns = [{name: 'node_key', contract: number}, {name: 'bound', contract: boolean}];
const results = {matched: {rows, columns}};
const prefix = 'WITH n AS (SELECT 2 AS node_key UNION ALL SELECT 1 AS node_key), '
  + 'g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (node_key)))) ';
const sourceCall = "match_nodes(definition: 'N', bindings: {identity: `SELECT`}, "
  + 'where: {literal: true}, fields: [node_key, `SELECT`])';
const sourceTail = ' |> SELECT node_key, `SELECT` IS NOT NULL AS bound |> ORDER BY node_key |> RESULT matched';
const control = {version: 'actql/0.1', id: 'fixture.sga_quoted_output_name',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {node_key: number}, rows: [{node_key: 2}, {node_key: 1}]}, as: 'n'},
    {graph: {version: 'actql-graph-constructor/0.1', nodes: [{name: 'N', from: 'n',
      key: ['node_key'], labels: [{name: 'Node', properties: {mode: 'columns',
        columns: [{from: 'node_key', to: 'node_key'}]}}]}], edges: []}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', bindings: {identity: 'SELECT'},
      where: {literal: true}, fields: ['node_key', 'SELECT']}, as: 'matched'},
    {from: 'matched', derive: {bound: {not: {is_null: {field: 'SELECT'}}}}},
    {select: ['node_key', 'bound']},
    {sort: [{field: 'node_key', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {out: {from: 'ordered', fields: ['node_key', 'bound']}}}],
  results: {matched: {from: {stage: 'main', result: 'out'}}}};
export const sgaOutputNameSuccesses = [
  {name: 'sga-output-name-independent-json', format: 'json', text: JSON.stringify(control), results, sourceReadCount: 0},
  {name: 'sga-output-name-quoted-reserved', format: 'aql-text',
    text: prefix + 'FROM g |> ' + sourceCall + sourceTail, results, sourceReadCount: 0},
];
export const sgaOutputNameRefusals = ['SELECT', 'null'].map(name => ({
  name: 'sga-output-name-unquoted-' + name.toLowerCase(), format: 'aql-text',
  text: prefix + 'FROM g |> ' + sourceCall.replace('identity: `SELECT`', 'identity: ' + name) + sourceTail,
  expectedCode: 'ClientProgramInvalidInput', sourceReadCount: 0,
}));
