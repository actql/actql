import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {positive,orderKeys} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function topKSchema(partitioned=false) {
  return {type:'object',additionalProperties:false,required:[...(partitioned?['partition_by']:[]),'k','by'],properties:{
    ...(partitioned?{partition_by:{type:'array',items:{type:'string',minLength:1}}}:{}), k:positive,by:orderKeys,
  }};
}
export function checkTopKSchemas(registry) {
  for(const p of parameterPrograms(registry)) {
    assert.deepEqual(p.properties.steps.items.properties.top_k,topKSchema());
    assert.deepEqual(p.properties.steps.items.properties.top_k_by,topKSchema(true));
  }
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(registry)) {
      p.properties.steps.items.properties.top_k=topKSchema();
      p.properties.steps.items.properties.top_k_by=topKSchema(true);
    }
    for(const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkTopKSchemas(registry);
  console.log('Top-k schemas and artifact pins verified.');
}
