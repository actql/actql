import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {commandTargetBindingSchemas,commandTargetBindingSchema} from './command-target-bindings.mjs';
import {commandTargetBindingVectors} from './command-target-binding-vectors.mjs';
import {machineCid} from './actql-spec-family.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const protocol=read('spec/contracts/actql-protocol-schemas.json');
const previous=read('portability/fixtures/command-target-bindings/previous-command-schema.json');
const corpus=read('portability/corpus/command-target-bindings.json');

test('Command mode is the sole initial-0.1 target schema extension, with legacy declaration retained',()=>{
  const original=JSON.parse(execFileSync('git',['show',`${previous.source_revision}:spec/contracts/actql-protocol-schemas.json`],{encoding:'utf8',maxBuffer:8*1024*1024}));
  assert.deepEqual(previous.schema,original.schemas.command_contract);
  assert.equal(machineCid(previous.schema),previous.schema_cid);
  assert.equal(previous.schema_cid,'sha256:089b4bb20d9b047805d2176852265c3a4f4fd3822eaab80359b9e1bac8ca9a1b');
  const current=structuredClone(protocol.schemas.command_contract);
  assert.deepEqual(current.properties.target.properties.binding,commandTargetBindingSchema());
  delete current.properties.target.properties.binding;
  assert.deepEqual(current,previous.schema);
  assert.deepEqual(protocol.schemas.command_contract,protocol.schemas.connector_catalog.$defs.command_contract);
  commandTargetBindingSchemas(protocol);
});

test('closed installation and identifier declarations cannot drift between original Command and Catalog',()=>{
  const schema=commandTargetBindingSchema();
  assert.equal(schema.oneOf.length,2);
  assert.deepEqual(schema.oneOf.map(v=>[v.additionalProperties,v.required]),[
    [false,['kind']],[false,['kind','identity_contract']],
  ]);
  assert.deepEqual(schema.oneOf.map(v=>v.properties.kind.const),['installation','identifier']);
  assert.deepEqual(schema.oneOf[1].properties.identity_contract,{allOf:[{$ref:'#/$defs/value_contract'},{properties:{nullable:{const:false}}}]});
  for(const mutate of [
    p=>delete p.schemas.command_contract.properties.target.properties.binding,
    p=>p.schemas.command_contract.properties.target.properties.binding.oneOf[0].additionalProperties=true,
    p=>p.schemas.connector_catalog.$defs.command_contract.properties.target.properties.binding.oneOf[1].properties.identity_contract={},
  ]){
    const changed=structuredClone(protocol);mutate(changed);
    assert.throws(()=>commandTargetBindingSchemas(changed));
  }
  assert.equal(protocol.schemas.command_contract.properties.target.required.includes('binding'),false);
});

test('independent complete Command originals preserve absent bytes and reject changed target or Catalog history',()=>{
  const generated=commandTargetBindingVectors(corpus);
  assert.equal(readFileSync('src/check_environment/command_target_bindings.generated_test.mbt','utf8'),generated);
  assert.equal(corpus.cases.length,3);
  assert.equal(corpus.cases[0].environment.command_contracts[0].target.binding,undefined);
  for(const mutate of [
    c=>c.cases[1].environment.connector_catalogs[0].commands[0].target.resource_kind='other',
    c=>c.cases[2].environment.command_contracts[0].target.binding.identity_contract.nullable=true,
    c=>c.cases[1].environment.connector_catalogs[0].catalog_cid=c.cases[0].catalog_cid,
    c=>c.cases[2].command_cid=c.cases[0].command_cid,
    c=>c.cases[2].environment.contract_registry=[],
  ]){
    const changed=structuredClone(corpus);mutate(changed);
    assert.throws(()=>commandTargetBindingVectors(changed));
  }
});
