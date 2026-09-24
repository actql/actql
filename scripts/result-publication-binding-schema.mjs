import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};

export const resultPublicationTargetSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['kind', 'unit_definition_cid', 'result_name', 'measure'],
  properties: {
    kind: {const: 'result_publication'},
    unit_definition_cid: cid,
    result_name: {type: 'string', minLength: 1},
    measure: {enum: ['rows', 'bytes']},
  },
};

export function planLimitTargetSchemas(registry) {
  return [
    registry.artifact_schemas.executable_plan.properties.limit_bindings.items.properties.target,
    registry.artifact_schemas.plan_document.properties.plan.properties.limit_bindings.items.properties.target,
  ];
}

export function checkResultPublicationTargetSchemas(registry) {
  const [executable, document] = planLimitTargetSchemas(registry);
  assert.deepEqual(executable, document);
  assert.deepEqual(executable.oneOf.at(-1), resultPublicationTargetSchema);
  assert.equal(executable.oneOf.filter(schema => schema.properties.kind.const === 'result_publication').length, 1);
  for (const [name, body] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(body), name);
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const schema of planLimitTargetSchemas(registry)) {
      const targets = schema.oneOf.filter(target => target.properties.kind.const !== 'result_publication');
      schema.oneOf = [...targets, structuredClone(resultPublicationTargetSchema)];
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkResultPublicationTargetSchemas(registry);
}
