import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync}from'node:fs';
import{selectInstalledLocalMaterializationEnvironment,selectInstalledHostEnvironment}from'./installed-host-policy.mjs';
import{contentCid}from'./local-account-config.mjs';
const baseWire=readFileSync(new URL('../../packages/local-node/spec/local-check-environment.json',import.meta.url),'utf8').trimEnd();
const old=JSON.parse(baseWire),original=Object.freeze({});
const moon={clientLocalResourcePolicyOriginal:()=>original,clientLocalResourcePolicyRowCeiling:p=>p===original?2097152:-1,clientLocalResourcePolicyModelRequestByteCeiling:p=>p===original?65536n:-1n,clientProgramCheckEnvironment:()=>({})};
test('Local defaults select actual row and Model request windows; generic saved environment stays unchanged',()=>{
 const wire=selectInstalledLocalMaterializationEnvironment(moon,baseWire);
 const value=JSON.parse(wire),{evidence_bundle_cid:cid,...body}=value;
 assert.equal(value.host_policy_profile.capacity.max_relation_output_rows,2097152);
 assert.equal(value.host_policy_profile.capacity.max_artifact_rows,2097152);
 assert.equal(value.host_policy_profile.capacity.max_file_listing_items,2097152);
 assert.equal(value.host_policy_profile.capacity.max_model_request_bytes_per_item,65536);
 assert.equal(old.host_policy_profile.capacity.max_model_request_bytes_per_item,1000);
 assert.equal(value.host_policy_profile.capacity.max_effect_items,old.host_policy_profile.capacity.max_effect_items);
 assert.equal(cid,contentCid(body));assert.notEqual(cid,old.evidence_bundle_cid);
 assert.equal(selectInstalledHostEnvironment(moon,baseWire),baseWire);
 assert.equal(JSON.parse(baseWire).evidence_bundle_cid,old.evidence_bundle_cid);
});
test('explicit lower policy remains lower; higher explicit policy cannot exceed same installed resource bound',()=>{
 const selected={...old.host_policy_profile.capacity,max_relation_output_rows:10,max_artifact_rows:20};
 const value=JSON.parse(selectInstalledLocalMaterializationEnvironment(moon,baseWire,selected));
 assert.equal(value.host_policy_profile.capacity.max_model_request_bytes_per_item,1000);
 assert.equal(value.host_policy_profile.capacity.max_relation_output_rows,10);assert.equal(value.host_policy_profile.capacity.max_artifact_rows,20);
 assert.equal(Object.hasOwn(value.host_policy_profile.capacity,'max_file_listing_items'),false);
 const listing={...selected,max_file_listing_items:5};
 assert.equal(JSON.parse(selectInstalledLocalMaterializationEnvironment(moon,baseWire,listing)).host_policy_profile.capacity.max_file_listing_items,5);
 listing.max_file_listing_items=3000000;
 assert.equal(JSON.parse(selectInstalledLocalMaterializationEnvironment(moon,baseWire,listing)).host_policy_profile.capacity.max_file_listing_items,2097152);
 selected.max_relation_output_rows=3000000;
 assert.equal(JSON.parse(selectInstalledLocalMaterializationEnvironment(moon,baseWire,selected)).host_policy_profile.capacity.max_relation_output_rows,2097152);
});
test('invalid resource projection fails closed without replacing persisted evidence',()=>{
 assert.throws(()=>selectInstalledLocalMaterializationEnvironment({...moon,clientLocalResourcePolicyRowCeiling:()=>-1},baseWire),{code:'InvalidInstalledHostCapacityPolicy'});
 for(const invalid of [-1n,0n,9007199254740992n,65536,undefined]) {
  const selected={...moon,clientLocalResourcePolicyModelRequestByteCeiling:()=>invalid};
  assert.throws(()=>selectInstalledLocalMaterializationEnvironment(selected,baseWire),{code:'InvalidInstalledHostCapacityPolicy'});
  // An explicit current Host policy has no dependency on the default projection.
  const explicit=JSON.parse(selectInstalledLocalMaterializationEnvironment(selected,baseWire,old.host_policy_profile.capacity));
  assert.equal(explicit.host_policy_profile.capacity.max_model_request_bytes_per_item,1000);
 }
});
