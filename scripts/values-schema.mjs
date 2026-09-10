import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {fieldPattern} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

const singleton = name => ({type:'object',required:[name],maxProperties:1});
export function cellSchema() {
  return {oneOf:[
    {...singleton('$param'),properties:{$param:{type:'string',pattern:'^[A-Za-z_][A-Za-z0-9_]*$'}}},
    {...singleton('literal'),properties:{literal:{}}},
    {not:{anyOf:[singleton('$param'),singleton('literal')]}},
  ]};
}
export function valuesContract(base) {
  const c=JSON.parse(JSON.stringify(base).replaceAll('#/$defs/value_contract','#/$defs/values_contract'));
  c.oneOf=c.oneOf.filter(s=>!['resource_ref','artifact_ref'].includes(s.properties.type.const));
  for(const s of c.oneOf) {
    if(s.properties.type.enum) s.properties.type.enum=s.properties.type.enum.filter(t=>t!=='json');
    if(s.properties.max_items) s.properties.max_items.maximum=9007199254740991;
  }
  return c;
}
export function valuesSchema() {
  return {type:'object',additionalProperties:false,required:['schema','rows'],properties:{
    schema:{type:'object',minProperties:1,propertyNames:{pattern:fieldPattern},additionalProperties:{$ref:'#/$defs/values_contract'}},
    rows:{type:'array',items:{type:'object',additionalProperties:cellSchema()}},
  }};
}
export const generatorRule={if:{required:['values']},then:{required:['as'],properties:{as:{type:'string',minLength:1}},not:{required:['from']}}};
export function checkValuesSchemas(registry) {
  for(const p of parameterPrograms(registry)) {
    assert.deepEqual(p.$defs.values_contract,valuesContract(p.$defs.value_contract));
    assert.deepEqual(p.properties.steps.items.properties.values,valuesSchema());
    const rules=p.properties.steps.items.allOf.filter(r=>r.if?.required?.includes('values'));
    assert.deepEqual(rules,[generatorRule]);
  }
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const r=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(r)) {
      p.$defs.values_contract=valuesContract(p.$defs.value_contract);
      const step=p.properties.steps.items;
      step.properties.values=valuesSchema();
      step.allOf=[...(step.allOf??[]).filter(r=>!r.if?.required?.includes('values')),generatorRule];
    }
    for(const [name,body] of Object.entries(r.artifact_schemas)) r.artifact_schema_cids[name]=machineCid(body);
    r.artifact_registry_cid=machineCid(r.artifact_schemas);
    writeFileSync(path,JSON.stringify(r,null,2)+'\n');
  }
  checkValuesSchemas(r);
  console.log('Values schemas, generator envelopes, and artifact pins verified.');
}
