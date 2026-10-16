import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {valueBodyContract,generateValueKinds,commandInputPresenceBody,commandInputPresenceSchemas} from './protocol-value-contracts.mjs';
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
