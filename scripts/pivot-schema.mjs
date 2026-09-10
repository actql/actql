import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {fieldPattern} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export const cellValue = {oneOf:[
  {type:'object',additionalProperties:false,required:['$param'],properties:{$param:{type:'string',pattern:'^[A-Za-z_][A-Za-z0-9_]*$'}}},
  {type:'object',additionalProperties:false,required:['literal'],properties:{literal:{}}},
  {not:{type:'object',minProperties:1,maxProperties:1,anyOf:[{required:['$param']},{required:['literal']}]}}
]};
export const pivotSchema = {type:'object',additionalProperties:false,required:['index','column','values','value','aggregate'],properties:{
  index:{type:'array',items:{type:'string',minLength:1}},
  column:{type:'string',minLength:1},
  values:{type:'array',uniqueItems:true,items:{type:'string',pattern:fieldPattern}},
  value:{type:'string',minLength:1},
  aggregate:{enum:['sum','avg','count','min','max','first']},
  fill:cellValue,
}};

export function checkPivotSchemas(registry) {
  for(const p of parameterPrograms(registry)) assert.deepEqual(p.properties.steps.items.properties.pivot,pivotSchema);
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}

if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(registry)) p.properties.steps.items.properties.pivot=structuredClone(pivotSchema);
    for(const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkPivotSchemas(registry);
  console.log('Pivot schemas and artifact pins verified.');
}
