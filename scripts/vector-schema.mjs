import {parameter, fieldPattern} from './aggregate-schema.mjs';
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function vectorSchemas() {
  return {
    pool_vectors:{type:'object',additionalProperties:false,required:['by','method'],properties:{
      vector:{type:'string',minLength:1},
      by:{type:'array',minItems:1,uniqueItems:true,items:{type:'string',minLength:1}},
      method:{enum:['mean','sum','max']},
      output_id:{type:'string',pattern:fieldPattern},
    },allOf:[{if:{required:['output_id']},then:{properties:{by:{maxItems:1}}}}]},
    nearest:{type:'object',additionalProperties:false,required:['queries','metric','k'],properties:{
      queries:{type:'string',minLength:1},metric:{enum:['cosine','dot','l2']},
      k:{type:'integer',minimum:1,maximum:9007199254740991},
      ...Object.fromEntries(['candidate_id','candidate_vector','query_id','query_vector'].map(k => [k,{type:'string',minLength:1}])),
    }},
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
