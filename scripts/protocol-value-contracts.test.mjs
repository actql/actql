import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {valueBodyContract,generateValueKinds} from './protocol-value-contracts.mjs';
const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
test('all eight value roles use the checked grammar, never the carrier grammar',()=>{
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
