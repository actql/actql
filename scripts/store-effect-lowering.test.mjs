import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
const full=JSON.parse(readFileSync(new URL('./fixtures/store-effect-lowering/environment.json',import.meta.url),'utf8'));
const original=JSON.parse(readFileSync(new URL('./fixtures/store-source-targets/identities.json',import.meta.url),'utf8')).cases.collection;
const without=(value,key)=>Object.fromEntries(Object.entries(value).filter(([name])=>name!==key));
test('STORE full checker original retains the collection pair and explicit capacity',()=>{
  verifyIdentity(without(full.environment,'evidence_bundle_cid'),full.expected_environment_cid);
  assert.deepEqual(without(without(full.environment,'host_policy_profile'),'evidence_bundle_cid'),without(without(original.environment,'host_policy_profile'),'evidence_bundle_cid'));
  for(const file of ['../src/query_program/store_effect_program_test.mbt','../src/connectors_builtin_node/client_store_source_preparation_wbtest.mbt']) {
    const moon=readFileSync(new URL(file,import.meta.url),'utf8');
    assert.ok(moon.includes(canonicalText(full.environment)),file);
  }
  assert.equal(full.environment.host_policy_profile.capacity.max_effect_items,1000);
  assert.equal(full.environment.host_policy_profile.capacity.max_artifact_rows,1000);
  assert.deepEqual(original.environment.host_policy_profile,{});
});
