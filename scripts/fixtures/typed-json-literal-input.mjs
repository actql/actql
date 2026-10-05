// Independent machine input and expected delivery values. No runtime imports.
import {createHash} from 'node:crypto';
const json = value => ({typed_literal: {type: 'json', value}});
const fields = ['json_null', 'sql_null', 'json_number', 'number', 'json_string',
  'string', 'json_boolean', 'boolean', 'json_object', 'json_array'];
const expressions = {
  json_null: json('null'),
  sql_null: {if: [{literal: false}, json('null'), {literal: null}]},
  json_number: json('1.5'), number: {literal: 1.5},
  json_string: json('"x"'), string: {literal: 'x'},
  json_boolean: json('true'), boolean: {literal: true},
  json_object: json('{"a":1,"a":2,"e\\u0301":null}'),
  json_array: json('[null,false]'),
};
const program = (bindings = expressions, empty = false, resultFields = fields) => ({version: 'actql/0.1',
  id: 'typed-json-literals', stages: [{id: 's', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}},
      rows: [{unit: true}]}},
    {as: 'typed', derive: bindings},
    ...(empty ? [{as: 'empty', filter: {literal: false}}] : []),
  ], results: {out: {from: empty ? 'empty' : 'typed', fields: resultFields}}}],
  results: {answer: {from: {stage: 's', result: 'out'}}}});
const columns = fields.map(name => ({name, contract: {type:
  name.startsWith('json_') || name === 'sql_null' ? 'json' : name,
nullable: name === 'sql_null', ...(name === 'string' ? {max_utf8_bytes: 1} : {})}}));
const expected = [{json_null: {$json: null}, sql_null: null,
  json_number: {$json: 1.5}, number: 1.5, json_string: {$json: 'x'}, string: 'x',
  json_boolean: {$json: true}, boolean: true,
  json_object: {$json: {a: 1, 'e\u0301': null}}, json_array: {$json: [null, false]}}];
// A separate Result stays inside the existing 10-field Local profile while
// covering exact nested keys, CRLF and an ordinary $json payload member.
const nestedFields = ['json_envelope', 'json_nested', 'sql_null'];
const nested = {
  json_envelope: json('{"$json":null}'),
  json_nested: json('{"rows":[{"é":1,"e\\u0301":2,"line":"a\\r\\nb"},null,[false]]}'),
  sql_null: expressions.sql_null,
};
export const typedJsonLiteralSuccesses = [
  {name: 'typed-json-all-roots-and-sql-null', format: 'json',
    text: JSON.stringify(program()), expected, columns, sourceReadCount: 0},
  {name: 'typed-json-empty-result-schema', format: 'json',
    text: JSON.stringify(program(expressions, true)), expected: [], columns, sourceReadCount: 0},
  {name: 'typed-json-nested-exact-keys-and-envelope', format: 'json',
    text: JSON.stringify(program(nested, false, nestedFields)),
    expected: [{json_envelope: {$json: {$json: null}},
      json_nested: {$json: {rows: [{'é': 1, 'e\u0301': 2, line: 'a\r\nb'}, null, [false]]}},
      sql_null: null}],
    columns: nestedFields.map(name => ({name,
      contract: {type: 'json', nullable: name === 'sql_null'}})), sourceReadCount: 0},
];

// Authored producer and complete Graph snapshot preimages exercise JSON cells
// through the ordinary Graph Delta owner, with no compiler-derived oracle.
const canonicalData = value => Array.isArray(value)
  ? '[' + value.map(canonicalData).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
      canonicalData(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonicalData(value)).digest('hex');
const graphNumber = {type: 'number', nullable: false};
const graphJson = {type: 'json', nullable: false};
const graphSeed = {schema: {node_key: graphNumber}, rows: [{node_key: 1}]};
const beforePayload = {'é': 1, 'e\u0301': 2, line: 'a\r\nb', nil: null};
const afterPayload = {...beforePayload, 'e\u0301': 3};
const graphDerive = {p: json(canonicalData(beforePayload))};
const graphConstructor = {version: 'actql-property-graph-constructor/0.1',
  nodes: [{name: 'N', from: 'n', key: ['node_key'], labels: [{name: 'Node',
    properties: {mode: 'columns', columns: [{from: 'p', to: 'p'}]}}]}], edges: []};
const graphMapping = structuredClone(graphConstructor);
delete graphMapping.nodes[0].from;
graphMapping.nodes[0].input_occurrence = 0;
const graphDomain = cid({version: 'actql-property-graph-definition/0.1',
  constructor: graphMapping, producer_definitions: [{body: {derive: graphDerive},
    dependencies: [{body: {values: graphSeed}, dependencies: []}]}]});
const graphLaw = 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc';
const graphContract = {version: 'actql-property-graph-contract/0.1',
  domain: graphDomain, identity_law_cid: graphLaw, value_law_cid: graphLaw,
  node_definitions: [{name: 'N', key_columns: ['node_key'], key_contracts: [graphNumber],
    labels: {Node: ['p']}, properties: {p: graphJson}}], edge_definitions: []};
const graphContractCid = cid(graphContract);
const graphIdentity = {definition: 'N', domain: graphDomain, key: [1], key_types: [{kind: 'number'}]};
const graphRecord = payload => ({id: graphIdentity, key: [1], props: {p: {$json: payload}}});
const graphBefore = graphRecord(beforePayload), graphAfter = graphRecord(afterPayload);
const graphSnapshot = row => ['actql-property-graph-snapshot/0.1', graphContractCid,
  graphContract, [row], []];
const graphDelta = {version: 'actql-graph-delta/0.1', graph_contract_cid: graphContractCid,
  base_graph_cid: cid(graphSnapshot(graphBefore)), target_graph_cid: cid(graphSnapshot(graphAfter)),
  nodes: {add: [], remove: [], update: [{before: graphBefore, after: graphAfter}]},
  edges: {add: [], remove: [], update: []}};
const graphProgram = {version: 'actql/0.1', id: 'typed-json-graph-keys', stages: [{
  id: 's', inputs: {}, steps: [
    {values: graphSeed, as: 'seed'}, {from: 'seed', derive: graphDerive, as: 'n'},
    {property_graph: graphConstructor, as: 'g'},
    {values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}, as: 'unit'},
    {from: 'unit', derive: {delta: json(canonicalData(graphDelta))}, as: 'changes'},
    {from: 'g', apply_graph_delta: {with: 'changes', field: 'delta'}, as: 'applied'},
    {from: 'applied', node_rows: true, as: 'out'},
  ], results: {out: {from: 'out', fields: ['node_key', 'p']}}}],
results: {answer: {from: {stage: 's', result: 'out'}}}};
typedJsonLiteralSuccesses.push({name: 'typed-json-graph-delta-exact-property-keys',
  format: 'json', text: JSON.stringify(graphProgram), sourceReadCount: 0,
  graphSnapshots: [graphDelta.base_graph_cid, graphDelta.target_graph_cid],
  expected: [{node_key: 1, p: {$json: afterPayload}}],
  columns: [{name: 'node_key', contract: graphNumber}, {name: 'p', contract: graphJson}]});
export const typedJsonLiteralRefusals = [
  ['numeric-precision-loss', '9007199254740993'],
  ['numeric-overflow', '1e400'],
  ['malformed-json', '{"a":}'],
  ['json-depth', '['.repeat(501) + 'null' + ']'.repeat(501)],
].map(([name, value]) => ({name: 'typed-json-' + name, format: 'json',
  text: JSON.stringify(program({...expressions, json_null: json(value)}))}));
