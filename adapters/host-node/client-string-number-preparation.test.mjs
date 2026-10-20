import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';

// An explicit component Environment/profile, not an installed Host supplier,
// Source grant, Run authorization or numerical funding fixture.
const selected = {
  version: 'actql-check-environment/0.1', command_contracts: [],
  connector_capabilities: [], connector_catalogs: [], contract_registry: [],
  mapping_contracts: [], model_task_contracts: [], schema_snapshots: [], source_views: [],
  host_policy_profile: {capacity: Object.fromEntries([
    'max_aggregate_array_items', 'max_artifact_bytes', 'max_artifact_rows',
    'max_effect_items', 'max_graph_input_edges', 'max_graph_input_nodes',
    'max_graph_output_rows', 'max_graph_paths', 'max_infer_items',
    'max_model_input_tokens_per_item', 'max_model_request_bytes_per_item',
    'max_model_total_duration_ms', 'max_nested_value_bytes', 'max_nested_value_depth',
    'max_relation_output_rows', 'max_temporal_matches_per_key', 'max_temporal_output_rows',
  ].map(name => [name, 1000]).concat([['version', 'actql-capacity-host-policy/0.1']])),
  text_time_evaluation: {version: 'actql-text-time-host-policy/0.1',
    max_input_codepoints: 64, max_input_utf8_bytes: 256, max_output_bytes: 64,
    max_pattern_bytes: 1, max_replacements: 1}},
};
const cid = value => `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`;
selected.evidence_bundle_cid = cid(selected);
const environment = moon.clientProgramCheckEnvironment(canonicalText(selected),
  selected.evidence_bundle_cid, true, false, true, false, false, false, false);
assert.ok(environment);
const prepare = installNodeClientProgramPreparation({moon, environment,
  sourcePublication: sourceAliasPublication(moon, environment, [])});
const compile = original => {
  assert.equal(prepare.originalInputs(original).environment, environment);
  const compilation = checked(moon.clientProgramCompileLocalTasks(original));
  assert.equal(typeof moon.clientProgramTaskCompilationCompiledPlanWire(compilation), 'string');
  return compilation;
};

test('ordinary Program preparation carries original String TRY_NUMBER through task compilation', () => {
  const input = {version: 'actql/0.1', id: 'original-string-number', stages: [{id: 'main',
    inputs: {}, steps: [
      {values: {schema: {text: {type: 'string', nullable: true}},
        rows: [{text: '12.5'}, {text: 'bad-number'}, {text: null}]}, as: 'input'},
      {derive: {n: {try_number: {value: {field: 'text'}}}}, as: 'parsed'},
    ], results: {r: {from: 'parsed', fields: ['n']}}}],
  results: {r: {from: {stage: 'main', result: 'r'}}}};
  const original = prepare({kind: 'program', input, parameters: null});
  compile(original);
  const foreign = installNodeClientProgramPreparation({moon, environment});
  assert.throws(() => foreign.originalInputs(original), {code: 'ClientProgramPreparationFailure'});
  assert.throws(() => prepare.originalInputs({...original}), {code: 'ClientProgramPreparationFailure'});
});

test('public SQL and Pipe preparation preserve String Parameters and compile the same original owner', () => {
  for (const format of ['sql', 'aql-text']) {
    for (const text of [
      "SELECT TRY_NUMBER('12.5') AS n",
      "SELECT '12.5' AS text |> SELECT TRY_NUMBER(text) AS n",
      'SELECT TRY_NUMBER(@text) AS n',
      "SELECT IF(TRUE, 7, TRY_NUMBER('unparsed')) AS n",
    ]) {
      const parameters = text.includes('@text') ? {text: '12.5'} : null;
      const input = {format, text, ...(parameters === null ? {} : {
        parameterDeclarations: {text: {type: 'string'}},
      })};
      const original = prepare({kind: 'aql', input, parameters});
      assert.equal(prepare.originalInputs(original).parameters,
        parameters === null ? undefined : JSON.stringify(parameters));
      compile(original);
    }
  }
});
