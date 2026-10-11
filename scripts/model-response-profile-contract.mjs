import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const integer = {type: 'integer', minimum: 1, maximum: 2147483647};
const object = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const nullable = value => ({oneOf: [{type: 'null'}, value]});
export const responseObservationOrder = Object.freeze([
  'provider_request_id', 'provider_reported_model_id', 'finish_reason',
  'input_tokens', 'output_tokens', 'cached_input_tokens', 'reasoning_tokens',
  'provider_metadata',
]);
export const responseProfileLimitNames = Object.freeze([
  'request_bytes', 'response_bytes', 'chunk_bytes', 'chunks', 'header_bytes',
  'metadata_bytes', 'metadata_nodes', 'metadata_depth', 'parse_nodes',
  'parse_depth', 'parse_work', 'adapter_holding_bytes', 'adapter_workspace_bytes',
  'active_slots', 'unsettled_slots',
]);
export const responseProfileDisabledControls = Object.freeze([
  'retry', 'fallback', 'hedging', 'tools', 'repair', 'cache', 'media_fetch',
  'workflow_restore', 'sdk_telemetry', 'redirect',
]);

// Physical support declaration only. The installed builder/codec, current
// send gate and C's cumulative resource reservation are separate obligations.
export function modelResponseProfileSchema() {
  return {$schema: 'https://json-schema.org/draft/2020-12/schema',
    ...object({
      version: {const: 'actql-model-response-profile/0.1'},
      adapter: object({builder_id: text, builder_revision: text, codec_id: text,
        codec_revision: text, build_artifact_cid: cid,
        port_abi: {const: 'model-physical-port/1'},
        sdk: nullable(object({package: text, version: text,
          interface: {const: 'v4'}, lock_artifact_cid: cid}))}),
      operation: object({endpoint: text, method: {const: 'POST'},
        streaming: {const: false}}),
      task: object({contract_cid: cid,
        kind: {enum: ['structured_generate', 'decision']},
        input_schema_cid: cid, output_schema_cid: cid}),
      completion: object({validator_id: text, validator_revision: text,
        validator_artifact_cid: cid,
        basis: {enum: ['generation_finish', 'native_decision']},
        transport_eof: {const: true}, endpoint_envelope: {const: true},
        output_contract: {const: true}}),
      probability: nullable(object({source: {enum: ['native', 'estimated']},
        validation_profile_cid: cid})),
      observations: {type: 'array', uniqueItems: true, maxItems: 8,
        items: {enum: [...responseObservationOrder]}},
      limits: object(Object.fromEntries(responseProfileLimitNames.map(name =>
        [name, ['active_slots', 'unsettled_slots'].includes(name)
          ? {...integer, maximum: 4} : integer]))),
      controls: object({model_requests: {const: 1},
        ...Object.fromEntries(responseProfileDisabledControls.map(name =>
          [name, {const: false}]))}),
      self_cid: cid,
    }),
    allOf: [{if: {properties: {task: {type: 'object', properties: {
      kind: {const: 'structured_generate'}}}}},
    then: {properties: {probability: {type: 'null'}, completion: {type: 'object', properties: {
      basis: {const: 'generation_finish'}}}}},
    else: {properties: {probability: {type: 'object'}}}},
    {if: {properties: {completion: {type: 'object', properties: {
      basis: {const: 'native_decision'}}}}},
    then: {properties: {task: {type: 'object', properties: {kind: {const: 'decision'}}},
      probability: {type: 'object', properties: {source: {const: 'native'}}}}}}],
  };
}

export function checkModelResponseProfileSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.model_response_profile,
    modelResponseProfileSchema());
  assert.equal(registry.artifact_schema_cids.model_response_profile,
    machineCid(modelResponseProfileSchema()));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    const manifestPath = 'spec/spec-family.json';
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    const owner = manifest.documents.find(item => item.document_id === 'contracts');
    assert.ok(owner);
    let source = readFileSync(owner.path, 'utf8');
    const pointer = '/artifact_schemas/model_response_profile';
    const schema = modelResponseProfileSchema(), pin = machineCid(schema);
    const reference = owner.machine_contracts.find(item =>
      item.path === path && item.pointer === pointer);
    if (reference) {
      source = source.replace(`../../../${path}#${pointer} ${reference.cid}`,
        `../../../${path}#${pointer} ${pin}`);
      reference.cid = pin;
    } else {
      const anchor = source.split('\n').find(line => line.startsWith(
        '../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_prompt '));
      assert.ok(anchor);
      source = source.replace(anchor, anchor + `\n../../../${path}#${pointer} ${pin}`);
      owner.machine_contracts.push({path, pointer, cid: pin, version: registry.version});
    }
    registry.artifact_schemas.model_response_profile = schema;
    registry.artifact_schema_cids.model_response_profile = pin;
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(owner.path, source);
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  }
  checkModelResponseProfileSchema(registry);
}
