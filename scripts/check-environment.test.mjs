import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {canonicalText,verifyIdentity} from './check-canonical-json.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const contract=read('spec/contracts/actql-check-environment.json');
const corpus=read('portability/corpus/check-environment.json');
test('source data policy body is closed and retains unknown classification',()=>{
  assert.deepEqual(contract.contract_bodies.data_policy,{
    type:'object',additionalProperties:false,
    required:['version','source_ref','classification'],
    properties:{
      version:{const:'actql-source-data-policy/0.1'},
      source_ref:{type:'string',minLength:1},
      classification:{enum:['public','internal','confidential','restricted','unknown']},
    },
  });
});
// Only the explicit envelope schema subset; component admission is separate.
function shape(value){
  const s=contract.schema;
  if(value===null||typeof value!=='object'||Array.isArray(value))return false;
  if(s.required.some(k=>!Object.hasOwn(value,k)))return false;
  for(const [k,v] of Object.entries(value)){
    if(!Object.hasOwn(s.properties,k))return false;
    const p=s.properties[k];
    if(p.const!==undefined&&v!==p.const)return false;
    if(p.type==='object'&&(!v||typeof v!=='object'||Array.isArray(v)))return false;
    if(p.type==='array'&&(!Array.isArray(v)||v.some(e=>!e||typeof e!=='object'||Array.isArray(e))))return false;
    if(p.type==='string'&&(typeof v!=='string'||!new RegExp(p.pattern,'u').test(v)))return false;
  }
  return true;
}
test('closed envelope shape requires all sections without validating their contents',()=>{
  for(const c of corpus.cases){
    const wire=JSON.parse(c.expected_wire);
    assert.ok(shape(wire));
    for(const key of Object.keys(wire)){
      const copy=structuredClone(wire); delete copy[key]; assert.equal(shape(copy),false,key);
    }
    assert.equal(shape({...wire,check_environment_cid:wire.evidence_bundle_cid}),false);
    assert.equal(shape({...wire,schema_snapshots:null}),false);
    assert.equal(shape({...wire,connector_catalogs:[null]}),false);
  }
});
test('only the root identity member is excluded from the preimage',()=>{
  for(const c of corpus.cases){
    const {evidence_bundle_cid,...preimage}=JSON.parse(c.expected_wire);
    verifyIdentity(preimage,evidence_bundle_cid,c.expected_preimage);
    assert.throws(()=>verifyIdentity({...preimage,version:'wrong'},evidence_bundle_cid));
    assert.throws(()=>verifyIdentity(JSON.parse(c.expected_wire),evidence_bundle_cid));
  }
  const c=corpus.cases.find(c=>c.id==='nested-identity-data');
  const {evidence_bundle_cid,...preimage}=JSON.parse(c.expected_wire);
  delete preimage.host_policy_profile.extension.evidence_bundle_cid;
  assert.notEqual(canonicalText(preimage),c.expected_preimage);
  assert.throws(()=>verifyIdentity(preimage,evidence_bundle_cid));
});
