import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const pointer = '/schemas/model_provider_defaults';
const read = path => JSON.parse(readFileSync(path, 'utf8'));

// Existing contract-envelope identity, narrowed to its installed Model role.
// Body/CID correspondence and actual installation scope remain Common and Host
// obligations; the schema is not their proof.
export function modelProviderHandlingSchema() {
  const text = {type: 'string', minLength: 1};
  return {type: 'object', additionalProperties: false,
    required: ['schema', 'id', 'version', 'kind', 'body', 'cid'],
    properties: {schema: {const: 'actql.contract/0.1'}, id: text, version: text,
      kind: {const: 'request_data_handling'},
      body: {type: 'object', additionalProperties: false,
        required: ['accepted_classifications', 'allowed_regions', 'retention', 'training_use'],
        properties: {accepted_classifications: {type: 'array', minItems: 1,
          uniqueItems: true, items: {enum: ['public', 'internal', 'confidential', 'restricted']}},
        allowed_regions: {type: 'array', minItems: 1, uniqueItems: true, items: text},
        retention: {enum: ['none', 'provider_contract']}, training_use: {const: 'forbidden'}}},
      cid: {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'}}};
}

// A closed DATA subrecord of the original Provider configuration, not a new
// binding/evidence domain or a substitute for that configuration's contract.
export function modelProviderDefaultsSchema() {
  const text = {type: 'string', minLength: 1};
  const integer = {type: 'integer', minimum: 1, maximum: 9007199254740991};
  return {type: 'object', additionalProperties: false, required: ['models'],
    properties: {default_model: text, models: {type: 'array', items: {
      type: 'object', additionalProperties: false,
      required: ['model', 'generation_config'], properties: {model: text,
        data_handling: modelProviderHandlingSchema(),
        generation_config: {type: 'object', additionalProperties: false,
          required: ['temperature', 'top_p', 'max_output_tokens'], properties: {
            temperature: {type: 'number'},
            top_p: {type: 'number', exclusiveMinimum: 0, maximum: 1},
            max_output_tokens: integer,
            seed_requested: {type: 'integer', minimum: -9007199254740991,
              maximum: 9007199254740991},
          }},
      }}}}};
}

export function checkModelProviderDefaultsSchema(registry) {
  const schema = modelProviderDefaultsSchema();
  assert.deepEqual(registry.schemas.model_provider_defaults, schema);
  assert.equal(registry.schema_cids.model_provider_defaults, machineCid(schema));
  assert.equal(registry.registry_cid, machineCid(registry.schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = read(path);
  if (process.argv.includes('--write')) {
    const schema = modelProviderDefaultsSchema(), cid = machineCid(schema);
    registry.schemas.model_provider_defaults = schema;
    registry.schema_cids.model_provider_defaults = cid;
    registry.registry_cid = machineCid(registry.schemas);
    const manifestPath = 'spec/spec-family.json', manifest = read(manifestPath);
    const owner = manifest.documents.find(item => item.document_id === 'contracts');
    const existing = owner.machine_contracts.find(item => item.path === path && item.pointer === pointer);
    let source = readFileSync(owner.path, 'utf8');
    const prefix = `../../../${path}#${pointer} `;
    if (existing) {
      source = source.replace(prefix + existing.cid, prefix + cid);
      existing.cid = cid;
    } else {
      assert.ok(source.includes('<a id="model-task"></a>'));
      source = source.replace('<a id="model-task"></a>',
        `<a id="model-task"></a>\n\n<!-- machine-import: ${prefix}${cid} -->`);
      owner.machine_contracts.push({path, pointer, cid, version: registry.version});
    }
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
    writeFileSync(owner.path, source);
  }
  checkModelProviderDefaultsSchema(registry);
}
