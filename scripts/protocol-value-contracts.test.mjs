import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {valueBodyContract,generateValueKinds,commandInputPresenceBody,commandInputPresenceSchemas,textEnumerationBody} from './protocol-value-contracts.mjs';
const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
test('all eight legacy value roles use the checked grammar, never the carrier grammar',()=>{
  const body=valueBodyContract(protocol);
  assert.deepEqual(body.kinds,['request_schema','command_input','command_output','idempotency_key','checkpoint',
    'lookup_request_key','lookup_batch_request','lookup_response_key']);
  assert.equal(body.schema.pointer,'/schemas/canonical_value_contract');
  assert.ok(!body.kinds.includes('carrier_schema'));
  assert.equal((generateValueKinds(protocol).match(/"/g)??[]).length,18);
  assert.ok(generateValueKinds(protocol).includes(JSON.stringify(body.schema.cid)));
});
test('added, missing and repeated envelope kinds cannot bypass grammar routing',()=>{
  for(const mutate of [xs=>xs.push('new_role'),xs=>xs.pop(),xs=>xs.push(xs[0])]){
    const changed=structuredClone(protocol);mutate(changed.schemas.contract_envelope.properties.kind.enum);
    assert.throws(()=>valueBodyContract(changed));
  }
});
test('Command presence has one closed domain-specific record and unchanged child grammar',()=>{
  const presence=commandInputPresenceBody(protocol);
  const schema=presence.schema;
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(schema.required,['additional_properties','fields','required_fields']);
  assert.deepEqual(Object.keys(schema.properties),schema.required);
  assert.deepEqual(schema.properties.additional_properties,{const:false});
  assert.deepEqual(schema.properties.fields.additionalProperties,{$ref:'#/$defs/value_contract'});
  assert.deepEqual(schema.$defs,protocol.schemas.canonical_value_contract.$defs);
  assert.equal(schema.properties.required_fields.uniqueItems,true);
  assert.equal(schema.properties.required_fields.minItems,undefined,'empty required subset remains legal');
  assert.match(presence.correspondence,/same_original_command_catalog_environment/);
  assert.match(presence.required_fields,/preserve_exact_array_order/);
  assert.deepEqual(valueBodyContract(protocol).command_input_presence,presence);
  commandInputPresenceSchemas(protocol);
  for(const mutate of [p=>delete p.schemas.command_contract.properties.input_contract.properties.required_fields,
    p=>p.schemas.connector_catalog.$defs.command_contract.properties.input_contract.properties.required_fields={type:'array'}]){
    const drift=structuredClone(protocol);mutate(drift);assert.throws(()=>commandInputPresenceSchemas(drift));
  }
  assert.equal(protocol.schemas.canonical_value_contract.$defs.value_contract.oneOf.find(value=>value.properties?.type?.const==='object').properties.required_fields,undefined);
});

test('Text enum retains empty and repeated vectors in every current registered type entrance',()=>{
  const body=textEnumerationBody(protocol);
  assert.deepEqual(body.grammar,{type:'array',items:{type:'string'}});
  assert.match(body.join_qualification,/conservative_common_supertype/);
  let count=0;
  const visit=value=>{
    if(!value||typeof value!=='object')return;
    const kind=value.properties?.type;
    if(value.type==='object'&&value.properties?.nullable&&
      (kind?.const==='string'||kind?.enum?.includes('string'))){
      assert.deepEqual(value.properties.enum,body.grammar,'current Text entrance must retain constraint grammar');
      assert.equal(value.required.includes('enum'),false);
      count++;
    }
    for(const child of Object.values(value))visit(child);
  };
  visit(protocol.schemas);visit(protocol.artifact_schemas);
  assert.ok(count>0,'actual registered entrances inspected');
  for(const name of ['author_value_contract','canonical_value_contract']){
    for(const change of [branch=>delete branch.properties.enum,
      branch=>branch.properties.enum.uniqueItems=true,
      branch=>branch.properties.enum.minItems=1,
      branch=>branch.required.push('enum')]){
      const changed=structuredClone(protocol);
      change(changed.schemas[name].$defs.value_contract.oneOf.find(branch=>branch.properties?.type?.const==='string'));
      assert.throws(()=>textEnumerationBody(changed));
    }
  }
});

test('actual generated structural type validator keeps enum shape without claiming value membership',async()=>{
  const {project,structuralValidatorSource}=await import('./generate-client-publication-wire.mjs');
  const schema=project(protocol.schemas.canonical_value_contract.$defs.value_contract);
  const source='const schemas={value_contract:'+JSON.stringify(schema)+'};\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.value_contract);';
  const generated=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const enumeration of [[],['low','medium','high'],['high','low','high']]){
    const original={type:'string',nullable:false,enum:enumeration};
    assert.equal(generated.check(original),true);
    assert.deepEqual(original.enum,enumeration,'no source normalization');
  }
  assert.equal(generated.check({type:'string',nullable:false}),true,'old absence');
  for(const original of [
    {type:'string',nullable:false,enum:null},
    {type:'string',nullable:false,enum:['low',null]},
    {type:'string',nullable:false,enum:[1]},
    {type:'string',nullable:false,enum:['low'],default:'low'},
    {type:'number',nullable:false,enum:['1']},
  ])assert.equal(generated.check(original),false);
  // This checks the shipped structural declaration route only. Common must
  // still check Unicode, actual membership, extents and original value custody.
});
