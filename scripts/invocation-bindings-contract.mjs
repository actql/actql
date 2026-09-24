import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const bindingName = '^[A-Za-z_][A-Za-z0-9_]*$';

function insertAfter(entries, predecessor, key, value) {
  const result = {};
  for (const [name, body] of Object.entries(entries)) {
    result[name] = body;
    if (name === predecessor) result[key] = value;
  }
  assert.ok(Object.hasOwn(result, key), `Missing predecessor: ${predecessor}`);
  return result;
}

export function invocationBindingsSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-invocation-bindings-0.1.json',
    title: 'actql-invocation-bindings-0.1',
    type: 'object', additionalProperties: false,
    required: ['version', 'bindings', 'invocation_bindings_cid'],
    properties: {
      version: {const: 'actql-invocation-bindings/0.1'},
      bindings: {
        type: 'object', propertyNames: {pattern: bindingName},
        additionalProperties: cid,
      },
      invocation_bindings_cid: cid,
    },
  };
}

export function invocationBindingsCid(bindings) {
  return machineCid({version: 'actql-invocation-bindings/0.1', bindings});
}

export function assertInvocationBindingNames(declarations, bindings) {
  assert.ok(declarations && typeof declarations === 'object' &&
    !Array.isArray(declarations));
  assert.ok(bindings && typeof bindings === 'object' &&
    !Array.isArray(bindings));
  const declared = Object.keys(declarations).sort();
  const bound = Object.keys(bindings).sort();
  assert.deepEqual(bound, declared, 'Every declared binding must be supplied');
  for (const [name, referenceCid] of Object.entries(bindings)) {
    assert.match(name, /^[A-Za-z_][A-Za-z0-9_]*$/);
    assert.match(referenceCid, /^sha256:[0-9a-f]{64}$/);
  }
}

export function boundInvocationTemplateCid(template) {
  const {bound_invocation_template_cid: _self, ...preimage} = template;
  const required = [
    'version', 'program_definition_cid', 'parameter_values_cid',
    'invocation_bindings_cid', 'check_environment_cid',
    'grammar_manifest_cid', 'required_profile_contracts',
    'barrier_contract_manifest_cid', 'source_evidence',
  ];
  assert.deepEqual(Object.keys(preimage).sort(), required.sort());
  return machineCid(preimage);
}

export function applyInvocationBindingsSchema(registry) {
  const schema = invocationBindingsSchema();
  registry.artifact_schemas = insertAfter(registry.artifact_schemas,
    'parameter_values', 'invocation_bindings', schema);
  registry.artifact_schema_cids = insertAfter(registry.artifact_schema_cids,
    'parameter_values', 'invocation_bindings', machineCid(schema));
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkInvocationBindingsSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.invocation_bindings,
    invocationBindingsSchema());
  assert.equal(registry.artifact_schema_cids.invocation_bindings,
    machineCid(registry.artifact_schemas.invocation_bindings));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyInvocationBindingsSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkInvocationBindingsSchema(registry);
}
