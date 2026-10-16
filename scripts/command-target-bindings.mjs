import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

// The original Command declaration owns the mode. This grammar does not
// publish an installation, resolve an identifier, issue a Ref or grant access.
export function commandTargetBindingSchema() {
  return {oneOf:[
    {type:'object',additionalProperties:false,required:['kind'],
      properties:{kind:{const:'installation'}}},
    {type:'object',additionalProperties:false,required:['kind','identity_contract'],
      properties:{kind:{const:'identifier'},identity_contract:{allOf:[
        {$ref:'#/$defs/value_contract'},
        {properties:{nullable:{const:false}}},
      ]}}},
  ]};
}

export function commandTargetBindingSchemas(protocol, write=false) {
  const commands=[protocol.schemas.command_contract,
    protocol.schemas.connector_catalog.$defs.command_contract];
  for(const command of commands){
    assert.equal(command.properties.schema.const,'actql.command_contract/0.1');
    const target=command.properties.target;
    assert.equal(target.additionalProperties,false);
    assert.deepEqual(target.required,['resource_kind','cardinality']);
    if(write)target.properties.binding=commandTargetBindingSchema();
    assert.deepEqual(target.properties.binding,commandTargetBindingSchema());
    assert.deepEqual(Object.keys(target.properties).sort(),['binding','cardinality','max_items','resource_kind']);
  }
  assert.deepEqual(commands[0],commands[1]);
  if(write){
    for(const name of ['command_contract','connector_catalog'])protocol.schema_cids[name]=machineCid(protocol.schemas[name]);
    protocol.registry_cid=machineCid(protocol.schemas);
  }
  for(const name of ['command_contract','connector_catalog'])assert.equal(protocol.schema_cids[name],machineCid(protocol.schemas[name]));
  assert.equal(protocol.registry_cid,machineCid(protocol.schemas));
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const path='spec/contracts/actql-protocol-schemas.json';
  const protocol=JSON.parse(readFileSync(path,'utf8'));
  commandTargetBindingSchemas(protocol,process.argv.includes('--write'));
  if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(protocol,null,2)+'\n');
  console.log('Original Command target modes and Catalog structural copy agree.');
}
