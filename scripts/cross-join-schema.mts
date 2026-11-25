import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms, type ProgramRegistry} from './parameter-schema.mjs';
import {positive,fieldPattern} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

type CrossJoinProgram = {properties: {steps: {items: {properties: {
  cross_join: ReturnType<typeof crossJoinSchema>;
}}}}};

export function crossJoinSchema() {
  return {type:'object',additionalProperties:false,required:['with'],properties:{
    with:{type:'string',minLength:1},right_rows:{const:'one'},max_output_rows:positive,
    select:{type:'object',minProperties:1,propertyNames:{pattern:fieldPattern},additionalProperties:{type:'string',pattern:'^(left|right)\\.[\\s\\S]+$'}},
  }};
}
export function checkCrossJoinSchemas(registry: ProgramRegistry<CrossJoinProgram>) {
  for(const p of parameterPrograms(registry)) assert.deepEqual(p.properties.steps.items.properties.cross_join,crossJoinSchema());
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry: ProgramRegistry<CrossJoinProgram> = JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(registry)) p.properties.steps.items.properties.cross_join=crossJoinSchema();
    for(const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkCrossJoinSchemas(registry);
  console.log('Cross join schemas and artifact pins verified.');
}
