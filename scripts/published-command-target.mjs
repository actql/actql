// Canonical selection data only; original Command and installed authority stay
// with the existing Common/Effect owners.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function publishedCommandTargetSchema() {
  return {type:'object',additionalProperties:false,required:['published_command'],
    properties:{published_command:{type:'object',additionalProperties:false,
      required:['target_ref'],properties:{
        target_ref:{type:'string',pattern:'^connector://'},
        identifier_field:{type:'string',minLength:1},
      }}}};
}

export function publishedCommandTargetSchemas(protocol, write=false) {
  const prior=JSON.parse(readFileSync(new URL('../portability/fixtures/program-grammar-before-published-command.json',import.meta.url),'utf8'));
  const before=prior.properties.effects.additionalProperties.oneOf
    .find(member=>member.properties?.command).properties.command;
  for(const program of parameterPrograms(protocol)) {
    const command=program.properties.effects.additionalProperties.oneOf
      .find(member=>member.properties?.command).properties.command;
    assert.deepEqual(command.required,before.required,'Original Command required fields');
    const target=command.properties.target;
    assert.ok(target.oneOf?.length===2 || target.oneOf?.length===3,'Unreviewed Command target alternatives');
    assert.deepEqual(target.oneOf.slice(0,2),before.properties.target.oneOf,'Original field and STORE alternatives');
    if(write) {
      if(target.oneOf.length===3)assert.deepEqual(target.oneOf[2],publishedCommandTargetSchema());
      target.oneOf=[...target.oneOf.slice(0,2),publishedCommandTargetSchema()];
    }
    assert.deepEqual(target.oneOf,[...before.properties.target.oneOf,publishedCommandTargetSchema()]);
  }
  if(write) {
    for(const [name,body] of Object.entries(protocol.artifact_schemas))protocol.artifact_schema_cids[name]=machineCid(body);
    protocol.artifact_registry_cid=machineCid(protocol.artifact_schemas);
  }
  for(const [name,body] of Object.entries(protocol.artifact_schemas))assert.equal(protocol.artifact_schema_cids[name],machineCid(body));
  assert.equal(protocol.artifact_registry_cid,machineCid(protocol.artifact_schemas));
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const protocol=JSON.parse(readFileSync(path,'utf8'));
  publishedCommandTargetSchemas(protocol,process.argv.includes('--write'));
  if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(protocol,null,2)+'\n');
  console.log('Canonical published Command selectors retain both original target alternatives.');
}
