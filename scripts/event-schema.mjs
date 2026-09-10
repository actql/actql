import assert from 'node:assert/strict';
import {orderKeys} from './aggregate-schema.mjs';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function eventSchemas() {
  return {
    dedupe_events: {type:'object',additionalProperties:false,required:['by','order_by'],properties:{
      by:{type:'array',items:{type:'string',minLength:1}},order_by:orderKeys,
    }},
    to_events: {type:'object',additionalProperties:false,required:['id','time'],properties:{
      id:{type:'string',minLength:1},time:{type:'string',minLength:1},
    }},
    watermark_events: {type:'object',additionalProperties:false,required:['watermark_ms','policy'],properties:{
      watermark_ms:{type:'number'},policy:{enum:['drop','mark']},
    }},
  };
}

export function checkEventSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    const properties = program.properties.steps.items.properties;
    for (const operation of Object.keys(eventSchemas())) {
      assert.deepEqual(properties[operation], eventSchemas()[operation]);
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
      for (const operation of Object.keys(eventSchemas())) {
        program.properties.steps.items.properties[operation] = eventSchemas()[operation];
      }
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkEventSchemas(registry);
  console.log('Event operation schemas and artifact pins verified.');
}
