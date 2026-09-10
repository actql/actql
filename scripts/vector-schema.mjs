import {parameter} from './aggregate-schema.mjs';
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function vectorSchemas() {
  return {
    to_vectors: {type:'object',additionalProperties:false,required:['id','vector'],properties:{
      id:{type:'string',minLength:1},vector:{type:'string',minLength:1},
    }},
    normalize_vectors: {const:true},
    score_vectors: {type:'object',additionalProperties:false,required:['query','metric'],properties:{
      query:{oneOf:[{type:'array',minItems:1,items:{type:'number'}},parameter]},
      metric:{enum:['cosine','dot','l2']},
    }},
  };
}

export function checkVectorSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    const properties = program.properties.steps.items.properties;
    for (const operation of Object.keys(vectorSchemas())) {
      assert.deepEqual(properties[operation], vectorSchemas()[operation]);
    }
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
    for (const program of parameterPrograms(registry)) {
      for (const operation of Object.keys(vectorSchemas())) {
        program.properties.steps.items.properties[operation] = vectorSchemas()[operation];
      }
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkVectorSchemas(registry);
  console.log('Vector operation schemas and artifact pins verified.');
}
