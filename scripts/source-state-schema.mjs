import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export function sourceStateSchemas(registry) {
  return [registry.artifact_schemas.executable_plan.properties.source_state_requirements.items,
    registry.artifact_schemas.plan_document.properties.plan.properties.source_state_requirements.items];
}

export function checkSourceStateSchemas(registry) {
  const schemas = sourceStateSchemas(registry);
  assert.deepEqual(schemas[0], schemas[1]);
  assert.equal(schemas[0].additionalProperties, false);
  assert.ok(schemas[0].required.includes('stage_id'));
  assert.deepEqual(schemas[0].properties.stage_id, {type:'string', minLength:1});
  for (const [name, body] of Object.entries(registry.artifact_schemas))
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const schema of sourceStateSchemas(registry)) {
      if (!schema.required.includes('stage_id')) schema.required.push('stage_id');
      schema.properties.stage_id = {type:'string', minLength:1};
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      const next = machineCid(body);
      if (next !== registry.artifact_schema_cids[name]) console.log(name, registry.artifact_schema_cids[name], next);
      registry.artifact_schema_cids[name] = next;
    }
    const next = machineCid(registry.artifact_schemas);
    console.log('registry', registry.artifact_registry_cid, next);
    registry.artifact_registry_cid = next;
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkSourceStateSchemas(registry);
}
