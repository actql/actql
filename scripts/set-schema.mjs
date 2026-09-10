import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function setSchema() {
  return {type:'object',additionalProperties:false,required:['with','duplicates'],properties:{
    with:{type:'string',minLength:1}, duplicates:{enum:['distinct','all']},
  }};
}
export function checkSetSchemas(registry) {
  for (const p of parameterPrograms(registry)) for (const op of ['except','intersect']) {
    assert.deepEqual(p.properties.steps.items.properties[op],setSchema());
  }
  for (const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if (process.argv.includes('--write')) {
    for (const p of parameterPrograms(registry)) for (const op of ['except','intersect']) p.properties.steps.items.properties[op]=setSchema();
    for (const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkSetSchemas(registry);
  console.log('Row-set operation schemas and artifact pins verified.');
}
