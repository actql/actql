import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {generateRoutes} from './catalog-reference-roles.mjs';
const load=()=>JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8')).schemas;

test('all current reference paths produce the committed table',()=>{
  const generated=generateRoutes(load());
  assert.equal(generated.count,19);
  assert.equal(generated.output,readFileSync('src/check_environment/catalog_roles.generated.mbt','utf8'));
});
test('added removed or conditional references fail instead of silently losing coverage',()=>{
  let schemas=load();
  schemas.source_view.properties.new_reference=structuredClone(schemas.source_view.properties.output.properties.schema);
  assert.throws(()=>generateRoutes(schemas),/reference role coverage/);
  schemas=load();
  delete schemas.command_contract.properties.poll;
  assert.throws(()=>generateRoutes(schemas),/reference role coverage/);
  schemas=load();
  schemas.command_contract.properties.poll={anyOf:[schemas.command_contract.properties.poll,{type:'null'}]};
  assert.throws(()=>generateRoutes(schemas),/conditional ContractRef/);
});
test('local reference schemas are resolved and newly referenced slots remain covered',()=>{
  const schemas=load();
  schemas.command_contract.$defs.reference=schemas.command_contract.properties.poll;
  schemas.command_contract.properties.poll={$ref:'#/$defs/reference'};
  assert.equal(generateRoutes(schemas).output,generateRoutes(load()).output);
  schemas.command_contract.properties.new_reference={$ref:'#/$defs/reference'};
  assert.throws(()=>generateRoutes(schemas),/reference role coverage/);
});
test('schema optionality changes generated hops and invalid kinds fail',()=>{
  const schemas=load();
  schemas.command_contract.required.push('poll');
  assert.match(generateRoutes(schemas).output,/RefField\("poll", true\)/);
  schemas.contract_envelope.properties.kind.enum=schemas.contract_envelope.properties.kind.enum.filter(k=>k!=='poll');
  assert.throws(()=>generateRoutes(schemas));
});
