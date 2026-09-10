import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { machineCid } from './actql-spec-family.mjs';

const fieldPattern = '^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$';
const safeBound = minimum => ({ type: 'integer', minimum, maximum: 9007199254740991 });
export function parameterSchema(declaration = false) {
  const bodies = {
    number: { integer: { type: 'boolean' }, minimum: { type: 'number' }, maximum: { type: 'number' } },
    string: { format: { const: 'duration' } },
    boolean: {}, timestamp: {}, date: {},
    decimal: { precision: { type: 'integer', minimum: 1, maximum: 38 }, scale: { type: 'integer', minimum: 0, maximum: 38 } },
    array: { items: { $ref: '#/$defs/parameter_type' }, length: safeBound(1), max_items: safeBound(0) },
    object: { fields: { type: 'object', propertyNames: { pattern: fieldPattern }, additionalProperties: { $ref: '#/$defs/parameter_type' } } },
  };
  return { oneOf: Object.entries(bodies).map(([type, extra]) => ({
    type: 'object', additionalProperties: false,
    required: ['type', ...({ decimal: ['precision', 'scale'], array: ['items'], object: ['fields'] }[type] ?? [])],
    properties: { type: { const: type }, nullable: { type: 'boolean', default: false }, ...extra,
      ...(declaration ? { default: {}, meta: { $ref: '#/$defs/meta' } } : {}) },
    ...(type === 'decimal' ? { allOf: Array.from({ length: 38 }, (_, index) => ({
      if: { properties: { precision: { const: index + 1 } }, required: ['precision'] },
      then: { properties: { scale: { maximum: index + 1 } } },
    })) } : {}),
  })) };
}

export const sourceParameters = {
  recursive_objects_arrays: true,
  nullable_default: false,
  nullable_default_scope: 'all-recursive-parameter-type-positions',
  recursive_constraints: ['integer', 'minimum', 'maximum', 'format', 'length', 'max_items'],
  declaration_only_members: ['default', 'meta'],
  literal_default_on_missing_only: true,
  deep_merge: false,
  bind_once_program_wide: true,
};

export function parameterPrograms(registry) {
  return [
    registry.artifact_schemas.executable_plan.properties.execution_material.properties.program,
    registry.artifact_schemas.plan_document.properties.plan.properties.execution_material.properties.program,
  ];
}

export function checkParameterSchemas(registry, stages) {
  assert.deepEqual(stages.source.parameters, sourceParameters);
  for (const program of parameterPrograms(registry)) {
    assert.deepEqual(program.properties.params.additionalProperties, parameterSchema(true));
    assert.deepEqual(program.$defs.parameter_type, parameterSchema());
    assert.deepEqual(program.properties.params.propertyNames, { pattern: '^[A-Za-z_][A-Za-z0-9_]*$' });
  }
  for (const [name, body] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const registryPath = 'spec/contracts/actql-protocol-schemas.json';
  const stagesPath = 'spec/contracts/actql-stage-contracts.json';
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  const stages = JSON.parse(readFileSync(stagesPath, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const program of parameterPrograms(registry)) {
      program.properties.params.additionalProperties = parameterSchema(true);
      program.$defs.parameter_type = parameterSchema();
    }
    stages.source.parameters = sourceParameters;
    for (const [name, body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name] = machineCid(body);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(stagesPath, JSON.stringify(stages, null, 2) + '\n');
  }
  checkParameterSchemas(registry, stages);
  console.log('Recursive Parameter schemas and artifact pins verified.');
}
