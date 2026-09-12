import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {pushdownBodyContract, pushdownOperations} from './pushdown-contract.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
const read = path => JSON.parse(readFileSync(path,'utf8'));
const contract = pushdownBodyContract();
const corpus = read('portability/corpus/pushdown-contract.json');

// Independent fixed-rule oracle, not the product checker or a generic schema validator.
function accepts(body, carrier, operations) {
  if (!['relation','graph','events','vectors'].includes(carrier)
    || !Array.isArray(operations) || new Set(operations).size !== operations.length
    || operations.some(x => !pushdownOperations.includes(x))) return false;
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false;
  if (Object.keys(body).length === 0) return operations.length === 0;
  return Object.keys(body).sort().join(',') === 'carrier,operations,version'
    && body.version === 'actql-source-view-pushdown/0.1' && body.carrier === carrier
    && Array.isArray(body.operations) && new Set(body.operations).size === body.operations.length
    && body.operations.every(x=>pushdownOperations.includes(x))
    && (carrier === 'relation' || body.operations.length === 0)
    && operations.length === body.operations.length
    && operations.every(x=>body.operations.includes(x));
}
test('pushdown body grammar and semantic dependency pins are registered',()=>{
  assert.deepEqual(pushdownOperations,['projection','filter','order_by','limit','assert_unique_by']);
  assert.deepEqual(read('spec/contracts/actql-check-environment.json').pushdown_contract_bodies, contract);
  assert.deepEqual(contract.schema.oneOf[0], {type:'object',maxProperties:0});
  const structured = contract.schema.oneOf[1];
  assert.equal(structured.additionalProperties,false);
  assert.deepEqual(structured.required,['version','carrier','operations']);
  assert.deepEqual(structured.properties.operations.items.enum, pushdownOperations);
  assert.equal(structured.properties.operations.uniqueItems,true);
  for (const pin of Object.values(contract.semantic_dependencies)) verifyIdentity(read(pin.path), pin.cid);
});
test('fixed pushdown vectors separate operation sets from identity array order',()=>{
  assert.equal(corpus.version,'actql-pushdown-contract-vectors/0.1');
  assert.equal(new Set(corpus.cases.map(x=>x.id)).size,corpus.cases.length);
  for (const c of corpus.cases) {
    assert.equal(accepts(c.body,c.carrier,c.operations),c.accepted,c.id);
    if (c.accepted) verifyIdentity(c.body,c.expected_body_cid);
  }
  assert.notEqual(corpus.cases[1].expected_body_cid,corpus.cases[2].expected_body_cid);
  assert.match(contract.semantics.interpretation,/not_equivalence_proof/);
  assert.match(contract.semantics.preservation,/eager_failure/);
});
