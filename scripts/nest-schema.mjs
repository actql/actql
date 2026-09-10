import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parameterPrograms } from './parameter-schema.mjs';
import { machineCid } from './actql-spec-family.mjs';

export const projectionItem = {
  oneOf: [
    { type: 'string', minLength: 1 },
    { type: 'object', minProperties: 1, maxProperties: 1,
      additionalProperties: { type: 'string', minLength: 1 } },
  ],
};

export function checkNestSchemas(registry) {
  for (const p of parameterPrograms(registry)) {
    const n = p.properties.steps.items.properties.nest;
    assert.deepEqual(n.properties.fields.items, projectionItem);
    assert.equal(n.properties.fields.minItems, 1);
    assert.equal(n.properties.on.minItems, 1);
    assert.notEqual(n.properties.on.uniqueItems, true);
    assert.equal(n.properties.order_by.minItems, 1);
  }
  for (const [name, body] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const p of parameterPrograms(registry)) p.properties.steps.items.properties.nest.properties.fields.items = structuredClone(projectionItem);
    for (const [name, body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name] = machineCid(body);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkNestSchemas(registry);
  console.log('Nest projection schemas and artifact pins verified.');
}
