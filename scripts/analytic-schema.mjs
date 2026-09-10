import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {aggregateSchema,fieldPattern,orderKeys,parameter,positive} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

const call = (names, properties = {}, required = []) => ({type:'object',additionalProperties:false,required:['fn',...required],properties:{fn:{enum:names},...properties}});
const rankings = call(['row_number','rank','dense_rank']);
const navigation = call(['lag','lead'],{expr:{$ref:'#/$defs/value_expression'},offset:{oneOf:[{type:'integer',minimum:0,maximum:9007199254740991},parameter]}},['expr']);
const values = call(['first_value','last_value'],{expr:{$ref:'#/$defs/value_expression'}},['expr']);
const boundary = {oneOf:[{enum:['unbounded_preceding','current_row','unbounded_following']},...['preceding','following'].map(k=>({type:'object',additionalProperties:false,required:[k],properties:{[k]:positive}}))]};
export const analyticSchema = {type:'object',additionalProperties:false,required:['partition_by','order_by','functions'],properties:{
  partition_by:{type:'array',items:{type:'string',minLength:1}},
  order_by:orderKeys,
  functions:{type:'object',minProperties:1,propertyNames:{pattern:fieldPattern},additionalProperties:{oneOf:[rankings,navigation,values,...aggregateSchema(true).oneOf]}},
  frame:{type:'object',additionalProperties:false,required:['start','end'],properties:{start:{allOf:[boundary,{not:{const:'unbounded_following'}}]},end:{allOf:[boundary,{not:{const:'unbounded_preceding'}}]}}},
},allOf:[{if:{properties:{functions:{additionalProperties:{oneOf:[rankings,navigation]}}}},then:{not:{required:['frame']}},else:{required:['frame']}}]};

export function checkAnalyticSchemas(registry) {
  for(const p of parameterPrograms(registry)) assert.deepEqual(p.properties.steps.items.properties.analytic,analyticSchema);
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(registry)) p.properties.steps.items.properties.analytic=structuredClone(analyticSchema);
    for(const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkAnalyticSchemas(registry);
  console.log('Analytic call and frame schemas and artifact pins verified.');
}
