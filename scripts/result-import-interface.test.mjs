import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {schema,checkResultImportInterface} from './result-import-interface.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const corpus=read('portability/corpus/result-import-interface.json');
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const keys=(v,expected)=>object(v)&&Object.keys(v).sort().join(',')===[...expected].sort().join(',');
const name=v=>typeof v==='string'&&v.length>0;
const cid=v=>typeof v==='string'&&/^sha256:[0-9a-f]{64}$/.test(v);
// Closed wire-shape oracle only. Producer/type ownership needs compiler checks;
// the a/b/c/d pins in these encoding vectors are symbolic dependency handles.
function accepts(v) {
  return keys(v,schema.required)&&v.version==='actql-result-import-interface/0.1'
    &&name(v.input_name)&&name(v.producer_result)
    &&keys(v.producer_namespace,['program_id','node_id'])
    &&name(v.producer_namespace.program_id)&&name(v.producer_namespace.node_id)
    &&cid(v.producer_unit_definition_cid)&&cid(v.value_contract_cid)&&cid(v.self_cid)
    &&v.availability==='stage_success';
}
test('Result interface schema binds semantic dependencies without replacing receipt roles',()=>{
  checkResultImportInterface(read('spec/contracts/actql-stage-contracts.json'));
  const family=read('spec/spec-family.json');
  assert.ok(family.documents.find(d=>d.spec_id==='actql.language').machine_contracts.some(
    r=>r.path==='spec/contracts/actql-stage-contracts.json'
      &&r.pointer==='/schemas/result_import_interface'&&r.cid===machineCid(schema)));
});
test('fixed interface preimages distinguish aliases, namespaces, producer definitions and types',()=>{
  assert.equal(corpus.version,'actql-result-import-interface-vectors/0.1');
  const identities=new Set();
  for(const c of corpus.cases) {
    const preimage={...corpus.base,...c.changes};
    assert.ok(accepts({...preimage,self_cid:c.expected_cid}),c.id);
    verifyIdentity(preimage,c.expected_cid);
    verifyIdentity(Object.fromEntries(Object.entries(preimage).reverse()),c.expected_cid);
    assert.notEqual(machineCid({...preimage,self_cid:c.expected_cid}),c.expected_cid);
    identities.add(c.expected_cid);
  }
  assert.equal(identities.size,corpus.cases.length);
  for(const c of corpus.rejections) {
    const v={...corpus.base,self_cid:corpus.cases[0].expected_cid,...c.changes};
    if(c.remove)delete v[c.remove];
    assert.equal(accepts(v),false,c.id);
  }
});
