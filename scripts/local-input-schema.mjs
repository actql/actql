import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function checkLocalInputSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    const alternatives = program.properties.inputs.additionalProperties.oneOf;
    const object = alternatives.find(s => s.properties?.carrier);
    assert.ok(object, 'missing object-form input');
    assert.equal(object.additionalProperties, false);
    assert.ok(object.properties.schema, 'inline schema must remain available');
    assert.ok(object.properties.expected_columns);
    assert.deepEqual(object.properties.minimum_classification.enum,
      ['public', 'internal', 'confidential', 'restricted']);
    assert.ok(!JSON.stringify(alternatives).includes('"schema_ref"'), 'schema_ref is not an authored input field');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const program of parameterPrograms(registry)) {
      const object = program.properties.inputs.additionalProperties.oneOf.find(s => s.properties?.carrier);
      delete object.properties.schema_ref;
      for (const rule of object.allOf ?? []) {
        if (rule.then?.not?.anyOf) {
          rule.then.not.anyOf = rule.then.not.anyOf.filter(s => !s.required?.includes('schema_ref'));
        }
      }
    }
    checkLocalInputSchemas(registry);
    for (const [name, body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name] = machineCid(body);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkLocalInputSchemas(registry);
  console.log('Embedded local input schemas exclude legacy schema_ref.');
}
