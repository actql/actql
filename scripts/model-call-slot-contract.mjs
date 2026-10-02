import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const ordinal = {type: 'integer', minimum: 0,
  maximum: Number.MAX_SAFE_INTEGER};
const text = {type: 'string', minLength: 1};

export const modelIdentityFields = Object.freeze({
  model_effective_inputs: 'effective_inputs_cid',
  model_input_artifact: 'input_artifact_cid',
  model_input_key: 'input_key_cid',
  model_call_slot: 'model_call_slot_cid',
});

function schema(name, fields) {
  const version = `actql-${name.replaceAll('_', '-')}/0.1`;
  const identity = modelIdentityFields[name];
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: `https://smooth.dev/schemas/${version.replace('/0.1', '-0.1')}.json`,
    title: version.replace('/0.1', '-0.1'),
    type: 'object', additionalProperties: false,
    required: ['version', ...Object.keys(fields), identity],
    properties: {version: {const: version}, ...fields, [identity]: cid},
  };
}

export function modelIdentitySchemas() {
  return {
    model_effective_inputs: schema('model_effective_inputs', {
      parameter_values_cid: cid,
      invocation_bindings_cid: cid,
      input_artifacts: {type: 'object', additionalProperties: cid},
    }),
    model_input_artifact: schema('model_input_artifact', {
      program_definition_cid: cid,
      unit_definition_cid: cid,
      source_ordinal: ordinal,
      effective_inputs_cid: cid,
      input_fragment_cid: cid,
      logical_relation_cid: cid,
      relation_schema_cid: cid,
      ordered_rows_cid: cid,
      completeness: {const: 'complete'},
    }),
    model_input_key: schema('model_input_key', {
      components: {type: 'array', minItems: 1, items: {
        type: 'object', additionalProperties: false,
        required: ['field', 'value_contract_cid', 'value_cid'],
        properties: {field: text, value_contract_cid: cid, value_cid: cid},
      }},
    }),
    model_call_slot: schema('model_call_slot', {
      program_definition_cid: cid,
      unit_definition_cid: cid,
      source_ordinal: ordinal,
      effective_inputs_cid: cid,
      input_artifact_cid: cid,
      input_key_cid: cid,
      model_task_cid: cid,
      fixed_request_cid: cid,
    }),
  };
}

export function applyModelIdentitySchemas(registry) {
  for (const [name, body] of Object.entries(modelIdentitySchemas())) {
    registry.artifact_schemas[name] = body;
    registry.artifact_schema_cids[name] = machineCid(body);
  }
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkModelIdentitySchemas(registry) {
  for (const [name, body] of Object.entries(modelIdentitySchemas())) {
    assert.deepEqual(registry.artifact_schemas[name], body);
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyModelIdentitySchemas(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkModelIdentitySchemas(registry);
}
